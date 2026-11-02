extends GutTest

## The camera's view-mode seam (ViewMode, OrbitView, CameraController.set_view_mode) and the
## projection-independent helpers the eye-level views need (CameraRig.metres_per_pixel, screen_of).
## A fake second view stands in for the eye mode: it must swap in and out with no edit to OrbitView,
## and the orbit view must leave no input state behind when it is deactivated.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const VIEWPORT := Vector2(1920.0, 1080.0)


## A stand-in second mode: records what the controller asks of it.
class FakeView:
	extends ViewMode

	var activations: int = 0
	var deactivations: int = 0
	var frames: int = 0
	var keys: Array[InputEvent] = []
	var notches: Array[int] = []
	var pans: int = 0
	var consume_keys: bool = false

	func mode_name() -> StringName:
		return &"fake"

	func fov_deg() -> float:
		return 60.0

	func activate(owner_controller: CameraController, map: GameMap) -> void:
		super.activate(owner_controller, map)
		activations += 1

	func deactivate() -> void:
		deactivations += 1

	func process(_delta: float) -> void:
		frames += 1

	func handle_input(event: InputEvent) -> bool:
		keys.append(event)
		return consume_keys

	func pan_begin(_screen_pos: Vector2, _rmb: bool) -> void:
		pans += 1

	func zoom_notch(direction: int) -> void:
		notches.append(direction)


var _game_map: GameMap


func before_each() -> void:
	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	_game_map = GAME_MAP_SCENE.instantiate()
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	controller.setup(_game_map)
	_game_map.setup(controller)


func _forward_key() -> InputEventAction:
	var event := InputEventAction.new()
	event.action = "camera_move_forward"
	event.pressed = true
	return event


# --- CameraRig.metres_per_pixel and screen_of ---


func test_ortho_metres_per_pixel_is_size_over_extent() -> void:
	assert_almost_eq(CameraRig.ortho_metres_per_pixel(13.85, 1080.0), 13.85 / 1080.0, 0.000001)
	assert_eq(CameraRig.ortho_metres_per_pixel(10.0, 0.0), 0.0, "no viewport: zero, not a crash")


func test_perspective_metres_per_pixel_grows_with_distance_and_fov() -> void:
	var near := CameraRig.perspective_metres_per_pixel(60.0, 5.0, 1080.0)
	var far := CameraRig.perspective_metres_per_pixel(60.0, 10.0, 1080.0)
	assert_almost_eq(far, near * 2.0, 0.000001, "twice as far, twice the metres a pixel")
	# fov 90 spans 2 * d metres at distance d.
	assert_almost_eq(CameraRig.perspective_metres_per_pixel(90.0, 4.0, 100.0), 0.08, 0.000001)
	assert_gt(CameraRig.perspective_metres_per_pixel(75.0, 5.0, 1080.0), near, "wider lens")


func test_metres_per_pixel_dispatches_on_the_projection() -> void:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20.0
	assert_almost_eq(CameraRig.metres_per_pixel(camera, VIEWPORT, 99.0), 20.0 / 1080.0, 0.000001)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 60.0
	var expected := 2.0 * 8.0 * tan(deg_to_rad(30.0)) / 1080.0
	assert_almost_eq(CameraRig.metres_per_pixel(camera, VIEWPORT, 8.0), expected, 0.000001)
	camera.keep_aspect = Camera3D.KEEP_WIDTH
	var by_width := 2.0 * 8.0 * tan(deg_to_rad(30.0)) / 1920.0
	assert_almost_eq(CameraRig.metres_per_pixel(camera, VIEWPORT, 8.0), by_width, 0.000001)


func test_screen_of_is_null_behind_the_eye_and_a_position_in_front() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.near = 0.05
	add_child_autofree(camera)
	# The default camera looks along -Z from the origin.
	assert_null(CameraRig.screen_of(camera, Vector3(0.0, 0.0, 5.0)), "behind the eye")
	assert_null(CameraRig.screen_of(camera, Vector3(2.0, 0.0, 0.0)), "level with the eye")
	var ahead: Variant = CameraRig.screen_of(camera, Vector3(0.0, 0.0, -5.0))
	assert_typeof(ahead, TYPE_VECTOR2)
	var vp_centre := Vector2(camera.get_viewport().get_visible_rect().size) * 0.5
	assert_true((ahead as Vector2).is_equal_approx(vp_centre), "straight ahead is the centre")


func test_screen_of_matches_unproject_in_front_for_the_orthographic_camera() -> void:
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	add_child_autofree(camera)
	var point := Vector3(1.0, 2.0, -4.0)
	var screen: Variant = CameraRig.screen_of(camera, point)
	assert_typeof(screen, TYPE_VECTOR2)
	assert_true((screen as Vector2).is_equal_approx(camera.unproject_position(point)))


# --- the seam ---


func test_the_orbit_view_is_the_active_mode_at_start() -> void:
	var cc := _game_map.get_camera_controller()
	assert_true(cc.view_mode() is OrbitView)
	assert_eq(cc.view_mode().mode_name(), &"orbit")
	assert_eq(cc.view_mode().fov_deg(), 0.0, "orthographic")
	assert_eq(_game_map.camera_node.projection, Camera3D.PROJECTION_ORTHOGONAL)


func test_a_fake_view_takes_the_keys_the_frames_and_the_wheel() -> void:
	var cc := _game_map.get_camera_controller()
	var orbit := cc.view_mode() as OrbitView
	var fake := FakeView.new()
	cc.set_view_mode(fake)
	assert_eq(fake.activations, 1)
	assert_eq(cc.view_mode(), fake)
	cc._unhandled_key_input(_forward_key())
	assert_eq(fake.keys.size(), 1, "the key goes to the active view")
	assert_eq(orbit.camera_move_dir, Vector3.ZERO, "and not to the deactivated orbit")
	cc._process(1.0 / 60.0)
	assert_eq(fake.frames, 1)
	cc.zoom_out_step()
	cc.zoom_in_step()
	assert_eq(fake.notches, [1, -1] as Array[int])
	cc.start_pan(Vector2(5.0, 5.0))
	assert_eq(fake.pans, 1)
	assert_false(orbit.is_panning(), "the orbit view saw no pan")


func test_deactivating_the_orbit_view_leaves_no_input_state() -> void:
	var cc := _game_map.get_camera_controller()
	var orbit := cc.view_mode() as OrbitView
	orbit.handle_input(_forward_key())
	orbit.camera_velocity = Vector3(3.0, 0.0, 3.0)
	orbit.current_edge_pan = Vector2(1.0, 0.0)
	orbit.pan_begin(Vector2(10.0, 10.0), true)
	assert_ne(orbit.camera_move_dir, Vector3.ZERO)
	cc.set_view_mode(FakeView.new())
	assert_eq(orbit.camera_move_dir, Vector3.ZERO, "held key forgotten")
	assert_eq(orbit.camera_velocity, Vector3.ZERO, "velocity stopped")
	assert_eq(orbit.current_edge_pan, Vector2.ZERO, "edge pan stopped")
	assert_false(orbit.is_panning(), "pan dropped")
	assert_false(orbit.is_rmb_pan_active())


func test_swapping_back_restores_the_orbit_view_and_the_picture() -> void:
	var cc := _game_map.get_camera_controller()
	var orbit := cc.view_mode() as OrbitView
	var camera := _game_map.camera_node
	var size_before := camera.size
	var position_before := camera.position
	var fake := FakeView.new()
	cc.set_view_mode(fake)
	cc.set_view_mode(orbit)
	assert_eq(fake.deactivations, 1)
	assert_eq(cc.view_mode(), orbit)
	assert_eq(camera.projection, Camera3D.PROJECTION_ORTHOGONAL)
	assert_almost_eq(camera.size, size_before, 0.0001)
	assert_true(camera.position.is_equal_approx(position_before), "same placement")
	cc._unhandled_key_input(_forward_key())
	assert_ne(orbit.camera_move_dir, Vector3.ZERO, "the orbit view takes keys again")


func test_the_same_or_a_null_mode_changes_nothing() -> void:
	var cc := _game_map.get_camera_controller()
	var orbit := cc.view_mode()
	cc.set_view_mode(orbit)
	cc.set_view_mode(null)
	assert_eq(cc.view_mode(), orbit)
