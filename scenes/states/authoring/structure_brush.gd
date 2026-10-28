class_name StructureBrush
extends BrushMode

## The Structure tool's mode (StructureTool): the ghost lot that follows the pointer, a click
## that drops it, a drag that sizes it, Q and E that turn it, R that re-rolls it, and the removal
## of the structure under the pointer. BrushTool routes the tool's press, frames, release and
## cancel to it (the BrushMode hooks below); what a lot may stand on and the plans it takes are
## StructurePlacement's rules, the edit is StructureEditor's (`AuthoringEditor.structures`).
##
## Gesture. With a structure picked (`ref`), the pointer carries a ghost lot at the recipe's
## default size: its footprint on the ground, the door marked on its front, its height as a ring
## over it. The ghost eases to the nearest legal spot (not on water, not on a steep bank, not on
## another building) instead of turning red, and slides there rather than jumping. A click lays
## it. A press and drag sizes it instead: the press is one corner, the pointer the opposite one,
## and the size clamps to the recipe's range (the ghost shows the clamp). The release lays the
## lot as one history entry. Q and E turn the lot 15 degrees (Shift a quarter), R draws the next
## lot's look afresh (or the structure under the pointer), RMB or Delete over a structure
## removes it, Ctrl and a click does too, and RMB or Escape during a drag drops it.
##
## A lot that fits nowhere within StructurePlacement.REACH_M says why in plain words beside the
## cursor; a release then lays nothing and says the same as a toast.

const YAW_STEP := deg_to_rad(15.0)
## A press and release moving the pointer less than this (world metres) is a click.
const DRAG_MIN_M := 0.75
## The pointer's ground point moves this far (metres) before a drag's lot is planned again.
const REPLAN_M := 0.08
## A bracket key makes the size a click lays this much bigger or smaller (multiplicative, like the
## brush size), within SIZE_SCALE_RANGE of the recipe's default.
const SIZE_STEP := 1.1
const SIZE_SCALE_RANGE := Vector2(0.6, 2.5)
## The ghost slides to its target at this rate (per second, exponential).
const EASE_RATE := 22.0
## The door mark is this wide on the front edge (world metres); the footprint fill alpha.
const DOOR_MARK_M := 1.0
const FOOTPRINT_ALPHA := 0.3
## The ghost's edges are sampled this far apart along the ground (metres).
const LINE_STEP_M := 0.5
const FADE_M := 2.5
## Plain-words reasons a lot cannot be laid.
const WATER_TEXT := "Not on the water. Move onto dry ground."
const STEEP_TEXT := "That ground is too steep to build on."
const OFF_MAP_TEXT := "Keep the building on the map."
const OCCUPIED_TEXT := "There is a building here already."
const FULL_TEXT := "The map holds as many buildings as it can. Remove one to make room."
const UNKNOWN_TEXT := "That building is not in a library this map has."
const INVALID_TEXT := "A building cannot stand there."
const NOTHING := "There is no building here to remove."
const NONE_PICKED := "Pick a building to place."

## The structure picked (`<library>:<id>`), "" before one is. Changing it drops the plan of a lot
## being sized and the ghost's remembered spot.
var ref: String = "":
	set(value):
		ref = value
		_planned_to = Vector3.INF
		_wanted = {}
		preview = null
## The turn of the next lot (radians from the map X axis; Q and E), and the size a click lays as
## a multiple of the recipe's default (the bracket keys).
var yaw: float = 0.0
var size_scale: float = 1.0
## The seed the next lot is drawn with (R; each lot laid takes the next one).
var seed_value: int = 4242
## A lot being sized: its first corner and the pointer's last ground point (world).
var drawing: bool = false
var from: Vector3 = Vector3.INF
var to: Vector3 = Vector3.INF
## The structure the drag would lay (map frame; null when no spot), and why not.
var preview: Structure = null
var refusal: String = ""
## The ghost lot's centre now (map XZ; INF before the pointer first reaches the ground), where
## it is easing to, whether that is not where the pointer is, and what stops it (a ground
## problem, "" when it can be laid).
var ghost_centre: Vector2 = Vector2.INF
var target_centre: Vector2 = Vector2.INF
var eased: bool = false
var problem: String = ""
## The size of the lot the ghost shows (map metres) and its plan.
var ghost_size: Vector2 = Vector2.ZERO
## The structure under the pointer (its id), or -1.
var hover_id: int = -1

var _message: String = ""
var _planned_to: Vector3 = Vector3.INF
var _wanted: Dictionary = {}
var _last_ticks: int = 0
var _heights: Dictionary = {}


func _init() -> void:
	fades = true
	picks = true


# ============================================================================
# Pure helpers
# ============================================================================


## The reason a lot cannot be laid (a StructurePlacement problem, or an editor refusal), in plain
## words, or "". Pure.
static func refusal_text(reason: String) -> String:
	match reason:
		StructurePlacement.WATER:
			return WATER_TEXT
		StructurePlacement.STEEP:
			return STEEP_TEXT
		StructurePlacement.OFF_MAP:
			return OFF_MAP_TEXT
		StructurePlacement.OCCUPIED:
			return OCCUPIED_TEXT
		String(StructureEditor.REFUSED_FULL):
			return FULL_TEXT
		String(StructureEditor.REFUSED_UNKNOWN):
			return UNKNOWN_TEXT
		String(StructureEditor.REFUSED_INVALID):
			return INVALID_TEXT
	return ""


## The readout beside the cursor: the structure's name and its two sides ("Cottage  20 x 13 ft").
## Pure.
static func readout(
	title: String, along_m: float, across_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var a := roundi(ScaleUtils.world_to_display(along_m, cell_m, per_cell))
	var b := roundi(ScaleUtils.world_to_display(across_m, cell_m, per_cell))
	return "%s  %d x %d %s" % [title, a, b, label]


## `row` (a LibraryStructureStore row) with its sizes in document metres, for a map whose root is
## scaled `scale` (world metres per document metre): the tool's sizes are world metres, so a
## house keeps its size on a scaled map. Pure.
static func scaled_row(row: Dictionary, scale: float) -> Dictionary:
	var out := row.duplicate()
	for key in ["min_side_m", "max_side_m"]:
		if out.has(key):
			out[key] = float(out[key]) / scale
	if out.has("max_area_m2"):
		out["max_area_m2"] = float(out["max_area_m2"]) / (scale * scale)
	var size := StructurePlacement.default_size(row)
	out["default_size_m"] = [size.x / scale, size.y / scale]
	return out


## `colour` with its alpha set to `alpha`.
static func faded(colour: Color, alpha: float) -> Color:
	var out := colour
	out.a = alpha
	return out


# ============================================================================
# State
# ============================================================================


## Picks the structure `new_ref` to place (a ref the libraries serve; others are kept anyway and
## say so when laid).
func pick(new_ref: String) -> void:
	ref = new_ref
	ghost_centre = Vector2.INF


## The picked structure's palette row, {} when none is picked or no library serves it. With no
## pick yet, the first structure served is picked.
func row() -> Dictionary:
	if ref == "":
		var served := LibraryStructureStore.structures()
		if not served.is_empty():
			pick(String(served[0]["ref"]))
	return LibraryStructureStore.structure(ref) if ref != "" else {}


## The picked structure's name.
func title() -> String:
	return String(row().get("name", "Building"))


## The size (map metres) a click lays: the recipe's default times `size_scale`, clamped.
func default_size(editor: AuthoringEditor) -> Vector2:
	var found := row()
	if found.is_empty():
		return Vector2.ZERO
	var sized := scaled_row(found, editor.map_scale())
	return StructurePlacement.clamp_size(StructurePlacement.default_size(sized) * size_scale, sized)


## The ghost lot's footprint now (map XZ), or empty with no ghost.
func ghost_plan() -> PackedVector2Array:
	if ghost_centre == Vector2.INF or ghost_size == Vector2.ZERO:
		return PackedVector2Array()
	return StructurePlacement.rect_plan(ghost_centre, ghost_size, yaw)


## Starts a lot at world point `hit`.
func begin(hit: Vector3) -> void:
	drawing = true
	from = hit
	to = hit
	preview = null
	refusal = ""
	_planned_to = Vector3.INF
	hover_id = -1


## One frame with the pointer's ground point at `hit` (INF: none) and `delta` seconds since the
## last: while sized, the lot follows the pointer (planned again once it moved REPLAN_M);
## otherwise the idle ghost aims at the nearest legal spot under the pointer. Either way the
## ghost eases toward its target. With `erasing` (Ctrl held) the hover is for a removal.
func track(editor: AuthoringEditor, hit: Vector3, delta: float) -> void:
	if editor == null:
		return
	if drawing:
		if hit != Vector3.INF:
			to = hit
		if _planned_to == Vector3.INF or _planned_to.distance_to(to) >= REPLAN_M:
			_plan(editor)
		_ease(delta)
		return
	hover_id = editor.structures.structure_at(hit) if hit != Vector3.INF else -1
	if hit == Vector3.INF or row().is_empty():
		return
	ghost_size = default_size(editor)
	var want := editor.to_map_xz(hit)
	var key := [StructurePlacement.snapped_centre(want), ghost_size, yaw, _signature(editor)]
	if _wanted.get("key") != key:
		var spot := StructurePlacement.nearest_legal(editor.document, want, ghost_size, yaw)
		_wanted = {"key": key, "spot": spot}
	var found: Dictionary = _wanted["spot"]
	target_centre = found["centre"]
	eased = bool(found["moved"])
	problem = String(found["problem"])
	_ease(delta)


## Moves the ghost toward its target (`delta` seconds), straight there the first time.
func _ease(delta: float) -> void:
	if target_centre == Vector2.INF:
		return
	if ghost_centre == Vector2.INF:
		ghost_centre = target_centre
		return
	var gain := 1.0 - exp(-EASE_RATE * delta)
	ghost_centre = ghost_centre.lerp(target_centre, gain)
	if ghost_centre.distance_to(target_centre) < 0.01:
		ghost_centre = target_centre


## A value that changes when the structures standing do (the ghost's spot is asked again).
func _signature(editor: AuthoringEditor) -> int:
	var ids: Array = []
	for structure in editor.document.structures:
		ids.append([structure.id, structure.footprint])
	return hash(ids)


func _plan(editor: AuthoringEditor) -> void:
	_planned_to = to
	preview = null
	refusal = ""
	var found := row()
	if found.is_empty():
		refusal = NONE_PICKED
		return
	var scale := editor.map_scale()
	var a := editor.to_map_xz(from)
	var b := editor.to_map_xz(to)
	var sized := scaled_row(found, scale)
	var size := default_size(editor)
	var centre := a
	if a.distance_to(b) * scale >= DRAG_MIN_M:
		var corners := StructurePlacement.corner_plan(a, b, yaw, sized)
		size = corners["size"]
		centre = corners["centre"]
	ghost_size = size
	var spot := StructurePlacement.nearest_legal(editor.document, centre, size, yaw)
	target_centre = spot["centre"]
	eased = bool(spot["moved"])
	problem = String(spot["problem"])
	if problem != "":
		refusal = problem
		return
	preview = editor.structures.lot(ref, spot["plan"], seed_value)
	if preview == null:
		refusal = String(editor.structures.last_refusal)


## Lays the lot being sized (the release): the structure's id, or -1 with message() saying why.
func finish(editor: AuthoringEditor) -> int:
	_message = ""
	if not drawing:
		return -1
	drawing = false
	if _planned_to != to or to == from:
		_plan(editor)
	var placed := -1
	if preview != null:
		placed = editor.structures.add(preview)
		if placed >= 0:
			seed_value = StructureEditor.next_seed(seed_value)
			_wanted = {}
		else:
			refusal = String(editor.structures.last_refusal)
	if placed < 0:
		_message = refusal_text(refusal)
	preview = null
	return placed


## Removes the structure under world point `hit` (a Ctrl press). False, with message() set, when
## there is none.
func erase_at(editor: AuthoringEditor, hit: Vector3) -> bool:
	_message = ""
	var found := editor.structures.structure_at(hit)
	if found < 0 or not editor.structures.remove(found):
		_message = NOTHING
		return false
	hover_id = -1
	_wanted = {}
	return true


## Why the last finish() or erase_at() made nothing, or "".
func message() -> String:
	return _message


## Drops a lot being sized (a cancel, or after a release).
func reset() -> void:
	drawing = false
	preview = null
	refusal = ""
	_planned_to = Vector3.INF


## Turns the next lot `steps` notches of YAW_STEP (E clockwise on screen).
func turn(steps: int) -> void:
	yaw = wrapf(yaw + steps * YAW_STEP, 0.0, TAU)
	_planned_to = Vector3.INF
	_wanted = {}


## Draws the next lot afresh, or re-rolls the structure under world point `hit` (-1 for none).
func reroll_at(editor: AuthoringEditor, under: int) -> void:
	if under >= 0 and editor != null:
		editor.structures.reroll(under)
		return
	seed_value = StructureEditor.next_seed(seed_value)


# ============================================================================
# BrushMode hooks
# ============================================================================


## Starts a lot, or with Ctrl erases the structure under the press (a miss says why).
func press(brush: BrushTool) -> bool:
	if brush.press_ctrl:
		if not erase_at(brush.editor, brush.hit):
			brush.refused.emit(message())
		return false
	if row().is_empty():
		brush.refused.emit(NONE_PICKED)
		return false
	begin(brush.hit)
	return false


## True when the press began a lot (an erase is silent, as a prop's removal is).
func took_press() -> bool:
	return drawing


func has_target() -> bool:
	return hover_id >= 0


func frame(brush: BrushTool) -> void:
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _last_ticks == 0 else minf(float(now - _last_ticks) / 1.0e6, 0.1)
	_last_ticks = now
	track(brush.editor, brush.hit, delta)


## Lays the lot being sized (a lot that fits nowhere says why).
func end(brush: BrushTool) -> void:
	if drawing and brush.editor != null:
		if finish(brush.editor) < 0:
			brush.refused.emit(message())
	reset()


func cancel(_brush: BrushTool) -> void:
	reset()


func leave(_brush: BrushTool) -> void:
	reset()
	hover_id = -1
	ghost_centre = Vector2.INF
	target_centre = Vector2.INF
	_wanted = {}
	_last_ticks = 0


## Shift+wheel over a building and the bracket keys: the size a click lays, a notch of SIZE_STEP
## each way (a drag still sizes a lot exactly).
func step(brush: BrushTool, steps: int) -> void:
	size_scale = stepped_scale(size_scale, steps)
	_planned_to = Vector3.INF
	_wanted = {}
	brush.redraw()


## `scale` stepped `steps` notches within SIZE_SCALE_RANGE. Pure.
static func stepped_scale(scale: float, steps: int) -> float:
	return clampf(scale * pow(SIZE_STEP, steps), SIZE_SCALE_RANGE.x, SIZE_SCALE_RANGE.y)


func rotates() -> bool:
	return true


func rotate(brush: BrushTool, steps: int) -> void:
	turn(steps)
	brush.redraw()


func rerolls() -> bool:
	return true


func reroll(brush: BrushTool) -> void:
	reroll_at(brush.editor, hover_id)
	_wanted = {}
	brush.redraw()


## RMB or Delete over a structure.
func remove_target(brush: BrushTool) -> void:
	if brush.editor != null and not erase_at(brush.editor, brush.hit):
		brush.refused.emit(message())


## The lot stays in view under a canopy: the focus is its middle.
func fade_focus(brush: BrushTool) -> Vector4:
	var centre := brush.hit
	if ghost_centre != Vector2.INF and brush.editor != null:
		var ground := WaterGeometry.ground_at(brush.editor.document, ghost_centre)
		centre = brush.editor.to_world(Vector3(ghost_centre.x, ground, ghost_centre.y))
	var reach := maxf(FADE_M, maxf(ghost_size.x, ghost_size.y) * 0.5 + 1.0)
	return Vector4(centre.x, centre.y, centre.z, reach)


func draw_cursor(brush: BrushTool, cursor: BrushCursor) -> void:
	if brush.editor == null:
		return
	var units := [brush.unit_cell_m, brush.unit_per_cell, brush.unit_label]
	var erasing := brush.ctrl and not brush.pressed
	draw(cursor.canvas, cursor.camera, brush.editor, brush.hit, erasing, units)


# ============================================================================
# Drawing
# ============================================================================


## The cursor and previews on `canvas` (see the header), for the pointer's ground point `hit`
## with Ctrl `erasing`; the readout in the level's units.
func draw(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	hit: Vector3,
	erasing: bool,
	units: Array
) -> void:
	var cell_m: float = units[0]
	var per_cell: float = units[1]
	var label: String = units[2]
	var scale := editor.map_scale()
	if not drawing and hover_id >= 0:
		var hovered := editor.document.structure(hover_id)
		if hovered != null:
			var strength := 1.0 if erasing else 0.45
			var tint := WallBrush.ERASE_TINT if erasing else WallBrush.STONE_TINT
			draw_plan(canvas, camera, editor, hovered.footprint, 0.0, tint, strength)
			if erasing:
				BridgeBrush.draw_pill(
					canvas,
					camera.unproject_position(hit),
					"Remove " + String(hovered.recipe.get_slice(":", 1)).replace("_", " "),
					WallBrush.REFUSED_COLOR
				)
				return
	elif erasing and not drawing:
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.ERASE_TINT)
		return
	if row().is_empty():
		if hit != Vector3.INF:
			BridgeBrush.draw_marker(canvas, camera, hit, WallBrush.STONE_TINT)
			BridgeBrush.draw_pill(
				canvas, camera.unproject_position(hit), NONE_PICKED, WallBrush.REFUSED_COLOR
			)
		return
	var plan := ghost_plan()
	if plan.is_empty():
		return
	var ok := problem == "" and (not drawing or preview != null)
	var tint := WallBrush.STONE_TINT if ok else WallBrush.REFUSED_COLOR
	var high := _height_of(ref) / scale
	draw_plan(canvas, camera, editor, plan, high, tint, 1.0 if drawing else 0.8)
	if drawing:
		for corner in [from, to]:
			BridgeBrush.draw_marker(canvas, camera, corner, tint)
	var ground := WaterGeometry.ground_at(editor.document, ghost_centre)
	var anchor := editor.to_world(Vector3(ghost_centre.x, ground, ghost_centre.y))
	var text := refusal_text(refusal if drawing else problem)
	if ok:
		text = readout(title(), ghost_size.x * scale, ghost_size.y * scale, cell_m, per_cell, label)
	BridgeBrush.draw_pill(
		canvas,
		camera.unproject_position(anchor),
		text,
		WallBrush.READOUT_COLOR if ok else WallBrush.REFUSED_COLOR
	)


## The recipe's default wall height in metres (cached per structure).
func _height_of(structure_ref: String) -> float:
	if not _heights.has(structure_ref):
		var height := LibraryStructures.TILE_DEFAULT_HEIGHT_M
		var recipe := StructureRecipes.document(structure_ref)
		if recipe != null:
			for item: Dictionary in recipe.interface:
				if String(item.get("name", "")) == "height":
					height = float(item.get("default", height))
		_heights[structure_ref] = height
	return _heights[structure_ref]


## A footprint (map XZ) on `canvas`: its outline on the ground, faintly filled, a ring `height`
## (document metres) above it joined by a pole at each corner, and the door marked on its front
## edge (edge 0: a bar the door width and a tick out from it). Every point sits on the
## document's ground.
static func draw_plan(
	canvas: Control,
	camera: Camera3D,
	editor: AuthoringEditor,
	plan: PackedVector2Array,
	height: float,
	tint: Color,
	strength: float
) -> void:
	var count := plan.size()
	if count < 3:
		return
	var doc := editor.document
	var screen := func(p: Vector2, lift: float) -> Vector2:
		var y := WaterGeometry.ground_at(doc, p) + lift
		return camera.unproject_position(editor.to_world(Vector3(p.x, y, p.y)))
	var base := PackedVector2Array()
	var top := PackedVector2Array()
	var corners := PackedVector2Array()
	for k in count:
		var a := plan[k]
		var b := plan[(k + 1) % count]
		var pieces := maxi(1, ceili(a.distance_to(b) / LINE_STEP_M))
		corners.append(screen.call(a, 0.04))
		for s in pieces:
			var xz := a.lerp(b, float(s) / pieces)
			base.append(screen.call(xz, 0.04))
			top.append(screen.call(xz, height))
	base.append(base[0])
	top.append(top[0])
	var fill := Geometry2D.triangulate_polygon(plan)
	if not fill.is_empty():
		var vertices := PackedVector2Array()
		for p in plan:
			vertices.append(screen.call(p, 0.04))
		var colors := PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(faded(tint, FOOTPRINT_ALPHA * strength))
		RenderingServer.canvas_item_add_triangle_array(
			canvas.get_canvas_item(), fill, vertices, colors
		)
	if height > 0.0:
		for k in count:
			var pole_base: Vector2 = screen.call(plan[k], 0.04)
			var pole_top: Vector2 = screen.call(plan[k], height)
			canvas.draw_line(pole_base, pole_top, faded(tint, 0.3 * strength), 1.0, true)
		canvas.draw_polyline(top, faded(WallBrush.SHADOW, 0.6 * strength), 3.0, true)
		canvas.draw_polyline(top, faded(tint, 0.7 * strength), 1.5, true)
	canvas.draw_polyline(base, faded(WallBrush.SHADOW, 0.6 * strength), 3.5, true)
	canvas.draw_polyline(base, faded(tint, 0.95 * strength), 1.75, true)
	for p in corners:
		canvas.draw_circle(p, 4.5, faded(WallBrush.SHADOW, 0.7 * strength))
		canvas.draw_circle(p, 3.0, faded(tint, strength))
	var scale := editor.map_scale()
	var door := DOOR_MARK_M / scale
	var middle := ProcgenPlan.edge_middle(plan, 0)
	var along := (ProcgenPlan.edge_end(plan, 0) - ProcgenPlan.edge_start(plan, 0)).normalized()
	var out := ProcgenPlan.outward(plan, 0)
	var left: Vector2 = screen.call(middle - along * door * 0.5, 0.05)
	var right: Vector2 = screen.call(middle + along * door * 0.5, 0.05)
	var step: Vector2 = screen.call(middle + out * door * 0.6, 0.05)
	var centre: Vector2 = screen.call(middle, 0.05)
	var white := faded(Color.WHITE, strength)
	canvas.draw_line(left, right, faded(WallBrush.SHADOW, 0.8 * strength), 7.0, true)
	canvas.draw_line(left, right, white, 4.0, true)
	canvas.draw_line(centre, step, faded(WallBrush.SHADOW, 0.8 * strength), 5.0, true)
	canvas.draw_line(centre, step, white, 2.5, true)
