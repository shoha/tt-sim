extends GutTest

## A village's bridges (villages phase 3, topic bridges; docs/systems/villages.md section 12): the
## wet runs of a street (pure, over a wet predicate: a puddle gets none, a sandbar joins, a street
## ending in water gets none), the kind by character and the width, and the editor: a Dress lays one
## crossing per run in its own history entry, lined up with the street, Clear and Undo take it back,
## a change of character swaps the kind under the same id, a crossing placed by hand is left alone,
## a full map is a toast, the record round trips and a peer ends level.

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
	_doc = _river_doc()
	StructureRecipes.ensure_served()


## A flat map with a river running north to south through x = 0, 3 m wide.
static func _river_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var heights := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 1.5:
				heights[doc.sample_index(x, z)] = BED
	doc.heights = heights
	var line := PackedVector2Array([Vector2(0, -15), Vector2(0, 15)])
	var widths := PackedFloat32Array([1.5, 1.5])
	doc.water_bodies.append(
		WaterBody.river(1, line, widths, WaterBody.Depth.ANKLE, RIVER_LEVEL)
	)
	return doc


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


func _street(editor: AuthoringEditor, z: float = 0.0) -> int:
	return editor.walls.place(
		Wall.Kind.ROW, Vector3(-12, 0, z), Vector3(12, 0, z), -1.0, {"seed": 5, "side": 2, "preset": 3}
	)


static func _line(from: Vector2, to: Vector2) -> PackedVector2Array:
	return PackedVector2Array([from, to])


# --- the wet runs (pure) ------------------------------------------------------------------------


func test_a_street_over_a_stream_has_one_run_from_bank_to_bank() -> void:
	var runs := VillageBridges.wet_runs(
		_line(Vector2(-10, 0), Vector2(10, 0)), func(p: Vector2) -> bool: return absf(p.x) < 1.5
	)
	assert_eq(runs.size(), 1)
	var run: Dictionary = runs[0]
	assert_almost_eq((run["from"] as Vector2).x, -1.5, 0.26, "the last dry sample before the water")
	assert_almost_eq((run["to"] as Vector2).x, 1.5, 0.26)
	assert_almost_eq(float(run["wet_m"]), 3.0, 0.26)
	assert_almost_eq((run["middle"] as Vector2).x, 0.0, 0.26)


func test_a_puddle_gets_no_run_and_a_sandbar_joins_one() -> void:
	var street := _line(Vector2(-10, 0), Vector2(10, 0))
	var puddle := VillageBridges.wet_runs(street, func(p: Vector2) -> bool: return absf(p.x) < 0.3)
	assert_eq(puddle.size(), 0, "under MIN_WET_M of wet street is a puddle")
	var bar := VillageBridges.wet_runs(
		street, func(p: Vector2) -> bool: return absf(p.x) < 2.0 and absf(p.x) > 0.2
	)
	assert_eq(bar.size(), 1, "a dry bar under JOIN_GAP_M mid-stream is one crossing")
	var two := VillageBridges.wet_runs(
		street, func(p: Vector2) -> bool: return absf(absf(p.x) - 5.0) < 1.0
	)
	assert_eq(two.size(), 2, "two streams, two runs")
	assert_lt((two[0]["middle"] as Vector2).x, (two[1]["middle"] as Vector2).x, "in street order")


func test_a_street_that_ends_in_water_gets_no_run() -> void:
	var runs := VillageBridges.wet_runs(
		_line(Vector2(-10, 0), Vector2(10, 0)), func(p: Vector2) -> bool: return p.x > 8.0
	)
	assert_eq(runs.size(), 0, "no dry street past the water: no crossing")
	var bend := PackedVector2Array([Vector2(-6, -6), Vector2(0, 0), Vector2(6, -6)])
	var bent := VillageBridges.wet_runs(bend, func(p: Vector2) -> bool: return p.length() < 1.5)
	assert_eq(bent.size(), 1, "a run over a bend is one run")


func test_the_kind_follows_the_character_and_the_width_the_road() -> void:
	assert_eq(VillageBridges.kinds_for("farming_hamlet", 0.5), [Crossing.Kind.PLANK])
	assert_eq(VillageBridges.kinds_for("harbour_town", 0.5), [Crossing.Kind.PLANK])
	assert_eq(
		VillageBridges.kinds_for("market_town", 0.5), [Crossing.Kind.ARCH, Crossing.Kind.PLANK]
	)
	assert_eq(
		VillageBridges.kinds_for("hill_fort_village", 0.9),
		[Crossing.Kind.ARCH, Crossing.Kind.PLANK]
	)
	assert_eq(
		VillageBridges.kinds_for("farming_hamlet", 0.1),
		[Crossing.Kind.FORD, Crossing.Kind.PLANK],
		"a poor lane fords first"
	)
	assert_eq(VillageBridges.width_for(Crossing.Kind.PLANK, 3.0), 3.0, "a 4.6 m road, held to 3 m")
	assert_eq(VillageBridges.width_for(Crossing.Kind.FORD, 3.0), 4.0)
	assert_almost_eq(VillageBridges.width_for(Crossing.Kind.PLANK, 1.0), 2.4, 0.001)


# --- the editor -------------------------------------------------------------------------------


func test_dress_lays_one_bridge_in_its_own_entry_lined_up_with_the_street() -> void:
	var editor := _editor()
	var street := _street(editor)
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_gt(id, 0)
	assert_eq(_doc.crossings.size(), 1, "one bridge for one stream")
	var bridge := _doc.crossings[0]
	assert_eq(bridge.kind, Crossing.Kind.PLANK)
	assert_eq(_doc.settlement(id).bridges, PackedInt32Array([bridge.id]))
	assert_lt(absf(bridge.direction().y), 0.01, "the deck runs along the street")
	assert_lt(minf(bridge.start.x, bridge.end.x), -1.5, "it stands on the west bank")
	assert_gt(maxf(bridge.start.x, bridge.end.x), 1.5, "and on the east bank")
	assert_almost_eq(bridge.width_m, 3.0, 0.001)
	assert_eq(editor.settlements.last_bridges["refused"], [])
	assert_eq(entries.size(), 1, "the street's dressing and its bridge are one entry")
	assert_eq(_history.undo(), "Dress street")
	assert_true(_doc.crossings.is_empty(), "one undo takes the bridge back")
	assert_true(_doc.settlements.is_empty())
	_history.redo()
	assert_eq(_doc.crossings.size(), 1, "redo lays it again")
	assert_eq(_doc.settlements.size(), 1)


func test_clear_takes_back_only_the_village_bridge() -> void:
	var editor := _editor()
	var street := _street(editor)
	var by_hand := editor.crossings.place(
		Crossing.Kind.STONES, Vector3(-1, 0, 10), Vector3(1, 0, 10)
	)
	assert_gt(by_hand, 0)
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_eq(_doc.crossings.size(), 2)
	assert_true(editor.settlements.clear(id))
	assert_eq(_doc.crossings.size(), 1, "the village bridge goes with Clear")
	assert_eq(_doc.crossings[0].id, by_hand, "the stones laid by hand stay")
	assert_eq(_history.undo(), "Clear village")
	assert_eq(_doc.crossings.size(), 2, "undo brings the bridge back with the village")
	assert_eq(_doc.settlement(id).bridges.size(), 1)


func test_a_change_of_character_swaps_the_kind_and_a_redress_keeps_it() -> void:
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	var first := _doc.crossings[0].id
	assert_true(editor.settlements.set_kit(id, "market_town"))
	assert_eq(_doc.crossings.size(), 1)
	assert_eq(_doc.crossings[0].kind, Crossing.Kind.ARCH, "a town crosses on a stone arch")
	assert_eq(_doc.crossings[0].id, first, "under the same id")
	var arch := _doc.crossings[0].copy()
	assert_true(editor.settlements.redress(id))
	assert_eq(_doc.crossings.size(), 1)
	assert_true(_doc.crossings[0].same_as(arch), "a re-dress over the same water keeps the bridge")
	assert_eq(_history.undo(), "Re-dress street")
	assert_eq(_history.undo(), "Change village character")
	assert_eq(_doc.crossings[0].kind, Crossing.Kind.PLANK, "undo puts the planks back")


func test_a_poor_lane_fords_and_a_hand_bridge_is_left_alone() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet", 0.1)
	assert_eq(_doc.crossings[0].kind, Crossing.Kind.FORD, "a poor lane fords wadeable water")
	assert_true(editor.settlements.clear(id))
	assert_true(_doc.crossings.is_empty())
	var by_hand := editor.crossings.place(
		Crossing.Kind.PLANK, Vector3(-1, 0, 0.6), Vector3(1, 0, 0.6)
	)
	assert_gt(by_hand, 0)
	var again := editor.settlements.dress(street, "farming_hamlet")
	assert_eq(_doc.crossings.size(), 1, "the street already crosses on the author's bridge")
	assert_eq(_doc.crossings[0].id, by_hand)
	assert_eq(int(editor.settlements.last_bridges["crossed"]), 1)
	assert_true(_doc.settlement(again).bridges.is_empty())


func test_a_full_map_dresses_and_says_why_there_is_no_bridge() -> void:
	var template := CrossingPlacement.place(
		_doc, Vector2(-1, 12), Vector2(1, 12), Crossing.Kind.STONES
	)["crossing"] as Crossing
	assert_not_null(template)
	for k in MapDocument.MAX_CROSSINGS:
		var filler := template.copy()
		filler.id = k + 1
		_doc.crossings.append(filler)
	var editor := _editor()
	var id := editor.settlements.dress(_street(editor), "farming_hamlet")
	assert_gt(id, 0, "the dress itself stands")
	assert_eq(_doc.crossings.size(), MapDocument.MAX_CROSSINGS)
	assert_true(_doc.settlement(id).bridges.is_empty())
	var refused: Array[StringName] = []
	refused.assign(editor.settlements.last_bridges["refused"])
	assert_eq(refused, [VillageBridges.REFUSED_FULL] as Array[StringName])
	assert_string_contains(VillageBridges.refusal_text(refused), "crossings")


# --- the record and a peer ----------------------------------------------------------------------


func test_the_bridge_list_round_trips_and_is_left_out_when_empty() -> void:
	var record := Settlement.make(2, "market_town", 3, 5)
	assert_false(MapSettlementIO.settlement_json(record).has("bridges"))
	record.bridges = PackedInt32Array([4, 17])
	var json := MapSettlementIO.settlement_json(record)
	assert_eq(json["bridges"], [4, 17])
	var warnings := MapDocumentIO._WarningLog.new()
	var text := JSON.stringify(json)
	var back := MapSettlementIO.parse_list([JSON.parse_string(text)], warnings)
	assert_eq(back.size(), 1)
	assert_eq(back[0].bridges, PackedInt32Array([4, 17]))
	assert_eq(JSON.stringify(MapSettlementIO.settlement_json(back[0])), text, "byte for byte")
	for hostile: Variant in [[0], ["a"], [300], [4, 4], "4", [1, 2, 3, 4, 5, 6, 7, 8, 9]]:
		var bad := json.duplicate(true)
		bad["bridges"] = hostile
		assert_eq(MapSettlementIO.parse_list([bad], warnings).size(), 0, "%s skipped" % [hostile])


func test_a_peer_ends_with_the_same_crossings_through_dress_clear_and_undo() -> void:
	var host := _editor()
	var street := _street(host)
	var peer_doc := _river_doc()
	peer_doc.walls = _doc.walls.duplicate()
	var peer := _editor(peer_doc, AuthoringHistory.new())
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var id := host.settlements.dress(street, "farming_hamlet")
	_send(entries[-1], host, peer_doc, peer, false)
	assert_eq(_crossings_of(peer_doc), _crossings_of(_doc), "the peer gets the planks")
	assert_true(host.settlements.set_kit(id, "market_town"))
	_send(entries[-1], host, peer_doc, peer, false)
	assert_eq(_crossings_of(peer_doc), _crossings_of(_doc), "and the arch in their place")
	assert_true(host.settlements.clear(id))
	_send(entries[-1], host, peer_doc, peer, false)
	assert_eq(entries.size(), 3)
	assert_true(peer_doc.crossings.is_empty(), "and Clear takes it back")
	for k in range(entries.size() - 1, -1, -1):
		_history.undo()
		_send(entries[k], host, peer_doc, peer, true)
		assert_eq(_crossings_of(peer_doc), _crossings_of(_doc), "undo %d keeps the peer level" % k)
	assert_true(peer_doc.crossings.is_empty())


func _send(
	entry: Dictionary, host: AuthoringEditor, peer_doc: MapDocument, peer: AuthoringEditor, undo: bool
) -> void:
	for op in LiveEditCodec.ops_of(entry, host, undo):
		var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
		assert_eq(decoded["problem"], "")
		LiveEditCodec.apply(decoded["op"], peer)


static func _crossings_of(doc: MapDocument) -> String:
	var out: Array[String] = []
	for crossing in doc.crossings:
		out.append(
			(
				"%d:%d:%s:%s:%s"
				% [crossing.id, crossing.kind, crossing.start, crossing.end, crossing.levels]
			)
		)
	out.sort()
	return "|".join(out)
