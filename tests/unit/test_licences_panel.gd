extends GutTest

## The Licences page: a list of every catalog entry, the selected notice in a scrolling pane,
## focus that moves the selection, and the way in from Settings, About.

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _panel: LicencesPanel


func before_each() -> void:
	_panel = LicencesPanel.new()
	add_child_autofree(_panel)
	await wait_process_frames(2)


func test_one_row_per_catalog_entry_and_the_first_is_shown() -> void:
	assert_eq(_panel.entry_count(), LicenceCatalog.entries().size())
	assert_eq(_panel.selected_index(), 0)
	assert_eq(_panel.title_label.text, LicenceCatalog.entries()[0]["name"])
	assert_ne(_panel.text_pane.text, "")
	assert_true(_panel.row_at(0).button_pressed)


func test_focusing_a_row_shows_its_notice() -> void:
	var last := _panel.entry_count() - 1
	_panel.row_at(last).grab_focus()
	assert_eq(_panel.selected_index(), last)
	assert_eq(_panel.title_label.text, LicenceCatalog.entries()[last]["name"])
	assert_true(_panel.row_at(last).button_pressed)
	assert_false(_panel.row_at(0).button_pressed)


func test_pressing_the_marked_row_keeps_it_marked() -> void:
	_panel.row_at(0).pressed.emit()
	assert_true(_panel.row_at(0).button_pressed)


func test_the_core_credit_line_shows_for_the_core_library() -> void:
	var index := -1
	for i in _panel.entry_count():
		if LicenceCatalog.entries()[i]["id"] == "core_library":
			index = i
	assert_gt(index, -1, "the core library is listed")
	_panel.row_at(index).grab_focus()
	assert_true(_panel.credit_label.visible)
	assert_eq(_panel.credit_label.text, "Core library by Hannah Shore, CC BY 4.0")
	_panel.row_at(0).grab_focus()
	assert_false(_panel.credit_label.visible)


func test_the_notice_is_reachable_from_the_list_by_focus() -> void:
	var row := _panel.row_at(0)
	assert_eq(row.get_node(row.focus_neighbor_right), _panel.text_pane)
	assert_eq(_panel.text_pane.get_node(_panel.text_pane.focus_neighbor_left), row)
	assert_eq(_panel.text_pane.focus_mode, Control.FOCUS_ALL)


func test_left_in_the_notice_returns_to_the_marked_item() -> void:
	_panel.row_at(2).grab_focus()
	_panel.text_pane.grab_focus()
	var event := InputEventAction.new()
	event.action = "ui_left"
	event.pressed = true
	_panel.text_pane.gui_input.emit(event)
	assert_eq(get_viewport().gui_get_focus_owner(), _panel.row_at(2))


func test_escape_closes_the_page() -> void:
	var event := InputEventAction.new()
	event.action = "ui_cancel"
	event.pressed = true
	_panel._unhandled_input(event)
	await wait_seconds(1.0)
	assert_false(is_instance_valid(_panel), "the page animates out and frees itself")


func test_the_page_keeps_every_shadow() -> void:
	assert_eq(ShadowGutter.violations(_panel), [], "no clipped shadow or focus ring")


func test_settings_about_opens_the_page() -> void:
	var settings := SETTINGS_SCENE.instantiate() as SettingsMenu
	add_child_autofree(settings)
	await wait_process_frames(2)
	assert_true(settings.section_rail.has_item(&"About"))
	assert_ne(settings.about_version_label.text, "")
	settings.licences_button.pressed.emit()
	await wait_process_frames(2)
	var open := get_tree().root.get_children().filter(func(n: Node) -> bool: return n is LicencesPanel)
	assert_eq(open.size(), 1)
	for panel in open:
		panel.free()
