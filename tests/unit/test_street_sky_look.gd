extends GutTest

## StreetSkyLook: the per-biome numbers of the eye view's painted sky and the pure maths around
## them (card eyesky). Every biome carries every required value, in range, and its own skyline.

const CORE_BIOMES: Array[String] = [
	"alpine_meadow",
	"birch_woodland",
	"boreal_taiga",
	"burnt_forest",
	"grassland_meadow",
	"rocky_badlands",
	"savanna",
	"temperate_forest",
	"wetland_riparian",
]


func test_every_core_biome_and_the_default_has_a_look() -> void:
	for biome in CORE_BIOMES:
		assert_true(StreetSkyLook.LOOKS.has(biome), "%s has a look" % biome)
	assert_true(StreetSkyLook.LOOKS.has(StreetSkyLook.DEFAULT))


func test_every_look_carries_every_required_value() -> void:
	for biome: String in StreetSkyLook.LOOKS:
		for key in StreetSkyLook.REQUIRED_KEYS:
			assert_true(StreetSkyLook.LOOKS[biome].has(key), "%s has %s" % [biome, key])


func test_values_are_in_range() -> void:
	for biome: String in StreetSkyLook.LOOKS:
		var look := StreetSkyLook.look_for(biome)
		for key: String in StreetSkyLook.RANGES:
			var limits: Vector2 = StreetSkyLook.RANGES[key]
			var value := float(look[key])
			assert_between(value, limits.x, limits.y, "%s %s" % [biome, key])
		for key in ["zenith_color", "horizon_color", "far_color", "near_color", "foot_color"]:
			assert_true(look[key] is Color, "%s %s is a colour" % [biome, key])
			var color: Color = look[key]
			assert_between(color.get_luminance(), 0.05, 0.95, "%s %s luminance" % [biome, key])


func test_no_two_biomes_share_a_skyline_or_a_foot_colour() -> void:
	var seeds := {}
	var feet := {}
	for biome: String in StreetSkyLook.LOOKS:
		var look := StreetSkyLook.look_for(biome)
		assert_false(seeds.has(look["noise_seed"]), "%s seed is its own" % biome)
		seeds[look["noise_seed"]] = biome
		assert_false(feet.has(look["foot_color"]), "%s foot colour is its own" % biome)
		feet[look["foot_color"]] = biome


func test_every_value_is_a_uniform_of_the_shader() -> void:
	var shader := load("res://shaders/street_sky.gdshader") as Shader
	assert_not_null(shader)
	var uniforms := {}
	for entry in shader.get_shader_uniform_list():
		uniforms[entry["name"]] = true
	var params := StreetSkyLook.shader_params("temperate_forest", 7, Vector2(180.0, 40.0))
	for key: String in params:
		assert_true(uniforms.has(key), "uniform %s exists" % key)


func test_the_horizon_haze_is_blue_not_cream() -> void:
	# The probe's cream horizon was paler than a Ghibli blue: blue stays the largest channel of
	# the haze in every biome that has a blue sky.
	for biome in ["default", "temperate_forest", "grassland_meadow", "alpine_meadow", "boreal_taiga"]:
		var haze: Color = StreetSkyLook.look_for(biome)["horizon_color"]
		assert_gt(haze.b, haze.r, "%s haze is bluer than red" % biome)


func test_resolve_matches_a_season_and_variant_suffix() -> void:
	assert_eq(StreetSkyLook.resolve("temperate_forest_summer_s1"), "temperate_forest")
	assert_eq(StreetSkyLook.resolve("boreal_taiga"), "boreal_taiga")
	assert_eq(StreetSkyLook.resolve("rocky_badlands_autumn"), "rocky_badlands")


func test_unknown_biome_and_none_get_the_default() -> void:
	assert_eq(StreetSkyLook.resolve(""), StreetSkyLook.DEFAULT)
	assert_eq(StreetSkyLook.resolve("moon_dust"), StreetSkyLook.DEFAULT)
	# A prefix that is not a whole word does not match.
	assert_eq(StreetSkyLook.resolve("savannah"), StreetSkyLook.DEFAULT)


func test_shader_params_shift_the_seed_by_the_map_and_carry_the_sun() -> void:
	var a := StreetSkyLook.shader_params("savanna", 1, Vector2(120.0, 30.0))
	var b := StreetSkyLook.shader_params("savanna", 2, Vector2(120.0, 30.0))
	assert_ne(a["noise_seed"], b["noise_seed"], "two maps of a biome differ")
	assert_eq(StreetSkyLook.shader_params("savanna", 1, Vector2.ZERO)["noise_seed"], a["noise_seed"])
	assert_eq(a["glow_az_deg"], 120.0)
	assert_eq(a["sun_el_deg"], 30.0)
	var low := StreetSkyLook.shader_params("savanna", 1, Vector2(0.0, -20.0))
	assert_between(float(low["sun_el_deg"]), 5.0, 85.0, "a sun below the horizon is lifted")


func test_sun_angles_follow_the_shader_convention() -> void:
	# The shader: dir = (-sin az cos el, sin el, cos az cos el); az = atan(x, -z) + PI.
	for az in [0.0, 90.0, 179.3, 270.0]:
		var a := deg_to_rad(az)
		var el := deg_to_rad(35.0)
		var dir := Vector3(-sin(a) * cos(el), sin(el), cos(a) * cos(el))
		var got := StreetSkyLook.sun_angles(dir)
		assert_almost_eq(got.x, az, 0.001, "azimuth %s" % az)
		assert_almost_eq(got.y, 35.0, 0.001, "elevation at %s" % az)


func test_sun_angles_undo_the_sky_rotation() -> void:
	var dir := Vector3(0.0, 0.5, 0.866).normalized()
	var turned := StreetSkyLook.sun_angles(dir, Vector3(0.0, deg_to_rad(40.0), 0.0))
	var plain := StreetSkyLook.sun_angles(dir)
	assert_almost_eq(fposmod(turned.x - plain.x + 540.0, 360.0) - 180.0, 40.0, 0.01)
	assert_almost_eq(turned.y, plain.y, 0.001)


func test_dominant_biome_is_the_one_covering_most() -> void:
	var ids := PackedStringArray(["a", "b", "c"])
	var slots := PackedByteArray()
	slots.resize(100)
	for i in 100:
		slots[i] = 2 if i % 3 != 0 else 1
	assert_eq(StreetSkyLook.dominant_biome(ids, slots), "b")
	assert_eq(StreetSkyLook.dominant_biome(ids, PackedByteArray()), "a")
	assert_eq(StreetSkyLook.dominant_biome(PackedStringArray(), slots), "")
	var empty := PackedByteArray()
	empty.resize(50)
	assert_eq(StreetSkyLook.dominant_biome(ids, empty), "a", "no painted sample: the first id")


func test_fog_is_the_owner_verdict() -> void:
	assert_eq(StreetSkyLook.FOG_BEGIN_M, 25.0)
	assert_eq(StreetSkyLook.FOG_END_M, 85.0)
