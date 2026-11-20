extends RefCounted

## The cases and the fuzz maps of the pond conditioner (test_water_pond.gd; not a test file itself:
## GUT only collects test_*.gd). Preload it as a const.
##
## The cases are the ones the river conditioner could not meet because the pond came second: the
## streams are drawn first (planned and carved as the editor does, WaterEdit.plan_river), then the
## pond is dug the way the editor digs it, by running WaterEditor.compute() on a snapshot of the
## document (the very function the Water tool's worker runs), with or without conditioning.
## make(name, on) returns {"doc", "out" (the compute's output: "level", "extra", "hints", "joined"),
## "mask" (the pond mask as painted)}.

const Cases := preload("res://tests/unit/water_condition_cases.gd")
const Multi := preload("res://tests/unit/water_multi_cases.gd")
const Fixtures := preload("res://tests/unit/water_fixtures.gd")
const WAIST := WaterBody.Depth.WAIST
const ANKLE := WaterBody.Depth.ANKLE
const NAMES: Array[String] = [
	"perched_head",
	"end_short",
	"two_in_one_out",
	"corner",
	"end_below",
	"pond_over_stream",
]


## Digs the pond of `centre` and `radius` (or the rectangle `box` when it has an area) into `doc`
## through WaterEditor.compute(), conditioned or not. Returns {"doc" (the document after the
## edit), "out", "mask" (the painted mask), "id", "rim_level"}.
static func dig(
	doc: MapDocument,
	centre: Vector2,
	radius: float,
	depth: WaterBody.Depth,
	on: bool,
	box: Rect2 = Rect2()
) -> Dictionary:
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
	var snapshot := WaterEditor.snapshot_of(doc)
	var rim := WaterGeometry.pond_rim_level(snapshot, id)
	var out := {}
	var spec := {"kind": "pond", "id": id, "depth": depth, "condition": on}
	WaterEditor.compute(snapshot, spec, out)
	return {"doc": snapshot, "out": out, "mask": mask, "id": id, "rim_level": rim}


## One case (see NAMES): the streams, then the pond.
static func make(name: String, pond_on: bool) -> Dictionary:
	var flat := func(_p: Vector2) -> float: return 0.0
	var doc: MapDocument = null
	# The streams are conditioned either way (the river conditioner is on in every build): the
	# A/B is the pond's alone.
	var on := true
	match name:
		"perched_head":
			# A stream whose head stands 1.5 m from where a pond is dug 3.9 m below it.
			doc = Cases.world(flat)
			Fixtures.tier(doc, Vector2(-30, -6), Vector2(30, -6), 6.0, 4.0)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(0, -9), Vector2(0, 8)]), 1.2, ANKLE, on)
			return dig(doc, Vector2(0, -14), 3.5, WaterBody.Depth.DEEP, pond_on)
		"end_short":
			# A stream that stops 1.5 m short of the pond, 3.9 m above it.
			doc = Cases.world(flat)
			Fixtures.tier(doc, Vector2(-30, -6), Vector2(30, -6), 6.0, 4.0)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(0, -2), Vector2(0, -9)]), 1.2, ANKLE, on)
			return dig(doc, Vector2(0, -14), 3.5, WaterBody.Depth.DEEP, pond_on)
		"two_in_one_out":
			# A bowl with an easy east side: two streams run in from the west and the north, one
			# starts on the east, each ending or starting 1.2 m from the pond's edge.
			doc = Cases.world(_bowl)
			var west := PackedVector2Array([Vector2(-12, -3), Vector2(-4.3, -0.9)])
			Cases.add_stroke(doc, west, 1.0, ANKLE, on)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(-3, 12), Vector2(-0.9, 4.3)]), 1.0, ANKLE, on)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(4.3, 0.9), Vector2(13, 3)]), 1.0, ANKLE, on)
			return dig(doc, Vector2.ZERO, 3.5, WaterBody.Depth.DEEP, pond_on)
		"corner":
			# A river down a slope that stops 1.4 m from the corner of a square pond dug after it.
			doc = Cases.world(func(p: Vector2) -> float: return 1.5 - 0.125 * clampf(p.x + p.y, -6.0, 6.0))
			var line := PackedVector2Array([Vector2(-12, -12), Vector2(-4, -4), Vector2(0.4, 0.4)])
			Cases.add_stroke(doc, line, 1.0, WAIST, on)
			var box := Rect2(Vector2(1, 1), Vector2(8, 8))
			return dig(doc, Vector2.ZERO, 0.0, WaterBody.Depth.DEEP, pond_on, box)
		"end_below":
			# A stream on a slope ends 1 m short of where a pond is dug whose rim holds it 0.4 m
			# above the stream's end: the stream would have to climb into the pond.
			doc = Cases.world(_dip)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(-12, 0), Vector2(-1.6, 0)]), 0.6, ANKLE, on)
			return dig(doc, Vector2(2.4, 0), 3.0, WaterBody.Depth.WAIST, pond_on)
		"pond_over_stream":
			# A pond dug across a stream: its rim reads the stream's carved bed.
			doc = Cases.world(func(p: Vector2) -> float: return -0.08 * p.x)
			Cases.add_stroke(doc, PackedVector2Array([Vector2(-13, 0), Vector2(13, 0)]), 1.0, WAIST, on)
			return dig(doc, Vector2(-3, 2.5), 3.0, WaterBody.Depth.DEEP, pond_on)
	return {}


## A gentle fall to the east that levels out at x = 0, with a 0.5 m dip at x = -1.4 (where the
## stream of "end_below" ends, 1.1 m short of the pond's edge).
static func _dip(p: Vector2) -> float:
	var base := 0.5 - 0.05 * clampf(p.x, -14.0, 0.0)
	return base - 0.9 * exp(-pow((p.x + 1.4) / 0.8, 2.0))


static func _bowl(p: Vector2) -> float:
	return 0.2 * maxf(p.length() - 4.0, 0.0) - 0.04 * clampf(p.x, 0.0, 8.0)


## Fuzz map `seed_value`: the river strokes of Multi.fuzz_strokes (random ground, free runs,
## tributaries, continuations, strokes stopping at or short of where a pond will be, drawn
## first), then its ponds dug after them (in drawing order, or reversed), each through compute().
## Returns {"doc", "ponds" (an Array of the dig() results, "level"/"rim"/"mask" per pond)}.
static func fuzz_map(seed_value: int, on: bool, reversed: bool = false) -> Dictionary:
	var doc := Multi.ground_doc()
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
	var rivers: Array[Dictionary] = []
	var ponds: Array[Dictionary] = []
	for s in Multi.fuzz_strokes(seed_value):
		if s.has("pond"):
			ponds.append(s)
		else:
			rivers.append(s)
	for s in rivers:
		Multi.draw(doc, s.p, s.hw, s.d, true)
	# The ponds: one to three, each dug a little beyond an end of a stroke (a tail or a head,
	# 0.3 to 2.5 m from its edge, a bit off the stroke's heading), as an author digs a pond where
	# a stream stops; the fuzz's own pond list only sets how many and how deep.
	var ends: Array[Vector2] = []
	var heads: Array[Vector2] = []
	for chain: Array in RiverProfile.strokes(doc.water_bodies):
		var first: WaterBody = chain[0]
		var last: WaterBody = chain[-1]
		ends.append(last.points[-1])
		heads.append(last.points[-1] - last.points[-2])
		ends.append(first.points[0])
		heads.append(first.points[0] - first.points[1])
	var digs: Array[Dictionary] = []
	if ends.is_empty():
		return {"doc": doc, "ponds": digs}
	var order: Array[Dictionary] = []
	for _i in rng.randi_range(1, 3):
		order.append({"d": rng.randi_range(0, 2) as WaterBody.Depth})
	if reversed:
		order.reverse()
	for s: Dictionary in order:
		var k := rng.randi_range(0, ends.size() - 1)
		var radius := rng.randf_range(2.0, 3.5)
		var away := heads[k].normalized().rotated(rng.randfn(0.0, 0.5))
		var centre: Vector2 = ends[k] + away * (radius + rng.randf_range(0.3, 2.5))
		if absf(centre.x) > 24.0 or absf(centre.y) > 24.0:
			continue
		var result := dig(doc, centre, radius, s.d, on)
		doc = result.doc
		digs.append(result)
	return {"doc": doc, "ponds": digs}
