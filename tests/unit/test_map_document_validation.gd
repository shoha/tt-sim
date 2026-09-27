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
				"splines.json": '{"rivers": []}'.to_utf8_buffer(),
				"authoring/future.bin": PackedByteArray([1, 2, 3]),
			}
		)
	)
	var result := _parse(entries)
	assert_not_null(result["document"])
	assert_eq(result["warnings"], PackedStringArray(), "silently ignored")


func test_non_byte_entry_is_ignored() -> void:
	var result := _parse(Fixtures.minimal_entries({"props.json": "a string, not bytes"}))
	assert_not_null(result["document"])
	assert_true(Fixtures.has_warning(result, "not a byte buffer"))


func test_manifest_over_its_byte_cap_is_ignored() -> void:
	var padding := " ".repeat(MapDocumentIO.ENTRY_CAPS["manifest.json"])
	var bytes := (padding + JSON.stringify({"format": 1})).to_utf8_buffer()
	var result := _parse(Fixtures.minimal_entries({"manifest.json": bytes}))
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "over its cap"))


func test_total_byte_cap() -> void:
	var log := MapDocumentIO._WarningLog.new()
	var total := MapDocumentIO.MAX_TOTAL_BYTES - 5
	assert_false(MapDocumentIO._size_allowed("height.bin", 10, total, log))
	assert_true(MapDocumentIO._size_allowed("height.bin", 5, total, log))
	assert_eq(log.result().size(), 1)


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
	var result := _parse(_with_manifest({"format": 2}))
	assert_null(result["document"])
	assert_true(Fixtures.has_warning(result, "unsupported"))


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
		{"format": 1, "size_cells": [20, 20], "cell_size_m": 1.524, "sample_spacing_m": 0.25}
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


func test_malformed_rows_are_skipped() -> void:
	var text := (
		'{"a/b": ['
		+ "[1,2,3,0,0,0,1,1,1,1],"  # good
		+ "[1,2,3,0,0,0,1,1,1],"  # nine components
		+ '[1,2,"3",0,0,0,1,1,1,1],'  # a string
		+ "[1,2,3,0,0,0,1,1,1,true],"  # a bool
		+ "[1e400,2,3,0,0,0,1,1,1,1],"  # Inf
		+ "[1e6,2,3,0,0,0,1,1,1,1],"  # beyond MAX_ROW_COMPONENT
		+ "[1,2,3,0,0,0,0,1,1,1],"  # zero quaternion
		+ "5,"
		+ "[4,5,6,0,0,0,1,1,1,1]"  # good
		+ "]}"
	)
	var result := _parse(Fixtures.rows_entry(text))
	var rows: PackedFloat32Array = result["document"].scatter["a/b"]
	assert_eq(rows.size(), 20, "two good rows kept")
	assert_eq(rows[10], 4.0)
	assert_true(Fixtures.has_warning(result, "7 malformed rows"), str(result["warnings"]))


func test_malformed_assets_are_skipped() -> void:
	var row := [0, 0, 0, 0, 0, 0, 1, 1, 1, 1]
	var long_id := "p/" + "x".repeat(MapDocumentIO.MAX_ID_LENGTH)
	var text := JSON.stringify(
		{"": [row], long_id: [row], "a/not_rows": 5, "a/all_bad": [[1]], "a/good": [row]}
	)
	var result := _parse(Fixtures.rows_entry(text))
	assert_eq(result["document"].scatter.keys(), ["a/good"])
	assert_eq(result["warnings"].size(), 4, str(result["warnings"]))


func test_unknown_asset_ids_are_kept() -> void:
	var text := '{"not_in_palette/Thing": [%s]}' % Fixtures.IDENTITY_ROW
	var result := _parse(Fixtures.rows_entry(text))
	assert_true(result["document"].scatter.has("not_in_palette/Thing"))


func test_bad_rows_entry_does_not_reject_the_map() -> void:
	var not_object := _parse(Fixtures.rows_entry("[1, 2]"))
	assert_not_null(not_object["document"])
	assert_true(not_object["document"].scatter.is_empty())
	var bad_json := _parse(Fixtures.minimal_entries({"props.json": "{".to_utf8_buffer()}))
	assert_not_null(bad_json["document"])
	assert_true(Fixtures.has_warning(bad_json, "props.json is not valid JSON"))


func test_rows_per_asset_cap() -> void:
	var rows := PackedStringArray()
	rows.resize(MapDocumentIO.MAX_ROWS_PER_ASSET + 1)
	rows.fill(Fixtures.IDENTITY_ROW)
	var result := _parse(Fixtures.rows_entry('{"a/b": [' + ",".join(rows) + "]}"))
	var kept := MapDocument.row_count(result["document"].scatter)
	assert_eq(kept, MapDocumentIO.MAX_ROWS_PER_ASSET)
	assert_true(Fixtures.has_warning(result, "keeps its first"))


## The total-row budget, exercised through the budget parameter rather than a
## million-row fixture; parse passes MAX_TOTAL_ROWS minus the props rows.
func test_total_row_budget() -> void:
	var log := MapDocumentIO._WarningLog.new()
	var text := (
		JSON
		. stringify(
			{
				"a/one": [[0, 0, 0, 0, 0, 0, 1, 1, 1, 1], [1, 0, 0, 0, 0, 0, 1, 1, 1, 1]],
				"a/two": [[2, 0, 0, 0, 0, 0, 1, 1, 1, 1], [3, 0, 0, 0, 0, 0, 1, 1, 1, 1]],
			}
		)
	)
	var rows := MapDocumentIO._parse_rows(text.to_utf8_buffer(), "scatter.json", 3, log)
	assert_eq(MapDocument.row_count(rows), 3)
	assert_eq(rows["a/two"].size(), 10)
	assert_eq(log.result().size(), 1)


func test_props_and_scatter_share_the_budget() -> void:
	var one := '{"x/a": [%s]}' % Fixtures.IDENTITY_ROW
	var entries := Fixtures.minimal_entries(
		{"props.json": one.to_utf8_buffer(), "scatter.json": one.to_utf8_buffer()}
	)
	var doc: MapDocument = _parse(entries)["document"]
	assert_eq(MapDocument.row_count(doc.props), 1)
	assert_eq(MapDocument.row_count(doc.scatter), 1)


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
	var assets := {}
	for i in 80:
		assets["bad_%d/x" % i] = "not rows"
	var result := _parse(Fixtures.rows_entry(JSON.stringify(assets)))
	var warnings: PackedStringArray = result["warnings"]
	assert_eq(warnings.size(), MapDocumentIO.MAX_WARNINGS + 1)
	assert_eq(warnings[warnings.size() - 1], "30 more problems not listed")
