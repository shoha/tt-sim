class_name UiMotion
extends RefCounted

## Shared tween helpers for the UI primitives. Every caller owns one Tween
## member and passes it in, so a new animation always replaces the previous
## one and nothing accumulates.


## Tween [param control]'s offset_transform_scale to [param target]. Kills
## [param previous] first. Returns the new tween for the caller to store.
static func scale_to(
	control: Control, previous: Tween, target: Vector2, duration: float, trans: Tween.TransitionType
) -> Tween:
	if previous and previous.is_valid():
		previous.kill()
	control.offset_transform_enabled = true
	var tween := control.create_tween()
	tween.set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "offset_transform_scale", target, duration)
	return tween
