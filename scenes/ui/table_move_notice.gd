class_name TableMoveNotice
extends CanvasLayer

## The notice everyone at the table sees before the table moves (TableMover, flow
## recommendation "The flow" 4): a glass chip at the top centre that names the move, where the
## table goes and, on a player's chip, who moves it, and counts it down: "Moving the table to
## Old Mill in 3", "Marigold is moving the table to Fen Crossing in 3". The GM's chip ends in
## Stay here, which calls the move off for everyone; that is the undo of a move (UI_TASTE I4),
## so the move itself asks nothing. The chip only fades in and out: the spectacle is the
## table's (M7).
##
## Each sentence is one translated template with named placeholders ({map}, {gm}, {n}), so a
## translation may order them as its language does. The count is drawn on its own, in semibold
## tabular figures, so the chip's width never moves as it counts; the sentence is cut at {n}
## into the words before and after it. A long name is shortened with an ellipsis until the
## sentence fits MAX_SENTENCE_WIDTH, the whole sentence in the chip's tooltip.

## The seconds ran out (the move goes ahead).
signal elapsed
## The GM pressed Stay here.
signal cancelled

## What a move does: the table goes to another map, everyone returns to the room, the map on
## the table is set back as it was saved (Discard changes on the table), or set out again from
## the map just saved (Save into map on the table, when its terrain was written).
enum Kind { MAP, ROOM, RESET, RELOAD }

## Over the board and its drawers, under dialogs and the loading screen (the toasts' layer).
const LAYER := 90
const TOP_MARGIN := 12
## The widest the words around the count may be: with the icon, the count and Stay here the
## chip stays inside a 1280x720 canvas.
const MAX_SENTENCE_WIDTH := 520.0
## A name is never shortened below this many characters before the label itself ellipsizes.
const MIN_NAME := 6
const STAY_HERE := "Stay here"
## Who moves the table on a player's chip when the GM's name is not known.
const SOMEONE := "The GM"
## The GM's own chip, by Kind.
const OWN_TEXT := {
	Kind.MAP: "Moving the table to {map} in {n}",
	Kind.ROOM: "Returning everyone to the room in {n}",
	Kind.RESET: "Putting {map} back as it was saved in {n}",
	Kind.RELOAD: "Setting out {map} as saved in {n}",
}
## A player's chip, naming who moves the table, by Kind.
const PLAYER_TEXT := {
	Kind.MAP: "{gm} is moving the table to {map} in {n}",
	Kind.ROOM: "{gm} is returning everyone to the room in {n}",
	Kind.RESET: "{gm} is putting {map} back as it was saved in {n}",
	Kind.RELOAD: "{gm} saved {map} and is setting it out again in {n}",
}
const ICONS := {
	Kind.MAP: "map", Kind.ROOM: "users", Kind.RESET: "restore", Kind.RELOAD: "device-floppy"
}

## The words before and after the count, and the count.
var before_label: Label
var after_label: Label
var count_label: Label
## The GM's Stay here, or null on a player's chip.
var stay_button: Button = null

var _kind := Kind.MAP
var _map := ""
var _mover := ""
var _left := 0.0
var _shown := 0
var _done := false
var _chip: PanelContainer
var _icon: TextureRect


## A notice for a move of `kind` to the map named `map_name` counting down `seconds`. The GM's
## own chip has `mover` "" and, with `can_cancel`, Stay here; a player's names `mover`, who
## moves the table, and never has Stay here.
static func create(
	kind: Kind, map_name: String, seconds: float, mover := "", can_cancel := true
) -> TableMoveNotice:
	var notice := TableMoveNotice.new()
	notice.name = "TableMoveNotice"
	notice._kind = kind
	notice._map = map_name
	notice._mover = mover
	notice._left = maxf(seconds, 0.0)
	notice._build(can_cancel and mover == "")
	return notice


## The chip's sentence for a move of `kind` to `map_name`, with its count left as {n}: the GM's
## own when `mover` is "", else a player's naming `mover`. Translated. Pure.
static func sentence(kind: Kind, map_name: String, mover := "") -> String:
	var template: String = OWN_TEXT[kind] if mover == "" else PLAYER_TEXT[kind]
	return TranslationServer.translate(template).format({"map": map_name, "gm": mover})


## `text` (a sentence()) with the whole seconds left of `left`, as the chip reads. Pure.
static func countdown_text(text: String, left: float) -> String:
	return text.format({"n": whole_seconds(left)})


## The count the chip shows for `left` seconds: whole seconds up, never below 1. Pure.
static func whole_seconds(left: float) -> int:
	return maxi(ceili(left), 1)


## The seconds left before the move.
func seconds_left() -> float:
	return _left


## The chip's whole sentence as it reads now, with no name shortened.
func shown_text() -> String:
	return countdown_text(sentence(_kind, _map, _mover), _left)


## Takes the chip away (the move went ahead or was called off elsewhere). Idempotent.
func dismiss() -> void:
	if _done:
		return
	_done = true
	if not is_inside_tree():
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_chip, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	tween.finished.connect(queue_free)


func _build(can_cancel: bool) -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A column across the top, TOP_MARGIN down, that centres the chip.
	var column := VBoxContainer.new()
	column.theme = ThemeColors.glass_theme()
	column.set_anchors_preset(Control.PRESET_TOP_WIDE)
	column.offset_top = TOP_MARGIN
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	_chip = PanelContainer.new()
	_chip.name = "Chip"
	_chip.theme_type_variation = &"Toast"
	_chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_chip.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(_chip)
	var row := HBoxContainer.new()
	row.theme_type_variation = &"BoxContainerSpaced"
	_chip.add_child(row)
	_icon = TextureRect.new()
	_icon.texture = IconButton.load_icon(ICONS[_kind])
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(ToastContainer.ICON_SIZE, ToastContainer.ICON_SIZE)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_icon)
	# The words and the count, the tight gap (about a space at body size) apart.
	var words := HBoxContainer.new()
	words.name = "Words"
	words.theme_type_variation = &"BoxContainerTight"
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(words)
	before_label = _words_label("Before")
	words.add_child(before_label)
	count_label = Label.new()
	count_label.name = "Count"
	count_label.theme_type_variation = &"H3"
	words.add_child(count_label)
	after_label = _words_label("After")
	words.add_child(after_label)
	if can_cancel:
		stay_button = AnimatedButton.new()
		stay_button.name = "StayHere"
		stay_button.text = STAY_HERE
		stay_button.icon = IconButton.load_icon("arrow-back-up")
		stay_button.theme_type_variation = &"Secondary"
		stay_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stay_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		stay_button.pressed.connect(_on_stay_pressed)
		row.add_child(stay_button)


func _words_label(node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = &"Body"
	return label


func _ready() -> void:
	# Information is cool (lake), resolved against the glass theme the chip carries.
	_icon.self_modulate = ThemeColors.of(_chip, ThemeColors.STATE)
	# No theme variation carries tabular figures at body size: the count's own font is the
	# H3 face with tnum switched on (a ratcheted override, tests/ui_bypass_baseline.json).
	count_label.add_theme_font_override(&"font", tabular(count_label.get_theme_font(&"font")))
	var font := before_label.get_theme_font(&"font")
	_fit_words(font, before_label.get_theme_font_size(&"font_size"))
	if stay_button:
		_outline(stay_button)
	_show_count()
	_chip.modulate.a = 0.0
	create_tween().tween_property(_chip, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	AudioManager.play(&"tick")


func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	if _left > 0.0:
		_show_count()
		return
	dismiss()
	elapsed.emit()


func _show_count() -> void:
	var count := whole_seconds(_left)
	if count != _shown:
		_shown = count
		count_label.text = str(count)


## The words around the count, fitted to MAX_SENTENCE_WIDTH: the destination is what the chip
## is for, so the mover's name gives way first (their first name alone), then the map's
## (shortened with an ellipsis), then the first name; the label ellipsizes past that.
func _fit_words(font: Font, font_size: int) -> void:
	var names := [_map, _mover]
	var parts := _parts(names)
	var width := func(text: String) -> float:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var too_wide := func(pieces: PackedStringArray) -> bool:
		return width.call(pieces[0]) + width.call(pieces[1]) > MAX_SENTENCE_WIDTH
	var first_name := _mover.get_slice(" ", 0)
	if bool(too_wide.call(parts)) and first_name != "" and first_name != _mover:
		names[1] = first_name
		parts = _parts(names)
	for index in [0, 1]:
		var whole: String = names[index]
		var keep := whole.length()
		while bool(too_wide.call(parts)) and keep > MIN_NAME:
			keep -= 1
			names[index] = whole.left(keep).strip_edges() + "…"
			parts = _parts(names)
	before_label.text = parts[0]
	after_label.text = parts[1]
	after_label.visible = parts[1] != ""
	# A shortened name is whole in the tooltip.
	var whole_names := PackedStringArray()
	for index in names.size():
		if names[index] != [_map, _mover][index]:
			whole_names.append([_map, _mover][index])
	_chip.tooltip_text = " · ".join(whole_names)
	if bool(too_wide.call(parts)):
		before_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		before_label.custom_minimum_size.x = MAX_SENTENCE_WIDTH - width.call(parts[1])


## The sentence for `names` ([map, mover]) cut at the count: [before, after], trimmed.
func _parts(names: Array) -> PackedStringArray:
	var text := sentence(_kind, str(names[0]), str(names[1]) if _mover != "" else "")
	var cut := text.split("{n}", true, 1)
	if cut.size() < 2:
		cut.append("")
	return PackedStringArray([cut[0].strip_edges(), cut[1].strip_edges()])


## `font` with tabular figures switched on, so every digit takes the same width.
static func tabular(font: Font) -> Font:
	var variation := font as FontVariation
	var copy := variation.duplicate() as FontVariation if variation else FontVariation.new()
	if variation == null:
		copy.base_font = font
	var features := copy.opentype_features.duplicate()
	features[TextServerManager.get_primary_interface().name_to_tag("tnum")] = 1
	copy.opentype_features = features
	return copy


## Stay here's frame at 3:1 against the chip (the glass track role) in every state, where the
## quiet button's own edge is a faint rim.
static func _outline(button: Button) -> void:
	var edge := ThemeColors.of(button, ThemeColors.TRACK)
	for state: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed"]:
		var box := button.get_theme_stylebox(state) as StyleBoxFlat
		if box == null:
			continue
		var framed := box.duplicate() as StyleBoxFlat
		framed.border_color = edge
		framed.set_border_width_all(maxi(framed.border_width_left, 1))
		button.add_theme_stylebox_override(state, framed)


func _on_stay_pressed() -> void:
	if _done:
		return
	dismiss()
	cancelled.emit()
