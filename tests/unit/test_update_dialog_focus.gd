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
