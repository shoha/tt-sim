class_name WaterGeometry
extends RefCounted

## Pure geometry of the authored water model (MapDocument.water_bodies, WaterBody): river
## courses, distance to a polyline, the area and wet samples of each body, per-sample
## water levels, and the level rules. Shared by the flow bake (WaterFlowBaker), the
## carve and the water surface. Summary: docs/ARCHITECTURE.md "Water model and flow bake".
##
## Areas. A river's area is every point within its half-width plus RIVER_BANK_M of its
## course (the Chaikin-smoothed control line, river_course()), the half-width taken at
## the nearest point of the course; the bank margin lets carved soft banks stay wet where
## they dip below the level. At an end where another river continues (the next reach of the
## same stroke: its first point is this one's last, flush_ends()) the area stops flush at
## the shared point instead of reaching round it, so a reach's flat water ends at the crest
## the carve leaves there (WaterCarve) and never hangs over the lower reach's riffle. A
## pond's area is the samples of MapDocument.pond_mask holding
## its id. A sample is wet when it lies in a body's area and its ground is below that
## body's level; where areas overlap, the highest level wins.
##
## Level rules (every body is flat). A river's level is the lowest ground along its
## centreline minus FREEBOARD_M (reach_level()), so the surface sits below the banks all
## along it and the carve cuts the channel down to it. A stroke over sloped ground is split
## into reaches (reach_ranges(): no reach spans more than REACH_DROP_M of ground height
## along its centreline), each its own flat river body, the next reach starting at the
## point where the previous one ends; the step between reaches is where a waterfall can go
## later. A pond's level is the lowest ground on the rim of its painted area minus
## FREEBOARD_M (pond_rim_level()), so it fills the basin without spilling.

const CHAIKIN_ITERATIONS := 2
## Margin beyond a river's half-width that still belongs to its area (banks).
const RIVER_BANK_M := 1.0
## How far a new body's surface sits below the lowest bank or rim ground.
const FREEBOARD_M := 0.15
## Most ground height one flat river reach spans along its centreline.
const REACH_DROP_M := 0.5
## The level of a sample no water covers.
const DRY := -INF
## Two river ends closer than this (squared metres) are one shared point (flush_ends()).
const JOIN_EPSILON_SQ := 1e-6


## Chaikin corner cutting, terrain-paint's chaikin_smooth(): each pass replaces every
## segment by its 1/4 and 3/4 points, keeping both endpoints, so the course still starts
## upstream and ends at the mouth; a two-point line comes back unchanged. `widths` (one
## per point) is cut the same way. Returns [PackedVector2Array, PackedFloat32Array].
static func chaikin(
	points: PackedVector2Array, widths: PackedFloat32Array, iterations: int = CHAIKIN_ITERATIONS
) -> Array:
	var line := points
	var sizes := widths
	for _pass in iterations:
		var n := line.size()
		if n < 3 or sizes.size() != n:
			break
		var out_line := PackedVector2Array()
		var out_sizes := PackedFloat32Array()
		out_line.resize(2 * n - 2)
		out_sizes.resize(2 * n - 2)
		out_line[0] = line[0]
		out_sizes[0] = sizes[0]
		for i in n - 1:
			# Interior point 2i is the quarter point, 2i + 1 the three-quarter point; the
			# first and last interior points are replaced by the endpoints.
			if i > 0:
				out_line[2 * i] = line[i] * 0.75 + line[i + 1] * 0.25
				out_sizes[2 * i] = sizes[i] * 0.75 + sizes[i + 1] * 0.25
			if i < n - 2:
				out_line[2 * i + 1] = line[i] * 0.25 + line[i + 1] * 0.75
				out_sizes[2 * i + 1] = sizes[i] * 0.25 + sizes[i + 1] * 0.75
		out_line[2 * n - 3] = line[n - 1]
		out_sizes[2 * n - 3] = sizes[n - 1]
		line = out_line
		sizes = out_sizes
	return [line, sizes]


## A river's course: its control line and half-widths Chaikin-smoothed twice.
## [PackedVector2Array, PackedFloat32Array].
static func river_course(body: WaterBody) -> Array:
	return chaikin(body.points, body.half_widths)


## The nearest point of `points` (a polyline) to `p`: Vector3(distance, segment index,
## t along that segment 0..1). Degenerate segments are skipped; a tie goes to the earlier
## segment. Vector3(INF, -1, 0) when the polyline has no usable segment.
static func nearest_on_polyline(points: PackedVector2Array, p: Vector2) -> Vector3:
	var best := Vector3(INF, -1, 0)
	for s in points.size() - 1:
		var a := points[s]
		var segment := points[s + 1] - a
		var length_sq := segment.length_squared()
		if length_sq <= 1e-12:
			continue
		var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
		var distance := p.distance_to(a + segment * t)
		if distance < best.x:
			best = Vector3(distance, s, t)
	return best


## The half-width at segment `segment`, fraction `t`, of a course's widths.
static func width_at(widths: PackedFloat32Array, segment: int, t: float) -> float:
	return lerpf(widths[segment], widths[segment + 1], t)


## The bounding rectangle of `points`, grown by `pad` on every side.
static func bounds(points: PackedVector2Array, pad: float) -> Rect2:
	if points.is_empty():
		return Rect2()
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	return box.grow(pad)


## The nearest-segment field of one river course over a regular grid of `size` cells
## whose cell (i, j) sits at origin + Vector2(i, j) * step, computed for the cells within
## the course's widest half-width plus `bank` of it (a cell farther away cannot be in the
## river's reach). Returns {"rect": Rect2i of the cells covered, and PackedFloat32Arrays
## over that rect, row-major: "distance" to the nearest segment (INF where none is within
## reach), "half_width" at the nearest point, "tangent_x" and "tangent_z" of that
## segment's unit direction (downstream)}. A cell is in the river's reach when
## distance <= half_width + bank (in_reach()). Ties go to the earlier segment, as in
## terrain-paint's nearest_segment(). Looped per segment over its padded bounding box.
## `flush` (x: the start, y: the end; 1 = flush) cuts the course's area square at that end:
## a cell near the end (within twice the reach) on the far side of the line through it
## square to the course is not reached at all, so a reach that continues into the next one
## stops at their shared point instead of reaching round it (P4-3).
static func nearest_field(
	course: PackedVector2Array,
	widths: PackedFloat32Array,
	origin: Vector2,
	step: Vector2,
	size: Vector2i,
	bank: float,
	flush: Vector2i = Vector2i.ZERO
) -> Dictionary:
	var widest := 0.0
	for w in widths:
		widest = maxf(widest, w)
	var reach := widest + bank
	var rect := _cells_in(bounds(course, reach), origin, step, size)
	var count := rect.size.x * rect.size.y
	var distance := PackedFloat32Array()
	var half_width := PackedFloat32Array()
	var tangent_x := PackedFloat32Array()
	var tangent_z := PackedFloat32Array()
	distance.resize(count)
	distance.fill(INF)
	half_width.resize(count)
	tangent_x.resize(count)
	tangent_z.resize(count)
	# Flush ends: the half-plane beyond the end (near it) is cut off for every segment.
	var cut_start := flush.x != 0 and course.size() >= 2
	var cut_end := flush.y != 0 and course.size() >= 2
	var start_at := course[0] if cut_start else Vector2.ZERO
	var end_at := course[-1] if cut_end else Vector2.ZERO
	var start_dir := end_direction(course, false) if cut_start else Vector2.ZERO
	var end_dir := end_direction(course, true) if cut_end else Vector2.ZERO
	var cut_sq := 4.0 * reach * reach
	for s in course.size() - 1:
		var a := course[s]
		var segment := course[s + 1] - a
		var length_sq := segment.length_squared()
		if length_sq <= 1e-12:
			continue
		var tangent := segment / sqrt(length_sq)
		var box := Rect2(a, Vector2.ZERO).expand(course[s + 1]).grow(reach)
		var cells := _cells_in(box, origin, step, size).intersection(rect)
		var w0 := widths[s]
		var w1 := widths[s + 1]
		for j in range(cells.position.y, cells.end.y):
			var z := origin.y + j * step.y
			var row := (j - rect.position.y) * rect.size.x - rect.position.x
			for i in range(cells.position.x, cells.end.x):
				var p := Vector2(origin.x + i * step.x, z)
				if (
					cut_end
					and (p - end_at).dot(end_dir) > 0.0
					and p.distance_squared_to(end_at) < cut_sq
				):
					continue
				if (
					cut_start
					and (p - start_at).dot(start_dir) < 0.0
					and p.distance_squared_to(start_at) < cut_sq
				):
					continue
				var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
				var d := p.distance_to(a + segment * t)
				var k := row + i
				if d < distance[k]:
					distance[k] = d
					half_width[k] = lerpf(w0, w1, t)
					tangent_x[k] = tangent.x
					tangent_z[k] = tangent.y
	return {
		"rect": rect,
		"distance": distance,
		"half_width": half_width,
		"tangent_x": tangent_x,
		"tangent_z": tangent_z,
	}


## The unit direction of `course` at its end (`at_end`) or start, downstream, from its last
## (first) segment of non-zero length; Vector2.ZERO when there is none.
static func end_direction(course: PackedVector2Array, at_end: bool) -> Vector2:
	var n := course.size()
	for k in n - 1:
		var i := n - 2 - k if at_end else k
		var segment := course[i + 1] - course[i]
		if segment.length_squared() > 1e-12:
			return segment.normalized()
	return Vector2.ZERO


## True when cell `k` of a nearest_field() is within the river's half-width plus `bank`.
static func in_reach(field: Dictionary, k: int, bank: float) -> bool:
	return field["distance"][k] <= field["half_width"][k] + bank


## The water level at every sample of `doc`'s grid (row-major like heights): the highest
## level among the bodies whose area holds the sample, DRY where none does. A sample is
## wet where its height is below this (wet_mask()).
static func levels(doc: MapDocument) -> PackedFloat32Array:
	var count := doc.sample_count()
	var out := PackedFloat32Array()
	out.resize(count)
	out.fill(DRY)
	var pond_levels := PackedFloat32Array()
	pond_levels.resize(WaterBody.MAX_ID + 1)
	pond_levels.fill(DRY)
	var has_pond := false
	for body in doc.water_bodies:
		if not body.is_river():
			pond_levels[body.id] = body.level_m
			has_pond = true
			continue
		var width := doc.samples_x()
		var field := _sample_field(doc, body)
		var rect: Rect2i = field["rect"]
		for j in rect.size.y:
			for i in rect.size.x:
				var k := j * rect.size.x + i
				if in_reach(field, k, RIVER_BANK_M):
					var at := (rect.position.y + j) * width + rect.position.x + i
					out[at] = maxf(out[at], body.level_m)
	if has_pond and doc.pond_mask.size() == count:
		var mask := doc.pond_mask
		for i in count:
			var id := mask[i]
			if id != 0 and pond_levels[id] > out[i]:
				out[i] = pond_levels[id]
	return out


## The water level at map point `p` (the highest level among the bodies of `doc` whose area
## holds it, as levels() decides per sample but without the flush cut at shared reach ends:
## a river within its half-width plus RIVER_BANK_M of its course, a pond on the mask sample
## nearest `p`), or DRY. `exclude_id` skips one body.
## Cheap: no grid pass, so the Water tool can ask it per point of a stroke.
static func level_at(doc: MapDocument, p: Vector2, exclude_id: int = -1) -> float:
	var best := DRY
	var pond := 0
	if doc.pond_mask.size() == doc.sample_count() and doc.sample_count() > 0:
		var s := doc.world_to_sample(p).round()
		var x := clampi(int(s.x), 0, doc.samples_x() - 1)
		var z := clampi(int(s.y), 0, doc.samples_z() - 1)
		pond = doc.pond_mask[doc.sample_index(x, z)]
	for body in doc.water_bodies:
		if body.id == exclude_id or body.level_m <= best:
			continue
		if not body.is_river():
			if pond == body.id:
				best = body.level_m
			continue
		var course := river_course(body)
		var near := nearest_on_polyline(course[0], p)
		if near.y < 0:
			continue
		if near.x <= width_at(course[1], int(near.y), near.z) + RIVER_BANK_M:
			best = body.level_m
	return best


## True when map point `p` is under existing water of `doc` (its ground, ground_at(), below
## level_at()); `exclude_id` skips one body.
static func is_wet_at(doc: MapDocument, p: Vector2, exclude_id: int = -1) -> bool:
	if doc.heights.size() != doc.sample_count():
		return false
	var level := level_at(doc, p, exclude_id)
	return level != DRY and ground_at(doc, p) < level


## One byte per sample: 1 where the ground is below the water level (levels()), else 0.
## `water_levels` defaults to levels(doc).
static func wet_mask(
	doc: MapDocument, water_levels: PackedFloat32Array = PackedFloat32Array()
) -> PackedByteArray:
	var at_level := water_levels if not water_levels.is_empty() else levels(doc)
	var heights := doc.heights
	var out := PackedByteArray()
	out.resize(heights.size())
	for i in heights.size():
		if heights[i] < at_level[i]:
			out[i] = 1
	return out


## The sample indices in `body`'s area (see the header), ascending.
static func body_area(doc: MapDocument, body: WaterBody) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not body.is_river():
		if doc.pond_mask.size() == doc.sample_count():
			for i in doc.pond_mask.size():
				if doc.pond_mask[i] == body.id:
					out.append(i)
		return out
	var width := doc.samples_x()
	var field := _sample_field(doc, body)
	var rect: Rect2i = field["rect"]
	for j in rect.size.y:
		for i in rect.size.x:
			if in_reach(field, j * rect.size.x + i, RIVER_BANK_M):
				out.append((rect.position.y + j) * width + rect.position.x + i)
	return out


## The samples of `body`'s area whose ground is below its level, ascending.
static func wet_samples(doc: MapDocument, body: WaterBody) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in body_area(doc, body):
		if doc.heights[i] < body.level_m:
			out.append(i)
	return out


## Ground height at map XZ `xz`, bilinear between the four nearest samples; clamped to
## the map edge.
static func ground_at(doc: MapDocument, xz: Vector2) -> float:
	var sample := doc.world_to_sample(xz)
	var last := Vector2(doc.samples_x() - 1, doc.samples_z() - 1)
	sample = sample.clamp(Vector2.ZERO, last)
	var x0 := mini(int(sample.x), int(last.x) - 1)
	var z0 := mini(int(sample.y), int(last.y) - 1)
	var fx := sample.x - x0
	var fz := sample.y - z0
	var width := doc.samples_x()
	var h := doc.heights
	var top := lerpf(h[z0 * width + x0], h[z0 * width + x0 + 1], fx)
	var bottom := lerpf(h[(z0 + 1) * width + x0], h[(z0 + 1) * width + x0 + 1], fx)
	return lerpf(top, bottom, fz)


## ground_at() at every point of `points`.
static func ground_along(doc: MapDocument, points: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = ground_at(doc, points[i])
	return out


## Splits a centreline whose ground heights are `ground` into flat reaches: inclusive
## index ranges Vector2i(first, last), each of at least two points, consecutive ranges
## sharing their boundary point, none spanning more than `max_drop` of ground unless a
## single step does (a cliff between two points becomes its own two-point reach).
## Empty for fewer than two points.
static func reach_ranges(
	ground: PackedFloat32Array, max_drop: float = REACH_DROP_M
) -> Array[Vector2i]:
	var ranges: Array[Vector2i] = []
	var n := ground.size()
	if n < 2:
		return ranges
	var start := 0
	var low := ground[0]
	var high := ground[0]
	for i in range(1, n):
		var g := ground[i]
		if maxf(high, g) - minf(low, g) <= max_drop:
			low = minf(low, g)
			high = maxf(high, g)
			continue
		if i - 1 > start:
			ranges.append(Vector2i(start, i - 1))
			start = i - 1
			low = minf(ground[start], g)
			high = maxf(ground[start], g)
		else:
			ranges.append(Vector2i(start, i))
			start = i
			low = g
			high = g
	if n - 1 > start:
		ranges.append(Vector2i(start, n - 1))
	return ranges


## The level of a flat reach over `ground[range.x..range.y]`: its lowest ground minus
## FREEBOARD_M (see the header).
static func reach_level(ground: PackedFloat32Array, reach: Vector2i) -> float:
	var low := INF
	for i in range(reach.x, reach.y + 1):
		low = minf(low, ground[i])
	return low - FREEBOARD_M


## The level for the pond `body_id` of `doc`: the lowest ground on the rim of its area
## (area samples with a 4-neighbour outside it or on the map edge) minus FREEBOARD_M.
## NAN when the pond has no area.
static func pond_rim_level(doc: MapDocument, body_id: int) -> float:
	var mask := doc.pond_mask
	if mask.size() != doc.sample_count():
		return NAN
	var width := doc.samples_x()
	var depth := doc.samples_z()
	var low := INF
	for z in depth:
		for x in width:
			var i := z * width + x
			if mask[i] != body_id:
				continue
			var rim := (
				x == 0
				or z == 0
				or x == width - 1
				or z == depth - 1
				or mask[i - 1] != body_id
				or mask[i + 1] != body_id
				or mask[i - width] != body_id
				or mask[i + width] != body_id
			)
			if rim:
				low = minf(low, doc.heights[i])
	return NAN if is_inf(low) else low - FREEBOARD_M


## nearest_field() of a river body's course over `doc`'s sample grid, flush at an end
## another river continues from (flush_ends()).
static func _sample_field(doc: MapDocument, body: WaterBody) -> Dictionary:
	var course := river_course(body)
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	return nearest_field(
		course[0],
		course[1],
		-doc.extent_m() * 0.5,
		doc.sample_step(),
		grid,
		RIVER_BANK_M,
		flush_ends(doc.water_bodies, body)
	)


## Which ends of river `body` join another river of `bodies` (x: its first point is another
## river's last, the reach above; y: its last point is another's first, the reach below):
## the ends where its area stops flush at the shared point (see the header).
static func flush_ends(bodies: Array[WaterBody], body: WaterBody) -> Vector2i:
	var out := Vector2i.ZERO
	if body.points.size() < 2:
		return out
	for other in bodies:
		if other == body or not other.is_river() or other.points.size() < 2:
			continue
		if other.points[-1].distance_squared_to(body.points[0]) < JOIN_EPSILON_SQ:
			out.x = 1
		if other.points[0].distance_squared_to(body.points[-1]) < JOIN_EPSILON_SQ:
			out.y = 1
	return out


## The grid cells (see nearest_field()) whose positions fall inside `box`, clamped to the
## grid; an empty Rect2i when none do.
static func _cells_in(box: Rect2, origin: Vector2, step: Vector2, size: Vector2i) -> Rect2i:
	var low := ((box.position - origin) / step).ceil()
	var high := ((box.end - origin) / step).floor()
	var first := Vector2i(maxi(0, int(low.x)), maxi(0, int(low.y)))
	var last := Vector2i(mini(size.x - 1, int(high.x)), mini(size.y - 1, int(high.y)))
	if last.x < first.x or last.y < first.y:
		return Rect2i(first, Vector2i.ZERO)
	return Rect2i(first, last - first + Vector2i.ONE)
