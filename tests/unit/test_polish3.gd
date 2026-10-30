extends GutTest

## The Building tool's third UI round (topic polish3): the "Place another" strip, the hint bar's
## stay-put row, the chips grouped by axis, the panel's title, the toggle chips' theme variation,
## and the Style tiles' wrapping names. docs/systems/structures.md "The tool".

const COTTAGE := "core:cottage"

var _saved_path: String = ""


func before_each() -> void:
	StructureRecipes.ensure_served()
	_saved_path = UiPreferences.settings_path
	UiPreferences.settings_path = "user://test_polish3_settings.cfg"
	StructureHints.reset()


func after_each() -> void:
	UiPreferences.settings_path = _saved_path
	StructureHints.reset()
	var path := "user://test_polish3_settings.cfg"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _pane() -> StructureToolPane:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	return pane


func _held() -> Structure:
	var held := Structure.new()
	held.recipe = COTTAGE
	return held


func test_the_title_fits_the_whole_catalogue() -> void:
	var header := _pane().get_node("StructureHeader") as MenuHeader
	assert_eq(header.title_label.text, "Buildings")
	assert_string_contains(header.caption_label.text, "windmills")
	assert_ne(header.caption_label.autowrap_mode, TextServer.AUTOWRAP_OFF, "a long subtitle wraps")


func test_the_chips_sit_in_captioned_groups_and_regional_is_no_chip() -> void:
	var pane := _pane()
	assert_false(pane.chip_buttons.has("regional"), "it matched 85 of 98 buildings")
	assert_true(pane.chip_buttons.has("fantasy"))
	for group: Dictionary in StructurePalette.GROUPS:
		var id := String(group["id"])
		var caption := pane.find_child("ChipGroup_" + id, true, false) as Label
		assert_not_null(caption, "a caption for %s" % id)
		assert_eq(caption.text, String(group["caption"]))
		var row := pane.find_child("ChipRow_" + id, true, false)
		assert_not_null(row)
		for item: Dictionary in StructurePalette.CHIPS:
			if item["group"] == id:
				assert_eq(pane.chip_buttons[item["id"]].get_parent(), row)
	assert_eq(StructurePalette.GROUPS.size(), 2, "Kind and Material")


func test_chips_of_one_group_widen_and_of_two_groups_narrow() -> void:
	var pane := _pane()
	pane.set_chip("fantasy", true)
	var fantasy := pane.refs().size()
	assert_gt(fantasy, 0)
	pane.set_chip("toon", true)
	assert_gt(pane.refs().size(), fantasy, "Fantasy and Toon are both kinds: either")
	pane.set_chip("stone", true)
	assert_lt(pane.refs().size(), fantasy + 13, "Stone narrows the kinds")
	assert_true(pane.refs().has("core:wizard_tower") or fantasy > 0)


func test_the_hint_bar_keeps_the_put_another_down_row_from_the_start() -> void:
	var fresh := StructureHints.rows([], true)
	assert_eq(fresh[0]["action"], "Bare ground: put another down")
	var done_all: Array = []
	for gesture: Dictionary in StructureHints.SELECTED:
		done_all.append(String(gesture["id"]))
	var kept := StructureHints.rows(done_all, true)
	assert_eq(kept.size(), 1, "every other row has faded, this one stays while a selection exists")
	assert_eq(kept[0]["action"], "Bare ground: put another down")
	assert_true(StructureHints.rows(["click"], false).size() < StructureHints.PLACING.size())


func test_the_place_strip_names_the_armed_pick_and_opens_the_palette() -> void:
	var pane := _pane()
	assert_false(pane.place_strip.visible, "no selection, no strip: the palette is on view")
	pane.select_ref("core:stone_house")
	pane.show_selection(_held())
	assert_true(pane.place_strip.visible)
	assert_eq(pane.place_name.text, "Stone house")
	assert_not_null(pane.place_thumb.texture)
	assert_true(pane.selection_box.visible)
	assert_false(pane.family_fields[0].visible)
	pane.place_button.pressed.emit()
	assert_true(pane.is_browsing())
	assert_false(pane.selection_box.visible, "the palette takes the bar's place")
	assert_true(pane.family_fields[0].visible)
	assert_true(pane.place_strip.visible, "the strip stays to go back")
	assert_eq(pane.place_button.text, StructureToolPane.PLACE_BACK)
	var picked: Array[String] = []
	pane.structure_selected.connect(func(ref: String) -> void: picked.append(ref))
	var field := pane.family_fields[0]
	var other := ""
	for ref in pane.refs():
		if ref != "core:stone_house":
			other = ref
			break
	field.tiles.select(StringName(other))
	field.tiles.selection_changed.emit(StringName(other))
	assert_eq(picked, [other] as Array[String])
	assert_false(pane.is_browsing(), "a pick closes the palette")
	assert_true(pane.selection_box.visible)
	assert_eq(pane.place_name.text, String(LibraryStructureStore.structure(other)["name"]))
	pane.show_selection(null)
	assert_false(pane.place_strip.visible)
	assert_true(pane.family_fields[0].visible)


func test_a_new_selection_ends_browsing() -> void:
	var pane := _pane()
	pane.show_selection(_held())
	pane.set_browsing(true)
	pane.show_selection(_held())
	assert_false(pane.is_browsing())
	pane.show_selection(null)
	pane.set_browsing(true)
	assert_false(pane.is_browsing(), "nothing selected, nothing to browse from")


func test_toggle_chips_use_the_toggle_chip_variation_with_an_on_state() -> void:
	var pane := _pane()
	assert_eq((pane.chip_buttons["home"] as Button).theme_type_variation, &"ToggleChip")
	var section := StructureOrnamentsSection.new()
	add_child_autofree(section)
	for kind: String in section.chips:
		assert_eq((section.chips[kind] as Button).theme_type_variation, &"ToggleChip")
	var chip: Button = pane.chip_buttons["home"]
	var off := chip.get_theme_stylebox(&"normal") as StyleBoxFlat
	var on := chip.get_theme_stylebox(&"pressed") as StyleBoxFlat
	assert_not_null(off)
	assert_not_null(on)
	assert_ne(on.bg_color, off.bg_color, "on is filled, off is not")
	assert_gt(on.bg_color.a, 0.9, "a solid fill, not a faint outline")


func test_style_tile_names_wrap_instead_of_ending_in_dots() -> void:
	var pane := _pane()
	pane.show_selection(_held())
	assert_not_null(pane.variant_field)
	for id in pane.variant_field.tiles._tiles:
		var tile: Button = pane.variant_field.tiles._tiles[id]
		assert_ne(tile.autowrap_mode, TextServer.AUTOWRAP_OFF)
	assert_gte(StructureToolPane.VARIANT_TILE_SIZE.y, 90.0, "room for two lines")
