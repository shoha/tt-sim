extends RefCounted

## Shared ground-building helpers for the water tests (test_water_carve.gd,
## test_water_falls.gd, test_water_tool.gd; not a test file itself: GUT only collects
## test_*.gd). Preload it as a const. The shapes are built with the project's own tools (the
## tier profile through HeightStroke) or as plain functions of the map XZ, and the carve is
## applied as the editor applies it (min with the ground).


## Heights set by `shape_of` (Callable(Vector2 map XZ) -> float) at every sample of `doc`.
static func shape(doc: MapDocument, shape_of: Callable) -> void:
	var heights := PackedFloat32Array()
	heights.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			heights[doc.sample_index(x, z)] = shape_of.call(doc.sample_to_world(Vector2(x, z)))
	doc.heights = heights


## A Tier stroke to `target` along the capsule `from`-`to` of `radius`, run to rest: the
## real tier profile (HeightBrush.tier_goal through HeightStroke), face, rounded lip and all.
static func tier(
	doc: MapDocument, from: Vector2, to: Vector2, radius: float, target: float
) -> void:
	var stroke := HeightStroke.begin(doc, HeightBrush.TIER, target)
	for _frame in 4:
		stroke.dab(from, to, radius, 0.05)
	stroke.complete()


## A straight tier one tier high whose top covers z < 0 (the face stands around
## z = -1.4..0.5, running along X).
static func tier_band(doc: MapDocument) -> void:
	tier(doc, Vector2(-30, -10), Vector2(30, -10), 10.0, doc.tier_height_m)


## A 35 degree ramp (slope 0.7) losing 7 m over 10 m along `along` (unit; +X by default):
## flat at 7 m up to 5 m before the origin, flat at 0 from 5 m past it.
static func ramp(doc: MapDocument, along: Vector2 = Vector2.RIGHT) -> void:
	shape(doc, func(p: Vector2) -> float: return clampf(7.0 - 0.7 * (p.dot(along) + 5.0), 0.0, 7.0))


## Applies WaterCarve goals to `doc` (min with the ground), as the editor does.
static func carve(doc: MapDocument, goals: Dictionary) -> void:
	var rect: Rect2i = goals.rect
	var values: PackedFloat32Array = goals.goals
	var heights := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal := values[j * rect.size.x + i]
			var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
			if not is_inf(goal):
				heights[at] = minf(heights[at], goal)
	doc.heights = heights
