extends DrawerContainer
class_name LevelEditPanel

## Slide-out drawer for real-time level editing during gameplay.
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
signal open_editor_requested

## Emitted when the drawer opens (before the animation starts).
## The controller should snapshot current values and call initialize().
signal drawer_opened

## Emitted when the drawer finishes closing.
## The controller should revert changes if not saved.
signal drawer_closed

# Open full editor button
@onready var open_editor_button: Button = %OpenEditorButton

# Map scale control
@onready var map_scale_slider_spin: SliderSpinBox = %MapScaleSliderSpin

# Lighting controls
@onready var preset_dropdown: OptionButton = %PresetDropdown
@onready var intensity_slider_spin: SliderSpinBox = %IntensitySliderSpin
@onready var ambient_color_picker: ColorPickerButton = %AmbientColorPicker
@onready var ambient_energy_slider_spin: SliderSpinBox = %AmbientEnergySliderSpin
@onready var fog_enabled_check: CheckBox = %FogEnabledCheck
@onready var fog_density_slider_spin: SliderSpinBox = %FogDensitySliderSpin
@onready var glow_enabled_check: CheckBox = %GlowEnabledCheck
@onready var glow_intensity_slider_spin: SliderSpinBox = %GlowIntensitySliderSpin
@onready var revert_to_map_button: Button = %RevertToMapButton
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton

# Post-processing (lo-fi) controls
@onready var pixelation_slider_spin: SliderSpinBox = %PixelationSliderSpin
@onready var saturation_slider_spin: SliderSpinBox = %SaturationSliderSpin
@onready var color_levels_slider_spin: SliderSpinBox = %ColorLevelsSliderSpin
@onready var dither_slider_spin: SliderSpinBox = %DitherSliderSpin
@onready var vignette_slider_spin: SliderSpinBox = %VignetteSliderSpin
@onready var grain_slider_spin: SliderSpinBox = %GrainSliderSpin

var current_preset: String = "indoor_neutral"
var current_overrides: Dictionary = {}
var current_lofi_overrides: Dictionary = {}
var light_intensity_scale: float = 1.0
var map_scale: float = 1.0


func _on_ready() -> void:
	# Configure drawer
	edge = DrawerEdge.RIGHT
	drawer_width = 320.0
	tab_text = "Edit"
	play_sounds = true

	# Increase content padding inside the drawer panel
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

	_connect_control_signals()
	_populate_preset_dropdown()


func _connect_control_signals() -> void:
	# Open full editor
	open_editor_button.pressed.connect(func() -> void: open_editor_requested.emit())

	# Map scale
	map_scale_slider_spin.value_changed.connect(_on_map_scale_changed)

	# Lighting UI signals
	preset_dropdown.item_selected.connect(_on_preset_selected)
	intensity_slider_spin.value_changed.connect(_on_intensity_changed)
	ambient_color_picker.color_changed.connect(_on_ambient_color_changed)
	ambient_energy_slider_spin.value_changed.connect(_on_ambient_energy_changed)
	fog_enabled_check.toggled.connect(_on_fog_enabled_changed)
	fog_density_slider_spin.value_changed.connect(_on_fog_density_changed)
	glow_enabled_check.toggled.connect(_on_glow_enabled_changed)
	glow_intensity_slider_spin.value_changed.connect(_on_glow_intensity_changed)

	# Post-processing (lo-fi) UI signals
	pixelation_slider_spin.value_changed.connect(_on_pixelation_changed)
	saturation_slider_spin.value_changed.connect(_on_saturation_changed)
	color_levels_slider_spin.value_changed.connect(_on_color_levels_changed)
	dither_slider_spin.value_changed.connect(_on_dither_changed)
	vignette_slider_spin.value_changed.connect(_on_vignette_changed)
	grain_slider_spin.value_changed.connect(_on_grain_changed)

	revert_to_map_button.pressed.connect(func() -> void: revert_to_map_defaults_requested.emit())
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func _populate_preset_dropdown() -> void:
	preset_dropdown.clear()
	var presets = EnvironmentPresets.get_preset_names()

	for i in range(presets.size()):
		var preset_name = presets[i]
		var description = EnvironmentPresets.get_preset_description(preset_name)
		preset_dropdown.add_item("%s" % preset_name, i)
		preset_dropdown.set_item_tooltip(i, description)
		preset_dropdown.set_item_metadata(i, preset_name)


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
## [param has_map_defaults] controls whether the "Revert to Map Defaults"
## button is shown (true when the loaded map had an embedded WorldEnvironment).
func initialize(
	current_map_scale: float,
	intensity: float,
	preset: String,
	overrides: Dictionary,
	lofi_overrides: Dictionary = {},
	has_map_defaults: bool = false,
) -> void:
	map_scale = current_map_scale
	light_intensity_scale = intensity
	current_preset = preset
	current_overrides = overrides.duplicate()
	current_lofi_overrides = lofi_overrides.duplicate()

	# Set map scale control
	map_scale_slider_spin.set_value_no_signal(current_map_scale)

	# Set intensity control
	intensity_slider_spin.set_value_no_signal(intensity)

	# Select preset in dropdown
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == preset:
			preset_dropdown.select(i)
			break

	# Show revert button only when the map provided its own environment
	revert_to_map_button.visible = has_map_defaults

	# Sync environment and lo-fi controls from stored values
	_sync_controls_from_config()
	_sync_lofi_controls()


## Apply new environment state from outside (e.g. after reverting to map defaults)
## and refresh all controls to match.
func apply_environment_state(preset: String, overrides: Dictionary) -> void:
	current_preset = preset
	current_overrides = overrides.duplicate()

	# Update preset dropdown
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == preset:
			preset_dropdown.select(i)
			break

	_sync_controls_from_config()


## Sync the environment controls to match the resolved preset + overrides config.
## Uses EnvironmentPresets to compute the final values rather than reading from
## a WorldEnvironment node, keeping the panel independent of the live scene.
func _sync_controls_from_config() -> void:
	var config = EnvironmentPresets.get_environment_config(current_preset, current_overrides)
	ambient_color_picker.color = config.get("ambient_light_color", Color(0.4, 0.4, 0.45))
	ambient_energy_slider_spin.set_value_no_signal(config.get("ambient_light_energy", 0.5))
	fog_enabled_check.set_pressed_no_signal(config.get("fog_enabled", false))
	fog_density_slider_spin.set_value_no_signal(config.get("fog_density", 0.01))
	glow_enabled_check.set_pressed_no_signal(config.get("glow_enabled", false))
	glow_intensity_slider_spin.set_value_no_signal(config.get("glow_intensity", 0.8))


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


func _on_ambient_color_changed(color: Color) -> void:
	current_overrides["ambient_light_color"] = color
	environment_changed.emit(current_preset, current_overrides)


func _on_ambient_energy_changed(value: float) -> void:
	current_overrides["ambient_light_energy"] = value
	environment_changed.emit(current_preset, current_overrides)


func _on_fog_enabled_changed(enabled: bool) -> void:
	current_overrides["fog_enabled"] = enabled
	environment_changed.emit(current_preset, current_overrides)


func _on_fog_density_changed(value: float) -> void:
	current_overrides["fog_density"] = value
	environment_changed.emit(current_preset, current_overrides)


func _on_glow_enabled_changed(enabled: bool) -> void:
	current_overrides["glow_enabled"] = enabled
	environment_changed.emit(current_preset, current_overrides)


func _on_glow_intensity_changed(value: float) -> void:
	current_overrides["glow_intensity"] = value
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
	var pixelation = current_lofi_overrides.get("pixelation", 0.003)
	var saturation = current_lofi_overrides.get("saturation", 0.85)
	var color_levels = current_lofi_overrides.get("color_levels", 32.0)
	var dither_strength = current_lofi_overrides.get("dither_strength", 0.5)
	var vignette_strength = current_lofi_overrides.get("vignette_strength", 0.3)
	var grain_intensity = current_lofi_overrides.get("grain_intensity", 0.025)

	pixelation_slider_spin.set_value_no_signal(pixelation)
	saturation_slider_spin.set_value_no_signal(saturation)
	color_levels_slider_spin.set_value_no_signal(color_levels)
	dither_slider_spin.set_value_no_signal(dither_strength)
	vignette_slider_spin.set_value_no_signal(vignette_strength)
	grain_slider_spin.set_value_no_signal(grain_intensity)


func _emit_lofi_changed() -> void:
	lofi_changed.emit(current_lofi_overrides)


func _on_pixelation_changed(value: float) -> void:
	current_lofi_overrides["pixelation"] = value
	_emit_lofi_changed()


func _on_saturation_changed(value: float) -> void:
	current_lofi_overrides["saturation"] = value
	_emit_lofi_changed()


func _on_color_levels_changed(value: float) -> void:
	current_lofi_overrides["color_levels"] = value
	_emit_lofi_changed()


func _on_dither_changed(value: float) -> void:
	current_lofi_overrides["dither_strength"] = value
	_emit_lofi_changed()


func _on_vignette_changed(value: float) -> void:
	current_lofi_overrides["vignette_strength"] = value
	_emit_lofi_changed()


func _on_grain_changed(value: float) -> void:
	current_lofi_overrides["grain_intensity"] = value
	_emit_lofi_changed()
