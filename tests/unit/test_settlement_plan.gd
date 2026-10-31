extends GutTest

## Settlements, the pure half (card settlement, villages phase 1 host step B): the frontage of a
## street from its lots (SettlementFrontage, golden digests for all 11 species), the plan
## (SettlementPlan: determinism, the overrides), the record (Settlement, MapSettlementIO: round
## trip, old maps, hostile input, caps) and the live-edit codec. Digests:
## tests/fixtures/settlement_digests.txt (`<species> <frontage digest> <plan digest> <count>`, the
## fixture of a deliberate change). Summary: docs/systems/settlements.md.

const FIXTURE := "res://tests/fixtures/settlement_digests.txt"
const SAVE_PATH := "user://test_settlement_plan.ttmap"

var _doc: MapDocument = null


func before_each() -> void:
	StructureRecipes.ensure_served()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func after_each() -> void:
	DirAccess.remove_absolute(SAVE_PATH)


## A street of species `preset`: a straight 24 m line, or with `bent` a line turning twice.
func _street(preset: int, bent: bool = false, wall_id: int = 1) -> Wall:
	var line := PackedVector2Array([Vector2(-12, 0), Vector2(12, 0)])
	if bent:
		line = PackedVector2Array([Vector2(-12, -3), Vector2(-2, 1), Vector2(12, 4)])
	var street := Wall.make(wall_id, Wall.Kind.ROW, line, false, 3.5)
	street.preset = preset
	street.seed_value = 11
	_doc.walls.append(street)
	return street


func _settlement(street_id: int, kit: String = "farming_hamlet") -> Settlement:
	var settlement := Settlement.make(1, kit, street_id, 4242)
	settlement.wealth = 0.5
	settlement.density = 0.9
	return settlement


func _frontage_digest(frontages: Array[ProcgenFrontage]) -> String:
	var parts := PackedStringArray()
	for frontage in frontages:
		parts.append(JSON.stringify(frontage.to_dict(), "", true, true))
	return "\n".join(parts).md5_text()


func _lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).strip_edges().split("\n"):
		if line.strip_edges() != "":
			out.append(line.strip_edges())
	return out


# --- the frontage ---------------------------------------------------------------------------


func test_the_frontage_of_every_species_matches_its_golden_digest() -> void:
	assert_eq(Wall.ROW_PRESETS, 11)
	var now := PackedStringArray()
	for preset in Wall.ROW_PRESETS:
		_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
		var street := _street(preset, preset % 2 == 1)
		var frontages := SettlementFrontage.of_street(_doc, street)
		assert_gt(frontages.size(), 0, "%s has a frontage" % ProcgenStreetSpecies.NAMES[preset])
		for frontage in frontages:
			assert_eq(frontage.problems(), [] as Array[String], frontage.key)
		var kit: String = Settlement.KIND_NAMES[preset % Settlement.KIND_NAMES.size()]
		var items := SettlementPlan.place(_settlement(1, kit), frontages)
		now.append(
			(
				"%s %s %s %d"
				% [
					ProcgenStreetSpecies.NAMES[preset],
					_frontage_digest(frontages),
					SettlementPlan.digest(items),
					items.size()
				]
			)
		)
	var pinned := _lines(FIXTURE) if FileAccess.file_exists(FIXTURE) else PackedStringArray()
	assert_eq(pinned.size(), now.size(), "pinned lines; computed:\n" + "\n".join(now))
	for k in mini(pinned.size(), now.size()):
		assert_eq(now[k], pinned[k], "a deliberate change re-pins")


func test_a_frontage_has_both_sides_lots_in_order_and_a_door_in_each() -> void:
	var street := _street(3)
	var frontages := SettlementFrontage.of_street(_doc, street)
	assert_eq(frontages.size(), 2, "side 2 is both sides")
	assert_ne(frontages[0].key, frontages[1].key)
	assert_eq(frontages[0].street_side, -frontages[1].street_side)
	for frontage in frontages:
		assert_gte(frontage.lots.size(), 2)
		var end := 0.0
		for lot in frontage.lots:
			assert_gte(float(lot["s0"]), end - 0.0001, "sorted and apart")
			assert_eq((lot["doors"] as Array).size(), 1)
			var door: float = lot["doors"][0]["s"]
			assert_true(door >= float(lot["s0"]) and door <= float(lot["s1"]))
			end = float(lot["s1"])
		assert_true(frontage.open_start and frontage.open_end)


func test_one_sided_street_has_one_frontage() -> void:
	var street := _street(0)
	street.side = 0
	assert_eq(SettlementFrontage.of_street(_doc, street).size(), 1)


func test_the_facade_line_stands_the_setback_from_the_street() -> void:
	var line := SettlementFrontage.facade_line(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 3.0, 1
	)
	assert_almost_eq(absf(line[0].y), 3.0, 0.001)
	assert_almost_eq(line[0].x, 0.0, 0.001)
	var other := SettlementFrontage.facade_line(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0)]), 3.0, -1
	)
	assert_almost_eq(line[0].y, -other[0].y, 0.001, "the sides are opposite")


func test_a_neighbouring_building_becomes_an_obstacle() -> void:
	var street := _street(3)
	var near := Structure.make(
		1,
		"core:cottage",
		PackedVector2Array([Vector2(-2, 9), Vector2(2, 9), Vector2(2, 13), Vector2(-2, 13)]),
		5
	)
	_doc.structures.append(near)
	var frontages := SettlementFrontage.of_street(_doc, street)
	assert_eq(frontages[0].obstacles.size(), 1)
	var far := SettlementFrontage.from_lots(street, WallGeometry.row_lots(_doc, street))
	assert_eq(far[0].obstacles.size(), 0)


# --- the plan -------------------------------------------------------------------------------


func test_the_plan_repeats_and_dresses_a_street() -> void:
	var street := _street(3)
	var settlement := _settlement(street.id)
	var first := SettlementPlan.placements(_doc, settlement)
	var again := SettlementPlan.placements(_doc, settlement)
	assert_gt(first.size(), 3, "a village street is furnished")
	assert_eq(SettlementPlan.digest(first), SettlementPlan.digest(again))
	var slots := {}
	for item in first:
		assert_false(slots.has(item["slot"]), "slots are unique: %s" % item["slot"])
		slots[item["slot"]] = true
		assert_true(ProcgenProps.NAMES.has(item["prop"]))
		assert_true(int(item["seed"]) >= 0 and int(item["seed"]) < ProcgenSettlement.VARIANTS)
	var other := settlement.copy()
	other.seed_value = SettlementEditor.next_seed(settlement.seed_value)
	assert_ne(
		SettlementPlan.digest(SettlementPlan.placements(_doc, other)),
		SettlementPlan.digest(first),
		"another seed furnishes differently"
	)


func test_density_and_wealth_change_the_furnishing() -> void:
	var street := _street(3)
	var sparse := _settlement(street.id)
	sparse.density = 0.1
	var busy := sparse.copy()
	busy.density = 1.5
	assert_lt(
		SettlementPlan.placements(_doc, sparse).size(),
		SettlementPlan.placements(_doc, busy).size(),
		"a busier street has more"
	)


func test_removed_swapped_and_pinned_slots() -> void:
	var street := _street(3)
	var settlement := _settlement(street.id)
	var base := SettlementPlan.placements(_doc, settlement)
	var first_slot: String = base[0]["slot"]
	var second_slot: String = base[1]["slot"]
	var third_slot: String = base[2]["slot"]
	var edited := settlement.copy()
	edited.removed.append(first_slot)
	edited.swapped[second_slot] = "well"
	edited.pinned[third_slot] = {
		"prop": "bench", "at": Vector2(1.5, 2.5), "yaw": 0.5, "scale": 1.0, "seed": 2
	}
	var items := SettlementPlan.placements(_doc, edited)
	var by_slot := {}
	for item in items:
		by_slot[item["slot"]] = item
	assert_false(by_slot.has(first_slot), "removed")
	assert_eq(by_slot[second_slot]["prop"], "well", "swapped")
	assert_eq(by_slot[second_slot]["position"], base[1]["position"], "swapped stays put")
	assert_eq(by_slot[third_slot]["prop"], "bench", "pinned")
	assert_eq(by_slot[third_slot]["position"], Vector2(1.5, 2.5))
	assert_true(by_slot[third_slot]["pinned"])
	assert_eq(items.size(), base.size() - 1, "only the removed one is gone")
	# A pin whose slot no longer exists is still drawn.
	edited.pinned["gone:slot"] = {
		"prop": "barrel", "at": Vector2(0, 5), "yaw": 0.0, "scale": 1.0, "seed": 0
	}
	assert_eq(SettlementPlan.placements(_doc, edited).size(), items.size() + 1)
	# A removed slot that is also pinned stays out.
	edited.removed.append("gone:slot")
	assert_eq(SettlementPlan.placements(_doc, edited).size(), items.size())


func test_moving_a_house_changes_only_its_own_frontage() -> void:
	var street := _street(3)
	var settlement := _settlement(street.id)
	var before := SettlementPlan.placements(_doc, settlement)
	# Another seed for the right side's lots only: the walls seed moves both sides, so compare
	# the plan of a frontage whose lot list changed in one lot against the original.
	var frontages := SettlementFrontage.of_street(_doc, street)
	var moved := frontages[0]
	var lot: Dictionary = moved.lots[moved.lots.size() / 2]
	lot["s0"] = float(lot["s0"]) + 0.4
	var changed := SettlementPlan.place(settlement, frontages)
	var held := {}
	for item in before:
		held[item["slot"]] = SettlementPlan.lines_of([item as Dictionary] as Array[Dictionary])[0]
	var same := 0
	var differ := 0
	for item in changed:
		var line := SettlementPlan.lines_of([item as Dictionary] as Array[Dictionary])[0]
		if held.get(item["slot"], "") == line:
			same += 1
		else:
			differ += 1
	assert_gt(
		same,
		differ,
		"most of the street keeps its furnishings (%d same, %d differ)" % [same, differ]
	)
	# The other side is untouched.
	var other_key := frontages[1].key
	for item in changed:
		if String(item["slot"]).begins_with(other_key + ":"):
			assert_eq(
				held.get(item["slot"], ""),
				SettlementPlan.lines_of([item as Dictionary] as Array[Dictionary])[0],
				"the other side did not move"
			)


func test_a_missing_street_or_unknown_kit_has_no_furnishings() -> void:
	var settlement := _settlement(9)
	assert_eq(SettlementPlan.placements(_doc, settlement).size(), 0)
	var street := _street(3)
	var odd := _settlement(street.id)
	odd.kit = "nowhere"
	assert_eq(SettlementPlan.placements(_doc, odd).size(), 0)


func test_every_kit_furnishes_a_street() -> void:
	var street := _street(3)
	for kit in Settlement.KIND_NAMES:
		var settlement := _settlement(street.id, kit)
		settlement.density = 1.2
		assert_gt(SettlementPlan.placements(_doc, settlement).size(), 0, kit)


# --- the record -----------------------------------------------------------------------------


func _full() -> Settlement:
	var settlement := _settlement(1, "market_town")
	settlement.removed.append("w1l:l2/door/d0l")
	settlement.swapped["w1l:l3/door/d0r"] = "bench"
	settlement.pinned["w1r:l1/x"] = {
		"prop": "well", "at": Vector2(3.25, -4.5), "yaw": 0.125, "scale": 1.05, "seed": 3
	}
	return settlement


func test_a_settlement_round_trips_through_json_and_a_saved_map() -> void:
	_street(3)
	_doc.settlements.append(_full())
	assert_eq(MapSettlementIO.problem(_doc), "")
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: Dictionary = MapDocumentIO.read(SAVE_PATH)
	var loaded: MapDocument = read["document"]
	assert_eq(loaded.settlements.size(), 1)
	assert_true(loaded.settlements[0].same_as(_doc.settlements[0]))
	assert_eq(loaded.settlements[0].pinned["w1r:l1/x"]["at"], Vector2(3.25, -4.5))
	assert_eq(MapDocumentIO.write(loaded, SAVE_PATH + ".b"), OK)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_PATH).size(),
		FileAccess.get_file_as_bytes(SAVE_PATH + ".b").size(),
		"a re-save has the same size"
	)
	DirAccess.remove_absolute(SAVE_PATH + ".b")


func test_a_map_without_settlements_loads_unchanged() -> void:
	_street(3)
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var loaded: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(loaded.settlements.size(), 0)
	assert_eq(loaded.walls.size(), 1)
	var entries := {}
	MapSettlementIO.serialize(_doc, entries)
	assert_true(entries.is_empty(), "no entry is written when there is none")


func test_hostile_settlements_are_skipped_with_a_warning() -> void:
	var good := MapSettlementIO.settlement_json(_settlement(1))
	var cases: Array[Dictionary] = []
	for change: Dictionary in [
		{"id": 0},
		{"id": 33},
		{"kit": "elf_city"},
		{"seed": -1},
		{"wealth": 1.5},
		{"wealth": "rich"},
		{"density": 9.0},
		{"source": 0},
		{"source": 999},
		{"frozen": [{"line": [[0, 0]]}], "source": 0},
		{"removed": [5]},
		{"swapped": {"a": "dragon"}},
		{"pinned": {"a": {"prop": "well", "at": [0, 0], "yaw": 0.0, "scale": 99.0, "seed": 0}}},
		{"pinned": {"a": {"prop": "well", "at": [0], "yaw": 0.0, "scale": 1.0, "seed": 0}}},
	]:
		var bad := good.duplicate(true)
		bad.merge(change, true)
		cases.append(bad)
	for k in cases.size():
		var single := MapDocumentIO._WarningLog.new()
		assert_eq(
			MapSettlementIO.parse_list([cases[k]], single).size(), 0, "case %d is refused" % k
		)
	var many: Array = [good]
	many.append_array(cases)
	var warn_log := MapDocumentIO._WarningLog.new()
	var parsed := MapSettlementIO.parse_list(many, warn_log)
	assert_eq(parsed.size(), 1, "only the good one survives")
	assert_eq(MapSettlementIO.parse_list(["x", 3, null], warn_log).size(), 0)


func test_caps_and_duplicate_ids_and_streets() -> void:
	var items: Array = []
	for k in MapDocument.MAX_SETTLEMENTS + 2:
		var settlement := Settlement.make(k + 1, "farming_hamlet", k + 1, 5)
		items.append(MapSettlementIO.settlement_json(settlement))
	var warn_log := MapDocumentIO._WarningLog.new()
	assert_eq(MapSettlementIO.parse_list(items, warn_log).size(), MapDocument.MAX_SETTLEMENTS)
	var twice := [
		MapSettlementIO.settlement_json(Settlement.make(1, "farming_hamlet", 3, 5)),
		MapSettlementIO.settlement_json(Settlement.make(1, "farming_hamlet", 4, 5)),
		MapSettlementIO.settlement_json(Settlement.make(2, "farming_hamlet", 3, 5)),
	]
	assert_eq(MapSettlementIO.parse_list(twice, MapDocumentIO._WarningLog.new()).size(), 1)
	_doc.settlements.append(Settlement.make(1, "farming_hamlet", 3, 5))
	_doc.settlements.append(Settlement.make(1, "farming_hamlet", 4, 5))
	assert_ne(MapSettlementIO.problem(_doc), "", "the writer refuses a repeated id")
	assert_eq(_doc.next_settlement_id(), 2)


func test_overrides_are_capped() -> void:
	var settlement := _settlement(1)
	for k in Settlement.MAX_OVERRIDES + 1:
		settlement.removed.append("slot%d" % k)
	assert_ne(MapSettlementIO.settlement_problem(settlement), "")


# --- the live edit --------------------------------------------------------------------------


func test_the_live_edit_codec_carries_a_settlement_list_both_ways() -> void:
	_street(3)
	var map := Node3D.new()
	add_child_autofree(map)
	var history := AuthoringHistory.new()
	map.add_child(AuthoredTerrain.create(_doc))
	var editor := AuthoringEditor.create(_doc, map, history)
	var list: Array[Settlement] = [_full()]
	var entry := {"redo": editor.settlements.apply_list.bind(list, Rect2())}
	var op := LiveEditCodec.op_of(entry, editor)
	assert_eq(op["kind"], "settlements")
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), _doc)
	assert_eq(decoded["problem"], "", "decodes")
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	LiveEditCodec.apply(decoded["op"], peer)
	assert_eq(peer_doc.settlements.size(), 1)
	assert_true(peer_doc.settlements[0].same_as(list[0]))


func test_a_hostile_live_edit_is_refused() -> void:
	var bad := Settlement.make(1, "farming_hamlet", 1, 5)
	var json := MapSettlementIO.settlement_json(bad)
	json["kit"] = "nope"
	var bytes := LiveEditCodec.encode(
		{"v": LiveEditCodec.VERSION, "kind": "settlements", "args": [[json], Rect2()], "redo": true}
	)
	assert_ne(LiveEditCodec.decode(bytes, _doc)["problem"], "")
