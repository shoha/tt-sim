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


func test_a_biome_change_while_installed_repaints_the_fog_colour() -> void:
	# The still-ours check reads the biome's foot colour every frame (cached per biome): a new
	# biome must be seen by the next sync, not the one after.
	var env := _flat_env()
	_sky.sync(env, SUN)
	var temperate: Color = StreetSkyLook.look_for("temperate_forest")["foot_color"]
	var boreal: Color = StreetSkyLook.look_for("boreal_taiga")["foot_color"]
	assert_ne(temperate, boreal, "two looks to tell apart")
	assert_eq(env.fog_light_color, temperate)
	_sky.sync(env, SUN)
	_sky.set_map("boreal_taiga", 0)
	_sky.sync(env, SUN)
	assert_eq(env.fog_light_color, boreal, "the fog colour followed the biome at once")
	assert_eq((env.sky.sky_material as ShaderMaterial).get_shader_parameter("foot_color"), boreal)
	_sky.set_map("no_such_biome_anywhere", 0)
	_sky.sync(env, SUN)
	var fallback: Color = StreetSkyLook.look_for("no_such_biome_anywhere")["foot_color"]
	assert_eq(env.fog_light_color, fallback, "an unknown biome takes the default look")


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
	assert_eq(
		wanted["skirt_hold_m"], SkirtBackdrop.EYE_HOLD_M, "the ground holds past the edge at the eye"
	)
	assert_eq(SkirtBackdrop.uniforms(null, Vector3.FORWARD)["skirt_hold_m"], 0.0, "not elsewhere")


## An Environment as the painted look leaves it (PainterScene: its sky material marked
## `painter_sky`), with a preset's fog at the default hold on the sky.
func _painted_env() -> Environment:
	var env := Environment.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://painter/shaders/painter_sky.gdshader") as Shader
	material.set_meta(EyeSky.PAINTER_SKY_META, true)
	var sky := Sky.new()
	sky.sky_material = material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.fog_enabled = true
	env.fog_sky_affect = 1.0
	return env


func test_the_painted_sky_draws_its_backdrop_at_the_eye_and_not_after() -> void:
	var env := _painted_env()
	var sky := env.sky
	var material := sky.sky_material as ShaderMaterial
	_sky.sync(env, SUN)
	assert_false(_sky.is_active(), "no Classic sky is installed under Painted")
	assert_eq(env.sky, sky, "the painted sky stays")
	assert_eq(material.get_shader_parameter("eye_on"), 1.0)
	var params := EyeSky.painter_params("temperate_forest_summer_s1", 5)
	assert_almost_eq(float(material.get_shader_parameter("eye_seed")), params[&"eye_seed"], 1e-5)
	assert_almost_eq(
		float(material.get_shader_parameter("crown_deg")), params[&"crown_deg"], 1e-5, "tree-line"
	)
	assert_eq(env.fog_sky_affect, EyeSky.PAINTER_SKY_FOG, "the fog no longer hides the sky")
	_sky.leave()
	assert_eq(material.get_shader_parameter("eye_on"), 0.0, "the table view draws no backdrop")
	assert_eq(env.fog_sky_affect, 1.0, "the fog's hold on the sky is back")


func test_two_maps_have_skylines_of_their_own() -> void:
	var a := EyeSky.painter_params("temperate_forest_summer_s1", 5)
	var b := EyeSky.painter_params("temperate_forest_summer_s1", 6)
	var c := EyeSky.painter_params("grassland_meadow_summer_s1", 5)
	assert_ne(a[&"eye_seed"], b[&"eye_seed"], "another seed, another skyline")
	assert_ne(a[&"eye_seed"], c[&"eye_seed"], "another biome, another skyline")
	assert_eq(a.keys().size(), 7)


func test_painted_taking_over_drops_the_classic_eye_sky_and_keeps_its_own() -> void:
	var env := _flat_env()
	_sky.sync(env, SUN)
	assert_true(_sky.is_active())
	# What PainterScene.take writes over the Classic eye sky (a Settings Apply while in the eye).
	var painted := _painted_env()
	env.background_mode = Environment.BG_SKY
	env.sky = painted.sky
	env.fog_light_color = Color(0.9, 0.8, 0.7)
	_sky.sync(env, SUN)
	assert_false(_sky.is_active())
	assert_eq(env.sky, painted.sky, "the painted sky stays")
	assert_eq(env.fog_light_color, Color(0.9, 0.8, 0.7), "the painted haze stays")
	assert_eq(env.fog_mode, Environment.FOG_MODE_EXPONENTIAL, "the Classic eye's fog mode went back")
	assert_eq(env.fog_depth_begin, 3.0)
	assert_eq((env.sky.sky_material as ShaderMaterial).get_shader_parameter("eye_on"), 1.0)


func test_classic_taking_over_switches_the_painted_backdrop_off() -> void:
	var env := _painted_env()
	var material := env.sky.sky_material as ShaderMaterial
	_sky.sync(env, SUN)
	# PainterScene released: the level's flat colour is back.
	env.background_mode = Environment.BG_COLOR
	env.sky = null
	_sky.sync(env, SUN)
	assert_eq(material.get_shader_parameter("eye_on"), 0.0)
	assert_true(_sky.is_active(), "the Classic eye sky is installed")
