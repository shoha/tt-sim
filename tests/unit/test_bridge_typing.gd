extends GutTest

## Tests for BridgeTyping, the validation bridge's text-entry and screenshot-path helpers: the
## path policy (user data or temp folder only), the key events that type a string, the field
## lookup (path, name, text, placeholder, label beside a field, focus) and the signal tally.

const ROOTS: PackedStringArray = ["C:/Users/me/AppData/Roaming/Godot/app_userdata/TTSim", "C:/Temp"]


func _error(path: String, case_insensitive: bool = true) -> String:
	return BridgeTyping.screenshot_path_error(path, ROOTS, case_insensitive)


# --- path policy ----------------------------------------------------------


func test_path_inside_user_folder_is_allowed() -> void:
	assert_eq(_error("C:/Users/me/AppData/Roaming/Godot/app_userdata/TTSim/shots/a.png"), "")


func test_path_inside_temp_is_allowed_with_backslashes() -> void:
	assert_eq(_error("C:\\Temp\\probe\\a.png"), "")


func test_windows_paths_compare_case_insensitively_only_when_asked() -> void:
	assert_eq(_error("c:/temp/a.png", true), "")
	assert_ne(_error("c:/temp/a.png", false), "")


func test_dot_dot_cannot_escape_the_root() -> void:
	assert_ne(_error("C:/Temp/../Windows/a.png"), "")
	assert_ne(_error("C:/Temp/x/../../Windows/a.png"), "")


func test_dot_dot_that_stays_inside_is_allowed() -> void:
	assert_eq(_error("C:/Temp/x/../a.png"), "")


func test_sibling_folder_with_the_same_prefix_is_rejected() -> void:
	assert_ne(_error("C:/Temp2/a.png"), "")


func test_root_itself_and_other_drives_are_rejected() -> void:
	assert_ne(_error("C:/Temp.png"), "")
	assert_ne(_error("D:/Temp/a.png"), "")


func test_relative_empty_and_godot_url_paths_are_rejected() -> void:
	assert_ne(_error(""), "")
	assert_ne(_error("shots/a.png"), "")
	assert_ne(_error("user://a.png"), "")
	assert_ne(_error("res://a.png"), "")


func test_non_png_is_rejected() -> void:
	assert_ne(_error("C:/Temp/a.jpg"), "")
	assert_ne(_error("C:/Temp/a"), "")


func test_default_roots_include_the_user_data_folder() -> void:
	var roots := BridgeTyping.default_roots()
	var user_dir := BridgeTyping.normalize_path(ProjectSettings.globalize_path("user://"))
	assert_has(roots, user_dir)
	assert_eq(
		BridgeTyping.screenshot_path_error(user_dir + "/bridge/a.png", roots, true),
		""
	)


# --- key events -----------------------------------------------------------


func test_text_makes_a_press_and_a_release_per_character() -> void:
	var events := BridgeTyping.key_events_for_text("ab")
	assert_eq(events.size(), 4)
	assert_true(events[0].pressed)
	assert_eq(events[0].unicode, 97)
	assert_eq(events[0].keycode, KEY_A)
	assert_false(events[1].pressed)
	assert_eq(events[1].unicode, 0)
	assert_eq(events[2].unicode, 98)


func test_uppercase_sets_shift_and_symbols_keep_their_unicode() -> void:
	var events := BridgeTyping.key_events_for_text("A-")
	assert_true(events[0].shift_pressed)
	assert_eq(events[0].keycode, KEY_A)
	assert_false(events[2].shift_pressed)
	assert_eq(events[2].unicode, 45)
	assert_eq(events[2].keycode, KEY_NONE)


func test_newline_is_enter_tab_is_tab_and_carriage_return_is_dropped() -> void:
	var events := BridgeTyping.key_events_for_text("a\r\nb\t")
	var codes: Array = events.filter(func(e: InputEventKey) -> bool: return e.pressed).map(
		func(e: InputEventKey) -> int: return e.keycode
	)
	assert_eq(codes, [KEY_A, KEY_ENTER, KEY_B, KEY_TAB])


func test_empty_text_makes_no_events() -> void:
	assert_eq(BridgeTyping.key_events_for_text("").size(), 0)


# --- finding the field ----------------------------------------------------


func _form() -> Control:
	var root := Control.new()
	add_child_autofree(root)
	var row := HBoxContainer.new()
	row.name = "NameRow"
	root.add_child(row)
	var label := Label.new()
	label.name = "NameLabel"
	label.text = "Map name"
	row.add_child(label)
	var field := LineEdit.new()
	field.name = "NameField"
	field.placeholder_text = "Untitled map"
	row.add_child(field)
	var other := LineEdit.new()
	other.name = "SearchField"
	other.placeholder_text = "Search"
	root.add_child(other)
	return root


func test_finds_a_field_by_name_and_by_path() -> void:
	var root := _form()
	var by_name := BridgeTyping.resolve_target(root, "NameField")
	assert_true(by_name["ok"])
	assert_eq(by_name["control"].name, &"NameField")
	var path := str(root.get_node("NameRow/NameField").get_path())
	var by_path := BridgeTyping.resolve_target(root, path)
	assert_eq(by_path["control"].name, &"NameField")


func test_finds_a_field_by_placeholder_text() -> void:
	var found := BridgeTyping.resolve_target(_form(), "Search")
	assert_true(found["ok"])
	assert_eq(found["control"].name, &"SearchField")


func test_a_label_resolves_to_the_field_after_it() -> void:
	var found := BridgeTyping.resolve_target(_form(), "Map name")
	assert_true(found["ok"])
	assert_eq(found["control"].name, &"NameField")


func test_a_row_resolves_to_the_field_inside_it() -> void:
	var found := BridgeTyping.resolve_target(_form(), "NameRow")
	assert_eq(found["control"].name, &"NameField")


func test_unknown_query_and_non_field_controls_fail() -> void:
	var root := _form()
	assert_false(BridgeTyping.resolve_target(root, "Nothing here")["ok"])
	var lonely := Label.new()
	lonely.text = "Lonely"
	add_child_autofree(lonely)
	assert_false(BridgeTyping.resolve_target(lonely, "Lonely")["ok"])


func test_hidden_fields_are_not_found() -> void:
	var root := _form()
	root.get_node("SearchField").visible = false
	assert_false(BridgeTyping.resolve_target(root, "SearchField")["ok"])


func test_two_fields_with_one_name_are_ambiguous() -> void:
	var root := _form()
	var twin := LineEdit.new()
	twin.name = "NameField"
	root.add_child(twin)
	var found := BridgeTyping.resolve_target(root, "NameField")
	assert_false(found["ok"])
	assert_eq(found["matches"].size(), 2)


func test_empty_query_uses_the_focused_field() -> void:
	var root := _form()
	var field: LineEdit = root.get_node("SearchField")
	field.grab_focus()
	var found := BridgeTyping.resolve_target(root, "")
	assert_true(found["ok"])
	assert_eq(found["control"], field)
	field.release_focus()
	assert_false(BridgeTyping.resolve_target(root, "")["ok"])


# --- typing into the engine's own controls --------------------------------


func test_typed_events_edit_a_line_edit_and_fire_its_signals() -> void:
	var root := _form()
	var field: LineEdit = root.get_node("SearchField")
	field.grab_focus()
	var watch := BridgeTyping.TypeWatch.new(field)
	for event in BridgeTyping.key_events_for_text("Hi 5"):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	for event in BridgeTyping.key_pair(KEY_ENTER):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	# The controls emit text_changed deferred, so let a frame pass before reading the tally.
	await get_tree().process_frame
	watch.stop()
	assert_eq(field.text, "Hi 5")
	# One emission or several: the engine coalesces edits made inside one frame.
	assert_gt(watch.changed, 0)
	assert_eq(watch.submitted, 1)


func test_clear_replaces_existing_text() -> void:
	var root := _form()
	var field: LineEdit = root.get_node("SearchField")
	field.text = "old"
	field.grab_focus()
	field.select_all()
	for event in BridgeTyping.key_pair(KEY_BACKSPACE):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	for event in BridgeTyping.key_events_for_text("new"):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	assert_eq(field.text, "new")


func test_caret_to_end_appends() -> void:
	var root := _form()
	var field: LineEdit = root.get_node("SearchField")
	field.text = "ab"
	field.grab_focus()
	BridgeTyping.caret_to_end(field)
	for event in BridgeTyping.key_events_for_text("c"):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	assert_eq(field.text, "abc")


func test_text_edit_takes_newlines_and_has_no_submit_signal() -> void:
	var edit := TextEdit.new()
	add_child_autofree(edit)
	edit.grab_focus()
	var watch := BridgeTyping.TypeWatch.new(edit)
	for event in BridgeTyping.key_events_for_text("a\nb"):
		Input.parse_input_event(event)
		Input.flush_buffered_events()
	await get_tree().process_frame
	watch.stop()
	assert_eq(edit.text, "a\nb")
	assert_gt(watch.changed, 0)
	assert_eq(watch.submitted, 0)


func test_read_only_field_is_not_editable() -> void:
	var field := LineEdit.new()
	field.editable = false
	add_child_autofree(field)
	assert_false(BridgeTyping.is_editable(field))
	assert_false(BridgeTyping.is_editable(autofree(Label.new())))
