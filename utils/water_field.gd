class_name WaterField
extends RefCounted

## The water of a map document as ONE set of per-sample fields (the production form of the
## painter-water-field-spike's A1 "field surface"; the spike's drape, membrane and ballistic arc
## are gone: the arc lies under the carved face on every fall, and the carve is the curtain).
## Nothing draws from it yet: the old water path (WaterMeshBuilder, the fall meshes) still does.
##
## The model. Every sample of the document's grid gets a water surface height `w` (DRY where no
## body's area holds it). A river stroke (RiverProfile.strokes) gives each sample within its area
## (half-width, narrowed at a tapered head, plus WaterGeometry.RIVER_BANK_M) the profile's bank
## level at the sample's arc (RiverProfile.at: flat over a reach, eased over a riffle, stepping
## down a fall's face with the carve); a pond gives its mask its level; where samples overlap the
## highest wins, so there is no ownership rule beyond max, and a level change between two bodies
## is a slope of the one surface. A river's water that its carve does not hold (a bank sample
## beyond the channel, or a sample over a lower pond) is `spill`: it stands at most a slope above
## its neighbours (_spill_pass), steeply on a bank and gently into a pond. A bank sample standing
## over its ground by more than BANK_HOLD_M is not water the bank holds and stays dry. A run of
## undermined stations no longer than WaterFieldStroke.BRIDGE_M keeps the level (a dip the water
## bridges); a longer one is a thin film (FILM_M) over the dug bed, and an event.
##
## Derived per sample: `depth` (w - ground), `energy` (white water: along each stroke from its
## falls and the slope of its level, carried downstream and faded toward the channel's edge, and
## the surface's own slope), `steep` (the surface slope as a 0..1 curtain share) and `shore`
## (the signed horizontal distance to the waterline, positive in the water, from the zero
## contour of depth interpolated along grid edges and clamped at SHORE_FAR).
##
## Edits. update() rebuilds a dirty rect, and a full build is update() of the whole grid, so the
## two cannot differ in what they compute. Every stage is a function of a bounded neighbourhood,
## which is what makes an incremental result bit-identical to a full one (test_water_field):
## strokes and ponds per sample; spill as the unique greatest fixpoint under its caps (so
## independent of the order it is relaxed in, and recomputed over the connected spill samples that
## touch the rect); depth, the buried outer rings, slopes and energy within RING_MARGIN of what
## changed; shore from the exact distance transform of the boundary samples (DistanceField)
## within SHORE_MARGIN of that. Needs a sample step that is a power of two (0.25 m is): the
## transform's tie-breaks are then exact in any window.
##
## Inconsistencies are data, not fixes: `events` lists what the surface shows that the map's
## author should decide (see its doc), and `spill` and `calm` stay readable per sample. The field
## never connects water the map leaves apart.

## Below the ground, where the mesh's outer ring ends (always buried).
const TUCK_M := 0.1
## A river into a lower pond: the surface falls this many metres per metre into the pond's mask.
const INFLOW_SLOPE := 0.3
## How much of the foot and riffle white is lost at the channel's edge (a mid-channel tongue).
const LATERAL_FADE := 0.55
## Spill flags and slopes (_spill_pass): a bank drains steeply, a river over a lower pond ramps.
const SPILL_BANK := 1
const SPILL_POND := 2
const BANK_SPILL_SLOPE := 1.2
## A bank sample (beyond the channel) standing more than this over its own ground is not water
## the bank holds (beside a lip, over the face): it stays dry, so no ledge stands out sideways.
const BANK_HOLD_M := 0.3
## The share of its white a river keeps on its ramp into a lower pond (main's ponds are calmer).
const RAMP_KEEP := 0.2
## Water thinner than this beside a spill sample is a wet slope, not a curtain.
const RAMP_FLAT_M := 0.3
## The surface slope that starts and fills the curtain share: a fall's face, not a riffle step.
const STEEP := Vector2(1.2, 2.8)
## The surface slope that makes white water on its own (inflow ramps, spills).
const SLOPE_WHITE := Vector2(0.12, 0.45)
## How far (m) the shore distance is propagated; beyond it reads as this.
const SHORE_FAR := 4.0
## Undermined water beyond the bridge: a film this deep over the dug ground, within the channel.
const FILM_M := 0.03
## Samples around what changed that depth, the rings and the slopes are redone: the rings reach
## two samples out and a slope one more.
const RING_MARGIN := 3
## Samples around those that the shore is redone (SHORE_FAR in samples, one for the boundary
## sample's offset from its seed, one spare), and again that far for the transform's window.
const SHORE_MARGIN := 18
## How far past a stroke's own area an edit can change the field: a tapered end and a bridged
## run depend on the ground and the water around them (rect_of_bodies()).
const INFLUENCE_M := 3.0
## An open stroke end with other water within END_NEAR_M standing at least LEVEL_GAP_M above or
## below the stroke's level is an event (&"end_near_water"): a stream head the map leaves short
## of a pond it would fall into.
const END_NEAR_M := 2.0
const LEVEL_GAP_M := 0.3

## Exact waterline (field-resolution spike F1, ported by the foot-2 spike): the first buried ring
## stands at the surface's own level extended over the ground (not TUCK_M under it) unless the
## ground is lower, where it keeps EDGE_MIN under it, so the waterline is where the extended
## surface meets the terrain's own triangles; `shore` is then the exact distance to that contour
## (marching triangles, WaterFieldContour) within EXACT_M, the distance to its crossing points
## beyond.
const EDGE_MIN := 0.02
const EXACT_M := 0.75

## Shade spike: how much a metre of drop counts in the flow coordinate (below 1 a fall's patterns
## stretch and run faster than the reach's), and the marker of a sample no stroke wrote.
const FLOW_DROP_K := 0.5
const NO_FLOW_U := -1.0e6

const _NEIGHBOURS: Array[Vector2i] = [
	Vector2i(-1, -1),
	Vector2i(0, -1),
	Vector2i(1, -1),
	Vector2i(-1, 0),
	Vector2i(1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
	Vector2i(1, 1),
]

## Switch (a probe's A/B): the exact waterline on, or the stage-two shore; a field is built after a
## change.
static var exact_shore := true

var size := Vector2i.ZERO
var step := Vector2.ONE
## XZ of sample (0, 0).
var origin := Vector2.ZERO
var ground := PackedFloat32Array()
## The surface height per sample, WaterGeometry.DRY where dry; the outer two rings around the
## water stand buried (under the ground) so a mesh has somewhere to end.
var w := PackedFloat32Array()
## The surface as the mesh draws it: w, except on the first buried ring, which stands at the
## neighbouring surface extended (see EDGE_MIN); DRY where w is.
var ew := PackedFloat32Array()
## w - ground where there is water (negative on the buried rings), -INF where dry.
var depth := PackedFloat32Array()
## White water, 0..1.
var energy := PackedFloat32Array()
## The surface slope as a 0..1 curtain share.
var steep := PackedFloat32Array()
## The signed distance to the waterline in metres, positive in the water, at most SHORE_FAR.
var shore := PackedFloat32Array()
## The signed lateral coordinate of a river sample: the distance across the owning stroke's course
## in metres, the same side positive along the whole stroke (cross(tangent, sample - centre)), 0 on
## any sample no stroke wrote. It rides CUSTOM1.x of the mesh (the slot the old river share held,
## which the shader never read; the native mesh builder still names its array "river"). With the
## arc `flow_u` it is the stroke's own frame, so the white's columns run along the stream: a
## direction taken per fragment (the flow map's) turned dot(p, across) into arches (card
## painter-water-curl).
var lateral := PackedFloat32Array()
## SPILL_BANK or SPILL_POND where a river's water is not held by its own carve.
var spill := PackedByteArray()
## 1 where a slope of the surface is not white water (a bank's drain, an undermined film).
var calm := PackedByteArray()
## The id of the body whose level the sample holds (a pond's, or a stroke's first reach's), 0 dry.
var owner := PackedInt32Array()
## The drop-aware flow coordinate of a river sample (shade spike): the stroke's arc length to the
## sample plus FLOW_DROP_K times the drop of its level since the stroke's head, so a pattern that
## travels in this coordinate stretches down a fall with no seam at the lip (NO_FLOW_U elsewhere).
var flow_u := PackedFloat32Array()
## The foot coordinate of a river sample (foot spike): the signed arc distance to the nearest
## fall's foot (negative on the face, positive in the plunge pool; WaterFieldStroke.NO_FOOT
## beyond 4 m, on any sample no stroke wrote and at a seam, WaterFieldStroke.foot_seams()).
var foot := PackedFloat32Array()
## The continuous marks the shader reads per vertex: film, bank share, mouth distance.
var marks := WaterFieldMarks.new()
## What the map shows that its author should decide, sorted by (kind, body, position):
## {"kind": &"film_run", "body", "pos", "length"} a stretch of a stroke longer than the bridge
## whose ground no longer holds its water; {"kind": &"bridged_run", ...} the same, short enough
## that the water bridges it (information); {"kind": &"end_near_water", "body", "pos",
## "other_body", "gap_m", "level_gap"} an open stroke end near other water at another level.
var events: Array[Dictionary] = []
## Milliseconds by part of the last update().
var timings := {}

## The stroke and pond levels before the spill (max over bodies), and the stroke energy.
var _raw := PackedFloat32Array()
var _stroke_energy := PackedFloat32Array()
## The foot coordinate as the strokes wrote it, seams included (`foot` is made from it).
var _foot_raw := PackedFloat32Array()
## The areas of the strokes with a fall that the last update wrote (foot_seams() looks there).
var _foot_rects: Array[Rect2i] = []
## The surface after the spill, before the buried rings.
var _base := PackedFloat32Array()
## Each stroke's WaterFieldStroke.table with the inputs it was made from (_table_of), by the
## stroke's first body id.
var _tables := {}


## The field of `doc` (a full build: update() of the whole grid).
static func build(doc: MapDocument) -> WaterField:
	var f := WaterField.new()
	f.update(doc, Rect2i(Vector2i.ZERO, Vector2i(doc.samples_x(), doc.samples_z())))
	return f


## Redoes the field inside `dirty` (sample coordinates; a rect_of_bodies() of the changed bodies
## before and after the edit, or of a ground edit) and whatever its changes reach, from `doc`
## as it is now. Samples outside `dirty` are taken as unchanged inputs. Returns the sample rect
## whose outputs may have changed (empty when nothing was done), for a mesh to refresh.
func update(doc: MapDocument, dirty: Rect2i) -> Rect2i:
	var t0 := Time.get_ticks_usec()
	var rect := dirty
	if _fit(doc):
		rect = Rect2i(Vector2i.ZERO, size)
	rect = _clip(rect)
	if not rect.has_area():
		return Rect2i()
	var was := spill.duplicate()
	_reset(doc, rect)
	var pond_level := {}
	for body in doc.water_bodies:
		if not body.is_river():
			pond_level[body.id] = body.level_m
	_write_ponds(doc, rect, pond_level)
	var ends: Array[Dictionary] = []
	var runs: Array[Dictionary] = []
	_write_strokes(doc, rect, pond_level, ends, runs)
	foot = WaterFieldNative.foot_seams(self, _clip(rect.grow(1)))
	var t1 := Time.get_ticks_usec()
	var changed := _spill_pass(rect, was)
	var t2 := Time.get_ticks_usec()
	var inner := _clip(changed.grow(RING_MARGIN))
	_derive(inner)
	var t3 := Time.get_ticks_usec()
	var outer := _clip(inner.grow(SHORE_MARGIN))
	_shore(outer)
	var t4 := Time.get_ticks_usec()
	_set_events(rect, runs, ends)
	timings = {
		"bodies": (t1 - t0) / 1000.0,
		"spill": (t2 - t1) / 1000.0,
		"derive": (t3 - t2) / 1000.0,
		"shore": (t4 - t3) / 1000.0,
		"total": (Time.get_ticks_usec() - t0) / 1000.0,
	}
	return outer


## The sample rect an edit of `bodies` can change: their areas grown by INFLUENCE_M. A river's
## area is its whole stroke's (every reach chained to it in `doc`: the stroke's arc, taper and
## tables depend on all of them), each reach's course bounds grown by its widest half-width and
## the bank; a pond's is the bounds of its mask in `doc`. An edit's dirty rect is the union of
## this for the bodies as they were (asked of the document before the edit) and as they are
## (after it).
static func rect_of_bodies(doc: MapDocument, bodies: Array[WaterBody]) -> Rect2i:
	var box := Rect2()
	var any := false
	var spacing := doc.sample_step()
	var corner := -doc.extent_m() * 0.5
	var ids := {}
	for body in bodies:
		ids[body.id] = true
	var wanted: Array[WaterBody] = bodies.duplicate()
	for chain in RiverProfile.strokes(doc.water_bodies):
		var hit := false
		for reach: WaterBody in chain:
			hit = hit or ids.has(reach.id)
		if hit:
			wanted.append_array(chain)
	for body in wanted:
		var area := Rect2()
		if body.is_river():
			if body.points.is_empty():
				continue
			var widest := 0.0
			for hw in body.half_widths:
				widest = maxf(widest, hw)
			area = WaterGeometry.bounds(body.points, widest + WaterGeometry.RIVER_BANK_M)
		else:
			var cells := _mask_bounds(doc, body.id)
			if not cells.has_area():
				continue
			area = Rect2(corner + Vector2(cells.position) * spacing, Vector2(cells.size) * spacing)
		box = area if not any else box.merge(area)
		any = true
	if not any:
		return Rect2i()
	box = box.grow(INFLUENCE_M)
	var low := ((box.position - corner) / spacing).floor()
	var high := ((box.end - corner) / spacing).ceil()
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	return Rect2i(Vector2i(low), Vector2i(high) - Vector2i(low) + Vector2i.ONE).intersection(
		Rect2i(Vector2i.ZERO, grid)
	)


## The index of the sample nearest XZ `p`, -1 outside the grid.
func index_of(p: Vector2) -> int:
	var c := ((p - origin) / step).round()
	if c.x < 0.0 or c.y < 0.0 or c.x >= size.x or c.y >= size.y:
		return -1
	return int(c.y) * size.x + int(c.x)


## A false-colour image of the field for a debug view (a probe saves it as a PNG): ground in
## browns, water in blues by depth, tinted violet by steepness, whitened by energy and along the
## shore.
func debug_image() -> Image:
	var img := Image.create(maxi(size.x, 1), maxi(size.y, 1), false, Image.FORMAT_RGB8)
	for z in size.y:
		for x in size.x:
			var i := z * size.x + x
			var g := clampf((ground[i] + 3.0) / 8.0, 0.0, 1.0)
			var c := Color(g * 0.6, g * 0.55, g * 0.45)
			if depth[i] > 0.0:
				var d := clampf(depth[i] / 1.5, 0.0, 1.0)
				c = Color(0.2 * (1.0 - d), 0.5 + 0.3 * (1.0 - d), 0.6 + 0.4 * d)
				c = c.lerp(Color(0.6, 0.35, 0.8), steep[i] * 0.6)
				c = c.lerp(Color.WHITE, clampf(energy[i], 0.0, 1.0) * 0.7)
				if shore[i] < 0.2:
					c = c.lerp(Color.WHITE, 0.35)
			img.set_pixel(x, z, c)
	return img


## The bounds in samples of pond `id`'s mask (an empty rect when it has none).
static func _mask_bounds(doc: MapDocument, id: int) -> Rect2i:
	var mask := doc.pond_mask
	var sx := doc.samples_x()
	if mask.size() != doc.sample_count():
		return Rect2i()
	var lo := Vector2i(sx, doc.samples_z())
	var hi := Vector2i(-1, -1)
	for i in mask.size():
		if mask[i] != id:
			continue
		var x := i % sx
		var z := i / sx
		lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
		hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
	if hi.x < 0:
		return Rect2i()
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _clip(r: Rect2i) -> Rect2i:
	return r.intersection(Rect2i(Vector2i.ZERO, size))


static func _zeros(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	return out


## Sizes every array to `doc`'s grid when it changed (a first build or a resized map); true then.
func _fit(doc: MapDocument) -> bool:
	var grid := Vector2i(doc.samples_x(), doc.samples_z())
	if grid == size and w.size() == grid.x * grid.y:
		return false
	size = grid
	step = doc.sample_step()
	origin = -doc.extent_m() * 0.5
	var n := size.x * size.y
	ground = _zeros(n)
	w = _zeros(n)
	w.fill(WaterGeometry.DRY)
	ew = _zeros(n)
	ew.fill(WaterGeometry.DRY)
	depth = _zeros(n)
	depth.fill(-INF)
	energy = _zeros(n)
	steep = _zeros(n)
	shore = _zeros(n)
	lateral = _zeros(n)
	_raw = _zeros(n)
	_stroke_energy = _zeros(n)
	_base = _zeros(n)
	spill.resize(n)
	spill.fill(0)
	calm.resize(n)
	calm.fill(0)
	owner.resize(n)
	owner.fill(0)
	flow_u = _zeros(n)
	flow_u.fill(NO_FLOW_U)
	foot = _zeros(n)
	foot.fill(WaterFieldStroke.NO_FOOT)
	_foot_raw = foot.duplicate()
	marks.fit(n)
	events = []
	return true


## Clears the stage-one inputs in `rect` and reloads its ground from `doc`.
func _reset(doc: MapDocument, rect: Rect2i) -> void:
	var n := size.x * size.y
	var heights := doc.heights
	var has_heights := heights.size() == n
	marks.reset(self, rect)
	if rect == Rect2i(Vector2i.ZERO, size):
		# The whole grid (a build): bulk fills, no per-sample loop.
		ground = heights.duplicate() if has_heights else _zeros(n)
		_raw.fill(WaterGeometry.DRY)
		_stroke_energy.fill(0.0)
		lateral.fill(0.0)
		spill.fill(0)
		calm.fill(0)
		owner.fill(0)
		flow_u.fill(NO_FLOW_U)
		_foot_raw.fill(WaterFieldStroke.NO_FOOT)
		return
	for z in range(rect.position.y, rect.end.y):
		var row := z * size.x
		for i in range(row + rect.position.x, row + rect.end.x):
			ground[i] = heights[i] if has_heights else 0.0
			_raw[i] = WaterGeometry.DRY
			_stroke_energy[i] = 0.0
			lateral[i] = 0.0
			spill[i] = 0
			calm[i] = 0
			owner[i] = 0
			flow_u[i] = NO_FLOW_U
			_foot_raw[i] = WaterFieldStroke.NO_FOOT


## Ponds: each sample of a pond's mask in `rect` holds its level.
func _write_ponds(doc: MapDocument, rect: Rect2i, pond_level: Dictionary) -> void:
	var mask := doc.pond_mask
	if mask.size() != size.x * size.y or pond_level.is_empty():
		return
	for z in range(rect.position.y, rect.end.y):
		var row := z * size.x
		for i in range(row + rect.position.x, row + rect.end.x):
			var id := mask[i]
			if id != 0 and pond_level.has(id):
				_raw[i] = float(pond_level[id])
				owner[i] = id


## River strokes: each stroke whose area meets `rect` writes its samples there (max with what is
## there), and adds its end candidates to `ends` and its runs' events to `runs`.
func _write_strokes(
	doc: MapDocument,
	rect: Rect2i,
	pond_level: Dictionary,
	ends: Array[Dictionary],
	runs: Array[Dictionary]
) -> void:
	var rect_m := Rect2(origin + Vector2(rect.position) * step, Vector2(rect.size) * step).grow(1.0)
	var chains := RiverProfile.strokes(doc.water_bodies)
	_foot_rects.clear()
	if _tables.size() > chains.size():
		# Strokes that are gone (or whose first reach changed) leave their tables behind.
		var alive := {}
		for chain in chains:
			alive[chain[0].id] = true
		for id: Variant in _tables.keys():
			if not alive.has(id):
				_tables.erase(id)
	for chain in chains:
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		if not _chain_may_meet(typed, rect_m):
			continue
		var profile := RiverProfile.for_doc(doc, typed)
		if profile.points.size() < 2:
			continue
		var field := profile.field(doc, WaterGeometry.RIVER_BANK_M, rect)
		var area: Rect2i = field.rect
		if not area.has_area():
			continue
		if not profile.falls.is_empty():
			_foot_rects.append(area)
		var stations := profile.stations(doc, WaterFieldStroke.STATION_STEP)
		var found := WaterFieldStroke.runs(stations.undermined)
		var lost := WaterFieldStroke.without_bridged(stations.undermined, found)
		runs.append_array(WaterFieldStroke.run_events(typed[0].id, found, stations.centre))
		runs.append_array(WaterFieldStroke.climb_events(typed))
		if profile.taper.x == 1:
			ends.append({"body": typed[0].id, "pos": profile.points[0], "level": profile.at(0.0).x})
		if profile.taper.y == 1:
			ends.append(
				{"body": typed[0].id, "pos": profile.points[-1], "level": profile.at(profile.total).x}
			)
		var table := _table_of(profile, typed)
		_put_stroke(doc, typed[0].id, profile, table, lost, field, pond_level)


## False when the stroke `chain` (its reaches) cannot reach `rect_m` (a window in metres): the
## bounds of its control points, which hold its smoothed course, grown by its widest half-width,
## the bank and a metre, miss it. Conservative, so skipping such a stroke changes nothing (the
## profile and the raster it would have built come out empty over the rect).
func _chain_may_meet(chain: Array[WaterBody], rect_m: Rect2) -> bool:
	var box := Rect2()
	var any := false
	var widest := 0.0
	for body in chain:
		if body.points.is_empty():
			continue
		for hw in body.half_widths:
			widest = maxf(widest, hw)
		var part := WaterGeometry.bounds(body.points, 0.0)
		box = part if not any else box.merge(part)
		any = true
	if not any:
		return false
	return box.grow(widest + WaterGeometry.RIVER_BANK_M + 1.0).intersects(rect_m, true)


## WaterFieldStroke.table of `profile`, kept from the last update while its inputs (the profile's
## shape with its chutes, the reaches' speeds and the first reach's id, which places the chutes'
## white) are unchanged: an edit elsewhere never redoes a stroke's table.
func _table_of(profile: RiverProfile, chain: Array[WaterBody]) -> Dictionary:
	var speeds := PackedFloat32Array()
	for body in chain:
		speeds.append(body.speed)
	var key: Array = [
		profile.levels,
		profile.bounds,
		profile.flags,
		profile.arc,
		profile.depth,
		profile.taper,
		profile.run_off,
		speeds,
		profile.chute_runs,
	]
	var id := chain[0].id
	var kept: Variant = _tables.get(id)
	if kept != null and kept.key == key:
		return kept.table
	var table := WaterFieldStroke.table(profile, chain)
	_tables[id] = {"key": key, "table": table}
	return table


## Writes one stroke's surface into the arrays over `field.rect` (see the header).
func _put_stroke(
	doc: MapDocument,
	id: int,
	profile: RiverProfile,
	table: Dictionary,
	lost: PackedByteArray,
	field: Dictionary,
	pond_level: Dictionary
) -> void:
	var lev: PackedFloat32Array = table.level
	var en: PackedFloat32Array = table.energy
	var core: PackedFloat32Array = table.core
	var foot_t: PackedFloat32Array = table.foot
	var rect: Rect2i = field.rect
	var dist: PackedFloat32Array = field.distance
	var along: PackedFloat32Array = field.along
	var hws: PackedFloat32Array = field.half_width
	var mask := doc.pond_mask
	var has_mask := mask.size() == size.x * size.y
	var bank := WaterGeometry.RIVER_BANK_M
	var film := marks.film
	var bank_share := marks.bank
	for j in rect.size.y:
		for i in rect.size.x:
			var k := j * rect.size.x + i
			var d := dist[k]
			if d == INF:
				continue
			var s := along[k]
			var hw := profile.head(s, hws[k])
			if d > hw + bank:
				continue
			var at := (rect.position.y + j) * size.x + rect.position.x + i
			var ti := clampi(int(round(s / WaterFieldStroke.TABLE_STEP)), 0, lev.size() - 1)
			var level := lev[ti]
			var flow_coord := s + FLOW_DROP_K * (lev[0] - level)
			# The foot foam and the riffle white gather mid-channel (a tongue), the brink and the
			# curtain span it.
			var mid := 1.0 - LATERAL_FADE * smoothstep(0.2, 1.0, d / maxf(hw, 0.1))
			var e := maxf(core[ti], en[ti] * mid)
			var si := clampi(
				int(round(s / WaterFieldStroke.STATION_STEP)), 0, lost.size() - 1
			)
			var undermined := not lost.is_empty() and lost[si] != 0
			if undermined:
				# The ground no longer holds this stretch: a film over the dug bed, in the channel.
				if d > hw:
					continue
				level = minf(level, ground[at] + FILM_M)
			if level > _raw[at]:
				# Outside the channel, or over a lower pond, the river's water is not held by its
				# own carve: it spills (_spill_pass).
				var over_pond := (
					has_mask
					and mask[at] != 0
					and float(pond_level.get(mask[at], level)) < level
				)
				if d > hw and not over_pond and level - ground[at] > BANK_HOLD_M:
					continue
				spill[at] = SPILL_POND if over_pond else (SPILL_BANK if d > hw else 0)
				calm[at] = 1 if undermined or (d > hw and not over_pond) else 0
				film[at] = 1.0 if undermined and not over_pond else 0.0
				var out := (d - hw) / WaterFieldMarks.BANK_SHARE_M
				bank_share[at] = clampf(out, 0.0, 1.0) if spill[at] == SPILL_BANK else 0.0
				_raw[at] = level
				flow_u[at] = flow_coord
				lateral[at] = _lateral_of(
					profile, s, d, origin + Vector2(rect.position.x + i, rect.position.y + j) * step
				)
				_foot_raw[at] = foot_t[ti]
				owner[at] = id
				_stroke_energy[at] = maxf(_stroke_energy[at], 0.0 if undermined else e)
			elif (
				has_mask
				and mask[at] != 0
				and not undermined
				and _foot_raw[at] > WaterFieldStroke.NO_FOOT * 0.5
			):
				# A fall that lands in a pond: the pond holds the level (the stroke does not win the
				# sample), but the foot coordinate runs on across its cells, so the plunge's rules
				# (the veil, the pool's floor) reach the pond as they reach a pool of the stream.
				_foot_raw[at] = foot_t[ti]


## The signed lateral coordinate of the sample at `p`, `d` from the course and `s` along it: `d`
## with the sign of cross(segment, p - segment start) on the segment `s` falls on, so the same
## side is positive along the whole stroke and the coordinate is continuous through a bend (it
## only changes sign across the centre line).
func _lateral_of(profile: RiverProfile, s: float, d: float, p: Vector2) -> float:
	var points := profile.points
	var k := clampi(profile.arc.bsearch(s) - 1, 0, points.size() - 2)
	var a := points[k]
	return -d if (points[k + 1] - a).cross(p - a) < 0.0 else d


## The spill rule. Resets the surface to the raw levels over `rect` and the spill samples
## connected (8-neighbour, by old or new flag) to samples in or touching it, then relaxes those:
## a spill sample stands at most `slope` per metre above any neighbour's surface (a sample
## outside every area counts as its ground less TUCK_M), so a river ends in a lower pond on a
## ramp, a low bank lets the water run off it, and nothing stands flat in the air at an area's
## edge. The result is the greatest surface under those caps, which does not depend on the order
## of relaxing. Returns the bounds of the samples that may have changed.
func _spill_pass(rect: Rect2i, was: PackedByteArray) -> Rect2i:
	var native := WaterFieldNative.instance()
	if native != null:
		return WaterFieldNative.spill(native, self, rect, was)
	var width := size.x
	var n := width * size.y
	for z in range(rect.position.y, rect.end.y):
		var row := z * width
		for i in range(row + rect.position.x, row + rect.end.x):
			_base[i] = _raw[i]
	var seen := PackedByteArray()
	seen.resize(n)
	var closure := PackedInt32Array()
	var ring := _clip(rect.grow(1))
	for z in range(ring.position.y, ring.end.y):
		var row := z * width
		for i in range(row + ring.position.x, row + ring.end.x):
			if (spill[i] != 0 or was[i] != 0) and seen[i] == 0:
				seen[i] = 1
				closure.append(i)
	var lo := rect.position
	var hi := rect.end - Vector2i.ONE
	var head := 0
	while head < closure.size():
		var i := closure[head]
		head += 1
		var x := i % width
		var z := i / width
		lo = Vector2i(mini(lo.x, x), mini(lo.y, z))
		hi = Vector2i(maxi(hi.x, x), maxi(hi.y, z))
		for o in _NEIGHBOURS:
			var xx := x + o.x
			var zz := z + o.y
			if xx < 0 or zz < 0 or xx >= width or zz >= size.y:
				continue
			var j := zz * width + xx
			if seen[j] == 0 and (spill[j] != 0 or was[j] != 0):
				seen[j] = 1
				closure.append(j)
	var queue := PackedInt32Array()
	for i in closure:
		_base[i] = _raw[i]
		if spill[i] != 0:
			queue.append(i)
	var queued := PackedByteArray()
	queued.resize(n)
	for i in queue:
		queued[i] = 1
	var diag := step.length()
	var qh := 0
	while qh < queue.size():
		var i := queue[qh]
		qh += 1
		queued[i] = 0
		var x := i % width
		var z := i / width
		var slope := BANK_SPILL_SLOPE if spill[i] == SPILL_BANK else INFLOW_SLOPE
		var cap: float = _base[i]
		for o in _NEIGHBOURS:
			var xx := x + o.x
			var zz := z + o.y
			if xx < 0 or zz < 0 or xx >= width or zz >= size.y:
				continue
			var j := zz * width + xx
			var h := _base[j]
			if h == WaterGeometry.DRY:
				h = ground[j] - TUCK_M
			var run := diag if o.x != 0 and o.y != 0 else (step.x if o.x != 0 else step.y)
			cap = minf(cap, h + slope * run)
		var old := _base[i]
		_base[i] = cap
		if _base[i] < old:
			for o in _NEIGHBOURS:
				var xx := x + o.x
				var zz := z + o.y
				if xx < 0 or zz < 0 or xx >= width or zz >= size.y:
					continue
				var j := zz * width + xx
				if spill[j] != 0 and queued[j] == 0:
					queued[j] = 1
					queue.append(j)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


## Over `inner`: the buried rings, depth, the curtain share and the energy. Two rings outside
## every area stand at the nearest neighbour's surface but under the ground, so a mesh ends
## buried.
func _derive(inner: Rect2i) -> void:
	var native := WaterFieldNative.instance()
	if native != null:
		WaterFieldNative.derive(native, self, inner)
		return
	var dry := WaterGeometry.DRY
	var reach := _clip(inner.grow(1))
	var wide := _clip(reach.grow(1))
	var first := _ring(_cut(_base, wide), wide, reach)
	var second := _ring(first, reach, inner)
	var iw := inner.size.x
	for z in inner.size.y:
		var row := (inner.position.y + z) * size.x + inner.position.x
		for x in iw:
			var i := row + x
			var v := second[z * iw + x]
			w[i] = v
			depth[i] = v - ground[i] if v != dry else -INF
			steep[i] = 0.0
			energy[i] = _stroke_energy[i]
			ew[i] = _edge_surface(i, inner.position.x + x, inner.position.y + z, v)
	for z in range(inner.position.y, inner.end.y):
		for x in range(inner.position.x, inner.end.x):
			var i := z * size.x + x
			if depth[i] <= 0.0:
				continue
			var gx := _slope_axis(i, x, 1, size.x) / step.x
			var gz := _slope_axis(i, z, size.x, size.y) / step.y
			var sl := sqrt(gx * gx + gz * gz)
			steep[i] = smoothstep(STEEP.x, STEEP.y, sl)
			if calm[i] == 0:
				energy[i] = maxf(energy[i], smoothstep(SLOPE_WHITE.x, SLOPE_WHITE.y, sl) * 0.6)
			if _spill_near(x, z, 2, SPILL_POND):
				# A river's ramp into a lower pond is a slope of the pond, not a fall: a fifth of the
				# white on it and on the two samples round it, so the edge of the ramp is not a ring
				# of white pills round its calm middle (round 1: whole-cell white rectangles).
				energy[i] *= RAMP_KEEP
			if spill[i] != 0 or (depth[i] < RAMP_FLAT_M and _spill_near(x, z, 1, 0)):
				# Thin water on a ramp or beside a bank's drain is a wet slope, never a curtain: a
				# face of the carve is a stroke's own sample (spill 0) away from any spill.
				steep[i] = 0.0


## The part of the grid-sized `src` inside `r`, row-major over `r`.
func _cut(src: PackedFloat32Array, r: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(r.size.x * r.size.y)
	for z in r.size.y:
		var row := (r.position.y + z) * size.x + r.position.x
		for x in r.size.x:
			out[z * r.size.x + x] = src[row + x]
	return out


## One buried ring: `src` (over `src_rect`) restricted to `dst_rect`, each dry sample there next
## to a wet one standing at the highest neighbour's surface, but under its ground by TUCK_M.
func _ring(src: PackedFloat32Array, src_rect: Rect2i, dst_rect: Rect2i) -> PackedFloat32Array:
	var sw := src_rect.size.x
	var dw := dst_rect.size.x
	var dry := WaterGeometry.DRY
	var out := PackedFloat32Array()
	out.resize(dw * dst_rect.size.y)
	for z in dst_rect.size.y:
		var from := (z + dst_rect.position.y - src_rect.position.y) * sw
		from += dst_rect.position.x - src_rect.position.x
		for x in dw:
			out[z * dw + x] = src[from + x]
	var touched := PackedInt32Array()
	for z in src_rect.size.y:
		for x in sw:
			var v := src[z * sw + x]
			if v == dry:
				continue
			for o in _NEIGHBOURS:
				var px := x + src_rect.position.x + o.x
				var pz := z + src_rect.position.y + o.y
				if not dst_rect.has_point(Vector2i(px, pz)):
					continue
				if src[(pz - src_rect.position.y) * sw + px - src_rect.position.x] != dry:
					continue
				var li := (pz - dst_rect.position.y) * dw + px - dst_rect.position.x
				if out[li] == dry:
					touched.append(li)
				out[li] = maxf(out[li], v)
	for li in touched:
		var gi := (li / dw + dst_rect.position.y) * size.x + li % dw + dst_rect.position.x
		out[li] = minf(out[li], ground[gi] - TUCK_M)
	return out


## Whether sample (x, z) or any sample within `reach` of it (a square window) is a spill sample
## of `kind` (any kind when 0).
func _spill_near(x: int, z: int, reach: int, kind: int) -> bool:
	for dz in range(-reach, reach + 1):
		var zz := z + dz
		if zz < 0 or zz >= size.y:
			continue
		for dx in range(-reach, reach + 1):
			var xx := x + dx
			if xx < 0 or xx >= size.x:
				continue
			var s := spill[zz * size.x + xx]
			if s != 0 and (kind == 0 or s == kind):
				return true
	return false


## Half the central difference of w along one axis among wet neighbours (one-sided at an edge).
func _slope_axis(i: int, c: int, stride: int, count: int) -> float:
	var a := i - stride if c > 0 and depth[i - stride] > 0.0 else i
	var b := i + stride if c < count - 1 and depth[i + stride] > 0.0 else i
	if a == b:
		return 0.0
	var span := 2.0 if a != i and b != i else 1.0
	return (w[b] - w[a]) / span


## The signed horizontal distance to the depth's zero contour over `outer` (see the header). A
## boundary sample (an end of a grid edge the zero contour crosses) holds the nearest crossing
## on its edges; every sample takes the nearer of its own and its nearest boundary sample's
## (DistanceField), then clamps at SHORE_FAR.
func _shore(outer: Rect2i) -> void:
	var native := WaterFieldNative.instance()
	if native != null:
		WaterFieldNative.shore(native, self, outer)
		return
	var win := _clip(outer.grow(SHORE_MARGIN))
	var ww := win.size.x
	var count := ww * win.size.y
	var seeds := PackedVector2Array()
	seeds.resize(count)
	var has := PackedByteArray()
	has.resize(count)
	var best := PackedFloat32Array()
	best.resize(count)
	best.fill(INF)
	var sedge := PackedInt32Array()
	sedge.resize(count)
	var ed := PackedFloat32Array()
	ed.resize(count)
	for z in range(win.position.y, win.end.y):
		var lrow := (z - win.position.y) * ww - win.position.x
		for x in range(win.position.x, win.end.x):
			ed[lrow + x] = _edge_depth(z * size.x + x)
	for z in range(win.position.y, win.end.y):
		for x in range(win.position.x, win.end.x):
			var da := ed[(z - win.position.y) * ww + x - win.position.x]
			if da == -INF:
				continue
			for k in 2:
				var dx := 1 - k
				var dz := k
				var xx := x + dx
				var zz := z + dz
				if xx >= win.end.x or zz >= win.end.y:
					continue
				var li := (z - win.position.y) * ww + x - win.position.x
				var lj := li + dx + dz * ww
				var db := ed[lj]
				if db == -INF or (da > 0.0) == (db > 0.0):
					continue
				var t := da / (da - db)
				var p := origin + Vector2(x + dx * t, z + dz * t) * step
				var dd := (origin + Vector2(x, z) * step).distance_to(p)
				if dd < best[li]:
					best[li] = dd
					seeds[li] = p
					sedge[li] = li * 2 + k
					has[li] = 1
				dd = (origin + Vector2(xx, zz) * step).distance_to(p)
				if dd < best[lj]:
					best[lj] = dd
					seeds[lj] = p
					sedge[lj] = li * 2 + k
					has[lj] = 1
	var near: PackedInt32Array = DistanceField.transform(has, ww, win.size.y, step)["nearest"]
	var contour := {}
	if exact_shore:
		contour = WaterFieldContour.table(ed, win, has, origin, step)
	for z in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			var i := z * size.x + x
			var li := (z - win.position.y) * ww + x - win.position.x
			var q := origin + Vector2(x, z) * step
			var dd := SHORE_FAR
			if has[li] != 0:
				dd = minf(dd, q.distance_to(seeds[li]))
			var nn := near[li]
			if nn >= 0 and nn != li:
				dd = minf(dd, q.distance_to(seeds[nn]))
			if exact_shore and dd < EXACT_M + 0.12:
				if has[li] != 0:
					dd = minf(dd, WaterFieldContour.distance(q, contour, sedge[li], ww))
				if nn >= 0 and nn != li:
					dd = minf(dd, WaterFieldContour.distance(q, contour, sedge[nn], ww))
			shore[i] = dd if ed[li] > 0.0 else -dd


## The depth the waterline is taken from at sample `i`: with the exact shore, the surface as drawn
## (ew) over the ground; else the stage-two depth.
func _edge_depth(i: int) -> float:
	if not exact_shore or w[i] == WaterGeometry.DRY:
		return depth[i]
	return ew[i] - ground[i]


## The surface drawn at sample `i` (grid position (x, z), buried-ring result `v`): see `ew`.
func _edge_surface(i: int, x: int, z: int, v: float) -> float:
	var dry := WaterGeometry.DRY
	if not exact_shore or v == dry or _base[i] != dry:
		return v
	var top := -INF
	for o in _NEIGHBOURS:
		var xx := x + o.x
		var zz := z + o.y
		if xx < 0 or zz < 0 or xx >= size.x or zz >= size.y:
			continue
		var h := _base[zz * size.x + xx]
		if h != dry:
			top = maxf(top, h)
	if top == -INF:
		return v
	return minf(top, ground[i] - EDGE_MIN)


## Replaces the events inside `rect` (by the sample nearest their position) with those found
## now: `runs` (every stroke that meets the rect) and the open `ends` in it.
func _set_events(rect: Rect2i, runs: Array[Dictionary], ends: Array[Dictionary]) -> void:
	var kept: Array[Dictionary] = []
	for e in events:
		if not _in_rect(rect, e.pos):
			kept.append(e)
	for e in runs:
		if _in_rect(rect, e.pos):
			kept.append(e)
	for end in ends:
		if _in_rect(rect, end.pos):
			var found := _end_event(end)
			if not found.is_empty():
				kept.append(found)
	kept.sort_custom(_event_before)
	events = kept


func _in_rect(rect: Rect2i, pos: Vector2) -> bool:
	return rect.has_point(Vector2i(((pos - origin) / step).round()))


static func _event_before(a: Dictionary, b: Dictionary) -> bool:
	if a.kind != b.kind:
		return str(a.kind) < str(b.kind)
	if a.body != b.body:
		return int(a.body) < int(b.body)
	if a.pos.x != b.pos.x:
		return a.pos.x < b.pos.x
	return a.pos.y < b.pos.y


## The &"end_near_water" event of an open stroke `end` ({"body", "pos", "level"}), or {}.
func _end_event(end: Dictionary) -> Dictionary:
	var centre := Vector2i(((end.pos - origin) / step).round())
	var reach := int(ceil(END_NEAR_M / minf(step.x, step.y)))
	var nearest := INF
	var other := 0
	var other_level := 0.0
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var x := centre.x + dx
			var z := centre.y + dz
			if x < 0 or z < 0 or x >= size.x or z >= size.y:
				continue
			var i := z * size.x + x
			if owner[i] == 0 or owner[i] == int(end.body) or _raw[i] == WaterGeometry.DRY:
				continue
			var d := Vector2(dx * step.x, dz * step.y).length()
			if d <= END_NEAR_M and d < nearest:
				nearest = d
				other = owner[i]
				other_level = _raw[i]
	if other == 0:
		return {}
	var gap := other_level - float(end.level)
	if absf(gap) < LEVEL_GAP_M:
		return {}
	return {
		"kind": &"end_near_water",
		"body": end.body,
		"pos": end.pos,
		"other_body": other,
		"gap_m": nearest,
		"level_gap": gap,
	}
