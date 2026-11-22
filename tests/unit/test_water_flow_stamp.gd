extends GutTest

## The flow map as derived data (WaterFlowBaker.stamp, refreshed, store): a level written
## without its flow, one whose flow was baked from other inputs (an edit outside the editor, an
## older build) loads with the flow baked again, and a fresh one loads as stored, at the cost of
## the stamp only. Before card painter-water-flowbake (2026-11-21) a level written without a flow
## drew its rivers as still water at every load.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const DIR := "user://test_water_flow_stamp"
const BIOME := "temperate_forest_summer_s1"

var _root: Node3D = null


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(DIR)


func after_each() -> void:
	if _root != null:
		_root.free()
		_root = null


## A 20 x 20 map with a river and a pond, its flow baked and stamped (Fixtures.add_water).
func _water_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	Fixtures.add_water(doc)
	return doc


## `doc` written to a file and read back.
func _saved_and_read(doc: MapDocument, file_name: String) -> MapDocument:
	var path := DIR.path_join(file_name)
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray(), file_name)
	return result["document"]


func _without_flow(doc: MapDocument) -> MapDocument:
	doc.water_flow = PackedByteArray()
	doc.water_flow_size = Vector2i.ZERO
	doc.water_flow_stamp = ""
	return doc


func test_the_stamp_survives_a_save_and_a_reload() -> void:
	var doc := _water_doc()
	assert_eq(doc.water_flow_stamp.length(), WaterFlowBaker.STAMP_LENGTH)
	var read := _saved_and_read(doc, "fresh.ttmap")
	assert_eq(read.water_flow_stamp, doc.water_flow_stamp, "stored")
	assert_eq(WaterFlowBaker.stamp(read), doc.water_flow_stamp, "the reloaded inputs stamp the same")
	assert_true(WaterFlowBaker.is_fresh(read))


func test_a_level_saved_without_flow_loads_with_flow() -> void:
	var read := _saved_and_read(_without_flow(_water_doc()), "flowless.ttmap")
	assert_true(read.water_flow.is_empty(), "written without a flow")
	var prepared := AuthoredLoadPrep.start(read).finish()
	assert_true(prepared.has(AuthoredLoadPrep.FLOW), "the load checks the flow")
	WaterFlowBaker.store(read, prepared[AuthoredLoadPrep.FLOW])
	var size := WaterFlowBaker.resolution_for(read.extent_m())
	assert_eq(read.water_flow_size, size)
	assert_true(read.water_flow == WaterFlowBaker.bake(read, size), "the bake")
	assert_true(WaterFlowBaker.is_fresh(read))


func test_the_loader_bakes_a_missing_flow() -> void:
	# A new map's ground (a served biome), so the load finds its surfaces.
	var doc := NewMap.create(100, BIOME, 1234)
	Fixtures.add_water(doc)
	var read := _saved_and_read(_without_flow(doc), "loader.ttmap")
	_root = await MapSourceLoader.new(get_tree()).build_async("", read)
	assert_not_null(_root, "built")
	assert_false(read.water_flow.is_empty(), "the document carries the flow")
	assert_true(WaterFlowBaker.is_fresh(read))
	var water := _root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	assert_not_null(water, "the water")


func test_a_dressed_map_bakes_a_missing_flow() -> void:
	# A GLB's root takes the water without the prep: AuthoredWater.create bakes in place.
	var doc := _without_flow(_water_doc())
	var water := AuthoredWater.create(doc)
	assert_false(doc.water_flow.is_empty())
	assert_true(WaterFlowBaker.is_fresh(doc))
	water.free()


func test_a_stale_flow_is_rebuilt() -> void:
	# The warm-up's carved channel, so the river is wet and its flow not still everywhere.
	var doc := AuthoredWater.warmup_document()
	assert_true(WaterFlowBaker.ensure(doc), "baked")
	var read := _saved_and_read(doc, "stale.ttmap")
	assert_true(WaterFlowBaker.is_fresh(read), "fresh as saved")
	var old := read.water_flow
	# An edit made outside the editor: the river bends, the flow does not.
	var river := read.water_bodies[0]
	var points := river.points.duplicate()
	points[1] += Vector2(0.0, 0.75)
	river.points = points
	assert_false(WaterFlowBaker.is_fresh(read), "stale")
	var result := WaterFlowBaker.refreshed(read)
	assert_false(result.is_empty(), "rebaked")
	WaterFlowBaker.store(read, result)
	assert_true(read.water_flow != old, "a different flow")
	assert_true(read.water_flow == WaterFlowBaker.bake(read, read.water_flow_size))
	assert_true(WaterFlowBaker.is_fresh(read))


func test_a_flow_from_an_older_build_is_rebuilt() -> void:
	# A file saved before the stamp: its flow metadata has no "stamp".
	var entries: Dictionary = MapDocumentIO.serialize(_water_doc())["entries"]
	var data: Dictionary = JSON.parse_string(entries["splines.json"].get_string_from_utf8())
	(data["flow"] as Dictionary).erase("stamp")
	entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
	var read: MapDocument = MapDocumentIO.parse(entries)["document"]
	assert_false(read.water_flow.is_empty(), "the old flow is read")
	assert_eq(read.water_flow_stamp, "")
	assert_false(WaterFlowBaker.is_fresh(read))
	assert_true(WaterFlowBaker.ensure(read), "rebaked")
	assert_true(WaterFlowBaker.is_fresh(read))


func test_a_malformed_stamp_reads_as_none() -> void:
	var entries: Dictionary = MapDocumentIO.serialize(_water_doc())["entries"]
	var data: Dictionary = JSON.parse_string(entries["splines.json"].get_string_from_utf8())
	for stamp: Variant in [42, "zzzzzzzzzzzzzzzz", "abc", ["x"]]:
		data["flow"]["stamp"] = stamp
		entries["splines.json"] = JSON.stringify(data).to_utf8_buffer()
		var result := MapDocumentIO.parse(entries)
		assert_eq(result["document"].water_flow_stamp, "", str(stamp))
		assert_false(result["document"].water_flow.is_empty(), "the flow itself is kept")


func test_a_fresh_flow_is_not_rebaked() -> void:
	var read := _saved_and_read(_water_doc(), "kept.ttmap")
	var stored := read.water_flow
	var prepared := AuthoredLoadPrep.start(read).finish()
	assert_eq(prepared[AuthoredLoadPrep.FLOW], {}, "no bake at load")
	assert_eq(AuthoredLoadPrep.compute(read)[AuthoredLoadPrep.FLOW], {})
	assert_false(WaterFlowBaker.ensure(read))
	var water := AuthoredWater.create(read)
	water.free()
	assert_true(read.water_flow == stored, "the stored flow")


func test_ponds_only_carry_no_flow() -> void:
	var doc := _water_doc()
	var ponds: Array[WaterBody] = [doc.water_bodies[1]]
	doc.water_bodies = ponds
	assert_false(WaterFlowBaker.is_fresh(doc), "a flow with no river is stale")
	assert_true(WaterFlowBaker.ensure(doc))
	assert_true(doc.water_flow.is_empty())
	assert_eq(doc.water_flow_size, Vector2i.ZERO)
	assert_true(WaterFlowBaker.is_fresh(doc))
	var dry := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	assert_false(AuthoredLoadPrep.compute(dry).has(AuthoredLoadPrep.FLOW), "no water, no check")


func test_an_editor_refresh_stamps_its_bake() -> void:
	_root = Node3D.new()
	add_child(_root)
	var doc := _without_flow(_water_doc())
	var water := AuthoredWater.refresh_map(_root, doc)
	water.finish_refresh()
	assert_false(doc.water_flow.is_empty())
	assert_true(WaterFlowBaker.is_fresh(doc), "the refresh records the stamp")
	_root.get_parent().remove_child(_root)


func test_the_stamp_follows_every_input() -> void:
	var doc := _water_doc()
	var base := WaterFlowBaker.stamp(doc)
	var edits := {
		"heights":
		func(d: MapDocument) -> void:
			var h := d.heights.duplicate()
			h[5] += 0.25
			d.heights = h,
		"pond mask":
		func(d: MapDocument) -> void:
			var m := d.pond_mask.duplicate()
			m[0] = Fixtures.POND_ID
			d.pond_mask = m,
		"speed": func(d: MapDocument) -> void: d.water_bodies[0].speed = 0.5,
		"tier": func(d: MapDocument) -> void: d.tier_height_m = d.tier_height_m * 2.0,
		"seed": func(d: MapDocument) -> void: d.map_seed = d.map_seed + 1,
	}
	for label: String in edits:
		var edited := _water_doc()
		(edits[label] as Callable).call(edited)
		assert_ne(WaterFlowBaker.stamp(edited), base, label)
	assert_eq(WaterFlowBaker.stamp(_water_doc()), base, "deterministic")
