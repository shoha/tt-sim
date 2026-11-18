extends GutTest

## The buildings a fire burns (card painter-structure-fire; StructureBurn, StructureRuin,
## StructureEditor.burn_down, docs/systems/painter.md "Fire and events"): which buildings a fire
## reaches, the burn and collapse timeline and pose, the painted host's `burn` uniform on a
## building's parts, that Classic (no host) plays nothing, the ruin the change leaves as one history
## entry that travels to a peer, its undo, and a ruin that does not burn again.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const HOUSES: Array[String] = [
	"core:thatched_cottage", "core:stone_house", "core:half_timber_house"
]

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	PainterSheet.clear_cache()
	StructureRecipes.ensure_served()
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	_history = AuthoringHistory.new()


func _plan(at: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in [Vector2(-3, -2.5), Vector2(3, -2.5), Vector2(3, 2.5), Vector2(-3, 2.5)]:
		out.append(p + at)
	return out


## Three houses at x = -9, 0 and 9 (ids 1 to 3) in the document.
func _village() -> void:
	for i in HOUSES.size():
		_doc.structures.append(Structure.make(i + 1, HOUSES[i], _plan(Vector2(i * 9.0 - 9.0, 0)), 5))


func _built() -> AuthoredStructures:
	_village()
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	return structures


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	return AuthoringEditor.create(_doc, _map, _history)


func _puffs() -> Array:
	var flames := EventPuffs.new(120, FireSweep.FLAME_PRIORITY)
	var smoke := SmokePuffs.new(24)
	add_child_autofree(flames)
	add_child_autofree(smoke)
	return [flames, smoke]


func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	return rng


## `structures`' parts drawn by the painter (the host a burn needs); the caller releases it.
func _painted(structures: AuthoredStructures) -> PainterBuildings:
	var buildings := PainterBuildings.new()
	assert_true(buildings.paint(_map, STATE))
	assert_not_null(StructureBurn.host_of(structures), "the host is found by the node's meta")
	return buildings


## A burn of the middle house (id 2) of `structures` (painted), caught at second 0.
func _burn_middle(structures: AuthoredStructures) -> StructureBurn:
	var found: Array[Dictionary] = [
		{"id": 2, "centre": Vector2(0, 0), "radius": 3.9, "distance": 0.0, "start": 0.0}
	]
	var puffs := _puffs()
	var burn := StructureBurn.new()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 1)
	return burn


# --- the timeline ---------------------------------------------------------------------------


func test_the_burn_runs_on_the_trees_scale_and_the_collapse_follows_it() -> void:
	assert_eq(StructureBurn.BURN_RATE, FireSweep.BURN_RATE, "the shader's scale")
	assert_eq(StructureBurn.burn_value(-1.0, 2.4), 0.0, "nothing before it catches")
	assert_almost_eq(StructureBurn.burn_value(1.2, 2.4), StructureBurn.BURN_RATE * 0.5, 0.001)
	assert_eq(StructureBurn.burn_value(9.0, 2.4), StructureBurn.BURN_RATE, "held once out")
	assert_eq(
		StructureBurn.burn_value(1.0, 2.0), FireSweep.burn_progress(1.0, 2.0), "the trees' curve"
	)
	var burn_s := 2.4
	var start := burn_s * StructureBurn.COLLAPSE_AT
	assert_eq(StructureBurn.collapse_amount(start - 0.01, burn_s), 0.0, "it stands while it burns")
	assert_almost_eq(
		StructureBurn.collapse_amount(start + StructureBurn.COLLAPSE_S * 0.5, burn_s), 0.5, 0.001
	)
	assert_eq(StructureBurn.collapse_amount(99.0, burn_s), 1.0)
	assert_almost_eq(
		StructureBurn.end_after(burn_s), start + StructureBurn.COLLAPSE_S, 0.001, "its end"
	)
	assert_lt(
		StructureBurn.end_after(StructureBurn.BURN_S.y) + FireSweep.SPREAD_S + FireSweep.SPREAD_JITTER,
		7.0,
		"the longest a building takes after the front, inside a few seconds"
	)


func test_motion_is_held_in_ten_hertz_steps() -> void:
	assert_eq(StructureBurn.STEP_S, 0.1)
	assert_almost_eq(StructureBurn.stepped(0.19), 0.1, 0.0001)
	assert_almost_eq(StructureBurn.stepped(0.2), 0.2, 0.0001)
	assert_eq(StructureBurn.stepped(0.0), 0.0)


func test_the_slump_squashes_about_the_foot_to_the_ruin_height() -> void:
	var pivot := Vector3(4.0, 1.5, -2.0)
	var axis := Vector3.RIGHT
	assert_eq(StructureBurn.collapse_pose(0.0, pivot, axis, 1.0), Transform3D.IDENTITY)
	var done := StructureBurn.collapse_pose(1.0, pivot, axis, 1.0)
	assert_almost_eq(done.basis.get_scale().y, StructureBurn.RUIN_HEIGHT, 0.001, "to its height")
	assert_gt(done.basis.get_scale().x, 1.0, "spread a little")
	assert_true((done * pivot).is_equal_approx(pivot), "the foot stays where it stood")
	var top := pivot + Vector3(0.0, 4.0, 0.0)
	assert_lt((done * top).y - pivot.y, 4.0 * 0.4, "the roof came down")
	var mid := StructureBurn.collapse_pose(0.5, pivot, axis, 1.0)
	assert_gt(mid.basis.get_scale().y, StructureBurn.RUIN_HEIGHT)
	assert_lt(mid.basis.get_scale().y, 1.0, "part way down")
	assert_true(
		StructureBurn.collapse_pose(0.5, pivot, axis, 1.0).is_equal_approx(mid), "no randomness"
	)
	# It leans (held, not swinging back), sinks and is a strong squash from the game camera.
	var leaning := (done.basis * Vector3.UP).normalized()
	assert_almost_eq(
		leaning.angle_to(Vector3.UP), deg_to_rad(StructureBurn.LEAN_DEG), 0.01, "leaning at the end"
	)
	var sunk := StructureBurn.collapse_pose(1.0, pivot, axis, 1.0, 0.4)
	assert_almost_eq((sunk * pivot).y, pivot.y - 0.4, 0.001, "sunk into the ground")
	assert_lt(StructureBurn.RUIN_HEIGHT, 0.2, "a low heap, not a lowered house")


func test_the_burn_runs_on_into_the_break_up_and_the_flames_are_out_first() -> void:
	assert_eq(StructureBurn.break_value(-1.0), 0.0)
	assert_eq(StructureBurn.break_value(0.0), 0.0)
	assert_almost_eq(StructureBurn.break_value(0.5), StructureBurn.BREAK_SPAN * 0.5, 0.001)
	assert_eq(StructureBurn.break_value(9.0), StructureBurn.BREAK_SPAN)
	var slump_at := StructureBurn.BURN_S.x * StructureBurn.COLLAPSE_AT
	assert_lt(
		StructureBurn.BURN_S.x * StructureBurn.FLAME_WHEN.y + StructureBurn.FLAME_LIFE.y,
		slump_at,
		"no flame stands over a lowered roof"
	)
	var dust := StructureBurn.dust_color()
	assert_lt(dust.r, ForestFall.DUST.r, "darker than a fallen tree's dust")
	assert_gt(dust.a, ForestFall.DUST.a, "more opaque")
	var include := "res://painter/shaders/painter_building_burn.gdshaderinc"
	var shader := FileAccess.get_file_as_string(include)
	assert_true(
		shader.contains("const float BURN_CHARRED = %.1f;" % StructureBurn.BURN_RATE),
		"the shader's charred value is the burn's"
	)


# --- which buildings --------------------------------------------------------------------------


func test_a_circle_reaches_the_buildings_whose_footprint_it_touches() -> void:
	_village()
	var near := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 0.0), 2.0, 1))
	assert_eq(near.size(), 1, "only the house it stands on")
	assert_eq(near[0].id, 2)
	var edge := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 7.0), 4.6, 1))
	assert_eq(edge.size(), 1, "reaching a footprint's edge counts")
	var wide := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 0.0), 8.0, 1))
	assert_eq(wide.size(), 3)
	assert_eq(wide[0].id, 2, "nearest the start first")
	var missed := StructureBurn.find(_doc, TerrainEvent.fire(Vector2(0.0, 12.0), 3.0, 1))
	assert_true(missed.is_empty())
	assert_eq(StructureBurn.find(_doc, TerrainEvent.fire(Vector2.ZERO, 8.0, 1), 2).size(), 2, "limit")
	assert_eq(StructureBurn.ids_in(_doc, TerrainEvent.fire(Vector2.ZERO, 2.0, 1)), [2] as Array[int])


func test_a_path_reaches_the_buildings_it_passes_and_a_ruin_is_passed_over() -> void:
	_village()
	var line := PackedVector2Array([Vector2(-14, 0.5), Vector2(14, 0.5)])
	var event := TerrainEvent.fire_path(line, 1.5, 3)
	assert_eq(StructureBurn.find(_doc, event).size(), 3, "all three along the line")
	var aside := PackedVector2Array([Vector2(-14, 9.0), Vector2(14, 9.0)])
	assert_eq(StructureBurn.find(_doc, TerrainEvent.fire_path(aside, 1.5, 3)).size(), 0)
	_doc.structures[1] = Structure.make(2, "core:ruin_cottage", _plan(Vector2.ZERO), 5)
	assert_eq(StructureBurn.find(_doc, event).size(), 2, "a ruin does not burn again")


# --- the ruin ---------------------------------------------------------------------------------


func test_the_ruin_follows_what_the_building_was() -> void:
	assert_eq(StructureRuin.ruin_id_for("gambrel_barn", ["barn"], false), "ruin_barn")
	assert_eq(StructureRuin.ruin_id_for("stone_chapel", [], false), "ruin_chapel")
	assert_eq(StructureRuin.ruin_id_for("tudor_townhouse", ["townhouse"], false), "ruin_townhouse")
	assert_eq(StructureRuin.ruin_id_for("thatched_cottage", ["cottage"], false), "ruin_cottage")
	assert_eq(StructureRuin.ruin_id_for("watch_tower", [], true), "ruin_tower", "a round plan")
	assert_eq(StructureRuin.ruin_id_for("anything", [], false), StructureRuin.FALLBACK)


func test_a_building_becomes_its_ruin_on_the_same_footprint() -> void:
	var house := Structure.make(7, "core:stone_house", _plan(Vector2(3, 3)), 11, {}, "")
	var ruin := StructureRuin.ruin_of(house, _doc.extent_m(), 1.0)
	assert_not_null(ruin, "a ruin fits")
	assert_eq(ruin.id, 7, "the same record")
	assert_eq(ruin.seed_value, 11)
	assert_true(ruin.recipe.begins_with("core:ruin_"), ruin.recipe)
	assert_eq(MapStructureIO.structure_problem(ruin, _doc.extent_m()), "")
	assert_true(StructureRuin.is_ruin(ruin))
	assert_false(StructureRuin.is_ruin(house))
	assert_null(StructureRuin.ruin_of(ruin, _doc.extent_m(), 1.0), "a ruin has no ruin")
	var drawn := StructureRecipes.document(ruin.recipe)
	if not StructureEdit.param_spec(drawn.interface, StructureRuin.PARAM).is_empty():
		assert_almost_eq(float(ruin.params["ruin"]), StructureRuin.AMOUNT, 0.001, "far gone")


func test_burning_down_is_one_history_entry_that_travels_and_undoes() -> void:
	_village()
	var editor := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	var before: Array[Structure] = editor.structures.list()
	assert_true(editor.structures.burn_down([1, 3]))
	assert_eq(entries.size(), 1, "one entry")
	assert_true(StructureRuin.is_ruin(_doc.structures[0]), "house 1 is a ruin")
	assert_true(_doc.structures[1].same_as(before[1]), "house 2 untouched")
	assert_true(StructureRuin.is_ruin(_doc.structures[2]), "house 3 is a ruin")
	assert_false(editor.structures.burn_down([1]), "a ruin burns no further: nothing changed")
	assert_false(editor.structures.burn_down([99]), "an unknown id: nothing changed")
	var op := LiveEditCodec.op_of(entries[0], editor)
	assert_eq(op.kind, "structures")
	var peer_doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	peer_doc.structures = before.duplicate()
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer.document)
	assert_eq(decoded.problem, "")
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer.document.structures.size(), 3)
	for i in 3:
		assert_true(peer.document.structures[i].same_as(_doc.structures[i]), "peer matches %d" % i)
	assert_eq(_history.undo(), "Burn down")
	for i in 3:
		assert_true(_doc.structures[i].same_as(before[i]), "the undo brings %d back" % i)


func test_a_building_no_ruin_fits_is_removed() -> void:
	var odd := Structure.make(
		5,
		"core:stone_house",
		PackedVector2Array(
			[Vector2(0, 0), Vector2(6, 0), Vector2(7, 3), Vector2(3, 6), Vector2(-1, 3)]
		),
		3
	)
	_doc.structures.append(odd)
	var editor := _editor()
	var ruin := StructureRuin.ruin_of(odd, _doc.extent_m(), 1.0)
	var changed := editor.structures.burn_down([5])
	assert_true(changed)
	if ruin == null:
		assert_eq(_doc.structures.size(), 0, "removed when no ruin fits")
	else:
		assert_eq(_doc.structures.size(), 1)
		assert_true(StructureRuin.is_ruin(_doc.structures[0]))


# --- the painted host and the play ------------------------------------------------------------


func test_a_painted_building_burns_collapses_and_is_let_go() -> void:
	var structures := _built()
	var buildings := _painted(structures)
	var node := structures.get_structure_node(2)
	var burn := _burn_middle(structures)
	var entry: Dictionary = burn.entries[0]
	assert_false((entry.actor as Dictionary).is_empty(), "the painted parts are taken")
	var part: MeshInstance3D = (entry.actor.nodes as Array)[0]
	burn.step(0.0)
	assert_eq(float(part.get_instance_shader_parameter(&"burn")), 0.0, "just caught")
	burn.step(1.3)
	var mid := float(part.get_instance_shader_parameter(&"burn"))
	assert_gt(mid, 0.0)
	assert_lt(mid, StructureBurn.BURN_RATE, "burning")
	burn.step(1.3)
	assert_eq(
		float(part.get_instance_shader_parameter(&"burn")), mid, "held within a step: no new work"
	)
	assert_eq(node.transform, Transform3D.IDENTITY, "standing before its collapse")
	burn.step(burn.end_at() + 0.2)
	assert_eq(
		float(part.get_instance_shader_parameter(&"burn")),
		StructureBurn.BURN_RATE + StructureBurn.BREAK_SPAN,
		"charred and broken up"
	)
	assert_almost_eq(node.transform.basis.get_scale().y, StructureBurn.RUIN_HEIGHT, 0.01)
	assert_lt(node.transform.origin.y, 0.0, "sunk a little")
	assert_true(burn.is_done(burn.end_at()))
	assert_false(burn.landed(), "the stand-in waits for the change")
	burn.release()
	assert_eq(node.transform, Transform3D.IDENTITY, "let go: standing as it was")
	assert_eq(float(part.get_instance_shader_parameter(&"burn")), 0.0, "unburnt")
	assert_true(burn.landed(), "nothing held")
	buildings.release()


func test_the_stand_in_is_landed_when_its_node_goes() -> void:
	var structures := _built()
	var buildings := _painted(structures)
	var burn := _burn_middle(structures)
	burn.step(burn.end_at() + 0.2)
	assert_false(burn.landed())
	var node := structures.get_structure_node(2)
	structures.remove_child(node)
	node.free()
	assert_true(burn.landed(), "the ruin's node took its place")
	burn.step(burn.end_at() + 0.4)
	burn.release()
	buildings.release()


func test_classic_plays_nothing_and_the_building_stands_until_the_change() -> void:
	var structures := _built()
	assert_null(StructureBurn.host_of(structures), "no painter, no host")
	var node := structures.get_structure_node(2)
	var found: Array[Dictionary] = [
		{"id": 2, "centre": Vector2(0, 0), "radius": 3.9, "distance": 0.0, "start": 0.0}
	]
	var puffs := _puffs()
	var burn := StructureBurn.new()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	assert_eq(burn.end_at(), 0.0, "the change waits for nothing")
	burn.step(3.0)
	assert_eq(node.transform, Transform3D.IDENTITY, "standing through the fire")
	assert_true(burn.landed())
	burn.release()


func test_a_burn_with_no_structures_node_or_a_missing_one_holds_nothing() -> void:
	var burn := StructureBurn.new()
	var puffs := _puffs()
	var found: Array[Dictionary] = [{"id": 4, "centre": Vector2.ZERO, "radius": 2.0, "start": 0.0}]
	assert_eq(burn.setup(null, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	var structures := _built()
	assert_eq(burn.setup(structures, found, puffs[0], puffs[1], _rng(), Vector3.ZERO), 0)
	assert_true(burn.landed())
	assert_eq(burn.end_at(), 0.0)
	burn.step(3.0)
	burn.release()


func test_a_fire_with_no_buildings_waits_for_nothing_of_theirs() -> void:
	var sweep := FireSweep.new()
	autofree(sweep)
	assert_eq(sweep.hold_s(), sweep.duration, "no buildings: its own duration")
