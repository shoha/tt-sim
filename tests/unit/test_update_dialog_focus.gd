extends GutTest

## UpdateDialogUI toggles progress_container, button_container and
## post_download_buttons across its download lifecycle. Each state change
## must rebuild the focus trap so it only names controls that are actually
## visible in the tree.

const SCENE := preload("res://scenes/ui/update_dialog.tscn")


func _dialog() -> UpdateDialogUI:
	var dialog: UpdateDialogUI = SCENE.instantiate()
	add_child_autofree(dialog)
	dialog.setup({"version": "1.2.3", "body": "", "download_url": "https://example.com/update.zip"})
	return dialog


func _assert_trap_all_visible(dialog: UpdateDialogUI) -> void:
	for control in dialog._focusable_controls:
		assert_true(
			(control as Control).is_visible_in_tree(),
			"%s should be visible in tree" % (control as Control).name
		)


func test_download_complete_rebuilds_trap_to_post_download_buttons() -> void:
	var dialog := _dialog()
	dialog._on_download_complete("user://updates/fake.zip")
	_assert_trap_all_visible(dialog)
	assert_true(dialog._focusable_controls.has(dialog.restart_button))
	assert_true(dialog._focusable_controls.has(dialog.later_button))
	assert_true(dialog._focusable_controls.has(dialog.open_folder_button))
	assert_false(dialog._focusable_controls.has(dialog.download_button))


func test_download_pressed_rebuilds_trap() -> void:
	var dialog := _dialog()
	dialog._on_download_pressed()
	_assert_trap_all_visible(dialog)


func test_download_failed_rebuilds_trap() -> void:
	var dialog := _dialog()
	dialog._on_download_pressed()
	dialog._on_download_failed("network error")
	_assert_trap_all_visible(dialog)
	assert_true(dialog._focusable_controls.has(dialog.download_button))


func test_setup_hiding_download_button_rebuilds_trap() -> void:
	var dialog: UpdateDialogUI = SCENE.instantiate()
	add_child_autofree(dialog)
	dialog.setup({"version": "1.2.3", "body": "", "download_url": ""})
	_assert_trap_all_visible(dialog)
	assert_false(dialog._focusable_controls.has(dialog.download_button))


func _default_variant_visible_buttons(container: HBoxContainer) -> Array[Button]:
	var result: Array[Button] = []
	for child in container.get_children():
		if child is Button and (child as Button).visible:
			if String((child as Button).theme_type_variation) == "":
				result.append(child as Button)
	return result


func test_header_title_reads_update_available() -> void:
	var dialog := _dialog()
	assert_eq(dialog.header.title_label.text, "Update available")


func test_download_footer_has_one_default_variant_button_and_is_end_aligned() -> void:
	var dialog := _dialog()
	assert_eq(dialog.button_container.alignment, BoxContainer.ALIGNMENT_END)
	var default_buttons := _default_variant_visible_buttons(dialog.button_container)
	assert_eq(default_buttons.size(), 1)
	if default_buttons.size() == 1:
		assert_same(default_buttons[0], dialog.download_button)


func test_post_download_footer_has_one_default_variant_button_and_is_end_aligned() -> void:
	var dialog := _dialog()
	dialog._on_download_complete("user://updates/fake.zip")
	assert_eq(dialog.post_download_buttons.alignment, BoxContainer.ALIGNMENT_END)
	var default_buttons := _default_variant_visible_buttons(dialog.post_download_buttons)
	assert_eq(default_buttons.size(), 1)
	if default_buttons.size() == 1:
		assert_same(default_buttons[0], dialog.restart_button)
