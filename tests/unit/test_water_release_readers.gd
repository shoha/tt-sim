extends GutTest

## The river release's readers (card painter-release-frame): WaterGeometry.level_reader,
## wet_reader, ground_reader and water_ground_reader answer as level_at, is_wet_at, ground_at and
## WaterEdit.water_ground_at do, bit for bit, so join_line, the brush's through_rises and the fall
## profile land the same bytes as when they asked every river's whole course per point. The input
## is the bench's second river at its release (dumped from the windowed bench, 320 ft hilltop, seed
## 1234): the map with the first river and five others on it, and the drawn line in map metres, a
## bent 90 m stroke that crosses the first river.

const MAP := "res://tests/fixtures/release_frame_bent_river.ttmap"
## [world line, map line, ray slants, map scale] (store_var).
const LINE := "res://tests/fixtures/release_frame_bent_river.bin"

var _doc: MapDocument
var _line: PackedVector2Array


func before_all() -> void:
	_doc = MapDocumentIO.read(MAP).document
	var f := FileAccess.open(LINE, FileAccess.READ)
	var data: Array = f.get_var()
	_line = data[1]


func test_the_fixture_is_the_bent_river_over_other_water() -> void:
	assert_not_null(_doc, "the map reads")
	assert_eq(_line.size(), 302, "the drawn line")
	var rivers := 0
	for body in _doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	assert_eq(rivers, 6, "six rivers on the map")
	var wet := 0
	for p in _line:
		wet += 1 if WaterGeometry.is_wet_at(_doc, p) else 0
	assert_gt(wet, 0, "the line crosses water")
	assert_lt(wet, _line.size(), "and runs over dry ground")


## Over a grid across the whole map and a band around the line (tile corners included), every
## reader gives its original's value, with and without an excluded body and over cut courses.
func test_each_reader_answers_as_its_original() -> void:
	var points := _probe_points()
	var cut := WaterGeometry.river_courses(_doc, WaterGeometry.bounds(_line, 0.01))
	var excluded := _doc.water_bodies[0].id
	var level_of := WaterGeometry.level_reader(_doc)
	var level_ex := WaterGeometry.level_reader(_doc, excluded)
	var level_cut := WaterGeometry.level_reader(_doc, -1, cut)
	var wet_of := WaterGeometry.wet_reader(_doc)
	var ground_of := WaterGeometry.ground_reader(_doc)
	var water_of := WaterGeometry.water_ground_reader(_doc)
	var water_cut := WaterGeometry.water_ground_reader(_doc, cut)
	var differ := {}
	var wet := 0
	for p in points:
		_count(differ, "level", WaterGeometry.level_at(_doc, p) == level_of.call(p))
		_count(differ, "excluded", WaterGeometry.level_at(_doc, p, excluded) == level_ex.call(p))
		_count(differ, "cut", WaterGeometry.level_at(_doc, p, -1, cut) == level_cut.call(p))
		var is_wet := WaterGeometry.is_wet_at(_doc, p)
		wet += 1 if is_wet else 0
		_count(differ, "wet", is_wet == wet_of.call(p))
		_count(differ, "ground", WaterGeometry.ground_at(_doc, p) == ground_of.call(p))
		_count(differ, "water", WaterEdit.water_ground_at(_doc, p) == water_of.call(p))
		_count(differ, "water cut", WaterEdit.water_ground_at(_doc, p, cut) == water_cut.call(p))
	assert_eq(differ, {}, "no reader differs from its original over %d points" % points.size())
	assert_gt(wet, 500, "many of them in water")


## join_line over the line as drawn (it crosses the first river: nothing trimmed) and over the line
## from its first point in water on (an outflow: the head moves to the water's edge by bisection)
## gives the bytes the per-point original gave.
func test_join_line_lands_the_old_bytes() -> void:
	var widths := PackedFloat32Array([0.9])
	var whole := WaterEdit.join_line(_doc, _line, widths)
	assert_eq(var_to_bytes(whole), var_to_bytes(_old_join_line(_doc, _line, widths)), "as drawn")
	var first_wet := -1
	for i in _line.size():
		if WaterGeometry.is_wet_at(_doc, _line[i]):
			first_wet = i
			break
	assert_gt(first_wet, 0, "the line reaches water")
	var from_water := _line.slice(first_wet)
	var joined := WaterEdit.join_line(_doc, from_water, widths)
	var old := _old_join_line(_doc, from_water, widths)
	assert_eq(var_to_bytes(joined), var_to_bytes(old), "from inside the water")
	assert_ne((joined[0] as PackedVector2Array)[0], from_water[0], "the head moved to the edge")


## The brush's through_rises with the reader, and the fall profile over the plan's cut courses,
## give the bytes the per-point originals gave; the line has rises, so points move.
func test_through_rises_and_the_fall_profile_land_the_old_bytes() -> void:
	var slant := func(_p: Vector3) -> Vector2: return Vector2(0.3, -0.7)
	var old_of := func(p: Vector2) -> float: return WaterEdit.water_ground_at(_doc, p)
	var old := WaterBrush.through_rises(_line, old_of, slant)
	var now := WaterBrush.through_rises(_line, WaterGeometry.water_ground_reader(_doc), slant)
	assert_eq(var_to_bytes(now), var_to_bytes(old), "through_rises")
	assert_ne(old, _line, "the line has rises to move past")
	var cut := WaterGeometry.river_courses(_doc, WaterGeometry.bounds(_line, 0.01))
	var step := minf(_doc.sample_step().x, _doc.sample_step().y)
	var old_cut := func(p: Vector2) -> float: return WaterEdit.water_ground_at(_doc, p, cut)
	var before := WaterFallPlan.fine_profile(_line, step, old_cut)
	var after := WaterFallPlan.fine_profile(
		_line, step, WaterGeometry.water_ground_reader(_doc, cut)
	)
	assert_eq(var_to_bytes(after), var_to_bytes(before), "fine_profile")


## A whole plan of the line (WaterEdit.plan_river, the release's) is deterministic through the
## readers: two plans give the same bodies.
func test_a_plan_of_the_line_is_the_same_twice() -> void:
	var widths := PackedFloat32Array([0.9])
	var a := WaterEdit.plan_river(_doc, _line, widths, WaterBody.Depth.WAIST, 12.0)
	var b := WaterEdit.plan_river(_doc, _line, widths, WaterBody.Depth.WAIST, 12.0)
	assert_gt(a.size(), 0, "the line plans")
	assert_eq(_bodies_bytes(a), _bodies_bytes(b))


func _bodies_bytes(bodies: Array[WaterBody]) -> PackedByteArray:
	var out := PackedByteArray()
	for body in bodies:
		out.append_array(var_to_bytes([body.id, body.points, body.half_widths, body.level_m]))
	return out


func _count(differ: Dictionary, name: String, same: bool) -> void:
	if not same:
		differ[name] = int(differ.get(name, 0)) + 1


func _probe_points() -> PackedVector2Array:
	var half := _doc.extent_m() * 0.5
	var out := PackedVector2Array()
	for j in 90:
		for i in 90:
			out.append(Vector2(-half.x + (i + 0.37) * half.x / 45.0, -half.y + (j + 0.61) * half.y / 45.0))
	for p in _line:
		for k in 9:
			out.append(p + Vector2(cos(k * 0.7), sin(k * 0.7)) * (0.5 + k * 0.9))
		var tile := WaterGeometry.READER_TILE_M
		out.append((p / tile).round() * tile)
	return out


## WaterEdit.join_line as it was before card painter-release-frame: is_wet_at per point and per
## bisection step.
func _old_join_line(
	doc: MapDocument, points: PackedVector2Array, half_widths: PackedFloat32Array
) -> Array:
	var widths := half_widths
	if widths.size() != points.size():
		widths = PackedFloat32Array()
		widths.resize(points.size())
		widths.fill(half_widths[0])
	var falls := WaterFalls.falls(doc)
	var wet := PackedByteArray()
	wet.resize(points.size())
	var dry_first := -1
	var dry_last := -1
	for i in points.size():
		if WaterGeometry.is_wet_at(doc, points[i]) and WaterEdit._face_of(doc, falls, points[i]) < 0:
			wet[i] = 1
		elif dry_first < 0:
			dry_first = i
		if wet[i] == 0:
			dry_last = i
	if dry_first < 0:
		return [PackedVector2Array(), PackedFloat32Array()]
	var first := maxi(dry_first - 1, 0)
	var last := mini(dry_last + 1, points.size() - 1)
	var line := points.slice(first, last + 1)
	if wet[first] == 1:
		line[0] = _old_junction(doc, points[first], points[first + 1])
	else:
		line[0] = WaterEdit._face_junction(doc, falls, points[first])
	if last > first:
		if wet[last] == 1:
			line[-1] = _old_junction(doc, points[last], points[last - 1])
		else:
			line[-1] = WaterEdit._face_junction(doc, falls, points[last])
	return [line, widths.slice(first, last + 1)]


func _old_junction(doc: MapDocument, wet: Vector2, dry: Vector2) -> Vector2:
	var inside := wet
	var outside := dry
	for _step in 12:
		var middle := (inside + outside) * 0.5
		if WaterGeometry.is_wet_at(doc, middle):
			inside = middle
		else:
			outside = middle
	var inward := wet - inside
	if inward.length() <= WaterEdit.JOIN_INSET_M:
		return wet
	return inside + inward.normalized() * WaterEdit.JOIN_INSET_M
