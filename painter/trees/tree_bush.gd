class_name PainterTreeBush
extends RefCounted
## A bush drawn by the painted trees' host as a crown with no skeleton (painter-bushes;
## docs/systems/painter.md "Trees"). Core's card-built bushes (Bush_Bush_: long arching leaf
## straps) never read in the crowns' hand on their own cards: three shader rounds left them as
## splayed shards, then faceted artichokes. Here a bush is four leaf pads (leaf ellipsoids, the
## crowns' own masses) laid in the asset's mesh box at the row's scale; the host packs, tones and
## strokes them as a tree's crown, so a bush takes the crowns' scalloped dabs, block-in, light, snow
## and moods with nothing of its own in the shaders.
##
## ONE ORGANIC MASS (painter-look-bushes 3; the owner: bushes read as "ice cream scoops in a cone"):
## the earlier layouts stood three equal balls round the foot and a fourth on top of them, each its
## own form, so every ball took its own lit cap and the seams between them read as stacked spheres.
## Now the four pads are one form group (the light turns over the whole bush as over one mound, and
## the lit plane runs across the seams) and are unequal and overlapping:
##   body      a wide, low, rotated ellipsoid (longer one way than the other) that carries the bush
##   two lobes unequal ellipsoids at the body's flanks, tilted outward, one low and wide, one
##             higher and smaller, so the outline is lumpy and no horizontal seam runs round it
##   shoulder  a small flat ellipsoid on the high side, its top below the box's, bridging the lobes
## No pad stands on another: the bush is wider than tall (its height is about 0.8 of its box).
## A berry or a flowering bush is another species row (species.json: bush_berry, bush_flower)
## whose leaf strokes carry the trim colour's marks in bunches (tree_roles.json), as the rowan's
## berries.
##
## Every value is the row's: the box (the shipped mesh's AABB times the row's scale) and the seed,
## so a peer lays the same bush. Pure static functions, safe on a worker thread.
##
## Cost: the pads, not the strokes (painter-plants-fix4: a pad's block-in, drawn in the camera's and
## the sun's passes, cost about 0.001 ms at the village's home view and a level-1 stroke almost
## nothing). Four pads (one block instance) of ROOTS_PAD roots, 20 roots, 80 strokes at stroke
## level 1, against a tree's thousands. Its pads are the block-in's ellipsoids (they cast the sun's
## shadow, as a crown's do), its strokes cast none.

## The share of the mesh box the pads fill (a card bush's straps splay past its leafy mass).
const BOX_FILL := 0.85
## The pads' root spacing (metres; a tree pad's is 0.4): wide, so a pad's roots stay at the floor
## below and its level-1 strokes a root spread over it.
const SPACING := 0.5
## A bush's sway against a crown pad's (PainterTreeBase.W_PAD): low, stiff and near the ground.
const WIND_SHARE := 0.35
## The bush's one form group.
const FORM := 1
## The pads of a bush (one block instance) and a pad's roots (the floor; a large pad takes more).
const PADS := 4
const ROOTS_PAD := 4
## The bush's height against its box's (the mound stands lower than the mesh's tallest straps).
const HEIGHT_SHARE := 0.82

## A pad's roots (ROOTS_PAD; a switch for a look or cost sitting, regrown).
static var clump_roots := ROOTS_PAD


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


## The pads of a bush in `box` (box_of) with seed `rng_seed`, in the bush's own frame (its foot at
## the origin): the body, two flank lobes and the shoulder, all one form.
static func masses(box: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var r: Vector3 = box["r"]
	var top := (float(box["c"]) + r.y) * HEIGHT_SHARE
	var rx := r.x
	var out: Array[PainterTreeMass] = []
	var yaw := _h(rng_seed, 5) * TAU
	var mid := Vector3(0.0, top * 0.45, 0.0)
	# The body: wide and low, longer along its yaw than across it.
	var long_k := 0.84 + 0.12 * _h(rng_seed, 6)
	var short_k := 0.58 + 0.12 * _h(rng_seed, 7)
	var body := Vector3(rx * long_k, top * 0.34, rx * short_k)
	var lean := Vector3(_h(rng_seed, 2) - 0.5, 0.0, _h(rng_seed, 3) - 0.5) * rx * 0.14
	# (Roots come in twos, a slot: the body takes one slot more than a lobe, 9 slots in all.)
	var roots_body := clump_roots + 2
	out.append(
		_pad(lean + Vector3(0.0, body.y * 0.92, 0.0), body, yaw, Vector2.ZERO, mid, 0.0, roots_body)
	)
	# Two flank lobes, unequal, on opposite-ish sides of the body's long axis.
	for k in 2:
		var side := 1.0 if k == 0 else -1.0
		var a := yaw + side * (0.2 + 0.5 * _h(rng_seed, 10 + k))
		var s := (0.46 if k == 0 else 0.34) + 0.1 * _h(rng_seed, 20 + k)
		var lz := rx * s * (0.8 + 0.3 * _h(rng_seed, 40 + k))
		var lr := Vector3(rx * s, top * (0.27 if k == 0 else 0.3), lz)
		var out_r := maxf(rx * long_k - lr.x * 0.55, 0.0)
		var c := Vector3(cos(a) * out_r * side, 0.0, sin(a) * out_r * side)
		c.y = lr.y * (0.92 if k == 0 else 1.55)
		var jitter := Vector2(_h(rng_seed, 50 + k) - 0.5, _h(rng_seed, 60 + k) - 0.5) * 0.2
		var tilt := Vector2(side * 0.18, -side * 0.12) + jitter
		out.append(_pad(c, lr, yaw + _h(rng_seed, 30 + k) * TAU, tilt, mid, _h(rng_seed, 70 + k)))
	# The shoulder: small and flat on the body's high side, its top under the box's.
	var sa := yaw + PI * 0.5 + (_h(rng_seed, 4) - 0.5) * 1.4
	var sr := Vector3(rx * 0.36, top * 0.2, rx * 0.3)
	var sat := Vector3(cos(sa) * rx * 0.34, top * 0.58, sin(sa) * rx * 0.34)
	out.append(_pad(sat, sr, sa, Vector2(0.1, 0.1), mid, _h(rng_seed, 6)))
	return out


static func _pad(
	c: Vector3,
	r: Vector3,
	yaw: float,
	tilt: Vector2,
	centre: Vector3,
	phase: float,
	roots: int = -1
) -> PainterTreeMass:
	var basis := Basis.from_euler(Vector3(tilt.x, yaw, tilt.y))
	return PainterTreeMass.make(
		PainterTreeMass.Shape.ELLIPSOID,
		Transform3D(basis, c),
		r,
		PainterTreeMass.Role.LEAF,
		{
			"form": FORM,
			"bush": true,
			"centre": centre,
			"spacing": SPACING,
			"wind": PainterTreeBase.W_PAD * WIND_SHARE,
			"phase": phase,
			"min_roots": roots if roots > 0 else clump_roots
		}
	)


## A hash in 0..1 of the seed and a salt (integer arithmetic only, the same on every platform).
static func _h(rng_seed: int, salt: int) -> float:
	var h: int = (rng_seed * 374761393 + salt * 668265263) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h % 10007) / 10006.0
