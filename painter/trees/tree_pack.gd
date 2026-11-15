class_name PainterTreePack
extends RefCounted
## The painted trees' pack: a tree's PainterTreeMass list as texels of a data texture, which the
## painted tree shaders read to build the block-in and every stroke in the vertex stage. Pure
## static functions, safe on a worker thread. Ported from the painterspike branch's
## spike/painter/painter12.gd and painter13.gd (the spike's PPainter13.pack); the research
## rounds' notes follow.
##
## Round 12: round 11's pack with one more ellipsoid flag:
##   512   a willow's hanging strand mass (params "strands"): the shaders taper it to a hem
## Round 11: round 10's pack with three additions (the layouts are unchanged):
##   strand header flag 8    the stem: only it keeps the root flare
##   ellipsoid flag 256      a pine bough (params "bough"): needle flicks at its edge, flat below
##   neighbours              found through a coarse grid over the whole tree
## Round 10: a tree's paint is its MASS LIST in a data texture; the shaders derive the block-in
## and every stroke from it. Nothing per stroke or
## per vertex is made on the CPU.
##
## pack(masses, seed) -> {"data": PackedFloat32Array, ...}: the tree's texels (RGBA float), laid
## out from the tree's base texel as
##   [0, 9 * n_ell)            ellipsoid records, nine texels each
##   [str_base, seg_base)      strands: two header texels, then one texel per point
##   [seg_base, slot_base)     the segment table, one texel per strand segment (block-in tubes)
##   [slot_base, +n_slots)     the slot table, one texel per run of 8 stroke roots
## Ellipsoid record:
##   0 centre xyz, role (0 leaf, 8 evergreen, 5 trim)
##   1 axis x times radius x, flags (1 frond, 4 has form, 16 blend with the whole crown,
##     32 radial grain, 64 grain hangs, 128 tone leans on `centre`)
##   2 axis y times radius y, wind phase      3 axis z times radius z, wind weight
##   4 form group centre, size of the mass    5 form group radii, root spacing (level 0)
##   6 tone centre, number of roots           7 radial point, droop
##   8 seed, shadow strokes (before thinning), shadow stroke size, 0
## Strand header: (straight length, wind phase, wind weight, wind weight at the tip),
##   (points, flags: 1 block-in only, 2 under a crown, 4 wind ramps along it, root spacing, seed);
##   then (point xyz, radius) per point.
## Segment table texel: (strand header address, segment index, 0, 0).
## Slot table texel: ellipsoid (record address, -1, roots, first root of this slot);
##   strand (header address, segment index, steps + 256 * around, first root of this slot).
## All addresses are relative to the tree's base texel. A layer is 256 x 256 texels.

const W: int = 256
const LAYER_TEXELS: int = 65536
const ELL_T: int = 10
## Roots a slot: 2, not 8, since a bark segment has about two roots and every quad of a slot
## past its roots is a vertex-stage dead end (8 a slot left half the quads of a tree dead).
const ROOTS: int = 2
## Whether the slot table holds the bark strokes' slots. The shipped stroke uniforms carry
## wood19 = 1 (tree_uniforms.json, every season): a limb is ONE stroke drawn by the block-in pass
## and no separate bark stroke rides on it, so the stroke shader drops every bark stroke after
## deriving it. Their slots were 40 to 60 percent of a tree's instance vertices
## (painter-perf-derive, 2026-11-14: forest 40 %, taiga 60 % of the strokes of every level), all
## dead; a test pins this constant to the json's wood19.
const BARK_STROKES: bool = false
const ELL_PER_INST: int = 16
const SEG_PER_INST: int = 32
const SLOT_PER_INST: int = 64
const SHADOW_PER_INST: int = 64
## The mass sphere's tessellation (painter-perf-shadow: 8 x 5 was 80 triangles a sphere, 6 x 3 is
## 36; the block-in's cost followed its triangles, -0.2 to -0.45 ms at the forest and taiga views)
## and the factor its x and z are inflated by so the coarser solid keeps the 8 x 5's volume (the
## polygon cuts the sphere's corners: 6 x 3 holds 0.62 of a sphere against 0.81).
const ELL_SEGS: int = 6
const ELL_RINGS: int = 3
const ELL_FIT: float = 1.146
const TUBE_SIDES: int = 4
const TREE_W: int = 8
## The first radius (metres) under which a frond tree's (a spruce's) strand that starts inside the
## crown is not packed, the stem apart (painter-perf-taiga: a bough lies inside its own fronds and
## its whorl's dense heart, so its ribbon and bark strokes never showed; -0.5 ms at the taiga
## view, pixels unchanged). A spruce's boughs are 1 to 9 cm at the ages the game grows. 0 keeps
## every strand (the spike's own trees, which the port test compares).
const BOUGH_R: float = 0.1
## Metres the token pre-test (tree_token_near) allows past a tree's box (tree_row's texels 5 and 6)
## for a stroke's size, shift and lift and the wind's sway; the shaders' TREE_BOX_PAD, which a test
## pins to this, and the cells' engine box (PainterTrees.BOUND_GROW) use the same. The per-tree view
## cull (tree_view_box) has its own, smaller margin (view_margin) and is on (painter-perf-cull).
const BOUND_PAD: float = 2.5
## Stroke root spacing in metres per mass role (PainterTreeMass.Role), the research painter's.
const SPACING: Array[float] = [0.34, 0.17, 0.24, 0.30, 0.30, 0.16, 0.70]


static func _h01(v: int) -> float:
	return fposmod(sin(float(v % 100003) * 12.9898) * 43758.5453, 1.0)


## A tree's masses packed for the painted tree shaders (the layout above), with round 13's
## addition: a strand mass (ellipsoid flag 512) whose params hold "bend" carries that vector in
## texel 7 (xyz; otherwise used only by masses with a radial point, flag 32). The shaders move a
## point of the mass by bend * (1 - (1 - t)^2), t = 0 at the twig .. 1 at the hem.
static func pack(
	masses: Array[PainterTreeMass],
	rng_seed: int,
	shadow_k: float = 3.0,
	wide: int = 1,
	bough_r: float = BOUGH_R,
	bark: bool = BARK_STROKES
) -> Dictionary:
	var d: Dictionary = _pack12(masses, rng_seed, shadow_k, wide, bough_r, bark)
	var data: PackedFloat32Array = d["data"]
	var ei: int = 0
	var any: bool = false
	for m: PainterTreeMass in masses:
		if m.shape != PainterTreeMass.Shape.ELLIPSOID:
			continue
		if m.params.has("bend"):
			var b: Vector3 = m.params["bend"]
			var w: int = ei * ELL_T * 4 + 28
			data[w] = b.x
			data[w + 1] = b.y
			data[w + 2] = b.z
			any = true
		ei += 1
	if any:
		d["data"] = data
	return d


## After the slots comes the SHADOW TABLE, one texel per painted shadow stroke (one in
## `shadow_k` of round 8's, at most 8 a mass): (record or header address, -1 or segment, strokes
## of this mass, which of them).
static func _pack12(
	masses: Array[PainterTreeMass],
	rng_seed: int,
	shadow_k: float,
	wide: int,
	bough_limit: float,
	bark: bool
) -> Dictionary:
	var n: int = masses.size()
	# wide 0: round 10's neighbours (a window of 16 in list order); 1: a grid over the whole tree;
	# 2: every pair (the reference for the experiment, slow).
	var cell_of: Dictionary = {}
	var cell_m: float = 1.0
	var ells := PackedInt32Array()
	var strands := PackedInt32Array()
	var twigs := PackedInt32Array()
	var gid_of := PackedInt32Array()
	gid_of.resize(n)
	var g_index: Dictionary = {}
	var g_lo: Array[Vector3] = []
	var g_hi: Array[Vector3] = []
	var c_lo := Vector3.ONE * INF
	var c_hi := Vector3.ONE * -INF
	var b_lo := Vector3.ONE * INF
	var b_hi := Vector3.ONE * -INF
	var leaf_n: int = 0
	var ever_n: int = 0
	var leaf_groups: int = 0
	var str_texels: int = 0
	var n_seg: int = 0
	var n_seg_painted: int = 0
	# A frond tree (a spruce: its boughs carry frond masses) packs no strand thinner than
	# `bough_limit` that starts inside the crown (above the lowest frond's underside), the stem
	# apart (BOUGH_R). A bare stub on the bole below the crown stays.
	var bough_r: float = 0.0
	var crown_floor: float = INF
	for m0: PainterTreeMass in masses:
		if m0.shape == PainterTreeMass.Shape.ELLIPSOID and m0.params.get("frond", 0.0) > 0.5:
			var fb: Basis = m0.xform.basis
			var ext_y: float = sqrt(
				pow(fb.x.y * m0.size.x, 2.0) + pow(fb.y.y * m0.size.y, 2.0) + pow(fb.z.y * m0.size.z, 2.0)
			)
			crown_floor = minf(crown_floor, m0.xform.origin.y - ext_y)
			bough_r = bough_limit
	for mi: int in n:
		var m: PainterTreeMass = masses[mi]
		gid_of[mi] = -1
		if m.shape == PainterTreeMass.Shape.ELLIPSOID:
			ells.append(mi)
			var bas: Basis = m.xform.basis
			var ax: Vector3 = bas.x * m.size.x
			var ay: Vector3 = bas.y * m.size.y
			var az: Vector3 = bas.z * m.size.z
			var ext := Vector3(
				sqrt(ax.x * ax.x + ay.x * ay.x + az.x * az.x),
				sqrt(ax.y * ax.y + ay.y * ay.y + az.y * az.y),
				sqrt(ax.z * ax.z + ay.z * ay.z + az.z * az.z)
			)
			var lo: Vector3 = m.xform.origin - ext
			var hi: Vector3 = m.xform.origin + ext
			# A strand mass (a willow's hem) draws its strokes on a spindle that may fill the whole
			# cylinder round its axis (ay) and moves them by up to `bend` (the shaders' bend *
			# (1 - (1 - t)^2)): the box takes the cylinder and the bend in, not the ellipsoid.
			var box_lo := lo
			var box_hi := hi
			if m.params.has("bend"):
				var bend: Vector3 = (m.params["bend"] as Vector3).abs()
				var cyl := Vector3(
					absf(ay.x) + sqrt(ax.x * ax.x + az.x * az.x),
					absf(ay.y) + sqrt(ax.y * ax.y + az.y * az.y),
					absf(ay.z) + sqrt(ax.z * ax.z + az.z * az.z)
				)
				box_lo = m.xform.origin - cyl - bend
				box_hi = m.xform.origin + cyl + bend
			b_lo = b_lo.min(box_lo)
			b_hi = b_hi.max(box_hi)
			var gi: int = -1
			if m.params.has("form"):
				gi = int(m.params["form"])
			elif m.role == PainterTreeMass.Role.LEAF:
				gi = 0
			elif m.role == PainterTreeMass.Role.STONE:
				gi = 1000
			if gi >= 0:
				var slot: int = g_index.get(gi, -1)
				if slot < 0:
					slot = g_lo.size()
					g_index[gi] = slot
					g_lo.append(lo)
					g_hi.append(hi)
					if m.role == PainterTreeMass.Role.LEAF:
						leaf_groups += 1
				else:
					g_lo[slot] = g_lo[slot].min(lo)
					g_hi[slot] = g_hi[slot].max(hi)
				gid_of[mi] = slot
			if m.role == PainterTreeMass.Role.LEAF:
				c_lo = c_lo.min(lo)
				c_hi = c_hi.max(hi)
				leaf_n += 1
				if m.params.has("evergreen"):
					ever_n += 1
		elif m.shape == PainterTreeMass.Shape.STRAND:
			var pts: PackedVector3Array = m.params["pts"]
			if pts.size() < 2:
				continue
			for q: Vector3 in pts:
				b_lo = b_lo.min(q)
				b_hi = b_hi.max(q)
			if (
				bough_r > 0.0
				and not m.params.has("stem")
				and (m.params["radii"] as PackedFloat32Array)[0] < bough_r
				and pts[0].y > crown_floor
			):
				continue
			if m.params.get("built", false):
				twigs.append(mi)
			else:
				strands.append(mi)
				n_seg_painted += pts.size() - 1
			str_texels += 2 + pts.size()
			n_seg += pts.size() - 1
	var has_crown: bool = leaf_n > 0
	var multi: bool = leaf_groups > 1
	var crown_c := Vector3.ZERO
	var crown_r := Vector3.ONE
	var forms: Array[Dictionary] = []
	if has_crown:
		crown_c = (c_lo + c_hi) * 0.5
		crown_r = ((c_hi - c_lo) * 0.5).max(Vector3.ONE * 0.05)
		forms.append({"c": crown_c, "r": crown_r, "kind": 1 if ever_n * 2 > leaf_n else 0})
	var n_ell: int = ells.size()
	if wide == 1 and n_ell > 17:
		# The grid: an ellipsoid is listed in the cell of its centre; a cell is as wide as the
		# largest clump's reach, so every overlap lies within the 27 cells round a centre.
		var r_max: float = 0.3
		for mi: int in ells:
			var ms: Vector3 = masses[mi].size
			r_max = maxf(r_max, maxf(ms.x, maxf(ms.y, ms.z)))
		cell_m = r_max * 2.0
		for ei: int in n_ell:
			var cc: Vector3i = Vector3i((masses[ells[ei]].xform.origin / cell_m).floor())
			if cell_of.has(cc):
				(cell_of[cc] as PackedInt32Array).append(ei)
			else:
				cell_of[cc] = PackedInt32Array([ei])
	var str_base: int = n_ell * ELL_T
	var seg_base: int = str_base + str_texels
	var slot_base: int = seg_base + n_seg
	# Slots are appended; the array grows once more at the end.
	var data := PackedFloat32Array()
	data.resize((slot_base + n_ell * 8 + n_seg * 2) * 4)
	var sw: int = slot_base * 4
	var n_slots: int = 0
	var roots_total: int = 0
	var shadow_total: float = 0.0
	var shadow := PackedFloat32Array()
	var w: int = 0
	for ei: int in n_ell:
		var mi: int = ells[ei]
		var m: PainterTreeMass = masses[mi]
		var pr: Dictionary = m.params
		var c: Vector3 = m.xform.origin
		var bas: Basis = m.xform.basis
		var sz: Vector3 = m.size
		var leaf: bool = m.role == PainterTreeMass.Role.LEAF
		var ever: bool = pr.has("evergreen")
		var gs: int = gid_of[mi]
		var gc: Vector3 = crown_c
		var gr: Vector3 = crown_r
		var flags: float = 0.0
		if gs >= 0:
			gc = (g_lo[gs] + g_hi[gs]) * 0.5
			gr = ((g_hi[gs] - g_lo[gs]) * 0.5).max(Vector3.ONE * 0.05)
			flags += 4.0
			if multi and leaf:
				flags += 16.0
		var frond: bool = pr.get("frond", 0.0) > 0.5
		if frond:
			flags += 1.0
		var radial: Vector3 = Vector3.ZERO
		if pr.has("radial"):
			radial = pr["radial"]
			flags += 32.0
		if pr.has("grain"):
			flags += 64.0
		var centre: Vector3 = Vector3.ZERO
		if pr.has("centre"):
			centre = pr["centre"]
			flags += 128.0
		if pr.has("bough"):
			flags += 256.0
		if pr.has("strands"):
			flags += 512.0
		var sp0: float = float(pr.get("spacing", SPACING[m.role])) * 2.0
		# Knud Thomsen's ellipsoid area, as PPainter2._ell_area.
		var ab: float = pow(sz.x * sz.y, 1.6)
		var ac: float = pow(sz.x * sz.z, 1.6)
		var bc: float = pow(sz.y * sz.z, 1.6)
		var area: float = 4.0 * PI * pow((ab + ac + bc) / 3.0, 0.625)
		# (painter-bushes: a bush's pads take a lower floor, "min_roots"; a tree's never set it.)
		var roots: int = maxi(int(pr.get("min_roots", 6)), int(area / (sp0 * sp0)))
		var r0: float = minf(sz.x, minf(sz.y, sz.z))
		var r2: float = maxf(sz.x, maxf(sz.y, sz.z))
		var r1: float = sz.x + sz.y + sz.z - r0 - r2
		var msize: float = sqrt(r0 * r1) if frond else sqrt(r1 * maxf(r0, r1 * 0.6))
		var sh_n: float = 0.0
		var sh_size: float = 0.0
		if m.role != PainterTreeMass.Role.GROUND and m.role != PainterTreeMass.Role.TRIM:
			sh_size = clampf((sz.x + sz.y + sz.z - r0) * 0.5, 0.4, 1.5)
			sh_n = float(maxi(5, int(area / (sh_size * sh_size * 0.5184))))
			shadow_total += sh_n
			var n_sh: int = clampi(int(sh_n / shadow_k + _h01(rng_seed * 31 + mi * 17)), 1, 8)
			for k: int in n_sh:
				shadow.append_array(
					PackedFloat32Array([float(ei * ELL_T), -1.0, float(n_sh), float(k)])
				)
		data[w] = c.x
		data[w + 1] = c.y
		data[w + 2] = c.z
		data[w + 3] = 8.0 if ever else float(m.role)
		data[w + 4] = bas.x.x * sz.x
		data[w + 5] = bas.x.y * sz.x
		data[w + 6] = bas.x.z * sz.x
		data[w + 7] = flags
		data[w + 8] = bas.y.x * sz.y
		data[w + 9] = bas.y.y * sz.y
		data[w + 10] = bas.y.z * sz.y
		data[w + 11] = pr.get("phase", 0.0)
		data[w + 12] = bas.z.x * sz.z
		data[w + 13] = bas.z.y * sz.z
		data[w + 14] = bas.z.z * sz.z
		data[w + 15] = pr.get("wind", 0.0)
		data[w + 16] = gc.x
		data[w + 17] = gc.y
		data[w + 18] = gc.z
		data[w + 19] = msize
		data[w + 20] = gr.x
		data[w + 21] = gr.y
		data[w + 22] = gr.z
		data[w + 23] = sp0
		data[w + 24] = centre.x
		data[w + 25] = centre.y
		data[w + 26] = centre.z
		data[w + 27] = float(roots)
		data[w + 28] = radial.x
		data[w + 29] = radial.y
		data[w + 30] = radial.z
		data[w + 31] = pr.get("droop", 0.3)
		data[w + 32] = float((rng_seed * 7919 + mi * 104729) & 0xFFFFF)
		data[w + 33] = sh_n
		data[w + 34] = sh_size
		data[w + 35] = 0.0
		# Texel 9: up to four neighbours that overlap this clump most (record addresses, -1 none),
		# looked for among the sixteen nearest in list order (clumps are laid along the limbs,
		# so list neighbours are the likely overlaps). The shader drops a root that lies inside
		# one of them: round 8's burial test, against four masses instead of all.
		var rmax: float = r2
		var best := PackedFloat32Array([-1.0, -1.0, -1.0, -1.0])
		var score := PackedFloat32Array([0.12, 0.12, 0.12, 0.12])
		var cand := PackedInt32Array()
		if wide == 2 or (wide == 1 and cell_of.is_empty()):
			cand = PackedInt32Array(range(n_ell))
		elif wide == 1:
			var cc: Vector3i = Vector3i((c / cell_m).floor())
			for dz: int in range(-1, 2):
				for dy: int in range(-1, 2):
					for dx: int in range(-1, 2):
						var key: Vector3i = cc + Vector3i(dx, dy, dz)
						if cell_of.has(key):
							cand.append_array(cell_of[key])
		else:
			cand = PackedInt32Array(range(maxi(ei - 8, 0), mini(ei + 9, n_ell)))
		for j: int in cand:
			if j == ei:
				continue
			var mj: PainterTreeMass = masses[ells[j]]
			var rj: float = maxf(mj.size.x, maxf(mj.size.y, mj.size.z))
			var sc: float = (rmax + rj - c.distance_to(mj.xform.origin)) / minf(rmax, rj)
			if sc <= 0.12:
				continue
			var slot: int = 0
			for q: int in range(1, 4):
				if score[q] < score[slot]:
					slot = q
			if sc > score[slot]:
				score[slot] = sc
				best[slot] = float(j * ELL_T)
		data[w + 36] = best[0]
		data[w + 37] = best[1]
		data[w + 38] = best[2]
		data[w + 39] = best[3]
		w += ELL_T * 4
		roots_total += roots
		var k0: int = 0
		while k0 < roots:
			if sw + 4 > data.size():
				data.resize(data.size() + 1024)
			data[sw] = float(ei * ELL_T)
			data[sw + 1] = -1.0
			data[sw + 2] = float(roots)
			data[sw + 3] = float(k0)
			sw += 4
			n_slots += 1
			k0 += ROOTS
	# Strands: the painted ones first, so the stroke slots never reach a twig.
	var gw: int = seg_base * 4
	var twig_from: int = strands.size()
	strands.append_array(twigs)
	var bark_roots: int = 0
	for si: int in strands.size():
		var mi: int = strands[si]
		var m: PainterTreeMass = masses[mi]
		var pr: Dictionary = m.params
		var pts: PackedVector3Array = pr["pts"]
		var radii: PackedFloat32Array = pr["radii"]
		var np: int = pts.size()
		var hdr: int = w / 4
		var built: bool = si >= twig_from
		var ww: float = pr.get("wind", 0.0)
		var sp0: float = float(pr.get("spacing", SPACING[m.role])) * 2.0
		data[w] = pts[0].distance_to(pts[np - 1])
		data[w + 1] = pr.get("phase", 0.0)
		data[w + 2] = ww
		data[w + 3] = pr.get("wind_tip", ww)
		data[w + 4] = float(np)
		data[w + 5] = (
			(1.0 if built else 0.0)
			+ (2.0 if has_crown and m.role == PainterTreeMass.Role.BARK else 0.0)
			+ (4.0 if has_crown and pr.has("wind_tip") else 0.0)
			+ (8.0 if pr.has("stem") else 0.0)
		)
		data[w + 6] = sp0
		data[w + 7] = float((rng_seed * 7919 + mi * 104729) & 0xFFFFF)
		w += 8
		for i: int in np:
			var p: Vector3 = pts[i]
			data[w] = p.x
			data[w + 1] = p.y
			data[w + 2] = p.z
			data[w + 3] = radii[i]
			w += 4
		for i: int in np - 1:
			data[gw] = float(hdr)
			data[gw + 1] = float(i)
			data[gw + 2] = 0.0
			data[gw + 3] = 0.0
			gw += 4
			if built:
				continue
			var steps: int = maxi(1, roundi(pts[i].distance_to(pts[i + 1]) / sp0))
			var around: int = maxi(2, roundi(TAU * (radii[i] + radii[i + 1]) * 0.5 / sp0))
			var roots: int = steps * around
			if bark:
				bark_roots += roots
			var packed: float = float(mini(steps, 255) + 256 * mini(around, 255))
			var r0m: float = (radii[i] + radii[i + 1]) * 0.5
			if r0m >= 0.06:
				var full: float = maxf(
					1.0, floorf(pts[i].distance_to(pts[i + 1]) / maxf(0.3, r0m * 1.6))
				)
				var n_sh: int = mini(
					int(full / shadow_k + _h01(rng_seed * 31 + mi * 17 + i * 7)), 8
				)
				for k: int in n_sh:
					shadow.append_array(
						PackedFloat32Array([float(hdr), float(i), float(n_sh), float(k)])
					)
			var k0: int = 0
			while bark and k0 < roots:
				if sw + 4 > data.size():
					data.resize(data.size() + 1024)
				data[sw] = float(hdr)
				data[sw + 1] = float(i)
				data[sw + 2] = packed
				data[sw + 3] = float(k0)
				sw += 4
				n_slots += 1
				k0 += ROOTS
	data.resize(sw)
	var sh_base: int = sw / 4
	data.append_array(shadow)
	sw = data.size()
	roots_total += bark_roots
	return {
		"sh_base": sh_base,
		"n_shadow": shadow.size() / 4,
		"data": data,
		"texels": sw / 4,
		"n_ell": n_ell,
		"n_seg": n_seg,
		"n_slots": n_slots,
		"seg_base": seg_base,
		"slot_base": slot_base,
		"crown_c": crown_c,
		"crown_r": crown_r,
		"has_crown": has_crown,
		"multi": multi,
		"forms": forms,
		"aabb": AABB(b_lo, b_hi - b_lo) if n > 0 else AABB(),
		"roots": roots_total,
		"bark_roots": bark_roots,
		"shadow_full": shadow_total,
		"tris": n_ell * ELL_SEGS * ELL_RINGS * 2 + n_seg * TUBE_SIDES * 2,
		"strands": strands.size(),
		"twigs": twigs.size(),
		"n_seg_painted": n_seg_painted
	}


## The five texels of a tree's row in the tree table (see stroke10.txt).
static func tree_row(
	d: Dictionary,
	layer: int,
	base: int,
	inst_line: int,
	hue: float,
	value: float,
	thin: float,
	moss: float
) -> PackedFloat32Array:
	var c: Vector3 = d["crown_c"]
	var r: Vector3 = d["crown_r"]
	var out := PackedFloat32Array(
		[
			float(layer),
			float(base),
			float(d["n_ell"]),
			float(d["n_seg"]),
			float(d["seg_base"]),
			float(d["slot_base"]),
			float(d["n_slots"]),
			float(inst_line),
			hue + 0.5,
			value + 0.5,
			thin,
			moss,
			c.x,
			c.y,
			c.z,
			# 2 for a bush (PainterTreeBush, d "bush"): a crown the token window never takes whole.
			(2.0 if d.get("bush", false) else 1.0) if d["has_crown"] else 0.0,
			r.x,
			r.y,
			r.z,
			1.0 if d["multi"] else 0.0
		]
	)
	out.resize(TREE_W * 4)
	# Texels 5 and 6 (painter-perf-forest): the tree's box in its own frame for the shaders' per-tree
	# view cull and token pre-test (tree_view_box): its centre (w 1: a box) and its half extents,
	# the masses' own (the shaders add their margins).
	var box: AABB = d["aabb"]
	if box.size != Vector3.ZERO:
		var mid := box.get_center()
		var half := box.size * 0.5
		out[20] = mid.x
		out[21] = mid.y
		out[22] = mid.z
		out[23] = 1.0
		out[24] = half.x
		out[25] = half.y
		out[26] = half.z
	out[28] = float(d["sh_base"])
	out[29] = float(d["n_shadow"])
	return out


## Instances of one tree for a MultiMesh with custom data and no colours (16 floats each):
## the tree's transform, then (tree row, first unit, 0, 0).
static func add_instances(
	buf: PackedFloat32Array,
	xf: Transform3D,
	row: int,
	units: int,
	per: int,
	from: int = 0,
	to: int = 0
) -> int:
	var count: int = (units - from + per - 1) / per
	var b: Basis = xf.basis
	var o: Vector3 = xf.origin
	for i: int in count:
		buf.append_array(
			PackedFloat32Array(
				[
					b.x.x,
					b.y.x,
					b.z.x,
					o.x,
					b.x.y,
					b.y.y,
					b.z.y,
					o.y,
					b.x.z,
					b.y.z,
					b.z.z,
					o.z,
					float(row),
					float(from + i * per),
					float(to),
					0.0
				]
			)
		)
	return count
