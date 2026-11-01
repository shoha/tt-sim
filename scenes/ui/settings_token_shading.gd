class_name SettingsTokenShading
extends RefCounted

## The Graphics tab's "Token shading" choice (Painted or Original; graphics/token_shading, default
## Painted): the painted look of pack tokens (TokenToon). Split out of settings_menu.gd to keep
## that file under the lint budget. Like the other graphics options it is applied by Apply, with
## no restart: TokenToon.set_painted swaps every pack token's materials at once.


## The saved choice's item id (SHADING_PAINTED when the key is missing).
static func saved_id(config: ConfigFile) -> int:
	return int(config.get_value("graphics", TokenToon.SETTINGS_KEY, TokenToon.DEFAULT_ID))


## Puts the saved choice on the option without firing its handler.
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_select(menu, saved_id(config))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	var id := menu.token_shading_option.get_selected_id()
	config.set_value("graphics", TokenToon.SETTINGS_KEY, id)


static func show_defaults(menu: SettingsMenu) -> void:
	_select(menu, TokenToon.DEFAULT_ID)


## Applies the choice now, to the tokens on the map and the ones made later.
static func apply(menu: SettingsMenu) -> void:
	var painted := menu.token_shading_option.get_selected_id() == TokenToon.SHADING_PAINTED
	TokenToon.set_painted(painted, menu.get_tree())


static func apply_tooltip(menu: SettingsMenu) -> void:
	menu.token_shading_option.tooltip_text = (
		"Painted lights pack tokens in soft bands with tinted shadows, so tokens from different "
		+ "sources look alike. Original keeps each model's own materials. Avatars are not affected."
	)


static func _select(menu: SettingsMenu, id: int) -> void:
	var index := menu.token_shading_option.get_item_index(id)
	menu.token_shading_option.select(index if index >= 0 else 0)
