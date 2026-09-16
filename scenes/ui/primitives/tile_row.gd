class_name TileRow
extends HFlowContainer

## Equal-size selectable tiles (icon above a caption label) for enums of ten or
## fewer options. Single-select by default (one ButtonGroup); [member
## multi_select] makes every tile an independent toggle. Signals fire only for
## user clicks; [method select] and [method set_tile_on] are silent so panes can
## sync from state without feedback. Set [member columns] to fill the row width
## with a fixed number of tiles per line.

signal selection_changed(id: StringName)
signal tile_toggled(id: StringName, on: bool)

## Pointer entered / left a tile. Hosts use these for previews; they never
## change the selection, never fire from programmatic calls, and stay silent
## for disabled tiles (nothing to preview that cannot be picked).
signal tile_hovered(id: StringName)
signal tile_unhovered(id: StringName)

@export var multi_select: bool = false
@export var tile_min_size := Vector2(64, 56)

## Tiles per line when greater than zero: every tile is widened to an equal
## share of the row, so the row wraps at exactly this count and fills its
## width. Zero keeps the natural flow (tile_min_size widths).
@export var columns: int = 0:
	set(value):
		columns = value
		_fit_columns()

var selected: StringName = &""

var _tiles: Dictionary = {}
var _tweens: Dictionary = {}
var _group: ButtonGroup


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("h_separation", 6)
	add_theme_constant_override("v_separation", 6)
	resized.connect(_fit_columns)


func add_tile(
	id: StringName,
	label: String,
	icon_name: String = "",
	tooltip: String = "",
	icon_texture: Texture2D = null
) -> Button:
	var tile := Button.new()
	# Node names cannot be empty (Godot errors on set_name("")); a sentinel
	# "no selection" tile (e.g. SkyPane's "None" sky) legitimately has id == "".
	tile.name = String(id) if not String(id).is_empty() else "Tile%d" % get_child_count()
	tile.text = label
	tile.toggle_mode = true
	tile.theme_type_variation = &"Tile"
	tile.custom_minimum_size = tile_min_size
	tile.icon = icon_texture if icon_texture else IconButton.load_icon(icon_name)
	tile.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tile.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	tile.tooltip_text = tooltip
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.set_meta("ui_silent", true)
	tile.offset_transform_enabled = true
	if not multi_select:
		if not _group:
			_group = ButtonGroup.new()
			_group.allow_unpress = false
		tile.button_group = _group
	tile.toggled.connect(_on_tile_toggled.bind(id))
	tile.mouse_entered.connect(_on_tile_hover.bind(id, true))
	tile.mouse_exited.connect(_on_tile_hover.bind(id, false))
	add_child(tile)
	_tiles[id] = tile
	_fit_columns()
	return tile


func has_tile(id: StringName) -> bool:
	return _tiles.has(id)


## Single-select sync without signals.
func select(id: StringName) -> void:
	selected = id
	for tile_id in _tiles:
		_tiles[tile_id].set_pressed_no_signal(tile_id == id)


## Multi-select sync without signals.
func set_tile_on(id: StringName, on: bool) -> void:
	if _tiles.has(id):
		_tiles[id].set_pressed_no_signal(on)


func is_on(id: StringName) -> bool:
	return _tiles.has(id) and _tiles[id].button_pressed


func set_tile_visible(id: StringName, tile_visible: bool) -> void:
	if _tiles.has(id):
		_tiles[id].visible = tile_visible


func _on_tile_toggled(pressed: bool, id: StringName) -> void:
	if multi_select:
		AudioManager.play_tick()
		tile_toggled.emit(id, pressed)
		return
	# The group unpresses the previous tile with its own toggled(false); only
	# the newly pressed tile is a selection change.
	if not pressed or id == selected:
		return
	selected = id
	AudioManager.play_tick()
	selection_changed.emit(id)


func _on_tile_hover(id: StringName, entered: bool) -> void:
	var tile: Button = _tiles[id]
	if tile.disabled:
		return
	if entered:
		tile_hovered.emit(id)
	else:
		tile_unhovered.emit(id)
	var target := Constants.UI_HOVER_SCALE if entered else Vector2.ONE
	var duration := Constants.ANIM_HOVER_IN if entered else Constants.ANIM_HOVER_OUT
	var trans := Tween.TRANS_BACK if entered else Tween.TRANS_CUBIC
	_tweens[id] = UiMotion.scale_to(tile, _tweens.get(id), target, duration, trans)


## Size every tile to an equal share of the row so exactly `columns` fit per
## line. Setting an unchanged custom_minimum_size is a no-op in Godot, so the
## resized -> fit -> relayout path settles without looping.
func _fit_columns() -> void:
	if columns <= 0:
		for id in _tiles:
			_tiles[id].clip_text = false
			_tiles[id].custom_minimum_size = tile_min_size
		return
	if size.x <= 0.0:
		return
	var gap := float(get_theme_constant("h_separation"))
	var width := floorf((size.x - gap * float(columns - 1)) / float(columns))
	for id in _tiles:
		var tile: Button = _tiles[id]
		tile.custom_minimum_size = Vector2(width, tile_min_size.y)
		# A label wider than its share would widen the tile and break the wrap
		# count; clip instead. Hosts keep labels short enough to fit.
		tile.clip_text = true
