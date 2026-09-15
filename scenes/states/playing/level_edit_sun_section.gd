class_name LevelEditSunSection
extends RefCounted

## Owns the Visuals drawer's Sun section: control references, mode-dropdown
## population, syncing controls from a SunSettings, the "hand-aimed vs
## generated" derived state, the auto-to-on promotion rule, and every handler
## that mutates a SunSettings. Split out of level_edit_panel.gd to keep that
## file under the project's max-file-lines lint budget.
##
## The section holds no SunSettings of its own -- [param get_settings] (given
## to _init()) fetches the panel's current_sun fresh on every signal, since
## time-of-day regeneration replaces that object wholesale rather than mutating
## it in place. [param on_changed] is called with the resulting settings after
## every mutation; the panel's bound method re-adopts it as current_sun,
## _mark_dirty()s, and emits sun_changed.

const SUN_MODES := {
	"Auto": "auto",
	"On": "on",
	"Off": "off",
}

var _mode_dropdown: OptionButton
var _time_of_day_slider_spin: SliderSpinBox
var _aim_button: Button
var _azimuth_slider_spin: SliderSpinBox
var _elevation_slider_spin: SliderSpinBox
var _color_picker: ColorPickerButton
var _energy_slider_spin: SliderSpinBox
var _shadows_check: CheckBox
var _softness_slider_spin: SliderSpinBox
var _darkness_slider_spin: SliderSpinBox
var _regenerate_button: Button
var _get_settings: Callable
var _on_changed: Callable


func _init(
	panel: Node, get_settings: Callable, on_changed: Callable, on_aim_toggled: Callable
) -> void:
	_mode_dropdown = panel.sun_mode_dropdown
	_time_of_day_slider_spin = panel.sun_time_of_day_slider_spin
	_aim_button = panel.aim_sun_button
	_azimuth_slider_spin = panel.sun_azimuth_slider_spin
	_elevation_slider_spin = panel.sun_elevation_slider_spin
	_color_picker = panel.sun_color_picker
	_energy_slider_spin = panel.sun_energy_slider_spin
	_shadows_check = panel.sun_shadows_check
	_softness_slider_spin = panel.sun_softness_slider_spin
	_darkness_slider_spin = panel.sun_darkness_slider_spin
	_regenerate_button = panel.sun_regenerate_button
	_get_settings = get_settings
	_on_changed = on_changed
	_mode_dropdown.item_selected.connect(_on_mode_selected)
	_time_of_day_slider_spin.value_changed.connect(_on_time_of_day_changed)
	_aim_button.toggled.connect(on_aim_toggled)
	_azimuth_slider_spin.value_changed.connect(_on_azimuth_changed)
	_elevation_slider_spin.value_changed.connect(_on_elevation_changed)
	_color_picker.color_changed.connect(_on_color_changed)
	_energy_slider_spin.value_changed.connect(on_energy_changed)
	_shadows_check.toggled.connect(_on_shadows_toggled)
	_softness_slider_spin.value_changed.connect(_on_softness_changed)
	_darkness_slider_spin.value_changed.connect(_on_darkness_changed)
	_regenerate_button.pressed.connect(_on_regenerate_pressed)


func populate_mode_dropdown() -> void:
	_mode_dropdown.clear()
	var idx := 0
	for label in SUN_MODES:
		_mode_dropdown.add_item(label, idx)
		_mode_dropdown.set_item_metadata(idx, SUN_MODES[label])
		idx += 1


## Sync every sun control from [param settings].
func sync_controls(settings: SunSettings) -> void:
	LevelEditPanel._select_by_metadata(_mode_dropdown, settings.mode)
	_azimuth_slider_spin.set_value_no_signal(settings.azimuth_degrees)
	_elevation_slider_spin.set_value_no_signal(settings.elevation_degrees)
	_color_picker.color = settings.color
	_energy_slider_spin.set_value_no_signal(settings.energy)
	_shadows_check.set_pressed_no_signal(settings.shadows_enabled)
	_softness_slider_spin.set_value_no_signal(settings.softness)
	_softness_slider_spin.editable = settings.shadows_enabled
	_darkness_slider_spin.set_value_no_signal(settings.shadow_darkness)
	_darkness_slider_spin.editable = settings.shadows_enabled
	_time_of_day_slider_spin.set_value_no_signal(settings.time_of_day)
	update_generated_state(settings)


## Show the regenerate affordance only when [param settings] no longer matches
## what the generator would produce for its recorded hour.
func update_generated_state(settings: SunSettings) -> void:
	var generated := DefaultSun.settings_for_time(settings.time_of_day)
	var diverged := (
		not is_equal_approx(generated.azimuth_degrees, settings.azimuth_degrees)
		or not is_equal_approx(generated.elevation_degrees, settings.elevation_degrees)
		or not is_equal_approx(generated.energy, settings.energy)
		or generated.color != settings.color
	)
	_regenerate_button.visible = diverged


func set_aim_pressed(pressed: bool) -> void:
	_aim_button.set_pressed_no_signal(pressed)


## Called by GameplayMenuController via the panel's set_sun_direction_from_gizmo()
## forward when the gizmo reports a drag, so the numeric fields track the handle.
func apply_gizmo_direction(azimuth_degrees: float, elevation_degrees: float) -> void:
	var settings := _current()
	settings.azimuth_degrees = azimuth_degrees
	settings.elevation_degrees = elevation_degrees
	_azimuth_slider_spin.set_value_no_signal(azimuth_degrees)
	_elevation_slider_spin.set_value_no_signal(elevation_degrees)
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _current() -> SunSettings:
	return _get_settings.call()


func _emit_changed(settings: SunSettings) -> void:
	_on_changed.call(settings)
	update_generated_state(settings)


## A sun the user has deliberately shaped must actually be visible. In "auto"
## mode a map that brought its own lights hides the sun entirely, so editing any
## sun property while auto is selected promotes the mode to "on" -- otherwise
## the edit is a silent no-op.
func _promote_auto_to_on(settings: SunSettings) -> void:
	if settings.mode != "auto":
		return
	settings.mode = "on"
	LevelEditPanel._select_by_metadata(_mode_dropdown, "on")


## The one sun control that must NOT promote auto to on: it is the control that
## chooses the mode.
func _on_mode_selected(index: int) -> void:
	var settings := _current()
	settings.mode = _mode_dropdown.get_item_metadata(index)
	_emit_changed(settings)


## Time of day is a GENERATOR, not the sun's interface: it regenerates
## direction, color, and energy from the keyframes, discarding any hand-aiming.
## The shadow fields and mode are user choices and are carried across.
func _on_time_of_day_changed(value: float) -> void:
	var settings := _current()
	var generated := DefaultSun.settings_for_time(value)
	generated.mode = settings.mode
	generated.shadows_enabled = settings.shadows_enabled
	generated.softness = settings.softness
	generated.shadow_darkness = settings.shadow_darkness
	_promote_auto_to_on(generated)
	_emit_changed(generated)
	sync_controls(generated)


func _on_azimuth_changed(value: float) -> void:
	var settings := _current()
	settings.azimuth_degrees = value
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_elevation_changed(value: float) -> void:
	var settings := _current()
	settings.elevation_degrees = value
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_color_changed(color: Color) -> void:
	var settings := _current()
	settings.color = color
	_promote_auto_to_on(settings)
	_emit_changed(settings)


## Public (no leading underscore): also invoked directly by the panel's
## _on_sun_energy_changed() forward, which tests/unit/test_level_edit_panel_dirty.gd
## calls by name.
func on_energy_changed(value: float) -> void:
	var settings := _current()
	settings.energy = value
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_shadows_toggled(pressed: bool) -> void:
	var settings := _current()
	settings.shadows_enabled = pressed
	_softness_slider_spin.editable = pressed
	_darkness_slider_spin.editable = pressed
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_softness_changed(value: float) -> void:
	var settings := _current()
	settings.softness = value
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_darkness_changed(value: float) -> void:
	var settings := _current()
	settings.shadow_darkness = value
	_promote_auto_to_on(settings)
	_emit_changed(settings)


func _on_regenerate_pressed() -> void:
	_on_time_of_day_changed(_current().time_of_day)
