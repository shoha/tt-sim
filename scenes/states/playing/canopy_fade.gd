class_name CanopyFade
extends RefCounted

## The canopy fade: the crowns standing in front of the ground at the view centre dissolve
## over a soft round window in the middle of the screen (wind_foliage_include.gdshaderinc,
## apply_canopy_fade), so the ground and the tokens under a forest read while the trees at the
## frame's edges stay whole. In the window a tree keeps its trunk; its leaf cards drop out
## card by card and its limbs limb by limb. At play zooms (home to 20) the window is gentle
## and small, thinning the crowns over the stage; below the home zoom it ramps up to a full
## clearing; past the play camera's zoom-out it fades away (authoring's whole-map views).
## CameraController calls publish() once a frame; the global shader parameters it writes
## reach every tree material at once.
##
## The camera's near plane stands clear of every canopy (CameraController
## _hold_near_plane_over_canopies), so without this fade a dense forest fills the frame.
##
## The brush window: a map brush whose mode `fades` (BrushTool, BrushMode.fade_focus) opens
## the canopy over its ring by the same law, card by card with the trunks kept, in a soft
## round window of the ring's reach (set_brush; the shader's canopy_brush). It grows from
## the ring's centre over BRUSH_OPEN_S and, once let go (clear_brush), closes back in from
## its edge over BRUSH_CLOSE_S, so the crowns grow back rather than pop. It used to be a
## token entry of the occlusion fade, whose per-pixel screen door dithered whole trees,
## trunks included, so a cleared ring's neighbours read as half erased.

## Global shader parameters (project.godot [shader_globals]).
const GLOBAL_CENTRE := &"canopy_fade_centre"
const GLOBAL_VIEW := &"canopy_fade_view"
const GLOBAL_SHAPE := &"canopy_fade_shape"
const GLOBAL_BRUSH := &"canopy_brush"
## How long the brush window takes to open and to close, in seconds.
const BRUSH_OPEN_S := 0.15
const BRUSH_CLOSE_S := 0.4
## The ramp to the full close-zoom fade runs from the home zoom down to FULL_FRACTION of it.
const FULL_FRACTION := 0.55
## The full close-zoom window, per unit of orthographic size: inner and outer radius on screen
## and the depth band.
const CLOSE_INNER := 0.3
const CLOSE_OUTER := 0.75
const BAND := 0.35
## Above the play camera's zoom-out (CameraController.max_zoom's play value) the fade fades
## out, gone by FADE_OUT_SIZE.
const PLAY_MAX_SIZE := 20.0
const FADE_OUT_SIZE := 30.0
## Terrain collision layer for the view-centre ground ray.
const GROUND_MASK := 1
const RAY_LENGTH := 400.0

## The play-zoom window (home to PLAY_MAX_SIZE): strength, and inner and outer radius per unit
## of orthographic size. Chosen by eye on forest and taiga maps (Polish, 2026-10-05). Vars, not
## constants, so a render probe can tune them in-run (probes/close_zoom.gd play).
static var play_strength := 0.9
static var play_inner := 0.2
static var play_outer := 0.55

static var _last_centre := Vector4(INF, INF, INF, INF)
static var _last_view := Vector4(INF, INF, INF, INF)
static var _last_shape := Vector4(INF, INF, INF, INF)
static var _last_brush := Vector4(INF, INF, INF, INF)
## The brush window asked for: (ground centre, radius in metres), w 0 when let go; the last
## centre and radius stay while it closes.
static var _brush_asked := Vector4.ZERO
static var _brush_window := Vector4.ZERO
## How far the window is open, 0 to 1.
static var _brush_open := 0.0


## Opens the brush window over the ground point `centre` with radius `radius` (metres in the
## view plane), or moves it there while it is open.
static func set_brush(centre: Vector3, radius: float) -> void:
	_brush_asked = Vector4(centre.x, centre.y, centre.z, maxf(radius, 0.0))
	if _brush_asked.w > 0.0:
		_brush_window = _brush_asked


## Lets the brush window close (it shrinks back over BRUSH_CLOSE_S).
static func clear_brush() -> void:
	_brush_asked = Vector4.ZERO


## Whether the brush window is asked for (it may still be opening). For tests.
static func brush_asked() -> Vector4:
	return _brush_asked


## The brush window after `seconds` more of opening or closing: (centre, radius scaled by how
## far it is open), zero once shut. Advances the window's state.
static func step_brush(seconds: float) -> Vector4:
	var opening := _brush_asked.w > 0.0
	var rate := 1.0 / (BRUSH_OPEN_S if opening else BRUSH_CLOSE_S)
	_brush_open = clampf(_brush_open + (rate if opening else -rate) * maxf(seconds, 0.0), 0.0, 1.0)
	if _brush_open <= 0.0:
		return Vector4.ZERO
	var w := _brush_window
	return Vector4(w.x, w.y, w.z, w.w * smoothstep(0.0, 1.0, _brush_open))


## How far the camera has closed in past the home zoom: 0 at home and above, 1 at
## FULL_FRACTION of it and below. Pure.
static func closeness(size: float, home: float) -> float:
	if home <= 0.0:
		return 0.0
	return 1.0 - smoothstep(home * FULL_FRACTION, home, size)


## Fade strength (0 off, 1 full) at orthographic size `size`, for a camera whose home size is
## `home`: play_strength from the home zoom out to PLAY_MAX_SIZE, rising to 1 as the camera
## closes in, falling to 0 between PLAY_MAX_SIZE and FADE_OUT_SIZE. Pure but for the play
## settings.
static func strength(size: float, home: float) -> float:
	if home <= 0.0:
		return 0.0
	var close := lerpf(play_strength, 1.0, closeness(size, home))
	return close * (1.0 - smoothstep(PLAY_MAX_SIZE, FADE_OUT_SIZE, size))


## The window at size `size`: Vector4(inner radius, outer radius, depth band, 0) in metres.
## Pure but for the play settings.
static func shape(size: float, home: float) -> Vector4:
	var t := closeness(size, home)
	return Vector4(
		lerpf(play_inner, CLOSE_INNER, t) * size,
		lerpf(play_outer, CLOSE_OUTER, t) * size,
		BAND * size,
		0.0
	)


## Writes the fade's globals for `camera` at home size `home`: the ground under the view
## centre (a layer-1 ray, or the y = 0 plane when it misses), the strength, the camera's back
## axis and the window, and the brush window `seconds` on. Only pushes values that changed;
## while off, no ray is cast.
static func publish(
	camera: Camera3D, home: float, viewport_size: Vector2, seconds: float = 0.0
) -> void:
	var brush := step_brush(seconds)
	if brush != _last_brush:
		_last_brush = brush
		RenderingServer.global_shader_parameter_set(GLOBAL_BRUSH, brush)
	var s := strength(camera.size, home)
	var back := camera.global_basis.z.normalized()
	var centre := Vector4.ZERO
	if s > 0.0:
		var ground := view_centre_ground(camera, viewport_size)
		centre = Vector4(ground.x, ground.y, ground.z, s)
	var view := Vector4(back.x, back.y, back.z, 0.0)
	var window := shape(camera.size, home)
	if centre != _last_centre:
		_last_centre = centre
		RenderingServer.global_shader_parameter_set(GLOBAL_CENTRE, centre)
	if view != _last_view:
		_last_view = view
		RenderingServer.global_shader_parameter_set(GLOBAL_VIEW, view)
	if window != _last_shape:
		_last_shape = window
		RenderingServer.global_shader_parameter_set(GLOBAL_SHAPE, window)


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
