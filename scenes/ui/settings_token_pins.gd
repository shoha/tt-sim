class_name SettingsTokenPins
extends RefCounted

## The Graphics tab's "Token pins" choice (Always or Top-down only; graphics/token_pins, default
## Always): when the map pin over each token shows (TokenMarkers.mode). Split out of
## settings_menu.gd to keep that file under the lint budget. Applied by Apply, with no restart:
## the markers read the mode every frame.

const TOKEN_MARKERS := "res://scenes/board_token/token_markers.gd"


## The saved choice's item id (the default mode when the key is missing or unknown).
static func saved_id(config: ConfigFile) -> int:
	var id := int(config.get_value("graphics", _markers().SETTINGS_KEY, _markers().DEFAULT_MODE))
	return id if id == _markers().PinMode.TOP_DOWN else _markers().PinMode.ALWAYS


## TokenMarkers' script, loaded by path so the title does not compile it (perf audit boot2).
static func _markers() -> Variant:
	return load(TOKEN_MARKERS)


## Puts the saved choice on the option without firing its handler.
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_select(menu, saved_id(config))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", _markers().SETTINGS_KEY, menu.token_pins_option.get_selected_id())


static func show_defaults(menu: SettingsMenu) -> void:
	_select(menu, _markers().DEFAULT_MODE)


## Applies the choice now (TokenMarkers.mode, static: a later map reads it too).
static func apply(menu: SettingsMenu) -> void:
	apply_id(menu.token_pins_option.get_selected_id())


## Sets TokenMarkers.mode to `id` (the saved value, read at the start of a game).
static func apply_id(id: int) -> void:
	_markers().mode = id


static func apply_tooltip(menu: SettingsMenu) -> void:
	menu.token_pins_option.tooltip_text = (
		"The map pin over each token (its picture on a pin whose tip touches the token), which "
		+ "also picks the token up when clicked. Always shows it from every camera angle, quieter "
		+ "and smaller when the camera is low, so a small token under foliage or behind a wall is "
		+ "easy to find. Top-down only shows it when the camera looks steeply down."
	)


static func _select(menu: SettingsMenu, id: int) -> void:
	var index := menu.token_pins_option.get_item_index(id)
	menu.token_pins_option.select(index if index >= 0 else 0)
