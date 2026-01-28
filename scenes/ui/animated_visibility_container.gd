extends Control
class_name AnimatedVisibilityContainer

## Base class for UI containers with smooth show/hide animations
## Extend this class and override animation properties to customize behavior

# Animation configuration - override these in child classes for different effects
@export_group("Animation Settings")
@export var fade_in_duration: float = 0.3
@export var fade_out_duration: float = 0.2
@export var scale_in_from: Vector2 = Vector2(0.8, 0.8)
@export var scale_out_to: Vector2 = Vector2(0.9, 0.9)
@export var ease_in_type: Tween.EaseType = Tween.EASE_OUT
@export var ease_out_type: Tween.EaseType = Tween.EASE_IN
@export var trans_in_type: Tween.TransitionType = Tween.TRANS_BACK
@export var trans_out_type: Tween.TransitionType = Tween.TRANS_CUBIC
@export var start_hidden: bool = true

var tween: Tween
var _is_animating: bool = false

func _ready() -> void:
	if start_hidden:
		modulate.a = 0
		hide()
	_on_ready()

# Override this in child classes for custom initialization
func _on_ready() -> void:
	pass

## Smoothly show the container with animation
func animate_in() -> void:
	if tween:
		tween.kill()

	_is_animating = true
	show()
	
	# Set pivot to center so scale animates from center
	pivot_offset = size / 2

	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(ease_in_type)
	tween.set_trans(trans_in_type)

	# Animate opacity
	tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)

	# Animate scale
	scale = scale_in_from
	tween.tween_property(self, "scale", Vector2.ONE, fade_in_duration)

	# Callback when animation completes
	tween.finished.connect(_on_animate_in_finished, CONNECT_ONE_SHOT)

	_on_before_animate_in()

## Smoothly hide the container with animation
func animate_out() -> void:
	if tween:
		tween.kill()

	_is_animating = true
	
	# Set pivot to center so scale animates from center
	pivot_offset = size / 2

	tween = create_tween()
	tween.set_parallel(true)
	tween.set_ease(ease_out_type)
	tween.set_trans(trans_out_type)

	# Animate opacity
	tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)

	# Animate scale
	tween.tween_property(self, "scale", scale_out_to, fade_out_duration)

	# Hide after animation completes
	tween.finished.connect(_on_animate_out_finished, CONNECT_ONE_SHOT)

	_on_before_animate_out()

## Toggle visibility with animation
func toggle_animated(show_container: bool) -> void:
	if show_container:
		animate_in()
	else:
		animate_out()

## Check if currently animating
func is_animating() -> bool:
	return _is_animating

# Callbacks for child classes to override
func _on_before_animate_in() -> void:
	pass

func _on_after_animate_in() -> void:
	pass

func _on_before_animate_out() -> void:
	pass

func _on_after_animate_out() -> void:
	pass

func _on_animate_in_finished() -> void:
	_is_animating = false
	_on_after_animate_in()

func _on_animate_out_finished() -> void:
	hide()
	_is_animating = false
	_on_after_animate_out()
