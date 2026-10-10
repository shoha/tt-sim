class_name DisconnectIndicator
extends CanvasLayer

## Top-center banner shown during network reconnection attempts.
## Instantiate via the scene; call show_message() / hide_indicator().
## A glass warning toast (the ToastWarning variation: the ochre stripe); its text stays
## chalk, since the stripe and the words already say it is a warning (C7).

@onready var _label: Label = %Label


func _ready() -> void:
	var panel := $MarginContainer/PanelContainer as PanelContainer
	panel.theme_type_variation = &"ToastWarning"

	# Start hidden
	hide()


func show_message(text: String) -> void:
	_label.text = text
	if not visible:
		show()


func hide_indicator() -> void:
	hide()
