extends GutTest

## WeatherRenderer's rain collision heightfield exists only while rain or snow falls, and goes in
## a few drawn frames after they start (card firstview): kept on with no weather, its render
## compiled 3 to 7 pipelines on the main thread in a map's first view.


func _renderer() -> WeatherRenderer:
	var holder: Node3D = add_child_autofree(Node3D.new())
	var camera := Camera3D.new()
	holder.add_child(camera)
	var manager := LevelEnvironmentManager.new()
	manager.apply_level_environment(LevelData.new(), holder)
	var renderer := WeatherRenderer.new()
	holder.add_child(renderer)
	renderer.setup(camera, manager)
	return renderer


## Makes the pending heightfield due now (headless runs draw no frames) and adds it.
func _add_when_due(renderer: WeatherRenderer) -> void:
	if renderer._collision_due_frame >= 0:
		renderer._collision_due_frame = Engine.get_frames_drawn()
	renderer._add_rain_collision_when_due()


func test_no_collision_without_rain_or_snow() -> void:
	var renderer := _renderer()
	_add_when_due(renderer)
	assert_null(renderer.rain_collision(), "clear weather has no heightfield")
	assert_eq(
		renderer.find_children("*", "GPUParticlesCollisionHeightField3D", true, false).size(), 0
	)


func test_rain_adds_the_collision_a_few_frames_later() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"rain_intensity": 0.5})
	assert_null(renderer.rain_collision(), "not in the frame the rain starts")
	assert_eq(
		renderer._collision_due_frame,
		Engine.get_frames_drawn() + WeatherRenderer.COLLISION_DELAY_FRAMES
	)
	_add_when_due(renderer)
	var collision := renderer.rain_collision()
	assert_not_null(collision, "rain falls on a heightfield")
	assert_true(collision.is_inside_tree())
	assert_true(collision.follow_camera_enabled)


func test_snow_adds_the_collision() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"snow_intensity": 0.5})
	_add_when_due(renderer)
	assert_not_null(renderer.rain_collision())


func test_wind_alone_adds_no_collision() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"wind_intensity": 0.5})
	_add_when_due(renderer)
	assert_null(renderer.rain_collision(), "wind streaks do not collide")


func test_rain_stopped_before_due_adds_none() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"rain_intensity": 0.5})
	renderer._rain_emitter.emitting = false
	renderer._refresh_process_state()
	_add_when_due(renderer)
	assert_null(renderer.rain_collision())


func test_the_collision_goes_once_nothing_falls() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"rain_intensity": 0.5})
	_add_when_due(renderer)
	var collision := renderer.rain_collision()
	renderer._rain_emitter.emitting = false
	renderer._drop_rain_collision()
	assert_null(renderer.rain_collision())
	assert_true(collision.is_queued_for_deletion())


func test_the_collision_stays_while_snow_still_falls() -> void:
	var renderer := _renderer()
	renderer.apply_weather({"rain_intensity": 0.5, "snow_intensity": 0.5})
	_add_when_due(renderer)
	renderer._rain_emitter.emitting = false
	renderer._drop_rain_collision()
	assert_not_null(renderer.rain_collision(), "snow still falls on it")
