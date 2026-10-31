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
##   {"id", "recipe", "style", "palette" (the roof tile colour's name, StructurePaint),
##    "stone_tone" (the style's masonry hint, "grey", "warm" or ""; StructureMaterials),
##    "meshes": [{"kind": surface kind, "role": StructureLook role, "arrays": mesh arrays,
##                "tags": per vertex tag ids into "tag_table"}, ...],
##    "mill": {} or, for a windmill, StructureMill.split's moving parts without "rest" ("wheel" and
##    "cap" meshes, "hub", "axis", "centre", "curb_top"); they are NOT in "meshes" but are in
##    digest_of and triangle_count (all_meshes),
##    "tag_table": provenance paths (node id, then slot path), "collision": faces,
##    "walkable": the extra faces of decks, stairs, platforms and piles (StructureWalkable; not in
##    digest_of),
##    "top": highest walkable point (NONE when nothing was built), "openings": the boxes procgen
##    reports, "layout": the final ProcgenBuildingLayout or null (volumes, openings with slot
##    provenance, kept for the day a vision rule needs them), "triangles": int,
##    "placed_kinds": the ornament kinds the evaluated building holds pieces of
##    (ProcgenOrnaments.placed_kinds; a requested kind missing found no room; not in digest_of),
##    "anchors": ProcgenOrnaments.anchors, the ivy blankets and flower boxes where a host with decor
##    plants (StructureDecor) places them; "decor": true when the build was asked for `soft:
##    "anchors"` (the blobs are then NOT in "meshes"); neither is in digest_of. A build made with
##    decor false draws procgen's flat blobs, the fallback of a library without decor assets,
##    "dressing": StructureDressing.build's yard (soft ground patch, path, plants; not in digest_of
##    or the building's triangle budget), "problem": why nothing was built, or "", "warning": a soft
##    budget note, or ""}
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
const FORMAT_VERSION := 5
## Marks a structure with no top (no recipe, or nothing built).
const NONE := -INF
## digest_of rounds vertices and collision to this many metres (0.1 mm), as procgen's digests do.
const DIGEST_SNAP_M := 0.0001
## Scatter clearance: strips this wide (at most CLEAR_MAX_STRIPS per structure) cover the footprint;
## each strip is shortened at both ends because a Crossing clears past its anchors.
const CLEAR_STRIP_M := 0.75
const CLEAR_MAX_STRIPS := 12
const CLEAR_TRIM_M := 0.55
## How far past its footprint a structure reaches for scatter and edits, metres.
const REACH_M := 1.6
## The placeholder plot (a recipe this game lacks): how high it stands above the ground and how
## deep it sinks, metres, and its surface kind (modelled stone in the trim tone).
const PLOT_HEIGHT_M := 0.15
const PLOT_SINK_M := 0.1
const PLOT_KIND := "stone"

## True: masonry courses in the texture (a tenth of the triangles); false: modelled blocks. Applies
## to a recipe that declares a `textured` parameter the record does not set itself.
static var textured := true

## The ground a structure asks about is WallGeometry.Ground (the document's heights at a map point).


## A document that holds only the ground of `doc` (size, spacing and the height array, which is
## shared copy-on-write), its water and its structures' footprints, safe to read on a worker while
## the real document is edited.
static func ground_snapshot(doc: MapDocument) -> MapDocument:
	var ground := MapDocument.new()
	ground.size_cells = doc.size_cells
	ground.cell_size_m = doc.cell_size_m
	ground.sample_spacing_m = doc.sample_spacing_m
	ground.heights = doc.heights
	# What a yard keeps clear of (StructureDressing): water, and the other structures' footprints.
	# Private copies, so the worker never reads what the main thread edits.
	ground.pond_mask = doc.pond_mask
	for body in doc.water_bodies:
		ground.water_bodies.append(body.copy())
	for structure in doc.structures:
		ground.structures.append(structure.copy())
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
## With `decor` the ornaments' soft pieces (ivy blobs, flower-box foliage) are left out and the host
## places library plants on the anchors instead (StructureDecor); false draws the blobs.
## `info` ({"rows", "cost", "sig"}, AuthoredStructures' decor_info) lets the build also place the
## decor plants (`decor_plan`, StructureDecor.plan: placement, triangle cap and grouping are pure
## and
## the biggest part of the host's per-building work), so the main thread only makes meshes. It is
## not part of digest_of; the plan carries the info's `sig` and is made again when that moved.
static func build_one(
	doc: MapDocument, structure: Structure, decor: bool = false, info: Dictionary = {}
) -> Dictionary:
	var parts := _empty(structure)
	var reason := MapStructureIO.structure_problem(structure, doc.extent_m())
	if reason != "":
		parts.problem = reason
		return parts
	var recipe := StructureRecipes.document(structure.recipe)
	if recipe == null:
		parts.problem = "recipe %s is unknown" % structure.recipe
		return _with_plot(parts, doc, structure)
	# The ornaments the player added are nodes beside the walls of this build's own copy of the
	# recipe (documents are never shared), so the roles below find them too.
	StructureOrnaments.apply(recipe, structure.params, structure.seed_value)
	if decor:
		StructureOrnaments.soften(recipe)
	parts.decor = decor
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(
		recipe, inputs_for(doc, structure, recipe), true
	)
	if plant == null or not evaluator.errors.is_empty():
		var why := String(evaluator.errors[0]) if not evaluator.errors.is_empty() else "no result"
		parts.problem = "recipe %s failed: %s" % [structure.recipe, why]
		return _with_plot(parts, doc, structure)
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
		meshes.append_array(split_surface(surface, roles))
	meshes.sort_custom(_by_role)
	# The building's own roof tile colour and wall lean, from its seed and id (the same on every peer).
	# A building style's palette hints, written on the recipe's Output, replace the draw's roof colour
	# and give the walls their own tone.
	var hints := StructureLook.palette_hints(recipe)
	var palette := StructurePaint.palette_of(structure.seed_value, structure.id, hints)
	parts.palette = palette.name
	parts.stone_tone = String(hints.get("stone_tone", ""))
	StructurePaint.paint(meshes, PackedInt32Array(), [palette])
	parts.meshes = meshes
	parts.tag_table = PackedStringArray(geometry.tag_table)
	# Banner, pennant and awning cloth gets its wind weights in the second UV set (not in digest_of).
	StructureCloth.attach(meshes, parts.tag_table)
	parts.collision = geometry.collision
	parts.walkable = StructureWalkable.faces(meshes, parts.tag_table)
	# A windmill's sails and cap leave `meshes` for `mill` (they turn in the game); collision, the
	# walkable faces and the top above were made from the whole building and stay as they were.
	var mill := StructureMill.split(meshes, parts.tag_table, _centre_of(structure.footprint))
	if not mill.is_empty():
		parts.meshes = mill.rest
		mill.erase("rest")
		parts.mill = mill
	parts.top = geometry.top if triangles > 0 else NONE
	parts.openings = geometry.openings
	parts.layout = plant.get("layout")
	parts.anchors = ProcgenOrnaments.anchors(geometry)
	if decor and not info.is_empty() and not (parts.anchors as Array).is_empty():
		var anchors: Array[Dictionary] = []
		anchors.assign(parts.anchors)
		parts.decor_plan = StructureDecor.plan(anchors, info.rows, info.cost, int(info.sig))
	# With soft: "anchors" an ivy blanket or flower box that found room has an anchor but no blob.
	parts.placed_kinds = StructureDecor.placed_kinds_with(
		ProcgenOrnaments.placed_kinds(geometry), parts.anchors
	)
	parts.dressing = StructureDressing.build(doc, structure, parts.layout)
	return parts


## Every structure of `doc`: {"structures": [parts, ...]} (AuthoredLoadPrep's part).
## With `parallel` (and two or more structures) the structures build as one WorkerThreadPool group,
## on at most AuthoredStructures.load_threads() threads, and the result keeps the document's order
## (each task writes its own slot). Builds read the document and write nothing shared, so the
## output is the same either way (the pinned digests).
static func build(
	doc: MapDocument, parallel: bool = true, decor: bool = false, info: Dictionary = {}
) -> Dictionary:
	var list: Array[Structure] = doc.structures
	var out: Array = []
	if not parallel or list.size() < 2:
		for structure in list:
			out.append(build_one(doc, structure, decor, info))
		return {"structures": out, "decor": decor}
	out.resize(list.size())
	var group := WorkerThreadPool.add_group_task(
		func(index: int) -> void: out[index] = build_one(doc, list[index], decor, info),
		list.size(),
		mini(list.size(), AuthoredStructures.load_threads()),
		false,
		"StructureGeometry.build"
	)
	WorkerThreadPool.wait_for_group_task_completion(group)
	return {"structures": out, "decor": decor}


## A key that changes when anything a structure's geometry depends on does: its recipe (the digest
## of its text), footprint, params, seed, style, the `textured` switch, the mesh format and the
## ground sampled along its outline and across its inside. AuthoredStructures rebuilds a structure
## only when its key moved, and keeps built parts by key.
static func key_of(
	doc: MapDocument,
	structure: Structure,
	boxes: Dictionary = {},
	samples: Array = [],
	decor: bool = false,
	near: Variant = null
) -> int:
	var under: Array = samples if not samples.is_empty() else _ground_samples_of(doc, structure)
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
			decor,
			StructureDressing.enabled,
			under[0],
			under[1],
			(
				near
				if near != null
				else (
					StructureDressing.neighbours(doc, structure, boxes)
					if StructureDressing.enabled
					else ([] as Array[PackedVector2Array])
				)
			),
		]
	)


## Keys of every structure of `doc` (id -> key).
static func keys_of(doc: MapDocument, decor: bool = false) -> Dictionary:
	var boxes := _boxes_of(doc)
	var grid := _grid_of(doc, boxes)
	var out := {}
	for structure in doc.structures:
		var near: Variant = (
			StructureDressing.neighbours(doc, structure, boxes, grid)
			if not grid.is_empty()
			else null
		)
		out[structure.id] = key_of(doc, structure, boxes, [], decor, near)
	return out


## keys_of() with a memo (id -> {"sig", "key", "gsig", "samples"}, the caller's to keep between
## calls). Sampling the ground under a plan is the cost of a key, and it grew with every structure
## standing (struct_perf2: 100 sequential adds spent 2.0 s of 2.3 on it). Two levels of reuse:
## a structure whose whole signature is unchanged keeps its key; one whose neighbours changed
## (every add alters the keys of the 10 or so around it) keeps its ground samples, which depend
## only on its footprint and the ground. The signature holds everything key_of() reads but the
## samples: the structure's own fields, the recipe digest, its neighbours' footprints and
## ground_fingerprint(), a hash of every ground input, so any edit of the ground, water or ponds
## changes it and no version counter has to be bumped by every writer of those public fields.
## The keys equal keys_of().
static func keys_memoised(doc: MapDocument, memo: Dictionary, decor: bool = false) -> Dictionary:
	var boxes := _boxes_of(doc)
	var grid := _grid_of(doc, boxes)
	var ground := ground_fingerprint(doc)
	var out := {}
	var live := {}
	for structure in doc.structures:
		var near: Array[PackedVector2Array] = (
			StructureDressing.neighbours(doc, structure, boxes, grid)
			if StructureDressing.enabled
			else ([] as Array[PackedVector2Array])
		)
		var sig := hash(
			[
				ground,
				StructureRecipes.digest(structure.recipe),
				structure.recipe,
				structure.footprint,
				JSON.stringify(structure.params, "", true),
				structure.seed_value,
				structure.style,
				textured,
				decor,
				StructureDressing.enabled,
				near,
			]
		)
		var gsig := hash([ground, structure.footprint, StructureDressing.enabled])
		var seen: Dictionary = memo.get(structure.id, {})
		var entry := seen
		if seen.get("sig") != sig:
			var samples: Array = (
				seen["samples"] if seen.get("gsig") == gsig else _ground_samples_of(doc, structure)
			)
			entry = {
				"sig": sig,
				"gsig": gsig,
				"samples": samples,
				"key": key_of(doc, structure, boxes, samples, decor, near),
			}
			memo[structure.id] = entry
		live[structure.id] = true
		out[structure.id] = entry["key"]
	for id: int in memo.keys():
		if not live.has(id):
			memo.erase(id)
	return out


## The two ground reads of a key: [ground_samples, StructureDressing.ground_samples] of the plan.
static func _ground_samples_of(doc: MapDocument, structure: Structure) -> Array:
	return [
		ground_samples(doc, structure.footprint),
		StructureDressing.ground_samples(doc, structure.footprint),
	]


## The neighbour grid of `doc` (StructureDressing.neighbour_grid), {} when the yard is off.
static func _grid_of(doc: MapDocument, boxes: Dictionary) -> Dictionary:
	return StructureDressing.neighbour_grid(doc, boxes) if StructureDressing.enabled else {}


## Per structure id, the bounds of its footprint (what neighbour tests compare), none when the
## yard is off.
static func _boxes_of(doc: MapDocument) -> Dictionary:
	var boxes := {}
	if StructureDressing.enabled:
		for structure in doc.structures:
			boxes[structure.id] = StructureDressing.bounds_of(structure.footprint)
	return boxes


## A hash of everything the ground under a structure depends on: the sampling grid, the heights,
## the pond mask and every water body (its kind, depth, level, speed and courses). Any change to
## these changes it, so a cached key is reused only while the ground is as it was.
static func ground_fingerprint(doc: MapDocument) -> int:
	var bodies: Array = []
	for body in doc.water_bodies:
		bodies.append(
			[
				body.id,
				body.kind,
				body.depth,
				body.level_m,
				body.speed,
				body.points,
				body.half_widths,
				body.beyond,
				body.beyond_up
			]
		)
	return hash(
		[
			doc.size_cells,
			doc.cell_size_m,
			doc.sample_spacing_m,
			hash(doc.heights),
			hash(doc.pond_mask),
			bodies
		]
	)


## The ground under a plan: along every side every KEY_STEP_M, then across the inside on a grid of
## KEY_STEP_M (coarser for a very wide plan, KEY_MAX_SAMPLES at most).
static func ground_samples(doc: MapDocument, plan: PackedVector2Array) -> PackedFloat32Array:
	var samples := PackedFloat32Array()
	var points := sample_points(plan)
	samples.resize(points.size())
	# One batched read of the grid (WaterGeometry.grounds_at, the same arithmetic as ground_at, so
	# the key does not move): the per-point call was 90 % of key_of, which runs on the main thread
	# for every structure at every refresh.
	var grounds := WaterGeometry.grounds_at(doc, points)
	for i in points.size():
		samples[i] = grounds[i]
	return samples


## The points ground_samples() reads: along every side every KEY_STEP_M, then across the inside on a
## grid of KEY_STEP_M (coarser for a very wide plan, KEY_MAX_SAMPLES at most). Empty under 3 points.
static func sample_points(plan: PackedVector2Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	var count := plan.size()
	if count < 3:
		return points
	var box := Rect2(plan[0], Vector2.ZERO)
	for k in count:
		var a := plan[k]
		var b := plan[(k + 1) % count]
		box = box.expand(b)
		var steps := maxi(1, ceili(a.distance_to(b) / KEY_STEP_M))
		for s in steps:
			points.append(a.lerp(b, float(s) / steps))
	var step := maxf(KEY_STEP_M, sqrt(box.get_area() / KEY_MAX_SAMPLES))
	var y := box.position.y + step * 0.5
	while y < box.end.y:
		var x := box.position.x + step * 0.5
		while x < box.end.x:
			var at := Vector2(x, y)
			if Geometry2D.is_point_in_polygon(at, plan):
				points.append(at)
			x += step
		y += step
	return points


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
	for mesh: Dictionary in all_meshes(parts):
		ctx.update(String(mesh.kind).to_utf8_buffer())
		ctx.update(String(mesh.role).to_utf8_buffer())
		var arrays: Array = mesh.arrays
		ctx.update(_snapped(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).to_byte_array())
	var mill: Dictionary = parts.get("mill", {})
	if not mill.is_empty():
		# The pivots and axis of a windmill's moving parts (nothing is added for any other building).
		var pivots := PackedVector3Array(
			[mill.hub as Vector3, mill.axis as Vector3, mill.centre as Vector3]
		)
		ctx.update(_snapped(pivots).to_byte_array())
	var collision := parts.get("collision", PackedVector3Array()) as PackedVector3Array
	ctx.update(_snapped(collision).to_byte_array())
	var top: Variant = parts.get("top", NONE)
	var top_text := "%.4f" % float(top) if top is float else str(top)
	ctx.update(top_text.to_utf8_buffer())
	return ctx.finish().hex_encode()


## `points` rounded to DIGEST_SNAP_M, -0 written as 0: a one-ulp difference in a libm (Windows,
## glibc, macOS) must not move a pin.
static func _snapped(points: PackedVector3Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(points.size())
	for i in points.size():
		var p := points[i]
		out[i] = Vector3(_snap(p.x), _snap(p.y), _snap(p.z))
	return out


static func _snap(value: float) -> float:
	return snappedf(value, DIGEST_SNAP_M) + 0.0


## The triangles of `parts` in all its meshes.
static func triangle_count(parts: Dictionary) -> int:
	var total := 0
	for mesh: Dictionary in all_meshes(parts):
		total += (mesh.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


## Every mesh of `parts`: the static `meshes`, then a windmill's turning `mill.wheel` and
## `mill.cap` (StructureMill).
static func all_meshes(parts: Dictionary) -> Array:
	var mill: Dictionary = parts.get("mill", {})
	if mill.is_empty():
		return parts.get("meshes", [])
	return (
		(parts.get("meshes", []) as Array)
		+ (mill.get("wheel", []) as Array)
		+ (mill.get("cap", []) as Array)
	)


## The middle of the plan `footprint` (the mean of its corners), the windmill cap's fallback centre.
static func _centre_of(footprint: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for corner in footprint:
		sum += corner
	return sum / float(maxi(footprint.size(), 1))


## `parts` with the placeholder plot of `structure` as its only mesh, for a recipe this game does
## not have or cannot build (a peer whose library transfer is still running, a library removed,
## a recipe that fails): a low pale slab on the footprint that follows the ground, so the place of
## the building stays visible and nothing is a hole. No collision, no top.
static func _with_plot(parts: Dictionary, doc: MapDocument, structure: Structure) -> Dictionary:
	var plot := _plot(doc, structure.footprint)
	if plot.is_empty():
		return parts
	parts.meshes = [plot]
	parts.placeholder = true
	parts.triangles = (plot.arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return parts


## The plot mesh for plan `plan` (a role mesh like build_one's): the top face PLOT_HEIGHT_M above
## the ground at each corner and a skirt PLOT_SINK_M into it. {} when the plan cannot be
## triangulated.
static func _plot(doc: MapDocument, plan: PackedVector2Array) -> Dictionary:
	var cuts := Geometry2D.triangulate_polygon(plan)
	if cuts.is_empty():
		return {}
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var ground := PackedFloat32Array()
	for p in plan:
		ground.append(WaterGeometry.ground_at(doc, p))
	for k in range(0, cuts.size(), 3):
		var base := vertices.size()
		var corners: Array[Vector3] = []
		for c in 3:
			var at: int = cuts[k + c]
			corners.append(Vector3(plan[at].x, ground[at] + PLOT_HEIGHT_M, plan[at].y))
		vertices.append_array(PackedVector3Array(corners))
		for c in 3:
			normals.append(Vector3.UP)
		indices.append_array(
			_facing(corners[0], corners[1], corners[2], Vector3.UP, [base, base + 1, base + 2])
		)
	var count := plan.size()
	for k in count:
		var a := plan[k]
		var b := plan[(k + 1) % count]
		var side := (b - a).orthogonal().normalized()
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + side * 0.02, plan):
			side = -side
		var out := Vector3(side.x, 0.0, side.y)
		var base := vertices.size()
		var low_a := Vector3(a.x, ground[k] - PLOT_SINK_M, a.y)
		var low_b := Vector3(b.x, ground[(k + 1) % count] - PLOT_SINK_M, b.y)
		var high_a := Vector3(a.x, ground[k] + PLOT_HEIGHT_M, a.y)
		var high_b := Vector3(b.x, ground[(k + 1) % count] + PLOT_HEIGHT_M, b.y)
		vertices.append_array(PackedVector3Array([low_a, low_b, high_b, high_a]))
		for c in 4:
			normals.append(out)
		indices.append_array(_facing(low_a, low_b, high_b, out, [base, base + 1, base + 2]))
		indices.append_array(_facing(low_a, high_b, high_a, out, [base, base + 2, base + 3]))
	var uvs := PackedVector2Array()
	uvs.resize(vertices.size())
	var colors := PackedColorArray()
	colors.resize(vertices.size())
	colors.fill(Color.WHITE)
	var tags := PackedInt32Array()
	tags.resize(vertices.size())
	tags.fill(-1)
	return {
		"kind": PLOT_KIND,
		"role": StructureLook.TRIM,
		"arrays": _arrays(PLOT_KIND, vertices, normals, uvs, colors, indices),
		"tags": tags,
	}


## The indices `at` (three) of triangle (a, b, c), ordered so the face points along `normal`.
static func _facing(
	a: Vector3, b: Vector3, c: Vector3, normal: Vector3, at: Array[int]
) -> PackedInt32Array:
	var ordered := (b - a).cross(c - a).dot(normal) >= 0.0
	return PackedInt32Array([at[0], at[1], at[2]] if ordered else [at[0], at[2], at[1]])


static func _empty(structure: Structure) -> Dictionary:
	return {
		"placeholder": false,
		"palette": "",
		"stone_tone": "",
		"id": structure.id,
		"recipe": structure.recipe,
		"style": structure.style,
		"meshes": [],
		"mill": {},
		"tag_table": PackedStringArray(),
		"collision": PackedVector3Array(),
		"walkable": PackedVector3Array(),
		"top": NONE,
		"openings": [],
		"layout": null,
		"placed_kinds": [] as Array[String],
		"anchors": [] as Array[Dictionary],
		"decor": false,
		"dressing": {},
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


## `surface` cut into one mesh per material role: every triangle goes to the role of the node that
## made its first vertex (`roles` maps a tag id to a role). Vertices keep their relative order, so
## the quads the tangents rely on stay four in a row.
static func split_surface(surface: PlantSurface, roles: PackedStringArray) -> Array:
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
	if kind == "wood" or kind == "boards" or kind == "masonry":
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
