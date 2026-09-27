extends GutTest

## MapDocumentIO (utils/map_document_io.gd) at the file level: the map.ttmap round trip,
## atomic writes, serialize() refusals and the ZIP central-directory size guard. Entry
## validation is in test_map_document_validation.gd. Everything under DIR is removed in
## after_all.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const DIR := "user://test_map_document_io"


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	_remove_tree(DIR)


# --- helpers ------------------------------------------------------------------------


func _entries(doc: MapDocument) -> Dictionary:
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "", "fixture serializes")
	return packed["entries"]


func _write_zip(path: String, entries: Dictionary) -> void:
	var packer := ZIPPacker.new()
	assert_eq(packer.open(path), OK)
	for entry_name in entries:
		packer.start_file(entry_name)
		packer.write_file(entries[entry_name])
		packer.close_file()
	packer.close()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _find_last(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	for i in range(haystack.size() - needle.size(), -1, -1):
		if haystack.slice(i, i + needle.size()) == needle:
			return i
	return -1


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _assert_rows_close(actual: PackedFloat32Array, expected: PackedFloat32Array) -> void:
	assert_eq(actual.size(), expected.size())
	for i in mini(actual.size(), expected.size()):
		assert_almost_eq(actual[i], expected[i], 1e-6)


func _assert_same_document(actual: MapDocument, expected: MapDocument) -> void:
	assert_eq(actual.palette_version, expected.palette_version)
	assert_eq(actual.map_seed, expected.map_seed)
	assert_eq(actual.size_cells, expected.size_cells)
	assert_eq(actual.cell_size_m, expected.cell_size_m)
	assert_eq(actual.sample_spacing_m, expected.sample_spacing_m)
	assert_eq(actual.tier_height_m, expected.tier_height_m)
	assert_eq(actual.base_surface, expected.base_surface)
	assert_eq(actual.has_base_map, expected.has_base_map)
	assert_true(actual.heights == expected.heights, "heights are bit-exact")
	for field in ["scatter", "props"]:
		var got: Dictionary = actual.get(field)
		var want: Dictionary = expected.get(field)
		assert_eq(got.size(), want.size(), field)
		for asset_id in want:
			_assert_rows_close(got.get(asset_id, PackedFloat32Array()), want[asset_id])
	assert_true(actual.erase_mask == expected.erase_mask, "erase mask")
	assert_eq(actual.biome_ids, expected.biome_ids)
	assert_true(actual.biome_slots == expected.biome_slots, "biome slots")
	assert_true(actual.biome_density == expected.biome_density, "biome density")
	assert_eq(actual.surface_ids, expected.surface_ids)
	assert_true(actual.surface_weights == expected.surface_weights, "surface weights")


# --- round trips ------------------------------------------------------------------


func test_round_trip_through_a_file() -> void:
	var doc := Fixtures.full_doc()
	var path := DIR.path_join("round_trip.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	assert_false(FileAccess.file_exists(path + MapDocumentIO.TEMP_SUFFIX), "temp renamed away")
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray(), "a clean document reads without warnings")
	assert_not_null(result["document"])
	if result["document"] != null:
		_assert_same_document(result["document"], doc)


func test_round_trip_in_memory() -> void:
	var doc := Fixtures.full_doc()
	var result := MapDocumentIO.parse(_entries(doc))
	assert_eq(result["warnings"], PackedStringArray())
	_assert_same_document(result["document"], doc)


func test_flat_document_round_trips_without_optional_entries() -> void:
	var doc := MapDocument.create_flat(Vector2i(30, 30), "sand_red", "v1", -5)
	var entries := _entries(doc)
	assert_false(entries.has("erase.png"))
	assert_false(entries.has("authoring/biomes.png"))
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	_assert_same_document(result["document"], doc)


func test_write_replaces_an_existing_file() -> void:
	var path := DIR.path_join("replace.ttmap")
	var first := MapDocument.create_flat(Vector2i(20, 20), "", "first", 1)
	var second := MapDocument.create_flat(Vector2i(30, 30), "", "second", 2)
	assert_eq(MapDocumentIO.write(first, path), OK)
	assert_eq(MapDocumentIO.write(second, path), OK, "rename over an existing file works")
	var doc: MapDocument = MapDocumentIO.read(path)["document"]
	assert_eq(doc.palette_version, "second")
	assert_eq(doc.size_cells, Vector2i(30, 30))


func test_unknown_entries_in_a_real_archive_are_ignored() -> void:
	var path := DIR.path_join("unknown.ttmap")
	var extra := {
		"splines.json": "[]".to_utf8_buffer(),
		"future.png": Fixtures.mask_png(Vector2i(4, 4), Image.FORMAT_RGBA8),
	}
	_write_zip(path, Fixtures.minimal_entries(extra))
	var result := MapDocumentIO.read(path)
	assert_not_null(result["document"])
	assert_eq(result["warnings"], PackedStringArray())


# --- atomic write -----------------------------------------------------------------


## Failure before a byte is written: the temp path is blocked by a directory, so
## ZIPPacker.open fails. The old document must be untouched.
func test_failed_write_leaves_the_old_file_intact() -> void:
	var path := DIR.path_join("atomic_open.ttmap")
	var old := MapDocument.create_flat(Vector2i(20, 20), "", "old", 1)
	assert_eq(MapDocumentIO.write(old, path), OK)
	DirAccess.make_dir_recursive_absolute(path + MapDocumentIO.TEMP_SUFFIX)
	var err := MapDocumentIO.write(Fixtures.full_doc(), path)
	DirAccess.remove_absolute(path + MapDocumentIO.TEMP_SUFFIX)
	assert_ne(err, OK)
	assert_eq(MapDocumentIO.read(path)["document"].palette_version, "old")


## Failure after the whole new document was written, at the commit step: a held handle
## on the target makes the rename fail on Windows. The old document must be untouched
## and the temp file removed.
func test_failed_rename_leaves_the_old_file_intact() -> void:
	var path := DIR.path_join("atomic_rename.ttmap")
	var old := MapDocument.create_flat(Vector2i(20, 20), "", "old", 1)
	assert_eq(MapDocumentIO.write(old, path), OK)
	var held := FileAccess.open(path, FileAccess.READ)
	var err := MapDocumentIO.write(Fixtures.full_doc(), path)
	held.close()
	if OS.get_name() != "Windows":
		pass_test("an open handle only blocks a rename on Windows")
		return
	assert_ne(err, OK)
	assert_false(FileAccess.file_exists(path + MapDocumentIO.TEMP_SUFFIX), "temp removed")
	assert_eq(MapDocumentIO.read(path)["document"].palette_version, "old")


func test_write_refuses_a_document_the_reader_would_reject() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	doc.heights[5] = NAN
	var path := DIR.path_join("refused.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), ERR_INVALID_DATA)
	assert_engine_error(1, "one warning naming the problem")
	assert_false(FileAccess.file_exists(path))


func test_serialize_refusals() -> void:
	var inf_row := PackedFloat32Array([INF, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var zero_quat := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 1, 1, 1])
	var cases := {
		"heights": func(d: MapDocument) -> void: d.heights = PackedFloat32Array([0.0]),
		"partial row": func(d: MapDocument) -> void: d.scatter = {"a/b": PackedFloat32Array([1])},
		"asset id": func(d: MapDocument) -> void: d.props = {"": PackedFloat32Array()},
		"erase": func(d: MapDocument) -> void: d.erase_mask = PackedByteArray([1]),
		"slots": func(d: MapDocument) -> void: d.biome_slots = PackedByteArray([1]),
		"size": func(d: MapDocument) -> void: d.size_cells = Vector2i(65, 20),
		"inf row": func(d: MapDocument) -> void: d.scatter = {"a/b": inf_row},
		"zero quaternion": func(d: MapDocument) -> void: d.scatter = {"a/b": zero_quat},
		"long surface": func(d: MapDocument) -> void: d.base_surface = "x".repeat(200),
	}
	for label in cases:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
		cases[label].call(doc)
		var packed := MapDocumentIO.serialize(doc)
		assert_ne(packed["error"], "", "refused: " + label)
		assert_true(packed["entries"].is_empty(), "nothing to write: " + label)


# --- the archive guard ------------------------------------------------------------


## An archive whose central directory declares height.bin far over its cap must be
## rejected from the directory alone: ZIPReader.read_file sizes its buffer from that
## declaration (probed: a 432-byte archive claiming 400 MB allocated 400 MB).
func test_oversized_declared_entry_is_never_read() -> void:
	var path := DIR.path_join("bomb.ttmap")
	assert_eq(MapDocumentIO.write(MapDocument.create_flat(Vector2i(20, 20), "", "", 0), path), OK)
	var raw := FileAccess.get_file_as_bytes(path)
	var record := _find_last(raw, "height.bin".to_utf8_buffer()) - 46
	assert_eq(raw.decode_u32(record), 0x02014b50, "found the central directory record")
	raw.encode_u32(record + 24, 400000000)
	_write_bytes(path, raw)
	var result := MapDocumentIO.read(path)
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "over its cap"), str(result["warnings"]))


func test_zip64_archive_is_refused() -> void:
	var path := DIR.path_join("zip64.ttmap")
	_write_zip(path, Fixtures.minimal_entries())
	var raw := FileAccess.get_file_as_bytes(path)
	var eocd := raw.size() - 22
	var body := raw.slice(0, eocd)
	var record := PackedByteArray()
	record.resize(56)
	record.encode_u32(0, 0x06064b50)
	var locator := PackedByteArray()
	locator.resize(20)
	locator.encode_u32(0, 0x07064b50)
	locator.encode_u64(8, body.size())
	_write_bytes(path, body + record + locator + raw.slice(eocd))
	var result := MapDocumentIO.read(path)
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "Zip64"), str(result["warnings"]))


func test_unreadable_archives() -> void:
	var garbage := DIR.path_join("garbage.ttmap")
	_write_bytes(garbage, "definitely not a zip archive".to_utf8_buffer())
	var not_zip := MapDocumentIO.read(garbage)
	assert_null(not_zip["document"])
	assert_true(Fixtures.has_warning(not_zip, "not a ZIP"))
	var missing := MapDocumentIO.read(DIR.path_join("nope.ttmap"))
	assert_null(missing["document"])
	assert_true(Fixtures.has_warning(missing, "no map document"))


func test_central_directory_parser_rejects_truncation() -> void:
	assert_null(MapDocumentIO._parse_central_directory(PackedByteArray([0x50, 0x4b]), 1))
	assert_eq(MapDocumentIO._parse_central_directory(PackedByteArray(), 0), {})
