extends Control
class_name LightingEditorPanel

## Compact floating panel for editing level lighting, environment, and post-processing settings.
## Displays over the 3D map preview for real-time feedback.

signal save_requested(light_intensity_scale: float, environment_preset: String, environment_overrides: Dictionary, lofi_overrides: Dictionary)
signal cancel_requested()
signal intensity_changed(new_scale: float)
signal lofi_changed(overrides: Dictionary)

# Lighting controls
@onready var resize_handle: Control = %ResizeHandle
@onready var preset_dropdown: OptionButton = %PresetDropdown
@onready var intensity_slider: HSlider = %IntensitySlider
@onready var intensity_spin: SpinBox = %IntensitySpin
@onready var ambient_color_picker: ColorPickerButton = %AmbientColorPicker
@onready var ambient_energy_slider: HSlider = %AmbientEnergySlider
@onready var ambient_energy_spin: SpinBox = %AmbientEnergySpin
@onready var fog_enabled_check: CheckBox = %FogEnabledCheck
@onready var fog_density_slider: HSlider = %FogDensitySlider
@onready var fog_density_spin: SpinBox = %FogDensitySpin
@onready var glow_enabled_check: CheckBox = %GlowEnabledCheck
@onready var glow_intensity_slider: HSlider = %GlowIntensitySlider
@onready var glow_intensity_spin: SpinBox = %GlowIntensitySpin
@onready var save_button: Button = %SaveButton
@onready var cancel_button: Button = %CancelButton

# Post-processing (lo-fi) controls
@onready var pixelation_slider: HSlider = %PixelationSlider
@onready var pixelation_spin: SpinBox = %PixelationSpin
@onready var saturation_slider: HSlider = %SaturationSlider
@onready var saturation_spin: SpinBox = %SaturationSpin
@onready var color_levels_slider: HSlider = %ColorLevelsSlider
@onready var color_levels_spin: SpinBox = %ColorLevelsSpin
@onready var dither_slider: HSlider = %DitherSlider
@onready var dither_spin: SpinBox = %DitherSpin
@onready var vignette_slider: HSlider = %VignetteSlider
@onready var vignette_spin: SpinBox = %VignetteSpin
@onready var grain_slider: HSlider = %GrainSlider
@onready var grain_spin: SpinBox = %GrainSpin

var world_environment: WorldEnvironment = null
var current_preset: String = "indoor_neutral"
var current_overrides: Dictionary = {}
var current_lofi_overrides: Dictionary = {}
var light_intensity_scale: float = 1.0

# Resize state
var _is_resizing: bool = false
var _resize_start_x: float = 0.0
var _resize_start_width: float = 0.0
const MIN_PANEL_WIDTH: float = 280.0
const MAX_PANEL_WIDTH: float = 600.0


func _ready() -> void:
	# Connect resize handle
	resize_handle.gui_input.connect(_on_resize_handle_input)
	
	# Connect lighting UI signals
	preset_dropdown.item_selected.connect(_on_preset_selected)
	intensity_slider.value_changed.connect(_on_intensity_slider_changed)
	intensity_spin.value_changed.connect(_on_intensity_spin_changed)
	ambient_color_picker.color_changed.connect(_on_ambient_color_changed)
	ambient_energy_slider.value_changed.connect(_on_ambient_energy_slider_changed)
	ambient_energy_spin.value_changed.connect(_on_ambient_energy_spin_changed)
	fog_enabled_check.toggled.connect(_on_fog_enabled_changed)
	fog_density_slider.value_changed.connect(_on_fog_density_slider_changed)
	fog_density_spin.value_changed.connect(_on_fog_density_spin_changed)
	glow_enabled_check.toggled.connect(_on_glow_enabled_changed)
	glow_intensity_slider.value_changed.connect(_on_glow_intensity_slider_changed)
	glow_intensity_spin.value_changed.connect(_on_glow_intensity_spin_changed)
	
	# Connect post-processing (lo-fi) UI signals
	pixelation_slider.value_changed.connect(_on_pixelation_slider_changed)
	pixelation_spin.value_changed.connect(_on_pixelation_spin_changed)
	saturation_slider.value_changed.connect(_on_saturation_slider_changed)
	saturation_spin.value_changed.connect(_on_saturation_spin_changed)
	color_levels_slider.value_changed.connect(_on_color_levels_slider_changed)
	color_levels_spin.value_changed.connect(_on_color_levels_spin_changed)
	dither_slider.value_changed.connect(_on_dither_slider_changed)
	dither_spin.value_changed.connect(_on_dither_spin_changed)
	vignette_slider.value_changed.connect(_on_vignette_slider_changed)
	vignette_spin.value_changed.connect(_on_vignette_spin_changed)
	grain_slider.value_changed.connect(_on_grain_slider_changed)
	grain_spin.value_changed.connect(_on_grain_spin_changed)
	
	save_button.pressed.connect(_on_save_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Populate preset dropdown
	_populate_preset_dropdown()


func _populate_preset_dropdown() -> void:
	preset_dropdown.clear()
	var presets = EnvironmentPresets.get_preset_names()
	
	for i in range(presets.size()):
		var preset_name = presets[i]
		var description = EnvironmentPresets.get_preset_description(preset_name)
		preset_dropdown.add_item("%s" % preset_name, i)
		preset_dropdown.set_item_tooltip(i, description)
		preset_dropdown.set_item_metadata(i, preset_name)


## Initialize the panel with current level data settings
func initialize(env: WorldEnvironment, intensity: float, preset: String, overrides: Dictionary, lofi_overrides: Dictionary = {}) -> void:
	world_environment = env
	light_intensity_scale = intensity
	current_preset = preset
	current_overrides = overrides.duplicate()
	current_lofi_overrides = lofi_overrides.duplicate()
	
	# Set intensity controls (set spin first to avoid feedback loop)
	intensity_spin.set_value_no_signal(intensity)
	intensity_slider.set_value_no_signal(intensity)
	
	# Select preset in dropdown
	for i in range(preset_dropdown.item_count):
		if preset_dropdown.get_item_metadata(i) == preset:
			preset_dropdown.select(i)
			break
	
	# Apply current settings
	_apply_environment()
	_sync_controls_from_environment()
	_sync_lofi_controls()


func _apply_environment() -> void:
	if is_instance_valid(world_environment):
		EnvironmentPresets.apply_to_world_environment(world_environment, current_preset, current_overrides)


func _sync_controls_from_environment() -> void:
	if not is_instance_valid(world_environment) or not world_environment.environment:
		return
	
	var env = world_environment.environment
	
	# Sync controls to current environment values (use set_value_no_signal to avoid feedback loops)
	ambient_color_picker.color = env.ambient_light_color
	ambient_energy_slider.set_value_no_signal(env.ambient_light_energy)
	ambient_energy_spin.set_value_no_signal(env.ambient_light_energy)
	fog_enabled_check.set_pressed_no_signal(env.fog_enabled)
	fog_density_slider.set_value_no_signal(env.fog_density)
	fog_density_spin.set_value_no_signal(env.fog_density)
	glow_enabled_check.set_pressed_no_signal(env.glow_enabled)
	glow_intensity_slider.set_value_no_signal(env.glow_intensity)
	glow_intensity_spin.set_value_no_signal(env.glow_intensity)


# Signal handlers
func _on_preset_selected(index: int) -> void:
	current_preset = preset_dropdown.get_item_metadata(index)
	current_overrides.clear()
	_apply_environment()
	_sync_controls_from_environment()


func _on_intensity_slider_changed(value: float) -> void:
	light_intensity_scale = value
	intensity_spin.set_value_no_signal(value)
	intensity_changed.emit(value)


func _on_intensity_spin_changed(value: float) -> void:
	light_intensity_scale = value
	intensity_slider.set_value_no_signal(value)
	intensity_changed.emit(value)


func _on_ambient_color_changed(color: Color) -> void:
	current_overrides["ambient_light_color"] = color
	_apply_environment()


func _on_ambient_energy_slider_changed(value: float) -> void:
	current_overrides["ambient_light_energy"] = value
	ambient_energy_spin.set_value_no_signal(value)
	_apply_environment()


func _on_ambient_energy_spin_changed(value: float) -> void:
	current_overrides["ambient_light_energy"] = value
	ambient_energy_slider.set_value_no_signal(value)
	_apply_environment()


func _on_fog_enabled_changed(enabled: bool) -> void:
	current_overrides["fog_enabled"] = enabled
	_apply_environment()


func _on_fog_density_slider_changed(value: float) -> void:
	current_overrides["fog_density"] = value
	fog_density_spin.set_value_no_signal(value)
	_apply_environment()


func _on_fog_density_spin_changed(value: float) -> void:
	current_overrides["fog_density"] = value
	fog_density_slider.set_value_no_signal(value)
	_apply_environment()


func _on_glow_enabled_changed(enabled: bool) -> void:
	current_overrides["glow_enabled"] = enabled
	_apply_environment()


func _on_glow_intensity_slider_changed(value: float) -> void:
	current_overrides["glow_intensity"] = value
	glow_intensity_spin.set_value_no_signal(value)
	_apply_environment()


func _on_glow_intensity_spin_changed(value: float) -> void:
	current_overrides["glow_intensity"] = value
	glow_intensity_slider.set_value_no_signal(value)
	_apply_environment()


func _on_save_pressed() -> void:
	save_requested.emit(light_intensity_scale, current_preset, current_overrides, current_lofi_overrides)


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
	
	pixelation_slider.set_value_no_signal(pixelation)
	pixelation_spin.set_value_no_signal(pixelation)
	saturation_slider.set_value_no_signal(saturation)
	saturation_spin.set_value_no_signal(saturation)
	color_levels_slider.set_value_no_signal(color_levels)
	color_levels_spin.set_value_no_signal(color_levels)
	dither_slider.set_value_no_signal(dither_strength)
	dither_spin.set_value_no_signal(dither_strength)
	vignette_slider.set_value_no_signal(vignette_strength)
	vignette_spin.set_value_no_signal(vignette_strength)
	grain_slider.set_value_no_signal(grain_intensity)
	grain_spin.set_value_no_signal(grain_intensity)


func _emit_lofi_changed() -> void:
	lofi_changed.emit(current_lofi_overrides)


func _on_pixelation_slider_changed(value: float) -> void:
	current_lofi_overrides["pixelation"] = value
	pixelation_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_pixelation_spin_changed(value: float) -> void:
	current_lofi_overrides["pixelation"] = value
	pixelation_slider.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_saturation_slider_changed(value: float) -> void:
	current_lofi_overrides["saturation"] = value
	saturation_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_saturation_spin_changed(value: float) -> void:
	current_lofi_overrides["saturation"] = value
	saturation_slider.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_color_levels_slider_changed(value: float) -> void:
	current_lofi_overrides["color_levels"] = value
	color_levels_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_color_levels_spin_changed(value: float) -> void:
	current_lofi_overrides["color_levels"] = value
	color_levels_slider.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_dither_slider_changed(value: float) -> void:
	current_lofi_overrides["dither_strength"] = value
	dither_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_dither_spin_changed(value: float) -> void:
	current_lofi_overrides["dither_strength"] = value
	dither_slider.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_vignette_slider_changed(value: float) -> void:
	current_lofi_overrides["vignette_strength"] = value
	vignette_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_vignette_spin_changed(value: float) -> void:
	current_lofi_overrides["vignette_strength"] = value
	vignette_slider.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_grain_slider_changed(value: float) -> void:
	current_lofi_overrides["grain_intensity"] = value
	grain_spin.set_value_no_signal(value)
	_emit_lofi_changed()


func _on_grain_spin_changed(value: float) -> void:
	current_lofi_overrides["grain_intensity"] = value
	grain_slider.set_value_no_signal(value)
	_emit_lofi_changed()


# ============================================================================
# Resize Handling
# ============================================================================

func _on_resize_handle_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_is_resizing = true
				_resize_start_x = get_global_mouse_position().x
				_resize_start_width = size.x
			else:
				_is_resizing = false


func _input(event: InputEvent) -> void:
	if not _is_resizing:
		return
	
	if event is InputEventMouseMotion:
		var delta_x = get_global_mouse_position().x - _resize_start_x
		# Dragging left (negative delta) should increase width
		var new_width = _resize_start_width - delta_x
		new_width = clampf(new_width, MIN_PANEL_WIDTH, MAX_PANEL_WIDTH)
		
		# Update the panel's left offset to resize from the left edge
		custom_minimum_size.x = new_width
		offset_left = -new_width - 20  # 20px margin from right edge
	
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_is_resizing = false
