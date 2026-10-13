extends GutTest

## The fire mask in map.ttmap (fire.png; design docs/plans/2026-10-11-fire-features/design.md
## section 1): it round trips byte for byte, an all-zero mask is never written and reads as
## none, a wrong-sized or broken image is skipped with a warning and the map still loads, an
## entry over its cap is refused before it is decoded, and a document with no fire writes no
## entry (an older build, which ignores unknown entries, reads it as unburnt either way).

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const FOLDER := "user://_firefeat_document/"
const PATH := FOLDER + "map.ttmap"


func after_all() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)
	DirAccess.remove_absolute(FOLDER.trim_suffix("/"))


func _burning_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 7)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	for z in range(30, 60):
		for x in range(20, 90):
			mask[doc.sample_index(x, z)] = (x * 7 + z) % 256
	doc.fire_mask = mask
	return doc


func test_the_entry_is_known_and_capped() -> void:
	assert_true(MapDocumentIO.FIRE_ENTRY in MapDocumentIO.KNOWN_ENTRIES)
	assert_eq(MapDocumentIO.ENTRY_CAPS[MapDocumentIO.FIRE_ENTRY], 4 * 1024 * 1024)
	assert_eq(MapDocument.MIN_FORMAT, 1, "fire needed no bump: format 1 documents keep it")


func test_fire_round_trips_through_a_file() -> void:
	var doc := _burning_doc()
	DirAccess.make_dir_recursive_absolute(FOLDER)
	assert_eq(MapDocumentIO.write(doc, PATH), OK)
	var result := MapDocumentIO.read(PATH)
	var back: MapDocument = result["document"]
	assert_not_null(back)
	if back == null:
		return
	assert_true(back.fire_mask == doc.fire_mask, "the mask reads back byte for byte")


func test_no_fire_writes_no_entry() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 7)
	var entries: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	assert_false(entries.has(MapDocumentIO.FIRE_ENTRY))
	var zeros := PackedByteArray()
	zeros.resize(doc.sample_count())
	doc.fire_mask = zeros
	entries = MapDocumentIO.serialize(doc)["entries"]
	assert_false(entries.has(MapDocumentIO.FIRE_ENTRY), "an all-zero mask is not written")


func test_an_all_zero_entry_reads_as_no_fire() -> void:
	var png := Fixtures.mask_png(Vector2i(Fixtures.GRID, Fixtures.GRID), Image.FORMAT_L8)
	var result := MapDocumentIO.parse(Fixtures.minimal_entries({MapDocumentIO.FIRE_ENTRY: png}))
	assert_not_null(result["document"])
	assert_true(result["document"].fire_mask.is_empty())


func test_a_wrong_size_is_skipped_with_a_warning() -> void:
	var png := Fixtures.mask_png(Vector2i(Fixtures.GRID - 1, Fixtures.GRID), Image.FORMAT_L8)
	var result := MapDocumentIO.parse(Fixtures.minimal_entries({MapDocumentIO.FIRE_ENTRY: png}))
	assert_not_null(result["document"], "the map loads without its fire")
	assert_true(result["document"].fire_mask.is_empty())
	assert_true(Fixtures.has_warning(result, "fire.png is"), str(result["warnings"]))


func test_any_format_is_taken_as_greyscale() -> void:
	var image := Image.create_empty(Fixtures.GRID, Fixtures.GRID, false, Image.FORMAT_RGBA8)
	image.set_pixel(5, 6, Color8(200, 200, 200, 255))
	var entries := Fixtures.minimal_entries({MapDocumentIO.FIRE_ENTRY: image.save_png_to_buffer()})
	var doc: MapDocument = MapDocumentIO.parse(entries)["document"]
	assert_eq(doc.fire_mask.size(), doc.sample_count())
	assert_eq(doc.fire_mask[doc.sample_index(5, 6)], 200)


func test_garbage_is_skipped_with_a_warning() -> void:
	var junk := PackedByteArray([1, 2, 3, 4])
	var result := MapDocumentIO.parse(Fixtures.minimal_entries({MapDocumentIO.FIRE_ENTRY: junk}))
	assert_not_null(result["document"])
	assert_true(result["document"].fire_mask.is_empty())
	assert_true(Fixtures.has_warning(result, "fire.png is not a PNG"))


func test_an_entry_over_its_cap_is_refused_before_it_is_decoded() -> void:
	var huge := PackedByteArray()
	huge.resize(MapDocumentIO.ENTRY_CAPS[MapDocumentIO.FIRE_ENTRY] + 1)
	var result := MapDocumentIO.parse(Fixtures.minimal_entries({MapDocumentIO.FIRE_ENTRY: huge}))
	assert_not_null(result["document"])
	assert_true(result["document"].fire_mask.is_empty())
	assert_true(Fixtures.has_warning(result, "over its cap"))


func test_serialize_refuses_a_mask_off_the_grid() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 7)
	doc.fire_mask = PackedByteArray([9])
	var result := MapDocumentIO.serialize(doc)
	assert_string_contains(String(result["error"]), "fire_mask")


func test_the_fingerprint_names_the_fire() -> void:
	var doc := _burning_doc()
	var burning: String = MapFingerprint.of(null, doc).fire
	assert_ne(burning, "")
	doc.fire_mask = PackedByteArray()
	assert_eq(MapFingerprint.of(null, doc).fire, "")
