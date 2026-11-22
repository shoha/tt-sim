extends GutTest
## The bridge law (docs/systems/terraform.md "The bridge"; card terraform-p2-bridge, the heights
## part): with the switch on, on a map with a terrain section, after every landing the document's
## heights equal the derive's ground at the document samples bit for bit (TerraDerive.doc_heights).
## Checked over a scripted 40-dab held raise through TerraBridge.held (TerraSession.apply_held, a
## synchronous derive per frame) across both corpus rivers, every frame, then a release through
## the async path, after which the terrain's collision is the derived ground under the stroke.
## Later cards add their gestures (and the water and paint parts) here.

const CELLS := Vector2i(24, 24)
const MAX_FRAMES := 600
const DABS := 40


func after_each() -> void:
	TerraCore.switch_override = null


func _settle(s: TerraSession) -> bool:
	for i in MAX_FRAMES:
		if s.is_ready():
			return true
		await get_tree().process_frame
	return s.is_ready()


## One raise dab (stroke kind 3) on the layout's line across both rivers, `k` of DABS.
func _dab(c: TerraCorpus, k: int) -> PackedFloat32Array:
	return c.dabs([[18.0 + k * 0.6, 20.0 + k * 0.25, 2.5, 0.08, 0]])


func _law(doc: MapDocument, s: TerraSession) -> bool:
	return doc.heights == s.settled_derive().call("doc_heights")


## The water half: the document's bodies (ids included) and pond mask are the derive's
## (TerraBridge.water_of).
func _water_law(doc: MapDocument, s: TerraSession) -> bool:
	var water := TerraBridge.water_of(s.settled_derive(), doc)
	if water.has("error"):
		return false
	var bodies: Array[WaterBody] = water["bodies"]
	if bodies.size() != doc.water_bodies.size():
		return false
	for k in bodies.size():
		var a := bodies[k]
		var b := doc.water_bodies[k]
		if a.id != b.id or not TerraWaterBridge.same(a, b):
			return false
	return water["pond_mask"] == doc.pond_mask


func test_a_held_raise_keeps_the_law_every_frame() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var c := TerraCorpus.build(CELLS)
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	doc.terra = c.terra
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	var s := root.get_node("TerraSession") as TerraSession
	var bridge := s.bridge as TerraBridge
	add_child(root)
	assert_true(_law(doc, s), "after the load")
	assert_true(_water_law(doc, s), "the water after the load")
	assert_gt(doc.water_bodies.size(), 10, "the load wrote the derived water")
	var id := s.apply({"op": "add", "kind": TerraCore.STROKE, "data": _dab(c, 0)})
	assert_gt(id, 0)
	assert_true(await _settle(s), "the press lands")
	assert_true(_law(doc, s), "after the press (async, settled)")
	assert_true(_water_law(doc, s), "the water after the press")
	var broken := 0
	var synchronous := 0
	var wrote := 0
	var water_landings := bridge.water_landings
	for k in range(1, DABS):
		var was := s.derives_landed
		assert_eq(bridge.held({"op": "append", "id": id, "data": _dab(c, k)}), id)
		synchronous += 1 if s.derives_landed == was + 1 and s.is_ready() else 0
		wrote += 1 if bridge.last_samples > 0 else 0
		broken += 0 if _law(doc, s) else 1
		await get_tree().process_frame
	assert_eq(synchronous, DABS - 1, "every held frame derived at once")
	assert_gt(wrote, DABS / 2, "the held frames wrote heights")
	assert_eq(broken, 0, "the law held on every frame")
	assert_eq(bridge.water_landings, water_landings, "no water written on a held frame")
	# The release: one more dab through the async path, landed by `settled`.
	var last := s.apply({"op": "append", "id": id, "data": _dab(c, DABS)})
	assert_eq(last, id)
	assert_true(await _settle(s), "the release lands")
	assert_true(_law(doc, s), "after the release")
	assert_true(_water_law(doc, s), "the water after the release")
	assert_gt(bridge.water_landings, water_landings, "the raise across the rivers moved the water")
	var terrain := root.get_node("AuthoredTerrain") as AuthoredTerrain
	var collision := terrain.find_child("TerrainCollision", true, false) as TerrainCollision
	var off := 0
	var nx := doc.samples_x()
	for b in doc.samples_z():
		for a in nx:
			off += 1 if collision.height_at_sample(a, b) != doc.heights[b * nx + a] else 0
	assert_eq(off, 0, "the collision is the bridged ground after the release")
	assert_eq(doc.heights, TerraCache.derive_for(c.terra, doc).call("doc_heights"), "equals a build")
	root.free()


## A pond added in authoring (the session's async path) lands through the editor:
## WaterEditor.land_external fills the bridge's water record, the water law holds, and the map's
## AuthoredWater and wet dressing follow; removing it lands the other way.
func test_a_pond_lands_through_the_water_editor() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var c := TerraCorpus.build(CELLS)
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	doc.terra = c.terra
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	add_child(root)
	var s := root.get_node("TerraSession") as TerraSession
	var bridge := s.bridge as TerraBridge
	var editor := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	bridge.set_editor(editor)
	var before := doc.water_bodies.size()
	var ring: Array = []
	for k in 10:
		var a := TAU * k / 10.0
		ring.append(12.0 + cos(a) * 3.0)
		ring.append(50.0 + sin(a) * 3.0)
	var id := s.apply({"op": "add", "kind": TerraCore.POND, "data": c.line([0.9], ring)})
	assert_gt(id, 0)
	assert_true(await _settle(s), "the pond lands")
	editor.finish_height_work()
	editor.water.finish_work()
	assert_eq(doc.water_bodies.size(), before + 1, "one more body")
	assert_true(_water_law(doc, s), "the water law after the add")
	var record := bridge.last_water_record
	assert_true(record.get("landed", false), "the editor's landing filled the record")
	assert_true((record.get("region", Rect2i()) as Rect2i).has_area(), "over the pond's region")
	assert_eq((record.get("water_after", {}) as Dictionary).get("bodies", []).size(), before + 1)
	var water := root.get_node_or_null(NodePath(AuthoredWater.NODE_NAME)) as AuthoredWater
	assert_not_null(water)
	var pond_id := doc.water_bodies[-1].id
	assert_gt(doc.pond_mask.count(pond_id), 50, "the pond's mask")
	var wet := 0
	for i in doc.water_dressing.size():
		wet += 1 if doc.water_dressing[i] != 0 else 0
	assert_gt(wet, 0, "the wet dressing follows")
	s.apply({"op": "remove", "id": id})
	assert_true(await _settle(s), "the removal lands")
	editor.finish_height_work()
	editor.water.finish_work()
	assert_eq(doc.water_bodies.size(), before, "the pond is gone")
	assert_true(_water_law(doc, s), "the water law after the removal")
	if water != null:
		water.finish_refresh()
	editor.water.release()
	root.free()
