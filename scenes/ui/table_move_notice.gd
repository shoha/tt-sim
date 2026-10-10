class_name TableMoveNotice
extends CanvasLayer

## The notice everyone at the table sees before the table moves (TableMover, flow
## recommendation "The flow" 4): a glass chip at the top centre that names the move and counts
## it down, "Moving the table to Old Mill in 3" or "Returning everyone to the room in 3". The
## GM's chip ends in Stay here, which calls the move off for everyone; that is the undo of a
## move (UI_TASTE I4), so the move itself asks nothing more. The chip only fades in and out:
## the spectacle is the table's (M7).

## The seconds ran out (the move goes ahead).
signal elapsed
## The GM pressed Stay here.
signal cancelled

## Over the board and its drawers, under dialogs and the loading screen (the toasts' layer).
const LAYER := 90
const TOP_MARGIN := 12
const STAY_HERE := "Stay here"
const ROOM_TEXT := "Returning everyone to the room"

var label: Label
## The GM's Stay here, or null on a player's chip.
var stay_button: Button = null

var _text := ""
var _left := 0.0
var _done := false
var _chip: PanelContainer
var _icon: TextureRect


## A notice for `text` counting down `seconds`, with Stay here when `can_cancel` (the GM).
static func create(text: String, seconds: float, can_cancel: bool) -> TableMoveNotice:
	var notice := TableMoveNotice.new()
	notice.name = "TableMoveNotice"
	notice._text = text
	notice._left = maxf(seconds, 0.0)
	notice._build(can_cancel)
	return notice


## The words of a move to the map named `map_name`.
static func moving_text(map_name: String) -> String:
	return "Moving the table to %s" % map_name


## `text` with the whole seconds left of `left`, as the chip shows it. Pure.
static func countdown_text(text: String, left: float) -> String:
	return "%s in %d" % [text, maxi(ceili(left), 1)]


## The seconds left before the move.
func seconds_left() -> float:
	return _left


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
	var icon := TextureRect.new()
	icon.texture = IconButton.load_icon("users" if _text == ROOM_TEXT else "map")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ToastContainer.ICON_SIZE, ToastContainer.ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)
	label = Label.new()
	label.name = "Label"
	label.theme_type_variation = &"Body"
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.text = countdown_text(_text, _left)
	row.add_child(label)
	if can_cancel:
		stay_button = UiActions.secondary(STAY_HERE, "arrow-back-up", row)
		stay_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stay_button.pressed.connect(_on_stay_pressed)
	_icon = icon


func _ready() -> void:
	# Information is cool (lake), resolved against the glass theme the chip carries.
	_icon.self_modulate = ThemeColors.of(_chip, ThemeColors.STATE)
	_chip.modulate.a = 0.0
	create_tween().tween_property(_chip, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	AudioManager.play(&"tick")


func _process(delta: float) -> void:
	if _done:
		return
	_left -= delta
	if _left > 0.0:
		label.text = countdown_text(_text, _left)
		return
	dismiss()
	elapsed.emit()


func _on_stay_pressed() -> void:
	if _done:
		return
	dismiss()
	cancelled.emit()
