class_name DragMath
extends RefCounted

## The pure arithmetic of dragging a token, kept apart from the DragController node so each
## rule has one place and a unit test that needs no scene: when a press has moved far enough
## to be a drag, where a drag aims on the ground, how a held body eases toward its aim, where it
## lands on release, and how hard the screen edge pulls the camera.
##
## Nothing here reads the scene tree, the viewport or the clock.


## True when `position` is at least `threshold` screen pixels from where the button went down.
## The comparison is >=, so a move of exactly the threshold begins the drag.
static func threshold_reached(anchor: Vector2, position: Vector2, threshold: float) -> bool:
	return position.distance_to(anchor) >= threshold


## The ground point a drag aims at for cursor hit `hit`: snapped to the grid cell centre on XZ
## when `snap` (ScaleUtils.snap_to_grid keeps the hit's Y), then, when `resolver` is valid and
## finds ground there (not Vector3.INF), at that ground's height. A resolver miss (snapped off
## the terrain's edge) keeps the hit height, as a browser drop does.
static func resolve_target_ground(
	hit: Vector3, snap: bool, cell_size: float, origin: Vector2, resolver: Callable
) -> Vector3:
	var point := ScaleUtils.snap_to_grid(hit, cell_size, origin) if snap else hit
	if resolver.is_valid():
		var ground: Vector3 = resolver.call(point)
		if ground != Vector3.INF:
			point.y = ground.y
	return point


## The point a held body is steered to: the `ground` target lifted by the dragged object's own
## height offset (half its height, plus the pickup spring) and by the wheel's height steps.
static func lifted_target(ground: Vector3, object_offset: float, wheel_offset: float) -> Vector3:
	return ground + Vector3(0.0, object_offset + wheel_offset, 0.0)


## One frame of the held body's follow: `current` eased toward `target` with a frame-rate
## independent exponential (the same fraction of the remaining gap per unit time at any fps).
static func eased(current: Vector3, target: Vector3, speed: float, delta: float) -> Vector3:
	return current.lerp(target, 1.0 - exp(-speed * delta))


## Where the body is put on release. XZ is the exact (possibly grid-snapped) target rather than
## wherever the easing had got to. Y is left to the token's settle tween, except with
## `lift_to_target` (authored terrain): a body still rising toward a higher tier is lifted to
## the target height first, so it never settles from inside the tier's cliff.
static func landing(body: Vector3, target: Vector3, lift_to_target: bool) -> Vector3:
	var landed := Vector3(target.x, body.y, target.z)
	if lift_to_target:
		landed.y = maxf(body.y, target.y)
	return landed


## The camera pan a cursor near the screen edge asks for: each axis runs from 0 at `margin`
## pixels in from the edge to +-1 at the edge (x: -1 left, +1 right; y: -1 top, +1 bottom).
static func edge_pan(mouse: Vector2, viewport_size: Vector2, margin: float) -> Vector2:
	var pan := Vector2.ZERO
	if mouse.x < margin:
		pan.x = -(1.0 - mouse.x / margin)
	elif mouse.x > viewport_size.x - margin:
		pan.x = 1.0 - (viewport_size.x - mouse.x) / margin
	if mouse.y < margin:
		pan.y = -(1.0 - mouse.y / margin)
	elif mouse.y > viewport_size.y - margin:
		pan.y = 1.0 - (viewport_size.y - mouse.y) / margin
	return pan
