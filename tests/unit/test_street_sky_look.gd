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


func test_the_reach_is_the_farthest_corner_at_every_yaw() -> void:
	# A 150 ft (45.72 m) map centred on the origin, the eye at (10, 10): the far corner is
	# 32.86 m away on each axis.
	var bounds := AABB(Vector3(-22.86, 0.0, -22.86), Vector3(45.72, 4.0, 45.72))
	var reach := StreetSkyLook.map_reach(Vector2(10.0, 10.0), bounds)
	assert_almost_eq(reach, Vector2(32.86, 32.86).length(), 0.001)
	assert_almost_eq(
		StreetSkyLook.map_reach(Vector2.ZERO, bounds), Vector2(22.86, 22.86).length(), 0.001
	)
	assert_eq(StreetSkyLook.map_reach(Vector2(3.0, 4.0), AABB()), 0.0, "no map: no reach")


func test_the_fog_keeps_a_small_valley_clear_and_scales_with_the_map() -> void:
	# No map: the owner's 25 to 85 m.
	assert_eq(StreetSkyLook.fog_range(0.0), Vector2(25.0, 85.0))
	# The 150 ft valley from (10, 10): the fog begins past the middle of the far side, so the
	# ground across the valley (30 to 45 m) is nearly clear.
	var small := StreetSkyLook.fog_range(46.47)
	assert_gt(small.x, 30.0, "begins past the across-the-valley ground")
	assert_lt(small.x, 46.47, "begins on the map")
	assert_gt(small.y, 46.47, "ends past the farthest edge")
	assert_lt(_fog_amount(small, 45.0), 0.1, "the far side of the valley is not a veil")
	# A large map (about 1000 ft, eye at its centre): further out, still ending past the edge.
	var big := StreetSkyLook.fog_range(215.0)
	assert_gt(big.x, small.x)
	assert_gt(big.y, 215.0)
	assert_almost_eq(big.x, 215.0 * StreetSkyLook.FOG_BEGIN_REACH, 0.001, "begin follows the reach")
	assert_almost_eq(big.y, 215.0 * StreetSkyLook.FOG_END_REACH, 0.001, "end follows the reach")
	# A short reach changes nothing: the floors (25 and 85 m) stand until the map outgrows them.
	assert_eq(StreetSkyLook.fog_range(10.0), StreetSkyLook.fog_range(0.0))
	# Never nearer than the verdict, and the ramp never shorter than its 60 m.
	for reach in [0.0, 5.0, 20.0, 46.0, 80.0, 300.0]:
		var fog := StreetSkyLook.fog_range(reach)
		assert_true(fog.x >= 25.0 and fog.y >= 85.0, "floors at reach %s" % reach)
		assert_true(fog.y - fog.x >= 60.0 - 0.001, "ramp at reach %s" % reach)
	# Monotonic: walking toward the middle never thickens the fog.
	assert_true(StreetSkyLook.fog_range(60.0).x <= StreetSkyLook.fog_range(61.0).x)


## Godot's depth fog amount at `d` metres for begin and end `fog` (curve 1, density 1).
func _fog_amount(fog: Vector2, d: float) -> float:
	return smoothstep(fog.x, fog.y, d)
