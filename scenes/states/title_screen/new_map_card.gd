class_name NewMapCard
extends PanelContainer

## The library's first card, "+ New map": a painted picture of a map to come over Generate and
## Import... as siblings, and a closed Advanced disclosure under them (user verdict
## 2026-10-09: no Try step, "From image" never in the default view, custom dimensions under
## Advanced). Generate leads: it is the wider, taller of the two and wears the wand, but it is
## paper, since Host on the Play together card is the screen's one persimmon fill (C5) in an
## empty library too (Room first). Import... picks a map.glb exported from Blender (a file
## dropped anywhere on the library does the same; the title runs both).
##
## Advanced holds Size and Seed. Size is Drawn (the seed draws 100, 150 or 200 ft, so a pinned
## seed always draws the same size), one of NewMap.SIZES_FT, or Custom: width x depth in feet,
## refused past NewMap.size_error's range with its one sentence (Generate waits until the
## size is good), and warned in a quiet line above WARN_ABOVE_FT and again past
## NewMap.RECOMMENDED_MAX_FT. Seed is empty for a fresh random seed each Generate, or a whole
## number to pin it. Generate emits the spec ({"size_ft", "depth_ft" for a custom size,
## "seed"}) that Root hands to the new-map dialog, which asks the rest (starting place and
## landform) and opens authoring: no reroll here, so consecutive seeds never stand in for a
## fresh draw (coarse landform draws repeat on neighbouring seeds).
##
## In an empty library the card is the library: alone, larger (set_empty()), its picture
## bigger and its caption EMPTY_CAPTION, after the empty plaque it replaces.

signal generate_requested(spec: Dictionary)
signal import_requested

const SIZE_DRAWN := &"drawn"
const SIZE_CUSTOM := &"custom"
const TITLE := "New map"
const CAPTION := "Generate a place, or import one"
const EMPTY_CAPTION := "Make your first map, or drop a map.glb from Blender here"
const GENERATE_TIP := "Draw a new map from a seed, then choose where it starts"
const IMPORT_TIP := "Bring in a map.glb exported from Blender (or drop one anywhere here)"
## The picture's width over its height: a band beside cards, a wider picture alone.
const PICTURE_ASPECT := 4.0
const EMPTY_PICTURE_ASPECT := 2.2
const PICTURE_KEY := "Your first map"
## The card's width alone in an empty library.
const EMPTY_WIDTH := 520.0
## Above this side the size line warns that the map builds more slowly.
const WARN_ABOVE_FT := 200
const SLOW_LINE := "Over %d ft a side the map takes longer to build."
const BIG_LINE := "Over %d ft a side: it plays the same, but builds, opens and saves slowly."
const SEED_ERROR := "A seed is a whole number, or empty for a fresh one."
const CUSTOM_DEFAULT := Vector2i(150, 100)
const SIZE_TILE := Vector2(56, 32)

static var _chevron_down: Texture2D

## Advanced is open.
var advanced_open := false
## The Size tile chosen (SIZE_DRAWN, SIZE_CUSTOM or &"size_<ft>").
var size_choice: StringName = SIZE_DRAWN
var picture: Panel
var heading: Label
var caption: Label
var generate_button: Button
var import_button: Button
var advanced_button: Button
var advanced_body: VBoxContainer
var size_field: TileField
var custom_row: HBoxContainer
var width_box: SpinBox
var depth_box: SpinBox
var seed_edit: LineEdit
## The size or seed line: why Generate waits, or the big-map warning.
var size_line: Label

var _empty := false


func _init() -> void:
	name = "NewMapCard"
	theme_type_variation = &"PictureCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var column := VBoxContainer.new()
	column.name = "Column"
	column.theme_type_variation = &"BoxContainerSpaced"
	add_child(column)
	picture = RoomRows.map_well(Vector2(0, 64), null, PICTURE_KEY, "")
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.resized.connect(_fit_picture)
	column.add_child(picture)
	# The words and buttons sit inside the card's text margin, as a map card's caption does.
	var text_margin := MarginContainer.new()
	text_margin.name = "TextMargin"
	text_margin.theme_type_variation = &"CardText"
	text_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(text_margin)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerSpaced"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_margin.add_child(inner)
	var words := VBoxContainer.new()
	words.theme_type_variation = &"BoxContainerTight"
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(words)
	heading = Label.new()
	heading.name = "Heading"
	heading.text = TITLE
	heading.theme_type_variation = &"H3"
	words.add_child(heading)
	caption = Label.new()
	caption.name = "Caption"
	caption.text = CAPTION
	caption.theme_type_variation = &"Caption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.add_child(caption)
	_build_actions(inner)
	_build_advanced(inner)
	_refresh_size()


func _build_actions(column: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.theme_type_variation = &"BoxContainerSpaced"
	column.add_child(row)
	# Framed: the card's lead reads first without taking the screen's one fill.
	generate_button = UiActions.primary("Generate", "wand", "", row, &"Framed")
	generate_button.tooltip_text = GENERATE_TIP
	generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generate_button.size_flags_stretch_ratio = 1.4
	generate_button.custom_minimum_size.y = UiActions.SECONDARY_HEIGHT + 8
	generate_button.pressed.connect(generate)
	import_button = UiActions.secondary("Import...", "folder", row)
	import_button.name = "Import"
	import_button.tooltip_text = IMPORT_TIP
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.custom_minimum_size.y = generate_button.custom_minimum_size.y
	import_button.pressed.connect(import_requested.emit)


func _build_advanced(column: VBoxContainer) -> void:
	advanced_button = Button.new()
	advanced_button.name = "Advanced"
	advanced_button.text = "Advanced"
	advanced_button.theme_type_variation = &"FoldoutHeader"
	advanced_button.icon = IconButton.load_icon("chevron-right")
	advanced_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	advanced_button.tooltip_text = "Size and seed"
	advanced_button.pressed.connect(func() -> void: set_advanced(not advanced_open))
	column.add_child(advanced_button)
	advanced_body = VBoxContainer.new()
	advanced_body.name = "AdvancedBody"
	advanced_body.theme_type_variation = &"BoxContainerSpaced"
	advanced_body.visible = false
	column.add_child(advanced_body)
	size_field = TileField.new()
	size_field.name = "SizeField"
	size_field.caption = "Size"
	size_field.tiles.tile_min_size = SIZE_TILE
	size_field.tiles.columns = 3
	size_field.tiles.add_tile(SIZE_DRAWN, "Drawn", "", "The seed draws 100, 150 or 200 ft")
	for feet in NewMap.SIZES_FT:
		size_field.tiles.add_tile(StringName("size_%d" % feet), "%d ft" % feet, "", "")
	size_field.tiles.add_tile(SIZE_CUSTOM, "Custom", "", "Width x depth in feet")
	size_field.tiles.select(SIZE_DRAWN)
	size_field.tiles.selection_changed.connect(_on_size_selected)
	advanced_body.add_child(size_field)
	custom_row = HBoxContainer.new()
	custom_row.name = "CustomSize"
	custom_row.theme_type_variation = &"BoxContainerSpaced"
	custom_row.visible = false
	advanced_body.add_child(custom_row)
	width_box = _feet_box("Width", CUSTOM_DEFAULT.x, custom_row)
	var by := Label.new()
	by.text = "x"
	by.theme_type_variation = &"Caption"
	custom_row.add_child(by)
	depth_box = _feet_box("Depth", CUSTOM_DEFAULT.y, custom_row)
	var feet_word := Label.new()
	feet_word.text = "ft"
	feet_word.theme_type_variation = &"Caption"
	custom_row.add_child(feet_word)
	size_line = Label.new()
	size_line.name = "SizeLine"
	size_line.theme_type_variation = &"Caption"
	size_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_line.visible = false
	advanced_body.add_child(size_line)
	var seed_row := HBoxContainer.new()
	seed_row.name = "SeedRow"
	seed_row.theme_type_variation = &"BoxContainerSpaced"
	advanced_body.add_child(seed_row)
	var seed_word := Label.new()
	seed_word.text = "Seed"
	seed_word.theme_type_variation = &"Caption"
	seed_row.add_child(seed_word)
	seed_edit = LineEdit.new()
	seed_edit.name = "Seed"
	seed_edit.placeholder_text = "A fresh one each time"
	seed_edit.max_length = 10
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.tooltip_text = "Pin a seed to draw the same map again"
	seed_edit.text_changed.connect(func(_text: String) -> void: _refresh_size())
	seed_edit.text_submitted.connect(func(_text: String) -> void: generate())
	seed_row.add_child(seed_edit)


func _feet_box(what: String, feet: int, parent: Control) -> SpinBox:
	var box := SpinBox.new()
	box.name = what
	box.min_value = 5
	box.max_value = 1000
	box.step = NewMap.FEET_PER_CELL
	box.value = feet
	box.allow_greater = true
	box.select_all_on_focus = true
	box.tooltip_text = "%s in feet, in 5 ft squares" % what
	box.value_changed.connect(func(_value: float) -> void: _refresh_size())
	parent.add_child(box)
	return box


## Alone in an empty library: larger, a bigger picture and the first-map caption; beside cards:
## a card's width (LevelGrid sets it) with the picture a band.
func set_empty(on: bool) -> void:
	_empty = on
	caption.text = EMPTY_CAPTION if on else CAPTION
	heading.theme_type_variation = &"H2" if on else &"H3"
	if on:
		custom_minimum_size.x = EMPTY_WIDTH
	_fit_picture()


func is_empty_library() -> bool:
	return _empty


func set_advanced(open: bool) -> void:
	advanced_open = open
	advanced_body.visible = open
	advanced_button.icon = chevron_down() if open else IconButton.load_icon("chevron-right")
	AudioManager.play(&"tick")


## The disclosure's open chevron: the icon set has chevron-right only, turned a quarter.
static func chevron_down() -> Texture2D:
	if _chevron_down == null:
		var image := IconButton.load_icon("chevron-right").get_image()
		if image.is_compressed():
			image.decompress()
		image.rotate_90(CLOCKWISE)
		_chevron_down = ImageTexture.create_from_image(image)
	return _chevron_down


## The size chosen, in feet: Vector2i(width, depth), or Vector2i.ZERO for Drawn.
func chosen_size() -> Vector2i:
	if size_choice == SIZE_DRAWN:
		return Vector2i.ZERO
	if size_choice == SIZE_CUSTOM:
		return Vector2i(roundi(width_box.value), roundi(depth_box.value))
	var feet := int(String(size_choice).trim_prefix("size_"))
	return Vector2i(feet, feet)


## Why Generate cannot run with what Advanced holds, in one sentence, or "".
func refusal() -> String:
	if parse_seed(seed_edit.text) < -1:
		return SEED_ERROR
	var size := chosen_size()
	if size == Vector2i.ZERO:
		return ""
	return NewMap.size_error(size.x, size.y)


## The spec Generate emits: {"size_ft", "seed"}, and "depth_ft" for a custom size. A pinned
## seed is used; otherwise a fresh NewMap.random_seed(). Drawn draws the size from the seed.
func spec() -> Dictionary:
	var pinned := parse_seed(seed_edit.text)
	var seed_value := pinned if pinned >= 0 else NewMap.random_seed()
	var out := {"seed": seed_value}
	var size := chosen_size()
	if size == Vector2i.ZERO:
		out.size_ft = draw_size(seed_value)
	else:
		out.size_ft = size.x
		if size.y != size.x:
			out.depth_ft = size.y
	return out


func generate() -> void:
	if refusal() != "":
		_refresh_size()
		return
	AudioManager.play(&"confirm")
	generate_requested.emit(spec())


## The size Drawn gives seed `seed_value`: one of NewMap.SIZES_FT, the same for the same seed.
## Pure.
static func draw_size(seed_value: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return NewMap.SIZES_FT[rng.randi_range(0, NewMap.SIZES_FT.size() - 1)]


## A typed seed: -1 for none (empty), -2 for one that is not a whole number in 31 bits. Pure.
static func parse_seed(text: String) -> int:
	var trimmed := text.strip_edges()
	if trimmed == "":
		return -1
	if not trimmed.is_valid_int():
		return -2
	var value := trimmed.to_int()
	return value if value >= 0 and value <= 0x7fffffff else -2


## The quiet line under the size: the refusal, or a warning for a big map, or nothing.
static func size_note(width_ft: int, depth_ft: int) -> String:
	var error := NewMap.size_error(width_ft, depth_ft)
	if error != "":
		return error
	var side := maxi(width_ft, depth_ft)
	if side > NewMap.RECOMMENDED_MAX_FT:
		return BIG_LINE % NewMap.RECOMMENDED_MAX_FT
	if side > WARN_ABOVE_FT:
		return SLOW_LINE % WARN_ABOVE_FT
	return ""


func _on_size_selected(id: StringName) -> void:
	size_choice = id
	custom_row.visible = id == SIZE_CUSTOM
	_refresh_size()


func _refresh_size() -> void:
	if size_line == null:
		return
	var size := chosen_size()
	var note := size_note(size.x, size.y) if size != Vector2i.ZERO else ""
	if parse_seed(seed_edit.text) < -1:
		note = SEED_ERROR
	size_line.text = note
	size_line.visible = note != ""
	generate_button.disabled = refusal() != ""


func _fit_picture() -> void:
	var aspect := EMPTY_PICTURE_ASPECT if _empty else PICTURE_ASPECT
	var height := floorf(picture.size.x / aspect)
	if height > 0.0 and not is_equal_approx(picture.custom_minimum_size.y, height):
		picture.custom_minimum_size.y = height
