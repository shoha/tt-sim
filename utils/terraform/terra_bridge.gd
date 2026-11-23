class_name TerraBridge
extends RefCounted
## The bridge from the terraforming core to today's map document (card terraform-p2-bridge;
## docs/systems/terraform.md "The bridge"): whenever a TerraSession's derive lands, the derived
## ground H2 is written into MapDocument.heights at the document's samples (every second derive
## sample), so the game's own consumers (chunks, collision, skirt, shade field, scatter, tokens)
## build from the derive unchanged. With the switch on, on a map with a terrain section, nothing
## else writes those heights (the bridge law, test_terra_bridge_law.gd).
##
## How. The session says where its derives changed H2 (take_changed(), derive samples); the
## bridge halves that rect to document samples, asks the derive for the tight rect whose bits
## differ (TerraDerive.doc_heights_diff: a strided compare in C++) and writes that rect row by
## row into the document's array in place, the per-sample cost of today's sculpt dab. The whole
## array is swapped (swap_heights) only before the terrain is built (a new map, the load), since
## AuthoredTerrain and the painter keep references to it. The written rect then goes to the
## authoring editor's height queue (HeightEditor.external_rect while a gesture holds, else
## queue_heights and work) or, without an editor, straight to the map's AuthoredTerrain (chunks
## and collision).
##
## When. A held frame calls held(edit): TerraSession.apply_held derives synchronously when
## nothing is in flight, then land(true) writes the heights only. Every other edit goes through
## TerraSession.apply (async); its `settled` lands with land(false), heights then water.
##
## Water (card terraform-p2-bridge-water). The derive's water records and falls become today's
## bodies and pond mask (TerraWaterBridge.bodies; water_of), written only when their signature
## (TerraWaterBridge.signature) changes and never on a held frame, so a sculpt stroke that moves
## no water costs one hash at its release. The load swaps them in with the heights (swap_water,
## before the water is built); a landing hands the changed region to the authoring editor's
## WaterEditor.land_external (the wet dressing, the surface, wet rocks, the followers and the
## regrowth, as a carve lands; its record is last_water_record) or, without an editor, refreshes
## the map's dressing and AuthoredWater itself. A body list past a cap is refused (warned, the
## document's water left as it was), never truncated.
##
## Never blocking (card terraform-p2-river-release; at once a river release cost 81-108 ms of one
## frame). With an authoring editor the landing is spread: the written rect goes to the height
## queue within the frame budgets (HeightEditor.work(), drained by its step()), and the water
## conversion (TerraWaterBridge.bodies and region, about 30 ms at 320 ft) runs on a worker over a
## snapshot (_start_water), written and handed to land_external by step() once the task is done.
## TerraEditor lands a gesture's ground only after both (its _ground_busy), so everything lands in
## stage order; finish_water() lands a conversion at once (finish_work, the load), and a bridge
## freed meanwhile parks its task with TerraSession's reaper. Without an editor (play, tests of
## the bridge alone) the water is converted and landed at once, as before.

## Microseconds and samples of the last land(), by part (the held-stroke budget's timers): the
## native diff, the row writes, the queue, and the samples written.
var last_diff_usec := 0
var last_write_usec := 0
var last_queue_usec := 0
var last_samples := 0
## Landings that wrote heights (tests).
var landings := 0
## Landings that wrote water, and the microseconds of the last one's conversion and write.
var water_landings := 0
var last_water_usec := 0
## Why the last water conversion was refused (a cap), or "".
var last_water_error := ""
## The record of the last water landing (WaterEditor.land_external fills it as it finishes:
## "water_before", "water_after", the dressing, props, kept rocks, followers, "region",
## "landed"), for the gesture whose edit moved the water; {} before any.
var last_water_record: Dictionary = {}
## Landings that wrote paint bytes, and the microseconds of the last one's read and write.
var paint_landings := 0
var last_paint_usec := 0
## Microseconds of the last held frame's session edit (TerraSession.apply_held: the synchronous
## derive when the session was free).
var last_held_usec := 0

var session: TerraSession = null
var _editor: WeakRef = null
## TerraWaterBridge.signature of the water last written (or refused).
var _water_sig := PackedByteArray()
## The water conversion on its worker (_start_water), or {}: {"task", "result"}.
var _water_job: Dictionary = {}
## True when the last surfaces_only() rewrote MapDocument.surface_ids.
var _ids_moved := false


## Attaches the bridge to `p_session` (session.bridge is set) and, when given, the authoring
## editor whose height queue takes the written rects (an AuthoringEditor; set_editor() later).
func attach(p_session: TerraSession, editor: Object = null) -> void:
	session = p_session
	session.bridge = self
	set_editor(editor)
	if not session.settled.is_connected(_on_settled):
		session.settled.connect(_on_settled)


## The authoring editor the written rects go to (an AuthoringEditor), or null for the terrain.
func set_editor(editor: Object) -> void:
	_editor = weakref(editor) if editor != null else null


## Replaces the whole document height array with the settled derive's (TerraDerive.doc_heights)
## and forgets the changed rect. Only before the terrain is built (see the header). False while
## the session is not ready.
func swap_heights() -> bool:
	var derive := session.settled_derive() if session != null else null
	if derive == null:
		return false
	session.doc.heights = derive.call("doc_heights")
	session.take_changed()
	swap_surfaces(session.doc, derive)
	session.take_paint_changed()
	return true


## Replaces `doc`'s painted surfaces with `derive`'s paint planes at the document samples and its
## surface table (card terraform-p2-paint-path): surface_ids is the terrain document's table,
## surface_weights the planes (empty while the table is). Only before the terrain is built.
static func swap_surfaces(doc: MapDocument, derive: RefCounted) -> void:
	var terra := doc.terra as TerraDoc
	if terra == null:
		return
	doc.surface_ids = terra.surfaces.duplicate()
	if terra.surfaces.is_empty():
		doc.surface_weights = PackedByteArray()
	else:
		doc.surface_weights = derive.call("doc_surfaces", Rect2i())


## Writes the settled derive's water into the document (bodies and pond mask, water_of) with no
## landing: the load, before AuthoredLoadPrep builds the water from it. False while the session
## is not ready or when the conversion is refused (a cap; the document's water is left).
func swap_water() -> bool:
	finish_water()
	_write_water()
	return session != null and session.is_ready() and last_water_error == ""


## A held frame of a gesture: the edit through TerraSession.apply_held and, when it derived at
## once, land(true). Returns the edit's id, or -1 when refused.
func held(edit: Dictionary) -> int:
	var started := Time.get_ticks_usec()
	var id := session.apply_held(edit)
	last_held_usec = Time.get_ticks_usec() - started
	if id >= 0 and session.is_ready():
		land(true)
	return id


## Writes what the landed derives changed into the document: the heights (heights_only) and,
## unless `is_held`, the water when its signature moved (water_of), then lands it: with an
## authoring editor the conversion runs on a worker and lands from step() (see the header).
## Returns the document rect of the heights written.
func land(is_held: bool) -> Rect2i:
	var rect := heights_only()
	if rect.has_area():
		_queue(rect, is_held)
	var painted := surfaces_only()
	if painted.has_area() or _ids_moved:
		_land_paint(painted, is_held)
	if not is_held:
		if _editor_now() != null:
			_start_water()
		else:
			var water := _write_water()
			if not water.is_empty():
				_land_water(water)
	return rect


## True while a water conversion runs on its worker (land(); step() or finish_water() lands it).
func water_pending() -> bool:
	return not _water_job.is_empty()


## One frame (TerraEditor.step): lands the water conversion once its worker has finished. Never
## waits.
func step() -> void:
	if _water_job.is_empty() or not WorkerThreadPool.is_task_completed(int(_water_job.task)):
		return
	_land_job()


## Lands the water conversion in flight at once, waiting for its worker (TerraEditor.finish_work,
## the next stage's land(), the load).
func finish_water() -> void:
	if not _water_job.is_empty():
		_land_job()


## The heights half of land(): diffs the changed rect and writes the tight rect into
## MapDocument.heights in place. Returns the document rect written (empty when nothing differed or
## the session is not ready).
func heights_only() -> Rect2i:
	last_diff_usec = 0
	last_write_usec = 0
	last_queue_usec = 0
	last_samples = 0
	var derive := session.settled_derive() if session != null else null
	if derive == null:
		return Rect2i()
	var changed := session.take_changed()
	if not changed.has_area():
		return Rect2i()
	var doc := session.doc
	var nx := doc.samples_x()
	var started := Time.get_ticks_usec()
	var diff: Dictionary = derive.call(
		"doc_heights_diff", doc.heights, nx, TerraBridge.doc_rect(changed)
	)
	last_diff_usec = Time.get_ticks_usec() - started
	var rect: Rect2i = diff.get("rect", Rect2i())
	if diff.has("error"):
		push_warning("TerraBridge: %s" % diff["error"])
		return Rect2i()
	if not rect.has_area():
		return rect
	started = Time.get_ticks_usec()
	var values: PackedFloat32Array = diff["values"]
	# Packed arrays are shared by reference: this writes the document's own array.
	var heights := doc.heights
	var k := 0
	for z in range(rect.position.y, rect.end.y):
		var row := z * nx
		for x in range(rect.position.x, rect.end.x):
			heights[row + x] = values[k]
			k += 1
	last_write_usec = Time.get_ticks_usec() - started
	last_samples = k
	landings += 1
	return rect


## The paint half of land() (card terraform-p2-paint-path): the surface table into
## MapDocument.surface_ids when it moved, then the paint planes over the document rect the landed
## derives changed (TerraSession.take_paint_changed, halved), written row by row in place
## (SurfaceStroke.write_block skips the rows already equal). Returns the document rect whose bytes
## changed (empty when none); _ids_moved says whether the table did.
func surfaces_only() -> Rect2i:
	_ids_moved = false
	var derive := session.settled_derive() if session != null else null
	if derive == null or session.terra == null:
		return Rect2i()
	var doc := session.doc
	var table := session.terra.surfaces
	if doc.surface_ids != table:
		doc.surface_ids = table.duplicate()
		_ids_moved = true
	var changed := TerraBridge.doc_rect(session.take_paint_changed())
	if table.is_empty() and doc.surface_weights.is_empty():
		return Rect2i()
	if doc.surface_weights.size() != doc.sample_count() * MapDocument.SURFACE_BYTES:
		# The first paint of the map: the whole planes (a new array, as SurfaceStroke.begin does).
		doc.surface_weights = derive.call("doc_surfaces", Rect2i())
		return Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	if not changed.has_area():
		return Rect2i()
	var started := Time.get_ticks_usec()
	var bytes: PackedByteArray = derive.call("doc_surfaces", changed)
	var before := SurfaceStroke.read_block(doc, doc.surface_weights, changed)
	if bytes == before:
		return Rect2i()
	SurfaceStroke.write_block(doc, doc.surface_weights, changed, bytes)
	last_paint_usec = Time.get_ticks_usec() - started
	paint_landings += 1
	return changed


## The document's water as `derive` solves it on `doc`'s grid (TerraWaterBridge.bodies):
## {"bodies", "pond_mask"}, or {"error"} past a cap.
static func water_of(derive: RefCounted, doc: MapDocument) -> Dictionary:
	return TerraWaterBridge.bodies(derive.call("water_records"), derive.call("falls"), doc)


## The document samples (a, b) whose derive samples (2a, 2b) lie in `derive_rect`.
static func doc_rect(derive_rect: Rect2i) -> Rect2i:
	if not derive_rect.has_area():
		return Rect2i()
	var a0 := (derive_rect.position.x + 1) >> 1
	var b0 := (derive_rect.position.y + 1) >> 1
	var a1 := ((derive_rect.end.x - 1) >> 1) + 1
	var b1 := ((derive_rect.end.y - 1) >> 1) + 1
	return Rect2i(a0, b0, maxi(a1 - a0, 0), maxi(b1 - b0, 0))


## Gives a new map's document a terrain section (switch on; NewMapBuild, on its worker): one
## plane at the document's centre height, derived in full, and the whole height array and the
## water (none: the plane holds no water primitive) swapped for the derive's before any terrain
## is built, with the derived record made so the load's check matches. Until card
## terraform-p2-landforms the landform's own heights and water are not carried over (its other
## features stay in the document as they are). Returns false without the library.
static func seed_new_map(doc: MapDocument) -> bool:
	if doc == null or doc.heights.is_empty() or not TerraCore.native_available():
		return false
	var terra := TerraDoc.new()
	var centre := (doc.samples_z() / 2) * doc.samples_x() + doc.samples_x() / 2
	terra.add(TerraCore.PLANE, PackedFloat32Array([doc.heights[centre], 0.0, 0.0]))
	var derive := TerraCache.derive_for(terra, doc)
	if derive == null:
		return false
	doc.heights = derive.call("doc_heights")
	terra.derived = TerraCache.make_record(terra, doc, derive)
	doc.terra = terra
	swap_surfaces(doc, derive)
	var water := water_of(derive, doc)
	if not water.has("error"):
		doc.water_bodies = water["bodies"]
		doc.pond_mask = water["pond_mask"]
		doc.water_flow = PackedByteArray()
		doc.water_flow_size = Vector2i.ZERO
	return true


func _on_settled() -> void:
	land(false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _water_job.is_empty():
		# Abandoned (the map closed): the session's reaper lets the task go once it completes.
		TerraSession.park_task(int(_water_job.task))


func _editor_now() -> Object:
	return _editor.get_ref() if _editor != null else null


## The settled derive's water records and falls, with their signature, when it moved since the
## water last written ({} when unchanged or not ready); the signature is taken as written.
func _moved_water() -> Dictionary:
	var derive := session.settled_derive() if session != null else null
	if derive == null:
		return {}
	var doc := session.doc
	var records: Dictionary = derive.call("water_records")
	var falls: PackedFloat32Array = derive.call("falls")
	var sig := TerraWaterBridge.signature(records, falls, doc.terra as TerraDoc)
	if sig == _water_sig:
		return {}
	_water_sig = sig
	return {"records": records, "falls": falls}


## Converts and writes the settled derive's water when its signature moved, on this thread:
## {"region": the document samples the water changed over, "before": the water model before
## (WaterEdit.model_of)} or {} when nothing was written (unchanged, refused or not ready).
func _write_water() -> Dictionary:
	var started := Time.get_ticks_usec()
	var moved := _moved_water()
	if moved.is_empty():
		return {}
	var result := {}
	TerraBridge._convert(moved.records, moved.falls, session.doc, result)
	return _apply_water(result, Time.get_ticks_usec() - started)


## land()'s water with an authoring editor: the conversion of _write_water() on a worker over a
## snapshot (WaterMeshBuilder.snapshot, the terrain section copied), landed by step(). A conversion
## still in flight lands first, so the water lands in stage order (TerraEditor holds the next stage
## while one is pending, so this rarely waits).
func _start_water() -> void:
	finish_water()
	var moved := _moved_water()
	if moved.is_empty():
		return
	var doc := session.doc
	var snap := WaterMeshBuilder.snapshot(doc)
	snap.terra = (doc.terra as TerraDoc).duplicate() if doc.terra is TerraDoc else null
	var result := {}
	var run := TerraBridge._convert.bind(moved.records, moved.falls, snap, result)
	_water_job = {
		"task": WorkerThreadPool.add_task(run, false, "TerraBridge water"), "result": result
	}


## The conversion (pure, any thread): TerraWaterBridge.bodies of `records` and `falls` on `doc`'s
## grid and section and the region it changes against `doc`'s water, into `out` ({"bodies",
## "pond_mask", "region", "usec"} or {"error", "usec"}).
static func _convert(
	records: Dictionary, falls: PackedFloat32Array, doc: MapDocument, out: Dictionary
) -> void:
	var started := Time.get_ticks_usec()
	var water := TerraWaterBridge.bodies(records, falls, doc)
	if not water.has("error"):
		water["region"] = TerraWaterBridge.region(
			doc, doc.water_bodies, doc.pond_mask, water["bodies"], water["pond_mask"]
		)
	out.merge(water)
	out["usec"] = Time.get_ticks_usec() - started


## Waits for the worker's conversion (done by now from step()), writes it and lands it.
func _land_job() -> void:
	var job := _water_job
	_water_job = {}
	WorkerThreadPool.wait_for_task_completion(int(job.task))
	if session == null or not is_instance_valid(session):
		return
	var result: Dictionary = job.result
	var water := _apply_water(result, int(result.get("usec", 0)))
	if not water.is_empty():
		_land_water(water)


## Writes a conversion `result` (_convert) into the document; `usec` its cost so far. The
## _write_water() return.
func _apply_water(result: Dictionary, usec: int) -> Dictionary:
	if result.has("error"):
		last_water_error = String(result["error"])
		push_warning("TerraBridge: the derived water is refused: %s" % last_water_error)
		return {}
	var started := Time.get_ticks_usec()
	last_water_error = ""
	var doc := session.doc
	var bodies: Array[WaterBody] = result["bodies"]
	var mask: PackedByteArray = result["pond_mask"]
	var before := WaterEdit.model_of(doc)
	doc.water_bodies = bodies
	doc.pond_mask = mask
	water_landings += 1
	last_water_usec = usec + Time.get_ticks_usec() - started
	return {"region": result["region"], "before": before}


## Lands water _write_water() wrote: the authoring editor's WaterEditor.land_external (its
## record is last_water_record), else the map's dressing, ground layers and AuthoredWater.
func _land_water(water: Dictionary) -> void:
	var editor: Object = _editor.get_ref() if _editor != null else null
	var region: Rect2i = water["region"]
	if editor != null:
		last_water_record = {"water_before": water["before"]}
		var water_editor: WaterEditor = editor.get("water")
		water_editor.land_external(region, last_water_record)
		return
	if session == null or not is_instance_valid(session) or session.get_parent() == null:
		return
	var doc := session.doc
	doc.water_dressing = WaterDressing.refresh(doc)
	var terrain := _terrain()
	if terrain != null:
		terrain.refresh_water_dressing()
	var root := session.get_parent() as Node3D
	if root != null and (not doc.water_bodies.is_empty() or root.has_node(AuthoredWater.NODE_NAME)):
		AuthoredWater.refresh_map(root, doc)


## Hands the written rect on: the authoring editor's queue (an external stroke's frame while one
## is held), else the map's AuthoredTerrain directly (chunks now, collision at the release).
func _queue(rect: Rect2i, is_held: bool) -> void:
	var started := Time.get_ticks_usec()
	var editor: Object = _editor.get_ref() if _editor != null else null
	if editor != null:
		var heights: HeightEditor = editor.get("heights")
		if heights.is_external():
			heights.external_rect(rect)
		else:
			heights.queue_heights(rect)
			# Within the frame budgets; HeightEditor.step() drains the rest, and TerraEditor lands
			# the gesture's ground only once it has (card terraform-p2-river-release: at once it was
			# 40-59 ms of one frame).
			heights.work()
	else:
		var terrain := _terrain()
		if terrain != null:
			terrain.queue_heights(rect)
			terrain.mark_collision(rect)
			terrain.process_heights(-1)
			if not is_held:
				terrain.flush_collision()
				terrain.settle_heights()
	last_queue_usec = Time.get_ticks_usec() - started


## Hands a paint landing on: the authoring editor's Paint tool (TerraPaint.land: the ground's weight
## maps, and the scatter once released), else the map's AuthoredTerrain's weight maps.
func _land_paint(rect: Rect2i, is_held: bool) -> void:
	var editor: Object = _editor_now()
	var terra: Object = editor.get("terra") if editor != null else null
	if terra != null and terra.get("paint") != null:
		terra.get("paint").call("land", rect, is_held)
		return
	var terrain := _terrain()
	if terrain != null:
		terrain.update_ground_region(rect.grow(1) if rect.has_area() else Rect2i())


func _terrain() -> AuthoredTerrain:
	if session == null or not is_instance_valid(session) or session.get_parent() == null:
		return null
	return session.get_parent().get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
