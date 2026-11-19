class_name PainterMannerHost
extends RefCounted

## Puts the hand-drawn manner (card painter-manner's choice B, the Painted default since card
## painter-manner-b) on the painted buildings: the recipe mesh cut and wandered
## (PainterMannerMesh), strokes drawn in the fragment shader along each piece's own frame
## (painter_structure_manner.gdshader). A structure procgen gives no manner records for keeps the
## A3b look PainterBuildings already put on it.
##
## Per structure, on a WorkerThreadPool task: the records (PainterMannerSource: those the
## structure's own build kept, AuthoredStructures.built_parts, else a second evaluation), the
## arrays and the moved collider. On the main thread the
## results are installed in arrival order, one step a frame (a structure's meshes, then its
## collider: about 1 ms each; one process_frame connection while any wait, none otherwise: no
## poll). The shader is loaded on a loader thread when the host is made and kept, so neither the
## first install nor a return to Painted parses it on the main thread (painter-manner-b: 37 ms):
##   a painted part's own node draws the cut mesh in the manner's material and casts no shadow; when
##   the part cast one before, a child (SHADOW) casts it from the recipe topology, wandered, so the
##   shadow pass draws what Classic drew. An opening's frames and shutters cast none in Classic and
##   none here (card painter-manner-b: the probe made every part cast, about 1.5k more shadow
##   triangles for three houses);
##   a Classic part (panes, door metal) takes the wandered mesh in place so it stays in its hole;
##   the structure's collision shape is replaced by its faces under the same field
##   (PainterMannerMesh.collider), so a click and a standing token meet the leaning house;
##   while the sheet lays snow on roofs (PainterBuildings.snow_amount above 0) a child (SNOW)
##   draws the structure's snow strips (PainterMannerSnow) and casts no shadow. Built with the
##   parts when the mood already has snow, else on a worker when a re-tone brings it (from the
##   dress job kept per structure); freed when a re-tone takes it away. No snow, nothing added.
## restore_all() puts back every mesh, override, cast setting and shape and frees what it added.

const SHADER := "res://painter/shaders/painter_structure_manner.gdshader"
const SHADOW := "MannerShadow"
const SNOW := "MannerSnow"
## The material the snow strips draw with (PainterBuildings.PICK_SNOW: a blanket's vertex colour
## names its roof's kind and paint, the strips' own code picks their branch).
const SNOW_KEY := "roof_snow"
## Mesh names that are the yard, not the building (not wandered).
const SKIP_PREFIXES: Array[String] = ["dressing", "decor", "cap_", "wheel_", "vane_"]
## The wander amplitude (metres at full height).
const AMP_M := 0.14
## The structure's collision shape (AuthoredStructures._body).
const COLLISION := "Collision/CollisionShape3D"

## True (the default) gives winter's roofs their body (the strips and the shader's blanket);
## false draws them as before card painter-roof-snow (an A/B switch for measurements). Read when
## a structure is dressed and a material made: change it, then release() and paint() again.
static var snow_body := true
## True (the default) gives a stone-walled building the mason's hand (PainterMannerMesh.hand_at);
## false builds it as before card painter-buildings-fix4 (an A/B switch for measurements, read
## when a structure is dressed).
static var hand := true

## Per structure built: {"id", "eval_ms", "source" ("build": the records came with the structure's
## parts; "eval": evaluated again), "record_bytes", "build_ms", "install_ms",
## "tris": {src, draw, shadow, snow}, "bytes", "collider": [faces before, after], "snow_ms" (the
## strips' build on the worker)}.
var stats: Array[Dictionary] = []

var _generation := 0
## Node instance id -> [mesh instance, its mesh, its cast_shadow, its material_override].
var _restore: Dictionary = {}
## CollisionShape3D instance id -> [node, its shape].
var _shapes: Dictionary = {}
## Nodes added (shadow children).
var _added: Array[Node] = []
## Structure node instance ids dressed or being built.
var _dressed: Dictionary = {}
## [material, part key] of every material made (toned by PainterBuildings).
var _materials: Array = []
var _shared: Dictionary = {}
## The PainterBuildings that owns this (weak: it holds this host, a strong ref back would be a
## cycle that leaks every material at exit).
var _owner_ref: WeakRef = null
## Job key -> WorkerThreadPool task id, until its result is installed.
var _tasks: Dictionary = {}
var _next_key := 0
## Install steps waiting for the main thread, oldest first: a result ({"job", "parts", ...}) or
## a structure's collider ({"job", "collider"}).
var _queue: Array[Dictionary] = []
var _draining := false
var _shader: Shader = null
## Whether the dressed structures carry snow strips (the last snow_amount seen above 0).
var _snow_on := false
## Bumped when the snow comes or goes: a strips result of an older one is dropped.
var _snow_gen := 0
## Structure node instance id -> its dress job (kept to build its snow strips later).
var _jobs: Dictionary = {}
## Structure node instance id -> its SNOW node.
var _snow_nodes: Dictionary = {}


func _init(buildings: PainterBuildings) -> void:
	_owner_ref = weakref(buildings)
	ResourceLoader.load_threaded_request(SHADER)


## Starts the build of `structure` (a `Structure_<id>` node); nothing when it is done or under way.
func dress(structure: Node) -> void:
	if _dressed.has(structure.get_instance_id()) or not structure.is_inside_tree():
		return
	var id := AuthoredStructures._id_of(structure)
	var doc := PainterMannerSource.document(structure.get_tree())
	var record := PainterMannerSource.structure_of(doc, id)
	if record == null:
		return
	var parts: Dictionary = {}
	for child in structure.get_children():
		var mi := child as MeshInstance3D
		if mi == null or not mi.has_meta(AuthoredStructures.TAGS_META) or _skipped(str(mi.name)):
			continue
		parts[str(mi.name)] = PainterBuildings.kind_of(str(mi.name))
	var faces := PackedVector3Array()
	var cs := structure.get_node_or_null(COLLISION) as CollisionShape3D
	if cs != null and cs.shape is ConcavePolygonShape3D:
		faces = (cs.shape as ConcavePolygonShape3D).get_faces()
	var authored := structure.get_parent()
	var decor := bool(authored.call("_decor")) if authored.has_method("_decor") else false
	var built: Dictionary = (
		authored.call("built_parts", id) if authored.has_method("built_parts") else {}
	)
	_dressed[structure.get_instance_id()] = true
	_snow_on = _snow_wanted()
	var job := {
		"node": structure.get_instance_id(),
		"doc": doc,
		"structure": record,
		"decor": decor,
		"built": built if built.has("manner") else {},
		"parts": parts,
		"faces": faces,
		"generation": _generation,
		"snow": _snow_on,
		"snow_gen": _snow_gen
	}
	_jobs[structure.get_instance_id()] = job
	_start(_work, job)


func _start(work: Callable, job: Dictionary) -> void:
	_next_key += 1
	var task := job.duplicate()
	task["key"] = _next_key
	_tasks[_next_key] = WorkerThreadPool.add_task(work.bind(task))


## Puts back every mesh, override, cast setting and shape changed and frees every node added;
## results still on their way are dropped.
func restore_all() -> void:
	_generation += 1
	for id: int in _restore:
		var entry: Array = _restore[id]
		if is_instance_valid(entry[0]):
			var mi: MeshInstance3D = entry[0]
			mi.mesh = entry[1]
			mi.cast_shadow = entry[2]
			mi.material_override = entry[3]
	_restore.clear()
	for id: int in _shapes:
		var pair: Array = _shapes[id]
		if is_instance_valid(pair[0]):
			(pair[0] as CollisionShape3D).shape = pair[1]
	_shapes.clear()
	for node in _added:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_added.clear()
	_dressed.clear()
	_materials.clear()
	_shared.clear()
	_queue.clear()
	_jobs.clear()
	_snow_nodes.clear()
	_snow_on = false


## Tones every material this made (PainterBuildings._tone with the part's kind), and builds or
## frees the snow strips when the mood brings or takes away roof snow.
func retone(sheet: Dictionary) -> void:
	var owner := _owner_ref.get_ref() as PainterBuildings
	if owner == null:
		return
	for pair: Array in _materials:
		owner._tone(pair[0], PainterBuildings.kind_of(pair[1]), sheet)
	var wanted := _snow_wanted()
	if wanted == _snow_on:
		return
	_snow_on = wanted
	_snow_gen += 1
	for id: int in _snow_nodes:
		# A structure rebuilt since its strips were made freed them with it: the entry then holds a
		# freed instance, which a typed Node variable refuses (card painter-buildings-fix4).
		var held: Variant = _snow_nodes[id]
		if is_instance_valid(held):
			var node := held as Node
			_added.erase(node)
			node.get_parent().remove_child(node)
			node.queue_free()
	_snow_nodes.clear()
	for id: int in _jobs:
		var job: Dictionary = _jobs[id]
		job["snow_gen"] = _snow_gen
		job["snow"] = _snow_on
		if _snow_on and is_instance_valid(instance_from_id(id)):
			_start(_work_snow, job)


## Whether the strips are wanted now: snow_body on and the owner's mood lays roof snow.
func _snow_wanted() -> bool:
	var owner := _owner_ref.get_ref() as PainterBuildings
	return snow_body and owner != null and owner.snow_amount() > 0.0


## The building's own two numbers (0 to 1, from its structure id) for the shader's per-building
## choices: a door's paint, a wooden roof's tone, a wall's and the straw's tint (card
## painter-look-houses3: houses of one kind looked alike). Pure; set per mesh instance, so the
## shared materials stay shared.
static func building_seed(id: Variant) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("bld:%s" % str(id))
	return Vector2(rng.randf(), rng.randf())


static func _skipped(node_name: String) -> bool:
	for prefix in SKIP_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


# ---------------------------------------------------------------- worker


func _work(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var feed := PainterMannerSource.of_parts(job.built)
	var source := "build"
	if feed.is_empty():
		feed = PainterMannerSource.evaluate(job.doc, job.structure, job.decor)
		source = "eval"
	var t1 := Time.get_ticks_usec()
	var out := {"job": job, "parts": {}, "eval_ms": (t1 - t0) / 1000.0, "source": source}
	if not feed.is_empty():
		out["record_bytes"] = var_to_bytes(job.built.get("manner", [])).size()
	if feed.is_empty():
		_arrived.call_deferred(out)
		return
	var records: Dictionary = feed.records
	var opts := _field(feed, job.structure)
	var table: PackedStringArray = feed.table
	for part_name: String in job.parts:
		var mesh: Variant = feed.meshes.get(part_name)
		if mesh == null:
			continue
		var painted := not (job.parts[part_name] as Array).is_empty()
		var part_opts := opts.duplicate()
		part_opts["cut"] = painted
		part_opts["fringe"] = painted
		var built := PainterMannerMesh.build(mesh.arrays, mesh.tags, table, records, part_opts)
		if not painted:
			built.erase("draw")
		out.parts[part_name] = built
	var faces: PackedVector3Array = job.faces
	if not faces.is_empty():
		out["collider"] = PainterMannerMesh.collider(faces, opts)
	out["build_ms"] = (Time.get_ticks_usec() - t1) / 1000.0
	if bool(job.get("snow", false)):
		_snow_of(feed, opts, out)
	_arrived.call_deferred(out)


## The snow strips of a structure dressed before its mood had snow (retone): its records again
## (with its parts, or evaluated), then the strips.
func _work_snow(job: Dictionary) -> void:
	var feed := PainterMannerSource.of_parts(job.built)
	if feed.is_empty():
		feed = PainterMannerSource.evaluate(job.doc, job.structure, job.decor)
	var out := {"job": job}
	if not feed.is_empty():
		_snow_of(feed, _field(feed, job.structure), out)
	_arrived.call_deferred(out)


## Adds the strips of `feed` under the field `opts` to `out` ("snow": arrays, "snow_tris",
## "snow_ms"). Worker-safe.
static func _snow_of(feed: Dictionary, opts: Dictionary, out: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var src := PainterMannerSnow.source(feed.records, feed.meshes, feed.table, opts)
	var built := PainterMannerSnow.build(src)
	out["snow"] = built.arrays
	out["snow_tris"] = int(built.triangles)
	out["snow_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


## The wander field of a structure from its manner feed (PainterMannerMesh.build's opts). Pure.
static func _field(feed: Dictionary, structure: Structure) -> Dictionary:
	var building: Dictionary = feed.building
	var records: Dictionary = feed.records
	var foot := float(building.get("wall_foot", 0.0))
	var eave := foot
	for rec: Dictionary in records.values():
		if str(rec["kind"]) == "wall_face":
			var top: float = (rec["origin"] as Vector3).y + float(rec["v_len"]) * (rec["v"] as Vector3).y
			eave = maxf(eave, top)
	var field := {
		"amp": AMP_M,
		"phase": PainterMannerMesh.phase_of(structure.seed_value),
		"foot": foot,
		"eave": eave,
		"walls": PainterMannerMesh.wall_normals(records),
		"door_dir": PainterMannerMesh.door_dir(records)
	}
	# A stone-walled building gets the mason's hand (card painter-buildings-fix4).
	if hand:
		field.merge(PainterMannerMesh.hand_frame(records, eave))
	return field


# ---------------------------------------------------------------- main thread


## A worker's result on the main thread: queued, and the queue drained from the next frame on.
func _arrived(out: Dictionary) -> void:
	var key := int(out.job.key)
	if _tasks.has(key):
		# Finished but for its return: waited for here so the pool never holds an unwaited task.
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
	if int(out.job.generation) != _generation:
		return
	_queue.append(out)
	var tree := Engine.get_main_loop() as SceneTree
	if not _draining and tree != null:
		_draining = true
		tree.process_frame.connect(_drain, CONNECT_ONE_SHOT)


## Installs the oldest queued step, then waits a frame for the next.
func _drain() -> void:
	_draining = false
	if not _queue.is_empty():
		var step: Dictionary = _queue.pop_front()
		if step.has("parts"):
			_install(step)
			if step.has("collider"):
				_queue.push_front({"job": step.job, "collider": step.collider})
		elif step.has("collider"):
			_install_collider(step)
		else:
			_install_snow(step)
	var tree := Engine.get_main_loop() as SceneTree
	if not _queue.is_empty() and tree != null:
		_draining = true
		tree.process_frame.connect(_drain, CONNECT_ONE_SHOT)


func _install(out: Dictionary) -> void:
	var job: Dictionary = out.job
	var structure := instance_from_id(int(job.node)) as Node3D
	if int(job.generation) != _generation or structure == null or not is_instance_valid(structure):
		return
	var t0 := Time.get_ticks_usec()
	var tris := {"src": 0, "draw": 0, "shadow": 0, "snow": 0}
	var bytes := 0
	var bld := building_seed(AuthoredStructures._id_of(structure))
	for part_name: String in out.parts:
		var mi := structure.get_node_or_null(NodePath(part_name)) as MeshInstance3D
		if mi == null:
			continue
		var built: Dictionary = out.parts[part_name]
		var shadow: Array = built.shadow
		if (shadow[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != mi.mesh.surface_get_array_len(0):
			continue
		_restore[mi.get_instance_id()] = [mi, mi.mesh, mi.cast_shadow, mi.material_override]
		var material := mi.mesh.surface_get_material(0)
		tris.src += int(built.triangles[0])
		if not built.has("draw"):
			mi.mesh = _mesh(shadow, material, 0)
			tris.draw += int(built.triangles[0])
			if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				tris.shadow += int(built.triangles[2])
			continue
		var casts := mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.mesh = _mesh(built.draw, null, PainterMannerMesh.FORMAT)
		mi.material_override = _surface_material(part_name)
		mi.set_instance_shader_parameter(&"bld", bld)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tris.draw += int(built.triangles[1])
		bytes += _bytes(built.draw, 56)
		if casts:
			_child(mi, SHADOW, _mesh(shadow, material, 0))
			tris.shadow += int(built.triangles[2])
			bytes += _bytes(shadow, 32)
	(
		stats
		. append(
			{
				"id": AuthoredStructures._id_of(structure),
				"eval_ms": out.eval_ms,
				"source": out.get("source", ""),
				"record_bytes": out.get("record_bytes", 0),
				"build_ms": out.get("build_ms", 0.0),
				"install_ms": (Time.get_ticks_usec() - t0) / 1000.0,
				"collider_ms": 0.0,
				"tris": tris,
				"bytes": bytes,
				"collider": [0, 0],
				"snow_ms": 0.0
			}
		)
	)
	if out.has("snow"):
		_install_snow(out)


## Puts a structure's snow strips (`step.snow`, PainterMannerSnow arrays) on a SNOW child that casts
## no shadow; nothing when the snow went away since the build or the structure has them already.
func _install_snow(step: Dictionary) -> void:
	var job: Dictionary = step.job
	var id := int(job.node)
	var structure := instance_from_id(id) as Node3D
	var arrays: Array = step.get("snow", [])
	if (
		int(job.generation) != _generation
		or int(job.get("snow_gen", -1)) != _snow_gen
		or not _snow_on
		or arrays.is_empty()
		or _snow_nodes.has(id)
		or structure == null
		or not is_instance_valid(structure)
	):
		return
	var t0 := Time.get_ticks_usec()
	var mi := MeshInstance3D.new()
	mi.name = SNOW
	mi.mesh = _mesh(arrays, null, PainterMannerMesh.FORMAT)
	mi.material_override = _surface_material(SNOW_KEY)
	mi.set_instance_shader_parameter(&"bld", building_seed(AuthoredStructures._id_of(structure)))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	structure.add_child(mi)
	_added.append(mi)
	_snow_nodes[id] = mi
	var sid := AuthoredStructures._id_of(structure)
	for k in range(stats.size() - 1, -1, -1):
		if int(stats[k].id) == sid:
			stats[k].tris["snow"] = int(step.get("snow_tris", 0))
			stats[k]["snow_ms"] = float(step.get("snow_ms", 0.0))
			stats[k]["install_ms"] = (
				float(stats[k].install_ms) + (Time.get_ticks_usec() - t0) / 1000.0
			)
			break


## Puts a structure's moved collision faces (`step.collider`) in place of its shape; the shape it
## had is kept for restore_all().
func _install_collider(step: Dictionary) -> void:
	var job: Dictionary = step.job
	var structure := instance_from_id(int(job.node)) as Node3D
	if int(job.generation) != _generation or structure == null or not is_instance_valid(structure):
		return
	var t0 := Time.get_ticks_usec()
	var moved: PackedVector3Array = step.collider
	var cs := structure.get_node_or_null(COLLISION) as CollisionShape3D
	if moved.is_empty() or cs == null or not (cs.shape is ConcavePolygonShape3D):
		return
	var old := cs.shape as ConcavePolygonShape3D
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = old.backface_collision
	shape.set_faces(moved)
	_shapes[cs.get_instance_id()] = [cs, old]
	cs.shape = shape
	var id := AuthoredStructures._id_of(structure)
	for k in range(stats.size() - 1, -1, -1):
		if int(stats[k].id) == id:
			stats[k]["collider_ms"] = (Time.get_ticks_usec() - t0) / 1000.0
			stats[k]["collider"] = [(job.faces as PackedVector3Array).size() / 3, moved.size() / 3]
			break


func _child(parent: MeshInstance3D, child_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = child_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(mi)
	_added.append(mi)
	return mi


static func _mesh(arrays: Array, material: Material, flags: int) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


## About what the arrays take on the GPU: `stride` bytes a vertex and four an index.
static func _bytes(arrays: Array, stride: int) -> int:
	var verts := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	return verts * stride + (0 if index == null else (index as PackedInt32Array).size() * 4)


## The material the snow strips and blankets draw with (shared, toned with the rest), which the
## wall layers' blankets (PainterStreetSnow) take too.
func snow_material() -> ShaderMaterial:
	return _surface_material(SNOW_KEY)


func _surface_material(key: String) -> ShaderMaterial:
	if _shared.has(key):
		return _shared[key]
	var kind := PainterBuildings.kind_of(key)
	if _shader == null:
		var loaded := ResourceLoader.load_threaded_get(SHADER) as Shader
		_shader = loaded if loaded != null else load(SHADER) as Shader
	var material := ShaderMaterial.new()
	material.shader = _shader
	material.set_meta(PainterBuildings.META, true)
	material.set_shader_parameter(&"pattern", int(kind[1]))
	material.set_shader_parameter(&"pick", int(kind[3]))
	material.set_shader_parameter(&"snow_body", snow_body)
	_shared[key] = material
	_materials.append([material, key])
	var owner := _owner_ref.get_ref() as PainterBuildings
	if owner != null and not owner.applied.is_empty():
		owner._tone(material, kind, PainterSheet.load_sheet(owner.applied["sheet"]))
	return material
