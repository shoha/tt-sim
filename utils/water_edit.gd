class_name WaterEdit
extends RefCounted

## Edits of a MapDocument's water model (water_bodies, pond_mask) for the carve and the
## Water tool, pure: a river stroke split into flat reaches, pond areas painted and erased on
## the sample grid, rivers cut where water is erased, and whole-model snapshots for history.
## The ground the water carves is WaterCarve's. Summary: docs/ARCHITECTURE.md "Carving
## water".
##
## Rivers. A stroke's line is resampled every RESAMPLE_M (a drawn line arrives with a point
## per frame; the reaches, the erase and the flow bake cost per point, and the course is
## Chaikin-smoothed anyway), then split into flat reaches by the ground along it
## (WaterGeometry.reach_ranges: no reach spans more than REACH_DROP_M), each a river body at
## its reach's level, consecutive reaches sharing their boundary point. A line that starts
## or ends in existing water joins it (join_line(): a confluence).
##
## Erasing (P4-4). A river the eraser touches goes whole: every reach of its stroke (the
## reaches joined end to end, river_chain()), never a piece of one. A hole cut mid-reach left
## two ends draining into a dry channel (P4-3), and so did one reach of a stroke erased on its
## own (the reach above spilled over its crest into the dry riffle); so do the streams that
## flow into it (their end in its water), which would spill into its dry channel. A pond loses
## the samples under the eraser, is dropped once it has none, and otherwise settles to the
## lowest ground on its new rim (erased_bodies()), so its water never stands against the
## erased part of its basin.

## Spacing of a river's control points (metres).
const RESAMPLE_M := 2.0
## A river joining other water ends this far past that water's edge (join_line()).
const JOIN_INSET_M := 0.6
const COMPRESSION := FileAccess.COMPRESSION_ZSTD


## A copy of `doc`'s water model for history: {"bodies": Array[WaterBody] (deep copies),
## "pond_mask": the mask ZSTD-compressed (a mask is mostly zeros), "pond_size": its length}.
static func model_of(doc: MapDocument) -> Dictionary:
	var bodies: Array[WaterBody] = []
	for body in doc.water_bodies:
		bodies.append(body.copy())
	var mask := doc.pond_mask
	var packed := mask.compress(COMPRESSION) if not mask.is_empty() else PackedByteArray()
	return {"bodies": bodies, "pond_mask": packed, "pond_size": mask.size()}


## Puts a model_of() copy into `doc` (new arrays, never the stored ones, so history is not
## aliased).
static func apply_model(doc: MapDocument, model: Dictionary) -> void:
	var bodies: Array[WaterBody] = []
	for body: WaterBody in model.get("bodies", []):
		bodies.append(body.copy())
	doc.water_bodies = bodies
	var size: int = model.get("pond_size", 0)
	var packed: PackedByteArray = model.get("pond_mask", PackedByteArray())
	doc.pond_mask = packed.decompress(size, COMPRESSION) if size > 0 else PackedByteArray()


## Bytes a model_of() copy holds (for the history budget): the compressed mask and the
## rivers' points and widths.
static func model_bytes(model: Dictionary) -> int:
	var total: int = (model.get("pond_mask", PackedByteArray()) as PackedByteArray).size()
	for body: WaterBody in model.get("bodies", []):
		total += 64 + body.points.size() * 12
	return total


## `points` (with one half-width per point in `widths`) resampled every `spacing` metres of
## arc length, keeping both ends. [PackedVector2Array, PackedFloat32Array].
static func resample(
	points: PackedVector2Array, widths: PackedFloat32Array, spacing: float = RESAMPLE_M
) -> Array:
	var out_points := PackedVector2Array()
	var out_widths := PackedFloat32Array()
	if points.is_empty():
		return [out_points, out_widths]
	var sizes := widths
	if sizes.size() != points.size():
		sizes = PackedFloat32Array()
		sizes.resize(points.size())
		sizes.fill(widths[0] if not widths.is_empty() else WaterBody.MIN_HALF_WIDTH_M)
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	if total <= 1e-6:
		return [PackedVector2Array([points[0]]), PackedFloat32Array([sizes[0]])]
	var count := maxi(1, roundi(total / spacing))
	var interval := total / count
	var segment := 0
	var walked := 0.0
	for n in count + 1:
		var target := minf(n * interval, total)
		while segment < points.size() - 2:
			var length := points[segment].distance_to(points[segment + 1])
			if walked + length >= target:
				break
			walked += length
			segment += 1
		var length := points[segment].distance_to(points[segment + 1])
		var t := clampf((target - walked) / length, 0.0, 1.0) if length > 1e-9 else 0.0
		out_points.append(points[segment].lerp(points[segment + 1], t))
		out_widths.append(lerpf(sizes[segment], sizes[segment + 1], t))
	return [out_points, out_widths]


## The river bodies a stroke along `points` (map XZ, upstream first; `half_widths` per
## point) of depth class `depth` and flow `speed` becomes on `doc` as it is now: resampled,
## split into flat reaches (see the header), ids after the document's. Empty when the line
## is shorter than two points, the document has no room for them (MAX_WATER_BODIES,
## MAX_RIVERS) or no heights. Half-widths are clamped to WaterBody's range and to at least
## the depth class's WaterCarve.min_half_width() (ankle 0.44 m, waist 1.33 m, deep 2.96 m).
static func plan_river(
	doc: MapDocument,
	points: PackedVector2Array,
	half_widths: PackedFloat32Array,
	depth: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	if doc.heights.size() != doc.sample_count():
		return bodies
	var joined := join_line(doc, points, half_widths)
	var line: Array = resample(joined[0], joined[1])
	var course: PackedVector2Array = line[0]
	var widths: PackedFloat32Array = line[1]
	if course.size() < 2:
		return bodies
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	for i in widths.size():
		widths[i] = clampf(widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
	var ground := WaterGeometry.ground_along(doc, course)
	# Confluences: under existing water the line reads that water's level (plus the freeboard)
	# as its ground, so the reach that meets it is at its level or below, never down on its
	# bed (see join_line()).
	for i in course.size():
		var level := WaterGeometry.level_at(doc, course[i])
		if level != WaterGeometry.DRY and ground[i] < level:
			ground[i] = level + WaterGeometry.FREEBOARD_M
	var ranges := WaterGeometry.reach_ranges(ground)
	var rivers := 0
	for body in doc.water_bodies:
		rivers += 1 if body.is_river() else 0
	if (
		doc.water_bodies.size() + ranges.size() > MapDocument.MAX_WATER_BODIES
		or rivers + ranges.size() > MapDocument.MAX_RIVERS
	):
		return bodies
	var next := doc.next_water_id()
	var used := {}
	for body in doc.water_bodies:
		used[body.id] = true
	for reach in ranges:
		while next > 0 and next <= WaterBody.MAX_ID and used.has(next):
			next += 1
		if next <= 0 or next > WaterBody.MAX_ID:
			bodies.clear()
			return bodies
		used[next] = true
		var river := WaterBody.river(
			next,
			course.slice(reach.x, reach.y + 1),
			widths.slice(reach.x, reach.y + 1),
			depth,
			WaterGeometry.reach_level(ground, reach),
			clampf(speed, 0.0, WaterBody.MAX_SPEED)
		)
		bodies.append(river)
	return bodies


## A river line (map XZ, upstream first, with one half-width per point, or one for all) cut
## where it runs into existing water of `doc` (WaterGeometry.is_wet_at): a line that starts
## inside a river or pond keeps only its last point in the water before it leaves it (an
## outflow), and one that ends inside water keeps only its first point in it (an inflow, a
## confluence). That point, just past the other water's edge, is where the new channel meets
## it: the carve leaves that end open (no taper, WaterCarve.river_goals) and plan_river reads
## the other water's level there, so the two meet without a dry lip or a gap. Points in the
## water between two dry stretches (a line crossing a river) stay. [PackedVector2Array,
## PackedFloat32Array]; fewer than two points when the whole line lies in water.
static func join_line(
	doc: MapDocument, points: PackedVector2Array, half_widths: PackedFloat32Array
) -> Array:
	var widths := half_widths
	if widths.size() != points.size():
		widths = PackedFloat32Array()
		widths.resize(points.size())
		widths.fill(half_widths[0] if not half_widths.is_empty() else WaterBody.MIN_HALF_WIDTH_M)
	if doc.water_bodies.is_empty() or points.size() < 2:
		return [points, widths]
	var wet := PackedByteArray()
	wet.resize(points.size())
	var dry_first := -1
	var dry_last := -1
	for i in points.size():
		if WaterGeometry.is_wet_at(doc, points[i]):
			wet[i] = 1
		elif dry_first < 0:
			dry_first = i
		if wet[i] == 0:
			dry_last = i
	if dry_first < 0:
		return [PackedVector2Array(), PackedFloat32Array()]
	var first := maxi(dry_first - 1, 0)
	var last := mini(dry_last + 1, points.size() - 1)
	var line := points.slice(first, last + 1)
	# The joining point just past the other water's edge, however far apart the drawn points.
	if wet[first] == 1:
		line[0] = _junction(doc, points[first], points[first + 1])
	if wet[last] == 1 and last > first:
		line[-1] = _junction(doc, points[last], points[last - 1])
	return [line, widths.slice(first, last + 1)]


## Where the segment from `wet` (a point in water) to `dry` enters the water, found by
## bisection, moved JOIN_INSET_M into it (never past `wet`).
static func _junction(doc: MapDocument, wet: Vector2, dry: Vector2) -> Vector2:
	var inside := wet
	var outside := dry
	for _step in 12:
		var middle := (inside + outside) * 0.5
		if WaterGeometry.is_wet_at(doc, middle):
			inside = middle
		else:
			outside = middle
	var inward := wet - inside
	if inward.length() <= JOIN_INSET_M:
		return wet
	return inside + inward.normalized() * JOIN_INSET_M


## `doc`'s bodies with `added` appended, as a new array.
static func with_bodies(doc: MapDocument, added: Array[WaterBody]) -> Array[WaterBody]:
	var bodies: Array[WaterBody] = []
	bodies.assign(doc.water_bodies)
	bodies.append_array(added)
	return bodies


## The id a new pond painted from map point `at` gets: the pond already under it (so a
## stroke from inside a pond extends it), else a new id; -1 when there is no room.
static func pond_id_at(doc: MapDocument, at: Vector2) -> int:
	if doc.pond_mask.size() == doc.sample_count():
		var s := doc.world_to_sample(at).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		var id := doc.pond_mask[doc.sample_index(x, z)]
		if id != 0 and doc.water_body(id) != null:
			return id
	return doc.next_water_id()


## Writes `value` into `mask` (a pond mask of `doc`'s grid) for every sample within `radius`
## of the segment `from`-`to` (map XZ) whose byte is in `over` (bytes that may be replaced),
## marking each byte it replaced in `replaced` (byte -> true). Returns the rectangle of
## samples changed.
static func stamp(
	doc: MapDocument,
	mask: PackedByteArray,
	from: Vector2,
	to: Vector2,
	radius: float,
	value: int,
	over: PackedByteArray,
	replaced: Dictionary = {}
) -> Rect2i:
	var rect := MaskBrush.capsule_rect(doc, from, to, radius)
	var changed := Rect2i()
	if not rect.has_area() or mask.size() != doc.sample_count():
		return changed
	var replace := {}
	for b in over:
		replace[b] = true
	var width := doc.samples_x()
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2(origin.x + x * step.x, origin.y + z * step.y) - from
			var t := clampf(p.dot(segment) / length_sq, 0.0, 1.0) if length_sq > 0.0 else 0.0
			if (p - segment * t).length_squared() >= radius_sq:
				continue
			var i := z * width + x
			if mask[i] == value or not replace.has(mask[i]):
				continue
			replaced[mask[i]] = true
			mask[i] = value
			changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	return changed


## Marks in `touched` (body id -> true) every river reach of `doc` whose water the eraser
## capsule from `from` to `to` (map XZ) of `radius` reaches (its course, river_course(), comes
## within `radius` plus the half-width there), with the whole river it belongs to
## (river_chain()) and the rivers ending in it (_touch_tributaries()). Returns true when a
## reach was newly marked.
static func touch_rivers(
	doc: MapDocument, touched: Dictionary, from: Vector2, to: Vector2, radius: float
) -> bool:
	var any := false
	for body in doc.water_bodies:
		if not body.is_river() or touched.has(body.id):
			continue
		var course := WaterGeometry.river_course(body)
		var line: PackedVector2Array = course[0]
		var widths: PackedFloat32Array = course[1]
		for s in line.size() - 1:
			var hit := segment_distance(from, to, line[s], line[s + 1])
			if hit.x <= radius + lerpf(widths[s], widths[s + 1], hit.y):
				for id in river_chain(doc.water_bodies, body.id):
					touched[id] = true
				any = true
				break
	if any:
		_touch_tributaries(doc, touched)
	return any


## Adds to `touched` every river (whole, river_chain()) with an end in the water of a
## touched one: a stream that flowed into an erased river would end spilling into its dry
## channel.
static func _touch_tributaries(doc: MapDocument, touched: Dictionary) -> void:
	var grew := true
	while grew:
		grew = false
		for body in doc.water_bodies:
			if not body.is_river() or touched.has(body.id) or body.points.size() < 2:
				continue
			for end in [body.points[0], body.points[-1]]:
				if _in_touched(doc, touched, end):
					for id in river_chain(doc.water_bodies, body.id):
						touched[id] = true
					grew = true
					break


## True when map point `p` lies in the area of a river in `touched` (its half-width plus the
## bank of its course).
static func _in_touched(doc: MapDocument, touched: Dictionary, p: Vector2) -> bool:
	for body in doc.water_bodies:
		if not touched.has(body.id):
			continue
		var course := WaterGeometry.river_course(body)
		var near := WaterGeometry.nearest_on_polyline(course[0], p)
		if near.y < 0:
			continue
		var half := WaterGeometry.width_at(course[1], int(near.y), near.z)
		if near.x <= half + WaterGeometry.RIVER_BANK_M:
			return true
	return false


## The ids of the river `id` and every reach joined to it end to end (the reaches of one
## stroke share their boundary points, WaterGeometry.flush_ends), upstream and downstream.
static func river_chain(bodies: Array[WaterBody], id: int) -> PackedInt32Array:
	var chain := PackedInt32Array([id])
	var grew := true
	while grew:
		grew = false
		for body in bodies:
			if not body.is_river() or body.points.size() < 2 or chain.has(body.id):
				continue
			for other in bodies:
				if not chain.has(other.id) or not other.is_river() or other.points.size() < 2:
					continue
				var joined := (
					(
						other.points[-1].distance_squared_to(body.points[0])
						< WaterGeometry.JOIN_EPSILON_SQ
					)
					or (
						other.points[0].distance_squared_to(body.points[-1])
						< WaterGeometry.JOIN_EPSILON_SQ
					)
				)
				if joined:
					chain.append(body.id)
					grew = true
					break
	return chain


## The shortest distance between segments a0-a1 and b0-b1 and where it falls on b0-b1:
## Vector2(distance, t along b 0..1).
static func segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Vector2:
	var best := Vector2(INF, 0.0)
	# Each end against the other segment; crossing segments meet at distance 0.
	for k in 4:
		var p: Vector2 = [a0, a1, b0, b1][k]
		var on_b := k < 2
		var s0 := b0 if on_b else a0
		var s1 := b1 if on_b else a1
		var d := s1 - s0
		var t := (
			clampf((p - s0).dot(d) / d.length_squared(), 0.0, 1.0) if d != Vector2.ZERO else 0.0
		)
		var dist := p.distance_to(s0 + d * t)
		if dist < best.x:
			# On b: where a's end projects; b's own ends are at 0 and 1.
			best = Vector2(dist, t if on_b else float(k - 2))
	var hit: Variant = Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
	if hit is Vector2:
		var db := b1 - b0
		var along := clampf(((hit as Vector2) - b0).dot(db) / db.length_squared(), 0.0, 1.0)
		best = Vector2(0.0, along if db != Vector2.ZERO else 0.0)
	return best


## `doc`'s bodies after an erase (see the header): without the river reaches in `touched`
## (body id -> true), and with the ponds that still hold a sample of `doc.pond_mask`; a
## pond in `shrunk` (id -> true: the eraser took some of its samples) settles to the level of
## its new rim (WaterGeometry.pond_rim_level on `doc`'s heights, a copy of the body). A new
## array.
static func erased_bodies(
	doc: MapDocument, touched: Dictionary, shrunk: Dictionary = {}
) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var present := PackedInt32Array()
	present.resize(WaterBody.MAX_ID + 1)
	for id in doc.pond_mask:
		present[id] += 1
	for body in doc.water_bodies:
		if body.is_river():
			if not touched.has(body.id):
				out.append(body)
			continue
		if present[body.id] == 0:
			continue
		if shrunk.has(body.id):
			var level := WaterGeometry.pond_rim_level(doc, body.id)
			if not is_nan(level):
				var settled := body.copy()
				settled.level_m = minf(level, body.level_m)
				out.append(settled)
				continue
		out.append(body)
	return out


## The map XZ bounds of every river of `bodies` grown by its widest half-width plus the
## bank (the area its water and dressing can reach), merged; empty with no river.
static func rivers_bounds(bodies: Array[WaterBody], pad: float) -> Rect2:
	var out := Rect2()
	var any := false
	for body in bodies:
		if not body.is_river() or body.points.is_empty():
			continue
		var widest := 0.0
		for w in body.half_widths:
			widest = maxf(widest, w)
		var box := WaterGeometry.bounds(body.points, widest + pad)
		out = box if not any else out.merge(box)
		any = true
	return out
