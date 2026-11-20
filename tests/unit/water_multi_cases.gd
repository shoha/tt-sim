extends RefCounted

## Multi-stroke water maps for the conditioning tests (card painter-water-condition2; not a test
## file itself: GUT only collects test_*.gd). Preload it as a const.
##
## Every stroke goes through the same path the water tool takes: a pointer line sampled finely,
## decimated by LineGesture.spacing(), ended at the pointer, Chaikin smoothed (gesture_line()), then
## planned by WaterEdit.plan_river and carved (WaterCondition cases' add_stroke). verdict_map() is a
## reduction of the integration run's map (tiers, falls, ponds and the nine river strokes of
## tools/render_jobs/local/painter-water-field-v2/build_on.json on a gently rolling 61 m ground);
## fuzz_strokes() and fuzz_map() draw random multi-stroke maps (free runs, tributaries that end in
## earlier water, continuations that start at an earlier end, runs out of and into ponds), in the
## order drawn or reversed.

const Cases := preload("res://tests/unit/water_condition_cases.gd")
const Fixtures := preload("res://tests/unit/water_fixtures.gd")
const WAIST := WaterBody.Depth.WAIST
const ANKLE := WaterBody.Depth.ANKLE
const DEEP := WaterBody.Depth.DEEP
## The hard zigzag the integration run drew last (waist, half-width 1.2 m, 5 m amplitude).
const ZIGZAG: Array[Vector2] = [
	Vector2(2, 21),
	Vector2(6, 26),
	Vector2(11, 20),
	Vector2(16, 27),
	Vector2(21, 21),
	Vector2(26, 26),
]

## The plan reports of the strokes drawn since the last reset (draw() appends).
static var reports: Array[Dictionary] = []


## The line the water tool hands carve_river for a pointer path `raw` at half-width `hw`.
static func gesture_line(raw: PackedVector2Array, hw: float) -> PackedVector2Array:
	var spacing := LineGesture.spacing(hw)
	var length := StrokePath.line_length(raw)
	var pts := PackedVector2Array()
	var d := 0.0
	while d < length:
		pts = StrokePath.decimate(pts, point_at(raw, d), spacing)
		d += 0.05
	return StrokePath.smooth_line(StrokePath.with_tip(pts, raw[-1], StrokePath.DECIMATE_M))


static func point_at(points: PackedVector2Array, dist: float) -> Vector2:
	var walked := 0.0
	for i in points.size() - 1:
		var seg := points[i].distance_to(points[i + 1])
		if walked + seg >= dist and seg > 1e-9:
			return points[i].lerp(points[i + 1], (dist - walked) / seg)
		walked += seg
	return points[-1]


## A flat 61 m map (the integration run's "flat" new map, 200 ft).
static func ground_doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)


## Draws one river stroke: the pointer path `raw`, half-width `hw`, depth `depth`. Returns the
## plan's report.
static func draw(
	doc: MapDocument, raw: PackedVector2Array, hw: float, depth: WaterBody.Depth, condition: bool
) -> Dictionary:
	hw = WaterBrush.radius_for(hw, depth)
	var line := gesture_line(raw, hw)
	var report: Dictionary = Cases.add_stroke(doc, line, hw, depth, condition).report
	reports.append(report)
	return report


## A Tier stroke (the real sculpt profile) along the polyline `path` with brush `radius`, up to the
## tier the press picks (AuthoringEditor.tier_target: the ground under the first point, the
## neighbours within the radius), the way the Sculpt tool's tile does. `_levels` is the tier the
## integration run's author saw, unused.
static func tiers(doc: MapDocument, path: Array, radius: float, _levels: int = 0) -> void:
	var tier_m := doc.tier_height_m
	var press := WaterGeometry.ground_at(doc, path[0])
	var on_level := HeightBrush.tier_level(press, tier_m)
	var near := HeightBrush.tier_neighbours(
		doc, path[0], radius, HeightBrush.tier_height(on_level, tier_m), tier_m
	)
	var level := HeightBrush.tier_target_level(press, tier_m, false, near.x == 1, near.y == 1)
	for i in path.size() - 1:
		Fixtures.tier(doc, path[i], path[i + 1], radius, HeightBrush.tier_height(level, tier_m))


## The integration run's verdict map reduced to what the document sees: the tier strokes, the nine
## river strokes in the job's order and the two ponds (rim level), `condition` switching the plan's
## conditioning, `reversed` drawing the river strokes in the opposite order.
static func verdict_map(condition: bool, reversed: bool = false) -> MapDocument:
	var doc := NewMap.create(200, "temperate_forest_summer_s1", 1234)
	# The job's Tier strokes: each a pointer path round a box (x0, z0, x1, z1) and a brush radius.
	for box: Array in [
		[-13, -14, -3, -10, 3.0],
		[-11, -13.5, -5, -10.5, 2.4],
		[4, -14, 14, -10, 3.0],
		[6, -13.5, 12, -10.5, 2.4],
		[-13, 6, -3, 10, 3.0],
		[4, 6, 14, 10, 3.0],
		[6, 6.5, 12, 9.5, 2.4],
		[-21, -5, -17, -1, 2.0],
		[17, -28, 29, -8, 3.0],
		[18.5, -27, 27.5, -15, 2.4],
		[19.5, -26.5, 26.5, -21, 2.0],
	]:
		var ring := [
			Vector2(box[0], box[1]),
			Vector2(box[2], box[1]),
			Vector2(box[2], box[3]),
			Vector2(box[0], box[3]),
		]
		tiers(doc, ring, box[4])
	var strokes: Array[Dictionary] = [
		{"p": [Vector2(-8, -13.5), Vector2(-8, 0)], "hw": 1.5, "d": WAIST},
		{"p": [Vector2(9, -13.5), Vector2(9, -1.0)], "hw": 2.0, "d": WAIST},
		{"p": [Vector2(-8, 6.5), Vector2(-8, 18)], "hw": 0.55, "d": ANKLE},
		{"p": [Vector2(9, 6.5), Vector2(9, 18)], "hw": 0.55, "d": ANKLE},
		{"p": [Vector2(-21.5, -6), Vector2(-11.5, -0.5)], "hw": 1.0, "d": WAIST},
		{"p": [Vector2(23, -25), Vector2(23, -2)], "hw": 1.0, "d": WAIST},
		{"p": [Vector2(-12, 26), Vector2(-30.4, 26)], "hw": 0.6, "d": ANKLE},
		{"p": [Vector2(-1.5, -4), Vector2(-7.2, -4.5)], "hw": 0.5, "d": ANKLE},
		{"pond": [Vector2(9, 1.0)], "r": 3.5, "d": DEEP},
		{"pond": [Vector2(-21, 12.0)], "r": 3.0, "d": WAIST},
		{"p": [Vector2(-21, 12.5), Vector2(-21, 22)], "hw": 0.7, "d": ANKLE},
		{"p": ZIGZAG, "hw": 1.2, "d": WAIST},
	]
	if reversed:
		strokes.reverse()
	for s in strokes:
		if s.has("pond"):
			Cases.add_pond(doc, s.pond[0], s.r, s.d)
		else:
			draw(doc, PackedVector2Array(s.p), s.hw, s.d, condition)
	return doc


## The strokes of fuzz map `seed_value` as pointer paths: [{"p", "hw", "d"} or {"pond", "r", "d"}],
## in drawing order. Ponds come first.
static func fuzz_strokes(seed_value: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var out: Array[Dictionary] = []
	var ponds: Array[Vector2] = []
	for _i in rng.randi_range(0, 2):
		var at := Vector2(rng.randf_range(-16, 16), rng.randf_range(-16, 16))
		ponds.append(at)
		var pond_depth := rng.randi_range(0, 2) as WaterBody.Depth
		out.append({"pond": [at], "r": rng.randf_range(2.0, 3.5), "d": pond_depth})
	var courses: Array[PackedVector2Array] = []
	for k in rng.randi_range(3, 6):
		var kind := rng.randi_range(0, 4)
		var hw := rng.randf_range(0.55, 1.6)
		var depth := rng.randi_range(0, 2) as WaterBody.Depth
		var path := PackedVector2Array()
		var heading := rng.randf() * TAU
		var start := Vector2(rng.randf_range(-18, 18), rng.randf_range(-18, 18))
		var sigma := rng.randf_range(0.0, 0.35)
		if kind == 1 and not courses.is_empty():
			# A tributary: from afar, ending at a point of an earlier course.
			var other := courses[rng.randi_range(0, courses.size() - 1)]
			var join := other[rng.randi_range(0, other.size() - 1)]
			var away := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, 11.0)
			start = (join + away).clamp(Vector2(-26, -26), Vector2(26, 26))
			var bend := Vector2(rng.randfn(0.0, 0.8), rng.randfn(0.0, 0.8))
			path = PackedVector2Array([start, start.lerp(join, 0.5) + bend, join])
		elif kind == 2 and not courses.is_empty():
			# A continuation: starts at (or a little off) the end of an earlier stroke.
			var other := courses[rng.randi_range(0, courses.size() - 1)]
			start = other[-1] + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 2.5)
			heading = (other[-1] - other[-2]).angle() + rng.randfn(0.0, 0.4)
		elif kind == 3 and not ponds.is_empty():
			# Out of a pond.
			var shore := Vector2.from_angle(rng.randf() * TAU)
			start = ponds[rng.randi_range(0, ponds.size() - 1)] + shore
			heading = rng.randf() * TAU
		if path.is_empty():
			var pos := start
			path.append(pos)
			for _i in rng.randi_range(14, 40):
				heading += rng.randfn(0.0, 0.14)
				pos += Vector2.from_angle(heading) * 0.5
				if absf(pos.x) > 28.0 or absf(pos.y) > 28.0:
					break
				path.append(pos + Vector2(rng.randfn(0.0, sigma), rng.randfn(0.0, sigma)))
			if kind == 4 and not ponds.is_empty() and path.size() > 4:
				# Into a pond: the last point lands on its edge.
				path.append(ponds[rng.randi_range(0, ponds.size() - 1)])
		if path.size() < 4 or StrokePath.line_length(path) < 3.0:
			continue
		courses.append(path)
		out.append({"p": path, "hw": hw, "d": depth})
	return out


## fuzz map `seed_value` drawn from fuzz_strokes(), ponds first, then the strokes in order or
## reversed; `condition` switches the plan's conditioning.
static func fuzz_map(seed_value: int, condition: bool, reversed: bool = false) -> MapDocument:
	var doc := ground_doc()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var amp := rng.randf_range(0.0, 0.4)
	var slope := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.02, 0.1)
	var wave := rng.randf_range(4.0, 10.0)
	Fixtures.shape(
		doc,
		func(p: Vector2) -> float:
			return 2.0 + slope.dot(p) + amp * sin(p.x * TAU / wave) * cos(p.y * TAU / (wave * 1.3))
	)
	var strokes := fuzz_strokes(seed_value)
	var ponds: Array[Dictionary] = []
	var rivers: Array[Dictionary] = []
	for s in strokes:
		if s.has("pond"):
			ponds.append(s)
		else:
			rivers.append(s)
	if reversed:
		rivers.reverse()
	for s in ponds:
		Cases.add_pond(doc, s.pond[0], s.r, s.d)
	for s in rivers:
		draw(doc, s.p, s.hw, s.d, condition)
	return doc
