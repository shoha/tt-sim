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
## the action and dismisses the toast. A table event's toast wears the event's own icon
## (bridge-broken, tree-falling) in its kind's tint. Stacked toasts share the widest one's
## width, so their edges align in one column.

enum ToastType { INFO, SUCCESS, WARNING, ERROR }

const MAX_VISIBLE_TOASTS := 5
const DEFAULT_DURATION := 3.0
## A toast with an action stays long enough to read it and reach for the button.
const ACTION_DURATION := 6.0
const ICON_SIZE := 24
## The column's resting distance from the bottom edge (the scene's margin_bottom).
const REST_MARGIN_PX := 80.0
## The meta a toast carries its tag in (dismiss_tag).
const TAG_META := &"tt_toast_tag"
## Its words, kind and repeat count, for _repeat_of.
const MESSAGE_META := &"tt_toast_message"
const TYPE_META := &"tt_toast_type"
const COUNT_META := &"tt_toast_count"
## A toast the pointer has left stays at least this long.
const HOVER_GRACE_S := 1.0
## A toast arrives sliding this far up into place while it fades in (UI_TASTE M3: the offset
## transform, never the container's layout) and leaves sliding the other way.
const SLIDE_PX := 10.0
## A toast hugs its one line up to this width and wraps past it: room for a two-line warning
## ("Maps are built offline. Leave the session to build or edit a map.") rather than three,
## and a short one ("Raise undone") is no wider than its words (the 2a critic: a 360 px chip
## around two words read as an empty box).
const WIDTH := 360.0
## An error says what failed, why and how to recover (W3), so it wraps at the narrow sheet's
## width token (UI_TASTE S5) instead: three lines rather than five.
const ERROR_WIDTH := 420.0
## A toast stays at least as long as its words take to read: a moment to look, then this many
## words a second (a long error's recovery is read, not glimpsed).
const LOOK_S := 1.5
const WORDS_PER_S := 3.0
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


## The toasts stand on the centre line of the board the open drawers leave free, the line the
## input hint bar centres on (InputHints.on_drawers_moved), so the two never disagree: with a
## drawer open both sit beside it, with none both sit on the viewport's centre.
func _process(_delta: float) -> void:
	if _active_toasts.is_empty():
		return
	var viewport := get_viewport()
	var span := DrawerContainer.free_span(viewport)
	var rect := viewport.get_visible_rect()
	# The full-rect container is narrowed to the span by its offsets (a real layout, so the
	# Put back button's clicks land where it is drawn); the column centres in what is left.
	var margin := toast_vbox.get_parent() as Control
	margin.offset_left = span.x - rect.position.x
	margin.offset_right = span.y - rect.end.x
	# Above the hint bar when it is on show (two lines at 720p stand taller than the column's
	# resting margin), by the bar's height beyond that margin and a 8 px gap.
	var bar := get_tree().get_first_node_in_group(InputHints.GROUP) as InputHints
	var lift := 0.0
	if bar != null and bar.top_edge() < INF:
		lift = maxf(0.0, rect.end.y - bar.top_edge() + 8.0 - REST_MARGIN_PX)
	margin.offset_bottom = -lift


## Show a toast for `duration` seconds, or as long as its words take to read when that is
## longer (reading_seconds(); 0 keeps it up). With `action_label` and a valid `action`, a
## button at its end runs the action and dismisses the toast (`action_icon` is its Tabler
## icon).
func show_toast(
	message: String,
	type: ToastType = ToastType.INFO,
	duration: float = DEFAULT_DURATION,
	action_label: String = "",
	action: Callable = Callable(),
	action_icon: String = "",
	icon: String = "",
	tag: StringName = &"",
) -> void:
	var has_action := action.is_valid() and not action_label.is_empty()
	# The same words again (a move repeated, a save pressed twice) join the toast already up:
	# it stays a little longer and counts, instead of a second chip stacking (toast overload).
	if not has_action and _repeat_of(message, type, tag, maxf(duration, reading_seconds(message))):
		return
	var toast = _create_toast(message, type, icon)
	toast.set_meta(TAG_META, tag)
	toast.set_meta(MESSAGE_META, message)
	toast.set_meta(TYPE_META, type)
	if has_action:
		var button := _action_button(action_label, action_icon)
		button.pressed.connect(_on_action_pressed.bind(toast, action))
		toast.get_child(0).add_child(button)
	toast_vbox.add_child(toast)
	_fit_one_line(toast, max_width(type, has_action))
	_active_toasts.append(toast)

	# Limit visible toasts
	while _active_toasts.size() > MAX_VISIBLE_TOASTS:
		var oldest: Control = _active_toasts[_eviction_index()]
		if oldest and is_instance_valid(oldest):
			_dismiss_toast(oldest, true)
		else:
			_active_toasts.erase(oldest)

	# Animate in
	_animate_toast_in(toast, type)

	# Schedule dismissal on a timer the toast owns, so it goes with the toast when that is
	# freed early (the oldest past MAX_VISIBLE_TOASTS) and holds while the pointer rests on
	# it: a toast being read or aimed at (its Undo) never leaves under the pointer.
	if duration > 0:
		var timer := Timer.new()
		timer.name = "DismissTimer"
		timer.one_shot = true
		timer.wait_time = maxf(duration, reading_seconds(message))
		toast.add_child(timer)
		timer.timeout.connect(_dismiss_toast.bind(toast, false))
		timer.start()
		toast.mouse_entered.connect(timer.set_paused.bind(true))
		toast.mouse_exited.connect(_resume_after_hover.bind(timer))


## The index of the toast that makes room for a new one: the oldest that is not an error (an
## error says what failed and how to recover, and a run of good news must not push it off
## screen unread), else the oldest of all.
func _eviction_index() -> int:
	for i in _active_toasts.size():
		var toast: Control = _active_toasts[i]
		if not is_instance_valid(toast) or toast.get_meta(TYPE_META, -1) != ToastType.ERROR:
			return i
	return 0


## Whether a toast with this `message` and `type` is already up (an action toast never joins):
## if so it counts one more ("x2") and restarts its timer for `seconds`, and this returns true.
func _repeat_of(message: String, type: ToastType, tag: StringName, seconds: float) -> bool:
	for toast in _active_toasts:
		if not is_instance_valid(toast) or toast.is_queued_for_deletion():
			continue
		if toast.get_meta(MESSAGE_META, "") != message or toast.get_meta(TYPE_META, -1) != type:
			continue
		if toast.get_meta(TAG_META, &"") != tag:
			continue
		var count: int = int(toast.get_meta(COUNT_META, 1)) + 1
		toast.set_meta(COUNT_META, count)
		var badge := toast.get_child(0).get_node_or_null("Count") as Label
		if badge == null:
			badge = Label.new()
			badge.name = "Count"
			badge.theme_type_variation = &"Caption"
			badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			toast.get_child(0).add_child(badge)
		badge.text = "x%d" % count
		var timer := toast.get_node_or_null("DismissTimer") as Timer
		if timer != null:
			timer.start(seconds)
		return true
	return false


## The pointer left a toast: it stays a moment longer, then goes.
func _resume_after_hover(timer: Timer) -> void:
	if not is_instance_valid(timer):
		return
	timer.paused = false
	timer.start(maxf(timer.time_left, HOVER_GRACE_S))


## Fades out every toast shown with `tag` (a toast whose subject changed under it: a removal
## toast whose piece came back some other way). Nothing to do for a tag no toast wears.
func dismiss_tag(tag: StringName) -> void:
	if tag == &"":
		return
	for toast in _active_toasts.duplicate():
		if is_instance_valid(toast) and toast.get_meta(TAG_META, &"") == tag:
			_dismiss_toast(toast, false)


## How long `message` takes to read: LOOK_S, then WORDS_PER_S words a second. Pure.
static func reading_seconds(message: String) -> float:
	return LOOK_S + message.split(" ", false).size() / WORDS_PER_S


## The widest a toast of `type` grows before its words wrap: ERROR_WIDTH for an error,
## ACTION_MAX_WIDTH beside an action, WIDTH otherwise. Pure.
static func max_width(type: ToastType, has_action: bool) -> float:
	if has_action:
		return ACTION_MAX_WIDTH
	return ERROR_WIDTH if type == ToastType.ERROR else WIDTH


## A toast's chip: its icon (`icon`, or the kind's own when ""), then its words.
func _create_toast(message: String, type: ToastType, icon: String = "") -> Control:
	var panel = PanelContainer.new()
	panel.theme_type_variation = &"Toast"
	panel.custom_minimum_size = Vector2(WIDTH, 0)
	# The column is as wide as its widest toast (the box shrinks to it, centred) and each
	# toast fills it, so a stack's edges align instead of stepping in and out.
	panel.size_flags_horizontal = Control.SIZE_FILL

	var hbox = HBoxContainer.new()
	hbox.theme_type_variation = &"BoxContainerSpaced"
	panel.add_child(hbox)
	# The roles resolve against the glass theme the container carries.
	hbox.add_child(kind_icon(type, toast_vbox, icon))

	var label = Label.new()
	label.text = message
	label.theme_type_variation = "Body"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hbox.add_child(label)

	return panel


## The icon that names a toast kind, tinted with its role as resolved against `themed` (a
## node under the glass theme); `icon_name` (a Tabler icon) stands in for the kind's own
## picture when given. The disconnect banner wears the warning one.
static func kind_icon(type: ToastType, themed: Control, icon_name: String = "") -> TextureRect:
	var kind: Array = KINDS.get(type, KINDS[ToastType.INFO])
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.texture = IconButton.load_icon(icon_name if icon_name != "" else String(kind[0]))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.self_modulate = ThemeColors.of(themed, kind[1])
	return icon


## Sizes `toast` (in the tree, so its fonts resolve) to its words' one-line width beside the
## icon and any action, up to `limit_px`; past that they wrap.
func _fit_one_line(toast: Control, limit_px: float) -> void:
	var label := toast.get_child(0).get_child(1) as Label
	toast.custom_minimum_size.x = 0.0
	# The chip with its words wrapped to nothing, plus the words' one-line width (2 px spare,
	# so the line does not break on rounding).
	var rest := toast.get_combined_minimum_size().x
	var font := label.get_theme_font(&"font")
	var font_size := label.get_theme_font_size(&"font_size")
	var words := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	toast.custom_minimum_size.x = minf(ceilf(rest + words) + 2.0, limit_px)


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
	# Fade and a short slide on the offset transform, which does not re-sort the column.
	# Reduce motion keeps the fade (short) and drops the slide (UI_TASTE M5).
	toast.modulate.a = 0.0
	toast.offset_transform_enabled = true
	toast.offset_transform_position = Vector2(0.0, UiMotion.travel(SLIDE_PX, 0.0))

	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(UiMotion.ARRIVE_TRANS)
	var seconds := UiMotion.fade_s(UiMotion.PANEL_IN_S)
	tween.tween_property(toast, "modulate:a", 1.0, seconds)
	tween.tween_property(toast, "offset_transform_position", Vector2.ZERO, seconds)

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
	if idx < 0 and not immediate:
		return  # already leaving: its timer fired again after dismiss_tag or an Undo
	if idx >= 0:
		_active_toasts.remove_at(idx)

	if immediate:
		toast.queue_free()
		return

	# The chip no longer counts as a target while it fades (a press on its Undo would land
	# on nothing), and leaves faster than it arrived (UI_TASTE M1).
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(UiMotion.EXIT_TRANS)
	var seconds := UiMotion.fade_s(UiMotion.PANEL_OUT_S)
	tween.tween_property(toast, "modulate:a", 0.0, seconds)
	if not UiMotion.reduced():
		toast.offset_transform_enabled = true
		tween.tween_property(toast, "offset_transform_position", Vector2(0.0, SLIDE_PX * 0.5), seconds)
	tween.finished.connect(toast.queue_free)
