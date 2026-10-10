class_name ToastContainer
extends CanvasLayer

## Container for displaying toast notifications.
##
## Toasts appear at the bottom-center of the screen and auto-dismiss.
## Supports different types: info, success, warning, error. Each is a glass chip whose
## kind shows twice (UI_TASTE.md C7): a left stripe (the Toast* theme variations) and an
## icon tinted with the same role. Information is cool (lake: it says what is); the
## outcomes are moss, ochre and madder.

enum ToastType { INFO, SUCCESS, WARNING, ERROR }

const MAX_VISIBLE_TOASTS := 5
const DEFAULT_DURATION := 3.0
const ICON_SIZE := 20
## Every toast's width: a stack of equal chips, and room for a two-line warning ("Maps are
## built offline. Leave the game to build or edit a map.") rather than three.
const WIDTH := 360.0
## Per kind: the panel's theme variation, the icon and the role that tints it.
const KINDS := {
	ToastType.INFO: [&"ToastInfo", "info-circle", ThemeColors.STATE],
	ToastType.SUCCESS: [&"ToastSuccess", "circle-check", ThemeColors.SUCCESS],
	ToastType.WARNING: [&"ToastWarning", "alert-triangle", ThemeColors.WARNING],
	ToastType.ERROR: [&"ToastError", "alert-circle", ThemeColors.DANGER],
}

var _active_toasts: Array[Control] = []

@onready var toast_vbox: VBoxContainer = %VBoxContainer


func show_toast(
	message: String, type: ToastType = ToastType.INFO, duration: float = DEFAULT_DURATION
) -> void:
	var toast = _create_toast(message, type)
	toast_vbox.add_child(toast)
	_active_toasts.append(toast)

	# Limit visible toasts
	while _active_toasts.size() > MAX_VISIBLE_TOASTS:
		var oldest = _active_toasts.pop_front()
		if oldest and is_instance_valid(oldest):
			_dismiss_toast(oldest, true)

	# Animate in
	_animate_toast_in(toast, type)

	# Schedule dismissal
	if duration > 0:
		get_tree().create_timer(duration).timeout.connect(func(): _dismiss_toast(toast, false))


func _create_toast(message: String, type: ToastType) -> Control:
	var kind: Array = KINDS.get(type, KINDS[ToastType.INFO])
	var panel = PanelContainer.new()
	panel.theme_type_variation = kind[0]
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var hbox = HBoxContainer.new()
	hbox.theme_type_variation = &"BoxContainerSpaced"
	panel.add_child(hbox)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = IconButton.load_icon(kind[1])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The roles resolve against the glass theme the container carries.
	icon.self_modulate = ThemeColors.of(toast_vbox, kind[2])
	hbox.add_child(icon)

	var label = Label.new()
	label.text = message
	label.theme_type_variation = "Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(label)

	return panel


func _animate_toast_in(toast: Control, type: ToastType = ToastType.INFO) -> void:
	# Fade-only animation — avoids fighting with VBoxContainer layout management.
	toast.modulate.a = 0.0

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(toast, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)

	# Play a sound matching the toast type
	match type:
		ToastType.SUCCESS:
			AudioManager.play(&"success")
		ToastType.ERROR:
			AudioManager.play(&"error")
		ToastType.WARNING:
			AudioManager.play(&"tick")
		_:
			AudioManager.play(&"tick")


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
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(toast, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	tween.finished.connect(toast.queue_free)
