extends CanvasLayer
class_name InputHints

## Contextual input hints displayed at the bottom of the screen.
##
## Shows current available actions based on context.
## Automatically updates based on game state.

@onready var hints_container: HBoxContainer = %HBoxContainer

var _current_hints: Array[Dictionary] = []
var _tween: Tween


func _ready() -> void:
	# Start hidden
	$MarginContainer.modulate.a = 0.0


## Set hints to display. Each hint is a dictionary with "key" and "action".
## Example: [{"key": "ESC", "action": "Pause"}, {"key": "E", "action": "Interact"}]
func set_hints(hints: Array) -> void:
	if _are_hints_equal(hints):
		return

	_current_hints.clear()
	for hint in hints:
		_current_hints.append(hint)

	_rebuild_hints()


## Clear all hints
func clear_hints() -> void:
	_current_hints.clear()
	_animate_out()


## Add a single hint
func add_hint(key: String, action: String) -> void:
	for hint in _current_hints:
		if hint.key == key:
			hint.action = action
			_rebuild_hints()
			return

	_current_hints.append({"key": key, "action": action})
	_rebuild_hints()


## Remove a hint by key
func remove_hint(key: String) -> void:
	for i in range(_current_hints.size() - 1, -1, -1):
		if _current_hints[i].key == key:
			_current_hints.remove_at(i)
	_rebuild_hints()


func _are_hints_equal(new_hints: Array) -> bool:
	if new_hints.size() != _current_hints.size():
		return false

	for i in range(new_hints.size()):
		if (
			new_hints[i].key != _current_hints[i].key
			or new_hints[i].action != _current_hints[i].action
		):
			return false

	return true


func _rebuild_hints() -> void:
	# Clear existing
	for child in hints_container.get_children():
		child.queue_free()

	if _current_hints.is_empty():
		_animate_out()
		return

	# Build new hints
	for hint in _current_hints:
		var hint_widget = _create_hint_widget(hint.key, hint.action)
		hints_container.add_child(hint_widget)

	_animate_in()


func _create_hint_widget(key: String, action: String) -> Control:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)

	# Key badge
	var key_panel = PanelContainer.new()
	var key_style = StyleBoxFlat.new()
	key_style.bg_color = Color(0.24, 0.17, 0.24, 0.9)
	key_style.corner_radius_top_left = 4
	key_style.corner_radius_top_right = 4
	key_style.corner_radius_bottom_left = 4
	key_style.corner_radius_bottom_right = 4
	key_style.content_margin_left = 8
	key_style.content_margin_right = 8
	key_style.content_margin_top = 4
	key_style.content_margin_bottom = 4
	key_panel.add_theme_stylebox_override("panel", key_style)

	var key_label = Label.new()
	key_label.text = key
	key_label.theme_type_variation = "Body"
	key_label.add_theme_color_override("font_color", Color(0.86, 0.57, 0.29))
	key_panel.add_child(key_label)
	hbox.add_child(key_panel)

	# Action label
	var action_label = Label.new()
	action_label.text = action
	action_label.theme_type_variation = "Caption"
	hbox.add_child(action_label)

	return hbox


func _animate_in() -> void:
	if _tween:
		_tween.kill()

	# Slide up from below + fade in
	var container := $MarginContainer
	container.position.y += 12
	var target_y: float = container.position.y - 12

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(container, "modulate:a", 1.0, Constants.ANIM_FADE_IN_DURATION)
	_tween.tween_property(container, "position:y", target_y, 0.25)


func _animate_out() -> void:
	if _tween:
		_tween.kill()

	# Slide down + fade out
	var container := $MarginContainer

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(container, "modulate:a", 0.0, Constants.ANIM_FADE_OUT_DURATION)
	_tween.tween_property(
		container, "position:y", container.position.y + 12, Constants.ANIM_FADE_OUT_DURATION
	)
