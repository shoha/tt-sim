extends GutTest
## The derived record (TerraCache, terrain/derived.bin; card terraform-p1-cache): digests only.
## With a matching key a fresh derive gives the recorded digests, through the section, the map
## document and its snapshot; each kind of key change (a primitive, a mute, the grid, the core
## version) misses quietly while an add and its undo keep the key; a derive that disagrees warns
## once naming the arrays; a hostile record (truncated, over a cap, malformed) is refused while the
## terrain still loads; and a map without terrain is unaffected.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")


## A record for `c` from a full derive (the library is required).
func _record(c: TerraCorpus) -> Dictionary:
	var derive := TerraCache.derive_for(c.terra, c.map_doc)
	return TerraCache.make_record(c.terra, c.map_doc, derive)


## A record that needs no library: `c`'s key and grid, made-up digests for every name.
func _fake_record(c: TerraCorpus) -> Dictionary:
	var digests := {}
	for i in TerraCache.DIGESTS.size():
		digests[TerraCache.DIGESTS[i]] = (i + 1) * 0x1F2E3D4C5B6A7988 - 7
	var gd := TerraCore.grid_for(c.map_doc)
	return {
		"key": c.terra.derive_key_for(c.map_doc),
		"grid": TerraDoc.grid_bytes(gd["size"], gd["extent"]),
		"version": TerraCore.NATIVE_VERSION,
		"digests": digests,
	}


func _check(c: TerraCorpus, record: Dictionary, lines: Array) -> Dictionary:
	var derive := TerraCache.derive_for(c.terra, c.map_doc)
	var warn := func(l: String) -> void: lines.append(l)
	return TerraCache.check(record, c.terra, c.map_doc, derive, warn)


func _refused(bytes: PackedByteArray, fragment: String, label: String) -> void:
	var read := TerraCache.decode(bytes)
	assert_eq(read["record"], {}, label)
	assert_eq(read["warnings"].size(), 1, label + ": one warning")
	if read["warnings"].size() == 1:
		assert_string_contains(read["warnings"][0], fragment, label)


# --- the record -----------------------------------------------------------------------


func test_a_matching_key_gives_equal_digests_through_a_reload() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build_terraced()
	var record := _record(c)
	var names := PackedStringArray(record["digests"].keys())
	names.sort()
	assert_eq(names, PackedStringArray(TerraCache.DIGESTS), "the documented digest list")
	c.terra.derived = record
	var entries: Dictionary = MapDocumentIO.serialize(c.map_doc)["entries"]
	assert_true(entries.has(MapTerrainIO.DERIVED_ENTRY), "a current record is written")
	var bytes: PackedByteArray = entries[MapTerrainIO.DERIVED_ENTRY]
	assert_lt(bytes.size(), 512, "digests only: a few hundred bytes")
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	var doc: MapDocument = result["document"]
	var back := doc.terra as TerraDoc
	assert_eq(TerraCache.encode(back.derived), bytes, "the record reads back bit for bit")
	var lines: Array = []
	var got := TerraCache.derive_and_check(back, doc, func(l: String) -> void: lines.append(l))
	assert_eq(got["status"], TerraCache.MATCH)
	assert_eq(got["arrays"], PackedStringArray())
	assert_eq(lines, [], "no warning")
	assert_not_null(got["derive"], "the derive is handed on")


func test_the_record_rides_the_snapshot_and_a_stale_one_is_not_written() -> void:
	var c := TerraCorpus.build()
	c.terra.derived = _fake_record(c)
	var snap := MapDocumentSnapshot.capture(c.map_doc)
	c.terra.derived["digests"]["H2"] = 1
	var entries: Dictionary = snap.encode()["entries"]
	var read := TerraCache.decode(entries[MapTerrainIO.DERIVED_ENTRY])
	assert_ne(int(read["record"]["digests"]["H2"]), 1, "the snapshot holds its own copy")
	var data: PackedFloat32Array = c.terra.prims[1]["data"].duplicate()
	data[0] += 0.5
	c.terra.replace(c.terra.prims[1]["id"], data)
	var stale: Dictionary = MapDocumentIO.serialize(c.map_doc)["entries"]
	assert_true(stale.has(MapTerrainIO.ENTRY))
	assert_false(stale.has(MapTerrainIO.DERIVED_ENTRY), "a record for other primitives is dropped")


# --- the key --------------------------------------------------------------------------


func test_each_key_change_misses_quietly() -> void:
	var c := TerraCorpus.build()
	var record := _fake_record(c)
	assert_eq(TerraCache.miss_reason(record, c.terra, c.map_doc), "")
	# The grid: the same primitives on a map of other size.
	var other := TerraCorpus.build(Vector2i(40, 48))
	assert_eq(TerraCache.miss_reason(record, other.terra, other.map_doc), "grid")
	# The core: a record keyed and stamped by an older core.
	var gd := TerraCore.grid_for(c.map_doc)
	var old := record.duplicate(true)
	old["version"] = "terra 0 old"
	old["key"] = c.terra.derive_key(gd["size"], gd["extent"], "terra 0 old")
	assert_eq(TerraCache.miss_reason(old, c.terra, c.map_doc), "version")
	# A mute and a moved float.
	var muted := TerraCorpus.build()
	muted.terra.set_muted(muted.terra.prims[3]["id"], true)
	assert_eq(TerraCache.miss_reason(record, muted.terra, muted.map_doc), "primitives")
	var moved := TerraCorpus.build()
	var data: PackedFloat32Array = moved.terra.prims[2]["data"].duplicate()
	data[0] += 0.001
	moved.terra.replace(moved.terra.prims[2]["id"], data)
	assert_eq(TerraCache.miss_reason(record, moved.terra, moved.map_doc), "primitives")
	# An add and its undo: next_id moved, the document digest with it, the key did not.
	var undone := TerraCorpus.build()
	var before := undone.terra.digest_for(undone.map_doc)
	undone.terra.remove(undone.terra.add(TerraCore.HILL, PackedFloat32Array([0, 0, 1, 4, 2])))
	assert_ne(undone.terra.digest_for(undone.map_doc), before, "the document digest covers next_id")
	assert_eq(TerraCache.miss_reason(record, undone.terra, undone.map_doc), "", "the key does not")
	# A miss is quiet: no warning, and the status says so.
	if not TerraCore.native_available():
		return
	var lines: Array = []
	for pair: Array in [[other, record], [c, old], [moved, record]]:
		var corpus: TerraCorpus = pair[0]
		var got := _check(corpus, pair[1], lines)
		assert_eq(got["status"], TerraCache.MISS)
	assert_eq(lines, [], "misses never warn")


# --- the check ------------------------------------------------------------------------


func test_a_derive_that_disagrees_warns_once_naming_the_array() -> void:
	if not TerraCore.native_available():
		pending(TerraCorpus.NO_LIBRARY)
		return
	var c := TerraCorpus.build()
	var record := _record(c)
	var lines: Array = []
	var derive := TerraCache.derive_for(c.terra, c.map_doc)
	derive.call("debug_set_sample", "H2", 20, 30, 0.25, false)
	var got := TerraCache.check(
		record, c.terra, c.map_doc, derive, func(l: String) -> void: lines.append(l)
	)
	assert_eq(got["status"], TerraCache.MISMATCH)
	assert_eq(got["arrays"], PackedStringArray(["H2"]), "one sample of H2 changed, nothing else")
	assert_eq(lines.size(), 1, "one warning")
	if lines.size() == 1:
		assert_string_contains(lines[0], "H2")
		assert_string_contains(lines[0], "1 of %d" % TerraCache.DIGESTS.size())
	# A record that names two other values: both named, still one warning.
	var tampered := record.duplicate(true)
	tampered["digests"]["WL"] = int(tampered["digests"]["WL"]) ^ 1
	tampered["digests"]["water"] = int(tampered["digests"]["water"]) + 1
	lines.clear()
	got = _check(c, tampered, lines)
	assert_eq(got["arrays"], PackedStringArray(["WL", "water"]))
	assert_eq(lines.size(), 1)


# --- hostile records ------------------------------------------------------------------


func test_every_truncation_and_trailing_byte_is_refused() -> void:
	var bytes := TerraCache.encode(_fake_record(TerraCorpus.build()))
	var read := TerraCache.decode(bytes)
	assert_eq(read["warnings"], PackedStringArray())
	assert_eq(TerraCache.encode(read["record"]), bytes, "canonical")
	for n in bytes.size():
		var cut := TerraCache.decode(bytes.slice(0, n))
		assert_eq(cut["record"], {}, "cut at %d" % n)
		assert_eq(cut["warnings"].size(), 1, "cut at %d warns once" % n)
	var longer := bytes.duplicate()
	longer.append(0)
	_refused(longer, "after the last digest", "a trailing byte")


func test_caps_and_malformed_records_are_refused() -> void:
	var bytes := TerraCache.encode(_fake_record(TerraCorpus.build()))
	var big := PackedByteArray()
	big.resize(TerraCache.MAX_BYTES + 1)
	_refused(big, "over %d" % TerraCache.MAX_BYTES, "over the entry cap")
	var magic := bytes.duplicate()
	magic[0] = 0x58
	_refused(magic, "not a TTDC", "bad magic")
	var newer := bytes.duplicate()
	newer.encode_u16(4, 2)
	_refused(newer, "made by a newer version", "a newer version")
	# The digest count sits after the core version string.
	var count_at := 4 + 2 + TerraCache.KEY_BYTES + TerraCache.GRID_BYTES + 1
	count_at += bytes[count_at - 1]
	var many := bytes.duplicate()
	many.encode_u16(count_at, MapDocument.MAX_TERRA_DIGESTS + 1)
	_refused(many, "over %d" % MapDocument.MAX_TERRA_DIGESTS, "too many digests")
	var huge := bytes.duplicate()
	huge.encode_u16(count_at, MapDocument.MAX_TERRA_DIGESTS)
	_refused(huge, "need at least", "a count the bytes cannot hold, checked before the loop")
	# The first digest is "CT": rename it "WL" (out of order) and "C?" (malformed).
	var order := bytes.duplicate()
	order[count_at + 3] = 0x57
	order[count_at + 4] = 0x4C
	_refused(order, "out of order", "names out of order")
	var bad := bytes.duplicate()
	bad[count_at + 4] = 0x3F
	_refused(bad, "malformed name", "a malformed name")
	assert_eq(
		MapDocumentIO.ENTRY_CAPS[MapTerrainIO.DERIVED_ENTRY], MapDocument.MAX_TERRA_DERIVED_BYTES
	)


func test_a_refused_record_leaves_the_terrain_loaded() -> void:
	var c := TerraCorpus.build()
	c.terra.derived = _fake_record(c)
	var entries: Dictionary = MapDocumentIO.serialize(c.map_doc)["entries"]
	var cut: PackedByteArray = entries[MapTerrainIO.DERIVED_ENTRY]
	entries[MapTerrainIO.DERIVED_ENTRY] = cut.slice(0, 40)
	var result := MapDocumentIO.parse(entries)
	var back := (result["document"] as MapDocument).terra as TerraDoc
	assert_not_null(back)
	assert_eq(back.prims.size(), c.terra.prims.size())
	assert_eq(back.derived, {})
	assert_true(Fixtures.has_warning(result, "derived.bin refused"))


# --- maps without terrain -------------------------------------------------------------


func test_a_map_without_terrain_is_unaffected() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "", "v1", 1)
	var plain: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	assert_false(plain.has(MapTerrainIO.DERIVED_ENTRY))
	var c := TerraCorpus.build()
	var record := TerraCache.encode(_fake_record(c))
	# In a format 4 document the record is ignored with a warning, like the section.
	var older := MapDocumentIO.parse(Fixtures.minimal_entries({MapTerrainIO.DERIVED_ENTRY: record}))
	assert_not_null(older["document"])
	assert_null(older["document"].terra)
	assert_true(Fixtures.has_warning(older, "derived.bin in a format 4 document"))
	# In format 6 without the section there is no terrain to check.
	var alone := MapDocumentIO.parse(
		Fixtures.minimal_entries(
			{"manifest.json": Fixtures.manifest({"format": 6}), MapTerrainIO.DERIVED_ENTRY: record}
		)
	)
	assert_null(alone["document"].terra)
	# A terrain document without a record writes no record and loads with none.
	doc.terra = TerraDoc.new()
	var bare: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	assert_false(bare.has(MapTerrainIO.DERIVED_ENTRY))
	var back := MapDocumentIO.parse(bare)["document"].terra as TerraDoc
	assert_eq(back.derived, {})
	assert_eq(
		TerraCache.check(back.derived, back, doc, null)["status"], TerraCache.NONE, "no record"
	)
