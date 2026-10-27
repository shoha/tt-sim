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
## The ground under a wall is sampled this far apart (metres) along its line for its cache key.
const KEY_STEP_M := 0.5
## Marks a wall with no top (no recipe, or nothing built).
const NONE := -INF


## The ground a wall asks about: the document's heights at a map point.
class Ground:
	extends ProcgenEnvironment
	var doc: MapDocument = null

	func ground_at(u: float, v: float) -> float:
		return WaterGeometry.ground_at(doc, Vector2(u, v))


## The recipe path for `kind`.
static func recipe_path(kind: Wall.Kind) -> String:
	return FENCE_RECIPE if kind == Wall.Kind.FENCE else STONE_RECIPE


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
	var ground := Ground.new()
	ground.doc = doc
	inputs.env = ground
	inputs.seed_value = hash([doc.map_seed, wall.id, 100 + wall.kind])
	return inputs


## One wall's parts: {"id", "kind", "style", "stone": mesh arrays or [], "wood": mesh arrays or
## [], "collision": PackedVector3Array, "top": float (NONE when empty)}. Empty parts when the
## recipe is missing or fails.
static func build_one(doc: MapDocument, wall: Wall) -> Dictionary:
	var parts := {
		"id": wall.id,
		"kind": wall.kind,
		"style": wall.style,
		"stone": [],
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
	return wall.bounds().grow(1.0)


static func _arrays(surface: PlantSurface) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = surface.vertices
	arrays[Mesh.ARRAY_NORMAL] = surface.normals
	arrays[Mesh.ARRAY_TEX_UV] = surface.uvs
	arrays[Mesh.ARRAY_COLOR] = surface.colors
	arrays[Mesh.ARRAY_INDEX] = surface.indices
	if surface.kind == "wood":
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
