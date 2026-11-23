class_name WaterFieldStroke
extends RefCounted

## One river stroke's share of the water field (WaterField): the 1D tables along its arc, the
## runs of undermined stations the water bridges or films, and the events a map validation can
## read. Pure and static: nothing here touches a grid.

## The 1D tables per stroke are sampled this finely along the arc.
const TABLE_STEP := 0.05
## The stations of RiverProfile.stations() are this far apart.
const STATION_STEP := 0.25
## Riffle white: the level's slope (m per m) where it begins and is full, how far it carries,
## and its strength.
const RIFFLE_SLOPE := Vector2(0.05, 0.3)
const RIFFLE_CARRY_M := 1.4
const RIFFLE_WHITE := 0.6
## Fall white (card painter-water-lip): how far above the lip the brink line starts and how white it
## is (a thin soft line at the edge: the water above it is still glass), the white the face's top
## holds (a few bright columns) and the share of the face over which it builds to the full white of
## the face's lower part, and the foot foam's decay length (base plus per metre of drop).
const BRINK_M := 0.5
const BRINK_PEAK := 0.4
const FACE_TOP := 0.3
const FACE_RAMP := 0.65
const FOOT_DECAY_M := 0.4
const FOOT_DECAY_PER_DROP := 0.2
## A low fall of the terraforming core (table()'s `soft`: a step the reaches rule gathered on an
## even slope, under the derive's POOL_TALL_M) is a lively soft one, not a sheet: its brink, face
## and foot white are SOFT_FALL_WHITE of a tall fall's, so the face is glass with a few columns
## over the foot's floor of white tongues. At full white a 1.4 m step read as a white sluice gate
## of evenly spaced stripes, heavier than the tall fall above it (card terraform-p2-river-polish).
const SOFT_FALL_M := 2.5
const SOFT_FALL_WHITE := 0.55
## The lip speed of a fall's water (WaterFallMesh.V0_BASE plus V0_PER_SPEED times the upper
## reach's speed) sets where the white of the face ends and the foot foam begins (the distance
## it would travel in the fall's time): the field keeps that split, though no arc is drawn.
const G := 9.81
## Undermined water: a run of undermined stations no longer than BRIDGE_M between held ones is a
## dip the water bridges at its level; any other run is a film (a map error to validate).
const BRIDGE_M := 2.1
## The foot coordinate (see table()): how far either side of a fall's foot it is written, and the
## value outside it.
const FOOT_RANGE_M := 4.0
const NO_FOOT := 99.0
## The drop (m) whose fall the shader's foot rules are written for, and the least a low fall's
## coordinate is divided by (the rules' lengths shrink to this share of themselves).
const FOOT_DROP_REF := 3.0
const FOOT_SCALE_MIN := 0.45
## Two neighbouring samples whose foot coordinates have opposite signs and stand further apart
## than this are on a seam (foot_seams()). Across a foot itself the coordinate passes through 0
## in steps of at most a sample's diagonal over FOOT_SCALE_MIN (0.8) plus a table entry (0.55).
const FOOT_SEAM_JUMP := 2.0

## Switch (a probe's A/B): false keeps the foot coordinate's seams in the field (the data of
## before card painter-water-climb-2); a field is built after a change.
static var foot_seams_cleared := true


## The stroke's level, white-water `energy` and brink-and-face `core` white every TABLE_STEP
## along its arc: {"level", "energy", "core"} (PackedFloat32Array each). The level is the
## profile's bank level (flat over a reach, eased over a riffle, stepping down a fall's face with
## the carve); the energy is the fall's foot foam and the riffle white carried downstream, the
## core the brink and the face. `soft` (the terraforming core's water) draws every fall under
## SOFT_FALL_M as a soft one (SOFT_FALL_WHITE).
static func table(
	profile: RiverProfile, chain: Array[WaterBody], soft: bool = false
) -> Dictionary:
	var count := int(ceil(profile.total / TABLE_STEP)) + 1
	var lev := PackedFloat32Array()
	var en := PackedFloat32Array()
	var core := PackedFloat32Array()
	lev.resize(count)
	en.resize(count)
	core.resize(count)
	for t in count:
		lev[t] = profile.level_at(t * TABLE_STEP)
	for fall in profile.falls:
		var lip := float(fall.lip)
		var drop := float(fall.drop)
		var upper_body := chain[clampi(int(fall.step), 0, chain.size() - 1)]
		var v0 := WaterFallMesh.V0_BASE + WaterFallMesh.V0_PER_SPEED * upper_body.speed
		var land := v0 * sqrt(2.0 * drop / G)
		var decay := FOOT_DECAY_M + FOOT_DECAY_PER_DROP * drop
		var strength := clampf(drop / 1.0, 0.6, 1.0)
		if soft and drop < SOFT_FALL_M:
			strength *= SOFT_FALL_WHITE
		var face_m := maxf(float(fall.foot) - lip, 0.5)
		for t in count:
			var x := t * TABLE_STEP - lip
			if x <= 0.0:
				core[t] = maxf(core[t], smoothstep(-BRINK_M, 0.0, x) * BRINK_PEAK * strength)
			elif x <= land:
				# The face's white builds from a few columns at the lip to the full sheet low down.
				var build := smoothstep(0.0, FACE_RAMP * face_m, x)
				core[t] = maxf(core[t], strength * lerpf(FACE_TOP, 1.0, build))
			else:
				en[t] = maxf(en[t], exp(-(x - land) / decay) * strength)
	# The foot coordinate: the signed arc distance to the nearest fall's foot (the face's end, where
	# the surface reaches the lower level), negative on the face, positive in the plunge pool;
	# NO_FOOT beyond FOOT_RANGE_M. One smooth function of the arc, so the shader's face and pool
	# rules can meet on it (card painter-water-foot-spike).
	var foot := PackedFloat32Array()
	foot.resize(count)
	foot.fill(NO_FOOT)
	for fall in profile.falls:
		var foot_s := float(fall.foot)
		# The coordinate is stretched by the fall's own height (card painter-water-foot3): the shader's
		# rules (the white floor above the foot, the tongues and the veil below it) are fixed lengths in
		# the coordinate, so a low fall's get shorter in metres and a pool of calm blue shows at its foot
		# at every size, where a tall fall keeps the full rules.
		var k := clampf(float(fall.drop) / FOOT_DROP_REF, FOOT_SCALE_MIN, 1.0)
		for t in count:
			var real := t * TABLE_STEP - foot_s
			var d := real / k
			if absf(real) < FOOT_RANGE_M and (foot[t] > NO_FOOT * 0.5 or absf(d) < absf(foot[t])):
				foot[t] = d
	# Riffles: the level's own slope, carried downstream.
	var carry := int(RIFFLE_CARRY_M / TABLE_STEP)
	var slope_e := PackedFloat32Array()
	slope_e.resize(count)
	for t in range(1, count - 1):
		var sl := absf(lev[t + 1] - lev[t - 1]) / (2.0 * TABLE_STEP)
		slope_e[t] = smoothstep(RIFFLE_SLOPE.x, RIFFLE_SLOPE.y, sl) * RIFFLE_WHITE
	# Each sloped entry carries its white `carry` entries on, fading linearly; the max of what
	# reaches an entry (only sloped entries reach any: most are none), written from the source.
	for from in count:
		var e := slope_e[from]
		if e <= 0.0:
			continue
		for c in mini(carry, count - 1 - from) + 1:
			en[from + c] = maxf(en[from + c], e * (1.0 - float(c) / float(carry + 1)))
	return {"level": lev, "energy": en, "core": core, "foot": foot}


## Writes `out`, the foot coordinate the field hands the shader, from `raw`, the coordinate as
## the strokes wrote it, over `region` (samples) of a grid of `size`: `raw`, except NO_FOOT on
## every sample at a seam. A seam is where the coordinate jumps across zero between two of a
## sample's eight neighbours (FOOT_SEAM_JUMP): the far end of one fall's plunge pool (positive)
## beside the approach of the next fall (negative), which two falls of one stroke less than twice
## FOOT_RANGE_M apart have midway between their feet, and two strokes can have where they meet.
## The texture's filter draws every value between the two sides there, the foot's own among them
## (0: the white floor, the tongues and the veil), as a ruled white hairline across the pool,
## straight along the seam whatever the water does. With both sides cleared no 2 x 2 block of
## samples holds the two signs, and the filter (weighted by the foot's own weight) never mixes
## them: each side ends as the coordinate ends at its range. A function of `raw` within one
## sample, so an incremental update equals a full build. `areas` are the sample rects that can
## hold a foot (the areas of the strokes with a fall): over the whole grid seams are looked for
## only there. Returns the array to keep: a copy of `raw` when `region` is the whole grid, else
## `out` with `region` rewritten.
##
## The test is symmetric (a pair of neighbours on a seam clears both), so each pair is tested once,
## from its first sample in row order against the four neighbours ahead of it, and only samples
## that hold a foot are tested at all. Over the whole grid the areas are scanned as the union of
## their rows' spans (overlapping areas once); over a dirty rect the rect grown by one sample is
## scanned (a pair across its edge is tested from its first sample) and only samples inside the
## rect are cleared: every sample of the rect is judged again, since a stroke that only borders
## the rect wrote no area this time and its seam must stay cleared. The reference of the native
## twin that WaterField runs when the library is loaded (WaterFieldNative.foot_seams), bit for bit.
static func foot_seams(
	raw: PackedFloat32Array,
	out: PackedFloat32Array,
	size: Vector2i,
	region: Rect2i,
	areas: Array[Rect2i]
) -> PackedFloat32Array:
	var whole := region == Rect2i(Vector2i.ZERO, size)
	var made := out
	if whole:
		made = raw.duplicate()
	else:
		for z in range(region.position.y, region.end.y):
			var row := z * size.x
			for i in range(row + region.position.x, row + region.end.x):
				made[i] = raw[i]
	if not foot_seams_cleared:
		return made
	var look: Array[Rect2i] = []
	if whole:
		for area in areas:
			look.append(area.intersection(region))
	else:
		look.append(region.grow(1).intersection(Rect2i(Vector2i.ZERO, size)))
	var none := NO_FOOT * 0.5
	var sx := size.x
	var x0 := region.position.x
	var x1 := region.end.x
	var z0 := region.position.y
	var z1 := region.end.y
	var top := size.y
	var bottom := 0
	for part in look:
		if part.has_area():
			top = mini(top, part.position.y)
			bottom = maxi(bottom, part.end.y)
	for z in range(top, bottom):
		var spans := _row_spans(look, z)
		var row := z * sx
		var below := z + 1 < size.y
		var here := z >= z0 and z < z1
		var next := z + 1 >= z0 and z + 1 < z1
		for k in range(0, spans.size(), 2):
			for x in range(spans[k], spans[k + 1]):
				var v := raw[row + x]
				if v >= none:
					continue
				# The four neighbours ahead: (x + 1, z), (x - 1, z + 1), (x, z + 1), (x + 1, z + 1).
				var mine := here and x >= x0 and x < x1
				if x + 1 < sx:
					var o := raw[row + x + 1]
					if o < none and o * v < 0.0 and absf(o - v) > FOOT_SEAM_JUMP:
						if mine:
							made[row + x] = NO_FOOT
						if here and x + 1 >= x0 and x + 1 < x1:
							made[row + x + 1] = NO_FOOT
				if not below:
					continue
				var under := row + sx + x
				for dx in range(-1, 2):
					if x + dx < 0 or x + dx >= sx:
						continue
					var o := raw[under + dx]
					if o < none and o * v < 0.0 and absf(o - v) > FOOT_SEAM_JUMP:
						if mine:
							made[row + x] = NO_FOOT
						if next and x + dx >= x0 and x + dx < x1:
							made[under + dx] = NO_FOOT
	return made


## The union of `rects`' spans on row `z` as [start, end) pairs in order, overlaps merged.
static func _row_spans(rects: Array[Rect2i], z: int) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var ends := PackedInt32Array()
	for r in rects:
		if r.has_area() and z >= r.position.y and z < r.end.y:
			var at := starts.bsearch(r.position.x)
			starts.insert(at, r.position.x)
			ends.insert(at, r.end.x)
	var spans := PackedInt32Array()
	for k in starts.size():
		if not spans.is_empty() and starts[k] <= spans[-1]:
			spans[-1] = maxi(spans[-1], ends[k])
		else:
			spans.append(starts[k])
			spans.append(ends[k])
	return spans


## The runs of set stations in `lost` as Vector3i(first, end, bridged): `end` is exclusive and
## `bridged` is 1 for a run of at most BRIDGE_M with a held station each side (a dip the water
## bridges), 0 for one that touches the stroke's end or is longer (a film).
static func runs(lost: PackedByteArray) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var longest := int(BRIDGE_M / STATION_STEP)
	var n := lost.size()
	var t := 0
	while t < n:
		if lost[t] == 0:
			t += 1
			continue
		var end := t
		while end < n and lost[end] != 0:
			end += 1
		out.append(Vector3i(t, end, 1 if t > 0 and end < n and end - t <= longest else 0))
		t = end
	return out


## `lost` with every bridged run (see runs()) cleared.
static func without_bridged(lost: PackedByteArray, found: Array[Vector3i]) -> PackedByteArray:
	var out := lost.duplicate()
	for run in found:
		if run.z != 0:
			for c in range(run.x, run.y):
				out[c] = 0
	return out


## The events of one stroke's runs: {"kind" (&"film_run" for an unbridged run, &"bridged_run"
## for a bridged one), "body" (the stroke's first body id), "pos" (XZ of the run's middle
## station), "length" (m)} each, in station order.
static func run_events(
	body: int, found: Array[Vector3i], centres: PackedVector2Array
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for run in found:
		var mid := mini((run.x + run.y) / 2, centres.size() - 1)
		out.append(
			{
				"kind": &"bridged_run" if run.z != 0 else &"film_run",
				"body": body,
				"pos": centres[mid],
				"length": (run.y - run.x) * STATION_STEP,
			}
		)
	return out


## The &"climb" events of the stroke whose reaches are `chain` (flow order): one per stretch of
## reaches whose stored level stands over the lowest level upstream of it by more than the
## conditioner's dead band (WaterConditioner.climbs): {"kind", "body" (the stroke's first body
## id), "pos" (where the first climbing reach begins), "reach" (its id), "rise_m"}. Water does
## not climb: a plan never stores one (WaterEdit.plan_river), so an event marks a map saved before
## that rule or a document that was never conditioned; a re-fit removes it. The field draws the
## stroke as stored (a wall of water at the foot of the rise) and says so here.
static func climb_events(chain: Array[WaterBody]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if chain.size() < 2:
		return out
	var levels := PackedFloat64Array()
	for body in chain:
		levels.append(body.level_m)
	# By path: the conditioner stays out of the start-up script graph (test_boot_graph).
	var conditioner: GDScript = load("res://utils/water_conditioner.gd")
	for found: Dictionary in conditioner.climbs(levels):
		var first: WaterBody = chain[int(found.from)]
		out.append(
			{
				"kind": &"climb",
				"body": chain[0].id,
				"pos": first.points[0],
				"reach": first.id,
				"rise_m": float(found.rise),
			}
		)
	return out
