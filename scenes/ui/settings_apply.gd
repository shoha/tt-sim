class_name SettingsApply
extends RefCounted

## What Apply does with the Settings menu's controls, and what the live preview does with some of
## them, split out of settings_menu.gd to keep that file under the lint budget. Every function
## reads the menu's controls and acts on the renderer, the open map or an autoload; none saves.


## Everything Apply applies: audio, window, look, shadows, water, grid and network.
static func all(menu: SettingsMenu) -> void:
	# Sliders are percent, buses take 0..1.
	AudioManager.set_bus_volume(AudioManager.BUS_MASTER, menu.master_slider.value / 100.0)
	AudioManager.set_bus_volume(AudioManager.BUS_MUSIC, menu.music_slider.value / 100.0)
	AudioManager.set_bus_volume(AudioManager.BUS_SFX, menu.sfx_slider.value / 100.0)
	AudioManager.set_bus_volume(AudioManager.BUS_UI, menu.ui_slider.value / 100.0)

	# Defer fullscreen mode change: macOS native fullscreen (`toggleFullScreen:`) requires the
	# window to be fully presented and the run-loop to be idle.
	SettingsMenu._set_window_fullscreen.call_deferred(menu.fullscreen_check.button_pressed)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if menu.vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)

	# The options a preview leaves alone: foliage edges, the foliage antialiasing level, shadow
	# cascades, the look (which the rendering toggles' apply then carries to the open map, so it
	# comes before the preview) and the render scale (the world viewport's 3D resolution).
	var game_map := menu._find_game_map()
	SettingsGpuOptions.apply(menu, game_map)
	SettingsRenderScale.apply(menu, game_map)
	preview(menu)
	AssetManager.streamer.set_enabled(menu.p2p_enabled_check.button_pressed)


## The rows that show on the board as they are moved, before Apply (SettingsSpec.APPLY_ONLY names
## the rest): lo-fi, token shading, see-through, shadow quality, water, the rendering toggles and
## the grid.
static func preview(menu: SettingsMenu) -> void:
	var game_map := menu._find_game_map()
	if game_map:
		game_map.set_lofi_enabled(menu.lofi_check.button_pressed)
	SettingsTokenShading.apply(menu)
	SettingsSeeThrough.apply(menu, game_map)
	# Global renderer settings: no map is needed, so they apply from the title screen too. Shadow
	# quality is scoped to directional shadows, as DebugRenderToggles' "Hard sun shadows" tested.
	RenderingServer.directional_soft_shadow_filter_set_quality(
		menu.shadow_quality_option.get_selected_id()
	)
	var skip_low_detail := menu.water_quality_option.get_selected_id() == SettingsMenu.WaterQuality.LOW
	RenderingServer.global_shader_parameter_set("water_quality_skip_fine_detail", skip_low_detail)
	RenderingServer.global_shader_parameter_set("water_quality_skip_refraction", skip_low_detail)
	# The rendering toggles need the open level's environment: a no-op on the title screen, where
	# they take effect when a level loads.
	var controller := menu._find_level_play_controller()
	if controller:
		controller.get_environment_manager().apply_rendering_toggles(
			menu.ssao_check.button_pressed,
			menu.ssr_check.button_pressed,
			menu.sdfgi_check.button_pressed
		)
	if game_map:
		game_map.apply_grid_visual_settings(
			menu.cell_tint_opacity_slider.value / 100.0,
			menu.line_thickness_slider.value,
			menu.fade_distance_slider.value
		)
