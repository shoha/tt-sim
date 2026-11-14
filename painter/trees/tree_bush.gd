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
##   small (across radius under LARGE_R): a dome and two or three lobes round it, one form
##   large: a dark core and a SHELL of crown-sized clumps (CLUMP_R of the bush, within its
##          bounds) round its shoulder and on its top, each clump its own form, so the light turns
##          clump by clump and the snow lies on each clump's top, as on a crown's
## A berry or a flowering bush is another species row (species.json: bush_berry, bush_flower)
## whose leaf strokes carry the trim colour's marks in bunches (tree_roles.json), as the rowan's
## berries.
##
## Every value is the row's: the box (the shipped mesh's AABB times the row's scale) and the seed,
## so a peer lays the same bush. Pure static functions, safe on a worker thread.
##
## Cost: a small bush is about 6 + 3 x 4 = 18 stroke roots (the pads' floors, MIN_ROOTS_*), a large
## one ROOTS_CORE + ROOTS_CLUMP per clump: at most 2 + 7 x 3 = 23 roots, 92 strokes at stroke level
## 1 (two block instances of four pads, two of nine slots), against a tree's thousands. Its pads
## are the block-in's ellipsoids (they cast the sun's shadow, as a crown's do), its strokes cast
## none.

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
## A bush's form group (one light over a small bush; a large bush's core).
const FORM := 1
## The across radius (metres, the box's) from which a bush is laid as a core and a shell.
const LARGE_R := 0.7
## A shell clump's radius against the bush's across radius, and its bounds in metres (a crown
## clump's size: an oak's is about 0.4 to 0.6 m).
const CLUMP_SHARE := 0.36
const CLUMP_MIN := 0.3
const CLUMP_MAX := 0.55
## The shell's clumps at most (the ring and the top; with the core, two block instances of four).
const MAX_CLUMPS := 7
const ROOTS_CORE := 2
const ROOTS_CLUMP := 3
## The core's root spacing (metres): wide, so the pack's area rule leaves it at ROOTS_CORE (at
## SPACING a 3 m bush's core took 5, and the village's bushes averaged 101 level-1 strokes).
const CORE_SPACING := 1.6

## False lays every bush as a small one, as before card painter-plants-fix3 (an A/B switch for a
## cost sitting, as PainterBuildings.paint_yard; the host must regrow its bushes after a change).
static var shell := true


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
		out.append(_pad(at, lr, mid, _h(rng_seed, 30 + k), MIN_ROOTS_LOBE, FORM))
	return out


## A large bush: a core (the dark inside the clumps, one form) and a shell of clumps round its
## shoulder and on its top, each its own form, their outer edges on the bush's bounds.
static func _shell(box: Dictionary, rng_seed: int) -> Array[PainterTreeMass]:
	var r: Vector3 = box["r"]
	var cy: float = box["c"]
	var foot := maxf(cy - r.y, 0.0)
	var mid := Vector3(0.0, foot + r.y, 0.0)
	var out: Array[PainterTreeMass] = []
	var core := Vector3(r.x * 0.74, r.y * 0.72, r.z * 0.74)
	out.append(_pad(mid, core, mid, _h(rng_seed, 1), ROOTS_CORE, FORM, CORE_SPACING))
	var cr := clampf(r.x * CLUMP_SHARE, CLUMP_MIN, CLUMP_MAX)
	var ring_r := r.x - cr
	var ring := clampi(roundi(TAU * ring_r * 0.85 / (1.5 * cr)), 3, MAX_CLUMPS - 1)
	var a0 := _h(rng_seed, 5) * TAU
	for k in ring:
		var a := a0 + TAU * float(k) / float(ring) + (_h(rng_seed, 10 + k) - 0.5) * 0.5
		# The shoulder: 0.25 to 0.6 rad above the bush's middle, so the clumps' tops catch the light.
		var lat := 0.25 + 0.35 * _h(rng_seed, 40 + k)
		var s := 0.9 + 0.25 * _h(rng_seed, 20 + k)
		var at := (
			mid
			+ Vector3(cos(a) * cos(lat) * ring_r, sin(lat) * (r.y - cr), sin(a) * cos(lat) * ring_r)
		)
		var lr := Vector3(cr * s, cr * s * 0.86, cr * s)
		out.append(_pad(at, lr, mid, _h(rng_seed, 30 + k), ROOTS_CLUMP, FORM + 1 + k))
	var top := mid + Vector3(
		(_h(rng_seed, 2) - 0.5) * cr, r.y - cr * 0.9, (_h(rng_seed, 3) - 0.5) * cr
	)
	var top_r := Vector3(cr * 1.1, cr * 0.9, cr * 1.1)
	out.append(_pad(top, top_r, mid, _h(rng_seed, 6), ROOTS_CLUMP, FORM + 1 + ring))
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
