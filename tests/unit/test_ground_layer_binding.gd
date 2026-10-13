extends GutTest

## The index ground's binding (ground layers card G3): GroundLayerArrays' stable appends and
## capacity steps, GroundLayerBinding's pure packing (the shader's routing rows, broad tints,
## padded tiles) and its parity rules, and a crowded real map (three biomes and a burnt forest
## patch with ash) on which every accent is drawn.

const FOREST := "temperate_forest_summer_s1"
const TAIGA := "boreal_taiga_summer_s1"
const ALPINE := "alpine_meadow_summer_s1"
const BURNT := "burnt_forest_summer_s1"


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


## Surface names the palette does not have: their layers are small solid stand-ins, so the
## capacity steps can be checked past the palette's 29 surfaces, and quickly.
func _names(count: int, prefix: String = "absent") -> PackedStringArray:
	var out := PackedStringArray()
	for i in count:
		out.append("%s_%d" % [prefix, i])
	return out


func test_arrays_append_in_place_and_grow_by_capacity_steps() -> void:
	var arrays := GroundLayerArrays.new()
	assert_true(arrays.sync(_names(3), PaletteLibrary.DEFAULT_ROOT), "first build creates")
	assert_eq(arrays.capacity, 16)
	var albedo: Texture2DArray = arrays.textures.albedo
	assert_eq(albedo.get_layers(), 16, "padded to the capacity")
	assert_false(arrays.sync(_names(5), PaletteLibrary.DEFAULT_ROOT), "an append within it")
	assert_eq(arrays.textures.albedo, albedo, "the same textures")
	assert_eq(arrays.layers, _names(5))
	assert_true(arrays.sync(_names(17), PaletteLibrary.DEFAULT_ROOT), "past 16 recreates")
	assert_eq(arrays.capacity, 32)
	assert_eq((arrays.textures.albedo as Texture2DArray).get_layers(), 32)
	assert_true(arrays.sync(_names(33), PaletteLibrary.DEFAULT_ROOT))
	assert_eq(arrays.capacity, 64)
	assert_false(arrays.sync(_names(64), PaletteLibrary.DEFAULT_ROOT), "64 fits in place")
	var other := _names(3, "moved")
	assert_true(arrays.sync(other, PaletteLibrary.DEFAULT_ROOT), "a changed layer recreates")
	assert_eq(arrays.capacity, 16, "a compacted list shrinks back")
	assert_eq(GroundLayers.capacity(65), GroundLayers.MAX_LAYERS)


func test_the_base_is_layer_zero_with_the_palette_maps() -> void:
	var arrays := GroundLayerArrays.new()
	arrays.sync(PackedStringArray(["grass", "cliff"]), PaletteLibrary.DEFAULT_ROOT)
	for kind in GroundLayerArrays.KINDS:
		var image := GroundLayerArrays.surface_image("grass", kind, PaletteLibrary.DEFAULT_ROOT)
		var array: Texture2DArray = arrays.textures[kind]
		assert_not_null(image, kind)
		assert_eq(array.get_format(), image.get_format(), "%s keeps the palette format" % kind)
		assert_eq(array.get_width(), image.get_width())
		assert_true(array.has_mipmaps())


func test_shader_tables_pack_rows_and_accents() -> void:
	var routing := {
		"ground": PackedInt32Array([0, 4, 0, 6]),
		"cliff": PackedInt32Array([2, 5, -1, 7]),
		"scree": PackedInt32Array([3, -1, -1, 3]),
		"bed": PackedInt32Array([-1, -1, -1, 8]),
		"shore": PackedInt32Array([-1, -1, -1, 9]),
		"accent_entries":
		[
			[{"layer": 10, "surface": "moss", "coverage": 0.2, "scale_m": 6.0}],
			[],
			[],
			[
				{"layer": 11, "surface": "dirt", "coverage": 0.1, "scale_m": 4.0},
				{"layer": 10, "surface": "moss", "coverage": 0.1, "scale_m": 8.0},
			],
		],
	}
	var tables := GroundLayerBinding.shader_tables(routing, PackedByteArray([0, 1, 0]), 7)
	var rules: PackedInt32Array = tables.biome_rules
	var extra: PackedInt32Array = tables.biome_extra
	var params: PackedVector4Array = tables.accent_params
	assert_eq(rules.size(), GroundLayerBinding.ROWS * 4)
	assert_eq(rules.slice(0, 4), PackedInt32Array([-1, 2, 3, -1]), "row 0 draws as the base")
	assert_eq(rules.slice(4, 8), PackedInt32Array([4, 5, -1, -1]), "biome 1 on its ground")
	assert_eq(rules[8], GroundLayerBinding.AS_BASE, "biome 2 is on the base surface")
	assert_eq(rules.slice(12, 16), PackedInt32Array([6, 7, 3, 8]))
	assert_eq(extra.slice(0, 4), PackedInt32Array([-1, 10, -1, -1]), "the base's accent")
	assert_eq(extra.slice(12, 16), PackedInt32Array([9, 11, 10, -1]), "shore, two accents")
	assert_eq(rules.slice(16, 20), PackedInt32Array([-1, -1, -1, -1]), "unused rows")
	assert_eq(tables.accent_present, 1)
	assert_eq(params.size(), GroundLayerBinding.ACCENT_ENTRIES)
	var expected := GroundAccents.row_params(routing.accent_entries[3], 7)
	assert_eq(params[9], expected[0], "row 3's first accent at entry 9")
	assert_eq(params[10], expected[1])
	assert_almost_eq(params[9].y, 1.0 / 4.0, 1e-6, "1 / scale_m")
	assert_eq(GroundLayerBinding.shader_tables({}, PackedByteArray(), 0).accent_present, 0)


func test_tint_tables_tint_biome_grounds_and_built_paint_without_a_slot_limit() -> void:
	var grounds := _names(12)
	grounds[1] = ""
	var layer_of := func(surface: String) -> int: return 20 if surface == "planks" else 3
	var tables := GroundLayerBinding.tint_tables(
		grounds,
		PackedStringArray(["moss", "planks"]),
		func(surface: String) -> String: return "built" if surface == "planks" else "ground",
		layer_of,
		func(surface: String) -> Color:
			return Color(0.5, 0.25, 0.1) if surface == "planks" else Color(0.2, 0.4, 0.1)
	)
	var biomes: PackedColorArray = tables.biome
	assert_eq(biomes.size(), 13, "slot 0 and every biome: no slot limit")
	assert_eq(biomes[0].a, 0.0, "no biome, no tint")
	assert_eq(biomes[1], Color(0.2, 0.4, 0.1, 1.0), "a biome ground tints at weight 1")
	assert_eq(biomes[2].a, 0.0, "a biome drawn as the base does not")
	var paints: PackedColorArray = tables.paint
	assert_eq(paints[0].a, 0.0, "painted ground does not tint")
	assert_eq(paints[1], Color(0.5, 0.25, 0.1, GroundBroadTint.TRAMPLE_WEIGHT), "built does")
	var per_layer: PackedVector4Array = tables.layer
	assert_eq(per_layer.size(), GroundLayers.MAX_LAYERS)
	assert_eq(per_layer[20], Vector4(0.5, 0.25, 0.1, GroundBroadTint.TRAMPLE_WEIGHT))
	assert_eq(per_layer[3], Vector4(0.2, 0.4, 0.1, 0.0), "a ground: its colour, no paint weight")


func test_padded_tiles_fill_the_shader_array() -> void:
	var tiles := GroundLayerBinding.padded_tiles(
		PackedStringArray(["a", "b"]),
		func(surface: String) -> Variant: return 3.5 if surface == "a" else null
	)
	assert_eq(tiles.size(), GroundLayers.MAX_LAYERS)
	assert_almost_eq(tiles[0], 3.5, 1e-6)
	assert_almost_eq(tiles[1], GroundLayers.DEFAULT_TILE_M, 1e-6)
	assert_almost_eq(tiles[63], GroundLayers.DEFAULT_TILE_M, 1e-6)


## The base row takes the rules and accents of the most covered biome on the base surface,
## and such a biome draws as the base, as the slot table had it.
func test_a_biome_on_the_base_surface_draws_as_the_base() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "forest_floor", "test", 3)
	doc.biome_ids = PackedStringArray([FOREST, TAIGA])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(1)
	doc.biome_slots = slots
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_density = density
	var inputs := GroundLayerBinding.gather_inputs(doc, PaletteLibrary.DEFAULT_ROOT, false)
	assert_eq(inputs.as_base, PackedByteArray([1, 0]), "the forest's ground is the base")
	assert_eq(inputs.biome_ground[0], "", "its own row is blank")
	var forest := PaletteLibrary.biome(FOREST)
	assert_eq(
		inputs.base_rules[0], String(forest.get("cliff_surface", "")), "its rock dresses the base"
	)
	var accents := GroundAccents.surface_names(inputs.base_accents)
	var listed := GroundAccents.surface_names(forest.get("ground_accents", []))
	assert_eq(accents, listed.slice(0, accents.size()), "and its accents")


@warning_ignore("integer_division")
func _crowded_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(30, 30), "grass_birch", "test", 5)
	doc.biome_ids = PackedStringArray([FOREST, TAIGA, ALPINE, BURNT])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			# Three bands of biome, a burnt patch over the forest's band.
			slots[i] = 1 + mini(3 * x / doc.samples_x(), 2)
			if x < 20 and z < 20:
				slots[i] = 4
			density[i] = 255
	doc.biome_slots = slots
	doc.biome_density = density
	var ash := doc.ensure_surface("ash")
	for z in 24:
		for x in 24:
			doc.set_surface_weight(doc.sample_index(x, z), ash, 200)
	return doc


func test_three_biomes_and_a_burnt_patch_draw_every_accent() -> void:
	var doc := _crowded_doc()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	assert_engine_error(0, "no surface falls back and no accent drops")
	var layers := terrain.ground_layers()
	var binding := terrain.layer_binding()
	var rows: Array = binding.routing.accent_entries
	var extra: PackedInt32Array = terrain.get_material().get_shader_parameter("biome_extra")
	var drawn := 0
	for b in doc.biome_ids.size():
		var biome := PaletteLibrary.biome(doc.biome_ids[b])
		var own := String(biome.get("ground_surface", ""))
		if own == doc.base_surface:
			continue
		var wanted := PackedStringArray()
		for accent in biome.get("ground_accents", []):
			var surface := String(accent.surface)
			if surface != own and not surface in wanted and float(accent.coverage) > 0.0:
				wanted.append(surface)
		wanted = wanted.slice(0, GroundLayers.ACCENTS_PER_BIOME)
		var row: Array = rows[b + 1]
		assert_eq(row.size(), wanted.size(), "%s draws all its accents" % doc.biome_ids[b])
		for i in wanted.size():
			assert_true(layers.has(wanted[i]), "%s has a layer" % wanted[i])
			assert_eq(
				layers[extra[(b + 1) * 4 + 1 + i]], wanted[i], "row %d accent %d" % [b + 1, i]
			)
			drawn += 1
	assert_true(drawn >= 6, "a crowded map: %d accents" % drawn)
	assert_true(layers.has("ash"), "the painted ash")
	assert_true(layers.has("dirt"), "the burnt forest's dirt accent (dropped by the slot table)")
