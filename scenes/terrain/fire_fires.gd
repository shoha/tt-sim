class_name FireFires
extends RefCounted

## The persistent fire's placement: fewer, bigger fires (the reference fit's round 6, user
## 2026-10-17; docs/plans/2026-10-11-fire-features/production.md). FireField.plan_block hands
## every block here, so the rasters, the cluster sums, the lights and the budget follow the fires
## that show. The lattice, the mask read, the clump noise and the bands are FireField's
## (FireField.LatticeWindow); what stands on them:
##   - in the flames band a clump draws as one fire: a burning point (out of its clump's gap)
##     whose score (its clump value plus a little of the mask's heat) tops every other burning
##     point within CENTRE_REACH lattice points is a centre. It stands one fire, about as wide as
##     it is tall, at the centroid of the burning points round it pulled halfway back to its own
##     spot, sized by its clump value, its band and how much of its neighbourhood burns;
##   - a burning point with no centre within COVER_REACH (a ragged edge, a thin line) is
##     uncovered, and the uncovered point that tops its uncovered neighbours keeps one smaller
##     single flame (a straggler), so no burn goes bare and no carpet comes back;
##   - every other flames-band point stands nothing: its centre's fire covers it;
##   - a blaze point stands FireField's own flame (its big flames and their licks, at the
##     lattice's spacing) at SIM_BLAZE_SCALE of its height and a mass's width (SIM_BLAZE_SHARE),
##     so a blaze merges into one mass with many small tongues inside it and no blaze flame
##     stands as tall as the trees; the ember band keeps its sparks.
## Each entry's seed still carries a tongue layout for fire_field.gdshader (FireField.LAYOUT_ONE
## for a straggler, LAYOUT_TWO for a small fire, LAYOUT_THREE for a big one) until the flames draw
## from the fire book.
##
## Pure and deterministic, as FireField.plan_block: a point's decision reads only the lattice
## window (MARGIN points past the block), so neighbouring blocks agree on every centre, and a
## refresh re-plans every block within MARGIN points of a changed mask (FireField.blocks_to_replan).

## Lattice points (0.9 m) a centre must top, and how far a centre's fire covers.
const CENTRE_REACH := 3
const COVER_REACH := 3
## The window's margin: a straggler's uncovered neighbours need their centres' neighbourhoods.
const MARGIN := CENTRE_REACH + COVER_REACH + 1
## How much the mask's heat (0..1) adds to a point's clump value in the centre score, so a thin
## line's fire stands on its hottest part.
const HEAT_SCORE := 0.15
## A fire's height (metres) from a clump's edge to its middle, then scaled by its band (from the
## flames band's start to its end) and by its own draw; its width as a share of its height (a
## mass, about as wide as it is tall).
const FIRE_HEIGHT_M := Vector2(1.9, 2.9)
const BAND_SCALE := Vector2(0.9, 1.08)
const OWN_SCALE := Vector2(0.92, 1.08)
const FIRE_WIDTH := Vector2(0.9, 1.1)
## A straggler's scale of FireField.base_height, and its width share.
const SINGLE_SCALE := Vector2(0.8, 1.15)
const SINGLE_WIDTH := Vector2(0.45, 0.7)
## A blaze flame's height as a share of FireField's own flame, and its width share: wide enough
## that neighbours overlap into one blaze with tongues inside it.
const SIM_BLAZE_SCALE := 0.6
const SIM_BLAZE_SHARE := 1.05


## The fires of diff block `block` of `doc` (FireField.STRIDE floats each, shuffled), or empty
## without a fire mask.
static func plan_block(doc: MapDocument, block: Vector2i) -> PackedFloat32Array:
	var count := doc.sample_count()
	if doc.fire_mask.size() != count or doc.heights.size() != count:
		return PackedFloat32Array()
	var rect := MaskStroke.block_rect(doc, block)
	if not rect.has_area():
		return PackedFloat32Array()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var low := -half + Vector2(rect.position) * step
	var high := -half + Vector2(rect.end) * step
	var spacing := FireField.FLAME_SPACING_M
	# Lattice points whose unjittered spot lies in [low, high) belong to this block.
	var first := Vector2i(ceili(low.x / spacing), ceili(low.y / spacing))
	var end := Vector2i(ceili(high.x / spacing), ceili(high.y / spacing))
	var window := FireField.LatticeWindow.new(doc, first, end, MARGIN)
	var score := scores(window)
	var centre := centres(window, score)
	var covered := covers(window, score, centre)
	var entries: Array = []
	for iz in range(first.y, end.y):
		for ix in range(first.x, end.x):
			var i := window.index(ix, iz)
			var heat := window.heat[i]
			if heat < FireField.EMBER_MIN:
				continue
			var key := FireField._key(ix, iz)
			var entry := PackedFloat32Array()
			if heat < FireField.FLAME_MIN or heat >= FireField.BLAZE_MIN:
				entry = _own(doc.map_seed, key, window, i)
			elif centre[i]:
				entry = _fire(doc.map_seed, key, window, score, i)
			elif score[i] >= 0.0 and not covered[i] and tops_uncovered(window, score, covered, i):
				entry = _single(doc.map_seed, key, window, i)
			if entry.is_empty() or not _stands(doc, Vector2(entry[0], entry[2]), half, step):
				continue
			var at := (Vector2(entry[0], entry[2]) + half) / step
			entry[1] = ScatterGenerator.triangle_height(doc.heights, doc.samples_x(), doc.samples_z(), at)
			entries.append(entry)
	entries.sort_custom(func(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
		return fmod(a[FireField.SEED], 1.0) < fmod(b[FireField.SEED], 1.0))
	var out := PackedFloat32Array()
	for entry: PackedFloat32Array in entries:
		out.append_array(entry)
	return out


## The tallest fire this placement stands (metres): a centre's at the top of every range.
static func largest_height_m() -> float:
	return FIRE_HEIGHT_M.y * BAND_SCALE.y * OWN_SCALE.y


## The farthest (metres, along either axis) a fire stands off its block: a centre's fire stands
## at most half its neighbourhood's reach plus the lattice jitter off its lattice point (its
## centroid lies within CENTRE_REACH points, and is pulled halfway back to the centre's own
## jittered spot); every other flame stands on its own jittered spot.
static func spill_m() -> float:
	var spacing := FireField.FLAME_SPACING_M
	var jitter := FireField.JITTER * spacing
	return 0.5 * (CENTRE_REACH * spacing + jitter) + 0.5 * jitter


## The farthest (metres, along either axis) a fire's heat kernel reaches past its block: spill_m
## plus FireField.HEAT_REACH past the widest fire. FireField.HEAT_GROW covers it.
static func heat_reach_m() -> float:
	var width := largest_height_m() * FIRE_WIDTH.y
	return spill_m() + FireField.HEAT_REACH.x + FireField.HEAT_REACH.y * width


## Each window point's centre score: its clump value plus a little heat where it burns in the
## flames band out of its clump's gap, else -1 (a blaze point stands its own flame, so it
## neither centres nor covers nor suppresses a centre).
static func scores(window: FireField.LatticeWindow) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(window.heat.size())
	for i in window.heat.size():
		var heat := window.heat[i]
		var burns := false
		if heat >= FireField.FLAME_MIN and heat < FireField.BLAZE_MIN:
			burns = window.clump[i] >= _gap(heat)
		out[i] = window.clump[i] + HEAT_SCORE * heat / 255.0 if burns else -1.0
	return out


## Whether each window point is a centre (only points with their whole CENTRE_REACH inside the
## window are decided; the rest are false and never read for the block's own points).
static func centres(window: FireField.LatticeWindow, score: PackedFloat32Array) -> Array[bool]:
	var out: Array[bool] = []
	out.resize(score.size())
	out.fill(false)
	@warning_ignore("integer_division")
	var rows := score.size() / window.width
	var r := CENTRE_REACH
	for z in range(r, rows - r):
		for x in range(r, window.width - r):
			var i := z * window.width + x
			if score[i] < 0.0:
				continue
			var top := true
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if (dx == 0 and dz == 0) or dx * dx + dz * dz > r * r + 1:
						continue
					var j := i + dz * window.width + dx
					# Ties go to the lower lattice row, then column (the window's own order, the
					# same in every block's window).
					if score[j] > score[i] or (score[j] == score[i] and j < i):
						top = false
						break
				if not top:
					break
			out[i] = top
	return out


## Whether each window point has a centre within COVER_REACH (decided where the reach fits).
static func covers(
	window: FireField.LatticeWindow, score: PackedFloat32Array, centre: Array[bool]
) -> Array[bool]:
	var out: Array[bool] = []
	out.resize(score.size())
	out.fill(true)
	@warning_ignore("integer_division")
	var rows := score.size() / window.width
	var r := COVER_REACH
	for z in range(r, rows - r):
		for x in range(r, window.width - r):
			var i := z * window.width + x
			var near := false
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if dx * dx + dz * dz <= r * r + 1 and centre[i + dz * window.width + dx]:
						near = true
						break
				if near:
					break
			out[i] = near
	return out


## Whether uncovered burning point `i` tops its uncovered burning neighbours (eight ways): it
## stands a straggler.
static func tops_uncovered(
	window: FireField.LatticeWindow, score: PackedFloat32Array, covered: Array[bool], i: int
) -> bool:
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var j: int = i + dz * window.width + dx
			if score[j] < 0.0 or covered[j]:
				continue
			if score[j] > score[i] or (score[j] == score[i] and j < i):
				return false
	return true


## The clump value below which a flames-band point at mask value `heat` drops (its clump's gap).
static func _gap(heat: float) -> float:
	return lerpf(FireField.FLAME_GAP.x, FireField.FLAME_GAP.y, _strength(heat))


## Where mask value `heat` lies in the flames band (0 at its start, 1 at the blaze).
static func _strength(heat: float) -> float:
	return (heat - FireField.FLAME_MIN) / float(FireField.BLAZE_MIN - FireField.FLAME_MIN)


## Point `i`'s own flame (FireField's: an ember point's spark, a blaze point's flame at
## SIM_BLAZE_SCALE and SIM_BLAZE_SHARE), at its own spot, or empty.
static func _own(
	map_seed: int, key: int, window: FireField.LatticeWindow, i: int
) -> PackedFloat32Array:
	var entry := FireField._flame(map_seed, key, window.heat[i], window, i)
	if entry.is_empty():
		return entry
	entry[0] = window.px[i]
	entry[2] = window.pz[i]
	if window.heat[i] >= FireField.BLAZE_MIN:
		entry[FireField.HEIGHT] *= SIM_BLAZE_SCALE
		entry[FireField.WIDTH] = entry[FireField.HEIGHT] * SIM_BLAZE_SHARE
	return entry


## The fire of centre `i`: at the centroid of the burning points round it (score-weighted),
## pulled halfway back to its own spot so a lopsided clump's fire still stands on fire; its size
## from its clump value, its band and the share of its neighbourhood that burns.
static func _fire(
	map_seed: int, key: int, window: FireField.LatticeWindow, score: PackedFloat32Array, i: int
) -> PackedFloat32Array:
	var r := CENTRE_REACH
	var sum := Vector2.ZERO
	var weight := 0.0
	var burning := 0
	var total := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if dx * dx + dz * dz > r * r + 1:
				continue
			total += 1
			var j := i + dz * window.width + dx
			if score[j] < 0.0:
				continue
			burning += 1
			sum += Vector2(window.px[j], window.pz[j]) * score[j]
			weight += score[j]
	var cover := float(burning) / float(total)
	var own_spot := Vector2(window.px[i], window.pz[i])
	var at := sum / weight if weight > 0.0 else own_spot
	at = at.lerp(own_spot, 0.5)
	var seed := MaskBrush.sample_noise(map_seed + 2, key) * 0.999
	var own := MaskBrush.sample_noise(map_seed + 5, key)
	var shape := MaskBrush.sample_noise(map_seed + 4, key)
	var heat := window.heat[i]
	var gap := _gap(heat)
	var place := clampf((window.clump[i] - gap) / (1.0 - gap), 0.0, 1.0)
	var size := 0.55 * place + 0.45 * cover
	var height := lerpf(FIRE_HEIGHT_M.x, FIRE_HEIGHT_M.y, size)
	height *= lerpf(BAND_SCALE.x, BAND_SCALE.y, _strength(heat))
	height *= lerpf(OWN_SCALE.x, OWN_SCALE.y, own)
	var width := height * lerpf(FIRE_WIDTH.x, FIRE_WIDTH.y, shape)
	var layout := FireField.LAYOUT_THREE if size > 0.55 else FireField.LAYOUT_TWO
	var t := heat / 255.0
	return PackedFloat32Array([at.x, 0, at.y, t, layout + seed, height, width, FireField.FLAME])


## A straggler's single flame at point `i`.
static func _single(
	map_seed: int, key: int, window: FireField.LatticeWindow, i: int
) -> PackedFloat32Array:
	var seed := MaskBrush.sample_noise(map_seed + 2, key) * 0.999
	var own := MaskBrush.sample_noise(map_seed + 5, key)
	var t := window.heat[i] / 255.0
	var height := FireField.base_height(minf(t, (FireField.BLAZE_MIN - 1) / 255.0))
	height *= lerpf(SINGLE_SCALE.x, SINGLE_SCALE.y, own)
	var share := lerpf(SINGLE_WIDTH.x, SINGLE_WIDTH.y, MaskBrush.sample_noise(map_seed + 4, key))
	return PackedFloat32Array(
		[
			window.px[i],
			0,
			window.pz[i],
			t,
			FireField.LAYOUT_ONE + seed,
			height,
			height * share,
			FireField.FLAME
		]
	)


## Whether a fire may stand at document point `p` (metres): on the map, not on the wet line, not
## steeper than the cliff rule.
static func _stands(doc: MapDocument, p: Vector2, half: Vector2, step: Vector2) -> bool:
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var at := (p + half) / step
	if at.x < 0.0 or at.y < 0.0 or at.x > columns - 1 or at.y > rows - 1:
		return false
	var nearest := doc.sample_index(roundi(at.x), roundi(at.y))
	if doc.water_dressing.size() == doc.sample_count() * 4:
		if doc.water_dressing[nearest * 4 + 3] >= FireField.WET_LINE_MIN:
			return false
	var normal := ScatterGenerator.triangle_normal(doc.heights, columns, rows, at, step)
	return normal.y >= FireField.STEEP_NORMAL_Y
