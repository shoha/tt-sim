extends GutTest

## MapDocumentIO.parse() on untrusted entries: manifest and geometry caps, heights, rows,
## masks, biomes and the warning cap. File-level behaviour (round trips, atomic write,
## the ZIP guard) is in test_map_document_io.gd.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const GRID := Fixtures.GRID


func _parse(entries: Dictionary) -> Dictionary:
	return MapDocumentIO.parse(entries)


func _with_manifest(overrides: Dictionary) -> Dictionary:
	return Fixtures.minimal_entries({"manifest.json": Fixtures.manifest(overrides)})


# --- entries ---------------------------------------------------------------------------


func test_unknown_entries_are_ignored() -> void:
	var entries := (
		Fixtures
		. minimal_entries(
			{
				"authoring/future.png": Fixtures.mask_png(Vector2i(4, 4), Image.FORMAT_RGBA8),
				"roads.json": '{"roads": []}'.to_utf8_buffer(),
				"authoring/future.bin": PackedByteArray([1, 2, 3]),
			}
		)
	)
	var result := _parse(entries)
	assert_not_null(result["document"])
	assert_eq(result["warnings"], PackedStringArray(), "silently ignored")


func test_non_byte_entry_is_ignored() -> void:
	var result := _parse(Fixtures.minimal_entries({"props.bin": "a string, not bytes"}))
	assert_not_null(result["document"])
	assert_true(Fixtures.has_warning(result, "not a byte buffer"))


func test_manifest_over_its_byte_cap_is_ignored() -> void:
	var padding := " ".repeat(MapDocumentIO.ENTRY_CAPS["manifest.json"])
	var bytes := (padding + JSON.stringify({"format": MapDocument.FORMAT})).to_utf8_buffer()
	var result := _parse(Fixtures.minimal_entries({"manifest.json": bytes}))
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "over its cap"))


func test_total_byte_cap() -> void:
	var warnings := MapDocumentIO._WarningLog.new()
	var total := MapDocumentIO.MAX_TOTAL_BYTES - 5
	assert_false(MapDocumentIO._size_allowed("height.bin", 10, total, warnings))
	assert_true(MapDocumentIO._size_allowed("height.bin", 5, total, warnings))
	assert_eq(warnings.result().size(), 1)


# --- manifest and geometry ----------------------------------------------------------


func test_missing_manifest() -> void:
	var entries := Fixtures.minimal_entries()
	entries.erase("manifest.json")
	var result := _parse(entries)
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "manifest"))


func test_bad_json_manifest() -> void:
	var result := _parse(Fixtures.minimal_entries({"manifest.json": "{no".to_utf8_buffer()}))
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "not valid JSON"))
	var array := _parse(Fixtures.minimal_entries({"manifest.json": "[1]".to_utf8_buffer()}))
	assert_null(array["document"])


func test_unsupported_format() -> void:
	for format in [0, MapDocument.MAX_FORMAT + 1, 1.5, "4"]:
		var result := _parse(_with_manifest({"format": format}))
		assert_null(result["document"], "format %s" % str(format))
		assert_true(Fixtures.has_warning(result, "unsupported"))
	for format in [4, 5]:
		assert_not_null(_parse(_with_manifest({"format": format}))["document"], str(format))


## Formats 1 to 3 stored the rows as JSON, which this build no longer reads: the document is
## refused whole, with a warning that names the format and says what to do (never read as if it
## had no rows, which the next save would turn into an empty map).
func test_a_pre_binary_format_is_refused_with_a_clear_message() -> void:
	for format in [1, 2, 3]:
		var entries := _with_manifest({"format": format})
		entries["scatter.json"] = '{"a/b": [[0,0,0,0,0,0,1,1,1,1]]}'.to_utf8_buffer()
		var result := _parse(entries)
		assert_null(result["document"], "format %d" % format)
		assert_eq(result["warnings"].size(), 1, str(result["warnings"]))
		assert_true(Fixtures.has_warning(result, "format %d is from an older version" % format))
		assert_true(Fixtures.has_warning(result, "formats 4 to 5"))


func test_geometry_out_of_range_is_rejected() -> void:
	var cases := [
		{"size_cells": [65, 20]},
		{"size_cells": [0, 20]},
		{"size_cells": [20.5, 20]},
		{"size_cells": [20]},
		{"size_cells": "20x20"},
		{"sample_spacing_m": 0.05},
		{"sample_spacing_m": 1.5},
		{"sample_spacing_m": "0.25"},
		{"cell_size_m": 0.0},
		{"cell_size_m": true},
		{"tier_height_m": 1000.0},
		# 64 cells of 10 m at 0.25 m is 2561 samples per axis, over the 641 cap.
		{"size_cells": [64, 64], "cell_size_m": 10.0},
	]
	for overrides in cases:
		assert_null(_parse(_with_manifest(overrides))["document"], "rejected: %s" % overrides)


func test_json_overflow_to_infinity_is_rejected() -> void:
	# JSON.parse turns 1e400 into INF rather than failing (probed on 4.7.1).
	var text := Fixtures.manifest({}).get_string_from_utf8().replace("1.524", "1e400")
	var result := _parse(Fixtures.minimal_entries({"manifest.json": text.to_utf8_buffer()}))
	assert_null(result["document"])


func test_sample_cap_is_checked_before_heights_are_read() -> void:
	# No height.bin at all: the rejection must come from the manifest's numbers.
	var manifest := Fixtures.manifest({"size_cells": [64, 64], "cell_size_m": 10.0})
	var result := _parse({"manifest.json": manifest})
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "per axis"), str(result["warnings"]))


func test_optional_manifest_fields_fall_back_with_warnings() -> void:
	var manifest := JSON.stringify(
		{
			"format": MapDocument.FORMAT,
			"size_cells": [20, 20],
			"cell_size_m": 1.524,
			"sample_spacing_m": 0.25
		}
	)
	var result := _parse(Fixtures.minimal_entries({"manifest.json": manifest.to_utf8_buffer()}))
	var doc: MapDocument = result["document"]
	assert_not_null(doc)
	assert_eq(doc.map_seed, 0)
	assert_eq(doc.base_surface, "")
	assert_false(doc.has_base_map)
	assert_almost_eq(doc.tier_height_m, 1.524, 1e-6)
	assert_eq(result["warnings"].size(), 5, str(result["warnings"]))


func test_bad_optional_manifest_values() -> void:
	var long_text := "x".repeat(MapDocumentIO.MAX_TEXT_LENGTH + 1)
	var overrides := {"base_surface": long_text, "map_seed": 1.5, "has_base_map": "yes"}
	var result := _parse(_with_manifest(overrides))
	var doc: MapDocument = result["document"]
	assert_eq(doc.base_surface, "")
	assert_eq(doc.map_seed, 0)
	assert_false(doc.has_base_map)
	assert_eq(result["warnings"].size(), 3, str(result["warnings"]))


# --- heights -------------------------------------------------------------------------


func test_wrong_height_length() -> void:
	for size in [GRID * GRID * 4 - 4, GRID * GRID * 4 + 4, 0]:
		var bytes := PackedByteArray()
		bytes.resize(size)
		var result := _parse(Fixtures.minimal_entries({"height.bin": bytes}))
		assert_null(result["document"], "rejected at %d bytes" % size)
	var missing := Fixtures.minimal_entries()
	missing.erase("height.bin")
	assert_null(_parse(missing)["document"])


func test_non_finite_or_absurd_heights() -> void:
	for bad in [NAN, INF, -INF, 5000.0]:
		var heights := PackedFloat32Array()
		heights.resize(GRID * GRID)
		heights[4000] = bad
		var result := _parse(Fixtures.minimal_entries({"height.bin": heights.to_byte_array()}))
		assert_null(result["document"], "rejected: %s" % bad)
		assert_true(Fixtures.has_warning(result, "sample 4000"))


# --- rows -----------------------------------------------------------------------------


func _row(
	x: float, y: float, z: float, quaternion: Quaternion = Quaternion()
) -> PackedFloat32Array:
	return PackedFloat32Array(
		[x, y, z, quaternion.x, quaternion.y, quaternion.z, quaternion.w, 1.0, 1.0, 1.0]
	)


func _encoded(rows_by_asset: Dictionary) -> PackedByteArray:
	var typed: Dictionary[String, PackedFloat32Array] = {}
	typed.assign(rows_by_asset)
	return MapRowsCodec.encode_rows(typed)


func _decoded(bytes: PackedByteArray, budget: int = 1000) -> Dictionary:
	var warnings := MapDocumentIO._WarningLog.new()
	var rows := MapRowsCodec.decode_rows(bytes, budget, "scatter.bin", warnings)
	return {"rows": rows, "warnings": warnings.result()}


func test_degenerate_rows_are_dropped() -> void:
	var flat := _row(1, 2, 3)
	flat.append_array(_row(1, 2, 3, Quaternion(0, 0, 0, 0)))  # zero quaternion
	flat.append_array(_row(1.0e6, 2, 3))  # beyond MAX_ROW_COMPONENT
	flat.append_array(_row(4, 5, 6))
	var result := _parse(Fixtures.rows_entry({"a/b": flat}))
	var rows: PackedFloat32Array = result["document"].scatter["a/b"]
	assert_eq(rows.size(), 20, "two good rows kept")
	assert_eq(rows[10], 4.0)
	assert_true(Fixtures.has_warning(result, "2 malformed rows"), str(result["warnings"]))


func test_an_asset_with_a_bad_id_ends_the_entry_with_one_warning() -> void:
	var long_id := "p/" + "x".repeat(MapDocumentIO.MAX_ID_LENGTH)
	var bytes := _encoded({"a/good": _row(0, 0, 0)})
	var tail := _encoded({long_id: _row(0, 0, 0)})
	# The sorted second asset's header follows the first; patch a bad id by splicing an empty one.
	var empty_id := _encoded({"": _row(0, 0, 0)})
	var glued := bytes.slice(0, 5)
	glued.append_array(MapRowsCodec._u32(2))
	glued.append_array(bytes.slice(MapRowsCodec.HEADER_BYTES))
	glued.append_array(empty_id.slice(MapRowsCodec.HEADER_BYTES))
	var got := _decoded(glued)
	assert_eq(got["rows"].keys(), ["a/good"], "what came before the bad asset is kept")
	assert_eq(got["warnings"].size(), 1, str(got["warnings"]))
	var long := _decoded(tail)
	assert_true(long["rows"].is_empty())
	assert_eq(long["warnings"].size(), 1)


func test_unknown_asset_ids_are_kept() -> void:
	var result := _parse(Fixtures.rows_entry({"not_in_palette/Thing": _row(1, 0, 1)}))
	assert_true(result["document"].scatter.has("not_in_palette/Thing"))


func test_bad_rows_entry_does_not_reject_the_map() -> void:
	var not_rows := _parse(Fixtures.minimal_entries({"scatter.bin": "[1, 2]".to_utf8_buffer()}))
	assert_not_null(not_rows["document"])
	assert_true(not_rows["document"].scatter.is_empty())
	assert_true(Fixtures.has_warning(not_rows, "scatter.bin is not a TTRW entry"))
	var wrong_version := _encoded({"a/b": _row(0, 0, 0)})
	wrong_version[4] = 9
	var versioned := _parse(Fixtures.minimal_entries({"props.bin": wrong_version}))
	assert_not_null(versioned["document"])
	assert_true(Fixtures.has_warning(versioned, "props.bin is version 9"))


func test_an_asset_over_the_row_cap_is_not_read() -> void:
	var bytes := _encoded({"a/b": _row(0, 0, 0)})
	var count_at := MapRowsCodec.HEADER_BYTES + 2 + 3
	bytes.encode_u32(count_at, MapDocumentIO.MAX_ROWS_PER_ASSET + 1)
	var got := _decoded(bytes)
	assert_true(got["rows"].is_empty())
	assert_eq(got["warnings"].size(), 1)


## The total-row budget, exercised through the budget parameter rather than a
## million-row fixture; parse passes MAX_TOTAL_ROWS minus the props rows.
func test_total_row_budget() -> void:
	var one := _row(0, 0, 0)
	one.append_array(_row(1, 0, 0))
	var two := _row(2, 0, 0)
	two.append_array(_row(3, 0, 0))
	var got := _decoded(_encoded({"a/one": one, "a/two": two}), 3)
	var rows: Dictionary = got["rows"]
	assert_eq(MapDocument.row_count(rows), 3)
	assert_eq(rows["a/two"].size(), 10)
	assert_eq(got["warnings"].size(), 1)


func test_props_and_scatter_share_the_budget() -> void:
	var typed: Dictionary[String, PackedFloat32Array] = {"x/a": _row(0, 0, 0)}
	var entries := Fixtures.minimal_entries(
		{"props.bin": MapRowsCodec.encode_rows(typed), "scatter.bin": MapRowsCodec.encode_rows(typed)}
	)
	var doc: MapDocument = _parse(entries)["document"]
	assert_eq(MapDocument.row_count(doc.props), 1)
	assert_eq(MapDocument.row_count(doc.scatter), 1)


## Every prefix of a real entry, and the entry with a byte changed anywhere, decodes without a
## crash into rows that are all finite, in range and rotating (the reader's rule).
func test_truncated_and_corrupt_row_entries_never_yield_bad_rows() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var flat := PackedFloat32Array()
	for i in 40:
		flat.append_array(
			_row(
				rng.randf_range(-40, 40),
				rng.randf_range(-5, 5),
				rng.randf_range(-40, 40),
				Quaternion(Vector3.UP, rng.randf_range(0, TAU))
			)
		)
	MapDocumentIO.snap_rows(flat)
	var bytes := _encoded({"a/b": flat, "c/d": flat.slice(0, 100)})
	for cut in bytes.size():
		_assert_sound(_decoded(bytes.slice(0, cut))["rows"])
	for round in 300:
		var damaged := bytes.duplicate()
		for flips in rng.randi_range(1, 4):
			damaged[rng.randi_range(0, damaged.size() - 1)] = rng.randi_range(0, 255)
		_assert_sound(_decoded(damaged)["rows"])


func _assert_sound(rows_by_asset: Dictionary) -> void:
	for asset_id: String in rows_by_asset:
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		assert_eq(flat.size() % MapDocument.ROW_STRIDE, 0)
		for start in range(0, flat.size(), MapDocument.ROW_STRIDE):
			if not MapDocumentIO.row_ok(flat, start):
				fail_test("an unsound row came out of a damaged entry")
				return


# --- masks ---------------------------------------------------------------------------


func test_erase_mask_size_mismatch_is_ignored() -> void:
	var png := Fixtures.mask_png(Vector2i(10, 10), Image.FORMAT_L8)
	var result := _parse(Fixtures.minimal_entries({"erase.png": png}))
	assert_not_null(result["document"])
	assert_true(result["document"].erase_mask.is_empty())
	assert_true(Fixtures.has_warning(result, "sample grid"))


func test_erase_mask_not_a_png_is_ignored() -> void:
	var result := _parse(Fixtures.minimal_entries({"erase.png": "GIF89a...".to_utf8_buffer()}))
	assert_true(result["document"].erase_mask.is_empty())
	assert_true(Fixtures.has_warning(result, "not a PNG"))


func test_erase_mask_in_colour_is_converted() -> void:
	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGB8)
	image.set_pixel(3, 0, Color.WHITE)
	var result := _parse(Fixtures.minimal_entries({"erase.png": image.save_png_to_buffer()}))
	var mask: PackedByteArray = result["document"].erase_mask
	assert_eq(mask.size(), GRID * GRID)
	assert_gt(mask[3], MapDocument.ERASE_THRESHOLD)
	assert_eq(mask[4], 0)


func test_png_header_size_is_read_without_decoding() -> void:
	var png := Fixtures.mask_png(Vector2i(641, 7), Image.FORMAT_L8)
	assert_eq(MapDocumentIO._png_size(png), Vector2i(641, 7))
	assert_eq(MapDocumentIO._png_size(png.slice(0, 20)), Vector2i.ZERO)


func test_biomes_png_without_json_is_ignored() -> void:
	var png := Fixtures.mask_png(Vector2i(GRID, GRID), Image.FORMAT_RG8)
	var result := _parse(Fixtures.minimal_entries({"authoring/biomes.png": png}))
	assert_not_null(result["document"])
	assert_true(result["document"].biome_slots.is_empty())
	assert_true(Fixtures.has_warning(result, "without authoring/biomes.json"))


func test_biomes_json_without_png_keeps_the_list() -> void:
	var json := JSON.stringify({"biomes": [Fixtures.BIOME_A]}).to_utf8_buffer()
	var result := _parse(Fixtures.minimal_entries({"authoring/biomes.json": json}))
	assert_eq(result["document"].biome_ids, PackedStringArray([Fixtures.BIOME_A]))
	assert_true(result["document"].biome_slots.is_empty())
	assert_eq(result["warnings"], PackedStringArray())


func test_biome_slot_beyond_the_list_is_cleared() -> void:
	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RG8)
	image.set_pixel(0, 0, Color8(1, 200, 0))
	image.set_pixel(1, 0, Color8(9, 50, 0))
	var json := JSON.stringify({"biomes": [Fixtures.BIOME_A]}).to_utf8_buffer()
	var entries := Fixtures.minimal_entries(
		{"authoring/biomes.json": json, "authoring/biomes.png": image.save_png_to_buffer()}
	)
	var result := _parse(entries)
	var doc: MapDocument = result["document"]
	assert_eq(doc.biome_slots[0], 1)
	assert_eq(doc.biome_density[0], 200)
	assert_eq(doc.biome_slots[1], 0, "slot 9 of a one-biome list cleared")
	assert_eq(doc.biome_density[1], 50)
	assert_true(Fixtures.has_warning(result, "1 samples name no listed biome"))


func test_malformed_biome_list_drops_the_biomes() -> void:
	var png := Fixtures.mask_png(Vector2i(GRID, GRID), Image.FORMAT_RG8)
	var cases := [{"biomes": [Fixtures.BIOME_A, 5]}, {"biomes": "x"}, [1], {"biomes": [""]}]
	for bad in cases:
		var json := JSON.stringify(bad).to_utf8_buffer()
		var result := _parse(
			Fixtures.minimal_entries({"authoring/biomes.json": json, "authoring/biomes.png": png})
		)
		assert_not_null(result["document"], "authoring data never rejects the map")
		assert_true(result["document"].biome_ids.is_empty(), str(bad))
		assert_true(result["document"].biome_slots.is_empty(), str(bad))


# --- warnings -------------------------------------------------------------------------


func test_warnings_are_capped() -> void:
	# 80 assets whose column data is missing (a body of 0 bytes): one warning each.
	var bytes := "TTRW".to_ascii_buffer()
	bytes.append(MapRowsCodec.VERSION)
	bytes.append_array(MapRowsCodec._u32(80))
	for i in 80:
		var id := ("bad_%02d/x" % i).to_utf8_buffer()
		bytes.append_array(MapRowsCodec._u16(id.size()))
		bytes.append_array(id)
		bytes.append_array(MapRowsCodec._u32(1))
		bytes.append_array(MapRowsCodec._u32(0))
	var result := _parse(Fixtures.minimal_entries({"scatter.bin": bytes}))
	var warnings: PackedStringArray = result["warnings"]
	assert_eq(warnings.size(), MapDocumentIO.MAX_WARNINGS + 1)
	assert_eq(warnings[warnings.size() - 1], "30 more problems not listed")
