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

## Highest structure top, map Y (-INF with none), and a counter that changes with every rebuild.
var top_y: float = -INF
var version: int = 0
## How many structures this node has built (or taken from a cache) since it was made, and how many
## the last refresh() changed (tests count what an edit rebuilt).
var builds: int = 0
var last_rebuilt: int = 0
## Problems and budget notes of the builds installed so far (also logged), id -> text.
var notes: Dictionary = {}

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _materials: Dictionary = {}
## Per structure id, the StructureGeometry key its node was built from.
var _keys: Dictionary = {}
var _tops: Dictionary = {}
## Per structure id, {"layout", "openings"} of its build (the day a vision rule needs them).
var _details: Dictionary = {}
## Key -> built parts, oldest first in _cache_order.
var _cache: Dictionary = {}
var _cache_order: Array[int] = []
## Structure id -> {"task": int, "key": int, "out": Dictionary} for the build in flight.
var _jobs: Dictionary = {}
## Tasks whose result a newer edit replaced; reaped when they finish.
var _stale: PackedInt64Array = PackedInt64Array()
var _reported: Dictionary = {}


## The structures of `doc` as nodes, from `built` (StructureGeometry.build(doc), which a loader's
## worker ran) or, when that is empty, from a build on the calling thread.
static func create(
	doc: MapDocument, built: Dictionary = {}, root: String = PaletteLibrary.DEFAULT_ROOT
) -> AuthoredStructures:
	StructureRecipes.ensure_served()
	var structures := AuthoredStructures.new()
	structures.name = NODE_NAME
	structures._palette_root = root
	var made := built if not built.is_empty() else StructureGeometry.build(doc)
	structures.apply(made)
	var keys := StructureGeometry.keys_of(doc)
	structures._keys = keys
	var list: Array = made.get("structures", [])
	for k in mini(doc.structures.size(), list.size()):
		structures._cache_put(keys[doc.structures[k].id], list[k])
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


## Brings the nodes up to `doc`: frees the nodes of structures that left, makes (from the cache, or
## from a build on the calling thread when `use_workers` is false or the node is outside the tree)
## or queues (on a worker) the node of every structure whose key differs from the one its node was
## built with. A queued build lands within a few frames (_process), or at once with flush().
func refresh(doc: MapDocument, use_workers: bool = true) -> void:
	StructureRecipes.ensure_served()
	var keys := StructureGeometry.keys_of(doc)
	var changed := false
	for child in get_children():
		if not keys.has(_id_of(child)):
			_free_structure_node(_id_of(child))
			changed = true
	for id: int in _jobs.keys():
		if not keys.has(id):
			_drop_job(id)
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
			var parts := StructureGeometry.build_one(doc, structure)
			_cache_put(key, parts)
			_install(structure.id, key, parts)
			rebuilt += 1
			changed = true
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
	for child in get_children():
		remove_child(child)
		child.free()
	_keys.clear()
	_tops.clear()
	_details.clear()
	for parts: Dictionary in built.get("structures", []):
		_add_node(int(parts.id), parts)
	_recompute_top()
	version += 1


## Waits for every build in flight and makes its node. Returns how many nodes it made.
func flush() -> int:
	var made := 0
	for id: int in _jobs.keys():
		var job: Dictionary = _jobs[id]
		WorkerThreadPool.wait_for_task_completion(job.task)
		made += _land(id)
	_reap_stale(true)
	if made > 0:
		_recompute_top()
		version += 1
		builds += made
		last_rebuilt = made
		built.emit(made)
	return made


## How many builds are in flight.
func pending_count() -> int:
	return _jobs.size()


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
	var instance := node.get_node_or_null(NodePath(mesh_name)) as MeshInstance3D if node else null
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
	var made := 0
	for id: int in _jobs.keys():
		if WorkerThreadPool.is_task_completed(_jobs[id].task):
			WorkerThreadPool.wait_for_task_completion(_jobs[id].task)
			made += _land(id)
	_reap_stale(false)
	if made > 0:
		_recompute_top()
		version += 1
		builds += made
		last_rebuilt = made
		built.emit(made)
	if _jobs.is_empty() and _stale.is_empty():
		set_process(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# A task holds only its own copies, but never leave one running past its owner.
		for id: int in _jobs.keys():
			WorkerThreadPool.wait_for_task_completion(_jobs[id].task)
		for task in _stale:
			WorkerThreadPool.wait_for_task_completion(task)


## Queues the build of `structure` (a private copy) at `key`; an older job of the same id is
## replaced (its task finishes and is dropped).
func _start(structure: Structure, key: int, ground: MapDocument) -> void:
	_drop_job(structure.id)
	var out := {}
	var task := WorkerThreadPool.add_task(
		func() -> void: out["parts"] = StructureGeometry.build_one(ground, structure),
		false,
		"AuthoredStructures %d" % structure.id
	)
	_jobs[structure.id] = {"task": task, "key": key, "out": out}
	set_process(true)


## Forgets the build in flight for `id`; its task is reaped later.
func _drop_job(id: int) -> void:
	if not _jobs.has(id):
		return
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


## Makes the node of the finished job of `id`; 1 when it did, else 0.
func _land(id: int) -> int:
	var job: Dictionary = _jobs[id]
	_jobs.erase(id)
	var parts: Variant = (job.out as Dictionary).get("parts")
	if not parts is Dictionary:
		return 0
	_cache_put(job.key, parts)
	_install(id, job.key, parts)
	return 1


func _install(id: int, key: int, parts: Dictionary) -> void:
	_free_structure_node(id)
	_add_node(id, parts)
	_keys[id] = key
	_note(id, key, parts)


func _add_node(id: int, parts: Dictionary) -> void:
	add_child(_structure_node(id, parts))
	_tops[id] = float(parts.top)
	_details[id] = {"layout": parts.get("layout"), "openings": parts.get("openings", [])}


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
	for mesh: Dictionary in parts.get("meshes", []):
		var array_mesh := ArrayMesh.new()
		array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.arrays)
		array_mesh.surface_set_material(0, _material(String(mesh.kind), String(mesh.role), style))
		var instance := MeshInstance3D.new()
		instance.name = "%s_%s" % [mesh.role, mesh.kind]
		instance.mesh = array_mesh
		if mesh.role == StructureLook.OPENING:
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.set_meta(TAGS_META, mesh.tags)
		node.add_child(instance)
	node.set_meta(TAGS_META, parts.get("tag_table", PackedStringArray()))
	_add_dressing(node, parts.get("dressing", {}))
	var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
	# The decks, stair treads, platforms and piles procgen gives no collision (StructureWalkable).
	faces = faces + (parts.get("walkable", PackedVector3Array()) as PackedVector3Array)
	if not faces.is_empty():
		node.add_child(_body(faces, id))
	return node


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
## triple.
func _material(kind: String, role: String, style: String) -> Material:
	var key := "%s:%s:%s" % [kind, role, style]
	if not _materials.has(key):
		_materials[key] = StructureMaterials.make(kind, role, style, _palette_root)
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
