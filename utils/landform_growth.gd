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
## more often, the Terraces may gain a step, the Hilltop sits toward one end of a long map,
## leaving the other for what follows, and the Lakeshore's lake takes any corner or side of
## it (LandformLakeshore.wide_frame).
##
## And grow() adds one or two features drawn from a small palette by the seed (no sameness:
## a big map draws one, usually two, and which ones differs by seed and by landform): a tarn
## (a small pond with an open shore), a meadow (a clearing in the forest) or a knoll (a
## rounded hill, wooded round its foot, its crown open). Open ground, theirs and the recipe's
## own ("open": a hill's upper slopes, a lake's shore, a valley's floor), is opened in the
## cover and painted with the biome's meadow surface: the 2026-10-09 look found that from the
## whole-map view the trees hide a big map's relief, so what reads is water and bright open
## ground, which is why tarns and meadows are drawn far more often than knolls. Each is
## placed by a seeded search (LandformPlacement.find_spot) that keeps it clear of the stage,
## the water, the crossings, the recipe's own features ("keepout") and the other extras, on
## ground flat enough to stand on, and scores the rest so the feature belongs to the place
## (a tarn beside the river or at the hill's foot, a knoll rising behind the lake) rather
## than filling a corner. LandformPlacement also greens the thin parts of a big map's
## starting cover (paint_sparse, after NewMap paints it). Every draw comes from its own
## stream (STREAM_SHAPES for the recipes' growth, STREAM_EXTRAS salted by the landform here),
## so a map without room draws nothing new and a big map's base draws stay those of the same
## seed at any size.

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
## below it; 0.7 until the 2026-10-09 round 2 look, where one extra often read as none).
const SECOND_EXTRA_CHANCE := 0.85
const TARN := "tarn"
const KNOLL := "knoll"
const MEADOW := "meadow"
## Each landform's palette of extras and their draw weights: a lake's map wants a meadow or a
## hill more than another pond, a hill's map a tarn at its foot. Knolls are drawn least: under
## the forest a knoll reads only by its open crown, and two hills on a hilltop map read as the
## same map again (round 2 look, 2026-10-09).
const PALETTES := {
	"valley": {TARN: 0.4, MEADOW: 0.4, KNOLL: 0.2},
	"hilltop": {TARN: 0.5, MEADOW: 0.42, KNOLL: 0.08},
	"terraces": {TARN: 0.45, MEADOW: 0.4, KNOLL: 0.15},
	"lakeshore": {MEADOW: 0.55, KNOLL: 0.3, TARN: 0.15},
	"gorge": {TARN: 0.4, MEADOW: 0.4, KNOLL: 0.2},
}
## Each extra's search (LandformPlacement.find_spot): its radius as a share of the half extent
## within a range (metres), how far inside the map edge its centre must be (a share of its
## radius), the gap it keeps from water (negative: water and the ground's shape do not matter,
## it is cover only), its lean toward high (+) or low (-) ground and its tie to the recipe's
## features.
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
## A knoll's crown stays open (and painted, LandformPlacement.paint_open) over this share of
## its radius, so the hill reads as a green dome above the trees round its foot (0.6 until
## the round 2 look, where the trees closed over it).
const KNOLL_OPEN_SHARE := 0.95
## A map whose shorter side is at least this (metres; 200 ft is 60.96) is wide (is_wide).
const WIDE_FROM_M := 60.0
## The clear ground the search keeps round the stage and a crossing, and between extras.
const STAGE_CLEAR_M := 8.0
const CROSSING_CLEAR_M := 5.0
const EXTRA_GAP_M := 6.0


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


## True when the map's shorter side is at least WIDE_FROM_M (200 ft and up): wide enough
## that the whole-map view, not the home frame, is what a recipe composes for, so the Hilltop
## and the Lakeshore may stand their hill or lake toward any side.
static func is_wide(doc: MapDocument) -> bool:
	var extent := doc.extent_m()
	return minf(extent.x, extent.y) >= WIDE_FROM_M


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
## surface (LandformPlacement.meadow_surface), so it reads as a bright clearing from the
## whole-map view rather than bare forest floor between the trees. Nothing without room.
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
	var surface := LandformPlacement.meadow_surface(biome_id, root)
	var clearings: Array = shaped.get("clearings", [])
	for feature: Dictionary in shaped.get("open", []):
		if feature.has("at"):
			clearings.append(feature)
		LandformPlacement.paint_open(doc, surface, feature, rng)
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
			ties.append({"line": body.points, "radius": LandformPlacement.widest(body)})
	var report := PackedStringArray([String(shaped.get("report", ""))])
	var wet := false
	# Knolls before tarns: a tarn's level is read from its rim as it finally stands.
	picks.sort_custom(func(a: String, b: String) -> bool: return _order(a) < _order(b))
	for pick in picks:
		var want: Dictionary = SEARCH[pick].duplicate()
		var range_m: Vector2 = want.range
		want["radius"] = clampf(half * float(want.share), range_m.x, range_m.y)
		var radius: float = want.radius
		var at := LandformPlacement.find_spot(doc, rng, want, avoid, ties, stage)
		if at == Vector2.INF:
			report.append("%s: no open ground" % pick)
			continue
		match pick:
			KNOLL:
				var height := KNOLL_HEIGHT_M * StartingLandform.size_scale(doc)
				knoll(doc, at, radius, height, rng)
				var crown := {"at": at, "radius": radius * KNOLL_OPEN_SHARE}
				clearings.append(crown)
				LandformPlacement.paint_open(doc, surface, crown, rng)
				report.append("knoll %.1f m high at (%.1f, %.1f)" % [height, at.x, at.y])
			MEADOW:
				var meadow := {"at": at, "radius": radius}
				clearings.append(meadow)
				LandformPlacement.paint_open(doc, surface, meadow, rng)
				report.append("meadow at (%.1f, %.1f)" % [at.x, at.y])
			TARN:
				var body := tarn(doc, at, radius, rng)
				if body == null:
					report.append("tarn: no room for the water")
					continue
				wet = true
				var shore := {"at": at, "radius": radius * TARN_OPEN_SHARE}
				clearings.append(shore)
				LandformPlacement.paint_open(doc, surface, shore, rng)
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


## Knolls first, then meadows, then tarns (see grow()).
static func _order(pick: String) -> int:
	return [KNOLL, MEADOW, TARN].find(pick)
