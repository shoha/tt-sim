class_name PainterSites
extends RefCounted
## The small stones' dabs (card painter-terrain-dabs): which body is one, the outline of its mark
## and the flat geometry the mark is drawn with. PainterDabs keeps the meshes; painter_ground_body
## draws them (under PAINTER_DAB).
##
## A small stone is a body whose longer half is under HALF_M, no longer than ASPECT times its
## narrower one and at least MIN_M in radius. A mark its size (0.2 to 0.9 m) is one or two texels
## of the contact field (PainterOcclusion, 0.25 m): baked there it was an angular patch that joined
## three stones into one, and a second texture read per ground pixel cost 0.03 to 0.09 ms a frame.
## So a small stone leaves the field alone and its dab is GEOMETRY: a patch of the terrain's own
## surface under it, drawn with the ground's shader body. A pixel of a patch is therefore the
## ground at that place (the same biome paint, strata, zone maps, cast shadow and contact field)
## with one difference: inside the dab's outline it takes the seam's tone (and, in shade, the
## pool's), as a boulder's foot does. The seam is a tone the ground is set to, not a darkening, so
## a dab inside a boulder's seam or another dab is no darker than either.
##
## THE RULE the outline is built to (owner, card painter-terrain-dabs-finish): about a third of a
## stone shows on the side away from the sun, and elsewhere a sliver no wider than about a tenth of
## the stone's radius, for every stone, on every slope, at every size. The first model (three round
## lobes sized by the body's BOX, two of them standing off in hashed directions, and a brush wobble
## of 0.045 m whatever the stone's size) broke it by construction: a lobe reached 1.26 box radii
## toward the sun, the wobble was half the radius of a 0.2 m stone, and a stone's box is wider than
## where it meets the ground. So the outline now starts from the stone's FOOT, measured:
## - feet(): a body's plan sections at SLICES heights, each a centre and a radius round it as a
##   Fourier series (3 harmonics, fitted to DIRECTIONS rays), in the mesh's own frame. Made once
##   per body of a mesh (PainterOcclusion keeps them).
## - outline(): the section at the height where THIS stone meets THIS ground, turned and scaled as
##   the stone is; on sloped ground under an upright stone the section's first harmonic takes the
##   tilt (uphill the ground cuts the stone higher). 12 floats, three texels of PainterDabs'
##   texture: the foot's centre, its mean radius, the stone's radius, and the three harmonics.
## - The shader (dab_value; value() is its copy) draws the foot SLIVER wider, joined by a smooth
##   union (no cusp) to the same foot CAST as wide moved SHOW stone radii (SHOW_LOW more under a
##   level sun) away from the sun. The moved copy is narrower than the foot, so across the sun's
##   line nothing passes the sliver; the brush's wobble of the edge is EDGE * 0.15 of the stone's
##   radius, not a fixed length. The sun is a uniform: nothing is rebuilt when it turns.
##
## EVERY BODY that stands on an authored terrain is a site by the same rule (card
## painter-terrain-contact): a boulder, a rock of a group, a log (body_radius()). A boulder of
## 0.9 m and over used to keep an all-round ring from the contact field while the stone beside it
## got this mark; now neither writes into the field. A long body (a log) is told by its SECTIONS,
## not its box (a log may lie askew in its mesh): its foot is a strip round a line (the outline's
## last two floats: half that line), its radius is its half width, so its mark shows a third of its
## width away from the sun whatever its length. A body wholly in shade, whose mark's away part
## hides behind it, has no mark of its own: the owner judged "the cast shadow grounds them". (A
## contact line in shade only, line() and LINE, is the dabs' uniform dab_line, off at 0: at 0.1
## its captures showed no visible line, so it is not a working look.) Only a GLB map (no
## heightfield to lay a dab on) keeps radius()'s limit: a larger body there keeps its box in the
## field. Tree trunks still have the field's seam disc.
##
## The patch (append_dab) is the terrain's surface inside the rectangle the mark can reach
## whatever the sun (round_reach() of the foot's line; cells further from it are left out), cut
## exactly: each cell's part of the rectangle is split along the cell's own
## diagonal and each piece lies on its triangle's plane, so the patch is coplanar with the ground
## everywhere and the shader draws it at the ground's depth, moved toward the eye by under 3 mm
## along the pixel's own ray (no world lift: nothing that hugs the ground is hidden by it, and a
## pixel of the patch outside the mark is the ground's own). CUSTOM3 holds BASE, what the value
## loses at this vertex (CUT per metre its ground lies past the stone's vertical reach from the
## ground at the stone: a dab at a ledge's edge ends there), 0 and the stone's slot plus one.

## The fields of a site (site()); those from YAW on only when its foot was measured (measured()).
enum { X, Z, RADIUS, AT, UP_M, YAW, SCALE, BOTTOM, HEIGHT, UPRIGHT, FEET }

const HALF_M := 0.45
const ASPECT := 1.6
const MIN_M := 0.09
## What a patch's vertex holds in CUSTOM3.x.
const BASE := 8.0
## How far up and down from the ground at the stone a dab shows: UP of the stone's radius past
## half its height, and the value lost per metre past that.
const UP := 0.6
const CUT := 12.0
## Floats a plain site is: its middle's world x and z, its radius, the height of its foot and its
## vertical reach (metres).
const SITE_FLOATS := 5
## A body's sections (feet()): SLICES of them, the first SLICE_FIRST of the body's height above its
## underside and SLICE_STEP apart; each SLICE_FLOATS (centre x and z from the box's middle, the mean
## radius, and the cosine and sine parts of harmonics 1 to 3), from DIRECTIONS rays.
const SLICES := 5
const SLICE_FIRST := 0.08
const SLICE_STEP := 0.16
const SLICE_FLOATS := 11
const DIRECTIONS := 12
## The last two floats of a section: zero for a round body; for a long one (a log, whichever way
## it lies in its mesh: its sections' own long axis, not its box's, says so) half the line its
## foot is a strip round, as a plan vector in the mesh's frame. The mean radius is then the
## strip's half width (STRIP_WIDE of the crossings' mean distance from the strip's middle line:
## the ends' crossings lie nearer it) and the harmonics are 0. A body is long when its sections
## are ASPECT times as long as their widest reach across.
const AXIS := 9
const STRIP_WIDE := 1.1
## The foot of a stone that was not measured, in its radii.
const FOOT_SHARE := 0.85
## The outline (painter_ground_body's DAB_ constants: keep each pair equal): the foot's growth
## (the sliver), the stone's radii the mark shows past the foot away from the sun and what a level
## sun adds, the moved copy's width, the smooth union's reach (in foot radii) and the stone's radii
## one unit of the value is (the seam's noise moves the edge by 0.15 units).
const SLIVER := 0.05
const SHOW := 0.6
const SHOW_LOW := 0.15
const CAST := 0.85
const ROUND := 0.3
const EDGE := 0.3
## The contact line a body in shade may stand in (painter_ground_body's uniform dab_line on the
## dabs' material; 0, its default, draws none): the body's radii the line reaches past the BODY's
## own radius all round (a line at the foot hid under the body's bulge), and how much further on
## the side away from the sun as a share of that (DAB_LINE_AWAY).
const LINE := 0.1
const LINE_AWAY := 0.6
## Metres of plain ground a patch keeps round the furthest outline (the edge's one soft pixel).
const MARGIN_M := 0.03
## Floats an outline is (three RGBA texels).
const OUTLINE_FLOATS := 12


## The radius of the mark of a body of plan half extents `half` (metres) of ANY size, or 0 when it
## is too small for one: a long body's (longer than ASPECT times its narrower half: a log) is its
## narrower half, so its mark shows a third of its WIDTH away from the sun whatever its length; a
## round one's is the geometric mean of the two. Every body on an authored terrain is a site by
## this radius (card painter-terrain-contact); radius() and holds() are a GLB map's rule.
static func body_radius(half: Vector2) -> float:
	var narrow := minf(half.x, half.y)
	var r := narrow if maxf(half.x, half.y) > ASPECT * narrow else sqrt(half.x * half.y)
	return r if r >= MIN_M else 0.0


## The radius of the site a body of plan half extents `half` is, or 0 when it is none: any body
## where `all` (an authored terrain, body_radius()), only a small stone otherwise (radius()).
static func site_radius(half: Vector2, all: bool) -> float:
	return body_radius(half) if all else radius(half)


## The radius of the site a body of plan half extents `half` (metres) is where only small stones
## are sites (a GLB map: no heightfield to lay a dab on, so a larger body keeps its footprint in
## the field), or 0 when it is none: too large or too long, or too small for any mark.
static func radius(half: Vector2) -> float:
	var narrow := minf(half.x, half.y)
	var longer := maxf(half.x, half.y)
	if longer >= HALF_M or longer > ASPECT * narrow:
		return 0.0
	var r := sqrt(half.x * half.y)
	return r if r >= MIN_M else 0.0


## Whether a body of plan half extents `half` is a site's size (it then leaves no footprint in the
## field, whether or not it is large enough for a dab).
static func holds(half: Vector2) -> bool:
	var longer := maxf(half.x, half.y)
	return longer < HALF_M and longer <= ASPECT * minf(half.x, half.y)


## A site: a stone whose body's middle is at world (x, z), with radius `r` (radius()), whose foot
## stands at height `at` and whose body is `half_y` tall above and below its middle.
static func site(x: float, z: float, r: float, at: float, half_y: float) -> Array:
	return [x, z, r, at, 0.5 * half_y + UP * r]


## site() with the stone's measured foot: its turn about the vertical (`yaw`, the plan angle its
## mesh's +x points at), its plan scale, whether it stands upright, and its body's sections
## (feet(), in the mesh's frame).
static func measured(
	plain: Array, half_y: float, yaw: float, scale: float, upright: bool, sections: PackedFloat32Array
) -> Array:
	var out := plain.duplicate()
	var bottom := float(plain[AT]) - 0.5 * half_y
	out.append_array([yaw, scale, bottom, 2.0 * half_y, upright, sections])
	return out


## The plan sections of one body: `triangles` (three corners each, the mesh's frame) cut at SLICES
## heights of `box`. A section is the outermost crossing along DIRECTIONS rays from the middle of
## its crossings, as a mean radius and three harmonics. Empty when no slice crosses anything.
static func feet(triangles: PackedVector3Array, box: AABB) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(SLICES * SLICE_FLOATS)
	var mid := Vector2(box.position.x + 0.5 * box.size.x, box.position.z + 0.5 * box.size.z)
	# Every section as a strip along its own long axis: the body is long when they are.
	var cuts: Array[PackedVector2Array] = []
	var strips: Array[PackedFloat32Array] = []
	var long_sum := 0.0
	var wide_sum := 0.0
	var first_axis := Vector2.ZERO
	for s in SLICES:
		cuts.append(_crossings(triangles, box.position.y + box.size.y * (SLICE_FIRST + SLICE_STEP * s)))
		strips.append(_strip(cuts[s], first_axis))
		if not strips[s].is_empty():
			long_sum += strips[s][5]
			wide_sum += strips[s][6]
			if first_axis == Vector2.ZERO:
				first_axis = Vector2(strips[s][7], strips[s][8])
	var long := long_sum > ASPECT * wide_sum
	var found := -1
	for s in SLICES:
		var ends := cuts[s]
		var at := s * SLICE_FLOATS
		if ends.size() < 6:
			out[at + 2] = -1.0
			continue
		if long:
			out[at] = strips[s][0] - mid.x
			out[at + 1] = strips[s][1] - mid.y
			out[at + 2] = strips[s][2]
			out[at + AXIS] = strips[s][3]
			out[at + AXIS + 1] = strips[s][4]
			found = s
			continue
		var centre := Vector2.ZERO
		for p: Vector2 in ends:
			centre += p
		centre /= float(ends.size())
		var radii := PackedFloat32Array()
		radii.resize(DIRECTIONS)
		var mean := 0.0
		var hit := 0
		for k in DIRECTIONS:
			var u := Vector2.RIGHT.rotated(TAU * k / DIRECTIONS)
			var far := 0.0
			for e in range(0, ends.size(), 2):
				var along := ends[e + 1] - ends[e]
				var denom := u.cross(along)
				if absf(denom) < 1.0e-9:
					continue
				var from := ends[e] - centre
				var w := from.cross(u) / denom
				if w >= 0.0 and w <= 1.0:
					far = maxf(far, from.cross(along) / denom)
			radii[k] = far
			if far > 0.0:
				mean += far
				hit += 1
		if hit == 0:
			out[at + 2] = -1.0
			continue
		mean /= float(hit)
		out[at] = centre.x - mid.x
		out[at + 1] = centre.y - mid.y
		out[at + 2] = mean
		for k in DIRECTIONS:
			var value := radii[k] if radii[k] > 0.0 else mean
			for n in 3:
				var angle := TAU * k * (n + 1) / DIRECTIONS
				out[at + 3 + 2 * n] += 2.0 * (value - mean) * cos(angle) / DIRECTIONS
				out[at + 4 + 2 * n] += 2.0 * (value - mean) * sin(angle) / DIRECTIONS
		found = s
	if found < 0:
		return strip_feet(box)
	# A slice that crossed nothing (an open underside, a cap) takes the nearest one that did.
	for s in SLICES:
		if out[s * SLICE_FLOATS + 2] >= 0.0:
			continue
		var best := found
		for t in SLICES:
			if out[t * SLICE_FLOATS + 2] >= 0.0 and absi(t - s) < absi(best - s):
				best = t
		for k in SLICE_FLOATS:
			out[s * SLICE_FLOATS + k] = out[best * SLICE_FLOATS + k]
	return out


## One section's crossings `ends` as a strip along their own long axis (the first principal axis
## of the points, turned to agree with `like` when that is given): the strip's middle (x, z), its
## half width, half the line it is a strip round (a plan vector), its half length, its widest
## reach across and the axis (a unit vector). Empty for under three crossings.
static func _strip(ends: PackedVector2Array, like: Vector2) -> PackedFloat32Array:
	if ends.size() < 6:
		return PackedFloat32Array()
	var mean := Vector2.ZERO
	for p: Vector2 in ends:
		mean += p
	mean /= float(ends.size())
	var xx := 0.0
	var xz := 0.0
	var zz := 0.0
	for p: Vector2 in ends:
		var d := p - mean
		xx += d.x * d.x
		xz += d.x * d.y
		zz += d.y * d.y
	var axis := Vector2.RIGHT.rotated(0.5 * atan2(2.0 * xz, xx - zz))
	if axis.dot(like) < 0.0:
		axis = -axis
	var side := axis.orthogonal()
	var low := INF
	var high := -INF
	var wide := 0.0
	var widest := 0.0
	for p: Vector2 in ends:
		var d := p - mean
		low = minf(low, d.dot(axis))
		high = maxf(high, d.dot(axis))
		wide += absf(d.dot(side))
		widest = maxf(widest, absf(d.dot(side)))
	var length := 0.5 * (high - low)
	wide = minf(STRIP_WIDE * wide / float(ends.size()), minf(widest, length))
	var centre := mean + axis * 0.5 * (low + high)
	var line := axis * maxf(length - wide, 0.0)
	return PackedFloat32Array(
		[centre.x, centre.y, wide, line.x, line.y, length, widest, axis.x, axis.y]
	)


## The sections of a body whose mesh could not be cut (too large to read, or open): for a long
## `box`, a strip FOOT_SHARE of its width wide along it at every height. Empty for a box that is
## not long (a round body then takes FOOT_SHARE of its radius: outline()).
static func strip_feet(box: AABB) -> PackedFloat32Array:
	var along_x := box.size.x > ASPECT * box.size.z
	if not along_x and not box.size.z > ASPECT * box.size.x:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(SLICES * SLICE_FLOATS)
	var wide := 0.5 * FOOT_SHARE * minf(box.size.x, box.size.z)
	var line := 0.5 * maxf(box.size.x, box.size.z) - wide
	for s in SLICES:
		out[s * SLICE_FLOATS + 2] = wide
		out[s * SLICE_FLOATS + AXIS + (0 if along_x else 1)] = line
	return out


## The plan segments (pairs of ends, x and z) where `triangles` cross the height `y`.
static func _crossings(triangles: PackedVector3Array, y: float) -> PackedVector2Array:
	var ends := PackedVector2Array()
	for t in range(0, triangles.size() - 2, 3):
		var a := triangles[t]
		var b := triangles[t + 1]
		var c := triangles[t + 2]
		var over := int(a.y > y) + int(b.y > y) + int(c.y > y)
		if over == 0 or over == 3:
			continue
		# The corner alone on its side of the cut, and the two edges from it.
		var lone := a
		var p := b
		var q := c
		if (b.y > y) != (a.y > y) and (b.y > y) != (c.y > y):
			lone = b
			p = a
		elif (c.y > y) != (a.y > y) and (c.y > y) != (b.y > y):
			lone = c
			q = a
		var first := lone.lerp(p, (y - lone.y) / (p.y - lone.y))
		var second := lone.lerp(q, (y - lone.y) / (q.y - lone.y))
		ends.append(Vector2(first.x, first.z))
		ends.append(Vector2(second.x, second.z))
	return ends


## The outline of `site_of`'s dab on this ground (OUTLINE_FLOATS: the foot's centre x and z, its
## mean radius, the stone's radius, then the cosine and sine parts of harmonics 1 to 3, with two
## spare floats), or nothing for a stone that does not stand on it (off the map, or its foot
## further than twice its reach from the ground). The site is in the terrain's own frame; `grid`
## is the terrain's heights (`columns` by `rows` samples, `step` metres apart, centred on the
## origin: `half` is half its extent). One function of the stone and the ground under it.
static func outline(
	site_of: Array,
	grid: PackedFloat32Array,
	columns: int,
	rows: int,
	step: Vector2,
	half: Vector2
) -> PackedFloat32Array:
	var x: float = site_of[X]
	var z: float = site_of[Z]
	var r: float = site_of[RADIUS]
	if absf(x) > half.x or absf(z) > half.y:
		return PackedFloat32Array()
	var ground := _height(grid, columns, rows, step, half, x, z)
	if absf(ground - float(site_of[AT])) > 2.0 * float(site_of[UP_M]):
		return PackedFloat32Array()
	var own := PackedFloat32Array()
	own.resize(OUTLINE_FLOATS)
	own[0] = x
	own[1] = z
	own[2] = FOOT_SHARE * r
	own[3] = r
	if site_of.size() <= FEET:
		return own
	var sections: PackedFloat32Array = site_of[FEET]
	if sections.size() != SLICES * SLICE_FLOATS:
		return own
	# The section at the height the ground meets the body.
	var tall := maxf(float(site_of[HEIGHT]), 1.0e-3)
	var share := (ground - float(site_of[BOTTOM])) / tall
	var t := clampf((share - SLICE_FIRST) / SLICE_STEP, 0.0, SLICES - 1.0)
	var k := mini(int(t), SLICES - 2)
	var w := t - k
	var a := k * SLICE_FLOATS
	var b := a + SLICE_FLOATS
	var scale: float = site_of[SCALE]
	var yaw: float = site_of[YAW]
	var centre := (
		Vector2(lerpf(sections[a], sections[b], w), lerpf(sections[a + 1], sections[b + 1], w)).rotated(
			yaw
		)
		* scale
	)
	# A long body's foot is a strip round a line (half of it, a plan vector), and its radius is
	# its half WIDTH at its widest section, whatever its box (a log lying askew in its mesh).
	var line := (
		Vector2(
			lerpf(sections[a + AXIS], sections[b + AXIS], w),
			lerpf(sections[a + AXIS + 1], sections[b + AXIS + 1], w)
		).rotated(yaw)
		* scale
	)
	if line != Vector2.ZERO:
		var widest := 0.0
		for s in SLICES:
			widest = maxf(widest, sections[s * SLICE_FLOATS + 2])
		r = maxf(widest * scale, MIN_M)
		own[3] = r
		own[10] = line.x
		own[11] = line.y
	var foot := maxf(lerpf(sections[a + 2], sections[b + 2], w) * scale, 0.25 * r)
	own[0] = x + centre.x
	own[1] = z + centre.y
	own[2] = foot
	var waves := 0.0
	for n in 3:
		var part := (
			Vector2(
				lerpf(sections[a + 3 + 2 * n], sections[b + 3 + 2 * n], w),
				lerpf(sections[a + 4 + 2 * n], sections[b + 4 + 2 * n], w)
			).rotated((n + 1) * yaw)
			* scale
		)
		own[4 + 2 * n] = part.x
		own[5 + 2 * n] = part.y
		waves += part.length()
	if bool(site_of[UPRIGHT]):
		# Sloped ground cuts an upright stone higher uphill: the radius there is the higher
		# section's, a first harmonic along the ground's rise.
		var e := maxf(foot, 0.5 * minf(step.x, step.y))
		var rise := Vector2(
			(
				_height(grid, columns, rows, step, half, x + e, z)
				- _height(grid, columns, rows, step, half, x - e, z)
			),
			(
				_height(grid, columns, rows, step, half, x, z + e)
				- _height(grid, columns, rows, step, half, x, z - e)
			)
		)
		rise /= 2.0 * e
		var widens := (sections[b + 2] - sections[a + 2]) * scale / (SLICE_STEP * tall)
		var tilt := (rise * widens * foot).limit_length(0.4 * foot)
		waves -= Vector2(own[4], own[5]).length()
		own[4] += tilt.x
		own[5] += tilt.y
		waves += Vector2(own[4], own[5]).length()
	# The radius stays well over nothing in every direction.
	if waves > 0.5 * foot:
		for n in 6:
			own[4 + n] *= 0.5 * foot / waves
	return own


## The terrain's height at (x, z) of its own frame, on its triangles.
static func _height(
	grid: PackedFloat32Array,
	columns: int,
	rows: int,
	step: Vector2,
	half: Vector2,
	x: float,
	z: float
) -> float:
	return ScatterGenerator.triangle_height(
		grid, columns, rows, Vector2((x + half.x) / step.x, (z + half.y) / step.y)
	)


## Metres from an outline's centre within which its dab can show, whatever the sun: round_reach()
## and, for a long body, half the line its foot is a strip round.
static func reach(own: PackedFloat32Array) -> float:
	return round_reach(own) + Vector2(own[10], own[11]).length()


## Metres from an outline's centre (a long body's: from the line its foot is a strip round) within
## which its dab can show, whatever the sun: the foot's furthest reach with its sliver (or with the
## shade's contact line, LINE and its LINE_AWAY), or the moved copy's under a level sun, the
## union's rounding, the edge's wobble and the margin.
static func round_reach(own: PackedFloat32Array) -> float:
	var foot := own[2]
	var r := own[3]
	var most := (
		foot
		+ Vector2(own[4], own[5]).length()
		+ Vector2(own[6], own[7]).length()
		+ Vector2(own[8], own[9]).length()
	)
	var moved := (SHOW + SHOW_LOW) * r + (1.0 - CAST) * foot + CAST * most
	# The shade's contact line lies past the body's radius (a patch holds a line up to LINE wide).
	var line := (1.0 + (1.0 + LINE_AWAY) * LINE) * r * most / maxf(foot, 1.0e-4)
	return (
		maxf(maxf(most * (1.0 + SLIVER), moved), line)
		+ 0.25 * ROUND * foot
		+ 0.15 * EDGE * maxf(r, 0.04)
		+ MARGIN_M
	)


## The foot of outline `own`, `grow` times as wide, at offset `d` from its centre: metres inside.
## A long body's foot is that distance from the line it is a strip round.
static func _foot(own: PackedFloat32Array, d: Vector2, grow: float) -> float:
	var axis := Vector2(own[10], own[11])
	var along := axis.length_squared()
	if along > 0.0:
		d -= axis * clampf(d.dot(axis) / along, -1.0, 1.0)
	var length := maxf(d.length(), 1.0e-4)
	var u := d / length
	var two := Vector2(u.x * u.x - u.y * u.y, 2.0 * u.x * u.y)
	var three := Vector2(u.x * (4.0 * u.x * u.x - 3.0), u.y * (3.0 - 4.0 * u.y * u.y))
	var rho := (
		own[2]
		+ u.dot(Vector2(own[4], own[5]))
		+ two.dot(Vector2(own[6], own[7]))
		+ three.dot(Vector2(own[8], own[9]))
	)
	return maxf(rho, 0.3 * own[2]) * grow - length


## The value of the dab whose outline is `own` (outline()) at (x, z), for a sun whose plan
## direction away from it is `away` (a unit vector, or zero for a sun overhead) and whose
## levelness is `level` (0 overhead to 1 on the horizon): what painter_ground_body's dab_value()
## works out per pixel (the tests' and the probes' copy of it). Positive inside, in units of EDGE
## stone radii.
static func value(
	own: PackedFloat32Array, x: float, z: float, away: Vector2, level: float
) -> float:
	var d := Vector2(x - own[0], z - own[1])
	var show := own[3] * (SHOW + SHOW_LOW * level) if away != Vector2.ZERO else 0.0
	return _mark(own, d, 1.0 + SLIVER, away, show) / (EDGE * maxf(own[3], 0.04))


## The value of the contact line of the body whose outline is `own` at (x, z), `wide` stone radii
## wide (LINE), in value()'s units: positive within `wide` radii of the foot all round and LINE_AWAY
## of that further on the side away from the sun (`away`: a unit vector, or zero). The ground shows
## it only where it is in shade (painter_ground_body's light()): a lit side gets none.
static func line(own: PackedFloat32Array, x: float, z: float, away: Vector2, wide := LINE) -> float:
	var d := Vector2(x - own[0], z - own[1])
	# Past the body's own radius, not past its foot: a body bulges over its foot.
	var grow := maxf((1.0 + wide) * own[3] / maxf(own[2], 1.0e-4), 1.0 + SLIVER)
	var shift := maxf((1.0 + (1.0 + LINE_AWAY) * wide) * own[3] - own[2], 0.0)
	return _mark(own, d, grow, away, shift) / (EDGE * maxf(own[3], 0.04))


## The foot of `own` `grow` times as wide in a smooth union with the same foot CAST as wide whose
## far edge lies `shift` metres past the foot along `away`, at offset `d` from the centre: metres
## inside (painter_ground_body's dab_mark()).
static func _mark(
	own: PackedFloat32Array, d: Vector2, grow: float, away: Vector2, shift: float
) -> float:
	var body := _foot(own, d, grow)
	var cast := _foot(own, d - away * (shift + (1.0 - CAST) * own[2]), CAST)
	var k := ROUND * own[2]
	var h := maxf(k - absf(body - cast), 0.0)
	return maxf(body, cast) + h * h / (4.0 * k)


## Appends the patch of the dab whose outline is `own` (outline(), of `site_of` on this `grid`):
## its `vertices`, their `uvs` (the map-frame x, z the ground's shader reads), the four floats a
## vertex of `custom` (CUSTOM3: BASE, what the value loses, 0, and `slot` plus one, the stone's
## place in PainterDabs' texture of outlines) and its triangles' `indices`, counted from the
## patch's first vertex. The patch is the terrain's surface inside the square reach(own) round the
## outline's centre: every cell's part of it, split along the cell's diagonal, each piece on its
## triangle's plane. Returns the vertices it added.
static func append_dab(
	own: PackedFloat32Array,
	site_of: Array,
	grid: PackedFloat32Array,
	columns: int,
	rows: int,
	step: Vector2,
	half: Vector2,
	vertices: PackedVector3Array,
	uvs: PackedVector2Array,
	custom: PackedFloat32Array,
	indices: PackedInt32Array,
	slot := 0
) -> int:
	if own.size() != OUTLINE_FLOATS:
		return 0
	# The rectangle round the foot (a long body's: round its line), and inside it only the cells
	# the mark can reach: a cell wholly further than the reach from the line is left out.
	var far := round_reach(own)
	var axis := Vector2(own[10], own[11])
	var along := axis.length_squared()
	var span := axis.abs() + Vector2(far, far)
	var low := Vector2(maxf(own[0] - span.x, -half.x), maxf(own[1] - span.y, -half.y))
	var high := Vector2(minf(own[0] + span.x, half.x), minf(own[1] + span.y, half.y))
	if high.x <= low.x or high.y <= low.y:
		return 0
	var out_of_reach := far + 0.5 * step.length()
	var ground := _height(grid, columns, rows, step, half, site_of[X], site_of[Z])
	var up: float = site_of[UP_M]
	var tag := float(slot + 1)
	var first := vertices.size()
	var i0 := clampi(floori((low.x + half.x) / step.x), 0, columns - 2)
	var i1 := clampi(ceili((high.x + half.x) / step.x) - 1, i0, columns - 2)
	var j0 := clampi(floori((low.y + half.y) / step.y), 0, rows - 2)
	var j1 := clampi(ceili((high.y + half.y) / step.y) - 1, j0, rows - 2)
	var lower := PackedVector2Array()
	var upper := PackedVector2Array()
	for j in range(j0, j1 + 1):
		var cell_z := j * step.y - half.y
		var va := (maxf(low.y, cell_z) - cell_z) / step.y
		var vb := (minf(high.y, cell_z + step.y) - cell_z) / step.y
		if vb <= va:
			continue
		var row := j * columns
		for i in range(i0, i1 + 1):
			var cell_x := i * step.x - half.x
			var ua := (maxf(low.x, cell_x) - cell_x) / step.x
			var ub := (minf(high.x, cell_x + step.x) - cell_x) / step.x
			if ub <= ua:
				continue
			var off := Vector2(cell_x + 0.5 * step.x - own[0], cell_z + 0.5 * step.y - own[1])
			if along > 0.0:
				off -= axis * clampf(off.dot(axis) / along, -1.0, 1.0)
			if off.length() > out_of_reach:
				continue
			var h00 := grid[row + i]
			var h10 := grid[row + i + 1]
			var h01 := grid[row + columns + i]
			var h11 := grid[row + columns + i + 1]
			if ua == 0.0 and va == 0.0 and ub == 1.0 and vb == 1.0:
				# A whole cell: its two triangles as they are (most of a large body's patch).
				var base := vertices.size() - first
				for n in 4:
					var cx := cell_x + (step.x if n == 1 or n == 2 else 0.0)
					var cz := cell_z + (step.y if n >= 2 else 0.0)
					var ch := h00 if n == 0 else (h10 if n == 1 else (h11 if n == 2 else h01))
					vertices.append(Vector3(cx, ch, cz))
					uvs.append(Vector2(cx, cz))
					custom.append(BASE)
					custom.append(maxf(absf(ch - ground) - up, 0.0) * CUT)
					custom.append(0.0)
					custom.append(tag)
				indices.append(base)
				indices.append(base + 1)
				indices.append(base + 3)
				indices.append(base + 1)
				indices.append(base + 2)
				indices.append(base + 3)
				continue
			# The piece's corners in the cell (front faces up, as the terrain's), split along
			# the cell's diagonal u + v = 1 into the part on each of its two triangles.
			lower.clear()
			upper.clear()
			var p := Vector2(ua, va)
			for n in 4:
				var q := Vector2(ub if n < 2 else ua, va if n == 0 or n == 3 else vb)
				var sp := p.x + p.y - 1.0
				var sq := q.x + q.y - 1.0
				if sp <= 0.0:
					lower.append(p)
				if sp >= 0.0:
					upper.append(p)
				if (sp < 0.0 and sq > 0.0) or (sp > 0.0 and sq < 0.0):
					var cut := p.lerp(q, sp / (sp - sq))
					lower.append(cut)
					upper.append(cut)
				p = q
			for side in 2:
				var piece := lower if side == 0 else upper
				if piece.size() < 3:
					continue
				var start := vertices.size() - first
				for c: Vector2 in piece:
					var h := (
						h00 + c.x * (h10 - h00) + c.y * (h01 - h00)
						if side == 0
						else h11 + (1.0 - c.x) * (h01 - h11) + (1.0 - c.y) * (h10 - h11)
					)
					var px := cell_x + c.x * step.x
					var pz := cell_z + c.y * step.y
					vertices.append(Vector3(px, h, pz))
					uvs.append(Vector2(px, pz))
					custom.append(BASE)
					custom.append(maxf(absf(h - ground) - up, 0.0) * CUT)
					custom.append(0.0)
					custom.append(tag)
				for n in range(1, piece.size() - 1):
					indices.append(start)
					indices.append(start + n)
					indices.append(start + n + 1)
	return vertices.size() - first
