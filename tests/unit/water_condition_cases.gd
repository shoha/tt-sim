extends RefCounted

## The synthetic cases and the metrics of the water-conditioning spike (test_water_conditioner.gd;
## not a test file itself: GUT only collects test_*.gd). Preload it as a const.
##
## make(name, conditioned) builds one 30 m map for an edge case of the research's list (jittery
## stroke, non-monotone profile, stream over a hill, a stream end and a stream head 1.5 m from a
## pond 3.9 m below, a river into a square pond corner, a confluence, a tiny-kink profile, a very
## tall fall, a short ankle fall), the way the editor builds it: ponds first, then each stroke
## planned by WaterEdit.plan_river and carved. `conditioned` turns on the plan-time probe
## (course and levels) and snaps stroke ends by WaterPorts.end_decision(). metrics(doc) is what
## the field and the audit say about a document.

const Fixtures := preload("res://tests/unit/water_fixtures.gd")
const NAMES: Array[String] = [
	"jitter",
	"nonmonotone",
	"over_hill",
	"head_near_pond",
	"end_near_pond",
	"shore_corner",
	"confluence",
	"tiny_kink",
	"tall_fall",
	"ankle_fall",
]
const WAIST := WaterBody.Depth.WAIST
const ANKLE := WaterBody.Depth.ANKLE

## The deepest cut into the drawn ground (off a fall's face) any conditioned stroke planned since
## make() began asks of the carve (the plan's report); 0 for an unconditioned plan.
static var worst_cut := 0.0
## True when a stroke planned since make() began was kept as drawn because conditioning it would
## have cut a gorge (WaterConditioner.CUT_LIMIT_M).
static var blocked := false
## The hints (WaterHints records) of the strokes planned since make() began.
static var hints: Array = []


## A 30 m map with its ground set by `ground` (Callable(Vector2) -> float).
static func world(ground: Callable) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	Fixtures.shape(doc, ground)
	return doc


## A disc pond at `centre` of `radius`, or the rectangle `box` when it is not empty, level at its
## lowest rim, carved in as the editor does. Returns the pond's body.
static func add_pond(
	doc: MapDocument,
	centre: Vector2,
	radius: float,
	depth: WaterBody.Depth = WaterBody.Depth.DEEP,
	box: Rect2 = Rect2()
) -> WaterBody:
	var mask := doc.pond_mask.duplicate()
	if mask.size() != doc.sample_count():
		mask.resize(doc.sample_count())
	var id := doc.next_water_id()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			var inside := box.has_point(p) if box.has_area() else p.distance_to(centre) < radius
			if inside:
				mask[doc.sample_index(x, z)] = id
	doc.pond_mask = mask
	var pond := WaterBody.pond(id, depth, WaterGeometry.pond_rim_level(doc, id))
	doc.water_bodies = WaterEdit.with_bodies(doc, [pond] as Array[WaterBody])
	Fixtures.carve(doc, WaterCarve.pond_goals(doc, pond, doc.heights.duplicate()))
	return pond


## Plans, carves and adds the stroke along `pts` (half-width `hw`); `condition` conditions it
## (course, levels, the ends joined: WaterEdit.plan_river). Returns {"bodies", "report" (the
## plan's report, with its "hints")}.
static func add_stroke(
	doc: MapDocument,
	pts: PackedVector2Array,
	hw: float,
	depth: WaterBody.Depth,
	condition: bool
) -> Dictionary:
	var widths := PackedFloat32Array()
	widths.resize(pts.size())
	widths.fill(hw)
	var start := doc.heights.duplicate()
	var report := {}
	var bodies := WaterEdit.plan_river(doc, pts, widths, depth, 1.0, condition, report)
	blocked = blocked or bool(report.get("blocked", false))
	worst_cut = maxf(worst_cut, float(report.get("max_cut", 0.0)))
	hints.append_array(report.get("hints", []))
	Fixtures.carve(doc, WaterCarve.river_goals(doc, bodies, start))
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	return {"bodies": bodies, "report": report}


## A straight line from `a` to `b` with a point every `gap` metres and gaussian position jitter
## `sigma` (seeded; the ends stay).
static func jittered(
	a: Vector2, b: Vector2, gap: float, sigma: float, seed_value: int
) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out := PackedVector2Array()
	var count := maxi(2, roundi(a.distance_to(b) / gap))
	for i in count + 1:
		var p := a.lerp(b, float(i) / count)
		if i > 0 and i < count:
			p += Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma))
		out.append(p)
	return out


## The length of a river body's course.
static func course_length(body: WaterBody) -> float:
	var total := 0.0
	for i in body.points.size() - 1:
		total += body.points[i].distance_to(body.points[i + 1])
	return total


static func _line(points: Array) -> PackedVector2Array:
	return PackedVector2Array(points)


## The document of the case `name` (see NAMES), planned with or without the probe.
static func make(name: String, conditioned: bool) -> MapDocument:
	var doc: MapDocument = null
	worst_cut = 0.0
	blocked = false
	hints = []
	var flat := func(_p: Vector2) -> float: return 0.0
	match name:
		"jitter":
			# A gentle slope with a rolling bed, a hand-jittered stroke down it.
			doc = world(_rolling)
			var line := jittered(Vector2(-13, 1), Vector2(13, -1), 0.3, 0.3, 11)
			add_stroke(doc, line, 1.0, WAIST, conditioned)
		"nonmonotone":
			# A valley that climbs a 1.2 m saddle halfway down: its ends are level.
			doc = world(func(p: Vector2) -> float: return 1.2 * exp(-pow(p.x / 3.0, 2.0)))
			add_stroke(doc, _line([Vector2(-13, 0), Vector2(13, 0)]), 0.9, WAIST, conditioned)
		"over_hill":
			# A 2.5 m ridge across the line, the stroke drawn over it.
			doc = world(func(p: Vector2) -> float: return -0.05 * p.x + 2.5 * exp(-pow(p.x / 2.5, 2.0)))
			add_stroke(doc, _line([Vector2(-13, 0), Vector2(13, 0)]), 0.9, WAIST, conditioned)
		"head_near_pond":
			# The fall spike's F4: a tier, a deep pond at its south foot, an ankle stream whose
			# head stands 1.5 m from the pond's edge, 3.9 m above it.
			doc = _plateau(flat)
			add_stroke(doc, _line([Vector2(0, -9), Vector2(0, 12)]), 1.2, ANKLE, conditioned)
		"end_near_pond":
			# The same plateau, a stream running south along it that stops 1.5 m short of the pond.
			doc = _plateau(flat)
			add_stroke(doc, _line([Vector2(0, -2), Vector2(0, -9)]), 1.2, ANKLE, conditioned)
		"shore_corner":
			# A river down a slope into the corner of a square pond: the shore turns 90 degrees.
			doc = world(func(p: Vector2) -> float: return 1.5 - 0.125 * clampf(p.x + p.y, -6.0, 6.0))
			var box := Rect2(Vector2(1, 1), Vector2(8, 8))
			add_pond(doc, Vector2.ZERO, 0.0, WaterBody.Depth.DEEP, box)
			var line := _line([Vector2(-12, -12), Vector2(-4, -4), Vector2(0.4, 0.4)])
			add_stroke(doc, line, 1.0, WAIST, conditioned)
		"confluence":
			# A trunk down a slope and a tributary whose end is inside the trunk's water.
			doc = world(func(p: Vector2) -> float: return -0.1 * p.x + 0.1 * absf(p.y))
			add_stroke(doc, _line([Vector2(-13, 0), Vector2(13, 0)]), 1.2, WAIST, conditioned)
			var line := _line([Vector2(-2, 12), Vector2(-3, 6), Vector2(1.0, 0.3)])
			add_stroke(doc, line, 0.7, WAIST, conditioned)
		"tiny_kink":
			# A slope with a 0.3 m ripple every 3 m: the greedy split cuts a step at every ripple.
			doc = world(func(p: Vector2) -> float: return -0.12 * p.x + 0.3 * sin(p.x * 2.1))
			add_stroke(doc, _line([Vector2(-13, 0), Vector2(13, 0)]), 0.9, WAIST, conditioned)
		"tall_fall":
			doc = world(flat)
			Fixtures.tier(doc, Vector2(-30, -10), Vector2(30, -10), 10.0, 6.0)
			add_stroke(doc, _line([Vector2(0, -12), Vector2(0, 12)]), 1.0, WAIST, conditioned)
		"ankle_fall":
			doc = world(flat)
			Fixtures.tier(doc, Vector2(-30, -10), Vector2(30, -10), 10.0, 0.8)
			add_stroke(doc, _line([Vector2(0, -12), Vector2(0, 12)]), 0.8, ANKLE, conditioned)
	return doc


static func _rolling(p: Vector2) -> float:
	return -0.07 * p.x + 0.18 * sin(p.x * 2.1) + 0.12 * sin(p.y * 1.7 + p.x)


## The F4 plateau: a tier whose south brink is at z -12 and a deep pond at its south foot.
static func _plateau(flat: Callable) -> MapDocument:
	var doc := world(flat)
	Fixtures.tier(doc, Vector2(-30, -6), Vector2(30, -6), 6.0, 4.0)
	add_pond(doc, Vector2(0, -14), 3.5)
	return doc


## What the field and the audit say about `doc`: {"film_run", "bridged_run", "end_near" (event
## counts), "film_m" (metres of film), "rises", "rise_m", "tiny", "falls", "reaches", "wet"
## (samples), "perched" (wet samples over 0.3 m deep on the waterline), "field_rise_m" (metres
## the field's surface climbs along strokes), "ms" (build time)}.
static func metrics(doc: MapDocument) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var field := WaterField.build(doc)
	var out := {
		"film_run": 0,
		"bridged_run": 0,
		"end_near": 0,
		"film_m": 0.0,
		"wet": 0,
		"perched": 0,
		"ms": (Time.get_ticks_usec() - t0) / 1000.0,
	}
	for e in field.events:
		match e.kind:
			&"film_run":
				out.film_run += 1
				out.film_m += e.length
			&"bridged_run":
				out.bridged_run += 1
			&"end_near_water":
				out.end_near += 1
	var audit := WaterPorts.audit(doc)
	out.rises = audit.rises
	out.rise_m = audit.rise_m
	out.tiny = audit.tiny_steps
	out.falls = audit.falls
	out.reaches = 0
	for body in doc.water_bodies:
		out.reaches += 1 if body.is_river() else 0
	out.wet = _wet_count(field)
	out.perched = _perched(field)
	out["field_rise_m"] = _field_rises(doc, field)
	return out


static func _wet_count(field: WaterField) -> int:
	var count := 0
	for d in field.depth:
		count += 1 if d > 0.0 else 0
	return count


## Wet samples over 0.3 m deep with a dry or buried neighbour: water standing proud of its shore.
static func _perched(field: WaterField) -> int:
	var count := 0
	var w := field.size.x
	for i in field.depth.size():
		if field.depth[i] <= 0.3:
			continue
		var x := i % w
		for off in [-1, 1, -w, w]:
			var j: int = i + off
			if (off == -1 and x == 0) or (off == 1 and x == w - 1):
				continue
			if j >= 0 and j < field.depth.size() and field.depth[j] <= 0.0:
				count += 1
				break
	return count


## Metres the water surface climbs along each stroke (steps over 1 cm between 0.5 m samples).
static func _field_rises(doc: MapDocument, field: WaterField) -> float:
	var total := 0.0
	for chain in RiverProfile.strokes(doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		var pts: PackedVector2Array = RiverProfile.build(typed).points
		var last := -INF
		for k in pts.size() - 1:
			var count := maxi(1, int(pts[k].distance_to(pts[k + 1]) / 0.5))
			for s in count:
				var i := field.index_of(pts[k].lerp(pts[k + 1], float(s) / count))
				if i < 0 or field.w[i] == WaterGeometry.DRY or field.depth[i] <= 0.0:
					continue
				if is_finite(last) and field.w[i] > last + 0.01:
					total += field.w[i] - last
				last = field.w[i]
	return total
