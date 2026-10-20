extends GutTest

## CameraController.is_at_rest and finish_zoom, which the render jobs' `settle` op waits on
## and ends with: a zoom or a home reset is not at rest while it eases, is at rest once it
## has eased, and finish_zoom lands the size exactly on its target. The real GameMap scene
## (wired as test_map_view_fit.gd wires it), no level loaded.

const GAME_MAP_SCENE := preload("res://scenes/states/playing/game_map.tscn")
const EASE_TIMEOUT := 5.0

var _game_map: GameMap


func before_each() -> void:
	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	_game_map = GAME_MAP_SCENE.instantiate()
	# DragAndDrop3D awaits the current scene's ready signal, and GUT's runner has no current
	# scene: a stand-in whose ready has already fired lets that wait sit harmlessly.
	var stand_in := Node.new()
	get_tree().root.add_child(stand_in)
	get_tree().current_scene = stand_in
	add_child_autofree(_game_map)
	get_tree().current_scene = null
	stand_in.free()
	controller.setup(_game_map)
	_game_map.setup(controller)


## Frames until the camera is at rest, or -1 after EASE_TIMEOUT seconds.
func _frames_to_rest(cc: CameraController) -> int:
	var started := Time.get_ticks_msec()
	var frames := 0
	while not cc.is_at_rest():
		if Time.get_ticks_msec() - started > EASE_TIMEOUT * 1000.0:
			return -1
		await get_tree().process_frame
		frames += 1
	return frames


func test_a_zoom_is_at_rest_once_it_has_eased() -> void:
	var cc := _game_map.get_camera_controller()
	assert_gt(await _frames_to_rest(cc), -1, "at rest after setup")
	var before := _game_map.camera_node.size
	cc.adjust_zoom(4.0)
	assert_false(cc.is_at_rest(), "easing toward the new zoom")
	var frames: int = await _frames_to_rest(cc)
	assert_gt(frames, 1, "the ease takes frames")
	var target := CameraController.compute_aspect_corrected_size(
		cc.get("_target_zoom"), _game_map.world_viewport.size, CameraController.REFERENCE_ASPECT
	)
	assert_almost_eq(_game_map.camera_node.size, target, 0.001)
	assert_gt(_game_map.camera_node.size, before)
	cc.finish_zoom()
	# Camera3D keeps its size in single precision: compare with the target stored the same way.
	var stored := Camera3D.new()
	stored.size = target
	assert_eq(_game_map.camera_node.size, stored.size, "finish_zoom lands exactly on the target")
	stored.free()
	assert_true(cc.is_at_rest())


func test_a_home_reset_is_not_at_rest_while_its_tween_runs() -> void:
	var cc := _game_map.get_camera_controller()
	await _frames_to_rest(cc)
	_game_map.cameraholder_node.global_position += Vector3(6.0, 0.0, -4.0)
	cc.call("_reset_camera_to_home")
	assert_false(cc.is_at_rest(), "the home tween is running")
	assert_gt(await _frames_to_rest(cc), 0, "at rest when the tween is done")
