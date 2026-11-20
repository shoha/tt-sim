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


## The stroke's level, white-water `energy` and brink-and-face `core` white every TABLE_STEP
## along its arc: {"level", "energy", "core"} (PackedFloat32Array each). The level is the
## profile's bank level (flat over a reach, eased over a riffle, stepping down a fall's face with
## the carve); the energy is the fall's foot foam and the riffle white carried downstream, the
## core the brink and the face.
static func table(profile: RiverProfile, chain: Array[WaterBody]) -> Dictionary:
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
