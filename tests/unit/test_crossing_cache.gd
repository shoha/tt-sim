extends GutTest

## The per-crossing rebuild cache (P4d-5b): CrossingCache keys a crossing's geometry on its
## fields and the ground and water under it, and AuthoredCrossings.refresh() rebuilds only the
## crossings whose key changed, with the same geometry a full build gives.

const RIVER_LEVEL := -0.2
const BED := -1.0
## A second river across the map, far from the first, for edits that touch one body only.
const FAR_Z := 10.0

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 10.0 and (absf(p.y) <= 1.5 or absf(p.y - FAR_Z) <= 1.5):
				heights[_doc.sample_index(x, z)] = BED
	_doc.heights = heights
	var line := PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)])
	var widths := PackedFloat32Array([1.5, 1.5])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))
	var far := PackedVector2Array([Vector2(-10, FAR_Z), Vector2(10, FAR_Z)])
	_doc.water_bodies.append(WaterBody.river(2, far, widths, WaterBody.Depth.WAIST, RIVER_LEVEL))


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	MapSourceLoader.add_authored_crossings(_map, _doc, true)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func _node() -> AuthoredCrossings:
	return _map.get_node(AuthoredCrossings.NODE_NAME) as AuthoredCrossings


## A plank bridge over the first river at x.
func _plank(editor: AuthoringEditor, x: float, z: float = 0.0) -> int:
	return editor.crossings.place(Crossing.Kind.PLANK, Vector3(x, 0, z - 1), Vector3(x, 0, z + 1))


## Stepping stones over the first river at x (7 m by default: its footprint and fade, which
## the key's ground rectangle covers, stay clear of an edit at x = 0).
func _stones(editor: AuthoringEditor, x: float = 7.0) -> int:
	return editor.crossings.place(Crossing.Kind.STONES, Vector3(x, 0, -1), Vector3(x, 0, 1))


## A Raise stroke centred at world `at`.
func _raise(editor: AuthoringEditor, at: Vector3, radius: float, seconds: float) -> void:
	assert_true(editor.begin_height_stroke(HeightBrush.RAISE))
	editor.stroke_dab(at, at, radius, seconds)
	editor.flush()
	editor.end_stroke()
	editor.finish_height_work()


## Sets the ground of the first river's near bank by the plank at x = 0 (|x| <= 2.5 m,
## 1.5 m < z < 5 m) to `height`, as a sculpt and its undo would.
func _set_bank(height: float) -> void:
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			var p := _doc.sample_to_world(Vector2(x, z))
			if absf(p.x) <= 2.5 and p.y > 1.5 and p.y < 5.0:
				heights[_doc.sample_index(x, z)] = height
	_doc.heights = heights


## The vertex array of `instance`'s mesh (surface 0; every surface shares the vertices).
static func _vertices(instance: MeshInstance3D) -> PackedVector3Array:
	return instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


## The vertices of the stone mesh of stepping stones `crossing_id`'s node.
func _stone_mesh(crossing_id: int) -> PackedVector3Array:
	return _vertices(_node().get_crossing_node(crossing_id).get_node("Stones") as MeshInstance3D)


## Asserts that every node holds the geometry a full CrossingGeometry.build(doc) gives now.
func _assert_matches_full_build() -> void:
	var node := _node()
	var full := CrossingGeometry.build(_doc)
	assert_eq(node.get_child_count(), _doc.crossings.size(), "one node per crossing")
	for parts: Dictionary in full.crossings:
		var crossing := node.get_crossing_node(int(parts.id))
		assert_not_null(crossing, "node %d" % int(parts.id))
		if crossing == null:
			continue
		var wood := parts.wood as Array
		if not wood.is_empty():
			var mesh := crossing.get_node("Wood") as MeshInstance3D
			assert_eq(_vertices(mesh), wood[Mesh.ARRAY_VERTEX], "wood of %d" % int(parts.id))
		var stone := parts.stone as Array
		if not stone.is_empty() and (parts.gravel as Array).is_empty():
			var mesh := crossing.get_node_or_null("Stones") as MeshInstance3D
			if mesh == null:
				mesh = crossing.get_node("Arch") as MeshInstance3D
			assert_eq(_vertices(mesh), stone[Mesh.ARRAY_VERTEX], "stone of %d" % int(parts.id))
		var body := crossing.get_node("Collision") as StaticBody3D
		var shape := (body.get_child(0) as CollisionShape3D).shape as ConcavePolygonShape3D
		assert_eq(shape.get_faces(), parts.collision, "collision of %d" % int(parts.id))
	assert_eq(node.deck_heights, full.deck, "the deck field")


# --- CrossingCache, pure -----------------------------------------------------------------


func test_key_follows_the_fields_the_ground_and_the_water_under_the_crossing() -> void:
	var crossing := Crossing.make(
		1, Crossing.Kind.PLANK, Vector2(0, -2), Vector2(0, 2), Vector3(0.2, 0.5, 0.2), 1.5
	)
	var key := CrossingCache.key_of(_doc, crossing)
	assert_eq(CrossingCache.key_of(_doc, crossing), key, "deterministic")
	var moved := crossing.copy()
	moved.width_m = 2.0
	assert_ne(CrossingCache.key_of(_doc, moved), key, "a field")
	var heights := _doc.heights.duplicate()
	var under := Vector2i(_doc.world_to_sample(Vector2(0.3, 0.2)).round())
	heights[_doc.sample_index(under.x, under.y)] = BED - 0.5
	var far := Vector2i(_doc.world_to_sample(Vector2(8.0, 8.0)).round())
	var elsewhere := _doc.heights.duplicate()
	elsewhere[_doc.sample_index(far.x, far.y)] = 3.0
	_doc.heights = heights
	assert_ne(CrossingCache.key_of(_doc, crossing), key, "the ground under it")
	_doc.heights = elsewhere
	assert_eq(CrossingCache.key_of(_doc, crossing), key, "ground far away is not in the key")
	_doc.water_bodies[1].level_m = 0.4
	assert_eq(CrossingCache.key_of(_doc, crossing), key, "a river far away is not in the key")
	_doc.water_bodies[0].level_m = 0.1
	assert_ne(CrossingCache.key_of(_doc, crossing), key, "the river under it is")
	_doc.water_bodies[0].level_m = RIVER_LEVEL
	_doc.map_seed = 4
	assert_ne(CrossingCache.key_of(_doc, crossing), key, "the seed (rng_for)")


func test_key_sees_a_pond_through_its_mask() -> void:
	var crossing := Crossing.make(
		1, Crossing.Kind.FORD, Vector2(0, -2), Vector2(0, 2), Vector3(0.2, -0.5, 0.2), 1.5
	)
	var key := CrossingCache.key_of(_doc, crossing)
	_doc.water_bodies.append(WaterBody.pond(3, WaterBody.Depth.WAIST, 0.3))
	var mask := PackedByteArray()
	mask.resize(_doc.sample_count())
	_doc.pond_mask = mask
	assert_eq(CrossingCache.key_of(_doc, crossing), key, "a pond marked nowhere near")
	var far := Vector2i(_doc.world_to_sample(Vector2(9.0, 9.0)).round())
	mask[_doc.sample_index(far.x, far.y)] = 3
	_doc.pond_mask = mask
	assert_eq(CrossingCache.key_of(_doc, crossing), key, "marked far away")
	var under := Vector2i(_doc.world_to_sample(Vector2(0.2, 1.0)).round())
	mask[_doc.sample_index(under.x, under.y)] = 3
	_doc.pond_mask = mask
	var with_pond := CrossingCache.key_of(_doc, crossing)
	assert_ne(with_pond, key, "marked under the ford")
	_doc.water_bodies[2].level_m = 0.6
	assert_ne(CrossingCache.key_of(_doc, crossing), with_pond, "that pond's level")


func test_river_near_is_conservative_on_the_control_line() -> void:
	var bend := WaterBody.river(
		5,
		PackedVector2Array([Vector2(-8, -8), Vector2(0, -2), Vector2(8, -8)]),
		PackedFloat32Array([1.0, 1.0, 1.0]),
		WaterBody.Depth.WAIST,
		0.0
	)
	assert_true(CrossingCache.river_near(bend, Rect2(-1, -3, 2, 2)), "at the bend")
	assert_true(
		CrossingCache.river_near(bend, Rect2(-1, -5.5, 2, 1)), "inside the corner, where it is cut"
	)
	assert_false(CrossingCache.river_near(bend, Rect2(-1, 2, 2, 2)), "well away")
	assert_false(CrossingCache.river_near(bend, Rect2(-14, -14, 2, 2)), "past its end")


func test_plan_names_the_stale_crossings() -> void:
	var a := Crossing.make(1, Crossing.Kind.PLANK, Vector2(0, -2), Vector2(0, 2), Vector3.ZERO, 1.5)
	var b := Crossing.make(
		2, Crossing.Kind.STONES, Vector2(5, -2), Vector2(5, 2), Vector3.ZERO, 1.1
	)
	_doc.crossings.assign([a, b])
	var first := CrossingCache.plan(_doc, {})
	assert_eq(first.stale, PackedInt32Array([1, 2]), "everything at first")
	assert_eq((first.keys as Dictionary).keys(), [1, 2])
	var again := CrossingCache.plan(_doc, first.keys)
	assert_eq(again.stale, PackedInt32Array(), "nothing changed")
	_doc.crossings.assign([a.copy(), b])
	_doc.crossings[0].levels = Vector3(0, 0.3, 0)
	var moved := CrossingCache.plan(_doc, first.keys)
	assert_eq(moved.stale, PackedInt32Array([1]))
	_doc.crossings.assign([b])
	var gone := CrossingCache.plan(_doc, moved.keys)
	assert_eq(gone.stale, PackedInt32Array())
	assert_eq((gone.keys as Dictionary).keys(), [2], "the removed id leaves the keys")


func test_six_keys_cost_well_under_a_millisecond() -> void:
	for k in 6:
		_doc.crossings.append(
			Crossing.make(
				k + 1,
				Crossing.Kind.ARCH,
				Vector2(-9 + k * 3, -3),
				Vector2(-9 + k * 3, 3),
				Vector3(0.2, 1.0, 0.2),
				2.0
			)
		)
	CrossingCache.keys_of(_doc)
	var started := Time.get_ticks_usec()
	var runs := 20
	for _i in runs:
		CrossingCache.keys_of(_doc)
	var per_refresh_ms := (Time.get_ticks_usec() - started) / 1000.0 / runs
	gut.p("six crossings' keys: %.3f ms per refresh" % per_refresh_ms)
	assert_lt(per_refresh_ms, 5.0, "a loose bound for a loaded test machine")


# --- AuthoredCrossings.refresh with the cache ----------------------------------------------


func test_placing_a_second_crossing_builds_only_the_new_one() -> void:
	var editor := _editor()
	var node := _node()
	var first := _plank(editor, 0.0)
	assert_eq(node.builds, 1)
	var first_node := node.get_crossing_node(first)
	var second := _stones(editor)
	assert_eq(node.builds, 2, "one more build")
	assert_eq(node.last_rebuilt, 1)
	assert_same(node.get_crossing_node(first), first_node, "the first node is kept")
	assert_not_null(node.get_crossing_node(second))
	node.refresh(_doc)
	assert_eq(node.builds, 2, "a refresh with nothing changed builds nothing")
	assert_eq(node.last_rebuilt, 0)
	_assert_matches_full_build()


func test_the_deck_field_changes_with_decks_alone_and_matches_a_full_build() -> void:
	var editor := _editor()
	var node := _node()
	_plank(editor, 0.0)
	var field := node.deck_heights
	var ford := editor.crossings.place(Crossing.Kind.FORD, Vector3(-6, 0, -1), Vector3(-6, 0, 1))
	assert_true(ford >= 0, "the ford is placed: %s" % editor.crossings.last_refusal)
	assert_eq(node.deck_heights, field, "a ford leaves the deck field as it was")
	_assert_matches_full_build()
	var arch := editor.crossings.place(Crossing.Kind.ARCH, Vector3(5, 0, -1), Vector3(5, 0, 1))
	assert_true(arch >= 0, "the arch is placed: %s" % editor.crossings.last_refusal)
	assert_ne(node.deck_heights, field, "the arch's deck is added")
	_assert_matches_full_build()
	assert_true(editor.crossings.remove(arch))
	assert_eq(node.deck_heights, field, "and taken out again with it")
	_assert_matches_full_build()
	assert_true(editor.crossings.remove(ford))
	_assert_matches_full_build()


func test_deck_field_add_is_the_full_field() -> void:
	_editor()
	var editor_doc := _doc
	var a := Crossing.new()
	a.id = 1
	a.kind = Crossing.Kind.ARCH
	a.start = Vector2(-1.5, -2.0)
	a.end = Vector2(2.5, 2.2)
	a.width_m = 2.0
	a.levels = Vector3(0.1, 0.9, 0.2)
	var b := a.copy()
	b.id = 2
	b.kind = Crossing.Kind.PLANK
	b.start = Vector2(0.5, -3.0)
	b.end = Vector2(-0.5, 3.0)
	b.levels = Vector3(0.0, 1.2, 0.1)
	var both: Array[Crossing] = [a, b]
	var first: Array[Crossing] = [a]
	var second: Array[Crossing] = [b]
	var full := CrossingGeometry.deck_field(editor_doc, both)
	var added := CrossingGeometry.deck_field_add(
		editor_doc, CrossingGeometry.deck_field(editor_doc, first), second
	)
	assert_eq(added, full, "the crossed decks keep the higher one where they overlap")
	assert_eq(
		CrossingGeometry.deck_field_add(editor_doc, PackedFloat32Array(), both), full, "from none"
	)


func test_batched_ground_and_levels_are_the_per_point_values() -> void:
	# A bent river too, so the chunks cut its course to different runs of segments.
	var bend := PackedVector2Array(
		[Vector2(-9, -8), Vector2(-3, -5), Vector2(0, -7), Vector2(6, -4)]
	)
	var widths := PackedFloat32Array([0.6, 1.2, 0.8, 1.0])
	_doc.water_bodies.append(WaterBody.river(3, bend, widths, WaterBody.Depth.ANKLE, -0.4))
	var points := PackedVector2Array()
	for k in 300:
		points.append(
			Vector2(-9.0 + k * 0.06, -9.0 + 0.5 * k * 0.06) + Vector2(sin(k), cos(k * 1.7))
		)
	var near := Rect2(-12, -12, 24, 24)
	var courses := WaterGeometry.river_courses(_doc, near)
	var grounds := WaterGeometry.grounds_at(_doc, points)
	var levels := WaterGeometry.levels_along(_doc, points, courses, 9)
	var wet := 0
	for k in points.size():
		assert_eq(grounds[k], WaterGeometry.ground_at(_doc, points[k]), "ground %d" % k)
		var level := WaterGeometry.level_at(_doc, points[k], -1, courses)
		assert_eq(levels[k], level, "level %d" % k)
		if level != WaterGeometry.DRY:
			wet += 1
	assert_gt(wet, 20, "the walk crosses the rivers")


func test_a_sculpt_far_from_every_crossing_rebuilds_none() -> void:
	var editor := _editor()
	var node := _node()
	_plank(editor, 0.0)
	_stones(editor)
	var version := node.version
	_raise(editor, Vector3(-9, 0, -9), 1.5, 0.5)
	assert_eq(node.builds, 2, "the stroke reached no crossing: nothing rebuilt")
	node.refresh(_doc)
	assert_eq(node.builds, 2, "nothing rebuilt")
	assert_eq(node.version, version, "nothing changed for the grid")


func test_a_sculpt_under_one_crossing_rebuilds_that_one() -> void:
	var editor := _editor()
	var node := _node()
	var plank := _plank(editor, 0.0)
	var stones := _stones(editor)
	var stones_node := node.get_crossing_node(stones)
	var plank_node := node.get_crossing_node(plank)
	_raise(editor, Vector3(0, 0, 2.6), 1.0, 0.3)
	node.refresh(_doc)
	assert_eq(node.builds, 3, "the plank once, whether or not it re-anchored")
	assert_same(node.get_crossing_node(stones), stones_node, "the stones' node is kept")
	assert_ne(node.get_crossing_node(plank), plank_node, "the plank has a new node")
	_assert_matches_full_build()


func test_a_raise_under_the_stones_refreshes_them_without_moving_an_anchor() -> void:
	# P4d-5c: the bed rises under the stones' roots and no anchor moves, so the follow
	# re-anchors nothing; the stroke still refreshes the stones (the cache finds their ground
	# changed) and its undo refreshes them again over the restored bed. The plank, out of the
	# stroke's reach, keeps its node. (A plank's deck is independent of the bed, so the stones
	# are the subject whose geometry shows the rebuild.)
	var editor := _editor()
	var node := _node()
	var plank := _plank(editor, 0.0)
	var stones := _stones(editor)
	var plank_node := node.get_crossing_node(plank)
	var before := _doc.crossing(stones).copy()
	var mesh := _stone_mesh(stones)
	var entries := _history.undo_count()
	_raise(editor, Vector3(7, 0, 0), 0.8, 0.5)
	assert_true(_doc.crossing(stones).same_as(before), "no anchor moved")
	assert_eq(_history.undo_count(), entries + 1, "one entry: the stroke")
	assert_eq(node.builds, 3, "the stones rebuilt once by the stroke")
	assert_eq(node.last_rebuilt, 1)
	assert_same(node.get_crossing_node(plank), plank_node, "the plank's node is kept")
	assert_ne(_stone_mesh(stones), mesh, "the stones stand on the raised bed")
	_assert_matches_full_build()
	node.refresh(_doc)
	assert_eq(node.builds, 3, "nothing left stale")
	assert_ne(_history.undo(), "", "undo the stroke")
	editor.finish_height_work()
	assert_eq(node.builds, 4, "undo rebuilds the stones once, over the restored bed")
	assert_eq(_stone_mesh(stones), mesh, "as they stood")
	assert_same(node.get_crossing_node(plank), plank_node, "the plank never rebuilt")
	_assert_matches_full_build()
	assert_ne(_history.redo(), "", "redo the stroke")
	editor.finish_height_work()
	assert_eq(node.builds, 5, "redo rebuilds them once")
	_assert_matches_full_build()


func test_a_water_erase_frees_the_crossing_s_node_and_rebuilds_no_other() -> void:
	var editor := _editor()
	var node := _node()
	var near := _plank(editor, 0.0)
	var far := _plank(editor, 0.0, FAR_Z)
	assert_gt(far, 0, "a bridge over the far river")
	var near_node := node.get_crossing_node(near)
	assert_true(editor.water.erase_water_begin())
	editor.water.erase_water_dab(Vector3(0, 0, FAR_Z), Vector3(0.5, 0, FAR_Z), 1.0)
	assert_true(editor.water.erase_water_end())
	editor.finish_height_work()
	assert_eq(_doc.water_bodies.size(), 1, "the far river is gone")
	assert_null(_doc.crossing(far), "and its crossing with it")
	assert_null(node.get_crossing_node(far), "its node is freed")
	assert_same(node.get_crossing_node(near), near_node, "the other node is kept")
	assert_eq(node.builds, 2, "nothing rebuilt")
	_assert_matches_full_build()


func test_a_replace_keeping_the_id_rebuilds_that_one() -> void:
	var editor := _editor()
	var node := _node()
	var plank := _plank(editor, 0.0)
	var stones := _stones(editor)
	var stones_node := node.get_crossing_node(stones)
	var wider := editor.crossings.get_crossing(plank)
	wider.width_m = 2.0
	assert_true(editor.crossings.replace(plank, wider))
	assert_eq(node.builds, 3)
	assert_eq(node.last_rebuilt, 1)
	assert_same(node.get_crossing_node(stones), stones_node)
	_assert_matches_full_build()


func test_undo_and_redo_through_restore_rebuild_the_followed_crossing_once() -> void:
	var editor := _editor()
	var node := _node()
	var plank := _plank(editor, 0.0)
	var stones := _stones(editor)
	var stones_node := node.get_crossing_node(stones)
	var before := _doc.crossing(plank).copy()
	# The bank under the plank's end rises half a metre: it follows, re-anchored (P4b-2).
	_set_bank(0.5)
	var record := editor.crossings.follow(Rect2(-2.5, 1.5, 5, 3.5))
	assert_false(record.is_empty(), "the plank moved")
	assert_eq(node.builds, 3, "the plank rebuilt once by the follow")
	var moved := _doc.crossing(plank).copy()
	# Undo: the ground goes back, then the crossing list (AuthoringEditor._apply_height_diff).
	_set_bank(0.0)
	editor.crossings.restore(record, false)
	assert_true(_doc.crossing(plank).same_as(before))
	assert_eq(node.builds, 4, "undo rebuilds it once")
	assert_eq(node.last_rebuilt, 1)
	_assert_matches_full_build()
	_set_bank(0.5)
	editor.crossings.restore(record, true)
	assert_true(_doc.crossing(plank).same_as(moved))
	assert_eq(node.builds, 5, "redo rebuilds it once")
	assert_same(node.get_crossing_node(stones), stones_node, "the stones never rebuilt")
	_assert_matches_full_build()


func test_a_load_seeds_the_keys_so_the_first_edit_rebuilds_nothing_else() -> void:
	var editor := _editor()
	_plank(editor, 0.0)
	_stones(editor)
	# A second map made from the same document the way a load does: the worker's parts.
	var other := Node3D.new()
	add_child_autofree(other)
	var built: Dictionary = AuthoredLoadPrep.compute(_doc)[AuthoredLoadPrep.CROSSINGS]
	var loaded := MapSourceLoader.add_authored_crossings(other, _doc, true, built)
	assert_eq(loaded.builds, 0, "the worker built them")
	assert_eq(loaded.keys().size(), 2, "the keys are seeded")
	loaded.refresh(_doc)
	assert_eq(loaded.builds, 0, "nothing to rebuild")
	var stones_node := loaded.get_crossing_node(2)
	_doc.crossings[0].width_m = 2.0
	loaded.refresh(_doc)
	assert_eq(loaded.builds, 1, "the changed one only")
	assert_same(loaded.get_crossing_node(2), stones_node)
	var full := CrossingGeometry.build(_doc)
	assert_almost_eq(
		loaded.top_y, maxf(float(full.crossings[0].top), float(full.crossings[1].top)), 1e-6
	)
	# Removing a crossing frees its node and recomputes the top and the deck field.
	_doc.crossings.remove_at(0)
	loaded.refresh(_doc)
	assert_null(loaded.get_crossing_node(1))
	assert_false(loaded.has_decks(), "no deck without the plank")
	assert_eq(loaded.builds, 1)
