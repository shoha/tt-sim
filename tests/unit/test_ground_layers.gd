extends GutTest

## The slot table (GroundLayerTable: which surfaces get the eight slots, the routing, the
## overflow fallback, the weight planes; removed in ground layers card G5) and the index
## ground's binding on a real terrain (G3, GroundLayerBinding): the layer list with the base
## first, the routing rows, the index maps as the document's bytes, partial updates of the
## broad tint (G4), and that updates never replace the material. The tint is checked on its
## CPU mirror.

const BIRCH := "birch_woodland_summer_s1"
const FOREST := "temperate_forest_summer_s1"
const TAIGA := "boreal_taiga_summer_s1"
const ALPINE := "alpine_meadow_summer_s1"
const SAVANNA := "savanna_summer_s1"
const BADLANDS := "rocky_badlands_summer_s1"
const P := GroundLayerTable.Source.PAINTED
const G := GroundLayerTable.Source.GROUND
const R := GroundLayerTable.Source.RULE
const BASE := GroundLayerTable.BASE
const NONE := GroundLayerTable.NONE
const ROLES := {
	"cliff": "cliff",
	"cliff_basalt": "cliff",
	"cliff_sandstone": "cliff",
	"cobblestone": "built",
	"flagstone": "built",
}


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _role(surface: String) -> String:
	return ROLES.get(surface, "ground")


func _inputs(overrides: Dictionary) -> Dictionary:
	var inputs := {
		"base": "grass",
		"biome_ground": PackedStringArray(["grass", "forest_floor", "grass_alpine"]),
		"biome_cliff": PackedStringArray(["cliff", "cliff", "cliff_basalt"]),
		"biome_scree": PackedStringArray(["gravel", "gravel", "gravel"]),
		"biome_coverage": PackedInt64Array([10, 50, 20]),
		"painted": PackedStringArray(["cobblestone"]),
		"base_rules": PackedStringArray(["cliff", "gravel"]),
		"role_of": _role,
		"color_of": func(_s: String) -> Variant: return null,
	}
	inputs.merge(overrides, true)
	return inputs


func _layers(the_plan: Dictionary) -> Array:
	var out := []
	for layer in the_plan.layers:
		out.append([layer.surface, layer.source])
	return out


func test_plan_orders_painted_base_rules_ground_then_other_rules() -> void:
	var the_plan := GroundLayerTable.plan(_inputs({}))
	assert_eq(
		_layers(the_plan),
		[
			["cobblestone", P],
			["cliff", R],
			["gravel", R],
			["forest_floor", G],
			["grass_alpine", G],
			["cliff_basalt", R],
		]
	)
	assert_eq(the_plan.painted_layers, PackedInt32Array([0]))
	# Birch is on the base surface (grass): its density writes nothing.
	assert_eq(the_plan.biome_layers, PackedInt32Array([BASE, BASE, 3, 4]))
	var cliff_of := PackedInt32Array([NONE, NONE, NONE, 1, 5, NONE, NONE, NONE, 1])
	var scree_of := PackedInt32Array([NONE, NONE, NONE, 2, 2, NONE, NONE, NONE, 2])
	assert_eq(the_plan.cliff_of, cliff_of, "forest and the base on cliff, alpine on basalt")
	assert_eq(the_plan.scree_of, scree_of)
	assert_eq(GroundLayerTable.source_mask(the_plan, P), 1)
	assert_eq(GroundLayerTable.source_mask(the_plan, G), (1 << 3) | (1 << 4))
	assert_eq(
		GroundLayerTable.shader_routing(the_plan.cliff_of),
		PackedInt32Array([-1, -1, -1, 1, 5, -1, -1, -1, 1]),
		"the shader reads 8 for the base and -1 for none"
	)


func test_rule_pair_follows_the_most_covered_biome_on_a_surface() -> void:
	# Two biomes on forest_floor with different rock: the better covered one wins.
	var the_plan := (
		GroundLayerTable
		. plan(
			_inputs(
				{
					"biome_ground": PackedStringArray(["forest_floor", "forest_floor"]),
					"biome_cliff": PackedStringArray(["cliff", "cliff_sandstone"]),
					"biome_scree": PackedStringArray(["gravel", "gravel_sandstone"]),
					"biome_coverage": PackedInt64Array([5, 90]),
					"painted": PackedStringArray(),
				}
			)
		)
	)
	var forest := _layers(the_plan).find(["forest_floor", G])
	var drawn: Dictionary = the_plan.layers[the_plan.cliff_of[forest]]
	assert_eq(drawn.surface, "cliff_sandstone")


func test_a_rule_surface_on_the_base_routes_to_the_base() -> void:
	var the_plan := GroundLayerTable.plan(
		_inputs({"base": "gravel", "painted": PackedStringArray()})
	)
	assert_false(_layers(the_plan).has(["gravel", R]), "no slot for the base surface")
	assert_eq(the_plan.scree_of[GroundLayerTable.MAX_LAYERS], BASE)
	var none := GroundLayerTable.plan(
		_inputs(
			{"base_rules": PackedStringArray(["cliff", ""]), "biome_ground": PackedStringArray()}
		)
	)
	assert_eq(none.scree_of[GroundLayerTable.MAX_LAYERS], NONE, "no scree: the ground keeps it")


func test_fixed_slots_keep_their_index_and_a_rule_slot_can_become_ground() -> void:
	var first := GroundLayerTable.plan(_inputs({}))
	# A biome whose ground is gravel arrives: the gravel rule slot becomes its ground slot.
	var second := (
		GroundLayerTable
		. plan(
			_inputs(
				{
					"biome_ground":
					PackedStringArray(["grass", "forest_floor", "grass_alpine", "gravel"]),
					"biome_cliff": PackedStringArray(["cliff", "cliff", "cliff_basalt", "cliff"]),
					"biome_scree": PackedStringArray(["gravel", "gravel", "gravel", ""]),
					"biome_coverage": PackedInt64Array([10, 50, 20, 999]),
				}
			),
			first.layers
		)
	)
	for j in first.layers.size():
		assert_eq(second.layers[j].surface, first.layers[j].surface, "slot %d kept" % j)
	assert_eq(second.layers[2].source, G, "gravel is a ground slot now")
	assert_eq(second.biome_layers[4], 2)
	assert_eq(second.scree_of[3], 2, "scree still routed to the same slot")


func test_overflow_falls_back_by_role_then_colour_and_painted_forces_a_replan() -> void:
	var colors := {
		"grass": Color(0.3, 0.5, 0.2),
		"a": Color(0.5, 0.3, 0.2),
		"b": Color(0.8, 0.8, 0.8),
		"near_a": Color(0.52, 0.31, 0.2),
		"near_grass": Color(0.3, 0.52, 0.21),
		"rock": Color(0.4, 0.4, 0.4),
		"dark_rock": Color(0.2, 0.2, 0.25),
		"near_rock": Color(0.42, 0.4, 0.4),
	}
	var roles := {"rock": "cliff", "dark_rock": "cliff", "near_rock": "cliff"}
	var full := []
	for surface in ["a", "b", "rock", "dark_rock", "c", "d", "e", "f"]:
		(
			full
			. append(
				{
					"surface": surface,
					"source": R if roles.has(surface) else G,
					"role": roles.get(surface, "ground"),
				}
			)
		)
	var inputs := _inputs(
		{
			"biome_ground": PackedStringArray(["near_a", "near_grass"]),
			"biome_cliff": PackedStringArray(["near_rock", "rock"]),
			"biome_scree": PackedStringArray(["", ""]),
			"biome_coverage": PackedInt64Array([10, 5]),
			"painted": PackedStringArray(),
			"base_rules": PackedStringArray(["rock", ""]),
			"role_of": func(s: String) -> String: return roles.get(s, "ground"),
			"color_of": func(s: String) -> Variant: return colors.get(s, null),
		}
	)
	var the_plan := GroundLayerTable.plan(inputs, full)
	assert_eq(the_plan.layers.size(), GroundLayerTable.MAX_LAYERS)
	assert_eq(the_plan.fallbacks.get("near_a"), "a", "nearest ground slot by colour")
	assert_eq(the_plan.fallbacks.get("near_grass"), "", "the base is nearer")
	assert_eq(the_plan.fallbacks.get("near_rock"), "rock", "a cliff falls back to a cliff")
	assert_eq(the_plan.biome_layers, PackedInt32Array([BASE, 0, BASE]))
	assert_eq(the_plan.cliff_of[0], 2, "slot a's rock is drawn as rock")
	assert_false(the_plan.replanned)
	# A painted surface never falls back: the table is replanned with it first.
	inputs.painted = PackedStringArray(["cobblestone"])
	var replanned := GroundLayerTable.plan(inputs, full)
	assert_true(replanned.replanned)
	assert_eq(_layers(replanned)[0], ["cobblestone", P])


func _doc(base: String, biomes: Array) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), base, "test", 11)
	doc.biome_ids = PackedStringArray(biomes)
	var zeros := PackedByteArray()
	zeros.resize(doc.sample_count())
	doc.biome_slots = zeros
	doc.biome_density = zeros.duplicate()
	return doc


func _paint_biome(doc: MapDocument, rect: Rect2i, slot: int, density: int) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := doc.sample_index(x, z)
			doc.biome_slots[i] = slot
			doc.biome_density[i] = density


func _paint_surface(doc: MapDocument, surface: String, rect: Rect2i, weight: int) -> void:
	var slot := doc.ensure_surface(surface)
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			doc.set_surface_weight(doc.sample_index(x, z), slot, weight)


## The broad tint's weight at sample (x, z) (the CPU mirror's alpha).
func _tint_weight(terrain: AuthoredTerrain, x: int, z: int) -> float:
	return terrain.get_broad_tint().get_pixel(x, z).a


func _terrain(doc: MapDocument) -> AuthoredTerrain:
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	return terrain


func test_weight_planes_hold_biome_density_and_painted_weight() -> void:
	var doc := _doc("grass", [FOREST])
	_paint_biome(doc, Rect2i(0, 0, 10, 10), 1, 200)
	_paint_surface(doc, "cobblestone", Rect2i(5, 0, 10, 4), 255)
	# Route the forest to slot 1 and the painted cobblestone to slot 6 (plane B).
	var planes := GroundLayerTable.weight_planes(
		doc, PackedInt32Array([BASE, 1]), PackedInt32Array([6]), Rect2i(0, 0, 20, 20)
	)
	var at := func(plane: int, x: int, z: int) -> PackedByteArray:
		var o := (z * 20 + x) * 4
		return (planes[plane] as PackedByteArray).slice(o, o + 4)
	assert_eq(at.call(0, 2, 2), PackedByteArray([0, 200, 0, 0]), "forest density")
	assert_eq(at.call(1, 12, 2), PackedByteArray([0, 0, 255, 0]), "painted weight in plane B")
	assert_eq(at.call(0, 7, 2), PackedByteArray([0, 200, 0, 0]), "painted over the forest")
	assert_eq(at.call(1, 7, 2), PackedByteArray([0, 0, 255, 0]))
	assert_eq(at.call(0, 15, 15), PackedByteArray([0, 0, 0, 0]))


func test_terrain_binds_the_table_and_its_routing() -> void:
	var doc := _doc("grass", [FOREST, ALPINE])
	_paint_biome(doc, Rect2i(0, 0, 30, 30), 1, 255)
	_paint_biome(doc, Rect2i(40, 40, 30, 30), 2, 255)
	_paint_surface(doc, "cobblestone", Rect2i(60, 0, 20, 5), 255)
	var terrain := _terrain(doc)
	var layers := terrain.ground_layers()
	# The index ground (G3): the base is layer 0, then painted surfaces, then the biomes'.
	assert_eq(layers[0], "grass", "the base first")
	assert_eq(layers[1], "cobblestone", "then the painted surfaces")
	for surface in ["forest_floor", "grass_alpine", "cliff", "cliff_basalt", "gravel"]:
		assert_true(layers.has(surface), "%s has a layer" % surface)
	var material := terrain.get_material()
	var albedo: Texture2DArray = material.get_shader_parameter("layer_albedo_array")
	assert_eq(albedo.get_layers(), GroundLayers.capacity(layers.size()))
	assert_eq((material.get_shader_parameter("layer_tile_m") as PackedFloat32Array).size(), 64)
	var paint_layer: PackedInt32Array = material.get_shader_parameter("paint_layer")
	assert_eq(paint_layer[0], 1, "document surface 0 draws as layer 1")
	var flags: PackedInt32Array = material.get_shader_parameter("layer_flags")
	assert_eq(flags[layers.find("cliff")], GroundLayers.FLAG_CLIFF)
	assert_eq(flags[1], GroundLayers.FLAG_BUILT)
	# Rows by biome slot: (ground, cliff, scree, bed); row 0 the base.
	var rules: PackedInt32Array = material.get_shader_parameter("biome_rules")
	assert_eq(layers[rules[2 * 4 + 1]], "cliff_basalt", "alpine ground dressed with basalt")
	assert_eq(layers[rules[1]], "cliff", "grass (the base) dressed like the wetland: cliff")
	assert_eq(rules[0], GroundLayerBinding.AS_BASE, "row 0 draws as the base")
	assert_eq(layers[rules[1 * 4]], "forest_floor", "the forest's ground")
	var binding := terrain.layer_binding()
	var index := binding.index_image("paint_index_map").get_data()
	assert_eq(index, doc.surface_plane(MapDocument.SURFACE_INDEX_PLANE), "the document's bytes")
	assert_not_null(binding.index_texture("paint_index_map"), "bound as a texture")
	var slots := binding.index_image("biome_slots_map").get_data()
	assert_eq(slots, doc.biome_slots, "uploaded verbatim")
	assert_eq(material.get_shader_parameter("biome_present"), 1)
	assert_eq(material.get_shader_parameter("paint_present"), 1)
	var trample := GroundBroadTint.TRAMPLE_WEIGHT
	assert_almost_eq(_tint_weight(terrain, 70, 2), trample, 1e-6, "a trampled path tints")
	assert_almost_eq(_tint_weight(terrain, 10, 10), 1.0, 1e-6, "the forest's ground tints")
	assert_engine_error(0, "every accent drawn")


func test_partial_update_touches_only_the_rect_and_matches_full() -> void:
	var doc := _doc("grass", [FOREST, TAIGA])
	_paint_biome(doc, Rect2i(0, 0, 40, 40), 1, 180)
	_paint_surface(doc, "flagstone", Rect2i(0, 0, 2, 2), 255)
	var terrain := _terrain(doc)
	var before := terrain.get_broad_tint().get_data()
	var texture := terrain.get_broad_texture()
	var rect := Rect2i(20, 20, 13, 13)
	_paint_biome(doc, Rect2i(25, 25, 20, 20), 2, 255)
	_paint_biome(doc, Rect2i(80, 80, 5, 5), 1, 90)
	_paint_surface(doc, "flagstone", Rect2i(30, 30, 3, 3), 128)
	terrain.update_ground_region(rect)
	assert_eq(terrain.get_broad_texture(), texture, "the map is updated in place")
	var fresh := _terrain(doc)
	var after := terrain.get_broad_tint().get_data()
	var full := fresh.get_broad_tint().get_data()
	var inside_ok := true
	var outside_ok := true
	var bytes := GroundBroadTint.CHANNELS * 4
	for z in doc.samples_z():
		for x in doc.samples_x():
			var o := (z * doc.samples_x() + x) * bytes
			if rect.has_point(Vector2i(x, z)):
				inside_ok = inside_ok and after.slice(o, o + bytes) == full.slice(o, o + bytes)
			else:
				outside_ok = outside_ok and after.slice(o, o + bytes) == before.slice(o, o + bytes)
	assert_true(inside_ok, "the rect matches a full recompute")
	assert_true(outside_ok, "nothing outside the rect changed")
	# The index maps are the document's, whole, after any update.
	var weights := terrain.layer_binding().index_image("paint_weight_map")
	assert_eq(weights.get_data(), doc.surface_plane(MapDocument.SURFACE_WEIGHT_PLANE))
	var density := terrain.layer_binding().index_image("biome_density_map")
	assert_eq(density.get_data(), doc.biome_density, "even outside the rect")
	terrain.update_ground_region(Rect2i(-10, -10, 1000, 1000))
	assert_eq(terrain.get_broad_tint().get_data(), fresh.get_broad_tint().get_data())
	assert_engine_error(0, "every accent drawn")


func test_new_biome_or_surface_mid_session_keeps_every_slot() -> void:
	var doc := _doc("grass", [FOREST])
	_paint_biome(doc, Rect2i(0, 0, 10, 10), 1, 255)
	var terrain := _terrain(doc)
	var material := terrain.get_material()
	var albedo: Texture2DArray = material.get_shader_parameter("layer_albedo_array")
	var index: Texture2D = material.get_shader_parameter("paint_index_map")
	var first := terrain.ground_layers()
	doc.biome_ids.append(TAIGA)
	_paint_biome(doc, Rect2i(50, 50, 30, 30), 2, 255)
	terrain.update_ground_region(Rect2i(50, 50, 30, 30))
	_paint_surface(doc, "planks", Rect2i(5, 60, 5, 5), 255)
	terrain.update_ground_region(Rect2i(5, 60, 5, 5))
	var now := terrain.ground_layers()
	# Every layer stays put (painting never rebinds); the new surfaces append, and within the
	# arrays' capacity they go in as new layers of the same textures.
	assert_eq(now.slice(0, first.size()), first, "every layer kept")
	assert_true(now.find("pine_duff") >= first.size(), "the taiga's ground appended")
	assert_true(now.find("planks") >= first.size(), "the planks appended")
	assert_engine_error(0, "every accent drawn")
	assert_eq(terrain.get_material(), material, "same material")
	assert_eq(material.get_shader_parameter("layer_albedo_array"), albedo, "same layer arrays")
	assert_eq(material.get_shader_parameter("paint_index_map"), index, "same index texture")
	var planks: Color = terrain.layer_binding().paint_tints[doc.surface_ids.find("planks")]
	assert_gt(planks.a, 0.0, "planks are built: a trodden fringe")
	assert_almost_eq(_tint_weight(terrain, 60, 60), 1.0, 1e-6, "the taiga tints")
	assert_almost_eq(_tint_weight(terrain, 6, 61), planks.a, 1e-6, "the planks tint")
	for cell in terrain.chunk_cells():
		assert_eq(terrain.get_chunk(cell).mesh.surface_get_material(0), material)


func test_six_biomes_draw_every_surface_without_a_warning() -> void:
	# Grass base; six biomes with distinct grounds plus their rock, scree and accents: the
	# eight-slot table overflowed here (ten warnings); the index ground draws them all.
	var biomes := [FOREST, TAIGA, ALPINE, BADLANDS, SAVANNA, BIRCH]
	var doc := _doc("grass", biomes)
	for index in biomes.size():
		_paint_biome(doc, Rect2i((index % 5) * 20, (index / 5) * 40, 20, 20), index + 1, 255)
	_paint_surface(doc, "cobblestone", Rect2i(0, 100, 5, 5), 255)
	_paint_surface(doc, "flagstone", Rect2i(10, 100, 5, 5), 255)
	var terrain := _terrain(doc)
	doc.biome_ids.append("wetland_riparian_summer_s1")
	terrain.update_ground_region(Rect2i(0, 0, 40, 40))
	assert_engine_error(0, "no surface falls back, no accent drops")
	var layers := terrain.ground_layers()
	assert_eq(layers[1], "cobblestone", "painted surfaces keep their layers")
	assert_eq(layers[2], "flagstone")
	var binding := terrain.layer_binding()
	assert_false(binding.overflowed())
	for surface in ["grass_birch", "cliff_basalt", "cliff_sandstone", "gravel_sandstone"]:
		assert_true(layers.has(surface), "%s drawn as itself" % surface)


func test_broad_textures_follow_the_weights() -> void:
	var doc := _doc("grass", [FOREST])
	var terrain := _terrain(doc)
	var broad := terrain.get_broad_texture()
	var material := terrain.get_material()
	assert_eq(material.get_shader_parameter("broad_tint_map"), broad)
	assert_eq(material.get_shader_parameter("broad_present"), 1, "the forest is a tint")
	_paint_biome(doc, Rect2i(0, 0, 40, 40), 1, 255)
	terrain.update_ground_region(Rect2i(0, 0, 40, 40))
	assert_eq(material.get_shader_parameter("broad_tint_map"), broad, "in place")
	var expected := GroundBroadTint.broad_image(terrain.get_broad_tint())
	assert_eq(expected.get_format(), Image.FORMAT_RGBAH)
	assert_eq(broad.get_format(), Image.FORMAT_RGBAH)
	assert_gt(expected.get_pixel(1, 1).a, 0.9, "the painted corner reads broad")
	var f := GroundBroadTint.BROAD_FACTOR
	assert_eq(GroundBroadTint.broad_size(Vector2i(10 * f + 1, 3 * f)), Vector2i(11, 3))
	assert_eq(GroundBroadTint.broad_size(Vector2i(3, 3)), Vector2i.ONE, "never empty")


func test_biome_coverage_sums_density_per_biome() -> void:
	var slots := PackedByteArray([1, 1, 2, 2, 2, 3, 0])
	var density := PackedByteArray([255, 255, 100, 100, 100, 255, 255])
	assert_eq(GroundLayerTable.biome_coverage(slots, density, 3), PackedInt64Array([510, 300, 255]))
