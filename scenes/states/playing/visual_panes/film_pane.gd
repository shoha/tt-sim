class_name FilmPane
extends LevelEditPane

## Lo-fi post-processing: pixelate, colour levels, dither, colour fade,
## vignette, grain. Edits go straight into a working LofiSettings and out as
## lofi_changed(to_dict()).

signal lofi_changed(overrides: Dictionary)

## [label, LofiSettings field, min, max, step, allow_greater]
const ROWS := [
	["Pixelate", "pixelation", 0.0, 0.01, 0.0001, true],
	["Colors", "color_levels", 2.0, 256.0, 1.0, false],
	["Dither", "dither_strength", 0.0, 1.0, 0.01, false],
	["Color fade", "saturation", 0.0, 1.5, 0.01, false],
	["Vignette", "vignette_strength", 0.0, 1.0, 0.01, false],
	["Grain", "grain_intensity", 0.0, 0.1, 0.001, true],
]

var _lofi: LofiSettings = LofiSettings.default()
var _rows: Dictionary = {}


func _build() -> void:
	_add_heading("Film")
	for spec in ROWS:
		var key: String = spec[1]
		var row := _add_row(
			spec[0], spec[2], spec[3], spec[4], _lofi.get(key), {"allow_greater": spec[5]}
		)
		row.value_changed.connect(_on_row_changed.bind(key))
		_rows[key] = row


func load_state(state: LevelVisualState) -> void:
	_lofi = state.lofi.copy_settings()
	for key in _rows:
		_rows[key].set_value_no_signal(_lofi.get(key))


func write_state(state: LevelVisualState) -> void:
	state.lofi = _lofi.copy_settings()


func _on_row_changed(value: float, key: String) -> void:
	_lofi.set(key, value)
	lofi_changed.emit(_lofi.to_dict())
	changed.emit()
