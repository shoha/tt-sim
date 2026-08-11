class_name SettingsMenu
extends AnimatedCanvasLayerPanel

## Settings menu with Audio, Graphics, and Controls tabs.
##
## Integrates with UIManager for proper overlay handling.
## Settings are saved to user://settings.cfg

signal closed

## Water Quality tiers (Settings > Graphics). A project-defined enum, not a
## RenderingServer builtin (unlike Shadow Quality) since this is a
## project-specific feature, not an engine one.
enum WaterQuality { LOW, MEDIUM, HIGH }

const SLIDER_TICK_INTERVAL := 0.08  # Minimum seconds between slider tick sounds

## Maps the "Renderer" OptionButton's item ids to the string values Godot's
## rendering/renderer/rendering_method project setting and --rendering-method
## command-line argument both accept. Index 0 ("" / Default) means "don't
## force anything -- respect project.godot's own per-platform choice,"
## matching the behavior shipped before this setting existed. Item ids in the
## .tscn are authored to equal these indices exactly (0-3) -- this is the
## single source of truth both directions must agree with.
const _RENDERING_METHOD_VALUES: PackedStringArray = [
	"",
	"forward_plus",
	"mobile",
	"gl_compatibility",
]

## Appended (after a "--" separator) to every relaunch this file triggers, and
## checked for on every boot before considering a relaunch at all. Guarantees
## at most one relaunch hop per real launch even if the requested renderer
## turns out unsupported and the engine silently falls back to a different
## one -- without this, a boot that keeps disagreeing with its own saved
## preference would relaunch forever. OS.get_cmdline_args() only returns
## engine-consumed arguments and never anything after "--", so this sentinel
## must be read via OS.get_cmdline_user_args() instead.
const _RELAUNCH_SENTINEL_ARG := "--renderer-relaunched"

var _last_slider_tick_time: float = 0.0

# Audio controls
@onready var master_slider: HSlider = %MasterVolumeSlider
@onready var master_label: Label = %MasterVolumeLabel
@onready var music_slider: HSlider = %MusicVolumeSlider
@onready var music_label: Label = %MusicVolumeLabel
@onready var sfx_slider: HSlider = %SFXVolumeSlider
@onready var sfx_label: Label = %SFXVolumeLabel
@onready var ui_slider: HSlider = %UIVolumeSlider
@onready var ui_label: Label = %UIVolumeLabel

# Tab container for cross-fade transitions
@onready var tab_container: TabContainer = %TabContainer

# Graphics controls
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var vsync_check: CheckButton = %VSyncCheck
@onready var lofi_check: CheckButton = %LofiCheck
@onready var occlusion_fade_check: CheckButton = %OcclusionFadeCheck
@onready var antialiasing_option: OptionButton = %AntialiasingOption
@onready var shadow_quality_option: OptionButton = %ShadowQualityOption
@onready var water_quality_option: OptionButton = %WaterQualityOption
@onready var renderer_method_option: OptionButton = %RendererMethodOption

# Grid visual controls
@onready var cell_tint_opacity_slider: HSlider = %CellTintOpacitySlider
@onready var cell_tint_opacity_label: Label = %CellTintOpacityLabel
@onready var line_thickness_slider: HSlider = %LineThicknessSlider
@onready var line_thickness_label: Label = %LineThicknessLabel
@onready var fade_distance_slider: HSlider = %FadeDistanceSlider
@onready var fade_distance_label: Label = %FadeDistanceLabel

# Controls display
@onready var input_device_option: OptionButton = %InputDeviceOption
@onready var controls_list: VBoxContainer = %ControlsList

# Network controls
@onready var p2p_enabled_check: CheckButton = %P2PEnabledCheck
@onready var clear_cache_button: Button = %ClearCacheButton
@onready var cache_info_label: Label = %CacheInfo

# Update controls
@onready var updates_tab: ScrollContainer = %Updates
@onready var version_label: Label = %VersionLabel
@onready var prereleases_check: CheckButton = %PrereleasesCheck
@onready var check_updates_button: Button = %CheckUpdatesButton
@onready var update_status_label: Label = %UpdateStatus

# Buttons
@onready var close_button: Button = %CloseButton
@onready var reset_button: Button = %ResetButton
@onready var apply_button: Button = %ApplyButton


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		animate_out()
		get_viewport().set_input_as_handled()


## Apply saved graphics settings (fullscreen, vsync, shadow quality) at startup.
## Call this early (e.g. from Root._ready()) so the window mode is correct
## before any UI is shown.  Fullscreen is deferred so the window is fully
## presented first — required on macOS where native fullscreen is async. A
## fresh install with no settings.cfg returns early and simply keeps whatever
## project.godot's own boot-time default already applied (see
## rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality)
## -- there is nothing saved yet to override it with.
static func apply_startup_graphics_settings() -> void:
	var config = ConfigFile.new()
	if config.load(Paths.SETTINGS_PATH) != OK:
		return

	var fullscreen: bool = config.get_value("graphics", "fullscreen", false)
	var vsync: bool = config.get_value("graphics", "vsync", true)

	# Apply vsync immediately (safe on all platforms)
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)

	var shadow_quality: int = config.get_value(
		"graphics", "shadow_quality", RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	)
	RenderingServer.directional_soft_shadow_filter_set_quality(shadow_quality)

	# Defer fullscreen — macOS native fullscreen requires the window to be
	# fully presented before `toggleFullScreen:` will take effect.
	_set_window_fullscreen.call_deferred(fullscreen)


## Check whether the saved rendering-method preference differs from whatever
## is actually active this boot, and relaunch the process with the correct
## --rendering-method flag if so. Call this early (e.g. from Root._ready(),
## alongside apply_startup_graphics_settings()) so a normal launch -- which
## never knows to pass this flag on its own -- still ends up on the player's
## saved choice. Godot decides the rendering method when the rendering server
## boots, before any GDScript runs, so there is no live "just apply it" path
## the way there is for MSAA/antialiasing; a relaunch is the only lever.
##
## No-ops entirely under a headless run (DisplayServer.get_name() ==
## "headless") -- without this guard, `godot --headless --path . --quit-after 1`
## (which, unlike GUT's test runner, does boot the real Root main scene) would
## attempt a relaunch on any machine with a non-default local preference
## saved, on every syntax check.
## Guards against relaunching more than once per real launch via a sentinel
## user argument (see _RELAUNCH_SENTINEL_ARG) -- necessary because a requested
## renderer that turns out unsupported on the player's GPU would otherwise
## disagree with its own saved preference forever.
static func apply_startup_rendering_method() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if OS.get_cmdline_user_args().has(_RELAUNCH_SENTINEL_ARG):
		return

	var config = ConfigFile.new()
	if config.load(Paths.SETTINGS_PATH) != OK:
		return

	var saved: String = config.get_value("graphics", "rendering_method", "")
	var active: String = _get_active_rendering_method()
	if not _rendering_method_needs_relaunch(saved, active):
		return

	var args := _build_relaunch_args(OS.get_cmdline_args(), saved)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_warning(
			"SettingsMenu: failed to relaunch with --rendering-method %s (pid %d)" % [saved, pid]
		)
		return
	Engine.get_main_loop().quit()


## Set the window fullscreen mode, guarding against redundant toggles.
## Extracted as a static helper so it can be used with call_deferred().
static func _set_window_fullscreen(enable: bool) -> void:
	var current_mode := DisplayServer.window_get_mode()
	var is_currently_fullscreen := (
		current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN
		or current_mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	)

	if enable and not is_currently_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not enable and is_currently_fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


## Single source of truth for "what rendering method is actually active this
## boot." Deliberately NOT ProjectSettings.get_setting(
## "rendering/renderer/rendering_method") -- that always returns
## project.godot's base value, ignoring both a --rendering-method CLI
## override and this project's own per-platform feature-tag override
## (renderer/rendering_method.macos). RenderingServer reflects the true,
## resolved-and-initialized method, including CLI overrides, platform
## overrides, and hardware-forced fallbacks.
static func _get_active_rendering_method() -> String:
	return RenderingServer.get_current_rendering_method()


## Pure comparison: true only when [param saved] names a specific renderer
## (never for "" / Default, which means "don't force anything") and it
## differs from [param active].
static func _rendering_method_needs_relaunch(saved: String, active: String) -> bool:
	return saved != "" and saved != active


## Build a new command-line argument list from [param current_args] with any
## existing "--rendering-method <value>" pair removed and a fresh one for
## [param method] appended, followed by a "--" separator and
## _RELAUNCH_SENTINEL_ARG (see its own doc comment for why).
##
## [param current_args] is OS.get_cmdline_args(), which only contains
## arguments the *engine* itself did not already consume -- flags a player's
## original launch used that Godot recognizes (--fullscreen, --max-fps,
## --path, a Steam launch option) are already gone from this list before this
## function ever sees it and cannot be recovered here. This is a Godot API
## limitation, not a bug in this function.
static func _build_relaunch_args(
	current_args: PackedStringArray, method: String
) -> PackedStringArray:
	var result: Array[String] = []
	var i := 0
	while i < current_args.size():
		if current_args[i] == "--rendering-method":
			i += 2  # skip the flag and its value
			continue
		result.append(current_args[i])
		i += 1
	result.append("--rendering-method")
	result.append(method)
	result.append("--")
	result.append(_RELAUNCH_SENTINEL_ARG)
	return PackedStringArray(result)


func _on_panel_ready() -> void:
	# Connect UI signals
	close_button.pressed.connect(_on_close_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	apply_button.pressed.connect(_on_apply_pressed)

	# Audio sliders (config-driven: [slider, label, bus_name])
	for binding in [
		[master_slider, master_label, "Master"],
		[music_slider, music_label, "Music"],
		[sfx_slider, sfx_label, "SFX"],
		[ui_slider, ui_label, "UI"],
	]:
		binding[0].value_changed.connect(_on_volume_changed.bind(binding[1], binding[2]))

	# Graphics
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	vsync_check.toggled.connect(_on_vsync_toggled)
	lofi_check.toggled.connect(_on_lofi_toggled)
	occlusion_fade_check.toggled.connect(_on_occlusion_fade_toggled)
	antialiasing_option.item_selected.connect(_on_antialiasing_selected)
	shadow_quality_option.item_selected.connect(_on_shadow_quality_selected)
	water_quality_option.item_selected.connect(_on_water_quality_selected)
	renderer_method_option.item_selected.connect(_on_renderer_method_selected)

	# Grid visuals
	cell_tint_opacity_slider.value_changed.connect(_on_cell_tint_opacity_changed)
	line_thickness_slider.value_changed.connect(_on_line_thickness_changed)
	fade_distance_slider.value_changed.connect(_on_fade_distance_changed)

	# Controls
	input_device_option.item_selected.connect(_on_input_device_selected)
	InputProfile.profile_changed.connect(_on_input_profile_changed)

	# Network
	p2p_enabled_check.toggled.connect(_on_p2p_toggled)
	clear_cache_button.pressed.connect(_on_clear_cache_pressed)

	# Updates
	prereleases_check.toggled.connect(_on_prereleases_toggled)
	check_updates_button.pressed.connect(_on_check_updates_pressed)

	# Hide Updates tab for Steam users — Steam handles updates
	if not OS.get_environment("SteamAppId").is_empty():
		tab_container.set_tab_hidden(updates_tab.get_index(), true)

	# Tab transition animation
	tab_container.tab_changed.connect(_on_tab_changed)

	# Apply tooltips to settings controls
	_apply_tooltips()

	# Load current settings
	_load_settings()
	_populate_controls_list()
	_update_cache_info()
	_update_version_info()

	# Register as overlay (cast to Control for type compatibility)
	UIManager.register_overlay($ColorRect as Control)


func _on_before_animate_out() -> void:
	if InputProfile.profile_changed.is_connected(_on_input_profile_changed):
		InputProfile.profile_changed.disconnect(_on_input_profile_changed)
	UIManager.unregister_overlay($ColorRect as Control)


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


func _populate_controls_list() -> void:
	# Clear existing
	for child in controls_list.get_children():
		child.queue_free()

	# Add control hints (profile-aware labels)
	var controls: Array[Array] = [
		["Left Click + Drag", "Move token"],
		["Right Click", "Open context menu"],
		[InputProfile.label(&"zoom"), "Zoom camera"],
		[InputProfile.label(&"pan"), "Pan camera"],
		[InputProfile.label(&"rotate"), "Rotate token"],
		[InputProfile.label(&"scale"), "Scale token"],
		[InputProfile.label(&"reset_transform"), "Reset token transform"],
		[InputProfile.label(&"reset_camera"), "Reset camera"],
		[InputProfile.label(&"wasd"), "Move camera"],
		[InputProfile.label(&"measure"), "Measure tool"],
		[InputProfile.label(&"grid"), "Toggle grid"],
		[InputProfile.label(&"pause"), "Pause / Close menu"],
	]

	for control in controls:
		var hbox := HBoxContainer.new()

		var key_label := Label.new()
		key_label.text = control[0]
		key_label.theme_type_variation = "Body"
		key_label.custom_minimum_size = Vector2(180, 0)
		hbox.add_child(key_label)

		var action_label := Label.new()
		action_label.text = control[1]
		action_label.theme_type_variation = "Caption"
		hbox.add_child(action_label)

		controls_list.add_child(hbox)


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)

	if err == OK:
		master_slider.value = config.get_value("audio", "master", 100.0)
		music_slider.value = config.get_value("audio", "music", 100.0)
		sfx_slider.value = config.get_value("audio", "sfx", 100.0)
		ui_slider.value = config.get_value("audio", "ui", 100.0)
		fullscreen_check.button_pressed = config.get_value("graphics", "fullscreen", false)
		vsync_check.button_pressed = config.get_value("graphics", "vsync", true)
		lofi_check.button_pressed = config.get_value("graphics", "lofi_enabled", true)
		occlusion_fade_check.button_pressed = config.get_value(
			"graphics", "occlusion_fade_enabled", true
		)
		p2p_enabled_check.button_pressed = config.get_value("network", "p2p_enabled", true)
		prereleases_check.button_pressed = config.get_value("updates", "check_prereleases", false)
		cell_tint_opacity_slider.value = (
			config.get_value("grid_visuals", "cell_tint_opacity", 0.65) * 100.0
		)
		line_thickness_slider.value = config.get_value("grid_visuals", "line_thickness", 2.0)
		fade_distance_slider.value = config.get_value("grid_visuals", "fade_radius", 30.0)

	# Antialiasing selection must be set unconditionally (not just when a config
	# file exists) so a fresh install without user://settings.cfg still lands on
	# a valid item instead of leaving the OptionButton at selected == -1. Index
	# and item id are not guaranteed to match, so resolve via id lookup.
	var antialiasing_value: int = config.get_value(
		"graphics", "antialiasing", Viewport.MSAA_DISABLED
	)
	antialiasing_option.select(antialiasing_option.get_item_index(antialiasing_value))

	# Same unconditional-select reasoning as antialiasing above. Defaults to Ultra --
	# project.godot's own configured value -- so a fresh install matches the engine's
	# own boot-time default rather than silently downgrading shadow quality.
	var shadow_quality_value: int = config.get_value(
		"graphics", "shadow_quality", RenderingServer.SHADOW_QUALITY_SOFT_ULTRA
	)
	shadow_quality_option.select(shadow_quality_option.get_item_index(shadow_quality_value))

	var water_quality_value: int = config.get_value(
		"graphics", "water_quality", WaterQuality.MEDIUM
	)
	water_quality_option.select(water_quality_option.get_item_index(water_quality_value))

	# Renderer selection must also be set unconditionally (see the comment
	# above) -- ids here are arbitrary strings, not a coincidentally-matching
	# int enum, so lookup is always via the explicit _RENDERING_METHOD_VALUES
	# table. Clamp to index 0 ("Default") if the saved value is ever not one
	# of the four known strings (e.g. a hand-edited config), rather than
	# leaving the OptionButton deselected.
	var renderer_method_value: String = config.get_value("graphics", "rendering_method", "")
	var renderer_method_idx := _RENDERING_METHOD_VALUES.find(renderer_method_value)
	renderer_method_option.select(renderer_method_idx if renderer_method_idx >= 0 else 0)

	# Input device profile (reads from InputProfile autoload, not config)
	input_device_option.selected = InputProfile.get_selected_profile() as int

	# Update labels
	_update_volume_label(master_label, master_slider.value)
	_update_volume_label(music_label, music_slider.value)
	_update_volume_label(sfx_label, sfx_slider.value)
	_update_volume_label(ui_label, ui_slider.value)
	_update_grid_labels()


func _save_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SettingsMenu: failed to load settings for save: %d" % err)

	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)
	config.set_value("audio", "ui", ui_slider.value)
	config.set_value("graphics", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("graphics", "vsync", vsync_check.button_pressed)
	config.set_value("graphics", "lofi_enabled", lofi_check.button_pressed)
	config.set_value("graphics", "occlusion_fade_enabled", occlusion_fade_check.button_pressed)
	config.set_value("graphics", "antialiasing", antialiasing_option.get_selected_id())
	config.set_value("graphics", "shadow_quality", shadow_quality_option.get_selected_id())
	config.set_value("graphics", "water_quality", water_quality_option.get_selected_id())
	(
		config
		. set_value(
			"graphics",
			"rendering_method",
			_RENDERING_METHOD_VALUES[renderer_method_option.get_selected_id()],
		)
	)
	config.set_value("network", "p2p_enabled", p2p_enabled_check.button_pressed)
	config.set_value("updates", "check_prereleases", prereleases_check.button_pressed)
	config.set_value("grid_visuals", "cell_tint_opacity", cell_tint_opacity_slider.value / 100.0)
	config.set_value("grid_visuals", "line_thickness", line_thickness_slider.value)
	config.set_value("grid_visuals", "fade_radius", fade_distance_slider.value)

	config.save(Paths.SETTINGS_PATH)


func _apply_settings() -> void:
	# Apply audio settings
	_apply_audio_bus("Master", master_slider.value)
	_apply_audio_bus("Music", music_slider.value)
	_apply_audio_bus("SFX", sfx_slider.value)
	_apply_audio_bus("UI", ui_slider.value)

	# Defer fullscreen mode change — macOS native fullscreen (`toggleFullScreen:`)
	# requires the window to be fully presented and the run-loop to be idle.
	_apply_fullscreen_mode.call_deferred(fullscreen_check.button_pressed)

	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_check.button_pressed else DisplayServer.VSYNC_DISABLED
	)

	# Apply lo-fi filter setting
	_apply_lofi_setting()

	# Apply occlusion fade setting
	_apply_occlusion_fade_setting()

	# Apply foliage antialiasing setting
	_apply_foliage_antialiasing_setting()

	# Apply shadow quality setting
	_apply_shadow_quality_setting()

	# Apply water quality setting
	_apply_water_quality_setting()

	# Apply grid visual settings
	_apply_grid_visual_settings()

	# Apply network settings
	_apply_network_settings()


func _apply_network_settings() -> void:
	AssetManager.streamer.set_enabled(p2p_enabled_check.button_pressed)


func _apply_audio_bus(bus_name: String, volume_percent: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db = linear_to_db(volume_percent / 100.0)
		AudioServer.set_bus_volume_db(bus_idx, db)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value)


## Generic handler for all volume sliders.
func _on_volume_changed(value: float, label: Label, bus_name: String) -> void:
	_update_volume_label(label, value)
	_apply_audio_bus(bus_name, value)
	_try_play_slider_tick()


## Throttled tick sound for slider movement feedback
func _try_play_slider_tick() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_slider_tick_time >= SLIDER_TICK_INTERVAL:
		_last_slider_tick_time = now
		AudioManager.play_tick()


## Cross-fade animation when switching settings tabs
func _on_tab_changed(_tab_idx: int) -> void:
	TabUtils.animate_tab_change(tab_container, self)


func _on_fullscreen_toggled(_pressed: bool) -> void:
	pass


func _apply_fullscreen_mode(enable: bool) -> void:
	_set_window_fullscreen(enable)


func _on_vsync_toggled(_pressed: bool) -> void:
	pass


func _on_lofi_toggled(_pressed: bool) -> void:
	pass


func _on_occlusion_fade_toggled(_pressed: bool) -> void:
	pass


func _on_antialiasing_selected(_index: int) -> void:
	pass


func _on_shadow_quality_selected(_index: int) -> void:
	pass


func _on_water_quality_selected(_index: int) -> void:
	pass


func _on_renderer_method_selected(_index: int) -> void:
	pass


func _apply_lofi_setting() -> void:
	# Find active GameMap and apply lo-fi setting
	var game_map = _find_game_map()
	if game_map:
		game_map.set_lofi_enabled(lofi_check.button_pressed)


func _apply_occlusion_fade_setting() -> void:
	var game_map = _find_game_map()
	if game_map:
		game_map.set_occlusion_fade_enabled(occlusion_fade_check.button_pressed)


func _apply_foliage_antialiasing_setting() -> void:
	var game_map = _find_game_map()
	if game_map:
		game_map.set_foliage_antialiasing_level(antialiasing_option.selected)


## Unlike the other _apply_*_setting() functions, this needs no GameMap lookup --
## RenderingServer.directional_soft_shadow_filter_set_quality() is a global renderer
## setting, not tied to a specific light or map, so it applies (and is safe to call)
## even from the title screen before any level is loaded. Scoped to directional
## shadows only, matching what the debug-panel investigation this setting grew out of
## actually tested (see DebugRenderToggles' "Hard sun shadows" toggle) -- positional
## shadow quality is a separate, untouched project setting.
func _apply_shadow_quality_setting() -> void:
	RenderingServer.directional_soft_shadow_filter_set_quality(
		shadow_quality_option.get_selected_id()
	)


## Unlike most other _apply_*_setting() functions, the fine-detail/refraction
## half of this needs no GameMap/LevelPlayController lookup -- global shader
## uniforms apply engine-wide regardless of whether a level (or any water
## material) is currently loaded, exactly like _apply_shadow_quality_setting().
## The SSR half genuinely does need the current level's environment, so it
## goes through _find_level_play_controller() and is a safe no-op if no level
## is loaded (title screen) -- it takes effect on next level load instead, via
## LevelEnvironmentManager.apply_environment_settings()'s own tail call.
func _apply_water_quality_setting() -> void:
	var quality := water_quality_option.get_selected_id()
	var skip_low_detail := quality == WaterQuality.LOW
	RenderingServer.global_shader_parameter_set("water_quality_skip_fine_detail", skip_low_detail)
	RenderingServer.global_shader_parameter_set("water_quality_skip_refraction", skip_low_detail)

	var controller := _find_level_play_controller()
	if controller:
		var environment_manager := controller.get_environment_manager()
		var current_style := ""
		if controller.active_level_data:
			current_style = controller.active_level_data.water_style
		environment_manager.apply_water_quality_ssr_override(
			current_style, quality == WaterQuality.HIGH
		)


func _apply_grid_visual_settings() -> void:
	var game_map = _find_game_map()
	if game_map:
		(
			game_map
			. apply_grid_visual_settings(
				cell_tint_opacity_slider.value / 100.0,
				line_thickness_slider.value,
				fade_distance_slider.value,
			)
		)


func _on_cell_tint_opacity_changed(value: float) -> void:
	cell_tint_opacity_label.text = "%d%%" % int(value)
	_try_play_slider_tick()


func _on_line_thickness_changed(value: float) -> void:
	line_thickness_label.text = "%.1f" % value
	_try_play_slider_tick()


func _on_fade_distance_changed(value: float) -> void:
	fade_distance_label.text = "%d" % int(value)
	_try_play_slider_tick()


func _update_grid_labels() -> void:
	cell_tint_opacity_label.text = "%d%%" % int(cell_tint_opacity_slider.value)
	line_thickness_label.text = "%.1f" % line_thickness_slider.value
	fade_distance_label.text = "%d" % int(fade_distance_slider.value)


func _find_game_map() -> GameMap:
	# Look for GameMap in the scene tree
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "Root":
			for subchild in child.get_children():
				if subchild is GameMap:
					return subchild
	return null


func _find_level_play_controller() -> LevelPlayController:
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "Root":
			for subchild in child.get_children():
				if subchild is LevelPlayController:
					return subchild
	return null


func _on_close_pressed() -> void:
	animate_out()


func _on_reset_pressed() -> void:
	# Tween sliders smoothly to defaults
	var tw = create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(master_slider, "value", 100.0, 0.3)
	tw.tween_property(music_slider, "value", 100.0, 0.3)
	tw.tween_property(sfx_slider, "value", 100.0, 0.3)
	tw.tween_property(ui_slider, "value", 100.0, 0.3)

	tw.tween_property(cell_tint_opacity_slider, "value", 65.0, 0.3)
	tw.tween_property(line_thickness_slider, "value", 2.0, 0.3)
	tw.tween_property(fade_distance_slider, "value", 30.0, 0.3)

	# Snap toggles immediately (no meaningful tween for booleans)
	fullscreen_check.button_pressed = false
	vsync_check.button_pressed = true
	lofi_check.button_pressed = true
	occlusion_fade_check.button_pressed = true
	antialiasing_option.select(antialiasing_option.get_item_index(Viewport.MSAA_DISABLED))
	shadow_quality_option.select(
		shadow_quality_option.get_item_index(RenderingServer.SHADOW_QUALITY_SOFT_ULTRA)
	)
	water_quality_option.select(water_quality_option.get_item_index(WaterQuality.MEDIUM))
	renderer_method_option.select(0)
	p2p_enabled_check.button_pressed = true
	prereleases_check.button_pressed = false
	input_device_option.selected = InputProfile.Profile.AUTO
	InputProfile.set_profile(InputProfile.Profile.AUTO)


func _on_input_device_selected(index: int) -> void:
	InputProfile.set_profile(index as InputProfile.Profile)


func _on_input_profile_changed(_new_profile: InputProfile.Profile) -> void:
	_populate_controls_list()


func _on_p2p_toggled(_pressed: bool) -> void:
	pass


func _on_clear_cache_pressed() -> void:
	AssetManager.downloader.clear_all_caches()
	_update_cache_info()

	UIManager.show_toast("Asset cache cleared", 1)  # SUCCESS type


func _update_cache_info() -> void:
	var cache_size = _get_cache_size()
	var size_text = _format_size(cache_size)
	cache_info_label.text = "Cache size: %s\nClearing will force re-download of assets." % size_text


func _get_cache_size() -> int:
	var cache_dir = "user://asset_cache/"
	if not DirAccess.dir_exists_absolute(cache_dir):
		return 0
	return _get_dir_size(cache_dir)


func _get_dir_size(path: String) -> int:
	var total_size = 0
	var dir = DirAccess.open(path)
	if not dir:
		return 0

	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		var full_path = path + "/" + file_name
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				total_size += _get_dir_size(full_path)
		else:
			var file = FileAccess.open(full_path, FileAccess.READ)
			if file:
				total_size += file.get_length()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	return total_size


func _format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	return "%.1f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))


func _on_apply_pressed() -> void:
	var previous_rendering_method := _get_saved_rendering_method()
	var new_rendering_method: String = _RENDERING_METHOD_VALUES[
		renderer_method_option.get_selected_id()
	]

	_apply_settings()
	_save_settings()

	UIManager.show_toast("Settings saved", 0)  # INFO type

	if new_rendering_method != previous_rendering_method:
		_offer_rendering_method_restart(new_rendering_method)


## Read the currently-saved rendering_method value directly from disk (not
## from the OptionButton, which may already reflect the player's new,
## not-yet-saved choice) -- used by _on_apply_pressed() to detect whether this
## Apply actually changed it, before _save_settings() overwrites it.
func _get_saved_rendering_method() -> String:
	var config = ConfigFile.new()
	config.load(Paths.SETTINGS_PATH)
	return config.get_value("graphics", "rendering_method", "")


## Offer an immediate relaunch when the renderer choice changed. Declining
## does not lose the choice -- SettingsMenu.apply_startup_rendering_method()
## applies it automatically the next time the app starts normally.
func _offer_rendering_method_restart(new_value: String) -> void:
	UIManager.show_confirmation(
		"Restart Required",
		"The renderer change will take effect the next time you restart the app. Restart now?",
		"Restart Now",
		"Later",
		func(): _relaunch_with_rendering_method(new_value),
		Callable(),
	)


func _relaunch_with_rendering_method(value: String) -> void:
	var args := _build_relaunch_args(OS.get_cmdline_args(), value)
	var pid := OS.create_process(OS.get_executable_path(), args)
	if pid <= 0:
		push_warning(
			"SettingsMenu: failed to relaunch with --rendering-method %s (pid %d)" % [value, pid]
		)
		return
	get_tree().quit()


func _update_version_info() -> void:
	version_label.text = "v" + UpdateManager.get_current_version()


func _on_prereleases_toggled(pressed: bool) -> void:
	UpdateManager.set_prerelease_enabled(pressed)


## Apply helpful tooltips to settings controls
func _apply_tooltips() -> void:
	master_slider.tooltip_text = "Overall volume for all audio"
	music_slider.tooltip_text = "Background music volume"
	sfx_slider.tooltip_text = "Sound effects for token interactions"
	ui_slider.tooltip_text = "UI sounds (clicks, hover, panel open/close)"
	fullscreen_check.tooltip_text = "Toggle fullscreen mode (F11)"
	vsync_check.tooltip_text = "Sync frame rate to monitor refresh rate"
	lofi_check.tooltip_text = "Apply a lo-fi pixel filter to the 3D view"
	occlusion_fade_check.tooltip_text = "Fade map geometry that hides tokens from view"
	antialiasing_option.tooltip_text = "Smooths jagged edges on foliage (uses more GPU memory)"
	shadow_quality_option.tooltip_text = "Shadow edge softness (Hard is fastest, Ultra is priciest)"
	water_quality_option.tooltip_text = (
		"Water ripple detail and reflection quality (Low is fastest, High adds "
		+ "real reflections for the Realistic water style)"
	)
	renderer_method_option.tooltip_text = (
		"Which Godot rendering backend to use (Default follows the platform's "
		+ "normal choice). Changing this requires a restart."
	)
	cell_tint_opacity_slider.tooltip_text = "Opacity of the cell fill shading on the grid"
	line_thickness_slider.tooltip_text = "Thickness of the grid lines"
	fade_distance_slider.tooltip_text = "How far the grid extends from the camera center"
	input_device_option.tooltip_text = "Choose which key labels to show in hints (Auto detects device)"
	p2p_enabled_check.tooltip_text = "Allow peer-to-peer asset sharing with other players"
	clear_cache_button.tooltip_text = "Delete downloaded asset files to free disk space"
	prereleases_check.tooltip_text = "Include pre-release versions when checking for updates"
	check_updates_button.tooltip_text = "Check for a newer version of TTSim"
	reset_button.tooltip_text = "Reset all settings to defaults"
	apply_button.tooltip_text = "Apply and save current settings"
	close_button.tooltip_text = "Close settings (ESC)"


func _on_check_updates_pressed() -> void:
	check_updates_button.disabled = true
	update_status_label.text = "Checking for updates..."

	# Connect signals for this check only
	var on_complete = func(has_update: bool) -> void:
		check_updates_button.disabled = false
		if has_update:
			var version = UpdateManager.latest_release.get("version", "?")
			update_status_label.text = "Update available: v" + version
			# Show the update dialog
			var DialogScene = preload("res://scenes/ui/update_dialog.tscn")
			var dialog = DialogScene.instantiate()
			get_tree().root.add_child(dialog)
			dialog.setup(UpdateManager.latest_release)
		else:
			update_status_label.text = "You're up to date!"

	var on_failed = func(error: String) -> void:
		check_updates_button.disabled = false
		update_status_label.text = "Check failed: " + error

	# Connect one-shot signals
	UpdateManager.update_check_complete.connect(on_complete, CONNECT_ONE_SHOT)
	UpdateManager.update_check_failed.connect(on_failed, CONNECT_ONE_SHOT)

	UpdateManager.check_for_updates()
