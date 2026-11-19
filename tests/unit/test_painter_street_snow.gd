extends GutTest

## The wall layers' roof blankets (PainterStreetSnow, card painter-roof-round3; docs/systems/
## painter.md "Roof round 3"): a roof part's up faces read back into slopes with the edges of a
## manner roof record (a gable's eave, two verges and a ridge; a hip roof's hips and apex), so
## PainterMannerSnow lays the hand-drawn houses' blanket on a street lot's roof; a winter mood lays
## them on a painted wall layer and a mood with no roof snow takes them away. Also the fixed-kind
## roof's grey test by saturation (the trullo's cone, painter_structure_common.gdshaderinc).

const RED := Color(0.5, 0.12, 0.08)


## Mesh arrays of `faces` (each three or four corners, wound as one face, normal up) plus a
## downward underside the reader must skip.
func _mesh(faces: Array) -> Array:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for face: Array in faces:
		var base := verts.size()
		var p0: Vector3 = face[0]
		var n := ((face[1] as Vector3) - p0).cross((face[2] as Vector3) - p0).normalized()
		if n.y < 0.0:
			n = -n
		for p: Vector3 in face:
			verts.append(p)
			normals.append(n)
			cols.append(RED)
		for k in range(1, face.size() - 1):
			idx.append_array(PackedInt32Array([base, base + k, base + k + 1]))
	# An underside (normal down).
	var under := verts.size()
	for p: Vector3 in [Vector3(-3, 2.9, -2), Vector3(3, 2.9, -2), Vector3(3, 2.9, 2)]:
		verts.append(p)
		normals.append(Vector3.DOWN)
		cols.append(RED)
	idx.append_array(PackedInt32Array([under, under + 1, under + 2]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	return arrays


func _gable() -> Array:
	return _mesh(
		[
			[Vector3(-3, 3, -2), Vector3(3, 3, -2), Vector3(3, 4.5, 0), Vector3(-3, 4.5, 0)],
			[Vector3(-3, 3, 2), Vector3(3, 3, 2), Vector3(3, 4.5, 0), Vector3(-3, 4.5, 0)],
		]
	)


## A gable with a flat ridge band `band` metres wide between its two slopes (a street lot's ridge
## board).
func _banded_gable(band: float) -> Array:
	var h := band * 0.5
	return _mesh(
		[
			[Vector3(-3, 3, -2), Vector3(3, 3, -2), Vector3(3, 4.5, -h), Vector3(-3, 4.5, -h)],
			[Vector3(-3, 3, 2), Vector3(3, 3, 2), Vector3(3, 4.5, h), Vector3(-3, 4.5, h)],
			[Vector3(-3, 4.5, -h), Vector3(3, 4.5, -h), Vector3(3, 4.5, h), Vector3(-3, 4.5, h)],
		]
	)


func test_a_ridge_band_closes_between_the_two_crests() -> void:
	# Card painter-roof-round4: each blanket crested over its own ridge line, and the 6 to 10 cm
	# ridge board between them showed as a brown slit along the ridge, under the chimneys.
	var recs := PainterStreetSnow.records_of(_banded_gable(0.08), 1, "p")
	var ridges: Array = []
	for rec: Dictionary in recs:
		for e: Dictionary in rec["edges"]:
			if str(e["kind"]) == "ridge":
				ridges.append(e)
	assert_eq(recs.size(), 2, "the two slopes (the band is too narrow for snow of its own)")
	assert_eq(ridges.size(), 2, "a ridge on each slope")
	if ridges.size() == 2:
		var a := ((ridges[0]["a"] as Vector3) + (ridges[0]["b"] as Vector3)) * 0.5
		var b := ((ridges[1]["a"] as Vector3) + (ridges[1]["b"] as Vector3)) * 0.5
		assert_almost_eq(a.z, 0.0, 0.005, "the first ridge carried to the band's middle")
		assert_almost_eq(b.z, 0.0, 0.005, "the second too")
		assert_almost_eq(a.y, b.y, 0.01, "at one height")
	for rec: Dictionary in recs:
		assert_false(PainterMannerBlanket.layout(rec).is_empty(), "still a blanket's frame")
	var wide := PainterStreetSnow.records_of(_banded_gable(0.6), 1, "p")
	for rec: Dictionary in wide:
		for e: Dictionary in rec["edges"]:
			if str(e["kind"]) == "ridge":
				var m := ((e["a"] as Vector3) + (e["b"] as Vector3)) * 0.5
				assert_almost_eq(absf(m.z), 0.3, 0.005, "a wide flat top is not a ridge band")


func _kinds(rec: Dictionary) -> Array:
	var out: Array = []
	for e: Dictionary in rec["edges"]:
		out.append(str(e["kind"]))
	out.sort()
	return out


func test_a_gable_roof_reads_as_two_blanket_slopes() -> void:
	var recs := PainterStreetSnow.records_of(_gable(), 1, "t")
	assert_eq(recs.size(), 2, "two slopes; the underside is no slope")
	for rec: Dictionary in recs:
		assert_eq(_kinds(rec), ["eave", "ridge", "verge", "verge"])
		assert_false(PainterMannerBlanket.layout(rec).is_empty(), "the blanket reads it")
		assert_almost_eq(float(rec["v_len"]), 2.5, 0.01, "up the slope")
		assert_almost_eq(float(rec["u_len"]), 6.0, 0.01, "along the eave")
		var tone: Color = rec["tone"]
		assert_almost_eq(tone.a, 1.0 / PainterMannerSnow.KIND_SCALE, 0.001, "a tile roof's kind")
		assert_almost_eq(tone.r, RED.r, 0.001, "the roof's paint")
	var built := PainterMannerSnow.build({"roofs": recs, "pads": [], "opts": {}})
	assert_gt(int(built.by_kind.blanket), 0, "a blanket on both slopes")
	assert_eq(int(built.by_kind.lip), 0, "no strips where the blanket lies")


func test_neighbouring_lots_slopes_join_at_their_seam() -> void:
	# Two lots' front slopes side by side, 0.1 m apart (a party wall), and a third 1 m off.
	var recs := PainterStreetSnow.records_of(
		_mesh(
			[
				[Vector3(-3, 3, -2), Vector3(0, 3, -2), Vector3(0, 4.5, 0), Vector3(-3, 4.5, 0)],
				[Vector3(0.1, 3, -2), Vector3(3, 3, -2), Vector3(3, 4.5, 0), Vector3(0.1, 4.5, 0)],
				[Vector3(4, 3, -2), Vector3(7, 3, -2), Vector3(7, 4.5, 0), Vector3(4, 4.5, 0)],
			]
		),
		1,
		"t"
	)
	assert_eq(recs.size(), 3, "three slopes")
	var kinds: Array = []
	for rec: Dictionary in recs:
		kinds.append(_kinds(rec))
	assert_has(kinds, ["eave", "hip", "ridge", "verge"], "the first lot: its seam side a hip")
	assert_has(kinds, ["eave", "ridge", "verge", "verge"], "the lot 1 m off keeps its verges")
	var hips := 0
	for k: Array in kinds:
		hips += k.count("hip")
	assert_eq(hips, 2, "one seam, a hip on each side of it")


func test_a_hip_roof_reads_its_hips_and_apex() -> void:
	var arrays := _mesh(
		[
			[Vector3(-3, 3, -2), Vector3(3, 3, -2), Vector3(1, 4.5, 0), Vector3(-1, 4.5, 0)],
			[Vector3(-3, 3, 2), Vector3(3, 3, 2), Vector3(1, 4.5, 0), Vector3(-1, 4.5, 0)],
			[Vector3(-3, 3, -2), Vector3(-3, 3, 2), Vector3(-1, 4.5, 0)],
			[Vector3(3, 3, -2), Vector3(3, 3, 2), Vector3(1, 4.5, 0)],
		]
	)
	var recs := PainterStreetSnow.records_of(arrays, 5, "t")
	assert_eq(recs.size(), 4)
	var shapes := {}
	for rec: Dictionary in recs:
		var kinds := _kinds(rec)
		shapes[str(kinds)] = int(shapes.get(str(kinds), 0)) + 1
		var lay := PainterMannerBlanket.layout(rec)
		assert_false(lay.is_empty(), "the blanket reads %s" % str(kinds))
		if kinds.size() == 3:
			assert_eq(str(lay["top"]), "apex")
		assert_eq(str(rec["material"]), "shingle")
	assert_eq(shapes.get(str(["eave", "hip", "hip", "ridge"]), 0), 2, "the long sides")
	assert_eq(shapes.get(str(["eave", "hip", "hip"]), 0), 2, "the hip ends")


func test_a_narrow_flat_board_gets_no_snow_of_its_own() -> void:
	var board := _mesh(
		[[Vector3(-3, 4.5, -0.1), Vector3(3, 4.5, -0.1), Vector3(3, 4.5, 0.1), Vector3(-3, 4.5, 0.1)]]
	)
	assert_eq(PainterStreetSnow.records_of(board, 1, "t").size(), 0, "a ridge board")
	var flat := _mesh([[Vector3(-3, 4, -2), Vector3(3, 4, -2), Vector3(3, 4, 2), Vector3(-3, 4, 2)]])
	var recs := PainterStreetSnow.records_of(flat, 4, "t")
	assert_eq(recs.size(), 1, "a flat roof")
	assert_eq(_kinds(recs[0]), ["eave", "eave", "eave", "eave"], "a lip all round")


func test_a_winter_wall_layer_wears_blankets() -> void:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	var layer := Node3D.new()
	layer.name = PainterBuildings.WALL_LAYERS[0]
	map.add_child(layer)
	var wall := Node3D.new()
	wall.name = "Wall_1"
	layer.add_child(wall)
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _gable())
	roof.mesh = mesh
	wall.add_child(roof)
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(map, {"sheet": "core", "mood": "winter", "elevation": 20.0}))
	await wait_until(func() -> bool: return not buildings.street_snow.busy(), 10.0)
	await wait_process_frames(2)
	var laid := buildings.street_snow.laid()
	assert_eq(laid.size(), 1, "a blanket on the roof part")
	if laid.size() == 1:
		assert_eq(laid[0].get_parent(), roof, "in its roof's frame")
		assert_eq(laid[0].cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		assert_eq(laid[0].material_override, buildings.manner.snow_material(), "the manner's snow")
	buildings.paint(map, {"sheet": "core", "mood": "summer", "elevation": 40.0})
	assert_eq(buildings.street_snow.laid().size(), 0, "no blanket without roof snow")
	buildings.release()


func test_a_fixed_kind_roof_is_grey_by_saturation() -> void:
	# The trullo's warm grey cone (two of its faces' paints, LINEAR): its faces differ in value
	# only, so their saturation is one and they all fall on one side (some drew brown, some
	# blue-grey under a chroma threshold of 0.015). Every street lot's fixed-kind paint has 0.034.
	var common := FileAccess.get_file_as_string(
		"res://painter/shaders/painter_structure_common.gdshaderinc"
	)
	assert_string_contains(common, "c < PAINT_GREY_KIND * max(lab.x, 0.05)")
	var needle := "const float PAINT_GREY_KIND = "
	var at := common.find(needle)
	assert_gt(at, -1)
	var limit := common.substr(at + needle.length(), 8).split(";")[0].to_float()
	assert_between(limit, 0.024, 0.033)
	for c: Vector3 in [Vector3(0.267, 0.251, 0.216), Vector3(0.188, 0.173, 0.149)]:
		var lab := _lab(c)
		assert_lt(Vector2(lab.y, lab.z).length() / lab.x, limit, "the trullo's paint is grey")


func _lab(c: Vector3) -> Vector3:
	var l := pow(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z, 1.0 / 3.0)
	var m := pow(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z, 1.0 / 3.0)
	var s := pow(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z, 1.0 / 3.0)
	return Vector3(
		0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
		1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
		0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	)
