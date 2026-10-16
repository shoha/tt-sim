extends GutTest

## The ground look as uniforms (GroundLookUniforms) and its bake owner (GroundLookBake): a biome's
## merged look gives back round 20's uniforms, a map whose biomes carry no look leaves every gate
## off, and a map of several biomes gives each its own slot and values.

const FIXTURE := "res://tests/fixtures/ground_look_r20_grassland.json"
const TAIGA := "boreal_taiga_summer_s1"
## The installed palette's biomes that carry a ground_look (ASSET_PIPELINE section 9).
const ZONED := [
	"grassland_meadow_summer_s1",
	"savanna_summer_s1",
	"birch_woodland_summer_s1",
	"wetland_riparian_summer_s1",
	"alpine_meadow_summer_s1",
	"temperate_forest_summer_s1",
]
const SURFACES := {
	"grass_meadow_r5": {"role": "ground"},
	"dirt_opening_r5": {"role": "ground"},
	"dirt_road_packed_r5": {"role": "built"},
	"turf": {"role": "ground"},
	"glade": {"role": "ground"},
	"moss": {"role": "ground"},
	"mud": {"role": "ground"},
}
## Set by the consumer at run time (or the probe's dry drift, not in the format).
const RUN_TIME := [
	"light_field_ref",
	"light_field_zoned",
	"light_field_dry",
	"light_field_dry_scale_m",
	"light_field_dry_tint",
]
const LAYERS := {"turf": 0, "glade": 3, "moss": 4, "mud": 5, "dirt_opening_r5": 6}


func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


func _look(raw: Dictionary) -> Dictionary:
	var warnings: Array[String] = []
	return GroundLook.validate(raw, "b", "turf", SURFACES, warnings)


func _layer_of(surface: Variant) -> int:
	return int(LAYERS.get(String(surface), -1))


func _assert_same(got: Variant, want: Variant, key: String) -> void:
	if want is Array:
		assert_true(got is Array and got.size() == want.size(), "%s: shape" % key)
		for i in want.size():
			assert_almost_eq(float(got[i]), float(want[i]), 1e-6, "%s[%d]" % [key, i])
	else:
		assert_almost_eq(float(got), float(want), 1e-6, key)


func test_grassland_merged_uniforms_equal_round_20() -> void:
	var fixture := _fixture()
	var look := _look(fixture.ground_look)
	var uniforms := GroundLookUniforms.uniforms(look)
	var compared := 0
	for group in ["field", "rim", "shape"]:
		var want: Dictionary = fixture[group]
		for key: String in want:
			if key in RUN_TIME:
				continue
			assert_true(uniforms.has(key), "%s is a contract uniform" % key)
			if key == "zone_layers":
				assert_eq(uniforms[key], want[key], key)
			elif uniforms.has(key):
				_assert_same(uniforms[key], want[key], key)
			compared += 1
	assert_eq(compared, 86, "every round 20 uniform but the run-time ones")
	assert_eq(uniforms.rim_surfaces, fixture.rim_surfaces)
	assert_eq(uniforms.ref_surface, "grass_meadow_r5")


func test_every_contract_key_has_a_uniform_name() -> void:
	var keys := 0
	for group: String in GroundLook.BASE:
		if GroundLook.BASE[group] is Dictionary:
			for key: String in GroundLook.BASE[group]:
				assert_true(GroundLookUniforms.NAMES.has("%s.%s" % [group, key]), key)
				keys += 1
		else:
			assert_true(GroundLookUniforms.NAMES.has(group), group)
			keys += 1
	assert_eq(keys, 89, "the contract's 89 keys")
	assert_eq(GroundLookUniforms.NAMES.size(), 89)


func test_material_params_are_typed_and_split() -> void:
	var look := _look(_fixture().ground_look)
	var ref := Color(0.2711, 0.3928, 0.0485)
	var rect := Vector4(-50.0, -50.0, 100.0, 100.0)
	var bake := GroundLookUniforms.bake_params(look, ref, Vector2(3.0, -4.0), rect)
	assert_eq(bake.zone_color_2, Vector3(0.4986, 0.4346, 0.041))
	assert_eq(bake.light_field_ref, Vector3(ref.r, ref.g, ref.b))
	assert_eq(bake.zone_seed_m, Vector2(3.0, -4.0))
	assert_eq(bake.bake_rect, rect)
	assert_almost_eq(float(bake.light_field_cover), 0.4, 1e-6)
	for absent in ["zone_strength", "light_field_knee", "zone_tuft_step", "mass_shade", "zone_layers"]:
		assert_false(bake.has(absent), "%s is not the bake's" % absent)
	var tuft := GroundLookUniforms.tuft_params(look, ref, Vector2(0.707, -0.707), null, rect)
	assert_almost_eq(float(tuft.zone_tuft_step), 2.35, 1e-6)
	assert_almost_eq(float(tuft.zone_mass_lit_m), 2.5, 1e-6)
	assert_almost_eq(float(tuft.light_field_knee), 0.64, 1e-6)
	assert_eq(tuft.zone_mass_lit_dir, Vector2(0.707, -0.707))
	for absent in ["mass_shade", "mass_lift_push", "zone_cover", "light_field_scale_m"]:
		assert_false(tuft.has(absent), "%s is not the grass's" % absent)


## Card 3c: round 20's probes set the light reference, the tuft reference and the accent tint
## on the ground and the grass (spatial materials) as a Color, which Godot converts from sRGB to
## linear there; the bake (canvas) and the rim colour (a plain vector) took their values raw.
## Parity with round 20's frames needs the same values on the GPU.
func test_spatial_colours_reach_the_gpu_as_round_20s_did() -> void:
	var look := _look(_fixture().ground_look)
	var ref := Color(0.2711, 0.3928, 0.0485)
	# What round 20's grass and ground got for grassland's reference (logged in the 3c run).
	var r20_ref := Vector3(0.059736, 0.127878, 0.003802)
	var gpu := GroundLookUniforms.as_r20_spatial(ref)
	for i in 3:
		assert_almost_eq(gpu[i], r20_ref[i], 1e-5, "srgb_to_linear, channel %d" % i)
	var rect := Vector4(-50.0, -50.0, 100.0, 100.0)
	var bake := GroundLookUniforms.bake_params(look, ref, Vector2.ZERO, rect)
	assert_eq(bake.light_field_ref, Vector3(ref.r, ref.g, ref.b), "the bake takes it raw")
	var tuft := GroundLookUniforms.tuft_params(look, ref, Vector2(0.0, -1.0), null, rect)
	assert_eq(tuft.light_field_ref, gpu, "the grass takes it converted")
	var tinted := _look({"zones": look.zones, "rim": {"accent_tint": [1.0, 0.86, 0.55]}})
	var the_plan := GroundLookUniforms.plan([{"biome": "m", "ground": 0}], {"m": tinted}, _layer_of)
	var tables := GroundLookUniforms.ground_tables(the_plan, [tinted], [ref], [null], rect)
	assert_almost_eq(tables.look_ref[0].x, r20_ref.x, 1e-5, "the ground's reference converted")
	assert_almost_eq(tables.look_ref[0].y, r20_ref.y, 1e-5)
	var tint := GroundLookUniforms.as_r20_spatial(Color(1.0, 0.86, 0.55))
	assert_almost_eq(tables.look_accent_tint[0].y, tint.y, 1e-6, "the accent tint converted")
	assert_almost_eq(tables.look_accent_tint[0].x, 1.0, 1e-6, "white stays white")
	var rim: Array = tinted.rim.color_linear
	assert_almost_eq(tables.look_rim_color[0].x, float(rim[0]), 1e-6, "the rim colour raw")


func test_a_biome_without_a_look_leaves_every_gate_off() -> void:
	assert_eq(GroundLookUniforms.uniforms({}), {}, "no uniforms")
	var rows := [{"biome": "plain", "ground": 0}, {"biome": "burnt", "ground": 2}]
	var the_plan := GroundLookUniforms.plan(rows, {"plain": {}}, _layer_of)
	assert_true(the_plan.biomes.is_empty(), "no slot")
	assert_eq(Array(the_plan.row_slots).count(-1), GroundLookUniforms.ROW_SLOTS, "no row looked")
	assert_eq(Array(the_plan.layer_slots).count(-1), GroundLookUniforms.LAYER_SLOTS)
	var tables := GroundLookUniforms.ground_tables(the_plan, [], [], [], Vector4.ZERO)
	assert_eq(tables, {"look_present": 0})
	# The installed ship palette (treecube 020bbdc) zones six biomes; the boreal taiga carries no
	# ground_look: a map of it makes no bake and binds nothing.
	var root := PaletteLibrary.DEFAULT_ROOT
	assert_true(PaletteLibrary.ground_look(TAIGA, root).is_empty(), "taiga: no look")
	for zoned in ZONED:
		assert_false(PaletteLibrary.ground_look(zoned, root).is_empty(), "%s is zoned" % zoned)
	var biome := PaletteLibrary.biome(TAIGA)
	var doc := MapDocument.create_flat(Vector2i(8, 8), String(biome.ground_surface), "", 1234)
	doc.biome_ids = PackedStringArray([TAIGA])
	assert_false(GroundLookBake.has_look(doc, root), "no look")
	var terrain := AuthoredTerrain.create(doc)
	assert_null(terrain.ground_look(), "no bake node")
	var present: Variant = terrain.get_material().get_shader_parameter("look_present")
	assert_true(present == null or int(present) == 0, "look_present off")
	terrain.free()


func test_two_biome_map_gives_each_biome_its_values() -> void:
	var three := [[0.2, 0.3, 0.05], [0.1, 0.2, 0.03], [0.5, 0.4, 0.04]]
	var four := [[0.3, 0.3, 0.1], [0.2, 0.3, 0.1], [0.4, 0.3, 0.1], [0.5, 0.2, 0.1]]
	var a := _look(
		{
			"zones": {"colors_linear": three},
			"brush": {"mean": 3.2},
			"rim": {"surfaces": ["dirt_opening_r5"], "strength": 0.6},
		}
	)
	var b := _look(
		{
			"zones": {"colors_linear": four, "layers": ["glade", "moss"]},
			"brush": {"mean": 4.15, "contrast": 0.3},
			"rim": {"strength": 0.4, "accent_core_m": 0.2, "core_dark": 0.3},
			"accent_shape": {"stretch": 1.0, "break": 0.5, "edge_scale": 0.6},
			"light": {"knee": 0.72},
		}
	)
	var rows := [
		{"biome": "meadow", "ground": 0},
		{"biome": "meadow", "ground": 0},
		{"biome": "forest", "ground": 2},
		{"biome": "burnt", "ground": 5},
	]
	var looks := {"meadow": a, "forest": b, "burnt": {}}
	var the_plan := GroundLookUniforms.plan(rows, looks, _layer_of)
	assert_eq(the_plan.biomes, PackedStringArray(["meadow", "forest"]))
	assert_eq(Array(the_plan.row_slots.slice(0, 5)), [0, 0, 1, -1, -1], "rows to slots")
	assert_eq(the_plan.layer_slots[0], 0, "the meadow's ground")
	assert_eq(the_plan.layer_slots[3], 1, "the forest's zone layers, not its ground")
	assert_eq(the_plan.layer_slots[4], 1)
	assert_eq(the_plan.layer_slots[2], -1)
	assert_eq(the_plan.layer_slots[5], -1, "the burnt forest draws today's ground")
	assert_eq(Array(the_plan.rim_layers.slice(0, 8)), [6, -1, -1, -1, -1, -1, -1, -1])
	var refs := [Color(0.27, 0.39, 0.05), Color(0.3, 0.35, 0.08)]
	var tables := GroundLookUniforms.ground_tables(
		the_plan, [a, b], refs, [null, null], Vector4(-1, -1, 2, 2)
	)
	assert_eq(tables.look_present, 1)
	assert_almost_eq(tables.look_brush[0].w, 3.2, 1e-6, "the meadow's brush mean")
	assert_almost_eq(tables.look_brush[1].w, 4.15, 1e-6, "the forest's")
	assert_almost_eq(tables.look_brush[1].x, 0.3, 1e-6)
	assert_almost_eq(tables.look_rim[0].z, 0.6, 1e-6, "the meadow's rim strength")
	assert_almost_eq(tables.look_rim[1].z, 0.4, 1e-6)
	assert_almost_eq(tables.look_rim_more[1].z, 0.2, 1e-6, "the forest's wet core")
	assert_almost_eq(tables.look_shape[0].z, 0.4, 1e-6, "the base accent break")
	assert_almost_eq(tables.look_shape[1].z, 0.5, 1e-6)
	assert_almost_eq(tables.look_shape[1].w, 0.6, 1e-6)
	assert_almost_eq(tables.look_light[1].z, 0.72, 1e-6, "the forest's knee")
	assert_almost_eq(
		tables.look_ref[1].y, GroundLookUniforms.as_r20_spatial(refs[1]).y, 1e-6, "the forest's ref"
	)
	assert_eq(tables.look_shape[2], Vector4(1, 0, 0, 1), "an unused slot draws today's patches")


func test_looks_past_the_slots_are_dropped() -> void:
	var colors := [[0.2, 0.3, 0.05], [0.1, 0.2, 0.03], [0.5, 0.4, 0.04]]
	var look := _look({"zones": {"colors_linear": colors}})
	var rows := []
	var looks := {}
	for i in GroundLookUniforms.SLOTS + 1:
		rows.append({"biome": "b%d" % i, "ground": i})
		looks["b%d" % i] = look
	var the_plan := GroundLookUniforms.plan(rows, looks, _layer_of)
	assert_eq(the_plan.biomes.size(), GroundLookUniforms.SLOTS)
	assert_eq(the_plan.dropped, PackedStringArray(["b%d" % GroundLookUniforms.SLOTS]))
	assert_eq(the_plan.row_slots[GroundLookUniforms.SLOTS], -1)


func test_the_bake_shader_is_warmed() -> void:
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/ground_light_field_bake.gdshader")
