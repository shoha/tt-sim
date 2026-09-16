class_name FilmPane
extends LevelEditPane

## Lo-fi post-processing: pixelate, colour levels, dither, colour fade,
## vignette, grain. Edits go straight into a working LofiSettings and out as
## lofi_changed(to_dict()).

signal lofi_changed(overrides: Dictionary)

const CUSTOM_KEY := "custom"
## Style presets over STYLE_FIELDS, in that order.
const STYLE_FIELDS := [
	"pixelation",
	"saturation",
	"color_levels",
	"dither_strength",
	"vignette_strength",
	"grain_intensity"
]
const STYLES := {
	"off": [0.0, 1.0, 256.0, 0.0, 0.0, 0.0],
	"subtle": [0.0, 1.0, 256.0, 0.0, 0.15, 0.012],
	"retro": [0.003, 0.85, 32.0, 0.5, 0.3, 0.025],
	"heavy": [0.006, 0.7, 16.0, 0.8, 0.5, 0.05],
}
## [tile id, label, icon]
const STYLE_TILES := [
	["off", "Off", "circle-off"],
	["subtle", "Subtle", "sparkles"],
	["retro", "Retro", "grid-dots"],
	["heavy", "Heavy", "grain"],
	["custom", "Custom", "adjustments"],
]
## [label, LofiSettings field, min, max, step, allow_greater, primary, hint_low, hint_high]
const ROWS := [
	["Pixelate", "pixelation", 0.0, 0.01, 0.0001, true, true, "Sharp", "Blocky"],
	["Vignette", "vignette_strength", 0.0, 1.0, 0.01, false, true, "None", "Heavy"],
	["Grain", "grain_intensity", 0.0, 0.1, 0.001, true, true, "Clean", "Grainy"],
	["Colours", "color_levels", 2.0, 256.0, 1.0, false, false, "Few", "Many"],
	["Dither", "dither_strength", 0.0, 1.0, 0.01, false, false, "Smooth", "Dotted"],
	["Colour fade", "saturation", 0.0, 1.5, 0.01, false, false, "Faded", "Full"],
]

var _lofi: LofiSettings = LofiSettings.default()
var _rows: Dictionary = {}
var _style_field: TileField


func _build() -> void:
	_add_heading("Film")
	_style_field = _add_tile_field("Style", STYLE_TILES)
	_style_field.tiles.selection_changed.connect(_on_style_selected)
	for spec in ROWS:
		if spec[6]:
			_add_lofi_row(spec, self)
	var foldout := _add_foldout()
	for spec in ROWS:
		if not spec[6]:
			_add_lofi_row(spec, foldout.body)
	_sync_style_tiles()


func _add_lofi_row(spec: Array, parent: Node) -> void:
	var key: String = spec[1]
	var row := _add_row(
		spec[0],
		spec[2],
		spec[3],
		spec[4],
		_lofi.get(key),
		{"allow_greater": spec[5], "parent": parent, "hint_low": spec[7], "hint_high": spec[8]}
	)
	row.value_changed.connect(_on_row_changed.bind(key))
	_rows[key] = row


func load_state(state: LevelVisualState) -> void:
	_lofi = state.lofi.copy_settings()
	for key in _rows:
		_rows[key].set_value_no_signal(_lofi.get(key))
	_sync_style_tiles()


func write_state(state: LevelVisualState) -> void:
	state.lofi = _lofi.copy_settings()


func _matching_style() -> String:
	for id in STYLES:
		var values: Array = STYLES[id]
		var matches := true
		for i in range(STYLE_FIELDS.size()):
			if not is_equal_approx(float(_lofi.get(STYLE_FIELDS[i])), float(values[i])):
				matches = false
				break
		if matches:
			return id
	return CUSTOM_KEY


func _sync_style_tiles() -> void:
	var key := _matching_style()
	_style_field.tiles.set_tile_visible(StringName(CUSTOM_KEY), key == CUSTOM_KEY)
	_style_field.tiles.select(StringName(key))


## A style sets all six values at once and broadcasts once; Custom is a
## read-only marker, never an edit.
func _on_style_selected(id: StringName) -> void:
	var key := String(id)
	if key == CUSTOM_KEY or not STYLES.has(key):
		return
	var values: Array = STYLES[key]
	for i in range(STYLE_FIELDS.size()):
		var field: String = STYLE_FIELDS[i]
		_lofi.set(field, float(values[i]))
		_rows[field].set_value_no_signal(float(values[i]))
	_style_field.tiles.set_tile_visible(StringName(CUSTOM_KEY), false)
	lofi_changed.emit(_lofi.to_dict())
	changed.emit()


func _on_row_changed(value: float, key: String) -> void:
	_lofi.set(key, value)
	_sync_style_tiles()
	lofi_changed.emit(_lofi.to_dict())
	changed.emit()
