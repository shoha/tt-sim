class_name ToastContainer
extends CanvasLayer

## Container for displaying toast notifications.
##
## Toasts appear at the bottom-center of the screen and auto-dismiss.
## Supports different types: info, success, warning, error. Each is the same glass chip (the
## Toast variation, no side stripe: a stripe at rest is decoration, UI_TASTE anti-patterns);
## its kind shows twice (C7), in an icon tinted with the kind's role and in the words.
## Information is cool (lake: it says what is); the outcomes are moss, ochre and madder.
## A toast may offer one action at its end (the removal toast's Undo, I4): pressing it runs
## the action and dismisses the toast.

enum ToastType { INFO, SUCCESS, WARNING, ERROR }

const MAX_VISIBLE_TOASTS := 5
const DEFAULT_DURATION := 3.0
## A toast with an action stays long enough to read it and reach for the button.
const ACTION_DURATION := 6.0
const ICON_SIZE := 20
## Every toast's width: a stack of equal chips, and room for a two-line warning ("Maps are
## built offline. Leave the session to build or edit a map.") rather than three.
const WIDTH := 360.0
## Per kind: the icon and the role that tints it.
const KINDS := {
	ToastType.INFO: ["info-circle", ThemeColors.STATE],
	ToastType.SUCCESS: ["circle-check", ThemeColors.SUCCESS],
	ToastType.WARNING: ["alert-triangle", ThemeColors.WARNING],
	ToastType.ERROR: ["alert-circle", ThemeColors.DANGER],
}
## A toast with an action is as wide as its one line needs, up to this, so its words do not
## wrap beside the button ("Cleared for everyone at the table" with Undo, at 720p).
const ACTION_MAX_WIDTH := 520.0

var _active_toasts: Array[Control] = []

@onready var toast_vbox: VBoxContainer = %VBoxContainer


## Show a toast. With `action_label` and a valid `action`, a button at its end runs the
## action and dismisses the toast (`action_icon` is its Tabler icon).
func show_toast(
	message: String,
	type: ToastType = ToastType.INFO,
	duration: float = DEFAULT_DURATION,
	action_label: String = "",
	action: Callable = Callable(),
	action_icon: String = "",
) -> void:
	var toast = _create_toast(message, type)
	var has_action := action.is_valid() and not action_label.is_empty()
	if has_action:
		var button := _action_button(action_label, action_icon)
		button.pressed.connect(_on_action_pressed.bind(toast, action))
		toast.get_child(0).add_child(button)
	toast_vbox.add_child(toast)
	if has_action:
		_fit_one_line(toast)
	_active_toasts.append(toast)

	# Limit visible toasts
	while _active_toasts.size() > MAX_VISIBLE_TOASTS:
		var oldest = _active_toasts.pop_front()
		if oldest and is_instance_valid(oldest):
			_dismiss_toast(oldest, true)

	# Animate in
	_animate_toast_in(toast, type)

	# Schedule dismissal. Held weakly: a toast dismissed at once (the oldest past
	# MAX_VISIBLE_TOASTS) is freed before its timer runs, and a lambda that captured it
	# errors on the freed capture.
	if duration > 0:
		var held: WeakRef = weakref(toast)
		get_tree().create_timer(duration).timeout.connect(
			func() -> void:
				var shown: Control = held.get_ref()
				if shown != null:
					_dismiss_toast(shown, false)
		)


func _create_toast(message: String, type: ToastType) -> Control:
	var panel = PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var hbox = HBoxContainer.new()
	hbox.theme_type_variation = &"BoxContainerSpaced"
	panel.add_child(hbox)
	# The roles resolve against the glass theme the container carries.
	hbox.add_child(kind_icon(type, toast_vbox))

	var label = Label.new()
	label.text = message
	label.theme_type_variation = "Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(label)

	return panel


## The icon that names a toast kind, tinted with its role as resolved against `themed` (a
## node under the glass theme). The disconnect banner wears the warning one.
static func kind_icon(type: ToastType, themed: Control) -> TextureRect:
	var kind: Array = KINDS.get(type, KINDS[ToastType.INFO])
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = IconButton.load_icon(kind[0])
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = ThemeColors.of(themed, kind[1])
	return icon


## Widens `toast` (in the tree, so its fonts resolve) to its words' one-line width beside
## the icon and the action, between WIDTH and ACTION_MAX_WIDTH; past that they wrap.
func _fit_one_line(toast: Control) -> void:
	var label := toast.get_child(0).get_child(1) as Label
	toast.custom_minimum_size.x = 0.0
	# The chip with its words wrapped to nothing, plus the words' one-line width (2 px spare,
	# so the line does not break on rounding).
	var rest := toast.get_combined_minimum_size().x
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var words := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	toast.custom_minimum_size.x = clampf(ceilf(rest + words) + 2.0, WIDTH, ACTION_MAX_WIDTH)


## The action at a toast's end: a quiet Secondary button with its icon and a verb.
func _action_button(label: String, icon: String) -> Button:
	var button := AnimatedButton.new()
	button.name = "Action"
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.theme_type_variation = &"Secondary"
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return button


## Runs once: a second press while the toast fades finds it already dismissed.
func _on_action_pressed(toast: Control, action: Callable) -> void:
	if not _active_toasts.has(toast):
		return
	_dismiss_toast(toast, false)
	action.call()


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
