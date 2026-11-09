class_name FoliageDensityController
extends RefCounted

## Zoom-keyed thinning of ground cover: writes MultiMesh.visible_instance_count on the scatter
## chunks of ground cover (the wind category "grass": grass cards, sprig clumps, litter and
## flowers) so that, zoomed out, a share of them is not drawn.
##
## Why: the audit (docs/PERFORMANCE.md "Zoom-keyed ground thinning") found ground cover the
## largest foliage cost per instance (a card is a lit fragment, and a filled map draws three or
## four layers of them per pixel), that its cost follows the drawn instances almost linearly, and
## that zoomed out the canopy hides most of the ground the cards lie on while each card is
## smaller on screen. Thinning to two thirds at the far end (it was half; measured numbers in
## PERFORMANCE.md) costs less GPU there and nothing at the zoom the table is played at, where
## the ground cover is all visible at 1:1. The triangle budget this replaced counted triangles, which are not what foliage costs,
## and never engaged on a reference map.
##
## No instance moves or fades: every chunk is shuffled at build (ScatterGlbUtils for a GLB's
## scatter, ScatterRows.instance_order for an authored map's, both deterministic and seeded by the
## chunk's name), so a prefix of it is a spatially even sample and a thinner draw keeps the
## instances of a fuller one. The same instances stay while the camera zooms (no shimmer); the
## fraction moves in 1/STEPS steps over six metres of camera size, so a step drops about three
## percent of the ground cover, scattered over every chunk at once, while the zoom itself moves.
##
## Only ground cover is thinned: trees, bushes, rocks and a structure's decor are drawn in full at
## every zoom. Flowers are ground cover here on purpose: a flower is about four ground cards of
## cost (352-400 triangles, three surfaces, the full shader), so thinning the cards alone saved
## only 0.07 ms at zoom 20 on the reference map.
##
## The fraction is one process-wide value, set by GroundThinner (the play scene's node) from the
## camera, and read by whoever sizes a chunk (AuthoredScatter when it builds one, apply() at
## load). The view's eye mode, a perspective camera at the ground, never thins.

## Camera size (Camera3D.size, the orthographic height in metres) up to which every instance
## is drawn: the home zoom of a 100 ft map is 13.85, and half the ground cover missing there is
## visible at 1:1. A map whose home zoom is larger keeps its own home (keep_fraction's
## `full_until`).
const FULL_UNTIL_SIZE := 14.0
## The camera size at which the thinning reaches GROUND_KEEP for a map whose home is
## FULL_UNTIL_SIZE; the span scales with a larger home, so the ramp keeps its shape. It is also
## the default far end of the orbit zoom range.
const FLOOR_AT_SIZE := 20.0
## The share of ground cover still drawn at the far end of the ramp and beyond.
## Two thirds (user board perf-look-thin, "gentler", 2026-11-09; look-pending; it was one half),
## which the 1 / STEPS quantisation makes 21 / 32 = 0.656 at the far end.
const GROUND_KEEP := 2.0 / 3.0
## The fraction moves in steps of 1 / STEPS (1.0, 0.969, ... 0.656), so a zoom does not rewrite
## every chunk each frame.
const STEPS := 32
## Group of the ground-cover chunks that have been sized, so the thinner finds them without
## walking the tree.
const GROUP := &"ground_cover_chunk"
const MULTIMESH_SUFFIX := "_MultiMesh"
const _META_GROUND := &"is_ground_cover_chunk"

## The share of ground cover drawn now (1.0 = all). Process-wide: one camera looks at one map.
static var fraction: float = 1.0


## The share of ground cover to draw at orthographic camera `camera_size`, `full_until` being
## the size up to which all of it is drawn (at least FULL_UNTIL_SIZE). 1.0 up to it, GROUND_KEEP
## from `full_until` times FLOOR_AT_SIZE / FULL_UNTIL_SIZE, a smoothstep between, quantised to
## 1 / STEPS.
static func keep_fraction(camera_size: float, full_until: float = FULL_UNTIL_SIZE) -> float:
	var start := maxf(full_until, FULL_UNTIL_SIZE)
	var span := start * (FLOOR_AT_SIZE / FULL_UNTIL_SIZE - 1.0)
	var t := clampf((camera_size - start) / span, 0.0, 1.0)
	var eased := t * t * (3.0 - 2.0 * t)
	return snappedf(lerpf(1.0, GROUND_KEEP, eased), 1.0 / STEPS)


## How many of `count` instances of a ground-cover chunk are drawn at `keep`: the first
## ceil(count * keep) of its shuffled order, never fewer than one (a chunk is never emptied).
static func thinned_count(count: int, keep: float) -> int:
	if count <= 0 or keep >= 1.0:
		return maxi(count, 0)
	return clampi(ceili(float(count) * keep), 1, count)


## True for a scatter chunk of ground cover: named like a chunk (`<species>_MultiMesh...`, which
## a structure's decor is not) and of the wind category "grass" (grass cards, sprig clumps, litter
## and flowers; trees, bushes and rocks are not). Cached on the node.
static func is_ground(chunk: MultiMeshInstance3D) -> bool:
	if chunk.has_meta(_META_GROUND):
		return chunk.get_meta(_META_GROUND)
	if chunk.multimesh == null or chunk.multimesh.mesh == null:
		return false
	var ground := (
		String(chunk.name).contains(MULTIMESH_SUFFIX)
		and String(chunk.get_meta("wind_foliage_category", "")) == "grass"
	)
	chunk.set_meta(_META_GROUND, ground)
	return ground


## The visible_instance_count `chunk` should have now: all of its instances, except a
## ground-cover chunk at the current fraction. A ground chunk joins GROUP here.
static func visible_count(chunk: MultiMeshInstance3D) -> int:
	var count := chunk.multimesh.instance_count
	if not is_ground(chunk):
		return count
	if not chunk.is_in_group(GROUP):
		chunk.add_to_group(GROUP)
	return thinned_count(count, fraction)


## Sizes every scatter chunk under `map_root` (the load-time pass: every node carrying the
## "wind_foliage_category" meta, deny-listed rocks included) and returns the ground chunks.
static func apply(map_root: Node) -> int:
	var ground := 0
	for child in map_root.get_children():
		if child is MultiMeshInstance3D and child.has_meta("wind_foliage_category"):
			var chunk := child as MultiMeshInstance3D
			if chunk.multimesh != null:
				chunk.multimesh.visible_instance_count = visible_count(chunk)
				if is_ground(chunk):
					ground += 1
		ground += apply(child)
	return ground


## Moves the fraction to `keep` and re-sizes every ground chunk; returns how many it wrote.
## Does nothing when it is already there.
static func set_fraction(tree: SceneTree, keep: float) -> int:
	if is_equal_approx(keep, fraction):
		return 0
	fraction = keep
	var written := 0
	for node in tree.get_nodes_in_group(GROUP):
		var chunk := node as MultiMeshInstance3D
		if chunk != null and chunk.multimesh != null:
			chunk.multimesh.visible_instance_count = thinned_count(
				chunk.multimesh.instance_count, keep
			)
			written += 1
	return written
