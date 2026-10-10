class_name MapViewFit
extends RefCounted

## One camera model for play and authoring, so the author judges a map from the views a
## player gets: the zoom-out reaches a view of the whole map (never less than the camera's
## own PLAY_MAX_ZOOM), an authored map's pan range is its own extent even where nothing
## stands yet, the near plane stays above the highest ground, and every frame the sun's
## shadows reach the far side of the part of the map in view
## (LevelEnvironmentManager.fit_shadow_distance_to_view).
##
## LevelPlayController and AuthoringController each own one: fit() once a map is installed,
## refit() when an edit (or a live map-scale change) moved what it was fit to, follow() from
## their _process, clear() when the map goes. A plain object, not a node, so a controller
## that is never set up (tests) holds one for free.
##
## Heights follow the ground's real range (sculpted ground can rise above or sink below
## Y = 0; a Blender map's is taken as 0): the zoom fit, the pan bounds and the shadow bounds
## all span the lowest ground to the highest plus CONTENT_HEIGHT_M of canopy. The extent is
## the map document's when there is one (a dressed GLB's covers the GLB), else a Blender
## map's mesh bounds (LevelEnvironmentManager.compute_map_bounds). A map with a GLB keeps
## the mesh-walk pan bounds GameMap.notify_map_loaded() gave it.

const MIN_ZOOM := 2.0
## The zoom-out limit before a map is fit, and the least any map gets (the exported
## CameraController.max_zoom).
const PLAY_MAX_ZOOM := 20.0
## Room around a whole map at the widest zoom.
const ZOOM_FIT_MARGIN := 1.08
## Height the zoom-out fit leaves room for above the ground: the tallest palette trees.
const CONTENT_HEIGHT_M := 12.0

## The world-space box the sun's shadows need to reach: the map's extent from its lowest
## ground to its highest plus CONTENT_HEIGHT_M. Empty while no map is fit.
var shadow_bounds: AABB = AABB()
## The zoom-out limit (CameraController's 16:9 reference size) the last fit set.
var max_zoom: float = PLAY_MAX_ZOOM

var _game_map: GameMap = null
var _environment: LevelEnvironmentManager = null
var _map_root: Node3D = null
## The map's extent in its root's frame, flat at Y = 0.
var _local_extent: AABB = AABB()
## Whether the pan range is the extent (an authored map with no GLB).
var _pans_on_extent: bool = false
## The ground range the last fit used.
var _fitted_ground: Vector2 = Vector2.ZERO


## The GameMap whose camera this fits and the environment whose sun it keeps in reach.
func setup(game_map: GameMap, environment: LevelEnvironmentManager) -> void:
	_game_map = game_map
	_environment = environment


## Fits the camera to `map_root`, already installed in the GameMap (MapSourceLoader.install).
## `document` is the map's document, or null for a Blender map without one.
func fit(map_root: Node3D, document: MapDocument) -> void:
	_map_root = map_root
	if document != null:
		var extent := document.extent_m()
		_local_extent = AABB(
			Vector3(-extent.x, 0.0, -extent.y) * 0.5, Vector3(extent.x, 0.0, extent.y)
		)
	else:
		var world := LevelEnvironmentManager.compute_map_bounds(map_root)
		_local_extent = map_root.global_transform.affine_inverse() * world
		_local_extent.position.y = 0.0
		_local_extent.size.y = 0.0
	_pans_on_extent = document != null and not document.has_base_map
	refit()


## Fits again to the current ground range and the map root's current transform. Does
## nothing while no map is fit.
func refit() -> void:
	if not _has_map():
		return
	var ground := ground_range()
	_fitted_ground = ground
	var bounds := view_bounds(_local_extent, _map_root.global_transform, ground)
	var fit_size := (
		_game_map.fit_zoom_for_extent(
			Vector2(bounds.size.x, bounds.size.z), ground.y + CONTENT_HEIGHT_M, ground.x
		)
		* ZOOM_FIT_MARGIN
	)
	max_zoom = maxf(PLAY_MAX_ZOOM, fit_size)
	_game_map.set_zoom_limits(MIN_ZOOM, max_zoom)
	if _pans_on_extent:
		_game_map.set_map_bounds(bounds)
	shadow_bounds = bounds.expand(
		Vector3(bounds.position.x, ground.y + CONTENT_HEIGHT_M, bounds.position.z)
	)


## True when the ground's range differs from the one the last fit used (a sculpt settled).
func ground_moved() -> bool:
	return _has_map() and not ground_range().is_equal_approx(_fitted_ground)


## The per-frame half: the near plane follows raised ground at once (the range only widens
## mid-stroke), and the sun's shadow distance follows the view. Called from the owner's
## _process; does nothing while no map is fit.
func follow() -> void:
	if not _has_map():
		return
	var ground := ground_range()
	_game_map.set_ground_top(ground.y)
	_environment.fit_shadow_distance_to_view(
		_game_map.camera_node, Vector2(_game_map.world_viewport.size), shadow_bounds, ground.x
	)


## Forgets the map and puts the zoom-out limit back to PLAY_MAX_ZOOM.
func clear() -> void:
	_map_root = null
	shadow_bounds = AABB()
	_fitted_ground = Vector2.ZERO
	max_zoom = PLAY_MAX_ZOOM
	if is_instance_valid(_game_map):
		_game_map.set_zoom_limits(MIN_ZOOM, PLAY_MAX_ZOOM)


## The ground's world height range (lowest, highest): the authored terrain's, or 0..0 for a
## map without one.
func ground_range() -> Vector2:
	if not _has_map():
		return Vector2.ZERO
	var terrain := _map_root.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	return terrain.world_height_range() if terrain else Vector2.ZERO


## The world-space box of a map whose flat extent is `local_extent` in a root at `to_world`,
## spanning the ground range `ground` (lowest, highest) in Y. Pure.
static func view_bounds(local_extent: AABB, to_world: Transform3D, ground: Vector2) -> AABB:
	var bounds := to_world * local_extent
	bounds.position.y = ground.x
	bounds.size.y = ground.y - ground.x
	return bounds


func _has_map() -> bool:
	return is_instance_valid(_map_root) and is_instance_valid(_game_map)
