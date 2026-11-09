extends GutTest

## The new-map recipe is deterministic to the byte: the same size, landform, biome and seed give
## the same document, written out (MapDocumentIO.serialize), as the frozen digest. Frozen before
## the recipe's whole-map loops read the sample grid once instead of per sample (perfaudit
## sysopen, 2026-11-09), so it proves that hoist changed no byte, and it catches any later change
## that moves a new map's bytes by accident. A change meant to move them (the recipe, the core
## library's biome or surfaces, the document format: re-pinned for format 4 on 2026-11-09, the
## manifest's number and the row entries' names) refreshes the digests: run each case and paste
## what it prints.

const BIOME := "temperate_forest_summer_s1"
const SEED := 1234
## [size_ft, landform, the first 16 hex digits of the digest].
const CASES: Array = [
	[100, "flat", "b8c9242bc0a23619"],
	[100, "valley", "64b2918b873c57b7"],
	[100, "hilltop", "45b7ff3e73496b83"],
	[100, "terraces", "7afd0a07e43bac9f"],
	[100, "lakeshore", "2ac8c91dff3f0bd2"],
	[100, "gorge", "0f05f9f810f85592"],
	[200, "valley", "30411ef3e06b25e1"],
]


func test_new_maps_match_their_frozen_digests() -> void:
	for case: Array in CASES:
		var doc := NewMap.create(int(case[0]), BIOME, SEED, PaletteLibrary.DEFAULT_ROOT, case[1])
		var got := digest(doc).substr(0, 16)
		assert_eq(got, String(case[2]), "%d ft %s" % [case[0], case[1]])


## SHA-256 (hex) of `doc` as MapDocumentIO.serialize writes it: each top-level key in sorted
## order ("entries", "error"), its name then its value's var_to_bytes.
static func digest(doc: MapDocument) -> String:
	var written := MapDocumentIO.serialize(doc)
	var keys := written.keys()
	keys.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for key in keys:
		ctx.update(String(key).to_utf8_buffer())
		ctx.update(var_to_bytes(written[key]))
	return ctx.finish().hex_encode()
