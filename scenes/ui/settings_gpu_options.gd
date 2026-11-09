class_name SettingsGpuOptions
extends RefCounted

## The Graphics tab's three cost options, split out of settings_menu.gd to keep that file under
## the lint budget: "Foliage edges" (graphics/foliage_edges, FoliageEdges, beside Antialiasing),
## "Shadow cascades" (graphics/shadow_cascades, ShadowCascades, beside Shadow quality) and "Idle
## throttle" (graphics/idle_throttle, IdleThrottle, beside VSync: a checkbox, on by default, that
## caps the frame rate while the window is in the background). The first two default to the game as
## it shipped before them. Like the other graphics options they apply on Apply, with no restart:
## the foliage re-picks its shader variant, the sun its cascades and the throttle its cap at once.

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
const GROUND_DETAIL_TOOLTIP := (
	"How much of the ground is drawn once and reused instead of per pixel every frame, which "
	+ "makes the game faster. Each step down uses less graphics memory (5 levels 160 MB, 4 "
	+ "levels 128, 3 levels 96, plus about 48 MB for drawing them) and gives up some of the "
	+ "speed-up when zoomed in close on a large map; Off draws the ground per pixel as before. "
	+ "Off and a level count take effect at once; turning it back on takes effect when the "
	+ "next map loads."
)
const IDLE_THROTTLE_TOOLTIP := (
	"Slows the game down while its window is in the background (15 frames a second when another "
	+ "window has the focus, 5 when minimised) to save power and heat. Turn it off to keep the "
	+ "table at full speed on a second monitor. Never slows a map that is loading, or a host "
	+ "with players connected."
)


## Reads both choices from the settings file at startup (Root, before any map loads).
static func apply_startup(config: ConfigFile) -> void:
	FoliageEdges.current = FoliageEdges.stored(config)
	ShadowCascades.current = ShadowCascades.stored(config)
	GroundClipmapSetting.current = GroundClipmapSetting.stored(config)
	IdleThrottle.enabled = IdleThrottle.stored(config)


## Puts the saved choices on the options without applying them (Root applied them at startup).
static func show_saved(menu: SettingsMenu, config: ConfigFile) -> void:
	_select(menu.foliage_edges_option, FoliageEdges.stored(config))
	_select(menu.shadow_cascades_option, ShadowCascades.stored(config))
	_select(menu.ground_detail_option, GroundClipmapSetting.stored(config))
	menu.idle_throttle_check.set_pressed_no_signal(IdleThrottle.stored(config))


static func save(menu: SettingsMenu, config: ConfigFile) -> void:
	config.set_value("graphics", IdleThrottle.KEY, menu.idle_throttle_check.button_pressed)
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
	config.set_value(
		"graphics",
		GroundClipmapSetting.KEY,
		GroundClipmapSetting.sanitize(menu.ground_detail_option.get_selected_id())
	)


static func show_defaults(menu: SettingsMenu) -> void:
	menu.idle_throttle_check.set_pressed_no_signal(IdleThrottle.DEFAULT)
	_select(menu.foliage_edges_option, FoliageEdges.DEFAULT)
	_select(menu.shadow_cascades_option, ShadowCascades.DEFAULT)
	_select(menu.ground_detail_option, GroundClipmapSetting.DEFAULT)


## Applies both choices now, with the Antialiasing level: the map on screen sets its MSAA and
## re-picks every foliage shader variant (that reads FoliageEdges.current, so it runs after it),
## the sun on screen takes its cascades, and later maps read both.
static func apply(menu: SettingsMenu, game_map: Node3D) -> void:
	FoliageEdges.current = FoliageEdges.sanitize(menu.foliage_edges_option.get_selected_id())
	ShadowCascades.current = ShadowCascades.sanitize(menu.shadow_cascades_option.get_selected_id())
	GroundClipmapSetting.current = GroundClipmapSetting.sanitize(
		menu.ground_detail_option.get_selected_id()
	)
	IdleThrottle.set_enabled(menu.idle_throttle_check.button_pressed)
	if game_map == null:
		return
	game_map.set_foliage_antialiasing_level(menu.antialiasing_option.selected)
	if game_map.world_viewport:
		ShadowCascades.apply_in(game_map.world_viewport, ShadowCascades.current)


static func apply_tooltips(menu: SettingsMenu) -> void:
	menu.foliage_edges_option.tooltip_text = FOLIAGE_EDGES_TOOLTIP
	menu.shadow_cascades_option.tooltip_text = SHADOW_CASCADES_TOOLTIP
	menu.ground_detail_option.tooltip_text = GROUND_DETAIL_TOOLTIP
	menu.idle_throttle_check.tooltip_text = IDLE_THROTTLE_TOOLTIP


static func _select(option: OptionButton, choice: int) -> void:
	var index := option.get_item_index(choice)
	option.select(index if index >= 0 else 0)
