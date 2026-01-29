extends CanvasLayer
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
var _tween: Tween


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	
	# Start hidden for animation
	$ColorRect.modulate.a = 0.0
	$CenterContainer.modulate.a = 0.0
	_animate_in()


func setup(title: String, message: String, confirm_text: String = "Confirm", cancel_text: String = "Cancel", confirm_callback: Callable = Callable(), cancel_callback: Callable = Callable(), confirm_style: String = "Success") -> void:
	title_label.text = title
	message_label.text = message
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_button.theme_type_variation = confirm_style
	_confirm_callback = confirm_callback
	_cancel_callback = cancel_callback


func _animate_in() -> void:
	if _tween:
		_tween.kill()
	
	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	panel.scale = Vector2(0.9, 0.9)
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_BACK)
	_tween.tween_property($ColorRect, "modulate:a", 1.0, 0.2)
	_tween.tween_property($CenterContainer, "modulate:a", 1.0, 0.2)
	_tween.tween_property(panel, "scale", Vector2.ONE, 0.2)
	
	await _tween.finished
	confirm_button.grab_focus()


func _animate_out(confirmed: bool) -> void:
	if _tween:
		_tween.kill()
	
	var panel = $CenterContainer/PanelContainer
	panel.pivot_offset = panel.size / 2
	
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property($ColorRect, "modulate:a", 0.0, 0.15)
	_tween.tween_property($CenterContainer, "modulate:a", 0.0, 0.15)
	_tween.tween_property(panel, "scale", Vector2(0.95, 0.95), 0.15)
	
	await _tween.finished
	closed.emit(confirmed)
	queue_free()


func _on_confirm_pressed() -> void:
	if _confirm_callback.is_valid():
		_confirm_callback.call()
	_animate_out(true)


func _on_cancel_pressed() -> void:
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	_animate_out(false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()
