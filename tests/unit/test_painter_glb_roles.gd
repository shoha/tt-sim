extends GutTest

## The optional painter-role extras of a GLB map (ASSET_PIPELINE.md "Painter roles", card
## painter-glb-roles): PainterGlbRoles reads tt_paint_role and tt_ground as the one reader, an
## explicit extra beating the name, material and shape rules; an unknown value is ignored with one
## warning line; absent extras change nothing; Classic never reads them; and the extras survive
## the loader. The map is written by glb_roles_fixture.gd and loaded through
## GlbUtils.load_map_async, the path a play load takes.

const FIXTURE := preload("res://tests/unit/glb_roles_fixture.gd")
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}
const PATH := "user://_painter-glb-roles_test.glb"

var _container: Node3D = null
var _map: Node3D = null
var _choice: int = RenderStyle.DEFAULT_CHOICE


func before_each() -> void:
	PainterSheet.clear_cache()
	PainterGlbRoles.forget_unknown()
	_choice = RenderStyle.choice
	_container = Node3D.new()
	add_child_autofree(_container)


func after_each() -> void:
	RenderStyle.choice = _choice
	PainterGlbRoles.forget_unknown()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))


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


## Paints the loaded map and finishes the scan (the fixture supplies the surface arrays).
func _painted() -> PainterSurfaces:
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	surfaces.glb_map().set("surface_arrays", FIXTURE.arrays_of)
	surfaces.glb_map().call("complete")
	assert_engine_error(1, "the fixture's one unknown extra warns once")
	return surfaces


func _node(node_name: String) -> MeshInstance3D:
	return GlbUtils.find_node_by_name(_map, node_name) as MeshInstance3D


func _roles(host: RefCounted, node_name: String) -> Array[String]:
	var out: Array[String] = []
	for record: Array in host.call("props"):
		if str((record[0] as Node).name) == node_name:
			out.append(str((record[4] as Dictionary)["role"]))
	return out


func _zone_of(node_name: String) -> String:
	var ground := _node(node_name).material_override as ShaderMaterial
	if ground == null:
		return "none"
	if not ground.get_shader_parameter(&"glb_zone"):
		return "meadow" if float(ground.get_shader_parameter(&"base_meadow")) > 0.5 else "plain"
	var texture := ground.get_shader_parameter(&"glb_albedo") as Texture2D
	if texture.get_width() > 1:
		return "baked"
	var color := texture.get_image().get_pixel(0, 0)
	return "path" if color.r > color.b + 0.1 else "rock"


# --- the reader, pure ------------------------------------------------------------------------


func test_every_role_value_maps_to_its_dress() -> void:
	var white := Color(0.9, 0.9, 0.9)
	var expect := {"roof": "roof-clay", "bark": "bark", "stone": "stone", "leaf": "leaf", "keep": ""}
	for value: String in expect:
		var role := PainterGlbRoles.prop_role(
			"Window_Glass", "Barrel", white, false, {"tt_paint_role": value}
		)
		assert_eq(role, expect[value], "%s beats the names (a glass name is otherwise kept)" % value)
	for value in ["ground-meadow", "ground-path", "ground-rock"]:
		var extras := {"tt_paint_role": value}
		assert_eq(PainterGlbRoles.ground_mark(extras), 1, value + " marks ground")
		assert_eq(PainterGlbRoles.ground_zone(extras), value.trim_prefix("ground-"))
		assert_eq(
			PainterGlbRoles.prop_role("House_Roof", "House", white, false, extras),
			"roof-clay",
			value + " is no prop role: a prop falls back to its names"
		)
	assert_eq(PainterGlbRoles.ground_mark({"tt_paint_role": "keep"}), -1, "keep is never ground")
	assert_eq(PainterGlbRoles.unknown_logged().size(), 0, "no value of the contract warns")


func test_a_role_value_ignores_case_and_spaces_and_a_bad_value_is_ignored_once() -> void:
	var white := Color(0.9, 0.9, 0.9)
	assert_eq(
		PainterGlbRoles.prop_role("Marble", "n", white, true, {"tt_paint_role": "  Bark "}), "bark"
	)
	var bad := {"tt_paint_role": "wall"}
	assert_eq(
		PainterGlbRoles.prop_role("House_Roof", "n", white, true, bad),
		"roof-clay",
		"an unknown value is read as absent: the name rule answers"
	)
	assert_eq(PainterGlbRoles.prop_role("Marble", "n", white, true, bad), "stone")
	assert_eq(PainterGlbRoles.extra_role({"tt_paint_role": 7}), "", "a non-string is unknown")
	assert_eq(PainterGlbRoles.unknown_logged(), ["tt_paint_role=wall", "tt_paint_role=7"])
	PainterGlbRoles.extra_role(bad)
	assert_eq(PainterGlbRoles.unknown_logged().size(), 2, "one line per distinct value")
	assert_engine_error(2, "a warning line for each of the two values, not for each read")


func test_tt_ground_reads_booleans_numbers_and_words() -> void:
	for yes: Variant in [true, 1, 2.0, "true", " TRUE "]:
		assert_eq(PainterGlbRoles.ground_mark({"tt_ground": yes}), 1, str(yes))
	for no: Variant in [false, 0, "false"]:
		assert_eq(PainterGlbRoles.ground_mark({"tt_ground": no}), -1, str(no))
	assert_eq(PainterGlbRoles.unknown_logged().size(), 0)
	assert_eq(PainterGlbRoles.ground_mark({"tt_ground": "maybe"}), 0, "unknown is absent")
	assert_eq(PainterGlbRoles.ground_mark({"tt_ground": null}), 0)
	assert_eq(PainterGlbRoles.unknown_logged().size(), 2)
	assert_engine_error(2, "one line for each unknown value")
	assert_eq(PainterGlbRoles.ground_mark({}), 0, "absent")
	assert_eq(PainterGlbRoles.ground_zone({}), "")


func test_absent_extras_read_exactly_as_before() -> void:
	var cases := [
		["House_Roof", "House", Color(0.9, 0.9, 0.9), false],
		["Barrel_Wood", "Barrel", Color(0.9, 0.9, 0.9), true],
		["Window_Glass", "House", Color(0.9, 0.9, 0.9), false],
		["Mat_01", "Thing", Color(0.2, 0.5, 0.15), false],
		["Mat_01", "Thing", Color(0.2, 0.5, 0.15), true],
	]
	for c: Array in cases:
		var old := PainterGlbRoles.prop_role(c[0], c[1], c[2], c[3])
		assert_eq(PainterGlbRoles.prop_role(c[0], c[1], c[2], c[3], {}), old)
		assert_eq(
			PainterGlbRoles.prop_role(c[0], c[1], c[2], c[3], {"other": "bark", "tt_wind": 1}),
			old,
			"other keys are not ours"
		)


func test_extras_of_takes_the_most_specific_per_key() -> void:
	var node := Node3D.new()
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	autofree(node)
	assert_eq(PainterGlbRoles.extras_of(node, mesh, material), {}, "none anywhere")
	mesh.set_meta("extras", {"tt_paint_role": "stone", "tt_ground": true, "tt_junk": 1})
	assert_eq(
		PainterGlbRoles.extras_of(node, mesh, material),
		{"tt_paint_role": "stone", "tt_ground": true},
		"the mesh's, and only the keys that are ours"
	)
	node.set_meta("extras", {"tt_paint_role": "leaf"})
	var merged := PainterGlbRoles.extras_of(node, mesh, material)
	assert_eq(merged["tt_paint_role"], "leaf", "node over mesh")
	assert_eq(merged["tt_ground"], true, "a key the node lacks stays the mesh's")
	material.set_meta("extras", {"tt_paint_role": "roof"})
	assert_eq(PainterGlbRoles.extras_of(node, mesh, material)["tt_paint_role"], "roof")
	node.set_meta("extras", "not a dictionary")
	assert_eq(PainterGlbRoles.extras_of(node, null, null), {}, "malformed extras are skipped")


# --- the extras through the loader -------------------------------------------------------------


func test_extras_survive_the_loader_on_nodes_meshes_and_materials() -> void:
	await _world()
	assert_eq(_node("Prop_bark").get_meta("extras"), {"tt_paint_role": "bark"}, "node")
	assert_eq(_node("Ground_Marked").get_meta("extras"), {"tt_ground": true}, "tt_ground")
	assert_eq(
		_node("Ground_OnMesh").mesh.get_meta("extras"), {"tt_paint_role": "ground-path"}, "mesh"
	)
	var split := _node(FIXTURE.SPLIT)
	assert_false(split.mesh.surface_get_material(0).has_meta("extras"))
	assert_eq(
		split.mesh.surface_get_material(1).get_meta("extras"), {"tt_paint_role": "roof"}, "material"
	)
	assert_false(_node(FIXTURE.PLAIN).has_meta("extras"), "a node with none has none")


func test_a_duplicate_group_keeps_its_first_nodes_extras() -> void:
	var mesh := BoxMesh.new()
	var scene := Node3D.new()
	autofree(scene)
	for i in 4:
		var post := MeshInstance3D.new()
		post.name = "Post_%d" % i
		post.mesh = mesh
		if i == 0:
			post.set_meta("extras", {"tt_paint_role": "bark"})
		scene.add_child(post)
	assert_eq(MeshInstancingUtils.process_duplicate_mesh_instancing(scene, 3), 1)
	var group := scene.find_children("*_MultiMesh", "MultiMeshInstance3D", false, false)
	assert_eq(group.size(), 1)
	assert_eq(group[0].get_meta("extras"), {"tt_paint_role": "bark"})


# --- a map with extras, painted ----------------------------------------------------------------


func test_props_wear_the_role_their_extra_names_not_the_one_their_names_say() -> void:
	await _world()
	var surfaces := _painted()
	var host := surfaces.glb_map()
	var expect := {
		"Prop_roof": ["roof-clay"],
		"Prop_bark": ["bark"],
		"Prop_stone": ["stone"],
		"Prop_leaf": ["leaf"],
		"Prop_loud": ["bark"],
		FIXTURE.NODE_OVER_MESH: ["leaf"],
		FIXTURE.MESH_ONLY: ["bark"],
		FIXTURE.SPLIT: ["stone", "roof-clay"],
		FIXTURE.PLAIN: ["bark"],
		FIXTURE.STRAY: ["bark"],
	}
	for node_name: String in expect:
		var want: Array[String] = []
		for role: String in expect[node_name]:
			want.append(role)
		assert_eq(_roles(host, node_name), want, node_name)
	assert_eq(_roles(host, "Prop_keep"), [] as Array[String], "keep stays as authored")
	assert_eq(PainterGlbRoles.unknown_logged(), ["tt_paint_role=wall"], "the stray warned once")
	surfaces.release()


func test_terrain_marked_by_an_extra_is_ground_and_the_shape_rule_can_be_overruled() -> void:
	await _world()
	var surfaces := _painted()
	assert_eq(_zone_of("Ground_Lane"), "path", "a ground-path node")
	assert_eq(_zone_of("Ground_Pad"), "rock", "a ground-rock node")
	assert_eq(_zone_of("Ground_Meadow"), "meadow", "a ground-meadow node")
	assert_eq(_zone_of("Ground_OnMesh"), "path", "a ground role on the mesh")
	var marked := _node("Ground_Marked").material_override as ShaderMaterial
	assert_not_null(marked, "tt_ground alone marks a 5 m slab the shape rule would refuse")
	assert_true(marked.get_shader_parameter(&"world_frame"))
	assert_true(marked in surfaces.ground_materials(), "tokens' feet reach it")
	assert_eq(_zone_of(FIXTURE.WIDE), "meadow", "a wide plane with no extras is ground by shape")
	assert_null(_node(FIXTURE.NOT_GROUND).material_override, "tt_ground false is never ground")
	assert_eq(_roles(surfaces.glb_map(), FIXTURE.NOT_GROUND), ["leaf"] as Array[String], "a prop")
	surfaces.release()


func test_unmarked_multi_surface_terrain_stays_as_authored() -> void:
	await _world()
	var node := _node(FIXTURE.WIDE)
	var plane := PlaneMesh.new()
	plane.size = Vector2(FIXTURE.FIELD_SIZE, FIXTURE.FIELD_SIZE)
	var mesh := ArrayMesh.new()
	for i in 2:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, plane.get_mesh_arrays())
	node.mesh = mesh
	var host := PainterGlbMap.new()
	host.surface_arrays = FIXTURE.arrays_of
	assert_false(host.call("_ground_candidate", node), "two surfaces, no mark: not ground")
	node.set_meta("extras", {"tt_ground": true})
	assert_true(host.call("_ground_candidate", node), "the mark makes it ground")


func test_release_puts_a_role_marked_map_back_and_classic_never_reads_it() -> void:
	await _world()
	var before := {}
	for node in _map.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		before[mesh_node] = [mesh_node.material_override, mesh_node.get_surface_override_material(0)]
	var classic := PainterSurfaces.new()
	assert_null(classic.glb_map(), "no host before a paint: Classic never makes one")
	classic.release()
	for node: MeshInstance3D in before:
		assert_eq(node.material_override, before[node][0], node.name + " untouched by Classic")
		assert_eq(node.get_surface_override_material(0), before[node][1])
	var surfaces := _painted()
	surfaces.release()
	for node: MeshInstance3D in before:
		assert_eq(node.material_override, before[node][0], node.name + " override back")
		assert_eq(node.get_surface_override_material(0), before[node][1], node.name + " surface back")
