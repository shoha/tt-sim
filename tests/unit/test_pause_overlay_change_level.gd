extends GutTest

## The pause menu offers Change Level to the GM and relays the picked level.

const SCENE := preload("res://scenes/states/paused/pause_overlay.tscn")


func test_change_level_visibility_matches_edit_level() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	assert_eq(overlay.change_level_button.visible, overlay.edit_level_button.visible)


func test_picked_level_is_relayed() -> void:
	var overlay = SCENE.instantiate()
	add_child_autofree(overlay)
	watch_signals(overlay)
	var info := {"path": "user://x/a/", "name": "Alpha"}
	overlay._on_level_picked(info)
	assert_signal_emitted_with_parameters(overlay, "change_level_requested", [info])
