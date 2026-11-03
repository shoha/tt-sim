extends GutTest

## The play tools at the eye (card eyepick): the places that need a ground point under the view
## centre have a defined answer when the centre ray never meets the ground, the weather box
## surrounds the eye instead of reading the stale orthographic size, and entering authoring leaves
## the eye. The pure ray maths is in test_view_ground.gd and the drag target in
## test_drag_controller.gd.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")

var _game_map: GameMap
var _controller: CameraController


func before_each() -> void:
	var play := LevelPlayController.new()
	add_child_autofree(play)
	_game_map = GAME_MAP_SCENE.instantiate()
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	play.setup(_game_map)
	_game_map.setup(play)
	_controller = _game_map.get_camera_controller()


# --- the view centre on the ground ------------------------------------------------------


func test_the_orbit_view_has_no_eye_centre() -> void:
	assert_null(ViewGround.eye_centre(_game_map), "the orbit view keeps its plane maths")


func test_the_orbit_landing_point_is_the_plane_hit_as_before() -> void:
	var camera := _game_map.camera_node
	var centre := Vector2(_game_map.world_viewport.size) / 2.0
	var origin := camera.project_ray_origin(centre)
	var dir := camera.project_ray_normal(centre)
	var hit := origin - dir * (origin.y / dir.y)
	var point := SessionParty.camera_ground_point(_game_map)
	assert_almost_eq(point.x, hit.x, 0.001)
	assert_almost_eq(point.z, hit.z, 0.001)
	assert_eq(point.y, 0.0)


func test_at_the_eye_a_new_token_lands_ahead_of_the_feet() -> void:
	_controller.set_view_mode(_controller.eye)
	_controller.set_pitch_now(0.0)
	var foot := _controller.eye.foot()
	var point := SessionParty.camera_ground_point(_game_map)
	var ahead := Vector2(point.x, point.z) - foot
	assert_almost_eq(ahead.length(), ViewGround.AHEAD_M, 0.01, "a level view lands 5 m ahead")
	var forward := CameraRig.screen_up(_controller.current_yaw())
	assert_gt(ahead.normalized().dot(Vector2(forward.x, forward.z)), 0.99, "in front, not behind")


func test_at_the_eye_looking_down_the_landing_is_where_the_view_meets_the_ground() -> void:
	_controller.set_view_mode(_controller.eye)
	_controller.set_pitch_now(45.0)
	var foot := _controller.eye.foot()
	var point := SessionParty.camera_ground_point(_game_map)
	var distance := Vector2(point.x, point.z).distance_to(foot)
	var eye_y := _game_map.camera_node.global_position.y
	assert_almost_eq(distance, minf(eye_y, ViewGround.AHEAD_M), 0.05)


# --- the weather box ---------------------------------------------------------------------


func test_the_weather_box_is_the_visible_area_for_an_orthographic_view() -> void:
	var half := WeatherRenderer.emission_half_extent(false, 20.0, Vector2i(1920, 1080))
	assert_almost_eq(half, 20.0 * 0.5 * (1920.0 / 1080.0) * WeatherRenderer.EMISSION_MARGIN, 0.001)
	var tall := WeatherRenderer.emission_half_extent(false, 20.0, Vector2i(600, 1080))
	assert_almost_eq(tall, 10.0 * WeatherRenderer.EMISSION_MARGIN, 0.001, "the larger half wins")


func test_the_weather_box_ignores_the_stale_size_at_the_eye() -> void:
	var near := WeatherRenderer.emission_half_extent(true, 1.0, Vector2i(1920, 1080))
	var far := WeatherRenderer.emission_half_extent(true, 500.0, Vector2i(1920, 1080))
	assert_eq(near, WeatherRenderer.EYE_HALF_EXTENT)
	assert_eq(far, WeatherRenderer.EYE_HALF_EXTENT)


# --- authoring is orbit-only --------------------------------------------------------------


func test_leave_eye_returns_to_the_orbit_rig() -> void:
	_controller.set_view_mode(_controller.eye)
	assert_eq(_controller.view_mode().mode_name(), &"eye")
	_controller.leave_eye()
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	assert_eq(_game_map.camera_node.projection, Camera3D.PROJECTION_ORTHOGONAL)


func test_leave_eye_in_the_orbit_view_does_nothing() -> void:
	var size_before := _game_map.camera_node.size
	_controller.leave_eye()
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	assert_eq(_game_map.camera_node.size, size_before)


func test_entering_authoring_mode_leaves_the_eye() -> void:
	_controller.set_view_mode(_controller.eye)
	_game_map.setup_authoring()
	assert_eq(_controller.view_mode().mode_name(), &"orbit")
	assert_true(_game_map.authoring_mode)
