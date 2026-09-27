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
## its reach's level, consecutive reaches sharing their boundary point.
##
## Erasing. A river loses the control points under the eraser and falls apart into the runs
## of at least two points that remain (the first keeps its id); a pond loses the samples
## under it and is dropped once it has none.

## Spacing of a river's control points (metres).
const RESAMPLE_M := 2.0
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
	var line: Array = resample(points, half_widths)
	var course: PackedVector2Array = line[0]
	var widths: PackedFloat32Array = line[1]
	if course.size() < 2:
		return bodies
	var narrowest := maxf(WaterBody.MIN_HALF_WIDTH_M, WaterCarve.min_half_width(depth))
	for i in widths.size():
		widths[i] = clampf(widths[i], narrowest, WaterBody.MAX_HALF_WIDTH_M)
	var ground := WaterGeometry.ground_along(doc, course)
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
## of the segment `from`-`to` (map XZ) whose byte is in `over` (bytes that may be replaced).
## Returns the rectangle of samples changed.
static func stamp(
	doc: MapDocument,
	mask: PackedByteArray,
	from: Vector2,
	to: Vector2,
	radius: float,
	value: int,
	over: PackedByteArray
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
			mask[i] = value
			changed = MaskBrush.merge_rect(changed, Rect2i(x, z, 1, 1))
	return changed


## Per river of `doc` (body id -> PackedByteArray, one byte per control point), 1 for the
## control points within `radius` of the segment `from`-`to`, merged into `hits`. Returns
## true when any point was newly hit.
static func hit_rivers(
	doc: MapDocument, hits: Dictionary, from: Vector2, to: Vector2, radius: float
) -> bool:
	var any := false
	var segment := to - from
	var length_sq := segment.length_squared()
	for body in doc.water_bodies:
		if not body.is_river():
			continue
		var marks: PackedByteArray = hits.get(body.id, PackedByteArray())
		if marks.size() != body.points.size():
			marks.resize(body.points.size())
		for i in body.points.size():
			if marks[i] != 0:
				continue
			var p := body.points[i] - from
			var t := clampf(p.dot(segment) / length_sq, 0.0, 1.0) if length_sq > 0.0 else 0.0
			if (p - segment * t).length() < radius:
				marks[i] = 1
				any = true
		hits[body.id] = marks
	return any


## `doc`'s bodies after an erase: rivers without the control points `hits` marks (split into
## the remaining runs, see the header; new ids after `doc`'s), and ponds that still hold a
## sample of `doc.pond_mask`. A new array.
static func erased_bodies(doc: MapDocument, hits: Dictionary) -> Array[WaterBody]:
	var out: Array[WaterBody] = []
	var present := {}
	for id in doc.pond_mask:
		present[id] = true
	var used := {}
	for body in doc.water_bodies:
		used[body.id] = true
	var next := 1
	for body in doc.water_bodies:
		if not body.is_river():
			if present.has(body.id):
				out.append(body)
			continue
		var marks: PackedByteArray = hits.get(body.id, PackedByteArray())
		if marks.count(1) == 0:
			out.append(body)
			continue
		var first := true
		var start := -1
		for i in body.points.size() + 1:
			var kept := i < body.points.size() and marks[i] == 0
			if kept and start < 0:
				start = i
			if kept or start < 0:
				continue
			if i - start >= 2:
				var piece := body.copy()
				piece.points = body.points.slice(start, i)
				piece.half_widths = body.half_widths.slice(start, i)
				if not first:
					while used.has(next) and next <= WaterBody.MAX_ID:
						next += 1
					if next > WaterBody.MAX_ID or out.size() >= MapDocument.MAX_WATER_BODIES:
						break
					piece.id = next
					used[next] = true
				first = false
				out.append(piece)
			start = -1
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
