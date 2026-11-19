class_name PainterStreetSnow
extends RefCounted

## Winter's snow blanket on the roofs of the wall layers (card painter-roof-round3): the street
## lots', wall rows' and boundaries' roofs. Procgen gives them no manner records (a headless probe:
## a street row evaluated with `manner` set leaves none), so their snow had its body only in the
## A3b shader's shading and read flat beside the hand-drawn houses' blankets (owner, 2026-11-19,
## l45_snow: "More body (a geometric lip on the street roofs)").
##
## The model. A roof part's up faces fall into slopes (faces joined by an edge that lie in one
## plane), and each slope's outline is read back into the edges a manner roof record carries:
##   eave    the level side along the slope's foot;
##   ridge   the level side along its top (or an apex, where its two sides meet);
##   hip     a side that runs across the slope's fall line or that another slope shares;
##   verge   any other side (a gable's).
## The slopes go to PainterMannerSnow.build as the hand-drawn houses' roofs do, so a street roof
## wears the same blanket: thick and rounded in the field, a lip that rolls over the eave, hangs in
## scallops and tucks under, a soft roll at a verge, one crest where two halves meet. A slope whose
## outline is not one eave, two sides and a top (an L plan's valley) takes the strips' lips and caps
## instead. The blanket is a child of its roof part (its frame), drawn by the hand-drawn manner's
## snow material (PainterMannerHost.snow_material) and casting no shadow; it is built while the
## mood lays roof snow and freed when it stops.

## Faces under this much of up (normal Y) are walls, a fascia or an underside, not a slope.
const UP_MIN := 0.2
## Positions this close are one vertex (metres).
const WELD_M := 0.004
## Two faces sharing an edge are one slope when their normals agree this closely (dot).
const PLANE_DOT := 0.995
## A side is level (an eave or a ridge) when its ends differ by less than this in height (metres).
const LEVEL_M := 0.04
## How near the slope's foot (top) a level side runs to be its eave (ridge), metres up the slope.
const EDGE_M := 0.08
## Two outline steps that turn less than this (the sine of the angle) are one side.
const TURN := 0.03
## A side that runs this much along the eave per metre of its length is a hip, not a verge.
const HIP_ALONG := 0.3
## A slope under this area gets no blanket (a finial's facet, a sliver), square metres.
const MIN_AREA_M2 := 0.3
## A face above this much of up is a flat roof; one narrower than FLAT_MIN_M (a ridge board's top)
## or a slope narrower than SLOPE_MIN_M gets no snow of its own (metres).
const FLAT_UP := 0.97
const FLAT_MIN_M := 0.8
const SLOPE_MIN_M := 0.3
## Two slopes' verges this close side by side (metres, each one's middle to the other) are one seam
## (_join_verges).
const JOIN_M := 0.25
## Two slopes' ridges this far apart across a flat band (a street gable's ridge board, 6 to 10 cm
## measured) meet on the band's middle line (_join_ridges), metres.
const RIDGE_JOIN_M := 0.2
## The hold name of each roof kind number (PainterMannerSnow.ROOF_MESH_KINDS, its HOLD's keys).
const MATERIALS: Dictionary = {
	1: "tile", 2: "wood", 3: "thatch", 4: "slate", 5: "shingle", 6: "turf"
}
## The name of a roof part's snow child.
const SNOW := "StreetSnow"

## False leaves the wall layers' roofs with their shader-only snow, as before card
## painter-roof-round3 (an A/B switch for measurements). Read when a wall is dressed.
static var bodied := true

## Per built blanket, for a probe: {"ms", "tris"} by roof part instance id.
var stats: Dictionary = {}
## Roof part instance id -> its snow child, or null while its blanket is being built.
var _nodes: Dictionary = {}
## Worker task ids by job key (each waited for when its result arrives).
var _tasks: Dictionary = {}
var _next_key := 0
## Bumped by clear(): a blanket built for an older one is dropped.
var _generation := 0
## The material the blankets draw with (the last dress's).
var _material: ShaderMaterial = null


## Lays a blanket on each roof part of `wall` (a wall layer's child) that has none yet, drawn with
## `material`: the slopes are read and the blanket built on a worker, and put in place on the main
## thread when done. Nothing while bodied is off.
func dress(wall: Node, material: ShaderMaterial) -> void:
	if not bodied or material == null:
		return
	_material = material
	for node: Node in wall.find_children("*", "MeshInstance3D", true, false):
		var part := node as MeshInstance3D
		var id := part.get_instance_id()
		if _nodes.has(id) and (_nodes[id] == null or is_instance_valid(_nodes[id])):
			continue
		var kind := int(PainterMannerSnow.ROOF_MESH_KINDS.get(_roof_key(str(part.name)), 0))
		if kind == 0 or part.mesh == null or part.mesh.get_surface_count() == 0:
			continue
		_nodes[id] = null
		var arrays := part.mesh.surface_get_arrays(0)
		_next_key += 1
		_tasks[_next_key] = WorkerThreadPool.add_task(
			_work.bind(_next_key, id, arrays, kind, _generation)
		)


## Frees every blanket laid; blankets still being built are dropped when they arrive.
func clear() -> void:
	_generation += 1
	for id: int in _nodes:
		var mi: Variant = _nodes[id]
		if mi != null and is_instance_valid(mi):
			(mi as Node).queue_free()
	_nodes.clear()


## Whether a blanket is still being built.
func busy() -> bool:
	return not _tasks.is_empty()


## The blanket of one roof part (`arrays` its mesh, `kind` its roof kind number). Worker-safe.
func _work(key: int, id: int, arrays: Array, kind: int, generation: int) -> void:
	var t0 := Time.get_ticks_usec()
	var built := PainterMannerSnow.build(
		{"roofs": records_of(arrays, kind, str(id)), "pads": [], "opts": {}}
	)
	built["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	_arrive.call_deferred(key, id, built, generation)


## A worker's blanket on the main thread: put on its roof part as a SNOW child, unless the snow went
## away since (clear) or the part is gone.
func _arrive(key: int, id: int, built: Dictionary, generation: int) -> void:
	if _tasks.has(key):
		# Finished but for its return: waited for here so the pool never holds an unwaited task.
		WorkerThreadPool.wait_for_task_completion(_tasks[key])
		_tasks.erase(key)
	var part := instance_from_id(id) as MeshInstance3D
	if generation != _generation or part == null or not is_instance_valid(part):
		if generation == _generation:
			_nodes.erase(id)
		return
	stats[id] = {"ms": float(built.ms), "tris": int(built.triangles)}
	if (built.arrays as Array).is_empty():
		return
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, built.arrays, [], {}, PainterMannerMesh.FORMAT
	)
	var mi := MeshInstance3D.new()
	mi.name = SNOW
	mi.mesh = mesh
	mi.material_override = _material
	mi.set_instance_shader_parameter(&"bld", PainterMannerHost.building_seed(id))
	# No wind-scoured crest gaps: in a row's one frame they fell beside every chimney (the manner
	# shader's `scour`, card painter-roof-round4).
	mi.set_instance_shader_parameter(&"scour", 0.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	part.add_child(mi)
	_nodes[id] = mi


## The blankets laid now (live nodes).
func laid() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for id: int in _nodes:
		if is_instance_valid(_nodes[id]):
			out.append(_nodes[id] as MeshInstance3D)
	return out


## The structures' `<role>_<kind>` key of a wall layer's roof part named `node_name` ("" for any
## other part). Pure.
static func _roof_key(node_name: String) -> String:
	if node_name == SNOW:
		return ""
	var key := PainterBuildings.wall_part_key(node_name)
	return key if key.begins_with("roof_") else ""


## The roof records (PainterMannerSnow.source's: "id", "kind", "n", "origin", "u", "v", "u_len",
## "v_len", "edges", "material", "tone") of the slopes of roof mesh `arrays`, `kind` its roof kind
## number (ROOF_MESH_KINDS) and `prefix` its records' ids. Pure.
static func records_of(arrays: Array, kind: int, prefix: String) -> Array:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	var cols: Variant = arrays[Mesh.ARRAY_COLOR]
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	var idx := PackedInt32Array()
	if index != null:
		idx = index
	else:
		for k in verts.size():
			idx.append(k)
	var wid := _weld(verts)
	var faces := _up_faces(verts, normals, idx, wid)
	var out: Array = []
	for group: PackedInt32Array in _slopes(faces):
		var rec := _record(group, faces, verts, cols, idx, wid)
		if rec.is_empty():
			continue
		rec["id"] = "%s/%d" % [prefix, out.size()]
		rec["kind"] = "roof_slope"
		rec["material"] = str(MATERIALS.get(kind, "tile"))
		var tone: Color = rec["tone"]
		rec["tone"] = Color(tone.r, tone.g, tone.b, float(kind) / PainterMannerSnow.KIND_SCALE)
		out.append(rec)
	_join_verges(out)
	_join_ridges(out)
	return out


## A street gable's two slopes end at their own ridge lines with a flat band between them (a ridge
## board 6 to 10 cm wide; card painter-roof-round4, a headless probe of a village row), and each
## blanket crested over its own line, so the band showed through between the two crests as a brown
## slit along the ridge, under each chimney that stands astride it (owner, final60 st_win_z9_p and
## st_win_z30_p). Such a pair of ridges (level, parallel, at one height, each slope rising toward
## the other, under RIDGE_JOIN_M apart) is carried on up each slope's plane to the band's middle
## line, where the two crests meet as one. Changes `records` in place.
static func _join_ridges(records: Array) -> void:
	var tops: Array = []
	for i in records.size():
		for e: Dictionary in records[i]["edges"]:
			if str(e["kind"]) == "ridge":
				tops.append([i, e])
	var joined := {}
	for x in tops.size():
		for y in range(x + 1, tops.size()):
			var i: int = tops[x][0]
			var j: int = tops[y][0]
			if i == j or joined.has(x) or joined.has(y):
				continue
			var ea: Dictionary = tops[x][1]
			var eb: Dictionary = tops[y][1]
			var off := _ridge_gap(ea, eb)
			if off == Vector3.ZERO:
				continue
			var ra: Dictionary = records[i]
			var rb: Dictionary = records[j]
			if _rise_to(ra, off * 0.5) <= 0.0 or _rise_to(rb, -off * 0.5) <= 0.0:
				continue
			_raise(ra, ea, _rise_to(ra, off * 0.5))
			_raise(rb, eb, _rise_to(rb, -off * 0.5))
			joined[x] = true
			joined[y] = true


## The level offset across from ridge `ea` to ridge `eb` when they are a pair _join_ridges joins
## (parallel, one height, each middle within RIDGE_JOIN_M of the other line, not already one
## line), else Vector3.ZERO. Pure.
static func _ridge_gap(ea: Dictionary, eb: Dictionary) -> Vector3:
	var a0: Vector3 = ea["a"]
	var a1: Vector3 = ea["b"]
	var b0: Vector3 = eb["a"]
	var b1: Vector3 = eb["b"]
	var dir := (a1 - a0).normalized()
	if absf(dir.dot((b1 - b0).normalized())) < 0.99:
		return Vector3.ZERO
	var ma := (a0 + a1) * 0.5
	var mb := (b0 + b1) * 0.5
	if absf(ma.y - mb.y) > LEVEL_M:
		return Vector3.ZERO
	var near_a := Geometry3D.get_closest_point_to_segment(ma, b0, b1)
	var near_b := Geometry3D.get_closest_point_to_segment(mb, a0, a1)
	if ma.distance_to(near_a) > RIDGE_JOIN_M or mb.distance_to(near_b) > RIDGE_JOIN_M:
		return Vector3.ZERO
	var off := mb - ma
	off -= dir * off.dot(dir)
	off.y = 0.0
	return off if off.length() > 0.005 else Vector3.ZERO


## How far up slope `rec`'s plane its top must run for its ridge to move `toward` (a level offset);
## 0 when the slope does not rise that way. Pure.
static func _rise_to(rec: Dictionary, toward: Vector3) -> float:
	var v: Vector3 = rec["v"]
	var level := Vector3(v.x, 0.0, v.z)
	if level.length() < 0.05 or level.normalized().dot(toward.normalized()) < 0.9:
		return 0.0
	return toward.length() / level.length()


## Moves slope `rec`'s ridge `edge` `run` metres on up its plane: the ridge, the sides' ends on it
## and the frame's length up the slope.
static func _raise(rec: Dictionary, edge: Dictionary, run: float) -> void:
	var shift: Vector3 = (rec["v"] as Vector3) * run
	var old_a: Vector3 = edge["a"]
	var old_b: Vector3 = edge["b"]
	for e: Dictionary in rec["edges"]:
		for end: String in ["a", "b"]:
			var p: Vector3 = e[end]
			if p.distance_to(old_a) < WELD_M * 5.0 or p.distance_to(old_b) < WELD_M * 5.0:
				e[end] = p + shift
	rec["v_len"] = float(rec["v_len"]) + run


## Two neighbouring lots' slopes that meet side by side (a party wall, a chimney between them) each
## end in a verge there; each blanket rolled down to its own verge and the roof showed through the
## valley between them as a dark slit from ridge to eave (after frame st_win_z9_p). Such a pair of
## verges, parallel and each within JOIN_M of the other, becomes a pair of hips: the blankets run
## full to the seam. Changes `records`' edges in place.
static func _join_verges(records: Array) -> void:
	var sides: Array = []
	for i in records.size():
		for e: Dictionary in records[i]["edges"]:
			if str(e["kind"]) == "verge":
				sides.append([i, e])
	for x in sides.size():
		for y in range(x + 1, sides.size()):
			if sides[x][0] == sides[y][0]:
				continue
			var ea: Dictionary = sides[x][1]
			var eb: Dictionary = sides[y][1]
			var a0: Vector3 = ea["a"]
			var a1: Vector3 = ea["b"]
			var b0: Vector3 = eb["a"]
			var b1: Vector3 = eb["b"]
			if absf((a1 - a0).normalized().dot((b1 - b0).normalized())) < 0.95:
				continue
			var ma := (a0 + a1) * 0.5
			var mb := (b0 + b1) * 0.5
			var near_a := Geometry3D.get_closest_point_to_segment(ma, b0, b1)
			var near_b := Geometry3D.get_closest_point_to_segment(mb, a0, a1)
			if ma.distance_to(near_a) < JOIN_M and mb.distance_to(near_b) < JOIN_M:
				ea["kind"] = "hip"
				eb["kind"] = "hip"


## Each vertex's welded id (positions within WELD_M are one).
static func _weld(verts: PackedVector3Array) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	out.resize(verts.size())
	for k in verts.size():
		var key := Vector3i((verts[k] / WELD_M).round())
		if not seen.has(key):
			seen[key] = seen.size()
		out[k] = seen[key]
	return out


## The faces that face up: {"tri": [first index of each in `idx`], "n": normals, "area": areas,
## "edges": {Vector2i welded edge: [faces]}}.
static func _up_faces(
	verts: PackedVector3Array, normals: Variant, idx: PackedInt32Array, wid: PackedInt32Array
) -> Dictionary:
	var tri := PackedInt32Array()
	var ns := PackedVector3Array()
	var areas := PackedFloat32Array()
	var edges := {}
	for t in idx.size() / 3:
		var a := verts[idx[t * 3]]
		var cr := (verts[idx[t * 3 + 1]] - a).cross(verts[idx[t * 3 + 2]] - a)
		if cr.length_squared() < 1e-10:
			continue
		var n := cr.normalized()
		if normals != null:
			var vn: PackedVector3Array = normals
			if n.dot(vn[idx[t * 3]] + vn[idx[t * 3 + 1]] + vn[idx[t * 3 + 2]]) < 0.0:
				n = -n
		elif n.y < 0.0:
			n = -n
		if n.y < UP_MIN:
			continue
		var f := tri.size()
		tri.append(t * 3)
		ns.append(n)
		areas.append(cr.length() * 0.5)
		for k in 3:
			var e := _edge(wid[idx[t * 3 + k]], wid[idx[t * 3 + (k + 1) % 3]])
			if not edges.has(e):
				edges[e] = []
			(edges[e] as Array).append(f)
	return {"tri": tri, "n": ns, "area": areas, "edges": edges}


static func _edge(a: int, b: int) -> Vector2i:
	return Vector2i(mini(a, b), maxi(a, b))


## The faces of `faces` grouped into slopes: faces joined by an edge whose normals agree.
static func _slopes(faces: Dictionary) -> Array:
	var tri: PackedInt32Array = faces.tri
	var ns: PackedVector3Array = faces.n
	var parent := PackedInt32Array()
	for f in tri.size():
		parent.append(f)
	for e: Vector2i in faces.edges:
		var on: Array = faces.edges[e]
		for k in range(1, on.size()):
			if ns[int(on[0])].dot(ns[int(on[k])]) > PLANE_DOT:
				var ra := _root(parent, int(on[0]))
				var rb := _root(parent, int(on[k]))
				if ra != rb:
					parent[rb] = ra
	var groups := {}
	for f in tri.size():
		var r := _root(parent, f)
		if not groups.has(r):
			groups[r] = PackedInt32Array()
		var g: PackedInt32Array = groups[r]
		g.append(f)
		groups[r] = g
	return groups.values()


static func _root(parent: PackedInt32Array, f: int) -> int:
	var r := f
	while parent[r] != r:
		r = parent[r]
	return r


## The record of one slope (`group` faces of `faces`) without its id, kind and material; {} for a
## slope too small or whose outline does not close.
static func _record(
	group: PackedInt32Array,
	faces: Dictionary,
	verts: PackedVector3Array,
	cols: Variant,
	idx: PackedInt32Array,
	wid: PackedInt32Array
) -> Dictionary:
	var tri: PackedInt32Array = faces.tri
	var ns: PackedVector3Array = faces.n
	var areas: PackedFloat32Array = faces.area
	var area := 0.0
	var nsum := Vector3.ZERO
	var paint := Vector3.ZERO
	var in_group := {}
	# Directed outline steps (welded a -> b, a face's own winding) and where each welded id lies.
	var steps := {}
	var at := {}
	for f in group:
		area += areas[f]
		nsum += ns[f] * areas[f]
		in_group[f] = true
		for k in 3:
			var i := idx[tri[f] + k]
			at[wid[i]] = verts[i]
			if cols != null:
				var c: Color = (cols as PackedColorArray)[i]
				paint += Vector3(c.r, c.g, c.b)
	if area < MIN_AREA_M2:
		return {}
	var shared := {}
	for f in group:
		for k in 3:
			var a := wid[idx[tri[f] + k]]
			var b := wid[idx[tri[f] + (k + 1) % 3]]
			var mine := 0
			var other := false
			for g: int in faces.edges[_edge(a, b)]:
				if in_group.has(g):
					mine += 1
				else:
					other = true
			if mine == 1:
				steps[a] = b
				shared[a] = other
	var loop := _loop(steps)
	if loop.size() < 3:
		return {}
	var n := nsum.normalized()
	var flat := n.y > FLAT_UP
	var v := (Vector3.UP - n * n.y).normalized()
	if flat:
		# A flat roof has no fall line: its frame runs along its longest side, every side an eave.
		var longest := Vector3.ZERO
		for k in loop.size():
			var d: Vector3 = (at[loop[(k + 1) % loop.size()]] as Vector3) - at[loop[k]]
			if d.length() > longest.length():
				longest = d
		v = n.cross(longest).normalized()
	var u := v.cross(n).normalized()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w: int in loop:
		var p: Vector3 = at[w]
		lo = Vector2(minf(lo.x, p.dot(u)), minf(lo.y, p.dot(v)))
		hi = Vector2(maxf(hi.x, p.dot(u)), maxf(hi.y, p.dot(v)))
	if minf(hi.x - lo.x, hi.y - lo.y) < (FLAT_MIN_M if flat else SLOPE_MIN_M):
		return {}
	var p0: Vector3 = at[loop[0]]
	var origin := p0 + u * (lo.x - p0.dot(u)) + v * (lo.y - p0.dot(v))
	var edges: Array = []
	for side: Array in _sides(loop, at, shared):
		var a: Vector3 = side[0]
		var b: Vector3 = side[1]
		var kind := "eave" if flat else _side_kind(a, b, bool(side[2]), u, v, lo.y, hi.y)
		edges.append({"kind": kind, "a": a, "b": b})
	var count := float(group.size() * 3)
	var mean := paint / count if cols != null else Vector3.ONE
	return {
		"n": n,
		"origin": origin,
		"u": u,
		"v": v,
		"u_len": hi.x - lo.x,
		"v_len": hi.y - lo.y,
		"edges": edges,
		"tone": Color(mean.x, mean.y, mean.z),
	}


## The longest closed loop of outline `steps` (welded a -> b), as welded ids.
static func _loop(steps: Dictionary) -> PackedInt32Array:
	var best := PackedInt32Array()
	var used := {}
	for start: int in steps:
		if used.has(start):
			continue
		var loop := PackedInt32Array()
		var w := start
		while not used.has(w) and steps.has(w):
			used[w] = true
			loop.append(w)
			w = int(steps[w])
		if w == start and loop.size() > best.size():
			best = loop
	return best


## The loop's sides: [a, b, shared] with steps that run on in one line merged, `shared` true when
## most of a side's length is shared with another slope.
static func _sides(loop: PackedInt32Array, at: Dictionary, shared: Dictionary) -> Array:
	var count := loop.size()
	# The corners: where the outline turns.
	var corners: Array[int] = []
	for k in count:
		var prev: Vector3 = at[loop[(k + count - 1) % count]]
		var here: Vector3 = at[loop[k]]
		var next: Vector3 = at[loop[(k + 1) % count]]
		var d0 := (here - prev).normalized()
		var d1 := (next - here).normalized()
		if d0.cross(d1).length() > TURN or d0.dot(d1) < 0.0:
			corners.append(k)
	var out: Array = []
	for c in corners.size():
		var k0 := corners[c]
		var k1 := corners[(c + 1) % corners.size()]
		var along := 0.0
		var on_other := 0.0
		var k := k0
		while k != k1:
			var a: Vector3 = at[loop[k]]
			var b: Vector3 = at[loop[(k + 1) % count]]
			var length := a.distance_to(b)
			along += length
			if bool(shared.get(loop[k], false)):
				on_other += length
			k = (k + 1) % count
		out.append([at[loop[k0]], at[loop[k1]], on_other > along * 0.5])
	return out


## What a side a-b of a slope (frame `u` along the eave, `v` up the slope, from `lo` to `hi` metres
## up it) is: "eave", "ridge", "hip", "verge", or "step" (a level side partway up). Pure.
static func _side_kind(
	a: Vector3, b: Vector3, shared: bool, u: Vector3, v: Vector3, lo: float, hi: float
) -> String:
	if absf(a.y - b.y) < LEVEL_M:
		if maxf(a.dot(v), b.dot(v)) - lo < EDGE_M:
			return "eave"
		if hi - minf(a.dot(v), b.dot(v)) < EDGE_M:
			return "ridge"
		return "step"
	var d := b - a
	if shared or absf(d.dot(u)) > HIP_ALONG * d.length():
		return "hip"
	return "verge"
