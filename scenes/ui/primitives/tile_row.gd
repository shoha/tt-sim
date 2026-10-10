class_name TileRow
extends HFlowContainer

## Equal-size selectable tiles (icon above a caption label) for enums of ten or
## fewer options. Single-select by default (one ButtonGroup); [member
## multi_select] makes every tile an independent toggle. Signals fire only for
## user clicks; [method select] and [method set_tile_on] are silent so panes can
## sync from state without feedback. Set [member columns] to fill the row width
## with up to that many tiles per line. Labels are never clipped mid-letter
## (docs/UI_TASTE.md T6): a row too narrow for its longest label at that count
## takes fewer, balanced columns (six landforms become two lines of three), and a
## label that still does not fit ends in an ellipsis with the full name in its
## tooltip.

signal selection_changed(id: StringName)
signal tile_toggled(id: StringName, on: bool)

## Pointer entered / left a tile. Hosts use these for previews; they never
## change the selection, never fire from programmatic calls, and stay silent
## for disabled tiles (nothing to preview that cannot be picked).
signal tile_hovered(id: StringName)
signal tile_unhovered(id: StringName)

## The host's own tooltip, kept so a truncated label can put its full name in front.
const TOOLTIP_META := &"tile_tooltip"

@export var multi_select: bool = false
@export var tile_min_size := Vector2(64, 56)

## Tiles per line when greater than zero: every tile is widened to an equal
## share of the row, so the row wraps at this count (fewer when the longest
## label would not fit, see fitted_columns) and fills its width. Zero keeps the
## natural flow (tile_min_size widths).
@export var columns: int = 0:
	set(value):
		columns = value
		_fit_columns()

## Tile icons are pictures (biome thumbnails, surface swatches) rather than tinted glyphs:
## drawn at their own size and untinted in every state. The Tile variation otherwise caps
## icons at 24 px and tints them like the white Tabler icons.
@export var photo_icons: bool = false
## Photo icons fill the tile above its label, as wide as the tile allows at their own aspect
## (Button.expand_icon), for pictures painted as wide strips; the tile's height is then
## tile_min_size's alone.
@export var photo_fill: bool = false

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
	tile.set_meta(TOOLTIP_META, tooltip)
	tile.focus_mode = Control.FOCUS_NONE
	tile.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tile.set_meta("ui_silent", true)
	tile.offset_transform_enabled = true
	if photo_icons and tile.icon:
		tile.add_theme_constant_override("icon_max_width", tile.icon.get_width())
		tile.expand_icon = photo_fill
		for state in [
			"icon_normal_color",
			"icon_hover_color",
			"icon_pressed_color",
			"icon_hover_pressed_color",
			"icon_focus_color",
		]:
			tile.add_theme_color_override(state, Color.WHITE)
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


## Replaces tile `id`'s tooltip (a disabled tile's says why). Kept as the tile's own, so a
## refit (a resize) keeps it rather than restoring the one add_tile gave.
func set_tile_tooltip(id: StringName, tooltip: String) -> void:
	if not _tiles.has(id):
		return
	var tile: Button = _tiles[id]
	tile.set_meta(TOOLTIP_META, tooltip)
	tile.tooltip_text = tooltip
	_fit_columns()


func _on_tile_toggled(pressed: bool, id: StringName) -> void:
	if multi_select:
		AudioManager.play(&"tick")
		tile_toggled.emit(id, pressed)
		return
	# The group unpresses the previous tile with its own toggled(false); only
	# the newly pressed tile is a selection change.
	if not pressed or id == selected:
		return
	selected = id
	AudioManager.play(&"tick")
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


## The column count for `count` tiles in a row `width` wide with `gap` between
## tiles, when the widest tile needs `need` px: `wanted`, or fewer when a share
## would be narrower than `need`, then balanced so no line is left nearly empty
## (six that fit five per line become three and three). Never fewer than two
## (one when one is wanted): a picker of one long column is worse than an
## ellipsis.
static func fitted_columns(wanted: int, count: int, width: float, gap: float, need: float) -> int:
	var fit := wanted
	while fit > 1 and floorf((width - gap * float(fit - 1)) / float(fit)) < need:
		fit -= 1
	fit = maxi(fit, mini(wanted, 2))
	if fit < wanted and count > fit:
		var lines := ceili(float(count) / float(fit))
		fit = ceili(float(count) / float(lines))
	return fit


## Size every tile to an equal share of the row so `columns` (or the fitted
## count) fit per line. Setting an unchanged custom_minimum_size is a no-op in
## Godot, so the resized -> fit -> relayout path settles without looping.
func _fit_columns() -> void:
	if columns <= 0:
		for id in _tiles:
			var tile: Button = _tiles[id]
			tile.clip_text = false
			tile.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
			tile.tooltip_text = tile.get_meta(TOOLTIP_META, "")
			tile.custom_minimum_size = tile_min_size
		return
	if size.x <= 0.0 or _tiles.is_empty():
		return
	var gap := float(get_theme_constant("h_separation"))
	var need := 0.0
	for id in _tiles:
		need = maxf(need, _natural_width(_tiles[id]))
	var count := fitted_columns(columns, _tiles.size(), size.x, gap, need)
	var width := floorf((size.x - gap * float(count - 1)) / float(count))
	for id in _tiles:
		var tile: Button = _tiles[id]
		tile.custom_minimum_size = Vector2(width, tile_min_size.y)
		# A label wider than its share would widen the tile and break the wrap
		# count; it ends in an ellipsis instead, with its full name in the tooltip.
		tile.clip_text = true
		tile.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var tooltip: String = tile.get_meta(TOOLTIP_META, "")
		if _natural_width(tile) > width and not tooltip.contains(tile.text):
			tooltip = tile.text if tooltip.is_empty() else "%s\n%s" % [tile.text, tooltip]
		tile.tooltip_text = tooltip


## The width `tile` needs to show its label and icon whole: the wider of the two
## plus the Tile style's side padding.
func _natural_width(tile: Button) -> float:
	var font := tile.get_theme_font(&"font")
	var font_size := tile.get_theme_font_size(&"font_size")
	var text_width := font.get_string_size(tile.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var icon_width := 0.0
	# A filling picture shrinks to the tile, so only the label sets the width it needs.
	if tile.icon and not tile.expand_icon:
		var cap := tile.get_theme_constant(&"icon_max_width")
		icon_width = float(tile.icon.get_width())
		if cap > 0:
			icon_width = minf(icon_width, float(cap))
	var style := tile.get_theme_stylebox(&"normal")
	var sides := style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style else 0.0
	return ceilf(maxf(text_width, icon_width) + sides)
