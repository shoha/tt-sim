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
## same place drawn again. The recipe bodies are LandformRecipes; this class holds the
## kinds, the seeded frame and the shared steps every recipe composes: a height pass, a
## river carved through the water tools' pure path, a crossing placed and given an id, a
## surface painted along a line.
##
## Seeds. Every draw comes from a RandomNumberGenerator seeded from the map seed xor one
## constant per feature (stream()), as CrossingFord does for its stones, so the frame, the
## feature draws, the river's wobble, the tributary and the crossing each have their own
## stream and a change in one feature's draw does not shuffle the others.

const FLAT := "flat"
const VALLEY := "valley"
## Every kind, in tile order (more recipes come in P5-2).
const KINDS: Array[String] = [FLAT, VALLEY]
## Tile names and the captions under them. A caption describes the landform, not the draw,
## so an author is not promised a ford this seed did not draw.
const NAMES := {FLAT: "Flat", VALLEY: "Valley"}
const CAPTIONS := {
	FLAT: "Level ground, yours to shape",
	VALLEY: "A broad valley; often a river runs down it",
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
