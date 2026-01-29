extends CanvasLayer
class_name TransitionOverlay

## Screen transition overlay for smooth state changes.
##
## Provides fade in/out transitions between scenes or states.
## Can optionally show a loading indicator during the transition.

signal fade_out_complete
signal fade_in_complete
signal transition_complete

@onready var color_rect: ColorRect = %ColorRect

var _tween: Tween
var _is_transitioning := false

# Configuration
var fade_duration := 0.3
var fade_color := Color(0.102, 0.071, 0.102, 1.0) # Dark theme background


func _ready() -> void:
	color_rect.color = fade_color
	color_rect.modulate.a = 0.0
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fade to black (or configured color)
func fade_out(duration: float = -1.0) -> void:
	if duration < 0:
		duration = fade_duration
	
	_is_transitioning = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "modulate:a", 1.0, duration)
	
	await _tween.finished
	fade_out_complete.emit()


## Fade from black back to normal
func fade_in(duration: float = -1.0) -> void:
	if duration < 0:
		duration = fade_duration
	
	if _tween:
		_tween.kill()
	
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "modulate:a", 0.0, duration)
	
	await _tween.finished
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
	fade_in_complete.emit()
	transition_complete.emit()


## Perform a full transition: fade out, call middle_callback, fade in
func transition(middle_callback: Callable, fade_out_duration: float = -1.0, fade_in_duration: float = -1.0) -> void:
	await fade_out(fade_out_duration)
	
	if middle_callback.is_valid():
		middle_callback.call()
	
	# Small delay to ensure scene changes are processed
	await get_tree().process_frame
	
	await fade_in(fade_in_duration)


## Check if currently transitioning
func is_transitioning() -> bool:
	return _is_transitioning


## Start with screen faded out (for initial load)
func start_faded_out() -> void:
	color_rect.modulate.a = 1.0
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_transitioning = true
