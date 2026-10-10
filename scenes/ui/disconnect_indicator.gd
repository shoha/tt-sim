class_name DisconnectIndicator
extends CanvasLayer

## Top-center banner shown during network reconnection attempts.
## Instantiate via the scene; call show_message() / hide_indicator().
## A glass warning toast (the Toast variation with the warning kind's ochre icon); its text
## stays chalk, since the icon and the words already say it is a warning (C7).

@onready var _label: Label = %Label
@onready var _row: HBoxContainer = %Row


func _ready() -> void:
	var panel := $MarginContainer/PanelContainer as PanelContainer
	panel.theme_type_variation = &"Toast"
	var icon := ToastContainer.kind_icon(ToastContainer.ToastType.WARNING, panel)
	_row.add_child(icon)
	_row.move_child(icon, 0)

	# Start hidden
	hide()


func show_message(text: String) -> void:
	_label.text = text
	if not visible:
		show()


func hide_indicator() -> void:
	hide()
