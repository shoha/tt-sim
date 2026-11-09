class_name ViewGround
extends RefCounted

## Where a view ray lands on the ground at the eye, for the play tools that need "the ground
## under the pointer" or "the ground the view is centred on" (the token drag, the sun gizmo, a
## new token's landing point, the grid's fade centre).
##
## The orbit view is orthographic and steep: a ray through any pixel meets the y = 0 plane within
## the picture, so those tools intersect a plane. At the eye (a perspective camera 1.6 m up,
## looking near the horizon) that fails three ways: the screen-centre ray meets the ground at the
## horizon or never, a grazing ray is metres of ground per pixel, and a ray toward a token behind
## a house hits the facade first. So at the eye:
##   - a pointer ray marches the ground height field (`march`), so the first ground it meets is
##     the terrain and never a wall, roof or trunk, and a hill in the way is hit as it looks;
##   - a ray flatter than EyeRig.MIN_GROUND_RAY_DEG below the horizon finds no ground (a drag
##     target stays where it was);
##   - "the view centre" is a point AHEAD_M ahead of the eye on the ground (`eye_point`).
##
## All of it is pure maths on a ray and a height function (`func(world_xz: Vector2) -> float`),
## so it is tested without a camera; `eye_centre` is the one wrapper that reads a GameMap.

## How far ahead of the eye the view centre is held on the ground, in metres.
const AHEAD_M := 5.0
## The longest pointer ray marched, in metres (the eye's far plane is 600).
const MARCH_MAX_M := 300.0
## The march step: a fraction of the distance travelled, held between these bounds in metres.
const MARCH_STEP_FRACTION := 0.02
const MARCH_MIN_STEP_M := 0.25
const MARCH_MAX_STEP_M := 3.0
## Bisection steps that refine the crossing found by the march.
const BISECTIONS := 10


## Whether a ray along `dir` is too flat to name a ground point: flatter than
## EyeRig.MIN_GROUND_RAY_DEG below the horizon (a grazing, horizontal or upward ray).
static func too_flat(dir: Vector3) -> bool:
	return dir.normalized().y > -sin(deg_to_rad(EyeRig.MIN_GROUND_RAY_DEG))


## Where the ray from `origin` along `dir` first meets the ground `height_at` describes, or null:
## the ray is too flat, starts below the ground, or leaves `max_distance` metres behind. The step
## grows with the distance so a near hit is found finely and a far one cheaply, then the crossing
## is bisected. A ridge in the way is the hit, as it looks from the eye.
static func march(
	origin: Vector3, dir: Vector3, height_at: Callable, max_distance: float = MARCH_MAX_M
) -> Variant:
	var d := dir.normalized()
	if too_flat(d) or not height_at.is_valid():
		return null
	if origin.y <= float(height_at.call(Vector2(origin.x, origin.z))):
		return null
	var before := 0.0
	var t := 0.0
	while t < max_distance:
		t = minf(
			t + clampf(t * MARCH_STEP_FRACTION, MARCH_MIN_STEP_M, MARCH_MAX_STEP_M), max_distance
		)
		if _below(origin, d, t, height_at):
			var low := before
			var high := t
			for _i in BISECTIONS:
				var mid := (low + high) * 0.5
				if _below(origin, d, mid, height_at):
					high = mid
				else:
					low = mid
			return origin + d * high
		before = t
	return null


static func _below(origin: Vector3, d: Vector3, t: float, height_at: Callable) -> bool:
	var p := origin + d * t
	return p.y <= float(height_at.call(Vector2(p.x, p.z)))


## The ground point the view is centred on at the eye: where the ray (`origin`, `dir`: the
## screen-centre ray) meets the ground when it looks down far enough and lands within `ahead`
## metres, else the point `ahead` metres along the ray's flat heading. Always defined. The height
## is `height_at` there, or `plane_y` without a height function. Pure.
static func eye_point(
	origin: Vector3,
	dir: Vector3,
	plane_y: float,
	height_at: Callable = Callable(),
	ahead: float = AHEAD_M
) -> Vector3:
	var d := dir.normalized()
	var has_field := height_at.is_valid()
	var base_y := float(height_at.call(Vector2(origin.x, origin.z))) if has_field else plane_y
	var flat := Vector2(d.x, d.z)
	var distance := ahead
	if not too_flat(d):
		var reach := (origin.y - base_y) / -d.y * flat.length()
		distance = clampf(reach, 0.0, ahead)
	var heading := flat.normalized() if flat.length() > 0.0001 else Vector2.ZERO
	var xz := Vector2(origin.x, origin.z) + heading * distance
	return Vector3(xz.x, float(height_at.call(xz)) if has_field else plane_y, xz.y)


## The ground height function of `game_map` (its ground field's world_height_at), or an invalid
## Callable on the fixed Y = 0 band.
static func height_function(game_map: Node3D) -> Callable:
	if game_map == null:
		return Callable()
	var field: Variant = game_map.get_grid_ground()
	if field == null or not field.is_valid():
		return Callable()
	return field.world_height_at


## The view centre on the ground at the eye (eye_point of the screen-centre ray), or null when
## the camera is not perspective: the orbit view keeps its own plane maths.
static func eye_centre(game_map: Node3D) -> Variant:
	if game_map == null or game_map.camera_node == null or game_map.world_viewport == null:
		return null
	var camera: Camera3D = game_map.camera_node
	if camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return null
	var centre := Vector2(game_map.world_viewport.size as Vector2i) * 0.5
	return eye_point(
		camera.project_ray_origin(centre),
		camera.project_ray_normal(centre),
		0.0,
		height_function(game_map)
	)
