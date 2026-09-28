class_name AuthoredLoadPrep
extends RefCounted

## The pure data an authored map's load needs before it can make its nodes, computed on
## worker threads while the main thread waits under the loading screen for the ground
## textures (MapSourceLoader._create_authored_root_async). Before P4b-0 all of it ran on the
## main thread inside two frames of the load (the wet dressing 114 ms, the water mesh 85 ms,
## the rule fields 24 ms, the skirt 33 ms and the chunk arrays on a 150 ft badlands map with
## five water bodies); the main thread now only makes the nodes and resources from it.
##
## Parts, one task each, reading the document only (no Node, no texture or other resource
## the renderer owns, so also safe under the headless dummy renderer, whose textures are not
## thread-safe: GlbUtils.threaded_loads_safe). Each task writes its own Dictionary; finish()
## merges them on the main thread:
##   DRESSING         WaterDressing.field_of (AuthoredTerrain stores it in the document)
##   WATER            WaterMeshBuilder.build (AuthoredWater's geometry), only with water
##   FIELDS, CHUNKS   TerrainMeshBuilder.grid_fields, then every chunk's mesh arrays with them
##   SKIRT            TerrainMeshBuilder.build_skirt_arrays
##   CROSSINGS        CrossingGeometry.build (AuthoredCrossings' geometry), only with crossings
## Summary: docs/ARCHITECTURE.md Map Loading Flow.

const DRESSING := "dressing"
const WATER := "water"
const FIELDS := "fields"
const CHUNKS := "chunks"
const SKIRT := "skirt"
const CROSSINGS := "crossings"

var _tasks: PackedInt64Array = PackedInt64Array()
var _outs: Array[Dictionary] = []


## Starts the tasks for `doc`, which must not change until finish().
static func start(doc: MapDocument) -> AuthoredLoadPrep:
	var prep := AuthoredLoadPrep.new()
	var parts: Array[String] = [DRESSING, FIELDS, SKIRT]
	if not doc.water_bodies.is_empty():
		parts.append(WATER)
	if not doc.crossings.is_empty():
		parts.append(CROSSINGS)
	for part in parts:
		var out := {}
		prep._outs.append(out)
		prep._tasks.append(
			WorkerThreadPool.add_task(
				func() -> void: work(doc, part, out), false, "AuthoredLoadPrep " + part
			)
		)
	return prep


## True when every task has finished.
func is_done() -> bool:
	for task in _tasks:
		if not WorkerThreadPool.is_task_completed(task):
			return false
	return true


## Waits for every task and returns the parts merged ({} after the first call).
func finish() -> Dictionary:
	for task in _tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	_tasks = PackedInt64Array()
	var merged := {}
	for out in _outs:
		merged.merge(out)
	_outs.clear()
	return merged


## Everything start() and finish() would give, on the calling thread (tests).
static func compute(doc: MapDocument) -> Dictionary:
	var out := {}
	for part in [DRESSING, FIELDS, SKIRT, WATER, CROSSINGS]:
		if part == WATER and doc.water_bodies.is_empty():
			continue
		if part == CROSSINGS and doc.crossings.is_empty():
			continue
		work(doc, part, out)
	return out


## One part (see the header) into `out`. Touches no Node.
static func work(doc: MapDocument, part: String, out: Dictionary) -> void:
	match part:
		DRESSING:
			out[DRESSING] = WaterDressing.field_of(doc)
		WATER:
			out[WATER] = WaterMeshBuilder.build(doc)
		CROSSINGS:
			out[CROSSINGS] = CrossingGeometry.build(doc)
		FIELDS:
			var fields := TerrainMeshBuilder.grid_fields(doc)
			var chunks := {}
			for cell in TerrainMeshBuilder.chunk_cells(doc):
				chunks[cell] = TerrainMeshBuilder.build_chunk_arrays(doc, cell, fields)
			out[FIELDS] = fields
			out[CHUNKS] = chunks
		SKIRT:
			out[SKIRT] = TerrainMeshBuilder.build_skirt_arrays(
				doc, AuthoredTerrain.skirt_width_m(), AuthoredTerrain.SKIRT_FADE_M
			)
