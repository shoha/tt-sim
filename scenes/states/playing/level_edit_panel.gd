class_name LevelEditPanel
extends DrawerContainer

## Slide-out drawer for real-time visual tuning during gameplay.
## Provides controls for map scale, lighting, environment, and post-processing.
## Changes apply immediately to the live game viewport.
## Uses DrawerContainer with edge = RIGHT so the tab appears on the left.

signal save_requested(values: Dictionary)
signal cancel_requested
signal intensity_changed(new_scale: float)
signal scale_config_changed(
	grid_cell_size: float, display_unit: String, display_unit_per_cell: float
)
signal environment_changed(preset: String, overrides: Dictionary)
signal lofi_changed(overrides: Dictionary)
signal weather_changed(overrides: Dictionary)
signal foliage_changed(overrides: Dictionary)
signal sun_changed(settings: SunSettings)
signal water_style_changed(style: String)
signal revert_to_map_defaults_requested

## Emitted when the user toggles "Aim Sun". GameplayMenuController owns the
## GameMap reference, so it toggles the actual tool.
signal aim_sun_toggled(active: bool)

## Emitted when the drawer opens (before the animation starts).
## The controller should snapshot current values and call initialize().
signal drawer_opened

## Emitted when the drawer finishes closing.
## The controller should revert changes if not saved.
signal drawer_closed

const TONEMAP_MODES = {
	"Linear": Environment.TONE_MAPPER_LINEAR,
	"Reinhardt": Environment.TONE_MAPPER_REINHARDT,
	"Filmic": Environment.TONE_MAPPER_FILMIC,
	"ACES": Environment.TONE_MAPPER_ACES,
}

const SUN_MODES = {
	"Auto": "auto",
	"On": "on",
	"Off": "off",
}

var current_preset: String = ""
var current_overrides: Dictionary = {}
var current_water_style: String = "stylized"
var current_lofi_overrides: Dictionary = {}
var current_weather_overrides: Dictionary = {}
var current_foliage_overrides: Dictionary = {}
var current_sun: SunSettings = SunSettings.default()
var light_intensity_scale: float = 1.0
var current_grid_cell_size: float = 1.524
var current_display_unit: String = "ft"
var current_display_unit_per_cell: float = 5.0
var _current_scale_preset_key: String = ScaleUtils.DEFAULT_PRESET
## Environment config extracted from the map's embedded WorldEnvironment.
## Used as the base layer when current_preset is "" (no explicit choice).
var _map_defaults: Dictionary = {}

# Scale & measurement controls
@onready var map_grid_toggle: Button = %MapGridToggle
@onready var map_grid_container: VBoxContainer = %MapGridContainer
@onready var scale_preset_dropdown: OptionButton = %ScalePresetDropdown
@onready var grid_cell_size_slider_spin: SliderSpinBox = %GridCellSizeSliderSpin

# Lighting controls — basic
@onready var preset_dropdown: OptionButton = %PresetDropdown
@onready var water_style_dropdown: OptionButton = %WaterStyleDropdown
@onready var intensity_slider_spin: SliderSpinBox = %IntensitySliderSpin
@onready var bg_color_picker: ColorPickerButton = %BgColorPicker
@onready var ambient_color_picker: ColorPickerButton = %AmbientColorPicker
@onready var ambient_energy_slider_spin: SliderSpinBox = %AmbientEnergySliderSpin
@onready var fog_enabled_check: CheckBox = %FogEnabledCheck
@onready var fog_color_picker: ColorPickerButton = %FogColorPicker
@onready var fog_density_slider_spin: SliderSpinBox = %FogDensitySliderSpin
@onready var glow_enabled_check: CheckBox = %GlowEnabledCheck
@onready var glow_intensity_slider_spin: SliderSpinBox = %GlowIntensitySliderSpin
@onready var exposure_slider_spin: SliderSpinBox = %ExposureSliderSpin
@onready var brightness_slider_spin: SliderSpinBox = %BrightnessSliderSpin
@onready var contrast_slider_spin: SliderSpinBox = %ContrastSliderSpin
@onready var saturation_slider_spin: SliderSpinBox = %SaturationSliderSpin
@onready var revert_to_map_button: Button = %RevertToMapButton

# Lighting controls — advanced
@onready var advanced_toggle: Button = %AdvancedToggle
@onready var advanced_container: VBoxContainer = %AdvancedContainer
@onready var sky_preset_dropdown: OptionButton = %SkyPresetDropdown
@onready var fog_energy_slider_spin: SliderSpinBox = %FogEnergySliderSpin
@onready var fog_height_slider_spin: SliderSpinBox = %FogHeightSliderSpin
@onready var fog_height_density_slider_spin: SliderSpinBox = %FogHeightDensitySliderSpin
@onready var tonemap_mode_dropdown: OptionButton = %TonemapModeDropdown
@onready var tonemap_white_slider_spin: SliderSpinBox = %TonemapWhiteSliderSpin
@onready var glow_strength_slider_spin: SliderSpinBox = %GlowStrengthSliderSpin
@onready var glow_bloom_slider_spin: SliderSpinBox = %GlowBloomSliderSpin

# Action buttons
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton

# Post-processing (lo-fi) controls
@onready var pixelation_slider_spin: SliderSpinBox = %PixelationSliderSpin
@onready var color_fade_slider_spin: SliderSpinBox = %ColorFadeSliderSpin
@onready var color_levels_slider_spin: SliderSpinBox = %ColorLevelsSliderSpin
@onready var dither_slider_spin: SliderSpinBox = %DitherSliderSpin
@onready var vignette_slider_spin: SliderSpinBox = %VignetteSliderSpin
@onready var grain_slider_spin: SliderSpinBox = %GrainSliderSpin

# Weather controls
@onready var rain_slider_spin: SliderSpinBox = %RainSliderSpin
@onready var snow_slider_spin: SliderSpinBox = %SnowSliderSpin
@onready var fog_slider_spin: SliderSpinBox = %FogSliderSpin
@onready var wind_slider_spin: SliderSpinBox = %WindSliderSpin

# Foliage controls
@onready var tree_sway_speed_slider_spin: SliderSpinBox = %TreeSwaySpeedSliderSpin
@onready var tree_sway_amplitude_slider_spin: SliderSpinBox = %TreeSwayAmplitudeSliderSpin
@onready var grass_sway_speed_slider_spin: SliderSpinBox = %GrassSwaySpeedSliderSpin
@onready var grass_sway_amplitude_slider_spin: SliderSpinBox = %GrassSwayAmplitudeSliderSpin

# Sun controls
@onready var sun_mode_dropdown: OptionButton = %SunModeDropdown
@onready var sun_time_of_day_slider_spin: SliderSpinBox = %SunTimeOfDaySliderSpin
@onready var aim_sun_button: Button = %AimSunButton
@onready var sun_azimuth_slider_spin: SliderSpinBox = %SunAzimuthSliderSpin
@onready var sun_elevation_slider_spin: SliderSpinBox = %SunElevationSliderSpin
@onready var sun_color_picker: ColorPickerButton = %SunColorPicker
@onready var sun_energy_slider_spin: SliderSpinBox = %SunEnergySliderSpin
@onready var sun_shadows_check: CheckBox = %SunShadowsCheck
@onready var sun_softness_slider_spin: SliderSpinBox = %SunSoftnessSliderSpin
@onready var sun_darkness_slider_spin: SliderSpinBox = %SunDarknessSliderSpin
@onready var sun_regenerate_button: Button = %SunRegenerateButton


func _on_ready() -> void:
	# Configure drawer
	edge = DrawerEdge.RIGHT
	drawer_width = 350.0
	tab_icon = preload("res://assets/icons/ui/Sun.svg")
	play_sounds = true

	# Increase content padding inside the drawer panel.
	var margin_node = _panel.get_child(0) as MarginContainer
	if margin_node:
		margin_node.add_theme_constant_override("margin_left", 16)
		margin_node.add_theme_constant_override("margin_right", 16)
		margin_node.add_theme_constant_override("margin_top", 16)
		margin_node.add_theme_constant_override("margin_bottom", 16)

	# Reparent the scene-defined root VBox -- the ScrollContainer plus the
	# Cancel/Save ButtonsRow pinned below it -- into the drawer's content area.
	# Must set size_flags so the DrawerContainer's VBoxContainer allocates full
	# height to it. ButtonsRow lives outside the ScrollContainer so Cancel/Save
	# are always visible without scrolling; only the ScrollContainer itself
	# expands to fill the remaining space (set in the .tscn).
	var root_vbox = %RootVBox
	if root_vbox:
		root_vbox.get_parent().remove_child(root_vbox)
		root_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_container.add_child(root_vbox)

		# Wrap the VBox in an inner MarginContainer so the right padding sits
		# *between* the content and the scrollbar, not outside the scrollbar.
		var scroll = root_vbox.get_node("ScrollContainer")
		var vbox = scroll.get_child(0) if scroll else null
		if vbox:
			var inner_margin := MarginContainer.new()
			inner_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
			inner_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inner_margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
			inner_margin.add_theme_constant_override("margin_right", 16)
			scroll.remove_child(vbox)
			inner_margin.add_child(vbox)
			scroll.add_child(inner_margin)

	_connect_control_signals()
	_populate_scale_preset_dropdown()
	_populate_preset_dropdown()
	_populate_water_style_dropdown()
	_populate_sky_preset_dropdown()
	_populate_tonemap_mode_dropdown()
	_populate_sun_mode_dropdown()


func _connect_control_signals() -> void:
	# Scale & measurement
	map_grid_toggle.toggled.connect(_on_map_grid_toggled)
	scale_preset_dropdown.item_selected.connect(_on_scale_preset_selected)
	grid_cell_size_slider_spin.value_changed.connect(_on_grid_cell_size_changed)

	# Special-case controls (preset selection, dropdowns with complex logic)
	preset_dropdown.item_selected.connect(_on_preset_selected)
	water_style_dropdown.item_selected.connect(_on_water_style_selected)
	intensity_slider_spin.value_changed.connect(_on_intensity_changed)
	advanced_toggle.toggled.connect(_on_advanced_toggled)
	sky_preset_dropdown.item_selected.connect(_on_sky_preset_selected)
	tonemap_mode_dropdown.item_selected.connect(_on_tonemap_mode_selected)
	sun_mode_dropdown.item_selected.connect(_on_sun_mode_selected)
	sun_time_of_day_slider_spin.value_changed.connect(_on_sun_time_of_day_changed)
	aim_sun_button.toggled.connect(_on_aim_sun_toggled)
	sun_azimuth_slider_spin.value_changed.connect(_on_sun_azimuth_changed)
	sun_elevation_slider_spin.value_changed.connect(_on_sun_elevation_changed)
	sun_color_picker.color_changed.connect(_on_sun_color_changed)
	sun_energy_slider_spin.value_changed.connect(_on_sun_energy_changed)
	sun_shadows_check.toggled.connect(_on_sun_shadows_toggled)
	sun_softness_slider_spin.value_changed.connect(_on_sun_softness_changed)
	sun_darkness_slider_spin.value_changed.connect(_on_sun_darkness_changed)
	sun_regenerate_button.pressed.connect(_on_sun_regenerate_pressed)

	# Config-driven environment overrides: [control, signal_name, override_key]
	for binding in [
		[bg_color_picker, "color_changed", "background_color"],
		[ambient_color_picker, "color_changed", "ambient_light_color"],
		[ambient_energy_slider_spin, "value_changed", "ambient_light_energy"],
		[fog_enabled_check, "toggled", "fog_enabled"],
		[fog_color_picker, "color_changed", "fog_light_color"],
		[fog_density_slider_spin, "value_changed", "fog_density"],
		[glow_enabled_check, "toggled", "glow_enabled"],
		[glow_intensity_slider_spin, "value_changed", "glow_intensity"],
		[exposure_slider_spin, "value_changed", "tonemap_exposure"],
		[fog_energy_slider_spin, "value_changed", "fog_light_energy"],
		[fog_height_slider_spin, "value_changed", "fog_height"],
		[fog_height_density_slider_spin, "value_changed", "fog_height_density"],
		[tonemap_white_slider_spin, "value_changed", "tonemap_white"],
		[glow_strength_slider_spin, "value_changed", "glow_strength"],
		[glow_bloom_slider_spin, "value_changed", "glow_bloom"],
	]:
		binding[0].connect(binding[1], _on_env_override_changed.bind(binding[2]))

	# Adjustment overrides (also sets adjustment_enabled = true)
	for binding in [
		[brightness_slider_spin, "value_changed", "adjustment_brightness"],
		[contrast_slider_spin, "value_changed", "adjustment_contrast"],
		[saturation_slider_spin, "value_changed", "adjustment_saturation"],
	]:
		binding[0].connect(binding[1], _on_adjustment_override_changed.bind(binding[2]))

	# Lo-fi post-processing overrides: [control, signal_name, override_key]
	for binding in [
		[pixelation_slider_spin, "value_changed", "pixelation"],
		[color_fade_slider_spin, "value_changed", "saturation"],
		[color_levels_slider_spin, "value_changed", "color_levels"],
		[dither_slider_spin, "value_changed", "dither_strength"],
		[vignette_slider_spin, "value_changed", "vignette_strength"],
		[grain_slider_spin, "value_changed", "grain_intensity"],
	]:
		binding[0].connect(binding[1], _on_lofi_override_changed.bind(binding[2]))

	# Weather overrides: [control, signal_name, override_key]
	for binding in [
		[rain_slider_spin, "value_changed", "rain_intensity"],
		[snow_slider_spin, "value_changed", "snow_intensity"],
		[fog_slider_spin, "value_changed", "fog_intensity"],
		[wind_slider_spin, "value_changed", "wind_intensity"],
	]:
		binding[0].connect(binding[1], _on_weather_override_changed.bind(binding[2]))

	# Foliage overrides: [control, signal_name, override_key]
	for binding in [
		[tree_sway_speed_slider_spin, "value_changed", "tree_sway_speed"],
		[tree_sway_amplitude_slider_spin, "value_changed", "tree_sway_amplitude"],
		[grass_sway_speed_slider_spin, "value_changed", "grass_sway_speed"],
		[grass_sway_amplitude_slider_spin, "value_changed", "grass_sway_amplitude"],
	]:
		binding[0].connect(binding[1], _on_foliage_override_changed.bind(binding[2]))

	revert_to_map_button.pressed.connect(func() -> void: revert_to_map_defaults_requested.emit())
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _populate_preset_dropdown(has_map_defaults: bool = false) -> void:
	preset_dropdown.clear()
	var idx := 0

	# "Map Defaults" option — shown when the map has an embedded environment
	if has_map_defaults:
		preset_dropdown.add_item("Map Defaults", idx)
		preset_dropdown.set_item_tooltip(idx, "Use the map's embedded lighting")
		preset_dropdown.set_item_metadata(idx, "")
		idx += 1

	var presets = EnvironmentPresets.get_preset_names()
	for preset_name in presets:
		var description = EnvironmentPresets.get_preset_description(preset_name)
		preset_dropdown.add_item("%s" % preset_name, idx)
		preset_dropdown.set_item_tooltip(idx, description)
		preset_dropdown.set_item_metadata(idx, preset_name)
		idx += 1


func _populate_water_style_dropdown() -> void:
	water_style_dropdown.clear()
	var idx := 0
	for style_name in WaterPresets.get_preset_names():
		water_style_dropdown.add_item(style_name.capitalize(), idx)
		water_style_dropdown.set_item_metadata(idx, style_name)
		idx += 1


## Populate the sky preset dropdown.
## [param has_map_sky] adds the "map_default" option when the loaded map has
## an embedded Sky resource.
func _populate_sky_preset_dropdown(has_map_sky: bool = false) -> void:
	sky_preset_dropdown.clear()

	# "None" option (no sky, use background color)
	sky_preset_dropdown.add_item("None", 0)
	sky_preset_dropdown.set_item_metadata(0, "")

	var idx := 1
	# Map default option (only shown when a map sky exists)
	if has_map_sky:
		sky_preset_dropdown.add_item("Map Default", idx)
		sky_preset_dropdown.set_item_metadata(idx, "map_default")
		idx += 1

	# Built-in presets
	var sky_names = EnvironmentPresets.get_sky_preset_names()
	for sky_name in sky_names:
		var desc = EnvironmentPresets.get_sky_preset_description(sky_name)
		sky_preset_dropdown.add_item(sky_name, idx)
		sky_preset_dropdown.set_item_tooltip(idx, desc)
		sky_preset_dropdown.set_item_metadata(idx, sky_name)
		idx += 1


func _populate_tonemap_mode_dropdown() -> void:
	tonemap_mode_dropdown.clear()
	var idx := 0
	for label in TONEMAP_MODES:
		tonemap_mode_dropdown.add_item(label, idx)
		tonemap_mode_dropdown.set_item_metadata(idx, TONEMAP_MODES[label])
		idx += 1


func _populate_sun_mode_dropdown() -> void:
	sun_mode_dropdown.clear()
	var idx := 0
	for label in SUN_MODES:
		sun_mode_dropdown.add_item(label, idx)
		sun_mode_dropdown.set_item_metadata(idx, SUN_MODES[label])
		idx += 1


# ============================================================================
# Drawer Lifecycle
# ============================================================================


## Override open to emit signal before the animation starts.
## The controller uses this to snapshot values and initialize the panel.
func open() -> void:
	drawer_opened.emit()
	super.open()


## Override _on_closed to notify the controller when the drawer finishes closing.
func _on_closed() -> void:
	drawer_closed.emit()


# ============================================================================
# Initialize
# ============================================================================


## Initialize the panel with current level data settings.
## Call this in response to drawer_opened, before the panel animates in.
## [param map_defaults] is the environment config extracted from the map's
## embedded WorldEnvironment (empty dict if none).  It is used as the base
## layer when preset is "" and for the "Map Defaults" dropdown option.
func initialize(
	level_data: LevelData, map_defaults: Dictionary = {}, has_map_sky: bool = false
) -> void:
	var intensity := level_data.light_intensity_scale
	var preset := level_data.environment_preset
	light_intensity_scale = intensity
	current_preset = preset
	current_water_style = level_data.water_style
	var water_style_matched := false
	for i in range(water_style_dropdown.item_count):
		if water_style_dropdown.get_item_metadata(i) == current_water_style:
			water_style_dropdown.select(i)
			water_style_matched = true
			break
	if not water_style_matched:
		# Corrupt/unrecognized save data -- fall back to the default preset
		# rather than leaving the dropdown showing a stale/mismatched item.
		# Must also update current_water_style directly (not just the
		# dropdown's visual selection): .select() doesn't emit item_selected,
		# so _on_water_style_selected() -- the only place that normally
		# updates current_water_style -- never runs here. Without this, Save
		# without touching the dropdown would silently re-persist the corrupt
		# value while the UI shows "Stylized".
		current_water_style = WaterPresets.DEFAULT_PRESET
		for i in range(water_style_dropdown.item_count):
			if water_style_dropdown.get_item_metadata(i) == WaterPresets.DEFAULT_PRESET:
				water_style_dropdown.select(i)
				break
	current_overrides = level_data.environment_overrides.duplicate()
	current_lofi_overrides = level_data.lofi_overrides.duplicate()
	current_weather_overrides = level_data.weather_overrides.duplicate()
	current_foliage_overrides = level_data.foliage_overrides.duplicate()
	current_sun = level_data.visual_settings.sun.copy_settings()
	_map_defaults = map_defaults

	# Set scale controls
	current_grid_cell_size = level_data.grid_cell_size
	current_display_unit = level_data.display_unit
	current_display_unit_per_cell = level_data.display_unit_per_cell
	_sync_scale_controls()

	# Set intensity control
	intensity_slider_spin.set_value_no_signal(intensity)

	# Repopulate preset dropdown (may include "Map Defaults" option)
	var has_map_defaults := not map_defaults.is_empty()
	_populate_preset_dropdown(has_map_defaults)

	# Select preset in dropdown
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == preset:
			preset_dropdown.select(i)
			break

	# Show revert button only when the map provided its own environment
	revert_to_map_button.visible = has_map_defaults

	# Repopulate sky dropdown (map_default may or may not be available)
	_populate_sky_preset_dropdown(has_map_sky)

	# Sync environment and lo-fi controls from stored values
	_sync_controls_from_config()
	_sync_lofi_controls()
	_sync_weather_controls()
	_sync_foliage_controls()
	_sync_sun_controls()

	# The gizmo does not survive a level change, so the toggle must not either.
	# initialize() resyncs every other sun control from the new level; without
	# this the button could stay latched against a freed SunGizmoTool.
	set_aim_sun_pressed(false)


## Apply new environment state from outside (e.g. after reverting to map defaults)
## and refresh all controls to match.
func apply_environment_state(preset: String, overrides: Dictionary) -> void:
	current_preset = preset
	current_overrides = overrides.duplicate()

	# Update preset dropdown selection
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == preset:
			preset_dropdown.select(i)
			break

	_sync_controls_from_config()


## Sync the environment controls to match the resolved preset + overrides config.
## Uses EnvironmentPresets to compute the final values rather than reading from
## a WorldEnvironment node, keeping the panel independent of the live scene.
func _sync_controls_from_config() -> void:
	var config = EnvironmentPresets.get_environment_config(
		current_preset, current_overrides, _map_defaults
	)

	# Basic controls
	bg_color_picker.color = config.get("background_color", Color(0.3, 0.3, 0.3))
	ambient_color_picker.color = config.get("ambient_light_color", Color(0.4, 0.4, 0.45))
	ambient_energy_slider_spin.set_value_no_signal(config.get("ambient_light_energy", 0.5))
	fog_enabled_check.set_pressed_no_signal(config.get("fog_enabled", false))
	fog_color_picker.color = config.get("fog_light_color", Color(0.5, 0.5, 0.55))
	fog_density_slider_spin.set_value_no_signal(config.get("fog_density", 0.01))
	glow_enabled_check.set_pressed_no_signal(config.get("glow_enabled", false))
	glow_intensity_slider_spin.set_value_no_signal(config.get("glow_intensity", 0.8))
	exposure_slider_spin.set_value_no_signal(config.get("tonemap_exposure", 1.0))
	brightness_slider_spin.set_value_no_signal(config.get("adjustment_brightness", 1.0))
	contrast_slider_spin.set_value_no_signal(config.get("adjustment_contrast", 1.0))
	saturation_slider_spin.set_value_no_signal(config.get("adjustment_saturation", 1.0))

	# Advanced controls — sky preset
	var sky_preset_name: String = config.get("sky_preset", "")
	for i in range(sky_preset_dropdown.item_count):
		if sky_preset_dropdown.get_item_metadata(i) == sky_preset_name:
			sky_preset_dropdown.select(i)
			break

	# Advanced controls — fog details
	fog_energy_slider_spin.set_value_no_signal(config.get("fog_light_energy", 1.0))
	fog_height_slider_spin.set_value_no_signal(config.get("fog_height", 0.0))
	fog_height_density_slider_spin.set_value_no_signal(config.get("fog_height_density", 0.0))

	# Advanced controls — tonemap
	var tm_mode: int = config.get("tonemap_mode", Environment.TONE_MAPPER_FILMIC)
	for i in range(tonemap_mode_dropdown.item_count):
		if tonemap_mode_dropdown.get_item_metadata(i) == tm_mode:
			tonemap_mode_dropdown.select(i)
			break
	tonemap_white_slider_spin.set_value_no_signal(config.get("tonemap_white", 1.0))

	# Advanced controls — glow details
	glow_strength_slider_spin.set_value_no_signal(config.get("glow_strength", 1.0))
	glow_bloom_slider_spin.set_value_no_signal(config.get("glow_bloom", 0.0))


# ============================================================================
# Scale & Measurement Handlers
# ============================================================================


func _populate_scale_preset_dropdown() -> void:
	scale_preset_dropdown.clear()
	var options := ScaleUtils.get_preset_options()
	for i in range(options.size()):
		scale_preset_dropdown.add_item(options[i].label, i)
		scale_preset_dropdown.set_item_metadata(i, options[i].key)


## Sync scale controls from current values.
## Also detects which preset (if any) currently matches.
func _sync_scale_controls() -> void:
	grid_cell_size_slider_spin.set_value_no_signal(current_grid_cell_size)

	# Find matching preset or fall back to "Custom"
	_current_scale_preset_key = "custom"
	for key in ScaleUtils.PRESETS:
		var p: Dictionary = ScaleUtils.PRESETS[key]
		if (
			is_equal_approx(p.grid_cell_size, current_grid_cell_size)
			and p.display_unit == current_display_unit
			and is_equal_approx(p.display_unit_per_cell, current_display_unit_per_cell)
		):
			_current_scale_preset_key = key
			break

	# Select the matching item in the dropdown
	for i in range(scale_preset_dropdown.item_count):
		if scale_preset_dropdown.get_item_metadata(i) == _current_scale_preset_key:
			scale_preset_dropdown.select(i)
			break


func _on_scale_preset_selected(index: int) -> void:
	var key: String = scale_preset_dropdown.get_item_metadata(index)
	_current_scale_preset_key = key
	if key == "custom":
		return
	if ScaleUtils.PRESETS.has(key):
		var p: Dictionary = ScaleUtils.PRESETS[key]
		current_grid_cell_size = p.grid_cell_size
		current_display_unit = p.display_unit
		current_display_unit_per_cell = p.display_unit_per_cell
		grid_cell_size_slider_spin.set_value_no_signal(current_grid_cell_size)
		scale_config_changed.emit(
			current_grid_cell_size, current_display_unit, current_display_unit_per_cell
		)


func _on_grid_cell_size_changed(value: float) -> void:
	current_grid_cell_size = value
	# Manually changing the slider switches to "Custom"
	_current_scale_preset_key = "custom"
	for i in range(scale_preset_dropdown.item_count):
		if scale_preset_dropdown.get_item_metadata(i) == "custom":
			scale_preset_dropdown.select(i)
			break
	scale_config_changed.emit(
		current_grid_cell_size, current_display_unit, current_display_unit_per_cell
	)


# ============================================================================
# Lighting Signal Handlers
# ============================================================================


func _on_preset_selected(index: int) -> void:
	current_preset = preset_dropdown.get_item_metadata(index)
	current_overrides.clear()
	environment_changed.emit(current_preset, current_overrides)
	_sync_controls_from_config()


func _on_intensity_changed(value: float) -> void:
	light_intensity_scale = value
	intensity_changed.emit(value)


func _on_water_style_selected(index: int) -> void:
	current_water_style = water_style_dropdown.get_item_metadata(index)
	water_style_changed.emit(current_water_style)


## Generic handler for config-driven environment overrides.
func _on_env_override_changed(value: Variant, key: String) -> void:
	current_overrides[key] = value
	environment_changed.emit(current_preset, current_overrides)


## Handler for adjustment overrides that also enables the adjustment system.
func _on_adjustment_override_changed(value: Variant, key: String) -> void:
	current_overrides[key] = value
	current_overrides["adjustment_enabled"] = true
	environment_changed.emit(current_preset, current_overrides)


# ============================================================================
# Advanced Toggle
# ============================================================================


func _on_advanced_toggled(pressed: bool) -> void:
	advanced_container.visible = pressed
	advanced_toggle.text = "Advanced ▲" if pressed else "Advanced ▼"


## Map scale and grid calibration are set once when a map is imported and never
## revisited while tuning a level's look, so they live in their own collapsed
## group rather than in the lighting flow. They stay in this drawer, not the
## Level Editor, because calibrating the grid means dragging it until it lines up
## with the map's visible squares -- which needs the live 3D view.
func _on_map_grid_toggled(pressed: bool) -> void:
	map_grid_container.visible = pressed
	map_grid_toggle.text = "Map & Grid ▲" if pressed else "Map & Grid ▼"


# ============================================================================
# Advanced Signal Handlers
# ============================================================================


func _on_sky_preset_selected(index: int) -> void:
	var sky_name: String = sky_preset_dropdown.get_item_metadata(index)
	current_overrides["sky_preset"] = sky_name
	# When a sky is selected, switch to BG_SKY; when "None", revert to BG_COLOR
	if sky_name != "":
		current_overrides["background_mode"] = Environment.BG_SKY
		current_overrides["ambient_light_source"] = Environment.AMBIENT_SOURCE_SKY
	else:
		current_overrides["background_mode"] = Environment.BG_COLOR
		current_overrides["ambient_light_source"] = Environment.AMBIENT_SOURCE_COLOR
	environment_changed.emit(current_preset, current_overrides)


func _on_tonemap_mode_selected(index: int) -> void:
	current_overrides["tonemap_mode"] = tonemap_mode_dropdown.get_item_metadata(index)
	environment_changed.emit(current_preset, current_overrides)


func _on_save_pressed() -> void:
	(
		save_requested
		. emit(
			{
				"light_intensity_scale": light_intensity_scale,
				"environment_preset": current_preset,
				"environment_overrides": current_overrides,
				"lofi_overrides": current_lofi_overrides,
				"weather_overrides": current_weather_overrides,
				"foliage_overrides": current_foliage_overrides,
				"sun_settings": current_sun,
				"grid_cell_size": current_grid_cell_size,
				"display_unit": current_display_unit,
				"display_unit_per_cell": current_display_unit_per_cell,
				"water_style": current_water_style,
			}
		)
	)


func _on_cancel_pressed() -> void:
	cancel_requested.emit()


# ============================================================================
# Lo-Fi Post-Processing Handlers
# ============================================================================


## Sync lo-fi controls from current_lofi_overrides (or defaults)
func _sync_lofi_controls() -> void:
	# Use stored overrides or defaults
	var pixelation = current_lofi_overrides.get("pixelation", Constants.LOFI_DEFAULTS["pixelation"])
	var saturation = current_lofi_overrides.get("saturation", Constants.LOFI_DEFAULTS["saturation"])
	var color_levels = current_lofi_overrides.get(
		"color_levels", Constants.LOFI_DEFAULTS["color_levels"]
	)
	var dither_strength = current_lofi_overrides.get(
		"dither_strength", Constants.LOFI_DEFAULTS["dither_strength"]
	)
	var vignette_strength = current_lofi_overrides.get(
		"vignette_strength", Constants.LOFI_DEFAULTS["vignette_strength"]
	)
	var grain_intensity = current_lofi_overrides.get(
		"grain_intensity", Constants.LOFI_DEFAULTS["grain_intensity"]
	)

	pixelation_slider_spin.set_value_no_signal(pixelation)
	color_fade_slider_spin.set_value_no_signal(saturation)
	color_levels_slider_spin.set_value_no_signal(color_levels)
	dither_slider_spin.set_value_no_signal(dither_strength)
	vignette_slider_spin.set_value_no_signal(vignette_strength)
	grain_slider_spin.set_value_no_signal(grain_intensity)


## Generic handler for config-driven lo-fi overrides.
func _on_lofi_override_changed(value: Variant, key: String) -> void:
	current_lofi_overrides[key] = value
	lofi_changed.emit(current_lofi_overrides)


## Generic handler for config-driven weather overrides.
func _on_weather_override_changed(value: Variant, key: String) -> void:
	current_weather_overrides[key] = value
	weather_changed.emit(current_weather_overrides)


## Sync weather controls from current_weather_overrides
func _sync_weather_controls() -> void:
	rain_slider_spin.set_value_no_signal(current_weather_overrides.get("rain_intensity", 0.0))
	snow_slider_spin.set_value_no_signal(current_weather_overrides.get("snow_intensity", 0.0))
	fog_slider_spin.set_value_no_signal(current_weather_overrides.get("fog_intensity", 0.0))
	wind_slider_spin.set_value_no_signal(current_weather_overrides.get("wind_intensity", 0.0))


## Sync foliage controls from current_foliage_overrides (or WindFoliage presets)
func _sync_foliage_controls() -> void:
	var tree_preset := WindFoliage.get_effective_preset("tree", current_foliage_overrides)
	var grass_preset := WindFoliage.get_effective_preset("grass", current_foliage_overrides)
	tree_sway_speed_slider_spin.set_value_no_signal(tree_preset["sway_speed"])
	tree_sway_amplitude_slider_spin.set_value_no_signal(tree_preset["sway_amplitude"])
	grass_sway_speed_slider_spin.set_value_no_signal(grass_preset["sway_speed"])
	grass_sway_amplitude_slider_spin.set_value_no_signal(grass_preset["sway_amplitude"])


## Generic handler for config-driven foliage sway overrides.
func _on_foliage_override_changed(value: Variant, key: String) -> void:
	current_foliage_overrides[key] = value
	foliage_changed.emit(current_foliage_overrides)


## The one sun control that must NOT promote auto to on: it is the control that
## chooses the mode.
func _on_sun_mode_selected(index: int) -> void:
	current_sun.mode = sun_mode_dropdown.get_item_metadata(index)
	_emit_sun_changed()


## Time of day is a GENERATOR, not the sun's interface: it regenerates direction,
## color, and energy from the keyframes, discarding any hand-aiming. The shadow
## fields and mode are user choices and are carried across.
func _on_sun_time_of_day_changed(value: float) -> void:
	var generated := DefaultSun.settings_for_time(value)
	generated.mode = current_sun.mode
	generated.shadows_enabled = current_sun.shadows_enabled
	generated.softness = current_sun.softness
	generated.shadow_darkness = current_sun.shadow_darkness
	current_sun = generated
	# Must come after the reassignment above: generated.mode was copied from the
	# old current_sun, so promoting before it would be overwritten here.
	_promote_auto_mode_to_on()
	_emit_sun_changed()
	_sync_sun_controls()


## Sync sun controls from current_sun.
func _sync_sun_controls() -> void:
	for i in range(sun_mode_dropdown.item_count):
		if sun_mode_dropdown.get_item_metadata(i) == current_sun.mode:
			sun_mode_dropdown.select(i)
			break
	sun_azimuth_slider_spin.set_value_no_signal(current_sun.azimuth_degrees)
	sun_elevation_slider_spin.set_value_no_signal(current_sun.elevation_degrees)
	sun_color_picker.color = current_sun.color
	sun_energy_slider_spin.set_value_no_signal(current_sun.energy)
	sun_shadows_check.set_pressed_no_signal(current_sun.shadows_enabled)
	sun_softness_slider_spin.set_value_no_signal(current_sun.softness)
	sun_softness_slider_spin.editable = current_sun.shadows_enabled
	sun_darkness_slider_spin.set_value_no_signal(current_sun.shadow_darkness)
	sun_darkness_slider_spin.editable = current_sun.shadows_enabled
	sun_time_of_day_slider_spin.set_value_no_signal(current_sun.time_of_day)
	_update_sun_generated_state()


## Emit the current sun and refresh the derived parts of the UI. Every sun
## control funnels through here -- including Mode and Time of Day, which used to
## emit sun_changed directly and so skipped the derived-state refresh.
func _emit_sun_changed() -> void:
	sun_changed.emit(current_sun)
	_update_sun_generated_state()


## A sun the user has deliberately shaped must actually be visible. In "auto"
## mode a map that brought its own lights hides the sun entirely, so editing any
## sun property while auto is selected promotes the mode to "on" -- otherwise the
## edit is a silent no-op.
func _promote_auto_mode_to_on() -> void:
	if current_sun.mode != "auto":
		return
	current_sun.mode = "on"
	for i in range(sun_mode_dropdown.item_count):
		if sun_mode_dropdown.get_item_metadata(i) == "on":
			sun_mode_dropdown.select(i)
			break


## Show the regenerate affordance only when the sun has been hand-aimed, i.e.
## when it no longer matches what the generator would produce for its recorded
## hour. Derived rather than tracked with a flag, so there is no second piece of
## state to keep in sync.
func _update_sun_generated_state() -> void:
	var generated := DefaultSun.settings_for_time(current_sun.time_of_day)
	var diverged := (
		not is_equal_approx(generated.azimuth_degrees, current_sun.azimuth_degrees)
		or not is_equal_approx(generated.elevation_degrees, current_sun.elevation_degrees)
		or not is_equal_approx(generated.energy, current_sun.energy)
		or generated.color != current_sun.color
	)
	sun_regenerate_button.visible = diverged


func _on_aim_sun_toggled(pressed: bool) -> void:
	aim_sun_toggled.emit(pressed)


func _on_sun_azimuth_changed(value: float) -> void:
	current_sun.azimuth_degrees = value
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_elevation_changed(value: float) -> void:
	current_sun.elevation_degrees = value
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_color_changed(color: Color) -> void:
	current_sun.color = color
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_energy_changed(value: float) -> void:
	current_sun.energy = value
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_shadows_toggled(pressed: bool) -> void:
	current_sun.shadows_enabled = pressed
	sun_softness_slider_spin.editable = pressed
	sun_darkness_slider_spin.editable = pressed
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_softness_changed(value: float) -> void:
	current_sun.softness = value
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_darkness_changed(value: float) -> void:
	current_sun.shadow_darkness = value
	_promote_auto_mode_to_on()
	_emit_sun_changed()


func _on_sun_regenerate_pressed() -> void:
	_on_sun_time_of_day_changed(current_sun.time_of_day)


## Called by GameplayMenuController when the gizmo reports a drag, so the
## numeric fields track the handle.
func set_sun_direction_from_gizmo(azimuth_degrees: float, elevation_degrees: float) -> void:
	current_sun.azimuth_degrees = azimuth_degrees
	current_sun.elevation_degrees = elevation_degrees
	sun_azimuth_slider_spin.set_value_no_signal(azimuth_degrees)
	sun_elevation_slider_spin.set_value_no_signal(elevation_degrees)
	_promote_auto_mode_to_on()
	_emit_sun_changed()


## Called by GameplayMenuController when the gizmo deactivates by any route
## (RMB, or the measure tool taking over), so the toggle button cannot be left
## showing a pressed state for an inactive tool.
func set_aim_sun_pressed(pressed: bool) -> void:
	aim_sun_button.set_pressed_no_signal(pressed)
