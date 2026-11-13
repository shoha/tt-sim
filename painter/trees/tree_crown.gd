class_name PainterTreeCrown
extends PainterTreeSkeleton
## The painted trees' crown: the foliage masses hung on a grown skeleton (_crown8) and the
## polyline walk it samples limbs with. PainterTreeGrowth extends it with 	ree(). Pure static
## functions, safe on a worker thread. Ported from the painterspike branch's
## spike/painter/family14.gd (_walk, _crown8), split out of the generator for the file cap.


## Points along a polyline from fraction `f0` of its length to its end, about a step apart, the
## end first: [position, direction, fraction].
static func _walk(p: PackedVector3Array, f0: float, step: float) -> Array:
	var total: float = 0.0
	for j: int in p.size() - 1:
		total += p[j].distance_to(p[j + 1])
	var out: Array = []
	if total < 0.01:
		return out
	var count: int = maxi(int(ceil(total * (1.0 - f0) / maxf(step, 0.05))), 1)
	for k: int in count + 1:
		var s: float = total * lerpf(1.0, f0, float(k) / float(count))
		var acc: float = 0.0
		for j: int in p.size() - 1:
			var seg: float = p[j].distance_to(p[j + 1])
			if acc + seg >= s - 0.0001 or j == p.size() - 2:
				var t: float = clampf((s - acc) / maxf(seg, 0.0001), 0.0, 1.0)
				out.append([p[j].lerp(p[j + 1], t), (p[j + 1] - p[j]).normalized(), s / total])
				break
			acc += seg
	return out


## The crown, laid along the skeleton. Returns how many clumps it made.
static func _crown8(
	out: Array[PainterTreeMass],
	sk: Sk,
	c: Dictionary,
	sp: Dictionary,
	centre: Vector3,
	live_top: float,
	vig_r: float,
	plates: bool
) -> int:
	var seed_v: int = c["seed"]
	var h: float = c["h"]
	var rc: float = c["rc"]
	var open: float = c["open"]
	var old: float = c["old"]
	var weep: float = c["weep"]
	var y_cb: float = c["y_cb"]
	var dense: float = clampf(float(sp["dense"]), 0.0, 1.0)
	var fill: float = clampf(float(sp["fill"]), 0.0, 1.0) if float(sp["fill"]) >= 0.0 else dense
	var flat: float = float(sp["clump_flat"]) * lerpf(1.15, 0.9, open)
	var wide: float = lerpf(1.0, 1.25, clampf(1.0 - flat, 0.0, 1.0))
	var cr: float = clampf(
		float(sp["clump"]) * (0.16 * rc + 0.28) * vig_r * lerpf(0.68, 1.0, dense), 0.2, 1.3
	)
	if plates:
		cr = clampf(float(sp["clump"]) * (0.2 * rc + 0.3) * vig_r, 0.3, 1.5)
	# Dense species overlap their clumps; airy ones keep them apart and the sky shows between.
	var sep: float = lerpf(1.3, 0.78, dense)
	var boughs: bool = plates and float(sp["boughs"]) > 0.5
	var billow: float = clampf(float(sp["billow"]), 0.0, 1.0)
	var juv: float = c["juv"]
	if juv > 0.0 and not plates:
		# Round 14: a young tree's clumps are in scale with it (a few big blobs were no species).
		cr = maxf(cr * lerpf(1.0, 0.7, juv), 0.2)
	if boughs:
		# A bough is a main dome with smaller ones beside it: fewer, further apart.
		sep = lerpf(1.5, 1.0, juv)
	var f_in: float = lerpf(0.62, 0.2, fill)
	if boughs and juv > 0.0:
		# Round 14: a young pine is clothed in to the stem (separate balls on bare limbs: pom-poms).
		f_in = lerpf(f_in, 0.08, juv)
	if float(sp["clothe"]) > 0.5:
		f_in = 0.04
	var flute: bool = float(sp["flute"]) > 0.5 and not plates
	var sprays: bool = float(sp["sprays"]) > 0.5 and not plates
	var flutes_a: Array = []
	var flutes_b: Array = []
	var spray_pts: Array = []
	var tassels: Array = []
	var strand_k: float = clampf(float(sp["strands"]), 0.0, 1.0)
	var strands: bool = strand_k > 0.01 and weep > 0.3
	var plate: float = clampf(float(sp["plate"]), 0.0, 1.0) * float(c["ft"])
	var bvar: float = clampf(float(sp["boughvar"]), 0.0, 1.0)
	var curtain: Array = []
	var lobes: int = clampi(int(sp["lobes"]), 1, 8)
	var ks: Array[float] = [1.0, 1.0, 0.85, 0.62]
	var n: int = sk.pts.size()
	var lobe_of: Dictionary = {0: 1}
	# A sample: [position, radius, limb group, direction, is a tip].
	var tips: Array = []
	var inner: Array = []
	var core: Array = []
	var hangs: Array = []
	for i: int in n:
		if sk.state[i] != 0:
			continue
		var p: PackedVector3Array = sk.pts[i]
		var tip: Vector3 = p[p.size() - 1]
		var ord: int = mini(sk.order[i], 3)
		var g: int = sk.grp[i]
		if i == 0 and sk.kids[0] > 0 and tip.y < h * 0.9:
			continue
		# Die-back takes some of the top limbs whole (a stag head).
		if (
			tip.y > live_top + 0.03 * h
			and live_top < h * 0.999
			and _h(seed_v, g, 30) < 0.5
			and not (i == 0 and old < 0.5)
		):
			continue
		if not lobe_of.has(g):
			var off: Vector3 = tip - _stem(c, tip.y)
			off.y = 0.0
			var v: float = (tip.y - y_cb) / maxf(live_top - y_cb, 0.01)
			if lobes <= 1 or v > 0.76 or off.length() < 0.22 * rc:
				lobe_of[g] = 1
			else:
				lobe_of[g] = (
					2
					+ (
						int(
							(
								fposmod(atan2(off.z, off.x) - float(c["phi0"]), TAU)
								/ TAU
								* float(lobes - 1)
							)
						)
						% (lobes - 1)
					)
				)
		var tip_dir: Vector3 = (tip - p[p.size() - 2]).normalized()
		var hanging: bool = weep > 0.3 and ord >= 1 and tip_dir.y < -0.45
		if flute:
			# Round 14 (poplar): narrow upright masses along each limb's own length, the end first.
			if i != 0 and (ord >= 3 or (ord == 2 and sk.length[i] < 1.1)):
				continue
			var fw: Array = _walk(p, 0.84 if i == 0 else (0.14 if ord <= 1 else 0.45), 0.85)
			for k: int in fw.size():
				var wd: float = (
					clampf(0.3 + 0.15 * rc, 0.4, 0.78)
					* (0.75 + 0.5 * _h(seed_v, i * 7 + k, 31))
					* (0.62 if k == 0 else 1.0)
					* (0.8 if ord >= 2 else 1.0)
				)
				# The foliage stands on the outer side of its limb (limbs hug the stem: a pencil).
				var fo: Vector3 = (fw[k][0] as Vector3) - _stem(c, (fw[k][0] as Vector3).y)
				fo.y = 0.0
				var fs14: Array = [
					(
						(fw[k][0] as Vector3)
						+ (fo.normalized() * wd * 0.55 if fo.length() > 0.05 else Vector3.ZERO)
					),
					fw[k][1],
					wd,
					g,
					k == 0,
					i * 7 + k
				]
				if ord <= 1:
					flutes_a.append(fs14)
				else:
					flutes_b.append(fs14)
			continue
		if sprays:
			# Round 14 (birch): points for small leaf tufts along the fine twigs, the end first.
			var f14: float = 0.86 if i == 0 else (0.5 if ord <= 1 else (0.2 if ord == 2 else 0.0))
			var sw14: Array = _walk(p, f14, 0.42)
			for k: int in sw14.size():
				spray_pts.append([sw14[k][0], g, i * 31 + k, k if ord >= 2 else k + 1])
			if ord >= 2 and tip_dir.y < -0.15:
				tassels.append([tip, g, i])
			continue
		if strands:
			# No clump anywhere: points for the curtain along the outer length, the end first.
			if i == 0 and float(sp["curve"]) > 0.0:
				# Round 13: the leader's own top carries twigs too (round 12 left it bare).
				var cw0: Array = _walk(p, 0.8, 0.36)
				for k: int in cw0.size():
					curtain.append([cw0[k][0], g, k, k, 0, cw0[k][1]])
			if i != 0:
				var fs: float = (
					0.3 if sk.order[i] == 0 else (0.25 if ord == 1 else (0.1 if ord == 2 else 0.0))
				)
				if float(sp["curve"]) > 0.0 and strand_k > 0.99:
					# Round 13: the forks are clothed from near the crotch (it stood bare on top).
					fs = 0.1 if ord <= 1 else fs
				# Round 13: a longer step, so the count reaches in along the limbs to the top of
				# the crown (round 12's ran out at the cap and left the upper limbs bare).
				var cw: Array = _walk(
					p,
					fs,
					(
						(0.52 if ord <= 1 else 0.8)
						if float(sp["curve"]) > 0.0 and strand_k > 0.99
						else 0.36
					)
				)
				# Round 13: the forks and limbs are clothed first, whole, then the twigs from their
				# ends (counted: of 469 points 298 were twigs', they came first and took 101 of the
				# 190 masses; the forks got 11 of their 27 and stood bare).
				var first13: bool = float(sp["curve"]) > 0.0 and strand_k > 0.99
				for k: int in cw.size():
					curtain.append(
						[
							cw[k][0],
							g,
							i * 31 + k,
							(0 if ord <= 1 else 1 + k) if first13 else k,
							sk.order[i],
							cw[k][1]
						]
					)
			continue
		if hanging:
			hangs.append(i)
		var f0: float = (
			1.0
			if i == 0
			else (0.55 if ord == 0 else (f_in if ord == 1 else (0.3 if ord == 2 else 0.6)))
		)
		var walk: Array = _walk(p, f0, cr * 0.8)
		for k: int in walk.size():
			var w: Array = walk[k]
			var d: Vector3 = w[1]
			if hanging and d.y < -0.45:
				continue
			var fr: float = clampf((float(w[2]) - f0) / maxf(1.0 - f0, 0.01), 0.0, 1.0)
			var r: float = (
				cr * ks[ord] * lerpf(0.78, 1.0, fr) * (0.86 + 0.28 * _h(seed_v, i * 7 + k, 31))
			)
			var s: Array = [w[0], r, g, d, k == 0]
			if k == 0:
				tips.append(s)
			else:
				inner.append(s)
	# A dense crown closes over its limbs: the HULL of the branch system. Per height band and
	# compass sector, how far the foliage points reach from the stem; smoothed over neighbours, so
	# the notch between two limbs fills; a clump stands on that surface in each cell (in most
	# cells for a middling species, which leaves sky where the branches part).
	var shell_k: float = smoothstep(0.35, 0.85, fill)
	if shell_k > 0.01 and not plates and tips.size() + inner.size() > 6:
		var y_lo: float = INF
		var y_hi: float = -INF
		for list: Array in [tips, inner]:
			for s: Array in list:
				y_lo = minf(y_lo, (s[0] as Vector3).y)
				y_hi = maxf(y_hi, (s[0] as Vector3).y)
		var band: float = cr
		var nb: int = clampi(int(ceil((y_hi - y_lo) / band)) + 1, 2, 16)
		var ns: int = 12
		var reach := PackedFloat32Array()
		reach.resize(nb * ns)
		for list: Array in [tips, inner]:
			for s: Array in list:
				var p: Vector3 = s[0]
				var off: Vector3 = p - _stem(c, p.y)
				off.y = 0.0
				var cell: int = (
					clampi(int((p.y - y_lo) / band), 0, nb - 1) * ns
					+ int(fposmod(atan2(off.z, off.x), TAU) / TAU * float(ns)) % ns
				)
				reach[cell] = maxf(reach[cell], off.length())
		for it: int in 2:
			var nxt: PackedFloat32Array = reach.duplicate()
			for b: int in nb:
				for q: int in ns:
					var m: float = maxf(
						reach[b * ns + (q + 1) % ns], reach[b * ns + (q + ns - 1) % ns]
					)
					if b > 0:
						m = maxf(m, reach[(b - 1) * ns + q])
					if b < nb - 1:
						m = maxf(m, reach[(b + 1) * ns + q])
					nxt[b * ns + q] = maxf(reach[b * ns + q], m * 0.84)
			reach = nxt
		for b: int in nb:
			for q: int in ns:
				var id: int = 9000 + b * ns + q
				# Cell by cell the surface stands a little in or out: a scalloped outline, not an egg.
				var rr: float = reach[b * ns + q] * (0.8 + 0.2 * _h(seed_v, id, 36))
				if billow > 0.01:
					# Three billows round the stem, turning as they climb, and tiers up it; in the
					# notch between two billows the hull is left open and the limbs' own clumps show.
					var azc: float = (float(q) + 0.5) / float(ns) * TAU
					var bk: float = (
						0.6 * (0.5 + 0.5 * sin(azc * 3.0 + float(c["phi0"]) + float(b) * 0.9))
						+ 0.4 * (0.5 + 0.5 * sin(float(b) * TAU / 3.3 + float(c["phi0"]) * 1.7))
					)
					rr *= lerpf(1.0, 0.6 + 0.55 * bk, billow)
					if bk < 0.3 and _h(seed_v, id, 37) < billow:
						continue
				if rr < cr * 0.6 or _h(seed_v, id, 33) > shell_k:
					continue
				var az: float = (
					(float(q) + 0.5 + (_h(seed_v, id, 34) - 0.5) * 0.5) / float(ns) * TAU
				)
				var r: float = (
					maxf(cr, rr * TAU / float(ns) * 0.55) * (0.85 + 0.3 * _h(seed_v, id, 35))
				)
				var y: float = y_lo + (float(b) + 0.5) * band
				var top_lobe: bool = lobes <= 1 or float(b) > 0.76 * float(nb)
				lobe_of[id] = (
					1
					if top_lobe
					else (
						2
						+ (
							int(fposmod(az - float(c["phi0"]), TAU) / TAU * float(lobes - 1))
							% (lobes - 1)
						)
					)
				)
				core.append(
					[
						_stem(c, y) + Vector3(cos(az), 0.0, sin(az)) * maxf(rr - r * 0.55, 0.0),
						r,
						id,
						Vector3.UP,
						false
					]
				)
	var acc: Array = []
	for list: Array in [tips, core, inner]:
		for s: Array in list:
			if acc.size() >= 200:
				break
			var ok: bool = true
			var ps: Vector3 = s[0]
			var rs: float = s[1]
			for a: Array in acc:
				if ps.distance_to(a[0]) < sep * 0.5 * (rs + float(a[1])):
					ok = false
					break
			if ok:
				acc.append(s)
	# Round 12: the highest bough of each limb (an old pine's plates are levelled to it).
	var gtop: Dictionary = {}
	if boughs and plate > 0.0:
		for s: Array in acc:
			gtop[s[2]] = maxf(float(gtop.get(s[2], -INF)), (s[0] as Vector3).y)
	for s: Array in acc:
		var r: float = s[1]
		var g: int = s[2]
		var at: Vector3 = (
			(s[0] as Vector3) - ((s[3] as Vector3) * r * 0.25 if s[4] else Vector3.ZERO)
		)
		var phase: float = _h(seed_v, g, 20)
		if boughs:
			var hk: float = lerpf(0.42, 0.28, float(c["ft"]))
			var d3: Vector3 = s[3]
			var bid: int = out.size()
			var sats: int = 2 if s[4] else 1
			if bvar > 0.0:
				r *= lerpf(1.0, 0.5 + 1.05 * pow(_h(seed_v, bid, 44), 1.4), bvar)
				sats = mini(int(_h(seed_v, bid, 45) * (3.0 if s[4] else 2.0)), 2)
			if plate > 0.0:
				hk = lerpf(hk, 0.17, plate)
				r *= 1.0 + 0.45 * plate
				at.y += minf(float(gtop.get(g, at.y)) - at.y, 0.8) * 0.8 * plate
			var dh := Vector3(d3.x, 0.0, d3.z)
			if dh.length() < 0.05:
				var ha: float = _h(seed_v, bid, 40) * TAU
				dh = Vector3(cos(ha), 0.0, sin(ha))
			dh = dh.normalized()
			var from: Vector3 = at - dh * r * 1.3 - Vector3.UP * r * 0.35
			var form: int = 100 + g % 800
			var bc: Vector3 = at + Vector3.UP * r * hk * 0.45
			out.append(_bough(bc, Vector3(r, r * hk + 0.08, r), form, centre, from, phase))
			for j: int in sats:
				var sa: float = (
					atan2(dh.z, dh.x)
					+ (0.9 + 0.8 * _h(seed_v, bid * 5 + j, 41)) * (1.0 if j == 0 else -1.0)
				)
				var sr: float = (
					r
					* (0.5 + 0.22 * _h(seed_v, bid * 5 + j, 42))
					* lerpf(1.0, 0.7 + 0.6 * _h(seed_v, bid * 5 + j, 46), bvar)
				)
				var sc: Vector3 = (
					bc
					+ Vector3(cos(sa), 0.0, sin(sa)) * r * 0.78
					+ Vector3.UP * r * hk * (0.3 * _h(seed_v, bid * 5 + j, 43) - 0.08)
				)
				out.append(
					_bough(sc, Vector3(sr, sr * hk * 1.15 + 0.06, sr), form, centre, from, phase)
				)
		elif plates:
			var pc: Vector3 = at + Vector3.UP * (r * 0.12 + 0.08)
			out.append(
				PainterTreeBase._tier(
					pc,
					Basis.IDENTITY,
					Vector3(r, r * 0.2 + 0.14, r),
					100 + g % 800,
					centre,
					pc + Vector3.UP * r * 0.4,
					0.15,
					phase,
					0.0
				)
			)
		else:
			out.append(
				PainterTreeBase._pad(
					at + Vector3.UP * r * flat * 0.3,
					Vector3(r * wide, r * flat, r * wide),
					int(lobe_of.get(g, 1)),
					centre,
					phase,
					false
				)
			)
	var made: int = acc.size()
	if flute:
		var put: Array[Vector3] = []
		for list: Array in [flutes_a, flutes_b]:
			for s: Array in list:
				if put.size() >= 170:
					break
				var at: Vector3 = s[0]
				var near: bool = false
				for q: Vector3 in put:
					if q.distance_to(at) < 0.36:
						near = true
						break
				if near:
					continue
				put.append(at)
				var g: int = s[3]
				var tip14: bool = s[4]
				var wd: float = s[2]
				# Upright along the limb; the end of a limb is a longer, thinner point (the ragged top).
				var d3: Vector3 = ((s[1] as Vector3) + Vector3.UP * 0.7).normalized()
				var xa: Vector3 = d3.cross(Vector3.RIGHT)
				xa = xa.normalized() if xa.length_squared() > 1e-4 else Vector3.FORWARD
				var ln: float = (0.95 if tip14 else 0.66) * (0.85 + 0.3 * _h(seed_v, int(s[5]), 72))
				var m: PainterTreeMass = PainterTreeBase._pad(
					at + d3 * (0.3 if tip14 else 0.0),
					Vector3(wd, ln, wd * 0.85),
					100 + g % 800,
					centre,
					_h(seed_v, g, 20),
					false
				)
				m.xform = Transform3D(Basis(xa, d3, xa.cross(d3)), m.xform.origin)
				out.append(m)
		made += put.size()
	if sprays:
		var cells14: Dictionary = {}
		var count14: int = 0
		for pass_k: int in 10:
			for s: Array in spray_pts:
				if int(s[3]) != pass_k or count14 >= 118:
					continue
				var ps: Vector3 = s[0]
				var key := Vector3i((ps / 0.5).floor())
				if cells14.has(key):
					continue
				cells14[key] = true
				var id: int = 14000 + int(s[2])
				# A tuft hangs under its twig: a little taller than wide, unequal.
				var r: float = (
					(0.15 + 0.13 * _h(seed_v, id, 51))
					* clampf(float(sp["clump"]), 0.6, 1.4)
					* vig_r
				)
				out.append(
					PainterTreeBase._pad(
						ps - Vector3.UP * r * 0.7,
						Vector3(r, r * (1.0 + 0.5 * _h(seed_v, id, 52)), r * 0.85),
						int(lobe_of.get(int(s[1]), 1)),
						centre,
						_h(seed_v, int(s[1]), 20),
						true
					)
				)
				count14 += 1
		# Only the outermost twig ends hang, and those tassels are thin and short.
		var hung14: int = 0
		for s: Array in tassels:
			var tp: Vector3 = s[0]
			var off: Vector3 = tp - _stem(c, tp.y)
			off.y = 0.0
			var rho: float = clampf(off.length() / maxf(rc, 0.1), 0.0, 1.2)
			var id: int = 15000 + int(s[2])
			if hung14 >= 36 or rho < 0.34 or _h(seed_v, id, 53) < 0.15:
				continue
			var drop: float = minf(
				(0.55 + 0.6 * _h(seed_v, id, 50)) * (0.7 + 0.5 * rho) * clampf(h / 9.0, 0.45, 1.0),
				tp.y - 0.4
			)
			if drop < 0.3:
				continue
			var rd: Vector3 = off.normalized() if off.length() > 0.05 else Vector3.RIGHT
			var td: Vector3 = Vector3.UP.cross(rd)
			var dn: Vector3 = (
				(Vector3.DOWN + rd * 0.06 + td * (_h(seed_v, id, 59) - 0.5) * 0.2).normalized()
			)
			var xa: Vector3 = (td + dn * td.dot(-dn)).normalized()
			var wd: float = 0.1 + 0.05 * _h(seed_v, id, 51)
			var m: PainterTreeMass = PainterTreeBase._pad(
				tp + dn * drop * 0.5,
				Vector3(wd, drop * 0.5, wd * 0.8),
				int(lobe_of.get(int(s[1]), 1)),
				centre,
				_h(seed_v, int(s[1]), 20),
				true
			)
			m.xform = Transform3D(Basis(xa, -dn, xa.cross(-dn)), m.xform.origin)
			m.params["bend"] = rd * drop * 0.12
			m.params["strands"] = true
			out.append(m)
			hung14 += 1
		made += count14 + hung14
	if strands:
		# The willow's curtain. One mass a cell of ground unless it would hang inside another;
		# the ends of every limb first, so no limb goes bare when the count runs out.
		var cells: Dictionary = {}
		var cell_m: float = 0.4
		var count: int = 0
		var cap: int = 190 if strand_k > 0.99 else 140
		var curve: float = clampf(float(sp["curve"]), 0.0, 1.0)
		var n_part: int = int(c["part"])
		var over: float = clampf(float(sp["over"]), 0.0, 1.0)
		var mounds: int = 0
		var mound_at: Array[Vector3] = []
		var hem_old: float = float(sp["hem"]) if float(sp["hem"]) > 0.0 else 0.2
		# A young tree's curtain ends well above the ground: its stem shows.
		var hem_out: float = (
			lerpf(0.46, hem_old, smoothstep(0.3, 0.75, float(c["age"]))) if curve > 0.0 else 0.2
		)
		for pass_k: int in 12:
			for s: Array in curtain:
				if int(s[3]) != pass_k:
					continue
				if count >= cap:
					continue
				var ps: Vector3 = s[0]
				var id: int = 12000 + int(s[2])
				var off: Vector3 = ps - _stem(c, ps.y)
				off.y = 0.0
				var rho: float = clampf(off.length() / maxf(rc, 0.1), 0.0, 1.2)
				# The hem: high near the stem (the limbs show), low at the outside, ragged.
				var hem: float = (
					h
					* lerpf(0.55, hem_out, smoothstep(0.2, 0.9, rho))
					* (0.55 + 0.9 * _h(seed_v, id, 50))
				)
				# Near the stem and over the top the strands are short: a mop, not a bare frame.
				var drop: float = clampf(
					ps.y - maxf(hem, 0.3), 0.55 + 0.5 * _h(seed_v, id, 52), h * 0.62
				)
				if strand_k < 0.99:
					# A birch: tassels, longer at the outside of the crown.
					drop = (
						(0.7 + 1.3 * rho)
						* (0.7 + 0.6 * _h(seed_v, id, 50))
						* strand_k
						* 2.2
						* (1.0 + 0.5 * curve)
					)
				if curve > 0.0:
					# A twig that already hangs below the hem carries nothing (round 12 gave it a
					# strand to the ground, which closed the curtain over the stem).
					if strand_k > 0.99 and ps.y - hem < 0.45:
						continue
					# Strand to strand: one in five is a short one.
					if _h(seed_v, id, 53) < 0.2:
						drop *= 0.45
					# A parting: under the limbs only tassels, so the trunk and the ground show.
					if rho > 0.26:
						var az_s: float = atan2(off.z, off.x)
						for pk: int in n_part:
							var pa: float = (
								float(c["part_az"])
								+ float(pk) * TAU / float(n_part)
								+ (_h(seed_v, 60 + pk, 54) - 0.5) * 0.9
							)
							var pw: float = (
								(0.32 + 0.25 * _h(seed_v, 60 + pk, 55))
								* (0.75 + 0.5 * _h(seed_v, id, 56))
							)
							if absf(angle_difference(az_s, pa)) < pw:
								drop = minf(
									drop,
									maxf(ps.y - 0.42 * h * (0.8 + 0.4 * _h(seed_v, id, 57)), 0.8)
								)
				drop = minf(drop, ps.y - 0.3)
				if drop < 0.35:
					continue
				var key := Vector2i(int(floor(ps.x / cell_m)), int(floor(ps.z / cell_m)))
				var top: float = ps.y + 0.12
				var ok: bool = true
				if cells.has(key):
					for span: Vector2 in cells[key]:
						if (
							top < span.x + 0.25
							and top > span.y + (0.5 if curve > 0.0 else 0.35) * (span.x - span.y)
						):
							ok = false
							break
				if not ok:
					continue
				if cells.has(key):
					(cells[key] as Array).append(Vector2(top, top - drop))
				else:
					cells[key] = [Vector2(top, top - drop)]
				var wdt: float = (
					clampf(0.24 + 0.04 * rc, 0.26, 0.42)
					* (0.8 + 0.45 * _h(seed_v, id, 51))
					* (1.0 if strand_k > 0.99 else 0.8)
				)
				var rd: Vector3 = off.normalized() if off.length() > 0.05 else Vector3.RIGHT
				var td: Vector3 = Vector3.UP.cross(rd)
				var m: PainterTreeMass = PainterTreeBase._pad(
					Vector3(ps.x, top - drop * 0.5, ps.z),
					Vector3(wdt, drop * 0.5, wdt * 0.6),
					int(lobe_of.get(int(s[1]), 1)),
					centre,
					_h(seed_v, int(s[1]), 20),
					true
				)
				m.xform = Transform3D(Basis(td, Vector3.UP, rd), m.xform.origin)
				if curve > 0.0:
					# Round 13: the strand hangs FROM the twig (its top is the twig), leans a little
					# (out from the stem near the top of the crown: a mop, not a cap) and bows out
					# before it falls; the shaders draw the bend and taper both ends to points.
					var wd13: float = (
						clampf(0.14 + 0.05 * rc, 0.18, 0.4)
						* (0.6 + 0.7 * _h(seed_v, id, 51))
						* (1.0 if strand_k > 0.99 else 0.7)
					)
					var lean_out: float = (
						lerpf(0.5, 0.04, smoothstep(0.08, 0.7, rho))
						+ (_h(seed_v, id, 58) - 0.35) * 0.16
					)
					# Near the stem a strand leans any way round its limb (a limb seen from the stem's
					# side stood bare in front of strands that all leaned outward); further out, outward.
					var rd13: Vector3 = rd.rotated(
						Vector3.UP,
						(_h(seed_v, id, 63) - 0.5) * TAU * (1.0 - smoothstep(0.12, 0.55, rho))
					)
					var dn: Vector3 = (
						(Vector3.DOWN + rd13 * lean_out + td * (_h(seed_v, id, 59) - 0.5) * 0.26)
						. normalized()
					)
					var xa: Vector3 = (td + dn * td.dot(-dn)).normalized()
					# Round 14: on the upper limbs a strand springs from above the limb and is broader
					# there, so the limb lies under its own foliage (it lay on top like a loose stick).
					var up14: bool = (
						over > 0.0 and strand_k > 0.99 and int(s[4]) <= 1 and ps.y > 0.45 * h
					)
					# A strand is widest a fifth of the way down: that part is put at the limb.
					var lift14: float = 0.08
					if up14:
						wd13 *= 1.6
						lift14 = clampf(drop * 0.22, 0.34, 0.85)
					var at13: Vector3 = Vector3(ps.x, ps.y + lift14, ps.z) + dn * drop * 0.5
					m.xform = Transform3D(Basis(xa, -dn, xa.cross(-dn)), at13)
					m.size = Vector3(wd13, drop * 0.5, wd13 * 0.8)
					var bow: float = (
						minf(drop * 0.3, 0.9) * (0.3 + 0.7 * _h(seed_v, id, 60)) * curve
					)
					m.params["bend"] = rd13 * bow + td * (_h(seed_v, id, 62) - 0.5) * 0.5 * bow
					if up14 and count < cap - 1:
						# Its twin falls to the other side of the limb, shorter: the limb is thatched
						# from both sides. (Tried and dropped: low mounds over the limb, another tone
						# than the strands; a sleeve of leaves lying along the limb, a spiky fan.)
						var dn2: Vector3 = (
							(
								Vector3.DOWN
								- rd13 * (lean_out + 0.3)
								- td * (_h(seed_v, id, 59) - 0.5) * 0.26
							)
							. normalized()
						)
						var xb: Vector3 = (td + dn2 * td.dot(-dn2)).normalized()
						var drop2: float = maxf(drop * 0.5, 0.5)
						var m2: PainterTreeMass = PainterTreeBase._pad(
							Vector3(ps.x, ps.y + lift14, ps.z) + dn2 * drop2 * 0.5,
							Vector3(wd13, drop2 * 0.5, wd13 * 0.8),
							int(lobe_of.get(int(s[1]), 1)),
							centre,
							_h(seed_v, int(s[1]), 20),
							true
						)
						m2.xform = Transform3D(Basis(xb, -dn2, xb.cross(-dn2)), m2.xform.origin)
						m2.params["bend"] = -rd13 * bow * 0.5
						m2.params["strands"] = true
						out.append(m2)
						count += 1
				m.params["strands"] = true
				out.append(m)
				count += 1
				if (
					over > 1.5
					and strand_k > 0.99
					and int(s[4]) <= 1
					and mounds < 24
					and rho < 0.85
					and ps.y > 0.45 * h
				):
					# Round 14, tried and switched off (over: 2 brings it back): a low mound over the
					# limb. It hid the limb but read as a cap of round dabs in another tone than the
					# strands (teal lumps at dusk), so the strands themselves cover the limb instead.
					var mr: float = (
						clampf(0.1 * rc + 0.35, 0.45, 0.95) * (0.8 + 0.4 * _h(seed_v, id, 71))
					)
					var far: bool = true
					for q: Vector3 in mound_at:
						if q.distance_to(ps) < mr * 1.1:
							far = false
							break
					if far:
						mound_at.append(ps)
						mounds += 1
						out.append(
							PainterTreeBase._pad(
								ps + Vector3.UP * (mr * 0.2 + 0.12),
								Vector3(mr, mr * 0.5, mr),
								int(lobe_of.get(int(s[1]), 1)),
								centre,
								_h(seed_v, int(s[1]), 20),
								true
							)
						)
		made += count + mounds
	# A hanging end: the leaf follows the twig down (a birch's tassel, a willow's curtain).
	var hung: Array[Vector3] = []
	for i: int in hangs:
		var p: PackedVector3Array = sk.pts[i]
		var tip: Vector3 = p[p.size() - 1]
		var ord: int = mini(sk.order[i], 3)
		var rb: float = cr * ks[ord]
		var top_y: float = tip.y
		for q: Vector3 in p:
			top_y = maxf(top_y, q.y)
		var ry: float = clampf((top_y - tip.y) * 0.5 + rb * 0.3, rb * 0.6, 4.0)
		var hang_w: float = rb * lerpf(0.75, 0.55, weep)
		var hc := Vector3(tip.x, tip.y + ry * 0.9, tip.z)
		var ok: bool = hung.size() < 150
		for q: Vector3 in hung:
			if q.distance_to(hc) < hang_w * 0.95:
				ok = false
				break
		if ok:
			hung.append(hc)
			out.append(
				PainterTreeBase._pad(
					hc,
					Vector3(hang_w, ry, hang_w),
					int(lobe_of.get(sk.grp[i], 1)),
					centre,
					_h(seed_v, sk.grp[i], 20),
					true
				)
			)
			made += 1
	return made
