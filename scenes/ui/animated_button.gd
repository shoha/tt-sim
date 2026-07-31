class_name AnimatedButton
extends Button

## Button subclass with a subtle press scale animation for tactile feedback.
##
## On press, the button scales down slightly (0.95x) from its center, then
## bounces back on release. This gives every button a physical "click" feel.
##
## Usage:
##   - Use AnimatedButton instead of Button in scenes and scripts.
##   - If a specific button should NOT animate, use a plain Button instead.

const PRESS_SCALE := Vector2(0.95, 0.95)
const PRESS_DURATION := 0.05
const RELEASE_DURATION := 0.05

var _press_tween: Tween = null


func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _on_button_down() -> void:
	pivot_offset = size / 2
	_kill_press_tween()
	_press_tween = create_tween()
	(
		_press_tween
		. tween_property(self, "scale", PRESS_SCALE, PRESS_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


func _on_button_up() -> void:
	pivot_offset = size / 2
	_kill_press_tween()
	_press_tween = create_tween()
	(
		_press_tween
		. tween_property(self, "scale", Vector2.ONE, RELEASE_DURATION)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)


func _kill_press_tween() -> void:
	if _press_tween and _press_tween.is_valid():
		_press_tween.kill()
	_press_tween = null
