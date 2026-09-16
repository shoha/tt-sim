extends GutTest

## LevelGrid builds one card per level from its provider, tracks selection,
## relays activation, and runs the card actions through LevelManager.

const TEMP_DIR := "user://test_levels_grid/"

var _levels: Array[Dictionary] = []


func before_each() -> void:
	LevelManager.levels_dir = TEMP_DIR
	DirAccess.make_dir_recursive_absolute(TEMP_DIR)
	_levels = [
		_info("a", "Alpha", 300),
		_info("b", "Bravo", 200),
		_info("c", "Charlie", 100),
	]


func after_each() -> void:
	# Duplicate folders are named by slugifying the new level name (e.g.
	# "Alpha (Copy)" -> "alpha_copy"), not by a predictable suffix, so sweep
	# whatever is actually on disk rather than a fixed folder list. Loose
	# files (legacy .tres levels saved directly under TEMP_DIR) are swept too,
	# so they don't leak into later tests in the same run.
	var dir := DirAccess.open(TEMP_DIR)
	if dir:
		dir.list_dir_begin()
		var entry_name := dir.get_next()
		while entry_name != "":
			if dir.current_is_dir() and not entry_name.begins_with("."):
				LevelManager.delete_level_folder(TEMP_DIR + entry_name + "/")
			elif not dir.current_is_dir():
				DirAccess.remove_absolute(TEMP_DIR + entry_name)
			entry_name = dir.get_next()
		dir.list_dir_end()
		DirAccess.remove_absolute(TEMP_DIR)
	LevelManager.levels_dir = Paths.LEVELS_DIR


func _info(folder: String, name: String, modified: int) -> Dictionary:
	return {
		"path": TEMP_DIR + folder + "/",
		"folder": folder,
		"is_folder_based": true,
		"name": name,
		"token_count": 0,
		"modified_at": modified,
		"environment_preset": "",
		"thumbnail": "",
	}


func _grid() -> LevelGrid:
	var grid := LevelGrid.new()
	grid.provider = func() -> Array[Dictionary]: return _levels
	add_child_autofree(grid)
	grid.refresh()
	return grid


func test_refresh_builds_a_card_per_level_in_provider_order() -> void:
	var grid := _grid()
	assert_eq(grid.card_count(), 3)
	assert_eq(grid._cards[0].level_info["name"], "Alpha")
	assert_eq(grid._cards[2].level_info["name"], "Charlie")


func test_select_and_selection_signal() -> void:
	var grid := _grid()
	watch_signals(grid)
	grid.select(TEMP_DIR + "b/")
	assert_eq(grid.selected_info()["name"], "Bravo")
	assert_true(grid._cards[1].button_pressed)
	assert_signal_not_emitted(grid, "selection_changed", "programmatic select is silent")
	grid._cards[2]._on_pressed()
	assert_signal_emitted_with_parameters(grid, "selection_changed", [_levels[2]])
	assert_eq(grid.selected_info()["name"], "Charlie")


func test_activation_relays_the_card() -> void:
	var grid := _grid()
	watch_signals(grid)
	grid._cards[0].activated.emit(_levels[0])
	assert_signal_emitted_with_parameters(grid, "level_activated", [_levels[0]])


func test_locked_path_disables_delete_on_that_card() -> void:
	var grid := LevelGrid.new()
	grid.provider = func() -> Array[Dictionary]: return _levels
	grid.locked_path = TEMP_DIR + "a/"
	add_child_autofree(grid)
	grid.refresh()
	assert_true(grid._cards[0].locked)
	assert_false(grid._cards[1].locked)


func test_delete_confirms_then_removes_and_refreshes() -> void:
	_write_real_level("b", "Bravo")
	var grid := _grid()
	var asked := []
	grid.confirm_delete = func(title: String, _message: String, on_confirm: Callable) -> void:
		asked.append(title)
		on_confirm.call()
	grid.select(TEMP_DIR + "b/")
	grid._on_card_action(_levels[1], &"delete")
	assert_eq(asked, ["Delete Bravo?"])
	assert_false(DirAccess.dir_exists_absolute(TEMP_DIR + "b/"))


func test_duplicate_refreshes_and_selects_the_copy() -> void:
	_write_real_level("a", "Alpha")
	var grid := LevelGrid.new()
	add_child_autofree(grid)
	grid.refresh()
	assert_eq(grid.card_count(), 1)
	grid._on_card_action(grid._cards[0].level_info, &"duplicate")
	assert_eq(grid.card_count(), 2)
	assert_eq(grid.selected_info()["name"], "Alpha (Copy)")


func test_rename_writes_through_and_refreshes() -> void:
	_write_real_level("a", "Alpha")
	var grid := LevelGrid.new()
	add_child_autofree(grid)
	grid.refresh()
	grid._on_card_rename(grid._cards[0].level_info, "Omega")
	assert_eq(grid._cards[0].level_info["name"], "Omega")


func test_two_columns_fit_side_by_side_with_a_scrollbar() -> void:
	var levels: Array[Dictionary] = [
		_info("a", "Alpha", 100),
		_info("b", "Bravo", 200),
		_info("c", "Charlie", 300),
		_info("d", "Delta", 400),
		_info("e", "Echo", 500),
		_info("f", "Foxtrot", 600),
	]
	var grid := LevelGrid.new()
	grid.provider = func() -> Array[Dictionary]: return levels
	grid.columns = 2
	grid.size = Vector2(616, 360)
	add_child_autofree(grid)
	grid.refresh()
	await wait_frames(3)
	assert_gt(grid.card_count(), 5, "needs enough cards to overflow 360 px")
	var first: Control = grid._cards[0]
	var second: Control = grid._cards[1]
	assert_eq(first.position.y, second.position.y, "second card sits beside the first")
	assert_lt(first.size.x * 2.0 + 8.0 + grid.get_v_scroll_bar().size.x, 617.0)


func test_rename_of_a_legacy_level_reselects_by_the_new_path() -> void:
	var level := LevelData.new()
	level.level_name = "Old Camp"
	level.level_folder = ""
	level.map_path = "res://map.glb"
	var old_path := LevelManager.save_level(level)
	var grid := LevelGrid.new()
	add_child_autofree(grid)
	grid.refresh()
	grid.select(old_path)
	grid._on_card_rename(grid.selected_info(), "New Camp")
	assert_eq(grid.selected_info().get("name", ""), "New Camp")
	assert_eq(grid.card_count(), 1)


func _write_real_level(folder: String, name: String) -> void:
	DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
	var data := {
		"level_name": name,
		"map_path": "map.glb",
		"modified_at": 100,
		"level_folder": folder,
		"token_placements": [],
	}
	var file := FileAccess.open(LevelManager.json_path(folder), FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var map := FileAccess.open(LevelManager.map_path(folder), FileAccess.WRITE)
	map.store_string("glb")
	map.close()
