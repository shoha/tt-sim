extends GutTest

## MapFingerprint: the built-map summary the authored-map parity scenario compares between
## two peers (tests/net/steam_authored_parity.gd). Synthetic map roots stand in for a loaded
## map: the node names are the ones MapSourceLoader's builders give.


## Stands in for AuthoredScatter: anything answering rows_by_asset().
class FakeScatter:
	extends Node3D
	var rows: Dictionary = {}

	func rows_by_asset() -> Dictionary:
		return rows


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "test", 7)
	var body := WaterBody.new()
	body.id = 3
	body.kind = WaterBody.Kind.POND
	body.depth = WaterBody.Depth.DEEP
	body.level_m = -0.15
	doc.water_bodies = [body]
	return doc


## A triangle-list mesh of `vertices` with per-vertex `colors` and `uv2s`.
func _mesh(
	vertices: PackedVector3Array, colors: PackedColorArray, uv2s: PackedVector2Array
) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _plain_mesh(count: int, offset: Vector3 = Vector3.ZERO) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for i in count:
		vertices.append(offset + Vector3(i, i * 0.5, 0))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _instance(node_name: String, mesh: Mesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	return instance


## A map root with two falls (3 and 6 curtain vertices) plus ring vertices, an arch moved
## to x = 10, a plank bridge, a skirt ribbon and a scatter node.
func _root() -> Node3D:
	var root := Node3D.new()
	root.name = "LevelMap"
	var water := Node3D.new()
	water.name = MapFingerprint.WATER_NODE
	root.add_child(water)
	var vertices := PackedVector3Array()
	var colors := PackedColorArray()
	var uv2s := PackedVector2Array()
	for i in 3:
		vertices.append(Vector3(0, 2 - i, 0))
		colors.append(Color(1, 0, 0))
		uv2s.append(Vector2(1.5, 1.37))
	for i in 6:
		vertices.append(Vector3(5, 1 - i * 0.2, 1))
		colors.append(Color(1, 0, 0))
		uv2s.append(Vector2(1.5, -0.15))
	for i in 3:
		vertices.append(Vector3(9, 0, 9))
		colors.append(Color(1, 0.5, 0))
		uv2s.append(Vector2(2.0, -0.15))
	water.add_child(_instance(MapFingerprint.FALLS_MESH, _mesh(vertices, colors, uv2s)))
	var crossings := Node3D.new()
	crossings.name = MapFingerprint.CROSSINGS_NODE
	root.add_child(crossings)
	var arch := Node3D.new()
	arch.name = "Crossing_2"
	arch.position = Vector3(10, 0, 0)
	arch.add_child(_instance("Arch", _plain_mesh(3)))
	crossings.add_child(arch)
	var plank := Node3D.new()
	plank.name = "Crossing_1"
	plank.add_child(_instance("Wood", _plain_mesh(6)))
	crossings.add_child(plank)
	var skirt := Node3D.new()
	skirt.name = "TerrainSkirt"
	root.add_child(skirt)
	skirt.add_child(_instance("Ribbon", _plain_mesh(12)))
	var scatter := FakeScatter.new()
	scatter.rows = {
		"fern": PackedFloat32Array(range(MapDocument.ROW_STRIDE * 2)),
		"birch": PackedFloat32Array(range(MapDocument.ROW_STRIDE)),
	}
	root.add_child(scatter)
	return root


func test_empty_inputs_give_the_empty_fingerprint() -> void:
	var fp := MapFingerprint.of(null, null)
	assert_eq(fp.heights, "")
	assert_eq(fp.falls_count, 0)
	assert_eq(fp.mesh_vertices, 0)
	assert_eq((fp.crossings as Array).size(), 0)


func test_heights_hash_ignores_sub_millimetre_noise() -> void:
	var doc := _doc()
	var before := MapFingerprint.of(null, doc).heights as String
	var noisy := doc.heights.duplicate()
	for i in noisy.size():
		noisy[i] += 0.0002
	doc.heights = noisy
	assert_eq(MapFingerprint.of(null, doc).heights, before, "0.2 mm of noise changes nothing")
	noisy[5] += 0.004
	doc.heights = noisy
	assert_ne(MapFingerprint.of(null, doc).heights, before, "a 4 mm step shows")
	assert_true((before as String).begins_with("%d " % noisy.size()))


func test_water_bodies_are_listed_by_id_kind_depth_and_level() -> void:
	var fp := MapFingerprint.of(null, _doc())
	assert_eq(fp.water, ["3 pond 2 -0.150"])


func test_falls_are_grouped_per_fall_from_the_curtain_vertices() -> void:
	var root := _root()
	var fp := MapFingerprint.of(root, null)
	assert_eq(fp.falls_count, 2, "two curtains; the ring vertices are left out")
	var falls: Array = fp.falls
	assert_true(falls.has("3 (0.000 0.000 0.000)+(0.000 2.000 0.000)"), str(falls))
	assert_true(falls.has("6 (5.000 0.000 1.000)+(0.000 1.000 0.000)"), str(falls))
	root.free()


func test_crossings_give_kind_vertices_and_bounds_in_the_root_frame() -> void:
	var root := _root()
	var fp := MapFingerprint.of(root, null)
	assert_eq(
		fp.crossings,
		[
			"Crossing_1 plank 6 (0.000 0.000 0.000)+(5.000 2.500 0.000)",
			"Crossing_2 arch 3 (10.000 0.000 0.000)+(2.000 1.000 0.000)",
		]
	)
	root.free()


func test_edge_scatter_and_vertex_totals() -> void:
	var root := _root()
	var fp := MapFingerprint.of(root, null)
	assert_eq(fp.edge, ["Ribbon 12"])
	assert_eq(fp.scatter, ["birch 1", "fern 2"])
	assert_eq(fp.mesh_vertices, 12 + 3 + 6 + 12)
	assert_eq((fp.scatter_hash as String).length(), MapFingerprint.HASH_CHARS)
	root.free()


func test_identical_builds_match_after_a_json_round_trip() -> void:
	var root_a := _root()
	var root_b := _root()
	var a := MapFingerprint.of(root_a, _doc())
	var b: Dictionary = JSON.parse_string(JSON.stringify(MapFingerprint.of(root_b, _doc())))
	assert_eq(MapFingerprint.diff(a, b), [] as Array[String], "ints read back as floats match")
	root_a.free()
	root_b.free()


func test_diff_names_the_keys_that_differ() -> void:
	var root_a := _root()
	var root_b := _root()
	var arch := root_b.get_node("%s/Crossing_2" % MapFingerprint.CROSSINGS_NODE) as Node3D
	arch.position.x += 0.01
	var a := MapFingerprint.of(root_a, _doc())
	var b := MapFingerprint.of(root_b, _doc())
	assert_eq(MapFingerprint.diff(a, b), ["crossings"] as Array[String])
	root_a.free()
	root_b.free()
