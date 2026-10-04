class_name AuthoredWater
extends Node3D

## The authored water of a map (MapDocument.water_bodies) as nodes, at the map origin with
## an identity transform (the frame of the flow map and the mesh's UVs):
##
## - one merged surface mesh, WaterMeshBuilder.MESH_NAME (`AuthoredWater-water`), so
##   WaterGlbUtils.process_water_meshes() gives it the shared water material like a Blender
##   plane; the document's flow map (MapDocument.water_flow) rides as its surface material's
##   emission texture, where process_water_meshes() looks for one. No shadow, and exempt
##   from the bounds walks (Constants.BOUNDS_EXEMPT_META) like the ground skirt, so the
##   camera and reflection probe measure the ground, not a surface tucked under its banks;
## - per body a surface StaticBody3D on WaterSurface.LAYER (grid, measure, drag ruler and the
##   float rule find the surface there; the terrain layer still sees the bed) and a
##   WaterZone with the body's level and footprint (WaterZone.create_for_footprint), so
##   bodies at different levels detect tokens under their own surface;
## - the waterfalls (phase 4c, P4c-3): one MeshInstance3D, WaterFallMesh.MESH_NAME
##   (`AuthoredWater-falls`, a name that deliberately does not end in `-water`, so
##   process_water_meshes() leaves it alone), holding every fall's curtain, foam ring and
##   mist (WaterFallMesh, built with the surface by WaterMeshBuilder.build). No shadow, no
##   collision (tokens land on the face or in the pool as on a Tier face), bounds-exempt, its
##   custom_aabb grown for the packed mist quads. Its material is the one shared
##   fall_material() on shaders/waterfall.gdshader (P4c-4) at FALLS_RENDER_PRIORITY:
##   strictly above the water material's and below GridOverlay.RENDER_PRIORITY, because at
##   an equal priority the water (alpha 1) paints over the curtain entirely (P4c-0 probe a).
##   WaterGlbUtils.apply_water_settings() forwards the palette and motion keys the falls
##   shader shares with the water's onto it, so the Water pane restyles falls live; the Water
##   tool warms it as it opens (warm_fall_material(), as the Bridge tool warms the crossing
##   materials) and the first-launch graphics warm-up draws a falls sample (warmup_samples()).
##
## `levels` and `wet` (per document sample) are what the grid's ground field raises to
## (GroundHeightField); `version` changes with every rebuild.
##
## Authoring edits (P4-3 carve, P4-4 water tool) call request_refresh(document): the mesh
## geometry and the flow bake (about 0.3 s on a 200 ft map) run on a worker thread from a
## snapshot of the document, and the result is swapped in on the main thread (the baked flow
## is written into the document, which ships it). A request while one runs is queued; only
## the newest queued one runs. Summary: docs/ARCHITECTURE.md "Authored water at runtime".

signal refreshed

const NODE_NAME := "AuthoredWater"
const WATER_SHADER := preload("res://shaders/water.gdshader")
const FALLS_SHADER := preload("res://shaders/waterfall.gdshader")
## The falls material's render priority: above the shared water material (0) so the water
## never paints over the curtain, below the grid (GridOverlay.RENDER_PRIORITY) and the
## submerged-token marker (SubmergedMarker.RENDER_PRIORITY), which draw over it.
const FALLS_RENDER_PRIORITY := 1
## The warm-up's falls map (warmup_falls_document): a tier one tier high across the map, its
## face from WARMUP_TIER_FACE_FROM_Z to WARMUP_TIER_FACE_TO_Z, and a waist river down it.
const WARMUP_TIER_FACE_FROM_Z := -0.7
const WARMUP_TIER_FACE_TO_Z := 0.7

static var _fall_material: ShaderMaterial = null

## Water level per document sample (WaterGeometry.DRY where no water), and 1 where wet.
var levels: PackedFloat32Array = PackedFloat32Array()
var wet: PackedByteArray = PackedByteArray()
## Changes with every apply(), so a cached composition of `levels` knows it is stale.
var version: int = 0
## Microseconds of the last refresh's worker parts and its main-thread swap.
var last_build_usec: int = 0
var last_bake_usec: int = 0
var last_swap_usec: int = 0

var _document: MapDocument = null
var _task: int = -1
var _work: Dictionary = {}
var _pending: MapDocument = null
var _pending_bake: bool = true


## The water of `doc` with the document's own flow map: the nodes now, from `built`
## (WaterMeshBuilder.build(doc), which a loader's worker ran: AuthoredLoadPrep) or, when that
## is empty, from a build on the calling thread.
static func create(doc: MapDocument, built: Dictionary = {}) -> AuthoredWater:
	var water := AuthoredWater.new()
	water.name = NODE_NAME
	var geometry := built if not built.is_empty() else WaterMeshBuilder.build(doc)
	water.apply(geometry, doc.water_flow, doc.water_flow_size)
	return water


## The graphics warm-up's water map: 20 x 20 cells, flat, with a straight channel carved to
## -1 m along X (|x| <= 10 m, |z| <= 1.5 m) and a waist-deep river in it.
static func warmup_document() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and absf(p.y) <= 1.5:
				heights[doc.sample_index(x, z)] = -1.0
	doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(0, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5, 1.5])
	doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, -0.2))
	return doc


## The graphics warm-up's falls map: 20 x 20 cells, a tier one tier high over the far half
## (z below WARMUP_TIER_FACE_FROM_Z; the face runs to WARMUP_TIER_FACE_TO_Z, steeper than
## WaterFalls.FALL_FACE_SLOPE), and a waist river planned and carved down it along Z as the
## Water tool carves one (WaterEdit.plan_river, WaterCarve.river_goals): one fall at the brink,
## so WaterMeshBuilder.build() makes a curtain, a ring and mist with the real vertex layout.
static func warmup_falls_document() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	var heights := doc.heights.duplicate()
	var run := WARMUP_TIER_FACE_TO_Z - WARMUP_TIER_FACE_FROM_Z
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			var down := clampf((p.y - WARMUP_TIER_FACE_FROM_Z) / run, 0.0, 1.0)
			heights[doc.sample_index(x, z)] = doc.tier_height_m * (1.0 - down)
	doc.heights = heights
	var start := doc.heights.duplicate()
	var bodies := WaterEdit.plan_river(
		doc,
		PackedVector2Array([Vector2(0, -10), Vector2(0, 10)]),
		PackedFloat32Array([1.0, 1.0]),
		WaterBody.Depth.WAIST
	)
	var goals := WaterCarve.river_goals(doc, bodies, start)
	var rect: Rect2i = goals.rect
	var values: PackedFloat32Array = goals.goals
	var carved := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal := values[j * rect.size.x + i]
			var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
			if not is_inf(goal):
				carved[at] = minf(carved[at], goal)
	doc.heights = carved
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	return doc


## GraphicsWarmup samples: the merged water surface of warmup_document() and the falls of
## warmup_falls_document(), built by WaterMeshBuilder as a real map's are, each on a bare
## ShaderMaterial of its shader.
static func warmup_samples() -> Array[Dictionary]:
	var samples: Array[Dictionary] = [
		{
			"name": "water",
			"primitive": Mesh.PRIMITIVE_TRIANGLES,
			"arrays": WaterMeshBuilder.build(warmup_document())["arrays"],
			"material": GraphicsWarmup.material_for(WATER_SHADER),
			"multimesh": false,
		},
		{
			"name": "falls",
			"primitive": Mesh.PRIMITIVE_TRIANGLES,
			"arrays": WaterMeshBuilder.build(warmup_falls_document())["falls"],
			"material": GraphicsWarmup.material_for(FALLS_SHADER),
			"multimesh": false,
		},
	]
	return samples


func _ready() -> void:
	set_process(_task >= 0)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	_pending = null


## True when the map has any water surface.
func has_water() -> bool:
	return get_node_or_null(NodePath(WaterMeshBuilder.MESH_NAME)) != null


## The merged surface mesh, or null with no water.
func get_mesh_instance() -> MeshInstance3D:
	return get_node_or_null(NodePath(WaterMeshBuilder.MESH_NAME)) as MeshInstance3D


## The waterfalls mesh (curtains, foam rings, mist), or null with no fall.
func get_falls_instance() -> MeshInstance3D:
	return get_node_or_null(NodePath(WaterFallMesh.MESH_NAME)) as MeshInstance3D


## Replaces every child with the water `built` (WaterMeshBuilder.build()) and flow map
## `flow` (RG8, `flow_size` texels; empty for none). Tokens a replaced zone held are released
## quietly; the new zone picks them up again.
func apply(built: Dictionary, flow: PackedByteArray, flow_size: Vector2i) -> void:
	for child in get_children():
		if child is WaterZone:
			(child as WaterZone).release_bodies()
		remove_child(child)
		child.free()
	levels = built.get("levels", PackedFloat32Array())
	wet = built.get("wet", PackedByteArray())
	version += 1
	var arrays: Array = built.get("arrays", [])
	if not arrays.is_empty():
		add_child(_surface_mesh(arrays, flow, flow_size))
	var falls: Array = built.get("falls", [])
	if not falls.is_empty():
		add_child(_falls_mesh(falls, built.get("falls_aabb", AABB())))
	for body: Dictionary in built.get("bodies", []):
		add_child(WaterSurface.make_body("Surface_%d" % body.id, body.faces, body.floats))
		var zone := WaterZone.create_for_footprint("Zone_%d" % body.id, body.level, body.tiles)
		if zone != null:
			add_child(zone)


static func _surface_mesh(
	arrays: Array, flow: PackedByteArray, flow_size: Vector2i
) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# Only a carrier: process_water_meshes() lifts the emission texture onto the shared water
	# material and overrides this one.
	var material := StandardMaterial3D.new()
	if flow_size.x > 0 and flow_size.y > 0 and flow.size() == flow_size.x * flow_size.y * 2:
		material.emission_texture = ImageTexture.create_from_image(
			WaterFlowBaker.to_image(flow, flow_size)
		)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = WaterMeshBuilder.MESH_NAME
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(Constants.BOUNDS_EXEMPT_META, true)
	instance.set_meta(WaterGlbUtils.AUTHORED_META, true)
	return instance


## The waterfalls node (see the header): `arrays` from WaterFallMesh.build with its bounds
## `aabb` (grown for the packed mist) as the mesh's custom AABB.
static func _falls_mesh(arrays: Array, aabb: AABB) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if aabb.has_volume() or aabb.has_surface():
		mesh.custom_aabb = aabb
	mesh.surface_set_material(0, fall_material())
	var instance := MeshInstance3D.new()
	instance.name = WaterFallMesh.MESH_NAME
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.set_meta(Constants.BOUNDS_EXEMPT_META, true)
	return instance


## The one falls material every falls mesh shares (see the header), made on first use.
static func fall_material() -> ShaderMaterial:
	if _fall_material == null:
		_fall_material = ShaderMaterial.new()
		_fall_material.shader = FALLS_SHADER
		_fall_material.render_priority = FALLS_RENDER_PRIORITY
	return _fall_material


## Makes the falls material now, its shader built, so the first fall drawn costs its
## geometry alone (the Water tool calls it as it opens, as the Bridge tool warms the crossing
## materials). Idempotent: the same material every time.
static func warm_fall_material() -> ShaderMaterial:
	var material := fall_material()
	material.get_rid()
	return material


## The refresh entry for authoring tools after an edit to the document's water or to the
## ground under it (P4-3 carve, P4-4 water tool): the AuthoredWater under map root `root`
## (AuthoringEditor.map_root; created there if missing) rebuilds from `doc`
## (request_refresh()). Returns the node.
static func refresh_map(root: Node3D, doc: MapDocument, bake: bool = true) -> AuthoredWater:
	var water := root.get_node_or_null(NODE_NAME) as AuthoredWater
	if water == null:
		water = AuthoredWater.new()
		water.name = NODE_NAME
		root.add_child(water)
	water.request_refresh(doc, bake)
	return water


## Rebuilds the water from `doc` (see the header): geometry and, with `bake`, the flow map on
## a worker thread; the swap follows on a later frame (refreshed). Needs to be in the tree.
func request_refresh(doc: MapDocument, bake: bool = true) -> void:
	_document = doc
	var snapshot := WaterMeshBuilder.snapshot(doc)
	if _task >= 0:
		_pending_bake = bake if _pending == null else (_pending_bake or bake)
		_pending = snapshot
		return
	_start(snapshot, bake)


## True while a refresh is running or queued.
func is_refreshing() -> bool:
	return _task >= 0 or _pending != null


## Waits for every running and queued refresh and swaps each in (tests, the harness).
func finish_refresh() -> void:
	while _task >= 0:
		_finish_task()


func _process(_delta: float) -> void:
	if _task < 0:
		set_process(false)
		return
	if WorkerThreadPool.is_task_completed(_task):
		_finish_task()


func _start(snapshot: MapDocument, bake: bool) -> void:
	var work := {}
	_work = work
	_task = WorkerThreadPool.add_task(
		func() -> void: refresh_work(snapshot, bake, work), false, "AuthoredWater refresh"
	)
	set_process(true)


## Worker half of a refresh: WaterMeshBuilder.build() and, with `bake`, the flow map
## (none when there is no river). Touches no Node; results go into `out`.
static func refresh_work(snapshot: MapDocument, bake: bool, out: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	out["built"] = WaterMeshBuilder.build(snapshot)
	out["build_usec"] = Time.get_ticks_usec() - started
	out["bake"] = bake
	if not bake:
		return
	started = Time.get_ticks_usec()
	var has_river := false
	for body in snapshot.water_bodies:
		has_river = has_river or body.is_river()
	if has_river:
		out["flow_size"] = WaterFlowBaker.resolution_for(snapshot.extent_m())
		out["flow"] = WaterFlowBaker.bake(snapshot, out["flow_size"])
	else:
		out["flow_size"] = Vector2i.ZERO
		out["flow"] = PackedByteArray()
	out["bake_usec"] = Time.get_ticks_usec() - started


func _finish_task() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var work := _work
	_work = {}
	var started := Time.get_ticks_usec()
	last_build_usec = work.get("build_usec", 0)
	if work.get("bake", false):
		last_bake_usec = work.get("bake_usec", 0)
		if _document != null:
			_document.water_flow = work["flow"]
			_document.water_flow_size = work["flow_size"]
	var flow := _document.water_flow if _document != null else PackedByteArray()
	var flow_size := _document.water_flow_size if _document != null else Vector2i.ZERO
	apply(work["built"], flow, flow_size)
	var parent := get_parent()
	WaterGlbUtils.process_water_meshes(parent if parent != null else self)
	last_swap_usec = Time.get_ticks_usec() - started
	refreshed.emit()
	if _pending != null:
		var snapshot := _pending
		var bake := _pending_bake
		_pending = null
		_pending_bake = false
		_start(snapshot, bake)
