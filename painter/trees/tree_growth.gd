class_name PainterTreeGrowth
extends PainterTreeCrown
## The painted trees' generator: `tree(species, context, seed, conifer)` grows the skeleton
## (PainterTreeSkeleton) and hangs the crown on it (PainterTreeCrown), as a list of
## PainterTreeMass. The context holds `age` (0 whip .. 1 old) and `openness` (0 forest-grown ..
## 1 open-grown); the same arguments always give the same masses. Pure static functions, safe
## on a worker thread. Ported from the painterspike branch's spike/painter/family14.gd (tree).


## The whole tree: skeleton strands, then the crown at the branch ends.
static func tree(
	sp: Dictionary, cx: Dictionary, rng_seed: int, conifer: bool
) -> Array[PainterTreeMass]:
	var c: Dictionary = {}
	var sk: Sk = skeleton(sp, cx, rng_seed, conifer, c)
	var out: Array[PainterTreeMass] = []
	var n: int = sk.pts.size()
	var h: float = c["h"]
	var g: float = c["g"]
	var old: float = c["old"]
	var age: float = c["age"]
	var open: float = c["open"]
	var rc: float = c["rc"]
	var weep: float = c["weep"]
	var plates: bool = conifer and float(sp["plates"]) > 0.5
	var vig: float = clampf(float(cx.get("vigour", sp["vigour"])), 0.2, 1.3)
	var vig_r: float = lerpf(0.7, 1.1, clampf(vig, 0.0, 1.0))
	# Die-back: the top tenth of an old tree stands bare (never on a species that flat-tops:
	# its crown IS its top).
	var live_top: float = (
		h
		* (
			1.0
			- (
				0.1
				* old
				* (0.0 if float(sp["flat_top"]) > 0.01 else 1.0)
				* clampf(float(sp["dieback"]), 0.0, 1.0)
			)
		)
	)
	var y_cb: float = c["y_cb"]
	var centre: Vector3 = (
		_stem(c, (y_cb + live_top) * 0.5)
		+ (
			Vector3((c["side_dir"] as Vector2).x, 0.0, (c["side_dir"] as Vector2).y)
			* float(c["side_len"])
			* rc
			* 0.3
		)
	)
	# Wind: a limb and all it carries share one phase; weight rises from the stem to the tips.
	var w0 := PackedFloat32Array()
	var w1 := PackedFloat32Array()
	w0.resize(n)
	w1.resize(n)
	for i: int in n:
		var p: PackedVector3Array = sk.pts[i]
		var par: int = sk.parent[i]
		if par < 0:
			w0[i] = W_STEM
			w1[i] = W_STEM
		else:
			var pp: PackedVector3Array = sk.pts[par]
			var fa: float = clampf(
				pp[sk.at[i]].distance_to(pp[0]) / maxf(pp[0].distance_to(pp[pp.size() - 1]), 0.01),
				0.0,
				1.0
			)
			w0[i] = lerpf(w0[par], w1[par], pow(fa, 1.5))
			w1[i] = (
				(w0[i] + 0.04)
				if sk.state[i] == 2
				else (
					W_PAD
					if sk.kids[i] == 0 or sk.order[i] >= 2
					else lerpf(w0[i], W_PAD, 0.3 if sk.order[i] == 0 else 0.75)
				)
			)
		var phase: float = 0.0 if sk.grp[i] == 0 else _h(rng_seed, sk.grp[i], 20)
		out.append(_strand(p, sk.rad[i], phase, w0[i], w1[i], sk.order[i] >= 3))
	out[0].params["stem"] = true
	# Buttress roots and the hollow of an old stem (round 5's).
	var hollow_az: float = PI * 0.5 + (_h(rng_seed, 5, 1) - 0.5) * 2.4
	if age > 0.4:
		var nb: int = 3 + int(old * 2.5)
		for k: int in nb:
			var ba: float = hollow_az + 0.4 + TAU * float(k) / float(nb)
			var bd := Vector3(cos(ba), 0.0, sin(ba))
			out.append(
				PainterTreeBase._strand(
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
	if old > 0.45 and not conifer:
		var hd := Vector3(cos(hollow_az), 0.0, sin(hollow_az))
		out.append(
			PainterTreeMass.make(
				PainterTreeMass.Shape.ELLIPSOID,
				Transform3D(Basis.IDENTITY, _stem(c, 0.5 + g * 1.4) + hd * g * 0.92),
				Vector3(g * 0.42, g * 0.95, g * 0.34),
				PainterTreeMass.Role.TRIM,
				{"spacing": 0.2, "wind": 0.0, "phase": 0.0}
			)
		)

	# The crown: every live axis of order 0 to 2 ends in foliage. What stands above the live top
	# of an old tree has died back and stays bare.
	var flat: float = float(sp["clump_flat"]) * lerpf(1.15, 0.9, open)
	var wide: float = lerpf(1.0, 1.25, clampf(1.0 - flat, 0.0, 1.0))
	var clump: float = sp["clump"]
	var dense: float = sp["dense"]
	var pads: int = 0
	var whorl_len: Dictionary = {}
	var whorl_at: Dictionary = {}
	# Round 8: every crown but the spruce's is laid along the skeleton (see _crown8).
	if plates or not conifer:
		pads = _crown8(out, sk, c, sp, centre, live_top, vig_r, plates)
	for i: int in n if conifer and not plates else 0:
		if sk.state[i] != 0 or sk.order[i] >= 3:
			continue
		var p: PackedVector3Array = sk.pts[i]
		var tip: Vector3 = p[p.size() - 1]
		var base: Vector3 = p[0]
		var ord: int = sk.order[i]
		var length: float = minf(sk.length[i], 2.2) if ord == 0 else sk.length[i]
		if i == 0 and sk.kids[0] > 0 and tip.y < h * 0.9:
			continue
		# Die-back takes some of the top limbs whole (a stag head), not a slice off the crown.
		if (
			tip.y > live_top + 0.03 * h
			and live_top < h * 0.999
			and _h(rng_seed, sk.grp[i], 30) < 0.5
			and not (i == 0 and old < 0.5)
		):
			continue
		var phase: float = _h(rng_seed, sk.grp[i], 20)
		var dir: Vector3 = (tip - p[p.size() - 2]).normalized()
		var form: int = sk.grp[i]
		if conifer and not plates:
			# Spruce: one long flat frond mass along each bough; its whorl is one form group.
			if ord != 1:
				continue
			var a: Vector3 = p[0].lerp(tip, 0.24)
			var chord: Vector3 = tip - a
			var bl: float = chord.length()
			if bl < 0.25:
				continue
			var bx: Vector3 = chord / bl
			var bz: Vector3 = bx.cross(Vector3.UP)
			bz = bz.normalized() if bz.length_squared() > 1e-4 else Vector3.RIGHT
			var by: Vector3 = bz.cross(bx).normalized()
			var wkey: int = int(round(base.y * 20.0))
			var stem_at: Vector3 = _stem(c, base.y)
			var dj: float = clampf(float(c["sag"]) * (0.7 + 0.5 * old), 0.1, 1.2)
			out.append(
				PainterTreeBase._tier(
					a + chord * 0.52,
					Basis(bx, by, bz),
					(
						Vector3(bl * 0.56, bl * 0.13 + 0.13, bl * 0.36 + 0.12)
						* Vector3(1.0, vig_r, vig_r)
					),
					100 + wkey % 800,
					centre,
					stem_at + Vector3.UP * bl * 0.35,
					dj,
					phase
				)
			)
			whorl_len[wkey] = maxf(float(whorl_len.get(wkey, 0.0)), bl)
			whorl_at[wkey] = stem_at
			pads += 1
			continue
		if plates:
			# Pine: a flat plate of needles at each bough and branch end; each its own layer.
			var pr: float = clampf(
				(0.5 * length if ord == 2 else 0.3 * length) * clump * vig_r + 0.16, 0.3, 1.5
			)
			var pc: Vector3 = tip + Vector3.UP * (pr * 0.12 + 0.08) - dir * pr * 0.2
			out.append(
				PainterTreeBase._tier(
					pc,
					Basis.IDENTITY,
					Vector3(pr, pr * 0.2 + 0.14, pr),
					100 + i % 800,
					centre,
					pc + Vector3.UP * pr * 0.4,
					0.15,
					phase,
					0.0
				)
			)
			pads += 1
			continue
		var rb: float = clampf(
			((0.55 if ord == 2 else 0.3) * length + 0.2) * clump * vig_r, 0.22, maxf(rc * 0.45, 0.3)
		)
		var drop: float = base.y - tip.y
		if weep > 0.3 and ord >= 1 and dir.y < -0.45:
			# A hanging end: the leaf follows the twig down as a curtain.
			var top_y: float = base.y
			for q: Vector3 in p:
				top_y = maxf(top_y, q.y)
			var ry: float = clampf((top_y - tip.y) * 0.5 + rb * 0.3, rb * 0.6, 4.0)
			var hang_w: float = rb * lerpf(0.75, 0.55, weep)
			out.append(
				PainterTreeBase._pad(
					Vector3(tip.x, tip.y + ry * 0.9, tip.z) - dir * 0.05,
					Vector3(hang_w, ry, hang_w),
					form,
					centre,
					phase,
					true
				)
			)
			if ord == 1 or drop < 0.0:
				out.append(
					PainterTreeBase._pad(
						p[p.size() / 2] + Vector3.UP * rb * 0.25,
						Vector3(rb * 0.9, rb * 0.6, rb * 0.9),
						form,
						centre,
						phase,
						false
					)
				)
				pads += 1
		else:
			out.append(
				PainterTreeBase._pad(
					tip + Vector3.UP * rb * flat * 0.3 - dir * rb * 0.25,
					Vector3(rb * wide, rb * flat, rb * wide),
					form,
					centre,
					phase,
					false
				)
			)
		pads += 1
		# A dense species is clothed along the limb as well (lime, poplar).
		if dense > 0.6 and ord == 1 and length > 1.4:
			var mr: float = rb * 1.05
			out.append(
				PainterTreeBase._pad(
					p[p.size() / 2] + Vector3.UP * mr * flat * 0.3,
					Vector3(mr, mr * flat, mr),
					form,
					centre,
					phase,
					false
				)
			)
	if conifer and not plates:
		# The dense heart of each whorl, and the leader's tip.
		for wkey: int in whorl_len:
			var rj: float = float(whorl_len[wkey]) * 0.66
			if rj > (0.12 if float(sp["spire"]) > 0.5 else 0.3):
				var at: Vector3 = whorl_at[wkey]
				out.append(
					PainterTreeBase._tier(
						at - Vector3.UP * rj * 0.25,
						Basis.IDENTITY,
						Vector3(rj, rj * 0.3 + 0.14, rj),
						100 + wkey % 800,
						centre,
						at + Vector3.UP * rj * 0.5,
						0.5,
						_h(rng_seed, wkey, 21)
					)
				)
		var top_key: int = -1
		for wkey: int in whorl_at:
			# The spire starts at the highest whorl of some size, so it also clothes the neck of
			# stem under the last small whorls.
			if float(sp["spire"]) > 0.5 and float(whorl_len[wkey]) < 0.6 and whorl_len.size() > 2:
				continue
			if top_key < 0 or (whorl_at[wkey] as Vector3).y > (whorl_at[top_key] as Vector3).y:
				top_key = wkey
		if top_key < 0:
			for wkey: int in whorl_at:
				if top_key < 0 or (whorl_at[wkey] as Vector3).y > (whorl_at[top_key] as Vector3).y:
					top_key = wkey
		if float(sp["spire"]) > 0.5 and top_key >= 0:
			# Round 13: the leader is a fine point that continues the top whorl: three short
			# fronded masses narrowing to the tip, in the top whorl's form group (its light).
			# Round 12's was one fat capsule with a group of its own on a bare neck of stem.
			var sp1: PackedVector3Array = sk.pts[0]
			var tip1: Vector3 = sp1[sp1.size() - 1]
			var y0: float = (whorl_at[top_key] as Vector3).y
			var gap: float = maxf(tip1.y + 0.2 - y0, 0.4)
			var r_top: float = clampf(float(whorl_len[top_key]) * 0.5, 0.14, 0.6)
			if float(sp["juv"]) > 0.0:
				# Round 14: a broad-based spire (a long gap under a thin point was a bare spike).
				r_top = clampf(maxf(r_top, gap * 0.24), 0.14, 0.95)
			var rks: Array[float] = [0.9, 0.62, 0.38, 0.17]
			for k: int in 4:
				var f: float = (float(k) + 0.5) / 4.0
				var rr: float = r_top * rks[k] + 0.03
				var yk: float = y0 + gap * f
				var at1: Vector3 = _stem(c, yk) if yk < tip1.y else Vector3(tip1.x, yk, tip1.z)
				out.append(
					PainterTreeBase._tier(
						at1,
						Basis.IDENTITY,
						Vector3(rr, gap * (0.16 if k < 3 else 0.2), rr),
						100 + top_key % 800,
						centre,
						at1 + Vector3.UP * gap * 0.3,
						1.3,
						_h(rng_seed, top_key, 21)
					)
				)
		elif old < 0.5:
			var tr2: float = clampf(rc * 0.12, 0.16, 0.5)
			var sp0: PackedVector3Array = sk.pts[0]
			var tc: Vector3 = sp0[sp0.size() - 1] - Vector3.UP * tr2 * 0.9
			out.append(
				PainterTreeBase._tier(
					tc,
					Basis.IDENTITY,
					Vector3(tr2, tr2 * 2.6, tr2),
					99,
					centre,
					tc + Vector3.UP * tr2 * 3.0,
					1.2,
					0.5
				)
			)
	# Never a bare pole: a tree with next to no crown keeps a tuft on its topmost live ends.
	if pads < 3:
		var done: int = 0
		for i: int in range(n - 1, -1, -1):
			if sk.state[i] == 2 or sk.order[i] >= 3 or done >= 3:
				continue
			var p: PackedVector3Array = sk.pts[i]
			var r: float = clampf(0.06 * h, 0.2, 0.7)
			if conifer:
				out.append(
					PainterTreeBase._tier(
						p[p.size() - 1],
						Basis.IDENTITY,
						Vector3(r, r * 0.5, r),
						100 + i % 800,
						centre,
						p[p.size() - 1] + Vector3.UP * r,
						0.3,
						0.3,
						0.0 if plates else 1.0
					)
				)
			else:
				out.append(
					PainterTreeBase._pad(
						p[p.size() - 1], Vector3(r, r * 0.8, r), sk.grp[i], centre, 0.3, false
					)
				)
			done += 1
	# A skirt of basal shoots (lime).
	var skirt: float = sp["skirt"]
	if skirt > 0.01 and age > 0.3:
		var foot: Vector3 = sk.pts[0][0]
		var count: int = 5 + int(3.0 * skirt)
		var shoots: bool = float(sp["shoots"]) > 0.5
		if shoots:
			count = 11
		for k: int in count:
			var az: float = (
				_h(rng_seed, 6, 1) * TAU
				+ TAU * float(k) / float(count)
				+ (_h(rng_seed, 700 + k, 1) - 0.5) * 0.5
			)
			var r: float = (
				(0.26 + 0.2 * _h(rng_seed, 700 + k, 2))
				* skirt
				* (0.7 + 0.6 * age)
				* (1.0 + 0.45 * float(sp["billow"]))
			)
			var d := Vector3(cos(az), 0.0, sin(az))
			if shoots:
				# Round 14: a ring of many thin upright sprays close against the foot, lit as one
				# (six sprays standing off the trunk read as separate bushes stuck to it).
				r *= 0.7
				var top14: Vector3 = (
					foot
					+ d * (g + 0.05 + r * 0.5)
					+ Vector3.UP * (0.25 + r * (2.6 + 2.2 * _h(rng_seed, 700 + k, 3)))
				)
				out.append(
					PainterTreeBase._pad(
						top14 - Vector3.UP * r * 1.3,
						Vector3(r * 0.6, r * 1.9, r * 0.6),
						80,
						foot + Vector3.UP * 0.5,
						_h(rng_seed, 700 + k, 4),
						false
					)
				)
				continue
			var tip: Vector3 = (
				foot
				+ d * (g + 0.2 + r * 0.6)
				+ Vector3.UP * (0.35 + r * 1.7 + 0.5 * _h(rng_seed, 700 + k, 3))
			)
			var ph: float = _h(rng_seed, 700 + k, 4)
			out.append(
				PainterTreeBase._strand(
					PackedVector3Array([foot + d * g * 0.9, tip]),
					PackedFloat32Array([0.035, 0.024]),
					ph,
					0.05,
					0.35
				)
			)
			if float(sp["browse"]) > 0.0:
				# Round 13: upright sprays of shoots lit as one ring, not a few round bushes.
				out.append(
					PainterTreeBase._pad(
						tip - Vector3.UP * r * 0.5,
						Vector3(r * 0.62, r * 1.9, r * 0.62),
						80,
						foot + Vector3.UP * 0.5,
						ph,
						false
					)
				)
				continue
			out.append(
				PainterTreeBase._pad(
					tip, Vector3(r, r * 1.5, r), 80 + k, foot + Vector3.UP * 0.5, ph, false
				)
			)
	return out

