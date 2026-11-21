extends GutTest

## The native passes of the water field (WaterFieldNative, native/src/water_field.cpp; card
## painter-water-latency) against the GDScript they port, bit for bit, on the canonical map
## (tests/fixtures/water_field_canonical.ttmap): a full build, a native update of several kinds of
## edit against a GDScript full build, and RiverProfile.field's raster with and without a clip.
## Pending without the library; its absence is the GDScript path test_water_field checks.

const FIXTURE := "res://tests/fixtures/water_field_canonical.ttmap"
const Corpus := preload("res://tests/unit/water_corpus_cases.gd")
const _ARRAYS := [
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
	"flow_u",
	"foot",
]


func after_each() -> void:
	ScatterNative.force_gdscript_wfield = false


func _skip_without_library() -> bool:
	if ScatterNative.wfield_instance() != null:
		return false
	pending("the native library is not built (AGENTS.md Testing): GDScript path only")
	return true


func _read() -> MapDocument:
	return MapDocumentIO.read(FIXTURE).get("document")


func _build_gdscript(doc: MapDocument) -> WaterField:
	ScatterNative.force_gdscript_wfield = true
	var f := WaterField.build(doc)
	ScatterNative.force_gdscript_wfield = false
	return f


## The name of the first array (or "events") in which two fields differ, "" when they match.
func _difference(a: WaterField, b: WaterField) -> String:
	for name: String in _ARRAYS:
		if a.get(name) != b.get(name):
			return name
	if a.events != b.events:
		return "events"
	return ""


func test_the_native_build_equals_the_gdscript_build() -> void:
	if _skip_without_library():
		return
	var doc := _read()
	var native := WaterField.build(doc)
	assert_eq(_difference(native, _build_gdscript(doc)), "", "native build equals the GDScript build")
	WaterField.exact_shore = false
	var stage_two_native := WaterField.build(doc)
	var stage_two_gd := _build_gdscript(doc)
	WaterField.exact_shore = true
	assert_eq(_difference(stage_two_native, stage_two_gd), "", "the same with the exact shore off")


func test_a_native_update_equals_a_gdscript_full_build_after_edits() -> void:
	if _skip_without_library():
		return
	var step := _read().sample_step()
	for centre: Vector2 in [Vector2(9.0, -9.0), Vector2(23.0, -14.0), Vector2(-21.0, 12.0)]:
		var doc := _read()
		var field := WaterField.build(doc)
		var origin := -doc.extent_m() * 0.5
		var low := Vector2i(((centre - Vector2(2.5, 2.5) - origin) / step).floor())
		var high := Vector2i(((centre + Vector2(2.5, 2.5) - origin) / step).ceil())
		for z in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				var d := (origin + Vector2(x, z) * step).distance_to(centre)
				if d < 2.5:
					doc.heights[z * doc.samples_x() + x] += 0.5 * (1.0 - d / 2.5)
		var rect := Rect2i(low, high - low + Vector2i.ONE).grow(int(WaterField.INFLUENCE_M / step.x))
		field.update(doc, rect)
		assert_eq(
			_difference(field, _build_gdscript(doc)), "", "ground edit at %s: native update" % centre
		)
	var doc := _read()
	var field := WaterField.build(doc)
	var before: Array[WaterBody] = [doc.water_bodies[2], doc.water_bodies[28]]
	var rect := WaterField.rect_of_bodies(doc, before)
	doc.water_bodies[2].level_m += 0.4
	doc.water_bodies[28].level_m -= 0.3
	field.update(doc, rect.merge(WaterField.rect_of_bodies(doc, before)))
	assert_eq(_difference(field, _build_gdscript(doc)), "", "level changes: native update")


func test_the_native_mesh_and_textures_equal_the_gdscript_ones() -> void:
	if _skip_without_library():
		return
	var doc := _read()
	var field := WaterField.build(doc)
	var native := WaterFieldMesh.build(field)
	var native_tex := WaterFieldNative.pack_textures(field, -0.3)
	ScatterNative.force_gdscript_wfield = true
	var gd := WaterFieldMesh.build(field)
	var gd_tex := WaterFieldNative.pack_textures(field, -0.3)
	ScatterNative.force_gdscript_wfield = false
	assert_gt(native.vertices, 3000, "the canonical map has a mesh")
	assert_eq(native.vertices, gd.vertices, "vertex count")
	assert_eq(native.triangles, gd.triangles, "triangle count")
	assert_eq(native.aabb, gd.aabb, "bounds")
	var names := ["vertices", "normals", "uvs", "custom0", "custom1", "custom2", "indices"]
	var slots := [
		Mesh.ARRAY_VERTEX,
		Mesh.ARRAY_NORMAL,
		Mesh.ARRAY_TEX_UV,
		Mesh.ARRAY_CUSTOM0,
		Mesh.ARRAY_CUSTOM1,
		Mesh.ARRAY_CUSTOM2,
		Mesh.ARRAY_INDEX,
	]
	for k in slots.size():
		assert_eq(native.arrays[slots[k]], gd.arrays[slots[k]], "mesh %s" % names[k])
	assert_eq(native_tex.a, gd_tex.a, "texture a")
	assert_eq(native_tex.b, gd_tex.b, "texture b")


func test_the_native_raster_equals_the_gdscript_raster() -> void:
	if _skip_without_library():
		return
	var doc := _read()
	var clips := [
		Rect2i(),
		Rect2i(Vector2i(70, 40), Vector2i(60, 50)),
		Rect2i(Vector2i(0, 0), Vector2i(20, 245)),
	]
	var checked := 0
	for chain in RiverProfile.strokes(doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var profile := RiverProfile.for_doc(doc, typed)
		for clip: Rect2i in clips:
			var native := profile.field(doc, WaterGeometry.RIVER_BANK_M, clip)
			ScatterNative.force_gdscript_wfield = true
			var gd := profile.field(doc, WaterGeometry.RIVER_BANK_M, clip)
			ScatterNative.force_gdscript_wfield = false
			assert_eq(native.rect, gd.rect, "raster rect")
			for key: String in ["distance", "along", "half_width"]:
				assert_eq(native[key], gd[key], "raster %s of stroke %d clip %s" % [key, typed[0].id, clip])
			checked += 1
	assert_gt(checked, 20, "every stroke checked with every clip")


func test_the_native_seam_pass_equals_the_gdscript_and_the_rule() -> void:
	# Card painter-water-editcost: a grid of coordinates of both signs and jumps of every size
	# inside three overlapping areas (none outside, as the strokes write them), over the whole grid
	# and over dirty rects at the grid's edges and inside it.
	if _skip_without_library():
		return
	var size := Vector2i(41, 33)
	var areas: Array[Rect2i] = [Rect2i(2, 1, 20, 18), Rect2i(14, 10, 25, 22), Rect2i(30, 0, 11, 6)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 118
	var raw := PackedFloat32Array()
	for z in size.y:
		for x in size.x:
			var inside := false
			for a in areas:
				inside = inside or a.has_point(Vector2i(x, z))
			var has_foot := inside and rng.randf() < 0.8
			raw.append(rng.randf_range(-8.0, 8.0) if has_foot else WaterFieldStroke.NO_FOOT)
	var rule := Corpus.seam_rule(raw, size)
	assert_ne(rule, raw, "the grid holds seams")
	var f := WaterField.new()
	f.size = size
	f._foot_raw = raw
	f._foot_rects = areas
	var all := Rect2i(Vector2i.ZERO, size)
	for region: Rect2i in [all, Rect2i(0, 0, 9, 7), Rect2i(12, 8, 17, 13), Rect2i(30, 25, 11, 8)]:
		var before := raw.duplicate()
		before.fill(3.0)
		f.foot = before.duplicate()
		var native := WaterFieldNative.foot_seams(f, region)
		assert_eq(f.foot, before, "the field's own array is not written")
		var gd := WaterFieldStroke.foot_seams(raw, before.duplicate(), size, region, areas)
		assert_eq(native, gd, "native equals GDScript over %s" % region)
		var differ := 0
		for z in size.y:
			for x in size.x:
				var i := z * size.x + x
				var want := rule[i] if region.has_point(Vector2i(x, z)) else 3.0
				differ += 1 if native[i] != want else 0
		assert_eq(differ, 0, "the rule's samples over %s, the rest kept" % region)
	WaterFieldStroke.foot_seams_cleared = false
	var kept := WaterFieldNative.foot_seams(f, all)
	WaterFieldStroke.foot_seams_cleared = true
	assert_eq(kept, raw, "the switch off keeps the coordinate as written")
