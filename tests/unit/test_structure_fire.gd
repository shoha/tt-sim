extends GutTest

## A fire over a house in a forest, end to end without a network (card painter-structure-fire;
## test_fire_event's harness): the GM's board and a client's play it painted, the house stands
## collapsing on both until the change, then the GM's change is one history entry of three parts
## (the burnt biome, the ash, the structures) and the client's copy gets the ruin as ops; the maps
## match, an undo brings the house back on both, and a late joiner gets only the ops. Under Classic
## (no painted host) nothing of the house plays and the same change still lands.

const STATE := {"sheet": "core", "mood": "summer", "elevation": 60.0}
const DIR := "user://_painter-structure-fire_test/"
const LEVEL := DIR + "map.ttmap"
const FOREST := "temperate_forest_summer_s1"
const MAP_CELLS := 24
const SEED := 91
const FOREST_EDGE_X := 2.0
const SETTLE_S := 45.0
const FIRE_CENTRE := Vector2(-9.0, 8.0)
const RADIUS := 5.0
const HOUSE := "core:stone_house"

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


func _make_level() -> bool:
	StructureRecipes.ensure_served()
	var doc := MapDocument.create_flat(Vector2i(MAP_CELLS, MAP_CELLS), "grass_birch", "fire", SEED)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x < FOREST_EDGE_X:
				slots[doc.sample_index(x, z)] = 1
				density[doc.sample_index(x, z)] = 220
	doc.biome_slots = slots
	doc.biome_density = density
	var plan := PackedVector2Array(
		[Vector2(-12, 5.5), Vector2(-6, 5.5), Vector2(-6, 10.5), Vector2(-12, 10.5)]
	)
	doc.structures.append(Structure.make(1, HOUSE, plan, 5))
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	var growing := func() -> bool: return e.scatter.is_regenerating() or e.scatter.is_growing()
	var settled: bool = await _wait(growing, "the level's scatter")
	doc.scatter = e.scatter.rows_by_asset()
	doc.props = e.props.rows_by_asset()
	assert_eq(MapDocumentIO.write(doc, LEVEL), OK)
	remove_child(root)
	root.free()
	return settled


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


func _wait(busy: Callable, what: String) -> bool:
	var begin := Time.get_ticks_msec()
	while busy.call() and Time.get_ticks_msec() - begin < SETTLE_S * 1000.0:
		await get_tree().process_frame
	var settled: bool = not busy.call()
	assert_true(settled, "%s: settled within %.0f s" % [what, SETTLE_S])
	return settled


func _settle(copies: Array, what: String) -> void:
	await _wait(func() -> bool: return copies.any(_busy), what)
	await get_tree().process_frame


## The node of structure 1 in `copy`, null when it has none.
func _house(copy: Copy) -> Node3D:
	return AuthoredStructures.of_map(copy.root).get_structure_node(1)


func test_a_fire_burns_the_house_down_on_every_board_and_the_change_keeps_it() -> void:
	var made: bool = await _make_level()
	if not made:
		return
	var gm := await _load(true)
	var client := await _load(false)
	await _settle([gm, client], "the loads")
	PainterSheet.clear_cache()
	var painters: Array[PainterBuildings] = []
	for copy: Copy in [gm, client]:
		var painter := PainterBuildings.new()
		assert_true(painter.paint(copy.root, STATE), "the board draws painted")
		painters.append(painter)
	var key := gm.edits.table_key
	gm.edits.op_logged.connect(
		func(index: int, bytes: PackedByteArray) -> void: client.edits.receive_op(key, index, bytes)
	)
	gm.edits.events.started.connect(client.edits.events.receive)
	client.edits.receive_log(key, 0)
	var before := gm.doc.structures[0].copy()
	var reached := StructureBurn.ids_in(gm.doc, TerrainEvent.fire(FIRE_CENTRE, RADIUS, 9))
	assert_eq(reached, [1] as Array[int])

	var entries := []
	gm.edits.history.recorded.connect(func(recorded: Dictionary) -> void: entries.append(recorded))
	var fire := TerrainEvent.fire(FIRE_CENTRE, RADIUS, 9)
	assert_eq(gm.edits.events.start(fire), "")
	# Early in the fire the house is still standing and caught on both boards.
	for copy: Copy in [gm, client]:
		copy.edits.events.advance(0.1)
	for copy: Copy in [gm, client]:
		var effect := copy.edits.events.effects()[0] as FireSweep
		assert_eq(effect._structures.entries.size(), 1, "the house is in the fire")
		assert_gt(effect.hold_s(), fire.duration_s - 0.01, "the change waits for the collapse")
	# Run to the end of the collapse: slumped, still the old node, and no change yet.
	var wait: float = (gm.edits.events.effects()[0] as FireSweep).hold_s()
	for copy: Copy in [gm, client]:
		copy.edits.events.advance(wait - 0.2)
	for copy: Copy in [gm, client]:
		var node := _house(copy)
		assert_not_null(node, "the stand-in stands")
		assert_lt(node.transform.basis.get_scale().y, 0.5, "slumped")
		assert_eq(copy.doc.structures[0].recipe, HOUSE, "the record is unchanged until the change")
	assert_eq(entries.size(), 0, "no change before the collapse is over")
	for copy: Copy in [gm, client]:
		copy.edits.events.advance(0.4)
	await _settle([gm, client], "the fire")
	assert_eq(entries.size(), 1, "one history entry")
	assert_eq((entries[0].get("parts", []) as Array).size(), 3, "the biome, the ash, the house")
	for copy: Copy in [gm, client]:
		assert_true(StructureRuin.is_ruin(copy.doc.structures[0]), "a ruin in the document")
		assert_eq(copy.doc.structures[0].id, 1)
		assert_eq(copy.doc.structures[0].footprint.size(), 4)
		var node := _house(copy)
		assert_not_null(node, "the ruin's own node stands")
		assert_eq(node.transform, Transform3D.IDENTITY, "not the squashed stand-in")
	assert_true(gm.doc.structures[0].same_as(client.doc.structures[0]), "the boards match")
	assert_eq(client.edits.events.active_count(), 0, "every effect is gone")

	# The ruin does not burn again; an undo is one step and brings the house back.
	assert_eq(StructureBurn.ids_in(gm.doc, TerrainEvent.fire(FIRE_CENTRE, RADIUS, 9)).size(), 0)
	assert_true(gm.edits.history.is_newest(entries[0]))
	gm.edits.history.undo()
	await _settle([gm, client], "the undo")
	for copy: Copy in [gm, client]:
		assert_true(copy.doc.structures[0].same_as(before), "the house is back")

	# A late joiner gets only the ops.
	gm.edits.history.redo()
	await _settle([gm, client], "the redo")
	var joiner := await _load(false)
	await _settle([joiner], "the late joiner's load")
	joiner.edits.receive_log(key, gm.edits.op_log.size())
	for index in gm.edits.op_log.size():
		joiner.edits.receive_op(key, index, gm.edits.op_log[index])
	assert_eq(joiner.edits.events.active_count(), 0, "no motion for a late joiner")
	await _settle([gm, joiner], "the late joiner's catch-up")
	assert_true(joiner.doc.structures[0].same_as(gm.doc.structures[0]), "the ruin for the joiner")
	for painter in painters:
		painter.release()
	assert_engine_error(0, "no accent dropped")


func test_under_classic_the_house_plays_nothing_and_still_becomes_its_ruin() -> void:
	var made: bool = FileAccess.file_exists(LEVEL) or await _make_level()
	if not made:
		return
	var gm := await _load(true)
	await _settle([gm], "the load")
	var entries := []
	gm.edits.history.recorded.connect(func(recorded: Dictionary) -> void: entries.append(recorded))
	var fire := TerrainEvent.fire(FIRE_CENTRE, RADIUS, 9)
	assert_eq(gm.edits.events.start(fire), "")
	gm.edits.events.advance(0.1)
	var effect := gm.edits.events.effects()[0] as FireSweep
	assert_eq(effect._structures.entries.size(), 0, "no painted host: nothing of the house plays")
	assert_eq(effect.hold_s(), fire.duration_s, "the change waits for nothing")
	gm.edits.events.advance(fire.duration_s * 0.5)
	assert_eq(_house(gm).transform, Transform3D.IDENTITY, "standing through the fire")
	gm.edits.events.advance(fire.duration_s)
	await _settle([gm], "the fire")
	assert_eq(entries.size(), 1, "one history entry")
	assert_true(StructureRuin.is_ruin(gm.doc.structures[0]), "the change still leaves the ruin")
	assert_engine_error(0, "no accent dropped")
