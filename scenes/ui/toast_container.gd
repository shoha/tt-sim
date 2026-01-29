extends CanvasLayer
class_name ToastContainer

## Container for displaying toast notifications.
##
## Toasts appear in the bottom-right corner and auto-dismiss.
## Supports different types: info, success, warning, error.

enum ToastType {INFO, SUCCESS, WARNING, ERROR}

const MAX_VISIBLE_TOASTS := 5
const DEFAULT_DURATION := 3.0

@onready var toast_vbox: VBoxContainer = %VBoxContainer

var _active_toasts: Array[Control] = []


func show_toast(message: String, type: ToastType = ToastType.INFO, duration: float = DEFAULT_DURATION) -> void:
	var toast = _create_toast(message, type)
	toast_vbox.add_child(toast)
	_active_toasts.append(toast)
	
	# Limit visible toasts
	while _active_toasts.size() > MAX_VISIBLE_TOASTS:
		var oldest = _active_toasts.pop_front()
		if oldest and is_instance_valid(oldest):
			_dismiss_toast(oldest, true)
	
	# Animate in
	_animate_toast_in(toast)
	
	# Schedule dismissal
	if duration > 0:
		get_tree().create_timer(duration).timeout.connect(func(): _dismiss_toast(toast, false))


func _create_toast(message: String, type: ToastType) -> Control:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	margin.add_child(hbox)
	
	# Icon label
	var icon_label = Label.new()
	icon_label.text = _get_icon_for_type(type)
	hbox.add_child(icon_label)
	
	# Message label
	var label = Label.new()
	label.text = message
	label.theme_type_variation = "Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(label)
	
	# Apply style based on type
	_apply_toast_style(panel, icon_label, type)
	
	return panel


func _get_icon_for_type(type: ToastType) -> String:
	match type:
		ToastType.SUCCESS:
			return "+"
		ToastType.WARNING:
			return "!"
		ToastType.ERROR:
			return "X"
		_:
			return "i"


func _apply_toast_style(panel: PanelContainer, icon_label: Label, type: ToastType) -> void:
	var style = StyleBoxFlat.new()
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.border_width_left = 3
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	
	# Base dark background
	style.bg_color = Color(0.17, 0.12, 0.17, 0.95)
	
	# Type-specific accent
	match type:
		ToastType.SUCCESS:
			style.border_color = Color(0.62, 0.72, 0.53) # Green
			icon_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.53))
		ToastType.WARNING:
			style.border_color = Color(1.0, 0.82, 0.37) # Yellow
			icon_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.37))
		ToastType.ERROR:
			style.border_color = Color(0.99, 0.58, 0.51) # Red
			icon_label.add_theme_color_override("font_color", Color(0.99, 0.58, 0.51))
		_:
			style.border_color = Color(0.86, 0.57, 0.29) # Orange/Accent
			icon_label.add_theme_color_override("font_color", Color(0.86, 0.57, 0.29))
	
	panel.add_theme_stylebox_override("panel", style)


func _animate_toast_in(toast: Control) -> void:
	toast.modulate.a = 0.0
	toast.position.x += 50
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(toast, "modulate:a", 1.0, 0.2)
	tween.tween_property(toast, "position:x", toast.position.x - 50, 0.2)


func _dismiss_toast(toast: Control, immediate: bool) -> void:
	if not is_instance_valid(toast):
		return
	
	# Remove from tracking
	var idx = _active_toasts.find(toast)
	if idx >= 0:
		_active_toasts.remove_at(idx)
	
	if immediate:
		toast.queue_free()
		return
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(toast, "modulate:a", 0.0, 0.15)
	tween.tween_property(toast, "position:x", toast.position.x + 30, 0.15)
	tween.finished.connect(toast.queue_free)
