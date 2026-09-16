extends GutTest

## SkyPane: painted sky tiles and the grouped preset dropdown write the model,
## map options toggle the revert button and the map-default sky tile, and
## write_state carries preset + overrides.

var _model: EnvironmentEditModel


func _pane() -> SkyPane:
	_model = EnvironmentEditModel.new()
	_model.load_from("outdoor_day", {}, {})
	var pane := SkyPane.new()
	pane.set_model(_model)
	add_child_autofree(pane)
	pane.load_state(LevelVisualState.new())
	return pane


func _index_of_preset(pane: SkyPane, preset: String) -> int:
	for i in range(pane._preset_dropdown.item_count):
		if pane._preset_dropdown.get_item_metadata(i) == preset:
			return i
	return -1


func test_write_state_carries_preset_and_overrides() -> void:
	var pane := _pane()
	_model.set_override("fog_density", 0.05)
	var out := LevelVisualState.new()
	pane.write_state(out)
	assert_eq(out.environment_preset, "outdoor_day")
	assert_eq(out.environment_overrides.get("fog_density"), 0.05)
	out.environment_overrides["probe"] = 1
	assert_false(_model.overrides.has("probe"), "write_state hands out an independent copy")


func test_preset_selection_writes_model_and_emits_changed() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_preset_selected(_index_of_preset(pane, "dungeon_dark"))
	assert_eq(_model.preset, "dungeon_dark")
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
	assert_true(pane._sky_field.overridden)


func test_map_options_toggle_revert_and_map_default_tile() -> void:
	var pane := _pane()
	assert_false(pane._revert_button.visible)
	assert_false(pane._sky_tiles._tiles[&"map_default"].visible)
	pane.set_map_options(true, true)
	assert_true(pane._revert_button.visible)
	assert_true(pane._sky_tiles._tiles[&"map_default"].visible)
	assert_ne(_index_of_preset(pane, ""), -1, "Map Defaults entry present")


func test_no_map_defaults_offers_no_preset_and_an_honest_caption() -> void:
	var pane := _pane()
	pane.set_map_options(false, false)
	_model.set_preset("")
	assert_eq(pane._preset_dropdown.get_item_metadata(pane._preset_dropdown.selected), "")
	assert_eq(pane._preset_dropdown.get_item_text(pane._preset_dropdown.selected), "No preset")
	assert_eq(pane._preset_caption.text, "No preset: engine defaults")
	pane.set_map_options(true, true)
	var idx := _index_of_preset(pane, "")
	assert_eq(idx, 0)
	assert_eq(pane._preset_dropdown.get_item_text(idx), "Map defaults")
	assert_eq(pane._preset_caption.text, "The map's own lighting")


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


func test_load_selects_preset_and_shows_its_description() -> void:
	var pane := _pane()
	var selected: int = pane._preset_dropdown.selected
	assert_eq(pane._preset_dropdown.get_item_metadata(selected), "outdoor_day")
	assert_eq(pane._preset_dropdown.get_item_text(selected), "Outdoor Day")
	assert_eq(pane._preset_caption.text, EnvironmentPresets.get_preset_description("outdoor_day"))


func test_picker_has_a_separator_per_group_and_swatches() -> void:
	var pane := _pane()
	var separators := 0
	var swatches := 0
	for i in range(pane._preset_dropdown.item_count):
		if pane._preset_dropdown.is_item_separator(i):
			separators += 1
		elif pane._preset_dropdown.get_item_icon(i) != null:
			swatches += 1
	assert_eq(separators, EnvironmentPresets.PRESET_GROUPS.size())
	assert_eq(swatches, EnvironmentPresets.PRESETS.size())


func test_sky_tiles_are_ten_in_order_five_per_row_with_thumbnails() -> void:
	var pane := _pane()
	assert_true(pane._sky_field is TileField)
	assert_eq(
		pane._sky_tiles._tiles.keys(),
		[
			&"",
			&"map_default",
			&"clear_day",
			&"cloudy",
			&"overcast",
			&"morning",
			&"sunset",
			&"dusk",
			&"storm",
			&"night_sky",
		]
	)
	assert_eq(pane._sky_tiles.columns, 5)
	assert_eq(pane._sky_tiles.tile_min_size, Vector2(52, 52))
	assert_same(pane._sky_tiles._tiles[&"storm"].icon, SwatchTextures.sky_gradient("storm"))
	assert_same(pane._sky_tiles._tiles[&"night_sky"].icon, SwatchTextures.sky_gradient("night_sky"))
	assert_false(pane._sky_tiles._tiles[&"map_default"].visible)


func test_fog_colour_lives_in_advanced_with_its_own_reset() -> void:
	var pane := _pane()
	pane._fog_color_row._picker.color = Color.RED
	pane._fog_color_row._on_color_changed(Color.RED)
	assert_eq(_model.overrides["fog_light_color"], Color.RED)
	assert_true(pane._fog_color_row.overridden)
	pane._on_reset_requested(["fog_light_color"])
	assert_false(pane._fog_color_row.overridden)
	assert_eq(pane._fog_row.hint_high, "Thick")
	assert_eq(pane._fog_height_density_row._label.text, "Fog falloff")


func test_preview_shows_the_selected_sky_and_its_description() -> void:
	var pane := _pane()
	assert_true(pane._sky_preview.visible)
	assert_same(pane._sky_preview.texture, SwatchTextures.sky_preview("clear_day"))
	assert_eq(pane._sky_caption.text, EnvironmentPresets.get_sky_preset_description("clear_day"))


func test_hover_previews_without_touching_the_model_then_reverts() -> void:
	var pane := _pane()
	watch_signals(pane)
	pane._on_sky_tile_hovered(&"storm")
	assert_same(pane._sky_preview.texture, SwatchTextures.sky_preview("storm"))
	assert_eq(pane._sky_caption.text, EnvironmentPresets.get_sky_preset_description("storm"))
	assert_eq(_model.resolve().get("sky_preset", ""), "clear_day", "hover is not an edit")
	assert_signal_not_emitted(pane, "changed")
	pane._on_sky_tile_unhovered(&"storm")
	assert_same(pane._sky_preview.texture, SwatchTextures.sky_preview("clear_day"))


func test_none_and_map_hide_the_strip_with_honest_captions() -> void:
	var pane := _pane()
	pane._on_sky_tile_hovered(&"")
	assert_false(pane._sky_preview.visible)
	assert_eq(pane._sky_caption.text, SkyPane.CAPTION_NONE)
	pane._on_sky_tile_unhovered(&"")
	pane._on_sky_tile_hovered(&"map_default")
	assert_false(pane._sky_preview.visible)
	assert_eq(pane._sky_caption.text, SkyPane.CAPTION_MAP)
	pane._on_sky_tile_unhovered(&"map_default")
	assert_true(pane._sky_preview.visible, "back to the selected sky")


func test_selecting_a_tile_updates_the_preview() -> void:
	var pane := _pane()
	pane._on_sky_selected(&"dusk")
	assert_same(pane._sky_preview.texture, SwatchTextures.sky_preview("dusk"))
	assert_eq(pane._sky_caption.text, EnvironmentPresets.get_sky_preset_description("dusk"))
