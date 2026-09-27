class_name AuthoredScatter
extends Node3D

## The palette scatter of an authored map (map.ttmap rows), built as chunked
## MultiMeshInstance3D children of this node and rebuilt one 10 m cell at a time while a
## brush paints. Play-time loading builds the same nodes with build_all(), so authoring and
## play cannot drift apart. Design: docs/ARCHITECTURE.md "Authored scatter".
##
## Why a Node3D child of the map root and not a RefCounted helper: it owns the chunk nodes
## (freeing it frees them, and nothing else has to track them), it needs the SceneTree for
## the grow-in tweens and for polling worker jobs in _process, and its lifetime is exactly
## the map's, so a map torn down mid-job waits for its workers in _exit_tree instead of
## leaving results for nodes that no longer exist. It sits directly under LevelMap with an
## identity transform, so rows (map frame) land where the GLB scatter path would put them
## and every load-time walk that only sees LevelMap (store_wind_materials,
## FoliageDensityController.apply) still finds it.
##
## Species. Each palette asset id is resolved once per instance (PaletteLibrary.resolve,
## then WindFoliage.apply_material with the level's foliage overrides) and its mesh and
## materials are kept for the session. Rebuilding a cell never creates a material, so the
## foliage AA shader swap, occlusion fade registration and wind re-tuning done at load stay
## valid. A species first painted mid-session is new, though: species_added carries its
## wind materials, and the owner hands them to GameMap.adopt_foliage_materials() (AA
## variant, occlusion fade) and LevelEnvironmentManager.add_wind_materials() (wind
## re-tuning), the same bookkeeping load-time materials get.
##
## Cells. One MultiMeshInstance3D per (asset id, cell), named
## `<asset stem>_MultiMesh_c<x>_<z>` (always suffixed, unlike the GLB path's single-cell
## species), so FoliageDensityController groups them by species and a rebuild never
## renames a neighbour. Instances are ordered by a hash of the instance itself seeded by
## that name (ScatterRows.instance_order), not by their index, so the prefix the density
## budget draws keeps the same instances when others are added or removed. A row's identity
## is its X, Z and scale (ScatterRows.row_keys), so a height edit that moves Y keeps it the
## same instance; move_rows() rewrites moved instances in place.
##
## Grow-in. set_cells() with animation splits each rebuilt cell: rows that were already
## there stay in the cell's node untouched, and rows that are new go to a temporary
## `..._grow<n>` node that grows in over grow_seconds and is then merged back. Wind species
## grow through the `grow` instance uniform every wind shader variant multiplies the vertex
## by (one per-node value, no per-instance work); anything else, rocks above all, rises out
## of the ground by moving the temporary node, which needs no shader at all. Instances an
## animated rebuild removes shrink away the same two ways (ScatterShrink); an unanimated
## rebuild (a prop being rotated or scaled in place) replaces them at once.
##
## Brushes. attach_document() plus request_region(rect) regenerate the cells a painted
## rectangle can affect (ScatterRegen: the cells it touches plus each species' relation
## halo) on WorkerThreadPool from a copy of the document's masks, and apply finished jobs
## on the main thread, latest request wins per cell. A biome's asset scenes load on
## background threads as soon as it is registered (prepare_biome), species resolve one per
## frame as they arrive, and a finished job waits for its species rather than loading them
## on the spot. rows_by_asset() gives the current rows back in the document's form for
## saving.

## Emitted when a species with wind is resolved, with the wind ShaderMaterials it created.
## After load, these need GameMap.adopt_foliage_materials() and
## LevelEnvironmentManager.add_wind_materials().
signal species_added(materials: Array[ShaderMaterial])
## Emitted after set_cells() (and so after every applied brush job) with the cells rebuilt.
signal cells_applied(cells: Array[Vector2i])

const NODE_INFIX := "_MultiMesh"
const GROWING_INFIX := "_grow"
## Instance uniform in shaders/wind_foliage_include.gdshaderinc (0 = collapsed, 1 = full).
const GROW_UNIFORM := &"grow"
## How long a new instance takes to grow in. Long enough to read as growth rather than a
## pop at the game camera, short enough that a stroke does not trail a wave behind it.
const GROW_SECONDS := 0.35
## At most this many regeneration jobs run at once (and never more than half the cores),
## so a stroke cannot flood the pool that GLB loading and the renderer also use.
const MAX_JOBS := 4
## Species resolved per frame by _process (see _warm_species; measured cost in
## docs/PERFORMANCE.md "Authored scatter").
const SPECIES_PER_FRAME := 1
## Every instance joins this group, so GameMap.apply_foliage_density() can hand a changed
## density setting to set_budget() without knowing where the scatter lives.
const GROUP := &"authored_scatter"

const _GROW_SHADER := 0
const _GROW_RISE := 1

## Palette root species are resolved from.
var palette_root: String = PaletteLibrary.DEFAULT_ROOT
## The level's foliage overrides ("<category>_sway_speed" ...), baked into each species'
## wind material when it is resolved.
var foliage_overrides: Dictionary = {}
## Where FoliageDensityController applies the budget after a rebuild; null means the parent
## (LevelMap), which holds a dressed GLB's own scatter too, so the budget stays map-wide.
var budget_root: Node3D = null
## The foliage primitive budget; negative reads the player's setting once, on first use.
## Kept current by set_budget() through GROUP.
var budget: int = -1
## Grow-in duration; 0 builds new instances in place with no animation.
var grow_seconds: float = GROW_SECONDS
## Microseconds of the last set_cells() call and of the last worker job, for measurement.
var last_apply_usec: int = 0
var last_worker_usec: int = 0
## Draw each species once, invisibly, as it resolves (PipelineWarmer); off to measure.
var warm_pipelines: bool = true
## Props (AuthoredProps) whose rocks regeneration grows no twin inside (RockKeep.blockers_of).
var blocker_source: AuthoredScatter = null

## asset id -> {"mesh", "wind_category", "stem", "materials", "grow_mode", "height"}, or {}
## for an id that did not resolve (its rows are kept, nothing is built).
var _species: Dictionary = {}
## cell -> {asset id -> PackedFloat32Array}: the rows every node of the cell is built from.
var _cells: Dictionary = {}
## cell -> {asset id -> MultiMeshInstance3D}: the settled node of each asset in the cell.
var _nodes: Dictionary = {}
## cell -> {asset id -> Array of {"node", "keys", "tween"}}: instances still growing in.
var _growing: Dictionary = {}
## cell -> {asset id -> PackedInt32Array}: for each instance of the settled node, in
## instance order, the index of its row in _cells, so move_rows() can rewrite single
## instances in place.
var _orders: Dictionary = {}
var _grow_serial: int = 0
var _document: MapDocument = null
var _regen: ScatterRegen = null
## In-flight jobs: {"id": WorkerThreadPool task id, "job": Dictionary, "result": Dictionary}.
var _jobs: Array[Dictionary] = []
## Jobs done on the worker, waiting for their species ("needs": asset ids) to resolve.
var _finished: Array[Dictionary] = []
## asset id -> resource path of a threaded load started by prepare_biome().
var _loading: Dictionary = {}
## Scatter primitives under the budget root after the last full budget apply, kept current
## by each rebuild's delta; -1 when unknown or when the map was over budget (see
## _apply_budget). Valid because nothing else changes scatter under the root between
## rebuilds: a GLB's scatter is static, and a density change re-plans the whole map
## (GameMap.apply_foliage_density) and comes back through set_budget().
var _known_total: int = -1
## Nodes whose MultiMesh the current set_cells() built, for the budget fast path. Untyped:
## a node freed later in the same rebuild must not break the loop that skips it.
var _touched: Array = []
## True between begin_build() and end_build(): set_cells() skips the budget apply.
var _budget_deferred: bool = false
## Created on first use (never in a headless run, so tests see no extra child).
var _warmer: PipelineWarmer = null


## A new, empty instance named for the scene tree; add it under LevelMap before building
## with animation (tweens need the tree).
static func create(
	root: String = PaletteLibrary.DEFAULT_ROOT, overrides: Dictionary = {}
) -> AuthoredScatter:
	var scatter := AuthoredScatter.new()
	scatter.name = "AuthoredScatter"
	scatter.palette_root = root
	scatter.foliage_overrides = overrides
	return scatter


## The name of the settled node of `asset_id` in `cell`.
static func node_name_for(asset_id: String, cell: Vector2i) -> String:
	return asset_id.validate_node_name() + NODE_INFIX + ScatterChunker.cell_suffix(cell)


## A stable identity per row from its X, Z and scale, never its Y or rotation, so a height
## edit keeps every instance the same one (ScatterRows.row_keys).
static func row_keys(bits: PackedInt32Array) -> PackedInt64Array:
	return ScatterRows.row_keys(bits)


## Rows per asset regrouped by 10 m cell: cell -> {asset id -> PackedFloat32Array}.
static func rows_by_cell_of(rows_by_asset: Dictionary) -> Dictionary:
	var by_cell := {}
	for asset_id in rows_by_asset:
		var split := ScatterRegen.split_by_cell(rows_by_asset[asset_id])
		for cell in split:
			if not by_cell.has(cell):
				by_cell[cell] = {}
			by_cell[cell][asset_id] = split[cell]
	return by_cell


func _ready() -> void:
	set_process(false)
	add_to_group(GROUP)
	# Species resolved off-tree (the play-time load) are warmed once the map is installed.
	_warm_resolved.call_deferred()


func _warm_resolved() -> void:
	for species: Dictionary in _species.values():
		_warm(species)


## Draws a resolved species once, invisibly, so its draw-time pipelines compile now.
func _warm(species: Dictionary) -> void:
	if species.is_empty() or not warm_pipelines or not PipelineWarmer.available(self):
		return
	if _warmer == null:
		_warmer = PipelineWarmer.new()
		_warmer.name = "PipelineWarmer"
		add_child(_warmer)
	_warmer.warm(species.mesh, String(species.stem), String(species.wind_category))


## A new foliage density budget (the player moved the setting). The nodes themselves were
## already re-thinned by whoever applied it map-wide; this only keeps later rebuilds on it.
func set_budget(value: int) -> void:
	budget = value


func _exit_tree() -> void:
	# A task handed to WorkerThreadPool must be waited on; the results are dropped.
	for entry in _jobs:
		WorkerThreadPool.wait_for_task_completion(entry.id)
	_jobs.clear()
	_finished.clear()
	# Collect threaded loads nobody resolved, so the loader releases them.
	for path in _loading.values():
		ResourceLoader.load_threaded_get(path)
	_loading.clear()


func _process(_delta: float) -> void:
	if _regen != null:
		_collect_finished_jobs()
	_warm_species()
	if _regen != null:
		_apply_ready_jobs()
		_dispatch_jobs()
	if not is_regenerating() and _loading.is_empty():
		set_process(false)


## Builds every cell of a whole map's rows (asset id -> flat rows, MapDocument.scatter's
## form) with no animation, replacing whatever was built. The play-time load path.
func build_all(rows_by_asset: Dictionary) -> void:
	clear()
	set_cells(rows_by_cell_of(rows_by_asset), false)


## Replaces the instances of exactly the given cells (cell -> {asset id ->
## PackedFloat32Array}; an asset missing from a cell's dictionary, or a cell with an empty
## one, is removed) and leaves every other cell's nodes untouched, then re-applies the
## foliage density budget. With `animate`, instances new to a cell grow in and the rest
## stay put; without, the cell is rebuilt in place.
func set_cells(rows_by_cell: Dictionary, animate: bool = true) -> void:
	var started := Time.get_ticks_usec()
	var grow := animate and grow_seconds > 0.0 and is_inside_tree()
	var cells: Array[Vector2i] = []
	var delta := 0
	for cell in rows_by_cell:
		delta += _primitive_delta(_cells.get(cell, {}), rows_by_cell[cell])
		_rebuild_cell(cell, rows_by_cell[cell], grow)
		cells.append(cell)
	_apply_budget(delta)
	last_apply_usec = Time.get_ticks_usec() - started
	cells_applied.emit(cells)


## Moves instances of `asset_id` in `cell` in place: `rows` replaces the cell's rows of that
## asset and must hold the same rows in the same order (only their Y and rotation may
## differ, as after a height edit), and `moved` lists the indices of the rows that changed.
## Only those instances' transforms are rewritten, in every node that draws them; nothing is
## rebuilt, nothing grows or shrinks, and the density budget's visible counts stay as they
## are. Returns false (and changes nothing) when the rows do not match the cell's, so the
## caller can fall back to set_cells().
@warning_ignore("integer_division")
func move_rows(
	cell: Vector2i, asset_id: String, rows: PackedFloat32Array, moved: PackedInt32Array
) -> bool:
	var cell_rows: Dictionary = _cells.get(cell, {})
	var current: PackedFloat32Array = cell_rows.get(asset_id, PackedFloat32Array())
	if current.is_empty() or current.size() != rows.size():
		return false
	cell_rows[asset_id] = rows
	if moved.is_empty():
		return true
	var flags := PackedByteArray()
	flags.resize(rows.size() / MapDocument.ROW_STRIDE)
	for r in moved:
		flags[r] = 1
	var node: MultiMeshInstance3D = _nodes.get(cell, {}).get(asset_id)
	var order: PackedInt32Array = _orders.get(cell, {}).get(asset_id, PackedInt32Array())
	if node != null and node.multimesh != null and order.size() == node.multimesh.instance_count:
		var multimesh := node.multimesh
		for i in order.size():
			var r := order[i]
			if flags[r] != 0:
				multimesh.set_instance_transform(i, ScatterRows.row_transform(rows, r))
	var entries: Array = _growing.get(cell, {}).get(asset_id, [])
	if not entries.is_empty():
		var keys := row_keys(rows.to_byte_array().to_int32_array())
		for entry in entries:
			var indices := PackedInt32Array()
			for i in keys.size():
				if (entry.keys as Dictionary).has(keys[i]):
					indices.append(i)
			var growing_node: MultiMeshInstance3D = entry.node
			var visible := growing_node.multimesh.visible_instance_count
			growing_node.multimesh = ScatterGlbUtils.build_multimesh(
				growing_node.multimesh.mesh,
				_ordered_transforms(asset_id, cell, rows, keys, indices)
			)
			growing_node.multimesh.visible_instance_count = visible
	return true


## Frees every node and forgets every row (resolved species are kept).
func clear() -> void:
	for cell in _growing.keys():
		for asset_id in (_growing[cell] as Dictionary).keys():
			for entry in _growing[cell][asset_id]:
				_free_growing(entry)
	_growing.clear()
	for cell in _nodes:
		for node in (_nodes[cell] as Dictionary).values():
			_free_node(node)
	_nodes.clear()
	_orders.clear()
	_cells.clear()
	_known_total = -1


## Finishes every grow-in now (tests, and before anything reads the settled nodes).
func complete_growth() -> void:
	for cell in _growing.keys():
		for asset_id in (_growing[cell] as Dictionary).keys():
			for entry in (_growing[cell][asset_id] as Array).duplicate():
				_finish_growth(cell, asset_id, entry)


func is_growing() -> bool:
	return not _growing.is_empty()


## The current rows in MapDocument.scatter's form (asset id -> flat rows, cells in sorted
## order), for saving.
func rows_by_asset() -> Dictionary[String, PackedFloat32Array]:
	var cells := _cells.keys()
	cells.sort()
	var pieces := {}
	for cell in cells:
		for asset_id in _cells[cell]:
			if not pieces.has(asset_id):
				pieces[asset_id] = []
			pieces[asset_id].append(_cells[cell][asset_id])
	var flat: Dictionary[String, PackedFloat32Array] = {}
	for asset_id in pieces:
		var joined := PackedFloat32Array()
		for rows in pieces[asset_id]:
			joined.append_array(rows)
		flat[asset_id] = joined
	return flat


## The rows of one cell (asset id -> flat rows), or {}.
func cell_rows(cell: Vector2i) -> Dictionary:
	return _cells.get(cell, {})


## The settled node of `asset_id` in `cell`, or null.
func get_cell_node(cell: Vector2i, asset_id: String) -> MultiMeshInstance3D:
	return _nodes.get(cell, {}).get(asset_id)


## The temporary nodes of `asset_id` in `cell` that are still growing in.
func get_growing_nodes(cell: Vector2i, asset_id: String) -> Array[MultiMeshInstance3D]:
	var nodes: Array[MultiMeshInstance3D] = []
	for entry in _growing.get(cell, {}).get(asset_id, []):
		nodes.append(entry.node)
	return nodes


## The wind ShaderMaterials of a resolved species, or [] (unknown, unresolved or no wind).
func species_materials(asset_id: String) -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	materials.assign(_species.get(asset_id, {}).get("materials", []))
	return materials


## Starts brush regeneration against `doc`, whose biome masks the brush edits in place.
## Registers every biome it paints; request_region() registers biomes added later.
func attach_document(doc: MapDocument) -> void:
	_document = doc
	_regen = ScatterRegen.for_document(doc)
	_regen.built_surfaces = PackedStringArray(
		PaletteLibrary.surfaces_with_role("built", palette_root)
	)
	_regen.cliff_surfaces = PackedStringArray(
		PaletteLibrary.surfaces_with_role("cliff", palette_root)
	)
	_register_biomes()


## Queues regeneration of everything the density samples inside `rect` (world XZ) can
## change. Returns at once; results appear over the next frames.
func request_region(rect: Rect2) -> void:
	if _regen == null:
		push_warning("AuthoredScatter: request_region() before attach_document()")
		return
	_register_biomes()
	_regen.request_region(rect)
	_dispatch_jobs()
	set_process(true)


## True while regeneration is queued, running, or finished but waiting for its species.
func is_regenerating() -> bool:
	return (
		not _jobs.is_empty()
		or not _finished.is_empty()
		or (_regen != null and _regen.has_pending())
	)


## The scheduler, for tests and measurement.
func get_regen() -> ScatterRegen:
	return _regen


## Starts loading every asset of a biome on background threads, so the first dab of it
## does not stall the main thread on GLB loads (about 0.5 to 1.5 s for a whole biome,
## measured). Called for every biome the document paints; call it as soon as a biome is
## chosen for the brush to get ahead of the first dab. Species are then resolved a couple
## per frame as their loads finish (see _warm_species).
func prepare_biome(biome_id: String) -> void:
	for rule in PaletteLibrary.species(biome_id, palette_root):
		for asset_id in rule.get("assets", []):
			_request_asset(asset_id)
	if not _loading.is_empty():
		set_process(true)


## How many species have been resolved (including ids that failed to).
func resolved_species_count() -> int:
	return _species.size()


## Starts background loads for the given palette asset ids, like prepare_biome() does for
## a biome's assets. The play-time load knows its ids from the document rows, and calls
## this before building so build_all()'s species resolution never loads a GLB on the main
## thread (0.9 to 2.1 s cold for a whole biome, measured).
func prepare_assets(asset_ids: Array) -> void:
	for asset_id in asset_ids:
		_request_asset(asset_id)
	if not _loading.is_empty() and is_inside_tree():
		set_process(true)


## True while an asset started by prepare_assets() or prepare_biome() is still loading or
## loaded but not yet resolved.
func has_prepared_species() -> bool:
	return not _loading.is_empty()


## Resolves prepared species whose background loads have finished, until `budget_usec`
## of main-thread time is spent (at least one, so progress is guaranteed; one species
## costs up to about 10 ms). The play-time load calls it once per frame. Returns how many
## species it resolved.
func resolve_prepared(budget_usec: int) -> int:
	var start := Time.get_ticks_usec()
	var resolved := 0
	for asset_id in _loading.keys():
		if resolved > 0 and Time.get_ticks_usec() - start >= budget_usec:
			break
		if not _asset_loading(asset_id):
			_species_for(asset_id)
			resolved += 1
	return resolved


## Collects every background load still outstanding without resolving it. A scatter that
## is freed outside the tree (a load abandoned mid-way) never runs _exit_tree, so its
## owner calls this first.
func release_prepared() -> void:
	for path in _loading.values():
		ResourceLoader.load_threaded_get(path)
	_loading.clear()


## Starts a build spread over several calls: clears everything, then build_cells() adds
## cells without re-applying the density budget each time (a full re-plan walks the whole
## map), and end_build() applies it once. The play-time load builds this way so a painted
## 200 ft map (about 100 ms of MultiMesh building) does not stall one frame.
func begin_build() -> void:
	clear()
	_budget_deferred = true


## Adds the given cells (cell -> {asset id -> flat rows}) between begin_build() and
## end_build(), with no animation.
func build_cells(rows_by_cell: Dictionary) -> void:
	set_cells(rows_by_cell, false)


## Ends a begin_build() build: applies the density budget across the budget root once.
func end_build() -> void:
	_budget_deferred = false
	_known_total = -1
	_apply_budget(0)


func _register_biomes() -> void:
	for biome_id in _document.biome_ids:
		if not _regen.has_biome(biome_id):
			_regen.set_biome(biome_id, PaletteLibrary.species(biome_id, palette_root))
			prepare_biome(biome_id)


func _request_asset(asset_id: String) -> void:
	if _species.has(asset_id) or _loading.has(asset_id):
		return
	var entry := PaletteLibrary.asset(asset_id, palette_root)
	if entry.is_empty():
		return
	var path := palette_root.path_join(entry.file)
	# Only imported scenes load on a thread; a raw GLB (a user:// palette) resolves in place.
	if not ResourceLoader.exists(path, "PackedScene"):
		return
	if ResourceLoader.load_threaded_request(path, "PackedScene") == OK:
		_loading[asset_id] = path


func _asset_loading(asset_id: String) -> bool:
	var path: String = _loading.get(asset_id, "")
	if path == "":
		return false
	return ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS


## Resolves up to SPECIES_PER_FRAME species whose loads are done: first those finished
## jobs are waiting for, then preloaded ones, so resolution cost is spread over frames.
func _warm_species() -> void:
	var left := SPECIES_PER_FRAME
	for entry in _finished:
		for asset_id in entry.needs:
			if left == 0:
				return
			if not _species.has(asset_id) and not _asset_loading(asset_id):
				_species_for(asset_id)
				left -= 1
	for asset_id in _loading.keys():
		if left == 0:
			return
		if not _asset_loading(asset_id):
			_species_for(asset_id)
			left -= 1


func _dispatch_jobs() -> void:
	var limit := clampi(OS.get_processor_count() >> 1, 1, MAX_JOBS)
	var snapshot: MapDocument = null
	var busy := _jobs.size() >= limit or not _regen.has_pending()
	var blockers := PackedFloat32Array() if busy else RockKeep.blockers_of(blocker_source)
	while _jobs.size() < limit and _regen.has_pending():
		var job := _regen.take_job()
		if snapshot == null:
			# One copy serves every job dispatched this frame; they only read it.
			snapshot = _snapshot(_document)
		var work: Dictionary = RockKeep.with_blockers(job.work, blockers)
		var result := {}
		var task := func() -> void: result.merge(ScatterRegen.run(snapshot, work))
		var id := WorkerThreadPool.add_task(task, false, "AuthoredScatter regeneration")
		_jobs.append({"id": id, "job": job, "result": result})


## Moves jobs whose worker task has completed to _finished, noting the species their rows
## need. wait_for_task_completion() returns at once for a completed task.
func _collect_finished_jobs() -> void:
	for entry in _jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(entry.id):
			continue
		_jobs.erase(entry)
		WorkerThreadPool.wait_for_task_completion(entry.id)
		var result: Dictionary = entry.result
		last_worker_usec = result.get("usec", 0)
		var needs := {}
		for cell_rows in (result.get("rows_by_cell", {}) as Dictionary).values():
			for asset_id in cell_rows:
				needs[asset_id] = true
		entry["needs"] = needs.keys()
		_finished.append(entry)


## Applies every finished job whose species are all resolved, in one set_cells() call.
## Cells a newer request has touched since are dropped by ScatterRegen.accept().
func _apply_ready_jobs() -> void:
	var rows_by_cell := {}
	for entry in _finished.duplicate():
		var ready := true
		for asset_id in entry.needs:
			if not _species.has(asset_id):
				ready = false
				break
		if not ready:
			continue
		_finished.erase(entry)
		var job: Dictionary = entry.job
		var fresh: Dictionary = entry.result.get("rows_by_cell", {})
		for cell in _regen.accept(job):
			var base: Dictionary = rows_by_cell.get(cell, _cells.get(cell, {}))
			rows_by_cell[cell] = ScatterRegen.merge_cell(
				base, job.regenerated[cell], fresh.get(cell, {})
			)
	if not rows_by_cell.is_empty():
		set_cells(rows_by_cell)


## A copy of the parts of `doc` generation reads, for a worker. The arrays are duplicated:
## GDScript packed arrays are shared by reference, not copy-on-write (measured in 4.7: a
## write through one variable shows in every other holding the array), so without the copy
## a worker would read masks while the brush writes them, and an append that reallocates
## would pull the buffer out from under it. About 0.1 ms for a 200 ft map.
static func _snapshot(doc: MapDocument) -> MapDocument:
	var copy := MapDocument.new()
	copy.map_seed = doc.map_seed
	copy.size_cells = doc.size_cells
	copy.cell_size_m = doc.cell_size_m
	copy.sample_spacing_m = doc.sample_spacing_m
	copy.heights = doc.heights.duplicate()
	copy.biome_ids = doc.biome_ids.duplicate()
	copy.biome_slots = doc.biome_slots.duplicate()
	copy.biome_density = doc.biome_density.duplicate()
	copy.surface_ids = doc.surface_ids.duplicate()
	copy.surface_weights = doc.surface_weights.duplicate()
	return copy


func _rebuild_cell(cell: Vector2i, fresh: Dictionary, grow: bool) -> void:
	var old: Dictionary = _cells.get(cell, {})
	var kept := {}
	for asset_id in fresh:
		var rows: PackedFloat32Array = fresh[asset_id]
		if rows.size() >= MapDocument.ROW_STRIDE:
			kept[asset_id] = rows
	if kept.is_empty():
		_cells.erase(cell)
	else:
		_cells[cell] = kept
	var assets := {}
	for source in [old, kept, _nodes.get(cell, {}), _growing.get(cell, {})]:
		for asset_id in source:
			assets[asset_id] = true
	for asset_id in assets:
		_rebuild_asset(cell, asset_id, old.get(asset_id, PackedFloat32Array()), grow)


func _rebuild_asset(
	cell: Vector2i, asset_id: String, old_rows: PackedFloat32Array, grow: bool
) -> void:
	var species := _species_for(asset_id)
	if species.is_empty():
		return
	var rows: PackedFloat32Array = _cells.get(cell, {}).get(asset_id, PackedFloat32Array())
	var bits := rows.to_byte_array().to_int32_array()
	var keys := row_keys(bits)
	var present := {}
	for key in keys:
		present[key] = true
	var was_growing := {}
	for entry in _growing.get(cell, {}).get(asset_id, []):
		was_growing.merge(entry.keys)
	var growing_keys := _refresh_growing(cell, asset_id, rows, keys, present)
	var old_keys := {}
	if grow:
		var old_list := row_keys(old_rows.to_byte_array().to_int32_array())
		var removed := PackedInt32Array()
		for i in old_list.size():
			old_keys[old_list[i]] = true
			if not present.has(old_list[i]) and not was_growing.has(old_list[i]):
				removed.append(i)
		_shrink_out(species, cell, old_rows, removed)
	var settled := PackedInt32Array()
	var fresh := PackedInt32Array()
	for i in keys.size():
		if growing_keys.has(keys[i]):
			continue
		if grow and not old_keys.has(keys[i]):
			fresh.append(i)
		else:
			settled.append(i)
	# Growth first, so a cell whose instances are all new keeps its settled node (empty
	# until the merge) rather than freeing it and naming a new one.
	if not fresh.is_empty():
		_start_growth(cell, asset_id, rows, keys, fresh)
	_set_settled(cell, asset_id, rows, keys, settled, -1)


## Drops rows that left the cell from its growing nodes (freeing a node left empty and
## rebuilding one that lost some), keeping every surviving grow-in running from where it
## is. Returns the keys still growing.
func _refresh_growing(
	cell: Vector2i,
	asset_id: String,
	rows: PackedFloat32Array,
	keys: PackedInt64Array,
	present: Dictionary
) -> Dictionary:
	var growing_keys := {}
	var entries: Array = _growing.get(cell, {}).get(asset_id, [])
	for entry in entries.duplicate():
		var entry_keys: Dictionary = entry.keys
		var surviving := {}
		for key in entry_keys:
			if present.has(key):
				surviving[key] = true
		if surviving.is_empty():
			_free_growing(entry)
			entries.erase(entry)
			continue
		if surviving.size() != entry_keys.size():
			entry.keys = surviving
			var indices := PackedInt32Array()
			for i in keys.size():
				if surviving.has(keys[i]):
					indices.append(i)
			var node: MultiMeshInstance3D = entry.node
			node.multimesh = ScatterGlbUtils.build_multimesh(
				node.multimesh.mesh, _ordered_transforms(asset_id, cell, rows, keys, indices)
			)
			_touched.append(node)
		growing_keys.merge(surviving)
	if entries.is_empty():
		_erase_growing(cell, asset_id)
	return growing_keys


## Builds (or rebuilds, or frees) the settled node of an asset in a cell from the rows at
## `indices`. `visible` >= 0 sets its visible_instance_count directly (a grow-in merge,
## which moves instances between nodes without changing the species' total).
func _set_settled(
	cell: Vector2i,
	asset_id: String,
	rows: PackedFloat32Array,
	keys: PackedInt64Array,
	indices: PackedInt32Array,
	visible: int
) -> void:
	var node: MultiMeshInstance3D = _nodes.get(cell, {}).get(asset_id)
	var growing: bool = _growing.get(cell, {}).has(asset_id)
	if indices.is_empty() and not (growing and node != null):
		if node != null:
			_free_node(node)
			_nodes[cell].erase(asset_id)
			if (_nodes[cell] as Dictionary).is_empty():
				_nodes.erase(cell)
			_orders.get(cell, {}).erase(asset_id)
		return
	var order := ScatterRows.instance_order(keys, indices, node_name_for(asset_id, cell))
	var transforms := ScatterRows.transforms_from_rows(rows, order)
	if not _orders.has(cell):
		_orders[cell] = {}
	_orders[cell][asset_id] = order
	if node == null:
		node = _new_chunk_node(asset_id, cell, "", transforms)
		if not _nodes.has(cell):
			_nodes[cell] = {}
		_nodes[cell][asset_id] = node
	else:
		node.multimesh = ScatterGlbUtils.build_multimesh(node.multimesh.mesh, transforms)
	_touched.append(node)
	if visible >= 0:
		node.multimesh.visible_instance_count = mini(visible, node.multimesh.instance_count)


func _start_growth(
	cell: Vector2i,
	asset_id: String,
	rows: PackedFloat32Array,
	keys: PackedInt64Array,
	indices: PackedInt32Array
) -> void:
	var species: Dictionary = _species[asset_id]
	_grow_serial += 1
	var node := _new_chunk_node(
		asset_id,
		cell,
		GROWING_INFIX + str(_grow_serial),
		_ordered_transforms(asset_id, cell, rows, keys, indices)
	)
	var entry_keys := {}
	for i in indices:
		entry_keys[keys[i]] = true
	var lift := 0.0
	if species.grow_mode == _GROW_RISE:
		var tallest := 0.0
		for i in indices:
			tallest = maxf(tallest, rows[i * MapDocument.ROW_STRIDE + 8])
		lift = maxf(species.height * tallest, 0.05)
	_touched.append(node)
	var entry := {"node": node, "keys": entry_keys, "tween": null}
	_set_growth(0.0, node, species.grow_mode, lift)
	var tween := create_tween()
	(
		tween
		. tween_method(_set_growth.bind(node, species.grow_mode, lift), 0.0, 1.0, grow_seconds)
		. set_trans(Tween.TRANS_CUBIC)
		. set_ease(Tween.EASE_OUT)
	)
	tween.tween_callback(_finish_growth.bind(cell, asset_id, entry))
	entry.tween = tween
	if not _growing.has(cell):
		_growing[cell] = {}
	if not _growing[cell].has(asset_id):
		_growing[cell][asset_id] = []
	_growing[cell][asset_id].append(entry)


## Instances a rebuild removed (rows at `indices` of the cell's previous rows) shrink away
## on a temporary node instead of vanishing (ScatterShrink).
func _shrink_out(
	species: Dictionary, cell: Vector2i, old_rows: PackedFloat32Array, indices: PackedInt32Array
) -> void:
	if indices.is_empty():
		return
	var transforms := ScatterRows.transforms_from_rows(old_rows, indices)
	ScatterShrink.start(
		self,
		species.mesh,
		species.stem,
		ScatterChunker.cell_suffix(cell),
		transforms,
		species.wind_category,
		ScatterShrink.sink_depth_for(species.mesh, transforms),
		grow_seconds
	)


func _set_growth(value: float, node: MultiMeshInstance3D, mode: int, lift: float) -> void:
	if not is_instance_valid(node):
		return
	if mode == _GROW_SHADER:
		node.set_instance_shader_parameter(GROW_UNIFORM, value)
	else:
		node.position.y = -lift * (1.0 - value)


## Merges a finished grow-in into the cell's settled node. The merged node draws as many
## instances as the two did together, so the density budget's totals do not move and no
## global re-plan is needed.
func _finish_growth(cell: Vector2i, asset_id: String, entry: Dictionary) -> void:
	var entries: Array = _growing.get(cell, {}).get(asset_id, [])
	if not entry in entries:
		return
	entries.erase(entry)
	if entries.is_empty():
		_erase_growing(cell, asset_id)
	var grown: MultiMeshInstance3D = entry.node
	var settled: MultiMeshInstance3D = _nodes.get(cell, {}).get(asset_id)
	var visible := -1
	var grown_visible := grown.multimesh.visible_instance_count
	var settled_visible := settled.multimesh.visible_instance_count if settled else 0
	if grown_visible >= 0 and settled_visible >= 0:
		visible = grown_visible + settled_visible
	_free_growing(entry)
	var rows: PackedFloat32Array = _cells.get(cell, {}).get(asset_id, PackedFloat32Array())
	var keys := row_keys(rows.to_byte_array().to_int32_array())
	var still := {}
	for other in entries:
		still.merge(other.keys)
	var indices := PackedInt32Array()
	for i in keys.size():
		if not still.has(keys[i]):
			indices.append(i)
	_set_settled(cell, asset_id, rows, keys, indices, visible)


## A chunk node of this asset in this cell (ScatterGlbUtils.build_chunk, so it matches the
## GLB path's nodes), named with the cell suffix plus `extra`.
func _new_chunk_node(
	asset_id: String, cell: Vector2i, extra: String, transforms: Array[Transform3D]
) -> MultiMeshInstance3D:
	var species: Dictionary = _species[asset_id]
	return ScatterGlbUtils.build_chunk(
		self,
		species.mesh,
		species.stem,
		transforms,
		species.wind_category,
		ScatterChunker.cell_suffix(cell) + extra
	)


func _ordered_transforms(
	asset_id: String,
	cell: Vector2i,
	rows: PackedFloat32Array,
	keys: PackedInt64Array,
	indices: PackedInt32Array
) -> Array[Transform3D]:
	var order := ScatterRows.instance_order(keys, indices, node_name_for(asset_id, cell))
	return ScatterRows.transforms_from_rows(rows, order)


func _free_growing(entry: Dictionary) -> void:
	var tween: Tween = entry.tween
	if tween != null and tween.is_valid():
		tween.kill()
	_free_node(entry.node)


func _erase_growing(cell: Vector2i, asset_id: String) -> void:
	if not _growing.has(cell):
		return
	_growing[cell].erase(asset_id)
	if (_growing[cell] as Dictionary).is_empty():
		_growing.erase(cell)


func _free_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.get_parent() == self:
		remove_child(node)
	node.free()


## The species record of an asset id, resolving it on first use (see the class comment).
func _species_for(asset_id: String) -> Dictionary:
	if _species.has(asset_id):
		return _species[asset_id]
	# Collect a threaded load if one was started (waiting for it if it is still running):
	# holding the scene keeps it in the resource cache while resolve() loads it by path,
	# and a finished threaded load must be collected or it is never released.
	var path: String = _loading.get(asset_id, "")
	@warning_ignore("unused_variable")
	var held: Resource = null
	if path != "":
		_loading.erase(asset_id)
		held = ResourceLoader.load_threaded_get(path)
	var template := PaletteLibrary.resolve(asset_id, palette_root)
	if not template.get("mesh") is Mesh:
		_species[asset_id] = {}
		return {}
	var mesh: Mesh = template.mesh
	var category: String = template.get("wind_category", "")
	WindFoliage.apply_material(mesh, category, foliage_overrides)
	var materials: Array[ShaderMaterial] = []
	var all_wind := mesh.get_surface_count() > 0
	for i in mesh.get_surface_count():
		var material := mesh.surface_get_material(i)
		if material is ShaderMaterial and material.has_meta("wind_category"):
			materials.append(material)
		else:
			all_wind = false
	var aabb := mesh.get_aabb()
	_species[asset_id] = {
		"mesh": mesh,
		"wind_category": category,
		"stem": asset_id.validate_node_name(),
		"materials": materials,
		"grow_mode": _GROW_SHADER if all_wind else _GROW_RISE,
		"height": maxf(aabb.end.y, 0.0),
		"primitives": FoliageBudget.primitives_per_instance(mesh),
	}
	if not materials.is_empty():
		species_added.emit(materials)
	# After species_added: its handler may swap the wind shader variant (foliage AA), and
	# the variant that will be drawn is the one to warm.
	_warm(_species[asset_id])
	return _species[asset_id]


## Re-applies the density budget after a rebuild that changed the scatter's primitives by
## `delta`. The budget is global (FoliageBudget.plan thins every species by one ratio), so
## in general the whole map is re-planned: about 5 ms on a fully painted 200 ft map (999
## nodes). When the last full apply found the map under budget and it still is with the
## delta, nothing anywhere is thinned, so only the nodes this rebuild built need their
## visible count set, which is the common case while painting.
func _apply_budget(delta: int) -> void:
	if _budget_deferred:
		_touched.clear()
		return
	if budget < 0:
		budget = FoliageDensityController.budget_from_settings()
	if _known_total >= 0 and _known_total + delta <= budget:
		_known_total += delta
		for node in _touched:
			if is_instance_valid(node) and node.multimesh:
				node.multimesh.visible_instance_count = node.multimesh.instance_count
	else:
		var root: Node3D = budget_root
		if root == null:
			root = get_parent() as Node3D
		if root == null:
			root = self
		var report := FoliageDensityController.apply(root, budget)
		var total: int = report.get("total_before", 0)
		_known_total = total if total <= budget else -1
	_touched.clear()


## Primitives a cell gains going from `old` to `fresh` rows (negative when it loses some).
@warning_ignore("integer_division")
func _primitive_delta(old: Dictionary, fresh: Dictionary) -> int:
	var assets := {}
	assets.merge(old)
	assets.merge(fresh)
	var stride := MapDocument.ROW_STRIDE
	var delta := 0
	for asset_id in assets:
		var species := _species_for(asset_id)
		if species.is_empty():
			continue
		var before: int = (old.get(asset_id, PackedFloat32Array()) as PackedFloat32Array).size()
		var after: int = (fresh.get(asset_id, PackedFloat32Array()) as PackedFloat32Array).size()
		delta += (after / stride - before / stride) * int(species.primitives)
	return delta
