extends GutTest

## RenderScale (utils/render_scale.gd) and its Settings row (SettingsRenderScale): the default is
## the full render (the game before the setting), a saved choice round-trips through the settings
## file, Auto's resolution rule, and a choice reaching the world SubViewport.

const TMP_SETTINGS := "user://test_render_scale_settings.cfg"

var _saved_current: int


func before_each() -> void:
	_saved_current = RenderScale.current


func after_each() -> void:
	RenderScale.current = _saved_current
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_SETTINGS))


func test_default_is_the_full_render() -> void:
	assert_eq(RenderScale.DEFAULT, RenderScale.FULL)
	assert_eq(RenderScale.stored(ConfigFile.new()), RenderScale.FULL)
	# 100 % with no Interface size factor is no scaling at all: the game before the setting.
	assert_eq(RenderScale.scale_3d(RenderScale.DEFAULT, Vector2(3840, 2160)), 1.0)
	# The viewport itself is output-sized (WorldView), so 100 % is a 3D scale of exactly 1.
	assert_eq(RenderScale.scale_3d(RenderScale.DEFAULT, Vector2(1280, 720)), 1.0)


func test_stored_sanitizes_unknown_and_wrong_typed_values() -> void:
	var config := ConfigFile.new()
	config.set_value("graphics", RenderScale.KEY, 75)
	assert_eq(RenderScale.stored(config), 75)
	config.set_value("graphics", RenderScale.KEY, RenderScale.AUTO)
	assert_eq(RenderScale.stored(config), RenderScale.AUTO)
	config.set_value("graphics", RenderScale.KEY, 42)
	assert_eq(RenderScale.stored(config), RenderScale.DEFAULT)
	config.set_value("graphics", RenderScale.KEY, "fast")
	assert_eq(RenderScale.stored(config), RenderScale.DEFAULT)


func test_auto_keeps_the_full_render_at_1080p_and_up() -> void:
	# The viewport is output-sized there, so Auto is the full render (a player lowers it by hand).
	for size in [Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160), Vector2(2560, 1080)]:
		assert_eq(RenderScale.fraction_for(RenderScale.AUTO, size), 1.0, str(size))
		assert_eq(RenderScale.scale_3d(RenderScale.AUTO, size), 1.0, str(size))


func test_auto_renders_the_window_size_below_1080p() -> void:
	# A 720p window at Interface size 100 % shows 1280x720 of a 1920x1080 viewport: Auto draws
	# 1280x720 (two thirds) and FSR enlarges it, instead of the 2.25x supersample.
	assert_almost_eq(RenderScale.fraction_for(RenderScale.AUTO, Vector2(1280, 720)), 2.0 / 3.0, 1e-4)
	var scale := RenderScale.scale_3d(RenderScale.AUTO, Vector2(1280, 720))
	assert_almost_eq(scale, 2.0 / 3.0, 1e-4)
	assert_eq(RenderScale.mode_for(scale), Viewport.SCALING_3D_MODE_FSR)
	assert_eq(
		RenderScale.render_size(RenderScale.AUTO, Vector2(1280, 720)).round(), Vector2(1280, 720)
	)


func test_auto_snaps_to_the_viewport_size_when_the_window_nearly_matches() -> void:
	# A 1800x1012 window shows 0.937 of the 1920x1080 viewport: within AUTO_SNAP, so Auto renders
	# the viewport's own size instead of an upscale pass over a nearly equal one.
	var scale := RenderScale.scale_3d(RenderScale.AUTO, Vector2(1800, 1012))
	assert_eq(scale, 1.0)
	assert_eq(RenderScale.mode_for(scale), Viewport.SCALING_3D_MODE_BILINEAR)
	# A fixed choice never snaps.
	assert_almost_eq(RenderScale.scale_3d(67, Vector2(1800, 1012)), 0.67, 1e-6)


func test_fixed_choices_scale_the_full_render() -> void:
	assert_almost_eq(RenderScale.scale_3d(75, Vector2(1920, 1080)), 0.75, 1e-6)
	assert_almost_eq(RenderScale.scale_3d(50, Vector2(3840, 2160)), 0.5, 1e-6)
	assert_eq(RenderScale.render_size(75, Vector2(1920, 1080)), Vector2(1440, 810))
	# The share is of the output-sized viewport: FSR 50 % at 4K draws 1920x1080, 75 % at 1440p
	# draws 1920x1080 too.
	assert_eq(RenderScale.render_size(50, Vector2(3840, 2160)), Vector2(1920, 1080))
	assert_eq(RenderScale.render_size(75, Vector2(2560, 1440)), Vector2(1920, 1080))
	assert_eq(RenderScale.mode_for(0.75), RenderScale.UPSCALER)
	assert_eq(RenderScale.mode_for(1.0), Viewport.SCALING_3D_MODE_BILINEAR)


func test_labels_name_the_render_size() -> void:
	assert_eq(RenderScale.label_for(100, Vector2(1920, 1080)), "100% (1920x1080, full)")
	assert_eq(RenderScale.label_for(50, Vector2(3840, 2160)), "50% (1920x1080)")
	assert_eq(RenderScale.label_for(100, Vector2(3840, 2160)), "100% (3840x2160, full)")
	assert_eq(RenderScale.label_for(RenderScale.AUTO, Vector2(2560, 1440)), "Auto (2560x1440 here)")


func test_a_choice_reaches_the_world_subviewport() -> void:
	var viewport := SubViewport.new()
	add_child_autofree(viewport)
	var scale := RenderScale.apply_to(viewport, null, 50)
	assert_eq(scale, 0.5)
	assert_eq(viewport.scaling_3d_scale, 0.5)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)
	assert_almost_eq(viewport.fsr_sharpness, RenderScale.FSR_SHARPNESS, 1e-6)
	RenderScale.apply_to(viewport, null, RenderScale.FULL)
	assert_eq(viewport.scaling_3d_scale, 1.0)
	assert_eq(viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_BILINEAR)


func test_game_map_applies_the_current_choice_to_its_world_viewport() -> void:
	var game_map: GameMap = preload("res://scenes/states/playing/game_map.tscn").instantiate()
	add_child_autofree(game_map)
	await wait_physics_frames(1)
	RenderScale.current = 75
	# The handler a window resize or an Interface size change runs.
	game_map._match_world_render()
	assert_almost_eq(game_map.world_viewport.scaling_3d_scale, 0.75, 1e-4)
	assert_eq(game_map.world_viewport.scaling_3d_mode, Viewport.SCALING_3D_MODE_FSR)


func test_settings_menu_saves_and_shows_the_choice() -> void:
	var menu: SettingsMenu = preload("res://scenes/ui/settings_menu.tscn").instantiate()
	add_child_autofree(menu)
	var option := menu.render_scale_option
	assert_eq(option.item_count, RenderScale.CHOICES.size())
	for choice in RenderScale.CHOICES:
		assert_true(option.get_item_index(choice) >= 0, "choice %d offered" % choice)
	option.select(option.get_item_index(67))
	menu._save_settings(TMP_SETTINGS)
	var config := ConfigFile.new()
	assert_eq(config.load(TMP_SETTINGS), OK)
	assert_eq(config.get_value("graphics", RenderScale.KEY), 67)
	SettingsRenderScale.show_defaults(menu)
	assert_eq(option.get_selected_id(), RenderScale.DEFAULT)
	SettingsRenderScale.show_saved(menu, config)
	assert_eq(option.get_selected_id(), 67)
