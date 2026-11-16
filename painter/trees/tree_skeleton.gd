class_name PainterTreeSkeleton
extends RefCounted
## The painted trees' skeleton: the species architecture and the branch system a tree's crown
## hangs on (docs/systems/painter.md "Trees"). PainterTreeGrowth extends it with the crown.
## Pure static functions, safe on a worker thread: masses out, no colour, no mesh, no node.
##
## Ported from the painterspike branch's spike/painter/family14.gd (the research painter's round
## 14 form, the generator the spike drew in tt-sim), split in two at the crown; the code is the
## spike's, so a seed, age and openness grow the same tree (test_painter_trees.gd checks the
## spike's digests). The notes below are the research rounds' own.
##
## Round 14 FORM: family13.gd with these keys (all 0 = round 13's tree exactly):
##   sprays   (birch) no strand masses: small leaf tufts scattered along the fine twigs with sky
##            between, and a short thin tassel under the outermost twig ends only
##   flute    (poplar) no hull: each upswept limb is clothed by narrow upright masses along its
##            own length, lit limb by limb, so the column is fluted, slit and ragged at the top
##   over     (willow) on the upper limbs a strand springs from above the limb and is broader, so
##            the limb lies under its foliage; one parting only, a lifted hem facing the home
##            view (+z), not a notch in the crown; young trees have no parting (2 = also mounds
##            over the limbs: tried and dropped)
##   hem      (willow) the height of the curtain's hem at the outside, as a share of the height
##   juv      a young tree's foliage is in scale with it: smaller, more clumps (broadleaves);
##            whorls closer together and a broad-based spire (spruce); boughs in to the stem and
##            touching (Scots pine)
##   shoots   (lime) the basal shoots are a ring of many thin upright sprays against the foot
## Round 13 FORM: family12.gd with these keys (all 0, and dieback 1 = round 12's tree exactly):
##   curve    (willow, birch) a strand mass HANGS FROM its twig (its top is the twig, not a cap
##            above it), leans a little off the vertical, differs in length and width strand to
##            strand, and carries a bend (params "bend": out from the stem first, then down) that
##            the shaders draw; strands near the top lean out, so the top is a mop and not a cap
##   part     (willow) how many partings the curtain has: sectors where the strands are short
##            tassels, so the trunk and the ground show under the limbs
##   browse   (lime) metres: no limb, branch or twig hangs below this height (they level out
##            above it), so the trunk stands clear between the basal shoots and the crown
##   stout    (oak) a young tree is short and thick for its age and gives up its leader early
##   collar   every limb leaving the stem tapers along its length and swells where it joins
##   spire    (spruce) the leader is a fine point that continues the top whorls, in their light
##   irreg    (conifers) whorls unevenly spaced and unequal in reach
##   sway     the stem wanders gently (birch)
##   dieback  1 = an old tree's top stands bare (round 12); 0 = never (rowan, birch)
##   flame    (poplar) the low limbs stop lower, so the column is widest below the middle
## Round 12 FORM: family11.gd with four keys (all 0 = round 11's tree exactly):
##   strands  (willow) no clump at a branch end. The foliage is the CURTAIN: narrow hanging masses
##            (params "strands", thin toward the stem, tapered to a hem by the shaders) started
##            every third of a metre along the outer length of each arching limb and twig, longer
##            toward the outside of the crown, short near the stem so the limbs show.
##   plate    (Scots pine) an old tree's boughs are levelled per limb into broad flat-topped plates
##   boughvar (Scots pine) boughs of unequal size, some without a satellite dome
##   clothe   (poplar) foliage from the limb's base, so the stem is clothed from low down
## Round 11 FORM: family8.gd with
##   boughs   (Scots pine) 1 = foliage as BOUGHS: along each upswept limb a few domed clouds, each a
##            main dome and one or two smaller ones beside it, flat beneath, lit as one mass per
##            limb; flatter and broader on a tree that has lost its leader. 0 = round 8's plates.
##   billow   (lime) 0..1: the crown's hull stands in and out in a few large billows round the
##            stem and in tiers up it, and is left open in the notches between them.
## and the stem's strand marked "stem" (only it keeps a root flare in round 11's block-in).
## Round 8's notes follow.
## Round 8 FORM: round 7's skeleton (kept below, with three added architecture keys) and a crown
## that is DISTRIBUTED ALONG it instead of hung at its ends.
##   arch        a limb leaves ascending and then arches over and down toward its end (lime)
##   fastigiate  a limb runs up beside the stem to near the top, whatever its place (poplar)
##   lobes       how many masses the crown's light is gathered into: 1 = one dome (lime, poplar),
##               n = a top mass and n - 1 sectors round the stem (oak 5). Wind stays per limb.
##   fill        0..1: how far in along its limbs a crown is clothed, and whether its heart is
##               filled
## Foliage: sample points are laid along the outer part of every live limb, branch and twig
## (how far in: `fill`, else `dense`), tips first; a point becomes a clump unless a clump already
## stands within `sep` of it (dense species overlap, airy ones leave sky), so the crown's
## envelope is the hull of the branch system and its inside is as full as the species says.
##
## Round 7's notes follow.
## Round 7 FORM: a tree is a SKELETON grown by botanical rules, and the crown hangs on it.
## One generator for every species (broadleaf and conifer); a species is an ARCHITECTURE, a few
## sheet values. Pure functions: masses out, no colour, no mesh.
##
## The vocabulary is procgen's BranchGen (levels, attachment span, angle, length ratio, tip
## shrink, radius ratio, droop, spiral or whorled arrangement), which could not be loaded from
## this scratch project and has no age or openness. Added here: growth along age, apical
## dominance, self-pruning, sag and upturn, weeping twigs, the pipe model, a lost leader.
##
## Architecture keys (sheet, kind `tree`, overridden per species):
##   apical      0 decurrent (the stem dissolves into `forks` co-dominant limbs at the fork: oak,
##               willow) .. 1 excurrent (one leader runs to the top: spruce, poplar, birch). A
##               young tree and a forest-grown one hold their leader longer, whatever the species.
##   whorl       0 = limbs one at a time in a spiral (alternate); n >= 2 = whorls of n (conifers),
##               and their side branches then leave in opposite pairs, flat
##   angle-top   degrees between a young limb (top of the crown) and its parent axis
##   angle-low   the same for an old limb (bottom of the crown): limbs open out as they age
##   sag         how far a limb's own weight bends it down along its length
##   upturn      how far its tip turns back up to the light (spruce: down, then up)
##   weep        how far the side branches and twigs hang (willow 1, birch about 0.5)
##   len2        length of a side branch against its parent (falls again for each order)
##   twigs       most side branches a limb carries;  fine: twigs per side branch (winter detail)
##   pipe        pipe-model exponent: parent radius^pipe = sum of child radius^pipe
##   flat-top    age at which the leader is lost and the top limbs spread (Scots pine); 0 never
##   forks       how many co-dominant limbs a decurrent stem divides into
## Kept from rounds 5 and 6: height, spread, girth, limbs (limbs in a full crown), tiers (whorls
## in a full crown), crook (zig-zag at each node), bole (self-pruning: how high the clean stem
## goes), widest and top (which limbs are longest: the vigour profile up the crown), clump,
## clump-flat, dense, plates, skirt, vigour.
##
## Place axes: age (the stem has grown past more nodes, low limbs are shed, orders are added,
## the leader gives out, the top dies back), openness (clean tall stem, steep short limbs, held
## leader .. low wide heavy limbs), lean, side, vigour, room.
## Rules that hold by construction: every branch starts at a point of its parent's polyline;
## a side branch that would head back through the stem is mirrored outward; nothing goes below
## 0.3 m; a limb is never thicker than 0.8 of its parent where it leaves.

const GOLDEN: float = 2.39996323
const W_STEM: float = 0.12
const W_PAD: float = 0.6
## painter-look-wood: radius continuity. A strand narrows by at most this share of its width from
## one node to the next (the pipe model's step where a heavy limb leaves the trunk was a cone: the
## trunk above a fork stood a third of the width below it, under a limb thicker than itself).
const NARROW_MIN: float = 0.62
## painter-look-wood2: the stem's own floor (the trunk's width at one node is at least this share of
## the node below).
const NARROW_STEM: float = 0.8
## A limb's base flares to this many times its own width where it leaves its parent (no pegs), but
## never past FLARE_MAX of the parent's width there: the shader used to swell every limb 1.6 times
## on top of the pack's own collar, so a limb began up to 1.47 times as wide as its parent.
const FLARE: float = 1.6
const FLARE_MAX: float = 0.92
## Limbs thinner than this are not flared (a few millimetres on a twig, and a node per twig).
const FLARE_MIN_R: float = 0.05
## painter-look-wood2: the straight fork's share of the stem's width where the stem divides, and
## the share of its base a fork has left at its tip (see `_forks`).
const FORK_LEAD: float = 0.72
## The thinnest a stick on a thin parent is made (metres of radius).
const LEAST_STICK: float = 0.011
const FORK_TIP: float = 0.2
## painter-look-wood3: the widest fork's share of the stem's width where they meet (`_shoulder`).
const FORK_JOIN: float = 0.9
## The stem's area (to the power of the pipe exponent) that the forks after the lead share.
const FORK_REST: float = 0.9


class Sk:
	extends RefCounted
	var pts: Array[PackedVector3Array] = []
	var rad: Array[PackedFloat32Array] = []
	var area: Array[PackedFloat32Array] = []
	var order := PackedInt32Array()
	var parent := PackedInt32Array()
	var at := PackedInt32Array()
	var grp := PackedInt32Array()
	## 0 live, 2 dead (a stub or a snag: no children, no leaf)
	var state := PackedInt32Array()
	var kids := PackedInt32Array()
	var length := PackedFloat32Array()

	func add(p: PackedVector3Array, o: int, par: int, at_i: int, g: int, st: int, ln: float) -> int:
		pts.append(p)
		var a := PackedFloat32Array()
		a.resize(p.size())
		area.append(a)
		rad.append(PackedFloat32Array())
		order.append(o)
		parent.append(par)
		at.append(at_i)
		grp.append(g)
		state.append(st)
		kids.append(0)
		length.append(ln)
		if par >= 0:
			kids[par] += 1
		return pts.size() - 1


## A species' architecture from its form props (`painter/trees/species.json`): every key the
## generator reads, with its default when the props leave it out.
static func species_of(props: Dictionary) -> Dictionary:
	var sp: Dictionary = PainterTreeBase.species_of(props)
	sp["skirt"] = PainterTreeBase.num(props, "skirt", 0.0)
	sp["curtain"] = PainterTreeBase.num(props, "curtain", 0.0)
	sp["apical"] = PainterTreeBase.num(props, "apical", 0.5)
	sp["whorl"] = PainterTreeBase.num(props, "whorl", 0.0)
	sp["angle_top"] = PainterTreeBase.num(props, "angle-top", 40.0)
	sp["angle_low"] = PainterTreeBase.num(props, "angle-low", 70.0)
	sp["sag"] = PainterTreeBase.num(props, "sag", 0.2)
	sp["upturn"] = PainterTreeBase.num(props, "upturn", 0.2)
	sp["len2"] = PainterTreeBase.num(props, "len2", 0.5)
	sp["twigs"] = PainterTreeBase.num(props, "twigs", 3.0)
	sp["fine"] = PainterTreeBase.num(props, "fine", 2.0)
	sp["pipe"] = PainterTreeBase.num(props, "pipe", 2.3)
	sp["flat_top"] = PainterTreeBase.num(props, "flat-top", 0.0)
	sp["forks"] = PainterTreeBase.num(props, "forks", 3.0)
	sp["arch"] = PainterTreeBase.num(props, "arch", 0.0)
	sp["fastigiate"] = PainterTreeBase.num(props, "fastigiate", 0.0)
	sp["lobes"] = PainterTreeBase.num(props, "lobes", 4.0)
	sp["fill"] = PainterTreeBase.num(props, "fill", -1.0)
	sp["boughs"] = PainterTreeBase.num(props, "boughs", 0.0)
	sp["billow"] = PainterTreeBase.num(props, "billow", 0.0)
	sp["strands"] = PainterTreeBase.num(props, "strands", 0.0)
	sp["plate"] = PainterTreeBase.num(props, "plate", 0.0)
	sp["boughvar"] = PainterTreeBase.num(props, "boughvar", 0.0)
	sp["clothe"] = PainterTreeBase.num(props, "clothe", 0.0)
	sp["curve"] = PainterTreeBase.num(props, "curve", 0.0)
	sp["part"] = PainterTreeBase.num(props, "part", 0.0)
	sp["browse"] = PainterTreeBase.num(props, "browse", 0.0)
	sp["stout"] = PainterTreeBase.num(props, "stout", 0.0)
	sp["collar"] = PainterTreeBase.num(props, "collar", 0.0)
	sp["spire"] = PainterTreeBase.num(props, "spire", 0.0)
	sp["irreg"] = PainterTreeBase.num(props, "irreg", 0.0)
	sp["sway"] = PainterTreeBase.num(props, "sway", 0.0)
	sp["dieback"] = PainterTreeBase.num(props, "dieback", 1.0)
	sp["flame"] = PainterTreeBase.num(props, "flame", 0.0)
	sp["sprays"] = PainterTreeBase.num(props, "sprays", 0.0)
	sp["flute"] = PainterTreeBase.num(props, "flute", 0.0)
	sp["over"] = PainterTreeBase.num(props, "over", 0.0)
	sp["hem"] = PainterTreeBase.num(props, "hem", 0.0)
	sp["juv"] = PainterTreeBase.num(props, "juv", 0.0)
	sp["shoots"] = PainterTreeBase.num(props, "shoots", 0.0)
	return sp


## A pine bough's dome: an evergreen clump that is no frond, with the point its twigs come from.
static func _bough(
	c: Vector3, r: Vector3, form: int, centre: Vector3, from: Vector3, phase: float
) -> PainterTreeMass:
	var m: PainterTreeMass = PainterTreeBase._tier(
		c, Basis.IDENTITY, r, form, centre, from, -0.7, phase, 0.0
	)
	m.params["bough"] = true
	return m


## A fixed random number for (tree, branch, purpose): a branch keeps its draws whatever else
## grows or is shed, so a small change of an axis is a small change of the tree.
static func _h(seed_v: int, id: int, salt: int) -> float:
	return fposmod(
		(
			sin(float(id % 100003) * 12.9898 + float(salt) * 78.233 + float(seed_v % 9973) * 3.7717)
			* 43758.5453
		),
		1.0
	)


static func _stem(c: Dictionary, y: float) -> Vector3:
	return PainterTreeBase._stem_at(y, c["h"], c["lean"], c["wob"], c["amp"])


## How long a limb leaving the stem (or a co-dominant limb) at `p` toward `dir` grows: the
## species' vigour profile up the crown, the room it has, the side the crown favours.
static func _limb_len(c: Dictionary, p: Vector3, dir: Vector3, theta: float, id: int) -> float:
	var v: float = clampf(
		(p.y - float(c["y_cb"])) / maxf(float(c["h"]) - float(c["y_cb"]), 0.01), 0.0, 1.0
	)
	var open: float = c["open"]
	var az: float = atan2(dir.z, dir.x)
	var dh := Vector2(dir.x, dir.z).normalized()
	var sidew: float = clampf(1.0 + float(c["side_len"]) * 1.1 * dh.dot(c["side_dir"]), 0.25, 1.8)
	var shade: float = lerpf(lerpf(0.5, 1.0, smoothstep(0.0, 0.6, v)), 1.0, open)
	var reach: float = (
		float(c["rc"])
		* PainterTreeBase._env(v, c["widest"], c["top_p"], 0.62)
		* (0.82 + 0.3 * _h(c["seed"], id, 3))
		* sidew
		* shade
	)
	# A lost leader: the top limbs take over and spread.
	reach *= 1.0 + 0.9 * float(c["ft"]) * smoothstep(0.55, 1.0, v)
	# Round 13: one whorl is stronger than the next.
	if float(c["irreg"]) > 0.0 and id >= 1000:
		reach *= lerpf(1.0, 0.7 + 0.6 * _h(c["seed"], (id - 1000) / 8, 61), float(c["irreg"]))
	# Round 13: a parting is a notch in the crown itself: the limbs on that side are short, so
	# the curtain stands close to the stem there and the trunk and the ground show beside it.
	for pk: int in int(c["part"]):
		var pa: float = (
			float(c["part_az"])
			+ float(pk) * TAU / float(c["part"])
			+ (_h(c["seed"], 60 + pk, 54) - 0.5) * 0.9
		)
		reach *= lerpf(
			float(c["part_k"]), 1.0, smoothstep(0.2, 0.75, absf(angle_difference(az, pa)))
		)
	reach = maxf(PainterTreeBase._fit_room(reach, az, c["room"], open), 0.12)
	# A limb on a co-dominant limb starts out in the crown already: it has less far to go.
	var off: Vector3 = p - _stem(c, p.y)
	off.y = 0.0
	reach = maxf(reach - off.length() * 0.75, reach * 0.3)
	# A steep limb that turns up runs on beside the stem (poplar): longer than its reach.
	var st: float = sin(clampf(theta + 0.12, 0.1, 1.57))
	var std: float = minf(
		reach / maxf(st, 0.34) * (1.0 + float(c["upturn"]) * (1.0 - st)), float(c["h"]) * 0.55
	)
	# Fastigiate: every limb runs up beside the stem and ends near the top, so the low limbs are
	# the longest and the crown is a flame.
	var fast: float = c["fast"]
	if fast > 0.01:
		var up_k: float = 0.62 + 0.3 * _h(c["seed"], id, 17)
		if float(c["flame"]) > 0.0:
			# Round 13: a low limb stops lower, so the column is widest below its middle and
			# narrows to the tip (round 12's limbs all ended near the top: a torch).
			up_k = lerpf(
				up_k, lerpf(0.36, 0.8, v) * (0.88 + 0.24 * _h(c["seed"], id, 17)), float(c["flame"])
			)
		var up_len: float = clampf((float(c["h"]) * 0.97 - p.y) * up_k, 0.4, float(c["h"]) * 0.7)
		std = lerpf(std, up_len, fast)
	return std


static func _grow(
	sk: Sk,
	c: Dictionary,
	parent: int,
	at_i: int,
	o: Vector3,
	d0: Vector3,
	length: float,
	order: int,
	grp: int,
	id: int,
	state: int
) -> void:
	var seed_v: int = c["seed"]
	var max_order: int = c["max_order"]
	var pairs: bool = int(c["whorl"]) >= 2 and order >= 1
	var nk: int = 0
	if state == 0:
		if order == 0:
			nk = clampi(int(round(length / float(c["slot_dy"]))), 1, 4)
		elif order == 1 and max_order >= 2:
			nk = clampi(int(length / float(c["space2"])), 0, int(c["twigs"]))
		elif order == 2 and max_order >= 3 and length > 0.45:
			nk = int(c["fine"])
	var nseg: int = maxi(nk + 1, 3 if order < 3 else 2)
	var weep: float = float(c["weep"]) * (1.0 if order >= 2 else (0.22 if order == 1 else 0.0))
	var sag: float = (
		float(c["sag"])
		* (1.0 if order <= 1 else 0.5)
		* clampf(length / (0.5 * float(c["rc"]) + 0.5), 0.4, 1.6)
	)
	var up: float = float(c["upturn"]) * (1.0 if order <= 1 else 0.5)
	var crook: float = c["crook"]
	var pts := PackedVector3Array([o])
	var d: Vector3 = d0.normalized()
	var pos: Vector3 = o
	var kid_at := PackedInt32Array()
	var kid_dir: Array[Vector3] = []
	var kid_f := PackedFloat32Array()
	var f_prev: float = 0.0
	var f_last: float = 0.92 if nk > 0 else 0.0
	for j: int in nseg:
		var f1: float = float(j + 1) / float(nseg)
		if nk > 0:
			f1 = (
				lerpf(0.32, f_last, (float(j) + 0.5) / float(nk))
				if j < nk
				else lerpf(
					lerpf(0.32, f_last, (float(nk) - 0.5) / float(nk)),
					1.0,
					float(j - nk + 1) / float(nseg - nk)
				)
			)
		var dt: float = f1 - f_prev
		var tm: float = (f1 + f_prev) * 0.5
		var horiz: float = sqrt(maxf(1.0 - d.y * d.y, 0.0))
		d += (
			Vector3.DOWN * (sag * dt * 1.5 * horiz + weep * dt * 3.4 * tm)
			+ Vector3.UP * (up * dt * 1.7 * tm)
		)
		# Arching: nothing at first (the limb ascends), then over and down toward the end.
		d += Vector3.DOWN * float(c["arch"]) * (1.0 if order == 1 else 0.45) * dt * 4.2 * tm * tm
		if order >= 1:
			d += (
				Vector3(
					_h(seed_v, id * 13 + j, 5) - 0.5,
					(_h(seed_v, id * 13 + j, 6) - 0.5) * 0.5,
					_h(seed_v, id * 13 + j, 7) - 0.5
				)
				* crook
				* 0.16
			)
		d = d.normalized()
		var br: float = c["browse"]
		if br > 0.0 and order >= 1:
			# Round 13: a browse line. A limb coming down levels out above it.
			if d.y < 0.0:
				d.y *= smoothstep(br, br + 1.3, pos.y)
				d = d.normalized()
			pos += d * length * dt
			pos.y = maxf(pos.y, minf(br, o.y))
		else:
			pos += d * length * dt
		pos.y = maxf(pos.y, 0.3)
		pts.append(pos)
		f_prev = f1
		if j >= nk:
			continue
		# The children that leave at this node.
		var e_up: Vector3 = Vector3.UP - d * d.y
		var per_node: int = 2 if pairs else 1
		var first_side := Vector3.ZERO
		for k: int in per_node:
			var kid: int = id * 11 + j * 2 + k + 1
			var side: Vector3
			if e_up.length_squared() < 0.12:
				# Round a near-vertical axis: a spiral.
				var az: float = (
					float(c["phi0"]) + float(id) * 1.7 + float(j) * GOLDEN + float(k) * PI
				)
				var s0 := Vector3(cos(az), 0.0, sin(az))
				side = (s0 - d * s0.dot(d)).normalized()
			else:
				# On a leaning or level axis: left and right in turn, a little above the level
				# (below it on a weeper), since a limb branches in a plane.
				var eu: Vector3 = e_up.normalized()
				var es: Vector3 = d.cross(eu).normalized()
				var sgn: float = 1.0 if (j + id + k) % 2 == 0 else -1.0
				var tilt: float = (
					deg_to_rad(lerpf(8.0, 42.0, _h(seed_v, kid, 8)))
					* (1.0 - 1.4 * float(c["weep"]))
					* (0.15 if pairs else 1.0)
				)
				side = (es * sgn * cos(tilt) + eu * sin(tilt)).normalized()
			var theta: float = float(c["theta2"]) * (0.82 + 0.36 * _h(seed_v, kid, 9))
			if order == 0:
				var v: float = clampf(
					(pos.y - float(c["y_cb"])) / maxf(float(c["h"]) - float(c["y_cb"]), 0.01),
					0.0,
					1.0
				)
				theta = (
					deg_to_rad(lerpf(c["angle_low"], c["angle_top"], pow(v, 0.8)))
					* float(c["open_k"])
				)
			var cd: Vector3 = (d * cos(theta) + side * sin(theta)).normalized()
			# Never back through the stem.
			var out3: Vector3 = pos - _stem(c, pos.y)
			out3.y = 0.0
			if out3.length() > 0.25:
				var outn: Vector3 = out3.normalized()
				var dd: float = cd.dot(outn)
				if dd < -0.1:
					cd = (cd - outn * 2.0 * dd).normalized()
			kid_at.append(pts.size() - 1)
			kid_dir.append(cd)
			kid_f.append(f1)
			if k == 0:
				first_side = side
		# The zig-zag: the axis turns away from the branch it has just made (oak), or runs on (birch).
		if not pairs:
			d = (d - first_side * crook * 0.2).normalized()
	var me: int = sk.add(pts, order, parent, at_i, grp, state, length)
	for k: int in kid_at.size():
		var kid: int = id * 11 + k + 1
		var jit: float = 0.8 + 0.4 * _h(seed_v, kid, 10)
		var kl: float = 0.0
		var kgrp: int = grp
		var kstate: int = 0
		if order == 0:
			kl = _limb_len(
				c, pts[kid_at[k]], kid_dir[k], acos(clampf(kid_dir[k].y, -1.0, 1.0)), kid
			)
			c["groups"] = int(c["groups"]) + 1
			kgrp = int(c["groups"])
			if _h(seed_v, kid, 11) < 0.2 * float(c["old"]):
				kstate = 2
				kl *= 0.45
		elif order == 1:
			kl = maxf(length * float(c["len2"]) * (1.0 - 0.45 * kid_f[k]) * jit, 0.3)
		else:
			kl = clampf(length * 0.42, 0.22, 0.85) * (1.0 + 1.7 * float(c["weep"])) * jit
		_grow(sk, c, me, kid_at[k], pts[kid_at[k]], kid_dir[k], kl, order + 1, kgrp, kid, kstate)


## The pipe model, from the twigs down: a parent's radius^e is the sum of what it carries.
static func _radii(sk: Sk, c: Dictionary) -> void:
	var e: float = clampf(float(c["pipe"]), 1.6, 3.2)
	var n: int = sk.pts.size()
	for i: int in range(n - 1, -1, -1):
		var p: PackedVector3Array = sk.pts[i]
		var r := PackedFloat32Array()
		r.resize(p.size())
		var tip: float = 0.03 if sk.state[i] == 2 else (0.016 if sk.order[i] >= 3 else 0.02)
		var a: float = pow(tip, e)
		for j: int in range(p.size() - 1, -1, -1):
			a += sk.area[i][j]
			if j < p.size() - 1:
				a += pow(p[j].distance_to(p[j + 1]) * 0.014, e)
			r[j] = pow(a, 1.0 / e)
		sk.rad[i] = r
		if sk.parent[i] >= 0:
			sk.area[sk.parent[i]][sk.at[i]] += a
	# Fit to the species' girth at this age, and keep every limb thinner than what it leaves.
	var g: float = c["g"]
	var s: float = clampf(g / maxf(sk.rad[0][0], 0.001), 0.5, 2.4)
	for i: int in n:
		var r: PackedFloat32Array = sk.rad[i]
		var k: float = s
		# painter-look-wood2: the least width is a stem's own 0.012 (a sapling's leader runs up to a
		# fine tip, not a 4 cm pole), and a limb's is 0.75 of its parent's width at the joint when
		# that is less (a stick on a thin stem began as thick as the stem: 0.019 on 0.019).
		var least: float = 0.012 if i == 0 else (0.016 if sk.order[i] >= 3 else 0.019)
		if sk.parent[i] >= 0:
			var pr: float = sk.rad[sk.parent[i]][sk.at[i]]
			k = minf(s, 0.8 * pr / maxf(r[0], 0.0001))
			least = minf(least, maxf(0.75 * pr, LEAST_STICK))
		for j: int in r.size():
			r[j] = maxf(r[j] * k, least)
		sk.rad[i] = r
	var t: PackedFloat32Array = sk.rad[0]
	var top_r: float = lerpf(0.6, 0.12, c["lead"])
	var sp0: PackedVector3Array = sk.pts[0]
	var y_top: float = maxf(sp0[sp0.size() - 1].y, 0.01)
	for j: int in t.size():
		t[j] = maxf(t[j], g * lerpf(1.0, top_r, clampf(sp0[j].y / y_top, 0.0, 1.0)))
	t[0] = g * (1.08 + 0.3 * float(c["old"]))
	sk.rad[0] = t


## painter-look-wood: no strand narrows by more than 1 - NARROW_MIN from one node to the next. The
## pipe model takes a limb's whole area off the trunk at the node it leaves from, so the trunk
## above a heavy limb could stand at a third of the width below it. Raised from the base to the tip
## (a dead stub keeps its own taper), so a child only ever stands under a thicker parent: the
## children were fitted to their parent's radius at the joint, which this never lowers.
static func _steady(sk: Sk) -> void:
	for i: int in sk.pts.size():
		if sk.state[i] == 2:
			continue
		var r: PackedFloat32Array = sk.rad[i]
		# (the stem narrows by less at a node: a drop of a third at one node read as a horizontal
		# seam across the trunk under the crown)
		var keep: float = NARROW_STEM if i == 0 else NARROW_MIN
		for j: int in range(r.size() - 1):
			r[j + 1] = maxf(r[j + 1], r[j] * keep)
		sk.rad[i] = r


## The skeleton alone (for a bare tree, for measuring) and the context it was grown in.
static func skeleton(
	sp: Dictionary, cx: Dictionary, rng_seed: int, _conifer: bool, c: Dictionary
) -> Sk:
	var age: float = clampf(float(cx.get("age", 0.5)), 0.0, 1.0)
	var open: float = clampf(float(cx.get("openness", 0.5)), 0.0, 1.0)
	var side: Vector2 = cx.get("side", Vector2.ZERO)
	var old: float = smoothstep(0.7, 1.0, age)
	var young: float = 1.0 - smoothstep(0.15, 0.5, age)
	var sp_h: float = sp["height"]
	var flat_top: float = sp["flat_top"]
	var ft: float = smoothstep(flat_top - 0.12, flat_top + 0.18, age) if flat_top > 0.01 else 0.0
	var grow: float = 0.16 + 0.84 * (1.0 - pow(1.0 - minf(age / 0.72, 1.0), 1.7))
	var h: float = sp_h * grow * lerpf(1.22, 0.84, open) * (1.0 - 0.08 * ft)
	var g: float = maxf(
		0.025,
		(
			float(sp["girth"])
			* (0.06 + 0.94 * pow(age, 1.3))
			* lerpf(0.85, 1.1, open)
			* (1.0 + 0.22 * old)
		)
	)
	# Round 13: a stout species is short and thick while young, and forks early.
	var stout_y: float = float(sp["stout"]) * (1.0 - smoothstep(0.2, 0.7, age))
	h *= 1.0 - 0.2 * stout_y
	g *= 1.0 + 0.75 * stout_y
	var bole: float = sp["bole"]
	# Self-pruning: the clean stem rises with age, in a closed stand, and by species.
	var cb: float = clampf(
		(
			lerpf(
				lerpf(0.35, 0.62, 1.0 - young) * lerpf(1.0, bole, 0.5),
				lerpf(0.05, 0.2, 1.0 - young) * bole,
				open
			)
			+ 0.14 * ft
			+ 0.04 * old
		),
		0.03,
		0.78
	)
	var apical: float = clampf(
		(
			float(sp["apical"])
			+ 0.3 * (1.0 - open) * (1.0 - float(sp["apical"]))
			+ 0.7 * young * (1.0 - 0.85 * float(sp["stout"]))
		),
		0.0,
		1.0
	)
	var lead: float = smoothstep(0.3, 0.8, apical)
	var y_cb: float = cb * h
	var h_lead: float = lerpf(lerpf(y_cb + (h - y_cb) * 0.2, h, lead), h * 0.86, ft)
	var whorl: int = int(sp["whorl"])
	var crook: float = sp["crook"]
	c["seed"] = rng_seed
	c["age"] = age
	c["open"] = open
	c["old"] = old
	c["h"] = h
	c["g"] = g
	c["ft"] = ft
	c["lead"] = lead
	c["y_cb"] = y_cb
	c["lean"] = cx.get("lean", Vector2.ZERO)
	c["wob"] = Vector2(_h(rng_seed, 1, 1) * TAU, _h(rng_seed, 2, 1) * TAU)
	c["amp"] = (0.2 * g + 0.03 * h * crook) * (0.6 + 0.6 * old) + float(sp["sway"]) * 0.02 * h
	# painter-look-wood3: a sapling is not a ruled pole: it bends a little, to a side and by an
	# amount each seed draws (a third of that on a whorled conifer, which stands straight).
	var bend: float = young * h * (0.03 + 0.04 * _h(rng_seed, 6, 1))
	c["amp"] = float(c["amp"]) + bend * (1.0 if whorl == 0 else 0.35)
	c["phi0"] = _h(rng_seed, 3, 1) * TAU
	c["rc"] = (
		maxf(
			0.3,
			0.5 * float(sp["spread"]) * sp_h * (0.1 + 0.9 * pow(age, 0.85)) * lerpf(0.55, 1.0, open)
		)
		* (1.0 + 0.3 * stout_y)
	)
	c["irreg"] = clampf(float(sp["irreg"]), 0.0, 1.0)
	c["part"] = clampi(int(sp["part"]), 0, 4) if float(sp["curve"]) > 0.0 else 0
	# Round 14: a young weeper is one small fountain (a parting split it into two tufts).
	if float(sp["over"]) > 0.0 and age < 0.5:
		c["part"] = 0
	# Round 14: with `over` the parting is only a lifted hem (shorter limbs there made the crown
	# two-humped), and it faces the home view (+z), so the trunk shows where the table is seen from.
	c["part_az"] = (PI * 0.5 - 0.2) if float(sp["over"]) > 0.0 else (float(c["phi0"]) + 1.3)
	c["part_k"] = 0.9 if float(sp["over"]) > 0.0 else 0.55
	c["juv"] = clampf(float(sp["juv"]), 0.0, 1.0) * (1.0 - smoothstep(0.3, 0.75, age))
	c["flame"] = clampf(float(sp["flame"]), 0.0, 1.0)
	c["browse"] = float(sp["browse"]) * clampf(h / maxf(sp_h * 0.85, 0.1), 0.0, 1.0)
	c["collar"] = clampf(float(sp["collar"]), 0.0, 1.0)
	c["room"] = cx.get("room", PackedFloat32Array())
	c["side_len"] = minf(side.length(), 1.0)
	c["side_dir"] = side.normalized() if side.length() > 0.001 else Vector2.ZERO
	# A flat-topping species is a cone while it has its leader.
	c["widest"] = (
		lerpf(0.08, float(sp["widest"]), smoothstep(0.25, 0.65, age))
		if flat_top > 0.01
		else float(sp["widest"])
	)
	c["top_p"] = (
		lerpf(1.0, float(sp["top"]), smoothstep(0.25, 0.65, age))
		if flat_top > 0.01
		else float(sp["top"])
	)
	c["whorl"] = whorl
	c["crook"] = crook
	c["sag"] = sp["sag"]
	c["upturn"] = sp["upturn"]
	c["weep"] = sp["weep"]
	c["len2"] = sp["len2"]
	c["pipe"] = sp["pipe"]
	c["angle_top"] = sp["angle_top"]
	c["angle_low"] = lerpf(sp["angle_low"], 80.0, ft * 0.6)
	# A forest-grown tree holds its limbs steeper; an open-grown one lets them down.
	c["open_k"] = lerpf(0.76, 1.06, open)
	c["theta2"] = deg_to_rad(clampf(float(sp["angle_top"]) * 1.15, 22.0, 70.0))
	c["max_order"] = 1 if age < 0.17 else (2 if age < 0.3 else 3)
	c["twigs"] = clampi(
		int(round(float(sp["twigs"]) * lerpf(0.5, 1.0, smoothstep(0.17, 0.5, age)))), 1, 7
	)
	c["fine"] = clampi(int(sp["fine"]), 0, 6)
	c["arch"] = sp["arch"]
	c["fast"] = sp["fastigiate"]
	c["space2"] = maxf(0.4, sp_h * 0.055)
	c["groups"] = 0
	var per_crown: float = float(sp["tiers"]) if whorl >= 2 else float(sp["limbs"])
	var n_slots: int = clampi(int(per_crown * 1.6), 4, 24)
	c["slot_dy"] = sp_h * 1.22 / float(n_slots)

	# The stem's nodes: every slot the leader has grown past. Below the crown base a limb is
	# shed; for a while its stub stays.
	var ys := PackedFloat32Array()
	var kinds := PackedInt32Array()
	var slots := PackedInt32Array()
	for i: int in n_slots:
		var irr: float = c["irreg"]
		var y: float = (
			sp_h
			* 1.22
			* pow(
				(
					(
						float(i)
						+ lerpf(0.35, 0.1, irr)
						+ lerpf(0.3, 0.8, irr) * _h(rng_seed, 100 + i, 2)
					)
					/ float(n_slots)
				),
				1.22
			)
		)
		if whorl >= 2:
			# Round 14: a young conifer's whorls stand closer together (they stood apart as discs).
			y *= lerpf(1.0, 0.62, float(c["juv"]))
		if y > h_lead - 0.03 * h or y < 0.25:
			continue
		if y < y_cb:
			if (
				age > 0.3
				and y > y_cb - 0.3 * h
				and _h(rng_seed, 100 + i, 4) < 0.35 + 0.5 * (1.0 - open)
			):
				ys.append(y)
				kinds.append(2)
				slots.append(i)
			continue
		ys.append(y)
		kinds.append(0)
		slots.append(i)
	var sk := Sk.new()
	var tp := PackedVector3Array([_stem(c, 0.0), _stem(c, minf(0.06 * h, 0.5))])
	var y_last: float = minf(0.06 * h, 0.5)
	var node_of := PackedInt32Array()
	for k: int in ys.size():
		if ys[k] - y_last > 1.6:
			tp.append(_stem(c, (ys[k] + y_last) * 0.5))
		tp.append(_stem(c, ys[k]))
		node_of.append(tp.size() - 1)
		y_last = ys[k]
	if h_lead - y_last > 1.6:
		tp.append(_stem(c, (h_lead + y_last) * 0.5))
	tp.append(_stem(c, h_lead))
	sk.add(tp, 0, -1, 0, 0, 0, h_lead)
	for k: int in ys.size():
		var ni: int = node_of[k]
		var p: Vector3 = tp[ni]
		var tan: Vector3 = (tp[ni + 1] - tp[ni - 1]).normalized()
		var v: float = clampf((p.y - y_cb) / maxf(h - y_cb, 0.01), 0.0, 1.0)
		for w: int in maxi(whorl, 1):
			var id: int = 1000 + slots[k] * 8 + w
			var az: float = (
				float(c["phi0"]) + float(slots[k]) * GOLDEN + (_h(rng_seed, id, 12) - 0.5) * 0.7
			)
			if whorl >= 2:
				az = (
					float(c["phi0"])
					+ float(slots[k]) * (PI / float(whorl) + 0.3)
					+ float(w) * TAU / float(whorl)
					+ (_h(rng_seed, id, 12) - 0.5) * 0.45
				)
			var s0 := Vector3(cos(az), 0.0, sin(az))
			var sidev: Vector3 = (s0 - tan * s0.dot(tan)).normalized()
			if kinds[k] == 2:
				if w == 0 or _h(rng_seed, id, 13) < 0.5:
					var sd: Vector3 = (tan * cos(1.25) + sidev * sin(1.25)).normalized()
					sk.add(
						PackedVector3Array(
							[p, p + sd * (0.25 + g * 0.8 + 0.5 * _h(rng_seed, id, 14))]
						),
						1,
						0,
						ni,
						0,
						2,
						0.5
					)
				continue
			var theta: float = (
				deg_to_rad(lerpf(c["angle_low"], c["angle_top"], pow(v, 0.8))) * float(c["open_k"])
			)
			theta = lerpf(theta, deg_to_rad(78.0), ft * smoothstep(0.5, 1.0, v))
			var dir: Vector3 = (tan * cos(theta) + sidev * sin(theta)).normalized()
			var length: float = _limb_len(c, p, dir, theta, id)
			var state: int = 0
			# A limb an old tree has lost: a snag. Never the two at the top.
			if k < ys.size() - 2 and _h(rng_seed, id, 11) < 0.22 * old:
				state = 2
				length *= 0.42
			c["groups"] = int(c["groups"]) + 1
			_grow(sk, c, 0, ni, p, dir, length, 1, int(c["groups"]), id, state)
	# Where the leader gives out the stem divides into co-dominant limbs, one of them the
	# straighter; each carries limbs as the stem did.
	var top: Vector3 = tp[tp.size() - 1]
	if h - h_lead > 0.05 * h:
		# (painter-look-wood3: one more or one fewer than the species' count, by seed, and each fork's
		# spread and length drawn too: the flat-topped trees all stood as one umbrella)
		var nf: int = clampi(int(sp["forks"]) + int(_h(rng_seed, 4, 2) * 3.0) - 1, 2, 5)
		var phi_s: float = _h(rng_seed, 4, 1) * TAU
		for k: int in nf:
			var id: int = 500 + k
			var az: float = phi_s + TAU * float(k) / float(nf) + (_h(rng_seed, id, 12) - 0.5) * 0.6
			var theta: float = (
				deg_to_rad(float(sp["angle_top"])) * (0.3 if k == 0 else 0.85) * float(c["open_k"])
			)
			var spread: float = (74.0 if k > 0 else 58.0) + (_h(rng_seed, id, 15) - 0.5) * 22.0
			theta = lerpf(theta, deg_to_rad(spread), ft)
			var dir := Vector3(cos(az) * sin(theta), cos(theta), sin(az) * sin(theta))
			var length: float = minf(
				(h - h_lead) / maxf(cos(theta), 0.45) * (1.0 if k == 0 else 0.72 + 0.28 * _h(rng_seed, id, 16)),
				h * 0.6
			)
			c["groups"] = int(c["groups"]) + 1
			_grow(sk, c, 0, tp.size() - 1, top, dir, length, 0, int(c["groups"]), id, 0)
	_radii(sk, c)
	# (steadied first: the stem's top is what the forks share, and `_steady` raises it)
	_steady(sk)
	_forks(sk, clampf(float(c["pipe"]), 1.6, 3.2))
	_collars(sk, float(c["collar"]))
	_shoulder(sk)
	return sk


## painter-look-wood2: where the leader gives out, the stem divides into co-dominant limbs, and the
## pipe model's radii left them thin: each carries only its own crown (a few thin twigs) while the
## stem below stood at least 0.6 of the girth up to its last node (the floor `_radii` keeps), so the
## trunk ended in a flat shoulder with limbs half its width pushed into it like a sleeve. The forks
## now share the stem's width at the top as the pipe model says: the straight one (the first) takes
## FORK_LEAD of it, the rest share what is left (their areas to the power `e` sum to the stem's),
## and each tapers from there to FORK_TIP of that at its own tip. Only ever raised, never lowered.
static func _forks(sk: Sk, e: float) -> void:
	var top: int = sk.pts[0].size() - 1
	var forks := PackedInt32Array()
	for i: int in range(1, sk.pts.size()):
		if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
			forks.append(i)
	if forks.size() < 2:
		return
	var big: float = sk.rad[0][top]
	# (painter-look-wood3: the rest take FORK_REST of the stem's area between them, not what the
	# lead leaves: a mature oak's crown forks are wider than the pipe law's slender ones, which left
	# the trunk's top a shoulder.)
	var share: float = clampf(pow(FORK_REST / float(forks.size() - 1), 1.0 / e), 0.3, FORK_LEAD)
	for f: int in forks.size():
		var i: int = forks[f]
		var target: float = big * (FORK_LEAD if f == 0 else share)
		var r: PackedFloat32Array = sk.rad[i]
		var m: int = maxi(r.size() - 1, 1)
		for j: int in r.size():
			r[j] = maxf(r[j], target * lerpf(1.0, FORK_TIP, float(j) / float(m)))
		sk.rad[i] = r


## painter-look-wood3: the trunk narrows into its forks. Where the stem divides it stood at full
## girth to its last node, a flat shoulder with the widest fork at 0.72 of its width (the others at
## half) pushed into it: seen from the side the trunk ended in a horizontal edge (the "ring" under
## the crown, critic item 1). The stem's top now comes down to the widest fork over its last nodes
## (FORK_JOIN: the fork is that share of the stem where they meet), never by more than
## NARROW_STEM per node, and the limbs that leave the stem there are kept thinner than it as before.
## Only ever narrows, and only where the stem divides (two forks or more at its last node).
static func _shoulder(sk: Sk) -> void:
	var top: int = sk.pts[0].size() - 1
	var widest := 0.0
	var forks: int = 0
	for i: int in range(1, sk.pts.size()):
		if sk.parent[i] == 0 and sk.order[i] == 0 and sk.at[i] == top:
			forks += 1
			widest = maxf(widest, sk.rad[i][0])
	if forks < 2 or top < 2 or sk.rad[0][top] < FLARE_MIN_R:
		return
	var r: PackedFloat32Array = sk.rad[0]
	var to: float = maxf(widest / FORK_JOIN, r[top] * NARROW_STEM)
	if to >= r[top]:
		return
	r[top] = to
	for j: int in range(top - 1, 0, -1):
		r[j] = minf(r[j], r[j + 1] / NARROW_STEM)
	sk.rad[0] = r
	# The limbs that leave the stem on the narrowed nodes stay thinner than it, and what they carry
	# thinner than they (a limb is after its parent in the lists).
	var touched := {}
	for i: int in range(1, sk.pts.size()):
		var par: int = sk.parent[i]
		var on_stem: bool = par == 0 and sk.at[i] < top and sk.at[i] >= top - 3
		if not on_stem and not touched.has(par):
			continue
		var cr: PackedFloat32Array = sk.rad[i]
		var pr: float = sk.rad[par][sk.at[i]]
		var cap: float = FORK_JOIN * pr
		if cr[0] < FLARE_MIN_R:
			cap = maxf(0.8 * pr, LEAST_STICK)
		if cr[0] > cap:
			var k: float = cap / cr[0]
			for j: int in cr.size():
				cr[j] = maxf(cr[j] * k, minf(cr[j], LEAST_STICK))
			sk.rad[i] = cr
			touched[i] = true


## Round 13: a limb leaving the stem tapers along its whole length (the pipe model alone leaves
## an unbranched limb the same width from end to end: a plank) and swells where it joins: a
## point is added a little way out, and the radius at the joint is raised toward the stem's.
static func _collars(sk: Sk, col: float) -> void:
	var n: int = sk.pts.size()
	for i: int in range(1, n):
		var par: int = sk.parent[i]
		var r: PackedFloat32Array = sk.rad[i]
		var pr: float = sk.rad[par][sk.at[i]]
		# (a stick on a thin parent: see `_radii`)
		var least: float = minf(0.019, maxf(0.75 * pr, LEAST_STICK))
		if par == 0 and sk.order[i] == 1 and r.size() >= 3:
			var m: int = r.size() - 1
			for j: int in m + 1:
				r[j] = maxf(r[j] * lerpf(1.0, lerpf(1.0, 0.5, float(j) / float(m)), col), least)
		# A child is still thinner than what it leaves.
		if r[0] > 0.8 * pr:
			var k: float = 0.8 * pr / r[0]
			for j: int in r.size():
				r[j] = maxf(r[j] * k, minf(0.016, least))
		sk.rad[i] = r
	_steady(sk)
	# The flare: on every limb of any order wide enough to show one (the shader used to swell all
	# of them 1.6 times at the base, on top of this: a limb began wider than its parent). Baked
	# here it is capped at FLARE_MAX of the parent's width at the joint, so a limb never starts
	# wider than what it leaves.
	for i: int in range(1, n):
		if sk.state[i] != 0:
			continue
		var p: PackedVector3Array = sk.pts[i]
		var r: PackedFloat32Array = sk.rad[i]
		var seg: float = p[0].distance_to(p[1])
		var pr: float = sk.rad[sk.parent[i]][sk.at[i]]
		var cl: float = clampf(pr * 2.2, 0.2, 0.9)
		if r[0] < FLARE_MIN_R or seg < cl * 1.5:
			continue
		var f: float = cl / seg
		p.insert(1, p[0].lerp(p[1], f))
		r.insert(1, lerpf(r[0], r[1], f))
		# (and by the narrowing floor: the collar node beyond it is the limb's own width)
		r[0] = maxf(r[0], minf(minf(r[0] * FLARE, FLARE_MAX * pr), r[1] / NARROW_MIN))
		var a: PackedFloat32Array = sk.area[i]
		a.insert(1, 0.0)
		sk.pts[i] = p
		sk.rad[i] = r
		sk.area[i] = a
		for k: int in range(i + 1, n):
			if sk.parent[k] == i and sk.at[k] >= 1:
				sk.at[k] += 1


static func _strand(
	pts: PackedVector3Array,
	radii: PackedFloat32Array,
	phase: float,
	w0: float,
	w1: float,
	fine: bool
) -> PainterTreeMass:
	var m: PainterTreeMass = PainterTreeBase._strand(pts, radii, phase, w0, w1)
	if fine:
		# A twig is drawn by the block-in alone: no strokes of its own.
		m.params["built"] = true
	return m
