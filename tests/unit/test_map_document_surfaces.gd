extends GutTest

## Painted surfaces in the map document, format 2: the MapDocument entry helpers (slots,
## entries, the fifth-surface rule) and MapDocumentIO's surfaces.json / surfaces_index.png /
## surfaces_weight.png entries (round trips, caps, hostile input brought to canonical form).
## Format 1 reading and its migration are in test_map_document_surfaces_format1.gd.
## Everything under DIR is removed in after_all.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const GRID := Fixtures.GRID
const COUNT := GRID * GRID
const PLANE := COUNT * 4
const INDEX := MapDocument.SURFACE_INDEX_PLANE
const WEIGHT := MapDocument.SURFACE_WEIGHT_PLANE
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


## A 20 x 20 document listing `surfaces` surfaces (NAMES first, then generated ids): every
## sample carries two neighbouring slots whose weights sum to at most 250.
func _painted_doc(surfaces: int) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_alpine", "v", 1)
	for slot in surfaces:
		var surface := NAMES[slot] if slot < NAMES.size() else "surface_%d" % slot
		assert_eq(doc.ensure_surface(surface, MapDocument.MAX_SURFACES), slot)
	for sample in COUNT:
		var first := sample % surfaces
		var second := (sample + 1) % surfaces
		if second != first:
			doc.set_surface_weight(sample, second, 30)
		doc.set_surface_weight(sample, first, (sample * 7) % 200 + 20)
	return doc


func _entries(doc: MapDocument) -> Dictionary:
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "", "serializes")
	return packed["entries"]


func _ids_json(ids: Variant) -> PackedByteArray:
	return JSON.stringify({"surfaces": ids}).to_utf8_buffer()


## An RGBA8 grid PNG with `pixels` (Vector2i -> Color) set, the rest 0.
func _png(pixels: Dictionary) -> PackedByteArray:
	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	for at in pixels:
		image.set_pixelv(at, pixels[at])
	return image.save_png_to_buffer()


## Parses a format 2 document listing `ids` whose sample (0, 0) holds the entries
## `indices` / `weights` (four bytes each).
func _parse_sample(ids: Array, indices: Array, weights: Array) -> Dictionary:
	var at := Vector2i(0, 0)
	return _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(ids),
			MapDocumentIO.SURFACES_INDEX_ENTRY: _png({at: _color(indices)}),
			MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({at: _color(weights)}),
		}
	)


func _color(bytes: Array) -> Color:
	return Color8(bytes[0], bytes[1], bytes[2], bytes[3])


func _parse(extra: Dictionary) -> Dictionary:
	var entries := Fixtures.minimal_entries(extra)
	entries[MapDocumentIO.MANIFEST_ENTRY] = Fixtures.manifest({"format": 2})
	return MapDocumentIO.parse(entries)


## Sample `sample`'s entries as [[index, weight], ...] in entry order, unused ones included.
func _sample(doc: MapDocument, sample: int) -> Array:
	var out := []
	for e in MapDocument.SURFACE_ENTRIES:
		(
			out
			. append(
				[
					doc.surface_weights[MapDocument.surface_offset(sample, e, INDEX, COUNT)],
					doc.surface_weights[MapDocument.surface_offset(sample, e, WEIGHT, COUNT)],
				]
			)
		)
	return out


# --- MapDocument helpers ------------------------------------------------------------


func test_ensure_surface_appends_and_reuses_slots() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	assert_eq(doc.ensure_surface(""), -1, "an empty name gets no slot")
	assert_true(doc.surface_weights.is_empty())
	assert_eq(doc.ensure_surface(NAMES[0]), 0)
	assert_eq(doc.surface_weights.size(), COUNT * 8, "the first slot allocates both planes")
	assert_eq(doc.ensure_surface(NAMES[1]), 1)
	assert_eq(doc.ensure_surface(NAMES[0]), 0, "an existing surface keeps its slot")
	for slot in range(2, MapDocument.PAINT_SURFACE_LIMIT):
		assert_eq(doc.ensure_surface(NAMES[slot]), slot)
	for slot in MapDocument.PAINT_SURFACE_LIMIT:
		doc.set_surface_weight(slot, slot, 10)
	assert_eq(doc.ensure_surface("sand_red"), -1, "the paint limit with paint: none free")
	assert_eq(doc.ensure_surface("sand_red", MapDocument.MAX_SURFACES), 8, "the document cap")
	doc.surface_ids.resize(8)
	doc.set_surface_weight(5, 5, 0)
	assert_true(doc.surface_slot_unused(5))
	assert_eq(doc.ensure_surface("sand_red"), 5, "a slot with no paint is reused")
	assert_eq(doc.surface_ids[5], "sand_red")
	assert_eq(doc.surface_ids.size(), MapDocument.PAINT_SURFACE_LIMIT)
	assert_eq(MapDocument.MAX_SURFACES, 64)


func test_surface_offset_and_planes() -> void:
	assert_eq(MapDocument.surface_offset(3, 1, INDEX, COUNT), 3 * 4 + 1)
	assert_eq(MapDocument.surface_offset(3, 1, WEIGHT, COUNT), PLANE + 3 * 4 + 1)
	var doc := _painted_doc(6)
	var index_plane := doc.surface_plane(INDEX)
	var weight_plane := doc.surface_plane(WEIGHT)
	assert_eq(index_plane.size(), PLANE)
	assert_eq(weight_plane.size(), PLANE)
	# Sample 9: slot 3 at (9 * 7) % 200 + 20 = 83 and slot 4 at 30, high to low.
	assert_eq(_sample(doc, 9), [[3, 83], [4, 30], [0, 0], [0, 0]])
	assert_eq(index_plane[9 * 4], 3)
	assert_eq(weight_plane[9 * 4 + 1], 30)
	assert_eq(doc.surface_weight(9, 4), 30)
	assert_eq(doc.surface_weight(9, 0), 0, "no entry for the slot")


func test_set_surface_weight_keeps_the_sum_and_the_order() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	doc.ensure_surface("cobblestone")
	doc.ensure_surface("planks")
	doc.set_surface_weight(10, 0, 200)
	doc.set_surface_weight(10, 1, 200)
	assert_eq(doc.surface_weight(10, 1), 200, "the newest paint wins")
	assert_eq(doc.surface_weight(10, 0), 55, "the other slot scales into the room left")
	assert_eq(_sample(doc, 10), [[1, 200], [0, 55], [0, 0], [0, 0]], "high to low")
	doc.set_surface_weight(10, 1, 999)
	assert_eq(doc.surface_weight(10, 1), 255, "clamped")
	assert_eq(_sample(doc, 10), [[1, 255], [0, 0], [0, 0], [0, 0]], "a zero entry is unused")
	doc.set_surface_weight(10, 1, 0)
	assert_eq(_sample(doc, 10), [[0, 0], [0, 0], [0, 0], [0, 0]], "painting 0 removes it")
	doc.set_surface_weight(10, 4, 100)
	assert_eq(doc.surface_weight(10, 4), 0, "a slot not in use is not painted")


func test_a_fifth_surface_drops_the_weakest_entry() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
	for slot in 5:
		doc.ensure_surface(NAMES[slot])
	for pair in [[0, 100], [1, 60], [2, 40], [3, 20]]:
		doc.set_surface_weight(7, pair[0], pair[1])
	assert_eq(_sample(doc, 7), [[0, 100], [1, 60], [2, 40], [3, 20]])
	doc.set_surface_weight(7, 4, 0)
	assert_eq(_sample(doc, 7)[3], [3, 20], "painting nothing drops nothing")
	doc.set_surface_weight(7, 4, 30)
	assert_eq(_sample(doc, 7), [[0, 100], [1, 60], [2, 40], [4, 30]], "slot 3 gave way")
	assert_eq(doc.surface_weight(7, 3), 0, "its weight returns to the automatic ground")
	doc.set_surface_weight(7, 1, 80)
	assert_eq(_sample(doc, 7), [[0, 100], [1, 80], [2, 40], [4, 30]], "a listed slot updates")


func test_trim_unused_surfaces_drops_trailing_slots() -> void:
	var doc := _painted_doc(4)
	doc.ensure_surface("flagstone")
	doc.ensure_surface("planks")
	doc.trim_unused_surfaces()
	assert_eq(doc.surface_ids.size(), 4, "slots 4 and 5 hold no paint")
	assert_eq(doc.used_surface_slots(), PackedByteArray([1, 1, 1, 1]))
	doc.surface_weights.fill(0)
	doc.trim_unused_surfaces()
	assert_true(doc.surface_ids.is_empty())
	assert_true(doc.surface_weights.is_empty(), "the entries go with the last slot")


# --- round trips --------------------------------------------------------------------


func test_round_trip_writes_format_2_entries() -> void:
	var doc := _painted_doc(3)
	var entries := _entries(doc)
	var manifest: Dictionary = JSON.parse_string(
		(entries[MapDocumentIO.MANIFEST_ENTRY] as PackedByteArray).get_string_from_utf8()
	)
	assert_eq(int(manifest["format"]), 2)
	for entry_name in [
		MapDocumentIO.SURFACES_JSON_ENTRY,
		MapDocumentIO.SURFACES_INDEX_ENTRY,
		MapDocumentIO.SURFACES_WEIGHT_ENTRY,
	]:
		assert_true(entries.has(entry_name), entry_name)
	for entry_name in [MapDocumentIO.SURFACES_PNG_ENTRY, MapDocumentIO.SURFACES_B_PNG_ENTRY]:
		assert_false(entries.has(entry_name), "format 1 entries are not written")
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	var got: MapDocument = result["document"]
	assert_eq(got.surface_ids, doc.surface_ids)
	assert_true(got.surface_weights == doc.surface_weights, "entries are exact")


func test_round_trip_with_forty_surfaces_through_a_file() -> void:
	var doc := _painted_doc(40)
	var path := DIR.path_join("forty.ttmap")
	assert_eq(MapDocumentIO.write(doc, path), OK)
	var result := MapDocumentIO.read(path)
	assert_eq(result["warnings"], PackedStringArray())
	var got: MapDocument = result["document"]
	assert_eq(got.surface_ids.size(), 40)
	assert_true(got.surface_weights == doc.surface_weights, "entries are exact")
	assert_gt(got.surface_weight(39, 39), 0, "a slot past the old eight survived")


func test_unpainted_document_writes_no_surface_entries() -> void:
	var entries := _entries(MapDocument.create_flat(Vector2i(20, 20), "", "", 0))
	for entry_name in [
		MapDocumentIO.SURFACES_JSON_ENTRY,
		MapDocumentIO.SURFACES_INDEX_ENTRY,
		MapDocumentIO.SURFACES_WEIGHT_ENTRY,
	]:
		assert_false(entries.has(entry_name), entry_name)


func test_writer_canonicalises_without_touching_the_document() -> void:
	var doc := _painted_doc(2)
	var raw := doc.surface_weights
	# Sample 0 unsorted and over full; sample 1 names an unlisted slot.
	for pair in [[0, 0, 1, 100], [0, 1, 0, 200], [1, 0, 6, 90]]:
		raw[MapDocument.surface_offset(pair[0], pair[1], INDEX, COUNT)] = pair[2]
		raw[MapDocument.surface_offset(pair[0], pair[1], WEIGHT, COUNT)] = pair[3]
	raw[MapDocument.surface_offset(1, 1, WEIGHT, COUNT)] = 0
	var before := raw.duplicate()
	var result := MapDocumentIO.parse(_entries(doc))
	assert_eq(result["warnings"], PackedStringArray(), "the file needs no fixing")
	var got: MapDocument = result["document"]
	assert_eq(_sample(got, 0), [[0, 170], [1, 85], [0, 0], [0, 0]])
	assert_eq(_sample(got, 1), [[0, 0], [0, 0], [0, 0], [0, 0]], "the unlisted slot's entry")
	assert_true(doc.surface_weights == before, "the document itself is unchanged")


# --- hostile input ------------------------------------------------------------------


func test_an_index_past_the_list_is_dropped_with_a_warning() -> void:
	var result := _parse_sample(["cobblestone", "planks"], [1, 5, 0, 0], [120, 80, 0, 0])
	var doc: MapDocument = result["document"]
	assert_eq(_sample(doc, 0), [[1, 120], [0, 0], [0, 0], [0, 0]])
	assert_true(Fixtures.has_warning(result, "1 entries name an unlisted"), str(result))


func test_a_slot_named_twice_is_merged() -> void:
	var result := _parse_sample(["cobblestone", "planks"], [1, 0, 1, 0], [50, 60, 40, 0])
	var doc: MapDocument = result["document"]
	assert_eq(_sample(doc, 0), [[1, 90], [0, 60], [0, 0], [0, 0]])
	assert_true(Fixtures.has_warning(result, "1 samples name a surface twice"))


func test_unsorted_entries_are_resorted_quietly() -> void:
	var result := _parse_sample(["cobblestone", "planks", "gravel"], [0, 2, 1, 0], [10, 90, 50, 0])
	assert_eq(_sample(result["document"], 0), [[2, 90], [1, 50], [0, 10], [0, 0]])
	assert_eq(result["warnings"], PackedStringArray(), "order is not damage")


func test_a_sum_past_255_is_scaled_down() -> void:
	var result := _parse_sample(["cobblestone", "planks"], [0, 1, 0, 0], [200, 200, 0, 0])
	assert_eq(_sample(result["document"], 0), [[0, 127], [1, 127], [0, 0], [0, 0]])
	assert_true(Fixtures.has_warning(result, "1 samples sum past 255"))


func test_loose_unused_entries_become_zero() -> void:
	var result := _parse_sample(["cobblestone", "planks"], [1, 7, 9, 0], [40, 0, 0, 0])
	assert_eq(_sample(result["document"], 0), [[1, 40], [0, 0], [0, 0], [0, 0]])
	var gap := _parse_sample(["cobblestone", "planks"], [1, 0, 0, 0], [0, 40, 0, 0])
	assert_eq(_sample(gap["document"], 0), [[0, 40], [0, 0], [0, 0], [0, 0]], "a gap closes")


func test_a_missing_half_of_the_pair_drops_the_surfaces() -> void:
	var ids := _ids_json(["cobblestone"])
	for present in [MapDocumentIO.SURFACES_INDEX_ENTRY, MapDocumentIO.SURFACES_WEIGHT_ENTRY]:
		var result := _parse({MapDocumentIO.SURFACES_JSON_ENTRY: ids, present: _png({})})
		assert_true(result["document"].surface_ids.is_empty(), present)
		assert_true(result["document"].surface_weights.is_empty(), present)
		assert_true(Fixtures.has_warning(result, "painted surfaces dropped"), present)


func test_an_image_of_the_wrong_size_drops_the_surfaces() -> void:
	var small := Fixtures.mask_png(Vector2i(GRID - 1, GRID), Image.FORMAT_RGBA8)
	for wrong in [MapDocumentIO.SURFACES_INDEX_ENTRY, MapDocumentIO.SURFACES_WEIGHT_ENTRY]:
		var entries := {
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
			MapDocumentIO.SURFACES_INDEX_ENTRY: _png({}),
			MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({}),
		}
		entries[wrong] = small
		var result := _parse(entries)
		assert_true(result["document"].surface_ids.is_empty(), wrong)
		assert_true(Fixtures.has_warning(result, "sample grid"), wrong)


func test_images_without_ids_are_ignored() -> void:
	var images := {
		MapDocumentIO.SURFACES_INDEX_ENTRY: _png({}),
		MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({}),
	}
	var result := _parse(images)
	assert_true(result["document"].surface_weights.is_empty())
	assert_true(Fixtures.has_warning(result, "without surfaces.json"))
	images[MapDocumentIO.SURFACES_JSON_ENTRY] = _ids_json([])
	var empty_list := _parse(images)
	assert_true(empty_list["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(empty_list, "lists no surfaces"))


func test_format_1_images_in_a_format_2_document_are_ignored() -> void:
	var result := _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
			MapDocumentIO.SURFACES_PNG_ENTRY: _png({Vector2i(0, 0): Color8(255, 0, 0, 0)}),
		}
	)
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "without surfaces_index.png"))


func test_malformed_surface_lists_drop_the_surfaces() -> void:
	var too_many := []
	for k in MapDocument.MAX_SURFACES + 1:
		too_many.append("surface_%d" % k)
	var cases := [
		JSON.stringify({"surfaces": too_many}),
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
				MapDocumentIO.SURFACES_INDEX_ENTRY: _png({}),
				MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({}),
			}
		)
		assert_not_null(result["document"], "surfaces never reject the map")
		assert_true(result["document"].surface_ids.is_empty(), text)
		assert_true(result["document"].surface_weights.is_empty(), text)
		assert_gt(result["warnings"].size(), 0, "warned: " + text)
	var listed := _parse({MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(too_many)})
	assert_true(Fixtures.has_warning(listed, "more than 64 surfaces"))


func test_unknown_surface_names_stay_readable() -> void:
	var result := _parse_sample(["not_in_any_palette"], [0, 0, 0, 0], [77, 0, 0, 0])
	assert_eq(result["document"].surface_ids, PackedStringArray(["not_in_any_palette"]))
	assert_eq(result["document"].surface_weight(0, 0), 77)


func test_surface_images_over_their_cap_are_ignored() -> void:
	for entry_name in [MapDocumentIO.SURFACES_INDEX_ENTRY, MapDocumentIO.SURFACES_WEIGHT_ENTRY]:
		assert_eq(MapDocumentIO.ENTRY_CAPS[entry_name], 4 * 1024 * 1024)
		assert_true(entry_name in MapDocumentIO.KNOWN_ENTRIES)
	var huge := PackedByteArray()
	huge.resize(MapDocumentIO.ENTRY_CAPS[MapDocumentIO.SURFACES_INDEX_ENTRY] + 1)
	var result := _parse(
		{
			MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
			MapDocumentIO.SURFACES_INDEX_ENTRY: huge,
			MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({}),
		}
	)
	assert_not_null(result["document"])
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "over its cap"))


func test_serialize_refuses_bad_surfaces() -> void:
	var too_many := []
	for k in MapDocument.MAX_SURFACES + 1:
		too_many.append("surface_%d" % k)
	# label: [surface ids, entry bytes]
	var cases := {
		"65 ids": [too_many, COUNT * 8],
		"duplicate": [["a", "a"], COUNT * 8],
		"empty id": [[""], COUNT * 8],
		"ids only": [["a"], 0],
		"entries only": [[], COUNT * 8],
		"wrong size": [["a"], PLANE],
	}
	for label in cases:
		var doc := MapDocument.create_flat(Vector2i(20, 20), "", "", 0)
		doc.surface_ids = PackedStringArray(cases[label][0])
		doc.surface_weights.resize(cases[label][1])
		var packed := MapDocumentIO.serialize(doc)
		assert_ne(packed["error"], "", "refused: " + label)
		assert_true(packed["entries"].is_empty(), "nothing to write: " + label)
