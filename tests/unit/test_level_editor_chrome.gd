extends GutTest

## Level editor chrome: exactly one default-variant Button in the header
## (Play), every other header Button is Secondary or IconButton, no Button
## anywhere in the scene uses Success/Danger/Warning, the placement footer
## is end-aligned, and the title reads "Level editor".

const SCENE := preload("res://scenes/level_editor/level_editor.tscn")

const ALLOWED_HEADER_VARIATIONS := ["Secondary", "IconButton", "IconButtonActive"]
const FORBIDDEN_VARIATIONS := ["Success", "Danger", "Warning"]


func _editor() -> LevelEditor:
	var editor: LevelEditor = SCENE.instantiate()
	editor.check_autosave_on_ready = false
	add_child_autofree(editor)
	return editor


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	if node is Button:
		out.append(node as Button)
	for child in node.get_children():
		_collect_buttons(child, out)


func test_header_has_exactly_one_default_variant_button_and_it_is_play() -> void:
	var editor := _editor()
	var header: HBoxContainer = editor.get_node("MainContainer/VBox/Header")
	var default_variant_buttons: Array[Button] = []
	for child in header.get_children():
		if not (child is Button):
			continue
		var button := child as Button
		var variation := String(button.theme_type_variation)
		if variation == "":
			default_variant_buttons.append(button)
		else:
			assert_true(
				variation in ALLOWED_HEADER_VARIATIONS,
				"%s should be Secondary or IconButton, got %s" % [button.name, variation]
			)
	assert_eq(default_variant_buttons.size(), 1, "exactly one default-variant header button")
	if default_variant_buttons.size() == 1:
		assert_same(default_variant_buttons[0], editor.play_button)


func test_no_button_anywhere_uses_success_danger_or_warning() -> void:
	var editor := _editor()
	var buttons: Array[Button] = []
	_collect_buttons(editor, buttons)
	for button in buttons:
		var variation := String(button.theme_type_variation)
		assert_false(
			variation in FORBIDDEN_VARIATIONS, "%s should not use %s" % [button.name, variation]
		)


func test_placement_footer_is_end_aligned() -> void:
	var editor := _editor()
	var buttons_row: HBoxContainer = editor.get_node(
		"MainContainer/VBox/ContentSplit/RightPanel/PlacementPanel/PlacementVBox/ButtonsRow"
	)
	assert_eq(buttons_row.alignment, BoxContainer.ALIGNMENT_END)


func test_title_reads_level_editor() -> void:
	var editor := _editor()
	var title: Label = editor.get_node("MainContainer/VBox/Header/TitleBlock/Title")
	assert_eq(title.text, "Level editor")


func test_header_caption_follows_the_level_name_while_typing() -> void:
	var editor := _editor()
	editor.level_name_edit.text = "Dusty Hollow"
	editor.level_name_edit.text_changed.emit("Dusty Hollow")
	assert_eq(editor.level_title_caption.text, "Dusty Hollow")

	editor.level_name_edit.text = ""
	editor.level_name_edit.text_changed.emit("")
	assert_eq(editor.level_title_caption.text, "Untitled level")
