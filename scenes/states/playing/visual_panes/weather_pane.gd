class_name WeatherPane
extends LevelEditPane

## Four independent weather kinds as toggle tiles. A tile that is on reveals
## its intensity row; turning it off zeroes the intensity and remembers the
## previous value for the session so the next turn-on restores it.

signal weather_changed(overrides: Dictionary)

## [kind, label, icon]. WeatherSettings field is "<kind>_intensity".
const KINDS := [
	["rain", "Rain", "cloud-rain"],
	["snow", "Snow", "snowflake"],
	["fog", "Fog", "mist"],
	["wind", "Wind", "wind"],
]
const DEFAULT_INTENSITY := 0.5
const REROLL_TIP := (
	"Draw a different pattern of gusts: the same wind strength and direction, with the fronts "
	+ "crossing the map in a new rhythm. Everyone at the table sees the same pattern."
)

var _weather: WeatherSettings = WeatherSettings.default()
var _tiles: TileRow
var _rows: Dictionary = {}
var _last_intensity: Dictionary = {}
var _wind_presets: TileRow
var _wind_compass: TileRow
var _wind_readout: Label
var _wind_reroll: Button
var _rng := RandomNumberGenerator.new()


func _build() -> void:
	_add_heading("Weather")
	_tiles = TileRow.new()
	_tiles.multi_select = true
	for spec in KINDS:
		_tiles.add_tile(StringName(spec[0]), spec[1], spec[2])
	_tiles.tile_toggled.connect(_on_tile_toggled)
	add_child(_tiles)
	for spec in KINDS:
		var kind: String = spec[0]
		var row := _add_row(
			spec[1] + " intensity", 0.0, 1.0, 0.05, 0.0, {"hint_low": "Light", "hint_high": "Heavy"}
		)
		row.visible = false
		row.value_changed.connect(_on_intensity_changed.bind(kind))
		_rows[kind] = row
	_rng.randomize()
	_build_wind_controls()


## The wind's own controls under the four intensity rows: strength chips, a compass of eight
## directions plus Auto, a plain-words readout and the gust pattern re-roll. They write the same
## WeatherSettings the Wind tile does (wind_intensity, wind_direction_deg, wind_seed), so a level
## saves them and every peer receives them through weather_changed.
func _build_wind_controls() -> void:
	_add_caption("Wind strength")
	_wind_presets = TileRow.new()
	_wind_presets.columns = WindPresets.PRESET_ORDER.size()
	_wind_presets.tile_min_size = Vector2(56, 52)
	for preset_name in WindPresets.PRESET_ORDER:
		_wind_presets.add_tile(
			StringName(preset_name),
			preset_name.capitalize(),
			"wind",
			WindPresets.preset_tooltip(preset_name)
		)
	_wind_presets.selection_changed.connect(_on_wind_preset)
	add_child(_wind_presets)
	_enable_focus(_wind_presets)
	_add_caption("Wind direction")
	_wind_compass = TileRow.new()
	_wind_compass.columns = 3
	_wind_compass.tile_min_size = Vector2(56, 36)
	for id in WindCompass.GRID:
		var label := "Auto" if id == WindCompass.AUTO_ID else String(id).to_upper()
		_wind_compass.add_tile(id, label, "", WindCompass.tooltip_for(id))
	_wind_compass.selection_changed.connect(_on_wind_direction)
	add_child(_wind_compass)
	_enable_focus(_wind_compass)
	_wind_readout = _add_caption("")
	_wind_reroll = Button.new()
	_wind_reroll.name = "RerollGusts"
	_wind_reroll.text = "New gust pattern"
	_wind_reroll.tooltip_text = REROLL_TIP
	_wind_reroll.pressed.connect(_on_wind_reroll)
	add_child(_wind_reroll)
	_sync_wind_controls()


## Tiles skip keyboard focus by default (they are pointer pickers); the wind pickers take it, so a
## keyboard player can reach them.
static func _enable_focus(row: TileRow) -> void:
	for child in row.get_children():
		if child is Button:
			(child as Button).focus_mode = Control.FOCUS_ALL


func load_state(state: LevelVisualState) -> void:
	_weather = state.weather.copy_settings()
	for spec in KINDS:
		var kind: String = spec[0]
		var value: float = _weather.get(_field(kind))
		_rows[kind].set_value_no_signal(value)
		_rows[kind].visible = value > 0.0
		_tiles.set_tile_on(StringName(kind), value > 0.0)
	_sync_wind_controls()


func write_state(state: LevelVisualState) -> void:
	state.weather = _weather.copy_settings()


func _field(kind: String) -> String:
	return kind + "_intensity"


func _on_tile_toggled(id: StringName, on: bool) -> void:
	var kind := String(id)
	var value := 0.0
	if on:
		value = _last_intensity.get(kind, DEFAULT_INTENSITY)
	else:
		var current: float = _weather.get(_field(kind))
		if current > 0.0:
			_last_intensity[kind] = current
	_rows[kind].visible = on
	_rows[kind].set_value_no_signal(value)
	_set_intensity(kind, value)


func _on_intensity_changed(value: float, kind: String) -> void:
	if value > 0.0:
		_last_intensity[kind] = value
	_tiles.set_tile_on(StringName(kind), value > 0.0)
	_set_intensity(kind, value)


func _set_intensity(kind: String, value: float) -> void:
	_weather.set(_field(kind), value)
	if kind == "wind":
		_sync_wind_controls()
	_emit_weather()


func _emit_weather() -> void:
	weather_changed.emit(_weather.to_dict())
	changed.emit()


## A strength chip: the preset's stop on the one wind dial, shown on the Wind tile and its row too.
func _on_wind_preset(id: StringName) -> void:
	var value := WindPresets.strength_of(String(id))
	if value < 0.0:
		return
	_rows["wind"].set_value_no_signal(value)
	_rows["wind"].visible = value > 0.0
	if value > 0.0:
		_last_intensity["wind"] = value
	_tiles.set_tile_on(&"wind", value > 0.0)
	_set_intensity("wind", value)


## A compass pick: the direction the wind blows toward (Auto writes the default sentinel).
func _on_wind_direction(id: StringName) -> void:
	_weather.wind_direction_deg = WindCompass.direction_for(id)
	_sync_wind_controls()
	_emit_weather()


## The re-roll: a new seed, so the gust fronts and the slow veer cross the level in a new pattern.
func _on_wind_reroll() -> void:
	_weather.wind_seed = WindPresets.reroll_seed(_weather.wind_seed, _rng.randi())
	_emit_weather()


## Shows the stored strength, direction and words on the chips and the compass, with no signals.
func _sync_wind_controls() -> void:
	var preset := WindPresets.name_for(_weather.wind_intensity)
	if preset.is_empty():
		_wind_presets.clear_selection()
	else:
		_wind_presets.select(StringName(preset))
	var id := WindCompass.id_for(_weather.wind_direction_deg)
	if id.is_empty():
		_wind_compass.clear_selection()
	else:
		_wind_compass.select(id)
	_wind_readout.text = WindCompass.readout(_weather.wind_direction_deg)
