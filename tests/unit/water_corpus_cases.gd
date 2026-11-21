extends RefCounted

## The water corpus (card painter-water-robust; not a test file itself: GUT only collects
## test_*.gd). Preload it as a const.
##
## A set of drawn water layouts built from DATA, the same every run: the situations an author draws
## (straight and meandering streams, bends, joins, splits, streams into, out of and through ponds,
## falls, crossings, short and long strokes, both ends of the width range, strokes far from the
## map origin and beside its edge) and the ones that broke before (a pond's mouths, a fall into a
## pond, a stream ending short). maps() lists four maps, each a ground shape and its layouts; a
## layout is a cell of the map with its strokes in drawing order. build() draws one map the way the
## Water tool does, without a pointer, a frame or a worker (so two builds are identical: digest()):
## a river is the pointer path sampled every 5 cm, decimated, ended at the tip and smoothed
## (LineGesture's steps), planned by WaterEdit.plan_river and carved; a pond is its dabs' mask run
## through WaterEditor.compute(), the function the tool's worker runs. Conditioning is on.
##
## Two readers: test_water_corpus.gd runs field_report() on every map in the gate (the checks that
## need no window), and the render job tools/render_jobs/jobs/water_corpus.json plays the saved
## maps, captures every layout and scores the frames (tools/render_jobs/water_corpus_detect.gd).
## docs/systems/water.md "The water corpus" says how to run it before a water change merges.

const Fixtures := preload("res://tests/unit/water_fixtures.gd")
const ANKLE := WaterBody.Depth.ANKLE
const WAIST := WaterBody.Depth.WAIST
const DEEP := WaterBody.Depth.DEEP
const BIOME := "temperate_forest_summer_s1"
## The half extent (m) of a layout's cell a view frames.
const CELL_HALF := 9.0
## The distance between the centres of neighbouring cells (m).
const CELL_PITCH := 24.0
## The ground of map "steps": terraces stepping down along +x, [x of the cliff, its height].
const STEPS := [[-18.0, 1.0], [0.0, 1.6], [18.0, 2.5]]
## The fall of map "tilt" along +x (m per m).
const TILT := 0.05


## The corpus: [{"name", "size_ft", "ground" ("flat", "tilt", "steps"), "layouts": [{"name", "at"
## (the cell's centre), "ops": [{"p": points, "hw", "d"} a river stroke or {"pond": dab points,
## "r", "d"} a pond; points are relative to `at`]}]}].
static func maps() -> Array[Dictionary]:
	# The flat layouts fill two maps: one map of all 22 reached the document's body cap, and its
	# last strokes (the widths, the loop, the long stroke) were refused.
	#
	# Layouts must not touch each other (card painter-water-paths): a stroke end joins water
	# within 1.5 of its half-widths (WaterPorts.snap_reach), so cells stand CELL_PITCH apart
	# (strokes reach 8 m from a cell's centre: 8 m between neighbours, three widths of a waist
	# stroke), and the widest brush (10 m half-width, a 15 m reach) is drawn first on its map
	# (flat2) or alone on one (steps_wide).
	var flat := _flat_layouts()
	var wide := [_layout("s_fall_wide", _v(18, 0), [_river([_v(-7, 0), _v(7, 0)], 10.0, DEEP)])]
	return [
		{"name": "flat", "size_ft": 320, "ground": "flat", "layouts": flat.slice(0, 12)},
		{"name": "flat2", "size_ft": 320, "ground": "flat", "layouts": flat.slice(12)},
		{"name": "tilt", "size_ft": 320, "ground": "tilt", "layouts": _tilt_layouts()},
		{"name": "steps", "size_ft": 200, "ground": "steps", "layouts": _steps_layouts()},
		{"name": "steps_wide", "size_ft": 200, "ground": "steps", "layouts": wide},
		{"name": "wood", "size_ft": 200, "ground": "flat", "layouts": _wood_layouts()},
	]


## The map named `name` ({} when there is none).
static func map_named(name: String) -> Dictionary:
	for m in maps():
		if m.name == name:
			return m
	return {}


## The layout `name` of any map, with "map" added ({} when there is none).
static func layout_named(name: String) -> Dictionary:
	for m in maps():
		for l: Dictionary in m.layouts:
			if l.name == name:
				var out := l.duplicate()
				out["map"] = m.name
				return out
	return {}


static func _river(points: Array, hw: float = 1.0, depth: int = WAIST) -> Dictionary:
	return {"p": points, "hw": hw, "d": depth}


static func _pond(points: Array, r: float, depth: int = WAIST) -> Dictionary:
	return {"pond": points, "r": r, "d": depth}


static func _layout(name: String, at: Vector2, ops: Array) -> Dictionary:
	return {"name": name, "at": at, "ops": ops}


## A sine meander from `a` to `b`: `waves` whole waves of amplitude `amp`, a point every metre.
static func _meander(a: Vector2, b: Vector2, amp: float, waves: float) -> Array:
	var out := []
	var n := maxi(2, roundi(a.distance_to(b)))
	var side := (b - a).normalized().orthogonal()
	for i in n + 1:
		var t := float(i) / n
		out.append(a.lerp(b, t) + side * amp * sin(t * TAU * waves))
	return out


static func _v(x: float, z: float) -> Vector2:
	return Vector2(x, z)


static func _flat_layouts() -> Array:
	# Four columns and rows of cells on a 97 m map: centres at -36, -12, 12 and 36.
	var c := func(col: int, row: int) -> Vector2:
		return Vector2(col - 1.5, row - 1.5) * CELL_PITCH
	var ring := []
	for i in 25:
		ring.append(Vector2.from_angle(TAU * i / 24.0) * 5.0)
	return [
		# Map "flat": 12 layouts. f_through_pond's strokes in the map's far corner, 51 m from the
		# origin.
		_layout(
			"f_through_far",
			c.call(0, 0),
			[
				_river([_v(-8, -1.5), _v(-4.4, -0.6)]),
				_river([_v(-1.5, 8), _v(-0.6, 4.4)]),
				_river([_v(4.4, 0.6), _v(8, 2)]),
				_pond([_v(0, 0), _v(0.4, 0)], 3.5, DEEP),
			]
		),
		_layout("f_meander", c.call(1, 0), [_river(_meander(_v(-8, 0), _v(8, 0), 2.5, 1.5))]),
		_layout(
			"f_tight_bends",
			c.call(2, 0),
			[_river([_v(-8, -2), _v(-5, 2), _v(-2, -2), _v(1, 2), _v(4, -2), _v(7, 2)], 0.8)]
		),
		_layout(
			"f_hairpin",
			c.call(3, 0),
			[_river([_v(-6, -3), _v(4.5, -3), _v(6.5, 0), _v(4.5, 3), _v(-6, 3)], 0.8)]
		),
		_layout(
			"f_self_cross",
			c.call(0, 1),
			[_river([_v(-7, -3), _v(4, -3), _v(5, 2), _v(0, 4), _v(-2, 0), _v(-2, -7)], 0.8)]
		),
		_layout(
			"f_y_join",
			c.call(1, 1),
			[_river([_v(-7, 2), _v(7, 2)]), _river([_v(-5, -6), _v(-1, -1), _v(0, 1.6)], 0.7)]
		),
		_layout(
			"f_split",
			c.call(2, 1),
			[_river([_v(-7, 0), _v(0, 0), _v(7, -4)]), _river([_v(0, 0.2), _v(3, 2), _v(7, 4)], 0.8)]
		),
		_layout(
			"f_cross", c.call(0, 2), [_river([_v(-7, 0), _v(7, 0)]), _river([_v(0, -7), _v(0, 7)], 0.8)]
		),
		_layout(
			"f_short",
			c.call(1, 2),
			[_river([_v(-4, -2), _v(-2, -2)], 0.6, ANKLE), _river([_v(1, 2), _v(1.9, 2)], 0.6, ANKLE)]
		),
		# A stream drawn on past the map's east edge (the exit ribbon, not a field surface).
		_layout("f_exit", c.call(3, 1), [_river([_v(-6, -3), _v(0, 0), _v(16, 0)])]),
		_layout("f_pond_only", c.call(2, 2), [_pond([_v(0, 0), _v(0.4, 0)], 3.5, DEEP)]),
		_layout(
			"f_into_pond",
			c.call(3, 2),
			[_river([_v(-8, 0), _v(-1.6, 0)]), _pond([_v(3, 0), _v(3.4, 0)], 3.5, DEEP)]
		),
		# Map "flat2": 10 layouts. Both ends of the brush's width range, drawn first (the widest
		# deep river reaches 20 m for water to join, and nothing is there yet), the wide river
		# before the narrowest ankle stream, 14 m apart.
		_layout(
			"f_widths",
			_v(24, 12),
			[
				_river(_meander(_v(-8, 8), _v(8, 8), 1.0, 1.0), 10.0, DEEP),
				_river(_meander(_v(-8, -6), _v(8, -6), 1.0, 2.0), 0.1, ANKLE),
			]
		),
		_layout(
			"f_out_of_pond",
			c.call(0, 0),
			[_pond([_v(-3, 0), _v(-2.6, 0)], 3.5, DEEP), _river([_v(-2, 0), _v(3, 0.5), _v(8, 2)])]
		),
		_layout(
			"f_end_short",
			c.call(1, 0),
			[_river([_v(-8, 0), _v(-1.8, 0)]), _pond([_v(3, 0), _v(3.4, 0)], 2.8)]
		),
		_layout(
			"f_two_inflows",
			c.call(2, 0),
			[
				_pond([_v(2, 0), _v(2.4, 0)], 3.5),
				_river([_v(-8, -5), _v(-3, -3), _v(0.5, -1.5)]),
				_river([_v(-8, 5), _v(-3, 3), _v(0.5, 1.5)]),
			]
		),
		_layout(
			"f_pond_over_stream",
			c.call(3, 0),
			[_river([_v(-8, 0), _v(8, 0)]), _pond([_v(-1, 2.5), _v(-0.6, 2.5)], 3.0, DEEP)]
		),
		_layout(
			"f_pond_chain",
			c.call(0, 1),
			[
				_pond([_v(-5, -3), _v(-4.6, -3)], 2.5),
				_pond([_v(5, 3), _v(5.4, 3)], 2.5),
				_river([_v(-4, -2.4), _v(0, 0), _v(4, 2.4)], 0.7),
			]
		),
		_layout("f_loop", c.call(1, 1), [_river(ring, 0.8)]),
		# The same strokes as f_through_far, on the other map and after other layouts (on map
		# "flat" it would be the 32nd river and beyond: MapDocument.MAX_RIVERS, a join the
		# document has no room for is skipped).
		_layout(
			"f_through_pond",
			c.call(2, 1),
			[
				_river([_v(-8, -1.5), _v(-4.4, -0.6)]),
				_river([_v(-1.5, 8), _v(-0.6, 4.4)]),
				_river([_v(4.4, 0.6), _v(8, 2)]),
				_pond([_v(0, 0), _v(0.4, 0)], 3.5, DEEP),
			]
		),
		# One very long stroke along the map's south side, its ends under 3 m from the east and west
		# edges (its views: the middle and an end).
		_layout("f_long_mid", _v(0, 40), [_river(_meander(_v(-46, 0), _v(46, 0), 1.5, 5.0))]),
		_layout("f_long_end", _v(39, 40), []),
	]


static func _tilt_layouts() -> Array:
	var c := func(col: int, row: int) -> Vector2: return Vector2(col - 1, row - 1) * CELL_PITCH
	return [
		_layout("t_straight", c.call(0, 0), [_river([_v(-7, 0), _v(7, 0)])]),
		_layout("t_meander", c.call(1, 0), [_river(_meander(_v(-8, 0), _v(8, 0), 2.5, 1.5))]),
		_layout("t_across", c.call(2, 0), [_river([_v(0, -7), _v(0, 7)])]),
		_layout("t_uphill", c.call(0, 1), [_river([_v(7, 0), _v(-7, 0)])]),
		_layout(
			"t_through_pond",
			c.call(1, 1),
			[
				_river([_v(-8, -1.5), _v(-4.4, -0.6)]),
				_river([_v(-1.5, -8), _v(-0.6, -4.4)]),
				_river([_v(4.4, 0.6), _v(8, 2)]),
				_pond([_v(0, 0), _v(0.4, 0)], 3.5, DEEP),
			]
		),
		_layout(
			"t_hairpin",
			c.call(2, 1),
			[_river([_v(-6, -4), _v(4.5, -4), _v(6.5, 0), _v(4.5, 4), _v(-6, 4)], 0.8)]
		),
		_layout(
			"t_y_join",
			c.call(0, 2),
			[_river([_v(-7, 2), _v(7, 2)]), _river([_v(-5, -6), _v(-1, -1), _v(0, 1.6)], 0.7)]
		),
		_layout(
			"t_end_short",
			c.call(1, 2),
			[_river([_v(-8, 0), _v(-1.8, 0)]), _pond([_v(3, 0), _v(3.4, 0)], 2.8)]
		),
		_layout(
			"t_cross",
			c.call(2, 2),
			[_river([_v(-7, -3), _v(7, 3)]), _river([_v(-2, -7), _v(2, 7)], 0.8)]
		),
	]


static func _steps_layouts() -> Array:
	var out := []
	for k in STEPS.size():
		var x: float = STEPS[k][0]
		var tag := "s%d" % k
		# A stream over the cliff into its own pool (6.5 m each side: the cliffs stand 18 m apart,
		# and 5 m between two strokes' ends keeps them from joining).
		out.append(_layout(tag + "_fall_pool", _v(x, -22), [_river([_v(-6.5, 0), _v(6.5, 0)])]))
		# A fall straight into a pond: the stream first and the pond dug at the foot (k 0), or the
		# pond first and the stream drawn over the lip into it.
		if k == 0:
			out.append(
				_layout(
					tag + "_fall_pond",
					_v(x, -8),
					[_river([_v(-7, 0), _v(-0.4, 0)]), _pond([_v(4, 0), _v(4.4, 0)], 3.0, DEEP)]
				)
			)
		else:
			out.append(
				_layout(
					tag + "_fall_pond",
					_v(x, -8),
					[_pond([_v(4, 0), _v(4.4, 0)], 3.0, DEEP), _river([_v(-7, 0), _v(4, 0)])]
				)
			)
		# Water against the cliff: a stream along its foot.
		out.append(_layout(tag + "_cliff_foot", _v(x, 5), [_river([_v(1.8, -5), _v(1.8, 5)], 0.8)]))
	out.append(_layout("s_up_cliff", _v(-18, 17), [_river([_v(7, 0), _v(-7, 0)])]))
	out.append(_layout("s_pond_on_lip", _v(0, 17), [_pond([_v(0, 0), _v(0.4, 0)], 3.0)]))
	# (s_fall_wide, the widest stroke over the 2.5 m cliff, has map "steps_wide" to itself.)
	# Stacked falls: one stroke over all three cliffs, 3 m inside the map's south edge.
	out.append(_layout("s_stacked_a", _v(-9, 26.5), [_river([_v(-17, 0), _v(35, 0)])]))
	out.append(_layout("s_stacked_b", _v(12, 26.5), []))
	return out


## The wood: the biome's own trees (generated when the map is first shown in authoring) over a
## meandering stream and a pond; the render job stands the tokens in it.
static func _wood_layouts() -> Array:
	return [
		_layout("w_stream", _v(-12, -8), [_river(_meander(_v(-12, 0), _v(34, 4), 3.0, 2.5))]),
		_layout("w_stream_b", _v(10, -6), []),
		_layout(
			"w_pond",
			_v(0, 12),
			[_pond([_v(0, 0), _v(2, 1)], 4.0, DEEP), _river([_v(-3, -14), _v(-2, -8), _v(-1, -4.6)], 0.8)]
		),
	]


## The ground height of map kind `ground` at `p`, added to the new map's own.
static func ground_at(ground: String, p: Vector2) -> float:
	match ground:
		"tilt":
			return -TILT * p.x
		"steps":
			var h := 0.0
			for s: Array in STEPS:
				h += float(s[1]) * (1.0 - smoothstep(-0.6, 0.6, p.x - float(s[0])))
			return h
	return 0.0


## Builds corpus map `m` (an entry of maps()). Returns {"doc", "strokes" (per river stroke: the
## plan's report with "layout" added), "ponds" (per pond: compute()'s output with "layout")}.
static func build(m: Dictionary) -> Dictionary:
	var doc := NewMap.create(int(m.size_ft), BIOME, 1234)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			heights[i] += ground_at(String(m.ground), doc.sample_to_world(Vector2(x, z)))
	doc.heights = heights
	var strokes: Array[Dictionary] = []
	var ponds: Array[Dictionary] = []
	for l: Dictionary in m.layouts:
		var at: Vector2 = l.at
		for op: Dictionary in l.ops:
			if op.has("pond"):
				var out := dig(doc, _moved(op.pond, at), float(op.r), int(op.d))
				out["layout"] = l.name
				ponds.append(out)
				continue
			var depth := int(op.d) as WaterBody.Depth
			var hw := WaterBrush.radius_for(float(op.hw), depth)
			var line := gesture_line(_moved(op.p, at), hw)
			var report := add_stroke(doc, line, hw, depth)
			report["layout"] = l.name
			strokes.append(report)
	return {"doc": doc, "strokes": strokes, "ponds": ponds}


## Plans, carves and adds one river stroke along `line` the way WaterEditor.carve_river does (the
## part past the map edge becomes the river's exit, RiverExits; the plan is conditioned). Returns
## the plan's report, with "refused" when nothing was made.
static func add_stroke(
	doc: MapDocument, line: PackedVector2Array, hw: float, depth: WaterBody.Depth
) -> Dictionary:
	var widths := PackedFloat32Array()
	widths.resize(line.size())
	widths.fill(hw)
	var reach := AuthoredTerrain.skirt_width_m()
	var split := RiverExits.split_line(line, widths, doc.extent_m() * 0.5, reach)
	var inside: PackedVector2Array = split.inside
	var report := {}
	if inside.size() < 2:
		report["refused"] = "short"
		return report
	var start := doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(doc, inside, split.widths, depth, 1.0, true, report)
	if bodies.is_empty():
		# The plan's own refusal (a line too short to hold water) is kept.
		report["refused"] = String(report.get("refused", "in water or full"))
		return report
	RiverExits.attach(bodies, split)
	Fixtures.carve(doc, WaterCarve.river_goals(doc, bodies, start))
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	# What the tests compare: the line's length as drawn and as stored, and the stroke's bodies.
	report["drawn_m"] = line_length(inside)
	report["stored_m"] = 0.0
	report["ids"] = PackedInt32Array()
	for body in bodies:
		report.stored_m += line_length(body.points)
		report.ids.append(body.id)
	return report


## The length of polyline `points` (metres).
static func line_length(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	return total


static func _moved(points: Array, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(p + at)
	return out


## The line the Water tool hands the carve for a pointer path `raw` at half-width `hw`
## (LineGesture.track and line(): sampled every 5 cm here, never by a frame's length).
static func gesture_line(raw: PackedVector2Array, hw: float) -> PackedVector2Array:
	var spacing := LineGesture.spacing(hw)
	var pts := PackedVector2Array()
	var walked := 0.0
	for i in raw.size() - 1:
		var seg := raw[i].distance_to(raw[i + 1])
		var t := 0.0 if i == 0 else 0.05 - fmod(walked, 0.05)
		while t < seg:
			pts = StrokePath.decimate(pts, raw[i].lerp(raw[i + 1], t / maxf(seg, 1e-9)), spacing)
			t += 0.05
		walked += seg
	return StrokePath.smooth_line(StrokePath.with_tip(pts, raw[-1], StrokePath.DECIMATE_M))


## Digs a pond into `doc` the way the Water tool does: the mask of dabs of `radius` along `path`,
## then WaterEditor.compute() on a snapshot (conditioned), landed on `doc`. Returns its output.
static func dig(
	doc: MapDocument, path: PackedVector2Array, radius: float, depth: int
) -> Dictionary:
	var mask := doc.pond_mask.duplicate()
	if mask.size() != doc.sample_count():
		mask.resize(doc.sample_count())
	var id := doc.next_water_id()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			for i in path.size():
				var near := Geometry2D.get_closest_point_to_segment(p, path[maxi(i - 1, 0)], path[i])
				if near.distance_to(p) < radius:
					mask[doc.sample_index(x, z)] = id
					break
	doc.pond_mask = mask
	var snapshot := WaterEditor.snapshot_of(doc)
	var out := {}
	WaterEditor.compute(snapshot, {"kind": "pond", "id": id, "depth": depth, "condition": true}, out)
	doc.heights = snapshot.heights
	doc.water_bodies = snapshot.water_bodies
	if out.has("dressing"):
		doc.water_dressing = out.dressing
	out["id"] = id
	return out


## A hash of what the build made (heights, pond mask, every body's points, widths and level): two
## builds of one map give the same digest.
static func digest(doc: MapDocument) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(doc.heights.to_byte_array())
	if not doc.pond_mask.is_empty():
		ctx.update(doc.pond_mask)
	for b in doc.water_bodies:
		var head := PackedFloat32Array([b.id, b.level_m])
		ctx.update(head.to_byte_array())
		if not b.points.is_empty():
			ctx.update(b.points.to_byte_array())
			ctx.update(b.half_widths.to_byte_array())
	return ctx.finish().hex_encode().substr(0, 12)


## The field-side checks of a built map (no render): {"wet" samples, "nan" (a NaN or infinite
## value in a wet sample's channels), "lateral_out" (river samples whose |lateral| exceeds the
## widest half-width plus the bank and a sample), "foot_out" (a foot coordinate outside
## [-NO_FOOT, NO_FOOT]), "perched" (wet samples standing over 0.3 m above a dry 4-neighbour's
## ground), "u_jumps" (4-neighbour river pairs of ONE stroke whose flow coordinate differs by
## more than 2 m: the arc must be continuous inside a stroke), "lat_jumps" (the same for the
## lateral coordinate, 1 m), "seam_pairs" (wet 4-neighbour pairs owned by different bodies: where
## a stroke-keyed coordinate meets another frame; information, the shader's risk scales with it),
## "events" (the field's own, by kind), "junctions" (WaterJunctions.find), "junction_seams" (the
## pairs u_jumps and lat_jumps would count that lie in a junction of a stroke with itself: a
## self-crossing, a ring's closure, a bend's inside. Two passes of one stroke meet there as two
## strokes do, which are seam_pairs: two frames at one place, not a break inside a frame)}.
static func field_report(doc: MapDocument) -> Dictionary:
	var f := WaterField.build(doc)
	var junctions := WaterJunctions.find(doc)
	var own: Array[Dictionary] = []
	for junction in junctions:
		if bool(junction.own):
			own.append(junction)
	var widest := 0.0
	for b in doc.water_bodies:
		for hw in b.half_widths:
			widest = maxf(widest, hw)
	var lat_max := widest + WaterGeometry.RIVER_BANK_M + f.step.x
	var no_foot: float = WaterFieldStroke.NO_FOOT
	var r := {
		"wet": 0, "nan": 0, "lateral_out": 0, "foot_out": 0, "perched": 0, "u_jumps": 0,
		"lat_jumps": 0, "seam_pairs": 0, "events": {}, "foot_min": 0.0, "foot_max": 0.0,
		"junctions": junctions, "junction_seams": 0,
	}
	var sx := f.size.x
	for z in f.size.y:
		for x in sx:
			var i := z * sx + x
			if f.depth[i] <= 0.0:
				continue
			r.wet += 1
			var vals := [f.w[i], f.ew[i], f.depth[i], f.energy[i], f.steep[i], f.shore[i], f.lateral[i]]
			for v: float in vals:
				if is_nan(v) or is_inf(v):
					r.nan += 1
			var river := f.flow_u[i] > WaterField.NO_FLOW_U * 0.5
			if river and absf(f.lateral[i]) > lat_max:
				r.lateral_out += 1
			var has_foot := river and f.foot[i] < no_foot * 0.5
			if has_foot:
				r.foot_min = minf(r.foot_min, f.foot[i])
				r.foot_max = maxf(r.foot_max, f.foot[i])
			if river and (is_nan(f.foot[i]) or (has_foot and absf(f.foot[i]) > 4.5)):
				r.foot_out += 1
			# A foot seam (WaterFieldStroke.foot_seams): a neighbour ahead whose coordinate has the
			# other sign, further off than a foot's own crossing steps.
			for ahead: int in [1, sx - 1, sx, sx + 1] if f.foot[i] < no_foot * 0.5 else []:
				var other: float = f.foot[i + ahead] if i + ahead < f.foot.size() else no_foot
				var jump := absf(other - f.foot[i]) > WaterFieldStroke.FOOT_SEAM_JUMP
				if other < no_foot * 0.5 and other * f.foot[i] < 0.0 and jump:
					r.foot_seams = int(r.get("foot_seams", 0)) + 1
			for o: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var nx := x + o.x
				var nz := z + o.y
				if nx < 0 or nz < 0 or nx >= sx or nz >= f.size.y:
					continue
				var j := nz * sx + nx
				if f.depth[j] <= 0.0:
					if f.depth[i] > 0.3 and f.w[i] - f.ground[j] > 0.3:
						r.perched += 1
					continue
				if o.x < 0 or o.y < 0:
					continue
				if f.owner[i] != f.owner[j]:
					r.seam_pairs += 1
					continue
				var river_j := f.flow_u[j] > WaterField.NO_FLOW_U * 0.5
				if river and river_j:
					var u_jump := absf(f.flow_u[i] - f.flow_u[j]) > 2.0
					var lat_jump := absf(f.lateral[i] - f.lateral[j]) > 1.0
					if not u_jump and not lat_jump:
						continue
					var p := f.origin + Vector2(x, z) * f.step
					var in_junction := false
					for junction in own:
						if p.distance_to(junction.pos) <= float(junction.radius):
							in_junction = true
							break
					if in_junction:
						r.junction_seams += 1
						continue
					r.u_jumps += 1 if u_jump else 0
					r.lat_jumps += 1 if lat_jump else 0
	for e in f.events:
		r.events[e.kind] = int(r.events.get(e.kind, 0)) + 1
	r["event_list"] = f.events
	return r
