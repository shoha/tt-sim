extends CanvasLayer
class_name TransitionOverlay

## Screen transition overlay for smooth state changes.
##
## Provides fade in/out transitions between scenes or states.
## Can optionally show a loading indicator during the transition.
##
## Supports multiple transition styles:
##   FADE    - standard fade to/from black (default)
##   IRIS    - circular iris wipe (closing circle out, opening circle in)
##   CURTAIN - vertical slide down (out) / up (in)

signal fade_out_complete
signal fade_in_complete
signal transition_complete

enum TransitionType { FADE, IRIS, CURTAIN }

@onready var color_rect: ColorRect = %ColorRect

var _tween: Tween
var _is_transitioning := false
var _current_type: int = TransitionType.FADE

# Iris wipe shader material (created lazily)
var _iris_material: ShaderMaterial = null

# Configuration
var fade_duration := 0.3
var fade_color := Color(0.102, 0.071, 0.102, 1.0)  # Dark theme background


func _ready() -> void:
	color_rect.color = fade_color
	color_rect.modulate.a = 0.0
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Set the transition type for the next transition.
## Call before fade_out/fade_in/transition.
func set_transition_type(type: int) -> void:
	_current_type = type


## Fade to black (or configured color) using the current transition type.
func fade_out(duration: float = -1.0) -> void:
	if duration < 0:
		duration = fade_duration

	_is_transitioning = true
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP

	if _tween:
		_tween.kill()

	match _current_type:
		TransitionType.IRIS:
			_fade_out_iris(duration)
		TransitionType.CURTAIN:
			_fade_out_curtain(duration)
		_:
			_fade_out_fade(duration)

	AudioManager.play_transition()
	await _tween.finished
	if not is_instance_valid(self):
		return
	fade_out_complete.emit()


## Fade from black back to normal using the current transition type.
func fade_in(duration: float = -1.0) -> void:
	if duration < 0:
		duration = fade_duration

	if _tween:
		_tween.kill()

	match _current_type:
		TransitionType.IRIS:
			_fade_in_iris(duration)
		TransitionType.CURTAIN:
			_fade_in_curtain(duration)
		_:
			_fade_in_fade(duration)

	AudioManager.play_transition()
	await _tween.finished
	if not is_instance_valid(self):
		return
	_cleanup_transition()
	color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_is_transitioning = false
	fade_in_complete.emit()
	transition_complete.emit()


## Perform a full transition: fade out, call middle_callback, fade in
func transition(
	middle_callback: Callable,
	fade_out_duration: float = -1.0,
	fade_in_duration: float = -1.0,
) -> void:
	await fade_out(fade_out_duration)
	if not is_instance_valid(self):
		return

	if middle_callback.is_valid():
		middle_callback.call()

	# Small delay to ensure scene changes are processed
	await get_tree().process_frame
	if not is_instance_valid(self):
		return

	await fade_in(fade_in_duration)


## Check if currently transitioning
func is_transitioning() -> bool:
	return _is_transitioning


## Start with screen faded out (for initial load)
func start_faded_out() -> void:
	color_rect.modulate.a = 1.0
	color_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_is_transitioning = true


# ---------------------------------------------------------------------------
# FADE (default)
# ---------------------------------------------------------------------------


func _fade_out_fade(duration: float) -> void:
	color_rect.material = null  # Ensure no shader is applied
	color_rect.modulate.a = 0.0
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "modulate:a", 1.0, duration)


func _fade_in_fade(duration: float) -> void:
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "modulate:a", 0.0, duration)


# ---------------------------------------------------------------------------
# IRIS WIPE (circle shrink out, circle grow in)
# ---------------------------------------------------------------------------


func _get_iris_material() -> ShaderMaterial:
	if not _iris_material:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.102, 0.071, 0.102, 1.0);

void fragment() {
	vec2 center = vec2(0.5, 0.5);
	float dist = distance(UV, center);
	// Max radius is ~0.707 (corner to center)
	float radius = (1.0 - progress) * 0.75;
	float edge = smoothstep(radius, radius + 0.02, dist);
	COLOR = vec4(color.rgb, edge);
}
"""
		_iris_material = ShaderMaterial.new()
		_iris_material.shader = shader
		_iris_material.set_shader_parameter("color", fade_color)
	return _iris_material


func _fade_out_iris(duration: float) -> void:
	var mat := _get_iris_material()
	mat.set_shader_parameter("progress", 0.0)
	color_rect.material = mat
	color_rect.modulate.a = 1.0

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 0.0, 1.0, duration)


func _fade_in_iris(duration: float) -> void:
	var mat := _get_iris_material()
	mat.set_shader_parameter("progress", 1.0)

	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_method(func(v: float): mat.set_shader_parameter("progress", v), 1.0, 0.0, duration)


# ---------------------------------------------------------------------------
# CURTAIN (slide down to cover, slide up to reveal)
# ---------------------------------------------------------------------------


func _fade_out_curtain(duration: float) -> void:
	color_rect.material = null
	color_rect.modulate.a = 1.0
	# Start above the screen, slide down to cover
	color_rect.position.y = -color_rect.size.y
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "position:y", 0.0, duration)


func _fade_in_curtain(duration: float) -> void:
	# Slide down off the bottom of the screen to reveal
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_property(color_rect, "position:y", color_rect.size.y, duration)


# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------


func _cleanup_transition() -> void:
	# Reset state after any transition type
	color_rect.material = null
	color_rect.position = Vector2.ZERO
	color_rect.modulate.a = 0.0
