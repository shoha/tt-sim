class_name BiomeDesignerCompare
extends RefCounted

## The A/B view of the biome designer (step S9, design doc 4.4): the draft on one side of a
## draggable divider and a reference on the other, drawn by the real renderer from the same
## terrain, seed and camera. Method: ONE proving ground, two biomes painted on it (DesignerSplit:
## the draft in biome slot 1 left of the divider, the reference in slot 2 right of it), so the
## real scatter solver generates both and the real ground draws each biome's own surfaces, accents
## and look; no second map and no second viewport, so the memory cost is one extra biome's plants
## (the same GLBs are shared by AssetStore). The divider is a ground line perpendicular to the
## camera's right vector: the camera is fixed and orthographic, so the line is vertical on the
## screen. Moving it repaints the samples it crossed and regenerates only the 10 m cells it
## crossed (live, so the nearest show first); the ground is retabled for the same cells.
##
## The reference is one of DesignerReference.options: the saved version (compiled under a runtime
## id of its own), another season of the draft (then the edits regenerate it too, and it stays
## live), or another biome of any served library. Stopping paints the whole map with the draft
## again. The session owns one of these and keeps the biome list of the document in step with it
## (ids()).

signal changed

## Seconds between two regenerations while the divider is dragged.
const DRAG_INTERVAL_SEC := 0.12
## The camera's right vector on the ground when there is no camera (the game's fixed view looks
## toward -x -z).
const DEFAULT_RIGHT := Vector2(0.7071, -0.7071)

var session: BiomeDesignerSession = null
var active: bool = false
## The reference's spec (DesignerReference.options' form) with `runtime` filled in.
var reference: Dictionary = {}
## The divider's ground position along `right`, in map metres.
var divider_t: float = 0.0
## The camera's right vector on the ground, in map XZ.
var right: Vector2 = DEFAULT_RIGHT

var _painted_t: float = NAN
var _drag_wait: float = 0.0


func _init(owner_session: BiomeDesignerSession = null) -> void:
	session = owner_session


## The palette biome ids the document paints, draft first.
func ids() -> PackedStringArray:
	var out := PackedStringArray([session.runtime_biome_id()])
	if active:
		out.append(String(reference["runtime"]))
	return out


## The reference's palette biome id, "" when the view is off.
func reference_runtime() -> String:
	return String(reference.get("runtime", "")) if active else ""


## The name of the reference for the screen's label.
func reference_label() -> String:
	return String(reference.get("label", "")) if active else ""


## Whether the reference is another season of the draft (its rules follow the draft's edits).
func follows_draft() -> bool:
	return active and reference.get("kind") == "season"


## Turns the view on against `spec` (DesignerReference.options' entry). Returns {ok, error}.
func start(spec: Dictionary) -> Dictionary:
	var made := session.scatter()
	var doc := _document()
	if made == null or doc == null:
		return _failed("the map is not open yet")
	var runtime := String(spec.get("runtime", ""))
	if spec.get("kind") == "saved":
		var saved := DesignerReference.compile_saved(session.model, _season())
		if not saved["ok"]:
			return _failed("the saved version does not compile")
		var report := LibraryRegistry.serve_draft(saved["compiled"], session.model.context)
		if not report["ok"]:
			return _failed(String(report["error"]))
		runtime = String(saved["runtime"])
	if runtime == "" or PaletteLibrary.biome(runtime).is_empty():
		return _failed("that biome is not served")
	if runtime == session.runtime_biome_id():
		return _failed("that is the biome on the left")
	reference = spec.duplicate(true)
	reference["runtime"] = runtime
	active = true
	right = camera_right()
	var span := DesignerSplit.span(doc, right)
	divider_t = (span.x + span.y) * 0.5
	_painted_t = NAN
	if session.controller.editor != null:
		session.controller.editor.prepare_biome(runtime)
	else:
		made.prepare_biome(runtime)
	doc.biome_ids = ids()
	_paint(true)
	changed.emit()
	return {"ok": true, "error": ""}


## Lays the A/B painting into `doc` (a proving ground just built for the draft's biome): both
## biomes listed, the divider where it stands. The scatter is asked for nothing.
func paint_document(doc: MapDocument) -> void:
	doc.biome_ids = ids()
	DesignerSplit.paint(doc, right, NAN, divider_t)


## Turns the view off: the whole map is the draft again.
func stop() -> void:
	if not active:
		return
	var doc := _document()
	active = false
	var runtime := String(reference.get("runtime", ""))
	reference = {}
	if doc != null:
		doc.biome_ids = ids()
		var rect := DesignerSplit.clear(doc)
		_update_ground(rect)
		var made := session.scatter()
		if made != null:
			var started := Time.get_ticks_usec()
			var regen := made.get_regen()
			if regen != null:
				ScatterRefresh.drop_assets(made, regen.assets_of(runtime))
				regen.forget_biome(runtime)
			var info := ScatterRefresh.biome(made, session.runtime_biome_id(), true)
			session.begin_request(info, started)
	_painted_t = NAN
	changed.emit()


## Moves the divider to ground position `t` (clamped to the map). The repaint and the
## regeneration are throttled while `dragging`; a final move (the button released) applies at once.
func move_divider(t: float, dragging: bool) -> void:
	var doc := _document()
	if not active or doc == null:
		return
	var span := DesignerSplit.span(doc, right)
	divider_t = clampf(t, span.x, span.y)
	if dragging and _drag_wait > 0.0:
		return
	_drag_wait = DRAG_INTERVAL_SEC if dragging else 0.0
	_paint(false)
	changed.emit()


## Called every frame by the session while the view is on.
func tick(delta: float) -> void:
	_drag_wait = maxf(_drag_wait - delta, 0.0)
	if active and not is_equal_approx(_painted_t, divider_t) and _drag_wait <= 0.0:
		_paint(false)


## The share (0..1) of the map the draft covers, for the budget.
func draft_share() -> float:
	var doc := _document()
	if not active or doc == null:
		return 1.0
	return maxf(DesignerSplit.draft_share(doc, right, divider_t), 0.05)


## The divider's x in the world viewport's pixels.
func viewport_x() -> float:
	if session.game_map == null:
		return 0.0
	var camera := session.game_map.camera_node
	var xz := right * divider_t
	return camera.unproject_position(_world_of(xz)).x


## The ground position along `right` under world-viewport pixel column `x`.
func t_at_viewport_x(x: float) -> float:
	var camera := session.game_map.camera_node
	var at := Vector2(x, session.game_map.world_viewport.size.y * 0.5)
	var origin := camera.project_ray_origin(at)
	var direction := camera.project_ray_normal(at)
	var plane_y := _ground_y()
	if absf(direction.y) < 1.0e-6:
		return divider_t
	var hit := origin + direction * ((plane_y - origin.y) / direction.y)
	return session.controller.editor.to_map_xz(hit).dot(right)


## The camera's right direction on the ground, in map XZ metres (a unit vector).
func camera_right() -> Vector2:
	if session.game_map == null or session.controller.editor == null:
		return DEFAULT_RIGHT
	var camera := session.game_map.camera_node
	var origin := Vector3(0.0, _ground_y(), 0.0)
	var from := session.controller.editor.to_map_xz(origin)
	var to := session.controller.editor.to_map_xz(origin + camera.global_transform.basis.x)
	var direction := to - from
	return direction.normalized() if direction.length() > 1.0e-6 else DEFAULT_RIGHT


# ---- internals ----


func _failed(why: String) -> Dictionary:
	return {"ok": false, "error": why}


func _document() -> MapDocument:
	return session.controller.document if session.controller != null else null


func _season() -> String:
	return session.season_id()


func _ground_y() -> float:
	var root := session.controller.map_root
	return root.global_position.y if is_instance_valid(root) else 0.0


func _world_of(xz: Vector2) -> Vector3:
	var root := session.controller.map_root
	var local := Vector3(xz.x, 0.0, xz.y)
	return root.global_transform * local if is_instance_valid(root) else local


## Paints the document for the divider at `divider_t` (all of it on `fresh`) and asks the
## ground and the scatter for what that changed.
func _paint(fresh: bool) -> void:
	var doc := _document()
	var made := session.scatter()
	if doc == null or made == null:
		return
	var from_t := NAN if fresh else _painted_t
	var rect := DesignerSplit.paint(doc, right, from_t, divider_t)
	var lo := minf(from_t, divider_t) if not is_nan(from_t) else -DesignerSplit.FAR
	var hi := maxf(from_t, divider_t) if not is_nan(from_t) else DesignerSplit.FAR
	_painted_t = divider_t
	if not rect.has_area():
		return
	_update_ground(rect)
	var started := Time.get_ticks_usec()
	var info := {}
	if fresh:
		var info_ref := ScatterRefresh.biome(made, String(reference["runtime"]), true)
		info = ScatterRefresh.biome(made, session.runtime_biome_id(), true)
		info["cells"] = int(info.get("cells", 0)) + int(info_ref.get("cells", 0))
	else:
		var size := float(ScatterChunker.CHUNK_SIZE_WORLD_UNITS)
		var cells := DesignerSplit.cells_crossed(doc, right, lo, hi, size)
		for cell in cells:
			made.request_region(cell, true)
		info = {"cells": cells.size(), "species": 0, "of": 0}
	session.begin_request(info, started)


func _update_ground(rect: Rect2i) -> void:
	var editor := session.controller.editor
	if rect.has_area() and editor != null and is_instance_valid(editor.terrain):
		editor.terrain.update_ground_region(rect.grow(1))
