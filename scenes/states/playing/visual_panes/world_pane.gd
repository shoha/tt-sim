class_name WorldPane
extends LevelEditPane

## Map scale and grid calibration, water style, and foliage sway. Scale and
## grid are set once per map but need the live 3D view to line the grid up,
## so they stay in this drawer rather than the Level Editor.

signal scale_config_changed(
	grid_cell_size: float, display_unit: String, display_unit_per_cell: float
)
signal water_style_changed(style: String)
signal foliage_changed(overrides: Dictionary)

const CUSTOM_KEY := "custom"
const SCALE_TILE_LABELS := {
	"dnd_5ft": "5 ft",
	"dnd_metric": "1.5 m",
	"metric_1m": "1 m",
	"generic_squares": "Generic",
	"custom": "Custom",
}
const WATER_ICONS := {"stylized": "brush", "realistic": "droplet"}
## [label, FoliageSettings field, min, max, step]
const FOLIAGE_ROWS := [
	["Tree speed", "tree_sway_speed", 0.0, 5.0, 0.05],
	["Tree amount", "tree_sway_amplitude", 0.0, 1.0, 0.01],
	["Grass speed", "grass_sway_speed", 0.0, 5.0, 0.05],
	["Grass amount", "grass_sway_amplitude", 0.0, 1.0, 0.01],
]

var grid_cell_size: float = LevelData.DEFAULT_GRID_CELL_SIZE
var display_unit: String = LevelData.DEFAULT_DISPLAY_UNIT
var display_unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL
var water_style: String = WaterPresets.DEFAULT_PRESET

var _foliage: FoliageSettings = FoliageSettings.default()
var _scale_tiles: TileRow
var _cell_size_row: PropertyRow
var _water_tiles: TileRow
var _foliage_rows: Dictionary = {}


func _build() -> void:
	_add_heading("World")

	_add_caption("Scale")
	_scale_tiles = TileRow.new()
	for option in ScaleUtils.get_preset_options():
		var key: String = option.key
		_scale_tiles.add_tile(
			StringName(key), SCALE_TILE_LABELS.get(key, option.label), "", option.label
		)
	_scale_tiles.selection_changed.connect(_on_scale_preset_selected)
	add_child(_scale_tiles)
	_cell_size_row = _add_row("Cell size (m)", 0.1, 10.0, 0.001, grid_cell_size)
	_cell_size_row.value_changed.connect(_on_cell_size_changed)

	_add_caption("Water")
	_water_tiles = TileRow.new()
	for style in WaterPresets.get_preset_names():
		_water_tiles.add_tile(StringName(style), style.capitalize(), WATER_ICONS.get(style, ""))
	_water_tiles.selection_changed.connect(_on_water_selected)
	add_child(_water_tiles)

	_add_caption("Foliage sway")
	for spec in FOLIAGE_ROWS:
		var key: String = spec[1]
		var row := _add_row(spec[0], spec[2], spec[3], spec[4], _foliage.get(key))
		row.value_changed.connect(_on_foliage_changed.bind(key))
		_foliage_rows[key] = row


func load_state(state: LevelVisualState) -> void:
	grid_cell_size = state.grid_cell_size
	display_unit = state.display_unit
	display_unit_per_cell = state.display_unit_per_cell
	_cell_size_row.set_value_no_signal(grid_cell_size)
	_sync_scale_tiles()

	# Corrupt or unrecognised save data falls back to the default style, and
	# the fallback is adopted as the value so Save cannot re-persist the bad one.
	water_style = state.water_style
	if not _water_tiles.has_tile(StringName(water_style)):
		water_style = WaterPresets.DEFAULT_PRESET
	_water_tiles.select(StringName(water_style))

	_foliage = state.foliage.copy_settings()
	for key in _foliage_rows:
		_foliage_rows[key].set_value_no_signal(_foliage.get(key))


func write_state(state: LevelVisualState) -> void:
	state.grid_cell_size = grid_cell_size
	state.display_unit = display_unit
	state.display_unit_per_cell = display_unit_per_cell
	state.water_style = water_style
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


func _on_water_selected(id: StringName) -> void:
	water_style = String(id)
	water_style_changed.emit(water_style)
	changed.emit()


func _on_foliage_changed(value: float, key: String) -> void:
	_foliage.set(key, value)
	foliage_changed.emit(_foliage.to_dict())
	changed.emit()
