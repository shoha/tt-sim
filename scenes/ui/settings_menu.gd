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

## Shows the Music volume row. Off until the game plays music.
const SHOW_MUSIC_VOLUME := false

## The Graphics tab's Quality row (SettingsQuality), loaded by path when the menu opens so the
## quality scripts stay off the start-up graph that this file is on.
const QUALITY_ROW := "res://scenes/ui/settings_quality.gd"
## The helpers the menu opens with, loaded by path (see `layout` below).
const LAYOUT_SCRIPT := "res://scenes/ui/settings_layout.gd"
const SESSION_SCRIPT := "res://scenes/ui/settings_session.gd"
const APPLY_SCRIPT := "res://scenes/ui/settings_apply.gd"
const PAGES_SCRIPT := "res://scenes/ui/settings_pages.gd"

## The Shadow quality for a player with no saved choice; project.godot's
## directional soft_shadow_filter_quality matches it, since a fresh install keeps that one.
## Godot rotates its soft-shadow taps per pixel and, with no TAA, nothing averages them, so
## Very Low and Low read as a fine diagonal hatch in every penumbra and on shaded grass cards.
## High is the cheapest tier that removes most of it (the shadow term's dither at about 45 % of
## Low's, Ultra 32-51 %, Medium 60-72 %), for about 0.45 ms more GPU than Low at 1080p on an
## RTX 3080; Ultra costs another 0.5-0.65 ms for no visible gain (shadowtier, 2026-11-08;
## docs/PERFORMANCE.md "Shadow quality tiers"). Every tier stays selectable and a saved choice
## is always honoured.
const DEFAULT_SHADOW_QUALITY := RenderingServer.SHADOW_QUALITY_SOFT_HIGH

## [tab node name, Tabler icon]. Node names double as rail ids and labels.
const SECTIONS := [
	["Audio", "volume"],
	["Graphics", "photo"],
	["Accessibility", "adjustments"],
	["Grid", "grid-dots"],
	["Controls", "mouse"],
	["Network", "network"],
	["Updates", "download"],
	["About", "info-circle"],
]

## Canvas heights (logical px) under which the rail drops its labels, so a 150% interface on a
## 720p window keeps its room for the rows.
const COMPACT_HEIGHT := 560.0
## The sheet's gap to the canvas edge and its largest size (logical px).
const PANEL_MARGIN := 32.0
const PANEL_MAX := Vector2(720.0, 760.0)

var header: MenuHeader
var close_button: Button
## The search box in the header; typing hides every row, group and section without a match.
var search_box: LineEdit
## The groups the menu builds around its rows (SettingsSpec) and what it knows about them
## (SettingsSession: defaults, unsaved changes, preview).
##
## These are loaded by path when the menu opens, like the Quality row, so none of the helpers is
## on the start-up graph (tests/unit/test_boot_graph.gd); the vars are untyped for that reason.
var layout
var session

## True while Reset tweens the sliders to their defaults; the sliders do not tick then.
var _resetting := false
## The live Reset tween. A second Reset kills it and starts its own, and only the live
## tween's end clears _resetting, so the first tween ending cannot let the second tick.
var _reset_tween: Tween
## The Quality row's helper (SettingsQuality, made in _on_panel_ready).
var _quality: RefCounted = null

# Audio controls
@onready var master_slider: HSlider = %MasterVolumeSlider
@onready var master_label: Label = %MasterVolumeLabel
@onready var music_slider: HSlider = %MusicVolumeSlider
@onready var music_label: Label = %MusicVolumeLabel
@onready var sfx_slider: HSlider = %SFXVolumeSlider
@onready var sfx_label: Label = %SFXVolumeLabel
@onready var ui_slider: HSlider = %UIVolumeSlider
@onready var ui_label: Label = %UIVolumeLabel

@onready var tab_container: TabContainer = %TabContainer
@onready var section_rail: IconRail = %SectionRail

# Graphics controls
@onready var fullscreen_check: CheckButton = %FullscreenCheck
@onready var interface_size_option: OptionButton = %InterfaceSizeOption
@onready var reduce_motion_check: CheckButton = %ReduceMotionCheck
@onready var vsync_check: CheckButton = %VSyncCheck
@onready var idle_throttle_check: CheckButton = %IdleThrottleCheck
@onready var lofi_check: CheckButton = %LofiCheck
@onready var token_shading_option: OptionButton = %TokenShadingOption
@onready var token_ghost_check: CheckButton = %TokenGhostCheck
@onready var token_pins_option: OptionButton = %TokenPinsOption
@onready var canopy_fade_check: CheckButton = %CanopyFadeCheck
@onready var wind_motion_slider: HSlider = %WindMotionSlider
@onready var wind_motion_label: Label = %WindMotionLabel
@onready var antialiasing_option: OptionButton = %AntialiasingOption
@onready var foliage_edges_option: OptionButton = %FoliageEdgesOption
@onready var shadow_quality_option: OptionButton = %ShadowQualityOption
@onready var shadow_cascades_option: OptionButton = %ShadowCascadesOption
@onready var ground_detail_option: OptionButton = %GroundDetailOption
@onready var render_scale_option: OptionButton = %RenderScaleOption
@onready var water_quality_option: OptionButton = %WaterQualityOption
@onready var ssao_check: CheckButton = %SSAOCheck
@onready var ssr_check: CheckButton = %SSRCheck
@onready var sdfgi_check: CheckButton = %SDFGICheck
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

# About
@onready var about_version_label: Label = %AboutVersionLabel
@onready var licences_button: Button = %LicencesButton

# Buttons
@onready var reset_button: Button = %ResetButton
@onready var apply_button: Button = %ApplyButton


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		# The first Escape empties a search, the next closes the menu.
		if search_box and not search_box.text.is_empty():
			_clear_search()
		else:
			animate_out()
		get_viewport().set_input_as_handled()
	elif _section_step(event) != 0:
		_step_section(_section_step(event))
		get_viewport().set_input_as_handled()


## -1 or 1 for the keys that move to the previous or next section (Ctrl+Page Up and Page Down,
## a gamepad's shoulder buttons), 0 for any other event.
func _section_step(event: InputEvent) -> int:
	if event is InputEventKey and event.pressed and event.ctrl_pressed:
		if event.keycode == KEY_PAGEUP:
			return -1
		if event.keycode == KEY_PAGEDOWN:
			return 1
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
			return -1
		if event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
			return 1
	return 0


## Selects the section `step` places away among the visible ones, wrapping.
func _step_section(step: int) -> void:
	var ids: Array[StringName] = []
	for spec in SECTIONS:
		var id := StringName(spec[0])
		if section_rail.is_item_visible(id):
			ids.append(id)
	if ids.is_empty():
		return
	var at := maxi(ids.find(section_rail.selected), 0)
	section_rail.select(ids[posmod(at + step, ids.size())])


## Apply saved graphics settings (fullscreen, vsync, shadow quality, render scale, water quality)
## at startup.
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

	RenderingServer.directional_soft_shadow_filter_set_quality(saved_shadow_quality(config))
	RenderScale.current = RenderScale.stored(config)
	SettingsGpuOptions.apply_startup(config)

	var water_quality_value: int = config.get_value(
		"graphics", "water_quality", WaterQuality.MEDIUM
	)
	var water_skip_low_detail := water_quality_value == WaterQuality.LOW
	RenderingServer.global_shader_parameter_set(
		"water_quality_skip_fine_detail", water_skip_low_detail
	)
	RenderingServer.global_shader_parameter_set(
		"water_quality_skip_refraction", water_skip_low_detail
	)

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
	var box: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	box.move_child(header, 0)
	header.setup("Settings", "", true)
	header.close_requested.connect(_on_close_pressed)
	close_button = header.close_button

	# Connect UI signals
	reset_button.pressed.connect(_on_reset_pressed)
	apply_button.pressed.connect(_on_apply_pressed)

	# Audio sliders (config-driven: [slider, label, bus_name])
	for binding in [
		[master_slider, master_label, AudioManager.BUS_MASTER],
		[music_slider, music_label, AudioManager.BUS_MUSIC],
		[sfx_slider, sfx_label, AudioManager.BUS_SFX],
		[ui_slider, ui_label, AudioManager.BUS_UI],
	]:
		binding[0].value_changed.connect(_on_volume_changed.bind(binding[1], binding[2]))
	# The game has no music yet, so a Music slider would control nothing. The row comes
	# back when music does; its saved value and bus are kept meanwhile.
	music_slider.get_parent().visible = SHOW_MUSIC_VOLUME

	# Graphics. The toggles and option buttons here and the P2P toggle have no live handler:
	# Apply reads and applies them (_apply_settings). Interface size is the exception: it saves
	# and applies the moment it is picked, so the menu itself shows the new size.
	wind_motion_slider.value_changed.connect(SettingsWindMotion.on_changed.bind(self))
	InterfaceSize.fill_option(
		interface_size_option, get_tree().root, UIManager.get_interface_size()
	)
	interface_size_option.item_selected.connect(_on_interface_size_selected)
	# Reduce motion saves and applies the moment it is toggled, like Interface size.
	reduce_motion_check.set_pressed_no_signal(UiMotion.user_reduce)
	reduce_motion_check.toggled.connect(UiPreferences.save_reduce_motion)
	# Each fixed size is named against Auto on this window, which Fullscreen can change, and
	# each Render scale choice by its render size on it (_refill_window_labels).
	SettingsRenderScale.fill(self)
	get_tree().root.size_changed.connect(_refill_window_labels)
	SettingsGpuOptions.apply_tooltips(self)
	_quality = (load(QUALITY_ROW) as GDScript).new(self)

	# Grid visuals
	cell_tint_opacity_slider.value_changed.connect(_on_cell_tint_opacity_changed)
	line_thickness_slider.value_changed.connect(_on_line_thickness_changed)
	fade_distance_slider.value_changed.connect(_on_fade_distance_changed)

	# Controls
	input_device_option.item_selected.connect(_on_input_device_selected)
	InputProfile.profile_changed.connect(_on_input_profile_changed)

	# Network
	clear_cache_button.pressed.connect(_on_clear_cache_pressed)

	# Updates
	prereleases_check.toggled.connect(_on_prereleases_toggled)
	check_updates_button.pressed.connect(Callable(_pages(), "check_for_updates").bind(self))

	# About
	licences_button.pressed.connect(_on_licences_pressed)

	# Rows share one label column, then move under their group headings (SettingsSpec).
	_fit_tab_rows()
	layout = (load(LAYOUT_SCRIPT) as GDScript).new(self)
	layout.build()
	_decorate_tabs()

	# Hide Updates tab for Steam users — Steam handles updates
	if not OS.get_environment("SteamAppId").is_empty():
		tab_container.set_tab_hidden(updates_tab.get_index(), true)

	# Tab transition animation
	tab_container.tab_changed.connect(_on_tab_changed)

	# Sections are chosen from the labelled rail; the native tab bar is hidden. Under a short
	# canvas the rail drops its labels.
	tab_container.tabs_visible = false
	section_rail.show_labels = _canvas().y >= COMPACT_HEIGHT
	section_rail.focusable = true
	_populate_section_rail()
	_build_search()
	_fit_panel()
	get_viewport().size_changed.connect(_fit_panel)

	# Apply tooltips to settings controls
	SettingsTooltips.apply(self)
	reset_button.tooltip_text = "Put every setting back to its default (Apply keeps it)"

	# Load current settings
	_load_settings()
	_pages().populate_shortcuts(controls_list)
	_update_cache_info()
	_update_version_info()
	session = (load(SESSION_SCRIPT) as GDScript).new(self, layout)
	session.start()

	# Register as overlay (cast to Control for type compatibility)
	UIManager.register_overlay($ColorRect as Control)


## The sheet's keyboard entry: focus on the selected section, once the menu has opened. From here
## Tab walks the search box, the sections, each group's Reset and rows, then Reset all and Apply.
func _on_after_animate_in() -> void:
	session.live = true
	section_rail.grab_item_focus(section_rail.selected)


## The canvas the sheet lays out in, in logical pixels (the window under the Interface size).
func _canvas() -> Vector2:
	return get_viewport().get_visible_rect().size


## The sheet takes the canvas less a margin on each side, up to a comfortable reading size; the
## rows scroll inside it. A fixed height keeps the sheet from jumping as the section changes.
func _fit_panel() -> void:
	var canvas := _canvas()
	var panel := $CenterContainer/PanelContainer as Control
	panel.custom_minimum_size = Vector2(
		clampf(canvas.x - 2.0 * PANEL_MARGIN, 440.0, PANEL_MAX.x),
		clampf(canvas.y - 2.0 * PANEL_MARGIN, 280.0, PANEL_MAX.y)
	)


func _build_search() -> void:
	search_box = LineEdit.new()
	search_box.name = "SearchBox"
	search_box.placeholder_text = "Search settings"
	search_box.clear_button_enabled = true
	search_box.custom_minimum_size.x = 200.0
	search_box.tooltip_text = "Find a setting by name or by what it does (Esc clears it)"
	search_box.text_changed.connect(layout.set_filter)
	search_box.gui_input.connect(_on_search_input)
	var row := header.get_node("Row")
	row.add_child(search_box)
	row.move_child(search_box, 1)
	search_box.owner = self
	search_box.unique_name_in_owner = true


## Escape in the box empties it first (the LineEdit would only leave it).
func _on_search_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not search_box.text.is_empty():
		_clear_search()
		search_box.accept_event()


func _clear_search() -> void:
	search_box.clear()
	layout.set_filter("")


func _on_before_animate_out() -> void:
	session.revert_if_dirty()
	SettingsWindMotion.revert()
	if InputProfile.profile_changed.is_connected(_on_input_profile_changed):
		InputProfile.profile_changed.disconnect(_on_input_profile_changed)
	UIManager.unregister_overlay($ColorRect as Control)


func _on_after_animate_out() -> void:
	closed.emit()
	queue_free()


## Every tab's label-and-control rows share one label column and gap (PropertyRow).
func _fit_tab_rows() -> void:
	for node in tab_container.find_children("*", "HBoxContainer", true, false):
		PropertyRow.fit_sheet_row(node as HBoxContainer)


## A tab whose rows run past its bottom fades there instead of cutting a row (ScrollFade); its
## scroll bar is the handle alone, shown only while wanted (ScrollBarFade); and the scroll follows
## the keyboard focus, so a row reached with Tab is never left under the edge.
func _decorate_tabs() -> void:
	for tab in tab_container.get_children():
		if tab is ScrollContainer:
			(tab as ScrollContainer).follow_focus = true
			tab.add_child(ScrollFade.new())
			ScrollBarFade.attach(tab)


func _load_settings(path: String = Paths.SETTINGS_PATH) -> void:
	var config = ConfigFile.new()
	config.load(path)
	# A missing file shows the defaults (every value is read with its default), so a menu that
	# reloads after a discard lands on them too.
	_show_saved_values(config)

	# Antialiasing selection must be set unconditionally (not just when a config
	# file exists) so a fresh install without user://settings.cfg still lands on
	# a valid item instead of leaving the OptionButton at selected == -1. Index
	# and item id are not guaranteed to match, so resolve via id lookup.
	var antialiasing_value: int = config.get_value(
		"graphics", "antialiasing", Viewport.MSAA_DISABLED
	)
	antialiasing_option.select(antialiasing_option.get_item_index(antialiasing_value))

	# Same unconditional-select reasoning as antialiasing above. Defaults to
	# DEFAULT_SHADOW_QUALITY -- project.godot's own configured value -- so a fresh install
	# shows the tier the engine booted with.
	shadow_quality_option.select(shadow_quality_option.get_item_index(saved_shadow_quality(config)))
	SettingsRenderScale.show_saved(self, config)
	SettingsGpuOptions.show_saved(self, config)

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
	if _quality:
		_quality.call("show_saved", config)

	# Input device profile (reads from InputProfile autoload, not config)
	input_device_option.selected = InputProfile.get_selected_profile() as int

	_update_value_labels()


## The text beside every slider (volumes, wind, grid) follows the sliders' values.
func _update_value_labels() -> void:
	_update_volume_label(master_label, master_slider.value)
	_update_volume_label(music_label, music_slider.value)
	_update_volume_label(sfx_label, sfx_slider.value)
	_update_volume_label(ui_label, ui_slider.value)
	wind_motion_label.text = SettingsWindMotion.label_for(wind_motion_slider.value)
	_update_grid_labels()


## The Quality row shows the preset the four rows it covers make (after a reset or revert).
func _refresh_quality() -> void:
	if _quality:
		_quality.call("refresh")


## Puts the saved slider and toggle values in `config` on the controls. Showing a saved
## value changes nothing, so it sets them without signals: no slider or toggle ticks and
## no handler runs. The caller refreshes the labels, and AudioManager applied the bus
## volumes at startup from the same file.
func _show_saved_values(config: ConfigFile) -> void:
	master_slider.set_value_no_signal(config.get_value("audio", "master", 100.0))
	music_slider.set_value_no_signal(config.get_value("audio", "music", 100.0))
	sfx_slider.set_value_no_signal(config.get_value("audio", "sfx", 100.0))
	ui_slider.set_value_no_signal(config.get_value("audio", "ui", 100.0))
	fullscreen_check.set_pressed_no_signal(config.get_value("graphics", "fullscreen", false))
	vsync_check.set_pressed_no_signal(config.get_value("graphics", "vsync", true))
	lofi_check.set_pressed_no_signal(config.get_value("graphics", "lofi_enabled", true))
	SettingsTokenShading.show_saved(self, config)
	SettingsTokenPins.show_saved(self, config)
	SettingsSeeThrough.show_saved(self, config)
	SettingsWindMotion.show_saved(self, config)
	ssao_check.set_pressed_no_signal(
		config.get_value(
			"graphics", "ssao_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["ssao_enabled"]
		)
	)
	ssr_check.set_pressed_no_signal(
		config.get_value(
			"graphics", "ssr_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["ssr_enabled"]
		)
	)
	sdfgi_check.set_pressed_no_signal(
		config.get_value(
			"graphics", "sdfgi_enabled", Constants.RENDERING_TOGGLES_DEFAULTS["sdfgi_enabled"]
		)
	)
	p2p_enabled_check.set_pressed_no_signal(config.get_value("network", "p2p_enabled", true))
	prereleases_check.set_pressed_no_signal(config.get_value("updates", "check_prereleases", false))
	cell_tint_opacity_slider.set_value_no_signal(
		config.get_value("grid_visuals", "cell_tint_opacity", 0.65) * 100.0
	)
	line_thickness_slider.set_value_no_signal(
		config.get_value("grid_visuals", "line_thickness", 2.0)
	)
	fade_distance_slider.set_value_no_signal(config.get_value("grid_visuals", "fade_radius", 30.0))


## Writes every control's value to the settings file at `path` (tests pass their own),
## keeping the sections other code saves there. The volumes go with the taper marker, so a
## fresh install's first save is never mistaken for a linear-taper file and converted.
func _save_settings(path: String = Paths.SETTINGS_PATH) -> void:
	var config = ConfigFile.new()
	var err = config.load(path)
	if err != OK and err != ERR_FILE_NOT_FOUND:
		push_warning("SettingsMenu: failed to load settings for save: %d" % err)
	_write_values(config)
	config.save(path)


## Puts every control's value in `config` (the file's own sections and keys). SettingsSession
## compares two of these to tell whether anything is unsaved, so it never touches the disk.
func _write_values(config: ConfigFile) -> void:
	config.set_value("audio", "master", master_slider.value)
	config.set_value("audio", "music", music_slider.value)
	config.set_value("audio", "sfx", sfx_slider.value)
	config.set_value("audio", "ui", ui_slider.value)
	config.set_value("audio", AudioManager.VOLUME_TAPER_KEY, AudioManager.VOLUME_TAPER)
	config.set_value("graphics", "fullscreen", fullscreen_check.button_pressed)
	config.set_value("graphics", "vsync", vsync_check.button_pressed)
	config.set_value("graphics", "lofi_enabled", lofi_check.button_pressed)
	SettingsTokenShading.save(self, config)
	SettingsTokenPins.save(self, config)
	SettingsSeeThrough.save(self, config)
	SettingsWindMotion.save(self, config)
	config.set_value("graphics", "ssao_enabled", ssao_check.button_pressed)
	config.set_value("graphics", "ssr_enabled", ssr_check.button_pressed)
	config.set_value("graphics", "sdfgi_enabled", sdfgi_check.button_pressed)
	config.set_value("graphics", "antialiasing", antialiasing_option.get_selected_id())
	config.set_value("graphics", "shadow_quality", shadow_quality_option.get_selected_id())
	SettingsRenderScale.save(self, config)
	SettingsGpuOptions.save(self, config)
	config.set_value("graphics", "water_quality", water_quality_option.get_selected_id())
	(
		config
		. set_value(
			"graphics",
			"rendering_method",
			_RENDERING_METHOD_VALUES[renderer_method_option.get_selected_id()],
		)
	)
	# The foliage triangle budget was retired; a file written by an older build still holds its key.
	if config.has_section_key("graphics", "foliage_budget"):
		config.erase_section_key("graphics", "foliage_budget")
	config.set_value("network", "p2p_enabled", p2p_enabled_check.button_pressed)
	config.set_value("updates", "check_prereleases", prereleases_check.button_pressed)
	config.set_value("grid_visuals", "cell_tint_opacity", cell_tint_opacity_slider.value / 100.0)
	config.set_value("grid_visuals", "line_thickness", line_thickness_slider.value)
	config.set_value("grid_visuals", "fade_radius", fade_distance_slider.value)


## Everything Apply applies, and the preview a moved row gets before it (SettingsApply).
func _apply_settings() -> void:
	(load(APPLY_SCRIPT) as GDScript).call("all", self)


func _apply_preview() -> void:
	(load(APPLY_SCRIPT) as GDScript).call("preview", self)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % int(value)


## Generic handler for all volume sliders. The tick's own cooldown (tools/sfx_spec.py)
## keeps a fast drag from machine-gunning it.
func _on_volume_changed(value: float, label: Label, bus_name: String) -> void:
	_update_volume_label(label, value)
	AudioManager.set_bus_volume(bus_name, value / 100.0)
	_slider_tick()


## Ticks for a slider the user moved. Silent while Reset tweens the sliders home: the
## Reset button's own click is the whole sound of that gesture.
func _slider_tick() -> void:
	if not _resetting:
		AudioManager.play(&"tick")


## Cross-fade animation when switching settings tabs
func _on_tab_changed(_tab_idx: int) -> void:
	TabUtils.animate_tab_change(tab_container, self)


func _populate_section_rail() -> void:
	for spec in SECTIONS:
		section_rail.add_item(StringName(spec[0]), spec[1], spec[0])
	section_rail.selection_changed.connect(_on_section_selected)
	if not OS.get_environment("SteamAppId").is_empty():
		section_rail.set_item_visible(&"Updates", false)
	section_rail.select(StringName(tab_container.get_current_tab_control().name))


func _on_section_selected(id: StringName) -> void:
	var tab := tab_container.get_node_or_null(String(id))
	if tab:
		tab_container.current_tab = tab.get_index()
	# The keyboard ring stays on the chosen section when it was on the rail (Ctrl+Page Down, the
	# shoulder buttons), instead of marking the one that was left.
	var focused := get_viewport().gui_get_focus_owner()
	if focused and section_rail.is_ancestor_of(focused):
		section_rail.grab_item_focus(id)


## The player's saved Shadow quality from a loaded settings file, exactly as saved (Hard and
## every soft tier down to Very Low are honoured), or DEFAULT_SHADOW_QUALITY when none is saved.
static func saved_shadow_quality(config: ConfigFile) -> int:
	return config.get_value("graphics", "shadow_quality", DEFAULT_SHADOW_QUALITY)


func _on_cell_tint_opacity_changed(value: float) -> void:
	cell_tint_opacity_label.text = "%d%%" % int(value)
	_slider_tick()


func _on_line_thickness_changed(value: float) -> void:
	line_thickness_label.text = "%.1f" % value
	_slider_tick()


func _on_fade_distance_changed(value: float) -> void:
	fade_distance_label.text = "%d" % int(value)
	_slider_tick()


func _update_grid_labels() -> void:
	cell_tint_opacity_label.text = "%d%%" % int(cell_tint_opacity_slider.value)
	line_thickness_label.text = "%.1f" % line_thickness_slider.value
	fade_distance_label.text = "%d" % int(fade_distance_slider.value)


## The open GameMap, found by method, not class (keeps the map off the start-up graph, boot2).
func _find_game_map() -> Node3D:
	var root = get_tree().root
	for child in root.get_children():
		if child.name == "Root":
			for subchild in child.get_children():
				if subchild is Node3D and subchild.has_method(&"get_level_play_controller"):
					return subchild
	return null


func _find_level_play_controller() -> Node:
	var game_map := _find_game_map()
	if game_map:
		return game_map.get_level_play_controller()
	return null


func _on_close_pressed() -> void:
	animate_out()


## Reset to Defaults: shows the defaults (applied on Apply), and resets the three
## preferences that save the moment they change, the prerelease channel, the input
## profile and the Interface size, at once as before.
func _on_reset_pressed() -> void:
	_show_defaults()
	prereleases_check.button_pressed = false
	input_device_option.selected = InputProfile.Profile.AUTO
	InputProfile.set_profile(InputProfile.Profile.AUTO)
	interface_size_option.select(0)
	UIManager.set_interface_size(InterfaceSize.AUTO)
	reduce_motion_check.button_pressed = false
	session.touch()


func _on_interface_size_selected(index: int) -> void:
	UIManager.set_interface_size(interface_size_option.get_item_id(index))
	_fit_panel.call_deferred()


## Relabels the options named against this window (Interface size and Render scale), keeping
## each selection. A method of the menu, so the connection goes when the menu does.
func _refill_window_labels() -> void:
	InterfaceSize.fill_option(
		interface_size_option, get_tree().root, interface_size_option.get_selected_id()
	)
	SettingsRenderScale.refill(self)


## Puts every Settings control except those three on its default without a sound: the
## sliders tween home and hold their ticks (_slider_tick) until they land, and the
## toggles and options snap without signals (Apply applies them).
func _show_defaults(instant: bool = false) -> void:
	if _reset_tween and _reset_tween.is_valid():
		_reset_tween.kill()
	var sliders := [
		[master_slider, 100.0],
		[music_slider, 100.0],
		[sfx_slider, 100.0],
		[ui_slider, 100.0],
		[cell_tint_opacity_slider, 65.0],
		[line_thickness_slider, 2.0],
		[fade_distance_slider, 30.0],
		[wind_motion_slider, 100.0],
	]
	if instant:
		# Silently, for SettingsSession reading the defaults: no tween, no handler, no sound.
		for pair in sliders:
			pair[0].set_value_no_signal(pair[1])
	else:
		_resetting = true
		var tw := create_tween()
		_reset_tween = tw
		tw.finished.connect(_on_reset_tween_finished.bind(tw))
		tw.set_parallel(true)
		tw.set_ease(Tween.EASE_OUT)
		tw.set_trans(UiMotion.ARRIVE_TRANS)
		for pair in sliders:
			tw.tween_property(pair[0], "value", pair[1], 0.0 if UiMotion.reduced() else UiMotion.STATE_S)

	# Snap toggles immediately (no meaningful tween for booleans)
	fullscreen_check.set_pressed_no_signal(false)
	vsync_check.set_pressed_no_signal(true)
	lofi_check.set_pressed_no_signal(true)
	SettingsTokenShading.show_defaults(self)
	SettingsTokenPins.show_defaults(self)
	SettingsSeeThrough.show_defaults(self)
	antialiasing_option.select(antialiasing_option.get_item_index(Viewport.MSAA_DISABLED))
	shadow_quality_option.select(shadow_quality_option.get_item_index(DEFAULT_SHADOW_QUALITY))
	SettingsRenderScale.show_defaults(self)
	SettingsGpuOptions.show_defaults(self)
	water_quality_option.select(water_quality_option.get_item_index(WaterQuality.MEDIUM))
	ssao_check.set_pressed_no_signal(Constants.RENDERING_TOGGLES_DEFAULTS["ssao_enabled"])
	ssr_check.set_pressed_no_signal(Constants.RENDERING_TOGGLES_DEFAULTS["ssr_enabled"])
	sdfgi_check.set_pressed_no_signal(Constants.RENDERING_TOGGLES_DEFAULTS["sdfgi_enabled"])
	renderer_method_option.select(0)
	p2p_enabled_check.set_pressed_no_signal(true)
	if _quality:
		_quality.call("refresh")


## Lets the sliders tick again once the live Reset tween lands; a killed one's end is ignored.
func _on_reset_tween_finished(tween: Tween) -> void:
	if tween == _reset_tween:
		_resetting = false
		_reset_tween = null


func _on_input_device_selected(index: int) -> void:
	InputProfile.set_profile(index as InputProfile.Profile)


func _on_input_profile_changed(_new_profile: InputProfile.Profile) -> void:
	_pages().populate_shortcuts(controls_list)


## The Controls and Updates pages' helpers (SettingsPages), loaded on first use.
func _pages() -> GDScript:
	return load(PAGES_SCRIPT) as GDScript


func _on_clear_cache_pressed() -> void:
	AssetManager.downloader.clear_all_caches()
	_update_cache_info()

	UIManager.show_toast("Asset cache cleared", 1)  # SUCCESS type


func _update_cache_info() -> void:
	cache_info_label.text = SettingsCacheInfo.caption()


func _on_apply_pressed() -> void:
	var previous_rendering_method := _get_saved_rendering_method()
	var new_rendering_method: String = _RENDERING_METHOD_VALUES[
		renderer_method_option.get_selected_id()
	]

	_apply_settings()
	_save_settings()
	session.mark_clean()

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
	about_version_label.text = version_label.text


## Opens the Licences page over Settings (the base class steps this sheet back and returns it,
## with its focus, when the page closes).
func _on_licences_pressed() -> void:
	LicencesPanel.open(get_tree().root)


func _on_prereleases_toggled(pressed: bool) -> void:
	UpdateManager.set_prerelease_enabled(pressed)
