extends GutTest

## Village fields (topic fields, docs/systems/villages.md section 11): the pure rules
## (VillageFields: kinds per kit, strokes, the strokes a field laid, props and plants, the pick of
## plazas and fields), the record's `fields` (MapSettlementIO round trip and hostile input), the
## editor's add_field, resize_field and remove_field as one history entry each with the paint taken
## back byte for byte and a live-edit peer ending level, the brush laying a field, the plants layer
## and the pane's Lay and kind rows.

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _editor(doc: MapDocument = null, history: AuthoringHistory = null) -> AuthoringEditor:
	var use := doc if doc != null else _doc
	var root := _map
	if doc != null:
		root = Node3D.new()
		add_child_autofree(root)
	root.add_child(AuthoredTerrain.create(use))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	root.add_child(node)
	var editor := AuthoringEditor.create(use, root, history if history != null else _history)
	editor.scatter.attach_document(use)
	return editor


func _street(editor: AuthoringEditor) -> int:
	return editor.walls.place(
		Wall.Kind.ROW, Vector3(-12, 0, 0), Vector3(12, 0, 0), -1.0, {"seed": 5, "side": 2, "preset": 3}
	)


func _paint_state(doc: MapDocument) -> String:
	var weights := doc.surface_weights
	return "%s|%d|%d" % [",".join(doc.surface_ids), weights.size(), hash(weights)]


func _field(at: Vector2, radius: float, kind: String) -> Dictionary:
	return {"at": at, "radius": radius, "kind": kind}


func _hamlet(fields: Array = []) -> Settlement:
	var record := Settlement.make(1, "farming_hamlet", 1, 5)
	for field in fields:
		record.fields.append(field)
	return record


# --- the pure rules --------------------------------------------------------------------------


func test_a_kit_decides_the_kinds_and_its_default() -> void:
	assert_eq(VillageFields.kind_for("farming_hamlet", ""), "crops")
	assert_eq(VillageFields.kind_for("market_town", ""), "garden")
	assert_eq(VillageFields.kind_for("market_town", "crops"), "garden", "not offered: the default")
	assert_eq(VillageFields.kind_for("farming_hamlet", "orchard"), "orchard")
	assert_eq(VillageFields.kind_for("harbour_town", "garden"), "", "a harbour keeps no fields")
	assert_eq(VillageFields.radius_for_drag(Vector2.ZERO, Vector2(0.5, 0), "crops"), 8.0)
	assert_eq(VillageFields.radius_for_drag(Vector2.ZERO, Vector2(30, 0), "garden"), 8.0)
	assert_eq(VillageFields.radius_for_drag(Vector2.ZERO, Vector2(6.04, 0), "orchard"), 6.0)


func test_crops_are_an_earth_disc_with_broad_rows_inside_it() -> void:
	var field := _field(Vector2(3, 4), 8.0, "crops")
	var strokes := VillageFields.strokes_of(field, 5)
	assert_eq(strokes[0]["surface"], VillageFields.EARTH)
	assert_eq(strokes[0]["from"], strokes[0]["to"], "the ground is one disc")
	var rows := strokes.slice(1)
	assert_between(rows.size(), 4, 8, "a few bold rows, not fine stripes")
	var surface := str(rows[0]["surface"])
	assert_true(VillageFields.CROP_ROWS.has(surface))
	for row: Dictionary in rows:
		assert_eq(row["surface"], surface, "one crop per field")
		for key in ["from", "to"]:
			assert_lt((row[key] as Vector2).distance_to(Vector2(3, 4)), 8.0, "rows stay on the disc")
	assert_eq(VillageFields.strokes_of(field, 5), strokes, "the same record plans the same rows")
	assert_ne(VillageFields.angle_of(field, 5), VillageFields.angle_of(field, 6), "seeds turn rows")


func test_a_garden_has_beds_and_flowers_and_an_orchard_a_loose_grid_of_trees() -> void:
	var garden := _field(Vector2.ZERO, 4.5, "garden")
	var beds := VillageFields.strokes_of(garden, 5).slice(1)
	assert_between(beds.size(), 2, 4)
	for bed: Dictionary in beds:
		assert_eq(bed["surface"], VillageFields.EARTH)
	var record := _hamlet([garden, _field(Vector2(30, 0), 8.0, "orchard")])
	var plants := VillageFields.plants_of(record)
	var trees := plants.filter(
		func(p: Dictionary) -> bool: return VillageFields.ORCHARD_TREES.has(p["asset"])
	)
	assert_between(trees.size(), 5, 16, "a handful of trees, not a forest")
	for tree: Dictionary in trees:
		assert_lt((tree["at"] as Vector2).distance_to(Vector2(30, 0)), 8.0 - VillageFields.TREE_RIM_M)
	assert_gt(plants.size() - trees.size(), 4, "the garden has its flowers and shrubs")
	var other := _hamlet([garden, _field(Vector2(30, 0), 8.0, "orchard")])
	other.seed_value = 6
	assert_ne(var_to_str(VillageFields.plants_of(other)), var_to_str(plants), "seeds differ")


func test_the_strokes_a_field_laid_are_found_among_the_others() -> void:
	var field := _field(Vector2(0, 10), 6.0, "crops")
	var other := _field(Vector2(-20, 10), 6.0, "crops")
	var ground: Array[Dictionary] = []
	var road := {"surface": "dirt_road_packed", "from": Vector2(-12, 0), "to": Vector2(12, 0)}
	road.merge({"radius": 2.0, "seconds": 1.2})
	ground.append(SettlementGroundIO.snapped_stroke(
		road
	))
	ground.append_array(VillageFields.strokes_of(other, 5))
	var own := VillageFields.strokes_of(field, 5)
	ground.append_array(own)
	var found := VillageFields.stroke_indices(ground, field, 5)
	assert_eq(found.size(), own.size())
	assert_eq(found[0], ground.size() - 1, "newest first")
	assert_eq(
		VillageFields.stroke_indices(ground, field, 6).size(), 1, "another seed's rows: the disc alone"
	)


func test_a_crop_field_stands_a_scarecrow_that_the_plan_draws() -> void:
	var record := _hamlet([_field(Vector2(0, 12), 8.0, "crops")])
	var props := VillageFields.props_of(record)
	assert_eq(props[0]["prop"], "scarecrow")
	assert_lt((props[0]["position"] as Vector2).distance_to(Vector2(0, 12)), 8.0)
	assert_true(ProcgenProps.NAMES.has(props[0]["prop"]))
	var editor := _editor()
	record.source = _street(editor)
	var doc := _doc
	var slots := SettlementPlan.placements(doc, record).map(
		func(item: Dictionary) -> String: return item["slot"]
	)
	assert_has(slots, "f0:scarecrow")
	record.removed.append("f0:scarecrow")
	assert_does_not_have(
		SettlementPlan.placements(doc, record).map(func(i: Dictionary) -> String: return i["slot"]),
		"f0:scarecrow",
		"a removed slot is not drawn"
	)


func test_a_plaza_inside_a_field_wins_the_pick_and_a_rim_wins_over_an_inside() -> void:
	var record := _hamlet([_field(Vector2.ZERO, 10.0, "orchard")])
	record.plazas.append({"at": Vector2(2, 0), "radius": 3.0})
	var list: Array[Settlement] = [record]
	var inside := VillageFields.pick_any(list, Vector2(2, 0.5), 0.5)
	assert_eq(inside["group"], VillageFields.GROUP_PLAZAS)
	var rim := VillageFields.pick_any(list, Vector2(0, 9.8), 0.5)
	assert_eq(rim["group"], VillageFields.GROUP_FIELDS)
	assert_eq(rim["part"], VillagePlazas.PART_RIM)
	assert_eq(VillageFields.pick_any(list, Vector2(40, 0), 0.5), {})


# --- the record ------------------------------------------------------------------------------


func _round_trip(record: Settlement) -> Array[Settlement]:
	var text := JSON.stringify(MapSettlementIO.settlement_json(record), "", false, true)
	return MapSettlementIO.parse_list([JSON.parse_string(text)], MapDocumentIO._WarningLog.new())


func test_fields_round_trip_byte_for_byte_and_are_left_out_when_none() -> void:
	var bare := _hamlet()
	assert_false(MapSettlementIO.settlement_json(bare).has("fields"), "no fields: no key")
	var record := _hamlet(
		[_field(Vector2(1.234, -5.5), 7.25, "crops"), _field(Vector2(20, 3), 4.0, "garden")]
	)
	var read := _round_trip(record)
	assert_eq(read.size(), 1)
	assert_eq(
		JSON.stringify(MapSettlementIO.settlement_json(read[0])),
		JSON.stringify(MapSettlementIO.settlement_json(record))
	)
	assert_eq(read[0].fields[1]["kind"], "garden")
	assert_ne(record.fingerprint(), bare.fingerprint())


func test_a_hostile_field_list_skips_the_record() -> void:
	var good := MapSettlementIO.settlement_json(_hamlet([_field(Vector2.ZERO, 6.0, "crops")]))
	var one: Dictionary = good["fields"][0]
	var hostile: Array = [
		{"fields": "crops"},
		{"fields": [{"at": [0, 0], "radius": 6.0, "kind": "maze"}]},
		{"fields": [{"at": [0, 0], "radius": 99.0, "kind": "crops"}]},
		{"fields": [{"at": [0], "radius": 6.0, "kind": "crops"}]},
		{"fields": [{"at": [1e9, 0], "radius": 6.0, "kind": "crops"}]},
		{"fields": [{"at": [0, 0], "radius": "6", "kind": "crops"}]},
		{"fields": [one, one, one, one, one]},
	]
	for change: Dictionary in hostile:
		var value := good.duplicate(true)
		value.merge(change, true)
		var log := MapDocumentIO._WarningLog.new()
		assert_eq(MapSettlementIO.parse_list([value], log).size(), 0, "skipped: %s" % change)
	var record := _hamlet([_field(Vector2.ZERO, 30.0, "crops")])
	assert_ne(MapSettlementIO.settlement_problem(record), "", "the writer refuses it too")


# --- the editor ------------------------------------------------------------------------------


func test_a_field_is_painted_in_one_entry_and_removing_it_restores_the_weights() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	var before := _paint_state(_doc)
	var strokes := _doc.settlement(id).ground.size()
	var entries := _history.undo_count()
	# Clear of the road's soft edge: paint over another stroke cannot be taken back exactly.
	assert_true(editor.settlements.add_field(id, Vector2(0, 11), 4.0, "crops"))
	assert_eq(_history.undo_count(), entries + 1, "one history entry")
	assert_true(_doc.surface_ids.has(VillageFields.EARTH))
	var laid := VillageFields.strokes_of(_doc.settlement(id).fields[0], _doc.settlement(id).seed_value)
	assert_eq(_doc.settlement(id).ground.size(), strokes + laid.size(), "the record lists its paint")
	var painted := _paint_state(_doc)
	assert_ne(painted, before)
	assert_true(editor.settlements.remove_field(id, 0))
	assert_eq(_doc.settlement(id).fields.size(), 0)
	assert_eq(_doc.settlement(id).ground.size(), strokes)
	assert_eq(_paint_state(_doc), before, "the weights are back byte for byte, slots included")
	_history.undo()
	assert_eq(_paint_state(_doc), painted)
	_history.undo()
	assert_eq(_paint_state(_doc), before)
	assert_eq(_doc.settlement(id).fields.size(), 0)


func test_resize_repaints_a_field_and_clear_takes_everything_back() -> void:
	var editor := _editor()
	var street := _street(editor)
	var bare := _paint_state(_doc)
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_true(editor.settlements.add_field(id, Vector2(0, 9), 6.0, "orchard"))
	assert_true(editor.settlements.add_field(id, Vector2(0, -9), 4.0, "garden"))
	var two := _paint_state(_doc)
	assert_true(editor.settlements.resize_field(id, 0, 4.0))
	assert_eq(_doc.settlement(id).fields[0]["radius"], 4.0)
	assert_ne(_paint_state(_doc), two)
	assert_false(editor.settlements.resize_field(id, 0, 4.0), "the same size changes nothing")
	assert_false(editor.settlements.resize_field(id, 0, 40.0))
	_history.undo()
	assert_eq(_paint_state(_doc), two, "undo puts the larger field's paint back")
	assert_true(editor.settlements.redress(id), "a re-dress replans the fields with the next seed")
	assert_eq(_doc.settlement(id).fields.size(), 2)
	assert_true(editor.settlements.clear(id))
	var cleared := _paint_state(_doc).get_slice("|", 2)
	assert_eq(cleared, bare.get_slice("|", 2), "Clear leaves bare weights")


func test_a_village_holds_four_fields() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	for k in Settlement.MAX_FIELDS:
		assert_true(editor.settlements.add_field(id, Vector2(-9 + 6 * k, 9), 2.5, "garden"))
	assert_false(editor.settlements.add_field(id, Vector2(0, -9), 3.0, "garden"))
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_FULL)


func test_a_peer_ends_level_through_add_resize_remove_and_their_undos() -> void:
	var host := _editor()
	var street := _street(host)
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "farming_hamlet")
	assert_true(host.settlements.add_field(id, Vector2(0, 9), 6.0, "crops"))
	assert_true(host.settlements.resize_field(id, 0, 5.0))
	assert_true(host.settlements.remove_field(id, 0))
	assert_eq(entries.size(), 4)
	for entry in entries:
		_send(entry, host, peer_doc, peer, false)
	assert_eq(_paint_state(peer_doc), _paint_state(_doc), "the same ground byte for byte")
	for k in range(entries.size() - 1, -1, -1):
		_history.undo()
		_send(entries[k], host, peer_doc, peer, true)
		assert_eq(_paint_state(peer_doc), _paint_state(_doc), "undo %d keeps the peer level" % k)
		if not peer_doc.settlements.is_empty():
			assert_eq(
				var_to_str(peer_doc.settlements[0].fields), var_to_str(_doc.settlements[0].fields)
			)


func _send(
	entry: Dictionary, host: AuthoringEditor, peer_doc: MapDocument, peer: AuthoringEditor, undo: bool
) -> void:
	for op in LiveEditCodec.ops_of(entry, host, undo):
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)


# --- the brush, the plants and the pane ----------------------------------------------------------


func _tool(editor: AuthoringEditor) -> BrushTool:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	tool.editor = editor
	return tool


func test_with_field_picked_a_click_lays_the_kits_default_field_and_picks_it() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	mode.set_lay(true)
	tool.hit = Vector3(0, 0, 9)
	mode.frame(tool)
	assert_false(mode.press(tool))
	mode.end(tool)
	var held := _doc.settlement(id)
	assert_eq(held.fields.size(), 1)
	assert_eq(held.plazas.size(), 0)
	assert_eq(held.fields[0]["kind"], "crops")
	assert_eq(held.fields[0]["radius"], VillageFields.DEFAULT_RADIUS_M["crops"])
	assert_eq(mode.selected_group, VillageFields.GROUP_FIELDS)
	assert_eq(mode.selected_plaza, 0)
	assert_true(mode.set_selected_radius(editor, 5.0), "the pane's slider sizes a field")
	assert_eq(_doc.settlement(id).fields[0]["radius"], 5.0)
	assert_true(mode.remove_selected(editor))
	assert_eq(_doc.settlement(id).fields.size(), 0)
	assert_eq(mode.selected_plaza, -1)


func test_a_harbour_town_lays_no_field_and_says_why() -> void:
	var editor := _editor()
	editor.settlements.dress(_street(editor), "harbour_town")
	var mode := VillageBrush.new()
	var tool := _tool(editor)
	mode.set_lay(true, "garden")
	tool.hit = Vector3(0, 0, 9)
	mode.frame(tool)
	var said: Array[String] = []
	tool.refused.connect(func(text: String) -> void: said.append(text))
	mode.press(tool)
	assert_eq(said, [VillageBrush.NO_FIELDS] as Array[String])
	assert_false(mode.took_press())


func test_orchard_trees_are_drawn_on_the_map_as_derived_plants() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	assert_true(editor.settlements.add_field(id, Vector2(0, 8), 7.0, "orchard"))
	var plants := AuthoredFieldPlants.plants_of(_doc)
	assert_false(plants.is_empty())
	var layer := _map.get_node_or_null(AuthoredFieldPlants.NODE_NAME) as AuthoredFieldPlants
	assert_not_null(layer, "the layer follows the record")
	assert_gt(layer.placed, 4)
	assert_true(editor.settlements.remove_field(id, 0))
	assert_eq(layer.placed, 0, "the trees go with the field")


func test_the_pane_offers_plaza_or_field_and_the_kinds_the_village_keeps() -> void:
	var pane := VillageToolPane.new()
	add_child_autofree(pane)
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	doc.settlements.append(Settlement.make(1, "market_town", 1, 5))
	var state := VillagePlazas.state_of(doc, 1, -1)
	state = VillageFields.with_fields(state, doc, 1, VillageFields.GROUP_PLAZAS, -1, "")
	state["lay_field"] = true
	pane.show_state(state)
	assert_true(pane.lay_field.visible)
	assert_eq(pane.lay_field.tiles.selected, &"village_kind_garden", "the kit's default is lit")
	assert_eq(pane.plaza_title.text, VillageToolPane.field_room_text(0))
	assert_eq(pane.hint.text, VillageToolPane.FIELD_HINT % "a garden", "the hint says the gesture")
	var crops := pane.lay_field.tiles.get_node(^"village_kind_crops") as Button
	assert_true(crops.disabled, "a market town keeps no crops")
	assert_eq(pane.lay_field.note.text, "Market town keeps no crops", "said in the pane, not a tip")
	var picks: Array = []
	pane.lay_picked.connect(func(field: bool, kind: String) -> void: picks.append([field, kind]))
	pane._on_lay_tile(&"village_kind_orchard")
	pane._on_lay_tile(&"village_lay_plaza")
	assert_eq(picks, [[true, "orchard"], [false, ""]])
	doc.settlements[0].kit = "harbour_town"
	state = VillageFields.with_fields(
		VillagePlazas.state_of(doc, 1, -1), doc, 1, VillageFields.GROUP_PLAZAS, -1, ""
	)
	state["lay_field"] = false
	pane.show_state(state)
	assert_eq(pane.lay_field.tiles.selected, &"village_lay_plaza")
	assert_eq(pane.hint.text, VillageToolPane.HINT)
	assert_eq(pane.lay_field.note.text, "Harbour town keeps no fields")
	for kind in Settlement.FIELD_KINDS:
		var tile := pane.lay_field.tiles.get_node(NodePath("village_kind_" + kind)) as Button
		assert_true(tile.disabled, "%s greyed in a harbour town" % kind)


func test_a_field_tile_picture_is_painted_per_kind() -> void:
	var crops := VillageSwatch.field_image("crops", 32)
	var orchard := VillageSwatch.field_image("orchard", 32)
	assert_eq(crops.get_width(), 32)
	assert_ne(crops.get_pixel(16, 18), orchard.get_pixel(16, 18), "each kind reads apart")
