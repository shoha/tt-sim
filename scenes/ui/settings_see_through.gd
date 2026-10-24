class_name SettingsSeeThrough
extends RefCounted

## The Graphics tab's three "see tokens through scenery" options, split out of settings_menu.gd
## to keep that file under the lint budget. They are independent:
## - Token ghost (graphics/token_ghost_enabled, default on): the translucent silhouette of a
##   token that foliage, a trunk, a rock or a wall covers (TokenGhost).
## - Occlusion fade (graphics/occlusion_fade_enabled, default on): the per-token reveal that
##   dithers map geometry and tree cards in front of a token (OcclusionFadeManager).
## - Canopy fade (graphics/canopy_fade_enabled, default off): the close-zoom window of thinned
##   crowns round the screen centre (CanopyFade).

const KEY_GHOST := "token_ghost_enabled"
const KEY_OCCLUSION := "occlusion_fade_enabled"
const KEY_CANOPY := "canopy_fade_enabled"


## Puts the saved values in `config` on the checks without firing their handlers.
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	menu.token_ghost_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_GHOST, TokenGhost.DEFAULT_ENABLED)
	)
	menu.occlusion_fade_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_OCCLUSION, true)
	)
	menu.canopy_fade_check.set_pressed_no_signal(
		config.get_value("graphics", KEY_CANOPY, CanopyFade.DEFAULT_ENABLED)
	)


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", KEY_GHOST, menu.token_ghost_check.button_pressed)
	config.set_value("graphics", KEY_OCCLUSION, menu.occlusion_fade_check.button_pressed)
	config.set_value("graphics", KEY_CANOPY, menu.canopy_fade_check.button_pressed)


static func show_defaults(menu: SettingsMenu) -> void:
	menu.token_ghost_check.set_pressed_no_signal(TokenGhost.DEFAULT_ENABLED)
	menu.occlusion_fade_check.set_pressed_no_signal(true)
	menu.canopy_fade_check.set_pressed_no_signal(CanopyFade.DEFAULT_ENABLED)


## Applies the three checks now. The ghost and the canopy fade are static state that any later
## map reads too; the occlusion fade needs the open map (the next one reads the file).
static func apply(menu: SettingsMenu, game_map: GameMap) -> void:
	TokenGhost.set_enabled(menu.token_ghost_check.button_pressed, menu.get_tree())
	CanopyFade.enabled = menu.canopy_fade_check.button_pressed
	if game_map != null:
		game_map.set_occlusion_fade_enabled(menu.occlusion_fade_check.button_pressed)


static func apply_tooltips(menu: SettingsMenu) -> void:
	menu.token_ghost_check.tooltip_text = (
		"Draw a see-through silhouette of a token that foliage, a rock or a wall covers, with an "
		+ "outline (gold while it is selected or hovered). Plants and walls are left alone."
	)
	menu.occlusion_fade_check.tooltip_text = (
		"Fade map geometry and foliage that hide a token, in a small dithered patch round it"
	)
	menu.canopy_fade_check.tooltip_text = (
		"Thin the tree crowns in a window round the middle of the screen when zoomed in. "
		+ "Off by default: the window follows the camera."
	)
