class_name SettingsSeeThrough
extends RefCounted

## The Graphics tab's "see tokens through scenery" option, split out of settings_menu.gd to keep
## that file under the lint budget:
## - Token ghost (graphics/token_ghost_enabled, default on): the translucent silhouette of a
##   token that foliage, a trunk, a rock or a wall covers (TokenGhost).
## (The per-token Occlusion fade, graphics/occlusion_fade_enabled, was removed on 2026-11-15 and
## the Canopy fade window, graphics/canopy_fade_enabled, on 2026-11-16; a settings file that
## still holds either key loads fine, since nothing reads it.)

const KEY_GHOST := "token_ghost_enabled"
## TokenGhost, loaded by path so the title does not compile it (perf audit boot2).
const TOKEN_GHOST := "res://scenes/board_token/token_ghost.gd"


## Puts the saved value in `config` on the check without firing its handler.
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	menu.token_ghost_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_GHOST, _ghost().DEFAULT_ENABLED)
	)


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", KEY_GHOST, menu.token_ghost_check.button_pressed)


static func show_defaults(menu: SettingsMenu) -> void:
	menu.token_ghost_check.set_pressed_no_signal(_ghost().DEFAULT_ENABLED)


## Applies the check now. It is static state that any later map reads too.
static func apply(menu: SettingsMenu, _game_map: Node3D) -> void:
	_ghost().set_enabled(menu.token_ghost_check.button_pressed, menu.get_tree())


static func _ghost() -> Variant:
	return load(TOKEN_GHOST)


static func apply_tooltips(menu: SettingsMenu) -> void:
	menu.token_ghost_check.tooltip_text = (
		"Draw a see-through silhouette of a token that foliage, a rock or a wall covers, with an "
		+ "outline (gold while it is selected or hovered), so a covered token can be found and "
		+ "selected. Plants and walls are left alone."
	)
