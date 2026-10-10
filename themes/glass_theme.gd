@tool
extends "res://themes/painted_theme_base.gd"

## The glass leaf of the Painted Table theme: anything shown while play continues (the HUD,
## drawers, the hint bar, the token menu, toasts). Set on each in-play UI root through
## ThemeColors.glass_theme(); tests/unit/test_glass_roots.gd fails if a root lacks it.

const UPDATE_ON_SAVE = true


func setup() -> void:
	set_save_path(ThemeColors.GLASS_THEME_PATH)
	use_roles(ThemeColors.GLASS_ROLES, true)
