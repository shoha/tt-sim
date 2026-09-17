extends GutTest

## The assets the menu design language needs: a KeyChip panel variation in the
## generated theme, a named background colour, and the icons the new menu rows
## ask for by name.

const THEME_PATH := "res://themes/generated/dark_theme.tres"
const NEW_ICONS := ["player-play", "home", "copy", "logout", "arrow-left", "share"]


func test_key_chip_variation_is_in_the_generated_theme() -> void:
	var theme: Theme = load(THEME_PATH)
	assert_not_null(theme)
	assert_true(theme.has_stylebox("panel", "KeyChip"), "KeyChip panel stylebox")
	assert_eq(theme.get_type_variation_base("KeyChip"), &"PanelContainer")


func test_background_colour_has_a_name() -> void:
	assert_eq(ThemeColors.BACKGROUND, Color("#1a121a"))


func test_every_new_menu_icon_loads() -> void:
	for icon_name in NEW_ICONS:
		assert_not_null(IconButton.load_icon(icon_name), icon_name)
