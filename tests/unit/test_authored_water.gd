extends GutTest

## Authored water at runtime (phase 4, P4-2): the merged surface mesh (WaterMeshBuilder), the
## AuthoredWater node (flow map, surface bodies, zones per body, the worker refresh), the
## dressed-map flow rule and the repeat-safe processing in WaterGlbUtils, the float rule
## (WaterSurface) and the ground height field raised to the water (authored and GLB).

const RIVER_LEVEL := -0.2
const POND_LEVEL := -0.6
const BED := -1.0
const POND_BED := -2.5
const EPSILON := 0.0001

var _root: Node3D = null


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null


## A flat 20 x 20 cell map (30.48 m, 123 samples a side) with a straight channel carved to
## BED along X over -10..10 m, 1.5 m either side of Z = 0, holding a waist-deep river at
## RIVER_LEVEL; with `pond`, a deep pond basin carved to POND_BED over samples x 20..39,
## z 90..109 at POND_LEVEL.
func _doc(pond: bool = true) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 0)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5, 1.5])
	doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))
	if pond:
		var mask := PackedByteArray()
		mask.resize(doc.sample_count())
		for z in range(90, 110):
			for x in range(20, 40):
				heights[doc.sample_index(x, z)] = POND_BED
				mask[doc.sample_index(x, z)] = 2
		doc.pond_mask = mask
		doc.water_bodies.append(WaterBody.pond(2, WaterBody.Depth.DEEP, POND_LEVEL))
	doc.heights = heights
	return doc


## The cells (lower corners) of `doc` with a wet corner, computed independently from
## WaterGeometry's wet mask.
func _wet_cells(doc: MapDocument) -> Dictionary:
	var wet := WaterGeometry.wet_mask(doc)
	var columns := doc.samples_x()
	var cells := {}
	for z in doc.samples_z() - 1:
		for x in columns - 1:
			var a := z * columns + x
			if wet[a] + wet[a + 1] + wet[a + columns] + wet[a + columns + 1] > 0:
				cells[Vector2i(x, z)] = true
	return cells


## The cells a mesh covers: each triangle pair's lower corner, from the vertex positions.
func _covered_cells(doc: MapDocument, arrays: Array) -> Dictionary:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var cells := {}
	for t in range(0, indices.size(), 6):
		var low := Vector2(INF, INF)
		for k in 6:
			var v := vertices[indices[t + k]]
			low = Vector2(minf(low.x, v.x), minf(low.y, v.z))
		cells[Vector2i(doc.world_to_sample(low).round())] = true
	return cells


# --- WaterMeshBuilder ---------------------------------------------------------------------


func test_mesh_covers_every_wet_cell_and_a_tucked_margin_only() -> void:
	var doc := _doc()
	var built := WaterMeshBuilder.build(doc)
	var covered := _covered_cells(doc, built.arrays)
	var wet := _wet_cells(doc)
	for cell in wet:
		assert_true(covered.has(cell), "wet cell %s is covered" % cell)
	var columns := doc.samples_x()
	var margin := 0
	for cell: Vector2i in covered:
		if wet.has(cell):
			continue
		margin += 1
		var a := cell.y * columns + cell.x
		for i in [a, a + 1, a + columns, a + columns + 1]:
			assert_gte(doc.heights[i], POND_LEVEL, "a margin cell lies under the banks")
		var near_wet := false
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				near_wet = near_wet or wet.has(cell + Vector2i(dx, dz))
		assert_true(near_wet, "the margin is one ring of cells")
	assert_gt(margin, 0, "a margin ring exists")
	assert_eq(covered.size(), wet.size() + margin)


func test_margin_never_leaves_the_body_where_the_ground_is_below_its_level() -> void:
	var doc := _doc(false)
	# Ground below the river's level just outside its area, beyond its downstream end.
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x > 12.5 and p.x < 14.0 and absf(p.y) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var built := WaterMeshBuilder.build(doc)
	for v in built.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		assert_lte(v.x, 12.5, "no water over the low ground outside the river's area")


func test_uvs_are_map_normalised() -> void:
	var doc := _doc()
	var built := WaterMeshBuilder.build(doc)
	var vertices: PackedVector3Array = built.arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = built.arrays[Mesh.ARRAY_TEX_UV]
	var extent := doc.extent_m()
	assert_eq(uvs.size(), vertices.size())
	for i in vertices.size():
		var expected := Vector2(
			(vertices[i].x + extent.x * 0.5) / extent.x, (vertices[i].z + extent.y * 0.5) / extent.y
		)
		assert_almost_eq(uvs[i], expected, Vector2(EPSILON, EPSILON))


func test_each_body_is_flat_at_its_level() -> void:
	var doc := _doc()
	var built := WaterMeshBuilder.build(doc)
	var levels := {}
	for v in built.arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
		levels[snappedf(v.y, 0.001)] = true
		assert_eq((built.arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0], Vector3.UP)
	assert_eq(levels.keys().size(), 2, "one level per body")
	assert_true(levels.has(RIVER_LEVEL) and levels.has(POND_LEVEL))
	assert_eq(built.bodies.size(), 2)
	for body: Dictionary in built.bodies:
		var level: float = body.level
		for p in body.faces as PackedVector3Array:
			assert_almost_eq(p.y, level, EPSILON)
		assert_eq(body.floats, body.id == 2, "the deep pond floats, the waist river wades")
		assert_gt((body.tiles as Array).size(), 0)


func test_levels_and_wet_follow_the_water_model() -> void:
	var doc := _doc()
	var built := WaterMeshBuilder.build(doc)
	var model := WaterGeometry.levels(doc)
	assert_eq(built.levels, model, "the highest body's level per sample")
	assert_eq(built.wet, WaterGeometry.wet_mask(doc, model))


func test_no_water_builds_nothing() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "", "", 0)
	var built := WaterMeshBuilder.build(doc)
	assert_true((built.arrays as Array).is_empty())
	assert_true((built.bodies as Array).is_empty())
	assert_false(built.wet.has(1))


# --- AuthoredWater and WaterGlbUtils -----------------------------------------------------


func _flowing(doc: MapDocument) -> MapDocument:
	doc.water_flow_size = WaterFlowBaker.resolution_for(doc.extent_m())
	doc.water_flow = WaterFlowBaker.bake(doc, doc.water_flow_size)
	return doc


func test_the_mesh_is_named_bounds_exempt_and_carries_the_flow_map() -> void:
	var doc := _flowing(_doc())
	var water := AuthoredWater.create(doc)
	_root = Node3D.new()
	_root.add_child(water)
	var mesh := water.get_mesh_instance()
	assert_not_null(mesh)
	assert_eq(String(mesh.name), "AuthoredWater-water")
	assert_true(mesh.get_meta(Constants.BOUNDS_EXEMPT_META, false))
	assert_eq(mesh.transform, Transform3D.IDENTITY)
	assert_eq(mesh.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	var carried := WaterGlbUtils._extract_flow_map(mesh)
	assert_not_null(carried, "the flow map rides as the emission texture")
	assert_eq(Vector2i(carried.get_size()), doc.water_flow_size)
	WaterGlbUtils.process_water_meshes(_root)
	var material := WaterGlbUtils._get_water_material()
	assert_eq(material.get_shader_parameter(WaterGlbUtils.FLOW_MAP_PARAM), carried)
	assert_true(mesh.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM))
	assert_eq(mesh.material_override, material)
	var bounds := LevelEnvironmentManager.compute_map_bounds(_root)
	assert_eq(bounds.size, Vector3.ZERO, "the water is not in the map bounds")


func test_a_zone_and_a_surface_body_per_body_at_its_level() -> void:
	var water := AuthoredWater.create(_doc())
	_root = Node3D.new()
	_root.add_child(water)
	WaterGlbUtils.process_water_meshes(_root)
	var zones := {}
	var bodies := {}
	for child in water.get_children():
		if child is WaterZone:
			zones[String(child.name)] = child
		elif child is StaticBody3D:
			bodies[String(child.name)] = child
	assert_eq(zones.keys().size(), 2, "one zone per body, none added for the merged mesh")
	assert_almost_eq((zones["Zone_1"] as Node3D).position.y, RIVER_LEVEL, EPSILON)
	assert_almost_eq((zones["Zone_2"] as Node3D).position.y, POND_LEVEL, EPSILON)
	var river_zone: WaterZone = zones["Zone_1"]
	for shape in river_zone.get_children():
		var box: Vector3 = ((shape as CollisionShape3D).shape as BoxShape3D).size
		var at: Vector3 = (shape as CollisionShape3D).position
		assert_lte(absf(at.z) + box.z * 0.5, 1.5 + 0.3, "tiles hug the channel")
		assert_almost_eq(at.y + box.y * 0.5, WaterZone.SURFACE_MARGIN, EPSILON)
	assert_eq(bodies.keys().size(), 2)
	var pond: StaticBody3D = bodies["Surface_2"]
	assert_eq(pond.collision_layer, WaterSurface.LAYER, "off the terrain layer")
	assert_true(pond.get_meta(WaterSurface.FLOATS_META))
	assert_false((bodies["Surface_1"] as StaticBody3D).get_meta(WaterSurface.FLOATS_META))
	assert_null(_root.get_node_or_null("AuthoredWater-water_zone"))


func test_zone_for_footprint_skips_degenerate_tiles() -> void:
	var tiles: Array[Rect2] = [Rect2(0, 0, 0, 3)]
	assert_null(WaterZone.create_for_footprint("Z", 1.0, tiles))
	tiles.append(Rect2(1, 2, 3, 4))
	var zone := WaterZone.create_for_footprint("Z", 1.0, tiles)
	assert_eq(zone.get_child_count(), 1)
	assert_eq(zone.collision_mask, WaterZone.TOKEN_COLLISION_LAYER_MASK)
	assert_almost_eq((zone.get_child(0) as Node3D).position.x, 2.5, EPSILON)
	zone.free()


## A Blender plane (with or without a flow map) beside the authored water.
func _dressed_root(doc: MapDocument, glb_flow: bool) -> MeshInstance3D:
	_root = Node3D.new()
	var plane := MeshInstance3D.new()
	plane.name = "Lake-water"
	var quad := PlaneMesh.new()
	var material := StandardMaterial3D.new()
	if glb_flow:
		var image := Image.create(4, 4, false, Image.FORMAT_RGB8)
		material.emission_texture = ImageTexture.create_from_image(image)
	quad.material = material
	plane.mesh = quad
	plane.scale = Vector3(100, 1, 100)
	_root.add_child(plane)
	WaterGlbUtils.process_water_meshes(_root)
	MapSourceLoader.add_authored_water(_root, doc, false)
	return plane


func test_dressed_map_authored_river_flow_wins_over_a_bigger_glb_plane() -> void:
	var plane := _dressed_root(_flowing(_doc()), true)
	var mesh := (_root.get_node("AuthoredWater") as AuthoredWater).get_mesh_instance()
	assert_true(mesh.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM))
	assert_false(bool(plane.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM)))
	assert_eq(mesh.material_override, plane.material_override, "one shared material")


func test_dressed_map_with_ponds_only_keeps_the_glb_flow() -> void:
	var doc := _doc()
	doc.water_bodies.remove_at(0)
	var plane := _dressed_root(doc, true)
	assert_true(plane.get_instance_shader_parameter(WaterGlbUtils.FLOW_PRESENT_PARAM))


func test_processing_twice_adds_no_second_zone_or_surface() -> void:
	_dressed_root(_doc(), false)
	WaterGlbUtils.process_water_meshes(_root)
	var zones := 0
	var surfaces := 0
	for child in _root.get_children():
		zones += 1 if child is WaterZone else 0
		surfaces += 1 if child is StaticBody3D else 0
	assert_eq(zones, 1, "the GLB plane's zone once")
	assert_eq(surfaces, 1, "the GLB plane's surface body once")
	var surface := _root.get_node("Lake-water_surface") as StaticBody3D
	assert_eq(surface.collision_layer, WaterSurface.LAYER)
	assert_false(surface.has_meta(WaterSurface.FLOATS_META), "a Blender plane floats by depth")


func test_add_authored_water_needs_water_unless_always() -> void:
	_root = Node3D.new()
	var dry := MapDocument.create_flat(Vector2i(4, 4), "", "", 0)
	assert_null(MapSourceLoader.add_authored_water(_root, dry, false))
	assert_null(MapSourceLoader.add_authored_water(_root, null, true))
	var water := MapSourceLoader.add_authored_water(_root, dry, true)
	assert_not_null(water, "authoring always has the node")
	assert_false(water.has_water())


func test_refresh_rebuilds_on_a_worker_and_bakes_into_the_document() -> void:
	var doc := _doc()
	_root = Node3D.new()
	add_child(_root)
	var water := AuthoredWater.refresh_map(_root, doc)
	assert_true(water.is_refreshing())
	var before := water.version
	water.finish_refresh()
	assert_false(water.is_refreshing())
	assert_gt(water.version, before)
	assert_true(water.has_water())
	assert_eq(doc.water_flow_size, WaterFlowBaker.resolution_for(doc.extent_m()))
	assert_eq(doc.water_flow, WaterFlowBaker.bake(doc, doc.water_flow_size), "the same bake")
	assert_not_null(WaterGlbUtils._extract_flow_map(water.get_mesh_instance()))
	# Queued requests collapse to the newest.
	doc.water_bodies.remove_at(1)
	AuthoredWater.refresh_map(_root, doc)
	AuthoredWater.refresh_map(_root, doc)
	water.finish_refresh()
	var zones := 0
	for child in water.get_children():
		zones += 1 if child is WaterZone and not child.is_queued_for_deletion() else 0
	assert_eq(zones, 1, "the pond is gone")
	remove_child(_root)


# --- The float rule ---------------------------------------------------------------------


func test_landing_rule() -> void:
	assert_eq(WaterSurface.landing_y(-1.0, NAN, true), -1.0, "no water: the bed")
	assert_eq(WaterSurface.landing_y(-1.0, 0.0, false), -1.0, "wadeable: the bed")
	assert_almost_eq(
		WaterSurface.landing_y(-2.0, 0.0, true), -WaterSurface.DRAFT_M, EPSILON, "deep: floats"
	)
	assert_eq(WaterSurface.landing_y(-0.1, 0.0, true), -0.1, "a shallow edge: the bed")
	assert_eq(WaterSurface.landing_y(0.5, 0.0, true), 0.5, "surface under the ground")
	assert_true(WaterSurface.floats_for(true, 0.1))
	assert_false(WaterSurface.floats_for(false, 5.0))
	assert_true(WaterSurface.floats_for(null, WaterSurface.FLOAT_DEPTH_M))
	assert_false(WaterSurface.floats_for(null, 1.0), "a Blender plane wades when shallow")


## An authored root in the tree: terrain collision (layer 1) and the water.
func _authored_in_tree(doc: MapDocument) -> void:
	_root = Node3D.new()
	_root.add_child(AuthoredTerrain.create(doc))
	add_child(_root)
	MapSourceLoader.add_authored_water(_root, doc, false)


func test_tokens_float_in_deep_water_and_stand_on_the_bed_in_wadeable_water() -> void:
	var doc := _doc()
	_authored_in_tree(doc)
	await get_tree().physics_frame
	var space := _root.get_world_3d().direct_space_state
	var river := WaterSurface.landing_below(space, Vector3(0, 0, 0), 5.0)
	assert_almost_eq(river.y, BED, 0.01, "waist-deep river: on the bed")
	var pond_xz := doc.sample_to_world(Vector2(30, 100))
	var pond := WaterSurface.landing_below(space, Vector3(pond_xz.x, 0, pond_xz.y), 5.0)
	assert_almost_eq(pond.y, POND_LEVEL - WaterSurface.DRAFT_M, 0.01, "deep pond: afloat")
	var bank := WaterSurface.landing_below(space, Vector3(5, 0, 8), 5.0)
	assert_almost_eq(bank.y, 0.0, 0.01, "dry ground")
	# The map origin is a vertex of the surface's triangles, where a bare ray slips through.
	var surface := WaterSurface.surface_below(space, Vector3(0, 0, 0), 5.0)
	assert_almost_eq(surface.y, RIVER_LEVEL, 0.01, "measuring along the surface")
	assert_true(
		WaterSurface.floats_at(
			space, Vector3(pond_xz.x, POND_LEVEL - WaterSurface.DRAFT_M, pond_xz.y)
		)
	)
	assert_false(WaterSurface.floats_at(space, Vector3(0, BED, 0)), "wading is not floating")
	remove_child(_root)


## DraggableToken's _ready() reads get_tree().current_scene (see test_water_zone.gd).
func _token_over(at: Vector3) -> DraggableToken:
	var rigid_body := RigidBody3D.new()
	rigid_body.collision_layer = 2
	rigid_body.collision_mask = 0
	rigid_body.gravity_scale = 0.0
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	rigid_body.add_child(collision_shape)
	rigid_body.add_child(Node3D.new())
	var token := DraggableToken.new()
	token.rigid_body = rigid_body
	token.collision_shape = collision_shape
	token.add_child(rigid_body)
	_root.add_child(token)
	rigid_body.global_position = at
	return token


func test_a_dropped_token_lands_afloat_or_on_the_bed() -> void:
	var original_scene := get_tree().current_scene
	var scene_root := Node.new()
	get_tree().root.add_child(scene_root)
	get_tree().current_scene = scene_root
	var doc := _doc()
	_authored_in_tree(doc)
	var pond_xz := doc.sample_to_world(Vector2(30.3, 100.4))
	var floater := _token_over(Vector3(pond_xz.x, 3.0, pond_xz.y))
	var wader := _token_over(Vector3(0.2, 3.0, 0.3))
	await get_tree().physics_frame
	var afloat: Vector3 = floater._find_landing_position()
	assert_almost_eq(afloat.y - 0.5, POND_LEVEL - WaterSurface.DRAFT_M, 0.01, "base at the draft")
	var wading: Vector3 = wader._find_landing_position()
	assert_almost_eq(wading.y - 0.5, BED, 0.01, "base on the bed")
	# Even from below the surface (a token left on a deep bed) the landing floats it.
	floater.rigid_body.global_position = Vector3(pond_xz.x, POND_BED + 0.5, pond_xz.y)
	afloat = floater._find_landing_position()
	assert_almost_eq(afloat.y - 0.5, POND_LEVEL - WaterSurface.DRAFT_M, 0.01)
	get_tree().current_scene = original_scene
	scene_root.free()
	remove_child(_root)


# --- The ground height field --------------------------------------------------------------


func test_raise_to_water_is_the_level_on_wet_samples_only() -> void:
	var ground := PackedFloat32Array([0.0, -1.0, -1.0, 2.0])
	var levels := PackedFloat32Array([WaterGeometry.DRY, -0.5, WaterGeometry.DRY, 1.0])
	var raised := GroundHeightField.raise_to_water(ground, levels)
	assert_eq(raised[0], PackedFloat32Array([0.0, -0.5, -1.0, 2.0]))
	assert_eq(raised[1], PackedByteArray([0, 1, 0, 0]))


func test_authored_field_lies_on_the_water_surface() -> void:
	var doc := _doc()
	_authored_in_tree(doc)
	var terrain := _root.get_node("AuthoredTerrain") as AuthoredTerrain
	var field := GroundHeightField.from_terrain(terrain)
	assert_true(field.has_water())
	assert_almost_eq(field.world_height_at(Vector2(0, 0)), RIVER_LEVEL, EPSILON)
	assert_almost_eq(field.world_height_at(Vector2(5, 8)), 0.0, EPSILON, "dry ground unchanged")
	var texture := field.get_texture()
	assert_eq(texture.get_image().get_format(), Image.FORMAT_RGF, "heights and water flags")
	assert_ne(texture, terrain.get_height_texture())
	# A sculpt settling under the water recomposes the same texture in place.
	terrain.settle_heights()
	terrain.call("_refresh_height_texture")
	assert_same(field.get_texture(), texture)
	remove_child(_root)


func test_a_field_without_water_is_the_terrain_texture() -> void:
	var doc := _doc()
	doc.water_bodies.clear()
	_authored_in_tree(doc)
	var terrain := _root.get_node("AuthoredTerrain") as AuthoredTerrain
	var field := GroundHeightField.from_terrain(terrain)
	assert_false(field.has_water())
	assert_same(field.get_texture(), terrain.get_height_texture())
	remove_child(_root)


func test_glb_field_samples_the_water_surface_with_flags() -> void:
	_root = Node3D.new()
	add_child(_root)
	# Ground at Y = -1 (the bed) and a water plane at -0.3 over half of it.
	var ground := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 1, 8)
	var shape := CollisionShape3D.new()
	shape.shape = box
	ground.add_child(shape)
	ground.position = Vector3(0, -1.5, 0)
	_root.add_child(ground)
	var faces := PackedVector3Array(
		[Vector3(0, -0.3, -4), Vector3(4, -0.3, -4), Vector3(4, -0.3, 4)]
	)
	faces.append_array(
		PackedVector3Array([Vector3(0, -0.3, -4), Vector3(4, -0.3, 4), Vector3(0, -0.3, 4)])
	)
	_root.add_child(WaterSurface.make_body("Plane-water_surface", faces, null))
	await get_tree().physics_frame
	var sampler := DressingGround.begin_grid(
		_root.get_world_3d(),
		Transform3D.IDENTITY,
		10.0,
		Vector2(-3.5, -3.5),
		Vector2(1, 1),
		8,
		8,
		WaterSurface.WALKABLE_MASK
	)
	while not sampler.step(100000):
		pass
	assert_almost_eq(sampler.heights[0], -1.0, 0.01, "dry: the ground")
	assert_eq(sampler.water[0], 0)
	assert_almost_eq(sampler.heights[7], -0.3, 0.01, "over water: the surface")
	assert_eq(sampler.water[7], 1)
	var field := GroundHeightField.for_glb(
		_root,
		sampler.heights,
		sampler.hits,
		8,
		8,
		Vector2(-3.5, -3.5),
		Vector2(1, 1),
		sampler.water
	)
	assert_not_null(field)
	assert_true(field.has_water())
	assert_eq(field.get_texture().get_image().get_format(), Image.FORMAT_RGF)
	var bed_only := DressingGround.begin_grid(
		_root.get_world_3d(), Transform3D.IDENTITY, 10.0, Vector2(-3.5, -3.5), Vector2.ONE, 8, 8
	)
	while not bed_only.step(100000):
		pass
	assert_almost_eq(bed_only.heights[7], -1.0, 0.01, "the dressing ground keeps the bed")
	remove_child(_root)
