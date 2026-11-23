class_name TerraWaterTools
extends RefCounted
## The Water tool on terrain primitives (card terraform-p2-water; docs/systems/terraform.md
## "Tools"): with the terraforming core active, a river release, a pond stroke and a water erase
## are each one TerraEditor gesture of river (kind 4) and pond (kind 5) edits, and the derive does
## the rest: levels found downhill, the bed carved, an uphill stroke flipped, ends joined at the
## receiver's level, falls of FALL_MIN or more and riffles under it, a line over a rise cut
## through. The bridge writes the derived water and WaterEditor.land_external dresses it (wet
## dressing, AuthoredWater, wet rocks, the crossing follow, regrowth); its record becomes the
## gesture's water side (TerraEditor._land keeps it, undo and redo apply its props rows).
## Part of TerraEditor (`TerraEditor.water_tools`), split out by tool as each card adds its own.
##
## River. The drawn line (WaterBrush: smoothed, through_rises) in map XZ, conditioned within its
## cap (WaterCourseFit.condition: half a half-width), one `add` of [width, depth, x, z...] with
## the brush's width and the tile's depth (WaterBody.DEPTH_M). Points past the map edge are kept:
## the bridge makes them the course into the haze (`beyond`). Before the add, the caps: the reaches
## the derive could make of it (reach_bound()) must fit MapDocument.MAX_RIVERS beside today's,
## since the bridge refuses a whole set over a cap and would leave the water as it was.
##
## Pond. Dabs are capsules in a scratch list, traced on release (PondOutline.trace) to an outline:
## one `add`, or with the press inside a pond one `replace` of that pond's outline merged with the
## stroke (it takes the stroke's depth). A new pond never covers another (clipped out of it).
##
## Erase (Ctrl, either tile). The rivers the stroke touches (their derived lines, within the half
## width) are removed whole, with every river whose water ends in one of them (recv_river, followed
## upstream); ponds it covers are clipped (`replace`) or removed when less than
## PondOutline.MIN_AREA_M2 is left, and their level settles to the new rim in the derive. The carve
## goes with the river (the bed is the river's: a deliberate change from today's, which kept it).

## Refusals (the brush toasts them; WaterBrush's words).
const FULL := WaterBrush.FULL
const NOTHING := WaterBrush.NOTHING
const REFUSED := "The terrain core refused that water."
## The labels of the gestures.
const RIVER_LABEL := "Carve river"
const POND_LABEL := "Paint pond"
const ERASE_LABEL := "Erase water"
## The derive's flat-reach rule (terraform.md "Flat reaches"), for reach_bound(): a reach is at
## least MIN_REACH_M long, and reaches step by at least REACH_DEAD_BAND_M.
const MIN_REACH_M := 2.0
const REACH_DEAD_BAND_M := 0.25

## Why the last op refused ("" when it did not, or made nothing silently).
var last_refusal := ""
## The last river add's conditioning ({"max_disp", "changed", "reach_bound"}), for tests.
var last_river: Dictionary = {}

var _owner: WeakRef = null
## The stroke in progress: {"kind": "pond" or "erase", "dabs": capsules (PondOutline.DAB floats
## each, map XZ), "depth", "target": pond id pressed inside, or -1}, or {}.
var _stroke: Dictionary = {}


func _init(terra: TerraEditor = null) -> void:
	_owner = weakref(terra) if terra != null else null


func _terra() -> TerraEditor:
	return _owner.get_ref() as TerraEditor if _owner != null else null


# ============================================================================
# River
# ============================================================================


## A river release (TerraEditor.river): `line` world XZ, `half_widths` world metres (one for all
## points works), depth class `depth`. The new primitive's id, or -1 (last_refusal says why; ""
## for a line too short to carve, which makes nothing).
func add_river(line: PackedVector2Array, half_widths: PackedFloat32Array, depth: int) -> int:
	last_refusal = ""
	last_river = {}
	var te := _terra()
	var e := te._editor()
	te.prepare_gesture()
	var scale := e.map_scale()
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	for i in line.size():
		points.append(e.to_map_xz(Vector3(line[i].x, 0.0, line[i].y)))
		var w := half_widths[mini(i, half_widths.size() - 1)] if not half_widths.is_empty() else 1.0
		widths.append(clampf(w / scale, WaterBody.MIN_HALF_WIDTH_M, WaterBody.MAX_HALF_WIDTH_M))
	if points.size() < 2 or StrokePath.line_length(points) < StrokePath.MIN_LENGTH_M:
		e.water.last_refusal = WaterEditor.REFUSED_SHORT
		return -1
	var ground_of := WaterBrush.ground_reader(e)
	var ground := PackedFloat32Array()
	for p in line:
		ground.append(float(ground_of.call(p)))
	var bound := reach_bound(points, ground)
	if not fits(e.document, bound, 0):
		last_refusal = FULL
		return -1
	var fit := WaterCourseFit.condition(points, widths)
	last_river = {"max_disp": fit.max_disp, "changed": fit.changed, "reach_bound": bound}
	var data := river_data(fit.points, fit.widths, WaterBody.DEPTH_M[clampi(depth, 0, 2)])
	te.begin_gesture()
	var id := te.edit({"op": "add", "kind": TerraCore.RIVER, "data": data})
	if id < 0:
		te.end_gesture(RIVER_LABEL)
		last_refusal = REFUSED
		return -1
	te.end_gesture(RIVER_LABEL)
	e.water.last_refusal = &""
	e.water.last_hints = []
	return id


## River primitive data for conditioned `points` (map XZ) with half-widths `widths`: the widest
## half-width as the width (the kind has one), `depth_m`, then the points. Pure.
static func river_data(
	points: PackedVector2Array, widths: PackedFloat32Array, depth_m: float
) -> PackedFloat32Array:
	var hw := WaterBody.MIN_HALF_WIDTH_M
	for w in widths:
		hw = maxf(hw, w)
	var data := PackedFloat32Array([2.0 * hw, depth_m])
	for p in points:
		data.append_array([p.x, p.y])
	return data


## The most reaches the derive can make of a river along `points` (map XZ) over ground heights
## `ground` (map metres, one per point): no more than one per MIN_REACH_M of length, nor than one
## per REACH_DEAD_BAND_M of the running drop, plus a fall and the end. Pure.
static func reach_bound(points: PackedVector2Array, ground: PackedFloat32Array) -> int:
	var by_length := floori(StrokePath.line_length(points) / MIN_REACH_M) + 1
	if ground.size() != points.size() or ground.is_empty():
		return by_length
	var lo := ground[0]
	var hi := ground[0]
	for h in ground:
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return mini(by_length, floori((hi - lo) / REACH_DEAD_BAND_M) + 2)


## True when `doc`'s water (today's bodies, the derived reaches) can take `rivers` more river
## reaches and `ponds` more ponds within MapDocument's caps.
static func fits(doc: MapDocument, rivers: int, ponds: int) -> bool:
	var reaches := 0
	for body in doc.water_bodies:
		if body.is_river():
			reaches += 1
	var bodies := doc.water_bodies.size() + rivers + ponds
	return reaches + rivers <= MapDocument.MAX_RIVERS and bodies <= MapDocument.MAX_WATER_BODIES


# ============================================================================
# Pond and erase strokes
# ============================================================================


## A pond press of depth class `depth` at world point `hit` (TerraEditor.begin_pond): inside a pond
## it extends that one. False with last_refusal FULL when a new pond would pass the caps.
func begin_pond(depth: int, hit: Vector3) -> bool:
	last_refusal = ""
	var te := _terra()
	var e := te._editor()
	te.prepare_gesture()
	var target := pond_at(te.session().terra, e.to_map_xz(hit))
	if target < 0 and not fits(e.document, 0, 1):
		last_refusal = FULL
		return false
	_stroke = {"kind": "pond", "dabs": PackedFloat32Array(), "depth": depth, "target": target}
	return true


## An erase press (TerraEditor.begin_water_erase): false with last_refusal NOTHING when the
## document holds no water primitive.
func begin_erase() -> bool:
	last_refusal = ""
	var te := _terra()
	te.prepare_gesture()
	for p: Dictionary in te.session().terra.prims:
		if int(p.kind) == TerraCore.RIVER or int(p.kind) == TerraCore.POND:
			_stroke = {"kind": "erase", "dabs": PackedFloat32Array(), "depth": 0, "target": -1}
			return true
	last_refusal = NOTHING
	return false


## True while a pond or erase stroke is in progress.
func is_stroking() -> bool:
	return not _stroke.is_empty()


## One frame's capsule of the stroke (world points, world radius).
func dab(from: Vector3, to: Vector3, radius: float) -> void:
	if _stroke.is_empty():
		return
	var e := _terra()._editor()
	var a := e.to_map_xz(from)
	var b := e.to_map_xz(to)
	# A packed array read from a Dictionary is a copy: append to it and store it back.
	var dabs: PackedFloat32Array = _stroke.dabs
	dabs.append_array([a.x, a.y, b.x, b.y, radius / e.map_scale()])
	_stroke.dabs = dabs


## Ends the stroke: one gesture (see the header). True when it changed anything.
func end_stroke() -> bool:
	var stroke := _stroke
	_stroke = {}
	if stroke.is_empty():
		return false
	var te := _terra()
	var changes := (
		pond_changes(te.session().terra, stroke)
		if stroke.kind == "pond"
		else erase_changes(te.session(), stroke.dabs)
	)
	if changes.is_empty():
		return false
	te.begin_gesture()
	for change: Dictionary in changes:
		if te.edit(change) < 0:
			push_warning("TerraWaterTools: the session refused a %s edit" % change.op)
	var g := te.end_gesture(POND_LABEL if stroke.kind == "pond" else ERASE_LABEL)
	return not g.is_empty()


## Abandons the stroke (nothing was applied yet).
func cancel_stroke() -> void:
	_stroke = {}


## The edits a pond stroke `stroke` makes on `terra` (see the header): [] when it painted nothing.
static func pond_changes(terra: TerraDoc, stroke: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var outline := PondOutline.trace(stroke.dabs)
	if outline.is_empty():
		return out
	var depth_m: float = WaterBody.DEPTH_M[clampi(int(stroke.depth), 0, 2)]
	var target := int(stroke.target)
	if target >= 0:
		var old := PondOutline.of_data(terra.find(target).data)
		outline = PondOutline.merged(old, outline)
	for p: Dictionary in terra.prims:
		if int(p.kind) != TerraCore.POND or int(p.id) == target or outline.is_empty():
			continue
		var other := PondOutline.of_data(p.data)
		if PondOutline.overlaps(outline, other):
			outline = PondOutline.clipped(outline, other)
	if outline.size() < 3:
		return out
	var data := PackedFloat32Array([depth_m]) + PondOutline.floats(outline)
	if target >= 0:
		out.append({"op": "replace", "id": target, "data": data})
	else:
		out.append({"op": "add", "kind": TerraCore.POND, "data": data})
	return out


## The edits an erase stroke of capsules `dabs` makes on `s`'s document (see the header): the
## touched rivers and their tributaries removed, the covered ponds clipped or removed.
static func erase_changes(s: TerraSession, dabs: PackedFloat32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var terra := s.terra
	var derive := s.settled_derive()
	var records: Array = derive.call("water_records").get("rivers", []) if derive != null else []
	for id in erased_rivers(terra, records, dabs):
		out.append({"op": "remove", "id": id})
	var cut := PondOutline.trace(dabs)
	if cut.is_empty():
		return out
	for p: Dictionary in terra.prims:
		if int(p.kind) != TerraCore.POND:
			continue
		var outline := PondOutline.of_data(p.data)
		if not PondOutline.overlaps(outline, cut):
			continue
		var left := PondOutline.clipped(outline, cut)
		if left.size() < 3:
			out.append({"op": "remove", "id": int(p.id)})
		else:
			var data := PackedFloat32Array([(p.data as PackedFloat32Array)[0]])
			out.append({"op": "replace", "id": int(p.id), "data": data + PondOutline.floats(left)})
	return out


## The river primitive ids an erase of capsules `dabs` removes, in document order: each whose
## line (its derived record in `records`, else its own points) comes within its half-width of a
## capsule, and every river whose record's water ends in one removed (followed upstream). Pure.
static func erased_rivers(terra: TerraDoc, records: Array, dabs: PackedFloat32Array) -> Array[int]:
	var lines := {}
	var into := {}
	for r: Dictionary in records:
		lines[int(r.id)] = [r.pts, float(r.hw)]
		into[int(r.id)] = int(r.get("recv_river", -1))
	var gone := {}
	for p: Dictionary in terra.prims:
		if int(p.kind) != TerraCore.RIVER:
			continue
		var id := int(p.id)
		var data: PackedFloat32Array = p.data
		var line: Array = lines.get(id, [data.slice(2), data[0] * 0.5])
		if _touches(line[0], float(line[1]), dabs):
			gone[id] = true
	var grew := true
	while grew:
		grew = false
		for id: int in into:
			if not gone.has(id) and gone.has(into[id]):
				gone[id] = true
				grew = true
	var out: Array[int] = []
	for p: Dictionary in terra.prims:
		if gone.has(int(p.id)) and int(p.kind) == TerraCore.RIVER:
			out.append(int(p.id))
	return out


## The pond primitive whose outline holds map point `at`, or -1.
static func pond_at(terra: TerraDoc, at: Vector2) -> int:
	for p: Dictionary in terra.prims:
		if int(p.kind) == TerraCore.POND and not TerraDoc.is_muted(p):
			if Geometry2D.is_point_in_polygon(at, PondOutline.of_data(p.data)):
				return int(p.id)
	return -1


## True when the line `flat` (x, z pairs) of half-width `hw` meets a capsule of `dabs`.
static func _touches(flat: PackedFloat32Array, hw: float, dabs: PackedFloat32Array) -> bool:
	var dab := PondOutline.DAB
	for k in range(0, dabs.size() - dab + 1, dab):
		var a := Vector2(dabs[k], dabs[k + 1])
		var b := Vector2(dabs[k + 2], dabs[k + 3])
		var reach := dabs[k + 4] + hw
		for i in range(0, flat.size() - 3, 2):
			var p := Vector2(flat[i], flat[i + 1])
			var q := Vector2(flat[i + 2], flat[i + 3])
			var near := Geometry2D.get_closest_points_between_segments(p, q, a, b)
			if near[0].distance_to(near[1]) <= reach:
				return true
	return false
