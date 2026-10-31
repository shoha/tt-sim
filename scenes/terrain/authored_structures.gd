class_name AuthoredStructures
extends Node3D

## The structures of a map (MapDocument.structures) as nodes, at the map origin with an identity
## transform (the map frame, like AuthoredWalls). Per structure, a Node3D `Structure_<id>` holds one
## MeshInstance3D per (material role, surface kind) of its build (StructureGeometry: `wall_masonry`,
## `roof_wood`, `trim_stone`, ...) and one StaticBody3D `Collision` on the terrain layer (layer 1,
## mask 0, not ray pickable, STRUCTURE_META = its id) made of the recipe's collision faces plus the
## walkable faces of its decks, stair treads, platforms and piles (StructureWalkable): a token
## lands on a roof, a wall's top or a deck as on the ground, the drop indicator and measure tool
## hit it, and the tools that edit the ground skip it (exclude_of()). `top_y` is the highest top
## (map Y, -INF with none).
##
## Edits. refresh(doc) compares each structure's key (StructureGeometry.key_of: recipe digest,
## footprint, params, seed, style and the ground under the footprint) with the key its node was
## built from. A changed structure is built on a WorkerThreadPool task from a snapshot of the record
## and the ground; the old node stays until the new one is ready, and when the structure is edited
## again before that, only the newest edit is kept (an older task finishes and its result is
## dropped). Built parts are kept by key (CACHE_LIMIT), so an undo, or a drag back to a shape seen
## before, makes its node at once. A load builds the parts on a worker (AuthoredLoadPrep) and
## create() only makes the nodes. Materials come from the palette as a wall's do, split by role
## (StructureLook) and drawn by the painterly shaders (StructureMaterials, StructurePaint).
## Summary: docs/systems/structures.md.

## Emitted when nodes were made or freed after an asynchronous build (the count of structures).
signal built(count: int)

const NODE_NAME := "AuthoredStructures"
## Set on every structure's collision body: the structure's id.
const STRUCTURE_META := &"tt_structure"
## Set on a structure's node (its tag_table) and its mesh instances (the per vertex tag ids).
const TAGS_META := &"tt_tags"
const NORMAL_SCALE := 0.8
const CACHE_LIMIT := 48
## A queued build's task id until a worker takes it (see max_running()).
## The one mesh a structure's decor plants are baked into (StructureDecor.bake), one surface per
## material kind; an asset that cannot be baked keeps a MultiMeshInstance3D "decor_<asset>".
const DECOR_NODE := "decor_baked"
const NOT_STARTED := -1
## Milliseconds of node making (installs of landed builds) one frame may spend (perf3). A landed
## build waits in _installs (StructureInstallQueue) until its turn: at least one is made per frame,
## and the rest wait once this much has been spent, so adding 20 structures or loading 128 staged
## never holds a frame.
const INSTALL_BUDGET_MS := 3.0

## Highest structure top, map Y (-INF with none), and a counter that changes with every rebuild.
var top_y: float = -INF
var version: int = 0
## How many structures this node has built (or taken from a cache) since it was made, and how many
## the last refresh() changed (tests count what an edit rebuilt).
var builds: int = 0
var last_rebuilt: int = 0
## Problems and budget notes of the builds installed so far (also logged), id -> text.
var notes: Dictionary = {}
## False keeps procgen's flat blobs for ivy and flower boxes even when the library has decor plants
## (a render job's before and after, a debugging switch); takes effect with the next build.
var plants: bool = true

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _materials: Dictionary = {}
## Per structure id, the StructureGeometry key its node was built from.
var _keys: Dictionary = {}
## Per structure id, {"sig", "key"}: what StructureGeometry.keys_memoised keeps so a refresh only
## samples the ground under structures whose inputs changed.
var _key_memo: Dictionary = {}
var _tops: Dictionary = {}
## Per structure id, {"layout", "openings"} of its build (the day a vision rule needs them).
var _details: Dictionary = {}
## Key -> built parts, oldest first in _cache_order.
var _cache: Dictionary = {}
var _cache_order: Array[int] = []
## Structure id -> {"task": int (NOT_STARTED while queued), "key": int, "out": Dictionary,
## "structure", "ground" (until a worker takes it)} for the build in flight.
var _jobs: Dictionary = {}
## Structure id -> {"structure": Structure, "key": int, "ground": MapDocument}: the newest edit
## that arrived while the id's build was still running. It starts when that build lands (which
## shows its older result meanwhile), so a drag faster than a build still sees the building move
## at the build's pace instead of waiting for the pointer to stop (struct_perf: a 20 by 16 m
## courtyard takes 100 to 200 ms, and 40 previews at 10 Hz landed none).
var _pending: Dictionary = {}
## Tasks whose result a newer edit replaced; reaped when they finish.
var _stale: PackedInt64Array = PackedInt64Array()
var _reported: Dictionary = {}
## Decor row id -> {"source": instance id of the library's mesh, "mesh": its wind-dressed copy}.
var _decor_meshes: Dictionary = {}
## Surface key -> the ShaderMaterial the baked decor surfaces of that key share.
var _decor_baked_materials: Dictionary = {}
## Landed builds whose node is not made yet, at most one per structure id.
var _installs := StructureInstallQueue.new()
## Counts the builds started; a later build has a higher number (its install goes first).
var _seq: int = 0
## The decor info (_decor_info) of the batch being installed or launched, {} outside one.
var _info: Dictionary = {}


## The structures of `doc` as nodes, from `built` (StructureGeometry.build(doc), which a loader's
## worker ran) or, when that is empty, from a build on the calling thread.
## With `staged` the nodes are not made here: the builds wait in the install queue and _process
## makes them INSTALL_BUDGET_MS a frame (install_pending() or flush() make them at once), so a
## load of 128
## structures holds no frame; the collision of a structure exists once its node does.
static func create(
	doc: MapDocument,
	built: Dictionary = {},
	root: String = PaletteLibrary.DEFAULT_ROOT,
	staged: bool = false
) -> AuthoredStructures:
	StructureRecipes.ensure_served()
	var structures := AuthoredStructures.new()
	structures.name = NODE_NAME
	structures._palette_root = root
	# Parts a loader built with another decor setting (the library was not served yet) are rebuilt.
	var decor := StructureDecor.available(root)
	var info := structures._decor_info() if decor else {}
	structures._info = info
	var fresh := not built.is_empty() and bool(built.get("decor", false)) == decor
	var made := built if fresh else StructureGeometry.build(doc, true, decor, info)
	var list: Array = made.get("structures", [])
	if decor:
		# A loader's worker could not read the library: place the plants of its parts now, as a group.
		StructureDecor.plan_missing(list, info, load_threads())
	var keys := StructureGeometry.keys_of(doc, decor)
	if staged:
		structures._stage(doc, list, keys)
	else:
		structures.apply(made)
		structures._keys = keys
	for k in mini(doc.structures.size(), list.size()):
		structures._cache_put(keys[doc.structures[k].id], list[k])
	structures._info = {}
	return structures


## The AuthoredStructures under map root `root`, created there (empty) if missing.
static func of_map(root: Node3D) -> AuthoredStructures:
	var structures := root.get_node_or_null(NODE_NAME) as AuthoredStructures
	if structures == null:
		structures = AuthoredStructures.new()
		structures.name = NODE_NAME
		root.add_child(structures)
	return structures


## The AuthoredStructures under map root `root`, created if missing, brought up to `doc`.
static func refresh_map(root: Node3D, doc: MapDocument) -> AuthoredStructures:
	var structures := of_map(root)
	structures.refresh(doc)
	return structures


## The collision bodies' RIDs of the structures under map root `root` (none: []), for a ray that
## must see the ground under them.
static func exclude_of(root: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if root == null:
		return rids
	var structures := root.get_node_or_null(NODE_NAME) as AuthoredStructures
	if structures != null:
		rids = structures.body_rids()
	return rids


## The kinds of `requested` ornaments that structure `structure_id` of the map under `root` was
## built without (they found no room), by ProcgenOrnaments.missing_kinds on its build's placed
## kinds. [] while the structure has no built node yet (its build is still on a worker).
static func missing_kinds_in(root: Node, structure_id: int, requested: Array) -> Array[String]:
	var structures := (
		root.get_node_or_null(NODE_NAME) as AuthoredStructures if root != null else null
	)
	if structures == null or not structures._details.has(structure_id):
		return [] as Array[String]
	var placed: Array = (structures._details[structure_id] as Dictionary).get("placed_kinds", [])
	var held := {}
	for kind: Variant in placed:
		held[str(kind)] = true
	var out: Array[String] = []
	for entry: Variant in requested:
		var kind := str(entry)
		if kind != "" and not held.has(kind) and not out.has(kind):
			out.append(kind)
	return out


## Brings the nodes up to `doc`: frees the nodes of structures that left, makes (from the cache, or
## from a build on the calling thread when `use_workers` is false or the node is outside the tree)
## or queues (on a worker) the node of every structure whose key differs from the one its node was
## built with. A queued build lands within a few frames (_process), or at once with flush().
func refresh(doc: MapDocument, use_workers: bool = true) -> void:
	StructureRecipes.ensure_served()
	var decor := _decor()
	var keys := StructureGeometry.keys_memoised(doc, _key_memo, decor)
	var changed := false
	for child in get_children():
		if not keys.has(_id_of(child)):
			_free_structure_node(_id_of(child))
			changed = true
	for id: int in _jobs.keys():
		if not keys.has(id):
			_drop_job(id)
	_installs.retain(keys)
	_info = {}
	var rebuilt := 0
	var ground: MapDocument = null
	for structure in doc.structures:
		var key: int = keys[structure.id]
		var shown: bool = (
			_keys.get(structure.id) == key and get_structure_node(structure.id) != null
		)
		if shown:
			# The edit went back to what is on show: a build in flight is obsolete.
			_drop_job(structure.id)
			continue
		if _jobs.has(structure.id) and _jobs[structure.id].key == key:
			# The newest edit is the one running: anything queued behind it is obsolete.
			_pending.erase(structure.id)
			continue
		if _pending.has(structure.id) and _pending[structure.id].key == key:
			continue
		var cached: Variant = _cache.get(key)
		if cached is Dictionary:
			_drop_job(structure.id)
			_install(structure.id, key, cached)
			rebuilt += 1
			changed = true
		elif use_workers and is_inside_tree():
			if ground == null:
				ground = StructureGeometry.ground_snapshot(doc)
			_start(structure.copy(), key, ground)
		else:
			_drop_job(structure.id)
			var parts := StructureGeometry.build_one(
				doc, structure, decor, _info_now() if decor else {}
			)
			_cache_put(key, parts)
			_install(structure.id, key, parts)
			rebuilt += 1
			changed = true
	_info = {}
	builds += rebuilt
	last_rebuilt = rebuilt
	if changed:
		_recompute_top()
		version += 1


## Replaces every child with the structures `built` (StructureGeometry.build()). The keys are
## cleared; the next refresh() rebuilds every structure unless create() seeded them.
func apply(built: Dictionary) -> void:
	for id: int in _jobs.keys():
		_drop_job(id)
	_installs.clear()
	for child in get_children():
		remove_child(child)
		child.free()
	_keys.clear()
	_tops.clear()
	_details.clear()
	for parts: Dictionary in built.get("structures", []):
		_add_node(int(parts.id), parts)
	_info = {}
	_recompute_top()
	version += 1


## Waits for every build in flight and makes its node. Returns how many nodes it made.
func flush() -> int:
	var made := 0
	# A landing may start the edit queued behind it, so go round until nothing is in flight; an
	# older result with a newer edit behind it is not shown (the caller wants the final state).
	while not _jobs.is_empty():
		_launch_queued(1 << 30)
		for id: int in _jobs.keys():
			var job: Dictionary = _jobs[id]
			WorkerThreadPool.wait_for_task_completion(job.task)
			made += _land(id, not _pending.has(id))
	_reap_stale(true)
	made += _install_queued(1 << 30)
	_info = {}
	if made > 0:
		_recompute_top()
		version += 1
		builds += made
		last_rebuilt = made
		built.emit(made)
	return made


## How many builds are in flight or landed and waiting for their node.
func pending_count() -> int:
	return _jobs.size() + _installs.size()


## True when structure `id` has a node (the install queue serves a replacement first).
func _standing(id: int) -> bool:
	return get_structure_node(id) != null


## Makes the nodes of the landed builds waiting in the install queue, up to `budget_ms` of work
## (at least one), edits and prioritize()d ones first. Returns how many it made.
func install_pending(budget_ms: float = INSTALL_BUDGET_MS) -> int:
	var made := _install_queued(budget_ms)
	_info = {}
	if made > 0:
		_recompute_top()
		version += 1
		builds += made
		last_rebuilt = made
		built.emit(made)
	return made


## Moves the queued install of structure `structure_id` (if any) to the front of the line: the
## structure the player has selected or is dragging should not wait behind a burst of new ones.
func prioritize(structure_id: int) -> void:
	_installs.prioritize(structure_id)


## The key each structure's node was built with (id -> key; tests).
func keys() -> Dictionary:
	return _keys.duplicate()


## How many built results the cache holds.
func cache_size() -> int:
	return _cache.size()


## top_y in world space (the node's global transform), or -INF with none.
func world_top() -> float:
	if top_y == -INF:
		return -INF
	if not is_inside_tree():
		return top_y
	return (global_transform * Vector3(0.0, top_y, 0.0)).y


## Every structure's collision body RID.
func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child in get_children():
		var body := child.get_node_or_null(^"Collision") as StaticBody3D
		if body != null:
			rids.append(body.get_rid())
	return rids


## The node of structure `structure_id`, or null.
func get_structure_node(structure_id: int) -> Node3D:
	return get_node_or_null(NodePath("Structure_%d" % structure_id)) as Node3D


## The final layout of structure `structure_id`'s build (ProcgenBuildingLayout: volumes, openings
## with slot provenance), or null.
func layout_of(structure_id: int) -> ProcgenBuildingLayout:
	return (_details.get(structure_id, {}) as Dictionary).get("layout") as ProcgenBuildingLayout


## The openings (doors and windows as oriented boxes) of structure `structure_id`'s build.
func openings_of(structure_id: int) -> Array:
	return (_details.get(structure_id, {}) as Dictionary).get("openings", [])


## The provenance path (node id, then slot path) that made triangle `triangle` of the surface
## `surface` of structure `structure_id`'s mesh `mesh_name`, or "".
func provenance_at(structure_id: int, mesh_name: String, triangle: int) -> String:
	var node := get_structure_node(structure_id)
	# A windmill's turning meshes sit under its Mill and Wheel pivots (names "cap_...",
	# "wheel_...").
	var instance := node.find_child(mesh_name, true, false) as MeshInstance3D if node else null
	if instance == null:
		return ""
	var tags: PackedInt32Array = instance.get_meta(TAGS_META, PackedInt32Array())
	var table: PackedStringArray = node.get_meta(TAGS_META, PackedStringArray())
	var arrays := instance.mesh.surface_get_arrays(0)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if triangle < 0 or triangle * 3 >= indices.size():
		return ""
	var tag := tags[indices[triangle * 3]]
	return table[tag] if tag >= 0 and tag < table.size() else ""


func _process(_delta: float) -> void:
	for id: int in _jobs.keys():
		var task: int = _jobs[id].task
		if task != NOT_STARTED and WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			_land(id, true, true)
	_launch_queued(max_running())
	_reap_stale(false)
	install_pending(INSTALL_BUDGET_MS)
	if _jobs.is_empty() and _stale.is_empty() and _installs.is_empty():
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A task holds only its own copies, but never leave one running past its owner.
		for id: int in _jobs.keys():
			if _jobs[id].task != NOT_STARTED:
				WorkerThreadPool.wait_for_task_completion(_jobs[id].task)
		for task in _stale:
			WorkerThreadPool.wait_for_task_completion(task)


## Queues the build of `structure` (a private copy) at `key`. While a build of the same id is
## running the edit waits behind it (_pending), replacing any older waiting edit: at most one
## build per structure runs and one waits, and the newest edit always gets its turn.
func _start(structure: Structure, key: int, ground: MapDocument) -> void:
	if _jobs.has(structure.id) and _jobs[structure.id].task != NOT_STARTED:
		_pending[structure.id] = {"structure": structure, "key": key, "ground": ground}
		set_process(true)
		return
	# A build still queued (no worker has it) is simply replaced by the newer edit, keeping its
	# place in the queue: every add changes the keys of the dozen structures around it, and a
	# queue of 100 would otherwise build each of them once per neighbour added.
	_pending.erase(structure.id)
	_seq += 1
	_jobs[structure.id] = {
		"task": NOT_STARTED,
		"key": key,
		"out": {},
		"structure": structure,
		"ground": ground,
		"seq": _seq
	}
	_launch_queued(max_running())
	set_process(true)


## How many builds may run at once: a sixth of the logical cores, at least 2. Builds on every core
## left the main thread 14 times slower while they ran (struct_perf2, 24 threads: a 4 ms refresh
## took 57 ms; builds allocate heavily and the main thread waits on the same locks and cores), so
## 100 sequential adds stalled the editor for seconds. 4 builds at once (24 cores) keep an add at
## 2 to 8 ms and finish 100 builds in about 2.6 s, against 2.5 s with every core.
static func max_running() -> int:
	return maxi(2, OS.get_processor_count() / 6)


## How many threads a load's group build (StructureGeometry.build) may use: a quarter of the logical
## cores, at least 2. Measured on 24 cores for 100 structures: 3.1 s on one thread, 0.90 s on 6,
## 1.16 s on 3 and 1.37 s on 12 or 24 (more threads only fight over the allocator).
static func load_threads() -> int:
	return maxi(2, OS.get_processor_count() / 4)


## Starts queued builds (task NOT_STARTED, oldest first) until `limit` are running.
func _launch_queued(limit: int) -> void:
	var running := 0
	var decor := _decor()
	var info: Dictionary = {}
	for job: Dictionary in _jobs.values():
		if job.task != NOT_STARTED and not WorkerThreadPool.is_task_completed(job.task):
			running += 1
	for id: int in _jobs.keys():
		if running >= limit:
			return
		var job: Dictionary = _jobs[id]
		if job.task != NOT_STARTED:
			continue
		var out: Dictionary = job.out
		var structure: Structure = job.structure
		var ground: MapDocument = job.ground
		if decor and info.is_empty():
			info = _info_now()
		job.task = WorkerThreadPool.add_task(
			func() -> void:
				out["parts"] = StructureGeometry.build_one(ground, structure, decor, info),
			false,
			"AuthoredStructures %d" % id
		)
		job.erase("structure")
		job.erase("ground")
		running += 1


## Forgets the build in flight for `id`; its task is reaped later.
func _drop_job(id: int) -> void:
	_pending.erase(id)
	_installs.erase(id)
	if not _jobs.has(id):
		return
	if _jobs[id].task != NOT_STARTED:
		_stale.append(_jobs[id].task)
	_jobs.erase(id)


func _reap_stale(wait: bool) -> void:
	var keep := PackedInt64Array()
	for task in _stale:
		if wait or WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			keep.append(task)
	_stale = keep


## Makes the node of the finished job of `id` (unless `install` is false: the result is only
## cached), then starts the edit that waited behind it. 1 when it made a node, else 0. With `defer`
## the node is not made here: the result joins the install queue (_process makes it within the frame
## budget) and this returns 0.
func _land(id: int, install: bool = true, defer: bool = false) -> int:
	var job: Dictionary = _jobs[id]
	_jobs.erase(id)
	var made := 0
	var parts: Variant = (job.out as Dictionary).get("parts")
	if parts is Dictionary:
		_cache_put(job.key, parts)
		if install and defer:
			_enqueue(id, job.key, parts, int(job.get("seq", 0)))
		elif install:
			_install(id, job.key, parts)
			made = 1
	if _pending.has(id):
		var next: Dictionary = _pending[id]
		_pending.erase(id)
		_start(next.structure, next.key, next.ground)
	return made


## Puts a landed build in the install queue (replacing the one of the same id).
func _enqueue(id: int, key: int, parts: Dictionary, seq: int) -> void:
	_installs.push(id, key, parts, seq)
	set_process(true)


## Makes the nodes of queued installs, the best ranked first (StructureInstallQueue), until
## `budget_ms` is spent (one at least).
func _install_queued(budget_ms: float) -> int:
	var made := 0
	var started := Time.get_ticks_usec()
	while not _installs.is_empty():
		var chosen: Dictionary = _installs.pop_best(_standing)
		_install(int(chosen.id), int(chosen.key), chosen.parts)
		made += 1
		if (Time.get_ticks_usec() - started) / 1000.0 >= budget_ms:
			break
	return made


## Queues the nodes of `list` (the parts of doc's structures in order, `keys` their keys) for
## installing within the frame budget (create's `staged`).
func _stage(doc: MapDocument, list: Array, keys: Dictionary) -> void:
	_installs.clear()
	for k in mini(doc.structures.size(), list.size()):
		var id := doc.structures[k].id
		_installs.push(id, keys[id], list[k], k)
	set_process(not _installs.is_empty())


func _install(id: int, key: int, parts: Dictionary) -> void:
	_installs.erase(id)
	_free_structure_node(id)
	_add_node(id, parts)
	_keys[id] = key
	_note(id, key, parts)


func _add_node(id: int, parts: Dictionary) -> void:
	add_child(_structure_node(id, parts))
	_tops[id] = float(parts.top)
	_details[id] = {
		"layout": parts.get("layout"),
		"openings": parts.get("openings", []),
		"placed_kinds": parts.get("placed_kinds", [])
	}


## Logs a refused or over-soft-budget build once per build, and keeps the text in `notes`.
func _note(id: int, key: int, parts: Dictionary) -> void:
	var text := String(parts.get("problem", ""))
	if text == "":
		text = String(parts.get("warning", ""))
	if text == "":
		notes.erase(id)
		return
	notes[id] = text
	if not _reported.has(key):
		_reported[key] = true
		push_warning(
			"AuthoredStructures: structure %d (%s): %s" % [id, parts.get("recipe", ""), text]
		)


func _cache_put(key: int, parts: Dictionary) -> void:
	if _cache.has(key):
		_cache_order.erase(key)
	_cache[key] = parts
	_cache_order.append(key)
	while _cache_order.size() > CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())


## The structure id a `Structure_<id>` node carries (-1 for any other child).
static func _id_of(node: Node) -> int:
	var node_name := String(node.name)
	if not node_name.begins_with("Structure_"):
		return -1
	return int(node_name.trim_prefix("Structure_"))


func _free_structure_node(id: int) -> void:
	var node := get_structure_node(id)
	if node != null:
		remove_child(node)
		node.free()
	_tops.erase(id)
	_details.erase(id)
	_keys.erase(id)


func _recompute_top() -> void:
	top_y = -INF
	for top in _tops.values():
		top_y = maxf(top_y, float(top))


func _structure_node(id: int, parts: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Structure_%d" % id
	var style: String = parts.get("style", "")
	var tone: String = parts.get("stone_tone", "")
	var meshes: Array = parts.get("meshes", [])
	# A weathervane's arrow, shaft and tail turn in the wind (StructureVane): they leave the static
	# meshes.
	var vane := StructureVane.split(meshes, parts.get("tag_table", PackedStringArray()))
	if not vane.is_empty():
		meshes = vane.rest
	for mesh: Dictionary in meshes:
		node.add_child(_mesh_instance(mesh, "", style, tone))
	if not vane.is_empty():
		node.add_child(vane_node(vane, style, tone))
	var mill: Dictionary = parts.get("mill", {})
	if not mill.is_empty():
		node.add_child(mill_node(mill, int(parts.get("id", 0)), style, tone))
	node.set_meta(TAGS_META, parts.get("tag_table", PackedStringArray()))
	_add_dressing(node, parts.get("dressing", {}))
	_add_decor(node, parts)
	var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
	# The decks, stair treads, platforms and piles procgen gives no collision (StructureWalkable).
	faces = faces + (parts.get("walkable", PackedVector3Array()) as PackedVector3Array)
	if not faces.is_empty():
		node.add_child(_body(faces, id))
	return node


## One mesh dictionary (StructureGeometry) as a MeshInstance3D with the shared material of its kind
## and role; `prefix` goes before its name.
func _mesh_instance(
	mesh: Dictionary, prefix: String, style: String, tone: String
) -> MeshInstance3D:
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.arrays)
	array_mesh.surface_set_material(0, _material(String(mesh.kind), String(mesh.role), style, tone))
	var instance := MeshInstance3D.new()
	instance.name = "%s%s_%s" % [prefix, mesh.role, mesh.kind]
	instance.mesh = array_mesh
	if mesh.role == StructureLook.OPENING:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(TAGS_META, mesh.tags)
	return instance


## A windmill's turning parts (StructureMill.split's `mill`, without "rest") as a MillMotion node
## named "Mill": it stands at the tower's centre and holds the cap meshes (prefix "cap_") and its
## child "Wheel", which stands at the hub and holds the sail meshes (prefix "wheel_"). The meshes
## keep their map-frame vertices and sit at minus the pivot, so the pose at rest is the built one.
func mill_node(mill: Dictionary, seed_value: int, style: String, tone: String) -> MillMotion:
	var centre: Vector3 = mill.centre
	var hub: Vector3 = mill.hub
	var pivot := MillMotion.new()
	pivot.name = "Mill"
	pivot.position = centre
	var wheel := Node3D.new()
	wheel.name = "Wheel"
	wheel.position = hub - centre
	pivot.add_child(wheel)
	var reach := 0.0
	var cap_box := AABB()
	var boxed := false
	for mesh: Dictionary in mill.get("cap", []):
		var instance := _mesh_instance(mesh, "cap_", style, tone)
		instance.position = -centre
		pivot.add_child(instance)
		var box := instance.get_aabb()
		box.position += instance.position
		cap_box = box if not boxed else cap_box.merge(box)
		boxed = true
	for mesh: Dictionary in mill.get("wheel", []):
		var instance := _mesh_instance(mesh, "wheel_", style, tone)
		instance.position = -hub
		wheel.add_child(instance)
		for vertex: Vector3 in mesh.arrays[Mesh.ARRAY_VERTEX]:
			reach = maxf(reach, vertex.distance_to(hub))
	# Everything the pose can reach, in the pivot's frame: the cap and a ball round the hub.
	var swing := AABB(wheel.position - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = swing.merge(cap_box) if boxed else swing
	notifier.screen_entered.connect(pivot.on_screen_entered)
	notifier.screen_exited.connect(pivot.on_screen_exited)
	pivot.add_child(notifier)
	pivot.setup(wheel, mill.axis, seed_value)
	return pivot


## A weathervane's turning parts (StructureVane.split's `turning`) as a VaneMotion node "Vane" at
## the pole, its meshes at minus the pivot (the pose at rest is the built one), with a notifier so
## it only moves on screen.
func vane_node(vane: Dictionary, style: String, tone: String) -> VaneMotion:
	var pivot := VaneMotion.new()
	pivot.name = "Vane"
	pivot.position = vane.pivot
	for mesh: Dictionary in vane.turning:
		var instance := _mesh_instance(mesh, "vane_", style, tone)
		instance.position = -(vane.pivot as Vector3)
		pivot.add_child(instance)
	var notifier := VisibleOnScreenNotifier3D.new()
	notifier.aabb = AABB(Vector3(-1.2, -0.6, -1.2), Vector3(2.4, 1.2, 2.4))
	notifier.screen_entered.connect(pivot.on_screen_entered)
	notifier.screen_exited.connect(pivot.on_screen_exited)
	pivot.add_child(notifier)
	pivot.setup(vane.tip)
	return pivot


## What the pure decor work reads from the library, made on the main thread (the wind-dressed
## meshes are main-thread resources): {"rows" (AssetStore.decor_rows), "by_id", "cost" (id ->
## triangles of its mesh, 0 without one), "sig" (a hash of rows and costs: a plan made from another
## state is made again)}.
func _decor_info() -> Dictionary:
	var rows := AssetStore.decor_rows(_palette_root)
	var by_id := {}
	var cost := {}
	for row in rows:
		by_id[row.id] = row
		cost[row.id] = int(_decor_entry(row).get("tris", 0))
	return {"rows": rows, "by_id": by_id, "cost": cost, "sig": hash([rows, cost])}


## The decor info of the batch in hand, made once per batch (refresh, install, flush, create).
func _info_now() -> Dictionary:
	if _info.is_empty():
		_info = _decor_info()
	return _info


## True when the library serves decor plants: structures are then built with `soft: "anchors"`.
func _decor() -> bool:
	return plants and StructureDecor.available(_palette_root)


## The decor plants of a structure (StructureDecor.placements on its anchors), baked into one
## MeshInstance3D "decor_baked" with a surface per material kind (leaf, bark, planter parts), so a
## decorated building draws 2 to 4 surfaces instead of a MultiMesh per asset (7 to 8 nodes, 14 or
## more draws). Shadows off, dressed with the wind shader of its category as AssetStore.instance()
## dresses a library asset (shared materials; the vertex weights carry each asset's mesh_height).
## Freed with the node.
func _add_decor(node: Node3D, parts: Dictionary) -> void:
	if not bool(parts.get("decor", false)):
		return
	var anchors: Array[Dictionary] = []
	anchors.assign(parts.get("anchors", []))
	if anchors.is_empty():
		return
	var info := _info_now()
	var by_id: Dictionary = info.by_id
	# The placement, the cap of StructureDecor.MAX_TRIANGLES plants a structure (the lowest-value
	# anchors go first) and the grouping are pure: a build worker made them (parts.decor_plan,
	# perf3); a plan from another library state, or none (a synchronous or loader build), is made here.
	var plan: Dictionary = parts.get("decor_plan", {})
	if plan.is_empty() or int(plan.sig) != int(info.sig):
		plan = StructureDecor.plan(anchors, info.rows, info.cost, int(info.sig))
	var groups: Dictionary = plan.groups
	var ids: Array = plan.ids
	# Plants whose asset can be baked (every surface a wind material with vertex weights) go into
	# one mesh a structure draws once per surface kind; the rest keep a MultiMesh each.
	var baked: Array[Dictionary] = []
	var sources := {}
	for id: String in ids:
		var row: Dictionary = by_id[id]
		var entry := _decor_entry(row)
		if entry.is_empty():
			continue
		var group: Array[Dictionary] = groups[id]
		if not (entry.bake as Array).is_empty():
			sources[id] = entry.bake
			for placement in group:
				(
					baked
					. append(
						{
							"id": id,
							"transform": placement.transform,
							"under": bool(placement.get("under", false)),
						}
					)
				)
			continue
		var transforms: Array[Transform3D] = []
		for placement in group:
			transforms.append(placement.transform)
		_add_decor_multimesh(node, row, entry.mesh as Mesh, transforms)
	if baked.is_empty():
		return
	var array_mesh := ArrayMesh.new()
	for surface: Dictionary in StructureDecor.bake(baked, sources):
		array_mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, StructureDecor.mesh_arrays(surface)
		)
		array_mesh.surface_set_material(
			array_mesh.get_surface_count() - 1, _decor_baked_materials[surface.key]
		)
	var instance := MeshInstance3D.new()
	instance.name = DECOR_NODE
	instance.mesh = array_mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(&"wind_foliage_category", StructureDecor.category_of(by_id, ids))
	node.add_child(instance)


## One MultiMeshInstance3D for `transforms` of `mesh` (a decor asset that cannot be baked).
func _add_decor_multimesh(
	node: Node3D, row: Dictionary, mesh: Mesh, transforms: Array[Transform3D]
) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "decor_%s" % row.local
	instance.multimesh = multi
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(&"wind_foliage_category", row.wind_category)
	node.add_child(instance)


## The wind-dressed mesh of a decor row, shared by every structure of this node.
func _decor_mesh(row: Dictionary) -> Mesh:
	return _decor_entry(row).get("mesh")


## What a decor row keeps once per library asset: {"mesh" (wind-dressed copy, for a MultiMesh),
## "tris" (its triangles), "bake" (the surfaces StructureDecor.bake takes, empty when the asset
## cannot be baked)}; {} when the library has no mesh for it. Rebuilt when the library's mesh is.
func _decor_entry(row: Dictionary) -> Dictionary:
	var source := AssetStore.mesh(str(row.library), str(row.id), _palette_root)
	if source == null:
		return {}
	var held: Variant = _decor_meshes.get(row.id)
	if held is Dictionary and held.source == source.get_instance_id():
		return held
	var copy := source.duplicate() as Mesh
	WindFoliage.apply_material(copy, str(row.wind_category))
	var entry := {
		"source": source.get_instance_id(),
		"mesh": copy,
		"tris": StructureDecor.triangles_of(copy),
		"bake": _bake_surfaces(copy, str(row.wind_category)),
	}
	_decor_meshes[row.id] = entry
	return entry


## `mesh`'s surfaces as StructureDecor.bake's sources, each with the key of the material it
## shares (registering that material in _decor_baked_materials); empty when a surface is not a
## wind material with vertex weights, positions, normals, colours, UVs and an index (the asset then
## keeps its MultiMesh, so nothing about how it sways can change).
func _bake_surfaces(mesh: Mesh, category: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for surface in mesh.get_surface_count():
		var material := mesh.surface_get_material(surface) as ShaderMaterial
		var arrays := mesh.surface_get_arrays(surface)
		if (
			material == null
			or not bool(material.get_shader_parameter("use_vertex_wind"))
			or not arrays[Mesh.ARRAY_COLOR] is PackedColorArray
			or not arrays[Mesh.ARRAY_NORMAL] is PackedVector3Array
			or not arrays[Mesh.ARRAY_TEX_UV] is PackedVector2Array
			or not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array
		):
			return [] as Array[Dictionary]
		var key := (
			"%s|%s|%s"
			% [category, material.shader.resource_path, StructureDecor.texture_key(material)]
		)
		if not _decor_baked_materials.has(key):
			var shared := material.duplicate() as ShaderMaterial
			shared.set_shader_parameter("mesh_height", StructureDecor.BAKE_MESH_HEIGHT)
			_decor_baked_materials[key] = shared
		(
			out
			. append(
				{
					"key": key,
					"vertices": arrays[Mesh.ARRAY_VERTEX],
					"normals": arrays[Mesh.ARRAY_NORMAL],
					"colors":
					StructureDecor.baked_colors(
						arrays[Mesh.ARRAY_COLOR],
						float(material.get_shader_parameter("mesh_height"))
					),
					"uvs": arrays[Mesh.ARRAY_TEX_UV],
					"indices": arrays[Mesh.ARRAY_INDEX],
				}
			)
		)
	return out


## The yard of a building (StructureDressing): the soft ground patch and path (no shadow) and the
## plants and slabs along the walls. Shared materials, no collision.
func _add_dressing(node: Node3D, dressing: Dictionary) -> void:
	for part: String in ["ground", "props"]:
		var mesh: Dictionary = (dressing as Dictionary).get(part, {})
		if mesh.is_empty():
			continue
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.arrays)
		var key := "dressing:%s" % part
		if not _materials.has(key):
			_materials[key] = (
				StructureMaterials.dressing_ground()
				if part == "ground"
				else StructureMaterials.dressing_props()
			)
		array_mesh.surface_set_material(0, _materials[key])
		var instance := MeshInstance3D.new()
		instance.name = "dressing_%s" % part
		instance.mesh = array_mesh
		if part == "ground":
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(instance)


static func _body(faces: PackedVector3Array, structure_id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = WaterSurface.TERRAIN_LAYER
	body.collision_mask = 0
	body.input_ray_pickable = false
	body.set_meta(STRUCTURE_META, structure_id)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision)
	return body


# --- materials ---------------------------------------------------------------------------


## The material of surface `kind` in `role` for a structure of style `style` (StructureMaterials:
## the painterly wall and roof shaders over the rock's masonry and the planks), one shared per
## triple (masonry also by the style's `stone_tone` hint).
func _material(kind: String, role: String, style: String, tone: String = "") -> Material:
	var key := "%s:%s:%s" % [kind, role, style]
	if kind == "masonry" and tone != "":
		key += ":" + tone
	if not _materials.has(key):
		_materials[key] = StructureMaterials.make(kind, role, style, _palette_root, tone)
	return _materials[key]


## Resource paths of every palette texture the structures of `doc` bind (the loader requests them on
## background threads with the ground's): the planks, and each style's rock.
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var surfaces := PaletteLibrary.surfaces(root)
	var names := {}
	for structure in doc.structures:
		names[LibraryBindings.crossing_planks()] = true
		names[AuthoredCrossings.stone_surface(structure.style, root)] = true
	var paths := PackedStringArray()
	for surface_name in names:
		var surface: Dictionary = surfaces.get(surface_name, {})
		for key in ["albedo", "normal", "orm"]:
			var relative: Variant = surface.get(key, "")
			if (
				relative is String
				and relative != ""
				and not SurfaceStore.is_library_path(root, relative)
			):
				paths.append(root.path_join(relative))
	return paths
