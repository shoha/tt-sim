class_name StructureGeometry
extends RefCounted

## A structure's geometry (Structure) built by the shared procgen module: its recipe document
## (StructureRecipes), the footprint as a closed plan guide, the document's ground, and the
## record's stored seed and params go into `evaluate_structure(doc, inputs, with_layout)`, and the
## surfaces come back in the map frame split by material role (StructureLook), the shape
## AuthoredStructures makes nodes from. Pure and safe on any thread: it reads the Structure and the
## ground it is given and nothing else, so the same record on the same ground gives the same bytes
## on a worker, in a test and on another peer (docs/systems/structures.md "Geometry").
##
## Parts of one structure (build_one):
##   {"id", "recipe", "style",
##    "meshes": [{"kind": surface kind, "role": StructureLook role, "arrays": mesh arrays,
##                "tags": per vertex tag ids into "tag_table"}, ...],
##    "tag_table": provenance paths (node id, then slot path), "collision": faces,
##    "top": highest walkable point (NONE when nothing was built), "openings": the boxes procgen
##    reports, "layout": the final ProcgenBuildingLayout or null (volumes, openings with slot
##    provenance, kept for the day a vision rule needs them), "triangles": int,
##    "problem": why nothing was built, or "", "warning": a soft budget note, or ""}
## Budgets (design.md "Triangle budgets"): over SOFT_TRIANGLES a structure builds and warns; over
## HARD_TRIANGLES it is refused (empty parts, `problem` says why).

## Triangles per structure: a warning above the soft limit, a refusal above the hard one.
const SOFT_TRIANGLES := 12000
const HARD_TRIANGLES := 25000
## The ground under a footprint is sampled this far apart (metres) along its outline and across its
## inside for the cache key; a footprint wider than KEY_MAX_SAMPLES of them coarsens the grid.
const KEY_STEP_M := 0.5
const KEY_MAX_SAMPLES := 2048
## Bumped when the mesh layout of the parts changes, so cached parts rebuild.
const FORMAT_VERSION := 1
## Marks a structure with no top (no recipe, or nothing built).
const NONE := -INF
## Scatter clearance: strips this wide (at most CLEAR_MAX_STRIPS per structure) cover the footprint;
## each strip is shortened at both ends because a Crossing clears past its anchors.
const CLEAR_STRIP_M := 0.75
const CLEAR_MAX_STRIPS := 12
const CLEAR_TRIM_M := 0.55
## How far past its footprint a structure reaches for scatter and edits, metres.
const REACH_M := 1.6

## True: masonry courses in the texture (a tenth of the triangles); false: modelled blocks. Applies
## to a recipe that declares a `textured` parameter the record does not set itself.
static var textured := true

## The ground a structure asks about is WallGeometry.Ground (the document's heights at a map point).


## A document that holds only the ground of `doc` (size, spacing and the height array, which is
## shared copy-on-write), safe to read on a worker while the real document is edited.
static func ground_snapshot(doc: MapDocument) -> MapDocument:
	var ground := MapDocument.new()
	ground.size_cells = doc.size_cells
	ground.cell_size_m = doc.cell_size_m
	ground.sample_spacing_m = doc.sample_spacing_m
	ground.heights = doc.heights
	return ground


## The inputs `structure` gives `recipe`: its footprint as the closed plan guide, its params
## (clamped to the recipe's interface) plus `textured` where the recipe has it, the document's
## ground, and the stored seed.
static func inputs_for(
	doc: MapDocument, structure: Structure, recipe: PlantGraphDocument
) -> ProcgenStructureInputs:
	var inputs := ProcgenStructureInputs.new()
	inputs.guide = ProcgenPlan.to_guide(structure.footprint)
	inputs.params = StructureRecipes.clamp_params(recipe, structure.params)
	if (
		textured
		and not structure.params.has("textured")
		and StructureRecipes.has_param(recipe, "textured")
		and MasonryTextures.available()
	):
		inputs.params["textured"] = 1.0
	var ground := WallGeometry.Ground.new()
	ground.doc = doc
	inputs.env = ground
	inputs.seed_value = structure.seed_value
	return inputs


## One structure's parts (see the header). Empty parts, with `problem` set, when the record is
## invalid, its recipe is unknown or fails, or the result is over the hard budget.
static func build_one(doc: MapDocument, structure: Structure) -> Dictionary:
	var parts := _empty(structure)
	var reason := MapStructureIO.structure_problem(structure, doc.extent_m())
	if reason != "":
		parts.problem = reason
		return parts
	var recipe := StructureRecipes.document(structure.recipe)
	if recipe == null:
		parts.problem = "recipe %s is unknown" % structure.recipe
		return parts
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(
		recipe, inputs_for(doc, structure, recipe), true
	)
	if plant == null or not evaluator.errors.is_empty():
		var why := String(evaluator.errors[0]) if not evaluator.errors.is_empty() else "no result"
		parts.problem = "recipe %s failed: %s" % [structure.recipe, why]
		return parts
	var geometry: PlantGeometry = plant["lods"][0]
	var triangles := geometry.triangle_count()
	parts.triangles = triangles
	if triangles > HARD_TRIANGLES:
		parts.problem = (
			"%d triangles is over the limit of %d for one structure" % [triangles, HARD_TRIANGLES]
		)
		return parts
	if triangles > SOFT_TRIANGLES:
		parts.warning = (
			"%d triangles is over the %d a structure should stay under"
			% [triangles, SOFT_TRIANGLES]
		)
	var roles := PackedStringArray()
	for path in geometry.tag_table:
		roles.append(StructureLook.role_of_path(recipe, path))
	var meshes: Array = []
	for surface in geometry.merged_by_kind():
		meshes.append_array(_split(surface, roles))
	var panes := _panes(geometry.openings)
	if not panes.is_empty():
		meshes.append(panes)
		parts.triangles = (
			triangles + (panes.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		)
	meshes.sort_custom(_by_role)
	parts.meshes = meshes
	parts.tag_table = PackedStringArray(geometry.tag_table)
	parts.collision = geometry.collision
	parts.top = geometry.top if triangles > 0 else NONE
	parts.openings = geometry.openings
	parts.layout = plant.get("layout")
	return parts


## Every structure of `doc`: {"structures": [parts, ...]} (AuthoredLoadPrep's part).
static func build(doc: MapDocument) -> Dictionary:
	var out: Array = []
	for structure in doc.structures:
		out.append(build_one(doc, structure))
	return {"structures": out}


## A key that changes when anything a structure's geometry depends on does: its recipe (the digest
## of its text), footprint, params, seed, style, the `textured` switch, the mesh format and the
## ground sampled along its outline and across its inside. AuthoredStructures rebuilds a structure
## only when its key moved, and keeps built parts by key.
static func key_of(doc: MapDocument, structure: Structure) -> int:
	return hash(
		[
			StructureRecipes.digest(structure.recipe),
			structure.recipe,
			structure.footprint,
			JSON.stringify(structure.params, "", true),
			structure.seed_value,
			structure.style,
			textured,
			FORMAT_VERSION,
			ground_samples(doc, structure.footprint),
		]
	)


## Keys of every structure of `doc` (id -> key).
static func keys_of(doc: MapDocument) -> Dictionary:
	var out := {}
	for structure in doc.structures:
		out[structure.id] = key_of(doc, structure)
	return out


## The ground under a plan: along every side every KEY_STEP_M, then across the inside on a grid of
## KEY_STEP_M (coarser for a very wide plan, KEY_MAX_SAMPLES at most).
static func ground_samples(doc: MapDocument, plan: PackedVector2Array) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var count := plan.size()
	if count < 3:
		return samples
	var box := Rect2(plan[0], Vector2.ZERO)
	for k in count:
		var a := plan[k]
		var b := plan[(k + 1) % count]
		box = box.expand(b)
		var steps := maxi(1, ceili(a.distance_to(b) / KEY_STEP_M))
		for s in steps:
			samples.append(WaterGeometry.ground_at(doc, a.lerp(b, float(s) / steps)))
	var step := maxf(KEY_STEP_M, sqrt(box.get_area() / KEY_MAX_SAMPLES))
	var y := box.position.y + step * 0.5
	while y < box.end.y:
		var x := box.position.x + step * 0.5
		while x < box.end.x:
			var at := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(at, plan):
				samples.append(WaterGeometry.ground_at(doc, at))
			x += step
		y += step
	return samples


## The area a structure's scatter clearance and an edit of it reach: its footprint grown by REACH_M.
static func clear_bounds(structure: Structure) -> Rect2:
	return structure.bounds().grow(REACH_M)


## Strips across every footprint as plank-like Crossings (a width, no deck), the shape ScatterGround
## and the native scatter clear plants by: nothing grows under a structure or just beside it. The
## strips run along the front edge, one every CLEAR_STRIP_M across the plan, cut where the
## polygon is (an L plan gets two strips on its long arm's rows). Pure.
static func clearance_crossings(doc: MapDocument) -> Array[Crossing]:
	var out: Array[Crossing] = []
	for structure in doc.structures:
		out.append_array(footprint_strips(structure.footprint))
	return out


## clearance_crossings() for one footprint.
static func footprint_strips(plan: PackedVector2Array) -> Array[Crossing]:
	var out: Array[Crossing] = []
	var count := plan.size()
	if count < 3:
		return out
	var along := (plan[1] - plan[0]).normalized()
	if along == Vector2.ZERO:
		return out
	var across := Vector2(-along.y, along.x)
	var low := INF
	var high := -INF
	for p in plan:
		low = minf(low, p.dot(across))
		high = maxf(high, p.dot(across))
	var rows := clampi(ceili((high - low) / CLEAR_STRIP_M), 1, CLEAR_MAX_STRIPS)
	var width := (high - low) / rows
	for row in rows:
		var t := low + (row + 0.5) * width
		var hits := PackedFloat32Array()
		for k in count:
			var a := plan[k]
			var b := plan[(k + 1) % count]
			var da := a.dot(across) - t
			var db := b.dot(across) - t
			if (da <= 0.0) != (db <= 0.0):
				hits.append(lerpf(a.dot(along), b.dot(along), da / (da - db)))
		hits.sort()
		for pair in hits.size() / 2:
			var shrink := minf(CLEAR_TRIM_M, (hits[pair * 2 + 1] - hits[pair * 2]) * 0.45)
			var s0 := hits[pair * 2] + shrink
			var s1 := maxf(hits[pair * 2 + 1] - shrink, s0 + 0.01)
			out.append(
				Crossing.make(
					0,
					Crossing.Kind.PLANK,
					along * s0 + across * t,
					along * s1 + across * t,
					Vector3.ZERO,
					width
				)
			)
	return out


## An MD5 over everything a host reads from `parts`: each mesh's kind, role, vertices, normals,
## UVs, colours and indices, the collision faces and the top. The pins in
## tests/fixtures/structure_digests.txt are made with it.
static func digest_of(parts: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_MD5)
	for mesh: Dictionary in parts.get("meshes", []):
		ctx.update(String(mesh.kind).to_utf8_buffer())
		ctx.update(String(mesh.role).to_utf8_buffer())
		var arrays: Array = mesh.arrays
		ctx.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	ctx.update((parts.get("collision", PackedVector3Array()) as PackedVector3Array).to_byte_array())
	ctx.update(str(parts.get("top", NONE)).to_utf8_buffer())
	return ctx.finish().hex_encode()


## The triangles of `parts` in all its meshes.
static func triangle_count(parts: Dictionary) -> int:
	var total := 0
	for mesh: Dictionary in parts.get("meshes", []):
		total += (mesh.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


static func _empty(structure: Structure) -> Dictionary:
	return {
		"id": structure.id,
		"recipe": structure.recipe,
		"style": structure.style,
		"meshes": [],
		"tag_table": PackedStringArray(),
		"collision": PackedVector3Array(),
		"top": NONE,
		"openings": [],
		"layout": null,
		"triangles": 0,
		"problem": "",
		"warning": "",
	}


static func _by_role(a: Dictionary, b: Dictionary) -> bool:
	var ra := StructureLook.ROLES.find(a.role)
	var rb := StructureLook.ROLES.find(b.role)
	if ra != rb:
		return ra < rb
	return String(a.kind) < String(b.kind)


## One mesh of panes, a quad in the middle of every opening box (its first two axes span the pane,
## the third runs through the wall): a window's dark glass, a door's leaf. Without them the
## recipes' hollow walls show the ground through every window. {} with no openings.
static func _panes(openings: Array) -> Dictionary:
	if openings.is_empty():
		return {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for box: Dictionary in openings:
		var axes: Array = box.axes
		var across: Vector3 = axes[0]
		var up: Vector3 = axes[1]
		var through: Vector3 = axes[2]
		var half: Vector3 = box.half
		var centre: Vector3 = box.centre
		var is_window := String(box.get("kind", "")) == "window"
		var color := StructureLook.WINDOW_COLOR if is_window else StructureLook.DOOR_COLOR
		var base := vertices.size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			vertices.append(centre + across * half.x * corner.x + up * half.y * corner.y)
			normals.append(through)
			uvs.append((corner + Vector2.ONE) * 0.5)
			colors.append(color)
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var tags := PackedInt32Array()
	tags.resize(vertices.size())
	tags.fill(-1)
	return {
		"kind": StructureLook.GLASS_KIND,
		"role": StructureLook.OPENING,
		"arrays": _arrays(StructureLook.GLASS_KIND, vertices, normals, uvs, colors, indices),
		"tags": tags,
	}


## `surface` cut into one mesh per material role: every triangle goes to the role of the node that
## made its first vertex (`roles` maps a tag id to a role). Vertices keep their relative order, so
## the quads the tangents rely on stay four in a row.
static func _split(surface: PlantSurface, roles: PackedStringArray) -> Array:
	var tags := surface.tags
	var indices := surface.indices
	var triangles := indices.size() / 3
	var role_of := PackedByteArray()
	role_of.resize(triangles)
	var present := PackedByteArray()
	present.resize(StructureLook.ROLES.size())
	for t in triangles:
		var first := indices[t * 3]
		var tag := tags[first] if first < tags.size() else -1
		var role := roles[tag] if tag >= 0 and tag < roles.size() else StructureLook.WALL
		var at := StructureLook.ROLES.find(StructureLook.material_role(surface.kind, role))
		role_of[t] = at
		present[at] = 1
	var out: Array = []
	for at in StructureLook.ROLES.size():
		if present[at] == 0:
			continue
		var picked := PackedInt32Array()
		for t in triangles:
			if role_of[t] == at:
				picked.append(indices[t * 3])
				picked.append(indices[t * 3 + 1])
				picked.append(indices[t * 3 + 2])
		out.append(_mesh_of(surface, StructureLook.ROLES[at], picked))
	return out


static func _mesh_of(surface: PlantSurface, role: String, picked: PackedInt32Array) -> Dictionary:
	var used := PackedByteArray()
	used.resize(surface.vertices.size())
	for v in picked:
		used[v] = 1
	var remap := PackedInt32Array()
	remap.resize(surface.vertices.size())
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colors := PackedColorArray()
	var tags := PackedInt32Array()
	for v in surface.vertices.size():
		if used[v] == 0:
			continue
		remap[v] = vertices.size()
		vertices.append(surface.vertices[v])
		normals.append(surface.normals[v])
		uvs.append(surface.uvs[v])
		colors.append(surface.colors[v])
		tags.append(surface.tags[v] if v < surface.tags.size() else -1)
	var indices := PackedInt32Array()
	indices.resize(picked.size())
	for k in picked.size():
		indices[k] = remap[picked[k]]
	return {
		"kind": surface.kind,
		"role": role,
		"arrays": _arrays(surface.kind, vertices, normals, uvs, colors, indices),
		"tags": tags,
	}


static func _arrays(
	kind: String,
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	colors: PackedColorArray,
	indices: PackedInt32Array
) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	if kind == "wood" or kind == "masonry":
		arrays[Mesh.ARRAY_TANGENT] = ProcgenCrossing.quad_tangents(vertices, normals, uvs)
	else:
		# Triplanar stone (no UVs): +X with a positive binormal sign, as WallGeometry gives it.
		var tangents := PackedFloat32Array()
		tangents.resize(vertices.size() * 4)
		for k in vertices.size():
			tangents[k * 4] = 1.0
			tangents[k * 4 + 3] = 1.0
		arrays[Mesh.ARRAY_TANGENT] = tangents
	return arrays
