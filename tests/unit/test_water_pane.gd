extends GutTest

## WaterPane: three tile rows derived from the working WaterSettings (Custom
## only when nothing matches), a Clarity slider that is murkiness inverted, and
## Advanced rows that flip only their own tile row.


func _pane() -> WaterPane:
	var pane := WaterPane.new()
	add_child_autofree(pane)
	return pane


func _state() -> LevelVisualState:
	var state := LevelVisualState.new()
	state.water = WaterSettings.from_style("realistic")
	return state


func test_round_trip_every_field() -> void:
	var pane := _pane()
	var state := _state()
	state.water.caustic_scale = 3.3
	state.water.foam_color = Color(0.1, 0.2, 0.3, 0.4)
	pane.load_state(state)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.water.to_dict(), state.water.to_dict())
	out.water.wave_speed = 9.0
	assert_ne(pane._water.wave_speed, 9.0, "write_state hands out a copy")


func test_load_selects_matching_tiles_and_hides_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	assert_eq(pane._look_tiles.selected, &"realistic")
	assert_eq(pane._palette_tiles.selected, &"lake")
	assert_eq(pane._motion_tiles.selected, &"gentle")
	assert_false(pane._look_tiles._tiles[&"custom"].visible)
	assert_false(pane._palette_tiles._tiles[&"custom"].visible)
	assert_false(pane._motion_tiles._tiles[&"custom"].visible)


func test_load_sets_clarity_as_inverted_absorption() -> void:
	var pane := _pane()
	pane.load_state(_state())
	assert_almost_eq(pane._clarity_row.value, WaterPane.CLARITY_MAX - 2.2, 0.001)


func test_clarity_edit_sets_absorption_and_flips_only_color_to_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_clarity_changed(5.0)
	assert_almost_eq(pane._water.depth_absorption, WaterPane.CLARITY_MAX - 5.0, 0.001)
	assert_eq(pane._palette_tiles.selected, &"custom")
	assert_true(pane._palette_tiles._tiles[&"custom"].visible)
	assert_eq(pane._look_tiles.selected, &"realistic")
	assert_eq(pane._motion_tiles.selected, &"gentle")
	assert_signal_emitted(pane, "water_changed")
	assert_signal_emitted(pane, "changed")


func test_motion_row_edit_flips_only_motion_to_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_row_changed(2.0, "wave_speed")
	assert_almost_eq(pane._water.wave_speed, 2.0, 0.001)
	assert_eq(pane._motion_tiles.selected, &"custom")
	assert_eq(pane._look_tiles.selected, &"realistic")
	assert_eq(pane._palette_tiles.selected, &"lake")
	var emitted: Array = get_signal_parameters(pane, "water_changed")
	assert_almost_eq(float(emitted[0]["wave_speed"]), 2.0, 0.001)


func test_palette_tile_applies_its_keys_and_leaves_other_rows() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_palette_selected(&"swamp")
	assert_eq(pane._water.matching_palette(), "swamp")
	assert_eq(pane._look_tiles.selected, &"realistic")
	assert_eq(pane._motion_tiles.selected, &"gentle")
	assert_false(pane._palette_tiles._tiles[&"custom"].visible)
	assert_true(
		WaterSettings.colors_match(
			pane._color_rows["water_color"]._picker.color,
			WaterPresets.PALETTES["swamp"]["water_color"]
		)
	)
	assert_almost_eq(
		pane._clarity_row.value,
		WaterPane.CLARITY_MAX - WaterPresets.PALETTES["swamp"]["depth_absorption"],
		0.001
	)
	assert_signal_emitted(pane, "water_changed")


func test_look_and_motion_tiles_apply_their_groups() -> void:
	var pane := _pane()
	pane.load_state(_state())
	pane._on_look_selected(&"stylized")
	assert_eq(pane._water.matching_look(), "stylized")
	assert_almost_eq(pane._rows["roughness_value"].value, 0.15, 0.001)
	pane._on_motion_selected(&"rough")
	assert_eq(pane._water.matching_motion(), "rough")
	assert_almost_eq(pane._rows["wave_speed"].value, 1.4, 0.001)


func test_selecting_custom_is_not_an_edit() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_motion_selected(&"custom")
	assert_signal_not_emitted(pane, "water_changed")
	assert_signal_not_emitted(pane, "changed")


func test_color_row_edit_flips_palette_to_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_color_changed(Color.RED, "shore_color")
	assert_eq(pane._water.shore_color, Color.RED)
	assert_eq(pane._palette_tiles.selected, &"custom")
	var emitted: Array = get_signal_parameters(pane, "water_changed")
	assert_eq(emitted[0]["shore_color"], Color.RED.to_html(true))
