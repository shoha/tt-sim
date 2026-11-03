class_name EyeCollider
extends RefCounted

## The eye view's walls: a sphere (the walker's head and shoulders) swept through the physics
## world from the foot's old to its new position, at the eye's height, against the collision the
## map already has. Owner verdict SL6 (2026-11-02): walls and doors stop the eye, no interiors.
##
## What blocks is the terrain layer (WaterSurface.TERRAIN_LAYER, 1), which holds the authored
## structures' and walls' bodies, the crossings' (bridge rails and piers) and a dressed GLB's own
## collision. What does not: tokens (layer 2), water, grass and scatter (no bodies). The authored
## ground's own body is excluded by the caller (`exclude`), because the eye follows the ground by
## its height (EyeView) rather than by touching it: a sphere 1.6 m up never meets a slope, and a
## steep one is walked up, not stopped by.
##
## A move is cut into segments no longer than the sphere's radius (EyeRig.cast_step_count), so a
## run of 10 m/s or a long glide cannot jump a thin wall. A blocked segment ends at the safe
## fraction of the cast (a gap of a few millimetres, never inside the wall), the rest of the move
## is projected onto the wall (EyeRig.slide_motion) and swept again, up to MAX_SLIDES times, which
## is enough to settle into a corner without jitter: the position after a slide is again a safe
## cast position, so the next frame starts clear of the wall and meets it the same way.

## How many times one move may be redirected along a surface (a corner takes two).
const MAX_SLIDES := 3
## The collision sphere's radius, metres at map scale 1. Wider than a shoulder on purpose: the
## recipes' doors are open holes in the collision (measured on the dressed hamlet: 1.0 m wide,
## 2026-11-02), and the owner wants no interiors (SL6), so the sphere's diameter (1.1 m) must not
## fit through a standard door. A wider opening (a gate, a double door) is still passable.
const RADIUS_M := 0.55
## A move shorter than this (metres) is done.
const EPSILON := 0.0005
## How far past the first contact the probe for the surface normal looks, as a fraction of the
## segment, and the margin it inflates the sphere by.
const NORMAL_PROBE_MARGIN := 0.03
## The cosine above which the contact's radial direction and the engine's normal are the same
## surface (about 1 degree).
const RADIAL_AGREES := 0.9998
## A slid move is pushed this far (metres) away from the surface it slid on, so the residue of
## an estimated normal never presses it back into the surface and holds it still.
const SKIN_M := 0.0005

## Contacts met by the last move (tests, probes).
var last_hits: int = 0

var _space: PhysicsDirectSpaceState3D = null
var _exclude: Array[RID] = []
var _shape := SphereShape3D.new()


## Sweep through `space`, skipping the bodies `exclude`, with a sphere of `radius` metres.
func _init(space: PhysicsDirectSpaceState3D, exclude: Array[RID], radius: float = RADIUS_M) -> void:
	_space = space
	_exclude = exclude
	_shape.radius = radius


## The foot (world XZ) after moving from `from` by `motion`, the sphere's centre at world height
## `height`: stopped at walls and slid along them. `from` itself is not tested (a foot placed
## inside a body by a teleport can walk out of it).
func move(from: Vector2, motion: Vector2, height: float) -> Vector2:
	last_hits = 0
	if _space == null:
		return from + motion
	var position := from
	var remaining := motion
	for _slide in MAX_SLIDES + 1:
		if remaining.length() < EPSILON:
			return position
		var count := EyeRig.cast_step_count(remaining.length(), _shape.radius)
		var step := remaining / float(count)
		var normal := Vector2.ZERO
		var blocked := false
		for i in count:
			var swept := _sweep(position, step, height)
			position += step * swept.fraction
			if swept.fraction < 1.0:
				blocked = true
				normal = swept.normal
				remaining = step * (1.0 - swept.fraction) + step * float(count - i - 1)
				break
		if not blocked:
			return position
		last_hits += 1
		remaining = EyeRig.slide_motion(remaining, normal)
		if remaining.length() >= EPSILON:
			remaining += normal.normalized() * SKIN_M
	return position


## One cast of the sphere from `position` by `step`: the free fraction (1 when nothing is in the
## way) and the horizontal normal of the surface met.
func _sweep(position: Vector2, step: Vector2, height: float) -> Dictionary:
	var params := PhysicsShapeQueryParameters3D.new()
	params.shape = _shape
	params.collision_mask = WaterSurface.TERRAIN_LAYER
	params.exclude = _exclude
	params.transform = Transform3D(Basis.IDENTITY, Vector3(position.x, height, position.y))
	params.motion = Vector3(step.x, 0.0, step.y)
	var fractions := _space.cast_motion(params)
	if fractions.size() < 2 or fractions[0] >= 1.0:
		return {"fraction": 1.0, "normal": Vector2.ZERO}
	var safe: float = fractions[0]
	var unsafe: float = fractions[1]
	return {"fraction": safe, "normal": _normal_at(position, step, unsafe, height)}


## The horizontal normal of the surface the sphere meets `unsafe` of the way along `step`: from
## the rest info of the sphere put there, a little inflated. A hit with no horizontal part (a
## ceiling) or no answer returns the reverse of the step, which stops the move.
func _normal_at(position: Vector2, step: Vector2, unsafe: float, height: float) -> Vector2:
	var probe := PhysicsShapeQueryParameters3D.new()
	probe.shape = _shape
	probe.collision_mask = WaterSurface.TERRAIN_LAYER
	probe.exclude = _exclude
	probe.margin = NORMAL_PROBE_MARGIN
	var at := position + step * minf(unsafe, 1.0)
	probe.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, height, at.y))
	var rest := _space.get_rest_info(probe)
	if rest.is_empty():
		return -step.normalized()
	var normal3: Vector3 = rest.normal
	var flat := Vector2(normal3.x, normal3.z)
	var has_flat := flat.length_squared() >= 0.0001
	if has_flat:
		flat = flat.normalized()
		# Whichever way the engine orients it, it faces back toward where the sphere came from.
		if flat.dot(step) > 0.0:
			flat = -flat
	# From the contact point to the sphere's centre: the same as the face normal against a flat
	# wall, and the radial one around a wall's end or a door jamb, where the engine reports the
	# face normal of the triangle beside the edge (which would swallow a slide along the wall
	# past its end). The engine's own normal is kept when they agree: it is exact on a flat wall.
	var point: Vector3 = rest.point
	var radial := Vector2(at.x - point.x, at.y - point.z)
	if radial.length() > 0.001:
		radial = radial.normalized()
		if has_flat and radial.dot(flat) > RADIAL_AGREES:
			return flat
		return radial
	return flat if has_flat else -step.normalized()
