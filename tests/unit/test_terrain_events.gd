extends GutTest

## TerrainEvents, the table's terrain events, end to end without a network: the level of
## test_live_edits_table (a forest west of a river, a plank bridge over it) loaded as the GM's
## copy and a client's, each with its LiveEdits and their TerrainEvents. The GM starts a bridge
## collapse and a forest fall; the event's bytes reach the client's service (as
## NetworkGameSync would hand them over) and both boards play it: the bridge hidden behind its
## falling pieces, the trees hidden in their chunks behind toppling stand-ins. Only once it has
## played does the GM's side make the map change, one history entry labelled for the event,
## which reaches the client as an op; the maps then match. An undo restores the trees without
## playing anything, and a late joiner gets only the ops.

const DIR := "user://_terrain_events_test/"
const LEVEL := DIR + "map.ttmap"
const FOREST := "temperate_forest_summer_s1"
const MAP_CELLS := 24
const SEED := 77
const FOREST_EDGE_X := 2.0
const RIVER: Array[Vector2] = [Vector2(8, -20), Vector2(9, 0), Vector2(10, 20)]
const SETTLE_FRAMES := 900
const FALL_CENTRE := Vector2(-9.0, 6.0)
const FALL_RADIUS := 5.0


class Copy:
	var root: Node3D = null
	var doc: MapDocument = null
	var edits: LiveEdits = null


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	for file_name in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR + file_name)
	DirAccess.remove_absolute(DIR.trim_suffix("/"))


func _make_level() -> void:
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass", "net", SEED)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x < FOREST_EDGE_X:
				slots[doc.sample_index(x, z)] = 1
				density[doc.sample_index(x, z)] = 200
	doc.biome_slots = slots
	doc.biome_density = density
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var river := e.water.carve_river(
		PackedVector2Array(RIVER), PackedFloat32Array([1.4]), WaterBody.Depth.WAIST
	)
	assert_gt(river, 0, "the river is carved")
	assert_gt(e.crossings.place(Crossing.Kind.PLANK, Vector3(5, 0, 0), Vector3(13, 0, 0)), 0)
	e.finish_height_work()
	var frames := 0
	while frames < SETTLE_FRAMES and (e.scatter.is_regenerating() or e.scatter.is_growing()):
		await get_tree().process_frame
		frames += 1
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(doc, LEVEL), OK)
	remove_child(root)
	root.free()


func _load(sends: bool) -> Copy:
	var loader := MapSourceLoader.new(get_tree())
	loader.keep_props_apart = true
	var copy := Copy.new()
	copy.root = await loader.load_async("", LEVEL)
	copy.doc = loader.document
	assert_not_null(copy.root, "the level loads")
	add_child_autofree(copy.root)
	copy.edits = LiveEdits.create(copy.root, copy.doc, sends)
	add_child_autofree(copy.edits)
	return copy


func _busy(copy: Copy) -> bool:
	var e := copy.edits.editor
	return (
		not copy.edits.is_settled()
		or e.scatter.is_regenerating()
		or e.scatter.is_growing()
		or e.props.is_growing()
		or copy.edits.events.active_count() > 0
	)


func _settle(copies: Array) -> void:
	var frames := 0
	while frames < SETTLE_FRAMES and copies.any(_busy):
		await get_tree().process_frame
		frames += 1
	assert_lt(frames, SETTLE_FRAMES, "settled within %d frames" % SETTLE_FRAMES)
	await get_tree().process_frame


func _same(a: Copy, b: Copy, label: String) -> void:
	var diff := MapFingerprint.diff(MapFingerprint.of(a.root, a.doc), MapFingerprint.of(b.root, b.doc))
	assert_true(diff.is_empty(), "%s: the maps differ in %s" % [label, str(diff)])


## Both services `seconds` further on.
func _advance(copies: Array, seconds: float) -> void:
	for copy: Copy in copies:
		copy.edits.events.advance(seconds)


func _crossing_node(copy: Copy, id: int) -> Node3D:
	return AuthoredCrossings.of_map(copy.root).get_crossing_node(id)


func test_a_bridge_collapse_and_a_forest_fall_play_on_every_board_then_change_the_map() -> void:
	await _make_level()
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client])
	var key := gm.edits.table_key
	gm.edits.op_logged.connect(
		func(index: int, bytes: PackedByteArray) -> void: client.edits.receive_op(key, index, bytes)
	)
	gm.edits.events.started.connect(client.edits.events.receive)
	client.edits.receive_log(key, 0)

	# The bridge.
	var bridge := gm.doc.crossings[0]
	var middle := (bridge.start + bridge.end) * 0.5
	var collapse := TerrainEvent.bridge_collapse(bridge.id, middle, 11)
	assert_eq(gm.edits.events.start(collapse), "", "the GM's side starts the collapse")
	assert_eq(client.edits.events.active_count(), 1, "the client plays it too")
	assert_eq(
		gm.edits.events.start(TerrainEvent.bridge_collapse(bridge.id, middle, 12)),
		TerrainEvents.BUSY,
		"a falling bridge does not fall twice"
	)
	_advance([gm, client], 0.6)
	assert_eq(gm.edits.events.effects().size(), 1, "the GM's board plays it")
	assert_eq(client.edits.events.effects().size(), 1, "the client's board plays it")
	for copy: Copy in [gm, client]:
		assert_false(_crossing_node(copy, bridge.id).visible, "the bridge hides behind its pieces")
	assert_eq(gm.doc.crossings.size(), 1, "the map changes only once it has played")
	assert_eq(gm.edits.op_log.size(), 0)
	_advance([gm, client], collapse.duration_s)
	assert_eq(gm.doc.crossings.size(), 0, "then the crossing is removed")
	assert_eq(gm.edits.history.undo_count(), 1, "as one history entry")
	await _settle([gm, client])
	assert_eq(gm.edits.op_log.size(), 1, "one op")
	assert_eq(client.doc.crossings.size(), 0, "the client has it")
	assert_eq(client.edits.events.active_count(), 0, "every effect is gone")
	_same(gm, client, "after the collapse")

	# The forest.
	var gm_trees := ForestFall.trees_near(gm.edits.editor.scatter, FALL_CENTRE, FALL_RADIUS)
	assert_gt(gm_trees.size(), 2, "trees stand where the forest falls")
	var labels := []
	gm.edits.history.recorded.connect(
		func(entry: Dictionary) -> void: labels.append([entry.label, entry.get("preset", 0)])
	)
	var fall := TerrainEvent.forest_fall(FALL_CENTRE, FALL_RADIUS, 21)
	assert_eq(gm.edits.events.start(fall), "")
	assert_eq(client.edits.events.active_count(), 1)
	_advance([gm, client], 1.0)
	assert_eq(gm.edits.op_log.size(), 1, "no op while the trees fall")
	_advance([gm, client], fall.duration_s)
	assert_eq(labels, [["Forest fall", TerrainEvent.Kind.FOREST_FALL]], "labelled for the event")
	await _settle([gm, client])
	assert_eq(gm.edits.op_log.size(), 2)
	assert_eq(client.edits.op_log.size(), 2)
	for copy: Copy in [gm, client]:
		var left := ForestFall.trees_near(copy.edits.editor.scatter, FALL_CENTRE, FALL_RADIUS)
		assert_eq(left.size(), 0, "no tree stands where the forest fell")
	_same(gm, client, "after the fall")

	# Undo: the trees come back and nothing plays.
	assert_eq(gm.edits.history.undo(), "Forest fall")
	assert_eq(gm.edits.events.active_count(), 0, "an undo plays no effect")
	await _settle([gm, client])
	assert_eq(client.edits.events.active_count(), 0)
	var back := ForestFall.trees_near(gm.edits.editor.scatter, FALL_CENTRE, FALL_RADIUS)
	assert_eq(back.size(), gm_trees.size(), "the undo stands every tree up again")
	_same(gm, client, "after the undo")

	# A late joiner gets only the ops.
	var joiner := await _load(false)
	await _settle([joiner])
	joiner.edits.receive_log(key, gm.edits.op_log.size())
	for index in gm.edits.op_log.size():
		joiner.edits.receive_op(key, index, gm.edits.op_log[index])
	assert_eq(joiner.edits.events.active_count(), 0, "the late joiner sees no motion")
	await _settle([gm, joiner])
	_same(gm, joiner, "late joiner")

	# Another table's event, or bytes that are no event, play nothing.
	var other := TerrainEvent.forest_fall(FALL_CENTRE, FALL_RADIUS, 1)
	other.table_key = key + 2
	client.edits.events.receive(other.encode())
	client.edits.events.receive(PackedByteArray([1, 2, 3]))
	assert_eq(client.edits.events.active_count(), 0, "dropped without a word")


func test_a_client_never_starts_an_event() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)
	var root := Node3D.new()
	add_child_autofree(root)
	var edits := LiveEdits.create(root, doc, false)
	add_child_autofree(edits)
	var event := TerrainEvent.forest_fall(Vector2.ZERO, 3.0, 1)
	assert_eq(edits.events.start(event), TerrainEvents.NOT_GM)
	assert_eq(edits.events.active_count(), 0)
