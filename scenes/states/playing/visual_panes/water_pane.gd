class_name WaterPane
extends LevelEditPane

## Water tuning for the level's "-water" meshes. Three independent tile rows
## (Look, Color, Motion), each derived from the working WaterSettings by value
## matching so a Custom tile appears only when nothing matches -- the same
## contract as WorldPane's Wind and Scale rows -- plus one primary Clarity
## slider and an Advanced foldout with every remaining uniform, captioned by
## the tile row it un-matches. Presets live in WaterPresets; the pane never
## stores a tile id.

signal water_changed(overrides: Dictionary)

## Clarity is murkiness inverted so "more" sits on the right: slider value v
## maps to depth_absorption = CLARITY_MAX - v.
const CLARITY_MAX := 6.0
## [tile id, label, icon]
const LOOK_TILES := [
	["stylized", "Stylized", "brush"],
	["realistic", "Realistic", "droplet"],
	["custom", "Custom", "adjustments"],
]
const MOTION_TILES := [
	["still", "Still", "leaf"],
	["gentle", "Gentle", "cloud"],
	["lively", "Lively", "wind"],
	["rough", "Rough", "tornado"],
	["custom", "Custom", "adjustments"],
]
## [label, WaterSettings key]
const COLOR_ROWS := [
	["Deep color", "water_color"],
	["Shallows color", "shore_color"],
	["Foam color", "foam_color"],
]
## [label, WaterSettings key, min, max, step, hint_low, hint_high]
const MOTION_ROWS := [
	["Waves", "ripple_strength", 0.0, 1.5, 0.01, "Calm", "Choppy"],
	["Ripple detail", "ripple_scale", 0.5, 5.0, 0.05, "Broad", "Fine"],
	["Speed", "wave_speed", 0.0, 3.0, 0.05, "Still", "Rushing"],
	["Foam", "foam_strength", 0.0, 2.0, 0.05, "None", "Frothy"],
]
const LOOK_ROWS := [
	["Glint softness", "roughness_value", 0.02, 0.5, 0.01, "Sharp", "Soft"],
	["Shine", "specular_value", 0.0, 1.0, 0.01, "Matte", "Glossy"],
	["Sky reflection", "sky_blend_strength", 0.0, 1.0, 0.01, "None", "Mirror"],
	["Caustics", "caustic_strength", 0.0, 2.0, 0.05, "Off", "Bright"],
	["Caustic detail", "caustic_scale", 0.5, 4.0, 0.05, "Broad", "Fine"],
	["Shallows width", "shore_depth_range", 0.1, 2.0, 0.05, "Thin", "Wide"],
	["Distortion", "refraction_strength", 0.0, 0.1, 0.005, "None", "Wobbly"],
	["Edge foam cutoff", "foam_edge_sensitivity", 0.5, 5.0, 0.1, "Every bank", "Rocks only"],
	["Token ripples", "disturbance_ripple_strength", 0.0, 1.5, 0.05, "Faint", "Strong"],
	["Ripple reach", "disturbance_ripple_radius", 0.3, 3.0, 0.05, "Tight", "Wide"],
]

var _water: WaterSettings = WaterSettings.default()
var _look_tiles: TileRow
var _palette_tiles: TileRow
var _motion_tiles: TileRow
var _clarity_row: PropertyRow
var _rows: Dictionary = {}
var _color_rows: Dictionary = {}


func _build() -> void:
	_add_heading("Water")

	var look_field := _add_tile_field("Look", LOOK_TILES)
	_look_tiles = look_field.tiles
	_look_tiles.selection_changed.connect(_on_look_selected)

	var palette_field := _add_tile_field("Color", [])
	for name in WaterPresets.get_palette_names():
		palette_field.tiles.add_tile(
			StringName(name), name.capitalize(), "", "", SwatchTextures.water_swatch(name)
		)
	palette_field.tiles.add_tile(&"custom", "Custom", "adjustments")
	_palette_tiles = palette_field.tiles
	_palette_tiles.selection_changed.connect(_on_palette_selected)

	var motion_field := _add_tile_field("Motion", MOTION_TILES)
	_motion_tiles = motion_field.tiles
	_motion_tiles.selection_changed.connect(_on_motion_selected)

	_clarity_row = _add_row(
		"Clarity",
		0.0,
		CLARITY_MAX,
		0.05,
		CLARITY_MAX - _water.depth_absorption,
		{"hint_low": "Murky", "hint_high": "Clear"}
	)
	_clarity_row.value_changed.connect(_on_clarity_changed)

	var body := _add_foldout().body
	_add_caption("Color", body)
	for spec in COLOR_ROWS:
		var key: String = spec[1]
		var row := _add_row(
			spec[0], 0.0, 1.0, 1.0, 0.0, {"show_slider": false, "show_color": true, "parent": body}
		)
		row.set_color_no_signal(_water.get(key))
		row.color_changed.connect(_on_color_changed.bind(key))
		_color_rows[key] = row
	_add_caption("Motion", body)
	_add_float_rows(MOTION_ROWS, body)
	_add_caption("Look", body)
	_add_float_rows(LOOK_ROWS, body)
	_sync_tiles()


func load_state(state: LevelVisualState) -> void:
	_water = state.water.copy_settings()
	_sync_rows()
	_sync_tiles()


func write_state(state: LevelVisualState) -> void:
	state.water = _water.copy_settings()


func _add_float_rows(specs: Array, parent: Node) -> void:
	for spec in specs:
		var key: String = spec[1]
		var row := _add_row(
			spec[0],
			spec[2],
			spec[3],
			spec[4],
			_water.get(key),
			{"parent": parent, "hint_low": spec[5], "hint_high": spec[6]}
		)
		row.value_changed.connect(_on_row_changed.bind(key))
		_rows[key] = row


## Push every working value into its row without emitting.
func _sync_rows() -> void:
	_clarity_row.set_value_no_signal(CLARITY_MAX - _water.depth_absorption)
	for key in _rows:
		_rows[key].set_value_no_signal(_water.get(key))
	for key in _color_rows:
		_color_rows[key].set_color_no_signal(_water.get(key))


func _sync_tiles() -> void:
	_sync_tile_row(_look_tiles, _water.matching_look())
	_sync_tile_row(_palette_tiles, _water.matching_palette())
	_sync_tile_row(_motion_tiles, _water.matching_motion())


func _sync_tile_row(tiles: TileRow, id: String) -> void:
	var is_custom := id == WaterPresets.CUSTOM_KEY
	tiles.set_tile_visible(StringName(WaterPresets.CUSTOM_KEY), is_custom)
	tiles.select(StringName(id))


func _emit() -> void:
	water_changed.emit(_water.to_dict())
	changed.emit()


## Tile presses: apply that group's values, refresh the rows, hide Custom for
## that row only. Selecting Custom changes nothing on its own, so it is not an
## edit (matches WorldPane).
func _on_look_selected(id: StringName) -> void:
	_apply_tile(WaterPresets.LOOKS, String(id))


func _on_palette_selected(id: StringName) -> void:
	_apply_tile(WaterPresets.PALETTES, String(id))


func _on_motion_selected(id: StringName) -> void:
	_apply_tile(WaterPresets.MOTIONS, String(id))


func _apply_tile(group: Dictionary, id: String) -> void:
	if id == WaterPresets.CUSTOM_KEY or not group.has(id):
		return
	_water.apply_group(group[id])
	_sync_rows()
	_sync_tiles()
	_emit()


func _on_clarity_changed(value: float) -> void:
	_water.depth_absorption = CLARITY_MAX - value
	_sync_tiles()
	_emit()


func _on_row_changed(value: float, key: String) -> void:
	_water.set(key, value)
	_sync_tiles()
	_emit()


func _on_color_changed(color: Color, key: String) -> void:
	_water.set(key, color)
	_sync_tiles()
	_emit()
