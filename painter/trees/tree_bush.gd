class_name PainterTreeBush
extends RefCounted
## A bush drawn by the painted trees' host as a crown with no skeleton (painter-bushes;
## docs/systems/painter.md "Trees"). Core's card-built bushes (Bush_BerryBush, Bush_Bush_: long
## arching leaf straps) never read in the crowns' hand on their own cards: three shader rounds
## left them as splayed shards, then faceted artichokes. Here a bush is a few leaf pads (leaf
## ellipsoids, the crowns' own masses) laid in the asset's mesh box at the row's scale; the host
## packs, tones and strokes them as a tree's crown, so a bush takes the crowns' scalloped dabs,
## block-in, light, snow and moods with nothing of its own in the shaders.
##
## Two layouts by size (painter-plants-fix3: a large bush laid as one dome and two lobes, all one
## form, read at token zoom as a smooth ball with one broad lit band and a hard light/shade split,
## and its snow as one pale lens):
##   small (across radius under LARGE_R): a dome and two or three lobes round it, each its own
##          form, so a lobe turns from the light and takes its snow on its own top
##   large: a SHELL of clumps (CLUMP_SHARE of the bush across, within its bounds), RING round its
##          foot and one on its top, each its own form, so the light turns clump by clump and the
##          snow lies on each clump's top, as on a crown's
## A berry or a flowering bush is another species row (species.json: bush_berry, bush_flower)
## whose leaf strokes carry the trim colour's marks in bunches (tree_roles.json), as the rowan's
## berries.
##
## Every value is the row's: the box (the shipped mesh's AABB times the row's scale) and the seed,
## so a peer lays the same bush. Pure static functions, safe on a worker thread.
##
## Cost: the pads, not the strokes (painter-plants-fix4 measured fix3's shell, a core and up to
## seven clumps, eight pads a bush: a pad's block-in, drawn in the camera's and the sun's passes,
## cost about 0.001 ms at the village's home view and a level-1 stroke almost nothing). So a bush
## keeps the tip's pad count: a small one three or four pads, about 6 + 3 x 4 = 18 stroke roots
## (the pads' floors, MIN_ROOTS_*); a large one four pads (one block instance) and (RING + 1) x
## ROOTS_CLUMP = 12 roots, 48 strokes at stroke level 1, against a tree's thousands. Its pads are
## the block-in's ellipsoids (they cast the sun's shadow, as a crown's do), its strokes cast none.

## The share of the mesh box the pads fill (a card bush's straps splay past its leafy mass).
const BOX_FILL := 0.85
const MIN_ROOTS_DOME := 9
const MIN_ROOTS_LOBE := 6
## The pads' root spacing (metres; a tree pad's is 0.4): wide, so a pad's roots stay at the floors
## above (at 0.5 the village's 64 bushes averaged 22 roots, 89 level-1 strokes) and its four level-1
## strokes a root spread over it.
const SPACING := 0.5
## A bush's sway against a crown pad's (PainterTreeBase.W_PAD): low, stiff and near the ground.
const WIND_SHARE := 0.35
## A bush's first form group (a small bush's dome; each lobe or clump takes the next).
const FORM := 1
## The across radius (metres, the box's) from which a bush is laid as a shell of clumps.
const LARGE_R := 0.7
## A shell clump's radius against the bush's across radius (three of them close the bush round its
## axis, with no core inside), and its bounds in metres.
const CLUMP_SHARE := 0.52
const CLUMP_MIN := 0.36
const CLUMP_MAX := 0.9
## The clumps round the foot (with the top one, four pads: one block instance) and a clump's roots.
const RING := 3
const ROOTS_CLUMP := 8

## False lays every bush as a small one, as before card painter-plants-fix3 (an A/B switch for a
## cost sitting, as PainterBuildings.paint_yard; the host must regrow its bushes after a change).
static var shell := true
## A clump's roots (ROOTS_CLUMP; a switch for a look or cost sitting, regrown as `shell`).
static var clump_roots := ROOTS_CLUMP


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
## the origin): a small bush's dome and lobes, a large one's core and shell.
static func masses(box: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var r: Vector3 = box["r"]
	if shell and r.x >= LARGE_R:
		return _shell(box, rng_seed)
	var cy: float = box["c"]
	var foot := maxf(cy - r.y, 0.0)
	var mid := Vector3(0.0, foot + r.y, 0.0)
	var out: Array[PainterTreeMass] = []
	var phase := _h(rng_seed, 1)
	var dome := Vector3(r.x * 0.74, r.y * 0.82, r.z * 0.74)
	var lean := Vector3(_h(rng_seed, 2) - 0.5, 0.0, _h(rng_seed, 3) - 0.5) * r.x * 0.2
	out.append(_pad(mid + lean + Vector3.UP * r.y * 0.04, dome, mid, phase, MIN_ROOTS_DOME, FORM))
	var lobes := 2 + int(_h(rng_seed, 4) * 1.99)
	var a0 := _h(rng_seed, 5) * TAU
	for k in lobes:
		var a := a0 + TAU * float(k) / float(lobes) + (_h(rng_seed, 10 + k) - 0.5) * 0.9
		var s := 0.46 + 0.14 * _h(rng_seed, 20 + k)
		var lr := Vector3(r.x * s, r.y * (s + 0.06), r.z * s)
		var out_r := r.x - lr.x
		var at := Vector3(cos(a) * out_r, foot + lr.y * 0.95, sin(a) * out_r)
		out.append(_pad(at, lr, mid, _h(rng_seed, 30 + k), MIN_ROOTS_LOBE, FORM + 1 + k))
	return out


## A large bush: RING clumps standing round its foot, their outer edges on the bush's bounds and
## overlapping round its axis, and one on its top, each its own form.
static func _shell(box: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var r: Vector3 = box["r"]
	var cy: float = box["c"]
	var foot := maxf(cy - r.y, 0.0)
	var mid := Vector3(0.0, foot + r.y, 0.0)
	var out: Array[PainterTreeMass] = []
	var cr := clampf(r.x * CLUMP_SHARE, CLUMP_MIN, CLUMP_MAX)
	var ring_r := maxf(r.x - cr, 0.0)
	var a0 := _h(rng_seed, 5) * TAU
	for k in RING:
		var a := a0 + TAU * float(k) / float(RING) + (_h(rng_seed, 10 + k) - 0.5) * 0.6
		var s := 0.9 + 0.2 * _h(rng_seed, 20 + k)
		# From the ground (not the box's foot, which the fill lifts) to a little over the bush's middle,
		# so the ring closes its body.
		var lr := Vector3(cr * s, r.y * 0.62 * s, cr * s)
		var at := Vector3(cos(a) * ring_r, lr.y * 0.92, sin(a) * ring_r)
		out.append(_pad(at, lr, mid, _h(rng_seed, 30 + k), clump_roots, FORM + 1 + k))
	# The top clump, a little off the axis, its top on the bush's.
	var top_r := Vector3(cr * 1.1, r.y * 0.52, cr * 1.1)
	var top := Vector3(
		(_h(rng_seed, 2) - 0.5) * cr * 0.5,
		foot + 2.0 * r.y - top_r.y,
		(_h(rng_seed, 3) - 0.5) * cr * 0.5
	)
	out.append(_pad(top, top_r, mid, _h(rng_seed, 6), clump_roots, FORM + 1 + RING))
	return out


static func _pad(
	c: Vector3,
	r: Vector3,
	centre: Vector3,
	phase: float,
	min_roots: int,
	form: int,
	spacing: float = SPACING
) -> PainterTreeMass:
	return PainterTreeMass.make(
		PainterTreeMass.Shape.ELLIPSOID,
		Transform3D(Basis.IDENTITY, c),
		r,
		PainterTreeMass.Role.LEAF,
		{
			"form": form,
			"centre": centre,
			"spacing": spacing,
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
