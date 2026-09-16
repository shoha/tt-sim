class_name SunPane
extends LevelEditPane

## Sun direction, colour, energy and shadows. Time of day is a GENERATOR, not
## the sun's interface: it regenerates direction, colour and energy from the
## keyframes, discarding hand-aiming; mode and shadow fields are user choices
## carried across. Editing any sun property while the mode is "auto" promotes
## it to "on", because an auto sun may be hidden by a map that brings its own
## lights and the edit would otherwise be a silent no-op.

signal sun_changed(settings: SunSettings)
signal aim_toggled(active: bool)

## [mode value, label, icon]
const MODES := [["auto", "Auto", "wand"], ["on", "On", "sun"], ["off", "Off", "sun-off"]]
## [tile id, label, icon]
const SHADOW_TILES := [
	["off", "Off", "circle-off"], ["hard", "Hard", "contrast"], ["soft", "Soft", "cloud"]
]
const SHADOW_SOFT_SOFTNESS := 1.5
const SHADOW_HARD_MAX_SOFTNESS := 0.25
const COMPASS := ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const TIME_TOOLTIP := (
	"Regenerates direction, colour and energy from this hour. "
	+ "Any hand-aimed values are replaced."
)

var _sun: SunSettings = SunSettings.default()
var _time_row: PropertyRow
var _mode_field: TileField
var _mode_tiles: TileRow
var _shadow_field: TileField
var _aim_button: IconButton
var _azimuth_row: PropertyRow
var _elevation_row: PropertyRow
var _color_row: PropertyRow
var _energy_row: PropertyRow
var _softness_row: PropertyRow
var _darkness_row: PropertyRow
var _regenerate_button: Button


func _build() -> void:
	_add_heading("Sun")

	_time_row = _add_row(
		"Time of day",
		0.0,
		24.0,
		0.5,
		14.0,
		{
			"tooltip": TIME_TOOLTIP,
			"hint_low": "Dawn",
			"hint_high": "Dusk",
			"formatter": SunPane.format_time,
		}
	)
	_time_row.ticks = [
		{"value": 6.0, "icon": "sunrise"},
		{"value": 12.0, "icon": "sun"},
		{"value": 18.0, "icon": "sunset"},
	]
	_time_row.value_changed.connect(_on_time_changed)

	_mode_field = _add_tile_field("Sun", MODES)
	_mode_tiles = _mode_field.tiles
	_mode_tiles.selection_changed.connect(_on_mode_selected)

	_shadow_field = _add_tile_field("Shadows", SHADOW_TILES)
	_shadow_field.tiles.selection_changed.connect(_on_shadow_tile_selected)

	var aim_row := HBoxContainer.new()
	aim_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(aim_row)
	var aim_label := Label.new()
	aim_label.text = "Aim on map"
	aim_label.theme_type_variation = &"Body"
	aim_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aim_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aim_row.add_child(aim_label)
	_aim_button = IconButton.new()
	_aim_button.icon_name = "target"
	_aim_button.toggle_mode = true
	_aim_button.tooltip_text = "Drag the sun on the ground compass"
	_aim_button.toggled.connect(_on_aim_toggled)
	aim_row.add_child(_aim_button)

	var foldout := _add_foldout()
	var body := foldout.body
	_azimuth_row = _add_row(
		"Direction", 0.0, 360.0, 1.0, 0.0, {"parent": body, "formatter": SunPane.format_bearing}
	)
	_azimuth_row.value_changed.connect(_on_azimuth_changed)
	_elevation_row = _add_row(
		"Height", -15.0, 90.0, 1.0, 45.0, {"parent": body, "formatter": SunPane.format_degrees}
	)
	_elevation_row.value_changed.connect(_on_elevation_changed)
	_color_row = _add_row(
		"Colour", 0.0, 1.0, 1.0, 0.0, {"show_slider": false, "show_color": true, "parent": body}
	)
	_color_row.color_changed.connect(_on_color_changed)
	_energy_row = _add_row(
		"Energy", 0.0, 4.0, 0.05, 1.0, {"parent": body, "hint_low": "Dim", "hint_high": "Blazing"}
	)
	_energy_row.value_changed.connect(_on_energy_changed)
	_softness_row = _add_row(
		"Softness",
		0.0,
		5.0,
		0.05,
		0.0,
		{"parent": body, "hint_low": "Crisp", "hint_high": "Diffuse"}
	)
	_softness_row.value_changed.connect(_on_softness_changed)
	_darkness_row = _add_row(
		"Darkness", 0.0, 1.0, 0.01, 1.0, {"parent": body, "hint_low": "Faint", "hint_high": "Deep"}
	)
	_darkness_row.value_changed.connect(_on_darkness_changed)
	_regenerate_button = Button.new()
	_regenerate_button.text = "Back to generated"
	_regenerate_button.icon = IconButton.load_icon("rotate-clockwise")
	_regenerate_button.theme_type_variation = &"Secondary"
	_regenerate_button.visible = false
	_regenerate_button.pressed.connect(_on_regenerate_pressed)
	body.add_child(_regenerate_button)


func load_state(state: LevelVisualState) -> void:
	_sun = state.sun.copy_settings()
	_sync_controls()


func write_state(state: LevelVisualState) -> void:
	state.sun = _sun.copy_settings()


## The gizmo does not survive a level change, so the panel clears this on
## initialize(); GameplayMenuController also clears it when the tool
## deactivates by any route.
func set_aim_pressed(pressed: bool) -> void:
	_aim_button.set_pressed_no_signal(pressed)
	_aim_button.active = pressed


## Called (via the panel) when the ground gizmo reports a drag.
func apply_gizmo_direction(azimuth_degrees: float, elevation_degrees: float) -> void:
	_sun.azimuth_degrees = azimuth_degrees
	_sun.elevation_degrees = elevation_degrees
	_azimuth_row.set_value_no_signal(azimuth_degrees)
	_elevation_row.set_value_no_signal(elevation_degrees)
	_promote_auto_to_on()
	_emit_changed()


static func format_time(hours: float) -> String:
	var whole := int(floor(hours))
	var minutes := int(round((hours - float(whole)) * 60.0))
	if minutes == 60:
		whole += 1
		minutes = 0
	return "%02d:%02d" % [whole % 24, minutes]


static func format_bearing(degrees: float) -> String:
	var index := int(round(fposmod(degrees, 360.0) / 45.0)) % COMPASS.size()
	return "%d° %s" % [int(round(degrees)), COMPASS[index]]


static func format_degrees(degrees: float) -> String:
	return "%d°" % int(round(degrees))


func _sync_controls() -> void:
	_mode_tiles.select(StringName(_sun.mode))
	_azimuth_row.set_value_no_signal(_sun.azimuth_degrees)
	_elevation_row.set_value_no_signal(_sun.elevation_degrees)
	_color_row.set_color_no_signal(_sun.color)
	_energy_row.set_value_no_signal(_sun.energy)
	_shadow_field.tiles.select(shadow_tile_for(_sun))
	_softness_row.set_value_no_signal(_sun.softness)
	_softness_row.editable = _sun.shadows_enabled
	_darkness_row.set_value_no_signal(_sun.shadow_darkness)
	_darkness_row.editable = _sun.shadows_enabled
	_time_row.set_value_no_signal(_sun.time_of_day)
	_update_generated_state()


## Show the regenerate affordance only when the sun no longer matches what
## the generator would produce for its recorded hour.
func _update_generated_state() -> void:
	var generated := DefaultSun.settings_for_time(_sun.time_of_day)
	var diverged := (
		not is_equal_approx(generated.azimuth_degrees, _sun.azimuth_degrees)
		or not is_equal_approx(generated.elevation_degrees, _sun.elevation_degrees)
		or not is_equal_approx(generated.energy, _sun.energy)
		or generated.color != _sun.color
	)
	_regenerate_button.visible = diverged


func _promote_auto_to_on() -> void:
	if _sun.mode != "auto":
		return
	_sun.mode = "on"
	_mode_tiles.select(&"on")


func _emit_changed() -> void:
	sun_changed.emit(_sun)
	changed.emit()
	_update_generated_state()


## The one control that must NOT promote auto to on: it chooses the mode.
func _on_mode_selected(id: StringName) -> void:
	_sun.mode = String(id)
	_emit_changed()


func _on_time_changed(value: float) -> void:
	var generated := DefaultSun.settings_for_time(value)
	generated.mode = _sun.mode
	generated.shadows_enabled = _sun.shadows_enabled
	generated.softness = _sun.softness
	generated.shadow_darkness = _sun.shadow_darkness
	_sun = generated
	_promote_auto_to_on()
	_sync_controls()
	_emit_changed()


func _on_azimuth_changed(value: float) -> void:
	_sun.azimuth_degrees = value
	_promote_auto_to_on()
	_emit_changed()


func _on_elevation_changed(value: float) -> void:
	_sun.elevation_degrees = value
	_promote_auto_to_on()
	_emit_changed()


func _on_color_changed(color: Color) -> void:
	_sun.color = color
	_promote_auto_to_on()
	_emit_changed()


func _on_energy_changed(value: float) -> void:
	_sun.energy = value
	_promote_auto_to_on()
	_emit_changed()


static func shadow_tile_for(settings: SunSettings) -> StringName:
	if not settings.shadows_enabled:
		return &"off"
	return &"hard" if settings.softness <= SHADOW_HARD_MAX_SOFTNESS else &"soft"


func _on_shadows_toggled(pressed: bool) -> void:
	_sun.shadows_enabled = pressed
	_softness_row.editable = pressed
	_darkness_row.editable = pressed
	_shadow_field.tiles.select(shadow_tile_for(_sun))
	_promote_auto_to_on()
	_emit_changed()


## Off / Hard / Soft set the enable flag and a softness bucket in one click;
## the exact softness stays editable under Advanced.
func _on_shadow_tile_selected(id: StringName) -> void:
	match id:
		&"off":
			_sun.shadows_enabled = false
		&"hard":
			_sun.shadows_enabled = true
			_sun.softness = 0.0
		&"soft":
			_sun.shadows_enabled = true
			_sun.softness = SHADOW_SOFT_SOFTNESS
	_softness_row.set_value_no_signal(_sun.softness)
	_softness_row.editable = _sun.shadows_enabled
	_darkness_row.editable = _sun.shadows_enabled
	_promote_auto_to_on()
	_emit_changed()


func _on_softness_changed(value: float) -> void:
	_sun.softness = value
	_shadow_field.tiles.select(shadow_tile_for(_sun))
	_promote_auto_to_on()
	_emit_changed()


func _on_darkness_changed(value: float) -> void:
	_sun.shadow_darkness = value
	_promote_auto_to_on()
	_emit_changed()


func _on_regenerate_pressed() -> void:
	_on_time_changed(_sun.time_of_day)


func _on_aim_toggled(pressed: bool) -> void:
	_aim_button.active = pressed
	aim_toggled.emit(pressed)
