class_name EyeGlide
extends RefCounted

## The glide between the orbit view and the eye (cards eyeentry SR-P3 and eyeglide SR3, owner
## verdicts SL1 and EN1, 2026-11-03): EyeView owns one, runs it from its process while the eye
## is the active mode, and the eye mode stays active for the whole glide, so EyeSky's painted sky
## and fog are live from the first frame going in and until the last going out. EyeGlideRig has
## the maths (a dolly zoom: a far perspective camera with a vanishing field of view dropping onto
## the eye).
##
## Each frame the glide writes the camera's world pose, field of view, near and far, the fog
## offset EyeSky adds to its begin and end (so the fog is measured from the pivot, not from a
## camera 974 m away). The sun's shadow distance follows by itself: MapViewFit.follow fits it to
## the camera as it stands, and the camera is the glide's. There is no fade to the fog colour in
## the middle (owner verdict EN2, 2026-11-03): the straight path passes through whatever stands
## between the home camera and the pivot.
##
## Entering ends at the eye's own pose, so EyeView takes over from the final frame with no jump;
## leaving ends at the orbit pose, and EyeView switches to the orbit view on that frame (the
## orbit's pose and projection are restored exactly by EyeView.deactivate). Skipping a glide
## jumps to its end and does the same.

## Switched off by a player who wants the instant change (a Smooth view change setting would set
## it), and by an operating system that asks for reduced motion.
static var enabled: bool = true

var _active: bool = false
var _entering: bool = true
var _elapsed: float = 0.0
var _seconds: float = EyeGlideRig.SECONDS
var _camera: Camera3D = null
var _sky: EyeSky = null
# The anchors of the pose
var _home_basis: Basis = Basis.IDENTITY
var _pivot: Vector3 = Vector3.ZERO
var _eye_basis: Basis = Basis.IDENTITY
var _eye_position: Vector3 = Vector3.ZERO
var _view_height: float = 1.0
var _lens: float = 60.0
var _d_start: float = 0.0
# The state the last apply wrote, for tests and the render job
var _q: float = 0.0
var _d: float = 0.0


## Whether a glide may run at all: the setting is on and the system does not ask for less motion.
static func allowed() -> bool:
	return enabled and not UiMotion.reduced()


func is_active() -> bool:
	return _active


func is_entering() -> bool:
	return _entering


## Progress q of the last frame written (0 the home picture, 1 the eye) and the camera's distance
## from the pivot then.
func progress() -> float:
	return _q


func distance() -> float:
	return _d


## The elapsed fraction of the glide, 0..1.
func fraction() -> float:
	return clampf(_elapsed / _seconds, 0.0, 1.0)


## Start a glide on `camera`. `home_basis` and `pivot` are the orbit camera's basis and the ground
## point under its screen centre, `eye_basis` and `eye_position` the eye's pose, `view_height` the
## orthographic view height (metres) the home picture frames, `lens` the eye's field of view.
## The glide's first frame (the home picture going in, the eye going out) is written at once.
func begin(camera: Camera3D, sky: EyeSky, entering: bool, anchors: Dictionary) -> void:
	end()
	_camera = camera
	_sky = sky
	_entering = entering
	_elapsed = 0.0
	_home_basis = anchors["home_basis"]
	_pivot = anchors["pivot"]
	_eye_basis = anchors["eye_basis"]
	_eye_position = anchors["eye_position"]
	_view_height = anchors["view_height"]
	_lens = anchors["lens"]
	_d_start = EyeGlideRig.start_distance(_view_height)
	_active = true
	_write(0.0)


## Advance by `delta` seconds and write the frame. True while the glide runs; false once it has
## reached its end this frame (the end frame is written, the caller takes over).
func step(delta: float) -> bool:
	if not _active:
		return false
	# A stalled frame (the sky's first compile) slows the glide instead of skipping part of it.
	_elapsed += minf(delta, EyeGlideRig.MAX_STEP_SECONDS)
	var t := fraction()
	_write(t)
	return t < 1.0


## Hold the frame on screen now as a veil over the world (under the HUD) and dissolve it away over
## EyeGlideRig.VEIL_SECONDS: the glide's two ends switch between pictures that are the same but for
## their haze (the orbit's grey skirt and sky against the eye's foot-coloured fog, and the shadows'
## cascades), so the switch is covered by a dissolve of the last frame of the old view rather than
## a cut. Going in it is called with the last orbit frame, coming out with the last glide frame (the
## camera hardly moves in either, so nothing ghosts). Costs one read-back of the window. Returns
## whether a veil was made (none in a headless run or without a layer); the caller then waits one
## frame before it changes the view, so the veil has been drawn once when the picture changes
## (measured: a veil made in the same frame as the switch came up one frame late, a one-frame
## flicker of the new haze).
static func freeze_veil(layer: Node) -> bool:
	if layer == null or not layer.is_inside_tree() or DisplayServer.get_name() == "headless":
		return false
	var image := layer.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		return false
	var veil := TextureRect.new()
	veil.name = "EyeGlideVeil"
	veil.texture = ImageTexture.create_from_image(image)
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(veil)
	var tween := veil.create_tween()
	tween.tween_property(veil, "modulate:a", 0.0, EyeGlideRig.VEIL_SECONDS).set_trans(
		Tween.TRANS_SINE
	)
	tween.tween_callback(veil.queue_free)
	return true


## Stop now and put the fog back: the caller puts the camera where the mode it is switching to
## wants it. Safe when no glide runs.
func end() -> void:
	_active = false
	if _sky != null:
		_sky.fog_offset = 0.0
	_sky = null
	_camera = null


## The camera pose, field of view, planes and fog offset for elapsed fraction `t`.
func _write(t: float) -> void:
	var q := EyeGlideRig.progress(t)
	if not _entering:
		q = 1.0 - q
	_q = q
	_d = EyeGlideRig.distance(q, _d_start)
	_camera.global_transform = EyeGlideRig.pose(
		q, _home_basis, _pivot, _eye_basis, _eye_position, _d_start
	)
	_camera.fov = EyeGlideRig.fov(_d, _view_height, _lens)
	_camera.near = EyeGlideRig.NEAR
	_camera.far = EyeGlideRig.far_plane(_d)
	_sky.fog_offset = EyeGlideRig.fog_offset(_d)
