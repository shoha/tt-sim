extends GutTest

## The Settings menu's groups (SettingsSpec, SettingsLayout), the per-group Reset, the unsaved
## mark, the search, the keyboard reach and the sheet's fit at a small window
## (docs/UI_SYSTEMS.md "Settings").

const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")
const TMP_SETTINGS := "user://_ui_settings_test.cfg"

var _menu: SettingsMenu


func before_each() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child_autofree(_menu)


func after_each() -> void:
	if FileAccess.file_exists(TMP_SETTINGS):
		DirAccess.remove_absolute(TMP_SETTINGS)


func _controls_of(group_title: String) -> Array:
	for group in _menu.layout.groups:
		if group.title == group_title:
			return group.controls
	return []


func _group(tab: String, title: String) -> Dictionary:
	for group in _menu.layout.groups:
		if group.tab == tab and group.title == title:
			return group
	return {}


func test_every_listed_row_stands_in_its_group_with_its_sentence() -> void:
	for tab_name in SettingsSpec.TABS:
		for spec in SettingsSpec.TABS[tab_name]:
			var group := _group(tab_name, spec.title)
			assert_false(group.is_empty(), "%s / %s" % [tab_name, spec.title])
			for row_spec in spec.rows:
				var block := _menu.find_child("RowBlock_" + String(row_spec.row), true, false)
				assert_not_null(block, "row %s has its block" % row_spec.row)
				if block and row_spec.has("desc"):
					assert_not_null(block.get_node_or_null("Description"), row_spec.row)


func test_no_row_is_left_outside_a_group() -> void:
	for tab in _menu.tab_container.get_children():
		var content := tab.get_node_or_null("Margin/Content")
		assert_not_null(content, tab.name)
		for child in content.get_children():
			if child.is_queued_for_deletion():
				continue
			var grouped: bool = String(child.name).begins_with("Group_") or child is Foldout
			assert_true(grouped, "%s holds a stray %s" % [tab.name, child.name])
	assert_true(_group("Graphics", "More").is_empty(), "no row fell into More")


func test_unique_names_still_resolve_after_the_rows_move() -> void:
	for node_name in ["InterfaceSizeOption", "ReduceMotionCheck", "WindMotionSlider", "VSyncCheck"]:
		assert_not_null(_menu.get_node_or_null("%" + node_name), node_name)
	assert_not_null(_menu.get_node_or_null("%QualityOption"))


func test_accessibility_holds_size_and_motion() -> void:
	var tab := _menu.tab_container.get_node("Accessibility")
	for row_name in ["InterfaceSize", "ReduceMotion", "WindMotion"]:
		assert_not_null(tab.find_child(row_name, true, false), row_name)
	assert_null(_menu.tab_container.get_node("Graphics").find_child("ReduceMotion", true, false))


func test_every_value_control_is_reachable_by_keyboard() -> void:
	for control in _menu.session.value_controls():
		assert_ne(control.focus_mode, Control.FOCUS_NONE, "%s takes focus" % control.name)
	for tab in _menu.tab_container.get_children():
		assert_true((tab as ScrollContainer).follow_focus, "%s follows focus" % tab.name)
	for spec in SettingsMenu.SECTIONS:
		var button := _menu.section_rail._buttons[StringName(spec[0])] as Control
		assert_eq(button.focus_mode, Control.FOCUS_ALL, "%s rail item takes focus" % spec[0])
	for group in _menu.layout.groups:
		var reset := group.reset as Button
		if reset:
			assert_eq(reset.focus_mode, Control.FOCUS_ALL, "%s Reset takes focus" % group.title)


func test_section_keys_step_through_the_rail() -> void:
	_menu.section_rail.select(&"Audio")
	_menu._step_section(1)
	assert_eq(_menu.section_rail.selected, &"Graphics")
	_menu._step_section(-1)
	_menu._step_section(-1)
	assert_eq(_menu.section_rail.selected, &"About", "wraps from the first to the last")


func test_group_reset_puts_only_that_group_back() -> void:
	_menu.shadow_quality_option.select(_menu.shadow_quality_option.get_item_index(1))
	_menu.antialiasing_option.select(_menu.antialiasing_option.get_item_index(2))
	_menu.water_quality_option.select(_menu.water_quality_option.get_item_index(0))
	_menu.session.reset_group(_group("Graphics", "Effects"))
	assert_eq(
		_menu.shadow_quality_option.get_selected_id(), SettingsMenu.DEFAULT_SHADOW_QUALITY
	)
	assert_eq(_menu.antialiasing_option.get_selected_id(), Viewport.MSAA_DISABLED)
	assert_eq(_menu.water_quality_option.get_selected_id(), 0, "Water is another group")


func test_group_reset_glides_sliders_home() -> void:
	_menu.cell_tint_opacity_slider.set_value_no_signal(10.0)
	_menu.line_thickness_slider.set_value_no_signal(5.0)
	_menu.session.reset_group(_group("Grid", "Grid overlay"))
	await wait_seconds(UiMotion.STATE_S + 0.2)
	assert_almost_eq(_menu.cell_tint_opacity_slider.value, 65.0, 0.01)
	assert_almost_eq(_menu.line_thickness_slider.value, 2.0, 0.01)
	assert_false(_menu._resetting, "the sliders tick again once they land")


func test_group_reset_button_is_off_while_the_group_is_at_defaults() -> void:
	var group := _group("Audio", "Volume")
	_menu.session.refresh()
	assert_true((group.reset as Button).disabled)
	_menu.sfx_slider.set_value_no_signal(40.0)
	_menu.session.refresh()
	assert_false((group.reset as Button).disabled)


func test_unsaved_mark_follows_the_controls() -> void:
	assert_false(_menu.session.is_dirty())
	assert_true(_menu.apply_button.disabled, "nothing to apply yet")
	_menu.vsync_check.button_pressed = not _menu.vsync_check.button_pressed
	await wait_process_frames(2)
	assert_true(_menu.session.is_dirty())
	assert_false(_menu.apply_button.disabled)
	var status := _menu.apply_button.get_parent().get_node("Status") as Label
	assert_eq(status.text, SettingsSession.DIRTY_TEXT)
	_menu.vsync_check.button_pressed = not _menu.vsync_check.button_pressed
	await wait_process_frames(2)
	assert_false(_menu.session.is_dirty(), "putting it back is clean again")


func test_every_setting_round_trips_through_save_and_load() -> void:
	var changed := {}
	for control in _menu.session.value_controls():
		var key := String(control.name)
		if SettingsSpec.LIVE_DEFAULTS.has(key) or key == "QualityOption":
			continue
		var value: Variant = SettingsSession.value_of(control)
		if control is OptionButton:
			var option := control as OptionButton
			for i in option.item_count:
				if not option.is_item_disabled(i) and option.get_item_id(i) != value:
					value = option.get_item_id(i)
					break
		elif control is CheckButton:
			value = not value
		else:
			var slider := control as HSlider
			value = slider.min_value + (slider.max_value - slider.min_value) * 0.5
		SettingsSession.show_value(control, value)
		changed[key] = SettingsSession.value_of(control)
	_menu._save_settings(TMP_SETTINGS)
	_menu._show_defaults(true)
	_menu._load_settings(TMP_SETTINGS)
	for key in changed:
		var control := _menu.get_node("%" + String(key)) as Control
		assert_true(
			SettingsSession.same(SettingsSession.value_of(control), changed[key]),
			"%s survives save and load" % key
		)


func test_search_hides_what_does_not_match() -> void:
	_menu.layout.set_filter("shadow")
	var shadow := _menu.find_child("RowBlock_ShadowQuality", true, false) as Control
	var fullscreen := _menu.find_child("RowBlock_Fullscreen", true, false) as Control
	assert_true(shadow.visible)
	assert_false(fullscreen.visible)
	assert_false(_menu.section_rail.is_item_visible(&"Audio"))
	assert_true(_menu.section_rail.is_item_visible(&"Graphics"))
	assert_eq(_menu.section_rail.selected, &"Graphics", "moves to the section with a match")
	_menu.layout.set_filter("zzzzqq")
	assert_false(_menu.tab_container.visible)
	assert_true(_menu.get_node("CenterContainer/PanelContainer/VBoxContainer/NoResults").visible)
	_menu.layout.set_filter("")
	assert_true(fullscreen.visible)
	assert_true(_menu.section_rail.is_item_visible(&"Audio"))
	assert_true(_menu.tab_container.visible)


func test_search_finds_a_row_by_what_it_does() -> void:
	_menu.layout.set_filter("reduce animation sway")
	var wind := _menu.find_child("RowBlock_WindMotion", true, false) as Control
	assert_false(wind.visible, "sway alone is wind; reduce animation is not in its words")
	_menu.layout.set_filter("sway wind")
	assert_true(wind.visible)


func test_closing_with_unsaved_changes_puts_the_saved_values_back() -> void:
	var saved := _menu.sfx_slider.value
	_menu.sfx_slider.value = 12.0
	await wait_process_frames(2)
	assert_true(_menu.session.is_dirty())
	_menu.session.revert_if_dirty()
	assert_eq(_menu.sfx_slider.value, saved)
	assert_false(_menu.session.is_dirty())


func test_the_sheet_fits_a_small_window_and_the_last_row_scrolls_into_view() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autofree(viewport)
	var menu := MENU_SCENE.instantiate() as SettingsMenu
	viewport.add_child(menu)
	await wait_process_frames(4)
	var panel := menu.get_node("CenterContainer/PanelContainer") as Control
	var canvas := Rect2(Vector2.ZERO, Vector2(viewport.size))
	assert_true(canvas.encloses(panel.get_global_rect()), "the sheet stays on the canvas")
	for spec in SettingsMenu.SECTIONS:
		menu.section_rail.select(StringName(spec[0]))
		await wait_process_frames(2)
		var scroll := menu.tab_container.get_current_tab_control() as ScrollContainer
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
		await wait_process_frames(2)
		var last: Control = null
		for entry in menu.layout.entries:
			if entry.tab == spec[0] and (entry.block as Control).is_visible_in_tree():
				last = entry.block
		if last == null:
			continue
		var bottom := scroll.get_global_rect().end.y
		assert_true(
			last.get_global_rect().end.y <= bottom + 1.0,
			"%s: the last row ends inside the scroll area" % spec[0]
		)
