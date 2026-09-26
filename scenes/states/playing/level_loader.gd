class_name LevelPlayLoader

## Owns async level loading: the progressive load coroutine (map + token spawning with
## progress reporting), load-generation race protection, level queueing while a load is in
## progress, measure-tool/grid configuration from level data, and level/map clearing.
##
## Extracted from LevelPlayController -- this was the largest and highest-risk of the
## facade-splitting extractions (the async load coroutine alone spans the full progress
## lifecycle: map load, token model preload, staggered token spawn, and completion).
##
## active_level_data, loaded_map_instance, and is_editor_preview stay on LevelPlayController
## rather than moving here: external code depends on reading AND writing them directly on the
## LevelPlayController instance (e.g. app_menu_controller.gd does
## `_level_play_controller.is_editor_preview = true`, a direct external write that a
## getter-only computed property can't support). This class reaches those three fields, plus
## _game_map / _token_spawner / _network_token_sync / _environment_manager /
## _map_download_coordinator, through a back-reference to the owning LevelPlayController
## captured in setup() -- the same idea as GameMap's sub-components reading fields off their
## injected GameMap reference at call time.
##
## Plain-object sub-component (not a Node): constructed eagerly as a field default on
## LevelPlayController -- see TokenSpawner/MapDownloadCoordinator/NetworkTokenSync for the
## same pattern. Like NetworkTokenSync, it has no Node capabilities of its own (can't call
## get_tree(), is_inside_tree(), or await a process_frame), so it borrows those from the
## level_play_controller back-reference too.
##
## Named LevelPlayLoader (not LevelLoader) to avoid colliding with the pre-existing, unrelated
## global class_name LevelLoader at scenes/level_loader/level_loader.gd -- a legacy,
## apparently-unused Node3D-based level loading scene with no references anywhere else in the
## codebase. Godot requires globally unique class_name values, so reusing "LevelLoader" here
## would break project import.

signal level_loaded(level_data: LevelData)
signal level_cleared
signal token_spawned(token: BoardToken, placement: TokenPlacement)
signal level_loading_started
signal level_loading_progress(progress: float, status: String)
signal level_loading_completed

const TOKENS_PER_FRAME: int = 3  # How many tokens to spawn per frame during progressive loading
## Main-thread time per frame the authored scatter build (species resolution, then cells)
## may take before yielding, so a painted map loads without a long stall.
const FRAME_BUDGET_USEC: int = 8000
## Map-default lighting for a map with no GLB, written as the same scene extras a
## terrain-paint GLB carries (GlbUtils.extract_lighting_config reads them into the
## map-defaults layer, below any preset or override the level sets). Authored maps have no
## Blender world to take ambient light from, and with the bare PROPERTY_DEFAULTS they read
## darker and more olive than a Blender-made map. A sky-tinted fill, a little stronger than
## the default, lifts shadows toward blue and freshens the palette greens; a brighter
## neutral fill was tried and made the ground flatter and more khaki. Judged at the game
## camera beside the river level (2026-09-26).
const AUTHORED_MAP_LIGHTING := {
	"tt_ambient_light_color": [0.5, 0.58, 0.72],
	"tt_ambient_light_energy": 0.75,
}

var _level_play_controller: LevelPlayController = null
var _is_loading: bool = false  # True while async loading is in progress
var _load_generation: int = 0  # Bumped on every new load / reset_loading_state() call.
# Lets a suspended _play_level_async coroutine detect that it has been
# superseded (e.g. Root exited/re-entered PLAYING with a new GameMap) so it
# can abort instead of mutating state that now belongs to a newer load.

## Stores pending level data when a new level is requested during loading
var _queued_level_data: LevelData = null


## Initialize with a back-reference to the owning LevelPlayController, used to reach
## _game_map, _token_spawner, _network_token_sync, _environment_manager,
## _map_download_coordinator, active_level_data, loaded_map_instance, is_editor_preview, and
## Node capabilities (get_tree(), is_inside_tree()) this plain object doesn't have itself.
func setup(level_play_controller: LevelPlayController) -> void:
	_level_play_controller = level_play_controller


## Load and play a level (async version - does not block main thread)
## Returns true if loading started successfully, false on immediate failure
## Listen to level_loaded signal for completion
func play_level(level_data: LevelData) -> bool:
	if not _level_play_controller._game_map:
		push_error("LevelPlayLoader: No GameMap set. Call setup() first.")
		return false

	if _is_loading:
		# If we're already loading, queue this level to load after current completes/aborts
		# This handles cases like: host sends new level while client is still loading previous
		push_warning("LevelPlayLoader: Queueing level (currently loading)")
		_queued_level_data = level_data
		return true  # Return true - level will be loaded when current finishes

	# Start async loading
	_play_level_async(level_data)
	return true


## Internal async implementation of level loading
func _play_level_async(level_data: LevelData) -> void:
	# Bump the generation and capture it locally. If reset_loading_state() (or
	# another _play_level_async call) bumps _load_generation again while this
	# coroutine is suspended on an await, the captured value goes stale and
	# every checkpoint below will abort instead of mutating shared state.
	_load_generation += 1
	var generation: int = _load_generation

	_is_loading = true
	level_loading_started.emit()
	level_loading_progress.emit(0.0, "Preparing...")

	# Yield a few frames to let UI updates process:
	# - Loading overlay fades in
	# - Level editor fades out
	# This prevents the UI from appearing frozen during initial setup
	for i in range(3):
		await _level_play_controller.get_tree().process_frame

	# Check if we're still valid (user might have navigated away)
	if _should_abort_load(generation):
		return

	# Clear any previously loaded level first (also clears model cache)
	clear_level()

	# Yield after clearing to let freed nodes process
	await _level_play_controller.get_tree().process_frame

	# Check validity again after yield
	if _should_abort_load(generation):
		return

	# Store reference to active level
	_level_play_controller.active_level_data = level_data

	level_loading_progress.emit(0.05, "Loading map...")

	# Load the map model from level data (async)
	var map_loaded = await _load_level_map_async(level_data)

	# Check validity after async map load
	if _should_abort_load(generation):
		return

	if not map_loaded:
		push_error("LevelPlayLoader: Failed to load map")
		_abort_loading()
		return

	var drag_and_drop = _level_play_controller._game_map.drag_and_drop_node
	if not drag_and_drop:
		push_error("LevelPlayLoader: Could not find DragAndDrop3D node")
		_abort_loading()
		return

	# Pre-load all unique token models (this is the key optimization)
	# This way each model is loaded only ONCE, then tokens clone from cache
	var total_tokens = level_data.token_placements.size()
	if total_tokens > 0:
		level_loading_progress.emit(0.2, "Loading token models...")

		# Build asset list for preloading
		var assets_to_preload: Array[Dictionary] = []
		for placement in level_data.token_placements:
			assets_to_preload.append(
				{
					"pack_id": placement.pack_id,
					"asset_id": placement.asset_id,
					"variant_id": placement.variant_id
				}
			)

		if assets_to_preload.size() > 0:
			# Pre-load with progress callback (create_static_bodies=false for tokens)
			var loaded_count = await AssetManager.preload_models(
				assets_to_preload,
				func(loaded: int, total: int):
					var model_progress = 0.2 + (0.4 * loaded / max(total, 1))
					level_loading_progress.emit(
						model_progress, "Loading models... (%d/%d)" % [loaded, total]
					),
				false  # create_static_bodies
			)

		# Check validity after async model preload
		if _should_abort_load(generation):
			return

	# Now spawn tokens - this is fast since models are already cached
	var spawned_count = 0
	level_loading_progress.emit(0.6, "Spawning tokens...")

	for placement in level_data.token_placements:
		# Check validity before spawning each batch
		if _should_abort_load(generation):
			return

		var token = BoardTokenFactory.create_from_placement_async(placement).token
		if token and is_instance_valid(drag_and_drop):
			drag_and_drop.add_child(token)
			_level_play_controller._token_spawner._track_token(token, placement)
			_level_play_controller._connect_token_context_menu(token)
			# Staggered pop-in animation — sequential cascade instead of random
			token.play_spawn_animation(spawned_count * 0.05)
			token_spawned.emit(token, placement)

		spawned_count += 1

		# Yield every batch of tokens to keep UI responsive
		# With cached models, we can spawn more per frame
		if spawned_count % (TOKENS_PER_FRAME * 2) == 0:
			var progress = 0.6 + (0.4 * spawned_count / max(total_tokens, 1))
			level_loading_progress.emit(
				progress, "Spawning tokens... (%d/%d)" % [spawned_count, total_tokens]
			)
			await _level_play_controller.get_tree().process_frame

	level_loading_progress.emit(1.0, "Complete")

	# Yield a couple frames to let all tokens render before hiding loading screen
	for i in range(2):
		await _level_play_controller.get_tree().process_frame

	# Final check before flipping shared state / notifying listeners
	if _should_abort_load(generation):
		return

	_is_loading = false
	level_loading_completed.emit()
	level_loaded.emit(level_data)

	# Start reconciliation timer for networked games
	_level_play_controller._network_token_sync.start_reconciliation_timer()

	# Check if another level was queued during loading
	_process_queued_level()


## Load the map from level data (async: file reads, GLB parsing and the document read run
## on worker threads, and the authored scatter is built over several frames).
##
## A level has a map.glb (map_path), an authored map.ttmap (map_document), or both. Each
## named file is taken from the level folder, else (a client) from the download cache when
## its content hash matches the host's, else a client downloads what is missing and
## MapDownloadCoordinator finishes the load once every file has arrived. A host missing
## its GLB fails; a host missing only its document loads the GLB and says so.
func _load_level_map_async(level_data: LevelData) -> bool:
	# Remove previous level map if exists
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null
	_level_play_controller.loaded_map_document = null

	# Clear any existing map children from the game map
	_clear_existing_maps()

	if not level_data.has_map():
		push_error("LevelPlayLoader: No map path in level data")
		return false

	var sources := _resolve_map_sources(level_data)
	if sources["error"] != "":
		push_error("LevelPlayLoader: " + sources["error"])
		return false

	var missing: Array = sources["missing"]
	if not missing.is_empty():
		if NetworkManager.is_client():
			# Request the missing files from the host; the coordinator loads the map
			# once all of them are cached.
			return _level_play_controller._map_download_coordinator.request_map_download(
				level_data.level_folder, missing, sources["found"]
			)
		if Paths.LEVEL_MAP_VARIANT in missing:
			push_error("LevelPlayLoader: Map file not found: " + level_data.get_absolute_map_path())
			return false
		# Only the document is missing and there is a GLB: play the GLB without it.
		_report_document_problem(
			"Map document not found: " + level_data.get_absolute_map_document_path()
		)

	var found: Dictionary = sources["found"]
	var map := await load_map_sources_async(
		found.get(Paths.LEVEL_MAP_VARIANT, ""), found.get(Paths.LEVEL_MAP_DOCUMENT_VARIANT, "")
	)
	if not map:
		push_error("LevelPlayLoader: Failed to load map")
		return false

	_finalize_map_loading(map)
	return true


## Where each map file of `level_data` can be loaded from: {"found": {variant id -> path},
## "missing": [variant ids with no usable copy here], "error": String}. A client ignores a
## local or cached copy whose hash differs from the one the host sent (a stale copy).
func _resolve_map_sources(level_data: LevelData) -> Dictionary:
	var found := {}
	var missing: Array = []
	if level_data.map_path != "":
		var map_path := level_data.get_absolute_map_path()
		if map_path == "":
			return {"found": found, "missing": missing, "error": "Cannot resolve map path"}
		if map_path.begins_with("res://"):
			found[Paths.LEVEL_MAP_VARIANT] = map_path
		else:
			_resolve_map_file(level_data, Paths.LEVEL_MAP_VARIANT, map_path, found, missing)
	if level_data.map_document != "":
		var document_path := level_data.get_absolute_map_document_path()
		if document_path == "":
			return {"found": found, "missing": missing, "error": "Cannot resolve map document path"}
		_resolve_map_file(
			level_data, Paths.LEVEL_MAP_DOCUMENT_VARIANT, document_path, found, missing
		)
	return {"found": found, "missing": missing, "error": ""}


func _resolve_map_file(
	level_data: LevelData, variant: String, local_path: String, found: Dictionary, missing: Array
) -> void:
	var expected: String = level_data.map_hashes.get(variant, "")
	if FileAccess.file_exists(local_path):
		# The host's own file, or a client's same-named level; a client trusts that only
		# when it is the host's content.
		if (
			not NetworkManager.is_client()
			or expected == ""
			or MapFileHash.hash_file_cached(local_path) == expected
		):
			found[variant] = local_path
			return
	var cached := _level_play_controller._map_download_coordinator.get_cached_map_file(
		level_data.level_folder, variant, expected
	)
	if cached != "":
		found[variant] = cached
	else:
		missing.append(variant)


## Builds the map root from its files, ready for _finalize_map_loading(): the GLB (with its
## scatter filtered by the document's erase mask), or a bare root with an AuthoredTerrain
## when there is no GLB, plus the document's scatter and props as one AuthoredScatter under
## the root. Either path may be "" but not both. Returns null on failure, or when a newer
## load or a reset superseded this one while it was waiting (anything built is freed).
##
## The document is read, validated and split into 10 m cells on a worker thread; species
## load on background threads and resolve a few per frame; cells are built within a
## per-frame time budget. The shared seam of the direct load and the client download path.
func load_map_sources_async(glb_path: String, document_path: String) -> Node3D:
	var generation := _load_generation
	var tree := _level_play_controller.get_tree()
	var document: MapDocument = null
	var rows_by_cell := {}
	if document_path != "":
		var work := {}
		var task := WorkerThreadPool.add_task(
			func() -> void: _read_document_work(document_path, work),
			false,
			"LevelPlayLoader map document"
		)
		while not WorkerThreadPool.is_task_completed(task):
			await tree.process_frame
		WorkerThreadPool.wait_for_task_completion(task)
		if _superseded(generation):
			return null
		for warning in work.get("warnings", PackedStringArray()):
			push_warning("LevelPlayLoader: map document: " + warning)
		document = work.get("document")
		rows_by_cell = work.get("rows_by_cell", {})
		if document == null:
			if glb_path == "":
				push_error("LevelPlayLoader: Map document could not be read: " + document_path)
				return null
			_report_document_problem("Map document could not be read: " + document_path)

	var root: Node3D = null
	if glb_path != "":
		var result = await GlbUtils.load_map_async(
			glb_path,
			true,
			_get_light_intensity_scale(),
			_get_foliage_overrides(),
			document.erase_filter() if document else Callable()
		)
		if _superseded(generation):
			if result.success:
				result.scene.free()
			return null
		if not result.success:
			return null
		root = result.scene
	else:
		root = await _create_authored_root_async(document, generation)
		if root == null:
			return null

	if not rows_by_cell.is_empty():
		var scatter := AuthoredScatter.create(PaletteLibrary.DEFAULT_ROOT, _get_foliage_overrides())
		root.add_child(scatter)
		if not await _build_authored_scatter_async(scatter, rows_by_cell, generation):
			scatter.release_prepared()
			root.free()
			return null
	_level_play_controller.loaded_map_document = document
	return root


## The root of a map that has no GLB: a bare Node3D (named LevelMap by
## _finalize_map_loading) holding the document's AuthoredTerrain, and carrying the
## authored-map lighting as scene extras so it enters the same map-defaults layer a GLB's
## extras do (see AUTHORED_MAP_LIGHTING).
static func create_authored_root(document: MapDocument) -> Node3D:
	var root := _authored_root_shell()
	root.add_child(AuthoredTerrain.create(document))
	return root


static func _authored_root_shell() -> Node3D:
	var root := Node3D.new()
	root.name = "LevelMap"
	root.set_meta(GlbUtils.SCENE_EXTRAS_META, AUTHORED_MAP_LIGHTING.duplicate(true))
	return root


## create_authored_root() spread over frames: the ground textures load on background
## threads first (about 35 ms per surface cold on the main thread), then the material,
## biome weights and collision are built in one frame (about 25 ms) and the chunk meshes
## within the per-frame budget. Returns null when superseded.
func _create_authored_root_async(document: MapDocument, generation: int) -> Node3D:
	var tree := _level_play_controller.get_tree()
	var pending: Array[String] = []
	for path in AuthoredTerrain.texture_paths(document):
		if not ResourceLoader.has_cached(path) and ResourceLoader.load_threaded_request(path) == OK:
			pending.append(path)
	var loading := true
	while loading:
		loading = false
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
	if _superseded(generation):
		return null
	var root := _authored_root_shell()
	var terrain := AuthoredTerrain.create(document, PaletteLibrary.DEFAULT_ROOT, false)
	root.add_child(terrain)
	held.clear()
	var cells := TerrainMeshBuilder.chunk_cells(document)
	var next := 0
	while next < cells.size():
		await tree.process_frame
		if _superseded(generation):
			root.free()
			return null
		var start := Time.get_ticks_usec()
		var batch: Array[Vector2i] = []
		while next < cells.size() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
			batch.assign([cells[next]])
			terrain.rebuild_chunks(batch)
			next += 1
	return root


## Worker-thread half of load_map_sources_async(): reads and validates the document, then
## merges its scatter and props rows (props are hand-placed rows of the same assets; the
## document keeps them apart for saving) and splits them into 10 m cells. Touches no Node
## and no shared state; results go into `out`.
static func _read_document_work(path: String, out: Dictionary) -> void:
	var read := MapDocumentIO.read(path)
	out["warnings"] = read["warnings"]
	var document: MapDocument = read["document"]
	out["document"] = document
	if document == null:
		return
	var rows := {}
	for source in [document.scatter, document.props]:
		for asset_id in source:
			var flat: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array())
			flat.append_array(source[asset_id])
			rows[asset_id] = flat
	out["rows_by_cell"] = AuthoredScatter.rows_by_cell_of(rows)


## Preloads the species `rows_by_cell` uses off the main thread, then builds its cells a
## few per frame. Returns false when superseded mid-way.
func _build_authored_scatter_async(
	scatter: AuthoredScatter, rows_by_cell: Dictionary, generation: int
) -> bool:
	var tree := _level_play_controller.get_tree()
	var assets := {}
	for cell_rows in rows_by_cell.values():
		for asset_id in cell_rows:
			assets[asset_id] = true
	scatter.prepare_assets(assets.keys())
	while scatter.has_prepared_species():
		scatter.resolve_prepared(FRAME_BUDGET_USEC)
		await tree.process_frame
		if _superseded(generation):
			return false
	scatter.begin_build()
	var cells := rows_by_cell.keys()
	var next := 0
	while next < cells.size():
		var start := Time.get_ticks_usec()
		while next < cells.size() and Time.get_ticks_usec() - start < FRAME_BUDGET_USEC:
			scatter.build_cells({cells[next]: rows_by_cell[cells[next]]})
			next += 1
		await tree.process_frame
		if _superseded(generation):
			return false
	scatter.end_build()
	return true


## True when a newer load (or a reset) replaced the one that captured `generation`, or the
## controller left the tree; the caller drops whatever it built. A freed GameMap is caught
## by _finalize_map_loading, which discards the map.
func _superseded(generation: int) -> bool:
	return generation != _load_generation or not _level_play_controller.is_inside_tree()


## A document problem that does not stop the map from loading (there is a GLB to play):
## logged, and shown to the player once.
func _report_document_problem(message: String) -> void:
	push_warning("LevelPlayLoader: %s; loading the Blender map without it" % message)
	UIManager.show_toast(
		"The authored map layer could not be loaded, so the map shows without it.",
		UIManager.TOAST_WARNING,
		6.0
	)


## Finalize map loading after the map instance is ready
func _finalize_map_loading(map: Node3D) -> void:
	# Check if game map is still valid (might have been freed during async loading)
	if not is_instance_valid(_level_play_controller._game_map):
		push_warning("LevelPlayLoader: GameMap was freed during async loading, discarding map")
		map.queue_free()
		return

	_level_play_controller.loaded_map_instance = map
	_level_play_controller.loaded_map_instance.name = "LevelMap"

	# Safety check: warn if transform chain is broken (non-Node3D intermediate parents)
	GlbUtils.validate_transform_chain(_level_play_controller.loaded_map_instance)

	# Extract environment settings from any embedded WorldEnvironment nodes
	# before adding the map to the viewport.
	_level_play_controller._environment_manager.extract_and_strip_map_environment(
		_level_play_controller.loaded_map_instance
	)

	# Add to the dedicated MapContainer
	_level_play_controller._game_map.map_container.add_child(
		_level_play_controller.loaded_map_instance
	)

	if _level_play_controller.active_level_data:
		_level_play_controller.loaded_map_instance.scale = (
			_level_play_controller.active_level_data.map_scale
		)
		_level_play_controller.loaded_map_instance.position = (
			_level_play_controller.active_level_data.map_offset
		)

	# Store original light energies for real-time intensity editing
	_level_play_controller._environment_manager.store_original_light_energies(
		_level_play_controller.loaded_map_instance
	)

	# Cache wind-sway materials for real-time foliage tuning
	_level_play_controller._environment_manager.store_wind_materials(
		_level_play_controller.loaded_map_instance
	)

	# Apply environment settings from level data (map defaults used as a layer)
	if _level_play_controller.active_level_data:
		_level_play_controller._environment_manager.apply_level_environment(
			_level_play_controller.active_level_data,
			_level_play_controller._game_map.world_viewport
		)
		# Apply the level's water settings. Done here -- the shared seam both
		# the direct-load path (_load_level_map_async) and the client
		# map-download path (MapDownloadCoordinator -> _finalize_map_loading)
		# go through -- rather than only after the direct path's call site, so
		# clients who download a map from the host also get their water settings
		# applied.
		_level_play_controller.apply_water_settings(
			_level_play_controller.active_level_data.water.to_dict()
		)

	# Set up weather renderer (must happen after environment is applied)
	var game_map = _level_play_controller.get_game_map()
	if game_map:
		game_map.setup_weather(_level_play_controller._environment_manager)
		if _level_play_controller.active_level_data:
			# Unconditional: the renderer is freshly created, and an all-zero
			# WeatherSettings is a no-op on it.
			game_map.apply_weather_overrides(
				_level_play_controller.active_level_data.weather.to_dict()
			)

	# Rebuild occlusion fade mesh cache now that map geometry is in the scene tree
	_level_play_controller._game_map.notify_map_loaded()

	# Configure measure tool and grid with scale settings from level data
	_configure_measure_tool()
	_configure_grid()

	_apply_foliage_density_and_notify(map)

	var scatter := map.get_node_or_null(^"AuthoredScatter") as AuthoredScatter
	if scatter and not scatter.species_added.is_connected(_on_species_added):
		scatter.species_added.connect(_on_species_added)


## Applies the player's foliage density setting to a freshly loaded map, and tells them
## once if the map exceeded their budget. FoliageBudget.describe() names the density
## percentage and the setting as the cause; this function's only addition is appending a
## pointer to where the setting lives. Shown as an informational toast, not a warning --
## a user-configured setting behaving exactly as configured isn't a warning, and nothing
## here is a one-time, unrecoverable loss any more: the player can raise the dial back up
## without a reload.
func _apply_foliage_density_and_notify(map: Node3D) -> void:
	if not map:
		return
	var budget := FoliageDensityController.budget_from_settings()
	var report := FoliageDensityController.apply(map, budget)
	if report.thinned:
		UIManager.show_toast(
			"%s Adjust Foliage Density in Settings > Graphics." % FoliageBudget.describe(report),
			UIManager.TOAST_INFO,
			6.0
		)


## Hands wind materials of a species first resolved after load (AuthoredScatter
## .species_added) the same bookkeeping load-time materials got in _finalize_map_loading:
## foliage AA variant and occlusion fade (GameMap), and live wind re-tuning (environment
## manager). Play time builds every species before finalizing, so this only fires if a
## species is added later; it is wired here so authoring and play stay consistent.
func _on_species_added(materials: Array[ShaderMaterial]) -> void:
	var game_map := _level_play_controller.get_game_map()
	if is_instance_valid(game_map):
		game_map.adopt_foliage_materials(materials)
	_level_play_controller._environment_manager.add_wind_materials(materials)


## Get the light intensity scale from the active level data (or 1.0 if none)
func _get_light_intensity_scale() -> float:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.light_intensity_scale
	return 1.0


## Get the foliage sway overrides from the active level data (or {} if none)
func _get_foliage_overrides() -> Dictionary:
	if _level_play_controller.active_level_data:
		return _level_play_controller.active_level_data.foliage.to_dict()
	return {}


## Pass current scale settings from level data to the measure tool.
func _configure_measure_tool() -> void:
	if not _level_play_controller._game_map:
		return
	var tool := _level_play_controller._game_map.get_measure_tool()
	if not tool or not _level_play_controller.active_level_data:
		return
	(
		tool
		. configure(
			_level_play_controller.active_level_data.grid_cell_size,
			_level_play_controller.active_level_data.display_unit,
			_level_play_controller.active_level_data.display_unit_per_cell,
		)
	)


## Configure grid overlay, grid snap, and drag ruler from level data.
func _configure_grid() -> void:
	if not _level_play_controller._game_map or not _level_play_controller.active_level_data:
		return
	_level_play_controller._game_map.configure_grid(_level_play_controller.active_level_data)


## Public: update measure tool and grid configuration (called when GM changes scale in UI).
func update_measure_tool_scale() -> void:
	_configure_measure_tool()
	_configure_grid()


## Deactivate the measure tool if it's active (called on level clear/load).
func _deactivate_measure_tool() -> void:
	if not _level_play_controller._game_map:
		return
	var tool := _level_play_controller._game_map.get_measure_tool()
	if tool and tool.is_active():
		tool.deactivate()


## Check if level loading is in progress (async loading)
func is_loading() -> bool:
	return _is_loading


## Check if the controller is still valid for loading operations
## Returns false if GameMap has been freed or we're no longer in a valid state
func _is_valid_for_loading() -> bool:
	return (
		is_instance_valid(_level_play_controller._game_map)
		and _level_play_controller.is_inside_tree()
	)


## Checkpoint for _play_level_async: returns true if the calling coroutine's
## captured generation no longer matches _load_generation (superseded by a
## newer load or reset_loading_state()) or if the GameMap context is no
## longer valid. Callers must return immediately when this returns true —
## a stale coroutine must never mutate shared state (spawned_tokens,
## active_level_data, _game_map's children, etc.) after this point, since
## that state may already belong to a different load.
func _should_abort_load(generation: int) -> bool:
	if generation != _load_generation:
		# Superseded — another invocation (or reset_loading_state()) now owns
		# _is_loading and shared state. Abort silently without touching them.
		return true
	if not _is_valid_for_loading():
		_abort_loading()
		return true
	return false


## Abort an in-progress async loading operation
func _abort_loading() -> void:
	push_warning("LevelPlayLoader: Aborting async loading (context no longer valid)")
	_is_loading = false
	level_loading_completed.emit()

	# Check if another level was queued during loading
	_process_queued_level()


## Process any level that was queued during loading
func _process_queued_level() -> void:
	if _queued_level_data:
		var queued = _queued_level_data
		_queued_level_data = null
		print("LevelPlayLoader: Loading queued level")
		# Use call_deferred to avoid recursion issues
		call_deferred("play_level", queued)


## Check if there's a level queued to load after current loading completes
func has_queued_level() -> bool:
	return _queued_level_data != null


## Clear any existing map models from the MapContainer
func _clear_existing_maps() -> void:
	var game_map := _level_play_controller._game_map
	if not game_map or not is_instance_valid(game_map.map_container):
		return

	for child in game_map.map_container.get_children():
		child.queue_free()


## Save current token positions to level data
func save_level() -> String:
	if not _level_play_controller.active_level_data:
		push_error("LevelPlayLoader: No active level to save")
		return ""

	# Update map position and scale from the loaded map instance
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.active_level_data.map_scale = (
			_level_play_controller.loaded_map_instance.scale
		)
		_level_play_controller.active_level_data.map_offset = (
			_level_play_controller.loaded_map_instance.position
		)

	# Update each placement with current token position
	var tokens := _level_play_controller._token_spawner.get_spawned_tokens()
	for placement in _level_play_controller.active_level_data.token_placements:
		if tokens.has(placement.placement_id):
			var token = tokens[placement.placement_id] as BoardToken
			if is_instance_valid(token):
				_level_play_controller._token_spawner._sync_placement_from_token(placement, token)
				# Also sync to GameState
				if GameState.has_authority():
					GameState.sync_from_board_token(token)

	# Broadcast updated state to clients
	if NetworkManager.is_host():
		NetworkStateSync.broadcast_full_state()

	# Save the level — use folder format when the level came from a folder
	return LevelManager.save_level_in_place(_level_play_controller.active_level_data)


## Clear the loaded level map
func clear_level_map() -> void:
	# Clear occlusion fade state before freeing map geometry
	if _level_play_controller._game_map:
		_level_play_controller._game_map.notify_map_clearing()

	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.queue_free()
		_level_play_controller.loaded_map_instance = null
	_level_play_controller.loaded_map_document = null

	# Clear weather effects before environment state
	var game_map = _level_play_controller.get_game_map()
	if game_map:
		game_map.clear_weather()

	# Clear environment state (lights, WorldEnvironment, map config)
	_level_play_controller._environment_manager.clear()


## Clear everything from the current level
func clear_level() -> void:
	_deactivate_measure_tool()
	if _level_play_controller._game_map:
		_level_play_controller._game_map.reset_grid_state()

	# Stop reconciliation timer
	_level_play_controller._network_token_sync.stop_reconciliation_timer()

	# Clear network sync throttle state
	NetworkStateSync.clear_throttle_state()
	GameState.clear_all_drag_locks()

	# Clear undo history (stale network_ids would be meaningless)
	if _level_play_controller._game_map:
		var history := _level_play_controller._game_map.get_action_history()
		if history:
			history.clear()

	_level_play_controller.clear_level_tokens()
	clear_level_map()

	# Clear model cache to free memory
	AssetManager.clear_model_cache()

	level_cleared.emit()


## Reset all loading state (call when exiting PLAYING state)
func reset_loading_state() -> void:
	_is_loading = false
	_queued_level_data = null
	_level_play_controller.is_editor_preview = false
	# Invalidate any in-flight _play_level_async coroutine still suspended on
	# an await — its captured generation will no longer match, so it will
	# abort at its next checkpoint instead of mutating state for a level it
	# no longer owns (see _should_abort_load()).
	_load_generation += 1
	_level_play_controller._map_download_coordinator.reset()


## Set map scale in real-time (used by gameplay UI and network sync)
func set_map_scale(uniform_scale: float) -> void:
	if is_instance_valid(_level_play_controller.loaded_map_instance):
		_level_play_controller.loaded_map_instance.scale = Vector3.ONE * uniform_scale
	if _level_play_controller.active_level_data:
		_level_play_controller.active_level_data.map_scale = Vector3.ONE * uniform_scale


## Check if a level is currently loaded
func has_active_level() -> bool:
	# _level_play_controller stays null until LevelPlayController.setup(game_map) runs,
	# which only happens once Root actually enters State.PLAYING -- but
	# app_menu_controller.gd hands this loader's owning LevelPlayController to the App
	# Menu at startup (Root._setup_app_menu(), before any state transition), and the
	# Level Editor button is reachable from the title screen specifically so a map can
	# be tested before hosting/joining a game. Calling has_active_level() from there
	# used to crash with "Invalid access ... on a base object of type 'Nil'" instead of
	# just correctly reporting "no active level" -- which is exactly what's true at
	# that point.
	return _level_play_controller != null and _level_play_controller.active_level_data != null
