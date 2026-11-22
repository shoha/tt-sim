extends GutTest
## The bridge from the terraforming core to the map document (TerraBridge, card
## terraform-p2-bridge; docs/systems/terraform.md "The bridge"): the native strided diff and copy,
## the derive-to-document rect, the load's whole swap (the document's heights and the terrain's
## collision are the derive's ground), a new map made with the switch on (a terrain section, its
## heights the derive's, its record matching), and the switch off (a new map exactly as before).

## A small map (120 ft): the corpus scales to any extent, and the load stays quick.
const CELLS := Vector2i(24, 24)
const MAX_FRAMES := 600


func after_each() -> void:
	TerraCore.switch_override = null


func _map() -> MapDocument:
	var doc := MapDocument.create_flat(CELLS, "grass", "v", 3)
	doc.terra = TerraCorpus.build(CELLS).terra
	return doc


func _settle(s: TerraSession) -> bool:
	for i in MAX_FRAMES:
		if s.is_ready():
			return true
		await get_tree().process_frame
	return s.is_ready()


## The world (x, z) of document sample (a, b).
func _world(doc: MapDocument, a: int, b: int) -> Vector2:
	var ext := doc.extent_m()
	return Vector2(
		-ext.x * 0.5 + a * ext.x / (doc.samples_x() - 1),
		-ext.y * 0.5 + b * ext.y / (doc.samples_z() - 1)
	)


func test_doc_rect_takes_the_even_derive_samples() -> void:
	assert_eq(TerraBridge.doc_rect(Rect2i(3, 4, 6, 5)), Rect2i(2, 2, 3, 3))
	assert_eq(TerraBridge.doc_rect(Rect2i(0, 0, 1, 1)), Rect2i(0, 0, 1, 1))
	assert_eq(TerraBridge.doc_rect(Rect2i(1, 1, 1, 1)), Rect2i(1, 1, 0, 0), "an odd sample only")
	assert_eq(TerraBridge.doc_rect(Rect2i()), Rect2i())


func test_native_diff_and_copy() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var doc := _map()
	var derive := TerraCache.derive_for(doc.terra as TerraDoc, doc)
	var copy: PackedFloat32Array = derive.call("doc_heights")
	assert_eq(copy.size(), doc.sample_count(), "one height per document sample")
	var bytes: PackedByteArray = derive.call("array_bytes", "H2")
	var h2 := bytes.to_float32_array()
	var w := 2 * (doc.samples_x() - 1) + 1
	var strided := 0
	for b in doc.samples_z():
		for a in doc.samples_x():
			strided += 1 if copy[b * doc.samples_x() + a] != h2[2 * b * w + 2 * a] else 0
	assert_eq(strided, 0, "the copy is H2 at the even samples")
	var nx := doc.samples_x()
	var all := Rect2i(0, 0, nx, doc.samples_z())
	doc.heights = copy.duplicate()
	var same: Dictionary = derive.call("doc_heights_diff", doc.heights, nx, all)
	assert_false((same["rect"] as Rect2i).has_area(), "equal: an empty rect")
	doc.heights[7 * nx + 9] += 1.0
	doc.heights[11 * nx + 4] = -0.0 if copy[11 * nx + 4] == 0.0 else copy[11 * nx + 4] + 0.5
	var diff: Dictionary = derive.call("doc_heights_diff", doc.heights, nx, all)
	assert_eq(diff["rect"], Rect2i(4, 7, 6, 5), "the tight rect of the differing samples")
	var values: PackedFloat32Array = diff["values"]
	assert_eq(values.size(), 30)
	assert_eq(values[0 * 6 + 5], copy[7 * nx + 9], "the derive's value at the first change")
	var clipped: Dictionary = derive.call("doc_heights_diff", doc.heights, nx, Rect2i(0, 0, 8, 8))
	assert_eq(clipped["rect"], Rect2i(), "a rect without the changes")
	var bad: Dictionary = derive.call("doc_heights_diff", PackedFloat32Array([1.0]), nx, all)
	assert_true(bad.has("error"), "another grid is refused")


func test_the_load_swaps_in_the_derived_ground_and_its_collision() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	TerraCore.switch_override = true
	var doc := _map()
	var root := await MapSourceLoader.new(get_tree()).build_async("", doc)
	var s := root.get_node_or_null("TerraSession") as TerraSession
	assert_not_null(s, "a session")
	if s == null:
		root.free()
		return
	assert_true(s.is_ready(), "the load waited for the attach")
	assert_not_null(s.bridge, "the session has its bridge")
	assert_eq(doc.heights, s.settled_derive().call("doc_heights"), "the bridge law after the load")
	var terrain := root.get_node("AuthoredTerrain") as AuthoredTerrain
	var collision := terrain.find_child("TerrainCollision", true, false) as TerrainCollision
	assert_not_null(collision, "the terrain has its collision")
	if collision != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1234
		var off := 0
		for k in 200:
			var a := rng.randi_range(0, doc.samples_x() - 1)
			var b := rng.randi_range(0, doc.samples_z() - 1)
			var p := _world(doc, a, b)
			off += 1 if absf(collision.height_at_sample(a, b) - s.height_at(p.x, p.y)) > 1e-4 else 0
		assert_eq(off, 0, "the collision is the derived ground at 200 random samples")
	root.free()


func test_a_new_map_with_the_switch_on_has_a_section() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var spec := {"size_ft": 100, "seed": 1234, "landform": StartingLandform.FLAT}
	TerraCore.switch_override = false
	var off := NewMapBuild.start(spec, PaletteLibrary.DEFAULT_ROOT, false).finish()
	assert_null(off.terra, "switch off: no section")
	TerraCore.switch_override = true
	var on := NewMapBuild.start(spec, PaletteLibrary.DEFAULT_ROOT, false).finish()
	assert_not_null(on.terra, "switch on: a section")
	if on.terra == null:
		return
	var terra := on.terra as TerraDoc
	assert_eq(terra.prims.size(), 1, "one plane")
	var fresh := TerraCache.derive_for(terra, on)
	assert_eq(on.heights, fresh.call("doc_heights"), "the heights are the derive's")
	assert_true(TerraCache.key_matches(terra.derived, terra, on), "the record matches")
	assert_eq(on.heights.size(), off.heights.size(), "the same grid")
