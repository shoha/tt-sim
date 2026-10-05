class_name CanopyFade
extends RefCounted

## The close-zoom canopy fade: below the home zoom, the crowns standing in front of the
## ground at the view centre dissolve over a soft round clearing in the middle of the screen
## (wind_foliage_include.gdshaderinc, apply_canopy_fade), so zooming in reveals the ground
## and the tokens under a forest while the trees at the frame's edges stay whole. In the
## clearing a tree keeps its trunk; its leaf cards drop out card by card and its limbs limb by
## limb. CameraController calls publish() once a frame; the two global shader parameters it
## writes reach every tree material at once.
##
## Before this, the orthographic camera moved in with the zoom and its near plane sliced the
## canopies nearest the camera flat (a hard cut through the leaves, bushes shown hollow);
## CameraController now keeps the near plane where the home zoom has it, and this fade does
## the revealing instead, softly.

## Global shader parameters (project.godot [shader_globals]).
const GLOBAL_CENTRE := &"canopy_fade_centre"
const GLOBAL_VIEW := &"canopy_fade_view"
## The fade starts below this fraction of the home zoom and is full at FULL_FRACTION of it.
const START_FRACTION := 1.0
const FULL_FRACTION := 0.55
## Terrain collision layer for the view-centre ground ray.
const GROUND_MASK := 1
const RAY_LENGTH := 400.0

static var _last_centre := Vector4(INF, INF, INF, INF)
static var _last_view := Vector4(INF, INF, INF, INF)


## Fade strength (0 off, 1 full) at orthographic size `size`, for a camera whose home size is
## `home`. Off at the home zoom and above. Pure.
static func strength(size: float, home: float) -> float:
	if home <= 0.0:
		return 0.0
	return 1.0 - smoothstep(home * FULL_FRACTION, home * START_FRACTION, size)


## Writes the fade's globals for `camera` at home size `home`: the ground under the view
## centre (a layer-1 ray, or the y = 0 plane when it misses), the strength, the camera's back
## axis and its size. Only pushes values that changed; while off, no ray is cast.
static func publish(camera: Camera3D, home: float, viewport_size: Vector2) -> void:
	var s := strength(camera.size, home)
	var back := camera.global_basis.z.normalized()
	var centre := Vector4.ZERO
	if s > 0.0:
		var ground := view_centre_ground(camera, viewport_size)
		centre = Vector4(ground.x, ground.y, ground.z, s)
	var view := Vector4(back.x, back.y, back.z, camera.size)
	if centre != _last_centre:
		_last_centre = centre
		RenderingServer.global_shader_parameter_set(GLOBAL_CENTRE, centre)
	if view != _last_view:
		_last_view = view
		RenderingServer.global_shader_parameter_set(GLOBAL_VIEW, view)


## The ground point at the centre of the view: the first layer-1 hit along the centre ray,
## or where the ray crosses y = 0.
static func view_centre_ground(camera: Camera3D, viewport_size: Vector2) -> Vector3:
	var screen := viewport_size * 0.5
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var world := camera.get_world_3d()
	if world:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * RAY_LENGTH)
		query.collision_mask = GROUND_MASK
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit.position
	return plane_hit(origin, dir, 0.0)


## Where the ray (origin, dir) crosses the plane y = `y`; the origin when it runs parallel.
## Pure.
static func plane_hit(origin: Vector3, dir: Vector3, y: float) -> Vector3:
	if absf(dir.y) < 0.0001:
		return origin
	return origin + dir * ((y - origin.y) / dir.y)
