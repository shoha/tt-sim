class_name TerraWaterBridge
extends RefCounted
## The water half of the bridge (card terraform-p2-bridge-water; docs/systems/terraform.md "The
## bridge", water.md "Water model"): the core's derived water (TerraDerive.water_records() and
## falls()) turned into today's water model, MapDocument.water_bodies and pond_mask, so the game's
## water consumers (WaterGeometry, AuthoredWater, the wet dressing, the flow bake, the Painted water
## field, zones and tokens) build from the derive unchanged. Pure: no Node, safe on any thread.
##
## Rivers. The derive solves each river primitive as flat reaches (card terraform-p2-bridge): its
## record holds the downstream line (0.25 m apart, already smoothed and flipped when drawn uphill)
## and one level per point. Every run of equal levels is one WaterBody.river at that level.
## Consecutive reaches share the midpoint of the segment their levels step across, where the
## derive's water changes level (the carve's water takes the nearer point's reach), and where a
## step of FALL_MIN or more puts its fall record; WaterGeometry's flush end cuts each reach there.
## Within a reach the line keeps every LINE_STRIDE-th point (about 1 m; today's control lines are
## 2 m apart), since WaterGeometry smooths and rasterises the control line itself. The half-width
## is the record's; the depth class the nearest to the primitive's depth (ties deeper, so the
## carved bed is never deeper than the class holds: WaterMeshBuilder.hold_depth). Points past the
## map edge become the course into the skirt: the first reach's `beyond_up` and the last reach's
## `beyond` (RiverExits.split_line's rule, the crossing points kept just inside the edge).
##
## Ponds. A pond's record holds its level; its area is its primitive's outline, rounded as the
## derive rounds it (Chaikin, 3 passes, closed), rasterised to pond_mask at the document samples.
##
## Ids are a pure function of the document: rivers in document order, each one's reaches
## downstream, then ponds, numbered from 1, so a reload or a late joiner derives the host's ids.
## Caps (MapDocument.MAX_WATER_BODIES, MAX_RIVERS) are refused, never truncated: the tools check
## them before an add (card terraform-p2-water), and bodies() returns an error past them.

## Every this-many points of a record's 0.25 m line are kept in a reach's control line.
const LINE_STRIDE := 4
## A fall record lies on the step it was made for within this (it is the step's midpoint).
const FALL_MATCH_M := 0.05
## Chaikin passes the derive rounds a pond outline with (terra_water.cpp water_geometry).
const POND_ROUNDING := 3


## The water model of the derived `records` (TerraDerive.water_records()) and `falls`
## (TerraDerive.falls(), 7 floats a record) on `doc`'s grid, reading the pond outlines and the
## depths from `doc.terra`: {"bodies": Array[WaterBody], "pond_mask": PackedByteArray (empty
## without a pond)}, or {"error": String} past a cap (see the header).
static func bodies(records: Dictionary, falls: PackedFloat32Array, doc: MapDocument) -> Dictionary:
	var terra := doc.terra as TerraDoc
	var out: Array[WaterBody] = []
	var next := 1
	var rivers := 0
	for r: Dictionary in records.get("rivers", []):
		var prim := terra.find(int(r["id"])) if terra != null else {}
		var depth := depth_class(_prim_depth(prim, 1, 0.5))
		var reaches := river_reaches(r, falls, doc, depth, next)
		next += reaches.size()
		rivers += reaches.size()
		out.append_array(reaches)
	var mask := PackedByteArray()
	var ponds: Array = records.get("ponds", [])
	if not ponds.is_empty():
		mask.resize(doc.sample_count())
	for p: Dictionary in ponds:
		var prim := terra.find(int(p["id"])) if terra != null else {}
		if prim.is_empty():
			continue
		var data: PackedFloat32Array = prim["data"]
		var body := WaterBody.pond(next, depth_class(data[0]), float(p["level"]))
		if next <= WaterBody.MAX_ID:
			rasterise(rounded_outline(data.slice(1)), doc, next, mask)
		next += 1
		out.append(body)
	if rivers > MapDocument.MAX_RIVERS:
		return {"error": "too many rivers (%d reaches, the cap is %d)" % [rivers, MapDocument.MAX_RIVERS]}
	if out.size() > MapDocument.MAX_WATER_BODIES:
		return {
			"error":
			"too many water bodies (%d, the cap is %d)" % [out.size(), MapDocument.MAX_WATER_BODIES]
		}
	return {"bodies": out, "pond_mask": mask}


## The reaches of one river record `r` (see the header), ids from `first_id`, depth class `depth`.
static func river_reaches(
	r: Dictionary, falls: PackedFloat32Array, doc: MapDocument, depth: int, first_id: int
) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var flat: PackedFloat32Array = r["pts"]
	var lv: PackedFloat32Array = r["level"]
	var line := PackedVector2Array()
	for k in range(0, flat.size() - 1, 2):
		line.append(Vector2(flat[k], flat[k + 1]))
	if line.size() < 2 or lv.size() != line.size():
		return out
	var half := doc.extent_m() * 0.5
	var first := -1
	var last := -1
	for i in line.size():
		if RiverExits.edge_distance(line[i], half) >= 0.0:
			if first < 0:
				first = i
			last = i
	if first < 0:
		return out
	var hw := clampf(float(r["hw"]), WaterBody.MIN_HALF_WIDTH_M, WaterBody.MAX_HALF_WIDTH_M)
	var split := RiverExits.split_line(
		line, PackedFloat32Array([hw]), half, AuthoredTerrain.skirt_width_m()
	)
	var inside: PackedVector2Array = split.inside
	# One level per inside point: the crossing points split_line adds take their neighbour's.
	var levels := PackedFloat32Array()
	if first > 0:
		levels.append(lv[first])
	levels.append_array(lv.slice(first, last + 1))
	if last < line.size() - 1:
		levels.append(lv[last])
	if levels.size() != inside.size():
		return out
	var runs := level_runs(levels)
	for k in runs.size():
		var run: Vector2i = runs[k]
		var pts := PackedVector2Array()
		if k > 0:
			pts.append(_step_point(inside, run.x - 1, falls))
		for i in range(run.x, run.y + 1, LINE_STRIDE):
			pts.append(inside[i])
		if (run.y - run.x) % LINE_STRIDE != 0:
			pts.append(inside[run.y])
		if k < runs.size() - 1:
			pts.append(_step_point(inside, run.y, falls))
		if pts.size() < 2:
			continue
		var widths := PackedFloat32Array()
		widths.resize(pts.size())
		widths.fill(hw)
		var body := WaterBody.river(
			first_id + out.size(), pts, widths, depth as WaterBody.Depth, levels[run.x]
		)
		out.append(body)
	if not out.is_empty():
		out[0].beyond_up = split.up
		out[-1].beyond = split.down
	return out


## The runs of equal values of `levels` in order: Vector2i(first index, last index) each.
static func level_runs(levels: PackedFloat32Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var start := 0
	for i in levels.size():
		if i == levels.size() - 1 or levels[i + 1] != levels[i]:
			out.append(Vector2i(start, i))
			start = i + 1
	return out


## The depth class nearest `depth_m` (WaterBody.DEPTH_M; a tie takes the deeper class).
static func depth_class(depth_m: float) -> WaterBody.Depth:
	var best := 0
	for c in WaterBody.DEPTH_M.size():
		if absf(WaterBody.DEPTH_M[c] - depth_m) <= absf(WaterBody.DEPTH_M[best] - depth_m) + 1e-6:
			best = c
	return best as WaterBody.Depth


## A pond primitive's outline floats (x, z pairs) rounded as the derive rounds it: Chaikin
## corner cutting as a closed loop, POND_ROUNDING passes.
static func rounded_outline(flat: PackedFloat32Array) -> PackedVector2Array:
	var loop := PackedVector2Array()
	for k in range(0, flat.size() - 1, 2):
		loop.append(Vector2(flat[k], flat[k + 1]))
	for _pass in POND_ROUNDING:
		var n := loop.size()
		if n < 3:
			break
		var next := PackedVector2Array()
		for k in n:
			var a := loop[k]
			var b := loop[(k + 1) % n]
			next.append(a * 0.75 + b * 0.25)
			next.append(a * 0.25 + b * 0.75)
		loop = next
	return loop


## Writes `id` into `mask` (one byte per document sample of `doc`) at every sample inside
## `outline` (map XZ).
static func rasterise(
	outline: PackedVector2Array, doc: MapDocument, id: int, mask: PackedByteArray
) -> void:
	if outline.size() < 3:
		return
	var box := WaterGeometry.bounds(outline, 0.0)
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	var lo := doc.world_to_sample(box.position).floor().clamp(Vector2.ZERO, last)
	var hi := doc.world_to_sample(box.end).ceil().clamp(Vector2.ZERO, last)
	for z in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			if Geometry2D.is_point_in_polygon(doc.sample_to_world(Vector2(x, z)), outline):
				mask[doc.sample_index(x, z)] = id


## A key that changes whenever bodies() would answer differently for the same grid: the water
## records, the fall records and the water primitives' floats (depths and pond outlines) of
## `terra`. SHA-256 bytes.
static func signature(
	records: Dictionary, falls: PackedFloat32Array, terra: TerraDoc
) -> PackedByteArray:
	var b := PackedByteArray()
	var digest := PackedByteArray()
	digest.resize(8)
	digest.encode_s64(0, TerraCache.water_digest(records))
	b.append_array(digest)
	b.append_array(falls.to_byte_array())
	if terra != null:
		for p in terra.prims:
			var kind := int(p["kind"])
			if (kind == TerraCore.RIVER or kind == TerraCore.POND) and not TerraDoc.is_muted(p):
				var head := PackedByteArray()
				head.resize(8)
				head.encode_s32(0, int(p["id"]))
				head.encode_s32(4, kind)
				b.append_array(head)
				b.append_array((p["data"] as PackedFloat32Array).to_byte_array())
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	if not b.is_empty():
		ctx.update(b)
	return ctx.finish()


## The document samples over which the water changed from `old_bodies` and `old_mask` to
## `new_bodies` and `new_mask` on `doc`'s grid: every river that is not in both lists alike
## (WaterEdit.rivers_bounds with the carve's bank reach), every pond whose level or depth moved
## and every mask sample that differs. An empty rect when nothing changed.
static func region(
	doc: MapDocument,
	old_bodies: Array[WaterBody],
	old_mask: PackedByteArray,
	new_bodies: Array[WaterBody],
	new_mask: PackedByteArray
) -> Rect2i:
	var moved: Array[WaterBody] = []
	var moved_ponds := {}
	for pair in [[old_bodies, new_bodies], [new_bodies, old_bodies]]:
		var by_id := {}
		for body: WaterBody in pair[1]:
			by_id[body.id] = body
		for body: WaterBody in pair[0]:
			if by_id.has(body.id) and same(body, by_id[body.id]):
				continue
			if body.is_river():
				moved.append(body)
			else:
				moved_ponds[body.id] = true
	var rect := Rect2i()
	var bounds := WaterEdit.rivers_bounds(moved, WaterCarve.BANK_REACH_M)
	if bounds.has_area():
		var first := Vector2i(doc.world_to_sample(bounds.position).floor())
		var last := Vector2i(doc.world_to_sample(bounds.end).ceil())
		rect = Rect2i(first, last - first + Vector2i.ONE)
	var nx := doc.samples_x()
	var nz := doc.samples_z()
	var count := doc.sample_count()
	var empty := PackedByteArray()
	empty.resize(nx)
	var lo := Vector2i(nx, nz)
	var hi := Vector2i(-1, -1)
	if old_mask != new_mask or not moved_ponds.is_empty():
		# Row by row with native compares; only the rows that hold a change are walked.
		for z in nz:
			var a := old_mask.slice(z * nx, (z + 1) * nx) if old_mask.size() == count else empty
			var b := new_mask.slice(z * nx, (z + 1) * nx) if new_mask.size() == count else empty
			var touched := a != b
			for id: int in moved_ponds:
				touched = touched or a.has(id) or b.has(id)
			if not touched:
				continue
			for x in nx:
				if a[x] != b[x] or moved_ponds.has(a[x]) or moved_ponds.has(b[x]):
					lo = lo.min(Vector2i(x, z))
					hi = hi.max(Vector2i(x, z))
	if hi.x >= 0:
		var masked := Rect2i(lo, hi - lo + Vector2i.ONE)
		rect = masked if not rect.has_area() else rect.merge(masked)
	return rect.intersection(Rect2i(0, 0, nx, nz))


## True when two bodies are the same water (kind, depth, level, line, widths, speed, courses past
## the edge); ids are not compared.
static func same(a: WaterBody, b: WaterBody) -> bool:
	return (
		a.kind == b.kind
		and a.depth == b.depth
		and a.level_m == b.level_m
		and a.speed == b.speed
		and a.points == b.points
		and a.half_widths == b.half_widths
		and a.beyond == b.beyond
		and a.beyond_up == b.beyond_up
	)


## The shared point of the reaches either side of the step from inside[i] to inside[i + 1]: the
## segment's midpoint, or the fall record that sits on it (the same point; the record is the
## derive's word for where the fall is).
static func _step_point(inside: PackedVector2Array, i: int, falls: PackedFloat32Array) -> Vector2:
	var mid := (inside[i] + inside[i + 1]) * 0.5
	for k in range(0, falls.size() - 6, 7):
		var f := Vector2(falls[k], falls[k + 1])
		if f.distance_to(mid) <= FALL_MATCH_M:
			return f
	return mid


## A primitive's float `index` (its depth), or `fallback` without one.
static func _prim_depth(prim: Dictionary, index: int, fallback: float) -> float:
	if prim.is_empty():
		return fallback
	var data: PackedFloat32Array = prim["data"]
	return data[index] if data.size() > index else fallback
