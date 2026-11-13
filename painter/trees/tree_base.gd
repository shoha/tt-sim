class_name PainterTreeBase
extends RefCounted
## Round 5 FORM generators: two tree families that answer the same PLACE axes. Pure functions:
## masses out, no colour, no mesh.
##
##   broadleaf(species, context, seed)   limbs carry leaf pads; the crown is an ENVELOPE (a
##       profile of revolution set by the species) and every limb grows from the stem to its
##       own point on that envelope, so the silhouette is the species' and the limbs show
##       between the stem and the pads.
##   conifer(species, context, seed)     whorled tiers on one leader; a tier is one form group.
##
## Context axes, each valid along its whole range:
##   age       0 whip .. 0.3 young .. 0.6 mature (fullest) .. 1 old: limbs LOST (snags), a dead
##             top or stag-headed limb above the leaf, heavier limbs, flared base, a hollow
##   openness  0 forest-grown (tall clean bole with stubs, high narrow crown, limbs angled up)
##             .. 1 open-grown (short bole, low heavy spreading limbs, crown wider than tall)
##   lean      Vector2: the stem leans that way and the whole crown goes with it
##   side      Vector2: the crown reaches further that way and less the other
##   vigour    pad size and how many side branches a limb carries
##   room      8 floats (optional): free radius per compass sector; in a closed stand a limb
##             reaches into a gap and stops where it meets the neighbour
## A tree GROWS along age: all random draws are taken up front and every limb has a fixed
## place and birth age, so a small change of any axis is a small change of the tree.
## Wind: a limb and everything it carries share one phase, and a strand's weight rises from
## the stem's to the pad's along its length (params.wind .. params.wind_tip).
##
## Ported from the painterspike branch's spike/painter/family5.gd: PainterTreeSkeleton and
## PainterTreeGrowth build on its helpers (the stem, strands, pads, tiers, the envelope).

const GOLDEN: float = 2.39996323
const W_STEM: float = 0.12
const W_PAD: float = 0.6


## A form number: `props[key]` read as a float (a number or its text), else `fallback`.
static func num(props: Dictionary, key: String, fallback: float) -> float:
	if not props.has(key):
		return fallback
	var text := str(props[key])
	return text.to_float() if text.is_valid_float() else fallback


static func species_of(props: Dictionary) -> Dictionary:
	return {
		"height": num(props, "height", 8.0),
		"spread": num(props, "spread", 0.6),
		"girth": num(props, "girth", 0.4),
		"limbs": num(props, "limbs", 6.0),
		"limb_angle": num(props, "limb-angle", 55.0),
		"leader": num(props, "leader", 0.5),
		"clump": num(props, "clump", 1.0),
		"clump_flat": num(props, "clump-flat", 0.8),
		"droop": num(props, "droop", 0.2),
		"weep": num(props, "weep", 0.0),
		"vigour": num(props, "vigour", 0.85),
		"crook": num(props, "crook", 0.4),
		"bole": num(props, "bole", 1.0),
		"widest": num(props, "widest", 0.35),
		"top": num(props, "top", 2.0),
		"dense": num(props, "dense", 0.4),
		"tiers": num(props, "tiers", 8.0),
		"plates": num(props, "plates", 0.0)
	}


static func _stem_at(y: float, h: float, lean: Vector2, wob: Vector2, amp: float) -> Vector3:
	var u: float = y / maxf(h, 0.01)
	var off: Vector2 = lean * h * 0.55 * pow(maxf(u, 0.0), 1.25)
	off += Vector2(sin(u * 5.0 + wob.x), sin(u * 4.1 + wob.y)) * amp * minf(u, 1.2)
	return Vector3(off.x, y, off.y)


static func _strand(
	pts: PackedVector3Array, radii: PackedFloat32Array, phase: float, w0: float, w1: float
) -> PainterTreeMass:
	return PainterTreeMass.make(
		PainterTreeMass.Shape.STRAND,
		Transform3D.IDENTITY,
		Vector3.ONE,
		PainterTreeMass.Role.BARK,
		{
			"pts": pts,
			"radii": radii,
			"level": 1,
			"spacing": 0.26,
			"wind": w0,
			"wind_tip": w1,
			"phase": phase
		}
	)


static func _pad(
	c: Vector3, r: Vector3, form: int, centre: Vector3, phase: float, hang: bool
) -> PainterTreeMass:
	var params: Dictionary = {
		"form": form, "centre": centre, "spacing": 0.4, "wind": W_PAD, "phase": phase
	}
	if hang:
		params["grain"] = Vector3.DOWN
	return PainterTreeMass.make(
		PainterTreeMass.Shape.ELLIPSOID,
		Transform3D(Basis.IDENTITY, c),
		r,
		PainterTreeMass.Role.LEAF,
		params
	)


## The crown's profile: radius (0..1) at height v (0 crown base .. 1 top). `widest` is where
## it is widest, `top_p` the roundness above that (1 a cone, 2 a dome, 3.5 a flat-topped box).
static func _env(v: float, widest: float, top_p: float, base_r: float) -> float:
	if v < widest:
		var t: float = v / maxf(widest, 0.01)
		return lerpf(base_r, 1.0, t * (2.0 - t))
	var s: float = clampf((v - widest) / maxf(1.0 - widest, 0.01), 0.0, 1.0)
	return pow(maxf(1.0 - pow(s, top_p), 0.0), 1.0 / top_p)


## In a closed stand a limb takes the room there is: it reaches into a gap and stops where
## the neighbour's crown begins. Open-grown trees ignore their neighbours.
static func _fit_room(reach: float, az: float, room: PackedFloat32Array, open: float) -> float:
	if room.size() != 8:
		return reach
	var f: float = fposmod(az, TAU) / TAU * 8.0
	var i0: int = int(f) % 8
	var r: float = lerpf(room[i0], room[(i0 + 1) % 8], f - floorf(f))
	var closed_reach: float = clampf(r * 1.12, reach * 0.55, reach * 1.75)
	return lerpf(closed_reach, reach, smoothstep(0.35, 0.85, open))


static func _along(p0: Vector3, pa: Vector3, pb: Vector3, p3: Vector3, t: float) -> Vector3:
	if t < 0.36:
		return p0.lerp(pa, t / 0.36)
	if t < 0.7:
		return pa.lerp(pb, (t - 0.36) / 0.34)
	return pb.lerp(p3, (t - 0.7) / 0.3)


static func broadleaf(sp: Dictionary, cx: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var age: float = clampf(float(cx.get("age", 0.5)), 0.0, 1.0)
	var open: float = clampf(float(cx.get("openness", 0.5)), 0.0, 1.0)
	var lean: Vector2 = cx.get("lean", Vector2.ZERO)
	var side: Vector2 = cx.get("side", Vector2.ZERO)
	var vig: float = clampf(float(cx.get("vigour", sp["vigour"])), 0.2, 1.3)
	var room: PackedFloat32Array = cx.get("room", PackedFloat32Array())
	var sp_h: float = sp["height"]
	var sp_leader: float = sp["leader"]
	var crook: float = sp["crook"]
	var dense: float = sp["dense"]
	var weep: float = sp["weep"]
	var droop: float = sp["droop"]
	var widest: float = sp["widest"]
	var top_p: float = sp["top"]
	var nmax: int = clampi(int(float(sp["limbs"])), 3, 14)
	# Every random draw, up front and always the same count.
	var phi0: float = rng.randf() * TAU
	var wob := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var r_az := PackedFloat32Array()
	var r_v := PackedFloat32Array()
	var r_len := PackedFloat32Array()
	var r_ph := PackedFloat32Array()
	var r_dead := PackedFloat32Array()
	var r_k1 := PackedFloat32Array()
	var r_k2 := PackedFloat32Array()
	var r_sub := PackedFloat32Array()
	for i: int in nmax:
		r_az.append(rng.randf())
		r_v.append(rng.randf())
		r_len.append(rng.randf())
		r_ph.append(rng.randf())
		r_dead.append(rng.randf())
		r_k1.append(rng.randf())
		r_k2.append(rng.randf())
		r_sub.append(rng.randf())
	var hollow_az: float = PI * 0.5 + rng.randf_range(-1.2, 1.2)
	var stub_az: float = rng.randf() * TAU
	var top_ph: float = rng.randf()
	var stag_side: int = (nmax / 2 + rng.randi() % 2) % nmax

	var old: float = smoothstep(0.7, 1.0, age)
	var young: float = 1.0 - smoothstep(0.15, 0.5, age)
	var full: float = smoothstep(0.12, 0.55, age)
	var grow: float = 0.22 + 0.78 * (1.0 - pow(1.0 - minf(age / 0.72, 1.0), 1.7))
	var rgrow: float = 0.1 + 0.9 * pow(age, 0.85)
	var leader: float = clampf(sp_leader + 0.2 * (1.0 - open) + 0.6 * young, 0.0, 1.0)
	var h: float = sp_h * grow * lerpf(1.22, 0.84, open)
	var g: float = maxf(
		0.03,
		(
			float(sp["girth"])
			* (0.07 + 0.93 * pow(age, 1.3))
			* lerpf(0.85, 1.1, open)
			* (1.0 + 0.22 * old)
		)
	)
	var cb: float = clampf(
		(
			lerpf(lerpf(0.4, 0.62, 1.0 - young), lerpf(0.04, 0.22, 1.0 - young), open)
			* float(sp["bole"])
		),
		0.03,
		0.72
	)
	var rc: float = maxf(0.3, 0.5 * float(sp["spread"]) * sp_h * rgrow * lerpf(0.55, 1.0, open))
	var y_min: float = cb * h
	# Retrenchment: the live crown of an old tree is lower than the tree once was.
	var crown_top: float = h * (1.0 - 0.17 * old)
	var h_fork: float = minf(h * lerpf(cb + (1.0 - cb) * 0.18, 0.96, leader), crown_top)
	var amp: float = (0.2 * g + 0.03 * h * crook) * (0.6 + 0.6 * old)
	var top_r: float = lerpf(0.62, 0.2, leader)
	var vig_r: float = lerpf(0.7, 1.1, clampf(vig, 0.0, 1.0))
	var side_len: float = minf(side.length(), 1.0)
	var side_dir: Vector2 = side.normalized() if side_len > 0.001 else Vector2.ZERO
	var centre: Vector3 = (
		_stem_at((y_min + crown_top) * 0.5, h, lean, wob, amp)
		+ Vector3(side_dir.x, 0.0, side_dir.y) * side_len * rc * 0.3
	)
	var excurrent: bool = sp_leader > 0.5

	var out: Array[PainterTreeMass] = []
	# The stem: flared at the foot, thick up to the fork. An old leader species keeps its dead
	# top standing above the live crown.
	var stem_top: float = h * 0.98 if (excurrent and old > 0.7) else h_fork
	var tp := PackedVector3Array()
	var tr := PackedFloat32Array()
	tp.append(_stem_at(0.0, h, lean, wob, amp))
	tr.append(g * (1.05 + 0.3 * old))
	tp.append(_stem_at(minf(0.06 * h, 0.5), h, lean, wob, amp))
	tr.append(g * 1.05)
	for k: int in range(1, 6):
		var fk: float = float(k) / 5.0
		tp.append(_stem_at(lerpf(minf(0.06 * h, 0.5), stem_top, fk), h, lean, wob, amp))
		tr.append(maxf(0.028, g * lerpf(1.0, top_r, fk)))
	out.append(_strand(tp, tr, 0.0, W_STEM, W_STEM))
	# Buttress roots.
	if age > 0.4:
		var nb: int = 3 + int(old * 2.5)
		for k: int in nb:
			var ba: float = hollow_az + 0.4 + TAU * float(k) / float(nb)
			var bd := Vector3(cos(ba), 0.0, sin(ba))
			out.append(
				_strand(
					PackedVector3Array(
						[
							bd * g * 0.5 + Vector3.UP * (g * 1.0 + 0.15 * old),
							bd * g * (1.2 + 0.3 * old) + Vector3.UP * g * 0.4,
							bd * g * (1.8 + 0.6 * old) + Vector3.UP * 0.04
						]
					),
					PackedFloat32Array([g * 0.5, g * 0.4, g * 0.2]),
					0.0,
					0.0,
					0.0
				)
			)
	# A hollow in the old stem.
	if old > 0.45:
		var hy: float = 0.5 + g * 1.4
		var hd := Vector3(cos(hollow_az), 0.0, sin(hollow_az))
		out.append(
			PainterTreeMass.make(
				PainterTreeMass.Shape.ELLIPSOID,
				Transform3D(Basis.IDENTITY, _stem_at(hy, h, lean, wob, amp) + hd * g * 0.92),
				Vector3(g * 0.42, g * 0.95, g * 0.34),
				PainterTreeMass.Role.TRIM,
				{"spacing": 0.2, "wind": 0.0, "phase": 0.0}
			)
		)
	# Stubs of the lower limbs a forest-grown tree has shed.
	if open < 0.55 and age > 0.3:
		var ns: int = int((1.0 - open) * 4.5 * smoothstep(0.3, 0.6, age))
		for k: int in ns:
			var sa: float = stub_az + float(k) * 2.1
			var sy: float = y_min * (0.35 + 0.6 * float(k) / float(maxi(ns, 1)))
			var s0: Vector3 = _stem_at(sy, h, lean, wob, amp)
			var sd: Vector3 = Vector3(cos(sa), 0.55, sin(sa)).normalized()
			out.append(
				_strand(
					PackedVector3Array([s0, s0 + sd * (g * 0.8 + 0.3 + 0.3 * fposmod(sa, 1.0))]),
					PackedFloat32Array([maxf(0.035, g * 0.24), 0.028]),
					0.0,
					W_STEM,
					W_STEM
				)
			)

	# Which limbs exist, live or dead.
	var s_of := PackedFloat32Array()
	var n_live: int = 0
	for i: int in nmax:
		var birth: float = 0.42 * float((i * 5) % nmax) / float(nmax)
		var s_i: float = smoothstep(birth - 0.12, birth + 0.2, age)
		s_of.append(s_i)
		if s_i >= 0.15 and not (r_dead[i] < 0.22 * old):
			n_live += 1
	var flat: float = float(sp["clump_flat"]) * lerpf(1.15, 0.9, open)
	var n_sub: int = clampi(
		int(round(2.0 * full * (1.0 - 0.6 * old) * clampf(vig, 0.4, 1.1) * (0.55 + 0.9 * dense))),
		0,
		3
	)

	# The leader's own pads: the tuft of a young tree, the top of a leader species, and the
	# core that fills a dense crown.
	if leader > 0.5 and not (excurrent and old > 0.7):
		var rt: float = clampf(rc * lerpf(0.5, 0.3, full) * vig_r, 0.2, 2.2)
		var ry: float = rt * maxf(flat, 1.0) * lerpf(1.7, 1.2, full)
		out.append(
			_pad(
				_stem_at(crown_top - ry * 0.85, h, lean, wob, amp),
				Vector3(rt, ry, rt),
				0,
				centre,
				top_ph,
				false
			)
		)
	var core_r: float = rc * 0.6 * vig_r * smoothstep(0.55, 0.9, dense) * (1.0 - 0.7 * old) * full
	if core_r > 0.45:
		out.append(
			_pad(
				_stem_at(lerpf(y_min, crown_top, 0.5), h, lean, wob, amp),
				Vector3(core_r, core_r * maxf(flat, 1.0) * 1.25, core_r),
				0,
				centre,
				fposmod(top_ph + 0.4, 1.0),
				false
			)
		)

	# Limbs: each from the stem to its own point on the envelope.
	for i: int in nmax:
		var s_i: float = s_of[i]
		if s_i < 0.15:
			continue
		# Pads keep to the upper part of the crown zone, so the limbs rise bare from the fork
		# to carry them; a dense species and a young tree are clothed lower down.
		var v: float = lerpf(
			lerpf(0.1, lerpf((0.36 + 0.14 * old) * (0.35 + 0.65 * open), 0.1, dense), full),
			0.97,
			(float(i) + 0.25 + 0.5 * r_v[i]) / float(nmax)
		)
		var az: float = phi0 + float(i) * GOLDEN + (r_az[i] - 0.5) * 0.6
		var dirh := Vector2(cos(az), sin(az))
		var d3 := Vector3(dirh.x, 0.0, dirh.y)
		var sidew: float = clampf(1.0 + side_len * 1.1 * dirh.dot(side_dir), 0.25, 1.8)
		var shade: float = lerpf(lerpf(0.5, 1.0, smoothstep(0.0, 0.6, v)), 1.0, open)
		var reach: float = (
			rc
			* _env(v, widest, top_p, 0.62)
			* (0.82 + 0.3 * r_len[i])
			* sidew
			* shade
			* lerpf(0.55, 1.0, s_i)
		)
		# Where a limb reaches further to fill a gap, its pads grow with it: closed crowns meet.
		var fitted: float = _fit_room(reach, az, room, open)
		var gain: float = lerpf(
			1.0, clampf(fitted / maxf(reach, 0.05), 0.6, lerpf(1.3, 0.95, old)), 0.7
		)
		reach = maxf(fitted, 0.12)
		var dead: bool = r_dead[i] < 0.22 * old
		# Two bare limbs on an old tree: the dead top, and one reaching out beside the leaf.
		var stag: bool = old > 0.25 and ((i == nmax - 1 and not excurrent) or i == stag_side)
		if stag and i == stag_side:
			reach *= 1.3
		var y_tip: float = lerpf(y_min, crown_top, v)
		var th: float = (
			deg_to_rad(float(sp["limb_angle"])) * lerpf(0.55, 1.12, open) * lerpf(1.1, 0.75, v)
		)
		var rise: float = reach / tan(clampf(th, 0.12, 1.5))
		var y_att: float = clampf(
			y_tip - rise, minf(y_min, h_fork), maxf(minf(h_fork, y_tip), minf(y_min, h_fork))
		)
		var p0: Vector3 = _stem_at(y_att, h, lean, wob, amp)
		var p3: Vector3 = _stem_at(y_tip, h, lean, wob, amp) + d3 * reach
		if stag and i != stag_side:
			p3 += Vector3.UP * (h * 0.13 + reach * 0.4) + d3 * reach * 0.2
		var chord: Vector3 = p3 - p0
		var length: float = chord.length()
		var perp: Vector3 = d3.cross(Vector3.UP)
		var k1: float = (r_k1[i] - 0.5) * 2.0
		var k2: float = (r_k2[i] - 0.5) * 2.0
		var elbow: float = clampf(crook * 0.7 + 0.25 * open, 0.0, 0.9)
		var flat_c := Vector3(chord.x, 0.0, chord.z)
		var pa: Vector3 = p0.lerp(p3, 0.36).lerp(
			p0 + flat_c * 0.5 + Vector3.UP * chord.y * 0.12, elbow
		)
		var pb: Vector3 = p0.lerp(p3, 0.7).lerp(
			p0 + flat_c * 0.86 + Vector3.UP * chord.y * 0.5, elbow
		)
		pa += (perp * k1 + Vector3.UP * k2 * 0.6) * length * 0.14 * crook
		pb += (
			(perp * (-k1 * 0.7) + Vector3.UP * (0.2 - k2 * 0.4)) * length * 0.12 * crook
			+ Vector3.UP * droop * length * 0.16
		)
		var r0: float = clampf(
			(
				g
				* lerpf(1.0, top_r, clampf(y_att / maxf(h_fork, 0.01), 0.0, 1.0))
				* 0.62
				* sqrt(clampf(length / (rc * 1.3), 0.15, 1.2))
				* (1.0 + 0.5 * old)
			),
			0.028,
			g * 0.8
		)
		if dead and not stag:
			# A snag: the limb broke off part way.
			if length > 0.5:
				out.append(
					_strand(
						PackedVector3Array([p0, pa, pa.lerp(pb, 0.55)]),
						PackedFloat32Array([r0, r0 * 0.78, r0 * 0.55]),
						r_ph[i],
						W_STEM,
						0.2
					)
				)
			continue
		if length > 0.3:
			out.append(
				_strand(
					PackedVector3Array([p0, pa, pb, p3]),
					PackedFloat32Array([r0, r0 * 0.8, r0 * 0.55, maxf(r0 * 0.28, 0.026)]),
					r_ph[i],
					W_STEM,
					W_PAD
				)
			)
		if stag:
			# The stag head: a bare antler above or beside the leaf, with one fork.
			var fd: Vector3 = (
				(Vector3.UP * 0.8 + perp * (0.7 if k1 > 0.0 else -0.7) - d3 * 0.2).normalized()
			)
			out.append(
				_strand(
					PackedVector3Array([pb, pb + fd * length * 0.32]),
					PackedFloat32Array([r0 * 0.45, 0.03]),
					r_ph[i],
					0.4,
					W_PAD
				)
			)
			var fd2: Vector3 = (
				(Vector3.UP * 0.5 - perp * (0.8 if k1 > 0.0 else -0.8) + d3 * 0.3).normalized()
			)
			out.append(
				_strand(
					PackedVector3Array([pa.lerp(pb, 0.5), pa.lerp(pb, 0.5) + fd2 * length * 0.26]),
					PackedFloat32Array([r0 * 0.5, 0.03]),
					r_ph[i],
					0.3,
					0.5
				)
			)
			continue
		# Pads are small against the crown, so sky shows between them unless the species is dense.
		var rb: float = (
			sp["clump"]
			* rc
			* lerpf(0.42, 0.3, clampf(float(n_live) / 7.0, 0.0, 1.0))
			* vig_r
			* (0.85 + 0.3 * r_len[i])
			* lerpf(0.6, 1.0, s_i)
			* (1.0 - 0.12 * old)
			* gain
		)
		rb = clampf(minf(rb, maxf(reach * 0.8, 0.24)), 0.22, 3.0)
		var hang: bool = weep > 0.5
		var wide: float = lerpf(1.0, 1.25, clampf(1.0 - flat, 0.0, 1.0))
		var tip_r := Vector3(rb * wide, rb * flat, rb * wide)
		var tip_c: Vector3 = p3 + Vector3.UP * rb * flat * 0.45 - d3 * rb * 0.1
		if hang:
			tip_r = Vector3(rb * 0.9, rb * 0.62, rb * 0.9)
			tip_c = p3 + Vector3.UP * rb * 0.15
		out.append(_pad(tip_c, tip_r, i + 1, centre, r_ph[i], false))
		if hang and length > 0.6:
			# A hanging curtain below the limb's end.
			var hc: Vector3 = p3 + d3 * rb * 0.35 - Vector3.UP * rb * (0.7 + 0.5 * droop)
			out.append(
				_pad(
					hc,
					Vector3(rb * 0.34, rb * (0.8 + 0.7 * droop), rb * 0.34),
					i + 1,
					centre,
					r_ph[i],
					true
				)
			)
		if dense > 0.6 and length > 1.2:
			var mr: float = rb * 1.05
			out.append(
				_pad(
					pa.lerp(pb, 0.6) + Vector3.UP * mr * flat * 0.3,
					Vector3(mr, mr * flat, mr),
					i + 1,
					centre,
					r_ph[i],
					false
				)
			)
		if length > 1.3:
			for s: int in n_sub:
				var t_at: float = 0.52 + 0.2 * float(s) + 0.1 * r_sub[i]
				var base: Vector3 = _along(p0, pa, pb, p3, t_at)
				var turn: float = (
					(0.8 + 0.5 * fposmod(r_sub[i] * 7.3 + float(s) * 0.37, 1.0))
					* (1.0 if (s + i) % 2 == 0 else -1.0)
				)
				var sd3: Vector3 = d3.rotated(Vector3.UP, turn)
				var sl: float = length * (0.44 - 0.07 * float(s)) * (0.8 + 0.4 * r_k2[i])
				var q: Vector3 = (
					base
					+ (
						(
							(
								sd3 * 0.85
								+ Vector3.UP * (0.55 - droop * 0.8) * (1.0 if s == 0 else -0.3)
							)
							. normalized()
						)
						* sl
					)
				)
				var w_at: float = lerpf(
					W_STEM,
					W_PAD,
					pow(clampf(base.distance_to(p0) / maxf(length, 0.01), 0.0, 1.0), 1.5)
				)
				out.append(
					_strand(
						PackedVector3Array([base, base.lerp(q, 0.5) + Vector3.UP * sl * 0.08, q]),
						PackedFloat32Array([r0 * 0.5, r0 * 0.36, maxf(r0 * 0.2, 0.024)]),
						r_ph[i],
						w_at,
						W_PAD
					)
				)
				var sr: float = maxf(rb * 0.86, 0.22)
				out.append(
					_pad(
						q + Vector3.UP * sr * flat * 0.4,
						Vector3(sr * wide, sr * flat * (0.62 if hang else 1.0), sr * wide),
						i + 1,
						centre,
						r_ph[i],
						false
					)
				)
				if hang and s == 0:
					out.append(
						_pad(
							q - Vector3.UP * sr * (0.65 + 0.5 * droop),
							Vector3(sr * 0.32, sr * (0.75 + 0.7 * droop), sr * 0.32),
							i + 1,
							centre,
							r_ph[i],
							true
						)
					)
	return out


# ---------------------------------------------------------------- conifers


static func _tier(
	c: Vector3,
	basis: Basis,
	r: Vector3,
	form: int,
	centre: Vector3,
	apex: Vector3,
	droop: float,
	phase: float,
	frond: float = 1.0
) -> PainterTreeMass:
	return PainterTreeMass.make(
		PainterTreeMass.Shape.ELLIPSOID,
		Transform3D(basis, c),
		r,
		PainterTreeMass.Role.LEAF,
		{
			"form": form,
			"centre": centre,
			"spacing": 0.4,
			"wind": 0.45,
			"phase": phase,
			"evergreen": 1.0,
			"frond": frond,
			"radial": apex,
			"droop": droop
		}
	)


## A conifer: whorled tiers on a single leader. `plates` 0 is a spruce (a skirted cone of
## drooping whorls), 1 a pine (a bare bole carrying a few flat pads on visible limbs).
static func conifer(sp: Dictionary, cx: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var age: float = clampf(float(cx.get("age", 0.5)), 0.0, 1.0)
	var open: float = clampf(float(cx.get("openness", 0.5)), 0.0, 1.0)
	var lean: Vector2 = cx.get("lean", Vector2.ZERO)
	var vig: float = clampf(float(cx.get("vigour", sp["vigour"])), 0.2, 1.3)
	var room: PackedFloat32Array = cx.get("room", PackedFloat32Array())
	var plates: float = sp["plates"]
	var pine: bool = plates > 0.5
	var sp_h: float = sp["height"]
	var crook: float = sp["crook"]
	var droop: float = sp["droop"]
	var nt_max: int = clampi(int(float(sp["tiers"])), 3, 12)
	var phi0: float = rng.randf() * TAU
	var wob := Vector2(rng.randf() * TAU, rng.randf() * TAU)
	var r_gap := PackedFloat32Array()
	var r_az := PackedFloat32Array()
	var r_ph := PackedFloat32Array()
	var r_len := PackedFloat32Array()
	for j: int in 12:
		r_gap.append(rng.randf())
		r_az.append(rng.randf())
		r_ph.append(rng.randf())
		r_len.append(rng.randf())

	var old: float = smoothstep(0.7, 1.0, age)
	var young: float = 1.0 - smoothstep(0.15, 0.5, age)
	var grow: float = 0.14 + 0.86 * (1.0 - pow(1.0 - minf(age / 0.75, 1.0), 1.6))
	var rgrow: float = 0.12 + 0.88 * pow(age, 0.8)
	var h: float = sp_h * grow * lerpf(1.15, 0.9, open)
	var g: float = maxf(
		0.03,
		(
			float(sp["girth"])
			* (0.07 + 0.93 * pow(age, 1.3))
			* lerpf(0.85, 1.12, open)
			* (1.0 + 0.3 * old)
		)
	)
	var cb_open: float = (
		lerpf(0.03, lerpf(0.05, 0.38, plates), 1.0 - young) + 0.14 * old * (1.0 - plates)
	)
	var cb: float = clampf(lerpf(lerpf(0.3, 0.7, 1.0 - young), cb_open, open), 0.02, 0.76)
	var rc: float = maxf(0.25, 0.5 * float(sp["spread"]) * sp_h * rgrow * lerpf(0.55, 1.0, open))
	var live_top: float = h * (1.0 - 0.17 * old)
	var amp: float = 0.15 * g + 0.02 * h * crook
	var vig_r: float = lerpf(0.75, 1.08, clampf(vig, 0.0, 1.0))
	var centre: Vector3 = _stem_at((cb * h + live_top) * 0.5, h, lean, wob, amp)

	var out: Array[PainterTreeMass] = []
	# The leader. An old spruce keeps a dead spike above its live crown; an old pine ends in
	# its flat top.
	var stem_top: float = live_top * 0.98 if (pine or old < 0.2) else h
	var tp := PackedVector3Array()
	var tr := PackedFloat32Array()
	tp.append(_stem_at(0.0, h, lean, wob, amp))
	tr.append(g * (1.15 + 0.5 * old))
	for k: int in range(1, 7):
		var fk: float = float(k) / 6.0
		tp.append(_stem_at(stem_top * fk, h, lean, wob, amp))
		tr.append(maxf(0.026, g * lerpf(1.0, 0.3 if pine else 0.1, fk)))
	out.append(_strand(tp, tr, 0.0, W_STEM, W_STEM))
	# Dead lower snags on the bare bole.
	if age > 0.3:
		var ns: int = int(clampf(cb * h / 1.2, 0.0, 6.0) * maxf(1.0 - open, old * 0.8))
		for k: int in ns:
			var sa: float = phi0 + float(k) * 2.3
			var sy: float = cb * h * (0.3 + 0.65 * float(k) / float(maxi(ns, 1)))
			var s0: Vector3 = _stem_at(sy, h, lean, wob, amp)
			var sl: float = 0.35 + rc * 0.3 * r_len[k % 12]
			out.append(
				_strand(
					PackedVector3Array(
						[s0, s0 + Vector3(cos(sa), -0.22, sin(sa)).normalized() * sl]
					),
					PackedFloat32Array([maxf(0.035, g * 0.2), 0.026]),
					0.0,
					W_STEM,
					W_STEM
				)
			)

	var nt: int = clampi(
		int(
			round(
				(
					float(nt_max)
					* lerpf(0.3, 1.0, smoothstep(0.05, 0.6, age))
					* lerpf(0.55, 1.0, 1.0 - cb)
				)
			)
		),
		2,
		nt_max
	)
	for j: int in nt:
		var v: float = (float(j) + 0.5) / float(nt)
		var y: float = lerpf(cb * h, live_top, v)
		var shade: float = lerpf(lerpf(0.55, 1.0, smoothstep(0.0, 0.5, v)), 1.0, open)
		var rj: float = 0.0
		if pine:
			rj = rc * _env(v, lerpf(0.45, 0.8, old), 2.6, 0.6) * shade * vig_r
		else:
			rj = rc * lerpf(1.0, 0.13, pow(v, 0.9)) * shade * vig_r * (0.9 + 0.2 * r_len[j])
		rj = maxf(rj, 0.2)
		var at: Vector3 = _stem_at(y, h, lean, wob, amp)
		var top_tier: bool = j == nt - 1
		if not top_tier and j % 2 == 1 and r_gap[j] < 0.55 * old:
			# A lost whorl: two dead boughs where it was.
			for k: int in 2:
				var ga: float = r_az[j] * TAU + float(k) * 2.6
				out.append(
					_strand(
						PackedVector3Array(
							[at, at + Vector3(cos(ga), -0.15, sin(ga)).normalized() * rj * 0.6]
						),
						PackedFloat32Array([maxf(0.035, g * 0.22), 0.026]),
						r_ph[j],
						W_STEM,
						0.25
					)
				)
			continue
		var dj: float = droop * (0.7 + 0.5 * old + 0.3 * (1.0 - v))
		if pine:
			var kn: int = 1 if top_tier else clampi(int(1.5 + rj * 1.1), 2, 4)
			for k: int in kn:
				var pa: float = phi0 + r_az[j] * TAU + TAU * float(k) / float(kn)
				var d3 := Vector3(cos(pa), 0.0, sin(pa))
				var reach: float = (
					0.0
					if top_tier
					else _fit_room(
						rj * (0.8 + 0.3 * fposmod(r_len[j] * 3.7 + float(k) * 0.31, 1.0)),
						pa,
						room,
						open
					)
				)
				# The plates of one whorl sit at different heights: layers with sky between.
				var step_y: float = (live_top - cb * h) / float(nt)
				var tip: Vector3 = (
					at + d3 * reach + Vector3.UP * (float(k) - float(kn - 1) * 0.5) * step_y * 0.32
				)
				var pr: float = maxf(rj * (0.8 if top_tier else 0.46), 0.3)
				if reach > 0.5:
					var p0: Vector3 = _stem_at(
						maxf(y - reach * 0.4, cb * h * 0.9), h, lean, wob, amp
					)
					var mid: Vector3 = p0 + d3 * reach * 0.6 + Vector3.UP * (tip.y - p0.y) * 0.3
					var r0: float = maxf(0.03, g * lerpf(0.5, 0.3, v))
					out.append(
						_strand(
							PackedVector3Array([p0, mid, tip]),
							PackedFloat32Array([r0, r0 * 0.7, maxf(r0 * 0.35, 0.026)]),
							r_ph[j],
							W_STEM,
							0.45
						)
					)
				var pc: Vector3 = tip + Vector3.UP * (pr * 0.12 + 0.1)
				out.append(
					_tier(
						pc,
						Basis.IDENTITY,
						Vector3(pr, pr * 0.2 + 0.14, pr),
						100 + j * 4 + k,
						centre,
						pc + Vector3.UP * pr * 0.4,
						0.15,
						r_ph[j],
						0.0
					)
				)
		else:
			var apex: Vector3 = at + Vector3.UP * rj * 0.35
			out.append(
				_tier(
					at - Vector3.UP * rj * dj * 0.3,
					Basis.IDENTITY,
					Vector3(rj, rj * 0.27 + 0.16, rj),
					100 + j,
					centre,
					apex,
					dj,
					r_ph[j]
				)
			)
			if rj > 0.8:
				var kn2: int = clampi(int(rj * 2.6), 3, 6)
				for k: int in kn2:
					var ba: float = r_az[j] * TAU + TAU * float(k) / float(kn2)
					var bd := Vector3(cos(ba), 0.0, sin(ba))
					var bx: Vector3 = (bd - Vector3.UP * dj).normalized()
					var bz: Vector3 = bd.cross(Vector3.UP).normalized()
					var by: Vector3 = bz.cross(bx).normalized()
					out.append(
						_tier(
							at + bd * rj * 0.92 - Vector3.UP * rj * dj * 0.8,
							Basis(bx, by, bz),
							Vector3(rj * 0.34, rj * 0.1 + 0.1, rj * 0.2),
							100 + j,
							centre,
							apex,
							dj,
							r_ph[j]
						)
					)
	# The tip of a spruce that still has one.
	if not pine and old < 0.5:
		var tr2: float = clampf(rc * 0.12, 0.18, 0.5)
		var tc: Vector3 = _stem_at(live_top - tr2 * 0.6, h, lean, wob, amp)
		out.append(
			_tier(
				tc,
				Basis.IDENTITY,
				Vector3(tr2, tr2 * 2.6, tr2),
				100 + nt,
				centre,
				tc + Vector3.UP * tr2 * 3.0,
				1.2,
				top_ph_of(r_ph)
			)
		)
	return out


static func top_ph_of(r_ph: PackedFloat32Array) -> float:
	return fposmod(r_ph[0] + 0.5, 1.0)
