extends GutTest

## The confirmation dialog is the one place semantic fills survive: confirm
## takes Success by default and Danger when the caller asks for it, cancel is
## always quiet and sits before confirm in an end-aligned footer.

const SCENE := preload("res://scenes/ui/confirmation_dialog.tscn")


func _dialog() -> ConfirmationDialogUI:
	var dialog: ConfirmationDialogUI = SCENE.instantiate()
	add_child_autofree(dialog)
	return dialog


func test_default_confirm_is_success() -> void:
	var dialog := _dialog()
	dialog.setup("Save changes?", "Your level has unsaved edits.")
	assert_eq(dialog.confirm_button.theme_type_variation, &"Success")
	assert_eq(dialog.cancel_button.theme_type_variation, &"Secondary")
	assert_eq(dialog.title_label.text, "Save changes?")
	assert_eq(dialog.message_label.text, "Your level has unsaved edits.")


func test_danger_confirm_takes_the_red() -> void:
	var dialog := _dialog()
	dialog.setup(
		"Quit Game?",
		"Any unsaved progress will be lost.",
		"Quit",
		"Cancel",
		Callable(),
		Callable(),
		"Danger"
	)
	assert_eq(dialog.confirm_button.theme_type_variation, &"Danger")
	assert_eq(dialog.cancel_button.theme_type_variation, &"Secondary")
	assert_eq(dialog.confirm_button.text, "Quit")


func test_cancel_sits_before_confirm_in_an_end_aligned_footer() -> void:
	var dialog := _dialog()
	var footer := dialog.cancel_button.get_parent() as HBoxContainer
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_END)
	assert_lt(dialog.cancel_button.get_index(), dialog.confirm_button.get_index())


func test_the_title_comes_from_the_shared_header() -> void:
	var dialog := _dialog()
	dialog.setup("Return to Title?", "Any unsaved progress will be lost.")
	assert_same(dialog.title_label, dialog.header.title_label)
	assert_false(dialog.header.caption_label.visible, "dialogs carry no caption")
