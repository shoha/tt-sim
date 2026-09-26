extends GutTest

## MaskStroke (utils/mask_stroke.gd): brush strokes on a MapDocument's masks, the changed
## rectangles they report, and their diffs (undo, redo, cancel).

const FOREST := "temperate_forest_summer_s1"
const MEADOW := "alpine_meadow_summer_s1"


func _doc(base: bool = false) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 11)
	doc.has_base_map = base
	return doc


func _density_at(doc: MapDocument, world: Vector2) -> float:
	var s := doc.world_to_sample(world).round()
	return doc.biome_density[doc.sample_index(int(s.x), int(s.y))] / 255.0


func _slot_at(doc: MapDocument, world: Vector2) -> int:
	var s := doc.world_to_sample(world).round()
	return doc.biome_slots[doc.sample_index(int(s.x), int(s.y))]


func _paint(doc: MapDocument, biome: String, at: Vector2, radius: float, seconds: float) -> void:
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, biome)
	stroke.dab(at, at, radius, seconds)
	stroke.finish()


func _snapshot(doc: MapDocument) -> Dictionary:
	return {
		"ids": doc.biome_ids.duplicate(),
		"slots": doc.biome_slots.duplicate(),
		"density": doc.biome_density.duplicate(),
		"erase": doc.erase_mask.duplicate(),
	}


func test_paint_adds_the_biome_and_writes_a_soft_disc() -> void:
	var doc := _doc()
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	assert_eq(Array(doc.biome_ids), [FOREST], "added on first use")
	assert_eq(doc.biome_slots.size(), doc.sample_count(), "masks allocated")
	assert_true(stroke.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 0.5))
	var centre := _density_at(doc, Vector2.ZERO)
	var mid := _density_at(doc, Vector2(1.5, 0))
	var rim := _density_at(doc, Vector2(2.9, 0))
	assert_almost_eq(centre, MaskBrush.amount(1.0, 0.5), 0.01)
	assert_true(centre > mid and mid > rim, "falls off from the centre")
	assert_eq(_density_at(doc, Vector2(3.3, 0)), 0.0, "nothing past the radius")
	assert_eq(_slot_at(doc, Vector2.ZERO), 1)
	assert_eq(_slot_at(doc, Vector2(3.3, 0)), 0, "unpainted samples keep no slot")


func test_changed_rect_is_exactly_the_changed_samples() -> void:
	var doc := _doc()
	var before := doc.biome_density.duplicate()
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	stroke.dab(Vector2(2, -1), Vector2(4, -1), 2.0, 0.3)
	var rect := stroke.take_pending()
	assert_true(rect.has_area())
	var low := Vector2i(1 << 20, 1 << 20)
	var high := Vector2i(-1, -1)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var i := doc.sample_index(x, z)
			if doc.biome_density[i] != (before[i] if i < before.size() else 0):
				low = low.min(Vector2i(x, z))
				high = high.max(Vector2i(x, z))
	assert_eq(rect, Rect2i(low, high - low + Vector2i.ONE))
	assert_false(stroke.take_pending().has_area(), "taking clears it")


func test_repeated_strokes_approach_full_density_without_a_plateau() -> void:
	var doc := _doc()
	var previous_mid := 0.0
	for i in 12:
		_paint(doc, FOREST, Vector2.ZERO, 3.0, 0.3)
		var mid := _density_at(doc, Vector2(1.5, 0))
		assert_true(mid >= previous_mid)
		previous_mid = mid
	assert_gt(_density_at(doc, Vector2.ZERO), 0.97)
	assert_true(_density_at(doc, Vector2.ZERO) <= 1.0)
	assert_gt(previous_mid, 0.85, "the soft edge fills in on later strokes")


func test_a_new_biome_thins_the_old_one_lightly_and_replaces_it_firmly() -> void:
	var doc := _doc()
	_paint(doc, FOREST, Vector2.ZERO, 4.0, 3.0)
	var forest_before := _density_at(doc, Vector2(3.0, 0))
	# A light pass: the old biome only thins.
	_paint(doc, MEADOW, Vector2.ZERO, 4.0, 0.08)
	assert_eq(_slot_at(doc, Vector2.ZERO), 1, "forest keeps the sample under a light touch")
	assert_lt(_density_at(doc, Vector2.ZERO), 0.99)
	assert_eq(_slot_at(doc, Vector2(3.0, 0)), 1)
	assert_lt(_density_at(doc, Vector2(3.0, 0)), forest_before)
	# A firm pass: the new biome takes the core; the far rim stays forest.
	_paint(doc, MEADOW, Vector2.ZERO, 4.0, 2.0)
	assert_eq(_slot_at(doc, Vector2.ZERO), 2, "meadow owns the core")
	assert_gt(_density_at(doc, Vector2.ZERO), 0.9)
	assert_eq(_slot_at(doc, Vector2(3.7, 0)), 1, "the rim is still forest, thinned")


func test_thin_lowers_density_and_clear_empties_the_core() -> void:
	var doc := _doc()
	_paint(doc, FOREST, Vector2.ZERO, 5.0, 3.0)
	var full := _density_at(doc, Vector2.ZERO)
	var thin := MaskStroke.begin(doc, MaskBrush.THIN)
	thin.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 0.2)
	thin.finish()
	var thinned := _density_at(doc, Vector2.ZERO)
	assert_lt(thinned, full)
	assert_gt(thinned, 0.2, "thinning is gradual")
	assert_eq(_slot_at(doc, Vector2.ZERO), 1)
	var clear := MaskStroke.begin(doc, MaskBrush.CLEAR)
	clear.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 0.5)
	clear.finish()
	assert_eq(_density_at(doc, Vector2.ZERO), 0.0, "cleared completely")
	assert_eq(_slot_at(doc, Vector2.ZERO), 0)
	assert_gt(_density_at(doc, Vector2(4.2, 0)), 0.0, "outside the clear brush untouched")


func test_thin_on_an_unpainted_map_without_a_base_writes_nothing() -> void:
	var doc := _doc()
	var stroke := MaskStroke.begin(doc, MaskBrush.THIN)
	assert_false(stroke.writes_anything())
	assert_false(stroke.dab(Vector2.ZERO, Vector2.ZERO, 3.0, 1.0))
	assert_true(stroke.finish().is_empty())
	assert_true(doc.biome_slots.is_empty())
	assert_true(doc.erase_mask.is_empty())


func test_thin_on_a_base_map_erases_about_the_thinned_fraction() -> void:
	var doc := _doc(true)
	var stroke := MaskStroke.begin(doc, MaskBrush.THIN)
	assert_true(stroke.writes_anything())
	# A long exposure over a big brush: the core reaches a known thin amount.
	stroke.dab(Vector2.ZERO, Vector2.ZERO, 12.0, 0.25)
	stroke.finish()
	var expected := MaskBrush.amount(1.0, 0.25)
	var erased := 0
	var total := 0
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).length() < 2.0:
				total += 1
				if doc.erase_mask[doc.sample_index(x, z)] > MapDocument.ERASE_THRESHOLD:
					erased += 1
	assert_almost_eq(float(erased) / total, expected, 0.1, "stochastic erase ~ thin amount")
	var clear := MaskStroke.begin(doc, MaskBrush.CLEAR)
	clear.dab(Vector2.ZERO, Vector2.ZERO, 12.0, 1.0)
	clear.finish()
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).length() < 2.0:
				assert_true(doc.erase_mask[doc.sample_index(x, z)] > MapDocument.ERASE_THRESHOLD)


func test_undo_and_redo_restore_masks_exactly() -> void:
	var doc := _doc(true)
	_paint(doc, FOREST, Vector2(-3, 2), 4.0, 1.0)
	var before := _snapshot(doc)
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, MEADOW)
	stroke.dab(Vector2(-6, 0), Vector2(6, 1), 3.0, 0.4)
	stroke.dab(Vector2(6, 1), Vector2(6, 1), 3.0, 0.6)
	var diff := stroke.finish()
	var after := _snapshot(doc)
	assert_ne(after.density, before.density)
	assert_gt(int(diff.bytes), 0)
	var rect := MaskStroke.apply_diff(doc, diff, false)
	assert_true(rect.has_area())
	assert_eq(_snapshot(doc), before, "undo restores masks and the biome list")
	MaskStroke.apply_diff(doc, diff, true)
	assert_eq(_snapshot(doc), after, "redo restores the stroke")


func test_undo_of_the_first_stroke_frees_the_masks_it_allocated() -> void:
	var doc := _doc()
	var before := _snapshot(doc)
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	stroke.dab(Vector2.ZERO, Vector2.ZERO, 2.0, 0.5)
	var diff := stroke.finish()
	var after := _snapshot(doc)
	MaskStroke.apply_diff(doc, diff, false)
	assert_eq(_snapshot(doc), before)
	MaskStroke.apply_diff(doc, diff, true)
	assert_eq(_snapshot(doc), after)


func test_revert_cancels_a_stroke_in_progress() -> void:
	var doc := _doc(true)
	_paint(doc, FOREST, Vector2.ZERO, 3.0, 1.0)
	var before := _snapshot(doc)
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, MEADOW)
	stroke.dab(Vector2.ZERO, Vector2(5, 5), 4.0, 1.0)
	assert_true(stroke.revert().has_area())
	assert_eq(_snapshot(doc), before)


func test_a_stroke_that_changes_nothing_leaves_no_trace() -> void:
	var doc := _doc()
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	stroke.dab(Vector2(500, 500), Vector2(500, 500), 2.0, 1.0)
	assert_true(stroke.finish().is_empty())
	assert_true(doc.biome_ids.is_empty(), "the unused biome is not kept")
	assert_true(doc.biome_slots.is_empty(), "nor the masks it allocated")


func test_a_typical_stroke_diff_is_small() -> void:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 3)
	var stroke := MaskStroke.begin(doc, MaskBrush.PAINT, FOREST)
	var previous := Vector2(-15, 0)
	for i in 60:
		var point := Vector2(-15 + i * 0.5, sin(i * 0.1) * 3.0)
		stroke.dab(previous, point, 4.0, 1.0 / 60.0)
		previous = point
	var diff := stroke.finish()
	gut.p("30 m stroke, 4 m brush: %d bytes in %d blocks" % [diff.bytes, diff.blocks.size()])
	assert_lt(int(diff.bytes), 64 * 1024)
