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

var session: TerraSession = null
var _editor: WeakRef = null
## TerraWaterBridge.signature of the water last written (or refused).
var _water_sig := PackedByteArray()


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
	return true


## Writes the settled derive's water into the document (bodies and pond mask, water_of) with no
## landing: the load, before AuthoredLoadPrep builds the water from it. False while the session
## is not ready or when the conversion is refused (a cap; the document's water is left).
func swap_water() -> bool:
	_write_water()
	return session != null and session.is_ready() and last_water_error == ""


## A held frame of a gesture: the edit through TerraSession.apply_held and, when it derived at
## once, land(true). Returns the edit's id, or -1 when refused.
func held(edit: Dictionary) -> int:
	var id := session.apply_held(edit)
	if id >= 0 and session.is_ready():
		land(true)
	return id


## Writes what the landed derives changed into the document: the heights (heights_only) and,
## unless `is_held`, the water when its signature moved (water_of), then lands it. Returns the
## document rect of the heights written.
func land(is_held: bool) -> Rect2i:
	var rect := heights_only()
	if rect.has_area():
		_queue(rect, is_held)
	if not is_held:
		var water := _write_water()
		if not water.is_empty():
			_land_water(water)
	return rect


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
	var water := water_of(derive, doc)
	if not water.has("error"):
		doc.water_bodies = water["bodies"]
		doc.pond_mask = water["pond_mask"]
		doc.water_flow = PackedByteArray()
		doc.water_flow_size = Vector2i.ZERO
	return true


func _on_settled() -> void:
	land(false)


## Converts and writes the settled derive's water when its signature moved: {"region": the
## document samples the water changed over, "before": the water model before (WaterEdit.model_of)}
## or {} when nothing was written (unchanged, refused or not ready).
func _write_water() -> Dictionary:
	var derive := session.settled_derive() if session != null else null
	if derive == null:
		return {}
	var started := Time.get_ticks_usec()
	var doc := session.doc
	var records: Dictionary = derive.call("water_records")
	var falls: PackedFloat32Array = derive.call("falls")
	var sig := TerraWaterBridge.signature(records, falls, doc.terra as TerraDoc)
	if sig == _water_sig:
		return {}
	_water_sig = sig
	var water := TerraWaterBridge.bodies(records, falls, doc)
	if water.has("error"):
		last_water_error = String(water["error"])
		push_warning("TerraBridge: the derived water is refused: %s" % last_water_error)
		return {}
	last_water_error = ""
	var bodies: Array[WaterBody] = water["bodies"]
	var mask: PackedByteArray = water["pond_mask"]
	var region := TerraWaterBridge.region(doc, doc.water_bodies, doc.pond_mask, bodies, mask)
	var before := WaterEdit.model_of(doc)
	doc.water_bodies = bodies
	doc.pond_mask = mask
	water_landings += 1
	last_water_usec = Time.get_ticks_usec() - started
	return {"region": region, "before": before}


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
			heights.work(not is_held)
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


func _terrain() -> AuthoredTerrain:
	if session == null or not is_instance_valid(session) or session.get_parent() == null:
		return null
	return session.get_parent().get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
