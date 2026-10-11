extends GutTest

## The Fire tool's edit (FireEditor through AuthoringEditor.begin_fire_stroke): a lay is one
## "Lay fire" history entry of three strokes (the fire, the burnt forest only where forest
## stood, the ash), one undo puts every layer back and redo brings it again; a lay over a
## meadow leaves the meadow's biome alone; putting fire out is one plain entry that keeps the
## ash and the snags; ash refused (every paint slot holds paint) still lays the fire; a
## cancelled stroke leaves nothing. Uses the built-in palette (v7: burnt forest and ash).

const FOREST := "temperate_forest_summer_s1"
const MEADOW := "grassland_meadow_summer_s1"
## The forest is painted over x < 0, the meadow over x > 0 (world metres).
const FOREST_AT := Vector3(-5, 0, 0)
const MEADOW_AT := Vector3(5, 0, 0)


## Two biomes, their accents, the burnt forest and ash overflow the ground's eight layers on
## this small map; AuthoredTerrain warns and draws the extras as their neighbours, which is
## its own documented behaviour (test_ground_layers.gd), not this test's subject. Called at
## the end of each test that paints both biomes.
func _allow_layer_warnings() -> void:
	for e in get_errors():
		if "AuthoredTerrain:" in str(e.code) + str(e.rationale):
			e.handled = true


func _editor() -> AuthoringEditor:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 11)
	var root := MapSourceLoader.create_authored_root(doc)
	MapSourceLoader.add_fire_field(root, doc)
	add_child_autofree(root)
	var editor := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	_paint_biome(editor, FOREST, Vector3(-8, 0, -4), Vector3(-2, 0, 4))
	_paint_biome(editor, MEADOW, Vector3(2, 0, -4), Vector3(8, 0, 4))
	return editor


func _paint_biome(editor: AuthoringEditor, biome: String, from: Vector3, to: Vector3) -> void:
	assert_true(editor.begin_stroke(MaskBrush.PAINT, biome))
	for z in range(int(from.z), int(to.z) + 1):
		editor.stroke_dab(Vector3(from.x, 0, z), Vector3(to.x, 0, z), 2.0, 3.0)
	editor.end_stroke()


func _lay(editor: AuthoringEditor, from: Vector3, to: Vector3, erase := false) -> bool:
	assert_true(editor.begin_fire_stroke(1.0, erase))
	editor.stroke_dab(from, to, 2.0, 2.0)
	editor.flush()
	return editor.end_stroke()


func _fire_at(editor: AuthoringEditor, world: Vector3) -> int:
	var doc := editor.document
	if doc.fire_mask.size() != doc.sample_count():
		return 0
	var s := Vector2i(doc.world_to_sample(editor.to_map_xz(world)).round())
	return doc.fire_mask[doc.sample_index(s.x, s.y)]


func _biome_at(editor: AuthoringEditor, world: Vector3) -> String:
	var doc := editor.document
	var s := Vector2i(doc.world_to_sample(editor.to_map_xz(world)).round())
	var slot := doc.biome_slots[doc.sample_index(s.x, s.y)]
	return doc.biome_ids[slot - 1] if slot > 0 else ""


func _layers(doc: MapDocument) -> Array:
	return [
		doc.fire_mask.duplicate(),
		doc.biome_slots.duplicate(),
		doc.biome_density.duplicate(),
		doc.surface_ids.duplicate(),
		doc.surface_weights.duplicate(),
	]


func test_a_lay_is_one_entry_of_three_strokes_and_one_undo_takes_it_back() -> void:
	var editor := _editor()
	var doc := editor.document
	var burnt := FireSweep.burnt_biome(editor.palette_root)
	assert_ne(burnt, "", "the palette has the burnt forest")
	var before := _layers(doc)
	var count := editor.history.undo_count()
	assert_true(_lay(editor, FOREST_AT, MEADOW_AT))
	assert_eq(editor.history.undo_count(), count + 1, "one entry")
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq(entry.label, FireEditor.LAY_LABEL)
	assert_eq((entry.parts as Array).size(), 3, "fire, burnt forest, ash")
	assert_gt(_fire_at(editor, FOREST_AT), 200, "fire over the forest")
	assert_gt(_fire_at(editor, MEADOW_AT), 200, "fire over the meadow")
	assert_eq(_biome_at(editor, FOREST_AT), burnt, "the forest burnt to snags")
	assert_eq(_biome_at(editor, MEADOW_AT), MEADOW, "the meadow stays a meadow")
	var ash := doc.surface_ids.find("ash")
	assert_gt(ash, -1, "ash laid")
	var after := _layers(doc)
	assert_eq(editor.history.undo(), FireEditor.LAY_LABEL)
	assert_eq(_layers(doc), before, "one undo restores every layer")
	editor.history.redo()
	assert_eq(_layers(doc), after, "redo lays it all again")
	_allow_layer_warnings()


func test_a_lay_over_a_meadow_only_is_fire_and_ash() -> void:
	var editor := _editor()
	assert_true(_lay(editor, MEADOW_AT, MEADOW_AT + Vector3(1, 0, 0)))
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq((entry.parts as Array).size(), 2, "no forest to burn")
	assert_eq(_biome_at(editor, MEADOW_AT), MEADOW)


func test_putting_fire_out_keeps_the_ash_and_the_snags() -> void:
	var editor := _editor()
	var doc := editor.document
	assert_true(_lay(editor, FOREST_AT, MEADOW_AT))
	var slots := doc.biome_slots.duplicate()
	var density := doc.biome_density.duplicate()
	var weights := doc.surface_weights.duplicate()
	var hot := _fire_at(editor, FOREST_AT)
	assert_true(_lay(editor, FOREST_AT, FOREST_AT, true))
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq(entry.label, FireEditor.PUT_OUT_LABEL)
	assert_false(entry.has("parts"), "a plain entry")
	assert_lt(_fire_at(editor, FOREST_AT), hot / 4, "the fire is out under the brush")
	assert_gt(_fire_at(editor, MEADOW_AT), 200, "the rest still burns")
	assert_eq(doc.biome_slots, slots, "the snags stay")
	assert_eq(doc.biome_density, density)
	assert_eq(doc.surface_weights, weights, "the ash stays")
	editor.history.undo()
	assert_eq(_fire_at(editor, FOREST_AT), hot, "undo relights it")
	_allow_layer_warnings()


func test_ash_refused_still_lays_the_fire() -> void:
	var editor := _editor()
	var doc := editor.document
	var names: Array = []
	for surface in PaletteLibrary.surfaces(editor.palette_root):
		if not surface in ["ash", "dirt_peat"] and names.size() < MapDocument.MAX_SURFACES:
			names.append(surface)
	doc.surface_ids = PackedStringArray(names)
	var weights := PackedByteArray()
	weights.resize(doc.sample_count() * MapDocument.SURFACE_CHANNELS * 2)
	doc.surface_weights = weights
	for slot in names.size():
		doc.set_surface_weight(slot, slot, 40)
	assert_ne(editor.surface_refusal("ash"), "", "every slot holds paint")
	assert_true(_lay(editor, FOREST_AT, MEADOW_AT))
	var entry: Dictionary = editor.history.get("_undo").back()
	assert_eq((entry.parts as Array).size(), 2, "fire and burnt forest, no ash")
	assert_gt(_fire_at(editor, MEADOW_AT), 200, "the fire is laid")
	assert_false("ash" in doc.surface_ids)
	_allow_layer_warnings()


func test_a_cancelled_stroke_leaves_nothing() -> void:
	var editor := _editor()
	var doc := editor.document
	var count := editor.history.undo_count()
	assert_true(editor.begin_fire_stroke(1.0, false))
	editor.stroke_dab(FOREST_AT, MEADOW_AT, 2.0, 2.0)
	editor.flush()
	assert_gt(editor.fire_field.flame_count(), 0, "drawn while painting")
	editor.cancel_stroke()
	assert_true(doc.fire_mask.is_empty(), "the mask the stroke allocated is gone")
	assert_eq(editor.fire_field.flame_count(), 0)
	assert_eq(editor.history.undo_count(), count)


func test_forest_slots_are_the_dense_woods_only() -> void:
	var biomes := PaletteLibrary.biomes()
	var ids := PackedStringArray([FOREST, MEADOW, "burnt_forest_summer_s1", "no_such_biome"])
	var slots := FireEditor.forest_slots(ids, biomes)
	assert_eq(slots.size(), MapDocument.MAX_BIOMES + 1)
	assert_eq(slots[0], 0, "bare ground is not forest")
	assert_eq(slots[1], 1, "the temperate forest is")
	assert_eq(slots[2], 0, "a meadow is not")
	assert_eq(slots[3], 0, "the burnt forest never burns again")
	assert_eq(slots[4], 0, "an unknown biome is not")
