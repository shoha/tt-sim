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
## TerraSession.apply (async); its `settled` lands with land(false), heights then water. The water
## half (bodies and the pond mask, water_of) is card terraform-p2-bridge-water's; here it is a
## stub that writes nothing.

## Microseconds and samples of the last land(), by part (the held-stroke budget's timers): the
## native diff, the row writes, the queue, and the samples written.
var last_diff_usec := 0
var last_write_usec := 0
var last_queue_usec := 0
var last_samples := 0
## Landings that wrote heights (tests).
var landings := 0

var session: TerraSession = null
var _editor: WeakRef = null


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


## A held frame of a gesture: the edit through TerraSession.apply_held and, when it derived at
## once, land(true). Returns the edit's id, or -1 when refused.
func held(edit: Dictionary) -> int:
	var id := session.apply_held(edit)
	if id >= 0 and session.is_ready():
		land(true)
	return id


## Writes what the landed derives changed into the document: the heights (heights_only) and,
## unless `is_held`, the water (water_of; a stub until card 2). Returns the document rect written.
func land(is_held: bool) -> Rect2i:
	var rect := heights_only()
	if rect.has_area():
		_queue(rect, is_held)
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


## The document's water as the derive solves it (bodies and pond mask): card
## terraform-p2-bridge-water. A stub here: {}.
static func water_of(_derive: RefCounted) -> Dictionary:
	return {}


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
## plane at the document's centre height, derived in full, and the whole height array swapped
## for the derive's before any terrain is built, with the derived record made so the load's
## check matches. Until card terraform-p2-landforms the landform's own heights are not carried
## over (its features stay in the document as they are). Returns false without the library.
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
	return true


func _on_settled() -> void:
	land(false)


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
