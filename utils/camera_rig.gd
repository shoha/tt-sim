class_name CameraRig
extends RefCounted

## The pure maths of the camera rig's yaw: snap targets, the turn about a pivot, the pan axes
## and the vertical pan factor. CameraController owns the state and calls these every frame.
##
## The yaw is the camera's compass azimuth in degrees, seen from above: 45 is home (the camera
## stands at +x, +z over the pivot and looks toward -x, -z), and a snap is 90, so the four snaps
## are 45, 135, 225 and 315. The CameraHolder carries the yaw as a turn about +Y of
## `yaw - HOME_YAW` from the scene's own pose, so everything the holder's local axes mean (the
## WASD pan, the edge pan) follows the view with no further work. World north is -Z; the sun
## stays where it is in the world (the owner's decision, 2026-11-02), only the camera moves.
##
## Unwrapped yaws are kept while a turn runs (a state may read 495), so an eased turn never
## runs backwards over the wrap; wrap_deg() gives the 0 to 360 reading for display.

## What an event means to an Alt + drag in progress (orbit_action).
enum Orbit { NONE, BEGIN, MOVE, END }

## The yaw of the scene's own camera pose, and of Home.
const HOME_YAW := 45.0
## The home view's elevation above the ground in degrees (the scene's own camera pose), and the
## flattest the rig allows: no flatter than home, which the owner has not judged (2026-11-02).
const HOME_PITCH := 21.6
const MIN_PITCH := 21.6
## Straight down.
const TOP_DOWN_PITCH := 90.0
## The seconds the O toggle and Home take over the whole range (eased like a turn).
const TILT_SECONDS := 0.5
## An Alt + drag that pulls this many degrees flatter than home steps down to the street.
const STREET_PULL_DEG := 8.0
## Alt + drag: degrees of yaw per pixel dragged sideways, and of pitch per pixel dragged down.
## A 1080 px drag down the screen covers the 68 degree pitch range three times over.
const ORBIT_YAW_PER_PX := 0.3
const ORBIT_PITCH_PER_PX := 0.2
## One snap, in degrees.
const SNAP_STEP := 90.0
## The seconds a 90 degree turn takes (a quicker, flatter ease would read as a cut).
const TURN_SECONDS := 0.35
## The steepest slope an eased turn has, as a multiple of its mean speed (smoothstep: 1.5).
const EASE_PEAK := 1.5
## Never divide the vertical pan by less than this fraction of a metre of rise per metre.
const MIN_BACK_Y := 0.2
## How far in front of the near plane a line is cut when part of it is behind the camera.
const FRONT_CLIP_M := 0.02


## `yaw_deg` wrapped to [0, 360).
static func wrap_deg(yaw_deg: float) -> float:
	return fposmod(yaw_deg, 360.0)


## The signed shortest turn from `from_deg` to `to_deg`, in (-180, 180].
static func shortest_turn(from_deg: float, to_deg: float) -> float:
	var d := wrapf(to_deg - from_deg, -180.0, 180.0)
	return 180.0 if is_equal_approx(d, -180.0) else d


## The snap a step in `direction` (+1 clockwise on the compass, -1 counter-clockwise) from
## `yaw_deg` lands on: the next 45 + 90k strictly past the yaw in that direction, from any yaw
## (between snaps too). Unwrapped: 315 stepped +1 gives 405, which wrap_deg() reads as 45.
static func snap_target(yaw_deg: float, direction: int) -> float:
	var steps := (yaw_deg - HOME_YAW) / SNAP_STEP
	var k := floorf(steps + 1e-4) + 1.0 if direction > 0 else ceilf(steps - 1e-4) - 1.0
	return HOME_YAW + k * SNAP_STEP


## The yaw of the snap nearest `yaw_deg`.
static func nearest_snap(yaw_deg: float) -> float:
	return HOME_YAW + roundf((yaw_deg - HOME_YAW) / SNAP_STEP) * SNAP_STEP


## The yaw, in degrees, that has an eye standing at `from` (map XZ) look straight at `to`,
## reached from `current_deg` by the short way (unwrapped: never more than half a turn away).
## Forward at yaw y is (-sin y, -cos y) on the map's XZ (measured: yaw 90 looks west).
static func yaw_toward(from: Vector2, to: Vector2, current_deg: float) -> float:
	var want := rad_to_deg(atan2(-(to.x - from.x), -(to.y - from.y)))
	return current_deg + wrapf(want - current_deg, -180.0, 180.0)


## The holder's turn about +Y for a view yaw.
static func holder_basis(yaw_deg: float) -> Basis:
	return Basis(Vector3.UP, deg_to_rad(yaw_deg - HOME_YAW))


## `position` turned about the vertical axis through `pivot` by `delta_deg`, its height kept.
## The rotation of a holder about the ground point under the screen centre: its basis turns by
## the same angle, and the pivot stays where it is on the screen.
static func rotate_about_pivot(position: Vector3, pivot: Vector3, delta_deg: float) -> Vector3:
	var turn := Basis(Vector3.UP, deg_to_rad(delta_deg))
	var flat := turn * Vector3(position.x - pivot.x, 0.0, position.z - pivot.z)
	return Vector3(pivot.x + flat.x, position.y, pivot.z + flat.z)


## The smoothstep of `t` in [0, 1]: the ease of a turn (and its slope is 0 at both ends).
static func ease_turn(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## The seconds a turn of `degrees` takes: TURN_SECONDS for a snap, longer (as the square
## root) for a half turn or more, so a Home from the far side is not a blur.
static func turn_seconds(degrees: float) -> float:
	return TURN_SECONDS * sqrt(maxf(absf(degrees), SNAP_STEP * 0.25) / SNAP_STEP)


## The most degrees an eased turn of `degrees` over `seconds` moves in one frame at `fps`.
static func peak_degrees_per_frame(degrees: float, seconds: float, fps: float) -> float:
	return absf(degrees) * EASE_PEAK / maxf(seconds, 0.001) / fps


## The world direction (unit, flat) that screen-up shows at `yaw_deg`: away from the viewer.
static func screen_up(yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	return Vector3(-sin(a), 0.0, -cos(a))


## The world direction (unit, flat) that screen-right shows at `yaw_deg`.
static func screen_right(yaw_deg: float) -> Vector3:
	var a := deg_to_rad(yaw_deg)
	return Vector3(cos(a), 0.0, -sin(a))


## The world direction a holder-local pan vector (the legacy WASD axes: forward is (-1, 0, -1))
## moves the holder in at `yaw_deg`.
static func pan_direction(yaw_deg: float, local_dir: Vector3) -> Vector3:
	return holder_basis(yaw_deg) * local_dir


## Factor on the screen-vertical pan so W/S cover the same screen distance per second as A/D:
## the ground foreshortens by the sine of the view's elevation, which is the back axis' y.
## 2.7 at the home view (21.6 degrees), 1 looking straight down. Clamped so a near-level view
## cannot send the pan to infinity.
static func vertical_pan_factor(back_y: float) -> float:
	return 1.0 / clampf(absf(back_y), MIN_BACK_Y, 1.0)


## The angle, clockwise from screen-up in radians, at which world north (-Z) shows on screen.
## It is the yaw itself: at 45 north points up and to the right.
static func north_angle(yaw_deg: float) -> float:
	return deg_to_rad(yaw_deg)


## `pitch_deg` held to the rig's range, [MIN_PITCH, TOP_DOWN_PITCH].
static func clamp_pitch(pitch_deg: float) -> float:
	return clampf(pitch_deg, MIN_PITCH, TOP_DOWN_PITCH)


## The elevation in degrees of a camera whose back axis rises `back_y` per metre.
static func pitch_of_back_y(back_y: float) -> float:
	return rad_to_deg(asin(clampf(back_y, -1.0, 1.0)))


## The camera's basis (local to the yawed holder) at elevation `pitch_deg`, built from an explicit
## horizontal `right` axis so that exactly 90 degrees has no gimbal: back leans over the ground
## along right x up by `cos` and rises by `sin`. At HOME_PITCH it is the scene's own pose.
static func camera_basis(right: Vector3, pitch_deg: float) -> Basis:
	var p := deg_to_rad(pitch_deg)
	var back := right.cross(Vector3.UP) * cos(p) + Vector3.UP * sin(p)
	return Basis(right, back.cross(right).normalized(), back)


## The camera's local offset from the holder at `pitch_deg`: the scene's `home_offset` swung about
## the right axis by the rotation that takes the home back axis to the pitched one, so its length
## and its place relative to the view axis are kept (an orthographic picture does not depend on
## the offset, only the near plane and the pivot do; CameraController re-fits both).
static func pitched_offset(home_offset: Vector3, right: Vector3, pitch_deg: float) -> Vector3:
	var home_back := camera_basis(right, HOME_PITCH).z
	var back := camera_basis(right, pitch_deg).z
	return Basis(Quaternion(home_back, back)) * home_offset


## The pitch to ease to when the top-down key is pressed: straight down, or back to `before` (the
## pitch it was pressed at; home when that was already steep) when the view is already top-down.
static func top_down_target(current_target: float, before: float) -> float:
	if current_target < TOP_DOWN_PITCH - 0.5:
		return TOP_DOWN_PITCH
	return HOME_PITCH if before > TOP_DOWN_PITCH - 0.5 else clamp_pitch(before)


## The yaw and pitch change in degrees (x, y) a mouse move of `motion` pixels means during an
## Alt + drag: dragging the picture right turns the camera to the left (yaw falls), dragging it down
## tilts the camera higher (pitch rises), as if the ground were held.
static func orbit_delta(motion: Vector2) -> Vector2:
	return Vector2(-motion.x * ORBIT_YAW_PER_PX, motion.y * ORBIT_PITCH_PER_PX)


## What `event` means to an Alt + left drag: it BEGINs on a left press with Alt held (and no Ctrl
## or Meta) when the pointer is not over the UI and no other drag owns the mouse (`blocked`: a
## token, brush or tool drag), MOVEs the view while `orbiting`, and ENDs on the left release
## wherever the pointer is.
static func orbit_action(
	event: InputEvent, orbiting: bool, over_gui: bool, blocked: bool
) -> Orbit:
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if not button.pressed:
			return Orbit.END if orbiting else Orbit.NONE
		var chord := button.alt_pressed and not button.ctrl_pressed and not button.meta_pressed
		if chord and not orbiting and not over_gui and not blocked:
			return Orbit.BEGIN
		return Orbit.NONE
	if orbiting and event is InputEventMouseMotion:
		return Orbit.MOVE
	return Orbit.NONE


## Whether `event` is a fresh bare O press: the top-down toggle.
static func is_top_down_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_O:
		return false
	return not (key.alt_pressed or key.ctrl_pressed or key.meta_pressed or key.shift_pressed)


## Whether `event` is a fresh bare V press: step down to the street (the eye view) and back.
static func is_street_key(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_V:
		return false
	return not (key.alt_pressed or key.ctrl_pressed or key.meta_pressed or key.shift_pressed)


## Whether edge panning (a token dragged to the screen edge) waits: Alt is the orbit chord, so the
## view must not slide while it is held or an Alt drag runs.
static func edge_pan_paused(alt_held: bool, orbiting: bool) -> bool:
	return alt_held or orbiting


## The 0..1 strength of the top-down token marker at `pitch_deg`: off below 55 degrees, full from
## 70, smooth between (the token's own model is readable up to about 60).
static func marker_strength(pitch_deg: float) -> float:
	return smoothstep(55.0, 70.0, pitch_deg)


## The turn direction (+1 clockwise, -1 counter-clockwise, 0 none) a key press means.
## Q and E turn the view while no brush owns them; with a brush active they are the brush's
## and Alt+Q / Alt+E turn the view instead (the brush leaves Alt chords alone). `[` and `]`
## are brush size while a brush is active (BrushTool) and turn the view otherwise.
static func key_turn(keycode: Key, alt: bool, mod_other: bool, brush_owns_keys: bool) -> int:
	if mod_other:
		return 0
	match keycode:
		KEY_Q:
			return -1 if (alt == brush_owns_keys) else 0
		KEY_E:
			return 1 if (alt == brush_owns_keys) else 0
		KEY_BRACKETLEFT:
			return -1 if (not brush_owns_keys and not alt) else 0
		KEY_BRACKETRIGHT:
			return 1 if (not brush_owns_keys and not alt) else 0
	return 0


## The turn direction `event` means (key_turn), 0 for anything that is not a fresh key press.
static func event_turn(event: InputEvent, brush_owns_keys: bool) -> int:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return 0
	var other := key.ctrl_pressed or key.meta_pressed or key.shift_pressed
	return key_turn(key.keycode, key.alt_pressed, other, brush_owns_keys)


## The hint-bar key cap and caption for the tilt gesture (O and Home are in the help overlay).
static func tilt_hint() -> Dictionary:
	return {"key": "Alt + drag", "action": "Tilt (O top-down)"}


## The hint bar's base hints while playing: the orbit view's, or the eye's (the street) with
## `street` set. At the street WASD walks, Shift runs, the wheel is the lens and F9 or V leaves
## (Home leaves too, but it is the orbit's reset in the orbit's row). The run chip is
## "Shift + WASD", not "Shift": a token drag lays a "Shift" free-move hint on that key and
## removes it again, which would take a plain "Shift" run chip with it. `brush_owns_keys`: the
## turn chip names the live mapping (turn_hint). Pure but for InputProfile's labels.
static func play_hints(street: bool, brush_owns_keys: bool = false) -> Array[Dictionary]:
	var pause := {"key": InputProfile.label(&"pause"), "action": "Pause"}
	var help := {"key": "F1", "action": "Help"}
	var measure := {"key": InputProfile.label(&"measure"), "action": "Measure"}
	if street:
		return [
			pause,
			{"key": InputProfile.label(&"wasd"), "action": "Walk"},
			{"key": "Shift + WASD", "action": "Run"},
			{"key": InputProfile.label(&"zoom"), "action": "Lens"},
			turn_hint(brush_owns_keys),
			{"key": "F9 or V", "action": "Leave"},
			measure,
			help,
		]
	return [
		pause,
		{"key": InputProfile.label(&"wasd"), "action": "Pan"},
		{"key": InputProfile.label(&"zoom"), "action": "Zoom"},
		turn_hint(brush_owns_keys),
		tilt_hint(),
		{"key": InputProfile.label(&"reset_camera"), "action": "Reset camera"},
		measure,
		{"key": InputProfile.label(&"grid"), "action": "Grid"},
		help,
	]


## The hint-bar key cap and caption naming the turn keys that are live.
static func turn_hint(brush_owns_keys: bool) -> Dictionary:
	return {
		"key": "Alt + Q E" if brush_owns_keys else "Q E",
		"action": "Turn view",
	}


## Metres across the view per screen pixel for an orthographic camera of `size` metres spanning
## `extent_px` pixels (the viewport height for KEEP_HEIGHT, its width for KEEP_WIDTH). Pure.
static func ortho_metres_per_pixel(size: float, extent_px: float) -> float:
	if extent_px <= 0.0:
		return 0.0
	return size / extent_px


## Metres across the view per screen pixel for a perspective camera of field of view `fov_deg`
## (across `extent_px` pixels, as Camera3D.fov is) at `distance` metres from the eye. Pure.
static func perspective_metres_per_pixel(
	fov_deg: float, distance: float, extent_px: float
) -> float:
	if extent_px <= 0.0:
		return 0.0
	return 2.0 * maxf(distance, 0.0) * tan(deg_to_rad(fov_deg) * 0.5) / extent_px


## Metres across the view (on a plane facing the camera) per screen pixel at the screen centre,
## for either projection: the orthographic `size` (depth independent, `distance` is ignored) or a
## perspective camera's fov at `distance` metres from the eye. `viewport_px` is the viewport the
## camera renders to; Camera3D.keep_aspect picks whether size and fov span its height or width.
## Ground metres per pixel along the screen's vertical divide this by the sine of the pitch.
static func metres_per_pixel(
	camera: Camera3D, viewport_px: Vector2, distance: float = 0.0
) -> float:
	var extent := viewport_px.x if camera.keep_aspect == Camera3D.KEEP_WIDTH else viewport_px.y
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		return perspective_metres_per_pixel(camera.fov, distance, extent)
	return ortho_metres_per_pixel(camera.size, extent)


## Where `world_point` lands on the screen (viewport pixels), or null when it is behind the eye
## (the camera's near plane), where Camera3D.unproject_position would return a mirrored position.
## Overlays use this instead of unproject_position so nothing is drawn for a point it cannot see.
static func screen_of(camera: Camera3D, world_point: Vector3) -> Variant:
	if camera.is_position_behind(world_point):
		return null
	return camera.unproject_position(world_point)


## What a dirty check compares to see that the picture changed: the camera's pose, projection,
## orthographic size and field of view. An overlay that compared `size` alone missed a lens change
## at the eye, and one that compared the position alone missed a turn about it.
static func view_key(camera: Camera3D) -> Array:
	return [camera.global_transform, camera.projection, camera.size, camera.fov]


## The part of the segment `a` to `b` in front of the camera, as [from, to] in world space (an end
## behind the near plane moved onto it along the segment), or null when all of it is behind.
## Unchanged ends come back as given, so an orthographic camera, whose near plane is far behind
## it, returns the segment whole.
static func front_segment(camera: Camera3D, a: Vector3, b: Vector3) -> Variant:
	var forward := -camera.global_basis.z
	var origin := camera.global_position
	var cut := camera.near + FRONT_CLIP_M
	var depth_a := forward.dot(a - origin) - cut
	var depth_b := forward.dot(b - origin) - cut
	if depth_a >= 0.0 and depth_b >= 0.0:
		return [a, b]
	if depth_a < 0.0 and depth_b < 0.0:
		return null
	var at := a.lerp(b, depth_a / (depth_a - depth_b))
	return [at, b] if depth_a < 0.0 else [a, at]


## The screen positions [from, to] of the part of the segment `a` to `b` the camera can see, or
## an empty array when none of it is in front. Overlays draw a line with this, so a measure line
## that starts at the feet runs off the screen edge instead of mirroring behind the eye.
static func screen_segment(camera: Camera3D, a: Vector3, b: Vector3) -> PackedVector2Array:
	var seg: Variant = front_segment(camera, a, b)
	if seg == null:
		return PackedVector2Array()
	return PackedVector2Array([camera.unproject_position(seg[0]), camera.unproject_position(seg[1])])


## The part of the screen segment `a` to `b` inside `rect` (Liang-Barsky), as [from, to], or an
## empty array when none of it is. A segment cut at the near plane runs to a point thousands of
## pixels off screen; a dashed line drawn along it would cost a draw call per dash.
static func clip_line_to_rect(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return PackedVector2Array()
			continue
		var r: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, r)
		else:
			t1 = minf(t1, r)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])


## The screen polylines of the world polyline `points`: its parts in front of the camera, each a
## run of at least two screen points, split where the line passes behind the camera. A ground
## ring around a point 5 m ahead of the eye is one run when it is all in front.
static func screen_runs(camera: Camera3D, points: PackedVector3Array) -> Array[PackedVector2Array]:
	var runs: Array[PackedVector2Array] = []
	var run := PackedVector2Array()
	for i in range(points.size() - 1):
		var seg: Variant = front_segment(camera, points[i], points[i + 1])
		if seg == null:
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array()
			continue
		var start_cut: bool = not (seg[0] as Vector3).is_equal_approx(points[i])
		var end_cut: bool = not (seg[1] as Vector3).is_equal_approx(points[i + 1])
		if start_cut or run.is_empty():
			if run.size() > 1:
				runs.append(run)
			run = PackedVector2Array([camera.unproject_position(seg[0])])
		run.append(camera.unproject_position(seg[1]))
		if end_cut:
			runs.append(run)
			run = PackedVector2Array()
	if run.size() > 1:
		runs.append(run)
	return runs
