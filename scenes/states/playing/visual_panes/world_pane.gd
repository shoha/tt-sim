class_name WorldPane
extends LevelEditPane

## Map scale and grid calibration, and foliage sway. Scale and
## grid are set once per map but need the live 3D view to line the grid up,
## so they stay in this drawer rather than the Level Editor.

signal scale_config_changed(
	grid_cell_size: float, display_unit: String, display_unit_per_cell: float
)
signal foliage_changed(overrides: Dictionary)

const CUSTOM_KEY := "custom"
const SCALE_TILE_LABELS := {
	"dnd_5ft": "5 ft",
	"dnd_metric": "1.5 m",
	"metric_1m": "1 m",
	"generic_squares": "Generic",
	"custom": "Custom",
}
const METRES_PER_FOOT := 0.3048
## Wind presets over WIND_FIELDS, in that order.
const WIND_FIELDS := [
	"tree_sway_speed", "tree_sway_amplitude", "grass_sway_speed", "grass_sway_amplitude"
]
const WIND := {
	"still": [0.6, 0.0, 1.6, 0.0],
	"breeze": [0.6, 0.06, 1.6, 0.03],
	"gusty": [1.2, 0.15, 2.5, 0.08],
}
## [tile id, label, icon]
const WIND_TILES := [
	["still", "Still", "leaf"],
	["breeze", "Breeze", "wind"],
	["gusty", "Gusty", "tornado"],
	["custom", "Custom", "adjustments"],
]
## [label, FoliageSettings field, min, max, step, hint_low, hint_high]
const FOLIAGE_ROWS := [
	["Tree speed", "tree_sway_speed", 0.0, 5.0, 0.05, "Slow", "Fast"],
	["Tree amount", "tree_sway_amplitude", 0.0, 1.0, 0.01, "Still", "Wild"],
	["Grass speed", "grass_sway_speed", 0.0, 5.0, 0.05, "Slow", "Fast"],
	["Grass amount", "grass_sway_amplitude", 0.0, 1.0, 0.01, "Still", "Wild"],
]

var grid_cell_size: float = LevelData.DEFAULT_GRID_CELL_SIZE
var display_unit: String = LevelData.DEFAULT_DISPLAY_UNIT
var display_unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL

var _foliage: FoliageSettings = FoliageSettings.default()
var _scale_tiles: TileRow
var _cell_size_row: PropertyRow
var _foliage_rows: Dictionary = {}
var _scale_field: TileField
var _wind_field: TileField


func _build() -> void:
	_add_heading("World")

	_scale_field = _add_tile_field("Scale", [])
	for option in ScaleUtils.get_preset_options():
		var key: String = option.key
		_scale_field.tiles.add_tile(
			StringName(key), SCALE_TILE_LABELS.get(key, option.label), "", option.label
		)
	_scale_tiles = _scale_field.tiles
	_scale_tiles.selection_changed.connect(_on_scale_preset_selected)
	_cell_size_row = _add_row(
		"Cell size",
		0.1,
		10.0,
		0.001,
		grid_cell_size,
		{"hint_low": "Small", "hint_high": "Large", "formatter": WorldPane.format_cell_size}
	)
	_cell_size_row.value_changed.connect(_on_cell_size_changed)

	_wind_field = _add_tile_field("Wind", WIND_TILES)
	_wind_field.tiles.selection_changed.connect(_on_wind_selected)

	var foldout := _add_foldout()
	for spec in FOLIAGE_ROWS:
		var key: String = spec[1]
		var row := _add_row(
			spec[0],
			spec[2],
			spec[3],
			spec[4],
			_foliage.get(key),
			{"parent": foldout.body, "hint_low": spec[5], "hint_high": spec[6]}
		)
		row.value_changed.connect(_on_foliage_changed.bind(key))
		_foliage_rows[key] = row
	_sync_wind_tiles()


func load_state(state: LevelVisualState) -> void:
	grid_cell_size = state.grid_cell_size
	display_unit = state.display_unit
	display_unit_per_cell = state.display_unit_per_cell
	_cell_size_row.set_value_no_signal(grid_cell_size)
	_sync_scale_tiles()

	_foliage = state.foliage.copy_settings()
	for key in _foliage_rows:
		_foliage_rows[key].set_value_no_signal(_foliage.get(key))
	_sync_wind_tiles()


func write_state(state: LevelVisualState) -> void:
	state.grid_cell_size = grid_cell_size
	state.display_unit = display_unit
	state.display_unit_per_cell = display_unit_per_cell
	state.foliage = _foliage.copy_settings()


func _matching_scale_preset() -> String:
	for key in ScaleUtils.PRESETS:
		var p: Dictionary = ScaleUtils.PRESETS[key]
		if (
			is_equal_approx(p.grid_cell_size, grid_cell_size)
			and p.display_unit == display_unit
			and is_equal_approx(p.display_unit_per_cell, display_unit_per_cell)
		):
			return key
	return CUSTOM_KEY


func _sync_scale_tiles() -> void:
	var key := _matching_scale_preset()
	_scale_tiles.set_tile_visible(StringName(CUSTOM_KEY), key == CUSTOM_KEY)
	_scale_tiles.select(StringName(key))


func _emit_scale() -> void:
	scale_config_changed.emit(grid_cell_size, display_unit, display_unit_per_cell)
	changed.emit()


func _on_scale_preset_selected(id: StringName) -> void:
	var key := String(id)
	if key == CUSTOM_KEY or not ScaleUtils.PRESETS.has(key):
		# Selecting "Custom" changes nothing on its own, so it is not an edit.
		return
	var p: Dictionary = ScaleUtils.PRESETS[key]
	grid_cell_size = p.grid_cell_size
	display_unit = p.display_unit
	display_unit_per_cell = p.display_unit_per_cell
	_cell_size_row.set_value_no_signal(grid_cell_size)
	_scale_tiles.set_tile_visible(StringName(CUSTOM_KEY), false)
	_emit_scale()


func _on_cell_size_changed(value: float) -> void:
	grid_cell_size = value
	_sync_scale_tiles()
	_emit_scale()


func _on_foliage_changed(value: float, key: String) -> void:
	_foliage.set(key, value)
	_sync_wind_tiles()
	foliage_changed.emit(_foliage.to_dict())
	changed.emit()


func _matching_wind() -> String:
	for id in WIND:
		var values: Array = WIND[id]
		var matches := true
		for i in range(WIND_FIELDS.size()):
			if not is_equal_approx(float(_foliage.get(WIND_FIELDS[i])), float(values[i])):
				matches = false
				break
		if matches:
			return id
	return CUSTOM_KEY


func _sync_wind_tiles() -> void:
	var key := _matching_wind()
	_wind_field.tiles.set_tile_visible(StringName(CUSTOM_KEY), key == CUSTOM_KEY)
	_wind_field.tiles.select(StringName(key))


func _on_wind_selected(id: StringName) -> void:
	var key := String(id)
	if key == CUSTOM_KEY or not WIND.has(key):
		return
	var values: Array = WIND[key]
	for i in range(WIND_FIELDS.size()):
		var field: String = WIND_FIELDS[i]
		_foliage.set(field, float(values[i]))
		_foliage_rows[field].set_value_no_signal(float(values[i]))
	_wind_field.tiles.set_tile_visible(StringName(CUSTOM_KEY), false)
	foliage_changed.emit(_foliage.to_dict())
	changed.emit()


static func format_cell_size(metres: float) -> String:
	var feet := metres / METRES_PER_FOOT
	var feet_text: String
	if abs(feet - round(feet)) <= 0.05:
		feet_text = "%d" % int(round(feet))
	else:
		feet_text = "%.1f" % feet
	return "%.2f m (%s ft)" % [metres, feet_text]
