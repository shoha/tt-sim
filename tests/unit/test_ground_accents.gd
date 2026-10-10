extends GutTest

## Ground accents (GroundAccents, GroundLayerTable's accent slots, AuthoredTerrain's accent
## uniforms): patch coverage of the CPU twin of the shader's mask, the order-aware coverage
## split, the uniform packing, slot allocation (last, never holding a slot against anything
## else, dropping by priority then coverage), and that the shader mirrors every constant.

const SHADER_PATH := "res://shaders/authored_ground.gdshaderinc"
const FOREST := "temperate_forest_summer_s1"
const TAIGA := "boreal_taiga_summer_s1"
const P := GroundLayerTable.Source.PAINTED
const G := GroundLayerTable.Source.GROUND
const R := GroundLayerTable.Source.RULE
const A := GroundLayerTable.Source.ACCENT
const BASE := GroundLayerTable.BASE
const NONE := GroundLayerTable.NONE
const ROLES := {"cliff": "cliff", "cliff_basalt": "cliff", "cobblestone": "built"}
## (shader constant, GroundAccents constant)
const MIRRORED := [
	["ACCENTS_PER_COMPONENT", "PER_COMPONENT"],
	["ACCENT_EDGE", "EDGE"],
	["ACCENT_DETAIL", "DETAIL"],
	["ACCENT_DETAIL_SCALE", "DETAIL_SCALE"],
	["ACCENT_DETAIL_OFFSET", "DETAIL_OFFSET"],
	["ACCENT_FINE", "FINE"],
	["ACCENT_FINE_SCALE", "FINE_SCALE"],
	["ACCENT_FINE_OFFSET", "FINE_OFFSET"],
	["ACCENT_NOISE_CELLS", "NOISE_CELLS"],
	["ACCENT_ROTATION", "ROTATION"],
]


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _accent(surface: String, coverage: float, scale_m: float = 6.0) -> Dictionary:
	return {"surface": surface, "coverage": coverage, "scale_m": scale_m}


func _inputs(overrides: Dictionary) -> Dictionary:
	var inputs := {
		"base": "grass",
		"biome_ground": PackedStringArray(["forest_floor"]),
		"biome_cliff": PackedStringArray(["cliff"]),
		"biome_scree": PackedStringArray(["gravel"]),
		"biome_coverage": PackedInt64Array([50]),
		"painted": PackedStringArray(),
		"base_rules": PackedStringArray(["cliff", "gravel"]),
		"role_of": func(s: String) -> String: return ROLES.get(s, "ground"),
		"color_of": func(_s: String) -> Variant: return null,
		"biome_accents": [[_accent("moss", 0.25, 8.0), _accent("grass", 0.15, 5.0)]],
		"base_accents": [_accent("dirt", 0.2)],
	}
	inputs.merge(overrides, true)
	return inputs


func _layers(the_plan: Dictionary) -> Array:
	var out := []
	for layer in the_plan.layers:
		out.append([layer.surface, layer.source])
	return out


## Mean of the CPU mask over a regular grid of `side` x `side` points spaced `step` metres.
func _mean_mask(threshold: float, scale_m: float, seed_value: int, side: int, step: float) -> float:
	var offset := GroundAccents.surface_offset("moss", seed_value)
	var total := 0.0
	for z in side:
		for x in side:
			var xz := Vector2(x * step + 0.37, z * step - 0.61)
			total += GroundAccents.mask(xz, threshold, scale_m, offset)
	return total / float(side * side)


# --- the mask -------------------------------------------------------------------------


func test_the_covered_share_is_the_coverage() -> void:
	# 150 x 150 points 2 m apart: a 300 m square, about 2500 patches of 6 m.
	for coverage in [0.1, 0.2, 0.3, 0.5]:
		for seed_value in [3, 77]:
			var mean := _mean_mask(GroundAccents.threshold(coverage), 6.0, seed_value, 150, 2.0)
			assert_almost_eq(mean, coverage, 0.03, "coverage %s seed %d" % [coverage, seed_value])


func test_no_coverage_draws_nothing_and_full_draws_everything() -> void:
	assert_eq(_mean_mask(GroundAccents.threshold(0.0), 6.0, 1, 30, 1.7), 0.0)
	assert_eq(_mean_mask(GroundAccents.threshold(1.0), 6.0, 1, 30, 1.7), 1.0)


func test_patches_are_about_scale_m_across() -> void:
	# The mean patch width along a line (covered run lengths) grows with scale_m and is of
	# its order at 30 % coverage.
	var widths := []
	for scale_m in [4.0, 12.0]:
		var runs := 0
		var covered := 0
		var inside := false
		var t := GroundAccents.threshold(0.3)
		for row in 20:
			for i in 4000:
				var xz := Vector2(i * 0.1, row * 37.0)
				var on := GroundAccents.mask(xz, t, scale_m, Vector2(3.1, 7.7)) > 0.5
				covered += 1 if on else 0
				if on and not inside:
					runs += 1
				inside = on
			inside = false
		widths.append(covered * 0.1 / maxf(runs, 1))
	assert_between(widths[0], 4.0 * 0.3, 4.0 * 1.5, "4 m patches: %s m runs" % widths[0])
	assert_between(widths[1], 12.0 * 0.3, 12.0 * 1.5, "12 m patches: %s m runs" % widths[1])
	assert_gt(widths[1], widths[0] * 2.0)


func test_drawn_coverages_keep_each_accents_own_share() -> void:
	var drawn := GroundAccents.drawn_coverages(PackedFloat32Array([0.3, 0.2, 0.1]))
	assert_almost_eq(drawn[0], 0.3, 1e-5)
	assert_almost_eq(drawn[1], 0.2 / 0.7, 1e-5)
	assert_almost_eq(drawn[2], 0.1 / 0.5, 1e-5)
	# Drawn in order, each taking its share of what is left: 0.3, 0.7 * 0.2857 = 0.2, ...
	var left := 1.0
	var shares := []
	for c in drawn:
		shares.append(left * c)
		left -= left * c
	assert_almost_eq(shares[1], 0.2, 1e-5)
	assert_almost_eq(shares[2], 0.1, 1e-5)
	var over := GroundAccents.drawn_coverages(PackedFloat32Array([0.7, 0.5]))
	assert_eq(over[1], 1.0, "a list over 1 is clamped, never negative or above 1")


func test_two_accents_in_order_cover_their_own_shares() -> void:
	var drawn := GroundAccents.drawn_coverages(PackedFloat32Array([0.25, 0.15]))
	var offsets := [
		GroundAccents.surface_offset("moss", 9), GroundAccents.surface_offset("grass", 9)
	]
	var totals := [0.0, 0.0]
	var side := 120
	for z in side:
		for x in side:
			var xz := Vector2(x * 2.3, z * 2.3)
			var remaining := 1.0
			for i in 2:
				var share: float = (
					remaining
					* GroundAccents.mask(xz, GroundAccents.threshold(drawn[i]), 6.0, offsets[i])
				)
				remaining -= share
				totals[i] += share
	assert_almost_eq(totals[0] / (side * side), 0.25, 0.03)
	assert_almost_eq(totals[1] / (side * side), 0.15, 0.03)


func test_surface_offsets_are_stable_and_distinct_per_surface_and_seed() -> void:
	assert_eq(GroundAccents.surface_offset("moss", 4), GroundAccents.surface_offset("moss", 4))
	assert_ne(GroundAccents.surface_offset("moss", 4), GroundAccents.surface_offset("grass", 4))
	assert_ne(GroundAccents.surface_offset("moss", 4), GroundAccents.surface_offset("moss", 5))
	var offset := GroundAccents.surface_offset("grass", -12345)
	assert_between(offset.x, 0.0, float(GroundAccents.NOISE_CELLS))
	assert_between(offset.y, 0.0, float(GroundAccents.NOISE_CELLS))


func test_an_octave_is_smooth_value_noise_on_the_lattice() -> void:
	var image := GroundAccents.noise_image()
	assert_eq(image.get_size(), Vector2i(GroundAccents.NOISE_CELLS, GroundAccents.NOISE_CELLS))
	# On a lattice point the octave is that cell's value; halfway it is the mean of the two.
	var a := image.get_pixel(5, 7).g
	var b := image.get_pixel(6, 7).g
	assert_almost_eq(GroundAccents.octave(Vector2(5.0, 7.0), 1), a, 1e-5)
	assert_almost_eq(GroundAccents.octave(Vector2(5.5, 7.0), 1), (a + b) * 0.5, 1e-5)
	# It tiles every NOISE_CELLS cells, also for negative coordinates.
	var cells := float(GroundAccents.NOISE_CELLS)
	assert_almost_eq(
		GroundAccents.octave(Vector2(2.3, -4.6), 0),
		GroundAccents.octave(Vector2(2.3 + cells, -4.6 + 2.0 * cells), 0),
		1e-4
	)
	# The channels are independent octaves.
	assert_ne(image.get_pixel(3, 3).r, image.get_pixel(3, 3).b)


# --- slot allocation --------------------------------------------------------------------


func test_accents_come_after_everything_else_and_route_per_component() -> void:
	var the_plan := GroundLayerTable.plan(_inputs({"painted": PackedStringArray(["cobblestone"])}))
	assert_eq(
		_layers(the_plan),
		[
			["cobblestone", P],
			["cliff", R],
			["gravel", R],
			["forest_floor", G],
			["moss", A],
			["dirt", A],
		],
		"painted, base rules, ground, then accents by entry index then coverage"
	)
	var accents: Array = the_plan.accents
	assert_eq(accents.size(), GroundLayerTable.MAX_LAYERS + 1)
	assert_eq(
		accents[3],
		[
			{"slot": 4, "surface": "moss", "coverage": 0.25, "scale_m": 8.0},
			{"slot": BASE, "surface": "grass", "coverage": 0.15, "scale_m": 5.0},
		],
		"the forest ground's accents in entry order; grass is the base surface"
	)
	assert_eq(accents[GroundLayerTable.MAX_LAYERS].size(), 1, "the base's default accents")
	assert_eq(accents[GroundLayerTable.MAX_LAYERS][0].slot, 5)
	assert_eq(the_plan.dropped_accents, PackedStringArray())
	assert_eq(GroundLayerTable.shader_masks(the_plan).layer_ground_mask, 1 << 3)


func test_an_accent_reuses_a_slot_drawing_it_or_the_base() -> void:
	# The forest's grass accent is the base surface; its gravel accent is the scree slot.
	var the_plan := GroundLayerTable.plan(
		_inputs(
			{"biome_accents": [[_accent("grass", 0.2), _accent("gravel", 0.1)]], "base_accents": []}
		)
	)
	assert_eq(_layers(the_plan), [["cliff", R], ["gravel", R], ["forest_floor", G]])
	var forest: Array = the_plan.accents[2]
	assert_eq(forest[0].slot, BASE)
	assert_eq(forest[1].slot, 1)


func test_the_base_takes_the_accents_of_the_biome_on_it() -> void:
	# A forest map: its base is the forest's ground, so the base carries the forest's accents,
	# not the default ones.
	var the_plan := GroundLayerTable.plan(_inputs({"base": "forest_floor"}))
	var base_accents: Array = the_plan.accents[GroundLayerTable.MAX_LAYERS]
	assert_eq(base_accents.map(func(a: Dictionary) -> String: return a.surface), ["moss", "grass"])


func test_an_accent_never_holds_a_slot_against_ground_and_the_least_covered_drops() -> void:
	var first := GroundLayerTable.plan(_inputs({}))
	assert_eq(
		_layers(first), [["cliff", R], ["gravel", R], ["forest_floor", G], ["moss", A], ["dirt", A]]
	)
	var again := GroundLayerTable.plan(_inputs({}), first.layers)
	assert_eq(_layers(again), _layers(first), "a re-plan keeps every accent in its slot")
	# Four more biome grounds arrive: they take the accents' slots first; of the accents
	# only one still fits, the more covered of the two first entries (moss 0.25, dirt 0.2).
	var grounds := PackedStringArray(["forest_floor", "a", "b", "c", "d"])
	var the_plan := (
		GroundLayerTable
		. plan(
			_inputs(
				{
					"biome_ground": grounds,
					"biome_cliff": PackedStringArray(["cliff", "cliff", "cliff", "cliff", "cliff"]),
					"biome_scree":
					PackedStringArray(["gravel", "gravel", "gravel", "gravel", "gravel"]),
					"biome_coverage": PackedInt64Array([50, 40, 30, 20, 10]),
					"biome_accents":
					[[_accent("moss", 0.25), _accent("grass", 0.15)], [], [], [], []],
				}
			),
			first.layers
		)
	)
	var layers := _layers(the_plan)
	assert_eq(
		layers,
		[
			["cliff", R],
			["gravel", R],
			["forest_floor", G],
			["a", G],
			["b", G],
			["c", G],
			["d", G],
			["moss", A],
		],
		"ground slots keep their index and the new grounds take the freed accent slots"
	)
	assert_eq(the_plan.dropped_accents, PackedStringArray(["dirt"]))
	assert_eq(the_plan.accents[2].size(), 2, "moss, and grass on the base")
	assert_eq(the_plan.accents[GroundLayerTable.MAX_LAYERS], [])


func test_only_the_first_accents_per_component_are_drawn() -> void:
	var many := []
	for surface in ["m1", "m2", "m3", "m4"]:
		many.append(_accent(surface, 0.1))
	var the_plan := (
		GroundLayerTable
		. plan(
			_inputs(
				{
					"biome_accents": [many],
					"base_accents": [],
					"base_rules": PackedStringArray(["", ""]),
					"biome_cliff": PackedStringArray([""]),
					"biome_scree": PackedStringArray([""]),
				}
			)
		)
	)
	assert_eq(_layers(the_plan)[0], ["forest_floor", G])
	assert_eq(the_plan.accents[0].size(), GroundLayerTable.ACCENTS_PER_COMPONENT)
	assert_eq(the_plan.dropped_accents, PackedStringArray(["m4"]))


func test_a_plan_without_accents_is_unchanged() -> void:
	var the_plan := GroundLayerTable.plan(_inputs({"biome_accents": [], "base_accents": []}))
	assert_eq(_layers(the_plan), [["cliff", R], ["gravel", R], ["forest_floor", G]])
	var uniforms := GroundAccents.shader_uniforms(the_plan.accents, 1)
	assert_eq(uniforms.accent_components, 0)


# --- uniforms ---------------------------------------------------------------------------


func test_shader_uniforms_pack_slots_thresholds_and_offsets() -> void:
	var the_plan := GroundLayerTable.plan(_inputs({"base": "forest_floor"}))
	var uniforms := GroundAccents.shader_uniforms(the_plan.accents, 21)
	var per := GroundAccents.PER_COMPONENT
	var base := GroundLayerTable.MAX_LAYERS
	assert_eq(uniforms.accent_components, 1 << base)
	var layers: PackedInt32Array = uniforms.accent_layer
	var params: PackedVector4Array = uniforms.accent_params
	assert_eq(layers.size(), GroundAccents.COMPONENTS * per)
	assert_eq(params.size(), GroundAccents.COMPONENTS * per)
	var surfaces: Array = the_plan.layers.map(func(l: Dictionary) -> String: return l.surface)
	var moss: int = surfaces.find("moss")
	assert_eq(layers[base * per], moss)
	assert_eq(layers[base * per + 2], -1, "no third accent")
	assert_eq(layers[0], -1)
	var first: Vector4 = params[base * per]
	assert_almost_eq(first.x, GroundAccents.threshold(0.25), 1e-5)
	assert_almost_eq(first.y, 1.0 / 8.0, 1e-6)
	var offset := GroundAccents.surface_offset("moss", 21)
	assert_almost_eq(first.z, offset.x, 1e-4)
	assert_almost_eq(first.w, offset.y, 1e-4)
	var second: Vector4 = params[base * per + 1]
	assert_almost_eq(second.x, GroundAccents.threshold(0.15 / 0.75), 1e-5, "order-aware")
	# An accent on the base surface is 8 in the shader, like the rule routing.
	var on_base := GroundLayerTable.plan(
		_inputs({"biome_accents": [[_accent("grass", 0.2)]], "base_accents": []})
	)
	assert_eq(GroundAccents.shader_uniforms(on_base.accents, 21).accent_layer[2 * per], base)


func test_the_shader_mirrors_the_accent_constants() -> void:
	var text := FileAccess.get_file_as_string(SHADER_PATH)
	var found := {}
	var regex := RegEx.new()
	regex.compile("const\\s+(int|float|vec2)\\s+(\\w+)\\s*=\\s*([^;]+);")
	for m in regex.search_all(text):
		var value := m.get_string(3).strip_edges()
		match m.get_string(1):
			"vec2":
				var inner := value.trim_prefix("vec2(").trim_suffix(")").split(",")
				found[m.get_string(2)] = Vector2(float(inner[0]), float(inner[1]))
			"int":
				found[m.get_string(2)] = int(value)
			_:
				found[m.get_string(2)] = float(value)
	var cpu: Dictionary = GroundAccents.new().get_script().get_script_constant_map()
	for pair in MIRRORED:
		assert_true(found.has(pair[0]), "%s in the shader" % pair[0])
		assert_true(cpu.has(pair[1]), "%s in GroundAccents" % pair[1])
		if not found.has(pair[0]) or not cpu.has(pair[1]):
			continue
		var value: Variant = cpu[pair[1]]
		if value is Vector2:
			assert_true((found[pair[0]] as Vector2).is_equal_approx(value), pair[0])
		else:
			assert_almost_eq(float(found[pair[0]]), float(value), 1e-6, pair[0])
	var arrays := GroundAccents.COMPONENTS * GroundAccents.PER_COMPONENT
	var compact := text.replace(" ", "")
	assert_true(compact.contains("uniformintaccent_layer[%d];" % arrays), "accent_layer size")
	assert_true(compact.contains("uniformvec4accent_params[%d];" % arrays), "accent_params size")


# --- the terrain --------------------------------------------------------------------------


## The real palette with the temperate forest's accents replaced by `accents` (the cache is
## cleared after each test). `others` replaces every other biome's accents when given.
func _inject_forest_accents(accents: Array, others: Variant = null) -> void:
	PaletteLibrary.clear_cache()
	var palette: Dictionary = PaletteLibrary.get_palette().duplicate(true)
	for biome in palette.biomes:
		if biome.id == FOREST:
			biome["ground_accents"] = accents
		elif others is Array:
			biome["ground_accents"] = others
	PaletteLibrary._palettes[PaletteLibrary.DEFAULT_ROOT] = palette


func _forest_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "forest_floor", "test", 11)
	doc.biome_ids = PackedStringArray([FOREST])
	var full := PackedByteArray()
	full.resize(doc.sample_count())
	full.fill(1)
	doc.biome_slots = full
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	density.fill(255)
	doc.biome_density = density
	return doc


## Round 3 (2026-10-09): the accents shrink away in the map's edge band and the skirt draws
## none (it carried the base's until then: accent_components was the base bit and
## layer_count the slots).
func test_terrain_binds_accents_with_an_edge_band_and_the_skirt_draws_none() -> void:
	_inject_forest_accents([_accent("moss", 0.25, 8.0), _accent("grass", 0.15, 5.0)])
	var terrain := AuthoredTerrain.create(_forest_doc())
	add_child_autofree(terrain)
	var layers := terrain.ground_layers()
	assert_true(layers.has("moss") and layers.has("grass"), str(layers))
	var material := terrain.get_material()
	var base_bit := 1 << GroundLayerTable.MAX_LAYERS
	assert_eq(material.get_shader_parameter("accent_components"), base_bit)
	var half := terrain.document.extent_m() * 0.5
	assert_eq(material.get_shader_parameter("accent_edge_half"), half)
	assert_eq(material.get_shader_parameter("accent_edge_m"), NewMap.edge_feather_m(half))
	var skirt := terrain.get_skirt().mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(skirt.get_shader_parameter("accent_components"), 0, "no patches past the edge")
	assert_eq(skirt.get_shader_parameter("layer_count"), 0, "the base: no slot sampled")
	assert_eq(skirt.get_shader_parameter("skirt_ground_mask"), 0)
	assert_eq(skirt.get_shader_parameter("layer_ground_mask"), 0, "the skirt reads no weights")
	assert_eq(material.get_shader_parameter("accent_noise"), GroundAccents.noise_texture())
	var paths := AuthoredTerrain.texture_paths(terrain.document)
	assert_true(Array(paths).any(func(p: String) -> bool: return p.contains("/moss/")))
	PaletteLibrary.clear_cache()


func test_the_skirt_continues_a_surface_painted_over_the_map_edge() -> void:
	_inject_forest_accents([_accent("moss", 0.25, 8.0)])
	var doc := _forest_doc()
	var slot := doc.ensure_surface("grass")
	assert_eq(TerrainSkirt.edge_surface(doc), -1, "nothing painted yet")
	var last_x := doc.samples_x() - 1
	var last_z := doc.samples_z() - 1
	for z in doc.samples_z():
		for x in doc.samples_x():
			if x == 0 or z == 0 or x == last_x or z == last_z:
				doc.set_surface_weight(doc.sample_index(x, z), slot, 255)
	assert_eq(TerrainSkirt.edge_surface(doc), slot)
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var skirt := terrain.get_skirt().mesh.surface_get_material(0) as ShaderMaterial
	var mask: int = skirt.get_shader_parameter("skirt_ground_mask")
	var layers := terrain.ground_layers()
	assert_ne(mask, 0, "the skirt draws the edge's surface")
	assert_eq(layers[int(log(float(mask)) / log(2.0) + 0.5)], "grass", str(layers))
	assert_eq(skirt.get_shader_parameter("layer_count"), layers.size())
	PaletteLibrary.clear_cache()


func test_a_new_biome_takes_an_accent_slot_without_moving_the_weights() -> void:
	_inject_forest_accents([_accent("moss", 0.25, 8.0)])
	var doc := _forest_doc()
	var terrain := AuthoredTerrain.create(doc)
	add_child_autofree(terrain)
	var before := terrain.ground_layers()
	doc.biome_ids.append(TAIGA)
	terrain.update_ground_region(Rect2i(0, 0, 4, 4))
	var after := terrain.ground_layers()
	assert_true(after.has("pine_duff"))
	assert_true(after.has("moss"), "the accent still fits")
	for j in before.size():
		if before[j] != "moss":
			assert_eq(after[j], before[j], "slot %d kept" % j)
	PaletteLibrary.clear_cache()


func test_without_accents_the_terrain_binds_none() -> void:
	_inject_forest_accents([], [])
	var terrain := AuthoredTerrain.create(_forest_doc())
	add_child_autofree(terrain)
	assert_eq(terrain.get_material().get_shader_parameter("accent_components"), 0)
	var skirt := terrain.get_skirt().mesh.surface_get_material(0) as ShaderMaterial
	assert_eq(skirt.get_shader_parameter("layer_count"), 0)
	PaletteLibrary.clear_cache()
