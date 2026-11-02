class_name ViewMode
extends RefCounted

## The seam between CameraController and one way of looking at the map. The controller owns the
## single Camera3D, the CameraHolder, the yaw and pitch state (CameraView) and the input routing,
## and holds exactly one ViewMode at a time; everything that depends on how the picture is made
## (the projection, how the pointer pans and zooms, the pan bounds, the near plane, what "at rest"
## means) is behind this interface. OrbitView is today's mode (orthographic, the pivot under the
## screen centre); a second mode (an eye-level perspective camera) extends this class and is
## swapped in with CameraController.set_view_mode, with no edit to OrbitView.
##
## Every method here is a hook with a harmless default, so a mode overrides only what it needs.
## The lifecycle: activate() when the mode becomes the controller's, deactivate() when it stops
## being (it must leave no input state behind: a held key, a running pan, a glide), process()
## once a frame while active. The controller calls the others only on the active mode.

## The controller that holds this mode, set by activate().
var controller: CameraController = null
## The GameMap whose camera, holder and viewport the mode drives, set by activate().
var game_map: GameMap = null


## A short stable name for the bridge and render jobs: "orbit", "eye", ...
func mode_name() -> StringName:
	return &"none"


## The camera's vertical field of view in degrees; 0 for an orthographic mode.
func fov_deg() -> float:
	return 0.0


## The mode becomes the controller's active one. Takes over the Camera3D (its projection, size or
## fov, and local pose) for this mode.
func activate(owner_controller: CameraController, map: GameMap) -> void:
	controller = owner_controller
	game_map = map


## The mode stops being the active one: drop held keys, velocities, pans and glides.
func deactivate() -> void:
	pass


## One frame of the mode's own motion (keys, zoom ease, edge pan), after the controller has
## stepped the yaw and pitch.
func process(_delta: float) -> void:
	pass


## A key event the controller did not take itself (Home, turn and top-down are the controller's).
## True when the mode consumed it and the controller should mark it handled.
func handle_input(_event: InputEvent) -> bool:
	return false


## Begin a drag pan from `screen_pos`; `rmb` when the right button started it.
func pan_begin(_screen_pos: Vector2, _rmb: bool) -> void:
	pass


## The pan's button was released (`rmb` for the right button).
func pan_end(_rmb: bool) -> void:
	pass


## Drop any pan in progress at once (the pointer moved over the UI, a mode change).
func pan_cancel() -> void:
	pass


## Whether a drag pan is running.
func is_panning() -> bool:
	return false


## Whether the running pan was started with the right button.
func is_rmb_pan_active() -> bool:
	return false


## Pointer motion during a pan. True when the event must be marked handled.
func pan_motion(_event: InputEventMouseMotion) -> bool:
	return false


## The latest pointer position, tracked every frame (zoom toward the cursor).
func record_mouse(_screen_pos: Vector2) -> void:
	pass


## Zoom by a raw delta (orbit: the orthographic size, clamped to the zoom limits).
func zoom_by(_delta: float) -> void:
	pass


## One wheel notch: -1 zooms in, +1 out.
func zoom_notch(_direction: int) -> void:
	pass


## A trackpad pan-gesture zoom step; the sign of `delta_y` is the direction.
func zoom_gesture(_delta_y: float) -> void:
	pass


## Replace the zoom range (MapViewFit forwards the fitted limits).
func set_zoom_limits(_low: float, _high: float) -> void:
	pass


## End the zoom ease exactly on its target (render jobs, so a view is repeatable).
func finish_zoom() -> void:
	pass


## Put the ground point `at` (map X and Z) at the middle of the screen at zoom `zoom`, at once.
func frame_ground(_at: Vector2, _zoom: float) -> void:
	pass


## Glide to put the world position under the middle of the screen (double-click a token).
func focus_on(_world_position: Vector3) -> void:
	pass


## The pitch changed to `pitch_deg`: place the camera for it, keeping the pivot where it is.
func apply_pitch(_pitch_deg: float) -> void:
	pass


## The XZ offset from the holder to the ground point under the screen centre (the pivot).
func view_center_offset() -> Vector2:
	return Vector2.ZERO


## Re-place the camera for the current zoom, ground height and viewport.
func update_camera_offset() -> void:
	pass


## The terrain's highest ground (controller.ground_top_y) changed.
func ground_top_changed() -> void:
	pass


## The world viewport was resized.
func viewport_resized() -> void:
	pass


## Remember the current pose as the one Home returns to.
func capture_home() -> void:
	pass


## Home: return to the home pose (the yaw and pitch ease first, then the position glides).
func reset_home() -> void:
	pass


## The yaw and pitch have landed after a Home that waited for them: glide to the home position.
func glide_home() -> void:
	pass


## Stop a Home or focus glide, if one runs.
func cancel_glide() -> void:
	pass


## Fit the pan bounds again for the camera's basis as it is now.
func refit_bounds() -> void:
	pass


## Pull the holder back inside the pan bounds.
func clamp_to_bounds() -> void:
	pass


## A map finished loading: compute its bounds and snap into them.
func map_loaded() -> void:
	pass


## Use `bounds` as the map's extent for the pan range.
func set_map_bounds(_bounds: AABB) -> void:
	pass


## A map is about to be replaced: forget its bounds.
func map_clearing() -> void:
	pass


## Whether the mode's own motion has stopped (zoom eased, no glide, no key, edge or pan moving it).
func is_at_rest() -> bool:
	return true
