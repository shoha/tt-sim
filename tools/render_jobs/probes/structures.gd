extends RefCounted

## Render-job probe (`call` op) for structures (card S2; there is no Structure tool yet, so they
## are laid through the editor API). step.action:
##   town              lays the test town: a chimneyed cottage, a trimmed townhouse, a townhouse
##                     on an L plan and a stone house (turned), through AuthoringEditor.structures,
##                     then waits for their builds. step.set picks the layout: "basic" (default).
##   street {from, to, preset}  lays a street (Wall.Kind.ROW) through AuthoringEditor.walls.
##   flush             waits for every building in flight (AuthoredStructures.flush).
##   report            the structure nodes of the open map: triangles, meshes per role, top, notes.
##   remove_all        removes every structure (one history entry each), for a clean run.
##   tile {ref, width, depth, yaw, seed}  (card S3, tools/render_structure_thumbnails.gd) removes
##                     every structure and lays this one alone at the map's centre.
##   styles            (architecture styles card 1) lays the ten style starters in two rows of five
##                     (STYLE_LOTS), then waits for their builds.
##   styles2           (styles integration 2) lays tudor, pueblo, two adobe kits, a round hut and the
##                     five ruins (STYLES2_LOTS), then waits for their builds.
##   styles3           (styles integration 3) lays the thirteen profile-roof, tower, battlement and
##                     arched styles (STYLES3_LOTS), then waits for their builds.
##   rounds            (styles integration card) lays the five round starters as a hamlet
##                     (ROUND_LOTS), then waits for their builds. tile also takes {sides}.

const CLOTH_AIM := preload("res://tools/render_jobs/probes/cloth_aim.gd")

const STYLE_LOTS: Array = [
	# recipe, centre x, centre z, width, depth, yaw degrees, seed
	["core:villa_stucco", -30.0, -14.0, 7.0, 5.0, 0.0, 51],
	["core:adobe_house", -15.0, -14.0, 6.0, 5.0, 0.0, 52],
	["core:slate_house", 0.0, -14.0, 7.0, 5.0, 0.0, 53],
	["core:alpine_chalet", 15.0, -14.0, 7.0, 5.0, 0.0, 54],
	["core:canal_house", 30.0, -14.0, 5.0, 8.0, 0.0, 55],
	["core:thatched_cottage", -30.0, 14.0, 6.0, 4.0, 0.0, 56],
	["core:log_cabin", -15.0, 14.0, 6.0, 4.0, 0.0, 57],
	["core:turf_longhouse", 0.0, 14.0, 9.0, 4.0, 0.0, 58],
	["core:brick_terrace", 15.0, 14.0, 5.0, 7.0, 0.0, 59],
	["core:barn", 30.0, 14.0, 9.0, 6.0, 0.0, 60],
]

const STYLES2_LOTS: Array = [
	# recipe, centre x, centre z, width, depth, yaw degrees, seed (a round row's width is its diameter)
	["core:tudor_townhouse", -30.0, -14.0, 5.0, 7.0, 0.0, 81],
	["core:pueblo", -15.0, -14.0, 8.0, 6.0, 0.0, 82],
	["core:adobe_parapet", 0.0, -14.0, 6.0, 5.0, 0.0, 83],
	["core:adobe_rounded", 15.0, -14.0, 6.0, 5.0, 0.0, 84],
	["core:round_hut", 30.0, -14.0, 5.6, 5.6, 0.0, 85],
	["core:ruin_cottage", -30.0, 14.0, 6.0, 4.5, 0.0, 86],
	["core:ruin_chapel", -15.0, 14.0, 9.0, 5.5, 0.0, 92],
	["core:ruin_townhouse", 0.0, 14.0, 5.0, 8.0, 0.0, 88],
	["core:ruin_tower", 15.0, 14.0, 5.2, 5.2, 0.0, 89],
	["core:ruin_barn", 30.0, 14.0, 9.0, 6.0, 0.0, 90],
]

const STYLES3_LOTS: Array = [
	# recipe, centre x, centre z, width, depth, yaw degrees, seed: the profile-roof, tower, battlement,
	# stepped-gable and arched styles of styles integration 3 (2026-10-28), in two rows
	["core:gambrel_barn", -40.0, -24.0, 10.0, 7.0, 0.0, 101],
	["core:mansard_townhouse", -20.0, -24.0, 6.0, 8.0, 0.0, 102],
	["core:dutch_canal_house", 0.0, -24.0, 5.0, 8.0, 0.0, 103],
	["core:dutch_bell_house", 20.0, -24.0, 5.0, 8.0, 0.0, 104],
	["core:saltbox_house", 40.0, -24.0, 7.0, 5.0, 0.0, 105],
	["core:half_hip_cottage", -30.0, 0.0, 7.0, 5.0, 0.0, 106],
	["core:minka", -10.0, 0.0, 9.0, 7.0, 0.0, 107],
	["core:market_hall", 10.0, 0.0, 6.5, 10.0, 0.0, 108],
	["core:chinese_hall", 30.0, 0.0, 11.0, 7.0, 0.0, 109],
	["core:chapel", -30.0, 24.0, 5.0, 9.0, 0.0, 110],
	["core:pagoda_tower", -10.0, 24.0, 6.0, 6.0, 0.0, 111],
	["core:castle_keep", 10.0, 24.0, 7.0, 7.0, 0.0, 112],
	["core:gatehouse", 30.0, 24.0, 9.0, 5.0, 0.0, 113],
]

const ROUND_LOTS: Array = [
	# recipe, centre x, centre z, diameter, yaw degrees, seed (the hero roundhouse at the origin is
	# the one the selection captures edit)
	["core:roundhouse", 0.0, 0.0, 7.2, 0.0, 71],
	["core:roundhouse", -13.0, -7.0, 8.0, 20.0, 72],
	["core:round_hut", 12.0, -6.0, 5.6, -10.0, 73],
	["core:round_hut", -10.0, 10.0, 6.0, 30.0, 74],
	["core:watchtower", 17.0, 7.0, 4.8, 15.0, 75],
	["core:tower_hex", -19.0, 3.0, 5.2, 0.0, 76],
	["core:dome_hall", 6.0, 15.0, 9.2, -15.0, 77],
]

const BASIC_LOTS: Array = [
	# recipe, centre x, centre z, width, depth, yaw degrees, seed
	["core:cottage_chimneyed", -7.0, -3.0, 6.0, 4.0, 12.0, 11],
	["core:townhouse_trimmed", 3.0, -5.0, 6.0, 5.0, -8.0, 21],
	["core:townhouse", 10.0, 3.0, 5.0, 5.0, 0.0, 31],
	["core:stone_house", -4.0, 6.0, 5.0, 4.0, 35.0, 41],
]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"town":
			return _town(base)
		"styles":
			return _styles(base)
		"rounds":
			return _rounds(base, step.get("lots", ROUND_LOTS))
		"styles2":
			return _styles2(base, step)
		"styles3":
			return _styles2(base, {"lots": step.get("lots", STYLES3_LOTS)})
		"street":
			return _street(base, step)
		"flush":
			return _flush(base)
		"report":
			return _report(base)
		"remove_all":
			return _remove_all(base)
		"inside":
			return _inside(base)
		"tile":
			return _tile(base, step)
		"aim_cloth", "aim_wind":
			return CLOTH_AIM.run(base, step)
		"many":
			return _many(base, step)
		"village":
			return _village(base, step)
		"load_build":
			return _load_build(base, step)
		"plain":
			return _plain(base, bool(step.get("on", true)))
		"dressing":
			return _dressing(base, bool(step.get("on", true)))
	return "unknown action %s" % step.get("action", "")


## `count` structures on a grid around the map's centre (card S6 perf pass): the four recipes of
## BASIC_LOTS in turn, 14 m apart, each with its own seed, then waits for the builds. Returns the
## triangles they add up to.
static func _many(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var count := int(step.get("count", 20))
	var columns := int(ceil(sqrt(float(count))))
	var laid := 0
	var refusals := {}
	for k in count:
		var lot: Array = BASIC_LOTS[k % BASIC_LOTS.size()]
		var at := Vector2(
			(float(k % columns) - (columns - 1) * 0.5) * 14.0,
			(float(k / columns) - (columns - 1) * 0.5) * 14.0
		)
		var plan := _rect(float(lot[3]), float(lot[4]), float(lot[5]) + k * 7.0, at)
		var structure := Structure.make(0, String(lot[0]), plan, 100 + k)
		if String(lot[0]) == "core:townhouse":
			structure.footprint = _l_shape(at)
		if editor.structures.add(structure) >= 0:
			laid += 1
		else:
			refusals["%d:%s" % [k, editor.structures.last_refusal]] = true
	var nodes := _nodes(base)
	var triangles := 0
	if nodes != null:
		nodes.flush()
		for child in nodes.get_children():
			for mesh in child.get_children():
				if mesh is MeshInstance3D:
					var instance := mesh as MeshInstance3D
					triangles += (
						(
							(
								instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
								as PackedInt32Array
							)
							. size()
						)
						/ 3
					)
	return (
		"laid %d of %d structures, %d triangles%s"
		% [
			laid,
			count,
			triangles,
			"" if refusals.is_empty() else " (refused: " + str(refusals.keys()) + ")"
		]
	)


## (struct_perf) `count` structures of the served core library in turn (each at its default size, its
## own seed and yaw) on a square grid `spacing` m apart, then the cost of laying them: the time to
## queue every build, the time until the last lands, and what the nodes hold (mesh instances, unique
## materials, triangles, collision faces).
##
## (struct_perf2) Action `load_build` {count, mode}: builds the same `count` structures as a load does
## (StructureGeometry.build of a document, without laying them through the editor), mode "seq" one
## after another or "par" as a worker group, and reports the time, the static memory peak since the
## process began (run one mode per job) and a digest of every result, to compare the two modes.
static func _load_build(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var count := int(step.get("count", 100))
	var rows := LibraryStructureStore.structures("core")
	var columns := int(ceil(sqrt(float(count))))
	var spacing := float(step.get("span", 88.0)) / columns
	var doc := StructureGeometry.ground_snapshot(editor.document)
	doc.structures.clear()
	for k in count:
		var row: Dictionary = rows[k % rows.size()]
		var size: Array = row["default_size_m"]
		var at := Vector2(
			(float(k % columns) - (columns - 1) * 0.5) * spacing,
			(float(k / columns) - (columns - 1) * 0.5) * spacing
		)
		var fit := minf(1.0, (spacing - 2.0) / maxf(float(size[0]), float(size[1])))
		var plan := _rect(float(size[0]) * fit, float(size[1]) * fit, float((k * 37) % 360), at)
		doc.structures.append(Structure.make(k + 1, String(row["ref"]), plan, 100 + k))
	StructureRecipes.ensure_served()
	var mode := String(step.get("mode", "par"))
	var t0 := Time.get_ticks_usec()
	var built := StructureGeometry.build(doc, mode == "par")
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var digests := PackedStringArray()
	var refused := 0
	for parts: Dictionary in built["structures"]:
		if (parts.meshes as Array).is_empty():
			refused += 1
		else:
			digests.append(StructureGeometry.digest_of(parts))
	# What a load then does: makes the nodes (ArrayMeshes, collision) and seeds the parts cache.
	var nodes := AuthoredStructures.create(doc, built)
	var text := (
		"load_build %s: %d structures (%d refused) in %.0f ms, with nodes static %.0f MB peak %.0f MB, digest %d"
		% [
			mode,
			count,
			refused,
			ms,
			OS.get_static_memory_usage() / 1048576.0,
			OS.get_static_memory_peak_usage() / 1048576.0,
			hash(digests)
		]
	)
	nodes.free()
	return text


static func _village(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var count := int(step.get("count", 100))
	var rows := LibraryStructureStore.structures("core")
	var columns := int(ceil(sqrt(float(count))))
	# The map is at most 97 m across: the lots share `span` m, and a footprint larger than its lot
	# is scaled down to fit (a village is dense, not a refused row).
	var spacing := float(step.get("span", 88.0)) / columns
	var t0 := Time.get_ticks_usec()
	var laid := 0
	for k in count:
		var row: Dictionary = rows[k % rows.size()]
		var size: Array = row["default_size_m"]
		var at := Vector2(
			(float(k % columns) - (columns - 1) * 0.5) * spacing,
			(float(k / columns) - (columns - 1) * 0.5) * spacing
		)
		var fit := minf(1.0, (spacing - 2.0) / maxf(float(size[0]), float(size[1])))
		var plan := _rect(float(size[0]) * fit, float(size[1]) * fit, float((k * 37) % 360), at)
		if editor.structures.add(Structure.make(0, String(row["ref"]), plan, 100 + k)) >= 0:
			laid += 1
	var queued_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var nodes := _nodes(base)
	if nodes == null:
		return "no structures node"
	var t1 := Time.get_ticks_usec()
	nodes.flush()
	var flush_ms := (Time.get_ticks_usec() - t1) / 1000.0
	# What the parts cache keeps beside the nodes: the mesh arrays, and the collision faces.
	var cached_bytes := 0
	for parts: Dictionary in nodes._cache.values():
		for mesh: Dictionary in parts.get("meshes", []):
			for column: Variant in mesh["arrays"]:
				if column is Object or column == null:
					continue
				cached_bytes += var_to_bytes(column).size()
		cached_bytes += (
			(parts.get("collision", PackedVector3Array()) as PackedVector3Array).size() * 12
		)
	print(
		"village parts cache: %d entries, %.1f MB" % [nodes._cache.size(), cached_bytes / 1048576.0]
	)
	var instances := 0
	var triangles := 0
	var collision_faces := 0
	var materials := {}
	var meshes := {}
	for child in nodes.get_children():
		for part in child.get_children():
			if part is MeshInstance3D:
				var instance := part as MeshInstance3D
				instances += 1
				meshes[instance.mesh.get_rid()] = true
				materials[instance.mesh.surface_get_material(0).get_rid()] = true
				triangles += (
					(
						(instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array)
						. size()
					)
					/ 3
				)
			elif part is StaticBody3D:
				for shape in part.get_children():
					if shape is CollisionShape3D and shape.shape is ConcavePolygonShape3D:
						collision_faces += (
							(shape.shape as ConcavePolygonShape3D).get_faces().size() / 3
						)
	return (
		"village laid %d of %d: queue %.0f ms (main), flush wait %.0f ms; %d nodes, %d mesh instances, %d unique meshes, %d unique materials, %d triangles, %d collision faces"
		% [
			laid,
			count,
			queued_ms,
			flush_ms,
			nodes.get_child_count(),
			instances,
			meshes.size(),
			materials.size(),
			triangles,
			collision_faces
		]
	)


## Draws every structure mesh with one plain white StandardMaterial3D (on), or with its own
## materials again (off, which needs the originals kept: it rebuilds the nodes), so a run can split
## the cost of the geometry and shadows from the cost of the painterly shaders.
static func _plain(base: Node, on: bool) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no structures"
	var plain := StandardMaterial3D.new()
	plain.vertex_color_use_as_albedo = true
	var changed := 0
	for child in nodes.get_children():
		for mesh in child.get_children():
			if mesh is MeshInstance3D and (mesh as MeshInstance3D).mesh != null:
				var instance := mesh as MeshInstance3D
				if on:
					instance.set_meta("tt_s6_material", instance.mesh.surface_get_material(0))
					instance.mesh.surface_set_material(0, plain)
				elif instance.has_meta("tt_s6_material"):
					instance.mesh.surface_set_material(0, instance.get_meta("tt_s6_material"))
				changed += 1
	return "%s %d meshes" % ["plain" if on else "restored", changed]


## Switches the buildings' yards (StructureDressing: soft ground, path, plants) on or off and
## rebuilds every structure, so a perf run can split their cost.
static func _dressing(base: Node, on: bool) -> String:
	StructureDressing.enabled = on
	var nodes := _nodes(base)
	var editor := _editor(base)
	if nodes == null or editor == null:
		return "dressing %s (no structures yet)" % ["on" if on else "off"]
	nodes.refresh(editor.document)
	nodes.flush()
	var meshes := 0
	for child in nodes.get_children():
		meshes += child.find_children("dressing_*", "MeshInstance3D", false, false).size()
	return "dressing %s, %d yard meshes" % ["on" if on else "off", meshes]


## One structure alone at the centre (the thumbnail scene), the front turned `yaw` degrees.
static func _tile(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	_remove_all(base)
	var plan := _rect(
		float(step.get("width", 6.0)),
		float(step.get("depth", 4.0)),
		float(step.get("yaw", 0.0)),
		Vector2.ZERO
	)
	var sides := int(step.get("sides", 0))
	if sides > 0:
		# A round structure: `width` is its diameter.
		var diameter := float(step.get("width", 6.0))
		plan = StructurePlacement.lot_plan(
			Vector2.ZERO,
			Vector2(diameter, diameter),
			deg_to_rad(float(step.get("yaw", 0.0))),
			sides
		)
	# `ornaments`: kind names the Decorate row would have on (StructureOrnaments), `ivy` the amount.
	var params := StructureOrnaments.with_kinds({}, step.get("ornaments", []))
	if step.has("ivy"):
		params = StructureOrnaments.with_ivy_amount(params, float(step["ivy"]))
	var structure := Structure.make(
		0, String(step.get("ref", "")), plan, int(step.get("seed", 5)), params
	)
	# `decor` false keeps procgen's flat blobs (the "before" of the plant_decor look captures).
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var nodes := AuthoredStructures.of_map(ctrl.map_root)
	nodes.plants = bool(step.get("decor", true))
	var id := editor.structures.add(structure)
	nodes.flush()
	if id < 0:
		return "refused: %s" % editor.structures.last_refusal
	var report := ""
	if nodes != null:
		var node := nodes.get_structure_node(id)
		var multis := 0
		var triangles := 0
		var surfaces := 0
		if node != null:
			for child in node.get_children():
				if child is MeshInstance3D and child.name == AuthoredStructures.DECOR_NODE:
					# The baked decor (batch_c): its surfaces are its draws.
					var baked_mesh := (child as MeshInstance3D).mesh
					for s in baked_mesh.get_surface_count():
						surfaces += 1
						var baked_index: PackedInt32Array = baked_mesh.surface_get_arrays(s)[
							Mesh.ARRAY_INDEX
						]
						triangles += baked_index.size() / 3
				if child is MultiMeshInstance3D:
					var multi := (child as MultiMeshInstance3D).multimesh
					multis += 1
					for s in multi.mesh.get_surface_count():
						surfaces += 1
						var index: PackedInt32Array = multi.mesh.surface_get_arrays(s)[
							Mesh.ARRAY_INDEX
						]
						triangles += index.size() / 3 * multi.instance_count
		report = (
			"; decor: %d multimeshes, %d surfaces, %d triangles" % [multis, surfaces, triangles]
		)
		structure.id = id
		report += _coverage(editor.document, structure)
	return "tile %s -> %d%s" % [step.get("ref", ""), id, report]


## The ivy patches of `structure` against the plants laid on them (batch_c): the patch area, the
## free area (patches minus the openings' rectangles), the area of the plants' extents (overlaps
## counted twice) and the plants kept by the triangle cap. A text suffix for the tile report.
static func _coverage(doc: MapDocument, structure: Structure) -> String:
	var parts := StructureGeometry.build_one(doc, structure, true)
	var anchors: Array[Dictionary] = []
	anchors.assign(parts.get("anchors", []))
	var rows := AssetStore.decor_rows(PaletteLibrary.DEFAULT_ROOT)
	if anchors.is_empty():
		return "; no anchors (%s)" % str(parts.get("problem", ""))
	var free := 0.0
	var patch := 0.0
	for anchor in anchors:
		if anchor.get("kind") != "ivy":
			continue
		var area := float(anchor.width) * float(anchor.height)
		patch += area
		for rect: Variant in anchor.get("exclusions", []):
			var r: Array = rect
			area -= maxf(0.0, float(r[2]) - float(r[0])) * maxf(0.0, float(r[3]) - float(r[1]))
		free += maxf(area, 0.0)
	var covered := 0.0
	var ivy_count := 0
	for placement in StructureDecor.placements(anchors, rows):
		if placement.kind == StructureDecor.KIND_IVY:
			var extent: Vector2 = placement.extent
			covered += extent.x * extent.y
			ivy_count += 1
	return (
		"; ivy patch %.1f m2, free %.1f m2, plant extent %.1f m2 (%.0f%% of free), %d ivy plants uncapped"
		% [patch, free, covered, 100.0 * covered / maxf(free, 0.001), ivy_count]
	)


## How many scatter rows (plants, rocks) of the map root stand inside a structure's footprint,
## and how many stand within a metre of one (scatter clearance should leave none inside).
static func _inside(base: Node) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.map_root == null:
		return "no map"
	var scatter := ctrl.map_root.get_node_or_null(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	if scatter == null:
		return "no scatter node"
	var inside := 0
	var near := 0
	var total := 0
	var rows := scatter.rows_by_asset()
	for asset_id in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		for r in flat.size() / MapDocument.ROW_STRIDE:
			var at := Vector2(
				flat[r * MapDocument.ROW_STRIDE], flat[r * MapDocument.ROW_STRIDE + 2]
			)
			total += 1
			for structure in ctrl.document.structures:
				if Geometry2D.is_point_in_polygon(at, structure.footprint):
					inside += 1
					continue
				var grown := Geometry2D.offset_polygon(structure.footprint, 1.0)
				if not grown.is_empty() and Geometry2D.is_point_in_polygon(at, grown[0]):
					near += 1
	return "scatter rows %d, inside footprints %d, within 1 m outside %d" % [total, inside, near]


static func _editor(base: Node) -> AuthoringEditor:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	return ctrl.editor if ctrl != null else null


static func _nodes(base: Node) -> AuthoredStructures:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.map_root == null:
		return null
	return ctrl.map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures


static func _rect(width: float, depth: float, yaw_deg: float, at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in [
		Vector2(-width, -depth),
		Vector2(width, -depth),
		Vector2(width, depth),
		Vector2(-width, depth)
	]:
		out.append((corner * 0.5).rotated(deg_to_rad(yaw_deg)) + at)
	return out


static func _l_shape(at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for corner in [
		Vector2(-4, -3), Vector2(4, -3), Vector2(4, 0), Vector2(0, 0), Vector2(0, 3), Vector2(-4, 3)
	]:
		out.append(corner + at)
	return out


static func _town(base: Node) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var lines := PackedStringArray()
	for lot: Array in BASIC_LOTS:
		var plan := _rect(float(lot[3]), float(lot[4]), float(lot[5]), Vector2(lot[1], lot[2]))
		var structure := Structure.make(0, String(lot[0]), plan, int(lot[6]))
		if String(lot[0]) == "core:townhouse":
			structure.footprint = _l_shape(Vector2(lot[1], lot[2]))
		var id := editor.structures.add(structure)
		lines.append(
			"%s -> %d%s" % [lot[0], id, "" if id >= 0 else " " + editor.structures.last_refusal]
		)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	return "laid: " + "; ".join(lines)


## The ten style starters (STYLE_LOTS), laid through the editor API.
static func _styles(base: Node) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var lines := PackedStringArray()
	for lot: Array in STYLE_LOTS:
		var plan := _rect(float(lot[3]), float(lot[4]), float(lot[5]), Vector2(lot[1], lot[2]))
		var id := editor.structures.add(Structure.make(0, String(lot[0]), plan, int(lot[6])))
		lines.append(
			"%s -> %d%s" % [lot[0], id, "" if id >= 0 else " " + editor.structures.last_refusal]
		)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	return "laid: " + "; ".join(lines)


## The stacked, kit and ruin starters of the second styles integration (STYLES2_LOTS): two rows of
## five, a round row laid as its polygon. A step's `lots` (same rows, an optional eighth entry the
## recipe parameters) replaces the table, so a job can lay a comparison.
static func _styles2(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var lines := PackedStringArray()
	for lot: Array in step.get("lots", STYLES2_LOTS) as Array:
		var row := LibraryStructureStore.structure(String(lot[0]))
		var plan := StructurePlacement.lot_plan(
			Vector2(lot[1], lot[2]),
			Vector2(float(lot[3]), float(lot[4])),
			deg_to_rad(float(lot[5])),
			StructurePlacement.sides_of(row)
		)
		var record := Structure.make(0, String(lot[0]), plan, int(lot[6]))
		if lot.size() > 7:
			record.params = lot[7] as Dictionary
		var id := editor.structures.add(record)
		lines.append(
			"%s -> %d%s" % [lot[0], id, "" if id >= 0 else " " + editor.structures.last_refusal]
		)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	return "laid: " + "; ".join(lines)


## The round structures (styles integration card): the five round starters as a small hamlet
## (ROUND_LOTS), laid through the editor with the polygon plans the Structure tool makes.
static func _rounds(base: Node, lots: Array = ROUND_LOTS) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var lines := PackedStringArray()
	for lot: Array in lots:
		var row := LibraryStructureStore.structure(String(lot[0]))
		var diameter := float(lot[3])
		var plan := StructurePlacement.lot_plan(
			Vector2(lot[1], lot[2]),
			Vector2(diameter, diameter),
			deg_to_rad(float(lot[4])),
			StructurePlacement.sides_of(row)
		)
		var id := editor.structures.add(Structure.make(0, String(lot[0]), plan, int(lot[5])))
		lines.append(
			"%s -> %d%s" % [lot[0], id, "" if id >= 0 else " " + editor.structures.last_refusal]
		)
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	return "laid: " + "; ".join(lines)


static func _street(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var a: Array = step.get("from", [-14, 12])
	var b: Array = step.get("to", [14, 12])
	var id := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(float(a[0]), 0, float(a[1])),
		Vector3(float(b[0]), 0, float(b[1])),
		-1.0,
		{"seed": 7, "side": 0, "preset": int(step.get("preset", 3))}
	)
	return "street %d" % id if id >= 0 else "refused: %s" % editor.walls.last_refusal


static func _flush(base: Node) -> String:
	var nodes := _nodes(base)
	return "flushed %d" % nodes.flush() if nodes != null else "no AuthoredStructures"


static func _report(base: Node) -> String:
	var nodes := _nodes(base)
	if nodes == null:
		return "no AuthoredStructures"
	var lines := PackedStringArray()
	for child in nodes.get_children():
		var tris := 0
		var meshes := PackedStringArray()
		for mesh in child.find_children("*", "MeshInstance3D", true, false):
			var array_mesh := (mesh as MeshInstance3D).mesh
			var count: int = (
				array_mesh.surface_get_array_index_len(0) / 3
				if array_mesh.get_surface_count() > 0
				else 0
			)
			tris += count
			meshes.append("%s %d" % [mesh.name, count])
		lines.append("%s tris %d [%s]" % [child.name, tris, ", ".join(meshes)])
	return "top_y %.2f notes %s; %s" % [nodes.top_y, str(nodes.notes), "; ".join(lines)]


static func _remove_all(base: Node) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	var removed := 0
	for structure in editor.structures.list():
		if editor.structures.remove(structure.id):
			removed += 1
	return "removed %d" % removed
