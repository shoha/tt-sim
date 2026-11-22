class_name PainterSnowForms
extends RefCounted

## The snow body's forms for the snow-top records that are not roof planes (card snow-tops-builder;
## the records are procgen's, docs/ASSET_PIPELINE.md "snow_tops"). PainterMannerSnow.build lays
## them beside the roof planes' blankets, into the same Strips, so every asset's snow is one body
## from one builder:
##   cone     a round roof (`roof_cone`): one grid round the axis and up the roof's own profile
##            (`wall_y + rise * (1 - s^power)`, so a dome and a bell are followed, not a straight
##            cone), closed in one point over the apex, an eave lip at its rim. One grid, no facets:
##            facets drew a tone step per facet under any paint (spike 8). Ported from the spike's
##            PainterSnowBaked.lay_cone (H3b), with the record's numbers in place of a mesh read;
##   coping   a stone wall's run (`coping_line`): a rounded strip along the coping's top points,
##            a lit crown between two shaded shoulders, its depth swelling slowly along the run;
##   pad      a prop's level top (`pad`, rect or disc): a soft dome, foot, shoulder, two rings and
##            a crown, with rounded shading normals (a slab read as a low-poly heap at low sun).
## And for every eave lip (the blankets', the strips', the cone's): window_floor() keeps its foot
## above the top of any window or door under it (the wall faces' openings), so the snow never hangs
## over a window. Every vertex carries the manner's snow data (PainterMannerBlanket's CODE and
## frame). Pure and worker-safe.

const CODE := PainterMannerBlanket.CODE
## A round roof's grid: its cell (metres round and up the slant) and the stations in from the
## eave and down from the apex.
const CONE_CELL_M := 0.35
const EDGE: Array[float] = [0.0, 0.15]
const TOP: Array[float] = [0.0, 0.3]
## The cone's middle depth at full hold, the least share of it a steep pitch keeps, how much
## heavier it lies at the eave (over how many metres up), how much thinner at the apex (over how
## many metres down), and how much deeper on the lee side.
const MID_T_M := 0.27
const STEEP_SHARE := 0.55
const EAVE_HEAVY := 0.4
const EAVE_REACH_M := 1.6
const CONE_THIN := 0.1
const APEX_REACH_M := 1.3
const LEE := 0.35
## The wind in the plan, the drift's squeeze along it and the noise cells (metres) of the ripple,
## the long swell and the eave's lobes.
const WIND := Vector2(0.8, 0.6)
const ALONG := 0.35
const RIPPLE_CELL_M := 0.7
const SWELL_CELL_M := 2.5
const LOBE_CELL_M := 0.9
## The ripple's height, the swell's share of the depth, the deepest lobe and the lowest an eave's
## foot hangs under the eave's edge (metres at full hold), and its tuck under the roof's plane.
const RIPPLE_M := 0.04
const SWELL := 0.22
const SAG_M := 0.3
const FOOT_MAX_M := 0.3
const TUCK := 0.25
## A coping strip's depth as a share of its width and its bounds (metres), its overhang past each
## side, and its station along the run.
const COPING_T := 0.5
const COPING_T_MIN_M := 0.05
const COPING_T_MAX_M := 0.14
const COPING_OVER_M := 0.025
const COPING_STEP_M := 0.4
## A pad's dome: its depth as a share of its narrower width and its bounds (metres), its ring
## count round a disc, and the superellipse power that keeps a rect's corners.
const PAD_T := 0.38
const PAD_T_MIN_M := 0.03
const PAD_T_MAX_M := 0.14
const PAD_SIDES := 20
const RECT_POWER := 4.0
## An eave point within this plan distance of a window's top edge keeps its foot this far above it.
const WINDOW_REACH_M := 0.9
const WINDOW_CLEAR_M := 0.05
const WINDOW_LIFT_MAX_M := 0.4


# ---------------------------------------------------------------- noise


static func _hash(ix: int, iy: int, seed: int) -> float:
	var h := (ix * 73856093) ^ (iy * 19349663) ^ (seed * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffff) / 65535.0


## Smooth value noise at `p`, 0 to 1 (one cell per unit). Pure.
static func noise(p: Vector2, seed: int) -> float:
	var ix := floori(p.x)
	var iy := floori(p.y)
	var fx := p.x - ix
	var fy := p.y - iy
	fx = fx * fx * fx * (fx * (fx * 6.0 - 15.0) + 10.0)
	fy = fy * fy * fy * (fy * (fy * 6.0 - 15.0) + 10.0)
	var a := lerpf(_hash(ix, iy, seed), _hash(ix + 1, iy, seed), fx)
	var b := lerpf(_hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed), fx)
	return lerpf(a, b, fy)


## The ripple at plan point `p`, -1 to 1: a value noise turned to the wind, longer along it. Pure.
static func ripple(p: Vector2) -> float:
	var w := Vector2(p.dot(WIND) * ALONG, p.dot(Vector2(-WIND.y, WIND.x))) / RIPPLE_CELL_M
	return noise(w, 77) * 2.0 - 1.0


## The long swell of the depth at plan point `p`, -1 to 1. Pure.
static func swell_at(p: Vector2, phase: Vector3) -> float:
	return noise((p + Vector2(phase.z, phase.y) * 5.3) / SWELL_CELL_M, 83) * 2.0 - 1.0


## The hang of an eave's lobe at point `p`, 0 to 1. Pure.
static func lobe(p: Vector3, phase: Vector3) -> float:
	var q := Vector2(p.x + phase.y * 2.3, p.z + phase.x * 1.9) / LOBE_CELL_M
	return smoothstep(0.3, 0.8, noise(q, 91))


# ---------------------------------------------------------------- windows


## The top edges of the openings of `records` (manner records by id): each wall face's holes, as
## [{"a", "b"}] in the structure's frame. Pure.
static func windows_of(records: Dictionary) -> Array:
	var out: Array = []
	for rec: Dictionary in records.values():
		if str(rec.get("kind", "")) != "wall_face":
			continue
		var o: Vector3 = rec["origin"]
		var u: Vector3 = rec["u"]
		var v: Vector3 = rec.get("v", Vector3.UP)
		for hole: Dictionary in rec.get("holes", []):
			var top := float(hole["v1"])
			out.append(
				{"a": o + u * float(hole["u0"]) + v * top, "b": o + u * float(hole["u1"]) + v * top}
			)
	return out


## The lowest an eave lip's vertex at `p` may hang: WINDOW_CLEAR_M over the top of any opening of
## `windows` (windows_of) within WINDOW_REACH_M of it in plan, else -INF. Pure.
static func window_floor(windows: Array, p: Vector3) -> float:
	var out := -INF
	var q := Vector2(p.x, p.z)
	for w: Dictionary in windows:
		var a: Vector3 = w["a"]
		var b: Vector3 = w["b"]
		var near := Geometry2D.get_closest_point_to_segment(q, Vector2(a.x, a.z), Vector2(b.x, b.z))
		if near.distance_to(q) < WINDOW_REACH_M:
			out = maxf(out, maxf(a.y, b.y) + WINDOW_CLEAR_M)
	return out


## `at` lifted to window_floor() of `windows` when it hangs below it. A window whose top lies more
## than WINDOW_LIFT_MAX_M over `at` is not under this lip (a gable's window near an eave's end) and
## lifts nothing. Pure.
static func above_windows(windows: Array, at: Vector3) -> Vector3:
	if windows.is_empty():
		return at
	var near: Array = []
	for w: Dictionary in windows:
		if maxf((w["a"] as Vector3).y, (w["b"] as Vector3).y) < at.y + WINDOW_LIFT_MAX_M:
			near.append(w)
	var floor_y := window_floor(near, at)
	return Vector3(at.x, maxf(at.y, floor_y), at.z)


# ---------------------------------------------------------------- cone


## The height of round roof `rec`'s top face at plan distance `d` from its axis, and its slope
## (metres down per metre out): the record's profile, pinned to its eave ring (`base`) and apex.
## Pure.
static func cone_profile(rec: Dictionary, d: float) -> Vector2:
	var base: Vector3 = rec["base"]
	var apex: Vector3 = rec["apex"]
	var radius := maxf(float(rec["radius"]), 0.01)
	var wall_ap := float(rec.get("wall_apothem", radius))
	var power := float(rec.get("power", 1.0))
	if wall_ap <= 0.01 or not rec.has("rise"):
		var slope := (apex.y - base.y) / radius
		return Vector2(apex.y - slope * d, slope)
	var wall_y := float(rec["wall_y"])
	var rise := float(rec["rise"])
	var f := func(x: float) -> float: return wall_y + rise * (1.0 - pow(maxf(x, 0.0) / wall_ap, power))
	# Pinned: the formula's error at the eave ring and at the apex spread linearly between them.
	var at_eave: float = f.call(radius)
	var at_apex: float = f.call(0.0)
	var k := clampf(d / radius, 0.0, 1.0)
	var y: float = f.call(d) + lerpf(apex.y - at_apex, base.y - at_eave, k)
	var h := 0.02
	var y2: float = (
		f.call(d + h) + lerpf(apex.y - at_apex, base.y - at_eave, clampf((d + h) / radius, 0.0, 1.0))
	)
	return Vector2(minf(y, apex.y), maxf((y - y2) / h, 0.0))


## Lays the snow of round roof `rec` (a `roof_cone` record) into `g`: one grid round its axis,
## from the eave lip up its profile, closed in one point over the apex. `hold` the roof
## material's, `phase` the structure's field phase, `windows` (windows_of) the openings the lip
## keeps clear of. Returns the triangles laid; none for a record too small to hold a body.
static func lay_cone(
	g: PainterMannerSnow.Strips,
	rec: Dictionary,
	hold: float,
	phase: Vector3,
	seed: int,
	windows: Array = []
) -> int:
	var apex: Vector3 = rec["apex"]
	var base: Vector3 = rec["base"]
	var radius := float(rec["radius"])
	var rise := apex.y - base.y
	if radius < 0.3 or rise <= 0.02:
		return 0
	var slant := Vector2(radius, rise).length()
	var up_n := float(rec.get("up", radius / slant))
	var whole := MID_T_M * hold * lerpf(STEEP_SHARE, 1.0, smoothstep(0.5, 0.9, up_n))
	var nc := maxi(12, ceili(TAU * radius / CONE_CELL_M))
	var t_st := PainterMannerBlanket.stations(slant, EDGE, TOP, CONE_CELL_M)
	var rows: Array = [[0.0, 3], [0.0, 2], [0.0, 1]]
	for k in t_st.size():
		rows.append([t_st[k], 0])
	var nr := rows.size()
	var stride := nc + 1
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var shade := PackedFloat32Array()
	var fixed := PackedByteArray()
	pos.resize(stride * nr)
	nor.resize(stride * nr)
	shade.resize(stride * nr)
	fixed.resize(stride * nr)
	var ph := float(seed % 997) * 0.37
	for ri in nr:
		var t := float(rows[ri][0])
		var rk := int(rows[ri][1])
		for ci in stride:
			var a := TAU * float(ci % nc) / nc
			var out := Vector3(cos(a), 0.0, sin(a))
			var d := radius * (1.0 - t)
			var prof := cone_profile(rec, d)
			var n := (out * prof.y + Vector3.UP).normalized()
			var down := (out - Vector3.UP * prof.y).normalized()
			var base_p := Vector3(apex.x, prof.x, apex.z) + out * d
			var plan := Vector2(base_p.x, base_p.z)
			var top_m := (1.0 - t) * slant
			var eave := 1.0 + EAVE_HEAVY * (1.0 - smoothstep(0.0, EAVE_REACH_M, t * slant))
			var crown := 1.0 - CONE_THIN * (1.0 - smoothstep(0.0, APEX_REACH_M, top_m))
			var lee := 1.0 + LEE * Vector2(n.x, n.z).dot(WIND) * smoothstep(0.0, 1.2, top_m)
			var h := whole * eave * crown * lee * (1.0 + SWELL * swell_at(plan, phase))
			h = maxf(h + RIPPLE_M * hold * ripple(plan) * crown, 0.01)
			var at := base_p + n * h
			var dn := Vector3.ZERO
			var sh := 0.0
			if rk >= 1:
				# A swell that closes round the rim (the field's is not periodic).
				var sw := 1.0 + 0.22 * sin(a * 3.0 + ph) + 0.13 * sin(a * 7.0 + ph * 2.3)
				var over := PainterMannerBlanket.OVER_M * hold * sw
				var hang := SAG_M * hold * lobe(base_p, phase)
				var room := maxf(FOOT_MAX_M * hold - TUCK * h * n.y, 0.0)
				if rk == 1:
					at += down * over * 0.65 - n * h * 0.25 - Vector3.UP * minf(hang * 0.12, room)
					dn = down * 0.7 + n * 0.6
					sh = 0.1
				elif rk == 2:
					at += down * over - n * h * 0.9 - Vector3.UP * minf(hang, room)
					dn = down - n * 0.1
					sh = 0.4
				else:
					at += down * over * 0.3 - n * h * (1.0 + TUCK) - Vector3.UP * minf(hang, room)
					dn = -n * 0.8 + down * 0.2
					sh = 0.85
				at = above_windows(windows, at)
			elif ri == nr - 1:
				# The apex: every column ends in one point straight over it.
				at = Vector3(apex.x, apex.y, apex.z) + Vector3.UP * (h / maxf(up_n, 0.3))
				dn = Vector3.UP
			var k := ri * stride + ci
			pos[k] = at
			nor[k] = dn
			shade[k] = sh
			fixed[k] = 1 if dn != Vector3.ZERO else 0
	for ri in nr:
		for ci in stride:
			var k := ri * stride + ci
			if fixed[k] == 1:
				continue
			var right := ri * stride + (ci % nc + 1) % nc
			var left := ri * stride + (ci % nc + nc - 1) % nc
			var tu := pos[right] - pos[left]
			var tv := pos[mini(ri + 1, nr - 1) * stride + ci] - pos[maxi(ri - 1, 0) * stride + ci]
			var c := tu.cross(tv)
			var out := Vector3(pos[k].x - apex.x, 0.0, pos[k].z - apex.z).normalized()
			var cone_n := (out * rise + Vector3.UP * radius) / slant
			if c.length_squared() < 1e-10:
				nor[k] = cone_n
			else:
				nor[k] = (c if c.dot(cone_n) > 0.0 else -c).normalized()
	# The frame's length up the slope is given long: the shader's crest gaps would gather into one
	# bare blot at the apex, where every column meets.
	var size := Vector2(TAU * radius, slant + 10.0)
	var acc := float(seed % 1000) / 1000.0
	var first := g.pos.size()
	for ri in nr:
		var t := float(rows[ri][0])
		for ci in stride:
			var k := ri * stride + ci
			var uv := Vector2(TAU * float(ci) / nc * radius, t * slant)
			var data := PackedFloat32Array([size.x, size.y, float(CODE) + 0.9 * shade[k], acc])
			g.put(pos[k], nor[k], uv, data)
	var before := g.idx.size()
	for ri in nr - 1:
		g.band(first + ri * stride, first + (ri + 1) * stride, stride)
	return (g.idx.size() - before) / 3


# ---------------------------------------------------------------- coping


## Lays the strip of coping run `rec` (a `coping_line` record: "points" along the coping's top,
## "width") into `g`: per station a profile of five points across the top, a shaded foot just past
## each side, a shoulder, and the lit crown. Returns the triangles laid.
static func lay_coping(g: PainterMannerSnow.Strips, rec: Dictionary, seed: int) -> int:
	var raw: Variant = rec.get("points", [])
	var pts: Array[Vector3] = []
	for p: Vector3 in raw:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 0.002:
			pts.append(p)
	if pts.size() < 2:
		return 0
	var width := float(rec.get("width", 0.5))
	var half := width * 0.5
	var t := clampf(COPING_T * width, COPING_T_MIN_M, COPING_T_MAX_M)
	# Stations: every point, and between two far apart one every COPING_STEP_M (so the swell is
	# drawn).
	var st: Array[Vector3] = [pts[0]]
	for k in range(1, pts.size()):
		var a := pts[k - 1]
		var b := pts[k]
		var count := maxi(1, ceili(Vector2(b.x - a.x, b.z - a.z).length() / COPING_STEP_M))
		for i in range(1, count + 1):
			st.append(a.lerp(b, float(i) / count))
	var length := 0.0
	var first := g.pos.size()
	var size := Vector2(1.0, 5.0)
	var acc := float(seed % 1000) / 1000.0
	var along_dir: Vector3 = rec.get("u", (pts[pts.size() - 1] - pts[0]).normalized())
	for k in st.size():
		var p := st[k]
		if k > 0:
			length += Vector2(p.x - st[k - 1].x, p.z - st[k - 1].z).length()
		var d := along_dir
		if k > 0 and k < st.size() - 1:
			var dd := st[k + 1] - st[k - 1]
			if Vector2(dd.x, dd.z).length() > 0.01:
				d = dd
		var across := Vector3.UP.cross(Vector3(d.x, 0.0, d.z)).normalized()
		var sw := PainterMannerSnow.swell(length, seed)
		var tk := t * lerpf(0.8, 1.15, (sw - 0.65) / 0.7)
		var prof := [
			[p - across * (half + COPING_OVER_M) - Vector3.UP * 0.015, -across + Vector3.UP * 0.2, 0.7],
			[p - across * half * 0.75 + Vector3.UP * tk * 0.7, -across * 0.6 + Vector3.UP, 0.15],
			[p + Vector3.UP * tk, Vector3.UP, 0.0],
			[p + across * half * 0.75 + Vector3.UP * tk * 0.7, across * 0.6 + Vector3.UP, 0.15],
			[p + across * (half + COPING_OVER_M) - Vector3.UP * 0.015, across + Vector3.UP * 0.2, 0.7],
		]
		for j in prof.size():
			var data := PackedFloat32Array(
				[size.x, size.y, float(CODE) + 0.9 * float(prof[j][2]), acc]
			)
			g.put(prof[j][0], prof[j][1], Vector2(length, float(j) * width * 0.25), data)
	var before := g.idx.size()
	for k in st.size() - 1:
		g.band(first + k * 5, first + (k + 1) * 5, 5)
	var d0 := Vector3(along_dir.x, 0.0, along_dir.z).normalized()
	g.end_cap(first, 5, -d0)
	g.end_cap(first + (st.size() - 1) * 5, 5, d0)
	return (g.idx.size() - before) / 3


# ---------------------------------------------------------------- pad


## Lays the dome of level top `rec` (a `pad` record: a "disc" of "radius" or a "rect" of "u_len"
## by "v_len", round "centre" on axes "u", "v", "n") into `g`. Returns the triangles laid; none for
## a top too small to hold one.
static func lay_pad(g: PainterMannerSnow.Strips, rec: Dictionary) -> int:
	var c: Vector3 = rec["centre"]
	var up: Vector3 = (rec.get("n", Vector3.UP) as Vector3).normalized()
	var u: Vector3 = (rec.get("u", Vector3.RIGHT) as Vector3).normalized()
	var v: Vector3 = (rec.get("v", Vector3.BACK) as Vector3).normalized()
	var disc := str(rec.get("shape", "rect")) == "disc"
	var hu := float(rec.get("radius", 0.0)) if disc else float(rec.get("u_len", 0.0)) * 0.5
	var hv := float(rec.get("radius", 0.0)) if disc else float(rec.get("v_len", 0.0)) * 0.5
	if minf(hu, hv) < 0.05:
		return 0
	var t := clampf(PAD_T * 2.0 * minf(hu, hv), PAD_T_MIN_M, PAD_T_MAX_M)
	# Rings out to in: [plan scale, height share, normal's lean out, shade].
	var rings := [
		[1.04, -0.12, 0.85, 0.75],
		[0.97, 0.45, 0.6, 0.3],
		[0.82, 0.8, 0.35, 0.05],
		[0.5, 0.97, 0.15, 0.0],
	]
	var size := Vector2(2.0 * hu, 2.0 * hv)
	var first := g.pos.size()
	for ring: Array in rings:
		for i in PAD_SIDES:
			var a := TAU * float(i) / PAD_SIDES
			var ca := cos(a)
			var sa := sin(a)
			if not disc:
				ca = signf(ca) * pow(absf(ca), 2.0 / RECT_POWER)
				sa = signf(sa) * pow(absf(sa), 2.0 / RECT_POWER)
			var flat := u * ca * hu + v * sa * hv
			var out := flat.normalized()
			var p := c + flat * float(ring[0]) + up * t * float(ring[1])
			var n := (up + out * float(ring[2])).normalized()
			var data := PackedFloat32Array([size.x, size.y, float(CODE) + 0.9 * float(ring[3]), 0.5])
			g.put(p, n, Vector2(flat.dot(u), flat.dot(v)) * float(ring[0]), data)
	var crown_data := PackedFloat32Array([size.x, size.y, float(CODE), 0.5])
	var crown := g.put(c + up * t, up, Vector2.ZERO, crown_data)
	var before := g.idx.size()
	for r in rings.size() - 1:
		var r0 := first + r * PAD_SIDES
		var r1 := first + (r + 1) * PAD_SIDES
		for i in PAD_SIDES:
			var j := (i + 1) % PAD_SIDES
			var facing := g.nor[r0 + i] + g.nor[r1 + j]
			g.tri(r0 + i, r1 + i, r1 + j, facing)
			g.tri(r0 + i, r1 + j, r0 + j, facing)
	var last := first + (rings.size() - 1) * PAD_SIDES
	for i in PAD_SIDES:
		g.tri(last + i, crown, last + (i + 1) % PAD_SIDES, up)
	return (g.idx.size() - before) / 3
