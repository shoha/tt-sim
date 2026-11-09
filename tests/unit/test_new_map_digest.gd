extends GutTest

## The new-map recipe is deterministic to the byte: the same size, landform, biome and seed give
## the same document, written out (MapDocumentIO.serialize), as the frozen digest. Frozen before
## the recipe's whole-map loops read the sample grid once instead of per sample (perfaudit
## sysopen, 2026-11-09), so it proves that hoist changed no byte, and it catches any later change
## that moves a new map's bytes by accident. A change meant to move them (the recipe, the core
## library's biome or surfaces) refreshes the digests: run each case and paste what it prints.

const BIOME := "temperate_forest_summer_s1"
const SEED := 1234
## [size_ft, landform, the first 16 hex digits of the digest].
const CASES: Array = [
	[100, "flat", "8e9fbb723cb876e1"],
	[100, "valley", "11b5d3e418af9dae"],
	[100, "hilltop", "b4926c3d0f4984e2"],
	[100, "terraces", "2d03b60f62e63c76"],
	[100, "lakeshore", "00314e58bf49e710"],
	[100, "gorge", "6cc6aa47e4206fac"],
	[200, "valley", "0d35b2251c02c07e"],
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
