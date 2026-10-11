class_name NewMapCard
extends PanelContainer

## The library's first card, "New map", in the anatomy every map card has: a 16:9 picture, a
## name line and a caption band. The picture is a solid paper face with one ink glyph (a map
## still to come, never a map's picture); the name line says New map with Advanced at its end;
## the caption band holds Generate and Import... as siblings (user verdict 2026-10-09: no Try
## step, "From image" never in the default view, custom dimensions under Advanced). Generate
## leads: it is the wider of the two and wears the wand, but it is paper (Framed), since Host
## on the Play together card is the screen's one persimmon fill (C5) in an empty library too
## (Room first). Import... picks a map exported from Blender (a file dropped anywhere on the
## library does the same; the title runs both).
##
## Advanced opens a paper popover anchored under the card (coordinator decision 2026-10-10):
## it lies over the cards below, so opening it, typing in it and a refusal never change the
## card's height or move the grid. It closes on a click outside it or Escape; its choices stay.
## It is added to the nearest CanvasLayer above the card (the title), so it draws over the
## grid and is never clipped by it, and follows the card when the grid scrolls.
##
## Advanced holds Size and Seed. Size is Any size (the seed picks 100, 150 or 200 ft, so a
## pinned seed always picks the same size), one of NewMap.SIZES_FT, or Custom: width x depth
## in feet, each a field between 40 px minus and plus targets that step a 5 ft square. A side
## past the format's range is refused in the popover: its field outlined in the danger role
## beside the alert icon and a sentence that says which side, why and what to set (W3);
## Generate keeps its frame, waits, and its tooltip says why. Above WARN_ABOVE_FT, and again
## past NewMap.RECOMMENDED_MAX_FT, a quiet line with the warning icon says the map builds more
## slowly (warnings never block). Seed is empty for a fresh random seed each Generate, or a
## whole number to pin it. Generate emits the spec ({"size_ft", "depth_ft" for a custom size,
## "seed"}) that Root hands to the new-map dialog, which asks the rest (starting place and
## landform) and opens authoring.
##
## Beside map cards it is a map card's height (LevelGrid asks, fit_row()): its name line and
## buttons are taller than a map's caption band, so its face gives up the difference and is
## shorter than 16:9; no card in the line is stretched to meet it.
##
## In an empty library the card is the library: alone, larger (set_empty()), its face 2:1,
## its glyph bigger and a caption line (EMPTY_CAPTION, one line) over its buttons, with the
## Bundled maps offered under it (LevelGrid).

signal generate_requested(spec: Dictionary)
signal import_requested

const SIZE_ANY := &"any"
const SIZE_CUSTOM := &"custom"
const TITLE := "New map"
const CAPTION := "Generate a place, or import one"
const EMPTY_CAPTION := "Generate your first map, or bring one in from Blender"
const GENERATE_TIP := "Draw a new map from a seed, then choose where it starts"
const IMPORT_TIP := "Bring in a map exported from Blender as .glb (or drop one anywhere here)"
const ANY_TIP := "The seed picks the size: 100, 150 or 200 ft"
## The face's width over its height, a map card's picture's.
const PICTURE_ASPECT := LevelCard.THUMB_ASPECT
## The glyph on the face, beside cards and alone.
const GLYPH := "plus"
const GLYPH_SIZE := 40.0
const EMPTY_GLYPH_SIZE := 56.0
## The card's width alone in an empty library, and its face's width over its height there (no
## map card beside it to match; low enough that a Bundled map's name shows under it unscrolled
## on a 1280x720 canvas).
const EMPTY_WIDTH := 420.0
const EMPTY_FACE_ASPECT := 2.0
## The popover's narrowest.
const POPOVER_MIN_WIDTH := 360.0
## The face's shortest, however short the line it fits (fit_row()).
const FACE_MIN_HEIGHT := 64.0
## Above this side the size line warns that the map builds more slowly.
const WARN_ABOVE_FT := 200
const SLOW_LINE := "Over %d ft a side the map takes longer to build."
const BIG_LINE := "Over %d ft a side: it plays the same, but builds, opens and saves slowly."
const TOO_BIG := "%s %d ft is more than a map can hold: a side is %d ft at most. Set %d or less."
const TOO_SMALL := "%s %d ft is less than a square: a side must be at least %d ft."
const SEED_ERROR := "A seed is a whole number. Type one, or clear it for a fresh one."
const CUSTOM_DEFAULT := Vector2i(150, 100)
const SIZE_TILE := Vector2(64, 40)
## Minus and plus beside a side in feet: 40 px targets (S6).
const STEP_TARGET := Vector2(40, 40)

static var _chevron_down: Texture2D

## Advanced is open.
var advanced_open := false
## The Size tile chosen (SIZE_ANY, SIZE_CUSTOM or &"size_<ft>").
var size_choice: StringName = SIZE_ANY
var picture: Panel
## The ink glyph on the face.
var glyph: TextureRect
var heading: Label
var caption: Label
var generate_button: Button
var import_button: Button
var advanced_button: Button
## The popover Advanced opens, and its column.
var advanced_popover: PanelContainer
var advanced_body: VBoxContainer
var size_field: TileField
var custom_row: HBoxContainer
var width_box: FeetField
var depth_box: FeetField
var seed_edit: LineEdit
## The refusal or the big-map warning, with its icon (size_icon), in the popover.
var size_note_row: HBoxContainer
var size_icon: TextureRect
var size_line: Label

var _empty := false
var _anchor_parent: Control = null
var _column: VBoxContainer
## The line's height to fit (fit_row()), or 0 for the card's own (a 16:9 face).
var _row_height := 0.0


## A side in feet: its number in a field between minus and plus targets that step a 5 ft square
## (NewMap.FEET_PER_CELL). `value` reads and sets it as a SpinBox's does.
class FeetField:
	extends HBoxContainer

	signal value_changed(value: float)

	var edit: LineEdit
	var value: float = 0.0:
		set(feet):
			value = feet
			if edit != null and edit.text.to_int() != roundi(feet):
				edit.text = "%d" % roundi(feet)
			value_changed.emit(feet)

	func _init(what: String, feet: int) -> void:
		name = what
		theme_type_variation = &"BoxContainerTight"
		_step_button("minus", "%s 5 ft less" % what, -1)
		edit = LineEdit.new()
		edit.name = "Feet"
		edit.text = "%d" % feet
		edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
		edit.custom_minimum_size = Vector2(64, NewMapCard.STEP_TARGET.y)
		edit.select_all_on_focus = true
		edit.max_length = 4
		edit.tooltip_text = "%s in feet, in 5 ft squares" % what
		edit.text_changed.connect(_on_text_changed)
		add_child(edit)
		_step_button("plus", "%s 5 ft more" % what, 1)
		value = feet

	func _step_button(icon: String, tip: String, sign_of: int) -> void:
		var button := Button.new()
		button.icon = IconButton.load_icon(icon)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.tooltip_text = tip
		button.custom_minimum_size = NewMapCard.STEP_TARGET
		button.pressed.connect(
			func() -> void: value = maxf(value + sign_of * NewMap.FEET_PER_CELL, 0.0)
		)
		add_child(button)

	func _on_text_changed(text: String) -> void:
		var digits := text.strip_edges()
		value = float(digits.to_int()) if digits.is_valid_int() else 0.0


func _init() -> void:
	name = "NewMapCard"
	theme_type_variation = &"PictureCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	# A map card's column: the picture, then the words inside its text margin.
	var column := VBoxContainer.new()
	column.name = "Column"
	column.theme_type_variation = &"BoxContainerTight"
	add_child(column)
	_column = column
	# A solid paper face with one ink glyph: a map still to come, not a map's picture.
	picture = Panel.new()
	picture.name = "Face"
	picture.theme_type_variation = &"CardThumb"
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	picture.custom_minimum_size = Vector2(0, 64)
	picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picture.resized.connect(_fit_picture)
	column.add_child(picture)
	glyph = TextureRect.new()
	glyph.name = "Glyph"
	glyph.texture = IconButton.load_icon(GLYPH)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.theme_changed.connect(
		func() -> void: glyph.self_modulate = ThemeColors.of(glyph, ThemeColors.TEXT)
	)
	picture.add_child(glyph)
	# The words in a map card's text margin, its foot taken by the buttons' own margin below.
	var text_margin := MarginContainer.new()
	text_margin.name = "TextMargin"
	text_margin.theme_type_variation = &"CardTextHead"
	text_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(text_margin)
	var inner := VBoxContainer.new()
	inner.name = "Inner"
	inner.theme_type_variation = &"BoxContainerTight"
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_margin.add_child(inner)
	# The name line, as a map card's (Advanced at its end); a caption line over the buttons
	# only over an empty library, where the card stands alone.
	var heading_row := HBoxContainer.new()
	heading_row.name = "HeadingRow"
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_child(heading_row)
	heading = Label.new()
	heading.name = "Heading"
	heading.text = TITLE
	heading.theme_type_variation = &"Body"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	heading_row.add_child(heading)
	caption = Label.new()
	caption.name = "Caption"
	caption.text = CAPTION
	caption.theme_type_variation = &"Caption"
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.visible = false
	inner.add_child(caption)
	_build_actions(column)
	_build_advanced(heading_row)
	_refresh_size()


## The buttons in their own margin (CardActions): nearer the card's edge than the words, as the
## map panel's actions are, so the card needs no more than a grid column at a 1280x720 canvas.
func _build_actions(column: VBoxContainer) -> void:
	var margin := MarginContainer.new()
	margin.name = "ActionsMargin"
	margin.theme_type_variation = &"CardActions"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(margin)
	var row := HBoxContainer.new()
	row.name = "Actions"
	row.theme_type_variation = &"BoxContainerTight"
	margin.add_child(row)
	# Framed: the card's lead reads first without taking the screen's one fill.
	generate_button = UiActions.primary("Generate", "wand", "", row, &"Framed")
	generate_button.tooltip_text = GENERATE_TIP
	generate_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	generate_button.size_flags_stretch_ratio = 1.4
	generate_button.custom_minimum_size.y = UiActions.SECONDARY_HEIGHT
	generate_button.pressed.connect(generate)
	import_button = UiActions.secondary("Import...", "folder", row)
	import_button.name = "Import"
	import_button.tooltip_text = IMPORT_TIP
	import_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	import_button.custom_minimum_size.y = generate_button.custom_minimum_size.y
	import_button.pressed.connect(import_requested.emit)


func _build_advanced(row: HBoxContainer) -> void:
	advanced_button = Button.new()
	advanced_button.name = "Advanced"
	advanced_button.text = "Advanced"
	advanced_button.theme_type_variation = &"FoldoutHeader"
	advanced_button.icon = IconButton.load_icon("chevron-right")
	advanced_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	advanced_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	advanced_button.tooltip_text = "Size and seed"
	advanced_button.pressed.connect(func() -> void: set_advanced(not advanced_open))
	row.add_child(advanced_button)
	advanced_popover = PanelContainer.new()
	advanced_popover.name = "AdvancedPopover"
	advanced_popover.theme_type_variation = &"Sheet"
	advanced_popover.mouse_filter = Control.MOUSE_FILTER_STOP
	advanced_popover.visible = false
	advanced_body = VBoxContainer.new()
	advanced_body.name = "AdvancedBody"
	advanced_body.theme_type_variation = &"BoxContainerSpaced"
	advanced_popover.add_child(advanced_body)
	size_field = TileField.new()
	size_field.name = "SizeField"
	size_field.caption = "Size"
	size_field.tiles.tile_min_size = SIZE_TILE
	size_field.tiles.columns = 3
	size_field.tiles.add_tile(SIZE_ANY, "Any size", "", ANY_TIP)
	for feet in NewMap.SIZES_FT:
		size_field.tiles.add_tile(StringName("size_%d" % feet), "%d ft" % feet, "", "")
	size_field.tiles.add_tile(SIZE_CUSTOM, "Custom", "", "Width × depth in feet")
	size_field.tiles.select(SIZE_ANY)
	size_field.tiles.selection_changed.connect(_on_size_selected)
	advanced_body.add_child(size_field)
	custom_row = HBoxContainer.new()
	custom_row.name = "CustomSize"
	custom_row.theme_type_variation = &"BoxContainerSpaced"
	custom_row.visible = false
	advanced_body.add_child(custom_row)
	width_box = _feet_box("Width", CUSTOM_DEFAULT.x, custom_row)
	_caption_word("×", custom_row)
	depth_box = _feet_box("Depth", CUSTOM_DEFAULT.y, custom_row)
	_caption_word("ft", custom_row)
	size_note_row = HBoxContainer.new()
	size_note_row.name = "SizeNote"
	size_note_row.theme_type_variation = &"BoxContainerTight"
	size_note_row.visible = false
	advanced_body.add_child(size_note_row)
	size_icon = TextureRect.new()
	size_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	size_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	size_icon.custom_minimum_size = Vector2(20, 20)
	size_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	size_icon.theme_changed.connect(_tint_note)
	size_note_row.add_child(size_icon)
	size_line = Label.new()
	size_line.name = "SizeLine"
	size_line.theme_type_variation = &"Caption"
	size_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	size_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_line.custom_minimum_size.x = 200
	size_note_row.add_child(size_line)
	var seed_row := HBoxContainer.new()
	seed_row.name = "SeedRow"
	seed_row.theme_type_variation = &"BoxContainerSpaced"
	advanced_body.add_child(seed_row)
	_caption_word("Seed", seed_row)
	seed_edit = LineEdit.new()
	seed_edit.name = "Seed"
	seed_edit.placeholder_text = "A fresh one each time"
	seed_edit.max_length = 10
	seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seed_edit.tooltip_text = "Pin a seed to draw the same map again"
	seed_edit.text_changed.connect(func(_text: String) -> void: _refresh_size())
	seed_edit.text_submitted.connect(func(_text: String) -> void: generate())
	seed_row.add_child(seed_edit)


func _caption_word(text: String, parent: Control) -> void:
	var word := Label.new()
	word.text = text
	word.theme_type_variation = &"Caption"
	parent.add_child(word)


func _feet_box(what: String, feet: int, parent: Control) -> FeetField:
	var box := FeetField.new(what, feet)
	box.value_changed.connect(func(_value: float) -> void: _refresh_size())
	parent.add_child(box)
	return box


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			_anchor_parent = get_parent() as Control
			if _anchor_parent != null:
				_anchor_parent.item_rect_changed.connect(_place_popover)
			item_rect_changed.connect(_place_popover)
		NOTIFICATION_EXIT_TREE:
			var anchor := _anchor_parent
			if anchor != null and anchor.item_rect_changed.is_connected(_place_popover):
				anchor.item_rect_changed.disconnect(_place_popover)
			if item_rect_changed.is_connected(_place_popover):
				item_rect_changed.disconnect(_place_popover)
			_anchor_parent = null
		NOTIFICATION_PREDELETE:
			# The popover lives on the title's layer once opened: it goes with the card.
			if is_instance_valid(advanced_popover):
				if advanced_popover.get_parent() == null:
					advanced_popover.free()
				elif advanced_popover.get_parent() != self:
					advanced_popover.queue_free()


## Alone in an empty library: larger, a bigger glyph and the first-map caption over the
## buttons; beside cards: a card's width (LevelGrid sets it), its name line and buttons only.
func set_empty(on: bool) -> void:
	_empty = on
	caption.text = EMPTY_CAPTION if on else CAPTION
	caption.visible = on
	if on:
		custom_minimum_size.x = EMPTY_WIDTH
	_fit_picture()


func is_empty_library() -> bool:
	return _empty


## Opens or closes the Advanced popover over the cards below the card.
func set_advanced(open: bool) -> void:
	advanced_open = open
	advanced_button.icon = chevron_down() if open else IconButton.load_icon("chevron-right")
	if open and advanced_popover.get_parent() == null:
		_popover_host().add_child(advanced_popover)
	advanced_popover.visible = open
	AudioManager.play(&"tick")
	if open:
		_place_popover()
		_place_popover.call_deferred()


## The nearest CanvasLayer above the card (the title), so the popover draws over the grid and
## is never clipped by it; the card itself outside one (a test).
func _popover_host() -> Node:
	var node := get_parent()
	while node != null:
		if node is CanvasLayer:
			return node
		node = node.get_parent()
	return self


## The popover under the card at its left edge, so Generate stays in sight beside what it
## waits on (over the card's foot when the canvas ends first), at least POPOVER_MIN_WIDTH
## wide, kept on the canvas.
func _place_popover() -> void:
	if not advanced_open or not is_inside_tree() or advanced_popover.get_parent() == self:
		return
	var card := get_global_rect()
	var width := maxf(card.size.x, POPOVER_MIN_WIDTH)
	width = maxf(width, advanced_popover.get_combined_minimum_size().x)
	advanced_popover.size = Vector2(width, 0.0)
	var height := advanced_popover.get_combined_minimum_size().y
	var canvas := get_viewport_rect().size
	var x := card.position.x
	var y := card.end.y + 4.0
	if y + height > canvas.y - 8.0:
		# No room under the card (720p): beside it, over the next card, Generate still in sight.
		x = card.end.x + 4.0
		y = card.position.y
	x = clampf(x, 8.0, maxf(canvas.x - width - 8.0, 8.0))
	advanced_popover.position = Vector2(x, clampf(y, 8.0, maxf(canvas.y - 8.0 - height, 8.0)))


## A click outside the popover and its link closes it (the click still lands); Escape closes
## it and gives the focus back to the link.
func _input(event: InputEvent) -> void:
	if not advanced_open:
		return
	if event.is_action_pressed("ui_cancel"):
		set_advanced(false)
		advanced_button.grab_focus()
		get_viewport().set_input_as_handled()
		return
	var click := event as InputEventMouseButton
	if click == null or not click.pressed:
		return
	var point := click.global_position
	if advanced_popover.get_global_rect().has_point(point):
		return
	if advanced_button.get_global_rect().has_point(point):
		return
	set_advanced(false)


## The disclosure's open chevron: the icon set has chevron-right only, turned a quarter.
static func chevron_down() -> Texture2D:
	if _chevron_down == null:
		var image := IconButton.load_icon("chevron-right").get_image()
		if image.is_compressed():
			image.decompress()
		image.rotate_90(CLOCKWISE)
		_chevron_down = ImageTexture.create_from_image(image)
	return _chevron_down


## The size chosen, in feet: Vector2i(width, depth), or Vector2i.ZERO for Any size.
func chosen_size() -> Vector2i:
	if size_choice == SIZE_ANY:
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
	var width := side_refusal("Width", size.x)
	return width if width != "" else side_refusal("Depth", size.y)


## The refusal of one side `feet` long, named `what`, or "" when a map can have it. Pure.
static func side_refusal(what: String, feet: int) -> String:
	if NewMap.size_error(feet) == "":
		return ""
	if feet > NewMap.MAX_FT:
		return TOO_BIG % [what, feet, NewMap.MAX_FT, NewMap.MAX_FT]
	return TOO_SMALL % [what, feet, NewMap.MIN_FT]


## The spec Generate emits: {"size_ft", "seed"}, and "depth_ft" for a custom size. A pinned
## seed is used; otherwise a fresh NewMap.random_seed(). Any size draws the size from the seed.
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
	if advanced_open:
		set_advanced(false)
	generate_requested.emit(spec())


## The size Any size gives seed `seed_value`: one of NewMap.SIZES_FT, the same for the same
## seed. Pure.
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


## The quiet warning under a size that a map can have: the slow line above WARN_ABOVE_FT, the
## big line past NewMap.RECOMMENDED_MAX_FT, or "". Pure.
static func size_note(width_ft: int, depth_ft: int) -> String:
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


## The popover's note (the refusal with the alert icon and the refused field outlined, else
## the big-map warning with the warning icon) and Generate's state and tooltip.
func _refresh_size() -> void:
	if size_line == null:
		return
	var size := chosen_size()
	var refused := refusal()
	var note := refused
	if note == "" and size != Vector2i.ZERO:
		note = size_note(size.x, size.y)
	size_line.text = note
	size_note_row.visible = note != ""
	var role := ThemeColors.DANGER if refused != "" else ThemeColors.WARNING
	size_icon.texture = IconButton.load_icon("alert-circle" if refused != "" else "alert-triangle")
	size_icon.set_meta(&"role", role)
	_tint_note()
	var custom := size_choice == SIZE_CUSTOM
	for box: FeetField in [width_box, depth_box]:
		var bad := custom and side_refusal(String(box.name), roundi(box.value)) != ""
		box.edit.theme_type_variation = &"FieldError" if bad else &""
	seed_edit.theme_type_variation = &"FieldError" if parse_seed(seed_edit.text) < -1 else &""
	generate_button.disabled = refused != ""
	generate_button.tooltip_text = refused if refused != "" else GENERATE_TIP


func _tint_note() -> void:
	if size_icon.is_inside_tree():
		size_icon.self_modulate = ThemeColors.of(size_icon, size_icon.get_meta(&"role"))


## Fit a line `height` tall (a map card's, LevelGrid): the face takes up the difference between
## that and the rest of the card. 0 gives the card its own height, the face at 16:9.
func fit_row(height: float) -> void:
	if is_equal_approx(height, _row_height):
		return
	_row_height = height
	_fit_picture()


## The face at a map picture's 16:9 (EMPTY_FACE_ASPECT alone), or what a fitted line leaves it
## (fit_row()), the glyph centred on it.
func _fit_picture() -> void:
	var height := floorf(picture.size.x / (EMPTY_FACE_ASPECT if _empty else PICTURE_ASPECT))
	if _row_height > 0.0 and not _empty:
		var rest := _column.get_combined_minimum_size().y - picture.custom_minimum_size.y
		rest += get_theme_stylebox(&"panel").get_minimum_size().y
		height = maxf(floorf(_row_height - rest), FACE_MIN_HEIGHT)
	if height > 0.0 and not is_equal_approx(picture.custom_minimum_size.y, height):
		picture.custom_minimum_size.y = height
	var side := EMPTY_GLYPH_SIZE if _empty else GLYPH_SIZE
	glyph.size = Vector2(side, side)
	glyph.position = ((picture.size - glyph.size) * 0.5).floor()
