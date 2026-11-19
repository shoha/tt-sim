extends GutTest

## The painted look on a Blender-made map.glb (PainterGlbMap, PainterGlbRoles;
## docs/systems/painter.md "GLB maps", card painter-glb-parity): the ground meshes, scatter chunks,
## trees and props of a GLB the loader built are dressed in painted materials and put back
## exactly, the look switch works both ways, what the pass cannot classify stays as authored, and
## Classic is never touched. The map is written by glb_world_fixture.gd and loaded through
## GlbUtils.load_map_async, the path a play load takes.

const FIXTURE := preload("res://tests/unit/glb_world_fixture.gd")
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const PATH := "user://_painter-glb-parity_test.glb"

var _container: Node3D = null
var _map: Node3D = null
var _choice: int = RenderStyle.DEFAULT_CHOICE


func before_each() -> void:
	PainterSheet.clear_cache()
	_choice = RenderStyle.choice
	_container = Node3D.new()
	add_child_autofree(_container)


func after_each() -> void:
	RenderStyle.choice = _choice
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


## The fixture world, loaded as a play load builds it, under the container as LevelMap.
func _world() -> Node3D:
	assert_eq(FIXTURE.write(PATH), OK)
	var result: GlbUtils.AsyncLoadResult = await GlbUtils.load_map_async(
		PATH, true, 1.0, {}, Callable()
	)
	assert_true(result.success)
	_map = result.scene
	_map.name = "LevelMap"
	_container.add_child(_map)
	return _map


## Finishes the host's scan, reading the terrain tiles' arrays from the fixture (the headless dummy
## renderer keeps none to read back).
func _complete(surfaces: PainterSurfaces) -> void:
	var host := surfaces.glb_map()
	host.set(
		"surface_arrays",
		func(mesh: Mesh) -> Array:
			return (
				FIXTURE.tile_arrays(-24.0, 0.0)
				if mesh.get_aabb().position.x < -1.0
				else FIXTURE.tile_arrays(0.0, 24.0)
			)
	)
	host.call("complete")


func _node(node_name: String) -> Node:
	return GlbUtils.find_node_by_name(_map, node_name)


func _chunks(stem: String) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	for child in _map.get_children():
		if child is MultiMeshInstance3D and String(child.name).begins_with(stem + "_MultiMesh"):
			out.append(child)
	return out


func _painted(material: Material) -> bool:
	return material != null and material.has_meta(PainterSurfaces.META)


func _roles(host: RefCounted, node_name: String) -> Array[String]:
	var out: Array[String] = []
	for record: Array in host.call("props"):
		if str((record[0] as Node).name) == node_name:
			out.append(str((record[4] as Dictionary)["role"]))
	return out


# --- the pure reading ---------------------------------------------------------------------


func test_a_tree_is_grown_by_its_species_name_or_a_word_of_it() -> void:
	assert_eq(PainterGlbRoles.tree_species("Tree_Oak_Source"), "oak", "treecube's name")
	assert_eq(PainterGlbRoles.tree_species("Oak.003"), "oak", "a Blender duplicate")
	assert_eq(PainterGlbRoles.tree_species("old_pine_01"), "spruce", "a pine is a spruce form")
	assert_eq(PainterGlbRoles.tree_species("Fir_Big"), "spruce")
	assert_eq(PainterGlbRoles.tree_species("Fire_Pit"), "", "fir is a word, not a letter run")
	assert_eq(PainterGlbRoles.tree_species("Tree_Palm_01"), "", "an unknown tree keeps its mesh")
	assert_eq(PainterGlbRoles.tree_species("Bush_Bush_v0"), "", "a bush is not a grown tree")


func test_a_grown_tree_stands_as_tall_as_the_mesh_it_replaces() -> void:
	assert_almost_eq(PainterGlbRoles.tree_scale("oak", 9.3), 1.0, 0.01, "the nominal height")
	assert_almost_eq(PainterGlbRoles.tree_scale("oak", 4.65), 0.5, 0.01, "a small oak")
	assert_eq(
		PainterGlbRoles.tree_scale("oak", 0.01), PainterGlbRoles.TREE_SCALE_RANGE.x, "clamped low"
	)
	assert_eq(
		PainterGlbRoles.tree_scale("oak", 900.0), PainterGlbRoles.TREE_SCALE_RANGE.y, "clamped high"
	)
	var to_map := Transform3D(Basis.IDENTITY, Vector3(1, 2, 3))
	var rows := PainterGlbMap.rows_of(
		[Transform3D(Basis.from_scale(Vector3.ONE * 2.0), Vector3.ZERO)], to_map, 0.5
	)
	assert_almost_eq(
		rows[MapDocument.ROW_STRIDE - 1], 1.0, 0.001, "row scale is the node scale times k"
	)


func test_a_prop_surface_takes_its_role_from_its_names_then_its_colour() -> void:
	var white := Color(0.9, 0.9, 0.9)
	assert_eq(PainterGlbRoles.prop_role("House_Roof", "House", white, false), "roof-clay")
	assert_eq(
		PainterGlbRoles.prop_role("Mat", "Slate_Roof", white, false), "roof-slate", "slate first"
	)
	assert_eq(PainterGlbRoles.prop_role("Barrel_Wood", "Barrel", white, true), "bark")
	assert_eq(PainterGlbRoles.prop_role("House_Wall", "House", white, true), "stone")
	assert_eq(
		PainterGlbRoles.prop_role("Window_Glass", "House_wall", white, false), "", "lights stay"
	)
	assert_eq(PainterGlbRoles.prop_role("Iron_Bands", "Barrel", white, false), "", "ironwork stays")
	assert_eq(
		PainterGlbRoles.prop_role("Mat_01", "Thing", white, true),
		"",
		"a textured unnamed surface stays"
	)
	assert_eq(PainterGlbRoles.prop_role("Mat_01", "Thing", Color(0.2, 0.5, 0.15), false), "leaf")
	assert_eq(
		PainterGlbRoles.prop_role("Mat_01", "Thing", Color(0.75, 0.25, 0.15), false), "roof-clay"
	)
	assert_eq(PainterGlbRoles.prop_role("Mat_01", "Thing", Color(0.4, 0.28, 0.16), false), "bark")


func test_ground_is_wide_shallow_and_faces_up() -> void:
	assert_true(PainterGlbRoles.is_ground(Vector3(24, 6, 48), 0.9), "a hilly tile")
	assert_false(PainterGlbRoles.is_ground(Vector3(24, 6, 48), 0.2), "a wall of cliff")
	assert_false(PainterGlbRoles.is_ground(Vector3(5, 5, 5), 0.9), "a house")
	assert_false(
		PainterGlbRoles.is_ground(Vector3(30, 28, 30), 0.9), "a hill taller than it is wide"
	)
	assert_false(PainterGlbRoles.is_ground(Vector3(40, 1, 2), 0.9), "a long thin strip")


func test_the_planar_uv_fit_reads_any_affine_map_and_refuses_the_rest() -> void:
	var xz := PackedVector2Array()
	var uv := PackedVector2Array()
	for i in 40:
		var p := Vector2(float(i % 7) * 3.0 - 9.0, float(i / 7) * 4.0 - 10.0)
		xz.append(p)
		# Rotated, flipped in v and offset, as an exporter may leave a unwrap.
		uv.append(Vector2(0.5 + p.y / 80.0, 1.0 - (0.5 + p.x / 60.0)))
	var fit := PainterGlbRoles.uv_affine(xz, uv)
	assert_true(fit["ok"])
	var m: Vector4 = fit["uv"]
	var b: Vector2 = fit["b"]
	for i in xz.size():
		var got := Vector2(m.x * xz[i].x + m.z * xz[i].y, m.y * xz[i].x + m.w * xz[i].y) + b
		assert_lt(got.distance_to(uv[i]), 0.001, "the fit reproduces vertex %d" % i)
	uv[7] = uv[7] + Vector2(0.3, 0.2)
	uv[15] = uv[15] + Vector2(0.3, 0.2)
	uv[16] = uv[16] + Vector2(0.3, 0.2)
	uv[29] = uv[29] + Vector2(0.3, 0.2)
	assert_false(PainterGlbRoles.uv_affine(xz, uv)["ok"], "a mesh unwrapped in pieces is refused")
	assert_false(PainterGlbRoles.uv_affine(PackedVector2Array([Vector2.ZERO]), uv)["ok"], "too few")


func test_instance_rows_are_the_documents_layout_in_the_map_frame() -> void:
	var transforms: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 1.5), Vector3(2, 3, 4))
	]
	var rows := PainterGlbMap.rows_of(transforms, Transform3D(Basis.IDENTITY, Vector3(10, 0, 0)))
	assert_eq(rows.size(), MapDocument.ROW_STRIDE)
	assert_almost_eq(rows[0], 12.0, 0.0001)
	assert_almost_eq(rows[1], 3.0, 0.0001)
	assert_almost_eq(
		rows[PainterTreeSpecies.SCALE_AT], 1.5, 0.0001, "the scale the tree's age reads"
	)
	var wanted := PainterGlbMap.wanted({"Tree_Oak_Source": {"species": "oak", "rows": rows}}, null)
	assert_eq(wanted.size(), 1)
	assert_eq((wanted.values()[0] as Dictionary)["species"], "oak")
	assert_eq((wanted.values()[0] as Dictionary)["asset"], "Tree_Oak_Source")


# --- a GLB map, painted ----------------------------------------------------------------------


func test_painting_a_glb_map_dresses_its_ground_scatter_trees_and_props() -> void:
	await _world()
	var water_override := (_node("Lake-water") as MeshInstance3D).material_override
	var surfaces := PainterSurfaces.new()
	assert_null(surfaces.glb_map(), "nothing before the first Painted level")
	assert_true(surfaces.paint(_map, STATE))
	var host := surfaces.glb_map()
	_complete(surfaces)

	for tile in ["Terrain_West", "Terrain_East"]:
		var ground := (_node(tile) as MeshInstance3D).material_override as ShaderMaterial
		assert_not_null(ground, tile + " painted")
		assert_eq(ground.shader.resource_path, PainterSurfaces.GROUND_SHADER)
		assert_true(ground.get_shader_parameter(&"world_frame"), "in the world's frame")
		assert_true(ground.get_shader_parameter(&"glb_zone"), "its zone read from its albedo")
		assert_true(ground in surfaces.ground_materials(), "tokens' feet reach it")
	assert_eq(
		(_node("Lake-water") as MeshInstance3D).material_override,
		water_override,
		"water is PainterWater's"
	)

	assert_eq(_roles(host, "House_01"), ["stone", "roof-clay"] as Array[String], "walls and roof")
	for i in 3:
		assert_eq(_roles(host, "Barrel_%02d" % i), ["bark"] as Array[String])
	var grass := _chunks("Grass_Tuft_Source")[0].multimesh.mesh
	assert_eq(
		(grass.surface_get_material(0) as ShaderMaterial).shader.resource_path,
		PainterSurfaces.PLANT_SHADER
	)
	assert_true(_painted(grass.surface_get_material(0)))
	var rock := _chunks("Rock_Boulder_Source")[0].multimesh.mesh
	assert_eq(
		(rock.surface_get_material(0) as ShaderMaterial).shader.resource_path,
		PainterSurfaces.SOLID_SHADER
	)
	var bush := _chunks("Bush_Source")[0].multimesh.mesh
	assert_eq(
		int((bush.surface_get_material(0) as ShaderMaterial).get_shader_parameter(&"kind")),
		PainterPlantRoles.KIND_CROWN
	)

	var rows: Dictionary = host.call("tree_rows")
	assert_eq(rows.keys().size(), 2, "the oak and the pine")
	assert_eq(rows["Tree_Oak_Source"]["species"], "oak")
	assert_eq(rows["Tree_Pine_Source"]["species"], "spruce")
	assert_eq(
		(rows["Tree_Oak_Source"]["rows"] as PackedFloat32Array).size(), 14 * MapDocument.ROW_STRIDE
	)
	for chunk in _chunks("Tree_Oak_Source"):
		assert_false(chunk.visible, "the GLB oak is drawn by the painted trees")
	assert_eq(PainterGlbMap.rows_on(_map), rows)

	surfaces.release()


func test_release_puts_every_glb_material_and_node_back_exactly() -> void:
	await _world()
	var meshes: Array[MeshInstance3D] = []
	for node_name in ["Terrain_West", "Terrain_East", "House_01", "Barrel_00", "Fence_Post_03"]:
		meshes.append(_node(node_name) as MeshInstance3D)
	var overrides := {}
	var surface_materials := {}
	for node in meshes:
		overrides[node] = node.material_override
		var own: Array = []
		for i in node.mesh.get_surface_count():
			own.append(node.get_surface_override_material(i))
			own.append(node.mesh.surface_get_material(i))
		surface_materials[node] = own
	var species_meshes: Array[Mesh] = []
	var species_materials: Array = []
	for stem in [
		"Grass_Tuft_Source",
		"Flower_Daisy_Source",
		"Rock_Boulder_Source",
		"Bush_Source",
		"Tree_Oak_Source"
	]:
		var mesh := _chunks(stem)[0].multimesh.mesh
		species_meshes.append(mesh)
		var own: Array = []
		for i in mesh.get_surface_count():
			own.append(mesh.surface_get_material(i))
		species_materials.append(own)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	_complete(surfaces)
	surfaces.release()

	for node in meshes:
		assert_eq(node.material_override, overrides[node], "%s override back" % node.name)
		var own: Array = []
		for i in node.mesh.get_surface_count():
			own.append(node.get_surface_override_material(i))
			own.append(node.mesh.surface_get_material(i))
		assert_eq(own, surface_materials[node], "%s materials back" % node.name)
	for k in species_meshes.size():
		for i in species_meshes[k].get_surface_count():
			assert_eq(
				species_meshes[k].surface_get_material(i),
				species_materials[k][i],
				"species %d surface %d" % [k, i]
			)
	for chunk in _chunks("Tree_Oak_Source") + _chunks("Tree_Pine_Source"):
		assert_true(chunk.visible, "the GLB trees are shown again")
	assert_false(surfaces.is_active())


func test_classic_never_touches_a_glb_map() -> void:
	# Classic-pinned: with no paint call (the Classic path never makes a host) every node of the
	# loaded map keeps its loader-built materials, visibility and the unpainted shader of its own.
	await _world()
	var surfaces := PainterSurfaces.new()
	assert_null(surfaces.glb_map(), "no host before a paint")
	assert_false(surfaces.is_active())
	surfaces.release()
	var seen := 0
	for node in _map.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		assert_true(mesh_node.visible, "%s visible" % mesh_node.name)
		assert_false(_painted(mesh_node.material_override), "%s override" % mesh_node.name)
		for i in mesh_node.mesh.get_surface_count():
			assert_false(_painted(mesh_node.get_surface_override_material(i)))
			assert_false(_painted(mesh_node.mesh.surface_get_material(i)))
		seen += 1
	assert_gt(seen, 5, "the world has meshes to check")
	for chunk in _chunks("Tree_Oak_Source"):
		assert_true(chunk.visible)
		assert_false(_painted(chunk.multimesh.mesh.surface_get_material(0)))


func test_the_look_switches_both_ways_at_runtime() -> void:
	await _world()
	var surfaces := PainterSurfaces.new()
	for round in 2:
		surfaces.paint(_map, STATE)
		_complete(surfaces)
		assert_not_null(
			(_node("Terrain_West") as MeshInstance3D).material_override, "painted, round %d" % round
		)
		assert_false((_node("House_01") as MeshInstance3D).get_surface_override_material(1) == null)
		assert_false(_chunks("Tree_Oak_Source")[0].visible)
		surfaces.release()
		assert_null(
			(_node("Terrain_West") as MeshInstance3D).material_override, "Classic, round %d" % round
		)
		assert_null((_node("House_01") as MeshInstance3D).get_surface_override_material(1))
		assert_true(_chunks("Tree_Oak_Source")[0].visible)


func test_a_new_mood_retones_the_props_and_the_ground() -> void:
	await _world()
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	_complete(surfaces)
	var roof := (
		(_node("House_01") as MeshInstance3D).get_surface_override_material(1) as ShaderMaterial
	)
	var ground := (_node("Terrain_West") as MeshInstance3D).material_override as ShaderMaterial
	var summer_roof: Variant = roof.get_shader_parameter(&"c_mid0")
	var summer_ground: Variant = ground.get_shader_parameter(&"g_lit")
	var winter := STATE.duplicate()
	winter["mood"] = "winter"
	surfaces.paint(_map, winter)
	assert_ne(roof.get_shader_parameter(&"c_mid0"), summer_roof, "the roof follows the mood")
	assert_ne(ground.get_shader_parameter(&"g_lit"), summer_ground, "the ground follows the mood")
	assert_eq(
		(_node("Terrain_West") as MeshInstance3D).material_override,
		ground,
		"the same material, re-toned"
	)
	surfaces.release()


func test_what_the_pass_cannot_classify_stays_as_authored() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	# A lit window pane, a textured surface whose name says nothing, ironwork: all stay.
	var glass := _prop("Window_Glass", Color(0.6, 0.8, 0.9), false)
	var plain := _prop("Mat_01", Color.WHITE, true)
	var iron := _prop("Iron_Bands", Color(0.3, 0.3, 0.3), false)
	# A terrain of two surfaces cannot take one ground material: it is a prop by its names.
	var two := MeshInstance3D.new()
	two.name = "Terrain_Two"
	var arrays: Array = (PlaneMesh.new() as PlaneMesh).get_mesh_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	two.mesh = mesh
	_map.add_child(two)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var host := surfaces.glb_map()
	host.call("complete")
	for node in [glass, plain, iron]:
		assert_null(
			(node as MeshInstance3D).get_surface_override_material(0), "%s stays" % node.name
		)
	assert_null(two.material_override, "a two-surface terrain keeps its materials")
	var left: Array[String] = host.call("left_as_authored")
	assert_true(left.size() >= 3, "the pass says what it left: %s" % [left])
	surfaces.release()


func test_a_prop_node_that_carries_an_override_or_is_hidden_is_left_alone() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	var own := _prop("Barrel_Wood", Color(0.4, 0.3, 0.2), false)
	var mine := ShaderMaterial.new()
	own.material_override = mine
	var hidden := _prop("Barrel_Wood", Color(0.4, 0.3, 0.2), false)
	hidden.visible = false
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	surfaces.glb_map().call("complete")
	assert_eq(own.material_override, mine)
	assert_null(own.get_surface_override_material(0))
	assert_null(hidden.get_surface_override_material(0))
	surfaces.release()


func test_a_big_map_is_scanned_over_frames_and_nothing_runs_after() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)
	var shared := BoxMesh.new()
	shared.material = StandardMaterial3D.new()
	shared.material.resource_name = "Crate_Wood"
	for i in 1500:
		var node := MeshInstance3D.new()
		node.name = "Crate_%d" % i
		node.mesh = shared
		_map.add_child(node)
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var host := surfaces.glb_map()
	assert_true(host.call("is_scanning"), "the entry does not wait for 1500 props")
	var frames := 0
	while host.call("is_scanning") and frames < 600:
		await get_tree().process_frame
		frames += 1
	assert_false(host.call("is_scanning"), "the scan finished in %d frames" % frames)
	assert_gt(frames, 1, "spread over frames")
	assert_eq((host.call("props") as Array).size(), 1500)
	var connections := get_tree().process_frame.get_connections().size()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(
		get_tree().process_frame.get_connections().size(), connections, "no per-frame work is left"
	)
	surfaces.release()


func _prop(material_name: String, color: Color, textured: bool) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = material_name + "_Node"
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.albedo_color = color
	if textured:
		material.albedo_texture = ImageTexture.create_from_image(
			Image.create_empty(4, 4, false, Image.FORMAT_RGB8)
		)
	mesh.material = material
	node.mesh = mesh
	_map.add_child(node)
	return node
