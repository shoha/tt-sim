class_name WallGeometry
extends RefCounted

## A wall's or fence's geometry (Wall) built by the shared procgen module's recipes
## (procgen/recipes/stone_wall.json and wood_fence.json, docs/systems/walls.md). Pure and safe on
## any thread: it makes the guide, the ground and the inputs from the wall and the document,
## evaluates the recipe, and returns mesh arrays in the map frame, the shape AuthoredWalls makes
## nodes from. The module builds a wall in the map's own XZ plan (the guide's points are the
## wall's points), so nothing is re-framed.

const STONE_RECIPE := "res://procgen/recipes/stone_wall.json"
const FENCE_RECIPE := "res://procgen/recipes/wood_fence.json"
const BUILDING_RECIPE := "res://procgen/recipes/building.json"
const STREET_ROW_RECIPE := "res://procgen/recipes/street_row.json"
## The ground under a wall is sampled this far apart (metres) along its line for its cache key.
const KEY_STEP_M := 0.5
## The width plants clear across a wall's side (its thickness and a margin), metres.
const CLEAR_WIDTH_M := 0.7
## How far past its setback a row's buildings reach (the deepest lot, with its roof), metres.
const ROW_REACH_M := 9.0
## Marks a wall with no top (no recipe, or nothing built).
const NONE := -INF

## True: a wall carries its courses in the masonry texture (MasonryTextures), the coping modelled,
## a fraction of the triangles; false: modelled blocks. A static for comparing the two.
static var textured := false


## The ground a wall asks about: the document's heights at a map point.
class Ground:
	extends ProcgenEnvironment
	var doc: MapDocument = null

	func ground_at(u: float, v: float) -> float:
		return WaterGeometry.ground_at(doc, Vector2(u, v))


## The recipe path for `kind`.
static func recipe_path(kind: Wall.Kind) -> String:
	match kind:
		Wall.Kind.FENCE:
			return FENCE_RECIPE
		Wall.Kind.BUILDING:
			return BUILDING_RECIPE
		Wall.Kind.ROW:
			return STREET_ROW_RECIPE
	return STONE_RECIPE


## The recipe document at `path`, null when the file is missing or not a graph.
static func load_recipe(path: String) -> PlantGraphDocument:
	return ProcgenCrossing.load_recipe(path)


## The inputs a wall gives its recipe: its line as a polyline guide, its height as the `height`
## parameter, the document's ground, and a seed from the map seed, the wall's id and kind.
static func inputs_for(doc: MapDocument, wall: Wall) -> ProcgenStructureInputs:
	var inputs := ProcgenStructureInputs.new()
	var line := PackedVector3Array()
	for p in wall.points:
		line.append(Vector3(p.x, 0.0, p.y))
	inputs.guide = ProcgenGuide.polyline(line, wall.closed)
	inputs.params = {"height": wall.height_m}
	if wall.is_row():
		# A row's `height_m` is its setback; its side and seed vary the buildings.
		inputs.params = {
			"setback": wall.height_m, "side": float(wall.side), "preset": float(wall.preset)
		}
	if textured and wall.kind != Wall.Kind.FENCE and MasonryTextures.available():
		inputs.params["textured"] = 1.0
	var ground := Ground.new()
	ground.doc = doc
	inputs.env = ground
	inputs.seed_value = hash([doc.map_seed, wall.id, 100 + wall.kind, wall.seed_value])
	return inputs


## The lots of row `wall` (ProcgenRow.plan: each {"points" (four corners, the first side the
## front), "height", "pitch", "ridge", "side", "index"}), made exactly as the recipe makes them
## (the same node seed and parameters). [] when the recipe is missing. Cheap and pure: the tool
## draws them as the preview, and scatter clears under them.
static func row_lots(doc: MapDocument, wall: Wall) -> Array[Dictionary]:
	var recipe := load_recipe(STREET_ROW_RECIPE)
	if recipe == null or not wall.is_row():
		return []
	var inputs := inputs_for(doc, wall)
	var node := RowNode.new()
	var p := node.coerce_params(
		{"setback": wall.height_m, "side": wall.side, "preset": wall.preset}
	)
	var node_seed := node.node_seed(
		p, {"seed": inputs.seed_value, "node_id": recipe.resolve_node("street_row")}
	)
	return ProcgenRow.plan(inputs.guide, PlantRng.new(node_seed), p)


## One wall's parts: {"id", "kind", "style", "stone": mesh arrays or [], "wood": mesh arrays or
## [], "collision": PackedVector3Array, "top": float (NONE when empty)}. Empty parts when the
## recipe is missing or fails.
static func build_one(doc: MapDocument, wall: Wall) -> Dictionary:
	var parts := {
		"id": wall.id,
		"kind": wall.kind,
		"style": wall.style,
		"stone": [],
		"masonry": [],
		"wood": [],
		"collision": PackedVector3Array(),
		"top": NONE,
	}
	var recipe := load_recipe(recipe_path(wall.kind))
	if recipe == null or wall.points.size() < Wall.MIN_POINTS:
		return parts
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(recipe, inputs_for(doc, wall))
	if plant == null or not evaluator.errors.is_empty():
		return parts
	var geometry: PlantGeometry = plant["lods"][0]
	for surface in geometry.merged_by_kind():
		parts[surface.kind] = _arrays(surface)
	parts.collision = geometry.collision
	parts.top = geometry.top if geometry.triangle_count() > 0 else NONE
	return parts


## Every wall of `doc`: {"walls": [parts, ...]}.
static func build(doc: MapDocument) -> Dictionary:
	var out: Array = []
	for wall in doc.walls:
		out.append(build_one(doc, wall))
	return {"walls": out}


## A key that changes when anything a wall's geometry depends on does: its fields, the map seed
## and the ground sampled along its line. AuthoredWalls rebuilds a wall only when its key moved.
static func key_of(doc: MapDocument, wall: Wall) -> int:
	var samples := PackedFloat32Array()
	var count := wall.points.size()
	var sides := count if wall.closed else count - 1
	for k in maxi(sides, 0):
		var a := wall.points[k]
		var b := wall.points[(k + 1) % count]
		var steps := maxi(1, ceili(a.distance_to(b) / KEY_STEP_M))
		for s in steps + 1:
			samples.append(WaterGeometry.ground_at(doc, a.lerp(b, float(s) / steps)))
	return hash(
		[
			doc.map_seed,
			wall.id,
			wall.kind,
			wall.points,
			wall.closed,
			wall.height_m,
			wall.style,
			wall.seed_value,
			wall.side,
			wall.preset,
			textured,
			samples,
		]
	)


## Keys of every wall of `doc` (id -> key).
static func keys_of(doc: MapDocument) -> Dictionary:
	var out := {}
	for wall in doc.walls:
		out[wall.id] = key_of(doc, wall)
	return out


## The footprint of `wall` in map XZ, grown by its thickness: the area a scatter pass clears and
## an edit near it reaches.
static func clear_bounds(wall: Wall) -> Rect2:
	if wall.is_row():
		# The buildings stand up to a setback and a depth off the street's line.
		return wall.bounds().grow(wall.height_m + ROW_REACH_M)
	return wall.bounds().grow(1.0)


## Each side of every wall as a plank-like Crossing (anchors, a width of the wall's thickness
## and a little), the shape ScatterGround and the native scatter clear plants by: nothing grows
## on a wall's footprint or the strip beside it. Pure; the levels are unused.
static func clearance_crossings(doc: MapDocument) -> Array[Crossing]:
	var out: Array[Crossing] = []
	for wall in doc.walls:
		if wall.is_row():
			# Under each building, not along the street.
			for lot in row_lots(doc, wall):
				# The yard's plot when it has one, else the building.
				var q: PackedVector3Array = (
					lot.plot if not (lot.plot as PackedVector3Array).is_empty() else lot.points
				)
				var front := Vector2(q[0].x, q[0].z)
				var front_end := Vector2(q[1].x, q[1].z)
				out.append(
					Crossing.make(
						0,
						Crossing.Kind.PLANK,
						(front + front_end) * 0.5,
						(Vector2(q[2].x, q[2].z) + Vector2(q[3].x, q[3].z)) * 0.5,
						Vector3.ZERO,
						front.distance_to(front_end)
					)
				)
			continue
		var count := wall.points.size()
		var sides := count if wall.closed else count - 1
		for k in maxi(sides, 0):
			out.append(
				Crossing.make(
					0,
					Crossing.Kind.PLANK,
					wall.points[k],
					wall.points[(k + 1) % count],
					Vector3.ZERO,
					CLEAR_WIDTH_M
				)
			)
		if wall.is_building() and count == Wall.BUILDING_POINTS:
			# The whole footprint clears, not only its sides: a strip across it from the middle of
			# the first side to the middle of the third, as wide as the first side is long.
			out.append(
				Crossing.make(
					0,
					Crossing.Kind.PLANK,
					(wall.points[0] + wall.points[1]) * 0.5,
					(wall.points[2] + wall.points[3]) * 0.5,
					Vector3.ZERO,
					wall.points[0].distance_to(wall.points[1])
				)
			)
	return out


static func _arrays(surface: PlantSurface) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface.vertices
	arrays[Mesh.ARRAY_NORMAL] = surface.normals
	arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
	arrays[Mesh.ARRAY_COLOR] = surface.colors
	arrays[Mesh.ARRAY_INDEX] = surface.indices
	if surface.kind == "wood" or surface.kind == "masonry":
		arrays[Mesh.ARRAY_TANGENT] = ProcgenCrossing.quad_tangents(
			surface.vertices, surface.normals, surface.uvs
		)
	else:
		# Triplanar masonry (no UVs; a non-zero UV is a moss key, already in map XZ): +X with a
		# positive binormal sign.
		var tangents := PackedFloat32Array()
		tangents.resize(surface.vertices.size() * 4)
		for k in surface.vertices.size():
			tangents[k * 4] = 1.0
			tangents[k * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TANGENT] = tangents
	return arrays
