extends GutTest

## Village fields (topic fields, docs/systems/villages.md section 11): the pure rules
## (VillageFields: kinds per kit, strokes, the strokes a field laid, props and plants, the pick of
## plazas and fields), the record's `fields` (MapSettlementIO round trip and hostile input), the
## editor's add_field, resize_field and remove_field as one history entry each with the paint taken
## back byte for byte and a live-edit peer ending level, the brush laying a field, the plants layer
## and the pane's Lay and kind rows.

## The pane's rail width at 1280x720, and the height it may take there (round 4, P2-4, measured in
## fields_look's f_720_pane: content scale 1.4 makes the canvas 771 px tall, the pane starts at 122
## under the map-name block), less 60 px of slack.
const PANE_WIDTH_PX := 364.0
const PANE_BUDGET_PX := 771.0 - 122.0 - 60.0

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	# 40 cells (61 m): the street's houses reach about 9 m each side, and a field may not cover one.
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
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


func test_crops_are_a_light_earth_disc_with_broad_rows_inside_it() -> void:
	var field := _field(Vector2(3, 4), 8.0, "crops")
	var strokes := VillageFields.strokes_of(field, 5)
	assert_eq(strokes[0]["surface"], VillageCrops.EARTH, "light warm earth, not the dark peat")
	assert_eq(strokes[0]["from"], strokes[0]["to"], "the ground is one disc")
	var rows := strokes.slice(1)
	assert_between(rows.size(), 3, 16, "a few bold rows, not fine stripes")
	for row: Dictionary in rows:
		assert_true(VillageCrops.surfaces().has(str(row["surface"])))
		for key in ["from", "to"]:
			assert_lt((row[key] as Vector2).distance_to(Vector2(3, 4)), 8.0, "rows stay on the disc")
	assert_eq(VillageFields.strokes_of(field, 5), strokes, "the same record plans the same rows")
	assert_ne(VillageFields.angle_of(field, 5), VillageFields.angle_of(field, 6), "seeds turn rows")


func test_neighbouring_crop_fields_take_different_tones() -> void:
	var step := VillageCrops.CELL_M
	for seed_value in [0, 5, 11]:
		var tone := VillageCrops.tone_of(Vector2(1, 1), seed_value)
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var next := Vector2(1 + dx * step, 1 + dz * step)
				assert_ne(VillageCrops.tone_of(next, seed_value), tone, "a quilt, not one crop")
	assert_ne(
		VillageCrops.tone_of(Vector2(1, 1), 5), VillageCrops.tone_of(Vector2(1, 1), 6), "a re-dress"
	)


func test_a_crop_field_stands_rows_of_real_plants_by_default() -> void:
	assert_eq(VillageCrops.look, "plants", "round 5's verdict is the default")
	var hedge := 0
	for seed_value in 4:
		var field := _field(Vector2(0, 12), 8.0, "crops")
		var record := _hamlet([field])
		record.seed_value = seed_value
		var tone: Dictionary = VillageCrops.TONES[VillageCrops.tone_of(Vector2(0, 12), seed_value)]
		var crops := VillageFields.plants_of(record).filter(
			func(p: Dictionary) -> bool: return not VillageFields.HEDGE_SHRUBS.has(p["asset"])
		)
		hedge = VillageFields.plants_of(record).size() - crops.size()
		assert_between(crops.size(), 150, 450, "a field of plants in rows, not a sprinkle")
		var allowed: Array = VillageCrops.PLANT_ASSETS[str(tone["plant"])]
		for plant: Dictionary in crops:
			assert_true(allowed.has(plant["asset"]), "one crop per field")
			assert_lt((plant["at"] as Vector2).distance_to(Vector2(0, 12)), 8.0, "on the disc")
	assert_gt(hedge, 0, "the hedgerow still stands round it")


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


func test_an_orchard_has_mown_alleys_and_blossom_and_a_garden_broad_beds() -> void:
	var orchard := _field(Vector2(30, 0), 8.0, "orchard")
	var alleys := VillageFields.strokes_of(orchard, 5).slice(1)
	assert_between(alleys.size(), 3, 7, "a few mown alleys between the tree rows")
	for alley: Dictionary in alleys:
		assert_eq(alley["surface"], VillageFields.ALLEY)
		for key in ["from", "to"]:
			assert_lt((alley[key] as Vector2).distance_to(Vector2(30, 0)), 8.0, "on the disc")
	var record := _hamlet([orchard])
	var plants := VillageFields.plants_of(record)
	var trees := plants.filter(
		func(p: Dictionary) -> bool: return VillageFields.ORCHARD_TREES.has(p["asset"])
	)
	var blossom := plants.filter(
		func(p: Dictionary) -> bool: return VillageFields.BLOSSOM.has(p["asset"])
	)
	assert_eq(blossom.size(), trees.size() * VillageFields.BLOSSOM_COUNT, "blossom round each tree")
	var garden := _field(Vector2.ZERO, VillageFields.DEFAULT_RADIUS_M["garden"], "garden")
	var beds := VillageFields.strokes_of(garden, 5).slice(1)
	assert_eq(beds.size(), 3, "a default garden holds three broad beds")
	var flowers := VillageFields.plants_of(_hamlet([garden])).filter(
		func(p: Dictionary) -> bool: return VillageFields.GARDEN_FLOWERS.has(p["asset"])
	)
	assert_gt(flowers.size(), 6 * beds.size(), "each bed one mass of flowers, not a dotted line")


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
	assert_lte(
		VillageFields.stroke_indices(ground, field, 6).size(), 2, "another seed's rows: the discs alone"
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
	assert_true(editor.settlements.add_field(id, Vector2(0, 14), 4.0, "crops"))
	assert_eq(_history.undo_count(), entries + 1, "one history entry")
	assert_true(_doc.surface_ids.has(VillageCrops.EARTH))
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
	assert_true(editor.settlements.add_field(id, Vector2(0, 16), 6.0, "orchard"))
	assert_true(editor.settlements.add_field(id, Vector2(0, -15), 4.0, "garden"))
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
		assert_true(editor.settlements.add_field(id, Vector2(-9 + 6 * k, 13), 2.5, "garden"))
	assert_false(editor.settlements.add_field(id, Vector2(0, -9), 3.0, "garden"))
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_FULL)


func test_a_peer_ends_level_through_add_resize_remove_and_their_undos() -> void:
	var host := _editor()
	var street := _street(host)
	var peer_doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "farming_hamlet")
	assert_true(host.settlements.add_field(id, Vector2(0, 16), 6.0, "crops"))
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
	tool.hit = Vector3(0, 0, 18)
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
	assert_true(editor.settlements.add_field(id, Vector2(0, 17), 7.0, "orchard"))
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
	assert_eq(
		pane.hint.text,
		VillageToolPane.FIELD_HINT % VillageToolPane.FIELD_NOUNS["garden"],
		"the hint says the gesture"
	)
	assert_true(pane.hint.text.ends_with("a garden."), "the noun never wraps alone")
	var crops := pane.lay_field.tiles.get_node(^"village_kind_crops") as Button
	assert_true(crops.disabled, "a market town keeps no crops")
	assert_eq(pane.lay_note.text, "Market town keeps no crops", "said in the pane, not a tip")
	assert_true(pane.lay_note.visible)
	# The greyed tile's tip says the same words.
	assert_string_contains(crops.tooltip_text, pane.lay_note.text)
	assert_eq(pane.lay_field.caption, "Lay out")
	assert_lt(
		pane.lay_field.get_index(), pane.kit_field.get_index(), "the most used row comes first"
	)
	assert_eq(pane.lay_note.get_index(), pane.lay_field.get_index() + 1, "under its tiles")
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
	assert_eq(pane.lay_note.text, "Harbour town keeps no fields")
	for kind in Settlement.FIELD_KINDS:
		var tile := pane.lay_field.tiles.get_node(NodePath("village_kind_" + kind)) as Button
		assert_true(tile.disabled, "%s greyed in a harbour town" % kind)


## The pane on glass at its rail width, holding `villages` villages with village 1 of `kit` picked
## and a field picked (the size row shown), laid out.
func _laid_out_pane(villages: int, kit: String) -> VillageToolPane:
	var host := VBoxContainer.new()
	host.theme = load(ThemeColors.GLASS_THEME_PATH)
	host.size = Vector2(PANE_WIDTH_PX, 900)
	add_child_autofree(host)
	var pane := VillageToolPane.new()
	host.add_child(pane)
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	for id in range(1, villages + 1):
		doc.settlements.append(Settlement.make(id, kit if id == 1 else "farming_hamlet", 1, 5))
	doc.settlements[0].fields.append(_field(Vector2(0, 0), 4.0, "garden"))
	var state := VillagePlazas.state_of(doc, 1, -1)
	state = VillageFields.with_fields(state, doc, 1, VillageFields.GROUP_FIELDS, 0, "")
	state["lay_field"] = true
	pane.show_state(state)
	return pane



func test_the_pane_fits_720_with_three_villages_and_a_wrapped_note() -> void:
	var pane := _laid_out_pane(3, "harbour_town")
	await wait_physics_frames(3)
	assert_true(pane.village_field.visible and pane.lay_note.visible and pane.size_row.visible)
	var tall := pane.get_combined_minimum_size().y
	gut.p("pane %.0f px tall, budget %.0f" % [tall, PANE_BUDGET_PX])
	assert_lt(tall, PANE_BUDGET_PX, "the pane leaves 60 px of slack at 720")
	var lay := pane.lay_field.tiles.get_child(1) as Button
	var kit := pane.kit_field.tiles.get_child(0) as Button
	assert_gt(lay.size.y, kit.size.y, "the Lay out tiles are larger than the character's")


func test_the_boundary_tiles_share_one_row_with_their_labels_whole() -> void:
	var pane := _laid_out_pane(3, "market_town")
	await wait_physics_frames(3)
	var tiles := pane.boundary_field.tiles
	var top := (tiles.get_child(0) as Button).position.y
	for child in tiles.get_children():
		var tile := child as Button
		assert_eq(tile.position.y, top, "%s on the one row" % tile.text)
		var font := tile.get_theme_font(&"font")
		var wide := font.get_string_size(
			tile.text, HORIZONTAL_ALIGNMENT_LEFT, -1, tile.get_theme_font_size(&"font_size")
		).x
		var note := "%s fits its tile (%.0f of %.0f)" % [tile.text, wide, tile.size.x]
		assert_lt(wide, tile.size.x - 8.0, note)
	assert_between(tiles.get_child(0).size.y, 38.0, 44.0, "controls about 40 px")


func test_a_greyed_kind_reads_in_the_solid_disabled_role() -> void:
	var pane := _laid_out_pane(1, "market_town")
	await wait_physics_frames(2)
	var crops := pane.lay_field.tiles.get_node(^"village_kind_crops") as Button
	assert_true(crops.disabled)
	assert_eq(crops.modulate, Color.WHITE, "no modulate alpha (UI_TASTE C2)")
	assert_eq(crops.self_modulate, Color.WHITE)
	var words := crops.get_theme_color(&"font_disabled_color")
	assert_eq(words.a, 1.0, "a solid role")
	# The disabled tile over the glass panel over a white board, the lightest case for light words.
	var under := Color.WHITE
	var tile := crops.get_theme_stylebox(&"disabled") as StyleBoxFlat
	for layer: Color in [ThemeColors.GLASS, tile.bg_color]:
		under = Color(under.lerp(Color(layer, 1.0), layer.a), 1.0)
	var ratio := BackdropPaint.contrast(words, under)
	gut.p("greyed label %.2f:1" % ratio)
	assert_gt(ratio, 4.5, "the greyed label keeps 4.5:1 (C6)")


func test_a_crop_field_grows_a_hedgerow_with_a_gate() -> void:
	var field := _field(Vector2(3, -2), 8.0, "crops")
	var hedge := VillageFields.hedge_of(field, 77)
	assert_gt(hedge.size(), 25, "a ring of bushes round an 8 m field")
	var widest := 0.0
	var angles: Array[float] = []
	for plant in hedge:
		var off: Vector2 = (plant["at"] as Vector2) - Vector2(3, -2)
		assert_almost_eq(off.length(), 8.0 + VillageFields.HEDGE_OUT_M, 0.2, "just past the rim")
		assert_true(VillageFields.HEDGE_SHRUBS.has(plant["asset"]))
		angles.append(off.angle())
	angles.sort()
	for k in angles.size():
		var next := angles[(k + 1) % angles.size()] + (TAU if k == angles.size() - 1 else 0.0)
		widest = maxf(widest, next - angles[k])
	assert_gt(widest, VillageFields.HEDGE_GATE * 1.5, "a gate gap in the hedge")
	assert_eq(VillageFields.hedge_of(field, 77), hedge, "the same record gives the same hedge")
	var record := _hamlet([field, _field(Vector2(30, 0), 5.0, "garden")])
	var plants := VillageFields.plants_of(record)
	var shrubs := VillageFields.HEDGE_SHRUBS
	var hedged := plants.filter(func(p: Dictionary) -> bool: return shrubs.has(p["asset"]))
	assert_eq(hedged.size(), hedge.size(), "the crops are hedged, the garden is not")


func test_a_field_tile_picture_is_painted_per_kind() -> void:
	var crops := VillageSwatch.field_image("crops", 32)
	var orchard := VillageSwatch.field_image("orchard", 32)
	assert_eq(crops.get_width(), 32)
	assert_ne(crops.get_pixel(16, 18), orchard.get_pixel(16, 18), "each kind reads apart")
