extends Node

## Map document size and cost probe (topic mapformat; README.md in this folder). Builds the
## perfaudit net forest valley (seed 3) at each requested size, scatters it to the end headless
## (as a new map's open does) and measures what saving and reading it cost:
##   godot --headless --path <project> res://tools/map_size/doc_probe.tscn -- 100:0 200:1 320:1
## Each argument is <size ft>:<fill>; fill 1 paints the forest at full density everywhere. Lines
## start with `MF|`. The built rows are kept in user://_mapformat_/rows_<size>_<fill>.bin
## (var_to_bytes of {scatter, props, anchors}) for offline experiments; `clean` as the only
## argument deletes the folder's files. Output files all live in user://_mapformat_/.

const FOREST := "temperate_forest_summer_s1"
const MAP_SEED := 3
const DIR := "user://_mapformat_"
const READ_RUNS := 3


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() == 1 and args[0] == "clean":
		_clean()
		get_tree().quit(0)
		return
	DirAccess.make_dir_recursive_absolute(DIR)
	var failed := false
	for spec in args:
		var parts := String(spec).split(":")
		var size := int(parts[0])
		var fill := parts.size() > 1 and parts[1] == "1"
		var doc := await _build(size, fill)
		if doc == null:
			print("MF|%s|build failed" % spec)
			failed = true
			continue
		_measure(doc, "%d_%d" % [size, 1 if fill else 0])
	get_tree().quit(1 if failed else 0)


func _build(size: int, fill: bool) -> MapDocument:
	var doc := NewMap.create(
		size, FOREST, MAP_SEED, PaletteLibrary.DEFAULT_ROOT, StartingLandform.VALLEY
	)
	if doc == null:
		return null
	if fill:
		if doc.biome_ids.is_empty():
			doc.biome_ids = PackedStringArray([FOREST])
		doc.biome_slots.fill(doc.biome_ids.find(FOREST) + 1)
		doc.biome_density.fill(255)
	var loader := MapSourceLoader.new(get_tree())
	loader.separate_props = true
	var root := await loader.build_async("", doc)
	if root == null:
		return null
	add_child(root)
	var scatter := root.get_node(MapSourceLoader.SCATTER_NODE) as AuthoredScatter
	scatter.attach_document(doc)
	var e := AuthoringEditor.create(doc, root, AuthoringHistory.new())
	e.scatter.request_region(Rect2(-doc.extent_m() * 0.5, doc.extent_m()))
	e.finish_height_work()
	while e.scatter.is_regenerating() or e.scatter.is_growing():
		await get_tree().process_frame
	doc.scatter = e.scatter.rows_by_asset()
	doc.mass_anchors = ScatterMass.anchors_entry(e.scatter.mass_anchors, doc.scatter)
	doc.props = e.props.rows_by_asset()
	remove_child(root)
	root.free()
	return doc


func _measure(doc: MapDocument, tag: String) -> void:
	var rows_file := FileAccess.open("%s/rows_%s.bin" % [DIR, tag], FileAccess.WRITE)
	rows_file.store_buffer(
		var_to_bytes({"scatter": doc.scatter, "props": doc.props, "anchors": doc.mass_anchors})
	)
	rows_file.close()
	var path := "%s/doc_%s.ttmap" % [DIR, tag]
	var t0 := Time.get_ticks_usec()
	var snapshot := MapDocumentSnapshot.capture(doc)
	var t1 := Time.get_ticks_usec()
	var packed := snapshot.encode()
	var t2 := Time.get_ticks_usec()
	var snapshot2 := MapDocumentSnapshot.capture(doc)
	var t3 := Time.get_ticks_usec()
	var err := MapDocumentIO.write_snapshot(snapshot2, path)
	var t4 := Time.get_ticks_usec()
	var file := FileAccess.get_file_as_bytes(path)
	var entries: Dictionary = packed["entries"]
	var parts: PackedStringArray = []
	for entry_name: String in entries:
		var bytes: PackedByteArray = entries[entry_name]
		if bytes.size() > 4096:
			parts.append(
				(
					"%s %d (deflate %d)"
					% [
						entry_name,
						bytes.size(),
						bytes.compress(FileAccess.COMPRESSION_DEFLATE).size()
					]
				)
			)
	var z0 := Time.get_ticks_usec()
	var zstd := file.compress(FileAccess.COMPRESSION_ZSTD)
	var z1 := Time.get_ticks_usec()
	print(
		(
			"MF|%s|rows %d props %d anchors-assets %d|file %d B|zstd %d B (%.1f ms)|entries: %s"
			% [
				tag,
				MapDocument.row_count(doc.scatter),
				MapDocument.row_count(doc.props),
				doc.mass_anchors.size(),
				file.size(),
				zstd.size(),
				(z1 - z0) / 1000.0,
				", ".join(parts)
			]
		)
	)
	print(
		(
			(
				"MF|%s|capture %.2f ms|encode %.0f ms (error '%s')"
				+ "|write_snapshot (encode+zip+rename) %.0f ms err %d"
			)
			% [
				tag,
				(t1 - t0) / 1000.0,
				(t2 - t1) / 1000.0,
				str(packed["error"]),
				(t4 - t3) / 1000.0,
				err
			]
		)
	)
	var best_read := 1.0e12
	var best_extract := 1.0e12
	var read_rows := 0
	for run in READ_RUNS:
		var r0 := Time.get_ticks_usec()
		var warn_log := MapDocumentIO._WarningLog.new()
		MapDocumentIO._extract_entries(path, warn_log)
		var r1 := Time.get_ticks_usec()
		var result := MapDocumentIO.read(path)
		var r2 := Time.get_ticks_usec()
		best_extract = minf(best_extract, r1 - r0)
		best_read = minf(best_read, r2 - r1)
		var loaded: MapDocument = result["document"]
		read_rows = MapDocument.row_count(loaded.scatter) if loaded != null else -1
		if run == 0 and not (result["warnings"] as PackedStringArray).is_empty():
			print("MF|%s|read warnings: %s" % [tag, str(result["warnings"])])
	print(
		(
			"MF|%s|read %.0f ms (zip extract only %.0f ms, so parse %.0f ms), rows read %d"
			% [
				tag,
				best_read / 1000.0,
				best_extract / 1000.0,
				(best_read - best_extract) / 1000.0,
				read_rows
			]
		)
	)


func _clean() -> void:
	var dir := DirAccess.open(DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	print("MF|cleaned %s, folder files left: %d" % [DIR, dir.get_files().size()])
