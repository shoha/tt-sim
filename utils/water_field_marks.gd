class_name WaterFieldMarks
extends RefCounted

## The continuous marks of a WaterField (card painter-water-mouths; docs/systems/water_field.md
## "Marks and mouths"): what the Painted shader used to read from one enum per vertex (CUSTOM1.w:
## 0, film 0.125, bank spill 0.5, pond ramp 1). Interpolated across a triangle between a 0 and a
## 1 vertex that float passed through the film and bank-spill values, so every rule keyed to them
## drew a band along the border, and the lap's cut on the per-sample ramp flag left a stepped
## ring and ticks at every mouth. Here each quantity is its own channel, and a mouth is explicit:
##
## - `film` (0 or 1 per sample): a stroke's water the dug bed no longer holds (WaterField's film).
## - `bank` (0..1): the thin water a bank sheds, rising from 0 at the channel's edge to 1 over
##   BANK_SHARE_M beyond it (a function of the distance across the stroke, not of the grid).
## - `mouth` (metres, 0..MOUTH_FAR): the distance to the nearest mouth line, MOUTH_FAR where none
##   is near. A mouth line is the segment across a stroke between its two mouth corners: the
##   points where its left and its right bank line pass from land into other water (a pond's
##   mask or another stroke's channel), or out of it. A stream's mouth in a pond has one line
##   (the pond's ring opens between its ends), a crossing two per stroke that finds the other. A
##   corner with no partner on the other bank (a stream skirting a pond) is a line of no length.
##
## The corners are found analytically: the course is walked every WALK_STEP metres and, per side,
## the point CORNER_OFFSET_M outside the channel is asked whether other water stands there
## (`chan`, the id of the stroke whose channel covers a sample, -1 for several; and the
## document's pond mask); a corner lies midway between two stations that answer differently. A
## left and a right corner of the same kind (both entering or both leaving) no further apart
## than the channel is wide plus PAIR_SLACK_M make a line. Each line stamps its distance into the
## samples within MOUTH_FAR, so the channel is the exact distance to a set of segments:
## 1-Lipschitz, the same for any order of strokes and for a build and an update (an update
## clears and restamps the dirty rect grown by MOUTH_FAR plus a metre, which holds every sample
## a changed corner reaches). A stroke meeting itself (a tight bend, a self-crossing, a ring's
## closure) has no corner.
##
## They ride CUSTOM2 of the field's mesh (WaterFieldMesh), interpolated per vertex: no texture
## fetch. All of it is GDScript (the stroke's per-sample write is); the native mesh builder
## copies the three arrays in a second call, so `ttscatter`'s version did not move.

## Beyond every mouth line's reach: the value of `mouth` there.
const MOUTH_FAR := 1.25
## How far outside the channel's edge the bank line is asked for other water.
const CORNER_OFFSET_M := 0.25
## The spacing of the walk along a course.
const WALK_STEP := 0.25
## Two corners pair into a line when no further apart than the channel's width plus this.
const PAIR_SLACK_M := 2.0
## The bank share reaches 1 this far beyond the channel's edge.
const BANK_SHARE_M := 0.25

var film := PackedFloat32Array()
var bank := PackedFloat32Array()
var mouth := PackedFloat32Array()
## The first reach id of the stroke whose channel (not its bank band) covers the sample, -1 when
## several strokes' channels do, 0 when none does.
var chan := PackedInt32Array()
## The profiles WaterField built in this update, by first reach id (reused by mouths()).
var profiles := {}


## Sizes the arrays to `n` samples, cleared.
func fit(n: int) -> void:
	film.resize(n)
	bank.resize(n)
	mouth.resize(n)
	chan.resize(n)
	film.fill(0.0)
	bank.fill(0.0)
	mouth.fill(MOUTH_FAR)
	chan.fill(0)


## Clears what the strokes write (film, bank, chan) in `rect` of `f`'s grid.
func reset(f: WaterField, rect: Rect2i) -> void:
	if rect == Rect2i(Vector2i.ZERO, f.size):
		film.fill(0.0)
		bank.fill(0.0)
		chan.fill(0)
		return
	for z in range(rect.position.y, rect.end.y):
		var row := z * f.size.x
		for i in range(row + rect.position.x, row + rect.end.x):
			film[i] = 0.0
			bank[i] = 0.0
			chan[i] = 0


## The sample rect mouths() rewrites for an update of `rect`.
static func mouth_rect(f: WaterField, rect: Rect2i) -> Rect2i:
	var grow := int(ceil((MOUTH_FAR + 1.0) / minf(f.step.x, f.step.y)))
	return rect.grow(grow).intersection(Rect2i(Vector2i.ZERO, f.size))


## Rewrites `mouth` over mouth_rect(rect) from `doc`'s strokes, once every body has written
## `rect` (it reads `chan` and the pond mask as they stand).
func mouths(f: WaterField, doc: MapDocument, rect: Rect2i) -> void:
	var m := mouth_rect(f, rect)
	if not m.has_area():
		profiles.clear()
		return
	if m == Rect2i(Vector2i.ZERO, f.size):
		mouth.fill(MOUTH_FAR)
	else:
		for z in range(m.position.y, m.end.y):
			var row := z * f.size.x
			for i in range(row + m.position.x, row + m.end.x):
				mouth[i] = MOUTH_FAR
	var m_m := Rect2(f.origin + Vector2(m.position) * f.step, Vector2(m.size) * f.step)
	m_m = m_m.grow(MOUTH_FAR + 1.0)
	var mask := doc.pond_mask
	if mask.size() != f.size.x * f.size.y:
		mask = PackedByteArray()
	for chain in RiverProfile.strokes(doc.water_bodies):
		var typed: Array[WaterBody] = []
		typed.assign(chain)
		if not f._chain_may_meet(typed, m_m):
			continue
		var id := typed[0].id
		var profile: RiverProfile = profiles.get(id)
		if profile == null:
			profile = RiverProfile.for_doc(doc, typed)
		if profile.points.size() < 2:
			continue
		var lines := mouth_lines(f, profile, id, mask)
		@warning_ignore("integer_division")
		for k in lines.size() / 2:
			_stamp(f, lines[k * 2], lines[k * 2 + 1], m)
	profiles.clear()


## The mouth lines of the stroke `profile` (first reach `id`) over `f` (see the header) as pairs
## of end points in map XZ: [a0, b0, a1, b1, ...]; a lone corner is a pair of the same point.
func mouth_lines(
	f: WaterField, profile: RiverProfile, id: int, mask: PackedByteArray
) -> PackedVector2Array:
	# Per side: the corners along the course as [point, entering, half-width].
	var found: Array[Array] = [[], []]
	var points := profile.points
	var have := false
	var was := [false, false]
	var last := [Vector2.ZERO, Vector2.ZERO]
	for k in points.size() - 1:
		var a := points[k]
		var segment := points[k + 1] - a
		var length := segment.length()
		if length < 1e-6:
			continue
		var side := Vector2(-segment.y, segment.x) / length
		var count := maxi(1, int(ceil(length / WALK_STEP)))
		# The last segment's end point is a station too.
		var stations := count + 1 if k == points.size() - 2 else count
		for j in stations:
			var t := float(j) / count
			var s := lerpf(profile.arc[k], profile.arc[k + 1], t)
			var hw := profile.head(s, lerpf(profile.widths[k], profile.widths[k + 1], t))
			var centre := a + segment * t
			for e in 2:
				var q := centre + side * ((hw + CORNER_OFFSET_M) * (1.0 if e == 0 else -1.0))
				var now := _other_at(f, q, id, mask)
				if have and now != was[e]:
					found[e].append([(q + last[e]) * 0.5, now, hw])
				was[e] = now
				last[e] = q
			have = true
	var out := PackedVector2Array()
	var used := PackedByteArray()
	used.resize(found[1].size())
	for corner: Array in found[0]:
		var from: Vector2 = corner[0]
		var best := -1
		var best_gap := INF
		for r in found[1].size():
			var other: Array = found[1][r]
			if used[r] != 0 or other[1] != corner[1]:
				continue
			var gap := from.distance_to(other[0])
			if gap < best_gap:
				best = r
				best_gap = gap
		out.append(from)
		if best >= 0 and best_gap <= 2.0 * (float(corner[2]) + CORNER_OFFSET_M) + PAIR_SLACK_M:
			used[best] = 1
			out.append(found[1][best][0])
		else:
			out.append(from)
	for r in found[1].size():
		if used[r] == 0:
			out.append(found[1][r][0])
			out.append(found[1][r][0])
	return out


## True when water other than stroke `id`'s own stands at map point `q`: a pond's mask or another
## stroke's channel at the nearest sample.
func _other_at(f: WaterField, q: Vector2, id: int, mask: PackedByteArray) -> bool:
	var x := int(round((q.x - f.origin.x) / f.step.x))
	var z := int(round((q.y - f.origin.y) / f.step.y))
	if x < 0 or z < 0 or x >= f.size.x or z >= f.size.y:
		return false
	var i := z * f.size.x + x
	if not mask.is_empty() and mask[i] != 0:
		return true
	return chan[i] != 0 and chan[i] != id


## Lowers `mouth` to the distance from the segment `a`-`b` over the samples of `m` within
## MOUTH_FAR of it.
func _stamp(f: WaterField, a: Vector2, b: Vector2, m: Rect2i) -> void:
	var lo := (a.min(b) - Vector2(MOUTH_FAR, MOUTH_FAR) - f.origin) / f.step
	var hi := (a.max(b) + Vector2(MOUTH_FAR, MOUTH_FAR) - f.origin) / f.step
	var x0 := maxi(m.position.x, int(ceil(lo.x)))
	var x1 := mini(m.end.x - 1, int(floor(hi.x)))
	var z0 := maxi(m.position.y, int(ceil(lo.y)))
	var z1 := mini(m.end.y - 1, int(floor(hi.y)))
	var ab := b - a
	var length_sq := ab.length_squared()
	for z in range(z0, z1 + 1):
		var row := z * f.size.x
		for x in range(x0, x1 + 1):
			var p := f.origin + Vector2(x, z) * f.step
			var t := clampf((p - a).dot(ab) / length_sq, 0.0, 1.0) if length_sq > 1e-12 else 0.0
			var d := p.distance_to(a + ab * t)
			if d < mouth[row + x]:
				mouth[row + x] = d
