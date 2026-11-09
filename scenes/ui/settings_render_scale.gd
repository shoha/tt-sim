class_name SettingsRenderScale
extends RefCounted

## The Graphics tab's "Render scale" choice (graphics/render_scale: Auto or a percent, default
## 100, the full render), split out of settings_menu.gd to keep that file under the lint
## budget. RenderScale holds the model and the Auto rule. Like the other graphics options it
## applies on Apply, with no restart: GameMap re-sizes its world render at once. The labels name
## the render size on this window, so the option refills when the window resizes.

const TOOLTIP := (
	"How many pixels the 3D board draws. Lower it if maps run slowly: the board is drawn smaller "
	+ "and enlarged with AMD FSR 1.0, a little softer. Menus and text stay sharp. Auto draws no "
	+ "more pixels than your screen shows. 100% is the full board, 1920x1080 on a 16:9 screen."
)


## Puts the saved choice on the option without applying it (Root applied it at startup).
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_select(menu, RenderScale.stored(config))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", RenderScale.KEY, menu.render_scale_option.get_selected_id())


static func show_defaults(menu: SettingsMenu) -> void:
	_select(menu, RenderScale.DEFAULT)


## Applies the choice now: the map on screen re-sizes its render, and later maps read it.
static func apply(menu: SettingsMenu, game_map: GameMap) -> void:
	RenderScale.current = RenderScale.sanitize(menu.render_scale_option.get_selected_id())
	if game_map:
		RenderScale.apply_to(game_map.world_viewport, game_map.get_window(), RenderScale.current)


## Fills the option for the menu's window and selects the applied choice.
static func fill(menu: SettingsMenu) -> void:
	RenderScale.fill_option(menu.render_scale_option, menu.get_tree().root, RenderScale.current)


## Refills the labels for a resized window, keeping the selected choice.
static func refill(menu: SettingsMenu) -> void:
	var option := menu.render_scale_option
	RenderScale.fill_option(option, menu.get_tree().root, option.get_selected_id())


static func apply_tooltip(menu: SettingsMenu) -> void:
	menu.render_scale_option.tooltip_text = TOOLTIP


static func _select(menu: SettingsMenu, choice: int) -> void:
	var index := menu.render_scale_option.get_item_index(RenderScale.sanitize(choice))
	menu.render_scale_option.select(index if index >= 0 else 0)
