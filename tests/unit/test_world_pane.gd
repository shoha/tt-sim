extends GutTest

## WorldPane: scale tiles track the matching preset (Custom appears only when
## nothing matches), and foliage rows round-trip.


func _pane() -> WorldPane:
	var pane := WorldPane.new()
	add_child_autofree(pane)
	return pane


func _state() -> LevelVisualState:
	var state := LevelVisualState.new()
	state.grid_cell_size = 1.0
	state.display_unit = "m"
	state.display_unit_per_cell = 1.0
	state.foliage.tree_sway_speed = 2.0
	state.foliage.tree_sway_amplitude = 0.2
	state.foliage.grass_sway_speed = 3.0
	state.foliage.grass_sway_amplitude = 0.3
	return state


func test_round_trip_every_field() -> void:
	var pane := _pane()
	var state := _state()
	pane.load_state(state)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.grid_cell_size, 1.0)
	assert_eq(out.display_unit, "m")
	assert_eq(out.display_unit_per_cell, 1.0)
	assert_eq(out.foliage.to_dict(), state.foliage.to_dict())


func test_load_selects_matching_scale_tile_and_hides_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	assert_eq(pane._scale_tiles.selected, &"metric_1m")
	assert_false(pane._scale_tiles._tiles[&"custom"].visible)


func test_manual_cell_size_switches_to_custom() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_cell_size_changed(1.3)
	assert_eq(pane._scale_tiles.selected, &"custom")
	assert_true(pane._scale_tiles._tiles[&"custom"].visible)
	assert_signal_emitted_with_parameters(pane, "scale_config_changed", [1.3, "m", 1.0])
	assert_signal_emitted(pane, "changed")


func test_scale_tile_applies_preset() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_scale_preset_selected(&"dnd_5ft")
	var preset: Dictionary = ScaleUtils.PRESETS["dnd_5ft"]
	assert_eq(pane.grid_cell_size, preset.grid_cell_size)
	assert_eq(pane._cell_size_row.value, preset.grid_cell_size)
	assert_signal_emitted_with_parameters(
		pane,
		"scale_config_changed",
		[preset.grid_cell_size, preset.display_unit, preset.display_unit_per_cell]
	)


func test_foliage_edit_emits() -> void:
	var pane := _pane()
	pane.load_state(_state())
	watch_signals(pane)
	pane._on_foliage_changed(4.0, "grass_sway_speed")
	var params: Array = get_signal_parameters(pane, "foliage_changed")
	assert_eq(params[0]["grass_sway_speed"], 4.0)
	assert_signal_emit_count(pane, "changed", 1)


func test_load_selects_matching_wind_tile() -> void:
	var pane := _pane()
	var state := LevelVisualState.new()
	pane.load_state(state)
	assert_eq(pane._wind_field.tiles.selected, &"breeze", "defaults are a breeze")
	state.foliage.tree_sway_amplitude = 0.0
	state.foliage.grass_sway_amplitude = 0.0
	pane.load_state(state)
	assert_eq(pane._wind_field.tiles.selected, &"still")


func test_wind_tile_applies_values_once_and_custom_is_silent() -> void:
	var pane := _pane()
	pane.load_state(LevelVisualState.new())
	watch_signals(pane)
	pane._on_wind_selected(&"gusty")
	assert_eq(pane._foliage.tree_sway_speed, 1.2)
	assert_eq(pane._foliage.grass_sway_amplitude, 0.08)
	assert_eq(pane._foliage_rows["grass_sway_speed"].value, 2.5)
	assert_signal_emit_count(pane, "foliage_changed", 1)
	pane._on_wind_selected(&"custom")
	assert_signal_emit_count(pane, "foliage_changed", 1)
	pane._on_foliage_changed(9.9, "tree_sway_speed")
	assert_eq(pane._wind_field.tiles.selected, &"custom")


func test_scale_tiles_are_a_field_and_cell_size_reads_in_units() -> void:
	var pane := _pane()
	assert_same(pane._scale_tiles, pane._scale_field.tiles)
	assert_eq(WorldPane.format_cell_size(1.524), "1.52 m (5 ft)")
	assert_eq(WorldPane.format_cell_size(1.0), "1.00 m (3.3 ft)")
	assert_eq(pane._foliage_rows["tree_sway_amplitude"].hint_high, "Wild")
