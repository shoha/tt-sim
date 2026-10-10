extends GutTest

## LiveEditCodec on small maps: a real stroke's op reads back, hostile payloads are refused
## before anything is applied (the byte cap, the op's shape, rectangles, mask names, block
## sizes, slots, palette ids, heights, the pond mask, crossings, rows and their cells), the
## palette's id tables are cached, and apply() keeps ops in order: a sculpt returns with its
## height work queued, and the next op finishes it first. The nine-op identity check on a 200 ft
## map is test_live_map_edits.gd.

const FOREST := "temperate_forest_summer_s1"


func _small_doc() -> MapDocument:
	return MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)


## A valid mask op on a small document (a real stroke's after side).
func _mask_op() -> Dictionary:
	var stroke := MaskStroke.begin(_small_doc(), MaskBrush.PAINT, FOREST)
	stroke.dab(Vector2(-1, 0), Vector2(1, 0), 1.0, 0.5)
	return LiveEditCodec._op("mask", [LiveEditCodec._diff_after(stroke.finish())])


## A valid heights op (one block raised 0.5 m) on a small document.
func _height_op() -> Dictionary:
	var doc := _small_doc()
	var stroke := HeightStroke.begin(doc, HeightBrush.RAISE)
	stroke.dab(Vector2(-1, 0), Vector2(1, 0), 1.5, 1.0)
	var record := {"props_after": {}, "kept": {}, "crossings": {}}
	return LiveEditCodec._op("height", [LiveEditCodec._diff_after(stroke.finish()), record])


func _refused(op: Dictionary, doc: MapDocument) -> String:
	return LiveEditCodec.decode(LiveEditCodec.encode(op), doc).problem


func _tamper_mask(op: Dictionary, why: String) -> void:
	var diff: Dictionary = op.args[0]
	var block: Dictionary = diff.blocks[0]
	match why:
		"an unknown kind":
			op.kind = "terraform"
		"another version":
			op.v = LiveEditCodec.VERSION + 1
		"a rectangle off the grid":
			block.rect = Rect2i(10, 10, 40, 40)
		"a property that is not a mask":
			block.after = {&"heights": block.after[MaskStroke.SLOTS]}
		"an allocated property that is not a mask":
			diff.allocated = [&"map_seed"]
		"a block short of its rectangle":
			block.after[MaskStroke.DENSITY] = PackedByteArray([1, 2, 3]).compress(
				LiveEditReader.COMPRESSION
			)
		"a slot past the biome list":
			diff.ids_after = PackedStringArray()
		"an unknown biome":
			diff.ids_after = PackedStringArray(["no_such_biome"])
		"a repeated biome":
			diff.ids_after = PackedStringArray([FOREST, FOREST])


func test_the_decoder_refuses_hostile_payloads() -> void:
	var doc := _small_doc()
	var good := _mask_op()
	assert_eq(_refused(good, doc), "", "a real stroke reads back")
	for why in [
		"an unknown kind",
		"another version",
		"a rectangle off the grid",
		"a property that is not a mask",
		"an allocated property that is not a mask",
		"a block short of its rectangle",
		"a slot past the biome list",
		"an unknown biome",
		"a repeated biome",
	]:
		var op := good.duplicate(true)
		_tamper_mask(op, why)
		assert_ne(_refused(op, doc), "", why)
	var oversized := PackedByteArray()
	oversized.resize(LiveEditCodec.MAX_BYTES + 1)
	assert_ne(LiveEditCodec.decode(oversized, doc).problem, "", "over the byte cap, never read")
	assert_ne(LiveEditCodec.decode(var_to_bytes([1, 2]), doc).problem, "", "not an op")
	var heights := _height_op()
	assert_eq(_refused(heights, doc), "", "a raise reads back")
	var off_grid := heights.duplicate(true)
	off_grid.args[0].changed = Rect2i(0, 0, 100, 100)
	assert_ne(_refused(off_grid, doc), "", "changed samples off the grid")
	var block: Dictionary = heights.args[0].blocks[0]
	var rect: Rect2i = block.rect
	var bad := PackedFloat32Array()
	bad.resize(rect.size.x * rect.size.y)
	bad[0] = NAN
	block.after = bad.to_byte_array().compress(LiveEditReader.COMPRESSION)
	assert_ne(_refused(heights, doc), "", "a NaN height")


func test_crossings_props_and_water_are_checked_with_the_document_rules() -> void:
	var doc := _small_doc()
	var plank := {
		"id": 1,
		"kind": "plank",
		"start": [-1.5, 0.0],
		"end": [1.5, 0.0],
		"levels": [0.1, 0.15, 0.1],
		"width_m": 1.5,
		"style": "",
	}
	assert_eq(_refused(LiveEditCodec._op("crossings", [[plank], Rect2()]), doc), "", "a bridge")
	plank.id = 0
	var crossing := LiveEditCodec._op("crossings", [[plank], Rect2()])
	assert_ne(_refused(crossing, doc), "", "a crossing with id 0")
	var asset: String = PaletteLibrary.species(FOREST)[0].assets[0]
	var row := PackedFloat32Array([1, 0, 1, 0, 0, 0, 1, 1, 1, 1])
	assert_eq(_refused(LiveEditCodec._op("props", [Vector2i.ZERO, {asset: row}]), doc), "")
	var unturned := PackedFloat32Array([1, 0, 1, 0, 0, 0, 0, 1, 1, 1])
	var far := PackedFloat32Array([5005, 0, 5, 0, 0, 0, 1, 1, 1, 1])
	var cases := {
		"a prop filed in another cell": [Vector2i(1, 0), {asset: row}],
		"an asset the palette lacks": [Vector2i.ZERO, {"x/no_such_asset": row}],
		"a part row": [Vector2i.ZERO, {asset: row.slice(0, 7)}],
		"a zero rotation": [Vector2i.ZERO, {asset: unturned}],
		"a cell far off the map": [Vector2i(500, 0), {asset: far}],
	}
	for why in cases:
		assert_ne(_refused(LiveEditCodec._op("props", cases[why]), doc), "", why)
	var pond_mask := PackedByteArray()
	pond_mask.resize(doc.sample_count())
	pond_mask[0] = 7
	var record := {
		"props_after": {},
		"kept": {},
		"crossings": {},
		"water_after":
		{
			"bodies": [],
			"pond_mask": pond_mask.compress(LiveEditReader.COMPRESSION),
			"pond_size": doc.sample_count(),
		},
		"dressing_after": {"data": PackedByteArray(), "size": 0},
		"region": Rect2i(0, 0, 4, 4),
	}
	var water := LiveEditCodec._op("water", [{}, record])
	assert_ne(_refused(water, doc), "", "a pond mask naming a pond that is not there")
	pond_mask[0] = 0
	record.water_after.pond_mask = pond_mask.compress(LiveEditReader.COMPRESSION)
	assert_eq(_refused(water, doc), "", "the emptied pond mask reads back")


func test_the_palette_tables_are_built_once() -> void:
	var root := PaletteLibrary.DEFAULT_ROOT
	var first := LiveEditReader.palette_ids(root)
	assert_true(is_same(first, LiveEditReader.palette_ids(root)), "cached")
	assert_true((first.biomes as Dictionary).has(FOREST))
	assert_true((first.assets as Dictionary).has(PaletteLibrary.species(FOREST)[0].assets[0]))


# --- apply on a small map --------------------------------------------------------------------


func _editor(doc: MapDocument) -> AuthoringEditor:
	var map := Node3D.new()
	map.name = "LevelMap"
	add_child_autofree(map)
	map.add_child(AuthoredTerrain.create(doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		map.add_child(node)
	var editor := AuthoringEditor.create(doc, map, AuthoringHistory.new())
	editor.scatter.attach_document(doc)
	return editor


## The ops of `editor`'s history entries from `count` on, as bytes.
func _sent(editor: AuthoringEditor, count: int) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	for entry: Dictionary in (editor.history.get("_undo") as Array).slice(count):
		var op := LiveEditCodec.op_of(entry, editor)
		assert_false(op.is_empty(), "a redo the codec knows (%s)" % entry.label)
		out.append(LiveEditCodec.encode(op))
	return out


func test_a_sculpt_returns_with_its_work_queued_and_the_next_op_finishes_it() -> void:
	var host := _editor(MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9))
	var peer := _editor(MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9))
	assert_true(host.begin_height_stroke(HeightBrush.RAISE))
	host.stroke_dab(Vector3(-4, 0, 0), Vector3(4, 0, 2), 5.0, 3.0)
	host.flush()
	assert_true(host.end_stroke())
	var boulder := host.species_rule(FOREST, "boulder")
	var at := Vector3(1, 0, 1)
	at.y = host.ground_height_at(at)
	assert_false(host.place_prop(boulder, at, Vector3.UP).is_empty())
	host.commit_prop_edit()
	var sent := _sent(host, 0)
	assert_eq(sent.size(), 2, "the raise and the placement")
	var sculpt := LiveEditCodec.decode(sent[0], peer.document)
	assert_eq(sculpt.problem, "")
	LiveEditCodec.apply(sculpt.op, peer)
	assert_eq(peer.document.heights, host.document.heights, "the document takes the heights")
	assert_true(peer.terrain.has_height_work(), "the chunks are queued, not updated")
	assert_true(peer.has_height_work(), "the apply returned before its height work")
	var place := LiveEditCodec.decode(sent[1], peer.document)
	assert_eq(place.problem, "")
	LiveEditCodec.apply(place.op, peer)
	assert_false(peer.has_height_work(), "the raise's work was finished before the prop")
	assert_eq(peer.props.rows_by_asset(), host.props.rows_by_asset(), "the same props")
