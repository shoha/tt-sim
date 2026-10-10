extends GutTest

## LiveEdits, the table's live map edits, end to end without a network: a saved authored level
## (forest west of a river, a plank bridge over it) is loaded three times the way play loads a
## document's map (MapSourceLoader.keep_props_apart), as the GM's copy, a client's and a late
## joiner's, each with its own LiveEdits. The GM's ops (a forest clear, a sculpt, the bridge
## removed, that removal undone) leave the GM's service as logged bytes and reach the client's
## service in order, as NetworkGameSync would hand them over; after each the two
## MapFingerprints match. The late joiner then takes the header and the whole log and has the
## GM's map at once, before any frame passes (the catch-up is drained, so the tokens that
## follow land on the edited ground). Ops of another table, repeated or past a gap are
## dropped, and a refused op stops the table taking more.

const DIR := "user://_live_edits_table/"
const LEVEL := DIR + "map.ttmap"
const FOREST := "temperate_forest_summer_s1"
## 120 ft.
const MAP_CELLS := 24
const SEED := 77
const FOREST_EDGE_X := 2.0
const RIVER: Array[Vector2] = [Vector2(8, -20), Vector2(9, 0), Vector2(10, 20)]
const SETTLE_FRAMES := 900


## One loaded copy of the level with its live edits.
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


## Builds the level with an editor (forest, river, plank bridge) and saves it.
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
	var bridge := e.crossings.place(Crossing.Kind.PLANK, Vector3(5, 0, 0), Vector3(13, 0, 0))
	assert_gt(bridge, 0, "a plank bridge spans the river")
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


## The saved level loaded as play loads it, with live edits on the GM's side (`sends`) or a
## client's.
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
	var water := copy.root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	return (
		not copy.edits.is_settled()
		or e.scatter.is_regenerating()
		or e.scatter.is_growing()
		or e.props.is_growing()
		or (water != null and water.is_refreshing())
	)


## Frames until every copy has nothing left to do (its LiveEdits steps itself each frame).
func _settle(copies: Array) -> void:
	var frames := 0
	while frames < SETTLE_FRAMES and copies.any(_busy):
		await get_tree().process_frame
		frames += 1
	assert_lt(frames, SETTLE_FRAMES, "settled within %d frames" % SETTLE_FRAMES)
	# Freed nodes (a removed crossing's) leave at the end of a frame.
	await get_tree().process_frame


func _same(a: Copy, b: Copy, label: String) -> void:
	var diff := MapFingerprint.diff(MapFingerprint.of(a.root, a.doc), MapFingerprint.of(b.root, b.doc))
	assert_true(diff.is_empty(), "%s: the maps differ in %s" % [label, str(diff)])


func _dabs(e: AuthoringEditor, points: Array, radius: float, seconds: float) -> void:
	var last: Vector3 = points[0]
	for p: Vector3 in points:
		e.stroke_dab(last, p, radius, seconds)
		e.flush()
		last = p
	assert_true(e.end_stroke(), "the stroke changed the map")


func _clear(e: AuthoringEditor) -> void:
	assert_true(e.begin_stroke(MaskBrush.CLEAR))
	_dabs(e, [Vector3(-18, 0, -6), Vector3(-10, 0, -7), Vector3(-4, 0, -8)], 4.0, 0.6)


func _raise(e: AuthoringEditor) -> void:
	assert_true(e.begin_height_stroke(HeightBrush.RAISE))
	_dabs(e, [Vector3(-14, 0, 10), Vector3(-11, 0, 12), Vector3(-8, 0, 14)], 4.0, 0.5)


func _remove_bridge(e: AuthoringEditor) -> void:
	assert_eq(e.document.crossings.size(), 1)
	assert_true(e.crossings.remove(e.document.crossings[0].id))


func _undo(e: AuthoringEditor) -> void:
	assert_ne(e.history.undo(), "", "the bridge removal is undone")


func test_the_gm_edits_reach_a_client_and_a_late_joiner_in_order() -> void:
	await _make_level()
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client])
	_same(gm, client, "loaded")
	var key := gm.edits.table_key
	assert_ne(key, 0, "the GM's side draws its table key")
	assert_eq(client.edits.table_key, 0, "a client waits for the host's header")
	gm.edits.op_logged.connect(
		func(index: int, bytes: PackedByteArray) -> void:
			client.edits.receive_op(key, index, bytes)
	)
	client.edits.receive_log(key, 0)
	assert_eq(client.edits.table_key, key)
	var e := gm.edits.editor
	for step: Array in [
		["forest clear", _clear],
		["sculpt raise", _raise],
		["bridge removal", _remove_bridge],
		["undo", _undo],
	]:
		var before := gm.edits.op_log.size()
		(step[1] as Callable).call(e)
		await _settle([gm, client])
		assert_eq(gm.edits.op_log.size(), before + 1, "%s: one op logged" % step[0])
		assert_eq(client.edits.op_log.size(), gm.edits.op_log.size(), "%s: received" % step[0])
		_same(gm, client, step[0])
	assert_eq(gm.doc.crossings.size(), 1, "the undo put the bridge back")
	var undo_op := LiveEditCodec.decode(gm.edits.op_log[3], gm.doc)
	assert_eq(undo_op.op.kind, "crossings", "the undo travelled as the bridge list before")

	var joiner := await _load(false)
	await _settle([joiner])
	var heard := []
	joiner.edits.caught_up.connect(func(count: int) -> void: heard.append(count))
	var ops := gm.edits.op_log
	joiner.edits.receive_op(key, 0, ops[0])
	assert_eq(joiner.edits.op_log.size(), 0, "an op before the header is dropped")
	joiner.edits.receive_log(key, ops.size())
	for index in ops.size():
		joiner.edits.receive_op(key, index, ops[index])
	assert_eq(heard, [ops.size()], "caught up once the last op is in")
	assert_eq(joiner.doc.heights, gm.doc.heights, "the ground is edited at once")
	assert_false(joiner.edits.editor.has_height_work(), "its height work is done at once")
	await _settle([gm, joiner])
	_same(gm, joiner, "late joiner")

	joiner.edits.receive_op(key, 1, ops[1])
	joiner.edits.receive_op(key + 2, ops.size(), ops[0])
	joiner.edits.receive_op(key, ops.size() + 3, ops[0])
	assert_eq(joiner.edits.op_log.size(), ops.size(), "a repeat, another table and a gap dropped")
	var hostile := var_to_bytes({"v": LiveEditCodec.VERSION, "kind": "terraform", "args": []})
	joiner.edits.receive_op(key, ops.size(), hostile)
	assert_ne(joiner.edits.problem, "", "a refused op stops the table")
	assert_engine_error(1, "one warning says the map is out of step")
	joiner.edits.receive_op(key, ops.size(), ops[0])
	assert_eq(joiner.edits.op_log.size(), ops.size(), "and nothing more is taken")


func test_a_map_without_a_document_takes_no_live_edits() -> void:
	assert_ne(LiveEdits.refusal(null), "", "a Blender map says why")
	assert_eq(LiveEdits.refusal(MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)), "")
