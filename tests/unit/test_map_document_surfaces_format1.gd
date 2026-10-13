extends GutTest

## Format 1 painted surfaces (surfaces.json, surfaces.png with slots 0-3 in R, G, B, A,
## surfaces_b.png with slots 4-7) read by today's build and migrated to format 2 entries
## (SurfaceEntries.from_slots): the top four per sample kept and renormalised, a warning
## counting samples that painted more, stray and over-full samples fixed, the old caps kept.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const GRID := Fixtures.GRID
const COUNT := GRID * GRID
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


## Format 1 entries listing the first `ids` NAMES, with image A's and (when given) image
## B's pixels (Vector2i -> Color, one channel per slot).
func _format_1(ids: int, a: Dictionary, b: Dictionary = {}) -> Dictionary:
	var extra := {
		MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(NAMES.slice(0, ids)),
		MapDocumentIO.SURFACES_PNG_ENTRY: _png(a),
	}
	if not b.is_empty():
		extra[MapDocumentIO.SURFACES_B_PNG_ENTRY] = _png(b)
	return Fixtures.minimal_entries(extra)


func _ids_json(ids: Variant) -> PackedByteArray:
	return JSON.stringify({"surfaces": ids}).to_utf8_buffer()


func _png(pixels: Dictionary) -> PackedByteArray:
	var image := Image.create_empty(GRID, GRID, false, Image.FORMAT_RGBA8)
	for at in pixels:
		image.set_pixelv(at, pixels[at])
	return image.save_png_to_buffer()


## Sample `sample`'s entries as [[index, weight], ...], unused ones included.
func _sample(doc: MapDocument, sample: int) -> Array:
	var out := []
	for e in MapDocument.SURFACE_ENTRIES:
		(
			out
			. append(
				[
					doc.surface_weights[sample * 4 + e],
					doc.surface_weights[COUNT * 4 + sample * 4 + e],
				]
			)
		)
	return out


func test_a_format_1_document_migrates_its_paint_exactly() -> void:
	var a := {Vector2i(0, 0): Color8(40, 0, 200, 0), Vector2i(1, 0): Color8(0, 255, 0, 0)}
	var result := MapDocumentIO.parse(_format_1(3, a))
	assert_eq(result["warnings"], PackedStringArray())
	var doc: MapDocument = result["document"]
	assert_eq(doc.surface_ids, PackedStringArray(NAMES.slice(0, 3)))
	assert_eq(_sample(doc, 0), [[2, 200], [0, 40], [0, 0], [0, 0]], "high to low")
	assert_eq(_sample(doc, 1), [[1, 255], [0, 0], [0, 0], [0, 0]])
	assert_eq(doc.surface_weight(0, 0), 40)
	assert_eq(doc.surface_weight(2, 1), 0, "an unpainted sample")


func test_slots_of_the_second_image_migrate() -> void:
	var a := {Vector2i(0, 0): Color8(0, 30, 0, 0)}
	var b := {Vector2i(0, 0): Color8(0, 100, 0, 0)}
	var doc: MapDocument = MapDocumentIO.parse(_format_1(6, a, b))["document"]
	assert_eq(_sample(doc, 0), [[5, 100], [1, 30], [0, 0], [0, 0]])


func test_five_painted_surfaces_keep_the_strongest_four_and_warn_once() -> void:
	# Sample 0: slots 0-5 at 10, 20, 30, 40 / 50, 60: the total 210, the top four 180.
	# Sample 1: five at 50 (250 in all): one dropped, the rest scaled 50 * 250 / 200 = 62.
	var a := {Vector2i(0, 0): Color8(10, 20, 30, 40), Vector2i(1, 0): Color8(50, 50, 50, 50)}
	var b := {Vector2i(0, 0): Color8(50, 60, 0, 0), Vector2i(1, 0): Color8(50, 0, 0, 0)}
	var result := MapDocumentIO.parse(_format_1(6, a, b))
	var doc: MapDocument = result["document"]
	# 60, 50, 40, 30 scaled by 210 / 180, floored.
	assert_eq(_sample(doc, 0), [[5, 70], [4, 58], [3, 46], [2, 35]])
	assert_eq(doc.surface_weight(0, 0), 0, "the weakest went")
	var kept := 0
	for e in 4:
		kept += _sample(doc, 1)[e][1]
	assert_eq(kept, 248, "the painted total survives, less rounding")
	assert_true(
		Fixtures.has_warning(result, "2 samples paint over 4 surfaces"), str(result["warnings"])
	)
	var warned := 0
	for warning in result["warnings"]:
		warned += 1 if "paint over" in warning else 0
	assert_eq(warned, 1, "one warning for every crowded sample")


func test_over_full_and_stray_samples_are_fixed() -> void:
	var a := {Vector2i(0, 0): Color8(200, 200, 0, 0), Vector2i(1, 0): Color8(40, 0, 50, 0)}
	var result := MapDocumentIO.parse(_format_1(2, a))
	var doc: MapDocument = result["document"]
	assert_eq(_sample(doc, 0), [[0, 127], [1, 127], [0, 0], [0, 0]])
	assert_eq(_sample(doc, 1), [[0, 40], [0, 0], [0, 0], [0, 0]], "slot 2 is not listed")
	assert_true(Fixtures.has_warning(result, "1 samples sum past 255"))
	assert_true(Fixtures.has_warning(result, "1 samples paint an unlisted slot"))


func test_a_missing_second_image_keeps_the_first_four() -> void:
	var a := {Vector2i(0, 0): Color8(10, 20, 30, 40)}
	var result := MapDocumentIO.parse(_format_1(6, a))
	var doc: MapDocument = result["document"]
	assert_eq(doc.surface_ids.size(), 4)
	assert_eq(_sample(doc, 0), [[3, 40], [2, 30], [1, 20], [0, 10]])
	assert_true(Fixtures.has_warning(result, "surfaces 5-6"), str(result["warnings"]))


func test_a_second_image_with_four_surfaces_is_ignored() -> void:
	var b := {Vector2i(0, 0): Color8(9, 9, 9, 9)}
	var result := MapDocumentIO.parse(_format_1(4, {Vector2i(0, 0): Color8(5, 0, 0, 0)}, b))
	assert_eq(_sample(result["document"], 0), [[0, 5], [0, 0], [0, 0], [0, 0]])
	assert_true(Fixtures.has_warning(result, "surfaces_b.png with 4 surfaces"))


func test_format_1_keeps_its_eight_surface_cap() -> void:
	var result := MapDocumentIO.parse(_format_1(9, {}))
	assert_true(result["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(result, "more than 8 surfaces in format 1"))
	var without := Fixtures.minimal_entries(
		{MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"])}
	)
	var lone := MapDocumentIO.parse(without)
	assert_true(lone["document"].surface_ids.is_empty())
	assert_true(Fixtures.has_warning(lone, "without surfaces.png"))


func test_format_2_entries_in_a_format_1_document_are_ignored() -> void:
	var extra := {
		MapDocumentIO.SURFACES_JSON_ENTRY: _ids_json(["cobblestone"]),
		MapDocumentIO.SURFACES_INDEX_ENTRY: _png({}),
		MapDocumentIO.SURFACES_WEIGHT_ENTRY: _png({Vector2i(0, 0): Color8(99, 0, 0, 0)}),
	}
	var result := MapDocumentIO.parse(Fixtures.minimal_entries(extra))
	assert_true(result["document"].surface_ids.is_empty())


func test_a_migrated_document_saves_as_format_2() -> void:
	var a := {Vector2i(3, 0): Color8(0, 0, 77, 0)}
	var doc: MapDocument = MapDocumentIO.parse(_format_1(3, a))["document"]
	var packed := MapDocumentIO.serialize(doc)
	assert_eq(packed["error"], "")
	var entries: Dictionary = packed["entries"]
	assert_false(entries.has(MapDocumentIO.SURFACES_PNG_ENTRY))
	var again: Dictionary = MapDocumentIO.parse(entries)
	assert_eq(again["warnings"], PackedStringArray())
	assert_true(again["document"].surface_weights == doc.surface_weights)
	assert_eq(again["document"].surface_weight(3, 2), 77)


func test_from_slots_is_pure() -> void:
	var planes := PackedByteArray()
	planes.resize(2 * 8)
	planes[1] = 90
	planes[8 + 4 + 2] = 60
	var before := planes.duplicate()
	var got := SurfaceEntries.from_slots(planes, 2, 8)
	assert_true(planes == before, "the input is untouched")
	var entries: PackedByteArray = got["weights"]
	assert_eq(entries.size(), 2 * MapDocument.SURFACE_BYTES)
	assert_eq(Array(entries.slice(0, 8)), [1, 0, 0, 0, 6, 0, 0, 0], "indices")
	assert_eq(Array(entries.slice(8, 16)), [90, 0, 0, 0, 60, 0, 0, 0], "weights")
	assert_eq(entries[4], 6, "sample 1 paints slot 6 (image B, channel B)")
