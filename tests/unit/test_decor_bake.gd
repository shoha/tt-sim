extends GutTest

## The decor plants baked into one mesh per structure (topic polish3): StructureDecor.bake's
## counts and positions, the colour scaling that stands in for each asset's mesh_height, and the
## structure node a build makes. docs/systems/structures.md "Decor plants".

const COTTAGE := "core:cottage"

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _lay(editor: AuthoringEditor) -> int:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	return editor.structures.add(editor.structures.lot(COTTAGE, plan, 100))


func _source(key: String, scale: float, offset: float) -> Array:
	return [
		{
			"key": key,
			"vertices":
			PackedVector3Array(
				[Vector3(0, 0, 0) * scale, Vector3(1, 0, 0) * scale, Vector3(0, 1, 0) * scale]
			),
			"normals": PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
			"colors":
			PackedColorArray([Color(0.5, 0.2, 0.1), Color(0.6, 0.3, 0.2), Color(1, 1, 0)]),
			"uvs": PackedVector2Array([Vector2(offset, 0), Vector2(1, 0), Vector2(0, 1)]),
			"indices": PackedInt32Array([0, 1, 2]),
		}
	]


func test_a_bake_has_the_sum_of_the_instances_and_their_transformed_positions() -> void:
	var sources := {"a": _source("leaf", 1.0, 0.0), "b": _source("leaf", 2.0, 0.5)}
	var turn := Transform3D(Basis(Vector3.UP, PI * 0.5).scaled(Vector3.ONE * 1.5), Vector3(4, 1, 2))
	var placed: Array[Dictionary] = [
		{"id": "a", "transform": Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))},
		{"id": "b", "transform": turn},
		{"id": "missing", "transform": Transform3D.IDENTITY},
		{"id": "a", "transform": turn},
	]
	var out := StructureDecor.bake(placed, sources)
	assert_eq(out.size(), 1, "one surface kind")
	var surface := out[0]
	assert_eq((surface.vertices as PackedVector3Array).size(), 9, "3 plants of 3 vertices")
	assert_eq((surface.indices as PackedInt32Array).size() / 3, 3, "3 triangles")
	assert_eq((surface.normals as PackedVector3Array).size(), 9)
	assert_eq((surface.colors as PackedColorArray).size(), 9)
	assert_eq((surface.uvs as PackedVector2Array).size(), 9)
	# Positions are transform times the asset's vertices; indices follow their plant.
	var vertices := surface.vertices as PackedVector3Array
	var asset_b := sources["b"][0].vertices as PackedVector3Array
	for i in 3:
		assert_true(vertices[3 + i].is_equal_approx(turn * asset_b[i]))
	assert_eq((surface.indices as PackedInt32Array)[3], 3)
	assert_eq((surface.indices as PackedInt32Array)[8], 8)
	for normal in surface.normals as PackedVector3Array:
		assert_almost_eq(normal.length(), 1.0, 0.0001)
	var turned := (surface.normals as PackedVector3Array)[3]
	assert_true(turned.is_equal_approx(turn.basis.orthonormalized() * Vector3.BACK))


func test_surfaces_of_different_materials_stay_apart_in_key_order() -> void:
	var sources := {"leaf": _source("z_leaf", 1.0, 0.0), "pot": _source("a_pot", 1.0, 0.0)}
	var placed: Array[Dictionary] = [
		{"id": "leaf", "transform": Transform3D.IDENTITY},
		{"id": "pot", "transform": Transform3D.IDENTITY},
	]
	var out := StructureDecor.bake(placed, sources)
	assert_eq([out[0].key, out[1].key], ["a_pot", "z_leaf"])
	assert_eq(StructureDecor.bake([] as Array[Dictionary], sources).size(), 0)
	var arrays := StructureDecor.mesh_arrays(out[0])
	assert_eq(arrays.size(), Mesh.ARRAY_MAX)
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 3)


func test_baked_colours_carry_the_assets_mesh_height_in_red_only() -> void:
	var colors := PackedColorArray([Color(1.0, 0.4, 0.7), Color(0.5, 0.1, 0.2)])
	var out := StructureDecor.baked_colors(colors, StructureDecor.BAKE_MESH_HEIGHT * 0.5)
	assert_almost_eq(out[0].r, 0.5, 0.0001)
	assert_almost_eq(out[1].r, 0.25, 0.0001)
	assert_almost_eq(out[0].g, 0.4, 0.0001)
	assert_almost_eq(out[0].b, 0.7, 0.0001)
	assert_eq(colors[0].r, 1.0, "the source is not changed")
	var tall := StructureDecor.baked_colors(colors, StructureDecor.BAKE_MESH_HEIGHT * 3.0)
	assert_eq(tall[0].r, 1.0, "a channel holds 0 to 1")


func test_the_decor_plants_are_one_baked_mesh_with_a_surface_per_material() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var nodes := AuthoredStructures.of_map(_map)
	editor.structures.set_ornaments(id, ["ivy", "flower_boxes"], "Add")
	nodes.flush()
	var baked := nodes.find_children(AuthoredStructures.DECOR_NODE, "MeshInstance3D", true, false)
	var loose := nodes.find_children("decor_*", "MultiMeshInstance3D", true, false)
	if StructureDecor.available(PaletteLibrary.DEFAULT_ROOT) and not baked.is_empty():
		assert_eq(baked.size(), 1, "one baked mesh a structure")
		assert_true(loose.is_empty(), "no MultiMesh per asset")
		var mesh := (baked[0] as MeshInstance3D).mesh
		assert_lte(mesh.get_surface_count(), 4, "leaf and stem of ivy, the planter's two")
		assert_eq(
			(baked[0] as MeshInstance3D).cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		)
		var triangles := 0
		for surface in mesh.get_surface_count():
			assert_true(mesh.surface_get_material(surface) is ShaderMaterial)
			triangles += (
				(mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			)
		assert_lte(triangles, StructureDecor.MAX_TRIANGLES, "the triangle cap is unchanged")
