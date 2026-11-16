class_name UiMotion
extends RefCounted

## The one place UI motion is decided (docs/UI_TASTE.md M1-M6, 2026-11-15 section): the
## duration bands, the easing, the stagger, the Reduce motion switch, and shared tween helpers
## for the UI primitives. Constants.ANIM_* are aliases of the tokens here, so a number is
## defined once. Every caller owns one Tween member and passes it in, so a new animation always
## replaces the previous one and nothing accumulates.
##
## The principles, which tests/unit/test_ui_motion.gd holds:
## - Duration bands: feedback (hover, press) 90 to 120 ms, panels and menus 160 to 240 ms,
##   a large transition up to 400 ms and only for one authored moment; an exit is never slower
##   than its entrance.
## - Ease out for arrivals, ease in for exits, TRANS_CUBIC or TRANS_QUART; no bounce, elastic or
##   back on a functional control. A gentle overshoot (CELEBRATE_TRANS) is for a celebration only.
## - Lists stagger by STAGGER_S (20 to 30 ms) and the whole entrance stays under STAGGER_CAP_S.
## - Input is never blocked while a tween runs; a panel's controls are live from its first frame.
## - Animate transform and opacity only (offset_transform_*, scale on a panel, modulate), never
##   position or size of a container child, so nothing relayouts.
## - Reduce motion (the OS flag or Settings > Graphics): no scale, lift, slide or stagger, only
##   short fades of FADE_ONLY_S, and press and hover keep their colour change.

## Feedback: hover and press on a control (90 to 120 ms).
const FEEDBACK_IN_S := 0.12
const FEEDBACK_OUT_S := 0.10
const PRESS_S := 0.09
## State: a pane swap, a foldout, a tile selection (160 ms).
const STATE_S := 0.16
## Panels and menus: a sheet or drawer entering, leaving (160 to 240 ms).
const PANEL_IN_S := 0.22
const PANEL_OUT_S := 0.16
## A menu body's rows arriving, and the soft glide of a large thumbnail.
const ENTRANCE_S := 0.24
const SOFT_IN_S := 0.24
const SOFT_OUT_S := 0.20
## The longest any large transition may take.
const LARGE_MAX_S := 0.40
## The gap between list items and the cap on a whole staggered entrance (items past the cap
## share the remaining time).
const STAGGER_S := 0.03
const STAGGER_CAP_S := 0.36
## Under Reduce motion every fade is this long and nothing travels.
const FADE_ONLY_S := 0.12

## The arrival and exit curves: ease out in, ease in out, both gentle.
const ARRIVE_TRANS := Tween.TRANS_QUART
const EXIT_TRANS := Tween.TRANS_CUBIC
## The only curve with overshoot, for a celebratory moment (never a functional control).
const CELEBRATE_TRANS := Tween.TRANS_BACK

## Where a panel starts its scale, and where it ends going out (a sheet breathes in, it does
## not pop).
const PANEL_SCALE_FROM := 0.96
const PANEL_SCALE_TO := 0.98

## How far below its resting place a staggered item starts.
const ENTRANCE_OFFSET_PX := 12.0

## The Settings > Graphics Reduce motion choice, applied at start-up (UIManager) and when the
## row is toggled. The OS flag is read live in reduced().
static var user_reduce: bool = false


## Whether motion should be fewer and gentler (docs/UI_TASTE.md M5): the Reduce motion setting,
## or the operating system's reduce-animation flag where the platform reports one (-1, unknown,
## reads as no).
static func reduced() -> bool:
	return user_reduce or DisplayServer.accessibility_should_reduce_animation() == 1


## [param seconds], or FADE_ONLY_S under Reduce motion when that is shorter: the duration to
## give a fade that stays when movement goes.
static func fade_s(seconds: float) -> float:
	return minf(seconds, FADE_ONLY_S) if reduced() else seconds


## [param from] (a scale or a pixel offset) as it should start: unchanged, or the rest value
## [param rest] under Reduce motion, so nothing travels.
static func travel(from: Variant, rest: Variant) -> Variant:
	return rest if reduced() else from


## The gap between neighbours in a staggered list of [param count] items: STAGGER_S,
## trimmed so the whole entrance (the last item's delay plus [param duration]) stays under
## STAGGER_CAP_S. Zero under Reduce motion.
static func stagger_step(count: int, duration: float = ENTRANCE_S) -> float:
	if reduced() or count < 2:
		return 0.0
	return minf(STAGGER_S, maxf(0.0, STAGGER_CAP_S - duration) / float(count - 1))


## Tween [param control]'s offset_transform_scale to [param target]. Kills
## [param previous] first. Returns the new tween for the caller to store. Under Reduce motion
## the scale is not animated (it stays at rest, colour changes carry the feedback) and the
## result is null.
static func scale_to(
	control: Control, previous: Tween, target: Vector2, duration: float, trans: Tween.TransitionType
) -> Tween:
	if previous and previous.is_valid():
		previous.kill()
	if reduced():
		control.offset_transform_scale = Vector2.ONE
		return null
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
## and ENTRANCE_OFFSET_PX below its resting place, then tweens back over ENTRANCE_S with
## stagger_step() between items (the whole entrance under STAGGER_CAP_S). The lift is the
## control's offset transform, so a layout change mid-entrance (a window resize, which also
## changes the Interface size) never leaves it tweening toward a stale position. Under Reduce
## motion the rows only fade, together, over FADE_ONLY_S.
## Waits two process frames first so every container has settled before the
## rows show. Tweens are created on [param owner] so they
## die with the screen. Re-checks [param owner] after each await: unlike an
## awaited method on the node itself, this coroutine's resumption is not tied
## to owner's lifetime, so a screen freed mid-wait (a test's autofree, a fast
## screen swap) must be caught before the next call on it rather than only once
## at the end. The alpha reset
## happens synchronously, before the first await, so call this in the same run
## that makes the parent visible (AnimatedCanvasLayerPanel does this through
## _stagger_targets()) — never after a fade that already showed the targets, or
## they will flash at full alpha and then snap back to zero.
static func stagger_in(targets: Array[Control], owner: Node) -> void:
	for control in targets:
		control.modulate.a = 0.0
	await owner.get_tree().process_frame
	if not is_instance_valid(owner):
		return
	await owner.get_tree().process_frame
	if not is_instance_valid(owner):
		return
	var reduce := reduced()
	var step := stagger_step(targets.size())
	for i in range(targets.size()):
		var control := targets[i]
		if not is_instance_valid(control):
			continue
		var tween := owner.create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(ARRIVE_TRANS)
		var delay := i * step
		var duration := fade_s(ENTRANCE_S)
		tween.tween_property(control, "modulate:a", 1.0, duration).set_delay(delay)
		if not reduce:
			# The lift rides the control's offset transform, so its container never relayouts.
			control.offset_transform_enabled = true
			control.offset_transform_position = Vector2(0.0, ENTRANCE_OFFSET_PX)
			tween.tween_property(control, "offset_transform_position", Vector2.ZERO, duration).set_delay(
				delay
			)
