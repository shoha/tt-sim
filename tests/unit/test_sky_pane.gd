extends GutTest

## SkyPane: preset dropdown and sky tiles write the model, light scale is its
## own signal, map options toggle the revert button and the map-default sky
## tile, and write_state carries preset + overrides + light scale.

var _model: EnvironmentEditModel


func _pane() -> SkyPane:
	_model = EnvironmentEditModel.new()
	_model.load_from("outdoor_day", {}, {})
	var pane := SkyPane.new()
	pane.set_model(_model)
	add_child_autofree(pane)
	var state := LevelVisualState.new()
	state.light_intensity_scale = 1.4
	pane.load_state(state)
	return pane


func _index_of_preset(pane: SkyPane, preset: String) -> int:
	for i in range(pane._preset_dropdown.item_count):
		if pane._preset_dropdown.get_item_metadata(i) == preset:
			return i
	return -1


func test_load_sets_light_scale_and_selects_preset() -> void:
	var pane := _pane()
	assert_eq(pane._intensity_row.value, 1.4)
	var selected: int = pane._preset_dropdown.selected
	assert_eq(pane._preset_dropdown.get_item_metadata(selected), "outdoor_day")


func test_write_state_carries_preset_overrides_and_scale() -> void:
	var pane := _pane()
	_model.set_override("fog_density", 0.05)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.environment_preset, "outdoor_day")
	assert_eq(out.environment_overrides.get("fog_density"), 0.05)
	assert_eq(out.light_intensity_scale, 1.4)
	assert_ne(out.environment_overrides, _model.overrides, "independent copy")


func test_preset_selection_writes_model_and_emits_changed() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_preset_selected(_index_of_preset(pane, "dungeon_dark"))
	assert_eq(_model.preset, "dungeon_dark")
	assert_signal_emitted(pane, "changed")


func test_light_scale_edit_emits_intensity_changed() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_intensity_changed(0.5)
	assert_eq(pane.light_intensity_scale, 0.5)
	assert_signal_emitted_with_parameters(pane, "intensity_changed", [0.5])
	assert_signal_emitted(pane, "changed")


func test_fog_row_writes_three_keys_and_tints() -> void:
	var pane := _pane()
	pane._fog_row._check.button_pressed = true
	pane._fog_row._slider.value = 0.02
	assert_true(_model.overrides["fog_enabled"])
	assert_eq(_model.overrides["fog_density"], 0.02)
	assert_true(pane._fog_row.overridden)
	pane._on_reset_requested(SkyPane.FOG_KEYS)
	assert_false(pane._fog_row.overridden)


func test_sky_tile_sets_sky_preset() -> void:
	var pane := _pane()
	pane._on_sky_selected(&"sunset")
	assert_eq(_model.overrides["sky_preset"], "sunset")
	assert_eq(_model.overrides["background_mode"], Environment.BG_SKY)
	assert_true(pane._sky_row.overridden)


func test_map_options_toggle_revert_and_map_default_tile() -> void:
	var pane := _pane()
	assert_false(pane._revert_button.visible)
	assert_false(pane._sky_tiles._tiles[&"map_default"].visible)
	pane.set_map_options(true, true)
	assert_true(pane._revert_button.visible)
	assert_true(pane._sky_tiles._tiles[&"map_default"].visible)
	assert_ne(_index_of_preset(pane, ""), -1, "Map Defaults entry present")


func test_revert_and_clear() -> void:
	var pane := _pane()
	watch_signals(pane)
	assert_true(pane._clear_button.disabled)
	pane._on_revert_pressed()
	assert_signal_emitted(pane, "revert_to_map_defaults_requested")
	_model.set_override("fog_density", 0.05)
	assert_false(pane._clear_button.disabled)
	pane._on_clear_pressed()
	assert_true(_model.overrides.is_empty())
	assert_true(pane._clear_button.disabled)
