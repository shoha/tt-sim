extends GutTest

## FireField's placement (pure plan_block): deterministic, each lattice point in one block
## only, nothing below the ember band, nothing on wet or steep ground, heights from the
## document's triangles; the bands; and the map-wide cap the drawn field keeps.


func _doc(cells: int = 20, heat: int = 255) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(cells, cells), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	mask.fill(heat)
	doc.fire_mask = mask
	return doc


func test_the_plan_is_deterministic_and_burns_where_painted() -> void:
	var doc := _doc()
	var plan := FireField.plan_block(doc, Vector2i(1, 1))
	assert_gt(plan.size(), 0)
	assert_eq(plan.size() % FireField.STRIDE, 0)
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)), plan, "the same plan every time")
	var other := _doc()
	other.map_seed = 6
	assert_ne(FireField.plan_block(other, Vector2i(1, 1)), plan, "another seed, another plan")
	for k in plan.size() / FireField.STRIDE:
		assert_almost_eq(plan[k * FireField.STRIDE + 3], 1.0, 0.001, "full intensity")


func test_blocks_share_no_flame() -> void:
	var doc := _doc()
	var seen := {}
	var total := 0
	for block in FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z())):
		var plan := FireField.plan_block(doc, block)
		for k in plan.size() / FireField.STRIDE:
			var key := Vector2(plan[k * FireField.STRIDE], plan[k * FireField.STRIDE + 2])
			assert_false(seen.has(key), "a flame belongs to one block")
			seen[key] = true
			total += 1
	# About one flame per FLAME_SPACING_M square over the whole map.
	var expected := doc.extent_m().x * doc.extent_m().y / pow(FireField.FLAME_SPACING_M, 2)
	assert_almost_eq(float(total), expected, expected * 0.1)


func test_nothing_burns_below_the_ember_band_or_without_a_mask() -> void:
	assert_eq(FireField.plan_block(_doc(20, FireField.EMBER_MIN - 1), Vector2i(1, 1)).size(), 0)
	assert_gt(FireField.plan_block(_doc(20, FireField.EMBER_MIN), Vector2i(1, 1)).size(), 0)
	var doc := _doc()
	doc.fire_mask = PackedByteArray()
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0)


func test_wet_ground_does_not_burn() -> void:
	var doc := _doc()
	var dressing := PackedByteArray()
	dressing.resize(doc.sample_count() * 4)
	for i in doc.sample_count():
		dressing[i * 4 + 3] = 255
	doc.water_dressing = dressing
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0)
	for i in doc.sample_count():
		dressing[i * 4 + 3] = FireField.WET_LINE_MIN - 1
	doc.water_dressing = dressing
	assert_gt(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0, "a damp shore still burns")


func test_steep_ground_does_not_burn_and_flames_stand_on_the_ground() -> void:
	var doc := _doc()
	var step := doc.sample_step().x
	var steep := doc.heights.duplicate()
	var gentle := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			steep[doc.sample_index(x, z)] = x * step * 2.0
			gentle[doc.sample_index(x, z)] = x * step * 0.2
	doc.heights = steep
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0, "a 63 degree face")
	doc.heights = gentle
	var plan := FireField.plan_block(doc, Vector2i(1, 1))
	assert_gt(plan.size(), 0, "an 11 degree slope burns")
	var half := doc.extent_m().x * 0.5
	for k in plan.size() / FireField.STRIDE:
		var x := plan[k * FireField.STRIDE]
		var y := plan[k * FireField.STRIDE + 1]
		assert_almost_eq(y, (x + half) * 0.2, 0.01, "on the ground")


func test_bands() -> void:
	assert_eq(FireField.band(0), 0)
	assert_eq(FireField.band(FireField.EMBER_MIN - 1), 0)
	assert_eq(FireField.band(FireField.EMBER_MIN), 1)
	assert_eq(FireField.band(FireBrush.EMBERS), 1, "the Embers tile is embers")
	assert_eq(FireField.band(FireBrush.FLAMES), 2, "the Flames tile is flames")
	assert_eq(FireField.band(FireBrush.BLAZE), 3, "the Blaze tile is a blaze")
	assert_lt(FireField.card_height(FireBrush.EMBERS / 255.0), FireField.card_height(1.0))


func test_thin_keeps_an_even_share() -> void:
	var plan := PackedFloat32Array()
	for k in 10:
		plan.append_array([k, 0, 0, 1, 0])
	var kept := FireField.thin(plan, 5)
	assert_eq(kept.size(), 5 * FireField.STRIDE)
	assert_eq(kept[0], 0.0)
	assert_eq(kept[FireField.STRIDE], 2.0, "every other one")
	assert_eq(FireField.thin(plan, 20), plan)


func test_the_field_keeps_the_map_wide_cap() -> void:
	var doc := _doc(40)
	var field := FireField.create(doc)
	add_child_autofree(field)
	assert_eq(field.flame_count(), FireField.MAX_FLAMES, "a whole 40-cell map at the cap")
	var mask := doc.fire_mask.duplicate()
	mask.fill(0)
	doc.fire_mask = mask
	field.rebuild()
	assert_eq(field.flame_count(), 0)
	assert_eq(field.get_child_count(), 0, "no chunk without fire")
