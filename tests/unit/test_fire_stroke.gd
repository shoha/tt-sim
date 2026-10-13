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
	# Birch's ground (treecube 1c05fb0): a base whose rules and accents the forest shares.
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_birch", "v", 11)
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
	_allow_layer_warnings()


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
		if not surface in ["ash", "dirt_peat"] and names.size() < MapDocument.PAINT_SURFACE_LIMIT:
			names.append(surface)
	doc.surface_ids = PackedStringArray(names)
	var weights := PackedByteArray()
	weights.resize(doc.sample_count() * MapDocument.SURFACE_BYTES)
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


## [plants, rocks] of `scatter` within `radius` of the segment `from`-`to` (map XZ).
func _count(editor: AuthoringEditor, from: Vector2, to: Vector2, radius: float) -> Vector2i:
	var out := Vector2i.ZERO
	var rows_by_asset: Dictionary = editor.scatter.rows_by_asset()
	for asset_id in rows_by_asset:
		var role := ScatterGround.plan_role(editor.rule_for_asset(asset_id))
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		for r in flat.size() / MapDocument.ROW_STRIDE:
			var p := Vector2(flat[r * MapDocument.ROW_STRIDE], flat[r * MapDocument.ROW_STRIDE + 2])
			if Geometry2D.get_closest_point_to_segment(p, from, to).distance_to(p) > radius:
				continue
			if role == ScatterGround.ROLE_ROCK:
				out.y += 1
			elif ScatterGround.scorches(role):
				out.x += 1
	return out


func _settle(editor: AuthoringEditor) -> void:
	var frames := 0
	while editor.scatter.is_regenerating() and frames < 600:
		await get_tree().process_frame
		frames += 1
	assert_false(editor.scatter.is_regenerating(), "the scatter settled")


func test_a_lay_burns_away_the_plants_under_it_and_undo_brings_them_back() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 11)
	var root := MapSourceLoader.create_authored_root(doc)
	var scatter := AuthoredScatter.create()
	scatter.name = MapSourceLoader.SCATTER_NODE
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	root.add_child(scatter)
	MapSourceLoader.add_fire_field(root, doc)
	add_child_autofree(root)
	var editor := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	editor.scatter.attach_document(doc)
	_paint_biome(editor, MEADOW, Vector3(-8, 0, -6), Vector3(8, 0, 6))
	await _settle(editor)
	var from := Vector2(-5, 0)
	var to := Vector2(5, 0)
	# Well inside the fire's core, where the ash is full.
	var before := _count(editor, from, to, 1.0)
	assert_gt(before.x, 20, "grass and flowers grow there")
	assert_gt(before.y, 0, "and some stones")
	assert_true(_lay(editor, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y)))
	await _settle(editor)
	var after := _count(editor, from, to, 1.0)
	assert_eq(after.x, 0, "the plants under the fire are burnt away")
	assert_eq(after.y, before.y, "the rocks stay")
	assert_true(_lay(editor, Vector3(from.x, 0, from.y), Vector3(to.x, 0, to.y), true))
	await _settle(editor)
	assert_eq(_count(editor, from, to, 1.0).x, 0, "putting the fire out brings no plant back")
	editor.history.undo()
	editor.history.undo()
	await _settle(editor)
	assert_eq(_count(editor, from, to, 1.0), before, "undoing the lay brings them back")
	_allow_layer_warnings()


func test_ash_clears_small_plants_and_spares_rocks_trees_and_snags() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 3)
	doc.ensure_surface("ash")
	for i in doc.sample_count():
		doc.set_surface_weight(i, 0, 255)
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	var ground := ScatterGround.sampler(doc, doc.heights, grid, PackedStringArray())
	var at := Vector2(0.3, -0.2)
	for role in [ScatterGround.ROLE_COVER, ScatterGround.ROLE_TALL_COVER, ScatterGround.ROLE_SHRUB]:
		assert_eq(ground.call(at, role).x, 0.0, "role %d burns away" % role)
	assert_eq(ground.call(at, ScatterGround.ROLE_ROCK).x, 1.0, "a rock stays")
	assert_eq(ground.call(at, ScatterGround.ROLE_TREE).x, 1.0, "a tree stays (snags replace it)")
	var charred := ScatterGround.plan_role({"key": "stump", "size_class": "medium"})
	assert_eq(ground.call(at, charred).x, 1.0, "the burnt forest's stumps live on ash")
	var diff := {"ids_before": PackedStringArray(), "ids_after": PackedStringArray(["ash"])}
	assert_true(SurfaceStroke.changes_plants(diff, PaletteLibrary.surfaces()), "ash regrows")


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
