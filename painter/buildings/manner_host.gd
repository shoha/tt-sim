class_name PainterMannerHost
extends RefCounted

## Puts the hand-drawn manner (the owner's choice B of card painter-manner) on the painted
## buildings while PainterBuildings.manner_mode is "b" ("" is the A3b look and never makes one of
## these): the recipe mesh cut and wandered (PainterMannerMesh), strokes drawn in the fragment
## shader along each piece's own frame (painter_structure_manner.gdshader).
## Per structure, on a WorkerThreadPool task: the records (PainterMannerSource.evaluate) and the
## arrays; on the main thread (call_deferred, no poll) the meshes are made and put in: a painted
## part's own node keeps the recipe topology, wandered, as its shadow caster (SHADOWS_ONLY) and a
## child draws the cut mesh with no shadow; a Classic part (panes, door metal) takes the wandered
## mesh in place so it stays in its hole. restore_all() puts back every mesh and cast setting and
## frees what it added.

const SHADER := "res://painter/shaders/painter_structure_manner.gdshader"
const DRAW := "MannerDraw"
const MODES := {"b": 1}
## Mesh names that are the yard, not the building (not wandered).
const SKIP_PREFIXES: Array[String] = ["dressing", "decor", "cap_", "wheel_", "vane_"]
## The wander amplitude (metres at full height).
const AMP_M := 0.14

## Per structure built: {"id", "eval_ms", "build_ms", "install_ms", "tris": {src, draw, shadow},
## "bytes"}.
var stats: Array[Dictionary] = []

var _mode := ""
var _generation := 0
## Node instance id -> [mesh instance, its mesh, its cast_shadow] for every part changed.
var _restore: Dictionary = {}
## Nodes added (draw children).
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


func _init(buildings: PainterBuildings) -> void:
	_owner_ref = weakref(buildings)


## Starts the build of `structure` (a `Structure_<id>` node) in `mode`; nothing when it is done or
## under way, or when the mode is not a candidate.
func dress(structure: Node, mode: String) -> void:
	if not MODES.has(mode) or _dressed.has(structure.get_instance_id()):
		return
	if mode != _mode:
		restore_all()
		_mode = mode
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
	var authored := structure.get_parent()
	var decor := bool(authored.call("_decor")) if authored.has_method("_decor") else false
	_dressed[structure.get_instance_id()] = true
	var job := {
		"node": structure.get_instance_id(),
		"doc": doc,
		"structure": record,
		"decor": decor,
		"parts": parts,
		"mode": mode,
		"generation": _generation
	}
	_next_key += 1
	job["key"] = _next_key
	_tasks[_next_key] = WorkerThreadPool.add_task(_work.bind(job))


## Puts back every mesh and cast setting changed and frees every node added; results still on
## their way are dropped.
func restore_all() -> void:
	_generation += 1
	for id: int in _restore:
		var entry: Array = _restore[id]
		if is_instance_valid(entry[0]):
			var mi: MeshInstance3D = entry[0]
			mi.mesh = entry[1]
			mi.cast_shadow = entry[2]
	_restore.clear()
	for node in _added:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_added.clear()
	_dressed.clear()
	_materials.clear()
	_shared.clear()
	_mode = ""


## Tones every material this made (PainterBuildings._tone with the part's kind).
func retone(sheet: Dictionary) -> void:
	var owner := _owner_ref.get_ref() as PainterBuildings
	if owner == null:
		return
	for pair: Array in _materials:
		owner._tone(pair[0], PainterBuildings.kind_of(pair[1]), sheet)


static func _skipped(node_name: String) -> bool:
	for prefix in SKIP_PREFIXES:
		if node_name.begins_with(prefix):
			return true
	return false


# ---------------------------------------------------------------- worker


func _work(job: Dictionary) -> void:
	var t0 := Time.get_ticks_usec()
	var feed := PainterMannerSource.evaluate(job.doc, job.structure, job.decor)
	var t1 := Time.get_ticks_usec()
	var out := {"job": job, "parts": {}, "eval_ms": (t1 - t0) / 1000.0}
	if feed.is_empty():
		_install.call_deferred(out)
		return
	var structure: Structure = job.structure
	var building: Dictionary = feed.building
	var records: Dictionary = feed.records
	var foot := float(building.get("wall_foot", 0.0))
	var eave := foot
	for rec: Dictionary in records.values():
		if str(rec["kind"]) == "wall_face":
			var top: float = (rec["origin"] as Vector3).y + float(rec["v_len"]) * (rec["v"] as Vector3).y
			eave = maxf(eave, top)
	var opts := {
		"amp": AMP_M,
		"phase": PainterMannerMesh.phase_of(structure.seed_value),
		"foot": foot,
		"eave": eave
	}
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
	out["build_ms"] = (Time.get_ticks_usec() - t1) / 1000.0
	_install.call_deferred(out)


# ---------------------------------------------------------------- main thread


func _install(out: Dictionary) -> void:
	var job: Dictionary = out.job
	if _tasks.has(int(job.key)):
		# Finished but for its return: waited for here so the pool never holds an unwaited task.
		WorkerThreadPool.wait_for_task_completion(_tasks[int(job.key)])
		_tasks.erase(int(job.key))
	var structure := instance_from_id(int(job.node)) as Node3D
	if int(job.generation) != _generation or structure == null or not is_instance_valid(structure):
		return
	var t0 := Time.get_ticks_usec()
	var tris := {"src": 0, "draw": 0, "shadow": 0}
	var bytes := 0
	for part_name: String in out.parts:
		var mi := structure.get_node_or_null(NodePath(part_name)) as MeshInstance3D
		if mi == null:
			continue
		var built: Dictionary = out.parts[part_name]
		var shadow: Array = built.shadow
		if (shadow[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() != mi.mesh.surface_get_array_len(0):
			continue
		_restore[mi.get_instance_id()] = [mi, mi.mesh, mi.cast_shadow]
		var material := mi.mesh.surface_get_material(0)
		mi.mesh = _mesh(shadow, material, 0)
		tris.src += int(built.triangles[0])
		tris.shadow += int(built.triangles[2])
		if not built.has("draw"):
			tris.draw += int(built.triangles[0])
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		var draw := _child(mi, DRAW, _mesh(built.draw, null, PainterMannerMesh.FORMAT))
		draw.material_override = _surface_material(part_name)
		tris.draw += int(built.triangles[1])
		bytes += _bytes(built.draw, 56)
	(
		stats
		. append(
			{
				"id": AuthoredStructures._id_of(structure),
				"eval_ms": out.eval_ms,
				"build_ms": out.get("build_ms", 0.0),
				"install_ms": (Time.get_ticks_usec() - t0) / 1000.0,
				"tris": tris,
				"bytes": bytes
			}
		)
	)


func _child(parent: MeshInstance3D, child_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = child_name
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	return verts * stride + (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() * 4


func _surface_material(key: String) -> ShaderMaterial:
	if _shared.has(key):
		return _shared[key]
	var kind := PainterBuildings.kind_of(key)
	var material := ShaderMaterial.new()
	material.shader = load(SHADER) as Shader
	material.set_meta(PainterBuildings.META, true)
	material.set_shader_parameter(&"pattern", int(kind[1]))
	material.set_shader_parameter(&"pick", int(kind[3]))
	_shared[key] = material
	_materials.append([material, key])
	var owner := _owner_ref.get_ref() as PainterBuildings
	if owner != null and not owner.applied.is_empty():
		owner._tone(material, kind, PainterSheet.load_sheet(owner.applied["sheet"]))
	return material
