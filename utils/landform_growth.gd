class_name LandformGrowth
extends RefCounted

## Big and long maps (2026-10-09). The recipes compose one place on the square of a map's
## shorter side, sized for maps up to 250 ft (NewMap.RECOMMENDED_MAX_FT). A map past that, or
## one longer than it is wide, has room for more, and without more it reads as that one
## composition padded with plain forest, the same features at every size. room() says how
## much room a map has: 0 for a square map of 250 ft or less, so every such map draws exactly
## as before, rising to 1 at 320 ft (NewMap.MAX_FT) or at twice as long as wide. The recipes
## spend it two ways.
##
## Their own shapes grow and turn: a long map's Valley, Gorge and Terraces run along its
## length (turned()), the Valley may meander and its river widens, the Gorge bends twice
## more often, the Terraces may gain a step, and the Hilltop and the Lakeshore sit toward one
## end of a long map, leaving the other for what follows.
##
## And grow() adds one or two features drawn from a small palette by the seed (no sameness:
## a big map draws one, often two, and which ones differs by seed and by landform): a tarn (a
## small pond with an open shore), a knoll (a rounded hill, wooded round its foot, its crown
## open) or a meadow (a clearing in the forest). Open ground, theirs and the recipe's own
## ("open": a hill's upper slopes, a lake's shore, a valley's floor), is opened in the cover
## and painted with the biome's meadow surface: the 2026-10-09 look found that from the
## whole-map view the trees hide a big map's relief, so what reads is water and bright open
## ground. Each is placed by a seeded search (find_spot) that keeps it
## clear of the stage, the water, the crossings, the recipe's own features ("keepout") and
## the other extras, on ground flat enough to stand on, and scores the rest so the feature
## belongs to the place rather than filling a corner: about midway from the stage to the
## map's edge (TARGET_SHARE), well inside the edge, near the recipe's features and water by
## its tie (a tarn beside the river or at the hill's foot, a knoll rising behind the lake),
## on high or low ground by its lean, and toward the far ends of a long map. Every draw comes
## from its own stream (STREAM_SHAPES for the recipes' growth, STREAM_EXTRAS salted by the
## landform here), so a map without room draws nothing new and a big map's base draws stay
## those of the same seed at any size.

const STREAM_SHAPES := 0x6A4C3
const STREAM_EXTRAS := 0x7B5D1
## The longer side where a map starts to have room (250 ft) and where it has it all (320 ft),
## and the aspect (longer side over shorter) at which a long map has it all.
const FROM_M := 76.2
const FULL_M := 97.536
const LONG_FULL_ASPECT := 2.0
## A map at least this much longer than wide is long: its linear landforms run along it.
const LONG_ASPECT := 1.2
## At full room the first extra always comes and a second this often (both scaled by the room
## below it).
const SECOND_EXTRA_CHANCE := 0.7
const TARN := "tarn"
const KNOLL := "knoll"
const MEADOW := "meadow"
## Each landform's palette of extras and their draw weights: a lake's map wants a hill more
## than another pond, a hill's map a tarn at its foot.
const PALETTES := {
	"valley": {TARN: 0.4, KNOLL: 0.35, MEADOW: 0.25},
	"hilltop": {TARN: 0.5, MEADOW: 0.3, KNOLL: 0.2},
	"terraces": {TARN: 0.45, MEADOW: 0.3, KNOLL: 0.25},
	"lakeshore": {KNOLL: 0.55, MEADOW: 0.35, TARN: 0.1},
	"gorge": {TARN: 0.35, KNOLL: 0.35, MEADOW: 0.3},
}
## Each extra's search (find_spot): its radius as a share of the half extent within a range
## (metres), how far inside the map edge its centre must be (a share of its radius), the gap
## it keeps from water (negative: water and the ground's shape do not matter, it is cover
## only), its lean toward high (+) or low (-) ground and its tie to the recipe's features.
const SEARCH := {
	TARN: {"share": 0.2, "range": Vector2(3.5, 9.0), "inset": 1.2, "water_gap": 4.0,
		"lean": -0.5, "tie": 1.0},
	KNOLL: {"share": 0.32, "range": Vector2(5.0, 16.0), "inset": 0.6, "water_gap": 3.0,
		"lean": 1.0, "tie": 0.4},
	MEADOW: {"share": 0.3, "range": Vector2(5.0, 14.0), "inset": 0.6, "water_gap": -1.0,
		"lean": 0.0, "tie": 0.3},
}
## The tarn's shore warps by TARN_WARP of its radius; the cover stays open over
## TARN_OPEN_SHARE of its radius so the trees do not hide it. The knoll's height at 150 ft
## (scaled by StartingLandform.size_scale) and outline warp.
const TARN_WARP := 0.2
const TARN_OPEN_SHARE := 1.8
const KNOLL_HEIGHT_M := 3.0
const KNOLL_WARP := 0.2
## A knoll's crown stays open (and painted, paint_open) over this share of its radius, so the
## hill reads above the trees round its foot.
const KNOLL_OPEN_SHARE := 0.6
## Open ground's paint: full weight inside OPEN_CORE_SHARE of the radius, its outline warped
## by OPEN_WARP of the radius.
const OPEN_CORE_SHARE := 0.45
const OPEN_WARP := 0.25
## The search: candidate spots drawn per feature; the clear ground kept round the stage and a
## crossing and between extras; how far the ground under a tarn or a knoll may range (metres,
## over three quarters of its radius); the preferred distance from the stage (a share of the
## long half extent); the band inside the map edge (a share of the half extent past the
## feature's radius) where a spot loses score, and by how much; how near the recipe's
## features a spot counts as tied to them (a share of the half extent); the weight of a long
## map's far ends; the relief (metres at 150 ft) a lean is measured in.
const CANDIDATES := 48
const STAGE_CLEAR_M := 8.0
const CROSSING_CLEAR_M := 5.0
const EXTRA_GAP_M := 6.0
const FLAT_RANGE_M := 0.6
const TARGET_SHARE := 0.55
const EDGE_SHARE := 0.25
const EDGE_WEIGHT := 1.5
const TIE_REACH_SHARE := 0.4
const LONG_LEAN := 0.6
const LEAN_RELIEF_M := 3.0
const RING_POINTS := 16


## How much room `doc` has past the one-place composition (see the header), 0..1.
static func room(doc: MapDocument) -> float:
	var extent := doc.extent_m()
	var longer := maxf(extent.x, extent.y)
	# A centimetre of slack: a 250 ft side is 76.2 m only to float precision.
	var by_size := clampf((longer - FROM_M - 0.01) / (FULL_M - FROM_M), 0.0, 1.0)
	return maxf(by_size, long_room(doc))


## The part of room() a long map has from its shape alone: 0 square, 1 at LONG_FULL_ASPECT.
static func long_room(doc: MapDocument) -> float:
	return clampf((aspect(doc) - 1.0) / (LONG_FULL_ASPECT - 1.0), 0.0, 1.0)


## The map's longer side over its shorter.
static func aspect(doc: MapDocument) -> float:
	var extent := doc.extent_m()
	return maxf(extent.x, extent.y) / maxf(minf(extent.x, extent.y), 1e-3)


## True when the map is at least LONG_ASPECT longer than wide.
static func is_long(doc: MapDocument) -> bool:
	return aspect(doc) >= LONG_ASPECT


## The unit direction of the map's longer side (+x when square).
static func long_dir(doc: MapDocument) -> Vector2:
	var extent := doc.extent_m()
	return Vector2.RIGHT if extent.x >= extent.y else Vector2.DOWN


## Half the map's longer side (metres).
static func long_half(doc: MapDocument) -> float:
	var extent := doc.extent_m()
	return maxf(extent.x, extent.y) * 0.5


## `dir` (a recipe's heading) on a long map turned a quarter when it crosses the map's length
## (within 60 degrees of square to it), so the landform runs along the map; unchanged on a
## map that is not long and for a heading already along it or diagonal.
static func turned(doc: MapDocument, dir: Vector2) -> Vector2:
	if not is_long(doc) or absf(dir.dot(long_dir(doc))) >= 0.5:
		return dir
	return dir.rotated(PI / 2.0)


## A heading in whole degrees 0..359 for a report.
static func degrees(dir: Vector2) -> int:
	return posmod(roundi(rad_to_deg(dir.angle())), 360)


## Adds the extras a map with room draws (see the header) to `doc`, after `kind`'s recipe
## shaped it into `shaped` (its "stage", optionally "keepout": the recipe's own features as
## discs {"at", "radius"} or bands {"line", "radius"}). Appends a line per extra to shaped's
## "report" and sets its "clearings" ([{"at", "radius"}], the meadows and the tarns' open
## shores, for NewMap.paint_starting_cover). Open ground (a meadow, a knoll's crown, a tarn's
## shore, and the recipe's own "open" discs: a hill's top) is painted with the biome's meadow
## surface (meadow_surface), so it reads as a bright clearing from the whole-map view rather
## than bare forest floor between the trees. Nothing without room.
static func grow(
	doc: MapDocument,
	kind: String,
	seed_value: int,
	shaped: Dictionary,
	biome_id: String = "",
	root: String = PaletteLibrary.DEFAULT_ROOT
) -> void:
	var r := room(doc)
	if r <= 0.0 or not PALETTES.has(kind):
		return
	var rng := StartingLandform.stream(seed_value ^ kind.hash(), STREAM_EXTRAS)
	var picks := extras(PALETTES[kind], r, rng)
	var surface := meadow_surface(biome_id, root)
	var clearings: Array = shaped.get("clearings", [])
	for feature: Dictionary in shaped.get("open", []):
		if feature.has("at"):
			clearings.append(feature)
		paint_open(doc, surface, feature, rng)
	shaped["clearings"] = clearings
	if picks.is_empty():
		return
	var half := StartingLandform.half_extent(doc)
	var stage: Vector2 = shaped.get("stage", Vector2.ZERO)
	var keepout: Array = shaped.get("keepout", [])
	var avoid: Array = [{"at": stage, "radius": STAGE_CLEAR_M}]
	avoid.append_array(keepout)
	for crossing in doc.crossings:
		avoid.append({"at": (crossing.start + crossing.end) * 0.5, "radius": CROSSING_CLEAR_M})
	var ties: Array = keepout.duplicate()
	for body in doc.water_bodies:
		if body.is_river():
			ties.append({"line": body.points, "radius": _widest(body)})
	var report := PackedStringArray([String(shaped.get("report", ""))])
	var wet := false
	# Knolls before tarns: a tarn's level is read from its rim as it finally stands.
	picks.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	for pick in picks:
		var want: Dictionary = SEARCH[pick].duplicate()
		var range_m: Vector2 = want.range
		want["radius"] = clampf(half * float(want.share), range_m.x, range_m.y)
		var radius: float = want.radius
		var at := find_spot(doc, rng, want, avoid, ties, stage)
		if at == Vector2.INF:
			report.append("%s: no open ground" % pick)
			continue
		match pick:
			KNOLL:
				var height := KNOLL_HEIGHT_M * StartingLandform.size_scale(doc)
				knoll(doc, at, radius, height, rng)
				var crown := {"at": at, "radius": radius * KNOLL_OPEN_SHARE}
				clearings.append(crown)
				paint_open(doc, surface, crown, rng)
				report.append("knoll %.1f m high at (%.1f, %.1f)" % [height, at.x, at.y])
			MEADOW:
				var meadow := {"at": at, "radius": radius}
				clearings.append(meadow)
				paint_open(doc, surface, meadow, rng)
				report.append("meadow at (%.1f, %.1f)" % [at.x, at.y])
			TARN:
				var body := tarn(doc, at, radius, rng)
				if body == null:
					report.append("tarn: no room for the water")
					continue
				wet = true
				var shore := {"at": at, "radius": radius * TARN_OPEN_SHARE}
				clearings.append(shore)
				paint_open(doc, surface, shore, rng)
				report.append("tarn at (%.1f, %.1f), level %.2f m" % [at.x, at.y, body.level_m])
		avoid.append({"at": at, "radius": radius + EXTRA_GAP_M})
	if wet:
		doc.water_dressing = WaterDressing.refresh(doc)
	shaped["report"] = "; ".join(report)
	shaped["clearings"] = clearings


## The extras drawn from `palette` (name -> weight) for a map with `r` room: one with chance
## `r`, another with SECOND_EXTRA_CHANCE * `r`, each by weight among those not yet drawn. Four
## draws from `rng` whatever comes, so the spots after them do not shift with a chance.
static func extras(palette: Dictionary, r: float, rng: RandomNumberGenerator) -> Array[String]:
	var count := (1 if rng.randf() < r else 0) + (1 if rng.randf() < SECOND_EXTRA_CHANCE * r else 0)
	var left: Dictionary = palette.duplicate()
	var out: Array[String] = []
	for n in 2:
		var pick := rng.randf()
		if n >= count or left.is_empty():
			continue
		var total := 0.0
		for name in left:
			total += float(left[name])
		var sum := 0.0
		var chosen: String = left.keys()[-1]
		for name: String in left:
			sum += float(left[name]) / total
			if pick < sum:
				chosen = name
				break
		out.append(chosen)
		left.erase(chosen)
	return out


## A seeded spot for a feature (see the header) described by `want` (SEARCH's fields and its
## "radius"): CANDIDATES points drawn from `rng` at least its inset inside the map edge, each
## refused when its disc comes within an `avoid` feature (a disc {"at", "radius"} or a band
## {"line", "radius"}), when water lies within its water gap of its outline or the ground
## under it ranges more than FLAT_RANGE_M (a negative gap skips both); the rest scored by
## distance from `stage` against TARGET_SHARE, the edge band, the nearness of the `ties`
## features (same forms), the lean and a long map's far ends. Vector2.INF when none fits.
## Always draws 2 * CANDIDATES numbers.
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
	var reach := long_half(doc)
	var along := long_dir(doc)
	var long_weight := LONG_LEAN * long_room(doc)
	var relief := LEAN_RELIEF_M * StartingLandform.size_scale(doc)
	var best := Vector2.INF
	var best_score := -INF
	for n in CANDIDATES:
		var p := Vector2(
			rng.randf_range(-1.0, 1.0) * maxf(bound.x, 0.0),
			rng.randf_range(-1.0, 1.0) * maxf(bound.y, 0.0)
		)
		if not _clear_of(p, radius, avoid):
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
				gap = minf(gap, _gap(p, feature) - radius)
			score += float(want.tie) * clampf(1.0 - gap / (TIE_REACH_SHARE * half), 0.0, 1.0)
		score += long_weight * absf(p.dot(along)) / reach
		score += float(want.lean) * WaterGeometry.ground_at(doc, p) / maxf(relief, 1e-3)
		if score > best_score:
			best_score = score
			best = p
	return best


## Raises a knoll on `doc`: a rounded hill of `height` and `radius` about `at` (its outline
## warped by KNOLL_WARP, the warp noise from `rng`), added to the ground as it stands.
static func knoll(
	doc: MapDocument, at: Vector2, radius: float, height: float, rng: RandomNumberGenerator
) -> void:
	var noise := StartingLandform.warp_noise(rng, radius)
	var outer := radius * (1.0 + KNOLL_WARP)
	StartingLandform.write_heights(
		doc,
		func(p: Vector2, h: float) -> float:
			var d := p.distance_to(at)
			if d >= outer:
				return h
			var warped := StartingLandform.disc_distance(p, at, radius, noise, KNOLL_WARP) + d
			return h + height * StartingLandform.bump(d / maxf(warped, 1e-3))
	)


## Carves a tarn into `doc`: a waist-deep pond over a disc of `radius` about `at`, its shore
## warped by TARN_WARP (the warp noise from `rng`), through StartingLandform.carve_pond (the
## level from its rim as it stands). The body, or null when it could not be carved.
static func tarn(
	doc: MapDocument, at: Vector2, radius: float, rng: RandomNumberGenerator
) -> WaterBody:
	var noise := StartingLandform.warp_noise(rng, radius)
	var outer := radius * (1.0 + TARN_WARP)
	return StartingLandform.carve_pond(
		doc,
		func(p: Vector2) -> bool:
			return (
				p.distance_to(at) < outer
				and StartingLandform.disc_distance(p, at, radius, noise, TARN_WARP) > 0.0
			),
		WaterBody.Depth.WAIST
	)


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
			var inside := -_gap(p, feature) + noise.get_noise_2d(p.x, p.y) * OPEN_WARP * radius
			if inside <= 0.0:
				continue
			var t := smoothstep(0.0, radius * (1.0 - OPEN_CORE_SHARE), inside)
			var value := roundi(255.0 * t)
			var i := doc.sample_index(x, z)
			if value > doc.surface_weights[MapDocument.surface_offset(i, slot, count)]:
				doc.set_surface_weight(i, slot, value)


## Knolls first, then meadows, then tarns (see grow()).
static func _order(pick: String) -> int:
	return [KNOLL, MEADOW, TARN].find(pick)


## The distance from `p` to the edge of `feature` (a disc {"at", "radius"} or a band
## {"line", "radius"} about a polyline); negative inside it.
static func _gap(p: Vector2, feature: Dictionary) -> float:
	var centre := (
		p.distance_to(feature.at)
		if feature.has("at")
		else StartingLandform.nearest_on(feature.line, p).x
	)
	return centre - float(feature.radius)


## True when a disc of `radius` about `p` stays clear of every `avoid` feature.
static func _clear_of(p: Vector2, radius: float, avoid: Array) -> bool:
	for feature: Dictionary in avoid:
		if _gap(p, feature) < radius:
			return false
	return true


## A river's widest half-width with its bank (WaterGeometry.RIVER_BANK_M).
static func _widest(body: WaterBody) -> float:
	var widest := 0.0
	for w in body.half_widths:
		widest = maxf(widest, w)
	return widest + WaterGeometry.RIVER_BANK_M


## True when no water of `doc` lies within `reach` of `p`: a river's course with its
## half-width and bank measured exactly, a pond's mask read at the centre and on rings at a
## third, two thirds and all of `reach`.
static func _dry_around(doc: MapDocument, p: Vector2, reach: float) -> bool:
	var ponds := false
	for body in doc.water_bodies:
		if not body.is_river():
			ponds = true
		elif StartingLandform.nearest_on(body.points, p).x < reach + _widest(body):
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
