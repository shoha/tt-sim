class_name PainterMannerBlanket
extends RefCounted

## Winter's snow blanket on one roof slope of a hand-drawn building (card painter-buildings-fix2):
## one continuous mesh over the slope, built by PainterMannerSnow for every slope whose edges are an
## eave, two sides (verge or hip) and a ridge or an apex (a dormer's or a porch's roof piece gets
## those edges from its frame, PainterMannerSnow.source).
##
## The model. Snow lies on a roof as one blanket: thickest and most rounded in the middle of the
## slope and toward the ridge, where it piles, thinning to a soft edge at the verges and the eave
## (card painter-buildings-fix2: thick lips and caps round a thin flat field read as a tray). Over
## the slope a grid takes that thickness: MID_T_M at full hold (less on a steep slope) times a
## taper at each verge and at the eave (an ease from a few centimetres at the edge to the whole a
## VERGE_R_M or EAVE_R_M in), a pile toward the top and a slow sag keyed to the world. Its normals
## follow the shape, so the light does the rest: a lit top, the light rolling off toward each
## verge and into the sags. Past the edges:
##   eave   a modest rounded lip: the blanket rounds over the eave, hangs past it in scallops and
##          tucks under, its underside shaded blue;
##   verge  a small soft roll down over the edge;
##   ridge  the two halves meet in one rounded crest where the two blankets' planes meet, a
##   hip    little heaped, so a cap is the blanket itself, not a band; a ridge with no other half
##          (a porch roof against its wall) ends at the blanket's own thickness;
##   apex   a hip end's top: the blanket's own thickness.
## Each vertex carries the manner's data: UV2 the slope's frame metres (the shader lays the snow's
## brush washes there, as on a roof), CUSTOM0 [u_len, v_len, CODE + 0.9 * shade, accent], the
## shade 0 on the blanket and up to 1 under the eave's lip. Pure and worker-safe.

## The manner code of a blanket vertex (painter_structure_manner.gdshader).
const CODE := 10
## The thickness in the middle of a slope at full hold, and how much more it piles toward the top.
const MID_T_M := 0.3
const PILE := 0.3
## The thickness at a verge's edge and at the top of the eave's lip (at full hold), and how far in
## each taper reaches its whole.
## The eave's is most of the middle's (card painter-buildings-fix4: at eye level a thin eave read
## as a knife-straight edge; the snow rolls over the eave as thick as it lies, only the verges
## thin, so no rim stands round a thinner field).
const VERGE_T_M := 0.035
const EAVE_T_M := 0.22
const VERGE_R_M := 1.3
const EAVE_R_M := 1.3
## The eave lip's overhang past the edge and the deepest droop of a scallop (full hold), and the
## verge roll's reach past its edge.
const OVER_M := 0.2
const DROOP_M := 0.1
## How much the blanket cools toward a thin edge (its shade where the taper is at its thinnest),
## so the middle reads the thickest.
const THIN_SHADE := 0.22
## How far a thin edge's normal leans back to the slope's (at its thinnest) and how far a verge's
## roll turns outward (card painter-buildings-fix3): the taper and the roll read by their shape and
## their cooling, not as a band of their own light.
const THIN_FLAT := 0.5
const ROLL_TURN := 0.5
const VERGE_OVER_M := 0.05
## The sag's share of the thickness, and the heap on a crest (full hold).
const SAG := 0.4
const CREST_M := 0.05
## The crown (card painter-buildings-fix4: a big roof's blanket read as a flat white rectangle):
## the blanket domes toward the middle of its run along the eave by DOME and lies up to LEE / 2
## heavier toward the lee (a slow swell keyed to the world).
const DOME := 0.18
const LEE := 0.3
## Grid steps in from an edge where a taper is drawn (metres); between them the field's step, up
## the slope and along the eave (finer, so the lip's scallops and swell are drawn, not sampled
## into straight runs a metre long).
const EDGE_STEPS: Array[float] = [0.0, 0.15, 0.45, 0.95]
const TOP_STEPS: Array[float] = [0.0, 0.4]
const FIELD_STEP_M := 1.2
const FIELD_STEP_S_M := 0.5
## Corners closer than this are one point (metres).
const JOIN_M := 0.15

## The step along the eave in use (FIELD_STEP_S_M; FIELD_STEP_M builds the grid as before card
## painter-buildings-fix4, an A/B switch for measurements).
static var step_s := FIELD_STEP_S_M


## The blanket's frame on roof record `roof`: {"p0", "p1" (the eave's ends), "q0", "q1" (the top's
## ends over them; one point for an apex), "left", "right" ("verge" or "hip": the sides p0-q0 and
## p1-q1), "top" ("ridge" or "apex")}; {} when its edges are not one eave, two sides and a ridge or
## an apex. Pure.
static func layout(roof: Dictionary) -> Dictionary:
	var eave: Dictionary = {}
	var ridge: Dictionary = {}
	var sides: Array = []
	for e: Dictionary in roof.get("edges", []):
		match str(e["kind"]):
			"eave":
				if not eave.is_empty():
					return {}
				eave = e
			"ridge":
				if not ridge.is_empty():
					return {}
				ridge = e
			"verge", "hip":
				sides.append(e)
			_:
				return {}
	if eave.is_empty() or sides.size() != 2:
		return {}
	var u: Vector3 = roof["u"]
	var p0: Vector3 = eave["a"]
	var p1: Vector3 = eave["b"]
	if p0.dot(u) > p1.dot(u):
		var swap := p0
		p0 = p1
		p1 = swap
	var left := _side_at(sides, p0)
	var right := _side_at(sides, p1)
	if left.is_empty() or right.is_empty() or left == right:
		return {}
	var q0 := _other_end(left, p0)
	var q1 := _other_end(right, p1)
	var top := "ridge"
	if ridge.is_empty():
		if q0.distance_to(q1) > JOIN_M:
			return {}
		q0 = (q0 + q1) * 0.5
		q1 = q0
		top = "apex"
	else:
		var ra: Vector3 = ridge["a"]
		var rb: Vector3 = ridge["b"]
		var near := minf(ra.distance_to(q0) + rb.distance_to(q1), rb.distance_to(q0) + ra.distance_to(q1))
		if near > JOIN_M * 2.0:
			return {}
	return {
		"p0": p0,
		"p1": p1,
		"q0": q0,
		"q1": q1,
		"left": str(left["kind"]),
		"right": str(right["kind"]),
		"top": top,
		"left_edge": left,
		"right_edge": right,
		"ridge_edge": ridge,
	}


static func _side_at(sides: Array, p: Vector3) -> Dictionary:
	for e: Dictionary in sides:
		if (e["a"] as Vector3).distance_to(p) < JOIN_M or (e["b"] as Vector3).distance_to(p) < JOIN_M:
			return e
	return {}


static func _other_end(e: Dictionary, p: Vector3) -> Vector3:
	var a: Vector3 = e["a"]
	return e["b"] if a.distance_to(p) < JOIN_M else a


## The whole thickness of the blanket on `roof` (its middle, before tapers, pile and sag). Pure.
static func depth(roof: Dictionary, hold: float) -> float:
	var n: Vector3 = roof["n"]
	return MID_T_M * hold * lerpf(0.8, 1.0, smoothstep(0.5, 0.85, n.y))


## The ease of a taper from `lo` at an edge (`x` 0) to 1 at its reach (`x` 1): steep at the edge,
## so the blanket's edge reads rounded. Pure.
static func taper(x: float, lo: float) -> float:
	var k := clampf(x, 0.0, 1.0)
	return lerpf(lo, 1.0, k * (2.0 - k))


## A slow sag and swell keyed to the world, about -1 to 1 (`phase` the structure's field phase).
## Pure.
static func sag(p: Vector3, phase: Vector3) -> float:
	var a := sin(p.x * 1.3 + phase.x + 0.7 * sin(p.z * 0.9 + phase.y))
	var b := sin(p.z * 1.1 + phase.z + 0.5 * sin(p.x * 0.7))
	return 0.65 * a * b + 0.35 * sin(p.x * 2.6 - p.z * 2.1 + phase.y)


## The blanket's thickness at fractions (`s` across from p0's side, `t` up from the eave) of
## layout `lay` (with its "t", "w0", "w1", "h", "phase" added by build) over world point `p`. Pure.
static func thickness(lay: Dictionary, s: float, t: float, p: Vector3) -> float:
	var f := tapers(lay, s, t)
	var pile := 1.0 + PILE * smoothstep(0.35, 1.0, t)
	var phase: Vector3 = lay["phase"]
	var c := 2.0 * s - 1.0
	# The lee keyed to the world (about 13 m a wave), so two slopes meeting at a ridge agree there.
	var lee := 1.0 + LEE * 0.5 * sin(p.x * 0.45 + p.z * 0.3 + phase.z)
	# A hip end's dome fades toward its apex, where every column meets one point (a dome there
	# stood up as a spike).
	var dome := DOME * (1.0 - c * c) * (1.0 - t if lay["top"] == "apex" else 1.0)
	var crown := (1.0 + dome) * lee
	return float(lay["t"]) * f * pile * crown * (1.0 + SAG * sag(p, phase) * smoothstep(0.0, 0.3, f))


## The product of the verge and eave tapers at (`s`, `t`) of layout `lay` (thickness() takes
## it): 1 in the field, a few hundredths at a verge's edge. Pure.
static func tapers(lay: Dictionary, s: float, t: float) -> float:
	var whole := float(lay["t"])
	var w := lerpf(float(lay["w0"]), float(lay["w1"]), t)
	var f := 1.0
	if lay["left"] == "verge":
		f *= taper(s * w / VERGE_R_M, VERGE_T_M / whole)
	if lay["right"] == "verge":
		f *= taper((1.0 - s) * w / VERGE_R_M, VERGE_T_M / whole)
	return f * taper(t * float(lay["h"]) / EAVE_R_M, minf(EAVE_T_M * float(lay["hold"]) / whole, 1.0))


## The blanket's thickness over map point `p` of `roof` (its plane's x and z; 0 off the slope), for
## a drift that sits on it. Pure.
static func depth_at(
	roof: Dictionary, lay: Dictionary, hold: float, p: Vector3, phase: Vector3
) -> float:
	var full := _frame(roof, lay, hold, phase)
	var p0: Vector3 = lay["p0"]
	var p1: Vector3 = lay["p1"]
	var v: Vector3 = roof["v"]
	var t := clampf((p - p0).dot(v) / maxf(float(full["h"]), 0.01), 0.0, 1.0)
	var along := (p1 - p0).normalized()
	var start := p0.lerp(lay["q0"], t)
	var w := maxf(lerpf(float(full["w0"]), float(full["w1"]), t), 0.01)
	var s := clampf((p - start).dot(along) / w, 0.0, 1.0)
	return thickness(full, s, t, p)


static func _frame(roof: Dictionary, lay: Dictionary, hold: float, phase: Vector3) -> Dictionary:
	var full := lay.duplicate()
	var p0: Vector3 = lay["p0"]
	var v: Vector3 = roof["v"]
	full["t"] = depth(roof, hold)
	full["hold"] = hold
	full["w0"] = p0.distance_to(lay["p1"])
	full["w1"] = (lay["q0"] as Vector3).distance_to(lay["q1"])
	full["h"] = maxf(((lay["q0"] as Vector3) - p0).dot(v), 0.01)
	full["phase"] = phase
	return full


## Grid stations from 0 to 1 over `length` metres: EDGE_STEPS in from the start (`lo`) and the end
## (`hi`), the field's step (`step` metres at most) between. Pure.
static func stations(
	length: float, lo: Array[float], hi: Array[float], step: float = FIELD_STEP_M
) -> PackedFloat32Array:
	var metres: Array[float] = []
	for d in lo:
		if d < length * 0.5:
			metres.append(d)
	var a := lo[lo.size() - 1] if lo[lo.size() - 1] < length * 0.5 else length * 0.5
	var b := length - (hi[hi.size() - 1] if hi[hi.size() - 1] < length * 0.5 else length * 0.5)
	var count := ceili((b - a) / step)
	for k in range(1, count):
		metres.append(lerpf(a, b, float(k) / count))
	for k in range(hi.size() - 1, -1, -1):
		if hi[k] < length * 0.5:
			metres.append(length - hi[k])
	if metres[metres.size() - 1] < length - 0.001:
		metres.append(length)
	var out := PackedFloat32Array()
	for m in metres:
		var x := clampf(m / maxf(length, 0.001), 0.0, 1.0)
		if out.is_empty() or x > out[out.size() - 1] + 0.001:
			out.append(x)
	return out


## Lays the blanket of `roof` (layout `lay`) into `g`. `partners`: {"ridge", "left", "right"} the
## normal of the other slope over that crest, absent for none; `hold` the roof material's;
## `phase` the structure's field phase; `seed` for the lip's scallops. Returns the triangles laid.
static func lay_into(
	g: PainterMannerSnow.Strips,
	roof: Dictionary,
	lay: Dictionary,
	partners: Dictionary,
	hold: float,
	phase: Vector3,
	seed: int
) -> int:
	var full := _frame(roof, lay, hold, phase)
	var n: Vector3 = roof["n"]
	var origin: Vector3 = roof["origin"]
	var u: Vector3 = roof["u"]
	var v: Vector3 = roof["v"]
	var p0: Vector3 = lay["p0"]
	var p1: Vector3 = lay["p1"]
	var q0: Vector3 = lay["q0"]
	var q1: Vector3 = lay["q1"]
	var mid := (p0 + p1 + q0 + q1) * 0.25
	var o_eave := PainterMannerSnow.outward(p0, p1, n, mid)
	var o_left := PainterMannerSnow.outward(p0, q0, n, mid)
	var o_right := PainterMannerSnow.outward(p1, q1, n, mid)
	var o_top := -o_eave if lay["top"] == "apex" else PainterMannerSnow.outward(q0, q1, n, mid)
	var w0 := float(full["w0"])
	# Columns: [s, kind] with kind 0 field, 1 a verge's roll, 2 its tuck, 3 a hip's crest; rows:
	# [t, kind] with kind 0 field, 1-3 the eave lip's round, front and tuck, 4 the ridge's crest,
	# 5 the close of a ridge with no other half.
	var cols: Array = []
	var side_steps: Array[float] = EDGE_STEPS
	var s_st := stations(w0, side_steps, side_steps, step_s)
	if lay["left"] == "verge":
		cols.append([0.0, 2])
		cols.append([0.0, 1])
	for k in s_st.size():
		var kind := 3 if (k == 0 and lay["left"] == "hip") else 0
		if k == s_st.size() - 1 and lay["right"] == "hip":
			kind = 3
		cols.append([s_st[k], kind])
	if lay["right"] == "verge":
		cols.append([1.0, 1])
		cols.append([1.0, 2])
	var rows: Array = [[0.0, 3], [0.0, 2], [0.0, 1]]
	var t_st := stations(float(full["h"]), EDGE_STEPS, TOP_STEPS)
	for k in t_st.size():
		rows.append([t_st[k], 0])
	var ridge_n: Variant = partners.get("ridge")
	if lay["top"] == "ridge":
		if ridge_n != null:
			rows[rows.size() - 1][1] = 4
		else:
			rows.append([1.0, 5])
	var nc := cols.size()
	var nr := rows.size()
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var shade := PackedFloat32Array()
	var thin := PackedFloat32Array()
	var fixed := PackedByteArray()
	pos.resize(nc * nr)
	nor.resize(nc * nr)
	shade.resize(nc * nr)
	thin.resize(nc * nr)
	fixed.resize(nc * nr)
	for ri in nr:
		var t := float(rows[ri][0])
		var rk := int(rows[ri][1])
		for ci in nc:
			var s := float(cols[ci][0])
			var ck := int(cols[ci][1])
			var base := p0.lerp(p1, s).lerp(q0.lerp(q1, s), t)
			var h := thickness(full, s, t, base)
			var at := base + n * h
			var dn := Vector3.ZERO
			var th := 1.0 - tapers(full, s, t)
			var sh := THIN_SHADE * pow(th, 1.5)
			thin[ri * nc + ci] = th
			var bent := false
			if ck == 1 or ck == 2:
				var o := o_left if s < 0.5 else o_right
				var tuck := ck == 2
				at += o * (VERGE_OVER_M * (0.3 if tuck else 1.0)) - n * (h + (0.06 if tuck else 0.015))
				# The roll turns halfway: turned whole, a shaded slope's verge facing the sun lit up
				# as a bright band (card painter-buildings-fix3).
				dn += (-n + o * 0.3) if tuck else (o * ROLL_TURN + n * (1.0 - ROLL_TURN))
				sh = maxf(sh, 0.6 if tuck else 0.2)
				bent = true
			elif ck == 3:
				var pn: Variant = partners.get("left" if s < 0.5 else "right")
				if pn != null:
					var m := (n + (pn as Vector3)).normalized()
					at = base + m * (h / maxf(m.dot(n), 0.3) + CREST_M * hold * smoothstep(0.0, 0.3, t))
					dn += m
					bent = true
			if rk >= 1 and rk <= 3:
				var along_m := s * w0
				var sw := PainterMannerSnow.swell(along_m, seed)
				var over := OVER_M * hold * sw
				var ends := minf(minf(s, 1.0 - s) * w0 / 0.4, 1.0)
				var droop := DROOP_M * hold * PainterMannerSnow.scallop(along_m, seed) * ends
				var he := h
				if rk == 1:
					at += o_eave * over * 0.65 - n * he * 0.25 - Vector3.UP * droop * 0.3
					dn += o_eave * 0.7 + n * 0.6
					sh = maxf(sh, 0.1)
				elif rk == 2:
					at += o_eave * over - n * he * 0.9 - Vector3.UP * droop * 0.8
					dn += o_eave - n * 0.1
					sh = maxf(sh, 0.4)
				else:
					at += o_eave * over * 0.3 - n * he * 1.5 - Vector3.UP * droop
					dn += -n * 0.8 + o_eave * 0.2
					sh = maxf(sh, 0.85)
				bent = true
			elif rk == 4:
				var m := (n + (ridge_n as Vector3)).normalized()
				at += m * (h / maxf(m.dot(n), 0.3) + CREST_M * hold) - n * h
				dn += m
				bent = true
			elif rk == 5:
				at = base - n * 0.03
				dn += o_top
				sh = maxf(sh, 0.3)
				bent = true
			var k := ri * nc + ci
			pos[k] = at
			nor[k] = dn
			shade[k] = sh
			fixed[k] = 1 if bent else 0
	for ri in nr:
		for ci in nc:
			var k := ri * nc + ci
			if fixed[k] == 1:
				continue
			var tu := pos[ri * nc + mini(ci + 1, nc - 1)] - pos[ri * nc + maxi(ci - 1, 0)]
			var tv := pos[mini(ri + 1, nr - 1) * nc + ci] - pos[maxi(ri - 1, 0) * nc + ci]
			var c := tu.cross(tv)
			if c.length_squared() < 1e-10:
				nor[k] = n
			else:
				c = (c if c.dot(n) > 0.0 else -c).normalized()
				nor[k] = c.lerp(n, THIN_FLAT * thin[k]).normalized()
	var size := Vector2(float(roof.get("u_len", 1.0)), float(roof.get("v_len", 1.0)))
	var acc := float(seed % 1000) / 1000.0
	var first := g.pos.size()
	for k in pos.size():
		var rel := pos[k] - origin
		var data := PackedFloat32Array([size.x, size.y, float(CODE) + 0.9 * shade[k], acc])
		g.put(pos[k], nor[k], Vector2(rel.dot(u), rel.dot(v)), data)
	var before := g.idx.size()
	for ri in nr - 1:
		g.band(first + ri * nc, first + (ri + 1) * nc, nc)
	return (g.idx.size() - before) / 3
