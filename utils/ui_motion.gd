class_name UiMotion
extends RefCounted

## Shared tween helpers for the UI primitives. Every caller owns one Tween
## member and passes it in, so a new animation always replaces the previous
## one and nothing accumulates.

## How far below its resting place a staggered item starts.
const ENTRANCE_OFFSET_PX := 12.0


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


## Visible Control children of [param parent], in tree order — the usual target
## list for stagger_in().
static func visible_children(parent: Node) -> Array[Control]:
	var out: Array[Control] = []
	for child in parent.get_children():
		if child is Control and (child as Control).visible:
			out.append(child as Control)
	return out


## Fade and lift [param targets] in, one after another: each starts at alpha 0
## and ENTRANCE_OFFSET_PX below its resting y, then tweens back over
## Constants.ANIM_ENTRANCE with Constants.ANIM_ENTRANCE_STAGGER between items.
## Waits two process frames first so every container has settled and the
## captured positions are final — capturing early leaves items tweening toward
## a layout that no longer exists. Tweens are created on [param owner] so they
## die with the screen. Re-checks [param owner] after each await: unlike an
## awaited method on the node itself, this coroutine's resumption is not tied
## to owner's lifetime, so a screen freed mid-wait (a test's autofree, a fast
## screen swap) must be caught before the next call on it rather than only once
## at the end.
static func stagger_in(targets: Array[Control], owner: Node) -> void:
	for control in targets:
		control.modulate.a = 0.0
	await owner.get_tree().process_frame
	if not is_instance_valid(owner):
		return
	await owner.get_tree().process_frame
	if not is_instance_valid(owner):
		return
	for i in range(targets.size()):
		var control := targets[i]
		if not is_instance_valid(control):
			continue
		var target_y := control.position.y
		control.position.y = target_y + ENTRANCE_OFFSET_PX
		var tween := owner.create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		var delay := i * Constants.ANIM_ENTRANCE_STAGGER
		tween.tween_property(control, "modulate:a", 1.0, Constants.ANIM_ENTRANCE).set_delay(delay)
		tween.tween_property(control, "position:y", target_y, Constants.ANIM_ENTRANCE).set_delay(
			delay
		)
