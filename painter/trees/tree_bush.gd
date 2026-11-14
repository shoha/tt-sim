class_name PainterTreeBush
extends RefCounted
## A bush drawn by the painted trees' host as a crown with no skeleton (painter-bushes;
## docs/systems/painter.md "Trees"). Core's card-built bushes (Bush_BerryBush, Bush_Bush_: long
## arching leaf straps) never read in the crowns' hand on their own cards: three shader rounds
## left them as splayed shards, then faceted artichokes. Here a bush is a few leaf pads (leaf
## ellipsoids, the crowns' own masses), one dome and two or three lobes round it, laid in the
## asset's mesh box at the row's scale; the host packs, tones and strokes them as a tree's crown,
## so a bush takes the crowns' scalloped dabs, block-in, light, snow and moods with nothing of
## its own in the shaders.
##
## Every value is the row's: the box (the shipped mesh's AABB times the row's scale) and the seed,
## so a peer lays the same bush. Pure static functions, safe on a worker thread.
##
## Cost: a dome's MIN_ROOTS_DOME stroke roots and a lobe's MIN_ROOTS_LOBE (the pack's floor for a
## tree pad is 6), so a bush of core's sizes is about 6 + 3 x 4 = 18 roots (a larger one adds
## roots by pad area): 72 strokes at stroke level 1, against a tree's thousands (the village's
## 64 bushes: 1001 roots, 15.6 a bush); its pads are the block-in's ellipsoids (they cast the
## sun's shadow, as a crown's do), its strokes cast none.

## The share of the mesh box the pads fill (a card bush's straps splay past its leafy mass).
const BOX_FILL := 0.85
const MIN_ROOTS_DOME := 6
const MIN_ROOTS_LOBE := 4
## The pads' root spacing (metres; a tree pad's is 0.4): wide, so a pad's roots stay at the floors
## above (at 0.5 the village's 64 bushes averaged 22 roots, 89 level-1 strokes) and its four level-1
## strokes a root spread over it.
const SPACING := 0.7
## A bush's sway against a crown pad's (PainterTreeBase.W_PAD): low, stiff and near the ground.
const WIND_SHARE := 0.35
## A bush's form group (one light over the whole bush).
const FORM := 1


## The bush's box for the row: {"c": its centre's height above the row, "r": its radii (across,
## up, across)}, from the asset mesh's `aabb` at the row's `scale`. Round about the up axis, so a
## turned row keeps it.
static func box_of(aabb: AABB, scale: float) -> Dictionary:
	var half := aabb.size * 0.5
	var across := maxf(half.x, half.z) * scale * BOX_FILL
	var up := half.y * scale * BOX_FILL
	return {
		"c": aabb.get_center().y * scale,
		"r": Vector3(maxf(across, 0.12), maxf(up, 0.1), maxf(across, 0.12))
	}


## The pads of a bush in `box` (box_of) with seed `rng_seed`: a dome and two or three lobes, in the
## bush's own frame (its foot at the origin).
static func masses(box: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var r: Vector3 = box["r"]
	var cy: float = box["c"]
	var foot := maxf(cy - r.y, 0.0)
	var mid := Vector3(0.0, foot + r.y, 0.0)
	var out: Array[PainterTreeMass] = []
	var phase := _h(rng_seed, 1)
	var dome := Vector3(r.x * 0.74, r.y * 0.82, r.z * 0.74)
	var lean := Vector3(_h(rng_seed, 2) - 0.5, 0.0, _h(rng_seed, 3) - 0.5) * r.x * 0.2
	out.append(_pad(mid + lean + Vector3.UP * r.y * 0.04, dome, mid, phase, MIN_ROOTS_DOME))
	var lobes := 2 + int(_h(rng_seed, 4) * 1.99)
	var a0 := _h(rng_seed, 5) * TAU
	for k in lobes:
		var a := a0 + TAU * float(k) / float(lobes) + (_h(rng_seed, 10 + k) - 0.5) * 0.9
		var s := 0.46 + 0.14 * _h(rng_seed, 20 + k)
		var lr := Vector3(r.x * s, r.y * (s + 0.06), r.z * s)
		var out_r := r.x - lr.x
		var at := Vector3(cos(a) * out_r, foot + lr.y * 0.95, sin(a) * out_r)
		out.append(_pad(at, lr, mid, _h(rng_seed, 30 + k), MIN_ROOTS_LOBE))
	return out


static func _pad(
	c: Vector3, r: Vector3, centre: Vector3, phase: float, min_roots: int
) -> PainterTreeMass:
	return PainterTreeMass.make(
		PainterTreeMass.Shape.ELLIPSOID,
		Transform3D(Basis.IDENTITY, c),
		r,
		PainterTreeMass.Role.LEAF,
		{
			"form": FORM,
			"centre": centre,
			"spacing": SPACING,
			"wind": PainterTreeBase.W_PAD * WIND_SHARE,
			"phase": phase,
			"min_roots": min_roots
		}
	)


## A hash in 0..1 of the seed and a salt (integer arithmetic only, the same on every platform).
static func _h(rng_seed: int, salt: int) -> float:
	var h: int = (rng_seed * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10006.0
