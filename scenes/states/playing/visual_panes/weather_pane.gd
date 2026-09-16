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

var _weather: WeatherSettings = WeatherSettings.default()
var _tiles: TileRow
var _rows: Dictionary = {}
var _last_intensity: Dictionary = {}


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
		var row := _add_row(spec[1] + " intensity", 0.0, 1.0, 0.05, 0.0)
		row.visible = false
		row.value_changed.connect(_on_intensity_changed.bind(kind))
		_rows[kind] = row


func load_state(state: LevelVisualState) -> void:
	_weather = state.weather.copy_settings()
	for spec in KINDS:
		var kind: String = spec[0]
		var value: float = _weather.get(_field(kind))
		_rows[kind].set_value_no_signal(value)
		_rows[kind].visible = value > 0.0
		_tiles.set_tile_on(StringName(kind), value > 0.0)


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
	weather_changed.emit(_weather.to_dict())
	changed.emit()
