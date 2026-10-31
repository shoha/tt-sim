extends GutTest

## Settlement ground (villages phase 2, docs/systems/settlements.md "Ground"): SettlementGround's
## pure plan (the road along the centre line at a width from the setback, door paths joining each
## door, plaza discs, the slot budget, refusals for water, slope and buildings, determinism),
## SettlementEditor's one-undo Dress with its paint, the plazas of the record (round trip,
## hostile input, live edit) and the paint reaching a live-edit peer.

const KITS := ["farming_hamlet", "market_town", "harbour_town", "hill_fort_village"]
const POND_BED := -1.25
const POND_LEVEL := -0.25

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


func _street(editor: AuthoringEditor, preset: int = 3, seed_value: int = 5) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, 0),
		Vector3(12, 0, 0),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": preset}
	)


func _known() -> Dictionary:
	return PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT)


func _ground(kit: String) -> Dictionary:
	return ProcgenSettlement.ground_of(ProcgenSettlement.kit_named(kit))


func _record(wall_id: int, kit: String = "farming_hamlet") -> Settlement:
	return Settlement.make(1, kit, wall_id, 77)


func _plan(kit: String = "farming_hamlet", record: Settlement = null) -> Dictionary:
	var street := _doc.walls[0].id
	var settlement := record if record != null else _record(street, kit)
	return SettlementGround.plan(_doc, settlement, _ground(kit), _known())


func _carve_pond(centre: Vector2, radius: float) -> void:
	var heights := _doc.heights.duplicate()
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if _doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				heights[_doc.sample_index(x, z)] = POND_BED
				mask[_doc.sample_index(x, z)] = 2
	_doc.heights = heights
	_doc.pond_mask = mask
	_doc.water_bodies.append(WaterBody.pond(2, WaterBody.Depth.DEEP, POND_LEVEL))


func _strokes(result: Dictionary, role: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for stroke: Dictionary in result["strokes"]:
		if stroke["role"] == role:
			out.append(stroke)
	return out


func _paint_state(doc: MapDocument) -> String:
	return "%s|%s" % [
		",".join(doc.surface_ids), doc.surface_weights.compress(FileAccess.COMPRESSION_ZSTD).size()
	] + str(hash(doc.surface_weights))


# --- the kits' ground -------------------------------------------------------------------------


func test_every_kits_ground_is_a_plant_clearing_surface_of_the_palette() -> void:
	var known := _known()
	for kit in KITS:
		var ground := _ground(kit)
		assert_eq(ground.size(), 3, "%s names road, door path and plaza" % kit)
		var surfaces := {}
		for role: String in ground:
			var surface := str(ground[role])
			surfaces[surface] = true
			assert_true(known.has(surface), "%s: %s is in the core palette" % [kit, surface])
			assert_eq(
				str(known.get(surface, {}).get("role", "")),
				"built",
				"%s: %s clears plants (role built)" % [kit, surface]
			)
		assert_lte(surfaces.size(), 3, "%s takes at most three painted-surface slots" % kit)


# --- the plan ----------------------------------------------------------------------------------


func test_the_road_follows_the_centre_line_at_a_width_from_the_setback() -> void:
	var editor := _editor()
	var street := _street(editor)
	var wall := _doc.wall(street)
	var plan := _plan()
	var road := _strokes(plan, "road")
	assert_eq(road.size(), 1, "a straight 24 m street is one capsule")
	var half := SettlementGround.road_half_width(wall.height_m)
	for stroke in road:
		for key in ["from", "to"]:
			var p: Vector2 = stroke[key]
			assert_almost_eq(p.y, 0.0, 0.01, "on the centre line")
			assert_between(p.x, -12.01, 12.01, "within the street")
		assert_almost_eq(float(stroke["radius"]), half * SettlementGround.EDGE_REACH, 0.006)
		assert_eq(stroke["surface"], _ground("farming_hamlet")["road"])
	assert_almost_eq(float(plan["road_m"]), 24.0, 0.2, "the whole street is laid")
	var wide := _doc.wall(street)
	wide.height_m = 6.0
	assert_gt(
		SettlementGround.road_half_width(6.0), half, "a wider setback gets a wider road"
	)
	assert_lte(SettlementGround.road_half_width(50.0), SettlementGround.ROAD_HALF_MAX_M)
	# Villages3: about a third wider than the 0.58 share (1.74 m) and 0.9..2.4 m limits it had.
	assert_almost_eq(SettlementGround.road_half_width(3.0) / 1.74, 1.33, 0.02, "a third wider")
	assert_almost_eq(SettlementGround.ROAD_HALF_MIN_M / 0.9, 1.33, 0.02)
	assert_almost_eq(SettlementGround.ROAD_HALF_MAX_M / 2.4, 1.33, 0.02)


func test_a_bent_street_gets_a_stroke_a_straight_run_and_the_strokes_meet() -> void:
	var editor := _editor()
	var street := _street(editor)
	var wall := _doc.wall(street)
	wall.points = PackedVector2Array([Vector2(-12, 0), Vector2(0, 0), Vector2(8, 6), Vector2(8, 14)])
	var road := _strokes(_plan(), "road")
	assert_eq(road.size(), 3, "straight, diagonal, straight")
	for k in range(1, road.size()):
		assert_lt(
			(road[k - 1]["to"] as Vector2).distance_to(road[k]["from"]), 0.01, "the strokes meet"
		)
	assert_eq(road[0]["from"], Vector2(-12, 0))
	assert_eq(road[road.size() - 1]["to"], Vector2(8, 14))


func test_each_door_is_joined_to_the_street_by_two_short_strokes() -> void:
	var editor := _editor()
	var street := _street(editor)
	var wall := _doc.wall(street)
	var doors := 0
	for frontage in SettlementFrontage.of_street(_doc, wall):
		for lot: Dictionary in frontage.lots:
			doors += (lot["doors"] as Array).size()
	assert_gt(doors, 3, "the street has houses")
	var plan := _plan()
	var paths := _strokes(plan, "door_path")
	assert_eq(paths.size(), doors * 2, "two strokes a door")
	assert_eq(plan["doors"], doors)
	var half := SettlementGround.road_half_width(wall.height_m)
	for k in range(0, paths.size(), 2):
		var start: Vector2 = paths[k]["from"]
		var middle: Vector2 = paths[k]["to"]
		var end: Vector2 = paths[k + 1]["to"]
		assert_eq(paths[k + 1]["from"], middle, "the strokes join")
		assert_almost_eq(absf(start.y), wall.height_m, 0.5, "starts at the facade line")
		assert_lt(absf(end.y), half, "ends inside the road's edge")
		assert_lt(start.distance_to(end), wall.height_m + 0.2, "a few metres long")


func test_the_plan_is_deterministic_and_does_not_move_with_the_seed() -> void:
	var editor := _editor()
	var street := _street(editor)
	var first := _plan()
	var again := _plan()
	assert_eq(first["strokes"], again["strokes"], "same record, same strokes")
	var reseeded := _record(street)
	reseeded.seed_value = 123456
	assert_eq(
		_plan("farming_hamlet", reseeded)["strokes"],
		first["strokes"],
		"a re-dress moves no road or path"
	)


func test_a_pond_leaves_the_road_unpainted_and_no_stroke_lands_in_water() -> void:
	var editor := _editor()
	_street(editor)
	_carve_pond(Vector2(2, 0), 3.0)
	var plan := _plan()
	assert_gt(int(plan["refused"]["water"]), 0, "water refusals are counted")
	assert_eq(_strokes(plan, "road").size(), 2, "the dry ends are still laid, one stroke each")
	var courses := WaterGeometry.river_courses(_doc)
	for stroke: Dictionary in plan["strokes"]:
		for key in ["from", "to"]:
			assert_false(
				WaterGeometry.is_wet_at(_doc, stroke[key], -1, courses), "%s end is dry" % stroke["role"]
			)
	assert_lt(float(plan["road_m"]), 22.0, "the road stops short of the pond")


func test_a_steep_stretch_is_not_paved() -> void:
	var editor := _editor()
	_street(editor)
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if p.x > 0.0:
				heights[_doc.sample_index(x, z)] = p.x * 1.2
	_doc.heights = heights
	var plan := _plan()
	assert_gt(int(plan["refused"]["slope"]), 0, "slope refusals are counted")
	for stroke in _strokes(plan, "road"):
		assert_lt((stroke["to"] as Vector2).x, 1.6, "no road up the ramp")


func test_a_building_on_the_line_cuts_the_road_and_blocks_paths_through_it() -> void:
	var editor := _editor()
	_street(editor)
	var plan_before := _plan()
	_doc.structures.append(
		Structure.make(
			1,
			"core:cottage_a",
			PackedVector2Array([Vector2(-1, -1.5), Vector2(1, -1.5), Vector2(1, 1.5), Vector2(-1, 1.5)])
		)
	)
	var plan := _plan()
	assert_gt(int(plan["refused"]["building"]), 0)
	assert_lt(float(plan["road_m"]), float(plan_before["road_m"]) - 2.0, "a gap where it stands")
	for stroke in _strokes(plan, "road"):
		for key in ["from", "to"]:
			assert_gt(absf((stroke[key] as Vector2).x), 1.0, "no road through the building")


func test_the_slot_budget_serves_the_road_then_door_paths_then_plaza() -> void:
	var wanted := {"road": "a", "door_path": "b", "plaza": "c"}
	assert_eq(SettlementGround.affordable(_doc, wanted).size(), 3, "an empty map pays three")
	var full := PackedStringArray()
	for k in MapDocument.PAINT_SURFACE_LIMIT - 1:
		full.append("filler_%d" % k)
	_doc.surface_ids = full
	var one := SettlementGround.affordable(_doc, wanted)
	assert_eq(one, {"road": "a"}, "one slot left: the road")
	full.append("last")
	_doc.surface_ids = full
	assert_eq(SettlementGround.affordable(_doc, wanted), {}, "a full map paves nothing new")
	full[0] = "b"
	_doc.surface_ids = full
	assert_eq(
		SettlementGround.affordable(_doc, wanted),
		{"door_path": "b"},
		"a surface the map already paints costs no slot"
	)
	var shared := {"road": "a", "door_path": "a", "plaza": "c"}
	_doc.surface_ids = PackedStringArray()
	assert_eq(SettlementGround.affordable(_doc, shared).size(), 3, "two roles, one slot")


func test_a_full_map_refuses_the_ground_and_counts_it() -> void:
	var editor := _editor()
	_street(editor)
	var full := PackedStringArray()
	for k in MapDocument.PAINT_SURFACE_LIMIT:
		full.append("filler_%d" % k)
	_doc.surface_ids = full
	var plan := _plan()
	assert_eq(plan["strokes"].size(), 0)
	assert_eq(plan["refused"]["slots"], 3)


func test_a_surface_the_palette_lacks_is_not_painted() -> void:
	var editor := _editor()
	var street := _street(editor)
	var plan := SettlementGround.plan(
		_doc, _record(street), {"road": "no_such_surface", "door_path": "dirt_road_packed"}, _known()
	)
	assert_eq(plan["refused"]["unknown"], 1)
	assert_eq(_strokes(plan, "road").size(), 0)
	assert_gt(_strokes(plan, "door_path").size(), 0, "the others still go down")


func test_plaza_discs_are_filled_and_refused_in_water() -> void:
	var editor := _editor()
	var street := _street(editor)
	var record := _record(street)
	record.plazas = [{"at": Vector2(0, 9), "radius": 4.0}, {"at": Vector2(2, -9), "radius": 3.0}]
	var plan := _plan("farming_hamlet", record)
	var plazas := _strokes(plan, "plaza")
	assert_eq(plazas.size(), 2)
	assert_eq(plazas[0]["from"], Vector2(0, 9))
	assert_gt(float(plazas[0]["radius"]), 4.0, "the soft edge is beyond the disc")
	assert_eq(plan["roles"], ["road", "plaza", "door_path"], "paint order")
	_carve_pond(Vector2(2, -9), 4.0)
	assert_eq(_strokes(_plan("farming_hamlet", record), "plaza").size(), 1, "the wet one is refused")


# --- the editor: one undo ----------------------------------------------------------------------


func test_dress_paints_the_ground_and_one_undo_takes_back_everything() -> void:
	var editor := _editor()
	var street := _street(editor)
	var painted_before := _paint_state(_doc)
	var undo_before := _history.undo_count()
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_gt(id, 0)
	assert_eq(_history.undo_count(), undo_before + 1, "Dress is one history entry")
	assert_ne(_paint_state(_doc), painted_before, "the ground is painted")
	assert_true(_doc.surface_ids.has("dirt_road_packed"), "the hamlet's road surface took a slot")
	assert_eq(_doc.surface_ids.size(), 1, "road and door paths share a slot; no plaza, no slot")
	var summary: Dictionary = editor.settlements.last_ground
	assert_gt(int(summary["doors"]), 3)
	assert_eq(_doc.settlements.size(), 1)
	var painted_after := _paint_state(_doc)
	_history.undo()
	assert_eq(_paint_state(_doc), painted_before, "the paint is back to nothing")
	assert_eq(_doc.settlements.size(), 0, "and the record with it")
	assert_eq(_doc.surface_ids.size(), 0, "the slots are given back")
	_history.redo()
	assert_eq(_paint_state(_doc), painted_after, "redo repaves the same ground")
	assert_eq(_doc.settlements.size(), 1)


func test_painted_cells_under_the_road_hold_the_road_surface() -> void:
	var editor := _editor()
	var street := _street(editor)
	editor.settlements.dress(street, "farming_hamlet")
	var slot := _doc.surface_ids.find("dirt_road_packed")
	assert_gte(slot, 0)
	var centre := _doc.world_to_sample(Vector2(0, 0)).round()
	var index := _doc.sample_index(int(centre.x), int(centre.y))
	var found := 0
	var at := index * MapDocument.SURFACE_CHANNELS
	var plane := _doc.sample_count() * MapDocument.SURFACE_CHANNELS
	for e in MapDocument.SURFACE_ENTRIES:
		var weight := _doc.surface_weights[plane + at + e]
		if _doc.surface_weights[at + e] == slot and weight > 0:
			found = weight
	assert_gt(found, 200, "the road is near full cover on its centre line")


func test_a_redress_repaints_the_same_ground_and_a_feel_change_paints_nothing() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	var painted := _paint_state(_doc)
	var laid := _doc.settlement(id).ground.duplicate(true)
	var entries := _history.undo_count()
	assert_true(editor.settlements.redress(id))
	assert_eq(_history.undo_count(), entries + 1, "a re-dress is one entry")
	assert_eq(_paint_state(_doc), painted, "taken back and laid again: byte for byte the same ground")
	assert_eq(_doc.settlement(id).ground, laid, "the record lists the same strokes")
	assert_true(editor.settlements.set_feel(id, 0.2, 1.0))
	assert_eq(_paint_state(_doc), painted)
	assert_eq(_history.undo_count(), entries + 2)


func test_a_new_character_paves_its_own_ground_in_the_same_entry() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	var painted := _paint_state(_doc)
	var entries := _history.undo_count()
	assert_true(editor.settlements.set_kit(id, "market_town"))
	assert_eq(_history.undo_count(), entries + 1)
	assert_true(_doc.surface_ids.has("flagstone_sandstone"), "the market town's road")
	assert_false(_doc.surface_ids.has("dirt_road_packed"), "the hamlet's road was taken back")
	_history.undo()
	assert_eq(_paint_state(_doc), painted)
	assert_eq(_doc.settlement(id).kit, "farming_hamlet")


func test_dressing_a_map_with_no_free_slot_still_dresses_the_street() -> void:
	var editor := _editor()
	var street := _street(editor)
	var full := PackedStringArray()
	for k in MapDocument.PAINT_SURFACE_LIMIT:
		full.append("filler_%d" % k)
	_doc.surface_ids = full
	var entries := _history.undo_count()
	assert_gt(editor.settlements.dress(street, "farming_hamlet"), 0)
	assert_eq(_history.undo_count(), entries + 1)
	assert_eq(_doc.surface_ids, full, "no paint was written")
	assert_eq(editor.settlements.last_ground["refused"]["slots"], 3)


func test_a_plaza_is_added_paved_furnished_and_undone_as_one_entry() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "market_town", 0.7, 1.0)
	var entries := _history.undo_count()
	var before := _paint_state(_doc)
	var placed_before := SettlementPlan.placements(_doc, _doc.settlement(id)).size()
	assert_true(editor.settlements.add_plaza(id, Vector2(0, 8.123), 5.0))
	assert_eq(_history.undo_count(), entries + 1)
	var record := _doc.settlement(id)
	assert_eq(record.plazas.size(), 1)
	assert_eq(record.plazas[0]["at"], Vector2(0, 8.12), "to a centimetre")
	assert_ne(_paint_state(_doc), before, "the plaza is paved")
	assert_true(_doc.surface_ids.has("cobblestone"), "the market's plaza surface took a slot")
	assert_ne(
		SettlementPlan.placements(_doc, record).size(), placed_before, "the plaza rules furnish it"
	)
	_history.undo()
	assert_eq(_paint_state(_doc), before)
	assert_eq(_doc.settlement(id).plazas.size(), 0)


func test_plazas_are_capped_and_checked() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "market_town")
	assert_false(editor.settlements.add_plaza(id, Vector2(0, 8), 40.0), "too wide")
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_PLAZA)
	assert_false(editor.settlements.add_plaza(id, Vector2(0, 8), 0.5), "too small")
	assert_false(editor.settlements.add_plaza(99, Vector2(0, 8), 4.0), "no such settlement")
	for k in Settlement.MAX_PLAZAS:
		assert_true(editor.settlements.add_plaza(id, Vector2(-9.0 + 6.0 * k, 9), 2.5))
	assert_false(editor.settlements.add_plaza(id, Vector2(0, -9), 3.0), "a fifth")
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_FULL)
	assert_true(editor.settlements.remove_plaza(id, 0))
	assert_eq(_doc.settlement(id).plazas.size(), Settlement.MAX_PLAZAS - 1)


# --- a building's own path gives way -----------------------------------------------------------


func test_a_building_draws_no_path_ribbon_where_paint_already_leaves_its_door() -> void:
	var plan := PackedVector2Array([Vector2(-3, 8), Vector2(3, 8), Vector2(3, 13), Vector2(-3, 13)])
	var house := Structure.make(1, "cottage_a", plan, 3)
	_doc.structures.append(house)
	var bare := StructureDressing.build(_doc, house, null)
	var samples_bare := StructureDressing.ground_samples(_doc, plan)
	# Paint a blob over the front of the building (the door is in the middle of the first edge).
	var stroke := SurfaceStroke.begin(_doc, "dirt_road_packed", false)
	stroke.dab(Vector2(0, 8), Vector2(0, 8), 7.0, 3.0)
	assert_false(stroke.finish().is_empty())
	var painted := StructureDressing.build(_doc, house, null)
	assert_lt(
		int(painted["triangles"]), int(bare["triangles"]), "the alpha ribbon is left out of the yard"
	)
	assert_gt(int(painted["triangles"]), 0, "the skirt and the plants stay")
	assert_ne(
		StructureDressing.ground_samples(_doc, plan),
		samples_bare,
		"the structure's key sees the paint, so a rebuild draws the yard without it"
	)
	assert_eq(StructureDoorPaint.joined(_doc, Vector2(40, 40), Vector2.UP), 0.0, "unpainted ground")


# --- the record ---------------------------------------------------------------------------------


func test_plazas_round_trip_byte_for_byte() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	record.plazas = [{"at": Vector2(1.25, -8.5), "radius": 4.5}, {"at": Vector2(9, 3), "radius": 2.0}]
	assert_eq(MapSettlementIO.settlement_problem(record), "")
	var log := MapDocumentIO._WarningLog.new()
	var json := MapSettlementIO.settlement_json(record)
	var text := JSON.stringify([json], "", false, true)
	var read := MapSettlementIO.parse_list(JSON.parse_string(text), log)
	assert_eq(read.size(), 1, "read back")
	assert_eq(read[0].plazas, record.plazas)
	assert_eq(JSON.stringify([MapSettlementIO.settlement_json(read[0])], "", false, true), text)
	var bare := Settlement.make(2, "market_town", 3, 5)
	assert_false(MapSettlementIO.settlement_json(bare).has("plazas"), "none is left out")
	assert_eq(record.copy().plazas, record.plazas)
	assert_ne(record.fingerprint(), bare.fingerprint(), "a plaza changes the fingerprint")


func test_hostile_plazas_skip_the_settlement_with_a_warning() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	var base := MapSettlementIO.settlement_json(record)
	var cases := {
		"five discs": [[0, 0, 3], [1, 1, 3], [2, 2, 3], [3, 3, 3], [4, 4, 3]],
		"too wide": [[0, 0, 99]],
		"too small": [[0, 0, 0.1]],
		"far away": [[1.0e9, 0, 3]],
	}
	for label: String in cases:
		var discs: Array = []
		for d: Array in cases[label]:
			discs.append({"at": [d[0], d[1]], "radius": d[2]})
		var hostile := base.duplicate(true)
		hostile["plazas"] = discs
		var log := MapDocumentIO._WarningLog.new()
		assert_eq(MapSettlementIO.parse_list([hostile], log).size(), 0, label)
		assert_gt(log.items.size(), 0, "%s: a warning" % label)
	for bad: Variant in ["x", [1], [{"at": "x", "radius": 3}], [{"at": [0], "radius": 3}], [{}]]:
		var hostile := base.duplicate(true)
		hostile["plazas"] = bad
		var log := MapDocumentIO._WarningLog.new()
		assert_eq(MapSettlementIO.parse_list([hostile], log).size(), 0, "malformed %s" % str(bad))
	record.plazas = [{"at": Vector2(0, 0), "radius": 99.0}]
	assert_ne(MapSettlementIO.settlement_problem(record), "", "the writer refuses too")


# --- a live-edit peer ----------------------------------------------------------------------------


func test_a_peer_receives_the_paint_as_surface_ops_and_ends_with_the_same_ground() -> void:
	var host := _editor()
	var street := _street(host)
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	peer_doc.walls = _doc.walls.duplicate()
	var peer_history := AuthoringHistory.new()
	var peer := _editor(peer_doc, peer_history)
	host.settlements.dress(street, "farming_hamlet")
	assert_eq(entries.size(), 1)
	var ops := LiveEditCodec.ops_of(entries[0], host)
	var kinds: Array[String] = []
	for op in ops:
		kinds.append(str(op["kind"]))
	assert_true(kinds.has("surface"), "the paint crosses as surface ops")
	assert_eq(kinds[kinds.size() - 1], "settlements", "then the record")
	for op in ops:
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)
	assert_eq(peer_doc.surface_ids, _doc.surface_ids)
	assert_eq(peer_doc.surface_weights, _doc.surface_weights, "the same ground byte for byte")
	assert_eq(peer_doc.settlements.size(), 1)
	assert_eq(peer_doc.settlements[0].fingerprint(), _doc.settlements[0].fingerprint())
	# And an undo travels back the same way.
	_history.undo()
	var undo_ops := LiveEditCodec.ops_of(entries[0], host, true)
	for op in undo_ops:
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)
	assert_eq(peer_doc.surface_ids.size(), 0)
	assert_eq(peer_doc.settlements.size(), 0)
