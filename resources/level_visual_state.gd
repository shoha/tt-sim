class_name LevelVisualState
extends RefCounted

## Transient bundle of every live-editable visual field on a LevelData. It is
## the one unit the Visuals drawer snapshots on open, restores on Cancel, writes
## on Save and broadcasts to clients, and the one unit the client receive path
## patches and re-applies. It is never persisted: LevelData is the on-disk shape,
## this is a copy of the editable subset with independent ownership of every
## dictionary and resource, so holding one across edits cannot alias live data.
##
## Adding a live-synced visual property means: a field here, one line in
## from_level_data(), apply_to_level_data(), copy(), to_broadcast_dict() and
## patch_from_broadcast_dict(), one apply line in
## LevelPlayController.apply_visual_state(), and the panel control. A new field
## on VisualSettings also needs a line in apply_to_level_data() -- it assigns
## level_data.visual_settings.sun (the one field it currently carries), not the
## whole visual_settings, so a sibling field needs its own assignment line too.
## water is carried the same way as foliage: a typed resource field, copied in
## and out, with water_style derived from it rather than authored independently.
##
## The three grid fields (grid_cell_size, display_unit, display_unit_per_cell)
## are the exception: they ride along in from_level_data()/apply_to_level_data()/
## copy() for the drawer's snapshot/restore, but are deliberately absent from
## to_broadcast_dict()/patch_from_broadcast_dict() -- grid scale is not networked
## -- and are not applied by LevelPlayController.apply_visual_state(). A caller
## that changes them must call LevelPlayController.update_measure_tool_scale()
## itself after writing them to level data.

var light_intensity_scale: float = 1.0
var environment_preset: String = ""
var environment_overrides: Dictionary = {}
var water_style: String = WaterPresets.DEFAULT_PRESET
var water: WaterSettings = WaterSettings.default()
var lofi: LofiSettings = LofiSettings.default()
var weather: WeatherSettings = WeatherSettings.default()
var foliage: FoliageSettings = FoliageSettings.default()
var sun: SunSettings = SunSettings.default()
var grid_cell_size: float = LevelData.DEFAULT_GRID_CELL_SIZE
var display_unit: String = LevelData.DEFAULT_DISPLAY_UNIT
var display_unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL


## Independent snapshot of the level's editable visuals.
static func from_level_data(level_data: LevelData) -> LevelVisualState:
	var state := LevelVisualState.new()
	state.light_intensity_scale = level_data.light_intensity_scale
	state.environment_preset = level_data.environment_preset
	state.environment_overrides = level_data.environment_overrides.duplicate()
	state.water_style = level_data.water_style
	state.water = level_data.water.copy_settings()
	state.lofi = level_data.lofi.copy_settings()
	state.weather = level_data.weather.copy_settings()
	state.foliage = level_data.foliage.copy_settings()
	state.sun = level_data.visual_settings.sun.copy_settings()
	state.grid_cell_size = level_data.grid_cell_size
	state.display_unit = level_data.display_unit
	state.display_unit_per_cell = level_data.display_unit_per_cell
	return state


## Write this state into a level as independent copies, so later edits to the
## level cannot reach back into this snapshot (the drawer's Cancel depends on it).
func apply_to_level_data(level_data: LevelData) -> void:
	level_data.light_intensity_scale = light_intensity_scale
	level_data.environment_preset = environment_preset
	level_data.environment_overrides = environment_overrides.duplicate()
	level_data.water = water.copy_settings()
	# Derived, not authored: the closest Look for builds that only know the
	# two style names.
	level_data.water_style = water.matching_look()
	level_data.lofi = lofi.copy_settings()
	level_data.weather = weather.copy_settings()
	level_data.foliage = foliage.copy_settings()
	level_data.visual_settings.sun = sun.copy_settings()
	level_data.grid_cell_size = grid_cell_size
	level_data.display_unit = display_unit
	level_data.display_unit_per_cell = display_unit_per_cell


func copy() -> LevelVisualState:
	var state := LevelVisualState.new()
	state.light_intensity_scale = light_intensity_scale
	state.environment_preset = environment_preset
	state.environment_overrides = environment_overrides.duplicate()
	state.water_style = water_style
	state.water = water.copy_settings()
	state.lofi = lofi.copy_settings()
	state.weather = weather.copy_settings()
	state.foliage = foliage.copy_settings()
	state.sun = sun.copy_settings()
	state.grid_cell_size = grid_cell_size
	state.display_unit = display_unit
	state.display_unit_per_cell = display_unit_per_cell
	return state


## The full live-settings payload NetworkManager.broadcast_visual_settings()
## understands (it serialises environment_overrides itself). Grid scale is not
## networked today, so it is not included.
func to_broadcast_dict() -> Dictionary:
	return {
		"light_intensity": light_intensity_scale,
		"environment_preset": environment_preset,
		"environment_overrides": environment_overrides.duplicate(),
		"lofi_overrides": lofi.to_dict(),
		"weather_overrides": weather.to_dict(),
		"foliage_overrides": foliage.to_dict(),
		"sun_settings": sun.to_dict(),
		"water_style": water.matching_look(),
		"water_overrides": water.to_dict(),
	}


## Apply a partial broadcast (any subset of to_broadcast_dict()'s keys) on top of
## this state. environment_overrides is only read alongside environment_preset,
## matching how the host sends them.
func patch_from_broadcast_dict(settings: Dictionary) -> void:
	if settings.has("light_intensity"):
		light_intensity_scale = float(settings["light_intensity"])
	if settings.has("environment_preset"):
		environment_preset = str(settings["environment_preset"])
		var overrides: Variant = settings.get("environment_overrides", {})
		environment_overrides = (
			(overrides as Dictionary).duplicate() if overrides is Dictionary else {}
		)
	if settings.has("lofi_overrides"):
		lofi = LofiSettings.from_dict(settings["lofi_overrides"])
	if settings.has("weather_overrides"):
		weather = WeatherSettings.from_dict(settings["weather_overrides"])
	if settings.has("foliage_overrides"):
		foliage = FoliageSettings.from_dict(settings["foliage_overrides"])
	if settings.has("sun_settings"):
		var raw: Variant = settings["sun_settings"]
		sun = SunSettings.from_dict(raw) if raw is Dictionary else SunSettings.default()
	if settings.has("water_overrides"):
		water = WaterSettings.from_dict(settings["water_overrides"])
		water_style = water.matching_look()
	elif settings.has("water_style"):
		# An older host sends only the style name.
		water_style = str(settings["water_style"])
		water = WaterSettings.from_style(water_style)
