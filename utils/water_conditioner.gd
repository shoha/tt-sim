class_name WaterConditioner
extends RefCounted

## The level conditioner of the water-conditioning spike (card painter-water-condition-spike):
## pure static functions that turn a drawn level profile into a legal one, so that every renderer
## and the WaterField see a profile that never climbs, has no tiny kinks and steps only by
## whole falls. WaterEdit.plan_river calls condition_ranges() at plan time, once, on the
## authoring peer (the result is stored in the document's WaterBody list; peers never re-run it),
## and WaterEdit.refit_document() the tree solver over a stored document. The course half is
## WaterCourseFit, the ports half WaterPorts, the findings of the spike docs/systems/water_field.md
## "Conditioning" and the research docs/research/2026-11-20-water-research/03 and 04 in the
## suite root.
##
## Water is only ever LOWERED, never raised, so a conditioned level never stands over its banks
## (the bed is carved to follow it). The profile fit (fit_levels), over segments (stations or
## whole reaches) each with a target level and a cap (its banks: ground minus freeboard):
##  1. each level is the nearest lattice value at or under its target and its cap (the lattice is
##     QUANTUM_M, floor, so a cap is never broken and equal levels compare exactly equal);
##  2. the running minimum downstream ("water cannot climb out of a basin it left"): a hump in
##     the profile is cut down to the water upstream of it;
##  3. the dead band, swept from the outlet upstream: a level within the dead band above the
##     (final) level below it drops onto it, so every remaining step is at least the dead band
##     and nothing moves by the dead band or more. Pool adjacent violators was tried first and
##     rejected: pooling on a steady slope cascades, every step is under the band, and the whole
##     stroke collapses into one trench (measured, handoff);
##  4. a block shorter than the minimum reach length drops onto (or takes) the neighbour it differs
##     from least, unless that boundary is a pinned cut (a fall's lip) or a fall-sized step, then
##     the dead band is swept again.
## Steps of FALL_DROP_M or more are never touched: lowering only ever shrinks the step below a
## level and grows the one above it. fit_levels() of its own output (as targets, same caps) is the
## identity.
##
## The tree solver (solve_tree) is the same rules over a river and pond tree: each node is at
## most its upstream neighbours (the envelope, taken upstream to downstream), then the dead band
## swept top down; a pond's level is pinned.

## The level lattice (metres). Falls need 15 of it (WaterFalls.FALL_MIN_DROP_M is 0.75).
const QUANTUM_M := 0.05
## Steps smaller than this drop onto the level below. Half the greedy reach split's span
## (WaterGeometry.REACH_DROP_M): the greedy steps of a steady slope (up to 0.5 m) must survive,
## the kinks under 0.25 m must not (chosen by the sweep in the handoff).
const DEAD_BAND_M := 0.25
const FALL_DROP_M := WaterFalls.FALL_MIN_DROP_M
## A reach shorter than this merges away (a step needs room for its pool tail).
const MIN_REACH_M := 2.0
## A move past this is reported as an event rather than hidden (the author must feel the gesture).
const NUDGE_CAP_M := 0.5
## The deepest cut into the drawn ground the conditioned levels may ask of the carve before the
## plan is kept as drawn and flagged (condition_ranges).
const CUT_LIMIT_M := 1.5
const _EPS := 1.0e-9


## Fits the segments' levels (see the header). `lengths`, `targets` and `caps` are one entry per
## segment in drawn order, upstream first (a cap of INF is none); `cuts` has a nonzero byte at i
## where the boundary between segments i and i + 1 is pinned (never dropped across by the dead
## band or minimum length); `opts` overrides "quantum", "dead_band", "fall_drop", "min_len".
## Returns {"levels" (one per segment, metres), "blocks" (Array[Vector2i] of first and last
## segment of each pool), "block_levels", "moved" (the largest |level - target|), "lowered" (the
## most any level is under its target), "stuck" (short blocks that could not merge)}.
static func fit_levels(
	lengths: PackedFloat64Array,
	targets: PackedFloat64Array,
	caps: PackedFloat64Array,
	cuts: PackedByteArray = PackedByteArray(),
	opts: Dictionary = {}
) -> Dictionary:
	var out := {
		"levels": PackedFloat64Array(),
		"blocks": [] as Array[Vector2i],
		"block_levels": PackedFloat64Array(),
		"moved": 0.0,
		"lowered": 0.0,
		"stuck": 0,
	}
	var n := lengths.size()
	if n == 0 or targets.size() != n or caps.size() != n:
		return out
	var q: float = opts.get("quantum", QUANTUM_M)
	var dead: float = opts.get("dead_band", DEAD_BAND_M) - _EPS
	var fall: float = opts.get("fall_drop", FALL_DROP_M) - _EPS
	var min_len: float = opts.get("min_len", MIN_REACH_M)
	var level := PackedFloat64Array()
	level.resize(n)
	var low := INF
	for i in n:
		low = minf(low, minf(_lattice(targets[i], q), _lattice(caps[i], q)))
		level[i] = low
	# A last segment that ends in other water takes that water's level when within the dead band
	# of it (a join), and is never under it (water does not climb into it).
	var pin: float = opts.get("pin_last", NAN)
	if not is_nan(pin) and n > 1 and pin <= level[n - 2] + _EPS and level[n - 1] - pin < dead:
		level[n - 1] = pin
	_sweep(level, cuts, dead, fall)
	var stuck := _merge_short(level, lengths, cuts, dead, fall, min_len)
	var spans: Array[Vector2i] = []
	var block_levels := PackedFloat64Array()
	var first := 0
	for i in n:
		out.moved = maxf(out.moved, absf(level[i] - targets[i]))
		out.lowered = maxf(out.lowered, targets[i] - level[i])
		var ends := i == n - 1 or level[i + 1] != level[i] or _cut_after(cuts, i)
		if ends:
			spans.append(Vector2i(first, i))
			block_levels.append(level[i])
			first = i + 1
	out.blocks = spans
	out.block_levels = block_levels
	out.levels = level
	out.stuck = stuck
	return out


## fit_levels() over a stroke's stations (`arc` and `ground` per station): the target and the cap
## of a station are its ground minus WaterGeometry.FREEBOARD_M unless `targets` (levels the
## author set, same size) says otherwise. {"levels" per station, ...fit_levels()}.
static func fit_profile(
	arc: PackedFloat32Array,
	ground: PackedFloat32Array,
	targets: PackedFloat32Array = PackedFloat32Array(),
	opts: Dictionary = {}
) -> Dictionary:
	var n := arc.size()
	var lengths := PackedFloat64Array()
	var want := PackedFloat64Array()
	var caps := PackedFloat64Array()
	for i in n:
		var before := arc[i - 1] if i > 0 else arc[i]
		var after := arc[i + 1] if i < n - 1 else arc[i]
		lengths.append((after - before) * 0.5)
		var cap := ground[i] - WaterGeometry.FREEBOARD_M
		caps.append(cap)
		want.append(cap if targets.is_empty() else targets[i])
	return fit_levels(lengths, want, caps, PackedByteArray(), opts)


## The planned reach `ranges` of a river course (WaterGeometry.reach_ranges: inclusive index
## ranges over `course`, consecutive ones sharing a point) conditioned: levels fitted over the
## reaches (target and cap: WaterGeometry.reach_level of its `ground`; `forced`, the fall lips,
## are cuts), and reaches the fit pooled joined into one range. `free` (a fall's face, nonzero per
## point) is left out of the cut measure. {"ranges" Array[Vector2i], "levels" PackedFloat64Array
## per range, "max_cut" and "cut_at" (the deepest cut into the drawn ground off a fall's face),
## "blocked" (that cut passes CUT_LIMIT_M: the plan's own ranges and levels are returned),
## ...fit_levels()}.
static func condition_ranges(
	course: PackedVector2Array,
	ground: PackedFloat32Array,
	ranges: Array[Vector2i],
	forced: PackedInt32Array = PackedInt32Array(),
	opts: Dictionary = {},
	free: PackedByteArray = PackedByteArray()
) -> Dictionary:
	var lengths := PackedFloat64Array()
	var want := PackedFloat64Array()
	var cuts := PackedByteArray()
	var rises := 0
	var rise_m := 0.0
	var rise_at := -1
	for k in ranges.size():
		var reach := ranges[k]
		var length := 0.0
		for i in range(reach.x, reach.y):
			length += course[i].distance_to(course[i + 1])
		lengths.append(length)
		want.append(WaterGeometry.reach_level(ground, reach))
		cuts.append(1 if forced.has(reach.y) else 0)
		# A drawn level that climbs downstream: the plan's own reaches, before any fit.
		if k > 0 and want[k] > want[k - 1] + 0.001:
			rises += 1
			rise_m += want[k] - want[k - 1]
			rise_at = reach.x if rise_at < 0 else rise_at
	var fit := fit_levels(lengths, want, want, cuts, opts)
	fit["rises"] = rises
	fit["rise_m"] = rise_m
	fit["rise_at"] = maxi(rise_at, 0)
	fit["reaches_before"] = ranges.size()
	var merged: Array[Vector2i] = []
	for block: Vector2i in fit.blocks:
		merged.append(Vector2i(ranges[block.x].x, ranges[block.y].y))
	fit["ranges"] = merged
	fit["levels"] = fit.block_levels
	# How deep the conditioned levels ask the carve to cut into the drawn ground: a stroke over a
	# ridge is cut through it (the water never climbs), which a tool should say out loud.
	var cut := 0.0
	var cut_at := 0
	for k in fit.blocks.size():
		for i in range(merged[k].x, merged[k].y + 1):
			var on_face := (
				(i < free.size() and free[i] != 0) or (i > 0 and i - 1 < free.size() and free[i - 1] != 0)
			)
			if not on_face and ground[i] - fit.block_levels[k] > cut:
				cut = ground[i] - fit.block_levels[k]
				cut_at = i
	fit["max_cut"] = cut
	fit["cut_at"] = cut_at
	fit["blocked"] = false
	if cut > float(opts.get("cut_limit", CUT_LIMIT_M)):
		# A cut that deep is a gorge the author did not ask for (a stroke over a ridge, a head
		# standing in a pond's bank): keep the plan as drawn and flag it instead.
		fit["blocked"] = true
		fit["ranges"] = ranges
		fit["levels"] = want
	return fit


## The climbs of a stroke's reach `levels` (flow order): every stretch whose levels stand over the
## lowest level upstream of it by more than `band`, as {"from" (the first reach over it), "to"
## (the last), "low" (the reach it rose from), "rise" (metres, the highest of the stretch over
## that low)}. Empty for water that only descends: the rule every stored stroke must keep
## (docs/systems/water_field.md "Water does not climb").
static func climbs(levels: PackedFloat64Array, band: float = DEAD_BAND_M) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var low := INF
	var low_at := -1
	var open := {}
	for k in levels.size():
		if levels[k] - low > band:
			if open.is_empty():
				open = {"from": k, "to": k, "low": low_at, "rise": 0.0}
				out.append(open)
			open.to = k
			open.rise = maxf(float(open.rise), levels[k] - low)
			continue
		open = {}
		if levels[k] < low:
			low = levels[k]
			low_at = k
	return out


## The longest part of a stroke that does not climb: the first and last reach (inclusive) of the
## run of consecutive reaches, none over the lowest level before it in the run by more than `band`,
## with the greatest summed `lengths`. A run begins at the reach that broke the one before it, so
## the crest of a rise heads the run that descends from it. Vector2i(0, -1) for no reaches.
static func longest_descent(
	levels: PackedFloat64Array, lengths: PackedFloat64Array, band: float = DEAD_BAND_M
) -> Vector2i:
	var best := Vector2i(0, -1)
	var best_len := -1.0
	var first := 0
	var low := INF
	var length := 0.0
	for k in levels.size() + 1:
		if k == levels.size() or levels[k] - low > band:
			if k > first and length > best_len:
				best = Vector2i(first, k - 1)
				best_len = length
			first = k
			low = INF
			length = 0.0
		if k < levels.size():
			low = minf(low, levels[k])
			length += lengths[k]
	return best


## A stroke's reach `levels` (flow order) as the parts between its troughs and crests, in order:
## Vector3i(first reach, last reach, direction), direction -1 for a part that runs downhill as
## drawn and 1 for one that climbs (to be turned round: it runs down from its crest). A move
## against a part's direction within `band` does not end it. A crest heads the part that descends
## from it and a trough ends the part that descends into it, so a climbing part holds only the
## reaches strictly between the two (none for a single step up), except at the stroke's ends,
## where it holds the first or the last reach too. Every reach is in exactly one part.
static func monotone_parts(
	levels: PackedFloat64Array, band: float = DEAD_BAND_M
) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var n := levels.size()
	if n == 0:
		return out
	var first := 0
	var down := true
	# The lowest level of a descending part so far; the index of the highest of a climbing one.
	var low := levels[0]
	var top := 0
	for k in range(1, n):
		if down:
			if levels[k] - low > band:
				# A stroke that begins flat and then climbs: the flat start is the climb's foot.
				if first > 0 or levels[0] - low > band:
					out.append(Vector3i(first, k - 1, -1))
					first = k
				top = k
				down = false
			else:
				low = minf(low, levels[k])
		elif levels[k] > levels[top]:
			top = k
		elif levels[top] - levels[k] > band:
			if top > first:
				out.append(Vector3i(first, top - 1, 1))
			first = top
			low = levels[k]
			down = true
	# A stroke that ends on a rise: the climb is a part up to the end, its crest included.
	out.append(Vector3i(first, n - 1, -1 if down else 1))
	return out


## The conditioned levels of a tree of nodes (rivers' reaches and ponds). `parent[i]` is node i's
## downstream node (-1 for an outlet); a node must be at most each upstream neighbour (water does
## not climb: an outlet is lowered to the lowest water draining into it, and a node over a pond
## it drains into is raised to the pond's level, reported), then a node within the dead band
## above its parent drops onto it, top down. `pinned` (nonzero) nodes never move (a pond) and keep
## their own value bit for bit, `caps` bound a node from above (INF none). Returns {"levels",
## "changed" (nodes whose level moved), "moved" (largest move), "over_cap" (nodes moved by more
## than NUDGE_CAP_M), "raised" (nodes raised to a pond), "conflicts" (Array of [child, parent]
## pinned pairs the order forbids: a pond below the pond it feeds)}.
static func solve_tree(
	levels: PackedFloat64Array,
	parent: PackedInt32Array,
	pinned: PackedByteArray,
	caps: PackedFloat64Array = PackedFloat64Array(),
	opts: Dictionary = {}
) -> Dictionary:
	var n := levels.size()
	var q: float = opts.get("quantum", QUANTUM_M)
	var dead: float = opts.get("dead_band", DEAD_BAND_M) - _EPS
	var held := func(i: int) -> bool: return i < pinned.size() and pinned[i] != 0
	var fixed := levels.duplicate()
	for i in n:
		if not held.call(i):
			var cap := caps[i] if i < caps.size() else INF
			fixed[i] = minf(_lattice(levels[i], q), _lattice(cap, q))
	var order := _top_down(parent)
	var conflicts: Array = []
	var raised := 0
	# Upstream to downstream: an outlet is at most everything above it.
	for step in range(order.size() - 1, -1, -1):
		var i: int = order[step]
		var p := parent[i]
		if p < 0 or fixed[i] >= fixed[p] - _EPS:
			continue
		if not held.call(p):
			fixed[p] = fixed[i]
		elif not held.call(i):
			fixed[i] = fixed[p]
			raised += 1
		else:
			conflicts.append([i, p])
	# Top down: the dead band.
	for i in order:
		var p := parent[i]
		if p >= 0 and not held.call(i):
			var gap := fixed[i] - fixed[p]
			if gap > _EPS and gap < dead:
				fixed[i] = fixed[p]
	var changed := 0
	var moved := 0.0
	var over := 0
	for i in n:
		var d := absf(fixed[i] - levels[i])
		changed += 1 if d > _EPS else 0
		moved = maxf(moved, d)
		over += 1 if d > NUDGE_CAP_M else 0
	return {
		"levels": fixed,
		"changed": changed,
		"moved": moved,
		"over_cap": over,
		"raised": raised,
		"conflicts": conflicts,
	}


## `x` floored to the lattice (INF stays INF); the epsilon keeps a value already on it.
static func _lattice(x: float, q: float) -> float:
	return x if is_inf(x) else floorf(x / q + 1e-6) * q


static func _cut_after(cuts: PackedByteArray, i: int) -> bool:
	return i >= 0 and i < cuts.size() and cuts[i] != 0


## The dead band swept from the last segment upstream: a level within `dead` above the (final)
## level below it drops onto it, unless a cut sits between.
static func _sweep(
	level: PackedFloat64Array, cuts: PackedByteArray, dead: float, fall: float
) -> void:
	for i in range(level.size() - 2, -1, -1):
		var gap := level[i] - level[i + 1]
		if gap > _EPS and gap < dead and not _cut_after(cuts, i):
			# Never make a fall (a step of `fall` or more) of the step above out of a smaller one.
			var above := level[i - 1] - level[i] if i > 0 else 0.0
			if i > 0 and above < fall and above + gap >= fall:
				continue
			level[i] = level[i + 1]


## Merges every block shorter than `min_len` into the neighbour it differs from least (the upper
## of the two drops onto the lower), never across a cut or a step of `fall` or more, then sweeps
## the dead band again. Returns how many short blocks could not merge.
static func _merge_short(
	level: PackedFloat64Array,
	lengths: PackedFloat64Array,
	cuts: PackedByteArray,
	dead: float,
	fall: float,
	min_len: float
) -> int:
	var n := level.size()
	var stuck := {}
	while min_len > 0.0:
		# Blocks as runs of equal level not split by a cut.
		var spans: Array[Vector2i] = []
		var first := 0
		for i in n:
			if i == n - 1 or level[i + 1] != level[i] or _cut_after(cuts, i):
				spans.append(Vector2i(first, i))
				first = i + 1
		var pick := -1
		var shortest := INF
		for j in spans.size():
			var length := 0.0
			for i in range(spans[j].x, spans[j].y + 1):
				length += lengths[i]
			if spans.size() > 1 and length < min_len and length < shortest and not stuck.has(spans[j].x):
				pick = j
				shortest = length
		if pick < 0:
			break
		var best := -1
		var best_step := INF
		for nb in [pick + 1, pick - 1]:
			if nb < 0 or nb >= spans.size():
				continue
			var step := absf(level[spans[pick].x] - level[spans[nb].x])
			if _cut_after(cuts, spans[mini(pick, nb)].y) or step >= fall:
				continue
			# Never make a fall of the step above the dropped block out of a smaller one.
			var top := spans[mini(pick, nb)].x
			if top > 0:
				var above := level[top - 1] - level[top]
				if above < fall and above + step >= fall:
					continue
			if step < best_step:
				best = nb
				best_step = step
		if best < 0:
			stuck[spans[pick].x] = true
			continue
		var upper := spans[mini(pick, best)]
		var lower := spans[maxi(pick, best)]
		for i in range(upper.x, upper.y + 1):
			level[i] = level[lower.x]
		_sweep(level, cuts, dead, fall)
		# A merge changes the steps around it: blocks that could not merge may now.
		stuck.clear()
	return stuck.size()


## The nodes ordered so that every node comes after its parent (outlets first).
static func _top_down(parent: PackedInt32Array) -> PackedInt32Array:
	var n := parent.size()
	var depth := PackedInt32Array()
	depth.resize(n)
	for i in n:
		var at := i
		var d := 0
		while parent[at] >= 0 and d <= n:
			at = parent[at]
			d += 1
		depth[i] = d
	var order := PackedInt32Array()
	var keyed := []
	for i in n:
		keyed.append(Vector2i(depth[i], i))
	keyed.sort()
	for key: Vector2i in keyed:
		order.append(key.y)
	return order
