extends GutTest

## What a water dressing refresh marks as edited (card painter-edit-hitch; docs/systems/painter.md
## "Zone maps"): WaterDressing.changed_rect bounds exactly the samples whose dressing bytes changed,
## AuthoredTerrain.refresh_water_dressing emits that rect (nothing when the dressing is unchanged,
## the whole grid when the layers re-table), and after each kind of edit the painted ground's zone
## maps and the water field, kept by rects, hold the bytes a whole rebuild gives: a new river, an
## erased river, a raise beside water, a raise far from water, the first water on a dry map, and a
## river along the map's edge.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const FIELD_ARRAYS := [
	"ground",
	"w",
	"ew",
	"depth",
	"energy",
	"steep",
	"shore",
	"lateral",
	"spill",
	"calm",
	"owner",
	"foot",
]
const BED := -1.0
const LEVEL := -0.2

var _map: Node3D = null
var _doc: MapDocument = null
var _editor: AuthoringEditor = null
var _surfaces: PainterSurfaces = null
var _field: PainterWaterField = null
var _edits: Array[Rect2i] = []


func after_each() -> void:
	if _field != null:
		_field.detach()
	if _surfaces != null:
		_surfaces.release()
	_field = null
	_surfaces = null
	_editor = null
	_edits.clear()


# ---------------------------------------------------------------- changed_rect, pure


func _field_bytes(columns: int, rows: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(columns * rows * WaterDressing.CHANNELS)
	return out


## `field` with the bytes of the samples in `rect` set to `value` in channel `channel`.
func _with(field: PackedByteArray, columns: int, rect: Rect2i, channel: int) -> PackedByteArray:
	var out := field.duplicate()
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out[(z * columns + x) * WaterDressing.CHANNELS + channel] = 200
	return out


func test_equal_fields_change_nothing_and_a_new_size_changes_all() -> void:
	var a := _field_bytes(30, 20)
	assert_eq(WaterDressing.changed_rect(a, a.duplicate(), 30, 20), Rect2i())
	assert_eq(WaterDressing.changed_rect(PackedByteArray(), PackedByteArray(), 30, 20), Rect2i())
	assert_eq(WaterDressing.changed_rect(PackedByteArray(), a, 30, 20), Rect2i(0, 0, 30, 20))
	assert_eq(WaterDressing.changed_rect(a, PackedByteArray(), 30, 20), Rect2i(0, 0, 30, 20))


func test_the_rect_bounds_every_changed_sample() -> void:
	var a := _field_bytes(40, 30)
	for case: Array in [
		[[Rect2i(5, 6, 3, 2)], 0, Rect2i(5, 6, 3, 2)],
		[[Rect2i(0, 0, 1, 1)], 3, Rect2i(0, 0, 1, 1)],
		[[Rect2i(39, 29, 1, 1)], 3, Rect2i(39, 29, 1, 1)],
		[[Rect2i(0, 12, 40, 1)], 1, Rect2i(0, 12, 40, 1)],
		# A diagonal: the left bound moves on every row, the right one too.
		[[Rect2i(30, 2, 2, 1), Rect2i(20, 9, 2, 1), Rect2i(3, 20, 2, 1)], 2, Rect2i(3, 2, 29, 19)],
		[[Rect2i(12, 4, 1, 1), Rect2i(37, 4, 1, 1), Rect2i(25, 27, 1, 3)], 1, Rect2i(12, 4, 26, 26)],
	]:
		var b := a
		for rect: Rect2i in case[0]:
			b = _with(b, 40, rect, int(case[1]))
		assert_eq(WaterDressing.changed_rect(a, b, 40, 30), case[2], str(case))


# ---------------------------------------------------------------- the editor and the painted look


## An editor over a flat 24 m map, painted, with the water field drawing it; with `water` a river
## already lies along z = 0 in a carved bed.
func _editor_on(water: bool) -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(24, 24), "grass_meadow", "v", 9)
	if water:
		var heights := _doc.heights.duplicate()
		for z in _doc.samples_z():
			for x in _doc.samples_x():
				var p := _doc.sample_to_world(Vector2(x, z))
				if absf(p.x) <= 9.0 and absf(p.y) <= 1.5:
					heights[_doc.sample_index(x, z)] = BED
		_doc.heights = heights
		var line := PackedVector2Array([Vector2(-9, 0), Vector2(9, 0)])
		_doc.water_bodies.append(
			WaterBody.river(1, line, PackedFloat32Array([1.5, 1.5]), WaterBody.Depth.WAIST, LEVEL)
		)
		WaterDressing.refresh(_doc)
	var terrain := AuthoredTerrain.create(_doc)
	_map.add_child(terrain)
	var scatter := AuthoredScatter.create()
	scatter.name = MapSourceLoader.SCATTER_NODE
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	if water:
		AuthoredWater.refresh_map(_map, _doc)
		_water().finish_refresh()
	_editor = AuthoringEditor.create(_doc, _map, AuthoringHistory.new())
	_editor.scatter.attach_document(_doc)
	_surfaces = PainterSurfaces.new()
	assert_true(_surfaces.paint(_map, STATE), "painted")
	_field = PainterWaterField.new()
	var material := ShaderMaterial.new()
	material.shader = load(PainterWater.SHADER) as Shader
	assert_true(_field.attach(_map, material))
	await _settle()
	terrain.ground_edited.connect(func(rect: Rect2i) -> void: _edits.append(rect))


func _water() -> AuthoredWater:
	return _map.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater


## Lands every part of the edit, then the painted look's own follow-ups (the zone maps' deferred
## rebuild, the water field's flush on the next frame).
func _settle() -> void:
	if _editor != null:
		_editor.finish_height_work()
	if _water() != null:
		_water().finish_refresh()
	for i in 3:
		await get_tree().process_frame
	# A whole zone build after an edit runs on a worker (card painter-edit-hitch4) and may not have
	# landed in three frames on a slow machine: land it, and the edits that waited for it, now
	# (bounded: a landing's follow-up may start one more).
	# A water field flush over PainterWaterField.ASYNC_SAMPLES runs on a worker too (card
	# painter-river-landing): landed here, it must equal the synchronous update.
	for k in 4:
		var landed := _field != null and _field.finish_update()
		var zoned := _surfaces != null and _surfaces.finish_zones()
		if not (landed or zoned):
			break


func _grid() -> Rect2i:
	return Rect2i(0, 0, _doc.samples_x(), _doc.samples_z())


## The kept zone maps and water field against a whole rebuild of the document as it is now.
func _check(label: String) -> void:
	var zones := _surfaces.zones()
	var char_map := PainterZoneMaps.char_image(_doc)
	var biome := PainterZoneMaps.biome_zone_image(_doc)
	assert_eq(zones.zone.get_data(), PainterZoneMaps.zone_image(_doc).get_data(), "%s: zone" % label)
	assert_eq(zones.char_map == null, char_map == null, "%s: char map" % label)
	assert_eq(zones.biome == null, biome == null, "%s: biome zone map" % label)
	var whole := WaterField.build(_doc)
	var kept := _field.field
	var differ := PackedStringArray()
	for name: String in FIELD_ARRAYS:
		if kept.get(name) != whole.get(name):
			differ.append("%s (%d samples)" % [name, _count_differing(kept.get(name), whole.get(name))])
	if kept.events != whole.events:
		differ.append("events")
	assert_eq(differ, PackedStringArray(), "%s: the water field equals a whole build" % label)


static func _count_differing(a: Variant, b: Variant) -> int:
	if typeof(a) != typeof(b) or a.size() != b.size():
		return -1
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n


func _raise(at: Vector3) -> void:
	assert_true(_editor.begin_height_stroke(HeightBrush.RAISE))
	_editor.stroke_dab(at, at + Vector3(1, 0, 0), 1.5, 1.0)
	_editor.flush()
	assert_true(_editor.end_stroke())
	await _settle()


func test_a_new_river_marks_its_dressing_and_keeps_the_maps_whole_equal() -> void:
	await _editor_on(true)
	var before := _doc.water_dressing
	var carved := _editor.water.carve_river(
		PackedVector2Array([Vector2(-6, -8), Vector2(6, -8)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	assert_gt(carved, 0, "carved")
	await _settle()
	assert_false(_grid() in _edits, "no whole-grid edit: %s" % [_edits])
	var grid := _grid()
	var changed := WaterDressing.changed_rect(before, _doc.water_dressing, grid.size.x, grid.size.y)
	assert_true(changed.has_area(), "the dressing changed")
	assert_true(changed in _edits, "the refresh marked the changed rect %s" % changed)
	_check("new river")


func test_an_erased_river_keeps_the_maps_whole_equal() -> void:
	await _editor_on(true)
	_editor.water.carve_river(
		PackedVector2Array([Vector2(-6, -8), Vector2(6, -8)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	await _settle()
	_edits.clear()
	assert_true(_editor.water.erase_water_begin())
	_editor.water.erase_water_dab(Vector3(-7, 0, -8), Vector3(7, 0, -8), 2.0)
	assert_true(_editor.water.erase_water_end())
	await _settle()
	assert_false(_grid() in _edits, "no whole-grid edit")
	_check("erased river")


func test_a_raise_beside_water_keeps_the_maps_whole_equal() -> void:
	await _editor_on(true)
	await _raise(Vector3(-2, 0, 2.5))
	assert_false(_grid() in _edits, "no whole-grid edit")
	_check("raise beside water")


func test_a_raise_far_from_water_marks_no_dressing() -> void:
	await _editor_on(true)
	var before := _doc.water_dressing
	await _raise(Vector3(-6, 0, 9))
	assert_eq(
		WaterDressing.changed_rect(before, _doc.water_dressing, _grid().size.x, _grid().size.y),
		Rect2i(),
		"the dressing did not change"
	)
	assert_false(_grid() in _edits, "no whole-grid edit")
	_check("raise far from water")


func test_the_first_water_re_tables_and_marks_the_whole_grid() -> void:
	await _editor_on(false)
	assert_true(_doc.water_dressing.is_empty(), "a dry map")
	_editor.water.carve_river(
		PackedVector2Array([Vector2(-6, 3), Vector2(6, 3)]),
		PackedFloat32Array([1.0]),
		WaterBody.Depth.WAIST
	)
	await _settle()
	assert_false(_doc.water_dressing.is_empty(), "water now")
	assert_true(_grid() in _edits, "the re-table marked the whole grid")
	_check("first water")


func test_a_dressing_change_at_the_map_edge_marks_it_there() -> void:
	await _editor_on(true)
	var columns := _grid().size.x
	var rows := _grid().size.y
	# The corner samples and a strip along the right edge get a wet shore.
	var rect := Rect2i(columns - 3, rows - 6, 3, 6)
	var wet := _with(_doc.water_dressing, columns, rect, 1)
	wet = _with(wet, columns, Rect2i(0, 0, 2, 1), 1)
	_doc.water_dressing = wet
	_editor.terrain.refresh_water_dressing()
	await _settle()
	assert_eq(_edits, [Rect2i(0, 0, columns, rows)] as Array[Rect2i], "both corners: the grid")
	_edits.clear()
	_doc.water_dressing = _with(_doc.water_dressing, columns, Rect2i(columns - 1, 4, 1, 3), 0)
	_editor.terrain.refresh_water_dressing()
	await _settle()
	assert_eq(_edits, [Rect2i(columns - 1, 4, 1, 3)] as Array[Rect2i], "the edge strip alone")
	assert_eq(_surfaces.zones().last_rect, Rect2i(columns - 2, 3, 2, 5), "grown inside the grid")
	_check("edge")
	_edits.clear()
	_editor.terrain.refresh_water_dressing()
	await _settle()
	assert_eq(_edits, [] as Array[Rect2i], "an unchanged dressing marks nothing")
