extends GutTest

## The painted look's scene host through LevelEnvironmentManager (PainterScene, docs/systems/
## painter.md): Painted takes the sun's colour and energy, the sky, the ambient light, the tonemap,
## glow and SSAO from the sheet and keeps the level's sun direction; it follows the sun and the
## preset; and leaving it restores every Environment and DirectionalLight3D property exactly.

var _saved_choice: int = RenderStyle.DEFAULT_CHOICE
var _root: Node3D = null


func before_each() -> void:
	_saved_choice = RenderStyle.choice
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	_root = Node3D.new()


func after_each() -> void:
	RenderStyle.choice = _saved_choice
	_root.free()


func _manager(preset: String = "outdoor_day", elevation: float = 50.0) -> LevelEnvironmentManager:
	var level := LevelData.new()
	level.environment_preset = preset
	level.visual_settings.sun.mode = "on"
	level.visual_settings.sun.elevation_degrees = elevation
	level.visual_settings.sun.azimuth_degrees = 120.0
	var manager := LevelEnvironmentManager.new()
	manager.apply_level_environment(level, _root)
	return manager


## Every stored property of `target` (what a save would write), by name.
static func _props(target: Object) -> Dictionary:
	var out := {}
	for prop: Dictionary in target.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_STORAGE:
			out[prop["name"]] = target.get(prop["name"])
	return out


func test_painted_takes_the_light_from_the_sheet_and_keeps_the_suns_direction() -> void:
	var manager := _manager()
	var sun := manager.get_sun_light()
	var basis_before := sun.basis
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.apply_render_style()
	var env := manager.get_world_environment().environment
	var sheet := PainterSheet.load_sheet("core")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR)
	assert_eq(env.tonemap_exposure, 1.0)
	assert_false(env.glow_enabled)
	assert_false(env.ssao_enabled)
	assert_eq(env.background_mode, Environment.BG_SKY)
	assert_true(env.sky.sky_material.has_meta(&"painter_sky"), "the painted sky is on")
	var ambient := PainterSheet.tone(sheet, "summer", "ambient", 50.0)
	assert_true(env.ambient_light_color.is_equal_approx(ambient))
	assert_true(sun.light_color.is_equal_approx(PainterSheet.tone(sheet, "summer", "sun", 50.0)))
	assert_almost_eq(sun.light_energy, PainterSheet.number(sheet, "summer", "sun-energy", 50.0), 1e-5)
	assert_eq(sun.shadow_blur, PainterScene.SHADOW_BLUR)
	assert_true(sun.basis.is_equal_approx(basis_before), "the level's sun direction stays")
	assert_eq(manager.get_render_style()["mood"], "summer")


func test_a_level_apply_marks_its_world_stale_for_the_warm_up() -> void:
	# PainterWarmup's pipelines belong to a world: the first Painted check after a level's apply asks
	# for a run over the new one (a headless run never reaches it, so the flag stays set here).
	var manager := LevelEnvironmentManager.new()
	assert_false(manager._world_stale, "nothing applied yet")
	manager.apply_level_environment(LevelData.new(), _root)
	assert_true(manager._world_stale, "the level's world is new")


func test_leaving_painted_restores_the_environment_and_sun_exactly() -> void:
	var manager := _manager()
	var env := manager.get_world_environment().environment
	var sun := manager.get_sun_light()
	var env_before := _props(env)
	var sun_before := _props(sun)
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.apply_render_style()
	assert_ne(_props(env), env_before, "Painted changed the environment")
	# Edits under Painted go through Classic first, so the restore is still exact.
	manager.apply_rendering_toggles(false, false, false)
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	manager.apply_render_style()
	manager.apply_rendering_toggles(
		env_before["ssao_enabled"], env_before["ssr_enabled"], env_before["sdfgi_enabled"]
	)
	assert_eq(_props(env), env_before, "every Environment property is back")
	assert_eq(_props(sun), sun_before, "every sun property is back")
	assert_false(manager.get_painter().is_active())


func test_a_sun_change_under_painted_restores_to_the_new_classic_sun() -> void:
	var manager := _manager()
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.apply_render_style()
	var sheet := PainterSheet.load_sheet("core")
	var low := DefaultSun.settings_for_time(17.5)
	low.mode = "on"
	manager.apply_sun_settings(low)
	var sun := manager.get_sun_light()
	var want := PainterSheet.tone(sheet, "summer", "sun", low.elevation_degrees)
	assert_true(sun.light_color.is_equal_approx(want), "the sun follows the time of day")
	assert_almost_eq(sun.rotation_degrees.x, -low.elevation_degrees, 1e-3, "direction from the level")
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	manager.apply_render_style()
	assert_true(sun.light_color.is_equal_approx(low.color), "Classic shows the level's own colour")
	assert_almost_eq(sun.light_energy, low.energy, 1e-5)
	assert_eq(sun.shadow_blur, 2.0)


func test_a_classic_only_preset_draws_classic_and_restores() -> void:
	var manager := _manager()
	var reference := _manager("dungeon_dark")
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.apply_render_style()
	manager.apply_environment_settings("dungeon_dark", {})
	assert_eq(manager.get_render_style()["style"], RenderStyle.CLASSIC)
	var env := manager.get_world_environment().environment
	var ref_env := reference.get_world_environment().environment
	assert_eq(env.tonemap_mode, ref_env.tonemap_mode)
	assert_true(env.ambient_light_color.is_equal_approx(ref_env.ambient_light_color))
	assert_eq(env.sky, ref_env.sky)
	manager.apply_environment_settings("outdoor_sunset", {})
	assert_eq(manager.get_render_style()["mood"], "dusk", "a painted preset paints again")
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR)


func test_the_maps_look_applies_under_maps_choice() -> void:
	var manager := _manager()
	RenderStyle.choice = RenderStyle.CHOICE_MAP
	manager.set_look({"style": RenderStyle.PAINTED, "sheet": "", "mood": "winter"})
	assert_eq(manager.get_render_style()["mood"], "winter")
	var sheet := PainterSheet.load_sheet("core")
	var sun := manager.get_sun_light()
	assert_true(sun.light_color.is_equal_approx(PainterSheet.tone(sheet, "winter", "sun", 50.0)))
	manager.set_look({})
	assert_eq(sun.shadow_blur, 2.0, "a Classic look lets go")


func test_the_sky_carries_the_moods_eye_backdrop_but_the_table_view_draws_none() -> void:
	var manager := _manager()
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.apply_render_style()
	var material := manager.get_world_environment().environment.sky.sky_material as ShaderMaterial
	var sheet := PainterSheet.load_sheet("core")
	var wanted := PainterBackdrop.uniforms(sheet, "summer", 50.0)
	for key: StringName in wanted:
		var got: Variant = material.get_shader_parameter(key)
		if got is Color:
			assert_true((got as Color).is_equal_approx(wanted[key]), str(key))
		else:
			assert_almost_eq(float(got), float(wanted[key]), 1e-5, str(key))
	assert_ne(material.get_shader_parameter("eye_on"), 1.0, "only EyeSky switches the backdrop on")


func test_the_backdrop_follows_the_mood() -> void:
	var sheet := PainterSheet.load_sheet("core")
	var summer := PainterBackdrop.uniforms(sheet, "summer", 50.0)
	var grim := PainterBackdrop.uniforms(sheet, "grimdark", 27.0)
	var dusk := PainterBackdrop.uniforms(sheet, "dusk", 24.0)
	assert_gt(float(grim[&"cloud_cover"]), float(summer[&"cloud_cover"]), "a grey sky is clouded")
	for mood: Dictionary in [summer, grim, dusk]:
		var far := PainterSheet.lch_of_color(mood[&"hill_far_color"])
		var near := PainterSheet.lch_of_color(mood[&"hill_near_color"])
		assert_lt(far.x, 0.99, "the far range is not white")
		assert_ne(far, near, "the ranges differ")
	var dusk_far := PainterSheet.lch_of_color(dusk[&"hill_far_color"])
	assert_between(dusk_far.z, 250.0, 340.0, "a dusk range is violet")
	var light := PainterSheet.lch_of_color(summer[&"cloud_light_color"])
	var shade := PainterSheet.lch_of_color(summer[&"cloud_shade_color"])
	assert_gt(light.x, shade.x, "a cloud's top is lighter than its underside")
	assert_gt(shade.y, 0.02, "the underside is coloured, never grey")
