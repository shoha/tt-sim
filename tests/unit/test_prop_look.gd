extends GutTest

## How a prop looks in the host (topic props_host): the PROP role (colours procgen painted kept,
## ornament shader with a prop balance), the water of a well or a trough as WATER, cloth that sways
## (market stall awning, valance and apron; every piece of the washing on its own) and the yard a
## building gets but a prop does not.

var _doc: MapDocument = null


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(PaletteLibrary.DEFAULT_ROOT)


func _build(prop_name: String, seed_value: int = 0) -> Dictionary:
	var row := LibraryStructureStore.prop(prop_name, seed_value)
	var size: Array = row["default_size_m"]
	var plan := ProcgenProps.footprint(Vector2(float(size[0]), float(size[1])))
	return StructureGeometry.build_one(_doc, Structure.make(1, String(row["ref"]), plan, 5))


## The tag path of each mesh vertex index with kind `kind`: {tag path: [mesh, vertex]} first hits.
func _cloth_tags(parts: Dictionary) -> Dictionary:
	var out := {}
	var table: PackedStringArray = parts.tag_table
	for mesh: Dictionary in parts.meshes:
		if mesh.kind != "cloth":
			continue
		var tags: PackedInt32Array = mesh.tags
		for v in tags.size():
			var path := table[tags[v]] if tags[v] >= 0 else ""
			if not out.has(path):
				out[path] = []
			(out[path] as Array).append([mesh, v])
	return out


func test_a_prop_node_is_the_prop_role_and_its_water_is_water() -> void:
	assert_eq(StructureLook.role_of_type("prop"), StructureLook.PROP)
	assert_eq(StructureLook.role_of_slot("prop", "prop/well/water"), StructureLook.WATER)
	assert_eq(StructureLook.role_of_slot("prop", "prop/water_trough/water"), StructureLook.WATER)
	assert_eq(StructureLook.role_of_slot("prop", "prop/well/curb"), StructureLook.PROP)
	assert_eq(StructureLook.role_of_tag_path("prop_2/prop/barrel/body"), StructureLook.PROP)
	for kind in ["wood", "stone", "thatch", "accent", "cloth", "glass"]:
		assert_eq(StructureLook.material_role(kind, StructureLook.PROP), StructureLook.PROP, kind)
	assert_true(StructureLook.PROP in StructureLook.ROLES)
	assert_eq(StructureLook.ROLES.back(), StructureLook.PROP, "the new role is last: no digest moves")


func test_a_prop_part_is_drawn_by_the_ornament_shader_with_the_prop_balance() -> void:
	for kind in ["wood", "stone", "thatch", "accent", "cloth"]:
		var material := StructureMaterials.make(kind, StructureLook.PROP, "", "")
		assert_true(material is ShaderMaterial, kind)
		var shader := material as ShaderMaterial
		assert_eq(shader.shader, StructureMaterials.ORNAMENT_SHADER, kind)
		assert_eq(shader.get_shader_parameter("saturation"), StructureMaterials.PROP_SATURATION)
	var cloth := StructureMaterials.make("cloth", StructureLook.PROP, "", "") as ShaderMaterial
	assert_eq(cloth.get_shader_parameter("cloth_wind"), 1.0, "cloth sways")
	var wood := StructureMaterials.make("wood", StructureLook.PROP, "", "") as ShaderMaterial
	assert_eq(wood.get_shader_parameter("cloth_wind"), null, "wood does not")
	var glass := StructureMaterials.make("glass", StructureLook.PROP, "", "") as ShaderMaterial
	assert_eq(glass.shader, StructureMaterials.PANE_SHADER, "a lantern is an unshaded pane")
	var water := StructureMaterials.make("glass", StructureLook.WATER, "", "") as ShaderMaterial
	assert_eq(water.shader, StructureMaterials.WATER_SHADER)


func test_prop_cloth_groups_name_what_sways() -> void:
	for path in [
		"prop_2/prop/market_stall/awning",
		"prop_2/prop/market_stall/valance",
		"prop_2/prop/market_stall/apron",
		"prop_2/prop/laundry_line/cloth",
	]:
		assert_eq(StructureCloth.group_of(path), path)
	for path in [
		"prop_2/prop/market_stall/goods",
		"prop_2/prop/farm_wagon/cover",
		"prop_2/prop/scarecrow/coat",
		"prop_2/prop/market_stall/counter",
	]:
		assert_eq(StructureCloth.group_of(path), "", path)
	# The banner and awning ornaments of a building group as they did.
	assert_eq(
		StructureCloth.group_of("x/ornament/awning0/stripe3"), "x/ornament/awning0"
	)
	assert_eq(StructureCloth.group_of("x/ornament/banner1/cloth"), "x/ornament/banner1/cloth")


func test_a_wide_hanging_piece_hangs_instead_of_flying_as_a_flag() -> void:
	# A towel 0.6 wide and 0.3 tall hung from a line: wider than tall, so a pennant by shape.
	var points := PackedVector3Array(
		[
			Vector3(0.0, 1.5, 0.0),
			Vector3(0.6, 1.5, 0.0),
			Vector3(0.6, 1.2, 0.0),
			Vector3(0.0, 1.2, 0.0),
		]
	)
	var flag := StructureCloth.weights_of(points, false, false)
	assert_eq(flag[0].y, StructureCloth.LEAN_FLAG, "by shape a pennant")
	var hung := StructureCloth.weights_of(points, false, true)
	assert_eq(hung[0].x, 0.0, "the top edge is held")
	assert_almost_eq(float(hung[2].x), 0.3, 0.01, "the hem moves most")
	assert_almost_eq(float(hung[2].y), StructureCloth.LEAN_HANGING, 0.001)


func test_a_market_stall_cloth_carries_weights_and_its_goods_stay_still() -> void:
	var parts := _build("market_stall")
	assert_eq(parts.problem, "")
	assert_eq(parts.dressing, {}, "a prop has no yard")
	var moved := {}
	var still := {}
	for path: String in _cloth_tags(parts):
		var weight := 0.0
		for hit: Array in (_cloth_tags(parts)[path] as Array):
			var arrays: Array = (hit[0] as Dictionary).arrays
			var uv2 := PackedVector2Array()
			if arrays[Mesh.ARRAY_TEX_UV2] != null:
				uv2 = arrays[Mesh.ARRAY_TEX_UV2]
			if int(hit[1]) < uv2.size():
				weight = maxf(weight, uv2[int(hit[1])].x)
		if weight > 0.0:
			moved[path.get_slice("/", path.get_slice_count("/") - 1)] = true
		else:
			still[path.get_slice("/", path.get_slice_count("/") - 1)] = true
	assert_true(moved.has("awning"), "the awning sways: %s" % str(moved.keys()))
	assert_true(moved.has("apron") or moved.has("valance"), "an apron or valance hangs")
	assert_false(moved.has("goods"), "bolts of cloth stay")


func test_every_piece_of_the_washing_moves_on_its_own() -> void:
	var parts := _build("laundry_line", 1)
	assert_eq(parts.problem, "")
	var groups := {}
	var table: PackedStringArray = parts.tag_table
	var tag_group := {}
	for id in table.size():
		var group := StructureCloth.group_of(table[id])
		if group != "":
			tag_group[id] = group
	for mesh: Dictionary in parts.meshes:
		if mesh.kind != "cloth":
			continue
		for v in (mesh.tags as PackedInt32Array).size():
			if tag_group.has(mesh.tags[v]):
				groups[mesh.arrays[Mesh.ARRAY_VERTEX][v]] = true
		var groups_here := StructureCloth._groups_of(mesh, tag_group)
		var pieces := {}
		for group in groups_here:
			if group != "":
				pieces[group] = true
		assert_gt(pieces.size(), 1, "several pieces of washing: %d" % pieces.size())
		var uv2: PackedVector2Array = mesh.arrays[Mesh.ARRAY_TEX_UV2]
		var top := {}
		for v in uv2.size():
			if groups_here[v] != "":
				top[groups_here[v]] = maxf(float(top.get(groups_here[v], 0.0)), uv2[v].x)
		var swinging := 0
		for piece: String in top:
			# A folded or flat piece (the basket's) has no hem to swing and stays still.
			swinging += 1 if float(top[piece]) > 0.05 else 0
			assert_lt(float(top[piece]), 0.9, "not weighed as a whole line: %s" % piece)
		assert_gt(swinging, 2, "the hung washing swings: %d of %d" % [swinging, top.size()])


func test_the_digest_of_a_building_does_not_move_for_the_new_role() -> void:
	var cottage := StructureGeometry.build_one(
		_doc, Structure.make(1, "core:cottage", StructurePlacement.pin_plan({}), 5)
	)
	assert_eq(cottage.problem, "")
	assert_ne(cottage.dressing, {}, "a building keeps its yard")
