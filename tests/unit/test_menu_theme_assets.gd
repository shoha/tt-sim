extends GutTest

## The assets the menu design language needs: a KeyChip panel variation in the
## generated themes, a named backdrop role, and the icons the new menu rows ask
## for by name.

const NEW_ICONS := ["player-play", "home", "copy", "logout", "arrow-left", "share"]


func test_key_chip_variation_is_in_both_generated_themes() -> void:
	for theme: Theme in [ThemeColors.paper_theme(), ThemeColors.glass_theme()]:
		assert_not_null(theme)
		assert_true(theme.has_stylebox("panel", "KeyChip"), "KeyChip panel stylebox")
		assert_eq(theme.get_type_variation_base("KeyChip"), &"PanelContainer")


func test_backdrop_has_a_role_on_both_themes() -> void:
	assert_eq(
		ThemeColors.paper_theme().get_color(ThemeColors.BACKDROP, ThemeColors.TYPE),
		ThemeColors.SKY_TOP
	)
	assert_true(ThemeColors.glass_theme().has_color(ThemeColors.BACKDROP, ThemeColors.TYPE))


func test_every_new_menu_icon_loads() -> void:
	for icon_name in NEW_ICONS:
		assert_not_null(IconButton.load_icon(icon_name), icon_name)
