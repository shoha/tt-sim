extends GutTest

## Biome ground (AuthoredTerrain + BiomeGroundLayers): the RGBA8 weight map the ground
## shader blends biome surfaces by, its partial updates, layer assignment (shared
## surfaces, base-surface biomes, overflow past four surfaces) and that updates never
## replace the material. Weights are checked on the CPU mirror: headless runs cannot read
## the GPU texture back.

const BIRCH := "birch_woodland_summer_s1"
const GRASSLAND := "grassland_meadow_summer_s1"
const WETLAND := "wetland_riparian_summer_s1"
const FOREST := "temperate_forest_summer_s1"
const TAIGA := "boreal_taiga_summer_s1"
const ALPINE := "alpine_meadow_summer_s1"
const SAVANNA := "savanna_summer_s1"
const BADLANDS := "rocky_badlands_summer_s1"


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _doc(base: String, biomes: Array) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), base, "test", 11)
	doc.biome_ids = PackedStringArray(biomes)
	var zeros := PackedByteArray()
	zeros.resize(doc.sample_count())
	doc.biome_slots = zeros
	doc.biome_density = zeros.duplicate()
	return doc


func _paint(doc: MapDocument, rect: Rect2i, slot: int, density: int) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var i := doc.sample_index(x, z)
			doc.biome_slots[i] = slot
			doc.biome_density[i] = density


func _texel(terrain: AuthoredTerrain, x: int, z: int) -> PackedByteArray:
	var data := terrain.get_biome_weights().get_data()
	var offset := (z * terrain.document.samples_x() + x) * 4
	return data.slice(offset, offset + 4)


func _terrain(doc: MapDocument) -> AuthoredTerrain:
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	return terrain


func test_shared_surfaces_share_a_channel() -> void:
	# Birch and grassland both use "grass"; temperate forest uses "forest_floor".
	var doc := _doc("sand", [BIRCH, GRASSLAND, FOREST])
	_paint(doc, Rect2i(0, 0, 10, 10), 1, 200)
	_paint(doc, Rect2i(10, 0, 10, 10), 2, 100)
	_paint(doc, Rect2i(0, 20, 4, 4), 3, 255)
	var terrain := _terrain(doc)
	assert_eq(terrain.ground_layers(), PackedStringArray(["grass", "forest_floor"]))
	assert_eq(terrain.get_material().get_shader_parameter("biome_layer_count"), 2)
	var weights := terrain.get_biome_weights()
	assert_eq(
		weights.get_size(), Vector2i(doc.samples_x(), doc.samples_z()), "one texel per sample"
	)
	assert_eq(weights.get_format(), Image.FORMAT_RGBA8)
	assert_eq(_texel(terrain, 3, 3), PackedByteArray([200, 0, 0, 0]), "birch -> grass channel")
	assert_eq(_texel(terrain, 12, 3), PackedByteArray([100, 0, 0, 0]), "grassland -> same channel")
	assert_eq(_texel(terrain, 1, 21), PackedByteArray([0, 255, 0, 0]), "forest -> its own channel")
	assert_eq(_texel(terrain, 50, 50), PackedByteArray([0, 0, 0, 0]), "unpainted")


func test_layers_follow_coverage_then_first_appearance() -> void:
	var slots := PackedByteArray([1, 1, 2, 2, 2, 3, 0])
	var density := PackedByteArray([255, 255, 100, 100, 100, 255, 255])
	var coverage := BiomeGroundLayers.coverage(slots, density, PackedStringArray(["x", "y", "x"]))
	assert_eq(coverage, {"x": 765, "y": 300}, "density summed per surface over its biomes")
	var ranked := BiomeGroundLayers.plan(
		PackedStringArray(["y", "x"]), "base", coverage, func(_s: String) -> Variant: return null
	)
	assert_eq(ranked["layers"], PackedStringArray(["x", "y"]), "more coverage first")
	var surfaces := PackedStringArray(["a", "b"])
	var plan := BiomeGroundLayers.plan(
		surfaces, "base", {}, func(_s: String) -> Variant: return null
	)
	assert_eq(plan["layers"], surfaces, "ties keep first appearance")


func test_base_surface_biomes_contribute_nothing() -> void:
	# Grassland's ground is the base surface; an unknown biome has no ground at all.
	var doc := _doc("grass", [GRASSLAND, FOREST, "no_such_biome"])
	_paint(doc, Rect2i(0, 0, 30, 30), 1, 255)
	_paint(doc, Rect2i(40, 40, 5, 5), 2, 255)
	_paint(doc, Rect2i(60, 60, 5, 5), 3, 255)
	var terrain := _terrain(doc)
	assert_eq(terrain.ground_layers(), PackedStringArray(["forest_floor"]))
	assert_eq(_texel(terrain, 10, 10), PackedByteArray([0, 0, 0, 0]), "base-surface biome")
	assert_eq(_texel(terrain, 62, 62), PackedByteArray([0, 0, 0, 0]), "unknown biome")
	assert_eq(_texel(terrain, 42, 42), PackedByteArray([255, 0, 0, 0]))
	var only_base := _terrain(_doc("grass", [GRASSLAND, WETLAND]))
	assert_eq(only_base.ground_layers().size(), 0)
	assert_eq(only_base.get_material().get_shader_parameter("biome_layer_count"), 0)


func test_partial_update_touches_only_the_rect_and_matches_full() -> void:
	var doc := _doc("grass", [FOREST, TAIGA])
	_paint(doc, Rect2i(0, 0, 40, 40), 1, 180)
	var terrain := _terrain(doc)
	var before := terrain.get_biome_weights().get_data()
	var rect := Rect2i(20, 20, 13, 13)
	# Change samples inside and outside the rect; only the rect is pushed.
	_paint(doc, Rect2i(25, 25, 20, 20), 2, 255)
	_paint(doc, Rect2i(80, 80, 5, 5), 1, 90)
	terrain.update_biome_region(rect)
	var after := terrain.get_biome_weights().get_data()
	var fresh := _terrain(doc).get_biome_weights().get_data()
	var inside_ok := true
	var outside_ok := true
	var changed_inside := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var o := (z * doc.samples_x() + x) * 4
			var got := after.slice(o, o + 4)
			if rect.has_point(Vector2i(x, z)):
				inside_ok = inside_ok and got == fresh.slice(o, o + 4)
				if got != before.slice(o, o + 4):
					changed_inside += 1
			else:
				outside_ok = outside_ok and got == before.slice(o, o + 4)
	assert_true(inside_ok, "the rect matches a full recompute")
	assert_true(outside_ok, "nothing outside the rect changed")
	assert_eq(changed_inside, 8 * 8, "the painted part of the rect changed")
	terrain.update_biome_region(Rect2i(-10, -10, 1000, 1000))
	assert_eq(terrain.get_biome_weights().get_data(), fresh, "clipped full update matches")


func test_new_biome_mid_session_takes_a_free_layer() -> void:
	var doc := _doc("grass", [FOREST])
	_paint(doc, Rect2i(0, 0, 10, 10), 1, 255)
	var terrain := _terrain(doc)
	assert_eq(terrain.ground_layers(), PackedStringArray(["forest_floor"]))
	doc.biome_ids.append(TAIGA)
	_paint(doc, Rect2i(50, 50, 30, 30), 2, 255)
	terrain.update_biome_region(Rect2i(50, 50, 30, 30))
	assert_eq(
		terrain.ground_layers(),
		PackedStringArray(["forest_floor", "pine_duff"]),
		"the existing layer keeps its channel although the new one covers more"
	)
	assert_eq(_texel(terrain, 60, 60), PackedByteArray([0, 255, 0, 0]))
	assert_eq(_texel(terrain, 5, 5), PackedByteArray([255, 0, 0, 0]))


func test_updates_never_replace_the_material() -> void:
	var doc := _doc("grass", [FOREST])
	var terrain := _terrain(doc)
	var material := terrain.get_material()
	var albedo: Texture2D = material.get_shader_parameter("albedo_tex")
	var weights: Texture2D = material.get_shader_parameter("biome_weights")
	assert_true(weights is DrawableTexture2D, "weights bound at build")
	_paint(doc, Rect2i(0, 0, 10, 10), 1, 255)
	terrain.update_biome_region(Rect2i(0, 0, 10, 10))
	doc.biome_ids.append(ALPINE)
	_paint(doc, Rect2i(20, 20, 10, 10), 2, 255)
	terrain.update_biome_region(Rect2i(20, 20, 10, 10))
	assert_eq(terrain.get_material(), material, "same material")
	assert_eq(material.get_shader_parameter("albedo_tex"), albedo, "base still bound")
	assert_eq(material.get_shader_parameter("biome_weights"), weights, "same weight texture")
	assert_eq(material.get_shader_parameter("biome_layer_count"), 2)
	var layer_albedo: Array = material.get_shader_parameter("layer_albedo")
	assert_eq(layer_albedo.size(), BiomeGroundLayers.MAX_LAYERS, "every layer entry bound")
	var surfaces := PaletteLibrary.surfaces()
	assert_eq(
		(layer_albedo[1] as Texture2D).resource_path,
		PaletteLibrary.DEFAULT_ROOT.path_join(surfaces["grass_alpine"]["albedo"])
	)
	assert_almost_eq(
		(material.get_shader_parameter("layer_tile_m") as Vector4).y,
		float(surfaces["grass_alpine"]["tile_m"]),
		1e-4
	)
	for cell in terrain.chunk_cells():
		assert_eq(terrain.get_chunk(cell).mesh.surface_get_material(0), material)


func test_overflow_falls_back_to_the_nearest_colour() -> void:
	var colors := {
		"base": Color(0.3, 0.45, 0.15),
		"a": Color(0.5, 0.3, 0.2),
		"b": Color(0.8, 0.8, 0.8),
		"c": Color(0.2, 0.2, 0.6),
		"d": Color(0.7, 0.4, 0.2),
		"near_a": Color(0.52, 0.31, 0.2),
		"near_base": Color(0.3, 0.47, 0.16),
	}
	var color_of := func(surface: String) -> Variant: return colors.get(surface, null)
	var surfaces := PackedStringArray(["a", "b", "near_a", "c", "d", "near_base", "unknown"])
	var coverage := {"a": 90, "b": 80, "c": 70, "d": 60, "near_a": 5, "near_base": 4, "unknown": 3}
	var plan := BiomeGroundLayers.plan(surfaces, "base", coverage, color_of)
	assert_eq(plan["layers"], PackedStringArray(["a", "b", "c", "d"]), "best covered keep layers")
	assert_eq(plan["fallbacks"], {"near_a": "a", "near_base": "", "unknown": ""})
	assert_eq(
		plan["slot_layers"],
		PackedInt32Array([BiomeGroundLayers.BASE, 0, 1, 0, 2, 3, BiomeGroundLayers.BASE, -1])
	)


func test_overflow_in_a_real_document_warns_and_reuses_a_layer() -> void:
	# Five distinct non-grass surfaces: savanna is painted least, so it overflows.
	var biomes := [FOREST, TAIGA, ALPINE, BADLANDS, SAVANNA]
	var doc := _doc("grass", biomes)
	for index in 4:
		_paint(doc, Rect2i(index * 20, 0, 20, 20), index + 1, 255)
	_paint(doc, Rect2i(0, 60, 4, 4), 5, 255)
	var terrain := _terrain(doc)
	# Painting more of it later does not warn again.
	terrain.update_biome_region(Rect2i(0, 60, 4, 4))
	assert_engine_error(1, "one warning naming the overflowed surface")
	var layers := terrain.ground_layers()
	assert_eq(layers.size(), BiomeGroundLayers.MAX_LAYERS)
	assert_false(layers.has("grass_savanna"))
	var nearest := BiomeGroundLayers.nearest_surface(
		"grass_savanna",
		layers,
		"grass",
		func(surface: String) -> Variant: return AuthoredTerrain.surface_mean_albedo(surface)
	)
	var expected := PackedByteArray([0, 0, 0, 0])
	if nearest != "":
		expected[layers.find(nearest)] = 255
	assert_eq(_texel(terrain, 1, 61), expected, "savanna drawn as %s" % nearest)


func test_mean_albedo_reads_the_palette() -> void:
	var snow: Color = AuthoredTerrain.surface_mean_albedo("snow")
	var grass: Color = AuthoredTerrain.surface_mean_albedo("grass")
	assert_gt(snow.v, 0.8, "snow is bright")
	assert_gt(grass.g, grass.r, "grass is green")
	assert_null(AuthoredTerrain.surface_mean_albedo("no_such_surface"))
