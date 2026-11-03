extends GutTest

## EyeSky: the painted sky and edge fog the eye view installs in the level's Environment and takes
## away again (card eyesky). Plain Environment resources, no scene.

const SUN := Vector3(0.0, 0.64, 0.77)

var _sky: EyeSky


func before_each() -> void:
	EyeSky.enabled = true
	_sky = EyeSky.new()
	_sky.set_map("temperate_forest_summer_s1", 5)


func after_each() -> void:
	EyeSky.enabled = true


func _flat_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.4, 0.5, 0.6)
	env.fog_enabled = false
	env.fog_light_color = Color(0.1, 0.2, 0.3)
	# Godot 4.7 resets fog_density when fog_mode is assigned: the mode first.
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.02
	env.fog_depth_begin = 3.0
	env.fog_depth_end = 9.0
	env.fog_sky_affect = 0.7
	return env


func _hdri_env() -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var material := PanoramaSkyMaterial.new()
	material.panorama = ImageTexture.create_from_image(Image.create(4, 2, false, Image.FORMAT_RGBF))
	material.energy_multiplier = 0.75
	var sky := Sky.new()
	sky.sky_material = material
	env.sky = sky
	return env


func test_a_flat_level_gets_the_painted_sky_and_the_edge_fog() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	assert_true(_sky.is_active())
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.sky.sky_material is ShaderMaterial)
	var material := env.sky.sky_material as ShaderMaterial
	assert_false(material.get_shader_parameter("use_panorama"))
	assert_eq(material.get_shader_parameter("flat_color"), Color(0.4, 0.5, 0.6))
	assert_eq(material.get_shader_parameter("exposure"), 1.0)
	assert_eq(material.get_shader_parameter("foot_on"), 1.0)
	assert_true(env.fog_enabled)
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_eq(env.fog_depth_begin, 25.0)
	assert_eq(env.fog_depth_end, 85.0)
	assert_eq(env.fog_sky_affect, 0.0)
	var foot: Color = StreetSkyLook.look_for("temperate_forest")["foot_color"]
	assert_eq(env.fog_light_color, foot, "fog colour is the foot colour")
	assert_eq(material.get_shader_parameter("foot_color"), foot)


func test_leaving_puts_every_field_back() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	_sky.leave()
	assert_false(_sky.is_active())
	assert_eq(env.background_mode, Environment.BG_COLOR)
	assert_null(env.sky)
	assert_false(env.fog_enabled)
	assert_eq(env.fog_light_color, Color(0.1, 0.2, 0.3))
	assert_almost_eq(env.fog_density, 0.02, 0.0001)
	assert_eq(env.fog_mode, Environment.FOG_MODE_EXPONENTIAL)
	assert_eq(env.fog_depth_begin, 3.0)
	assert_eq(env.fog_depth_end, 9.0)
	assert_almost_eq(env.fog_sky_affect, 0.7, 0.0001)


func test_an_hdri_keeps_its_panorama_and_exposure_for_the_lighting_pass() -> void:
	var env := _hdri_env()
	var original := env.sky
	_sky.sync(env, SUN)
	var material := env.sky.sky_material as ShaderMaterial
	assert_true(material.get_shader_parameter("use_panorama"))
	var panorama := (original.sky_material as PanoramaSkyMaterial).panorama
	assert_eq(material.get_shader_parameter("source_panorama"), panorama)
	assert_almost_eq(float(material.get_shader_parameter("exposure")), 0.75, 0.0001)
	_sky.leave()
	assert_eq(env.sky, original, "the same Sky resource is back, not a copy")
	assert_eq(env.background_mode, Environment.BG_SKY)


func test_a_gradient_sky_is_left_alone() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	_sky.sync(env, SUN)
	assert_false(_sky.is_active())
	assert_eq(env.sky, sky)
	assert_false(env.fog_enabled)
	_sky.leave()
	assert_eq(env.sky, sky)


func test_a_reapplied_environment_is_taken_as_the_new_original_and_painted_again() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	# The level manager re-applies a preset: flat colour again, new fog.
	env.background_mode = Environment.BG_COLOR
	env.sky = null
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.9, 0.9)
	env.fog_density = 0.05
	_sky.sync(env, SUN)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.sky.sky_material is ShaderMaterial)
	assert_eq(env.fog_depth_end, 85.0)
	_sky.leave()
	assert_eq(env.background_mode, Environment.BG_COLOR)
	assert_null(env.sky)
	assert_eq(env.fog_light_color, Color(0.9, 0.9, 0.9), "leaving restores the re-applied values")
	assert_almost_eq(env.fog_density, 0.05, 0.0001)
	assert_eq(env.fog_depth_end, 9.0, "fields the manager never writes keep the first originals")


func test_a_steady_environment_is_not_rewritten_every_frame() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	var sky := env.sky
	_sky.sync(env, SUN)
	assert_eq(env.sky, sky, "the same Sky (no radiance re-bake)")
	assert_eq(_sky.material(), sky.sky_material)


func test_the_fog_follows_the_reach_and_the_glide_offset() -> void:
	var env := _flat_env()
	_sky.reach = 100.0
	_sky.sync(env, SUN)
	var fog := StreetSkyLook.fog_range(100.0)
	assert_almost_eq(env.fog_depth_begin, fog.x, 0.001, "installed at the map's scale")
	assert_almost_eq(env.fog_depth_end, fog.y, 0.001)
	_sky.fog_offset = 500.0
	_sky.sync(env, SUN)
	assert_almost_eq(env.fog_depth_begin, fog.x + 500.0, 0.001, "the glide still moves it out")
	_sky.fog_offset = 0.0
	_sky.reach = 0.0
	_sky.sync(env, SUN)
	assert_almost_eq(env.fog_depth_begin, 25.0, 0.001, "no map: the verdict's 25 m")


func test_a_moved_sun_updates_the_glow() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	var before: float = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("glow_az_deg")
	_sky.sync(env, Vector3(0.77, 0.64, 0.0))
	var after: float = (env.sky.sky_material as ShaderMaterial).get_shader_parameter("glow_az_deg")
	assert_ne(before, after)


func test_the_map_biome_picks_the_look() -> void:
	var env := _flat_env()
	_sky.set_map("boreal_taiga", 0)
	_sky.sync(env, SUN)
	var foot: Color = StreetSkyLook.look_for("boreal_taiga")["foot_color"]
	assert_eq(env.fog_light_color, foot)


func test_disabled_does_nothing() -> void:
	EyeSky.enabled = false
	var env := _flat_env()
	_sky.sync(env, SUN)
	assert_false(_sky.is_active())
	assert_eq(env.background_mode, Environment.BG_COLOR)


func test_the_skirt_fades_to_the_foot_colour_under_the_painted_sky() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	var wanted := SkirtBackdrop.uniforms(env, Vector3(0.0, 0.0, -1.0))
	var foot: Color = StreetSkyLook.look_for("temperate_forest")["foot_color"]
	var lin := foot.srgb_to_linear()
	assert_eq(wanted["skirt_backdrop_mode"], SkirtBackdrop.MODE_COLOR)
	assert_true((wanted["skirt_backdrop"] as Vector3).is_equal_approx(Vector3(lin.r, lin.g, lin.b)))
	assert_eq((wanted["skirt_fog_depth"] as Vector4).y, 25.0, "the skirt fogs by the same 25 m")
	assert_eq((wanted["skirt_fog_params"] as Vector4).w, 0.0, "fog does not touch the backdrop")
