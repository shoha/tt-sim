class_name WaterSurface
extends RefCounted

## The water surface as something to stand on, measure along and draw the grid on. Water
## renders without collision on the terrain layer (layer 1), so brushes, the sculpt and
## paint rays and a wading token's landing all see the bed through it. Its surface is
## collision on its own layer instead (LAYER, physics layer 3): the authored water's
## per-body StaticBody3Ds (AuthoredWater) and one body per Blender `-water` plane
## (WaterGlbUtils.process_water_meshes). A downward ray on WALKABLE_MASK therefore finds
## max(ground, water surface), which is what the grid, the measure tool and the drag ruler
## use; a token's landing picks between the bed and the surface by the float rule below.
##
## Float rule. A token stands on the bed in wadeable water and floats in deep water, its
## base DRAFT_M below the surface (landing_y()). Authored bodies say which they are (their
## depth class, FLOATS_META on the body: WaterBody.is_wadeable()); a Blender plane has no
## class, so there the water floats a token where it is at least FLOAT_DEPTH_M deep (between
## the waist class, 0.9 m, and the deep class, 2.0 m). Where a floating body's bed rises
## above the float height (its shallow edge), the token stands on the bed: the landing is
## the higher of the two, so walking out of deep water onto a bank is continuous.
## A token the water hides (is_submerged()) shows a SubmergedMarker at the surface above it.
## Summary: docs/ARCHITECTURE.md "Authored water at runtime".

## Collision layer bit of water surfaces (physics layer 3).
const LAYER := 4
## The terrain layer every ground ray uses (DragPlaceController.TERRAIN_COLLISION_LAYER).
const TERRAIN_LAYER := 1
## Ground or water surface, whichever is higher.
const WALKABLE_MASK := TERRAIN_LAYER | LAYER
## Set on every water surface body; true or false for authored bodies (floats or wades),
## absent on a Blender plane's body (the depth decides, FLOAT_DEPTH_M).
const FLOATS_META := &"tt_water_floats"
## Set on every water surface body, so a hit can be told from ground whatever its layer.
const BODY_META := &"tt_water_surface"
## How far below the surface a floating token's base rides.
const DRAFT_M := 0.2
## A Blender water plane floats tokens where the water is at least this deep.
const FLOAT_DEPTH_M := 1.4
## A water cast starts this far above where the matching ground cast starts: a wading
## token's top (where its landing ray starts) can be under the surface of deep water.
const CAST_CLEARANCE_M := 2.5
const RAY_LENGTH := 1000.0
## The retry offset of a water ray that missed (water_below()).
const VERTEX_NUDGE := Vector3(0.0007, 0.0, 0.0011)
## Gentle bob of a floating token's visuals: amplitude (m) and period (s).
const BOB_M := 0.03
const BOB_PERIOD_S := 2.6
## A token counts as submerged (its SubmergedMarker shows) while less than this much of it
## stands above the surface, or less than SUBMERGED_SHARE of its height, whichever is more:
## a sliver among the ripples reads as gone at play zoom (a 0.71 m token in 0.9 m water
## shows nothing; with 12 cm of it out, only a speck of its crest among the foam).
const SUBMERGED_FREEBOARD_M := 0.1
const SUBMERGED_SHARE := 0.2


## Where a token's base rests over bed height `bed_y` under a water surface at `surface_y`
## (NAN for no water) that floats tokens when `floats`: the bed in wadeable water or none,
## else the float height, never below the bed. Pure.
static func landing_y(bed_y: float, surface_y: float, floats: bool) -> float:
	if is_nan(surface_y) or surface_y <= bed_y or not floats:
		return bed_y
	return maxf(bed_y, surface_y - DRAFT_M)


## Whether a surface floats tokens: an authored body's own answer (`body_floats` a bool), or
## for a Blender plane (null) whether the water `depth` metres deep reaches FLOAT_DEPTH_M.
## Pure.
static func floats_for(body_floats: Variant, depth: float) -> bool:
	if body_floats is bool:
		return body_floats
	return depth >= FLOAT_DEPTH_M


## Whether a token standing from `base_y` to `top_y` (world Y) is hidden by a water surface at
## `surface_y` (NAN for none): its base under the surface and less than
## max(SUBMERGED_FREEBOARD_M, SUBMERGED_SHARE of its height) of it above. A small token
## wading waist-deep water is; a floating token rides at the surface and is not, unless it
## is tiny. Pure.
static func is_submerged(base_y: float, top_y: float, surface_y: float) -> bool:
	if is_nan(surface_y) or base_y >= surface_y:
		return false
	var showing := maxf(SUBMERGED_FREEBOARD_M, SUBMERGED_SHARE * (top_y - base_y))
	return top_y < surface_y + showing


## The world Y of the water surface hiding a token whose base is at world `base` and which
## stands `height` metres tall (is_submerged()), or NAN when no water hides it. One or two
## rays on LAYER, cast from above the token's top.
static func submerged_surface(
	space: PhysicsDirectSpaceState3D, base: Vector3, height: float
) -> float:
	var water := water_below(space, base, base.y + height + CAST_CLEARANCE_M)
	if water.is_empty():
		return NAN
	var y: float = water.y
	return y if is_submerged(base.y, base.y + height, y) else NAN


## The first water surface straight below world (xz.x, from_y, xz.z): {"y": world Y,
## "floats": the body's FLOATS_META or null, "collider"}, or {} when there is none.
static func water_below(space: PhysicsDirectSpaceState3D, xz: Vector3, from_y: float) -> Dictionary:
	var hit := cast_down(space, xz, from_y, LAYER)
	if hit.is_empty():
		# A ray exactly through a vertex the surface's triangles share can slip between them
		# (seen at the map origin, a vertex of every authored surface); a hair aside hits.
		hit = cast_down(space, xz + VERTEX_NUDGE, from_y, LAYER)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	var floats: Variant = null
	if collider != null and collider.has_meta(FLOATS_META):
		floats = collider.get_meta(FLOATS_META)
	return {"y": (hit.position as Vector3).y, "floats": floats, "collider": collider}


## A ray straight down from world (xz.x, from_y, xz.z) on `mask`, skipping the bodies of
## `exclude` (RIDs): the intersect_ray() result, {} on a miss or without a space.
static func cast_down(
	space: PhysicsDirectSpaceState3D,
	xz: Vector3,
	from_y: float,
	mask: int,
	exclude: Array[RID] = []
) -> Dictionary:
	if space == null:
		return {}
	var origin := Vector3(xz.x, from_y, xz.z)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + Vector3.DOWN * RAY_LENGTH)
	query.collision_mask = mask
	if not exclude.is_empty():
		query.exclude = exclude
	return space.intersect_ray(query)


## True when an intersect_ray() hit is a water surface.
static func is_water_hit(hit: Dictionary) -> bool:
	var collider: Object = hit.get("collider")
	return collider != null and collider.has_meta(BODY_META)


## The ground a token lands on at world XZ `xz`: the bed found casting down on the terrain
## layer from `ground_top`, raised to the float height (landing_y()) under a surface found
## casting down on LAYER from `ground_top` + CAST_CLEARANCE_M. Vector3.INF with no bed.
static func landing_below(
	space: PhysicsDirectSpaceState3D, xz: Vector3, ground_top: float
) -> Vector3:
	var bed := cast_down(space, xz, ground_top, TERRAIN_LAYER)
	if bed.is_empty():
		return Vector3.INF
	var at: Vector3 = bed.position
	var water := water_below(space, xz, ground_top + CAST_CLEARANCE_M)
	if water.is_empty():
		return at
	var floats := floats_for(water.floats, water.y - at.y)
	return Vector3(at.x, landing_y(at.y, water.y, floats), at.z)


## The walkable surface at world XZ `xz`: the higher of the ground (terrain layer, cast from
## `ground_top`) and a water surface (cast from `ground_top` + CAST_CLEARANCE_M), for the
## drag ruler and anything else that measures along the surface. Vector3.INF with neither.
static func surface_below(
	space: PhysicsDirectSpaceState3D, xz: Vector3, ground_top: float
) -> Vector3:
	var ground := cast_down(space, xz, ground_top, TERRAIN_LAYER)
	var water := water_below(space, xz, ground_top + CAST_CLEARANCE_M)
	if ground.is_empty() and water.is_empty():
		return Vector3.INF
	var y := -INF
	if not ground.is_empty():
		y = (ground.position as Vector3).y
	if not water.is_empty():
		y = maxf(y, water.y)
	return Vector3(xz.x, y, xz.z)


## True when a token whose base is at `base` floats: a floating surface is above it and the
## base sits at its float height (within `tolerance`). For the bob after a landing or a
## synced move.
static func floats_at(
	space: PhysicsDirectSpaceState3D, base: Vector3, tolerance: float = 0.05
) -> bool:
	var water := water_below(space, base, base.y + CAST_CLEARANCE_M)
	if water.is_empty() or water.y <= base.y:
		return false
	var bed := cast_down(space, base, water.y, TERRAIN_LAYER)
	var bed_y: float = (bed.position as Vector3).y if not bed.is_empty() else -INF
	if not floats_for(water.floats, water.y - bed_y):
		return false
	return absf(base.y - (water.y - DRAFT_M)) <= tolerance


## A StaticBody3D on LAYER only (no mask, not ray-pickable) carrying BODY_META and, when
## `floats` is a bool, FLOATS_META, with one CollisionShape3D of `faces` (triangles).
static func make_body(
	body_name: String, faces: PackedVector3Array, floats: Variant
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = LAYER
	body.collision_mask = 0
	body.input_ray_pickable = false
	body.set_meta(BODY_META, true)
	if floats is bool:
		body.set_meta(FLOATS_META, floats)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	# Found from above whatever the winding (a Blender plane's may face either way).
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision)
	return body
