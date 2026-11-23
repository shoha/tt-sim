class_name TerraPaint
extends RefCounted

## The Paint tool on terrain primitives (card terraform-p2-paint-path; docs/systems/terraform.md
## "Tools"): TerraEditor's paint ops while active(). One stroke is one paint coat (kind 8), one
## TerraEditor gesture and one history entry, whose undo and redo are exact.
##
## A coat. The press names the surface: an index of the document's surface table
## (TerraDoc.surfaces; a new name is appended by a "surfaces" edit inside the gesture, so undo takes
## it back), or PaintKind.ERASE_SURFACE for Ctrl, which fades every painted surface back to the
## automatic ground. The first frame with dabs adds the coat, every later frame appends that
## frame's capsule (PaintKind.dab: from, to, radius, seconds), so the coat reads as SurfaceStroke's
## stroke: the newest paint wins, a fifth surface drops the weakest (the paint stage's kernel). A
## map lists at most TerraDoc.MAX_SURFACES surfaces (refusal()).
##
## Ground. Every frame goes through TerraEditor.edit(change, true) (TerraBridge.held: derived at
## once when the session is free); the bridge writes the planes into MapDocument.surface_weights
## and calls land(), which updates the ground's weight maps over the written rect, as today's
## Paint flush does. No heights move, so no HeightEditor stroke is held. Plants follow at the end:
## when a surface of the table changes what grows (built, cliff or ash;
## SurfaceStroke.changes_plants), the scatter is requested over the stroke's rect at the release
## and over each undo's or redo's landing. Never blocking: nothing here waits for a derive.

const PaintKind := preload("res://utils/terraform/kinds/paint/paint_kind.gd")
const PathKind := preload("res://utils/terraform/kinds/path/path_kind.gd")
const PATH_LABEL := "Path"
const ERASE_PATH_LABEL := "Erase path"
## Why a new surface cannot be painted when the table is full.
const FULL_REASON := (
	"This map already uses 64 paint surfaces: paint with one of them" + " (or start a new map)."
)

## Microseconds of the last frame's edit (the held derive and the bridge's writes included).
var last_frame_usec := 0
## Microseconds of the last landing's ground weight-map update (land()).
var last_land_usec := 0
## Landings handed to land() (tests).
var landings := 0

var _editor_ref: WeakRef = null
var _terra_ref: WeakRef = null
var _active := false
## The coat's surface index (or ERASE_SURFACE), its id once added (-1: not yet), the frames' dabs
## not yet sent, the document rect the stroke's landings wrote, and the history label.
var _surface := -1
var _id := -1
var _pending := PackedFloat32Array()
var _rect := Rect2i()
var _label := ""


static func create(editor: AuthoringEditor, terra: TerraEditor) -> TerraPaint:
	var p := TerraPaint.new()
	p._editor_ref = weakref(editor)
	p._terra_ref = weakref(terra)
	return p


func _editor() -> AuthoringEditor:
	return _editor_ref.get_ref() as AuthoringEditor if _editor_ref != null else null


func _terra() -> TerraEditor:
	return _terra_ref.get_ref() as TerraEditor if _terra_ref != null else null


## True while a stroke is in progress.
func is_stroking() -> bool:
	return _active


## Why palette surface `surface` cannot be painted now, or "": a name the table lacks while it
## holds MAX_SURFACES.
func refusal(surface: String) -> String:
	var s := _terra().session()
	if s == null or s.terra == null:
		return ""
	var table := s.terra.surfaces
	if surface == "" or surface in table or table.size() < TerraDoc.MAX_SURFACES:
		return ""
	return FULL_REASON


## Starts a coat of palette surface `surface`, or with `erase` an erase coat. False when there is
## nothing to erase, no surface or the table is full (refusal()).
func begin(surface: String, erase: bool) -> bool:
	var terra := _terra()
	var s := terra.session()
	if s == null or s.terra == null:
		return false
	var table := s.terra.surfaces
	if erase and table.is_empty():
		return false
	if not erase and (surface == "" or refusal(surface) != ""):
		return false
	terra.begin_gesture()
	_surface = PaintKind.ERASE_SURFACE if erase else table.find(surface)
	if not erase and _surface < 0:
		var names := table.duplicate()
		names.append(surface)
		if terra.edit({"op": "surfaces", "names": names}) < 0:
			terra.abandon_gesture()
			return false
		_surface = names.size() - 1
	_active = true
	_id = -1
	_pending = PackedFloat32Array()
	_rect = Rect2i()
	_label = "Erase paint" if erase else "Paint " + AuthoringPanel.surface_label(surface).to_lower()
	return true


## One frame's exposure (world points and radius): the frame's dab, sent at flush().
func dab(from: Vector3, to: Vector3, radius: float, seconds: float) -> void:
	if not _active:
		return
	var e := _editor()
	var r := radius / e.map_scale()
	_pending.append_array(PaintKind.dab(e.to_map_xz(from), e.to_map_xz(to), r, seconds))


## Sends this frame's dabs to the ground (TerraBridge.held).
func flush() -> void:
	if not _active or _pending.is_empty():
		return
	var started := Time.get_ticks_usec()
	# A fresh array each frame: the session tells the derive this one, and nothing writes it again.
	var data := _pending
	_pending = PackedFloat32Array()
	if _id < 0:
		var coat := PackedFloat32Array([_surface])
		coat.append_array(data)
		_id = _terra().edit({"op": "add", "kind": TerraCore.PAINT, "data": coat, "flags": 0}, true)
	else:
		_terra().edit({"op": "append", "id": _id, "data": data}, true)
	last_frame_usec = Time.get_ticks_usec() - started
	_editor().last_flush_usec = last_frame_usec


## Ends the stroke and records its gesture. True when it changed anything.
func end_stroke() -> bool:
	if not _active:
		return false
	flush()
	_active = false
	var terra := _terra()
	if not terra.is_open():
		return false
	var g := terra.end_gesture(_label, {}, false)
	if g.is_empty():
		return false
	_regrow(_rect)
	return true


## Abandons the stroke: its edits are taken back as an undo would, with no history entry.
func cancel_stroke() -> void:
	if not _active:
		return
	_active = false
	_pending = PackedFloat32Array()
	var inverse := _terra().abandon_gesture()
	if not inverse.is_empty():
		_terra().apply_edits(inverse, {}, false)


## The Path tool's release (a line gesture; card terraform-p2-paint-path): one path primitive
## (kind 6) of `width` metres along `line` (map XZ) painting palette surface `surface` ("" paints
## nothing), as one gesture whose landing benches and grades the ground (the paths stage) and
## lays the surface as a coat at the path's place. Its id, or -1 when refused (a line under two
## points, the table full, or the session refused it).
func add_path(line: PackedVector2Array, width: float, surface: String) -> int:
	var terra := _terra()
	var s := terra.session()
	if s == null or s.terra == null or line.size() < 2 or width <= 0.0 or refusal(surface) != "":
		return -1
	terra.begin_gesture()
	var index := PathKind.NO_SURFACE
	if surface != "":
		index = s.terra.surfaces.find(surface)
		if index < 0:
			var names := s.terra.surfaces.duplicate()
			names.append(surface)
			terra.edit({"op": "surfaces", "names": names})
			index = names.size() - 1
	var data := PathKind.make(width, index, line)
	var id := terra.edit({"op": "add", "kind": TerraCore.PATH, "data": data, "flags": 0})
	terra.end_gesture(PATH_LABEL)
	return id


## The Path tool's Ctrl release: every path primitive whose line comes within its own half width
## plus `half_width` (map metres) of `line` (map XZ) is removed, in one gesture "Erase path" whose
## landing takes back its grading and its surface. The number removed (0: none touched, nothing
## recorded).
func erase_paths(line: PackedVector2Array, half_width: float) -> int:
	var terra := _terra()
	var s := terra.session()
	if s == null or s.terra == null or line.size() < 2:
		return 0
	var ids := touched_paths(s.terra, line, half_width)
	if ids.is_empty():
		return 0
	terra.begin_gesture()
	for id in ids:
		terra.edit({"op": "remove", "id": id})
	terra.end_gesture(ERASE_PATH_LABEL)
	return ids.size()


## The path primitive ids (document order) whose line comes within their half width plus
## `half_width` of `line` (map XZ). Pure.
static func touched_paths(
	terra: TerraDoc, line: PackedVector2Array, half_width: float
) -> Array[int]:
	var out: Array[int] = []
	for p: Dictionary in terra.prims:
		if int(p.kind) != TerraCore.PATH:
			continue
		var data: PackedFloat32Array = p.data
		var reach := data[0] * 0.5 + half_width
		if _near(data.slice(PathKind.HEADER), line, reach):
			out.append(int(p.id))
	return out


## True when polyline `flat` (x, z pairs) comes within `reach` of polyline `line`.
static func _near(flat: PackedFloat32Array, line: PackedVector2Array, reach: float) -> bool:
	for i in range(0, flat.size() - 3, 2):
		var p := Vector2(flat[i], flat[i + 1])
		var q := Vector2(flat[i + 2], flat[i + 3])
		for k in line.size() - 1:
			var near := Geometry2D.get_closest_points_between_segments(p, q, line[k], line[k + 1])
			if near[0].distance_to(near[1]) <= reach:
				return true
	return false


## A settlement's paving (SettlementPaint.lay while active): `strokes` (SettlementGround.plan's:
## {"surface", "from", "to", "radius", "seconds"}, map XZ) as one coat per run of one surface, in
## one gesture labelled `label`. Returns the coats added (0: nothing, or the table is full).
func lay_coats(strokes: Array[Dictionary], label: String) -> int:
	var terra := _terra()
	var s := terra.session()
	if s == null or s.terra == null or strokes.is_empty():
		return 0
	var names := s.terra.surfaces.duplicate()
	for stroke in strokes:
		var name := str(stroke["surface"])
		if not name in names:
			if names.size() >= TerraDoc.MAX_SURFACES:
				return 0
			names.append(name)
	terra.begin_gesture()
	if names != s.terra.surfaces:
		terra.edit({"op": "surfaces", "names": names})
	var added := 0
	var doc := _editor().document
	var area := Rect2i()
	for coat: PackedFloat32Array in coats_of(strokes, names):
		if terra.edit({"op": "add", "kind": TerraCore.PAINT, "data": coat, "flags": 0}) > 0:
			added += 1
			var box := PaintKind.bounds(coat)
			var low := Vector2i(doc.world_to_sample(box.position).floor())
			var high := Vector2i(doc.world_to_sample(box.end).ceil())
			area = MaskBrush.merge_rect(area, Rect2i(low, high - low + Vector2i.ONE))
	terra.end_gesture(label)
	_regrow(area.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z())))
	return added


## Takes back the coats lay_coats() made of `strokes` (SettlementPaint.unlay while active): every
## paint coat equal to one of them is removed, in one gesture. Returns 1 when one was.
func unlay_coats(strokes: Array[Dictionary], label: String) -> int:
	var terra := _terra()
	var s := terra.session()
	if s == null or s.terra == null or strokes.is_empty():
		return 0
	var wanted := coats_of(strokes, s.terra.surfaces)
	var gone: Array[int] = []
	for p in s.terra.prims:
		if int(p["kind"]) == TerraCore.PAINT and wanted.has(p["data"]):
			gone.append(int(p["id"]))
	if gone.is_empty():
		return 0
	terra.begin_gesture()
	for id in gone:
		terra.edit({"op": "remove", "id": id})
	terra.end_gesture(label)
	return 1


## The coats of `strokes` (one per run of one surface, in order) against surface table `names`.
## Pure.
static func coats_of(strokes: Array[Dictionary], names: PackedStringArray) -> Array:
	var out: Array = []
	var coat := PackedFloat32Array()
	var surface := ""
	for stroke in strokes:
		var name := str(stroke["surface"])
		if coat.is_empty() or name != surface:
			if coat.size() > 1:
				out.append(coat)
			surface = name
			coat = PackedFloat32Array([names.find(name)])
		coat.append_array(
			PaintKind.dab(stroke["from"], stroke["to"], stroke["radius"], stroke["seconds"])
		)
	if coat.size() > 1:
		out.append(coat)
	return out


## A paint landing (TerraBridge._land_paint): the ground's weight maps over document rect `rect`
## (or only the tables, for a surface table change), and, outside a stroke's held frames, the
## plants over it.
func land(rect: Rect2i, is_held: bool) -> void:
	landings += 1
	var e := _editor()
	if e == null:
		return
	if is_instance_valid(e.terrain):
		var started := Time.get_ticks_usec()
		e.terrain.update_ground_region(rect.grow(1) if rect.has_area() else Rect2i())
		last_land_usec = Time.get_ticks_usec() - started
		e.ground_updates += 1
	if not rect.has_area():
		return
	if _active:
		_rect = MaskBrush.merge_rect(_rect, rect)
	elif not is_held:
		_regrow(rect)


## Requests the scatter over document rect `rect` when a surface of the table changes what grows
## (AuthoringEditor._request_paint_rect's reach: the painted edge warp and the path fringe).
func _regrow(rect: Rect2i) -> void:
	var e := _editor()
	var s := _terra().session()
	if e == null or s == null or not rect.has_area() or not is_instance_valid(e.scatter):
		return
	var diff := {"ids_before": s.terra.surfaces, "ids_after": PackedStringArray()}
	if not SurfaceStroke.changes_plants(diff, PaletteLibrary.surfaces(e.palette_root)):
		return
	var doc := e.document
	var step := doc.sample_step()
	var reach := TerrainRules.PAINT_EDGE_WARP_M + ScatterGround.FRINGE_RADIUS_M
	e.scatter.request_region(
		MaskBrush.sample_rect_to_world(doc, rect).grow(maxf(step.x, step.y) + reach)
	)
