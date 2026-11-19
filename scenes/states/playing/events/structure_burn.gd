class_name StructureBurn
extends RefCounted

## The buildings a fire event burns (card painter-structure-fire), played beside FireSweep's
## trees on one board. A fire that starts in a forest also takes every building whose footprint
## lies within its circle or along its path (find; at most MAX_STRUCTURES, nearest the start
## first). Per building:
##
## - Catching. The front reaches its middle (FireSweep's front, CATCH_SHARE of the way, so a
##   roof catches a little ahead of the ground) and it burns for BURN_S seconds. Its `burn` goes
##   0 to BURN_RATE (FireSweep.burn_progress's scale) in the painter's building burn shader: char
##   climbing from the foot of each part in flat steps, an ember band at its edge
##   (painter_building_burn.gdshaderinc), roofs darkening with the walls. Flames stand on it as
##   the burn climbs and smoke billows over it.
## - Collapse (card painter-fire-polish). COLLAPSE_AT of the way through its burn it comes down
##   over COLLAPSE_S seconds in rigid charred pieces (StructureCollapse: its parts cut into roof
##   slabs, stretches of wall and a standing stump on a worker from setup on, made as hidden nodes
##   under it when that is done, and shown in its parts' place as the collapse starts): the roof
##   sags, breaks and falls in, the walls topple, every piece drops with gathering speed and
##   settles with a small bounce. Nothing is squashed or cut open. The node itself only shudders
##   and sinks SINK of its height. The `burn` value runs on past BURN_RATE by BREAK_SPAN, so ember
##   seams glow through the charcoal as it breaks (painter_building_burn.gdshaderinc), and two
##   rounds of layered dust puffs rise round its footprint. Every motion is held in STEP_S (10 Hz)
##   steps, as the painted event variants are.
## - The ruin. The charred, lowered building stands as the stand-in for its ruin until the
##   event's change lands: the GM's side replaces the record with its ruin recipe on the same
##   footprint (StructureRuin, StructureEditor.burn_down, one history entry with the fire's
##   strokes), which every peer gets as an ordinary op and a save keeps, and the structures node
##   frees the stand-in when the ruin's own node is ready (landed). A building with no ruin is
##   removed.
##
## The painted `burn` instance uniform comes from the painter's buildings host
## (PainterBuildings.take, set_burn, drop; found by the structures node's meta, never by naming
## a painter class: the start-up graph holds none). Under Classic there is no host and nothing
## here plays: the building stands through the fire and becomes its ruin when the change lands
## (the owner's call, 2026-11-18: no more work on Classic), so a Classic board and a Painted one
## still hold the same map.
##
## Bounded: a fixed set of at most MAX_STRUCTURES, every random draw made in setup, a frame only
## compares the step index (a tick sets uniforms and a transform per building and per piece and
## emits a few puffs into the fire's two pools, sized for them). The pieces' nodes are made once a
## building, the step its worker is done; no step allocates otherwise.

const MAX_STRUCTURES := 8
## The structures node's meta that holds a WeakRef to the painted buildings' host
## (PainterBuildings.HOST_META).
const HOST_META := &"painter_buildings_host"
## FireSweep.BURN_RATE's value (the burn shader's scale); a test checks they agree.
const BURN_RATE := 1.7
## A building catches this share of its front time (the front runs along the ground; a roof
## catches ahead of it), plus up to CATCH_JITTER seconds.
const CATCH_SHARE := 0.8
const CATCH_JITTER := 0.3
## How long a building burns (catching to fully charred), and where in that it starts to slump.
const BURN_S := Vector2(2.2, 2.6)
const COLLAPSE_AT := 0.8
const COLLAPSE_S := 1.8
## The share of its height the building's node sinks into the ground as it comes down, and its
## shudder (metres) while the roof sags.
const SINK := 0.04
const SHIVER_M := 0.06
## How far the burn value runs past BURN_RATE as it breaks up (the shader's ember seams glow and
## die down as it climbs; painter_building_burn.gdshaderinc).
const BREAK_SPAN := 1.0
## Every motion is held for this long (10 Hz, as the painted variants).
const STEP_S := 0.1
## Flames and dust puffs one building puts in the flame pool, smoke billows in the smoke pool.
const FLAMES := 10
const DUST_PUFFS := 8
const DUST_ROUNDS := 2
## How far into the collapse (collapse_amount) the first round of dust rises (as the roof breaks
## and falls: StructureCollapse.SAG_END) and the second (as the pieces land).
const DUST_AT := 0.3
const DUST_AGAIN_AT := 0.78
## How far out from the footprint's middle the ring of dust starts, in footprint radii: just
## outside the walls, so it reads beside the building and not behind its roof.
const DUST_RING := 1.3
## A dust puff's life (seconds, plus up to half a second) and its rise (metres a second, plus up to
## a third more): a slow, gentle billow.
const DUST_LIFE := 2.2
const DUST_RISE := 0.55
const FLAME_SLOTS := FLAMES + DUST_PUFFS * DUST_ROUNDS
const SMOKE_SLOTS := 3
## How much of ForestFall.DUST's lightness the burnt building's dust keeps (it rolls out of ash,
## a warm earth tone, not the pale dust of a fallen tree), and its alpha. The Painted puff lights
## its cap warmer and shades its underside cooler than this (FireVariants).
const DUST_DARKEN := 0.5
const DUST_SATURATE := 1.4
const DUST_ALPHA := 0.85
## Flames' life (seconds), their width against the building's height and their feet's height
## range (a share of it).
const FLAME_LIFE := Vector2(0.4, 0.6)
const FLAME_WIDE := Vector2(0.14, 0.24)
const FLAME_UP := Vector2(0.08, 0.5)
## The share of its burn a building's flames rise in: the last is out (FLAME_WHEN.y of the burn
## plus FLAME_LIFE.y) before the slump starts at COLLAPSE_AT, so none stands over a lowered roof.
const FLAME_WHEN := Vector2(0.15, 0.5)
const FLAME_TALL := 1.3
## Draws a building keeps: flames (when, angle, distance, height, size) then lean sign.
const DRAWS_PER_FLAME := 5
const DRAW_LEAN := FLAMES * DRAWS_PER_FLAME
const DRAWS := DRAW_LEAN + 1

## Per building: {"id", "node": its Structure_<id> Node3D, "base": the node's own transform,
## "pivot": its foot's middle, "radius", "height", "start", "burn", "actor": the host's take,
## "draws", "value": the last burn set, "flames", "smoked", "dusted" (rounds of dust so far),
## "settled" (the last pose set), "end": when it is done, and its pieces: "task" (the worker's id,
## -1 once collected), "split" (the worker's result), "sources" (the parts cut, one per surface),
## "materials" (each one's), "burnable" (whether each takes the burn), "hide" (every node the
## pieces stand in for), "pieces" (StructureCollapse.split's), "piece_nodes", "fallen" (shown)}.
var entries: Array[Dictionary] = []

var _host: Object = null
var _flames: EventPuffs = null
var _smoke: SmokePuffs = null
var _tick := -1
var _drift := Vector3.ZERO


## The painted buildings' host of `structures` (an AuthoredStructures node), null under Classic
## (where no building plays a burn).
static func host_of(structures: Node) -> Object:
	if structures == null or not structures.has_meta(HOST_META):
		return null
	var ref: Variant = structures.get_meta(HOST_META)
	return (ref as WeakRef).get_ref() if ref is WeakRef else null


## The buildings `event` burns in `doc`: [{"id", "centre": the footprint's middle (map XZ),
## "radius": the footprint's reach from it, "distance": from the event's start (a path: to its
## nearest point), "frame": StructureCollapse.frame_of its footprint}], nearest first, at most
## `limit`. A ruin is passed over (StructureRuin). Pure over the document and the served library.
static func find(
	doc: MapDocument, event: TerrainEvent, limit: int = MAX_STRUCTURES
) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if doc == null:
		return found
	var line := event.path if event.is_path() else PackedVector2Array([event.centre])
	for structure in doc.structures:
		var reach := reach_of(structure.footprint, line)
		if reach > event.radius_m or StructureRuin.is_ruin(structure):
			continue
		var middle := middle_of(structure.footprint)
		var radius := 0.0
		for p in structure.footprint:
			radius = maxf(radius, p.distance_to(middle))
		found.append(
			{
				"id": structure.id,
				"centre": middle,
				"radius": radius,
				"distance": TerrainEvent.distance_to_line(middle, line),
				"frame": StructureCollapse.frame_of(structure.footprint),
			}
		)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return a.distance < b.distance or (a.distance == b.distance and a.id < b.id)
	)
	if found.size() > limit:
		found.resize(limit)
	return found


## The ids of the buildings `event` burns in `doc` (find's), for the change that follows.
static func ids_in(doc: MapDocument, event: TerrainEvent) -> Array[int]:
	var out: Array[int] = []
	for entry in find(doc, event):
		out.append(int(entry.id))
	return out


## The mean of a footprint's points (map XZ).
static func middle_of(footprint: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in footprint:
		sum += p
	return sum / maxf(float(footprint.size()), 1.0)


## The least distance from `footprint` to the polyline `line` (a point: to it); 0 when a one point
## line is inside the plan. A plan's points, its edges' middles and its mean stand for it against a
## line of several points. Pure.
static func reach_of(footprint: PackedVector2Array, line: PackedVector2Array) -> float:
	if footprint.size() < 3 or line.is_empty():
		return INF
	if line.size() == 1:
		if Geometry2D.is_point_in_polygon(line[0], footprint):
			return 0.0
		var least := INF
		for i in footprint.size():
			var on := Geometry2D.get_closest_point_to_segment(
				line[0], footprint[i], footprint[(i + 1) % footprint.size()]
			)
			least = minf(least, line[0].distance_to(on))
		return least
	var nearest := TerrainEvent.distance_to_line(middle_of(footprint), line)
	for i in footprint.size():
		var next := footprint[(i + 1) % footprint.size()]
		nearest = minf(nearest, TerrainEvent.distance_to_line(footprint[i], line))
		nearest = minf(nearest, TerrainEvent.distance_to_line((footprint[i] + next) * 0.5, line))
	return nearest


## The burn shader's value `t` seconds after a building that burns `burn_s` seconds caught: 0
## before, BURN_RATE once its burn is out, held after. Pure.
static func burn_value(t: float, burn_s: float) -> float:
	return clampf(t / maxf(burn_s, 0.01), 0.0, 1.0) * BURN_RATE


## How far into its collapse a building is `t` seconds after catching (0 to 1). Pure.
static func collapse_amount(t: float, burn_s: float) -> float:
	return clampf((t - burn_s * COLLAPSE_AT) / COLLAPSE_S, 0.0, 1.0)


## When a building's collapse is over, seconds after catching. Pure.
static func end_after(burn_s: float) -> float:
	return burn_s * COLLAPSE_AT + COLLAPSE_S


## `t` held to its STEP_S step. Pure.
static func stepped(t: float) -> float:
	return floorf(t / STEP_S) * STEP_S


## The burn shader's value `x` (0..1, collapse_amount) into a slump: BREAK_SPAN of the way on past
## BURN_RATE as x runs 0 to 1 (0 before it). Pure.
static func break_value(x: float) -> float:
	return clampf(x, 0.0, 1.0) * BREAK_SPAN


## The transform a building's node takes `x` (0..1, collapse_amount) into its collapse (its
## pieces move under it, StructureCollapse.pose): a shudder while the roof sags (to
## StructureCollapse.SAG_END) and a sink of `sink` metres that gathers speed. Never a scale; x = 0
## is the identity. Pure.
static func node_pose(x: float, sink: float = 0.0) -> Transform3D:
	if x <= 0.0:
		return Transform3D.IDENTITY
	var sag := StructureCollapse.SAG_END
	var shake := SHIVER_M * clampf(1.0 - x / sag, 0.0, 1.0) * minf(x * 12.0, 1.0)
	var down := clampf(x / StructureCollapse.FALL_END, 0.0, 1.0)
	return Transform3D(
		Basis.IDENTITY,
		Vector3(sin(x * 61.0) * shake, -sink * down * down, cos(x * 47.0) * shake)
	)


## The burnt buildings of `found` (find's, each with its "start", seconds): finds their nodes under
## `structures`, takes the painted host's actors, draws every random number and sets up the puffs.
## `drift` is the smoke's drift. Returns how many it holds.
func setup(
	structures: Node,
	found: Array[Dictionary],
	flames: EventPuffs,
	smoke: SmokePuffs,
	rng: RandomNumberGenerator,
	drift: Vector3
) -> int:
	_flames = flames
	_smoke = smoke
	_drift = drift
	_host = host_of(structures)
	entries.clear()
	if structures == null or _host == null:
		return 0
	for item in found:
		var node := structures.get_node_or_null("Structure_%d" % int(item.id)) as Node3D
		if node == null:
			continue
		var box := bounds_of(node)
		if box.size.y <= 0.0:
			continue
		var actor: Dictionary = _host.call("take", node, true)
		if actor.is_empty():
			continue
		var centre: Vector2 = item.centre
		var burn := rng.randf_range(BURN_S.x, BURN_S.y)
		var draws := PackedFloat32Array()
		for i in DRAWS:
			draws.append(rng.randf())
		# The flames' times sorted (first draw of each), so the next one is always the earliest.
		var times: Array[float] = []
		for i in FLAMES:
			times.append(draws[i * DRAWS_PER_FLAME])
		times.sort()
		for i in FLAMES:
			draws[i * DRAWS_PER_FLAME] = times[i]
		var entry := {
			"id": int(item.id),
			"node": node,
			"base": node.transform,
			"pivot": Vector3(centre.x, box.position.y, centre.y),
			"radius": float(item.radius),
			"height": box.size.y,
			"start": float(item.get("start", 0.0)),
			"burn": burn,
			"actor": actor,
			"draws": draws,
			"value": -1.0,
			"flames": 0,
			"smoked": 0,
			"dusted": 0,
			"settled": false,
			"end": 0.0,
			"fallen": false,
			"piece_nodes": [],
			"pieces": [],
		}
		entry.end = float(entry.start) + end_after(burn)
		_start_split(entry, structures, item, box, rng.randi())
		entries.append(entry)
	return entries.size()


## Gathers the parts of `entry`'s building (`item` find's, `box` its bounds) and starts cutting them
## into pieces on a worker (StructureCollapse.split). Each part's arrays come from the structures'
## built parts (no read back from the GPU) when they are there.
func _start_split(
	entry: Dictionary, structures: Node, item: Dictionary, box: AABB, seed_value: int
) -> void:
	var node: Node3D = entry.node
	var built: Dictionary = {}
	if structures.has_method("built_parts"):
		built = structures.call("built_parts", int(item.id))
	var by_name: Dictionary = {}
	for mesh: Dictionary in built.get("meshes", []):
		by_name["%s_%s" % [mesh.role, mesh.kind]] = mesh.arrays
	var parts: Array = []
	var sources: Array[MeshInstance3D] = []
	var materials: Array[Material] = []
	var burnable := PackedByteArray()
	var hide: Array[Node3D] = []
	var taken: Array = (entry.actor as Dictionary).get("nodes", [])
	for child: Node in node.get_children():
		var name := String(child.name)
		if child is CollisionObject3D or name.begins_with("dressing_") or not child is Node3D:
			continue
		hide.append(child as Node3D)
		if name.begins_with("decor_") or name.ends_with("_" + StructureGlow.KIND):
			continue
		var meshes: Array[Node] = []
		if child is MeshInstance3D:
			meshes.append(child)
		meshes.append_array(child.find_children("*", "MeshInstance3D", true, false))
		for found: Node in meshes:
			var mi := found as MeshInstance3D
			if mi.mesh == null or sources.size() >= 255:
				continue
			var to_node := Transform3D.IDENTITY
			var up: Node = mi
			while up != null and up != node:
				to_node = (up as Node3D).transform * to_node
				up = up.get_parent()
			for k in mi.mesh.get_surface_count():
				var arrays: Variant = by_name.get(String(mi.name)) if mi == child and k == 0 else null
				parts.append(
					{
						"arrays": arrays if arrays != null else mi.mesh.surface_get_arrays(k),
						"to_node": to_node,
						"roof": String(mi.name).contains("roof_"),
					}
				)
				sources.append(mi)
				materials.append(mi.get_active_material(k))
				burnable.append(1 if taken.has(mi) else 0)
	var middle: Vector2 = item.centre
	var frame_of: Dictionary = item.get("frame", {})
	var axis: Vector2 = frame_of.get("axis", Vector2.RIGHT)
	var frame := {
		"centre": Vector3(middle.x, box.position.y, middle.y),
		"axis": Vector3(axis.x, 0.0, axis.y),
		"half": frame_of.get("half", Vector2(box.size.x, box.size.z) * 0.5),
		"height": box.size.y,
		"seed": seed_value,
	}
	if frame_of.has("middle"):
		var at: Vector2 = frame_of.middle
		frame.centre = Vector3(at.x, box.position.y, at.y)
	var split := {}
	entry.split = split
	entry.sources = sources
	entry.materials = materials
	entry.burnable = burnable
	entry.hide = hide
	entry.task = WorkerThreadPool.add_task(
		func() -> void: split["pieces"] = StructureCollapse.split(parts, frame)
	)


## Makes `entry`'s pieces once its worker is done (`wait`: wait for it), hidden until it falls.
func _collect(entry: Dictionary, wait: bool) -> void:
	var task := int(entry.get("task", -1))
	if task < 0 or not (wait or WorkerThreadPool.is_task_completed(task)):
		return
	WorkerThreadPool.wait_for_task_completion(task)
	entry.task = -1
	if not is_instance_valid(entry.node):
		return
	var pieces: Array[Dictionary] = (entry.split as Dictionary).get("pieces", [] as Array[Dictionary])
	var made := StructureCollapse.install(entry.node, pieces, entry.materials)
	var burnable: PackedByteArray = entry.burnable
	var nodes: Array = (entry.actor as Dictionary).get("nodes", [])
	for i in made.size():
		var surfaces: Array = pieces[i].surfaces
		for k in surfaces.size():
			if burnable[int(surfaces[k].part)] == 1:
				var part := made[i].get_child(k) as MeshInstance3D
				nodes.append(part)
				if float(entry.value) >= 0.0:
					part.set_instance_shader_parameter(&"burn", float(entry.value))
	entry.pieces = pieces
	entry.piece_nodes = made
	entry.split = {}


## Hides `entry`'s parts as its pieces come out of PARKED (once, as its collapse starts: the poses
## that follow put the pieces in place).
func _fall_in(entry: Dictionary) -> void:
	if bool(entry.fallen):
		return
	_collect(entry, true)
	entry.fallen = true
	var was: Array[Node3D] = []
	if (entry.piece_nodes as Array).is_empty():
		entry.hide = was
		return
	# Only what shows now is hidden, and only that is shown again on release.
	for part: Node3D in entry.hide:
		if is_instance_valid(part) and part.visible:
			part.visible = false
			was.append(part)
	entry.hide = was


## The box of `node`'s meshes in its own frame (the parts' transforms walked up to it, so it needs
## no tree); an empty box for none.
static func bounds_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for found: Node in node.find_children("*", "MeshInstance3D", true, false):
		var part := found as MeshInstance3D
		if part.mesh == null:
			continue
		var to_node := Transform3D.IDENTITY
		var up: Node = part
		while up != null and up != node:
			if up is Node3D:
				to_node = (up as Node3D).transform * to_node
			up = up.get_parent()
		var local := to_node * part.mesh.get_aabb()
		box = local if first else box.merge(local)
		first = false
	return box


## Plays the burns `elapsed` seconds into the fire: on each STEP_S step, every caught building's
## burn, flames, smoke, slump and dust.
func step(elapsed: float) -> void:
	var tick := int(elapsed / STEP_S)
	if tick == _tick:
		return
	_tick = tick
	var at := float(tick) * STEP_S
	for entry in entries:
		_collect(entry, false)
		_advance(entry, at - float(entry.start))


## When the last building's collapse is over (seconds into the fire), 0 with none.
func end_at() -> float:
	var end := 0.0
	for entry in entries:
		end = maxf(end, float(entry.end))
	return end


## True once every building has finished collapsing.
func is_done(elapsed: float) -> bool:
	return elapsed >= end_at()


## True once the change has landed: every building's node is gone (the ruin's own took its place,
## or the building was removed). True with none.
func landed() -> bool:
	for entry in entries:
		if is_instance_valid(entry.node):
			return false
	return true


## Lets every building go that is still standing: its transform back, its pieces gone and its parts
## shown and unburnt. Waits for a worker still cutting. Idempotent.
func release() -> void:
	for entry in entries:
		var task := int(entry.get("task", -1))
		if task >= 0:
			WorkerThreadPool.wait_for_task_completion(task)
			entry.task = -1
		# Untyped: a piece or a part may have gone with its node (the ruin landed).
		for piece: Variant in entry.get("piece_nodes", []):
			if is_instance_valid(piece):
				var taken: Array = (entry.actor as Dictionary).get("nodes", [])
				for part: Node in (piece as Node).get_children():
					taken.erase(part)
				(piece as Node).get_parent().remove_child(piece)
				(piece as Node).free()
		if bool(entry.get("fallen", false)):
			for part: Variant in entry.hide:
				if is_instance_valid(part):
					(part as Node3D).visible = true
		if is_instance_valid(entry.node):
			(entry.node as Node3D).transform = entry.base
			if is_instance_valid(_host):
				_host.call("drop", entry.actor)
		entry.actor = {}
	entries.clear()


func _advance(entry: Dictionary, t: float) -> void:
	if t < 0.0 or not is_instance_valid(entry.node):
		return
	var burn := float(entry.burn)
	var x := collapse_amount(t, burn)
	var value := burn_value(t, burn) + break_value(x)
	if value != float(entry.value) and is_instance_valid(_host):
		entry.value = value
		_host.call("set_burn", entry.actor, value)
	var draws: PackedFloat32Array = entry.draws
	while int(entry.flames) < FLAMES:
		var at := int(entry.flames) * DRAWS_PER_FLAME
		if t < lerpf(FLAME_WHEN.x, FLAME_WHEN.y, draws[at]) * burn:
			break
		_flame(entry, at)
		entry.flames = int(entry.flames) + 1
	if int(entry.smoked) < 1 and t >= 0.45 * burn:
		entry.smoked = 1
		_billow(entry, 0.5, 1.2)
	if x > 0.0:
		_fall_in(entry)
		if int(entry.dusted) < 1 and x >= DUST_AT:
			entry.dusted = 1
			_dust(entry, draws, 0)
			_billow(entry, 0.7, 1.6)
		if int(entry.dusted) < DUST_ROUNDS and x >= DUST_AGAIN_AT:
			entry.dusted = DUST_ROUNDS
			_dust(entry, draws, 1)
		if x < 1.0 or not entry.settled:
			entry.settled = x >= 1.0
			var pose := node_pose(x, SINK * float(entry.height))
			(entry.node as Node3D).transform = pose * (entry.base as Transform3D)
			var pieces: Array = entry.pieces
			var made: Array = entry.piece_nodes
			for i in mini(pieces.size(), made.size()):
				(made[i] as Node3D).transform = StructureCollapse.pose(pieces[i], x)


## A flame standing in the building's footprint at a random height as it burns.
func _flame(entry: Dictionary, at: int) -> void:
	var draws: PackedFloat32Array = entry.draws
	var height := float(entry.height)
	var angle := draws[at + 1] * TAU
	var out := sqrt(draws[at + 2]) * float(entry.radius) * 0.7
	var wide := clampf(
		height * lerpf(FLAME_WIDE.x, FLAME_WIDE.y, draws[at + 4]), 0.45, 1.5
	)
	var up := lerpf(FLAME_UP.x, FLAME_UP.y, draws[at + 3])
	var foot: Vector3 = entry.pivot + Vector3(cos(angle) * out, height * up, sin(angle) * out)
	var life := lerpf(FLAME_LIFE.x, FLAME_LIFE.y, fmod(draws[at + 4] * 5.3, 1.0))
	_flames.emit_flame(
		foot,
		Vector3(0.0, height * 0.04, 0.0),
		wide,
		wide * FLAME_TALL,
		life,
		FireSweep.FLAME if draws[at + 4] < 0.6 else FireSweep.FLAME_LATE
	)


## The warm ochre of a burnt building's dust (ForestFall.DUST darkened and made richer, more opaque:
## it rolls out of ash and old thatch, not the pale dust of a fallen tree).
static func dust_color() -> Color:
	var tone := ForestFall.DUST.darkened(DUST_DARKEN)
	tone.s = minf(tone.s * DUST_SATURATE, 1.0)
	tone.a = DUST_ALPHA
	return tone


## DUST_PUFFS puffs of dust (round number `again`, 0 or 1) in a ring just outside the footprint
## (DUST_RING radii out) as the building comes down, layered painted puffs under Painted
## (EventPuffs.emit_brush: a lit cap, a cool underside, a brush edge) that billow out a little and
## rise slowly. The second round is turned half a puff along, smaller and higher, drawn over the
## first (a later slot), so the two read as a layered cloud, not a row.
func _dust(entry: Dictionary, draws: PackedFloat32Array, again: int) -> void:
	var height := float(entry.height)
	var radius := float(entry.radius)
	var shrink := 1.0 - 0.3 * float(again)
	var color := dust_color()
	for i in DUST_PUFFS:
		var angle := (float(i) + 0.5 * float(again) + draws[i]) / float(DUST_PUFFS) * TAU
		var out := Vector3(cos(angle), 0.0, sin(angle))
		var ring := radius * (DUST_RING - 0.2 * float(again))
		var up := height * (0.08 + 0.2 * float(again))
		_flames.emit_brush(
			(entry.pivot as Vector3) + out * ring + Vector3(0.0, up, 0.0),
			out * (0.3 + 0.3 * draws[i + 1]) + Vector3(0.0, DUST_RISE * (1.0 + 0.3 * draws[i + 2]), 0.0),
			clampf(height * 0.55, 1.2, 3.0) * shrink,
			DUST_LIFE + 0.5 * draws[i + 2],
			color
		)


## A smoke billow above the building (`size` its height's share, `rise` its climb).
func _billow(entry: Dictionary, size: float, rise: float) -> void:
	var height := float(entry.height)
	var above: Vector3 = entry.pivot + Vector3(0.0, height * 0.9, 0.0)
	_smoke.emit(
		above,
		_drift * 1.5 + Vector3(0.0, rise * 0.5, 0.0),
		maxf(height * size, 1.0),
		2.8,
		Color.WHITE
	)
