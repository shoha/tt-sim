class_name LandformPlacement
extends RefCounted

## Where a big map's extras stand and how its open ground is painted (LandformGrowth, split
## out of it on 2026-10-09 along that seam).
##
## The search (find_spot) draws seeded candidate spots for an extra and refuses any whose
## disc comes near what it must keep clear of (the stage, a crossing, the recipe's own
## features, the other extras), lies within its gap of water or stands on ground that ranges
## too far to stand on; it scores the rest so the feature belongs to the place rather than
## filling a corner: about midway from the stage to the map's edge (TARGET_SHARE), well inside
## the edge, near the recipe's features and water by its tie, on high or low ground by its
## lean, and toward the far ends of a long map.
##
## The paint opens ground in the biome's meadow surface (meadow_surface: its grass accent,
## else its moss): paint_open over one feature (a meadow, a knoll's crown, a tarn's shore, a
## recipe's "open" discs and bands), and paint_sparse over the thin parts of a big map's
## starting cover. The 2026-10-09 looks found that from the whole-map view the trees hide a
## big map's relief and what reads is water and open ground, and that the forest floor between
## thin cover (a valley's camera-side slope, the uplands between groves) read as brown
## dirt. Sunlit ground under thin cover is grass, so paint_sparse greens it in a few bold,
## soft-edged patches that follow the cover the seed drew, which also gives every seed's map
## its own glades.

## The search: candidate spots drawn per feature; how far the ground under a tarn or a knoll
## may range (metres, over three quarters of its radius); the preferred distance from the
## stage (a share of the long half extent); the band inside the map edge (a share of the half
## extent past the feature's radius) where a spot loses score, and by how much; how near the
## recipe's features a spot counts as tied to them (a share of the half extent); the weight of
## a long map's far ends; the relief (metres at 150 ft) a lean is measured in; the points on
## each ring a pond is looked for on.
const CANDIDATES := 48
const FLAT_RANGE_M := 0.6
const TARGET_SHARE := 0.55
const EDGE_SHARE := 0.25
const EDGE_WEIGHT := 1.5
const TIE_REACH_SHARE := 0.4
const LONG_LEAN := 0.6
const LEAN_RELIEF_M := 3.0
const RING_POINTS := 16
## Open ground's paint: full weight inside OPEN_CORE_SHARE of the radius, its outline warped
## by OPEN_WARP of the radius.
const OPEN_CORE_SHARE := 0.45
const OPEN_WARP := 0.25
## The thin cover's paint (paint_sparse): a sample is thin from its cover density SPARSE_NONE
## down to wholly thin at SPARSE_FULL; SPARSE_NOISE of a noise SPARSE_FEATURE_M across (at
## 150 ft, scaled by StartingLandform.size_scale) is added to that, and the sum turns to the
## meadow over SPARSE_SOFT either side of SPARSE_THRESHOLD at full room (the threshold rises
## past anything the sum reaches as the room falls to 0). Nothing in the cover's own feather
## at the map edge (NewMap.edge_feather: thin there, but not open ground), easing in over
## SPARSE_EDGE_M inside it. Judged on the 2026-10-09 whole-map captures.
const SPARSE_STREAM := 0x5C3E9
const SPARSE_FULL := 0.18
const SPARSE_NONE := 0.45
const SPARSE_NOISE := 0.45
const SPARSE_FEATURE_M := 14.0
const SPARSE_THRESHOLD := 0.6
const SPARSE_SOFT := 0.12
const SPARSE_EDGE_M := 5.0


## A seeded spot for a feature (see the header) described by `want` (LandformGrowth.SEARCH's
## fields and its "radius"): CANDIDATES points drawn from `rng` at least its inset inside the
## map edge, each refused when its disc comes within an `avoid` feature (a disc {"at",
## "radius"} or a band {"line", "radius"}), when water lies within its water gap of its
## outline or the ground under it ranges more than FLAT_RANGE_M (a negative gap skips both);
## the rest scored by distance from `stage` against TARGET_SHARE, the edge band, the nearness
## of the `ties` features (same forms), the lean and a long map's far ends. Vector2.INF when
## none fits. Always draws 2 * CANDIDATES numbers.
static func find_spot(
	doc: MapDocument,
	rng: RandomNumberGenerator,
	want: Dictionary,
	avoid: Array,
	ties: Array,
	stage: Vector2
) -> Vector2:
	var radius: float = want.radius
	var water_gap: float = want.water_gap
	var extent := doc.extent_m() * 0.5
	var bound := extent - Vector2.ONE * radius * float(want.inset)
	var half := StartingLandform.half_extent(doc)
	var reach := LandformGrowth.long_half(doc)
	var along := LandformGrowth.long_dir(doc)
	var long_weight := LONG_LEAN * LandformGrowth.long_room(doc)
	var relief := LEAN_RELIEF_M * StartingLandform.size_scale(doc)
	var best := Vector2.INF
	var best_score := -INF
	for n in CANDIDATES:
		var p := Vector2(
			rng.randf_range(-1.0, 1.0) * maxf(bound.x, 0.0),
			rng.randf_range(-1.0, 1.0) * maxf(bound.y, 0.0)
		)
		if not clear_of(p, radius, avoid):
			continue
		if water_gap >= 0.0:
			if not _dry_around(doc, p, radius + water_gap):
				continue
			if _ground_range(doc, p, radius * 0.75) > FLAT_RANGE_M:
				continue
		var from_stage := p.distance_to(stage) / reach
		var score := 1.0 - absf(from_stage - TARGET_SHARE) / TARGET_SHARE
		var edge := minf(extent.x - absf(p.x), extent.y - absf(p.y)) - radius
		score -= EDGE_WEIGHT * clampf(1.0 - edge / (EDGE_SHARE * half), 0.0, 1.0)
		if not ties.is_empty():
			var gap := INF
			for feature: Dictionary in ties:
				gap = minf(gap, gap_to(p, feature) - radius)
			score += float(want.tie) * clampf(1.0 - gap / (TIE_REACH_SHARE * half), 0.0, 1.0)
		score += long_weight * absf(p.dot(along)) / reach
		score += float(want.lean) * WaterGeometry.ground_at(doc, p) / maxf(relief, 1e-3)
		if score > best_score:
			best_score = score
			best = p
	return best


## The surface a big map's open ground is painted with in `biome_id`: none when the biome's
## ground is already a grass, else its first grass accent, else a moss accent, else none (a
## sand or rock biome keeps its own ground).
static func meadow_surface(biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	if biome_id == "":
		return ""
	var biome := PaletteLibrary.biome(biome_id, root)
	if String(biome.get("ground_surface", "")).begins_with("grass"):
		return ""
	var accents: Array = biome.get("ground_accents", [])
	for prefix in ["grass", "moss"]:
		for accent: Dictionary in accents:
			if String(accent.get("surface", "")).begins_with(prefix):
				return String(accent.surface)
	return ""


## Paints `surface` over `feature` (a disc {"at", "radius"} or a band {"line", "radius"}):
## full weight from OPEN_CORE_SHARE of the radius inward, easing to none at its outline, which
## the noise (from `rng`, drawn whether or not anything is painted) pushes in and out by
## OPEN_WARP of the radius. Only ever raises a sample's weight; nothing when `surface` is ""
## or the document has no slot for it.
static func paint_open(
	doc: MapDocument, surface: String, feature: Dictionary, rng: RandomNumberGenerator
) -> void:
	var radius := float(feature.radius)
	var noise := StartingLandform.warp_noise(rng, maxf(radius, 1.0))
	if surface == "" or radius <= 0.0:
		return
	var slot := doc.ensure_surface(surface)
	if slot < 0:
		return
	var reach := radius * (1.0 + OPEN_WARP)
	var points: PackedVector2Array = (
		PackedVector2Array([feature.at]) if feature.has("at") else feature.line
	)
	var box := Rect2(points[0], Vector2.ZERO)
	for p in points:
		box = box.expand(p)
	box = box.grow(reach)
	var lo := doc.world_to_sample(box.position).floor()
	var hi := doc.world_to_sample(box.end).ceil()
	var count := doc.sample_count()
	for z in range(maxi(int(lo.y), 0), mini(int(hi.y) + 1, doc.samples_z())):
		for x in range(maxi(int(lo.x), 0), mini(int(hi.x) + 1, doc.samples_x())):
			var p := doc.sample_to_world(Vector2(x, z))
			var inside := -gap_to(p, feature) + noise.get_noise_2d(p.x, p.y) * OPEN_WARP * radius
			if inside <= 0.0:
				continue
			var t := smoothstep(0.0, radius * (1.0 - OPEN_CORE_SHARE), inside)
			_raise(doc, doc.sample_index(x, z), slot, roundi(255.0 * t), count)


## Paints the meadow surface of `biome_id` over the thin parts of `doc`'s starting cover (its
## painted biome density, NewMap.paint_starting_cover; see the header and the SPARSE
## constants), in proportion to the map's room (LandformGrowth.room): nothing on a map without
## room, so a square map up to 250 ft is left as it was. Only ever raises a sample's weight.
static func paint_sparse(
	doc: MapDocument, biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT
) -> void:
	var r := LandformGrowth.room(doc)
	var surface := meadow_surface(biome_id, root)
	var count := doc.sample_count()
	if r <= 0.0 or surface == "" or doc.biome_density.size() != count:
		return
	var slot := doc.ensure_surface(surface)
	if slot < 0:
		return
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = (doc.map_seed ^ SPARSE_STREAM) & 0x7fffffff
	noise.frequency = 1.0 / (SPARSE_FEATURE_M * StartingLandform.size_scale(doc))
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	var threshold := lerpf(1.0 + SPARSE_NOISE + SPARSE_SOFT, SPARSE_THRESHOLD, r)
	var half := doc.extent_m() * 0.5
	var band := NewMap.edge_feather_m(half) * (1.0 + NewMap.EDGE_FEATHER_WOBBLE)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			var p := doc.sample_to_world(Vector2(x, z))
			var edge := minf(half.x - absf(p.x), half.y - absf(p.y))
			var thin := 1.0 - smoothstep(SPARSE_FULL, SPARSE_NONE, doc.biome_density[i] / 255.0)
			thin *= smoothstep(band, band + SPARSE_EDGE_M, edge)
			var score := thin + SPARSE_NOISE * noise.get_noise_2d(p.x, p.y)
			var t := smoothstep(threshold - SPARSE_SOFT, threshold + SPARSE_SOFT, score)
			_raise(doc, i, slot, roundi(255.0 * t), count)


## The distance from `p` to the edge of `feature` (a disc {"at", "radius"} or a band
## {"line", "radius"} about a polyline); negative inside it.
static func gap_to(p: Vector2, feature: Dictionary) -> float:
	var centre := (
		p.distance_to(feature.at)
		if feature.has("at")
		else StartingLandform.nearest_on(feature.line, p).x
	)
	return centre - float(feature.radius)


## True when a disc of `radius` about `p` stays clear of every `avoid` feature.
static func clear_of(p: Vector2, radius: float, avoid: Array) -> bool:
	for feature: Dictionary in avoid:
		if gap_to(p, feature) < radius:
			return false
	return true


## A river's widest half-width with its bank (WaterGeometry.RIVER_BANK_M).
static func widest(body: WaterBody) -> float:
	var out := 0.0
	for w in body.half_widths:
		out = maxf(out, w)
	return out + WaterGeometry.RIVER_BANK_M


## Raises sample `i`'s weight of `slot` to `value` when it is below it.
static func _raise(doc: MapDocument, i: int, slot: int, value: int, count: int) -> void:
	if value > doc.surface_weights[MapDocument.surface_offset(i, slot, count)]:
		doc.set_surface_weight(i, slot, value)


## True when no water of `doc` lies within `reach` of `p`: a river's course with its
## half-width and bank measured exactly, a pond's mask read at the centre and on rings at a
## third, two thirds and all of `reach`.
static func _dry_around(doc: MapDocument, p: Vector2, reach: float) -> bool:
	var ponds := false
	for body in doc.water_bodies:
		if not body.is_river():
			ponds = true
		elif StartingLandform.nearest_on(body.points, p).x < reach + widest(body):
			return false
	if not ponds or doc.pond_mask.size() != doc.sample_count():
		return true
	if _pond_at(doc, p):
		return false
	for ring in [1.0 / 3.0, 2.0 / 3.0, 1.0]:
		for k in RING_POINTS:
			var angle := TAU * k / RING_POINTS
			if _pond_at(doc, p + Vector2(cos(angle), sin(angle)) * reach * ring):
				return false
	return true


static func _pond_at(doc: MapDocument, p: Vector2) -> bool:
	if not StartingLandform.inside(doc, p, 0.0):
		return false
	var s := doc.world_to_sample(p).round()
	return doc.pond_mask[doc.sample_index(int(s.x), int(s.y))] != 0


## How far the ground of `doc` ranges (metres) over the centre `p` and a ring of `reach`.
static func _ground_range(doc: MapDocument, p: Vector2, reach: float) -> float:
	var low := WaterGeometry.ground_at(doc, p)
	var high := low
	for k in 8:
		var angle := TAU * k / 8.0
		var h := WaterGeometry.ground_at(doc, p + Vector2(cos(angle), sin(angle)) * reach)
		low = minf(low, h)
		high = maxf(high, h)
	return high - low
