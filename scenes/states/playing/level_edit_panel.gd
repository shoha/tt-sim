extends DrawerContainer
class_name LevelEditPanel

## Slide-out drawer for real-time visual tuning during gameplay.
## Provides controls for map scale, lighting, environment, and post-processing.
## Changes apply immediately to the live game viewport.
## Uses DrawerContainer with edge = RIGHT so the tab appears on the left.

signal save_requested(
	map_scale: float,
	light_intensity_scale: float,
	environment_preset: String,
	environment_overrides: Dictionary,
	lofi_overrides: Dictionary
)
signal cancel_requested
signal map_scale_changed(new_scale: float)
signal intensity_changed(new_scale: float)
signal environment_changed(preset: String, overrides: Dictionary)
signal lofi_changed(overrides: Dictionary)
signal revert_to_map_defaults_requested

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

# Map scale control
@onready var map_scale_slider_spin: SliderSpinBox = %MapScaleSliderSpin

# Lighting controls — basic
@onready var preset_dropdown: OptionButton = %PresetDropdown
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
@onready var ssao_enabled_check: CheckBox = %SSAOEnabledCheck
@onready var ssao_intensity_slider_spin: SliderSpinBox = %SSAOIntensitySliderSpin
@onready var ssr_enabled_check: CheckBox = %SSREnabledCheck
@onready var sdfgi_enabled_check: CheckBox = %SDFGIEnabledCheck

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

var current_preset: String = ""
var current_overrides: Dictionary = {}
var current_lofi_overrides: Dictionary = {}
var light_intensity_scale: float = 1.0
var map_scale: float = 1.0
## Environment config extracted from the map's embedded WorldEnvironment.
## Used as the base layer when current_preset is "" (no explicit choice).
var _map_defaults: Dictionary = {}


func _on_ready() -> void:
	# Configure drawer
	edge = DrawerEdge.RIGHT
	drawer_width = 350.0
	tab_text = "Visuals"
	play_sounds = true

	# Increase content padding inside the drawer panel.
	var margin_node = _panel.get_child(0) as MarginContainer
	if margin_node:
		margin_node.add_theme_constant_override("margin_left", 16)
		margin_node.add_theme_constant_override("margin_right", 16)
		margin_node.add_theme_constant_override("margin_top", 16)
		margin_node.add_theme_constant_override("margin_bottom", 16)

	# Reparent the scene-defined ScrollContainer into the drawer's content area.
	# Must set size_flags so the VBoxContainer allocates full height to it.
	var scroll = $ScrollContainer
	if scroll:
		scroll.get_parent().remove_child(scroll)
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_container.add_child(scroll)

		# Wrap the VBox in an inner MarginContainer so the right padding sits
		# *between* the content and the scrollbar, not outside the scrollbar.
		var vbox = scroll.get_child(0)
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
	_populate_preset_dropdown()
	_populate_sky_preset_dropdown()
	_populate_tonemap_mode_dropdown()


func _connect_control_signals() -> void:
	# Map scale
	map_scale_slider_spin.value_changed.connect(_on_map_scale_changed)

	# Special-case controls (preset selection, dropdowns with complex logic)
	preset_dropdown.item_selected.connect(_on_preset_selected)
	intensity_slider_spin.value_changed.connect(_on_intensity_changed)
	advanced_toggle.toggled.connect(_on_advanced_toggled)
	sky_preset_dropdown.item_selected.connect(_on_sky_preset_selected)
	tonemap_mode_dropdown.item_selected.connect(_on_tonemap_mode_selected)

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
		[ssao_enabled_check, "toggled", "ssao_enabled"],
		[ssao_intensity_slider_spin, "value_changed", "ssao_intensity"],
		[ssr_enabled_check, "toggled", "ssr_enabled"],
		[sdfgi_enabled_check, "toggled", "sdfgi_enabled"],
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
	current_map_scale: float,
	intensity: float,
	preset: String,
	overrides: Dictionary,
	lofi_overrides: Dictionary = {},
	map_defaults: Dictionary = {},
	has_map_sky: bool = false,
) -> void:
	map_scale = current_map_scale
	light_intensity_scale = intensity
	current_preset = preset
	current_overrides = overrides.duplicate()
	current_lofi_overrides = lofi_overrides.duplicate()
	_map_defaults = map_defaults

	# Set map scale control
	map_scale_slider_spin.set_value_no_signal(current_map_scale)

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

	# Advanced controls — SSAO, SSR, SDFGI
	ssao_enabled_check.set_pressed_no_signal(config.get("ssao_enabled", false))
	ssao_intensity_slider_spin.set_value_no_signal(config.get("ssao_intensity", 2.0))
	ssr_enabled_check.set_pressed_no_signal(config.get("ssr_enabled", false))
	sdfgi_enabled_check.set_pressed_no_signal(config.get("sdfgi_enabled", false))


# ============================================================================
# Map Scale Handler
# ============================================================================


func _on_map_scale_changed(value: float) -> void:
	map_scale = value
	map_scale_changed.emit(value)


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
	save_requested.emit(
		map_scale, light_intensity_scale, current_preset, current_overrides, current_lofi_overrides
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
	var color_levels = current_lofi_overrides.get("color_levels", Constants.LOFI_DEFAULTS["color_levels"])
	var dither_strength = current_lofi_overrides.get("dither_strength", Constants.LOFI_DEFAULTS["dither_strength"])
	var vignette_strength = current_lofi_overrides.get("vignette_strength", Constants.LOFI_DEFAULTS["vignette_strength"])
	var grain_intensity = current_lofi_overrides.get("grain_intensity", Constants.LOFI_DEFAULTS["grain_intensity"])

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
