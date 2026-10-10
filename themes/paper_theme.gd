@tool
extends "res://themes/painted_theme_base.gd"

## The paper leaf of the Painted Table theme: anything that stops play (menus, dialogs,
## pause, confirms). The project default theme (project.godot theme/custom).

const UPDATE_ON_SAVE = true


func setup() -> void:
	set_save_path(ThemeColors.PAPER_THEME_PATH)
	use_roles(ThemeColors.PAPER_ROLES, false)
