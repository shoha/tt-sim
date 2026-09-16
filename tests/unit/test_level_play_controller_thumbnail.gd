extends GutTest

## capture_thumbnail is null without a map and save_level_with_thumbnail never
## fails a save because the thumbnail could not be written.


func test_capture_is_null_without_a_game_map() -> void:
	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	assert_null(controller.capture_thumbnail())


func test_save_with_thumbnail_skips_the_image_when_capture_fails() -> void:
	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	var calls := []
	controller._save_thumbnail = func(_level: LevelData, _image: Image) -> bool:
		calls.append(true)
		return true
	controller._save_level_impl = func() -> String: return "user://levels/x/"
	assert_eq(controller.save_level_with_thumbnail(), "user://levels/x/")
	assert_eq(calls.size(), 0, "no image, no thumbnail write")
