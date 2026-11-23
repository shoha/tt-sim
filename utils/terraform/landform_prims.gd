class_name LandformPrims
extends RefCounted
## The starting landforms as terrain primitives (card terraform-p2-landforms; switch on): a new
## map opens with a terrain section an author edits like any other, not a baked height array.
##
## The draws stay the recipes'. apply() runs StartingLandform.apply on the flat document first,
## so every seeded draw (the frame, each feature's chance, the river's wobble, the extras) is the
## one the switch-off map makes, from the same streams and chance constants, and the surfaces it
## paints (a wash, meadows) stay as they are. Each recipe also returns its shape as "form" hints
## (the trough, the hill, the plateaus, the cut, the lake; LandformGrowth's knolls and tarns),
## and its water as the bodies it carved. This class turns those into primitives, derives them in
## full and writes the derived ground and water over the recipe's (TerraBridge's whole swap, as
## seed_new_map does), then places the recipe's crossings again on the derived water
## (StartingLandform.place_crossing and span_crossing: CrossingPlacement's rules).
##
## The primitives per landform:
## - Flat: a plane.
## - Valley: a plane, a negative ridge along the bent axis, flatten level dabs along the floor
##   with its fall, the river (and tributary) as rivers, a dry wash as paint, the bluff as a run
##   of tier-cut level dabs along the bank.
## - Hilltop: hills (the second hill too), the crown as a run of tier dabs (a disc and lobes on
##   its warped outline), the flank ledge as tier dabs along its arc, the stream as a river (its
##   first reach on the flat crown is the crown's pool).
## - Terraces: per plateau, lowest first, a run of tier dabs filling its rounded box (spines
##   along the heading, the step edge wobbled by the recipe's noise), the river as a river.
## - Lakeshore: a raised plane and a negative hill (the ground rising away from the shore), the
##   lake as a pond on the warped shore (an islet a hill the outline goes round), the stream.
## - Gorge: tier-cut level dabs along the axis (the Sculpt tool's tier cut, as the recipe cuts
##   it; the targets follow the floor's fall), the stream as a river, a dry wash as paint.
## Shapes written as distance fields have no exact primitive, so they are approximated (a cosine
## bump by a hill's profile, a rounded box by capsules) and judged by the look, not by height.

const LevelKind := preload("res://utils/terraform/kinds/level/level_kind.gd")

## A hill's profile exponent for the recipes' cosine bump: (1 - t^2)^2.3 is within 0.02 of it.
const HILL_PROFILE := 2.3
## The trough's ridge profile: (1 - d^2 / rim^2)^2, flat at the rim like the recipe's cosine.
const TROUGH_PROFILE := 2.0
## Floor flatten dabs: their spacing along the axis, radius as a share of the floor's half
## width and seconds of exposure (1 - exp(-4 w s) of the way per dab).
const FLOOR_STEP_M := 1.0
const FLOOR_RADIUS_SHARE := 1.1
const FLOOR_SECONDS := 1.0
## Tier dabs along a line (the bluff, the gorge, the ledge): spacing.
const LINE_STEP_M := 1.0
## The crown's lobes round its warped outline, and their radius as a share of the crown's.
const CROWN_LOBES := 12
const CROWN_LOBE_SHARE := 0.45
## The ledge's dab radius as a share of its line's radius, at most LEDGE_RADIUS_MAX_M.
const LEDGE_RADIUS_SHARE := 0.4
const LEDGE_RADIUS_MAX_M := 6.0
## Plateau spines: their spacing across as a share of the corner radius, and segment length.
const SPINE_SHARE := 0.4
const SPINE_SEGMENT_M := 4.0
## Outline points of a pond (a warped disc) and of an islet's ring.
const POND_POINTS := 64
const ISLET_POINTS := 16
## A river's end is carried this much further along its last segment, so it reaches into the
## body it joins (a lake's shore, the river a tributary meets), when it is this far inside.
const RIVER_REACH_M := 1.0
const RIVER_END_INSIDE_M := 2.0
## A crossing the derived water refuses at the recipe's place is tried again at the nearest
## river points within CROSSING_SEARCH_M, up to CROSSING_TRIES of them.
const CROSSING_SEARCH_M := 6.0
const CROSSING_TRIES := 8
## Paint dabs along a wash: spacing as a share of the half width.
const WASH_STEP_SHARE := 0.5
## A wash coat: its soft edge past the half width (StartingLandform.paint_line's), and the exposure
## of each dab (SurfaceStroke seconds: about full cover inside half the radius).
const WASH_SOFT_M := 1.0
const WASH_SECONDS := 1.5
## The features a report names and the primitives must carry (report_features).
const SHAPE_FEATURES: Array[String] = [
	"bluff", "crown", "ledge", "second hill", "islet", "knoll", "tarn", "wash"
]


## Shapes `doc` (a flat new-map document) as landform `kind` with `seed_value` on primitives:
## StartingLandform.apply's result (the stage, the report, the glade, clearings and wood), its
## report ending in a "primitives:" line naming what was made, and "made" (the feature names,
## made_features()). The document gets a terrain section, derived heights and water and the
## crossings placed again. Returns {} (the document as the recipe left it) without the library.
static func apply(
	kind: String,
	doc: MapDocument,
	seed_value: int,
	biome_id: String = "",
	root: String = PaletteLibrary.DEFAULT_ROOT
) -> Dictionary:
	if doc == null or doc.heights.is_empty() or not TerraCore.native_available():
		return {}
	var base := doc.heights[(doc.samples_z() / 2) * doc.samples_x() + doc.samples_x() / 2]
	var shaped := StartingLandform.apply(doc, kind, seed_value, biome_id, root)
	var crossings: Array = doc.crossings.duplicate()
	var terra := TerraDoc.new()
	var made := PackedStringArray()
	terra.add(TerraCore.PLANE, PackedFloat32Array([base, 0.0, 0.0]))
	for hint: Dictionary in shaped.get("form", []):
		_add_form(terra, doc, hint, base, made)
	_add_water(terra, doc, made)
	var derive := TerraCache.derive_for(terra, doc)
	if derive == null:
		return shaped
	doc.heights = derive.call("doc_heights")
	terra.derived = TerraCache.make_record(terra, doc, derive)
	doc.terra = terra
	TerraBridge.swap_surfaces(doc, derive)
	var water := TerraBridge.water_of(derive, doc)
	if not water.has("error"):
		doc.water_bodies = water["bodies"]
		doc.pond_mask = water["pond_mask"]
		doc.water_flow = PackedByteArray()
		doc.water_flow_size = Vector2i.ZERO
	doc.crossings = []
	for crossing: Crossing in crossings:
		made.append(_place_again(doc, crossing))
	doc.water_dressing = WaterDressing.refresh(doc)
	shaped["made"] = made
	var line := "primitives: %d (%s)" % [terra.prims.size(), ", ".join(made)]
	shaped["report"] = "; ".join(PackedStringArray([String(shaped.get("report", "flat")), line]))
	if not shaped.has("stage"):
		shaped["stage"] = Vector2.ZERO
	return shaped


## The shape features a switch-off report names, in the vocabulary made_features() uses:
## "bluff", "crown", "ledge", "second hill", "islet", "knoll", "tarn", "wash". Water and
## crossings are compared on the documents.
static func report_features(report: String) -> PackedStringArray:
	var out := PackedStringArray()
	for part in report.split("; "):
		if part.begins_with("valley heading") and part.contains("bluff"):
			out.append("bluff")
		elif part.begins_with("crown at"):
			out.append("crown")
		elif part.begins_with("flank ledge"):
			out.append("ledge")
		elif part.begins_with("second hill"):
			out.append("second hill")
		elif part.begins_with("islet at"):
			out.append("islet")
		elif part.begins_with("knoll"):
			out.append("knoll")
		elif part.begins_with("tarn at"):
			out.append("tarn")
		elif part.begins_with("dry wash of"):
			out.append("wash")
	out.sort()
	return out


## The shape features of an apply() result's "made", sorted, as report_features() names them.
static func made_features(made: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for name in made:
		if name in SHAPE_FEATURES:
			out.append(name)
	out.sort()
	return out


static func _add_form(
	terra: TerraDoc, doc: MapDocument, hint: Dictionary, base: float, made: PackedStringArray
) -> void:
	match String(hint.get("type", "")):
		"trough":
			_trough(terra, doc, hint, base, made)
		"cut":
			_cut(terra, doc, hint, base)
			made.append("cut")
		"hill":
			_hill(terra, hint.at, hint.radius, hint.height)
			made.append(String(hint.get("feature", "hill")))
		"crown":
			_crown(terra, hint, base)
			made.append("crown")
		"ledge":
			_ledge(terra, hint, base)
			made.append("ledge")
		"plateaus":
			_plateaus(terra, doc, hint, base)
			made.append("plateaus")
		"lake":
			_lake(terra, doc, hint, base, made)
		"tarn":
			var outline := _outline(doc, hint.at, hint.radius, hint.noise, hint.warp)
			_pond(terra, doc, outline, WaterBody.DEPTH_M[WaterBody.Depth.WAIST])
			made.append("tarn")
		"wash":
			if _wash(terra, doc, hint):
				made.append("wash")


## The Valley's trough: a negative ridge whose value at the floor's edge is the floor's mean
## depth, flatten dabs along the floor toward its falling height, and the bluff's tier cut.
static func _trough(
	terra: TerraDoc, doc: MapDocument, hint: Dictionary, base: float, made: PackedStringArray
) -> void:
	var axis: PackedVector2Array = hint.axis
	var floor_half: float = hint.floor_half
	var rim: float = hint.rim
	var depth: float = hint.depth
	var fall: float = hint.fall
	var at_floor := pow(1.0 - pow(floor_half / rim, 2.0), TROUGH_PROFILE)
	var ridge := PackedFloat32Array([-(depth + fall * 0.5) / at_floor, rim, TROUGH_PROFILE])
	for p in axis:
		ridge.append_array([p.x, p.y])
	terra.add(TerraCore.RIDGE, ridge)
	made.append("trough")
	var radius := floor_half * FLOOR_RADIUS_SHARE
	var dabs := PackedFloat32Array()
	for seg in _segments(doc, axis, hint.s0, hint.s1, radius, FLOOR_STEP_M):
		var target: float = base - depth - fall * float(seg.along)
		dabs.append_array(LevelKind.flatten_dab(seg.a, seg.b, radius, FLOOR_SECONDS, target))
	if not dabs.is_empty():
		terra.add(LevelKind.ID, dabs)
	if not hint.bluff:
		return
	# The bluff: one tier cut to a tier under the bank, its face on the bluff's outline (the
	# rim line wobbled by the recipe's noise) on one bank; the floor side is below the target,
	# so only the bank's upper slope is cut.
	var side: float = hint.bluff_side
	var noise: FastNoiseLite = hint.bluff_noise
	var cut := PackedFloat32Array()
	for seg in _segments(doc, axis, hint.s0, hint.s1, rim, LINE_STEP_M):
		var normal: Vector2 = Vector2(seg.dir).rotated(side * PI / 2.0)
		var a: Vector2 = seg.a + normal * floor_half
		var b: Vector2 = seg.b + normal * floor_half
		var edge: Vector2 = seg.a + normal * float(hint.bluff_rim)
		var reach: float = (
			float(hint.bluff_rim) + float(hint.bluff_wobble) * noise.get_noise_2d(edge.x, edge.y)
		)
		cut.append_array(
			LevelKind.tier_dab(a, b, maxf(reach - floor_half, 0.5), base - doc.tier_height_m, true)
		)
	if not cut.is_empty():
		terra.add(LevelKind.ID, cut)
		made.append("bluff")


## The Gorge's cut: tier-cut dabs along the axis of the rim's half width, each toward the floor
## under it (the depth and the fall to that point), so the walls are the Sculpt tool's riser.
static func _cut(terra: TerraDoc, doc: MapDocument, hint: Dictionary, base: float) -> void:
	var dabs := PackedFloat32Array()
	var rim_half: float = hint.rim_half
	for seg in _segments(doc, hint.axis, hint.s0, hint.s1, rim_half, LINE_STEP_M):
		var target: float = base - float(hint.depth) - float(hint.fall) * float(seg.along)
		dabs.append_array(LevelKind.tier_dab(seg.a, seg.b, rim_half, target, true))
	if not dabs.is_empty():
		terra.add(LevelKind.ID, dabs)


static func _hill(terra: TerraDoc, at: Vector2, radius: float, height: float) -> void:
	terra.add(TerraCore.HILL, PackedFloat32Array([at.x, at.y, height, radius, HILL_PROFILE]))


## The Hilltop's crown: one run of tier dabs at the crown's height, a disc inside the warped
## outline and lobes whose outer edge lies on it (disc_distance's radius at each lobe's angle).
static func _crown(terra: TerraDoc, hint: Dictionary, base: float) -> void:
	var at: Vector2 = hint.at
	var radius: float = hint.radius
	var warp: float = hint.warp
	var noise: FastNoiseLite = hint.noise
	var target: float = base + float(hint.target)
	var dabs := PackedFloat32Array(
		LevelKind.tier_dab(at, at, radius * (1.0 - warp), target, false)
	)
	var lobe := radius * CROWN_LOBE_SHARE
	for k in CROWN_LOBES:
		var dir := Vector2.RIGHT.rotated(TAU * k / CROWN_LOBES)
		var edge := radius + StartingLandform.disc_distance(at + dir * radius, at, radius, noise, warp)
		var c := at + dir * maxf(edge - lobe, 0.0)
		dabs.append_array(LevelKind.tier_dab(c, c, lobe, target, false))
	terra.add(LevelKind.ID, dabs)


## The flank ledge: tier dabs along its arc about `facing`, their outer edge on the ledge's
## line, raising only the flank below the bench's height.
static func _ledge(terra: TerraDoc, hint: Dictionary, base: float) -> void:
	var at: Vector2 = hint.at
	var line_r: float = hint.line_r
	var arc: float = hint.arc
	var facing: Vector2 = hint.facing
	var radius := minf(line_r * LEDGE_RADIUS_SHARE, LEDGE_RADIUS_MAX_M)
	var spine := maxf(line_r - radius, 0.0)
	var half_angle := maxf(arc * 0.5 - radius / maxf(line_r, 1e-3), 0.0)
	var steps := maxi(1, ceili(2.0 * half_angle * maxf(spine, 1e-3) / LINE_STEP_M))
	var dabs := PackedFloat32Array()
	var target := base + float(hint.target)
	for n in steps:
		var a := at + facing.rotated(-half_angle + 2.0 * half_angle * n / steps) * spine
		var b := at + facing.rotated(-half_angle + 2.0 * half_angle * (n + 1) / steps) * spine
		dabs.append_array(LevelKind.tier_dab(a, b, radius, target, false))
	terra.add(LevelKind.ID, dabs)


## The Terraces' plateaus, lowest first (each higher one tiers the one below): per plateau one
## run of tier dabs, spines along the heading with the corner's radius filling its rounded box,
## the downhill ends moved by the recipe's edge wobble. Only the part on the map is dabbed.
static func _plateaus(terra: TerraDoc, doc: MapDocument, hint: Dictionary, base: float) -> void:
	var plateaus: Array = hint.plateaus
	var dir: Vector2 = hint.dir
	var normal := Vector2(-dir.y, dir.x)
	var noise: FastNoiseLite = hint.noise
	var wobble: float = hint.wobble
	var tier: float = hint.tier
	var reach := StartingLandform.half_extent(doc) * 1.5
	for k in range(plateaus.size() - 1, -1, -1):
		var plateau: Dictionary = plateaus[k]
		var centre: Vector2 = plateau.centre
		var half_size: Vector2 = plateau.half_size
		var radius := maxf(float(plateau.corner), HeightBrush.tier_span(tier))
		var target := base + float(plateau.level) * tier
		var across := maxf(half_size.y - radius, 0.0)
		var spines := maxi(1, ceili(2.0 * across / (radius * SPINE_SHARE)))
		var dabs := PackedFloat32Array()
		for s in spines + 1:
			var v := -across + 2.0 * across * s / spines
			var top := centre + normal * v + dir * (half_size.x - radius)
			var outline := top + dir * radius
			top += dir * wobble * noise.get_noise_2d(outline.x, outline.y)
			# From the downhill end back uphill, as far as the map (or the box) reaches.
			var length := minf(2.0 * maxf(half_size.x - radius, 0.0), top.length() + reach)
			var pieces := maxi(1, ceili(length / SPINE_SEGMENT_M))
			for n in pieces:
				var a := top - dir * length * n / pieces
				var b := top - dir * length * (n + 1) / pieces
				if StartingLandform.inside(doc, a, -radius) or StartingLandform.inside(doc, b, -radius):
					dabs.append_array(LevelKind.tier_dab(a, b, radius, target, false))
		if not dabs.is_empty():
			terra.add(LevelKind.ID, dabs)


## The Lakeshore: the plane raised by the shore's rise and a negative hill about the lake, so
## the ground falls toward the shore; an islet hill; the lake as a pond on the warped shore,
## going round the islet.
static func _lake(
	terra: TerraDoc, doc: MapDocument, hint: Dictionary, base: float, made: PackedStringArray
) -> void:
	var at: Vector2 = hint.at
	var radius: float = hint.radius
	var rise: float = hint.rise
	var bowl := radius * (1.0 + float(hint.warp)) + float(hint.run)
	terra.prims[0]["data"] = PackedFloat32Array([base + rise, 0.0, 0.0])
	_hill(terra, at, bowl, -rise)
	var outline := _outline(doc, at, radius, hint.noise, hint.warp)
	if hint.islet:
		var islet_at: Vector2 = hint.islet_at
		var islet_radius: float = hint.islet_radius
		var t := islet_at.distance_to(at) / bowl
		var ground := base + rise - rise * pow(maxf(1.0 - t * t, 0.0), HILL_PROFILE)
		var shore_t := radius / bowl
		var shore := base + rise - rise * pow(1.0 - shore_t * shore_t, HILL_PROFILE)
		_hill(terra, islet_at, islet_radius, shore + float(hint.islet_height) - ground)
		outline = _round_islet(outline, at, islet_at, islet_radius * 0.6)
		made.append("islet")
	if hint.carved:
		_pond(terra, doc, outline, WaterBody.DEPTH_M[WaterBody.Depth.DEEP])
		made.append("lake")


## `outline` (a closed loop about `centre`) with a ring of `ring` about `islet` cut out of it by
## a slit from the loop's point nearest the islet's bearing (the pond's inside test leaves the
## ring dry; the slit's two sides coincide).
static func _round_islet(
	outline: PackedVector2Array, centre: Vector2, islet: Vector2, ring: float
) -> PackedVector2Array:
	var bearing := (islet - centre).angle()
	var best := 0
	for k in outline.size():
		if absf(angle_difference((outline[k] - centre).angle(), bearing)) < absf(
			angle_difference((outline[best] - centre).angle(), bearing)
		):
			best = k
	var out := PackedVector2Array()
	for k in outline.size():
		out.append(outline[k])
		if k != best:
			continue
		var start := (outline[k] - islet).angle()
		for j in ISLET_POINTS + 1:
			out.append(islet + Vector2.RIGHT.rotated(start - TAU * j / ISLET_POINTS) * ring)
		out.append(outline[k])
	return out


## A pond of `depth` on `outline`, kept on the map.
static func _pond(
	terra: TerraDoc, doc: MapDocument, outline: PackedVector2Array, depth: float
) -> void:
	var data := PackedFloat32Array([depth])
	for p in outline:
		var q := StartingLandform.clamped(doc, p, 0.0)
		data.append_array([q.x, q.y])
	terra.add(TerraCore.POND, data)


## A warped disc's outline (StartingLandform.disc_distance's radius at each angle).
static func _outline(
	doc: MapDocument, at: Vector2, radius: float, noise: FastNoiseLite, warp: float
) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in POND_POINTS:
		var dir := Vector2.RIGHT.rotated(TAU * k / POND_POINTS)
		var r := radius + StartingLandform.disc_distance(at + dir * radius, at, radius, noise, warp)
		out.append(StartingLandform.clamped(doc, at + dir * r, 0.0))
	return out


## A dry wash as one paint coat of its surface (card terraform-p2-paint-path: the surface table's
## index) along its line: capsule dabs out to the recipe's soft edge, exposed WASH_SECONDS so the
## core reads as full cover. False without a surface or a free table entry.
static func _wash(terra: TerraDoc, _doc: MapDocument, hint: Dictionary) -> bool:
	var surface := String(hint.get("surface", ""))
	var line: PackedVector2Array = hint.get("line", PackedVector2Array())
	if surface == "" or line.size() < 2:
		return false
	var index := terra.surfaces.find(surface)
	if index < 0:
		if terra.surfaces.size() >= TerraDoc.MAX_SURFACES:
			return false
		terra.surfaces.append(surface)
		index = terra.surfaces.size() - 1
	var radius := float(hint.width) * 0.5 + WASH_SOFT_M
	var dabs := PackedFloat32Array([index])
	var total := 0.0
	for k in line.size() - 1:
		total += line[k].distance_to(line[k + 1])
	var steps := maxi(1, ceili(total / maxf(radius * WASH_STEP_SHARE, 0.25)))
	var last: Vector2 = StartingLandform.along(line, 0.0).point
	for n in range(1, steps + 1):
		var p: Vector2 = StartingLandform.along(line, total * n / steps).point
		dabs.append_array([last.x, last.y, p.x, p.y, radius, WASH_SECONDS])
		last = p
	terra.add(TerraCore.PAINT, dabs)
	return true


## The recipe's carved water as primitives: each run of joined river reaches one river (its
## widest half width, its depth class), each recipe pond is already a hint (the lake, a tarn).
static func _add_water(terra: TerraDoc, doc: MapDocument, made: PackedStringArray) -> void:
	var chains: Array = []
	for body: WaterBody in doc.water_bodies:
		if not body.is_river() or body.points.size() < 2:
			continue
		var last: Array = chains[-1] if not chains.is_empty() else []
		if not last.is_empty() and last[-1].points[-1].distance_to(body.points[0]) < 0.05:
			last.append(body)
		else:
			chains.append([body])
	for chain: Array in chains:
		var points := PackedVector2Array()
		var half_width := 0.0
		for body: WaterBody in chain:
			for i in body.points.size():
				if not points.is_empty() and i == 0:
					continue
				points.append(body.points[i])
			for w in body.half_widths:
				half_width = maxf(half_width, w)
		var end := points[-1]
		if StartingLandform.inside(doc, end, RIVER_END_INSIDE_M):
			points.append(end + (end - points[-2]).normalized() * RIVER_REACH_M)
		var data := PackedFloat32Array([half_width * 2.0, chain[0].depth_m()])
		for p in points:
			data.append_array([p.x, p.y])
		terra.add(TerraCore.RIVER, data)
		made.append("river")


## The axis from arc `s0` - `radius` to `s1` + `radius` in capsules of `step`, those reaching
## the map: [{"a", "b", "dir", "along" (0 at s0, 1 at s1, clamped)}].
static func _segments(
	doc: MapDocument, axis: PackedVector2Array, s0: float, s1: float, radius: float, step: float
) -> Array:
	var out: Array = []
	var from := s0 - radius
	var steps := maxi(1, ceili((s1 - s0 + 2.0 * radius) / step))
	var span := (s1 - s0 + 2.0 * radius) / steps
	for n in steps:
		var sa := from + span * n
		var at: Dictionary = StartingLandform.along(axis, sa)
		var a: Vector2 = at.point
		var b: Vector2 = StartingLandform.along(axis, sa + span).point
		if not StartingLandform.inside(doc, a, -radius) and not StartingLandform.inside(doc, b, -radius):
			continue
		var mid := sa + span * 0.5
		out.append(
			{"a": a, "b": b, "dir": at.dir, "along": clampf((mid - s0) / maxf(s1 - s0, 1e-3), 0.0, 1.0)}
		)
	return out


## Places a crossing the recipe made again on the derived water: an arch on its anchors
## (span_crossing), any other across the water at its middle (place_crossing), then at the
## nearest river points when that is refused. The made line: the kind's name, or "<kind>
## refused".
static func _place_again(doc: MapDocument, crossing: Crossing) -> String:
	var name: String = Crossing.KIND_NAMES[crossing.kind]
	if crossing.kind == Crossing.Kind.ARCH:
		var spanned := StartingLandform.span_crossing(
			doc, crossing.start, crossing.end, crossing.kind, crossing.style
		)
		return name if spanned.crossing != null else name + " refused"
	var mid := (crossing.start + crossing.end) * 0.5
	var u := (crossing.end - crossing.start).normalized()
	var dir := Vector2(u.y, -u.x)
	var tries: Array = [[mid, dir]]
	var near: Array = []
	for body: WaterBody in doc.water_bodies:
		if not body.is_river():
			continue
		for i in range(1, body.points.size() - 1):
			if body.points[i].distance_to(mid) <= CROSSING_SEARCH_M:
				near.append([body.points[i], (body.points[i + 1] - body.points[i - 1]).normalized()])
	near.sort_custom(
		func(a: Array, b: Array) -> bool: return a[0].distance_to(mid) < b[0].distance_to(mid)
	)
	tries.append_array(near.slice(0, CROSSING_TRIES))
	for t: Array in tries:
		var placed := StartingLandform.place_crossing(doc, t[0], t[1], crossing.kind, crossing.style)
		if placed.crossing != null:
			return name
	return name + " refused"
