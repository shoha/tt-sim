class_name SettingsGpuOptions
extends RefCounted

## The Graphics tab's two GPU-cost options, split out of settings_menu.gd to keep that file under
## the lint budget: "Foliage edges" (graphics/foliage_edges, FoliageEdges, beside Antialiasing) and
## "Shadow cascades" (graphics/shadow_cascades, ShadowCascades, beside Shadow quality). Both default
## to the game as it shipped before them. Like the other graphics options they apply on Apply,
## with no restart: the foliage re-picks its shader variant and the sun its cascades at once.

const FOLIAGE_EDGES_TOOLTIP := (
	"How leaf and grass edges look while antialiasing is on (an Antialiasing setting, or the eye "
	+ "view). Smooth feathers them. Fast keeps them crisp and draws foliage faster; the rest of "
	+ "the board is still antialiased."
)
const SHADOW_CASCADES_TOOLTIP := (
	"How the sun's shadows are split across the view. Blended is the smoothest. Unblended is "
	+ "faster; far tree shadows may pop as the camera tilts. Single is the fastest and softens "
	+ "distant shadows."
)


## Reads both choices from the settings file at startup (Root, before any map loads).
static func apply_startup(config: ConfigFile) -> void:
	FoliageEdges.current = FoliageEdges.stored(config)
	ShadowCascades.current = ShadowCascades.stored(config)


## Puts the saved choices on the options without applying them (Root applied them at startup).
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_select(menu.foliage_edges_option, FoliageEdges.stored(config))
	_select(menu.shadow_cascades_option, ShadowCascades.stored(config))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value(
		"graphics",
		FoliageEdges.KEY,
		FoliageEdges.sanitize(menu.foliage_edges_option.get_selected_id())
	)
	config.set_value(
		"graphics",
		ShadowCascades.KEY,
		ShadowCascades.sanitize(menu.shadow_cascades_option.get_selected_id())
	)


static func show_defaults(menu: SettingsMenu) -> void:
	_select(menu.foliage_edges_option, FoliageEdges.DEFAULT)
	_select(menu.shadow_cascades_option, ShadowCascades.DEFAULT)


## Applies both choices now, with the Antialiasing level: the map on screen sets its MSAA and
## re-picks every foliage shader variant (that reads FoliageEdges.current, so it runs after it),
## the sun on screen takes its cascades, and later maps read both.
static func apply(menu: SettingsMenu, game_map: GameMap) -> void:
	FoliageEdges.current = FoliageEdges.sanitize(menu.foliage_edges_option.get_selected_id())
	ShadowCascades.current = ShadowCascades.sanitize(menu.shadow_cascades_option.get_selected_id())
	if game_map == null:
		return
	game_map.set_foliage_antialiasing_level(menu.antialiasing_option.selected)
	if game_map.world_viewport:
		ShadowCascades.apply_in(game_map.world_viewport, ShadowCascades.current)


static func apply_tooltips(menu: SettingsMenu) -> void:
	menu.foliage_edges_option.tooltip_text = FOLIAGE_EDGES_TOOLTIP
	menu.shadow_cascades_option.tooltip_text = SHADOW_CASCADES_TOOLTIP


static func _select(option: OptionButton, choice: int) -> void:
	var index := option.get_item_index(choice)
	option.select(index if index >= 0 else 0)
