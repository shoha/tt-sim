class_name CanopyFade
extends RefCounted

## The canopy fades that remain: the brush window and the cut (authoring tools) and the eye
## view's near fade. The view-centre window (the crowns standing in front of the ground at the
## view centre dissolving over a soft round window in the middle of the screen; Settings > Canopy
## fade, default off) was removed on 2026-11-16 (owner decision, review board d_canopy): the token
## ghost and the map pins carry the find-a-covered-token job, and the window was a discard that kept
## the painted crown masses off their discard-free shader whenever it was on. The camera's global
## shader parameters (canopy_fade_view, the brush, the cut, the eye) are written here once a frame
## by publish() and reach every tree material at once.
##
## The eye view (a perspective camera, EyeView): publish() takes the eye (EyeCanopy has the
## maths): a near fade thins every crown within a few metres of the eye, and the same global
## carries the eye to the token ghost's range fade.
##
## The camera's near plane stands clear of every canopy (CameraController
## _hold_near_plane_over_canopies), so a dense forest fills the frame close to the ground; the
## near fade (eye view) and the brush window (authoring) are what open it.
##
## The brush window: a map brush whose mode `fades` (BrushTool, BrushMode.fade_focus) opens
## the canopy over its ring by the same law, card by card with the trunks kept, in a soft
## round window of the ring's reach (set_brush; the shader's canopy_brush). It grows from
## the ring's centre over BRUSH_OPEN_S and, once let go (clear_brush), closes back in from
## its edge over BRUSH_CLOSE_S, so the crowns grow back rather than pop. It used to be a
## token entry of a per-token occlusion fade (removed 2026-11-15), whose per-pixel screen door
## dithered whole trees, trunks included, so a cleared ring's neighbours read as half erased.
##
## The cut (set_cut; the shader's canopy_cut): one authoring piece (the Village tool's picked
## piece) clears every tree part, trunks and stems included, round it: a soft disc on the ground
## round the piece and the soft column between it and the camera. The brush window keeps a
## bush's stems by design, which left a picked barrel standing among bare stems
## (villages5b, 2026-11-03). It opens and closes over the brush window's times. Off while no
## mode asks for it (BrushMode.fade_cut), so play never sees it.

## Global shader parameters (project.godot [shader_globals]).
## xyz the camera's back axis (the shaders' mark of the camera's own pass).
const GLOBAL_VIEW := &"canopy_fade_view"
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

## False holds the eye view's near fade and the ghost's range fade off (EyeCanopy), the way the
## orbit view has them; on by default. A switch for render probes (before and after stills).
static var eye_fade_enabled := true
## False holds the eye view's near grass off (EyeCanopy GRASS_*: thinned, softened tufts near the
## eye); on by default. A switch for render probes (before and after stills, the cost A/B).
static var eye_grass_enabled := true

static var _last_view := Vector4(INF, INF, INF, INF)
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


## Whether any tree fade shows now: the brush or the cut last published with a w above 0
## (nothing published yet is not live). Only authoring raises either, so play never does. The
## painted trees' discard-free crown masses read it, because only the full shader fades
## (painter-perf-blockin).
static func live() -> bool:
	for window: Vector4 in [_last_brush, _last_cut]:
		if is_finite(window.w) and window.w > 0.0:
			return true
	return false


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


## Writes the fade's globals for `camera`: the brush window and the cut `seconds` on, the camera's
## back axis (the shaders' mark of the camera's own pass) and, for a perspective camera, the eye
## view's globals. Only pushes values that changed.
static func publish(camera: Camera3D, seconds: float = 0.0) -> void:
	var brush := step_brush(seconds)
	if brush != _last_brush:
		_last_brush = brush
		RenderingServer.global_shader_parameter_set(GLOBAL_BRUSH, brush)
	var cut := step_cut(seconds)
	if cut != _last_cut:
		_last_cut = cut
		RenderingServer.global_shader_parameter_set(GLOBAL_CUT, cut)
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		_publish_eye(camera)
		return
	_push_eye(Vector4.ZERO)
	_push_eye_grass(0.0)
	var back := camera.global_basis.z.normalized()
	_push_view(Vector4(back.x, back.y, back.z, 0.0))


## The eye view's fade (a perspective camera; EyeCanopy has the maths): `canopy_eye` carries the
## eye and the map scale for the near fade and the ghost range.
static func _publish_eye(camera: Camera3D) -> void:
	var scale := map_scale(camera)
	var eye := camera.global_position
	var back := camera.global_basis.z.normalized()
	_push_eye(Vector4(eye.x, eye.y, eye.z, scale if eye_fade_enabled else 0.0))
	_push_eye_grass(scale if eye_grass_enabled else 0.0)
	_push_view(Vector4(back.x, back.y, back.z, 0.0))


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


## Pushes the view global when it changed.
static func _push_view(view: Vector4) -> void:
	if view != _last_view:
		_last_view = view
		RenderingServer.global_shader_parameter_set(GLOBAL_VIEW, view)
