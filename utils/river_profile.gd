class_name RiverProfile
extends RefCounted

## One river stroke's profile along its course (card painter-river-profile), pure: the one
## description of a carved river that WaterCarve reads, built from the stroke's reaches (one
## WaterBody each, as WaterEdit.plan_river and WaterFallPlan.shape_line made them). Summary:
## docs/systems/water.md ("The river profile").
##
## The course is the reaches' courses joined (WaterCarve.joined_course: the lines WaterGeometry
## derives their areas from), with a half-width per point and its arc length s. Along s the
## profile gives the water's level (the bank line), the bed under it, the side-wall share of a
## fall (gorge) and the sill share (at()), and every fall is an entry of its own (falls: the lip,
## the carved face's foot and the end of the plunge pool, as arcs), not a rule the carve
## re-derives at each sample. Each flat reach stands at its own level over a bed at level -
## depth; toward the next reach the bed rises over a pool tail to a crest (a riffle's below it,
## WaterCarve.step_shape); below a fall's lip the bed follows WaterCarve.fall_shape down the face
## into the plunge pool; a tapered end lifts the bed and narrows the channel to a rounded head.
##
## The sill. Where the water over the bed is a fall's crest (WaterCarve.fall_crest_depth() deep,
## up to twice that), from the top of the pool tail above a lip, over the lip and down the face
## until the bank meets the lower level, the cross-section is a flat sill to the profile's edge:
## the shore at WaterCarve.MAX_SHORE_SLOPE with the small toe rounding, and no top-of-bank easing
## (WaterCarve.section(), blend_with_ground()). So the channel keeps its full width through the
## lip, where before the sill stopped at the lip line, the first row past it took the lower
## reach's rounded section (the middle lifted to 4 cm under the level) and the easing left the
## waterline 4 cm proud on a tier standing 0.15 m over the level: 2 of 4 samples wet there on the
## short ankle fall, a neck at every brink (card painter-water-round3 (c)).
##
## Stations (stations()): the profile sampled along the course at a spacing over a document's
## ground, each with an undermined flag where the ground no longer holds the water (its banks or
## its bed dug away by a later edit), the per-station form of WaterMeshBuilder's perched rule.

## The stroke's joined course (see the header), the arc length of each shared point between its
## reaches and each reach's level.
var points := PackedVector2Array()
var widths := PackedFloat32Array()
var arc := PackedFloat32Array()
var bounds := PackedFloat32Array()
var levels := PackedFloat32Array()
## The stroke's depth class and its metres of water, and the course length.
var depth_class := 0
var depth := 0.0
var total := 0.0
## One byte per shared point: 1 where the step is a fall (WaterFalls.fall_flags).
var flags := PackedByteArray()
## One entry per fall: {"step" (shared point index), "lip", "foot", "plunge" (arc lengths: the
## lip, the carved face's foot, WaterCarve.fall_foot(), and the end of the plunge pool,
## WaterFalls.plunge_length() past it), "upper", "lower" (levels), "drop"}.
var falls: Array[Dictionary] = []
## Which ends taper (a free end inside the map) and which run off the map edge untapered:
## Vector2i(start, end), 1 or 0. Set by for_doc(); a bare build() tapers neither.
var taper := Vector2i.ZERO
var run_off := Vector2i.ZERO


## The profile of the stroke whose reaches are `bodies` (rivers in order, each starting where
## the previous ends, one depth class). `fall_flags` empty derives the steps' fall flags from the
## bodies (WaterFalls.fall_flags); explicit zeros carve every step as a riffle (the v0.1.29
## carve). No ends taper (for_doc() decides those from a document).
static func build(
	bodies: Array[WaterBody], fall_flags: PackedByteArray = PackedByteArray()
) -> RiverProfile:
	var profile := RiverProfile.new()
	if bodies.is_empty():
		return profile
	var joined := WaterCarve.joined_course(bodies)
	profile.points = joined.points
	profile.widths = joined.widths
	profile.arc = joined.arc
	profile.bounds = joined.bounds
	profile.levels = joined.levels
	profile.depth_class = int(bodies[0].depth)
	profile.depth = WaterBody.depth_for(profile.depth_class)
	profile.total = profile.arc[-1] if not profile.arc.is_empty() else 0.0
	profile.flags = WaterFalls.fall_flags(bodies) if fall_flags.is_empty() else fall_flags
	for k in profile.bounds.size():
		if k >= profile.flags.size() or profile.flags[k] == 0:
			continue
		var upper := profile.levels[k]
		var lower := profile.levels[k + 1]
		var drop := upper - lower
		var foot := profile.bounds[k] + WaterCarve.fall_foot(drop, profile.depth)
		profile.falls.append(
			{
				"step": k,
				"lip": profile.bounds[k],
				"foot": foot,
				"plunge": foot + WaterFalls.plunge_length(drop),
				"upper": upper,
				"lower": lower,
				"drop": drop,
			}
		)
	return profile


## build() with the ends decided on `doc`: an end inside the map (WaterCarve.EDGE_MARGIN_M from
## the edge) tapers, one at the edge runs off it, and an end that runs into existing water (a
## confluence, WaterEdit.join_line) does neither: full depth and width into that water. An end
## at the map edge (P6-3) carries the channel's own cross-section straight on past its end
## point out to the edge (field()): the round cap past the end left the bed on the edge up to
## 0.1 m shallower than the river's, and the exit past the edge carries the edge's
## (RiverExitMesh), so the stream read deeper past the edge than in the map.
static func for_doc(
	doc: MapDocument, bodies: Array[WaterBody], fall_flags: PackedByteArray = PackedByteArray()
) -> RiverProfile:
	var profile := build(bodies, fall_flags)
	if profile.points.is_empty():
		return profile
	var half := doc.extent_m() * 0.5 - Vector2.ONE * WaterCarve.EDGE_MARGIN_M
	var inside := func(p: Vector2) -> int: return 1 if absf(p.x) < half.x and absf(p.y) < half.y else 0
	# The stroke's own water (a profile of a river already in the document) is not other water.
	var first := profile.points[0]
	var last := profile.points[-1]
	var open_first := 0 if WaterGeometry.is_wet_at(doc, first, bodies[0].id) else 1
	var open_last := 0 if WaterGeometry.is_wet_at(doc, last, bodies[-1].id) else 1
	profile.taper = Vector2i(inside.call(first) * open_first, inside.call(last) * open_last)
	profile.run_off = Vector2i(
		(1 - inside.call(first)) * open_first, (1 - inside.call(last)) * open_last
	)
	return profile


## The strokes among `bodies`: each a list of river reaches in order (the first one no other
## reach runs into, then each reach whose first point is the previous one's last), as build()
## takes them. Ponds and degenerate rivers are left out.
static func strokes(bodies: Array[WaterBody]) -> Array:
	var rivers: Array[WaterBody] = []
	for body in bodies:
		if body.is_river() and body.points.size() >= 2:
			rivers.append(body)
	var next := {}
	var continued := {}
	for i in rivers.size():
		for j in rivers.size():
			var end := rivers[i].points[-1]
			if i != j and end.distance_squared_to(rivers[j].points[0]) < WaterGeometry.JOIN_EPSILON_SQ:
				next[i] = j
				continued[j] = true
				break
	var out := []
	for i in rivers.size():
		if continued.has(i):
			continue
		var chain: Array[WaterBody] = []
		var at := i
		while at >= 0 and chain.size() < rivers.size():
			chain.append(rivers[at])
			at = int(next.get(at, -1))
		out.append(chain)
	return out


## Vector4(bank level, bed height, gorge share, sill share) at arc length `s` (see the header).
## The bank level is the water's level over a flat reach and steps down a fall's face with it;
## the gorge share (WaterCarve.section() and blend_with_ground()) is WaterCarve.fall_gorge()
## below a fall's lip and rises with the pool tail above one, 0 elsewhere; the sill share is the
## pool tail's rise into a fall's lip and 1 from the lip down the face, both while the water over
## the bed is no deeper than twice the crest's, 0 elsewhere.
func at(s: float) -> Vector4:
	var n := levels.size()
	if n == 0:
		return Vector4.ZERO
	var k := 0
	while k < n - 1 and s > bounds[k]:
		k += 1
	var level := levels[k]
	var bed := level - depth
	var bank := level
	var gorge := 0.0
	var share := 0.0
	var tail := WaterCarve.pool_tail(depth)
	var fall_above := k > 0 and k - 1 < flags.size() and flags[k - 1] != 0
	if fall_above:
		# The fall's face and plunge pool shape the whole bed from the lip; the next pool tail
		# then rises from whatever they left.
		var x := s - bounds[k - 1]
		var shaped := WaterCarve.fall_shape(x, levels[k - 1], level, depth)
		bank = shaped.x
		bed = shaped.y
		gorge = WaterCarve.fall_gorge(x, levels[k - 1] - level, depth)
		share = 1.0
	if k < n - 1:
		var full := k < flags.size() and flags[k] != 0
		var next := WaterCarve.step_shape(level, levels[k + 1], depth, full)
		var rising := smoothstep(bounds[k] - next.y, bounds[k], s)
		bed = lerpf(bed, next.x, rising)
		if full:
			gorge = maxf(gorge, rising)
			share = maxf(share, rising)
	if k > 0 and not fall_above:
		var upper := levels[k - 1]
		var step := WaterCarve.step_shape(upper, level, depth)
		var t := smoothstep(bounds[k - 1], bounds[k - 1] + step.z, s)
		bed = maxf(bed, lerpf(step.x, level - depth, t))
		bank = lerpf(upper, level, t)
	# A tapered end lifts the bed toward the level over its pool tail. A plunge pool (the only
	# bed under the flat bed) is carried past that lift and fades with the depth it leaves, so
	# the taper's max never fills it in.
	var flat := level - depth
	var plunge := maxf(flat - bed, 0.0)
	bed = maxf(bed, flat)
	if taper.x != 0:
		var left := _end_depth(tail, s)
		bed = maxf(bed, level - left)
		plunge *= left / depth
	if taper.y != 0:
		var left := _end_depth(tail, total - s)
		bed = maxf(bed, level - left)
		plunge *= left / depth
	bed -= plunge
	var sill := 0.0
	if share > 0.0 and bank > bed:
		var sill_depth := WaterCarve.fall_crest_depth(depth)
		sill = share * (1.0 - smoothstep(sill_depth, 2.0 * sill_depth, bank - bed))
	return Vector4(bank, bed, gorge, sill)


## at(s).x without the rest of the section (the bed, the gorge and sill shares, the tapered end):
## the bank level at arc length `s`, rounded to float as the Vector4 holds it.
## WaterFieldStroke.table reads the level every few centimetres, and at() is five times the work.
func level_at(s: float) -> float:
	var n := levels.size()
	if n == 0:
		return 0.0
	var k := 0
	while k < n - 1 and s > bounds[k]:
		k += 1
	var bank := levels[k]
	var fall_above := k > 0 and k - 1 < flags.size() and flags[k - 1] != 0
	if fall_above:
		bank = WaterCarve.fall_shape(s - bounds[k - 1], levels[k - 1], levels[k], depth).x
	elif k > 0:
		var upper := levels[k - 1]
		var step := WaterCarve.step_shape(upper, levels[k], depth)
		bank = lerpf(upper, levels[k], smoothstep(bounds[k - 1], bounds[k - 1] + step.z, s))
	return Vector4(bank, 0.0, 0.0, 0.0).x


## The half-width `half_width` (the course's at `s`) narrowed toward a tapered end to a rounded
## head (WaterCarve.head_width()).
func head(s: float, half_width: float) -> float:
	var hw := half_width
	if taper.x != 0:
		hw *= WaterCarve.head_width(s, hw, depth)
	if taper.y != 0:
		hw *= WaterCarve.head_width(total - s, hw, depth)
	return hw


## The fall entry whose face holds arc `s` (from its lip to its foot), or {}.
func fall_at(s: float) -> Dictionary:
	for fall in falls:
		if s > float(fall.lip) and s < float(fall.foot):
			return fall
	return {}


## The course rasterised on `doc`'s sample grid within `reach` of its edge: {"rect" (Rect2i of
## the samples reached), "distance" (to the nearest point of the course), "along" (its arc
## length), "half_width" (the course's there, before head()), row-major over the rect; distance
## INF where no segment is near}. An end that runs off the map carries the end segment on past
## its point. A `clip` with an area limits the rect to it (WaterField's dirty-rect rebuild): each
## sample's values are the same with or without it, only the samples outside are not made.
func field(doc: MapDocument, reach_m: float, clip: Rect2i = Rect2i()) -> Dictionary:
	var widest := 0.0
	for w in widths:
		widest = maxf(widest, w)
	var reach := widest + reach_m
	var origin := -doc.extent_m() * 0.5
	var step := doc.sample_step()
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	var rect := _cells_in(WaterGeometry.bounds(points, reach), origin, step, grid)
	if clip.has_area():
		rect = rect.intersection(clip)
	# The segment raster in the scatter library (native/src/water_field.cpp), bit for bit the loop
	# below.
	var native := ScatterNative.wfield_instance() if rect.has_area() else null
	if native != null:
		var raster: Dictionary = native.call(
			"water_raster",
			{
				"points": points,
				"widths": widths,
				"arc": arc,
				"rect": rect,
				"origin": origin,
				"step": step,
				"grid": grid,
				"reach": reach,
				"total": total,
				"run_off": run_off,
			}
		)
		return {
			"rect": rect,
			"distance": raster.distance,
			"along": raster.along,
			"half_width": raster.half_width,
		}
	var count := rect.size.x * rect.size.y
	var distance := PackedFloat32Array()
	var along := PackedFloat32Array()
	var half_width := PackedFloat32Array()
	distance.resize(count)
	distance.fill(INF)
	along.resize(count)
	half_width.resize(count)
	for s in points.size() - 1:
		var a := points[s]
		var segment := points[s + 1] - a
		var length_sq := segment.length_squared()
		if length_sq <= 1e-12:
			continue
		var length := sqrt(length_sq)
		var box := Rect2(a, Vector2.ZERO).expand(points[s + 1]).grow(reach)
		var cells := _cells_in(box, origin, step, grid).intersection(rect)
		var lo := -INF if s == 0 and run_off.x != 0 else 0.0
		var hi := INF if s == points.size() - 2 and run_off.y != 0 else 1.0
		for j in range(cells.position.y, cells.end.y):
			var z := origin.y + j * step.y
			var row := (j - rect.position.y) * rect.size.x - rect.position.x
			for i in range(cells.position.x, cells.end.x):
				var p := Vector2(origin.x + i * step.x, z)
				var t := clampf((p - a).dot(segment) / length_sq, lo, hi)
				var d := p.distance_to(a + segment * t)
				var k := row + i
				if d < distance[k]:
					distance[k] = d
					along[k] = clampf(arc[s] + t * length, 0.0, total)
					half_width[k] = lerpf(widths[s], widths[s + 1], clampf(t, 0.0, 1.0))
	return {"rect": rect, "distance": distance, "along": along, "half_width": half_width}


## The profile sampled every `spacing` metres along the course (and at its end) over `doc`'s
## ground: {"arc", "level" (the bank level), "bed", "half_width" (head() applied), "sill"
## (PackedFloat32Array each), "centre" (PackedVector2Array), "undermined" (PackedByteArray)}. A
## station is undermined where the ground no longer holds its water: a bank point (the
## half-width plus WaterMeshBuilder.BANK_MARGIN_M either side) lies more than
## WaterMeshBuilder.BANK_HOLD_M under the level, or the centre's ground lies more than
## WaterMeshBuilder.HOLD_SLACK_M under the bed. Never on a fall's face (lip to foot), where the
## water is the curtain, nor within a pool tail of an end in other water (that water's basin
## may have deepened it).
func stations(doc: MapDocument, spacing: float = 0.25) -> Dictionary:
	var out := {
		"arc": PackedFloat32Array(),
		"level": PackedFloat32Array(),
		"bed": PackedFloat32Array(),
		"half_width": PackedFloat32Array(),
		"sill": PackedFloat32Array(),
		"centre": PackedVector2Array(),
		"undermined": PackedByteArray(),
	}
	if points.size() < 2 or spacing <= 0.0:
		return out
	var tail := WaterCarve.pool_tail(depth)
	var open_start := taper.x == 0 and run_off.x == 0
	var open_end := taper.y == 0 and run_off.y == 0
	var arcs := PackedFloat32Array()
	var walked := 0.0
	while walked < total - 1e-4:
		arcs.append(walked)
		walked += spacing
	arcs.append(total)
	for s in arcs:
		var where := _locate(s)
		var segment := int(where.x)
		var tangent := (points[segment + 1] - points[segment]).normalized()
		var side := Vector2(-tangent.y, tangent.x)
		var centre := points[segment].lerp(points[segment + 1], where.y)
		var hw := head(s, lerpf(widths[segment], widths[segment + 1], where.y))
		var line := at(s)
		var lost := false
		var near_open := (open_start and s < tail) or (open_end and total - s < tail)
		if fall_at(s).is_empty() and not near_open:
			var hold := line.x - WaterMeshBuilder.BANK_HOLD_M
			var reach := hw + WaterMeshBuilder.BANK_MARGIN_M
			lost = (
				WaterGeometry.ground_at(doc, centre + side * reach) < hold
				or WaterGeometry.ground_at(doc, centre - side * reach) < hold
				or WaterGeometry.ground_at(doc, centre) < line.y - WaterMeshBuilder.HOLD_SLACK_M
			)
		out.arc.append(s)
		out.level.append(line.x)
		out.bed.append(line.y)
		out.half_width.append(hw)
		out.sill.append(line.w)
		out.centre.append(centre)
		out.undermined.append(1 if lost else 0)
	return out


## The depth left `s` metres from a tapered end over a pool tail `tail`: the depth tapered from
## zero, but never shallower than a WaterCarve.HEAD_DEPTH_M film shaped like the rounded head
## (WaterCarve.head_shape()), so the water reaches round the head instead of stopping where the
## taper runs out.
func _end_depth(tail: float, s: float) -> float:
	var film := minf(WaterCarve.HEAD_DEPTH_M, depth) * WaterCarve.head_shape(s, tail)
	return maxf(depth * smoothstep(0.0, tail, s), film)


## Where arc `s` falls on the course: Vector2(segment, t along it 0..1).
func _locate(s: float) -> Vector2:
	var k := 0
	while k < arc.size() - 2 and arc[k + 1] < s:
		k += 1
	var span := arc[k + 1] - arc[k]
	var t := clampf((s - arc[k]) / span, 0.0, 1.0) if span > 1e-9 else 0.0
	return Vector2(k, t)


## The grid cells whose positions fall inside `box` (WaterGeometry's rule).
static func _cells_in(box: Rect2, origin: Vector2, step: Vector2, size: Vector2i) -> Rect2i:
	var low := ((box.position - origin) / step).ceil()
	var high := ((box.end - origin) / step).floor()
	var first := Vector2i(maxi(0, int(low.x)), maxi(0, int(low.y)))
	var last := Vector2i(mini(size.x - 1, int(high.x)), mini(size.y - 1, int(high.y)))
	if last.x < first.x or last.y < first.y:
		return Rect2i(first, Vector2i.ZERO)
	return Rect2i(first, last - first + Vector2i.ONE)
