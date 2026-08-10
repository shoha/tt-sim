class_name VisualEffectsController
extends Node

## Manages the lo-fi post-process shader, grid visual appearance, and the
## occlusion fade effect for GameMap.
##
## Created as a child Node of GameMap in _ready() (mirrors the AssetManager
## facade/sub-component pattern). Reads node references (viewport_container,
## occlusion_fade, map_container, camera_node, drag_and_drop_node, and the
## lazily-created _grid_overlay) directly from the injected GameMap reference
## at call time, since several of these are only set up after this
## sub-component is constructed.

var _game_map: GameMap = null

var _lofi_material: ShaderMaterial = null  # Cached lo-fi material (from scene or created)
var _occlusion_fade_enabled: bool = true  # Whether the occlusion fade effect is active
var _foliage_antialiasing_level: int = Viewport.MSAA_DISABLED  # Current Antialiasing setting


## Wire this controller to its owning GameMap and run initial setup:
## cache the scene's lo-fi material, load lo-fi/occlusion settings from
## config, and perform the initial occlusion fade setup.
func setup(game_map: GameMap) -> void:
	_game_map = game_map

	# Cache the lo-fi material from the scene (if present).
	# This allows editor-tweaked values to be preserved.
	if game_map.viewport_container and game_map.viewport_container.material is ShaderMaterial:
		_lofi_material = game_map.viewport_container.material as ShaderMaterial

	_load_lofi_setting()
	_load_occlusion_fade_setting()
	setup_occlusion_fade()
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
	# Keep occlusion dither grid aligned with lo-fi pixelation
	_sync_lofi_pixelation()


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

	# If pixelation was among the overrides, sync it to the occlusion shader
	if "pixelation" in overrides:
		_sync_lofi_pixelation()


## Sync the lo-fi pixelation value to the occlusion fade manager so its dither
## grid aligns with the post-process pixelation. Pass 0 when lo-fi is off.
func _sync_lofi_pixelation() -> void:
	if not _game_map.occlusion_fade:
		return
	var px := 0.0
	if _game_map.viewport_container and _game_map.viewport_container.material is ShaderMaterial:
		var mat := _game_map.viewport_container.material as ShaderMaterial
		var val = mat.get_shader_parameter("pixelation")
		if val != null:
			px = float(val)
	_game_map.occlusion_fade.set_lofi_pixelation(px)


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


## Load occlusion fade setting from config
func _load_occlusion_fade_setting() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	var enabled = true
	if err == OK:
		enabled = config.get_value("graphics", "occlusion_fade_enabled", true)
	set_occlusion_fade_enabled(enabled)


## Enable or disable the occlusion fade effect
func set_occlusion_fade_enabled(enabled: bool) -> void:
	_occlusion_fade_enabled = enabled
	if not _game_map.occlusion_fade:
		return
	if enabled:
		# Re-setup if a map is already loaded
		if _game_map.map_container and _game_map.map_container.get_child_count() > 0:
			_game_map.occlusion_fade.setup(
				_game_map.camera_node, _game_map.map_container, _game_map.drag_and_drop_node
			)
			_sync_lofi_pixelation()
	else:
		_game_map.occlusion_fade.clear()


## Initialize the occlusion fade manager with node references.
## Called from setup() and again from GameMap.notify_map_loaded() whenever a
## new map finishes loading (the mesh cache must be rebuilt for new geometry).
func setup_occlusion_fade() -> void:
	if _game_map.occlusion_fade and _occlusion_fade_enabled:
		_game_map.occlusion_fade.setup(
			_game_map.camera_node, _game_map.map_container, _game_map.drag_and_drop_node
		)
		_sync_lofi_pixelation()


## Load the foliage antialiasing setting from config.
func _load_foliage_antialiasing_setting() -> void:
	var config = ConfigFile.new()
	var err = config.load(Paths.SETTINGS_PATH)
	var level = Viewport.MSAA_DISABLED
	if err == OK:
		level = config.get_value("graphics", "antialiasing", Viewport.MSAA_DISABLED)
	_foliage_antialiasing_level = level


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
		_game_map.world_viewport.msaa_3d = _foliage_antialiasing_level
	var materials := WindFoliage.collect_foliage_shader_materials(_game_map.map_container)
	if _foliage_antialiasing_level == Viewport.MSAA_DISABLED:
		var no_aa_shader := WindFoliage.get_shader_no_aa()
		if not no_aa_shader:
			push_warning(
				(
					"VisualEffectsController: wind_foliage_no_aa.gdshader failed to load -- "
					+ "foliage antialiasing setting has no effect on shader selection"
				)
			)
			return
		for mat in materials:
			mat.shader = no_aa_shader
	else:
		var aa_shader := WindFoliage.get_shader()
		for mat in materials:
			mat.shader = aa_shader
