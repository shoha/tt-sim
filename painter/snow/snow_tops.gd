class_name PainterSnowTops
extends RefCounted

## The snow bodies of the wall layers and the settlement cells in a mood with roof snow (card
## snow-tops-builder; the structures' own come from PainterMannerHost, through the same builder).
##
## The model. Every asset declares its snow-holding tops as procgen's snow-top records
## (docs/ASSET_PIPELINE.md "snow_tops"), and ONE builder, PainterMannerSnow.build, makes the body
## from them: roof planes get the blanket, round roofs the cone, a stone wall's coping runs a strip
## and a prop's level tops a dome (PainterSnowForms). This host asks each asset for its records and
## puts the bodies on it:
##   a wall    (a `Wall_<id>` of the drawn walls' layer: a street row or a stone wall) is evaluated
##             again with the manner data on, on a worker (WallGeometry.build_one with snow_tops);
##             a street's records are split per lot (PainterMannerSource.feeds_by_lot), so each lot
##             wears its own body, and a free-standing wall's coping runs make one more;
##   a cell    (a settlement cell's mesh) carries its props' pads, placed, in its meta
##             (AuthoredSettlements.SNOW_TOPS_META, from the bake), built on a worker.
## Each body is a child of its asset named NODE, in the asset's own frame, drawn with the
## hand-drawn manner's snow material and casting no shadow: it moves with the asset and is freed
## with it, so nothing is built again when the asset moves. An asset is asked once; clear() frees
## every body (the mood lost its snow) and forgets what was asked. Faces no record covers keep the
## painted law in their own shaders.

## The name of a body's node.
const NODE := "SnowTops"
## The wall layer whose walls carry records (AuthoredWalls).
const WALLS := "AuthoredWalls"

## True (the default) lays the bodies; false lays none and hides the ones laid (an A/B switch for
## measurements: read when an asset is dressed, and by shown()).
static var enabled := true

## Per body built, for a probe and the tests: [{"family" ("street", "wall", "props"), "lot",
## "eval_ms", "ms" (the builder), "tris"}].
var stats: Array = []
## Bodies installed since the last clear().
var builds := 0

## Asset instance id -> true once its records were asked for.
var _asked: Dictionary = {}
var _bodies: Array = []
var _tasks: Dictionary = {}
var _next_key := 0
var _generation := 0
var _material: ShaderMaterial = null


## Lays the bodies of wall node `wall` (a child of a wall layer) drawn with `material`: nothing for
## a fence, a wall of another layer or one already asked.
func dress_wall(wall: Node, material: ShaderMaterial) -> void:
	if not enabled or material == null or not wall is Node3D or not wall.is_inside_tree():
		return
	var id := wall.get_instance_id()
	if _asked.has(id):
		return
	var doc := PainterMannerSource.document(wall.get_tree())
	var record := wall_of(doc, wall)
	if record == null:
		return
	_asked[id] = true
	_material = material
	_start(_work_wall, [id, doc, record])


## Lays the body of settlement cell `cell` (a mesh carrying AuthoredSettlements.SNOW_TOPS_META)
## drawn with `material`; nothing for a cell with no pads or one already asked.
func dress_cell(cell: Node, material: ShaderMaterial) -> void:
	if not enabled or material == null or not cell is Node3D:
		return
	if not cell.has_meta(AuthoredSettlements.SNOW_TOPS_META):
		return
	var id := cell.get_instance_id()
	var pads: Array = cell.get_meta(AuthoredSettlements.SNOW_TOPS_META, [])
	if _asked.has(id) or pads.is_empty():
		return
	_asked[id] = true
	_material = material
	_start(_work_cell, [id, pads])


## Frees every body laid and forgets what was asked; bodies still being built are dropped when
## they arrive.
func clear() -> void:
	_generation += 1
	for body: Variant in _bodies:
		if is_instance_valid(body):
			(body as Node).queue_free()
	_bodies.clear()
	_asked.clear()
	builds = 0


## Whether a body is still being built.
func busy() -> bool:
	return not _tasks.is_empty()


## Shows the bodies laid when `enabled`, else hides them (the in-run A/B). Returns how many.
func shown() -> int:
	var bodies := laid()
	for body in bodies:
		body.visible = enabled
	return bodies.size()


## The bodies laid now (live nodes).
func laid() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for body: Variant in _bodies:
		if is_instance_valid(body):
			out.append(body as MeshInstance3D)
	return out


## The wall record of `doc` node `wall` (a `Wall_<id>` child of WALLS) is built from, when it can
## carry snow tops (a street row or a stone wall, not a fence); null otherwise. Pure.
static func wall_of(doc: MapDocument, wall: Node) -> Wall:
	var layer := wall.get_parent()
	if doc == null or layer == null or str(layer.name) != WALLS:
		return null
	var wall_id := int(str(wall.name).trim_prefix("Wall_"))
	for candidate: Wall in doc.walls:
		if candidate.id == wall_id and candidate.kind != Wall.Kind.FENCE:
			return candidate
	return null


## The builder's results for a wall's snow-top `records` (WallGeometry.snow_tops_of): one per lot
## that lays any snow, [{"lot", "arrays", "triangles", "ms"}], a free-standing wall's runs under
## lot "". Pure and worker-safe.
static func bodies_of(records: Array) -> Array:
	var out: Array = []
	var feeds := PainterMannerSource.feeds_by_lot(records)
	var lots: Array = feeds.keys()
	lots.sort()
	for lot: String in lots:
		var feed: Dictionary = feeds[lot]
		var t0 := Time.get_ticks_usec()
		var src := PainterMannerSnow.source(feed.records, {}, PackedStringArray(), {})
		if not PainterMannerSnow.has_tops(src):
			continue
		var built := PainterMannerSnow.build(src)
		if (built.arrays as Array).is_empty():
			continue
		built["lot"] = lot
		built["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		out.append(built)
	return out


## Runs `work` on a worker with `args` and then the task's key and the generation.
func _start(work: Callable, args: Array) -> void:
	_next_key += 1
	_tasks[_next_key] = WorkerThreadPool.add_task(work.bindv(args + [_next_key, _generation]))


## A wall's bodies: its records (evaluated again with the manner data on), then one body per lot.
## Worker-safe.
func _work_wall(id: int, doc: MapDocument, record: Wall, key: int, generation: int) -> void:
	var t0 := Time.get_ticks_usec()
	var parts := WallGeometry.build_one(doc, record, true)
	var eval_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var bodies := bodies_of(parts.get("snow_tops", []))
	var family := "street" if record.is_row() else "wall"
	for body: Dictionary in bodies:
		body["family"] = family
		body["eval_ms"] = eval_ms
	_arrive.call_deferred(key, id, bodies, generation)


## A settlement cell's body from its pads. Worker-safe.
func _work_cell(id: int, pads: Array, key: int, generation: int) -> void:
	var t0 := Time.get_ticks_usec()
	var built := PainterMannerSnow.build({"tops": pads, "opts": {}})
	built["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	built["eval_ms"] = 0.0
	built["family"] = "props"
	built["lot"] = ""
	var bodies: Array = [] if (built.arrays as Array).is_empty() else [built]
	_arrive.call_deferred(key, id, bodies, generation)


## A worker's bodies on the main thread: each put on its asset as a NODE child, unless the snow went
## away since (clear) or the asset is gone.
func _arrive(key: int, id: int, bodies: Array, generation: int) -> void:
	if _tasks.has(key):
		# Finished but for its return: waited for here so the pool never holds an unwaited task.
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
	var host := instance_from_id(id) as Node3D
	if generation != _generation or host == null or not is_instance_valid(host):
		return
	if not bodies.is_empty():
		# The roofs under a street's bodies keep no crest gaps either (painter_structure.gdshader's
		# `scour`, card painter-roof-round5: short bare slashes along the ridges by the chimneys).
		for node: Node in host.find_children("*", "MeshInstance3D", true, false):
			if PainterBuildings.wall_part_key(str(node.name)).begins_with("roof_"):
				(node as MeshInstance3D).set_instance_shader_parameter(&"scour", 0.0)
	for built: Dictionary in bodies:
		stats.append(
			{
				"family": str(built.family),
				"lot": str(built.lot),
				"eval_ms": float(built.eval_ms),
				"ms": float(built.ms),
				"tris": int(built.triangles),
			}
		)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, built.arrays, [], {}, PainterMannerMesh.FORMAT
		)
		var mi := MeshInstance3D.new()
		mi.name = NODE
		mi.mesh = mesh
		mi.material_override = _material
		var seed_of := PainterMannerHost.building_seed("%d/%s" % [id, built.lot])
		mi.set_instance_shader_parameter(&"bld", seed_of)
		# No wind-scoured crest gaps: in a row's one frame they fell beside every chimney.
		mi.set_instance_shader_parameter(&"scour", 0.0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# A readable name ("SnowTops2") for a wall's second lot.
		host.add_child(mi, true)
		_bodies.append(mi)
		builds += 1
