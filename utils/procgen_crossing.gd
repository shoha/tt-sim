class_name ProcgenCrossing
extends RefCounted

## A crossing built by the shared procgen module instead of CrossingGeometry's own code: the
## adapter between a Crossing and a structure recipe (procgen/, docs/systems/procgen.md). Pure
## and safe on any thread, like CrossingGeometry: it makes the guide, the environment and the
## inputs from the crossing and the document's ground, evaluates the recipe, and returns the
## module's local-frame geometry in the map frame.
##
## Frame. The module builds a structure in its own frame: origin at the start anchor, +X along
## the span, +Y up (map Y, absolute), +Z to the left of travel. That is CrossingGeometry's
## (u, y, v) order, so a local point (x, y, z) is map `start + d * x + left * z` at height y.

## The plank bridge recipe, until a library carries structures.
const PLANK_RECIPE := "res://procgen/recipes/plank_bridge.json"
const STONES_RECIPE := "res://procgen/recipes/stepping_stones.json"
const ARCH_RECIPE := "res://procgen/recipes/stone_arch.json"
const FORD_RECIPE := "res://procgen/recipes/ford.json"
## The recipe of each crossing kind the module builds (a kind absent here is built by
## CrossingGeometry's own code).
const RECIPES := {
	Crossing.Kind.PLANK: PLANK_RECIPE,
	Crossing.Kind.STONES: STONES_RECIPE,
	Crossing.Kind.ARCH: ARCH_RECIPE,
	Crossing.Kind.FORD: FORD_RECIPE,
}

## The switch: plank bridges are built by the module (CrossingGeometry.build_one) while this is
## true. Off by default. It changes geometry only (collision, top and the walking surface are
## the same), but every peer builds its own copy, so a rollout makes it a map or library fact,
## not a per-machine setting.
static var enabled := false


## The ground a structure asks about, in the crossing's local (u, v).
class Ground:
	extends ProcgenEnvironment
	var doc: MapDocument = null
	var crossing: Crossing = null
	## WaterGeometry.river_courses of the area round the crossing, made once.
	var courses: Dictionary = {}

	func ground_at(u: float, v: float) -> float:
		return WaterGeometry.ground_at(doc, ProcgenCrossing.map_xz(crossing, u, v))

	func water_at(u: float, v: float) -> float:
		var at := ProcgenCrossing.map_xz(crossing, u, v)
		return WaterGeometry.level_at(doc, at, -1, courses)

	func flow_at(u: float, v: float) -> Vector2:
		var flow := CrossingFord.flow_at(doc, ProcgenCrossing.map_xz(crossing, u, v), courses)
		var d := crossing.direction()
		return Vector2(flow.dot(d), flow.dot(Vector2(-d.y, d.x)))


## Map XZ of the local point (u along, v across).
static func map_xz(crossing: Crossing, u: float, v: float) -> Vector2:
	var d := crossing.direction()
	return crossing.start + d * u + Vector2(-d.y, d.x) * v


## A local-frame point in the map frame.
static func to_map(crossing: Crossing, p: Vector3) -> Vector3:
	var at := map_xz(crossing, p.x, p.z)
	return Vector3(at.x, p.y, at.y)


## A local-frame direction in the map frame.
static func dir_to_map(crossing: Crossing, n: Vector3) -> Vector3:
	var d := crossing.direction()
	return Vector3(d.x * n.x - d.y * n.z, n.y, d.y * n.x + d.x * n.z)


## The recipe document for `kind`'s structure, null when the file is missing or not a graph.
static func load_recipe(path: String = PLANK_RECIPE) -> PlantGraphDocument:
	if not FileAccess.file_exists(path):
		return null
	return PlantGraphDocument.from_json(
		FileAccess.get_file_as_string(path), ProcgenStructureRegistry.new()
	)


## The inputs a crossing gives its recipe: the span guide from its length and three levels, its
## width as the `width` parameter, the document's ground, and a seed from the map seed, the
## crossing's id and kind (as CrossingGeometry.rng_for does).
static func inputs_for(doc: MapDocument, crossing: Crossing) -> ProcgenStructureInputs:
	var inputs := ProcgenStructureInputs.new()
	inputs.guide = ProcgenGuide.span(crossing.span_m(), crossing.levels)
	inputs.params = {"width": crossing.width_m, "stride": doc.cell_size_m}
	var ground := Ground.new()
	ground.doc = doc
	ground.crossing = crossing
	var near := Rect2(crossing.start, Vector2.ZERO).expand(crossing.end)
	ground.courses = WaterGeometry.river_courses(doc, near.grow(crossing.width_m * 0.5 + 2.0))
	inputs.env = ground
	inputs.seed_value = hash([doc.map_seed, crossing.id, crossing.kind])
	return inputs


## {"surfaces": {role: mesh arrays in the map frame}, "collision": PackedVector3Array,
## "top": float, "errors": Array}. Empty surfaces and a `top` of -INF when the recipe is missing
## or the crossing has no span.
static func build(doc: MapDocument, crossing: Crossing, recipe: PlantGraphDocument) -> Dictionary:
	var out := {"surfaces": {}, "collision": PackedVector3Array(), "top": -INF, "errors": []}
	if recipe == null or crossing.span_m() <= 0.0:
		return out
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(recipe, inputs_for(doc, crossing))
	out["errors"] = evaluator.errors
	if plant == null:
		return out
	var geometry: PlantGeometry = plant["lods"][0]
	for surface in geometry.merged_by_kind():
		out["surfaces"][surface.kind] = _arrays_in_map(crossing, surface)
	var faces := PackedVector3Array()
	faces.resize(geometry.collision.size())
	for k in geometry.collision.size():
		faces[k] = to_map(crossing, geometry.collision[k])
	out["collision"] = faces
	out["top"] = geometry.top
	return out


## A crossing's parts in CrossingGeometry's shape ({"wood" | "stone" | "paving" | "gravel": mesh
## arrays, "collision", "top"}), or {} when the kind has no recipe, the recipe is missing or it
## fails, so the caller falls back to its own code.
static func parts_of(doc: MapDocument, crossing: Crossing) -> Dictionary:
	if not RECIPES.has(crossing.kind):
		return {}
	var built := build(doc, crossing, load_recipe(RECIPES[crossing.kind]))
	if built.surfaces.is_empty() or not built.errors.is_empty():
		return {}
	var parts := {"collision": built.collision, "top": built.top}
	parts.merge(built.surfaces)
	return parts


## Tangents for quads of four vertices in order (a box face), pointing along +U with the
## binormal sign in w, as CrossingGeometry's _Mesh.quad writes them for the normal-mapped wood.
static func quad_tangents(
	vertices: PackedVector3Array, normals: PackedVector3Array, uvs: PackedVector2Array
) -> PackedFloat32Array:
	var tangents := PackedFloat32Array()
	tangents.resize(vertices.size() * 4)
	for q in vertices.size() / 4:
		var base := q * 4
		var normal := normals[base]
		var e1 := vertices[base + 1] - vertices[base]
		var e2 := vertices[base + 3] - vertices[base]
		var du1 := uvs[base + 1] - uvs[base]
		var du2 := uvs[base + 3] - uvs[base]
		var det := du1.x * du2.y - du2.x * du1.y
		var tangent := e1
		var handed := 1.0
		if absf(det) > 1e-9:
			tangent = (e1 * du2.y - e2 * du1.y) / det
			var bitangent := (e2 * du1.x - e1 * du2.x) / det
			handed = 1.0 if normal.cross(tangent).dot(bitangent) >= 0.0 else -1.0
		tangent = (tangent - normal * normal.dot(tangent)).normalized()
		for k in 4:
			var at := (base + k) * 4
			tangents[at] = tangent.x
			tangents[at + 1] = tangent.y
			tangents[at + 2] = tangent.z
			tangents[at + 3] = handed
	return tangents


static func _arrays_in_map(crossing: Crossing, surface: PlantSurface) -> Array:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	vertices.resize(surface.vertices.size())
	normals.resize(surface.normals.size())
	for k in surface.vertices.size():
		vertices[k] = to_map(crossing, surface.vertices[k])
		normals[k] = dir_to_map(crossing, surface.normals[k])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var uvs := surface.uvs
	if surface.kind == "stone":
		# A non-zero UV on masonry is a moss key in the structure's local (u, v): the moss field
		# reads it in the map frame (CrossingArch's coping stones and caps), so map it there.
		uvs = surface.uvs.duplicate()
		for k in uvs.size():
			if uvs[k] != Vector2.ZERO:
				uvs[k] = map_xz(crossing, uvs[k].x, uvs[k].y)
	if surface.kind == "wood" or surface.kind == "paving":
		arrays[Mesh.ARRAY_TANGENT] = quad_tangents(vertices, normals, uvs)
	else:
		# Triplanar masonry and gravel (no UVs): +X with a positive binormal sign, as
		# CrossingGeometry's _Mesh.triangle writes.
		var tangents := PackedFloat32Array()
		tangents.resize(vertices.size() * 4)
		# The ford's gravel runs its tangent along the span (CrossingFord._bar).
		var along := (
			dir_to_map(crossing, Vector3.RIGHT) if surface.kind == "gravel" else Vector3.RIGHT
		)
		for k in vertices.size():
			tangents[k * 4] = along.x
			tangents[k * 4 + 1] = along.y
			tangents[k * 4 + 2] = along.z
			tangents[k * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TANGENT] = tangents
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = surface.colors
	arrays[Mesh.ARRAY_INDEX] = surface.indices
	return arrays
