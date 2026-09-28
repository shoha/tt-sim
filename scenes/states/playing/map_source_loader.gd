class_name MapSourceLoader
extends RefCounted

## Builds a map's root node from its files (a Blender-made map.glb, an authored map.ttmap,
## or both) and installs it into a GameMap. Shared by play-time loading (LevelPlayLoader,
## including the client download path) and authoring mode (AuthoringController), so the
## author sees exactly the nodes a player's load builds.
##
## Extracted from LevelPlayLoader, which used to own all of this through its
## LevelPlayController back-reference. The context a load needs (the SceneTree to wait
## frames on, the level's light scale and foliage overrides, a "was this load superseded"
## check) is plain fields here, so an owner without a LevelPlayController can use it.
##
## One instance per load: set the fields, await load_async() or build_async(), read
## `document` afterwards. install() is static and does the scene-side half.

## Main-thread time per frame the authored scatter build (species resolution, then cells)
## and the terrain chunk build may take before yielding, so a painted map loads without a
## long stall.
const FRAME_BUDGET_USEC: int = 8000
## Map-default lighting for a map with no GLB, written as the same scene extras a
## terrain-paint GLB carries (GlbUtils.extract_lighting_config reads them into the
## map-defaults layer, below any preset or override the level sets). Authored maps have no
## Blender world to take ambient light from, and with the bare PROPERTY_DEFAULTS they read
## darker and more olive than a Blender-made map. A sky-tinted fill, a little stronger than
## the default, lifts shadows toward blue and freshens the palette greens; a brighter
## neutral fill was tried and made the ground flatter and more khaki. Judged at the game
## camera beside the river level (2026-09-26). The backdrop past the map (where the ground
## skirt fades out) is a soft blue-grey haze in the same family as that fill: chosen over the
## default 0.3 grey, a warm paper, a dark slate and a moss green from zoomed-out renders
## (T7); it reads as mist around a diorama instead of a void.
const AUTHORED_MAP_LIGHTING := {
	"tt_ambient_light_color": [0.5, 0.58, 0.72],
	"tt_ambient_light_energy": 0.75,
	"tt_background_color": [0.56, 0.61, 0.67],
}
## The AuthoredScatter holding the document's generated scatter (and, when props are not
## kept apart, its props too).
const SCATTER_NODE := "AuthoredScatter"
## The AuthoredScatter holding hand-placed props, when separate_props is on.
const PROPS_NODE := "AuthoredProps"

var tree: SceneTree = null
## LevelData.light_intensity_scale of the level being loaded.
var light_intensity_scale: float = 1.0
## LevelData.foliage.to_dict() of the level being loaded, baked into wind materials.
var foliage_overrides: Dictionary = {}
## Authoring keeps the document's props in their own AuthoredScatter (PROPS_NODE) and always
## creates both nodes, even empty, because its tools edit scatter and props apart and write
## each back to the document. Play merges them into one node (fewer MultiMeshes) and creates
## it only when there are rows.
var separate_props: bool = false
## func() -> bool: true when a newer load or a reset replaced this one while it waited;
## everything built is freed and the load returns null.
var is_superseded: Callable = func() -> bool: return false
## The document load_async() read (or build_async() was given), or null when there is none
## or it could not be read.
var document: MapDocument = null
## The water geometry the authored root's worker built (AuthoredLoadPrep.WATER), for
## add_authored_water(); {} otherwise.
var _prepared_water: Dictionary = {}


func _init(scene_tree: SceneTree = null) -> void:
	tree = scene_tree


## Builds the map root from its files: the GLB (with its scatter filtered by the document's
## erase mask), or a bare root with an AuthoredTerrain when there is no GLB, plus the
## document's scatter and props as AuthoredScatter children of the root. Either path may be
## "" but not both. Returns null on failure, or when superseded (anything built is freed).
##
## The document is read, validated and split into 10 m cells on a worker thread; species
## load on background threads and resolve a few per frame; cells are built within a
## per-frame time budget.
func load_async(glb_path: String, document_path: String) -> Node3D:
	var cells := {}
	if document_path != "":
		var work := {}
		var separate := separate_props
		var task := WorkerThreadPool.add_task(
			func() -> void: read_document_work(document_path, separate, work),
			false,
			"MapSourceLoader map document"
		)
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		if is_superseded.call():
			return null
		for warning in work.get("warnings", PackedStringArray()):
			push_warning("MapSourceLoader: map document: " + warning)
		document = work.get("document")
		cells = work.get("cells", {})
		if document == null:
			if glb_path == "":
				push_error("MapSourceLoader: Map document could not be read: " + document_path)
				return null
			report_document_problem("Map document could not be read: " + document_path)
	return await _build_async(glb_path, cells)


## build_async() for a document already in memory (a new map, or a GLB being dressed whose
## document is not saved yet); `doc` may be null when there is a GLB. The rows are split
## into cells on the main thread, which is only cheap for a small or empty document.
func build_async(glb_path: String, doc: MapDocument) -> Node3D:
	document = doc
	var cells := {}
	if doc != null:
		cells = cells_of_document(doc, separate_props)
	return await _build_async(glb_path, cells)


func _build_async(glb_path: String, cells: Dictionary) -> Node3D:
	var root: Node3D = null
	if glb_path != "":
		var result = await GlbUtils.load_map_async(
			glb_path,
			true,
			light_intensity_scale,
			foliage_overrides,
			document.erase_filter() if document else Callable()
		)
		if is_superseded.call():
			if result.success:
				result.scene.free()
			return null
		if not result.success:
			return null
		root = result.scene
	elif document != null:
		root = await _create_authored_root_async(document)
		if root == null:
			return null
	else:
		push_error("MapSourceLoader: a map needs a GLB or a document")
		return null
	add_authored_water(root, document, separate_props, _prepared_water)
	_prepared_water = {}

	var groups: Array = [[SCATTER_NODE, cells.get(SCATTER_NODE, {})]]
	if separate_props:
		groups.append([PROPS_NODE, cells.get(PROPS_NODE, {})])
	for group in groups:
		var rows_by_cell: Dictionary = group[1]
		if rows_by_cell.is_empty() and not separate_props:
			continue
		var scatter := AuthoredScatter.create(PaletteLibrary.DEFAULT_ROOT, foliage_overrides)
		scatter.name = group[0]
		root.add_child(scatter)
		if rows_by_cell.is_empty():
			continue
		if not await _build_authored_scatter_async(scatter, rows_by_cell):
			scatter.release_prepared()
			root.free()
			return null
	return root


## The root of a map that has no GLB: a bare Node3D (named LevelMap) holding the document's
## AuthoredTerrain, and carrying the authored-map lighting as scene extras so it enters the
## same map-defaults layer a GLB's extras do (see AUTHORED_MAP_LIGHTING).
static func create_authored_root(doc: MapDocument) -> Node3D:
	var root := authored_root_shell()
	root.add_child(AuthoredTerrain.create(doc))
	return root


## Adds the document's water (AuthoredWater) to a map root, authored or a dressed GLB's, and
## gives every water mesh in the root the shared water material (a dressed GLB's own planes
## were processed by its load; the pass is safe to repeat, and the authored flow map wins,
## WaterGlbUtils._flow_map_plane). `always` (authoring) adds the node even with no water
## yet, so the water tools and the grid's ground have it from the start. Nothing without a
## document. `built` is the water geometry a worker built (AuthoredWater.create). Returns
## the node or null.
static func add_authored_water(
	root: Node3D, doc: MapDocument, always: bool, built: Dictionary = {}
) -> AuthoredWater:
	if doc == null or (doc.water_bodies.is_empty() and not always):
		return null
	var water := AuthoredWater.create(doc, built)
	root.add_child(water)
	WaterGlbUtils.process_water_meshes(root)
	return water


static func authored_root_shell() -> Node3D:
	var root := Node3D.new()
	root.name = "LevelMap"
	root.set_meta(GlbUtils.SCENE_EXTRAS_META, AUTHORED_MAP_LIGHTING.duplicate(true))
	return root


## create_authored_root() spread over frames: the ground textures load on background
## threads while workers compute the pure data (AuthoredLoadPrep: the wet dressing, the
## water geometry, the rule fields, the skirt and every chunk's arrays), then the material,
## biome weights, collision and skirt are built in one frame and the chunk meshes within the
## per-frame budget. Returns null when superseded.
func _create_authored_root_async(doc: MapDocument) -> Node3D:
	var prep := AuthoredLoadPrep.start(doc)
	var pending: Array[String] = []
	# Under the headless dummy renderer the material loads them in place instead
	# (GlbUtils.threaded_loads_safe).
	var threaded := GlbUtils.threaded_loads_safe()
	for path in AuthoredTerrain.texture_paths(doc) if threaded else PackedStringArray():
		if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
	var loading := true
	while loading:
		loading = not prep.is_done()
		for path in pending:
			if (
				ResourceLoader.load_threaded_get_status(path)
				== ResourceLoader.THREAD_LOAD_IN_PROGRESS
			):
				loading = true
				break
		if loading:
			await tree.process_frame
	# Collect every threaded load (a finished one must be collected to be released) and
	# hold the textures until the material has taken them from the resource cache.
	var held: Array[Resource] = []
	for path in pending:
		held.append(ResourceLoader.load_threaded_get(path))
	var prepared := prep.finish()
	if is_superseded.call():
		return null
	var root := authored_root_shell()
	var terrain := AuthoredTerrain.create(doc, PaletteLibrary.DEFAULT_ROOT, false, prepared)
	_prepared_water = prepared.get(AuthoredLoadPrep.WATER, {})
	root.add_child(terrain)
	held.clear()
	var chunk_cells := TerrainMeshBuilder.chunk_cells(doc)
	var next := 0
	while next < chunk_cells.size():
		await tree.process_frame
		if is_superseded.call():
			root.free()
			return null
		var start := Time.get_ticks_usec()
		var batch: Array[Vector2i] = []
		while next < chunk_cells.size() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
			batch.assign([chunk_cells[next]])
			terrain.rebuild_chunks(batch)
			next += 1
	return root


## Worker-thread half of load_async(): reads and validates the document, then splits its
## rows into 10 m cells (cells_of_document). Touches no Node and no shared state; results
## go into `out` ("warnings", "document", "cells").
static func read_document_work(path: String, separate: bool, out: Dictionary) -> void:
	var read := MapDocumentIO.read(path)
	out["warnings"] = read["warnings"]
	var doc: MapDocument = read["document"]
	out["document"] = doc
	if doc == null:
		return
	out["cells"] = cells_of_document(doc, separate)


## The document's rows split into 10 m cells, per scatter node: {SCATTER_NODE:
## rows_by_cell} with the props merged in (props are hand-placed rows of the same assets;
## the document keeps them apart for saving), or with `separate` {SCATTER_NODE: scatter
## rows_by_cell, PROPS_NODE: props rows_by_cell}. Pure.
static func cells_of_document(doc: MapDocument, separate: bool) -> Dictionary:
	if separate:
		return {
			SCATTER_NODE: AuthoredScatter.rows_by_cell_of(doc.scatter),
			PROPS_NODE: AuthoredScatter.rows_by_cell_of(doc.props),
		}
	var rows := {}
	for source in [doc.scatter, doc.props]:
		for asset_id in source:
			var flat: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array())
			flat.append_array(source[asset_id])
			rows[asset_id] = flat
	return {SCATTER_NODE: AuthoredScatter.rows_by_cell_of(rows)}


## Preloads the species `rows_by_cell` uses off the main thread, then builds its cells a
## few per frame. Returns false when superseded mid-way.
func _build_authored_scatter_async(scatter: AuthoredScatter, rows_by_cell: Dictionary) -> bool:
	var assets := {}
	for cell_rows in rows_by_cell.values():
		for asset_id in cell_rows:
			assets[asset_id] = true
	scatter.prepare_assets(assets.keys())
	while scatter.has_prepared_species():
		scatter.resolve_prepared(FRAME_BUDGET_USEC)
		await tree.process_frame
		if is_superseded.call():
			return false
	scatter.begin_build()
	var keys := rows_by_cell.keys()
	var next := 0
	while next < keys.size():
		var start := Time.get_ticks_usec()
		while next < keys.size() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
			scatter.build_cells({keys[next]: rows_by_cell[keys[next]]})
			next += 1
		await tree.process_frame
		if is_superseded.call():
			return false
	scatter.end_build()
	return true


## Gives a Blender map's grid overlay its ground (GroundHeightField.for_glb): after install(),
## waits one physics frame so the map's collision is in the space, then samples its layer-1
## collision and water surfaces (WaterSurface.WALKABLE_MASK: the grid lies on the water) on a
## GroundHeightField.grid_for_bounds() grid over the map's mesh bounds with
## DressingGround rays, FRAME_BUDGET_USEC per frame, and hands the field to
## GameMap.set_grid_ground() (null, the fixed band, for a map with no layer-1 collision or
## whose ground is at Y = 0 already). A map with authored terrain has its field already and
## is skipped. Returns {"samples", "ray_ms", "missed", "wall_ms", "follows_ground"} for
## measurement, or {} when skipped or superseded (the map left the container, or
## is_superseded()).
func fit_grid_ground_async(map: Node3D, game_map: GameMap) -> Dictionary:
	if map.get_node_or_null(^"AuthoredTerrain") != null:
		return {}
	var started := Time.get_ticks_usec()
	await tree.physics_frame
	if not _still_installed(map, game_map):
		return {}
	var to_world := map.global_transform
	var world_bounds := LevelEnvironmentManager.compute_map_bounds(map)
	var grid := GroundHeightField.grid_for_bounds(to_world.affine_inverse() * world_bounds)
	var sampler := DressingGround.begin_grid(
		map.get_world_3d(),
		to_world,
		world_bounds.end.y + DragPlaceController.TERRAIN_DOWNCAST_HEIGHT,
		grid.origin,
		grid.step,
		grid.columns,
		grid.rows,
		WaterSurface.WALKABLE_MASK
	)
	while not sampler.step(FRAME_BUDGET_USEC):
		await tree.process_frame
		if not _still_installed(map, game_map):
			return {}
	var field := GroundHeightField.for_glb(
		map,
		sampler.heights,
		sampler.hits,
		grid.columns,
		grid.rows,
		grid.origin,
		grid.step,
		sampler.water
	)
	game_map.set_grid_ground(field)
	return {
		"samples": sampler.heights.size(),
		"columns": grid.columns,
		"rows": grid.rows,
		"step": grid.step,
		"ray_ms": sampler.usec / 1000.0,
		"missed": sampler.miss_count(),
		"wall_ms": (Time.get_ticks_usec() - started) / 1000.0,
		"follows_ground": field != null,
		"water_samples": sampler.water.count(1),
	}


func _still_installed(map: Node3D, game_map: GameMap) -> bool:
	return (
		not is_superseded.call()
		and is_instance_valid(map)
		and is_instance_valid(game_map)
		and map.is_inside_tree()
		and map.get_parent() == game_map.map_container
	)


## A document problem that does not stop the map from loading (there is a GLB to show):
## logged, and shown to the player once.
static func report_document_problem(message: String) -> void:
	push_warning("MapSourceLoader: %s; loading the Blender map without it" % message)
	UIManager.show_toast(
		"The authored map layer could not be loaded, so the map shows without it.",
		UIManager.TOAST_WARNING,
		6.0
	)


## Puts a built map root into `game_map` as LevelMap and applies everything that depends on
## the map being in the scene: the level's transform, its environment (map defaults
## extracted from the root, preset, overrides, sun, reflection probe), water, weather,
## occlusion fade / foliage AA / camera bounds (GameMap.notify_map_loaded), the measure tool
## and grid configuration, and the wiring that hands wind materials of species first
## resolved later (AuthoredScatter.species_added) the same bookkeeping. `level` may be null
## (no level-specific settings are applied then). The foliage density budget is left to the
## caller, which knows whether to tell the player.
static func install(
	map: Node3D, game_map: GameMap, environment: LevelEnvironmentManager, level: LevelData
) -> void:
	map.name = "LevelMap"
	# Safety check: warn if transform chain is broken (non-Node3D intermediate parents)
	GlbUtils.validate_transform_chain(map)
	# Environment settings from any embedded WorldEnvironment, before the map joins the tree.
	environment.extract_and_strip_map_environment(map)
	game_map.map_container.add_child(map)
	if level:
		map.scale = level.map_scale
		map.position = level.map_offset
	# Original light energies for real-time intensity editing, wind materials for tuning.
	environment.store_original_light_energies(map)
	environment.store_wind_materials(map)
	if level:
		# Map geometry is under MapContainer by now, so the reflection probe can size itself.
		environment.apply_level_environment(level, game_map.world_viewport)
		WaterGlbUtils.apply_water_settings(level.water.to_dict())
	# The weather renderer must come after the environment it adds fog to.
	game_map.setup_weather(environment)
	if level:
		# Unconditional: the renderer is fresh, and an all-zero WeatherSettings is a no-op.
		game_map.apply_weather_overrides(level.weather.to_dict())
	# Occlusion fade cache, foliage AA, camera bounds, debug toggles.
	game_map.notify_map_loaded()
	# An authored map's ground may rise above Y = 0 (sculpted): keep the camera's near plane
	# above it. A Blender map leaves the camera as it always was.
	var terrain := map.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	if terrain:
		game_map.set_ground_top(terrain.world_height_range().y)
	# The grid draws on authored ground and token drags re-resolve their height on it; a
	# Blender map (null) keeps the cursor-hit drag height, and the fixed grid band until
	# fit_grid_ground_async() has sampled its ground. Water (either kind) raises both to its
	# surface where it is deep enough to float in (WaterSurface).
	game_map.set_ground_terrain(terrain, WaterGlbUtils.has_water(map))
	if level:
		var tool := game_map.get_measure_tool()
		if tool:
			tool.configure(level.grid_cell_size, level.display_unit, level.display_unit_per_cell)
		game_map.configure_grid(level)
	for node_name in [SCATTER_NODE, PROPS_NODE]:
		var scatter := map.get_node_or_null(NodePath(node_name)) as AuthoredScatter
		if scatter:
			scatter.species_added.connect(
				func(materials: Array[ShaderMaterial]) -> void:
					if is_instance_valid(game_map):
						game_map.adopt_foliage_materials(materials)
					environment.add_wind_materials(materials)
			)
