class_name AuthoringController
extends Node

## Authoring mode (Root.State.AUTHORING): the GM builds or dresses a map in the same GameMap
## players see, so every stroke is judged under the real camera, lighting, sky and weather.
## Offline only; Root refuses entry while hosting or joined.
##
## Owns what LevelPlayController owns in play, minus everything about tokens and peers: its
## own LevelEnvironmentManager, the GameMap setup it needs (authoring mode, measure tool,
## grid overlay; weather comes with MapSourceLoader.install), and the map, loaded through the
## same MapSourceLoader the play-time load uses (with props kept in their own node, since
## the tools edit scatter and props apart). The MapDocument is the source of truth for
## everything authored: masks and heights are edited in it in place, and the scatter and
## props rows are copied back from their AuthoredScatter nodes whenever the document is
## written (_sync_document).
##
## Three ways in (Root builds the request): a new map (NewMapDialog's spec, NewMap), a level
## with a map.ttmap, and a level with only a map.glb, which opens as a dressing layer: the
## GLB is the base and an empty document covering it is made in memory, written on the
## first save. A leftover autosave is offered first (AuthoringAutosave). Every dressed map
## (has_base_map) has its document heights sampled from the GLB's collision as it opens
## (_fit_dressing_to_ground), so painted plants stand on the GLB ground and the grid overlay
## draws on it.
##
## Saving writes map.ttmap atomically (MapDocumentIO), then level.json with map_document
## set (LevelManager), then a thumbnail of the current view. Unsaved edits are counted by
## AuthoringSession and autosaved every AUTOSAVE_INTERVAL seconds.
##
## Brushes (phase 2 T6). GameMap's BrushTool does the gestures and the cursor, and an
## AuthoringEditor made per opened map does the edits (masks, ground, scatter, props,
## history). The controller connects the two to the panel: a rail item picks the tool, a
## biome or Place tile picks what it paints or places (and warms it), the Advanced rows set
## size and strength, and the brush reports its state back (active tool tint, size).

signal loading_started
signal loading_progress(progress: float, status: String)
signal loading_completed
## The author left authoring. `level` is the level the session worked on (saved when its
## level_folder is set), or null when the session never had one.
signal exit_requested(level: LevelData)

const AUTOSAVE_INTERVAL := 30.0
const MIN_ZOOM := 2.0
## The play camera's zoom-out limit (CameraController.max_zoom); authoring never goes below.
const PLAY_MAX_ZOOM := 20.0
## Room around a whole map at the widest zoom.
const ZOOM_FIT_MARGIN := 1.08
## Height the zoom-out fit leaves room for above the ground: the tallest palette trees.
const CONTENT_HEIGHT_M := 12.0
## Longest the loading screen waits for the first palette species (see _await_palette_warm).
const PALETTE_WARM_TIMEOUT_MS := 2000
## Frames drawn after the first species resolves before the loading screen goes, so its
## pipeline warm-up node (PipelineWarmer) is drawn under it too.
const PALETTE_WARM_FRAMES := 3

var level: LevelData = null
var document: MapDocument = null
var session: AuthoringSession = AuthoringSession.new()
var history: AuthoringHistory = AuthoringHistory.new()
var map_root: Node3D = null
var scatter: AuthoredScatter = null
var props: AuthoredScatter = null
var panel: AuthoringPanel = null
## The biome the author last picked (the Biome tool's paint), or "".
var selected_biome: String = ""
var brush: BrushTool = null
var editor: AuthoringEditor = null
## The last dressing ground fit (_fit_dressing_to_ground), for measurement: {"samples",
## "ray_ms", "missed", "settled_rows", "wall_ms"}; {} for a map that is not a dressing.
var ground_fit: Dictionary = {}

var _game_map: GameMap = null
var _environment := LevelEnvironmentManager.new()
var _ui_layer: CanvasLayer = null
## The document's extent in world space (plus canopy height), for the shadow distance.
var _map_bounds: AABB = AABB()
## The ground range _fit_camera() last used, and whether an edit may have changed it.
var _fitted_ground: Vector2 = Vector2.ZERO
var _bounds_stale: bool = false
var _autosave_timer: Timer = null
## Bumped by every open and by teardown, so a load still awaiting drops its result.
var _generation: int = 0
var _is_open: bool = false
var _saving: bool = false
var _leave_prompt: Node = null
var _recovery_prompt: Node = null
## True once the open map's crossing textures were warmed (_warm_crossings).
var _crossings_warmed: bool = false


func _ready() -> void:
	set_process(false)


## Wires the controller to a fresh GameMap (already in the tree) and builds the tool drawer.
func setup(game_map: GameMap) -> void:
	_game_map = game_map
	_environment.setup(game_map)
	game_map.setup_authoring()
	game_map.setup_measure_tool()
	game_map.setup_grid_overlay()
	brush = game_map.setup_brush_tool()
	_build_ui()
	brush.toggled.connect(_on_brush_toggled)
	brush.paint_refused.connect(_on_paint_refused)
	brush.water_refused.connect(
		func(reason: String) -> void: UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)
	)
	brush.bridge_refused.connect(
		func(reason: String) -> void: UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)
	)
	brush.paint_surface = panel.get_paint_surface()
	brush.radius_changed.connect(func(_radius: float) -> void: _show_brush_values())
	_show_brush_values()
	_autosave_timer = Timer.new()
	_autosave_timer.name = "AutosaveTimer"
	_autosave_timer.wait_time = AUTOSAVE_INTERVAL
	_autosave_timer.timeout.connect(_on_autosave_timeout)
	add_child(_autosave_timer)
	history.changed.connect(_on_history_changed)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "AuthoringUI"
	_ui_layer.layer = Constants.LAYER_AUTHORING
	add_child(_ui_layer)
	panel = AuthoringPanel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(panel)
	panel.save_pressed.connect(save_async)
	panel.leave_pressed.connect(request_leave)
	panel.undo_pressed.connect(undo)
	panel.redo_pressed.connect(redo)
	panel.name_changed.connect(_on_name_changed)
	panel.biome_selected.connect(_on_biome_selected)
	panel.tool_selected.connect(_on_tool_selected)
	panel.place_selected.connect(_on_place_selected)
	panel.sculpt_selected.connect(_on_sculpt_selected)
	panel.paint_selected.connect(_on_paint_selected)
	panel.water_shape_selected.connect(_on_water_shape_selected)
	panel.water_depth_selected.connect(_on_water_depth_selected)
	panel.water_speed_changed.connect(func(speed: float) -> void: brush.water.speed = speed)
	panel.bridge_kind_selected.connect(_on_bridge_kind_selected)
	panel.brush_size_changed.connect(func(radius: float) -> void: brush.set_radius(radius))
	panel.brush_strength_changed.connect(func(flow: float) -> void: brush.set_flow(flow))


## Opens what `request` names ({"level": LevelData or null, "new_map": NewMapDialog spec or
## absent}), after offering a leftover autosave if there is one.
func start(request: Dictionary) -> void:
	if AuthoringAutosave.exists():
		_offer_recovery(request)
	else:
		_open_request(request)


func _open_request(request: Dictionary) -> void:
	var spec: Dictionary = request.get("new_map", {})
	var requested: LevelData = request.get("level")
	if requested == null:
		requested = new_level()
	if not spec.is_empty():
		_open_async(requested, spec, "")
	elif requested.map_document != "":
		_open_async(requested, {}, requested.get_absolute_map_document_path())
	else:
		_open_async(requested, {}, "")


## The level a new map made from the title starts as: named NewMap.DEFAULT_NAME, with the
## default look for authored maps.
static func new_level() -> LevelData:
	var created := LevelData.new()
	created.level_name = NewMap.DEFAULT_NAME
	return created


func _offer_recovery(request: Dictionary) -> void:
	var saved := AuthoringAutosave.read_level()
	if saved == null:
		AuthoringAutosave.discard()
		_open_request(request)
		return
	_recovery_prompt = UIManager.show_confirmation(
		"Recover an unsaved map?",
		(
			'Map building closed before "%s" was saved. Recover it, or discard it and go on?'
			% saved.level_name
		),
		"Recover",
		"Discard",
		func() -> void: _open_async(saved, {}, AuthoringAutosave.document_path(), true),
		func() -> void:
			AuthoringAutosave.discard()
			_open_request(request)
	)


## Loads and shows a map. `spec` non-empty: a new map from NewMap; else `document_path`
## names the document to read ("" for a GLB-only level, which gets an empty dressing
## document). `recovered`: the document is an autosave, so the session starts unsaved.
func _open_async(
	opened: LevelData, spec: Dictionary, document_path: String, recovered: bool = false
) -> void:
	_generation += 1
	var generation := _generation
	_is_open = false
	ground_fit = {}
	level = opened
	_game_map.map_loading = true
	loading_started.emit()
	loading_progress.emit(0.1, "Building the map...")
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	loader.light_intensity_scale = opened.light_intensity_scale
	loader.foliage_overrides = opened.foliage.to_dict()
	loader.is_superseded = func() -> bool: return _superseded(generation)
	var glb := opened.get_absolute_map_path() if opened.map_path != "" else ""
	var root: Node3D = null
	if not spec.is_empty():
		var created := NewMap.create(
			int(spec.get("size_ft", NewMap.DEFAULT_SIZE_FT)),
			String(spec.get("biome_id", NewMap.BARE_BIOME)),
			int(spec.get("seed", NewMap.random_seed()))
		)
		root = await loader.build_async("", created)
	elif document_path != "":
		root = await loader.load_async(glb, document_path)
	elif glb != "":
		root = await loader.build_async(glb, null)
	if _superseded(generation):
		if root:
			root.free()
		return
	if root == null:
		_fail_open()
		return
	loading_progress.emit(0.8, "Placing the map...")
	_install(root, loader.document)
	var settled_rows := 0
	if document.has_base_map:
		loading_progress.emit(0.85, "Fitting to the ground...")
		settled_rows = await _fit_dressing_to_ground(generation)
		if _superseded(generation):
			return
	loading_progress.emit(0.9, "Preparing the palette...")
	for biome in PaletteLibrary.biomes(scatter.palette_root):
		scatter.prepare_biome(String(biome.get("id", "")))
	# The Paint swatches decode each surface's albedo once; better here than on first click.
	panel.ensure_paint_tiles()
	await _await_palette_warm(generation)
	if _superseded(generation):
		return
	# Rows settled onto the ground are an edit the author saves (see _fit_dressing_to_ground).
	var unsaved := not spec.is_empty() or recovered or settled_rows > 0
	session = AuthoringSession.unsaved() if unsaved else AuthoringSession.new()
	session.dirty_changed.connect(_on_dirty_changed)
	history.clear()
	if not spec.is_empty() and not document.biome_ids.is_empty():
		# The starting cover grows in across the map on worker threads.
		scatter.request_region(Rect2(-document.extent_m() * 0.5, document.extent_m()))
	_game_map.map_loading = false
	loading_progress.emit(1.0, "Ready")
	loading_completed.emit()
	panel.set_map_name(level.level_name)
	panel.set_dirty(session.is_dirty())
	panel.set_history_state(false, false)
	if not document.biome_ids.is_empty():
		panel.select_biome(document.biome_ids[0])
		_use_biome(document.biome_ids[0])
	panel.begin_session()
	_is_open = true
	_autosave_timer.start()
	set_process(true)
	if settled_rows > 0:
		UIManager.show_toast(
			"Plants painted before were set down onto the ground. Save to keep the fix.",
			UIManager.TOAST_INFO,
			6.0
		)


func _superseded(generation: int) -> bool:
	return generation != _generation or not is_inside_tree()


## Holds the loading screen until the first palette species has resolved and been drawn,
## at most PALETTE_WARM_TIMEOUT_MS. Authoring prepares every palette biome as a map opens:
## the first palette mesh load compiles the GPU pipelines all palette species share (30 on
## the built-in palette, a one-time 100-115 ms stall that otherwise landed on the first
## stroke), and every biome's first dab then finds its species resolved. The rest of the
## palette (180 built-in species, about 4 s) resolves in the background, one species per
## frame (docs/PERFORMANCE.md "First-use pipeline compilation in authoring").
func _await_palette_warm(generation: int) -> void:
	var deadline := Time.get_ticks_msec() + PALETTE_WARM_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and not _superseded(generation):
		if not scatter.has_prepared_species() or scatter.resolved_species_count() > 0:
			break
		await get_tree().process_frame
	for _frame in PALETTE_WARM_FRAMES:
		if _superseded(generation):
			return
		await get_tree().process_frame


func _install(root: Node3D, loaded: MapDocument) -> void:
	map_root = root
	MapSourceLoader.install(root, _game_map, _environment, level)
	document = loaded
	if document == null:
		# A Blender map with nothing authored over it yet: dress it with an empty document
		# that reaches its farthest geometry. Written on the first save.
		var world := LevelEnvironmentManager.compute_map_bounds(root)
		document = NewMap.create_dressing(
			root.global_transform.affine_inverse() * world, NewMap.random_seed()
		)
	scatter = root.get_node_or_null(NodePath(MapSourceLoader.SCATTER_NODE)) as AuthoredScatter
	props = root.get_node_or_null(NodePath(MapSourceLoader.PROPS_NODE)) as AuthoredScatter
	scatter.attach_document(document)
	FoliageDensityController.apply(root, FoliageDensityController.budget_from_settings())
	_fit_camera()
	editor = AuthoringEditor.create(document, root, history)
	editor.edited.connect(mark_edited)
	editor.edited.connect(func() -> void: _bounds_stale = true)
	editor.edited.connect(_refresh_paint_limits)
	brush.deactivate()
	brush.editor = editor
	brush.unit_cell_m = level.grid_cell_size
	brush.unit_per_cell = level.display_unit_per_cell
	brush.unit_label = level.display_unit
	# Sculpting and painting edit the document's own ground; a dressed Blender map's is the
	# GLB's.
	panel.set_sculpt_available(editor.can_sculpt())
	panel.set_paint_available(editor.can_paint())
	# The Water tool's carve computes on a worker (WaterEditor), so a stroke never freezes.
	editor.water.use_worker = true
	editor.edited.connect(_refresh_water_available)
	# A crossing removed with its water is said (it vanished away from the pointer).
	editor.crossings.followed.connect(
		func(_moved: int, removed: int) -> void:
			if removed > 0:
				UIManager.show_toast(BridgeBrush.followed_text(removed), UIManager.TOAST_INFO, 5.0)
	)
	_crossings_warmed = false
	_refresh_water_available()
	_refresh_paint_limits()
	if editor.can_sculpt() and is_instance_valid(editor.terrain):
		# Builds the skirt's CPU vertex copy (45 ms on a 200 ft map) here, under the loading
		# screen, instead of in the first stroke frame that reaches the map edge
		# (docs/PERFORMANCE.md "In-game authoring phase 3: pinned performance pass").
		editor.terrain.refresh_skirt()


## Samples a dressed GLB's ground into the document's heights (DressingGround), a slice per
## frame under the loading screen, so the Biome brush generates plants on the GLB ground
## instead of at Y = 0. Waits one physics frame first so the map's collision is in the
## physics space. A document saved before this existed has its generated rows at Y = 0;
## they are set down onto the ground here (DressingGround.settle) and the session starts
## unsaved so the author saves the fix. It is not an undoable history entry: undoing it
## would only put the plants back in the air. Returns how many rows moved (0 when the
## document already matched its ground, which a save after this fix guarantees unless the
## GLB was re-exported).
func _fit_dressing_to_ground(generation: int) -> int:
	var started := Time.get_ticks_usec()
	await get_tree().physics_frame
	if _superseded(generation):
		return 0
	var top := (
		LevelEnvironmentManager.compute_map_bounds(map_root).end.y
		+ DragPlaceController.TERRAIN_DOWNCAST_HEIGHT
	)
	var sampler := DressingGround.begin(
		document,
		map_root.get_world_3d(),
		map_root.global_transform,
		top,
		AuthoredCrossings.exclude_of(map_root)
	)
	while not sampler.step(MapSourceLoader.FRAME_BUDGET_USEC):
		await get_tree().process_frame
		if _superseded(generation):
			return 0
	var moved := DressingGround.settle(
		document, sampler.heights, scatter, DressingGround.aligned_assets(document.biome_ids)
	)
	# The grid overlay draws on the same sampled ground (a play-time load samples its own,
	# MapSourceLoader.fit_grid_ground_async), or, where the map has water, on the surface:
	# sampled again with the water surfaces, since the plants need the bed.
	var grid := sampler
	if WaterGlbUtils.has_water(map_root):
		grid = DressingGround.begin_grid(
			map_root.get_world_3d(),
			map_root.global_transform,
			top,
			-document.extent_m() * 0.5,
			document.sample_step(),
			document.samples_x(),
			document.samples_z(),
			WaterSurface.WALKABLE_MASK
		)
		while not grid.step(MapSourceLoader.FRAME_BUDGET_USEC):
			await get_tree().process_frame
			if _superseded(generation):
				return moved
	_game_map.set_grid_ground(
		GroundHeightField.for_glb(
			map_root,
			grid.heights,
			grid.hits,
			document.samples_x(),
			document.samples_z(),
			-document.extent_m() * 0.5,
			document.sample_step(),
			grid.water
		)
	)
	ground_fit = {
		"samples": sampler.heights.size(),
		"ray_ms": sampler.usec / 1000.0,
		"missed": sampler.miss_count(),
		"settled_rows": moved,
		"wall_ms": (Time.get_ticks_usec() - started) / 1000.0,
	}
	return moved


## Zoom-out reaches a view of the whole map (never less than the play camera's), and panning
## is bounded by the map's extent even where nothing has been painted yet. Heights follow the
## terrain's real range (sculpted ground can rise above or sink below Y = 0; a dressed GLB
## map keeps 0): the zoom fit, the pan bounds and the shadow bounds all span the lowest
## ground to the highest plus CONTENT_HEIGHT_M of canopy.
func _fit_camera() -> void:
	var extent := document.extent_m()
	var scaled := extent * Vector2(map_root.scale.x, map_root.scale.z)
	var ground := _ground_range()
	_fitted_ground = ground
	var fit := (
		_game_map.fit_zoom_for_extent(scaled, ground.y + CONTENT_HEIGHT_M, ground.x)
		* ZOOM_FIT_MARGIN
	)
	_game_map.set_zoom_limits(MIN_ZOOM, maxf(PLAY_MAX_ZOOM, fit))
	var local := AABB(Vector3(-extent.x, 0.0, -extent.y) * 0.5, Vector3(extent.x, 0.0, extent.y))
	_map_bounds = map_root.global_transform * local
	_map_bounds.position.y = ground.x
	_map_bounds.size.y = ground.y - ground.x
	if not document.has_base_map:
		_game_map.set_map_bounds(_map_bounds)
	# Shadows reach the map's far side, with room for the canopy.
	_map_bounds = _map_bounds.expand(
		Vector3(_map_bounds.position.x, ground.y + CONTENT_HEIGHT_M, _map_bounds.position.z)
	)


## The authored terrain of the open map, or null (a dressed GLB map has none).
func _terrain() -> AuthoredTerrain:
	if not is_instance_valid(map_root):
		return null
	return map_root.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain


## The ground's world height range (lowest, highest): the terrain's, or 0..0 without one.
func _ground_range() -> Vector2:
	var terrain := _terrain()
	return terrain.world_height_range() if terrain else Vector2.ZERO


## After a sculpt stroke, undo or redo has settled (its chunks rebuilt, so their AABBs are
## exact again): refits the camera and shadow bounds and resizes the reflection probe to
## the new ground, when its range changed.
func _refresh_bounds_after_edit() -> void:
	var terrain := _terrain()
	if terrain == null:
		_bounds_stale = false
		return
	if (editor and editor.has_height_work()) or terrain.has_unsettled_chunks():
		return
	_bounds_stale = false
	if terrain.world_height_range().is_equal_approx(_fitted_ground):
		return
	_fit_camera()
	_environment.apply_reflection_probe(_game_map.world_viewport)


func _fail_open() -> void:
	_game_map.map_loading = false
	loading_completed.emit()
	UIManager.show_error("This map could not be opened for building.")
	exit_requested.emit(level)


func _process(_delta: float) -> void:
	if not _is_open or not is_instance_valid(_game_map):
		return
	if editor:
		# Sculpt work a stroke's frames left over drains even with the brush put away.
		editor.step_height_work()
	var ground := _ground_range()
	# The near plane follows raised ground at once (the range only widens mid-stroke).
	_game_map.set_ground_top(ground.y)
	_environment.fit_shadow_distance_to_view(
		_game_map.camera_node, Vector2(_game_map.world_viewport.size), _map_bounds, ground.x
	)
	if _bounds_stale:
		_refresh_bounds_after_edit()


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_undo"):
		undo()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_redo"):
		redo()
		get_viewport().set_input_as_handled()


# ============================================================================
# Editing seams
# ============================================================================


## Records one edit of the map (every stroke, rename, undo and redo).
func mark_edited() -> void:
	session.mark_edited()


func undo() -> void:
	_finish_brush_gesture()
	if history.undo() != "":
		mark_edited()
		_bounds_stale = true
		_refresh_paint_limits()
		_refresh_water_available()


func redo() -> void:
	_finish_brush_gesture()
	if history.redo() != "":
		mark_edited()
		_bounds_stale = true
		_refresh_paint_limits()
		_refresh_water_available()


## A stroke or prop gesture in progress becomes its own history entry before undo or redo
## moves through the stack.
func _finish_brush_gesture() -> void:
	if brush:
		brush.finish_gesture()
	elif editor:
		editor.commit_prop_edit()
	if editor:
		# A water edit still computing lands first, so undo takes it back (not the one before).
		editor.water.finish_work()


func _on_history_changed() -> void:
	if panel:
		panel.set_history_state(history.can_undo(), history.can_redo())


func _on_dirty_changed(dirty: bool) -> void:
	panel.set_dirty(dirty)


func _on_name_changed(_new_name: String) -> void:
	if _is_open and panel.get_map_name() != level.level_name:
		mark_edited()


## A picked biome becomes the Biome brush's paint and switches to that brush.
func _on_biome_selected(biome_id: String) -> void:
	_use_biome(biome_id)
	_select_tool(AuthoringPanel.TOOL_BIOME)


## Makes `biome_id` the Biome brush's paint and starts loading its assets and ground surface
## on background threads, so the first stroke with it does not wait on loads.
func _use_biome(biome_id: String) -> void:
	selected_biome = biome_id
	if editor:
		editor.prepare_biome(biome_id)
	elif is_instance_valid(scatter):
		scatter.prepare_biome(biome_id)
	if brush:
		brush.biome_id = biome_id
		brush.biome_tint = biome_tint(biome_id)
	# Silent; also opens the biome's group in the Place picker.
	panel.select_biome(biome_id)


func _on_tool_selected(tool_id: StringName) -> void:
	_select_tool(tool_id)


func _on_place_selected(biome_id: String, species_key: String) -> void:
	if editor == null:
		return
	brush.place_rule = editor.species_rule(biome_id, species_key)
	for asset_id in brush.place_rule.get("assets", []):
		if is_instance_valid(props):
			props.prepare_assets([asset_id])
	_select_tool(AuthoringPanel.TOOL_PLACE)


## A picked Sculpt tile becomes the Sculpt brush's operation and switches to that brush.
func _on_sculpt_selected(tile: int) -> void:
	if brush:
		brush.sculpt_tile = tile
	_select_tool(AuthoringPanel.TOOL_SCULPT)


## A picked Paint tile becomes the Paint brush's surface (its textures start loading so the
## first dab binds them from the cache) and switches to that brush. A surface that cannot
## take a slot says why at once rather than on the first press.
func _on_paint_selected(surface: String) -> void:
	_use_surface(surface)
	if editor != null:
		var reason := editor.surface_refusal(surface)
		if reason != "":
			UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)
	_select_tool(AuthoringPanel.TOOL_PAINT)


func _use_surface(surface: String) -> void:
	if brush == null:
		return
	brush.paint_surface = surface
	brush.paint_tint = surface_tint(surface)
	var terrain := _terrain()
	if terrain:
		terrain.warm_surface(surface)
	panel.select_paint_surface(surface)


## A picked Water tile (River or Pond) becomes the Water brush's shape and switches to it.
func _on_water_shape_selected(shape: int) -> void:
	if brush:
		brush.water.shape = shape
	_select_tool(AuthoringPanel.TOOL_WATER)


## A picked depth tile becomes the depth the Water brush's next stroke makes.
func _on_water_depth_selected(depth: int) -> void:
	if brush:
		brush.water.depth = depth
		_show_brush_values()
	_select_tool(AuthoringPanel.TOOL_WATER)


## Shows the brush's size and strength in the Advanced rows, and the Water tool's width (its
## radius clamped to the depth's narrowest channel, as a full width) and flow.
func _show_brush_values() -> void:
	panel.set_brush_values(brush.get_radius(), brush.get_flow())
	panel.set_water_values(2.0 * brush.water_radius(), brush.water.speed)


## The Water tool on the rail: carving where the ground is the document's, erasing only on
## a dressed Blender map that has water painted over it (AuthoringPanel.set_water_available).
## The Bridge tool with it: wherever water can be made or the document has some.
func _refresh_water_available() -> void:
	if editor == null or panel == null:
		return
	var has_water := not document.water_bodies.is_empty()
	panel.set_water_available(editor.water.can_carve(), has_water)
	panel.set_bridge_available(bridge_available(), has_water)


## True when the Bridge tool can work: crossings snap to the document's water, which the
## map can be given (its ground is the document's) or already has.
func bridge_available() -> bool:
	return editor != null and (editor.water.can_carve() or not document.water_bodies.is_empty())


## A picked Bridge tile becomes the kind the Bridge tool lays and switches to it.
func _on_bridge_kind_selected(kind: int) -> void:
	if brush:
		brush.bridge.kind = kind
	_select_tool(AuthoringPanel.TOOL_BRIDGE)


## Once per map, when the Bridge tool opens: starts loading the textures a crossing on this
## map would bind (the palette planks and each map biome's cliff rock) on background threads,
## then 0.4 s later makes the crossing materials of the map's biomes (their shaders build), so
## the first placement pays for neither (17 ms of first use on the main thread, P4b-2).
func _warm_crossings() -> void:
	if _crossings_warmed or not is_instance_valid(map_root):
		return
	_crossings_warmed = true
	var terrain := _terrain()
	if terrain != null:
		for surface in AuthoredCrossings.surfaces_for_styles(document.biome_ids):
			terrain.warm_surface(surface)
	var generation := _generation
	get_tree().create_timer(0.4).timeout.connect(
		func() -> void:
			if not _superseded(generation) and is_instance_valid(map_root):
				AuthoredCrossings.of_map(map_root).warm_materials(document.biome_ids)
	)


## A Paint press was refused (every slot holds paint): say why.
func _on_paint_refused(surface: String) -> void:
	var reason := editor.surface_refusal(surface) if editor else ""
	if reason != "":
		UIManager.show_toast(reason, UIManager.TOAST_WARNING, 5.0)


## Disables the Paint tiles that cannot take a slot (all eight hold paint) with the reason
## in their tooltips; enables them all otherwise. The slot walk only runs when all eight
## are taken (AuthoringEditor.surface_refusal).
func _refresh_paint_limits() -> void:
	if editor == null or panel == null:
		return
	var reason := ""
	if document.surface_ids.size() >= MapDocument.MAX_SURFACES:
		reason = editor.surface_refusal("")
	panel.set_paint_limits(reason, document.surface_ids)
	_refresh_paint_order()


## Orders the Paint tool's Built tiles for the biomes on the map: the painted ones in
## document order, then the base's (the palette's first biome on the base surface), whose
## palette path_surfaces come first. A default the author has not replaced follows.
func _refresh_paint_order() -> void:
	var biomes := document.biome_ids.duplicate()
	for biome in PaletteLibrary.biomes(panel.palette_root):
		if biome.get("ground_surface", "") == document.base_surface:
			if not biomes.has(String(biome.id)):
				biomes.append(String(biome.id))
			break
	if panel.order_paint_tiles(biomes):
		_use_surface(panel.get_paint_surface())


## Switches the brush to `tool_id` and activates it. The Biome brush waits for a biome to be
## picked (there is nothing to paint with before); Sculpt and Paint need a map whose ground
## is the document's.
func _select_tool(tool_id: StringName) -> void:
	if brush == null or not _is_open:
		return
	match tool_id:
		AuthoringPanel.TOOL_BIOME:
			brush.set_mode(BrushTool.Mode.BIOME)
			if selected_biome == "":
				brush.deactivate()
				return
		AuthoringPanel.TOOL_THIN:
			brush.set_mode(BrushTool.Mode.THIN)
		AuthoringPanel.TOOL_PLACE:
			brush.set_mode(BrushTool.Mode.PLACE)
		AuthoringPanel.TOOL_SCULPT:
			if editor == null or not editor.can_sculpt():
				return
			brush.set_mode(BrushTool.Mode.SCULPT)
		AuthoringPanel.TOOL_PAINT:
			if editor == null or not editor.can_paint():
				return
			brush.set_mode(BrushTool.Mode.PAINT)
			if brush.paint_surface == "":
				brush.deactivate()
				return
			_use_surface(brush.paint_surface)
		AuthoringPanel.TOOL_WATER:
			if editor == null:
				return
			if not editor.water.can_carve() and document.water_bodies.is_empty():
				return
			brush.set_mode(BrushTool.Mode.WATER)
		AuthoringPanel.TOOL_BRIDGE:
			if not bridge_available():
				return
			_warm_crossings()
			brush.set_mode(BrushTool.Mode.BRIDGE)
		_:
			return
	brush.activate()
	panel.set_active_tool(tool_id)


func _on_brush_toggled(active: bool) -> void:
	if not active:
		panel.set_active_tool(&"")
		return
	var ids := {
		BrushTool.Mode.BIOME: AuthoringPanel.TOOL_BIOME,
		BrushTool.Mode.THIN: AuthoringPanel.TOOL_THIN,
		BrushTool.Mode.PLACE: AuthoringPanel.TOOL_PLACE,
		BrushTool.Mode.SCULPT: AuthoringPanel.TOOL_SCULPT,
		BrushTool.Mode.PAINT: AuthoringPanel.TOOL_PAINT,
		BrushTool.Mode.WATER: AuthoringPanel.TOOL_WATER,
		BrushTool.Mode.BRIDGE: AuthoringPanel.TOOL_BRIDGE,
	}
	panel.set_active_tool(ids[brush.mode])


## The cursor tint of a biome: its thumbnail's mean colour, lifted toward white so the ring
## reads on dark ground too.
static func biome_tint(biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var thumbnail: Variant = PaletteLibrary.biome(biome_id, root).get("thumbnail", "")
	var texture := SwatchTextures.palette_thumbnail(thumbnail, 8, root)
	if texture == null:
		return Color(0.7, 0.9, 0.6)
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Color(0.7, 0.9, 0.6)
	image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var mean := image.get_pixel(0, 0)
	mean.a = 1.0
	return mean.lerp(Color.WHITE, 0.4)


## The cursor tint of a palette surface: its swatch's mean colour, lifted toward white like
## biome_tint so the ring reads on dark ground.
static func surface_tint(surface: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Color:
	var albedo: Variant = PaletteLibrary.surfaces(root).get(surface, {}).get("albedo", "")
	var texture := SwatchTextures.palette_thumbnail(
		String(albedo), AuthoringPanel.PAINT_THUMB_PX, root
	)
	var image := texture.get_image() if texture else null
	if image == null or image.is_empty():
		return Color(0.9, 0.82, 0.66)
	image = image.duplicate() as Image
	image.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var mean := image.get_pixel(0, 0)
	mean.a = 1.0
	return mean.lerp(Color.WHITE, 0.4)


## Copies what the scene holds back into the document and the level: the scatter and props
## rows (their AuthoredScatter nodes hold the current rows), and the map name.
func _sync_document() -> void:
	if is_instance_valid(scatter):
		document.scatter = scatter.rows_by_asset()
	if is_instance_valid(props):
		document.props = props.rows_by_asset()
	level.level_name = panel.get_map_name()


# ============================================================================
# Saving
# ============================================================================


## Saves the map into its level folder (a new folder named after the map the first time):
## map.ttmap atomically, then level.json with map_document set, then a thumbnail of the
## current view. Waits for any scatter regeneration to land first so what is saved is what
## is shown. Keeps the drawer open. Returns true on success.
func save_async() -> bool:
	if not _is_open or _saving:
		return false
	_saving = true
	if editor:
		# A sculpt stroke's kept rocks and its regeneration request come with its height work.
		editor.finish_height_work()
	while is_instance_valid(scatter) and scatter.is_regenerating():
		await get_tree().process_frame
	if not is_inside_tree():
		return false
	_sync_document()
	var ok := write_level(level, document, capture_thumbnail())
	_saving = false
	if not ok:
		UIManager.show_error("The map could not be saved.")
		return false
	session.mark_saved()
	AuthoringAutosave.discard()
	UIManager.show_success('Saved "%s"' % level.level_name)
	return true


## Writes `doc` and `saved` into the level's folder, making the folder first for a level that
## has none. The document goes first, so level.json never names a document that is not on
## disk; a failure leaves a new level folder-less again. Best-effort thumbnail. Returns true
## when both files were written.
static func write_level(saved: LevelData, doc: MapDocument, thumbnail: Image) -> bool:
	var folder := saved.level_folder
	var is_new := folder == ""
	if is_new:
		folder = LevelManager.new_folder_name(saved.level_name)
		if DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder)) != OK:
			return false
	if MapDocumentIO.write(doc, LevelManager.map_document_path(folder)) != OK:
		if is_new:
			DirAccess.remove_absolute(LevelManager.folder_path(folder).trim_suffix("/"))
		return false
	var previous_document := saved.map_document
	saved.level_folder = folder
	saved.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	if LevelManager.save_level_folder(saved, folder) == "":
		saved.map_document = previous_document
		if is_new:
			saved.level_folder = ""
			DirAccess.remove_absolute(LevelManager.map_document_path(folder))
			DirAccess.remove_absolute(LevelManager.folder_path(folder).trim_suffix("/"))
		return false
	if thumbnail != null:
		LevelManager.save_thumbnail(saved, thumbnail)
	return true


## The world viewport as it is now (no drawer: that lives on its own layer), or null.
func capture_thumbnail() -> Image:
	if not is_instance_valid(_game_map):
		return null
	var texture := _game_map.world_viewport.get_texture()
	return texture.get_image() if texture else null


func _on_autosave_timeout() -> void:
	if not _is_open or _saving or not session.needs_autosave():
		return
	if (
		(is_instance_valid(scatter) and scatter.is_regenerating())
		or (editor and editor.has_height_work())
	):
		return  # Next tick: half-regenerated rows are not worth recovering.
	_sync_document()
	if AuthoringAutosave.write(document, level) == OK:
		session.mark_autosaved()


# ============================================================================
# Leaving
# ============================================================================


## Leave authoring: at once when everything is saved, else after asking whether to save,
## discard, or keep editing.
func request_leave() -> void:
	if is_instance_valid(_leave_prompt) or _saving:
		return
	if not _is_open or not session.is_dirty():
		_leave()
		return
	panel.set_leave_pending(true)
	_leave_prompt = UIManager.show_choice(
		"Leave with unsaved changes?",
		'The changes to "%s" are not saved yet.' % panel.get_map_name(),
		"Save and leave",
		"Discard",
		"Keep editing",
		_save_and_leave,
		_discard_and_leave
	)
	_leave_prompt.closed.connect(_on_leave_prompt_closed)


func _on_leave_prompt_closed(_confirmed: bool) -> void:
	_leave_prompt = null
	if panel:
		panel.set_leave_pending(false)


func _save_and_leave() -> void:
	if await save_async():
		_leave()


func _discard_and_leave() -> void:
	AuthoringAutosave.discard()
	_leave()


func _leave() -> void:
	_is_open = false
	_autosave_timer.stop()
	exit_requested.emit(level)


## Called by Root when the state exits: drops any load in flight and releases Escape.
func teardown() -> void:
	_generation += 1
	_is_open = false
	set_process(false)
	if brush:
		brush.deactivate()
		brush.editor = null
	if editor:
		editor.water.release()
		editor.rock_keeper.release()
	if _autosave_timer:
		_autosave_timer.stop()
	if panel:
		panel.end_session()
	for prompt in [_leave_prompt, _recovery_prompt]:
		if is_instance_valid(prompt) and prompt.is_inside_tree():
			prompt.queue_free()
	_leave_prompt = null
	_recovery_prompt = null
	_environment.clear()
