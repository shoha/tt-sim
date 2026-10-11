class_name SunPane
extends LevelEditPane

## Sun direction, colour, energy and shadows. Time of day is a GENERATOR, not
## the sun's interface: it regenerates direction, colour and energy from the
## keyframes, discarding hand-aiming; mode and shadow fields are user choices
## carried across. Editing any sun property while the mode is "auto" promotes
## it to "on", because an auto sun may be hidden by a map that brings its own
## lights and the edit would otherwise be a silent no-op.
##
## Layout: Time of day on its own line with the hour (17:45, the 24 h form the game uses) at
## its end, the slider the pane's full width under it with Dawn, Noon and Dusk at their
## hours; the Sunlight mode tiles with a whole sentence under them saying what the picked mode
## does, placed as the Sky pane places its captions (2026-10-10 round 2: a note at the end of
## the caption's line sat just under Dawn, Noon and Dusk and read as one paragraph with them).

signal sun_changed(settings: SunSettings)
signal aim_toggled(active: bool)

## [mode value, label, icon]. Auto is an A in a ring: brightness-auto's rayed octagon read as
## the Settings cog at 720p.
const MODES := [["auto", "Auto", "circle-letter-a"], ["on", "On", "sun"], ["off", "Off", "sun-off"]]
## The mode field's caption: whether the game's sunlight shines (LevelEnvironmentManager
## _configure_sun_light). Daylight Auto / On / Off did not say what it switched (W1).
const MODE_CAPTION := "Sunlight"
## What each mode does (LevelEnvironmentManager._configure_sun_light), under the tiles for the
## picked one and as its tile's tooltip. Each fits one line of the drawer: "unless the map has
## its own lights" wrapped one word onto a second line, and the rows under it jumped a line as
## the mode changed.
const MODE_NOTES := {
	"auto": "Auto: the sun shines if the map has no lights",
	"on": "On: the sun shines with the map's own lights",
	"off": "Off: no sun, only the map's own lights",
}
## The time of day's markers: words at their hours, no icons.
const TIME_TICKS: Array[Dictionary] = [
	{"value": 6.0, "label": "Dawn"},
	{"value": 12.0, "label": "Noon"},
	{"value": 18.0, "label": "Dusk"},
]
## [tile id, label, icon]
const SHADOW_TILES := [
	["off", "Off", "circle-off"], ["hard", "Hard", "contrast"], ["soft", "Soft", "cloud"]
]
## A Shadows tile's tooltip while Sunlight is Off (shadows_live).
const SHADOWS_NO_SUN := "Shadows are the sun's: turn Sunlight on to cast them"
## The caption under the Shadows tiles while Sunlight is Off.
const SHADOWS_NEED_SUN := "Shadows need sunlight"
const AIM_TIP := "Drag the sun on the ground compass"
## Aim on map's tooltip while Sunlight is Off.
const AIM_NO_SUN := "There is no sun to aim: turn Sunlight on first"
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
var _mode_caption: Label
var _shadow_field: TileField
var _shadow_note: Label
var _shadow_note_gap: Control
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

	# The label on its own line with the hour at its end, the slider the pane's width under
	# it, and three words at their hours under that (2026-10-10: the label, a 200 px slider,
	# Dawn and Dusk at its ends and three icons between them crowded one line).
	_time_row = _add_row(
		"Time of day",
		0.0,
		24.0,
		0.5,
		14.0,
		{"tooltip": TIME_TOOLTIP, "formatter": SunPane.format_time, "show_readout": true}
	)
	_time_row.ticks = TIME_TICKS
	_time_row.value_changed.connect(_on_time_changed)

	_mode_field = _add_tile_field(MODE_CAPTION, MODES)
	_mode_field.tiles.columns = 3
	_mode_tiles = _mode_field.tiles
	for mode: Array in MODES:
		_mode_tiles.set_tile_tooltip(StringName(mode[0]), MODE_NOTES[mode[0]])
	_mode_tiles.selection_changed.connect(_on_mode_selected)
	_mode_caption = _add_note("")
	_show_mode_note()

	_shadow_field = _add_tile_field("Shadows", SHADOW_TILES)
	_shadow_field.tiles.columns = 3
	_shadow_field.tiles.selection_changed.connect(_on_shadow_tile_selected)
	# Said under the tiles while Sunlight is Off, not only in their tooltip.
	_shadow_note = _add_note(SHADOWS_NEED_SUN)
	_shadow_note_gap = get_child(get_child_count() - 1)

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
	_aim_button.tooltip_text = AIM_TIP
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
	_refresh_shadow_state()


func load_state(state: LevelVisualState) -> void:
	_sun = state.sun.copy_settings()
	_sync_controls()
	_update_generated_state()


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
	var wrapped := int(round(fposmod(degrees, 360.0))) % 360
	return "%d° %s" % [wrapped, COMPASS[index]]


static func format_degrees(degrees: float) -> String:
	return "%d°" % int(round(degrees))


func _sync_controls() -> void:
	_mode_tiles.select(StringName(_sun.mode))
	_show_mode_note()
	_azimuth_row.set_value_no_signal(_sun.azimuth_degrees)
	_elevation_row.set_value_no_signal(_sun.elevation_degrees)
	_color_row.set_color_no_signal(_sun.color)
	_energy_row.set_value_no_signal(_sun.energy)
	_shadow_field.tiles.select(shadow_tile_for(_sun))
	_softness_row.set_value_no_signal(_sun.softness)
	_darkness_row.set_value_no_signal(_sun.shadow_darkness)
	_refresh_shadow_state()
	_time_row.set_value_no_signal(_sun.time_of_day)


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
	_show_mode_note()


## Say what the picked Sunlight mode does, in the caption under its tiles.
func _show_mode_note() -> void:
	_mode_caption.text = String(MODE_NOTES.get(_sun.mode, ""))
	_refresh_shadow_state()


## Whether the sun's shadow controls act: Shadows are the sun's alone (DefaultSun gives them to
## its light, never to the map's lamps), so with Sunlight Off there is nothing to cast them and
## the tiles are drawn disabled, the picked one still marked (muted), with SHADOWS_NEED_SUN
## under them and their tooltip saying why; softness and darkness need shadows on, and Aim on
## map has no sun to aim.
func shadows_live() -> bool:
	return _sun.mode != "off"


func _refresh_shadow_state() -> void:
	if _shadow_field == null or _softness_row == null or _aim_button == null:
		return
	var live := shadows_live()
	for spec: Array in SHADOW_TILES:
		var id := StringName(spec[0])
		_shadow_field.tiles.set_tile_disabled(id, not live)
		_shadow_field.tiles.set_tile_tooltip(id, "" if live else SHADOWS_NO_SUN)
	_shadow_note.visible = not live
	_shadow_note_gap.visible = not live
	_softness_row.editable = live and _sun.shadows_enabled
	_darkness_row.editable = live and _sun.shadows_enabled
	if not live and _aim_button.button_pressed:
		set_aim_pressed(false)
		aim_toggled.emit(false)
	_aim_button.disabled = not live
	_aim_button.tooltip_text = AIM_TIP if live else AIM_NO_SUN


func _emit_changed() -> void:
	sun_changed.emit(_sun)
	changed.emit()
	_update_generated_state()


## The one control that must NOT promote auto to on: it chooses the mode.
func _on_mode_selected(id: StringName) -> void:
	_sun.mode = String(id)
	_show_mode_note()
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
	_refresh_shadow_state()
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
