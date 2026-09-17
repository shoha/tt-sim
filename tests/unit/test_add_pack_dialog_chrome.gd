extends GutTest

## AddPackDialog chrome: a MenuHeader title, URLEdit captioned "Pack URL",
## and an end-aligned footer with Cancel (Secondary) before the one
## default-variant Download button.

const SCENE := preload("res://scenes/ui/add_pack_dialog.tscn")


func _dialog() -> AddPackDialog:
	var dialog: AddPackDialog = SCENE.instantiate()
	add_child_autofree(dialog)
	return dialog


func test_header_title_reads_add_asset_pack() -> void:
	var dialog := _dialog()
	assert_eq(dialog.header.title_label.text, "Add asset pack")


func test_download_is_the_only_default_variant_button() -> void:
	var dialog := _dialog()
	assert_eq(String(dialog.download_button.theme_type_variation), "")
	assert_eq(dialog.cancel_button.theme_type_variation, &"Secondary")


func test_footer_is_end_aligned_with_cancel_before_download() -> void:
	var dialog := _dialog()
	var footer := dialog.cancel_button.get_parent() as HBoxContainer
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_END)
	assert_lt(dialog.cancel_button.get_index(), dialog.download_button.get_index())
