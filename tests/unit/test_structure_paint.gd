extends GutTest

## The painterly look of structures and street lots (card S6): the palette drawn from a record's
## seed and id, the colours and heights baked into the mesh arrays (StructurePaint), the roles found
## in a street's provenance paths, and the shared materials. Summary: docs/systems/structures.md
## "Look".

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _plan() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-3, -2), Vector2(3, -2), Vector2(3, 2), Vector2(-3, 2)])


func _mesh(parts: Dictionary, role: String, kind: String = "") -> Dictionary:
	for mesh: Dictionary in parts.meshes:
		if mesh.role == role and (kind == "" or mesh.kind == kind):
			return mesh
	return {}


func test_the_palette_is_a_pure_function_of_seed_and_id() -> void:
	assert_eq(StructurePaint.palette_of(5, 1), StructurePaint.palette_of(5, 1), "the same record")
	assert_ne(StructurePaint.mix(5, 1), StructurePaint.mix(5, 2), "the id moves it")
	assert_ne(StructurePaint.mix(5, 1), StructurePaint.mix(6, 1), "the seed moves it")
	assert_eq(StructurePaint.mix(5, 1), StructurePaint.mix(5, 1))
	assert_eq(StructurePaint.mix(-3, 1), StructurePaint.mix(-3, 1), "a negative seed too")


func test_a_town_draws_every_tile_colour_but_not_one_for_all() -> void:
	var names := {}
	for id in range(1, 120):
		names[StructurePaint.palette_of(id * 7919, id).name] = true
	assert_eq(names.size(), StructureLook.ROOF_PALETTE.size(), "every colour turns up in 120")
	var first: String = StructurePaint.palette_of(11, 1).name
	var same := 0
	for id in range(2, 20):
		if StructurePaint.palette_of(id * 31, id).name == first:
			same += 1
	assert_lt(same, 12, "a town is not one roof colour")


func test_palette_colours_are_luminous_not_grey() -> void:
	for id in range(1, 60):
		var palette := StructurePaint.palette_of(id * 17, id)
		var roof: Color = palette.roof
		assert_gt(maxf(roof.r, maxf(roof.g, roof.b)) - minf(roof.r, minf(roof.g, roof.b)), 0.08)
		assert_gt(roof.get_luminance(), 0.06, "not a dark mud")


func test_tag_paths_give_roles_and_lots() -> void:
	var roof := "street_row_2/left/lot0/roof_gable_4"
	assert_eq(StructureLook.role_of_tag_path(roof), StructureLook.ROOF)
	assert_eq(StructureLook.role_of_tag_path("street_row_2/left/lot1/building_walls_3"), "wall")
	assert_eq(
		StructureLook.role_of_tag_path("street_row_2/right/lot0/glazing_6/front0/door0/leaf"),
		StructureLook.OPENING
	)
	assert_eq(StructureLook.role_of_tag_path("street_row_2/left/lot2/yard"), "wall", "a yard")
	assert_eq(StructureLook.lot_of_tag_path(roof), "left/lot0")
	assert_eq(StructureLook.lot_of_tag_path("street_row_2/right/lot12/x"), "right/lot12")
	assert_eq(StructureLook.lot_of_tag_path("building_walls_3"), "")


func test_a_built_roof_carries_its_tile_colour_and_a_height_grade() -> void:
	var structure := Structure.make(1, "core:cottage", _plan(), 5)
	var parts := StructureGeometry.build_one(_doc, structure)
	assert_eq(parts.problem, "")
	assert_eq(parts.palette, StructurePaint.palette_of(5, 1).name)
	var roof := _mesh(parts, StructureLook.ROOF)
	assert_false(roof.is_empty())
	var colors: PackedColorArray = roof.arrays[Mesh.ARRAY_COLOR]
	var low := 1.0
	var high := 0.0
	for c in colors:
		assert_between(c.a, 0.0, 1.0)
		low = minf(low, c.a)
		high = maxf(high, c.a)
	assert_lt(low, 0.02, "an eave at 0")
	assert_gt(high, 0.98, "a ridge at 1")
	var tile: Color = StructurePaint.palette_of(5, 1).roof
	var dominant := 0
	for c in colors:
		if (
			absf(c.r - tile.r) + absf(c.g - tile.g) + absf(c.b - tile.b)
			< 0.45 * (tile.r + tile.g + tile.b)
		):
			dominant += 1
	assert_gt(dominant, colors.size() / 2, "the vertices wear the building's tile colour")


func test_walls_carry_height_above_the_foot() -> void:
	var parts := StructureGeometry.build_one(_doc, Structure.make(1, "core:cottage", _plan(), 5))
	var wall := _mesh(parts, StructureLook.WALL)
	assert_false(wall.is_empty())
	var vertices: PackedVector3Array = wall.arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = wall.arrays[Mesh.ARRAY_COLOR]
	var low := INF
	for v in vertices:
		low = minf(low, v.y)
	for k in vertices.size():
		var expected := clampf((vertices[k].y - low) / StructurePaint.WALL_ALPHA_SPAN_M, 0.0, 1.0)
		assert_almost_eq(colors[k].a, expected, 0.001)


func test_panes_keep_their_procgen_colours() -> void:
	var parts := StructureGeometry.build_one(_doc, Structure.make(1, "core:cottage", _plan(), 5))
	for mesh: Dictionary in parts.meshes:
		if mesh.role != StructureLook.OPENING:
			continue
		for c: Color in mesh.arrays[Mesh.ARRAY_COLOR]:
			assert_eq(c.a, 1.0, "panes are not graded")


func test_two_seeds_paint_differently_and_one_seed_the_same() -> void:
	var a := StructureGeometry.build_one(_doc, Structure.make(1, "core:cottage", _plan(), 5))
	var again := StructureGeometry.build_one(_doc, Structure.make(1, "core:cottage", _plan(), 5))
	assert_eq(StructureGeometry.digest_of(a), StructureGeometry.digest_of(again), "peers agree")
	var names := {}
	for s in range(1, 8):
		var parts := StructureGeometry.build_one(
			_doc, Structure.make(1, "core:cottage", _plan(), s)
		)
		assert_eq(parts.palette, StructurePaint.palette_of(s, 1).name)
		names[parts.palette] = true
	assert_gt(names.size(), 1, "the seed draws the colour")


func test_a_street_splits_its_roofs_and_paints_each_lot() -> void:
	var street := Wall.make(
		1, Wall.Kind.ROW, PackedVector2Array([Vector2(-8, 0), Vector2(8, 0)]), false, 3.0
	)
	var parts := WallGeometry.build_one(_doc, street)
	var roof: Array = parts.get(WallGeometry.ROOF_PART, [])
	assert_false(roof.is_empty(), "the lots' roofs are a part of their own")
	var colors: PackedColorArray = roof[Mesh.ARRAY_COLOR]
	var hues := {}
	for c in colors:
		hues[snappedf(c.r - c.b, 0.2)] = true
	assert_gt(hues.size(), 1, "lots wear their own tile colours")
	assert_false((parts.wood as Array).is_empty() and (parts.masonry as Array).is_empty())


# --- materials ---------------------------------------------------------------------------


func test_structure_nodes_share_one_roof_and_one_wall_look() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	_doc.structures.append(Structure.make(1, "core:cottage", _plan(), 5))
	_doc.structures.append(
		Structure.make(
			2,
			"core:cottage",
			PackedVector2Array([Vector2(5, -2), Vector2(9, -2), Vector2(9, 2), Vector2(5, 2)]),
			8
		)
	)
	var structures := AuthoredStructures.create(_doc)
	map.add_child(structures)
	var first := structures.get_structure_node(1).get_node("roof_wood") as MeshInstance3D
	var second := structures.get_structure_node(2).get_node("roof_wood") as MeshInstance3D
	var material := first.mesh.surface_get_material(0)
	assert_true(material is ShaderMaterial, "a roof is a shader")
	assert_eq((material as ShaderMaterial).shader, StructureMaterials.ROOF_SHADER)
	assert_eq(
		second.mesh.surface_get_material(0), material, "one roof material for every structure"
	)
	var wall := structures.get_structure_node(1).get_node("wall_wood") as MeshInstance3D
	assert_eq(
		(wall.mesh.surface_get_material(0) as ShaderMaterial).shader, StructureMaterials.WALL_SHADER
	)


func test_a_street_lot_wears_the_structure_roof_material() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	_doc.walls.append(
		Wall.make(1, Wall.Kind.ROW, PackedVector2Array([Vector2(-8, 0), Vector2(8, 0)]), false, 3.0)
	)
	var walls := AuthoredWalls.create(_doc)
	map.add_child(walls)
	var roof := walls.get_wall_node(1).get_node_or_null("Roof") as MeshInstance3D
	assert_not_null(roof, "a street has roofs of its own")
	assert_eq(
		(roof.mesh.surface_get_material(0) as ShaderMaterial).shader, StructureMaterials.ROOF_SHADER
	)


func test_a_fence_and_a_wall_keep_their_old_materials() -> void:
	var map := Node3D.new()
	add_child_autofree(map)
	_doc.walls.append(
		Wall.make(
			1, Wall.Kind.FENCE, PackedVector2Array([Vector2(-4, 0), Vector2(4, 0)]), false, 1.2
		)
	)
	var walls := AuthoredWalls.create(_doc)
	map.add_child(walls)
	var wood := walls.get_wall_node(1).get_node("Wood") as MeshInstance3D
	assert_true(wood.mesh.surface_get_material(0) is ORMMaterial3D)
	assert_null(walls.get_wall_node(1).get_node_or_null("Roof"))
