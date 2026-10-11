extends GutTest

## The index-based ground's pure tables (GroundLayers, card G1 of the ground-layers build):
## the per-map layer list (stable append across edits, compaction on load, the overflow
## past MAX_LAYERS), the per-biome routing table, painted index table, per-layer flags and
## tiles. Pure data: no palette, no textures; surface names, roles and colours are made up.

const NONE := GroundLayers.NONE
const ROLES := {
	"cliff": "cliff",
	"cliff_basalt": "cliff",
	"cobblestone": "built",
}
const COLORS := {
	"forest_floor": Color(0.35, 0.3, 0.2),
	"pine_duff": Color(0.4, 0.3, 0.2),
	"grass": Color(0.3, 0.5, 0.2),
	"cliff": Color(0.5, 0.5, 0.5),
	"cliff_basalt": Color(0.2, 0.2, 0.22),
}


func _role(surface: String) -> String:
	return ROLES.get(surface, "ground")


func _color(surface: String) -> Variant:
	return COLORS.get(surface, null)


## A forest map: forest_floor base with its own rock, one painted path, one forest biome.
func _forest_inputs() -> Dictionary:
	return {
		"base": "forest_floor",
		"painted": PackedStringArray(["cobblestone"]),
		"biome_ground": PackedStringArray(["forest_floor"]),
		"biome_cliff": PackedStringArray(["cliff"]),
		"biome_scree": PackedStringArray(["gravel"]),
		"biome_bed": PackedStringArray(["riverbed"]),
		"biome_shore": PackedStringArray(["sand"]),
		"base_rules": PackedStringArray(["cliff", "gravel", "riverbed", "sand"]),
		"biome_accents": [[{"surface": "moss", "coverage": 0.2, "scale_m": 6.0}]],
		"base_accents": [],
	}


func _table(inputs: Dictionary, previous := PackedStringArray()) -> Dictionary:
	return GroundLayers.extend(
		previous, GroundLayers.wanted(inputs), Callable(self, "_role"), Callable(self, "_color")
	)


func test_wanted_lists_each_surface_once_in_priority_order() -> void:
	var wants := GroundLayers.wanted(_forest_inputs())
	# Base, painted, biome grounds, base rules, biome rules; no water: no bed or shore.
	assert_eq(wants.surfaces, PackedStringArray(["forest_floor", "cobblestone", "cliff", "gravel"]))
	assert_eq(wants.accents, PackedStringArray(["moss"]))
	var wet := _forest_inputs()
	wet["water"] = true
	assert_eq(
		GroundLayers.wanted(wet).surfaces,
		PackedStringArray(["forest_floor", "cobblestone", "cliff", "gravel", "riverbed", "sand"])
	)


func test_indices_are_stable_across_edits() -> void:
	var first := _table(_forest_inputs())
	var before: PackedStringArray = first.layers
	assert_eq(before, PackedStringArray(["forest_floor", "cobblestone", "cliff", "gravel", "moss"]))
	# Paint snow, add a taiga biome and water: every layer keeps its index, new ones append.
	var edited := _forest_inputs()
	edited.painted = PackedStringArray(["cobblestone", "snow"])
	edited.biome_ground = PackedStringArray(["forest_floor", "pine_duff"])
	edited.biome_cliff = PackedStringArray(["cliff", "cliff_basalt"])
	edited.biome_scree = PackedStringArray(["gravel", "scree_dark"])
	edited.biome_bed = PackedStringArray(["riverbed", "riverbed"])
	edited.biome_shore = PackedStringArray(["sand", "sand"])
	edited.biome_accents = [[{"surface": "moss", "coverage": 0.2, "scale_m": 6.0}], []]
	edited["water"] = true
	var second := _table(edited, before)
	var after: PackedStringArray = second.layers
	assert_eq(after.slice(0, before.size()), before)
	assert_eq(
		after.slice(before.size()),
		PackedStringArray(["snow", "pine_duff", "riverbed", "sand", "cliff_basalt", "scree_dark"])
	)
	# The path is erased: its layer stays for the session, nothing moves.
	edited.painted = PackedStringArray(["snow"])
	var third := _table(edited, after)
	assert_eq(third.layers, after)
	assert_eq(GroundLayers.layer_of(third, "cobblestone"), 1)
	assert_eq(GroundLayers.layer_of(third, "snow"), 5)
	assert_true((third.fallbacks as Dictionary).is_empty())


func test_compaction_keeps_only_used_surfaces_with_the_base_first() -> void:
	var edited := _forest_inputs()
	edited.painted = PackedStringArray(["snow"])
	edited.biome_accents = [[]]
	var session := PackedStringArray(["forest_floor", "cobblestone", "cliff", "gravel", "moss"])
	assert_eq(_table(edited, session).layers.size(), 6)
	var loaded := GroundLayers.compact(
		GroundLayers.wanted(edited), Callable(self, "_role"), Callable(self, "_color")
	)
	assert_eq(loaded.layers, PackedStringArray(["forest_floor", "snow", "cliff", "gravel"]))
	assert_eq(GroundLayers.routing(edited, loaded).base_layer, 0)


func test_two_biomes_on_one_ground_keep_their_own_cliff_and_scree() -> void:
	var inputs := {
		"base": "forest_floor",
		"painted": PackedStringArray(),
		"biome_ground": PackedStringArray(["grass", "grass"]),
		"biome_cliff": PackedStringArray(["cliff", "cliff_basalt"]),
		"biome_scree": PackedStringArray(["gravel", "scree_dark"]),
		"biome_bed": PackedStringArray(["riverbed", ""]),
		"biome_shore": PackedStringArray(["sand", "sand"]),
		"base_rules": PackedStringArray(["cliff", "", "riverbed", "sand"]),
		"biome_accents":
		[
			[
				{"surface": "moss", "coverage": 0.2, "scale_m": 6.0},
				{"surface": "grass", "coverage": 0.3, "scale_m": 4.0},
			],
			[{"surface": "snow", "coverage": 0.1, "scale_m": 8.0}],
		],
		"base_accents": [{"surface": "moss", "coverage": 0.1, "scale_m": 5.0}],
		"water": true,
	}
	var table := _table(inputs)
	var route := GroundLayers.routing(inputs, table)
	var layer := func(surface: String) -> int: return GroundLayers.layer_of(table, surface)
	# Row 0 is the base, rows 1 and 2 the two biomes, both on the grass layer.
	assert_eq(route.ground, PackedInt32Array([0, layer.call("grass"), layer.call("grass")]))
	assert_eq(
		route.cliff,
		PackedInt32Array([layer.call("cliff"), layer.call("cliff"), layer.call("cliff_basalt")])
	)
	assert_ne(route.cliff[1], route.cliff[2])
	assert_eq(route.scree, PackedInt32Array([NONE, layer.call("gravel"), layer.call("scree_dark")]))
	assert_eq(route.bed, PackedInt32Array([layer.call("riverbed"), layer.call("riverbed"), NONE]))
	assert_eq(route.shore[2], layer.call("sand"))
	# Accents per row; a biome's own ground is never its accent.
	var per_row := GroundLayers.ACCENTS_PER_BIOME
	assert_eq(route.accents.size(), 3 * per_row)
	assert_eq(route.accents[0], layer.call("moss"))
	assert_eq(route.accents[per_row], layer.call("moss"))
	assert_eq(route.accents[per_row + 1], NONE)
	assert_eq(route.accents[2 * per_row], layer.call("snow"))
	assert_eq(route.accent_entries[2][0].scale_m, 8.0)
	# Without water bed and shore leave the weight with the ground.
	inputs.water = false
	var dry := GroundLayers.routing(inputs, _table(inputs))
	assert_eq(dry.bed, PackedInt32Array([NONE, NONE, NONE]))
	assert_eq(dry.shore, PackedInt32Array([NONE, NONE, NONE]))


func test_a_biome_without_a_ground_draws_the_base() -> void:
	var inputs := _forest_inputs()
	inputs.biome_ground = PackedStringArray([""])
	var route := GroundLayers.routing(inputs, _table(inputs))
	assert_eq(route.ground, PackedInt32Array([0, 0]))


## Fills the table: the base and 63 painted surfaces, s1..s63, coloured by index.
func _full_inputs() -> Dictionary:
	var painted := PackedStringArray()
	for i in range(1, GroundLayers.MAX_LAYERS):
		painted.append("s%d" % i)
	return {
		"base": "s0",
		"painted": painted,
		"biome_ground": PackedStringArray(["late_ground", "mystery"]),
		"biome_cliff": PackedStringArray(["late_cliff", ""]),
		"biome_scree": PackedStringArray(["", ""]),
		"base_rules": PackedStringArray(["", ""]),
		"biome_accents": [[{"surface": "late_accent", "coverage": 0.2, "scale_m": 6.0}], []],
	}


func _full_role(surface: String) -> String:
	return "cliff" if surface in ["s40", "s50", "late_cliff"] else "ground"


func _full_color(surface: String) -> Variant:
	if surface == "late_ground":
		return Color(0.104, 0.0, 0.0)
	if surface == "late_cliff":
		return Color(0.12, 0.0, 0.0)
	if surface.begins_with("s"):
		return Color(int(surface.substr(1)) / 100.0, 0.0, 0.0)
	return null


func _full_table(inputs: Dictionary) -> Dictionary:
	return GroundLayers.compact(
		GroundLayers.wanted(inputs), Callable(self, "_full_role"), Callable(self, "_full_color")
	)


func test_overflow_past_64_falls_back_to_the_nearest_albedo() -> void:
	var inputs := _full_inputs()
	var table := _full_table(inputs)
	assert_eq(table.layers.size(), GroundLayers.MAX_LAYERS)
	# A ground goes to the nearest ground layer (s10); a cliff to the nearest cliff-role
	# layer, not the nearest colour overall (s12); an unknown colour to the base; an accent
	# is dropped.
	assert_eq(table.fallbacks["late_ground"], "s10")
	assert_eq(GroundLayers.layer_of(table, "late_ground"), 10)
	assert_eq(table.fallbacks["late_cliff"], "s40")
	assert_eq(table.fallbacks["mystery"], "s0")
	assert_eq(table.dropped, PackedStringArray(["late_accent"]))
	var route := GroundLayers.routing(inputs, table)
	assert_eq(route.ground, PackedInt32Array([0, 10, 0]))
	assert_eq(route.cliff[1], 40)
	assert_eq(route.accents[GroundLayers.ACCENTS_PER_BIOME], NONE)
	assert_eq((route.accent_entries[1] as Array).size(), 0)
	# A full session list never grows past the cap either.
	var again := GroundLayers.extend(
		table.layers,
		GroundLayers.wanted(inputs),
		Callable(self, "_full_role"),
		Callable(self, "_full_color")
	)
	assert_eq(again.layers, table.layers)
	assert_eq_deep(again.fallbacks, table.fallbacks)


func test_tables_are_deterministic() -> void:
	var inputs := _full_inputs()
	var a := _full_table(inputs)
	var b := _full_table(inputs.duplicate(true))
	assert_eq(a.layers, b.layers)
	assert_eq_deep(a.fallbacks, b.fallbacks)
	assert_eq_deep(GroundLayers.routing(inputs, a), GroundLayers.routing(inputs, b))
	var forest := _forest_inputs()
	assert_eq_deep(
		GroundLayers.routing(forest, _table(forest)), GroundLayers.routing(forest, _table(forest))
	)


func test_painted_index_table() -> void:
	var inputs := _forest_inputs()
	var table := _table(inputs)
	var painted := GroundLayers.painted_layers(
		table, PackedStringArray(["cobblestone", "", "unknown"])
	)
	assert_eq(painted.size(), GroundLayers.MAX_PAINTED)
	assert_eq(painted.slice(0, 4), PackedInt32Array([1, NONE, NONE, NONE]))


func test_capacity_flags_and_tiles() -> void:
	assert_eq(GroundLayers.capacity(0), 16)
	assert_eq(GroundLayers.capacity(16), 16)
	assert_eq(GroundLayers.capacity(17), 32)
	assert_eq(GroundLayers.capacity(33), 64)
	assert_eq(GroundLayers.capacity(500), GroundLayers.MAX_LAYERS)
	var layers := PackedStringArray(["forest_floor", "cobblestone", "cliff", "gravel"])
	var flags := GroundLayers.layer_flags(layers, Callable(self, "_role"))
	assert_eq(flags.size(), 16)
	assert_eq(
		flags.slice(0, 5),
		PackedInt32Array([0, GroundLayers.FLAG_BUILT, GroundLayers.FLAG_CLIFF, 0, 0])
	)
	var tiles := GroundLayers.layer_tiles(
		layers,
		func(surface: String) -> Variant: return {"cobblestone": 1.5, "cliff": 0.0}.get(surface)
	)
	assert_eq(tiles.size(), 16)
	assert_eq(tiles.slice(0, 5), PackedFloat32Array([2.0, 1.5, 2.0, 2.0, 2.0]))
