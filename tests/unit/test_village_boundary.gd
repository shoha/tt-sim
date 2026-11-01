extends GutTest

## A village's boundary (villages phase 3, topic bounds; docs/systems/villages.md section 13): the
## line round the hull (pure: grown with rounded corners, sampled evenly), its gaps (gates where a
## street leaves, blocked where wet, by a field or by a building), the runs and the transient walls
## with their gate piers, the kind by character and seed, and the editor: a Dress draws the kind,
## the stone kinds draw one node per village and the hedge plants, Clear and Undo take them back,
## the record round trips and a village with none saves as before.

const RIVER_LEVEL := -0.2
const BED := -1.0

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(32, 32), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _editor(doc: MapDocument = null) -> AuthoringEditor:
	var use := doc if doc != null else _doc
	_map.add_child(AuthoredTerrain.create(use))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(use, _map, _history)
	editor.scatter.attach_document(use)
	return editor


func _street(editor: AuthoringEditor) -> int:
	return editor.walls.place(
		Wall.Kind.ROW, Vector3(-12, 0, 0), Vector3(12, 0, 0), -1.0, {"seed": 5, "side": 2, "preset": 3}
	)


static func _rect(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array(
		[Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]
	)


## How far `p` lies outside the rectangle of half size `half` round the origin.
static func _outside(p: Vector2, half: Vector2) -> float:
	var d := Vector2(maxf(absf(p.x) - half.x, 0.0), maxf(absf(p.y) - half.y, 0.0))
	return d.length()


# --- the line (pure) ----------------------------------------------------------------------------


func test_the_ring_stands_a_margin_round_the_hull_with_round_corners() -> void:
	var half := Vector2(12, 6)
	var ring := VillageBoundary.ring_of(_rect(half), 2.0, 0.5)
	assert_gt(ring.size(), 100, "a 24 x 12 m hull grown 2 m is about 84 m round")
	for p in ring:
		assert_almost_eq(_outside(p, half), 2.0, 0.05, "every sample 2 m out, corners round")
	var spacing := 0.0
	for k in ring.size():
		spacing = maxf(spacing, ring[k].distance_to(ring[(k + 1) % ring.size()]))
	assert_lt(spacing, 0.55, "evenly sampled")
	var line := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0)])
	assert_true(VillageBoundary.ring_of(line).is_empty(), "points in a line enclose nothing")


func test_the_hull_takes_the_street_widened_past_its_road() -> void:
	var street := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	var points := VillageBoundary.hull_points(street, 3.0, [], [])
	var ring := VillageBoundary.ring_of(points)
	for p in ring:
		if absf(p.x) <= 10.0:
			assert_gt(absf(p.y), 4.99, "a street with no lot on a side has a line past its road")


# --- the gaps and runs (pure) -------------------------------------------------------------------


func test_the_street_ends_are_gates_and_the_runs_carry_piers() -> void:
	var street := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	var ring := VillageBoundary.ring_of(VillageBoundary.hull_points(street, 4.0, [], []))
	var line := VillageBoundary.extended(street)
	var gates: Array[Dictionary] = [{"from": line[0], "to": line[1], "half": 2.3}]
	var flags := VillageBoundary.gate_flags(ring, gates, func(_p: Vector2) -> bool: return false)
	for i in ring.size():
		var at_end := absf(ring[i].x) > 10.0 and absf(ring[i].y) <= 2.3
		assert_eq(flags[i] == VillageBoundary.GATE, at_end, "a gate only where the road leaves")
	var runs := VillageBoundary.runs_of(ring, flags)
	assert_eq(runs.size(), 2, "two sides between the two gates")
	for run in runs:
		assert_true(run["gate_start"] and run["gate_end"], "a gate at both ends of each side")
		for p: Vector2 in run["points"]:
			assert_gt(absf(p.y), 2.3, "no wall across the road")
	var walls := VillageBoundary.walls_of({"kind": VillageBoundary.WALL, "runs": runs})
	var piers := walls.filter(func(w: Wall) -> bool: return w.length_m() < 1.0)
	assert_eq(piers.size(), 4, "a pier either side of each gate")
	for wall in walls:
		assert_lte(wall.length_m(), VillageBoundary.CHUNK_M + 1.0, "every line under the cap")
		assert_lte(wall.points.size(), Wall.MAX_POINTS)
		assert_false(wall.closed)
	assert_true(VillageBoundary.walls_of({"kind": VillageBoundary.HEDGE, "runs": runs}).is_empty())
	assert_gt(VillageBoundary.hedge_of({"kind": VillageBoundary.HEDGE, "runs": runs}, 3).size(), 40)


func test_water_buildings_and_fields_break_the_line_without_a_pier() -> void:
	var ring := VillageBoundary.ring_of(_rect(Vector2(12, 8)))
	var wet := PackedByteArray()
	for p in ring:
		wet.append(1 if absf(p.x) < 1.5 else 0)
	var house: Array[PackedVector2Array] = [_shifted(_rect(Vector2(2, 2)), Vector2(14, 0))]
	var blocked := func(p: Vector2) -> bool:
		return VillageBoundary.near_building(house, p, VillageBoundary.BUILDING_KEEP_M)
	var flags := VillageBoundary.gate_flags(ring, [], blocked, wet)
	var runs := VillageBoundary.runs_of(ring, flags)
	assert_eq(runs.size(), 3, "the stream cuts both long sides, the house the east end")
	for run in runs:
		assert_false(run["gate_start"] or run["gate_end"], "a gap that is no gate has no pier")
		for p: Vector2 in run["points"]:
			assert_gte(absf(p.x), 1.5, "nothing on the water")
			assert_false(VillageBoundary.near_building(house, p, 0.79), "nothing on the house")
	var zeros := PackedByteArray()
	zeros.resize(ring.size())
	var none := VillageBoundary.runs_of(ring, zeros)
	assert_eq(none.size(), 1)
	assert_true(none[0]["closed"], "no gap: one closed line")


func test_a_short_stub_between_gaps_is_dropped() -> void:
	var ring := VillageBoundary.ring_of(_rect(Vector2(10, 5)))
	var flags := PackedByteArray()
	for k in ring.size():
		flags.append(VillageBoundary.BLOCKED if k % 40 > 2 else VillageBoundary.KEEP)
	assert_true(VillageBoundary.runs_of(ring, flags).is_empty(), "two-sample stubs are clutter")


static func _shifted(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out


# --- the kind by character ----------------------------------------------------------------------


func test_the_kind_follows_the_character_and_not_every_seed_is_walled() -> void:
	var town := {}
	var hamlet := {}
	for seed_value in 60:
		assert_eq(VillageBoundary.kind_for("hill_fort_village", seed_value), VillageBoundary.WALL)
		assert_eq(VillageBoundary.kind_for("harbour_town", seed_value), "")
		town[VillageBoundary.kind_for("market_town", seed_value)] = true
		hamlet[VillageBoundary.kind_for("farming_hamlet", seed_value)] = true
	assert_eq(town.keys().size(), 2, "a market town is walled low on some seeds, open on others")
	assert_true(town.has(VillageBoundary.LOW_WALL))
	assert_eq(hamlet.keys().size(), 2, "a hamlet is hedged on some seeds")
	assert_true(hamlet.has(VillageBoundary.HEDGE))


# --- the editor and the layer -------------------------------------------------------------------


func test_a_hill_fort_dress_walls_the_village_and_clear_and_undo_take_it_back() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "hill_fort_village")
	assert_gt(id, 0)
	assert_eq(_doc.settlement(id).boundary, VillageBoundary.WALL)
	assert_eq(_doc.walls.size(), 1, "the boundary is no Wall record")
	var planned := VillageBoundary.plan(_doc, _doc.settlement(id))
	assert_eq(int(planned["gates"]), 2, "a gate at each end of the street")
	var plans := VillageFieldGround.footprints(_doc)
	for run: Dictionary in planned["runs"]:
		for p: Vector2 in run["points"]:
			assert_false(VillageBoundary.near_building(plans, p, 0.79), "clear of every house")
	var layer := _map.get_node_or_null(AuthoredBoundaries.BOUNDARY_NODE) as AuthoredBoundaries
	assert_not_null(layer)
	var node := layer.get_wall_node(id)
	assert_not_null(node, "one node for the village")
	assert_not_null(node.get_node_or_null(^"Masonry"))
	assert_null(node.get_node_or_null(^"Collision"), "walk-through")
	assert_gt(VillageBoundary.clearance_crossings(_doc).size(), 4, "the scatter clears under it")
	assert_eq(_history.undo(), "Dress street")
	assert_null(layer.get_wall_node(id), "undo takes the wall back")
	_history.redo()
	assert_not_null(layer.get_wall_node(id))
	assert_true(editor.settlements.clear(id))
	assert_null(layer.get_wall_node(id), "Clear takes it back")


func test_a_hedged_hamlet_grows_bushes_round_its_edge() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	editor.settlements.set_boundary(id, "")
	var bare := AuthoredFieldPlants.plants_of(_doc)
	assert_true(editor.settlements.set_boundary(id, VillageBoundary.HEDGE))
	assert_eq(_history.undo(), "Village boundary")
	_history.redo()
	var plants := AuthoredFieldPlants.plants_of(_doc)
	var count := 0
	for rows: Array in plants.values():
		count += rows.size()
	var before := 0
	for rows: Array in bare.values():
		before += rows.size()
	assert_gt(count - before, 40, "a hedge of meadow bushes round the hamlet")
	assert_false(editor.settlements.set_boundary(id, "moat"), "an unknown kind is refused")
	var layer := _map.get_node_or_null(AuthoredBoundaries.BOUNDARY_NODE) as AuthoredBoundaries
	assert_true(layer == null or layer.get_wall_node(id) == null, "a hedge draws no wall")


func test_a_village_over_a_river_keeps_its_wall_off_the_water() -> void:
	var doc := MapDocument.create_flat(Vector2i(32, 32), "grass", "v", 9)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			if absf(doc.sample_to_world(Vector2(x, z)).x) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var widths := PackedFloat32Array([1.5, 1.5])
	var course := PackedVector2Array([Vector2(0, -30), Vector2(0, 30)])
	doc.water_bodies.append(WaterBody.river(1, course, widths, WaterBody.Depth.ANKLE, RIVER_LEVEL))
	_doc = doc
	var editor := _editor(doc)
	var id := editor.settlements.dress(_street(editor), "hill_fort_village")
	var planned := VillageBoundary.plan(doc, doc.settlement(id))
	assert_gt((planned["runs"] as Array).size(), 2, "the river cuts the line")
	for run: Dictionary in planned["runs"]:
		for p: Vector2 in run["points"]:
			assert_false(WaterGeometry.is_wet_at(doc, p), "no wall in the river")


# --- the record ---------------------------------------------------------------------------------


func test_the_boundary_round_trips_and_is_left_out_when_none() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	assert_false(MapSettlementIO.settlement_json(record).has("boundary"), "none saves as before")
	record.boundary = VillageBoundary.LOW_WALL
	var json := MapSettlementIO.settlement_json(record)
	assert_eq(json["boundary"], "low_wall")
	var warnings := MapDocumentIO._WarningLog.new()
	var text := JSON.stringify(json)
	var back := MapSettlementIO.parse_list([JSON.parse_string(text)], warnings)
	assert_eq(back.size(), 1)
	assert_eq(back[0].boundary, VillageBoundary.LOW_WALL)
	assert_eq(JSON.stringify(MapSettlementIO.settlement_json(back[0])), text, "byte for byte")
	for hostile: Variant in ["moat", 3, [], {}, "WALL"]:
		var bad := json.duplicate(true)
		bad["boundary"] = hostile
		assert_eq(MapSettlementIO.parse_list([bad], warnings).size(), 0, "%s skipped" % [hostile])


func test_a_village_dressed_without_a_boundary_saves_and_clears_as_before() -> void:
	var editor := _editor()
	editor.settlements.lays_boundary = false
	var id := editor.settlements.dress(_street(editor), "hill_fort_village")
	assert_eq(_doc.settlement(id).boundary, "")
	assert_true(VillageBoundary.clearance_crossings(_doc).is_empty(), "the scatter as before")
	assert_null(_map.get_node_or_null(AuthoredBoundaries.BOUNDARY_NODE), "no layer")
	var text := JSON.stringify(MapSettlementIO.settlement_json(_doc.settlement(id)))
	assert_false(text.contains("boundary"))
