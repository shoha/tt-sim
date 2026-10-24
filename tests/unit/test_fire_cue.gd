extends GutTest

## The drag ruler's "In fire" cue (card F7; design section 5): DragRuler.in_fire is a pure lookup
## of the drop point in the document's fire mask at the flames band or above. Inside a fire it
## says so, outside or in the ember band it does not, the map's edge reads the edge sample and
## past it nothing burns, and a map with no fire or no document is never in fire. The label adds
## the cue after its other parts, in their form.

const CELL := 1.524


## A flat 40-cell map burning in a disc of `radius` metres at `centre` with mask byte `heat`.
func _doc(centre: Vector2, radius: float, heat: int) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	var half := doc.extent_m() * 0.5
	var step := doc.sample_step()
	for iz in doc.samples_z():
		for ix in doc.samples_x():
			if (-half + Vector2(ix, iz) * step).distance_to(centre) <= radius:
				mask[doc.sample_index(ix, iz)] = heat
	doc.fire_mask = mask
	return doc


func test_a_drop_inside_a_fire_is_in_fire() -> void:
	var doc := _doc(Vector2(5.0, -3.0), 4.0, FireField.FLAME_MIN)
	assert_true(DragRuler.in_fire(doc, Vector2(5.0, -3.0)), "the fire's middle")
	assert_true(DragRuler.in_fire(doc, Vector2(7.0, -2.0)), "inside its edge")


func test_a_drop_outside_a_fire_is_not() -> void:
	var doc := _doc(Vector2(5.0, -3.0), 4.0, 255)
	assert_false(DragRuler.in_fire(doc, Vector2(-10.0, 8.0)), "far from it")
	assert_false(DragRuler.in_fire(doc, Vector2(11.0, -3.0)), "past its edge")


func test_the_ember_band_is_not_counted() -> void:
	var embers := _doc(Vector2.ZERO, 6.0, FireField.FLAME_MIN - 1)
	assert_false(DragRuler.in_fire(embers, Vector2.ZERO), "embers only glow")
	var low := _doc(Vector2.ZERO, 6.0, FireField.EMBER_MIN)
	assert_false(DragRuler.in_fire(low, Vector2.ZERO))
	var flames := _doc(Vector2.ZERO, 6.0, FireField.FLAME_MIN)
	assert_true(DragRuler.in_fire(flames, Vector2.ZERO), "the flames band's first byte counts")


func test_the_map_edge_reads_the_edge_and_nothing_burns_past_it() -> void:
	var doc := _doc(Vector2.ZERO, 1000.0, 255)
	var half := doc.extent_m() * 0.5
	assert_true(DragRuler.in_fire(doc, half), "the corner sample")
	assert_true(DragRuler.in_fire(doc, Vector2(-half.x, 0.0)), "the west edge")
	assert_false(DragRuler.in_fire(doc, half + Vector2(0.01, 0.0)), "just off the map")
	assert_false(DragRuler.in_fire(doc, Vector2(0.0, -half.y - 3.0)), "off the north edge")


func test_no_fire_or_no_document_is_never_in_fire() -> void:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 5)
	assert_true(doc.fire_mask.is_empty(), "a new map has no fire mask")
	assert_false(DragRuler.in_fire(doc, Vector2.ZERO))
	assert_false(DragRuler.in_fire(null, Vector2.ZERO))
	var wrong := _doc(Vector2.ZERO, 6.0, 255)
	wrong.fire_mask = PackedByteArray([255, 255, 255])
	assert_false(DragRuler.in_fire(wrong, Vector2.ZERO), "a mask of the wrong size is no fire")


func test_the_label_adds_the_cue_after_its_other_parts() -> void:
	var plain := DragRuler.ruler_text(3.0 * CELL, 0.0, CELL, 5.0, "ft", false, true)
	assert_eq(plain, "15 ft  |  In fire")
	var cell_snapped := DragRuler.ruler_text(3.0 * CELL, 0.0, CELL, 5.0, "ft", true, true)
	assert_eq(cell_snapped,"3 cells / 15 ft  |  In fire")
	var climb := DragRuler.ruler_text(3.0 * CELL, 2.0, CELL, 5.0, "ft", false, true)
	assert_true(climb.ends_with("direct  |  In fire"), climb)
	assert_eq(DragRuler.ruler_text(3.0 * CELL, 0.0, CELL, 5.0, "ft", false), "15 ft", "no cue")


func test_a_field_made_for_a_map_is_found_by_its_group() -> void:
	var doc := _doc(Vector2.ZERO, 4.0, 255)
	var field := FireField.create(doc)
	add_child_autofree(field)
	assert_eq(get_tree().get_first_node_in_group(FireField.GROUP), field)
