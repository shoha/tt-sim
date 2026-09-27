extends GutTest

## Painted surfaces in the map document: the MapDocument slot and weight helpers, and
## MapDocumentIO's surfaces.json / surfaces.png / surfaces_b.png entries (round trips,
## caps, malformed input, sum normalisation). Everything under DIR is removed in after_all.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const GRID := Fixtures.GRID
const COUNT := GRID * GRID
const PLANE := COUNT * 4
const DIR := "user://test_map_document_surfaces"
const NAMES: Array[String] = [
	"grass_alpine",
	"cobblestone",
	"cliff_basalt",
	"dirt_road",
	"flagstone",
	"planks",
	"stone_tiles",
	"gravel",
	"sand_red",
]


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_all() -> void:
	var dir := DirAccess.open(DIR)
	if dir != null:
		for file_name in dir.get_files():
			dir.remove(file_name)
	DirAccess.remove_absolute(DIR)


# --- helpers ------------------------------------------------------------------------


## A 20 x 20 document painted with the first `surfaces` NAMES: every sample carries two
## neighbouring slots whose weights sum to at most 250.
func _painted_doc(surfaces: int) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "v", 1)
	for slot in surfaces:
		assert_eq(doc.ensure_surface(NAMES[slot]), slot)
	for sample in COUNT:
		var first := sample % surfaces
		var second := (sample + 1) % surfaces
		doc.surface_weights[MapDocument.surface_offset(sample, first, COUNT)] = (
			(sample * 7) % 200 + 20
		)
		if second != first:
			doc.surface_weights[MapDocument.surface_offset(sample, second, COUNT)] = 30
	return doc


func _entries(doc: MapDocument) -> Dictionary:
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "", "serializes")
	return packed["entries"]


func _ids_json(ids: Variant) -> PackedByteArray:
	return JSON.stringify({"surfaces": ids}).to_utf8_buffer()


func _weights_png(pixels: Dictionary) -> PackedByteArray:
	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	for at in pixels:
		image.set_pixelv(at, pixels[at])
	return image.save_png_to_buffer()


func _parse(extra: Dictionary) -> Dictionary:
	return MapDocumentIO.parse(Fixtures.minimal_entries(extra))


# --- MapDocument helpers ------------------------------------------------------------


func test_ensure_surface_appends_and_reuses_slots() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	assert_eq(doc.ensure_surface(""), -1, "an empty name gets no slot")
	assert_true(doc.surface_weights.is_empty())
	assert_eq(doc.ensure_surface(NAMES[0]), 0)
	assert_eq(doc.surface_weights.size(), COUNT * 8, "the first slot allocates both planes")
	assert_eq(doc.ensure_surface(NAMES[1]), 1)
	assert_eq(doc.ensure_surface(NAMES[0]), 0, "an existing surface keeps its slot")
	for slot in range(2, MapDocument.MAX_SURFACES):
		assert_eq(doc.ensure_surface(NAMES[slot]), slot)
	for slot in MapDocument.MAX_SURFACES:
		doc.set_surface_weight(slot, slot, 10)
	assert_eq(doc.ensure_surface("sand_red"), -1, "eight slots with paint: none free")
	doc.set_surface_weight(5, 5, 0)
	assert_true(doc.surface_slot_unused(5))
	assert_eq(doc.ensure_surface("sand_red"), 5, "a slot with no paint is reused")
	assert_eq(doc.surface_ids[5], "sand_red")
	assert_eq(doc.surface_ids.size(), MapDocument.MAX_SURFACES)


func test_surface_offset_is_planar() -> void:
	assert_eq(MapDocument.surface_offset(3, 1, COUNT), 3 * 4 + 1)
	assert_eq(MapDocument.surface_offset(3, 5, COUNT), PLANE + 3 * 4 + 1, "slot 5 is B.g")
	var doc := _painted_doc(6)
	var plane_b := doc.surface_plane(1)
	assert_eq(plane_b.size(), PLANE)
	assert_eq(plane_b[3 * 4 + 1], doc.surface_weight(3, 5))
	assert_eq(doc.surface_plane(0).size(), PLANE)


func test_set_surface_weight_keeps_the_sum() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	doc.ensure_surface("cobblestone")
	doc.ensure_surface("planks")
	doc.set_surface_weight(10, 0, 200)
	doc.set_surface_weight(10, 1, 200)
	assert_eq(doc.surface_weight(10, 1), 200, "the newest paint wins")
	assert_eq(doc.surface_weight(10, 0), 55, "the other slot scales into the room left")
	doc.set_surface_weight(10, 1, 999)
	assert_eq(doc.surface_weight(10, 1), 255, "clamped")
	assert_eq(doc.surface_weight(10, 0), 0)
	doc.set_surface_weight(10, 4, 100)
	assert_eq(doc.surface_weight(10, 4), 0, "a slot not in use is not painted")


func test_trim_unused_surfaces_drops_trailing_slots() -> void:
	var doc := _painted_doc(4)
	doc.ensure_surface("flagstone")
	doc.ensure_surface("planks")
	doc.trim_unused_surfaces()
	assert_eq(doc.surface_ids.size(), 4, "slots 4 and 5 hold no paint")
	assert_false(_entries(doc).has(MapDocumentIO.SURFACES_B_PNG_ENTRY), "one image again")
	doc.surface_weights.fill(0)
	doc.trim_unused_surfaces()
	assert_true(doc.surface_ids.is_empty())
	assert_true(doc.surface_weights.is_empty(), "weights go with the last slot")


# --- round trips --------------------------------------------------------------------


func test_round_trip_with_three_surfaces_writes_one_image() -> void:
	var doc := _painted_doc(3)
	var entries := _entries(doc)
	assert_true(entries.has(MapDocumentIO.SURFACES_JSON_ENTRY))
	assert_true(entries.has(MapDocumentIO.SURFACES_PNG_ENTRY))
	assert_false(entries.has(MapDocumentIO.SURFACES_B_PNG_ENTRY), "slots 4-7 unused")
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	var got: MapDocument = result["document"]
	assert_eq(got.surface_ids, doc.surface_ids)
	assert_true(got.surface_weights == doc.surface_weights, "weights are exact")


func test_round_trip_with_six_surfaces_through_a_file() -> void:
	var doc := _painted_doc(6)
	assert_true(_entries(doc).has(MapDocumentIO.SURFACES_B_PNG_ENTRY), "slots 4-5 need B")
	var path := DIR.path_join("six.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray())
	var got: MapDocument = result["document"]
	assert_eq(got.surface_ids, doc.surface_ids)
	assert_true(got.surface_weights == doc.surface_weights, "weights are exact")
	assert_gt(got.surface_weight(4, 4), 0, "a slot in image B survived")


func test_unpainted_document_writes_no_surface_entries() -> void:
	var entries := _entries(MapDocument.create_flat(Vector2i(20, 20), "", "", 0))
	for entry_name in [
		MapDocumentIO.SURFACES_JSON_ENTRY,
		MapDocumentIO.SURFACES_PNG_ENTRY,
		MapDocumentIO.SURFACES_B_PNG_ENTRY,
	]:
		assert_false(entries.has(entry_name), entry_name)


# --- sums ---------------------------------------------------------------------------


func test_writer_normalises_without_touching_the_document() -> void:
	var doc := _painted_doc(2)
	doc.surface_weights[MapDocument.surface_offset(0, 0, COUNT)] = 200
	doc.surface_weights[MapDocument.surface_offset(0, 1, COUNT)] = 200
	doc.surface_weights[MapDocument.surface_offset(1, 6, COUNT)] = 90
	var result := MapDocumentIO.parse(_entries(doc))
	assert_eq(result["warnings"], PackedStringArray(), "the file needs no fixing")
	var got: MapDocument = result["document"]
	assert_eq(got.surface_weight(0, 0), 127)
	assert_eq(got.surface_weight(0, 1), 127)
	assert_eq(got.surface_weights[MapDocument.surface_offset(1, 6, COUNT)], 0, "stray paint")
	assert_eq(doc.surface_weight(0, 0), 200, "the document itself is unchanged")


func test_parser_normalises_over_full_samples() -> void:
	var png := _weights_png(
		{Vector2i(0, 0): Color8(200, 200, 0, 0), Vector2i(1, 0): Color8(40, 0, 50, 0)}
	)
	var entries := {
		MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone", "planks"]),
		MapDocumentIO.SURFACES_PNG_ENTRY: png,
	}
	var result := _parse(entries)
	var doc: MapDocument = result["document"]
	assert_eq(doc.surface_weight(0, 0), 127)
	assert_eq(doc.surface_weight(0, 1), 127)
	assert_eq(doc.surface_weight(1, 0), 40)
	assert_eq(doc.surface_weights[MapDocument.surface_offset(1, 2, COUNT)], 0, "B of 2 slots")
	assert_true(Fixtures.has_warning(result, "1 samples sum past 255"), str(result["warnings"]))
	assert_true(Fixtures.has_warning(result, "1 samples paint an unlisted slot"))


# --- malformed input ------------------------------------------------------------------


func test_malformed_surface_lists_drop_the_surfaces() -> void:
	var png := _weights_png({})
	var nine := NAMES.duplicate()
	var cases := [
		JSON.stringify({"surfaces": nine}),
		JSON.stringify({"surfaces": ["cobblestone", 5]}),
		JSON.stringify({"surfaces": ["cobblestone", "cobblestone"]}),
		JSON.stringify({"surfaces": [""]}),
		JSON.stringify({"surfaces": ["x".repeat(MapDocumentIO.MAX_ID_LENGTH + 1)]}),
		JSON.stringify({"surfaces": "cobblestone"}),
		JSON.stringify(["cobblestone"]),
		"{not json",
	]
	for text in cases:
		var result := _parse(
			{
				MapDocumentIO.SURFACES_JSON_ENTRY: text.to_utf8_buffer(),
				MapDocumentIO.SURFACES_PNG_ENTRY: png,
			}
		)
		assert_not_null(result["document"], "surfaces never reject the map")
		assert_true(result["document"].surface_ids.is_empty(), text)
		assert_true(result["document"].surface_weights.is_empty(), text)
		assert_gt(result["warnings"].size(), 0, "warned: " + text)
	var too_many := _parse({MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(nine)})
	assert_true(Fixtures.has_warning(too_many, "more than 8 surfaces"))


func test_ids_without_the_image_are_dropped() -> void:
	var result := _parse({MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"])})
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "without surfaces.png"))


func test_image_without_ids_is_ignored() -> void:
	var result := _parse({MapDocumentIO.SURFACES_PNG_ENTRY: _weights_png({})})
	assert_true(result["document"].surface_weights.is_empty())
	assert_true(Fixtures.has_warning(result, "without surfaces.json"))
	var empty_list := _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json([]),
			MapDocumentIO.SURFACES_PNG_ENTRY: _weights_png({}),
		}
	)
	assert_true(empty_list["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(empty_list, "lists no surfaces"))


func test_image_of_the_wrong_size_drops_the_surfaces() -> void:
	var small := Fixtures.mask_png(Vector2i(GRID - 1, GRID), Image.FORMAT_RGBA8)
	var result := _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
			MapDocumentIO.SURFACES_PNG_ENTRY: small,
		}
	)
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "sample grid"))


func test_missing_second_image_keeps_the_first_four() -> void:
	var entries := _entries(_painted_doc(6))
	var expected: PackedByteArray = _painted_doc(6).surface_plane(0)
	entries.erase(MapDocumentIO.SURFACES_B_PNG_ENTRY)
	var result := MapDocumentIO.parse(entries)
	var doc: MapDocument = result["document"]
	assert_eq(doc.surface_ids.size(), 4)
	assert_true(doc.surface_plane(0) == expected, "slots 0-3 intact")
	assert_eq(doc.surface_plane(1).count(0), PLANE, "slots 4-7 empty")
	assert_true(Fixtures.has_warning(result, "surfaces 5-6"), str(result["warnings"]))


func test_second_image_with_four_surfaces_is_ignored() -> void:
	var entries := _entries(_painted_doc(4))
	entries[MapDocumentIO.SURFACES_B_PNG_ENTRY] = _weights_png({Vector2i(0, 0): Color8(9, 9, 9, 9)})
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["document"].surface_ids.size(), 4)
	assert_eq(result["document"].surface_plane(1).count(0), PLANE)
	assert_true(Fixtures.has_warning(result, "surfaces_b.png with 4 surfaces"))


func test_surface_images_over_their_cap_are_ignored() -> void:
	for entry_name in [MapDocumentIO.SURFACES_PNG_ENTRY, MapDocumentIO.SURFACES_B_PNG_ENTRY]:
		assert_eq(MapDocumentIO.ENTRY_CAPS[entry_name], 4 * 1024 * 1024)
		assert_true(entry_name in MapDocumentIO.KNOWN_ENTRIES)
	var huge := PackedByteArray()
	huge.resize(MapDocumentIO.ENTRY_CAPS[MapDocumentIO.SURFACES_PNG_ENTRY] + 1)
	var result := _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
			MapDocumentIO.SURFACES_PNG_ENTRY: huge,
		}
	)
	assert_not_null(result["document"])
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "over its cap"))


func test_serialize_refuses_bad_surfaces() -> void:
	# label: [surface ids, weight bytes]
	var cases := {
		"nine ids": [NAMES, COUNT * 8],
		"duplicate": [["a", "a"], COUNT * 8],
		"empty id": [[""], COUNT * 8],
		"ids only": [["a"], 0],
		"weights only": [[], COUNT * 8],
		"wrong size": [["a"], PLANE],
	}
	for label in cases:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
		doc.surface_ids = PackedStringArray(cases[label][0])
		doc.surface_weights.resize(cases[label][1])
		var packed := MapDocumentIO.serialize(doc)
		assert_ne(packed["error"], "", "refused: " + label)
		assert_true(packed["entries"].is_empty(), "nothing to write: " + label)
