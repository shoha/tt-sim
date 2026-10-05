class_name StartingLandform
extends RefCounted

## The landform a new map opens with (phase 5). A recipe is a pure function run on the
## document right after NewMap makes it flat and before the map is shown: it writes heights,
## carved water, a crossing and the stage (where the glade goes) as the ordinary data the
## tools edit, through the same pure functions the tools use (WaterEdit, WaterCarve,
## CrossingPlacement). No history entry: a new map starts clean.
##
## No sameness (decided 2026-10-04). A landform is a shape plus a small palette of features,
## and the seed draws from the palette: not every valley has a river, not every river a
## crossing, and a dry draw is a complete map on its own. The shape varies too (heading,
## offset, bend) within bounds that keep the recipe recognisable, so siblings read as the
## same place drawn again. The recipe bodies are LandformRecipes (the Valley), LandformHilltop,
## LandformTerraces, LandformLakeshore and LandformGorge; this class holds the kinds, the
## seeded frame and the shared steps every recipe composes: a height pass, outline distance
## fields (a warped disc, a rounded box) and the tier inset HeightBrush.tier_goal wants, so a
## recipe's plateau is the Sculpt tool's own terrace, a river or a pond carved through the
## water tools' pure path, the walls put back where a river's bank reach slumped them, a
## crossing placed (or spanned between chosen anchors) and given an id, a surface painted
## along a line.
##
## Seeds. Every draw comes from a RandomNumberGenerator seeded from the map seed xor one
## constant per feature (stream()), as CrossingFord does for its stones, so the frame, the
## feature draws, the river's wobble, the tributary and the crossing each have their own
## stream and a change in one feature's draw does not shuffle the others.

const FLAT := "flat"
const VALLEY := "valley"
const HILLTOP := "hilltop"
const TERRACES := "terraces"
const LAKESHORE := "lakeshore"
const GORGE := "gorge"
## Every kind, in tile order.
const KINDS: Array[String] = [FLAT, VALLEY, HILLTOP, TERRACES, LAKESHORE, GORGE]
## Tile names and the captions under them. A caption describes the landform, not the draw,
## so an author is not promised a ford this seed did not draw.
const NAMES := {
	FLAT: "Flat",
	VALLEY: "Valley",
	HILLTOP: "Hilltop",
	TERRACES: "Terraces",
	LAKESHORE: "Lakeshore",
	GORGE: "Gorge",
}
const CAPTIONS := {
	FLAT: "Level ground, yours to shape",
	VALLEY: "A broad valley; often a river runs down it",
	HILLTOP: "A rounded hill, often with a rock-lipped crown",
	TERRACES: "Tiers stepping down across the map",
	LAKESHORE: "A deep lake over one corner, its shore the stage",
	GORGE: "A ravine with rock walls winding across the map",
}
const DEFAULT := VALLEY

## Feature streams (stream()): one constant per feature.
const STREAM_FRAME := 0x1F3A5
const STREAM_FEATURES := 0x2B7E1
const STREAM_RIVER := 0x3C9D7
const STREAM_TRIBUTARY := 0x4D1E3
const STREAM_CROSSING := 0x5E2F9

## The extent the recipes' metres are written for (150 ft); size_scale() is 0.8 / 1.0 / 1.2
## at 100 / 150 / 200 ft.
const REFERENCE_EXTENT_M := 45.72
## A clipped line is walked this finely to find where it meets the map edge.
const CLIP_STEP_M := 0.25
## The wavelength of a river's wobble along its course.
const WOBBLE_WAVE_M := 14.0
## A crossing is drawn this far either side of the water's centreline (CrossingPlacement
## searches SEARCH_M further for the banks).
const CROSSING_DRAW_M := 3.5


## Runs the recipe for `kind` on `doc` (a flat document of the map's size) with `seed_value`.
## Returns {"stage": Vector2 (map XZ metres, where the glade goes), "report": String (what
## was drawn, with any refusal in plain words)}. FLAT and an unknown kind change nothing.
## `biome_id` is the starting biome (the crossing's style and the dry wash's surface).
static func apply(
	doc: MapDocument,
	kind: String,
	seed_value: int,
	biome_id: String = "",
	root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	match kind:
		VALLEY:
			return LandformRecipes.valley(doc, seed_value, biome_id, root)
		HILLTOP:
			return LandformHilltop.hilltop(doc, seed_value, biome_id)
		TERRACES:
			return LandformTerraces.terraces(doc, seed_value, biome_id)
		LAKESHORE:
			return LandformLakeshore.lakeshore(doc, seed_value, biome_id)
		GORGE:
			return LandformGorge.gorge(doc, seed_value, biome_id, root)
	return {"stage": Vector2.ZERO, "report": "flat"}


## The generator of one feature's draws: seeded from `seed_value` xor the feature's stream
## constant.
static func stream(seed_value: int, feature: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = (seed_value ^ feature) & 0x7fffffffffffffff
	return rng


## The map's half extent (metres; maps are square, the smaller axis otherwise).
static func half_extent(doc: MapDocument) -> float:
	return minf(doc.extent_m().x, doc.extent_m().y) * 0.5


## How the recipes' depths and falls scale with the map: 0.8 at 100 ft, 1.0 at 150, 1.2 at
## 200, so a landform keeps its proportions without a small map becoming a pit.
static func size_scale(doc: MapDocument) -> float:
	return clampf(0.4 + 0.6 * doc.extent_m().x / REFERENCE_EXTENT_M, 0.5, 1.5)


## One of eight headings (45 degree steps) as a unit direction.
static func heading(rng: RandomNumberGenerator) -> Vector2:
	var angle := rng.randi_range(0, 7) * PI / 4.0
	return Vector2(cos(angle), sin(angle))


## The nearest point of polyline `points` to `p`: Vector3(distance, arc length at it, the
## segment index). A single point is its own polyline.
static func nearest_on(points: PackedVector2Array, p: Vector2) -> Vector3:
	if points.size() < 2:
		return Vector3(p.distance_to(points[0]) if not points.is_empty() else INF, 0.0, 0.0)
	var best := Vector3(INF, 0.0, 0.0)
	var walked := 0.0
	for k in points.size() - 1:
		var a := points[k]
		var b := points[k + 1]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := p.distance_to(q)
		if d < best.x:
			best = Vector3(d, walked + a.distance_to(q), float(k))
		walked += a.distance_to(b)
	return best


## The point `s` metres of arc along polyline `points` (clamped to its ends) and the unit
## direction of the segment there: {"point": Vector2, "dir": Vector2}.
static func along(points: PackedVector2Array, s: float) -> Dictionary:
	var walked := 0.0
	for k in points.size() - 1:
		var length := points[k].distance_to(points[k + 1])
		var dir := (points[k + 1] - points[k]).normalized()
		if s <= walked + length or k == points.size() - 2:
			var t := clampf((s - walked) / maxf(length, 1e-6), 0.0, 1.0)
			return {"point": points[k].lerp(points[k + 1], t), "dir": dir}
		walked += length
	return {"point": points[0] if not points.is_empty() else Vector2.ZERO, "dir": Vector2.RIGHT}


## The trough profile across a valley: 1 on the floor (within `floor_half` of the axis), a
## cosine fall to 0 at `rim` and beyond, so the rim stays at the base height.
static func trough_shape(distance: float, floor_half: float, rim: float) -> float:
	if distance <= floor_half:
		return 1.0
	if distance >= rim:
		return 0.0
	return 0.5 * (1.0 + cos(PI * (distance - floor_half) / maxf(rim - floor_half, 1e-6)))


## A rounded hill's profile: 1 at the centre, a cosine fall to 0 at t = 1 (distance over
## radius) and beyond, with no crease at the foot.
static func bump(t: float) -> float:
	if t >= 1.0:
		return 0.0
	return 0.5 * (1.0 + cos(PI * maxf(t, 0.0)))


## A low-frequency smooth noise seeded from `rng` (one wave per `wave` metres) for warping
## an outline: a shore, a crown, a terrace edge.
static func warp_noise(rng: RandomNumberGenerator, wave: float) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = rng.randi() & 0x7fffffff
	noise.frequency = 1.0 / wave
	return noise


## The signed distance of `p` inside a disc of `radius` about `centre` (positive inside)
## whose outline is pushed in and out by up to `warp` of the radius by `noise` read around
## the circle (periodic, so the shore has no seam). Null noise: a plain disc.
static func disc_distance(
	p: Vector2, centre: Vector2, radius: float, noise: FastNoiseLite, warp: float
) -> float:
	var offset := p - centre
	var r := radius
	if noise != null and warp > 0.0:
		var angle := offset.angle()
		# The noise read on a circle of the disc's size, so the warp has about two waves of
		# detail per quarter turn whatever the radius.
		var ring := radius * 0.5
		r *= 1.0 + warp * noise.get_noise_2d(ring * cos(angle), ring * sin(angle))
	return r - offset.length()


## The signed distance of `p` inside a rounded rectangle (positive inside) whose centre is
## `centre`, half size `half_size` (along `axis` and its normal) and corner radius `corner`.
static func box_distance(
	p: Vector2, centre: Vector2, half_size: Vector2, corner: float, axis: Vector2
) -> float:
	var offset := p - centre
	var local := Vector2(offset.dot(axis), offset.dot(Vector2(-axis.y, axis.x))).abs()
	var q := local - (half_size - Vector2(corner, corner))
	var outside := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length()
	var inner := minf(maxf(q.x, q.y), 0.0)
	return -(outside + inner - corner)


## The `inset` HeightBrush.tier_goal wants for a sample `distance` metres inside a
## plateau's outline (negative outside): the Sculpt tool measures it from TIER_SOFTEN_M
## outside its ring, so the face stands on the outline and its toe eases out past it.
static func tier_inset(distance: float) -> float:
	return distance + HeightBrush.TIER_SOFTEN_M


## Writes `height_of(p: Vector2, h: float) -> float` over every sample of `doc` (p the
## sample's map XZ, h its height now), clamped to MAX_ABS_HEIGHT_M.
static func write_heights(doc: MapDocument, height_of: Callable) -> void:
	var limit := MapDocument.MAX_ABS_HEIGHT_M
	var heights := doc.heights
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			var h: float = height_of.call(doc.sample_to_world(Vector2(x, z)), heights[i])
			heights[i] = clampf(h, -limit, limit)
	doc.heights = heights


## Puts back the ground of `shape` (heights per sample, the landform before its water was
## carved) wherever the carve lowered it more than `keep` metres from polyline `line` (the
## water's course): a river's bank reach (WaterCarve.BANK_REACH_M) cuts a slope through any
## high ground beside it, which is right for a stroke across a hillside and wrong for a
## stream along the foot of a ravine's wall. Only ever raises, never above `shape`, and
## never within the channel and its bank, so the water model stands as planned.
static func restore_outside(
	doc: MapDocument, shape: PackedFloat32Array, line: PackedVector2Array, keep: float
) -> void:
	if shape.size() != doc.sample_count() or line.size() < 2:
		return
	var heights := doc.heights
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			if heights[i] >= shape[i]:
				continue
			if nearest_on(line, doc.sample_to_world(Vector2(x, z))).x > keep:
				heights[i] = shape[i]
	doc.heights = heights


## True when `p` lies on the map at least `margin` metres inside its edge.
static func inside(doc: MapDocument, p: Vector2, margin: float) -> bool:
	var half := doc.extent_m() * 0.5 - Vector2(margin, margin)
	return absf(p.x) <= half.x and absf(p.y) <= half.y


## `p` moved onto the map at least `margin` inside its edge.
static func clamped(doc: MapDocument, p: Vector2, margin: float) -> Vector2:
	var half := doc.extent_m() * 0.5 - Vector2(margin, margin)
	return p.clamp(-half, half)


## The run of polyline `points` that lies on the map at least `margin` inside its edge,
## resampled every `spacing` metres with both ends kept (the first and last points sit
## within CLIP_STEP_M of the margin line). Empty when the line misses the map.
static func map_line(
	doc: MapDocument, points: PackedVector2Array, margin: float, spacing: float
) -> PackedVector2Array:
	var total := 0.0
	for k in points.size() - 1:
		total += points[k].distance_to(points[k + 1])
	var fine := PackedVector2Array()
	var steps := maxi(1, ceili(total / CLIP_STEP_M))
	for n in steps + 1:
		var p: Vector2 = along(points, total * n / steps).point
		if inside(doc, p, margin):
			fine.append(p)
		elif not fine.is_empty():
			break
	if fine.size() < 2:
		return PackedVector2Array()
	var widths := PackedFloat32Array()
	widths.resize(fine.size())
	widths.fill(1.0)
	return WaterEdit.resample(fine, widths, spacing)[0]


## `points` pushed across their course by a smooth seeded wobble of up to `amplitude`
## metres (one noise wave per WOBBLE_WAVE_M of arc), kept `margin` inside the map.
static func wobbled(
	doc: MapDocument, points: PackedVector2Array, amplitude: float, rng: RandomNumberGenerator
) -> PackedVector2Array:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = rng.randi() & 0x7fffffff
	noise.frequency = 1.0 / WOBBLE_WAVE_M
	var phase := rng.randf_range(0.0, 1000.0)
	var out := PackedVector2Array()
	var arc := 0.0
	for i in points.size():
		if i > 0:
			arc += points[i - 1].distance_to(points[i])
		var prev := points[maxi(i - 1, 0)]
		var next := points[mini(i + 1, points.size() - 1)]
		var dir := (next - prev).normalized()
		var normal := Vector2(-dir.y, dir.x)
		var push := amplitude * noise.get_noise_1d(arc + phase)
		out.append(clamped(doc, points[i] + normal * push, 0.3))
	return out


## A river of depth class `depth` along `line` (map XZ, upstream first) with one half-width,
## planned, carved into the heights and added to the document's bodies as the Water tool
## does (WaterEdit.plan_river, WaterCarve.river_goals, WaterEditor.lower, with_bodies). The
## dressing is not refreshed here (once per recipe, at the end). Returns the reaches made,
## empty when nothing could be planned.
static func carve_river(
	doc: MapDocument,
	line: PackedVector2Array,
	half_width: float,
	depth: WaterBody.Depth,
	speed: float = WaterBody.DEFAULT_SPEED
) -> Array[WaterBody]:
	var widths := PackedFloat32Array()
	widths.resize(line.size())
	widths.fill(half_width)
	var bodies := WaterEdit.plan_river(doc, line, widths, depth, speed)
	if bodies.is_empty():
		return bodies
	var before := doc.heights.duplicate()
	WaterEditor.lower(doc, WaterCarve.river_goals(doc, bodies, before))
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	return bodies


## A crossing of `kind` drawn across the water at `at` (a point on the water's centreline
## running along `direction`), placed by CrossingPlacement and appended to `doc.crossings`
## with the id CrossingEditor.add would give it. {"crossing": Crossing or null, "refusal":
## StringName} as place() returns it; a refused line leaves the document as it was.
static func place_crossing(
	doc: MapDocument, at: Vector2, direction: Vector2, kind: Crossing.Kind, style: String
) -> Dictionary:
	var normal := Vector2(-direction.y, direction.x) * CROSSING_DRAW_M
	var placed := CrossingPlacement.place(doc, at - normal, at + normal, kind, -1.0, style)
	var crossing: Crossing = placed.crossing
	if crossing == null:
		return placed
	var crossing_id := doc.next_crossing_id()
	if crossing_id < 0:
		return {"crossing": null, "refusal": &"full"}
	crossing.id = crossing_id
	var problem := MapCrossingIO.crossing_problem(crossing, doc.extent_m())
	if problem != "":
		return {"crossing": null, "refusal": StringName(problem)}
	doc.crossings.append(crossing)
	return placed


## A pond of depth class `depth` over every sample where `inside.call(p: Vector2) -> bool`
## (map XZ), carved into the heights and added to the document's bodies as the Water tool's
## pond stroke does (the mask, WaterGeometry.pond_rim_level: the lowest rim ground less the
## freeboard, WaterCarve.pond_goals, WaterEditor.lower). The heights must be final around the
## pond first: the level is read from the rim as it is. Returns the body, or null when no
## sample is inside or the document has no room for it.
static func carve_pond(doc: MapDocument, inside: Callable, depth: WaterBody.Depth) -> WaterBody:
	var id := doc.next_water_id()
	if id < 1 or id > WaterBody.MAX_ID:
		return null
	var count := doc.sample_count()
	var mask := doc.pond_mask
	if mask.size() != count:
		mask = PackedByteArray()
		mask.resize(count)
	var marked := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			if mask[i] == 0 and inside.call(doc.sample_to_world(Vector2(x, z))):
				mask[i] = id
				marked += 1
	if marked == 0:
		return null
	doc.pond_mask = mask
	var level := WaterGeometry.pond_rim_level(doc, id)
	if is_nan(level):
		return null
	var body := WaterBody.pond(id, depth, level)
	var bodies: Array[WaterBody] = []
	bodies.assign(doc.water_bodies)
	bodies.append(body)
	doc.water_bodies = bodies
	WaterEditor.lower(doc, WaterCarve.pond_goals(doc, body, doc.heights))
	return body


## A crossing of `kind` standing on two chosen anchors `a` and `b` (map XZ, dry ground)
## over the water between them, for a span CrossingPlacement.place cannot find by itself: an
## arch from rim to rim of a ravine, whose waterline anchors would stand on the floor beside
## the stream. The levels are CrossingPlacement.levels_for's over the highest water level
## along the span; refused as place() refuses (&"no_bank" when an anchor is wet or off the
## map, &"no_water" without water between them, &"fall" near a fall, &"long" over
## Crossing.MAX_SPAN_M) and appended to `doc.crossings` with the id CrossingEditor.add would
## give it. {"crossing": Crossing or null, "refusal": StringName}.
static func span_crossing(
	doc: MapDocument, a: Vector2, b: Vector2, kind: Crossing.Kind, style: String
) -> Dictionary:
	if not inside(doc, a, 0.0) or not inside(doc, b, 0.0):
		return {"crossing": null, "refusal": &"no_bank"}
	if WaterGeometry.is_wet_at(doc, a) or WaterGeometry.is_wet_at(doc, b):
		return {"crossing": null, "refusal": &"no_bank"}
	var span := a.distance_to(b)
	if span > Crossing.MAX_SPAN_M:
		return {"crossing": null, "refusal": CrossingPlacement.REFUSED_LONG}
	var water := -INF
	var steps := maxi(2, ceili(span / 0.25))
	for n in steps + 1:
		var p := a.lerp(b, float(n) / steps)
		if WaterGeometry.is_wet_at(doc, p):
			water = maxf(water, WaterGeometry.level_at(doc, p))
	if water == -INF:
		return {"crossing": null, "refusal": CrossingPlacement.REFUSED_NO_WATER}
	var width: float = Crossing.DEFAULT_WIDTH_M[kind]
	if CrossingPlacement.fall_near(doc, a, b, width):
		return {"crossing": null, "refusal": &"fall"}
	var crossing := Crossing.new()
	crossing.kind = kind
	crossing.start = a
	crossing.end = b
	crossing.style = style
	crossing.width_m = width
	crossing.levels = CrossingPlacement.levels_for(
		kind, WaterGeometry.ground_at(doc, a), WaterGeometry.ground_at(doc, b), water, span
	)
	var crossing_id := doc.next_crossing_id()
	if crossing_id < 0:
		return {"crossing": null, "refusal": &"full"}
	crossing.id = crossing_id
	var problem := MapCrossingIO.crossing_problem(crossing, doc.extent_m())
	if problem != "":
		return {"crossing": null, "refusal": StringName(problem)}
	doc.crossings.append(crossing)
	return {"crossing": crossing, "refusal": &""}


## The index of the point of `course` where it runs straightest among `candidates` (the
## turning angle over the two points either side), or -1 with no candidates.
static func straightest(course: PackedVector2Array, candidates: PackedInt32Array) -> int:
	var best := -1
	var least := INF
	for i in candidates:
		if i < 2 or i > course.size() - 3:
			continue
		var before := (course[i] - course[i - 2]).normalized()
		var after := (course[i + 2] - course[i]).normalized()
		var turn := absf(before.angle_to(after))
		if turn < least:
			least = turn
			best = i
	return best


## Paints `surface` into `doc`'s surface weights along polyline `points`: full weight within
## `width` / 2 of the line, falling to nothing over `soft` metres (the probe's path paint).
## Returns the samples painted; 0 when the document has no slot for the surface.
static func paint_line(
	doc: MapDocument, surface: String, points: PackedVector2Array, width: float, soft: float
) -> int:
	var slot := doc.ensure_surface(surface)
	if slot < 0 or points.size() < 2:
		return 0
	var half_width := width * 0.5
	var count := doc.sample_count()
	var painted := 0
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	box = box.grow(half_width + soft)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if not box.has_point(p):
				continue
			var d := nearest_on(points, p).x - half_width
			if d >= soft:
				continue
			var t := clampf(1.0 - d / maxf(soft, 1e-3), 0.0, 1.0) if d > 0.0 else 1.0
			var value := roundi(255.0 * t * t * (3.0 - 2.0 * t))
			var i := doc.sample_index(x, z)
			if value > doc.surface_weights[MapDocument.surface_offset(i, slot, count)]:
				doc.set_surface_weight(i, slot, value)
				painted += 1
	return painted
