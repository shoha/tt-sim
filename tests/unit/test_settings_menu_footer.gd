extends GutTest

## The Settings chrome follows the menu rule: a shared header with the close
## button in it, Apply as the single accent action, and a quiet Reset.

const MENU_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _menu: SettingsMenu


func before_each() -> void:
	_menu = MENU_SCENE.instantiate()
	add_child_autofree(_menu)


func test_apply_is_the_only_accent_action() -> void:
	assert_eq(_menu.apply_button.theme_type_variation, &"")
	assert_eq(_menu.reset_button.theme_type_variation, &"Secondary")
	assert_eq(_menu.reset_button.text, "Reset to Defaults")
	assert_eq(_menu.apply_button.text, "Apply")


func test_footer_puts_the_primary_last_and_hugs_the_right() -> void:
	var footer := _menu.apply_button.get_parent() as HBoxContainer
	assert_eq(footer.alignment, BoxContainer.ALIGNMENT_END)
	assert_lt(_menu.reset_button.get_index(), _menu.apply_button.get_index())


func test_header_carries_the_title_and_the_close_button() -> void:
	assert_eq(_menu.header.title_label.text, "Settings")
	assert_same(_menu.close_button, _menu.header.close_button)
	assert_true(_menu.header.close_requested.is_connected(_menu._on_close_pressed))
