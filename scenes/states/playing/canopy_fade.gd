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
## The eye view (a perspective camera, EyeView): Camera3D.size means nothing there, so publish()
## takes the eye, the camera's forward and a focus point instead (EyeCanopy has the maths): a
## near fade thins every crown within a few metres of the eye whether or not the Settings switch
## is on, the same globals carry the eye to the token ghost's range fade, and the window (Settings
## switch) uses the eye-to-focus distance in place of the size. The orthographic path is the
## code it always was.
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
##
## The cut (set_cut; the shader's canopy_cut): one authoring piece (the Village tool's picked
## piece) clears every tree part, trunks and stems included, round it: a soft disc on the ground
## round the piece and the soft column between it and the camera. The brush window keeps a
## bush's stems by design, which left a picked barrel standing among bare stems
## (villages5b, 2026-11-03). It opens and closes over the brush window's times. Off while no
## mode asks for it (BrushMode.fade_cut), so play never sees it.

## Global shader parameters (project.godot [shader_globals]).
const GLOBAL_CENTRE := &"canopy_fade_centre"
const GLOBAL_VIEW := &"canopy_fade_view"
const GLOBAL_SHAPE := &"canopy_fade_shape"
const GLOBAL_BRUSH := &"canopy_brush"
const GLOBAL_CUT := &"canopy_cut"
## xyz the eye, w the map scale in the eye view, 0 otherwise (EyeCanopy).
const GLOBAL_EYE := &"canopy_eye"
## The map scale while the eye view's near grass is on, 0 otherwise (EyeCanopy GRASS_*).
const GLOBAL_EYE_GRASS := &"eye_grass"
## How long the brush window takes to open and to close, in seconds.
const BRUSH_OPEN_S := 0.15
const BRUSH_CLOSE_S := 0.4
## The cut's shape, as the shader's CANOPY_CUT_* (tests pin the pair): leaf cards are full inside
## CUT_INNER of the radius, bark is full out to the radius and gone by CUT_BARK times it, and the
## column to the camera starts CUT_BEHIND_M behind the piece (docs/systems/villages.md quotes
## 0.6 and 1.5).
const CUT_INNER := 0.6
const CUT_BARK := 1.5
const CUT_BEHIND_M := 0.5
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
## The Settings default of the close-zoom window (graphics/canopy_fade_enabled).
const DEFAULT_ENABLED := false

## The play-zoom window (home to PLAY_MAX_SIZE): strength, and inner and outer radius per unit
## of orthographic size. Chosen by eye on forest and taiga maps (Polish, 2026-10-05). Vars, not
## constants, so a render probe can tune them in-run (probes/close_zoom.gd play).
static var play_strength := 0.9
## False holds the whole close-zoom window off, whatever the zoom (the brush window is not
## affected). The Settings menu's "Canopy fade" sets it (VisualEffectsController
## .set_canopy_fade_enabled), off by default: the window follows the screen centre and players
## found the tunnel disruptive (2026-10-24), the token ghost and the per-token occlusion fade
## now show tokens under foliage without it.
static var enabled := DEFAULT_ENABLED
## False holds the eye view's near fade and the ghost's range fade off (EyeCanopy), the way the
## orbit view has them; on by default. A switch for render probes (before and after stills).
static var eye_fade_enabled := true
## False holds the eye view's near grass off (EyeCanopy GRASS_*: thinned, softened tufts near the
## eye); on by default. A switch for render probes (before and after stills, the cost A/B).
static var eye_grass_enabled := true
static var play_inner := 0.2
static var play_outer := 0.55

static var _last_centre := Vector4(INF, INF, INF, INF)
static var _last_view := Vector4(INF, INF, INF, INF)
static var _last_shape := Vector4(INF, INF, INF, INF)
static var _last_brush := Vector4(INF, INF, INF, INF)
static var _last_eye := Vector4(INF, INF, INF, INF)
static var _last_eye_grass := INF
## The brush window asked for: (ground centre, radius in metres), w 0 when let go; the last
## centre and radius stay while it closes.
static var _brush_asked := Vector4.ZERO
static var _brush_window := Vector4.ZERO
## How far the window is open, 0 to 1.
static var _brush_open := 0.0
static var _last_cut := Vector4(INF, INF, INF, INF)
## The cut asked for and the last one held while it closes, as the brush window's.
static var _cut_asked := Vector4.ZERO
static var _cut_window := Vector4.ZERO
static var _cut_open := 0.0


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
	_brush_open = opened(_brush_open, _brush_asked.w > 0.0, seconds)
	return scaled(_brush_window, _brush_open)


## Cuts every tree part (trunks and stems too) round the ground point `centre` out to `radius`
## metres, or moves the cut there while it is held; a radius of 0 lets it close.
static func set_cut(centre: Vector3, radius: float) -> void:
	_cut_asked = Vector4(centre.x, centre.y, centre.z, maxf(radius, 0.0))
	if _cut_asked.w > 0.0:
		_cut_window = _cut_asked


## Lets the cut close (it shrinks back over BRUSH_CLOSE_S).
static func clear_cut() -> void:
	_cut_asked = Vector4.ZERO


## Whether the cut is asked for (it may still be opening). For tests.
static func cut_asked() -> Vector4:
	return _cut_asked


## The cut after `seconds` more of opening or closing, as step_brush. Advances its state.
static func step_cut(seconds: float) -> Vector4:
	_cut_open = opened(_cut_open, _cut_asked.w > 0.0, seconds)
	return scaled(_cut_window, _cut_open)


## How far a window that was `open` (0 to 1) is open `seconds` later, opening over BRUSH_OPEN_S
## while `opening`, else closing over BRUSH_CLOSE_S. Pure.
static func opened(open: float, opening: bool, seconds: float) -> float:
	var rate := 1.0 / (BRUSH_OPEN_S if opening else BRUSH_CLOSE_S)
	return clampf(open + (rate if opening else -rate) * maxf(seconds, 0.0), 0.0, 1.0)


## The window `window` (centre, radius) with its radius eased by how far it is `open`; zero once
## shut. Pure.
static func scaled(window: Vector4, open: float) -> Vector4:
	if open <= 0.0:
		return Vector4.ZERO
	return Vector4(window.x, window.y, window.z, window.w * smoothstep(0.0, 1.0, open))


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
	var cut := step_cut(seconds)
	if cut != _last_cut:
		_last_cut = cut
		RenderingServer.global_shader_parameter_set(GLOBAL_CUT, cut)
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_publish_eye(camera, viewport_size)
		return
	_push_eye(Vector4.ZERO)
	_push_eye_grass(0.0)
	var s := strength(camera.size, home) if enabled else 0.0
	var back := camera.global_basis.z.normalized()
	var centre := Vector4.ZERO
	if s > 0.0:
		var ground := view_centre_ground(camera, viewport_size)
		centre = Vector4(ground.x, ground.y, ground.z, s)
	var view := Vector4(back.x, back.y, back.z, 0.0)
	var window := shape(camera.size, home)
	_push(centre, view, window)


## The eye view's fade (a perspective camera; EyeCanopy has the maths). Camera3D.size means
## nothing here, so the inputs are the eye, the camera's forward and a focus point (the ground
## under the centre ray, or FOCUS_AHEAD_M ahead when it misses): `canopy_eye` carries the eye
## and the map scale for the near fade and the ghost range, and the focus window (only while
## `enabled`) takes the eye-to-focus distance in place of the orthographic size.
static func _publish_eye(camera: Camera3D, viewport_size: Vector2) -> void:
	var scale := map_scale(camera)
	var eye := camera.global_position
	var forward := -camera.global_basis.z.normalized()
	var back := -forward
	var centre := Vector4.ZERO
	var window := Vector4(1.0, 2.0, 1.0, 0.0)
	if enabled:
		var ground := view_centre_ground(camera, viewport_size)
		var hit := ground != eye and absf(forward.y) > 0.0001 and (ground - eye).dot(forward) > 0.0
		var focus := EyeCanopy.focus_point(eye, forward, hit, ground, scale)
		var size := EyeCanopy.window_size((focus - eye).length(), camera.fov, scale)
		var home := EyeCanopy.home_size(camera.fov)
		var s := strength(size, home)
		if s > 0.0:
			centre = Vector4(focus.x, focus.y, focus.z, s)
			window = shape(size, home) * scale
	_push_eye(Vector4(eye.x, eye.y, eye.z, scale if eye_fade_enabled else 0.0))
	_push_eye_grass(scale if eye_grass_enabled else 0.0)
	_push(centre, Vector4(back.x, back.y, back.z, 0.0), window)


## The map's scale (world metres per map metre) as the eye sees it: the "LevelMap" under the
## camera's viewport's MapContainer, 1 with no map or a camera outside the game map.
static func map_scale(camera: Camera3D) -> float:
	var holder := camera.get_parent()
	var viewport := holder.get_parent() if holder != null else null
	var map := viewport.get_node_or_null("MapContainer/LevelMap") as Node3D if viewport else null
	if map == null:
		return 1.0
	return maxf(map.global_transform.basis.get_scale().x, 0.0001)


## Pushes the eye global when it changed (w 0: not the eye view).
static func _push_eye(eye: Vector4) -> void:
	if eye != _last_eye:
		_last_eye = eye
		RenderingServer.global_shader_parameter_set(GLOBAL_EYE, eye)


## Pushes the near grass global when it changed (the map scale, 0: off).
static func _push_eye_grass(scale: float) -> void:
	if scale != _last_eye_grass:
		_last_eye_grass = scale
		RenderingServer.global_shader_parameter_set(GLOBAL_EYE_GRASS, scale)


## Pushes the centre, view and window globals that changed.
static func _push(centre: Vector4, view: Vector4, window: Vector4) -> void:
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
