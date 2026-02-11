extends CanvasLayer
class_name DisconnectIndicator

## Top-center banner shown during network reconnection attempts.
## Instantiate via the scene; call show_message() / hide_indicator().

@onready var _label: Label = %Label


func _ready() -> void:
	# Apply warning-styled panel
	var panel := $MarginContainer/PanelContainer as PanelContainer
	var style := StyleBoxFlat.new()
	style.bg_color = Constants.COLOR_TOAST_BG
	style.border_color = Constants.COLOR_WARNING
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)

	_label.add_theme_color_override("font_color", Constants.COLOR_WARNING)

	# Start hidden
	hide()


func show_message(text: String) -> void:
	_label.text = text
	if not visible:
		show()


func hide_indicator() -> void:
	hide()
