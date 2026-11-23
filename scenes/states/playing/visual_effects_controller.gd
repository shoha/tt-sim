class_name VisualEffectsController
extends Node

## Manages the lo-fi post-process shader, grid visual appearance, foliage antialiasing and the
## token ghost's budget for GameMap.
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (viewport_container,
## map_container, camera_node, and the lazily-created _grid_overlay) directly from the
## injected GameMap reference at call time, since several of these are only set up after
## this sub-component is constructed.

var _game_map: GameMap = null

var _lofi_material: ShaderMaterial = null  # Cached lo-fi material (from scene or created)
var _foliage_antialiasing_level: int = Viewport.MSAA_DISABLED  # Current Antialiasing setting
var _eye_view_active: bool = false  # The eye view raises the level to at least 4x

## Seconds since the token ghost budget last looked at the tokens (TokenGhost.apply_budget).
var _ghost_budget_s := 0.0


## Wire this controller to its owning GameMap and run initial setup:
## cache the scene's lo-fi material and load the lo-fi, see-through and antialiasing settings
## from config.
func setup(game_map: GameMap) -> void:
	_game_map = game_map

	# Cache the lo-fi material from the scene (if present).
	# This allows editor-tweaked values to be preserved.
	if game_map.viewport_container and game_map.viewport_container.material is ShaderMaterial:
		_lofi_material = game_map.viewport_container.material as ShaderMaterial

	_load_lofi_setting()
	_load_see_through_settings()
	_load_foliage_antialiasing_setting()
	apply_foliage_antialiasing()


## Load lo-fi filter setting from config
func _load_lofi_setting() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)

	# Default to enabled if no setting exists
	var lofi_enabled = true
	if err == OK:
		lofi_enabled = config.get_value("graphics", "lofi_enabled", true)

	set_lofi_enabled(lofi_enabled)


## Enable or disable the lo-fi visual filter
func set_lofi_enabled(enabled: bool) -> void:
	if _game_map.viewport_container:
		if enabled:
			# Use the cached material (from scene) or create a default one
			if not _lofi_material:
				_lofi_material = _create_default_lofi_material()
			_game_map.viewport_container.material = _lofi_material
		else:
			# Remove the shader to show unprocessed viewport
			_game_map.viewport_container.material = null


## Create a default lo-fi material with sensible defaults
## Used as fallback if no material is defined in the scene
func _create_default_lofi_material() -> ShaderMaterial:
	var shader = load("res://shaders/lofi_canvas.gdshader")
	var material = ShaderMaterial.new()
	material.shader = shader
	# Apply shared defaults — prefer setting values in the scene's material
	for param_name in Constants.LOFI_DEFAULTS:
		material.set_shader_parameter(param_name, Constants.LOFI_DEFAULTS[param_name])
	return material


## Override lo-fi shader parameters from map data
## Call this after loading a map to apply map-specific visual settings
## Parameters dict can contain any subset of shader parameter names
func apply_lofi_overrides(overrides: Dictionary) -> void:
	if not _lofi_material:
		_lofi_material = _create_default_lofi_material()

	for param_name in overrides:
		_lofi_material.set_shader_parameter(param_name, overrides[param_name])


## Load grid visual settings from config and apply to the overlay.
## Called by GameMap once the GridOverlay has been created (setup_grid_overlay()).
func load_grid_visual_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	if err != OK:
		return
	if not _game_map._grid_overlay:
		return
	var cell_tint_opacity: float = config.get_value("grid_visuals", "cell_tint_opacity", 0.65)
	var line_thickness: float = config.get_value("grid_visuals", "line_thickness", 2.0)
	var fade_radius: float = config.get_value("grid_visuals", "fade_radius", 30.0)
	_game_map._grid_overlay.apply_visual_settings(cell_tint_opacity, line_thickness, fade_radius)


## Apply grid visual settings from the settings menu.
func apply_grid_visual_settings(
	cell_tint_opacity: float, line_thickness: float, fade_radius: float
) -> void:
	if _game_map._grid_overlay:
		_game_map._grid_overlay.apply_visual_settings(
			cell_tint_opacity, line_thickness, fade_radius
		)


## The saved Token ghost setting, on by default. Loaded once at setup; the Settings menu calls
## the setter below to apply a change at once. (graphics/occlusion_fade_enabled and
## graphics/canopy_fade_enabled in an old settings file are never read: both fades were removed.)
func _load_see_through_settings() -> void:
	var config := ConfigFile.new()
	config.load(Paths.SETTINGS_PATH)
	set_token_ghost_enabled(
		config.get_value("graphics", "token_ghost_enabled", TokenGhost.DEFAULT_ENABLED)
	)
	TokenToon.painted = SettingsTokenShading.saved_id(config) == TokenToon.SHADING_PAINTED
	SettingsTokenPins.apply_id(SettingsTokenPins.saved_id(config))


## Turns the token ghost (the see-through silhouette of a covered token) on or off for every
## token on the map and for the tokens made later.
func set_token_ghost_enabled(enabled: bool) -> void:
	TokenGhost.set_enabled(enabled, _game_map.get_tree())


## Re-dresses every token after a map load (the map's tokens exist by then) with the current
## Token ghost setting.
func refresh_token_ghosts() -> void:
	TokenToon.refresh_all(_game_map.get_tree())
	TokenGhost.refresh_all(_game_map.get_tree())


func _process(delta: float) -> void:
	_ghost_budget_s += delta
	if _ghost_budget_s >= TokenGhost.BUDGET_PERIOD_S:
		_ghost_budget_s = 0.0
		TokenGhost.apply_budget(_game_map.get_tree(), _game_map.camera_node)


func _load_foliage_antialiasing_setting() -> void:
	_foliage_antialiasing_level = saved_antialiasing_level()


## The saved Antialiasing setting (a Viewport.MSAA value), MSAA_DISABLED when unset or
## unreadable. Static so the graphics warm-up can match its viewport to it before any
## controller exists.
static func saved_antialiasing_level(path: String = Paths.SETTINGS_PATH) -> int:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return Viewport.MSAA_DISABLED
	return int(config.get_value("graphics", "antialiasing", Viewport.MSAA_DISABLED))


## Set the foliage antialiasing level (a Viewport.MSAA enum value) and apply it
## immediately -- called by the Settings menu, so a change takes effect mid-session,
## not just on the next map load.
func set_foliage_antialiasing_level(level: int) -> void:
	_foliage_antialiasing_level = level
	apply_foliage_antialiasing()


## Apply the current foliage antialiasing level: sets the game-world SubViewport's
## MSAA level and swaps every foliage ShaderMaterial between the antialiased and
## plain-cutout shader variants. Called from setup() and again from
## GameMap.notify_map_loaded() whenever a new map finishes loading -- freshly loaded
## foliage materials always default to the antialiased shader
## (WindFoliage.apply_material() always assigns get_shader()), so the "off" state
## must be reapplied on every map load, not just once.
func apply_foliage_antialiasing() -> void:
	if _game_map.world_viewport:
		_game_map.world_viewport.msaa_3d = effective_antialiasing_level() as Viewport.MSAA
	_apply_antialiasing_variant(
		WindFoliage.collect_foliage_shader_materials(_game_map.map_container)
	)


## The Antialiasing level in effect: the saved setting, raised to MSAA 4x while the eye view is
## on (a perspective view at eye height stair-steps fences, roof edges and thin foliage with MSAA
## off, card eyeprobe 2026-11-02; the orthographic view does not). A setting above 4x is kept.
## Eye view smoothing off (FoliageEdges.eye_smoothing, Settings > Graphics) keeps the setting.
func effective_antialiasing_level() -> int:
	if _eye_view_active and FoliageEdges.eye_smoothing:
		return maxi(_foliage_antialiasing_level, Viewport.MSAA_4X)
	return _foliage_antialiasing_level


## Raise (or put back) the antialiasing level for the eye view; applies at once. The setting
## itself is not changed, so leaving the eye restores exactly what the player chose.
func set_eye_view_antialiasing(active: bool) -> void:
	if _eye_view_active == active:
		return
	_eye_view_active = active
	apply_foliage_antialiasing()


## Gives wind materials created after the map loaded (a species first painted mid-session;
## see AuthoredScatter.species_added) the bookkeeping notify_map_loaded() gives load-time
## ones: every material gets the current Antialiasing setting's shader variant.
func adopt_foliage_materials(materials: Array[ShaderMaterial]) -> void:
	_apply_antialiasing_variant(materials)


## Points `materials` at the antialiased or plain-cutout wind shader for the current level and
## the Foliage edges setting (FoliageEdges: Fast keeps the plain cutout under MSAA), each keeping
## its plain or painted-light form (WindFoliage.shader_for).
func _apply_antialiasing_variant(materials: Array[ShaderMaterial]) -> void:
	var antialiased := FoliageEdges.uses_antialiased_shader(
		effective_antialiasing_level(), FoliageEdges.current
	)
	if not antialiased and not WindFoliage.get_shader_no_aa():
		push_warning(
			(
				"VisualEffectsController: wind_foliage_no_aa.gdshader failed to load -- "
				+ "foliage antialiasing setting has no effect on shader selection"
			)
		)
		return
	for mat in materials:
		mat.shader = WindFoliage.shader_for(mat, antialiased)
