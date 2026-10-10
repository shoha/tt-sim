class_name ConfirmationDialogUI
extends AnimatedCanvasLayerPanel

## Reusable confirmation dialog component.
##
## Usage:
##   var dialog = UIManager.show_confirmation("Delete Item?", "This cannot be undone.")
##   var result = await dialog.closed
##   if result:
##       # User confirmed
##
## Or with callbacks:
##   UIManager.show_confirmation("Save?", "Save before closing?", func(): save(), func(): discard())

signal closed(confirmed: bool)

var header: MenuHeader
var title_label: Label

var _confirm_callback: Callable
var _cancel_callback: Callable
var _confirm_sound: StringName = &"confirm"
var _confirmed: bool = false
var _closing: bool = false
var _is_danger: bool = false

@onready var message_label: Label = %MessageLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton


func _on_panel_ready() -> void:
	var box: VBoxContainer = $CenterContainer/PanelContainer/VBoxContainer
	header = MenuHeader.new()
	header.name = "Header"
	box.add_child(header)
	box.move_child(header, 0)
	title_label = header.title_label

	# Opt out of generic click — these buttons play confirm/cancel sounds instead
	confirm_button.set_meta("ui_silent", true)
	cancel_button.set_meta("ui_silent", true)

	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)


func setup(
	title: String,
	message: String,
	confirm_text: String = "Confirm",
	cancel_text: String = "Cancel",
	confirm_callback: Callable = Callable(),
	cancel_callback: Callable = Callable(),
	confirm_style: String = "Primary",
	confirm_sound: StringName = &"confirm",
) -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_button.theme_type_variation = confirm_style
	_confirm_callback = confirm_callback
	_cancel_callback = cancel_callback
	_confirm_sound = confirm_sound
	_is_danger = confirm_style == "Danger"


## Adds a third choice as a Secondary button between Cancel and the confirm button (for
## example "Discard" between "Cancel" and "Save and leave"). Pressing it calls
## `callback` and closes the dialog; `closed` reports false, as for Cancel. Escape still
## means Cancel.
func add_alternate_action(text: String, callback: Callable) -> Button:
	var button := AnimatedButton.new()
	button.name = "AlternateButton"
	button.text = text
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(120, 0)
	button.set_meta("ui_silent", true)
	var row := confirm_button.get_parent()
	# Three buttons share the 420 sheet's footer: Cancel takes its own width, not 120.
	cancel_button.custom_minimum_size.x = 0.0
	row.add_child(button)
	row.move_child(button, confirm_button.get_index())
	button.pressed.connect(_on_alternate_pressed.bind(callback))
	rebuild_focus_trap()
	return button


## Holds the sheet on the width token `width` (420 or 600, UI_TASTE S5) whatever the title
## says: the title wraps instead of widening the sheet (a long map name in the title).
func hold_width(width: float) -> void:
	($CenterContainer/PanelContainer as Control).custom_minimum_size.x = width
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART


## Sets the confirm, a destructive action (the Danger style), apart at the footer's left with
## Cancel alone at its right, so the action that loses something is never where the eye looks
## for the safe one. A danger dialog still opens with Cancel focused.
func set_confirm_apart() -> void:
	var row := confirm_button.get_parent()
	row.move_child(confirm_button, 0)
	var gap := Control.new()
	gap.name = "Apart"
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(gap)
	row.move_child(gap, 1)
	rebuild_focus_trap()


func _on_alternate_pressed(callback: Callable) -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	_confirmed = false
	if callback.is_valid():
		callback.call()
	animate_out()


## A danger dialog opens with Cancel focused, so Enter or Space keeps what is there; any
## other dialog focuses its confirm. A dialog whose Cancel is hidden focuses its confirm.
func _on_after_animate_in() -> void:
	var safe := _is_danger and cancel_button.visible
	(cancel_button if safe else confirm_button).grab_focus()

	# Danger dialogs get a subtle horizontal shake to draw attention
	if _is_danger:
		_play_danger_shake()


## Quick horizontal shake animation for danger/destructive confirmations
func _play_danger_shake() -> void:
	var panel = $CenterContainer/PanelContainer
	var base_x: float = panel.position.x
	var tw = create_tween()
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(panel, "position:x", base_x + 6, 0.04)
	tw.tween_property(panel, "position:x", base_x - 5, 0.04)
	tw.tween_property(panel, "position:x", base_x + 3, 0.04)
	tw.tween_property(panel, "position:x", base_x - 2, 0.04)
	tw.tween_property(panel, "position:x", base_x, 0.04)


func _on_after_animate_out() -> void:
	closed.emit(_confirmed)
	queue_free()


func _on_confirm_pressed() -> void:
	if _closing:
		return
	_closing = true
	# The panel's close sound in the same frame is outranked, so only this one plays.
	AudioManager.play(_confirm_sound)
	_confirmed = true
	if _confirm_callback.is_valid():
		_confirm_callback.call()
	animate_out()


func _on_cancel_pressed() -> void:
	if _closing:
		return
	_closing = true
	AudioManager.play(&"cancel")
	_confirmed = false
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
