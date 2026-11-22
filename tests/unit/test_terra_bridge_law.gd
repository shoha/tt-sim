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
	var id := s.apply({"op": "add", "kind": TerraCore.STROKE, "data": _dab(c, 0)})
	assert_gt(id, 0)
	assert_true(await _settle(s), "the press lands")
	assert_true(_law(doc, s), "after the press (async, settled)")
	var broken := 0
	var synchronous := 0
	var wrote := 0
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
	# The release: one more dab through the async path, landed by `settled`.
	var last := s.apply({"op": "append", "id": id, "data": _dab(c, DABS)})
	assert_eq(last, id)
	assert_true(await _settle(s), "the release lands")
	assert_true(_law(doc, s), "after the release")
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
