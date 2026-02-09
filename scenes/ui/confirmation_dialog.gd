extends AnimatedCanvasLayerPanel
class_name ConfirmationDialogUI

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

@onready var title_label: Label = %TitleLabel
@onready var message_label: Label = %MessageLabel
@onready var confirm_button: Button = %ConfirmButton
@onready var cancel_button: Button = %CancelButton

var _confirm_callback: Callable
var _cancel_callback: Callable
var _confirm_sound_override: Callable
var _confirmed: bool = false


func _on_panel_ready() -> void:
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
	confirm_style: String = "Success",
	confirm_sound_override: Callable = Callable(),
) -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_button.theme_type_variation = confirm_style
	_confirm_callback = confirm_callback
	_cancel_callback = cancel_callback
	_confirm_sound_override = confirm_sound_override
	_is_danger = confirm_style == "Danger"


var _is_danger: bool = false


func _on_after_animate_in() -> void:
	confirm_button.grab_focus()

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
	if _confirm_sound_override.is_valid():
		_confirm_sound_override.call()
		# Suppress the base class close sound so only the override is heard
		play_sounds = false
	else:
		AudioManager.play_confirm()
	_confirmed = true
	if _confirm_callback.is_valid():
		_confirm_callback.call()
	animate_out()


func _on_cancel_pressed() -> void:
	AudioManager.play_cancel()
	_confirmed = false
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	animate_out()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
