extends GutTest
## The terrain section of map.ttmap (MapTerrainIO, format 6): the round trip bit for bit
## (primitives and digest) through the section, the map document and a file; the format choice
## (6 only with a section, 4 or 5 as before without one); the refusals of a hostile section
## (truncated, over a cap, NaN, unknown kind, reserved flag, newer version); the snapshot's
## copy-on-write; and the fingerprint key. Section bytes are built by hand with _section so each
## field can be broken alone.

const Fixtures := preload("res://tests/unit/map_document_fixtures.gd")
const FILE := "user://_terraform-p1-document_test.ttmap"


func after_all() -> void:
	for path in [FILE, FILE + MapDocumentIO.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _small() -> TerraDoc:
	var t := TerraDoc.new()
	t.add(TerraCore.PLANE, PackedFloat32Array([1.0, 0.01, -0.05]))
	t.add(TerraCore.HILL, PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 2.0]))
	t.add(TerraCore.STROKE, PackedFloat32Array([0, 0, 2.5, 0.1, 0, 1, 1, 2.5, 0.1, 1]))
	return t


## Section bytes from parts: `prims` is [[id, kind, flags, floats(Array), float count or -1]],
## `kinds` [[id, name]]; `count` -1 is prims.size().
func _section(
	prims: Array, kinds: Array, version := 1, next_id := 100, count := -1
) -> PackedByteArray:
	var out := "TTPR".to_ascii_buffer()
	out.append_array(_u16(version))
	out.append(4)
	out.append_array("test".to_ascii_buffer())
	out.append_array(_u32(prims.size() if count < 0 else count))
	out.append_array(_u32(next_id))
	out.append_array(_u16(kinds.size()))
	for k: Array in kinds:
		out.append_array(_u16(k[0]))
		out.append(String(k[1]).length())
		out.append_array(String(k[1]).to_ascii_buffer())
	for p: Array in prims:
		var data := PackedFloat32Array(p[3])
		out.append_array(_u32(p[0]))
		out.append_array(_u16(p[1]))
		out.append_array(_u16(p[2]))
		out.append_array(_u32(data.size() if p.size() < 5 else p[4]))
		out.append_array(data.to_byte_array())
	return out


func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b


func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


func _assert_same(a: TerraDoc, b: TerraDoc, label: String) -> void:
	assert_not_null(b, label)
	if b == null:
		return
	assert_eq(b.next_id, a.next_id, label + ": next_id")
	assert_eq(b.prims.size(), a.prims.size(), label + ": count")
	for i in mini(a.prims.size(), b.prims.size()):
		for key in ["id", "kind", "flags"]:
			assert_eq(int(b.prims[i][key]), int(a.prims[i][key]), "%s: %s of %d" % [label, key, i])
		var da: PackedFloat32Array = a.prims[i]["data"]
		var db: PackedFloat32Array = b.prims[i]["data"]
		assert_eq(db.to_byte_array(), da.to_byte_array(), "%s: floats of %d" % [label, i])


func _format_of(entries: Dictionary) -> int:
	var bytes: PackedByteArray = entries[MapDocumentIO.MANIFEST_ENTRY]
	return int(JSON.parse_string(bytes.get_string_from_utf8())["format"])


func _read(bytes: PackedByteArray) -> Dictionary:
	return MapTerrainIO.decode(bytes)


func _warned(read: Dictionary, fragment: String) -> bool:
	for w: String in read["warnings"]:
		if fragment in w:
			return true
	return false


# --- round trips ----------------------------------------------------------------------


func test_the_section_round_trips_bit_for_bit() -> void:
	var c := TerraCorpus.build(Vector2i(40, 48))
	c.terra.set_muted(c.terra.prims[2]["id"], true)
	var bytes := MapTerrainIO.encode(c.terra)
	var read := _read(bytes)
	assert_eq(read["warnings"], PackedStringArray())
	_assert_same(c.terra, read["terra"], "section")
	assert_eq(MapTerrainIO.encode(read["terra"]), bytes, "canonical: the same bytes again")
	assert_eq((read["terra"] as TerraDoc).digest_for(c.map_doc), c.terra.digest_for(c.map_doc))


func test_the_map_document_round_trips_the_terrain_as_format_6() -> void:
	var c := TerraCorpus.build()
	var packed := MapDocumentIO.serialize(c.map_doc)
	assert_eq(packed["error"], "")
	var entries: Dictionary = packed["entries"]
	assert_true(entries.has(MapTerrainIO.ENTRY))
	assert_eq(_format_of(entries), MapDocument.FORMAT_TERRAIN)
	var result := MapDocumentIO.parse(entries)
	assert_eq(result["warnings"], PackedStringArray())
	var doc: MapDocument = result["document"]
	var back := doc.terra as TerraDoc
	_assert_same(c.terra, back, "document")
	assert_eq(back.digest_for(doc), c.terra.digest_for(c.map_doc), "digest across reload")
	# And through a real file.
	assert_eq(MapDocumentIO.write(c.map_doc, FILE), OK)
	var from_file: Dictionary = MapDocumentIO.read(FILE)
	_assert_same(c.terra, (from_file["document"] as MapDocument).terra as TerraDoc, "file")


func test_an_empty_terrain_document_is_still_a_section() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "", "v1", 1)
	doc.terra = TerraDoc.new()
	var result := MapDocumentIO.parse(MapDocumentIO.serialize(doc)["entries"])
	var back: MapDocument = result["document"]
	assert_not_null(back.terra)
	assert_eq((back.terra as TerraDoc).prims.size(), 0)


func test_a_map_without_terrain_writes_4_or_5_as_before() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "", "v1", 1)
	var plain: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	assert_false(plain.has(MapTerrainIO.ENTRY))
	assert_eq(_format_of(plain), MapDocument.FORMAT)
	assert_null(MapDocumentIO.parse(plain)["document"].terra)
	# With terrain the other entries are the same bytes; only the manifest's format moves.
	doc.terra = _small()
	var terrain_entries: Dictionary = MapDocumentIO.serialize(doc)["entries"]
	for entry_name in plain:
		if entry_name != MapDocumentIO.MANIFEST_ENTRY:
			assert_eq(terrain_entries[entry_name], plain[entry_name], entry_name)
	# Another library and terrain: 6, with the libraries record kept.
	var lib := Fixtures.full_doc()
	lib.scatter["alienworld__basin/Spire"] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	lib.libraries = [{"id": "alienworld", "version": "0.3.1", "hash": "ab12cd34"}]
	var five: Dictionary = MapDocumentIO.serialize(lib)["entries"]
	assert_eq(_format_of(five), 5)
	lib.terra = _small()
	var six: Dictionary = MapDocumentIO.serialize(lib)["entries"]
	var m6: Dictionary = JSON.parse_string(six["manifest.json"].get_string_from_utf8())
	assert_eq(int(m6["format"]), 6)
	assert_eq(m6["libraries"].size(), 2)


func test_the_format_and_the_entry_must_agree() -> void:
	var section := MapTerrainIO.encode(_small())
	var older := MapDocumentIO.parse(
		Fixtures.minimal_entries({MapTerrainIO.ENTRY: section})
	)
	assert_null(older["document"].terra, "a format 4 document's section is ignored")
	assert_true(Fixtures.has_warning(older, "format 4 document"))
	var bare := MapDocumentIO.parse(
		Fixtures.minimal_entries({"manifest.json": Fixtures.manifest({"format": 6})})
	)
	assert_not_null(bare["document"], "a format 6 document without a section still loads")
	assert_null(bare["document"].terra)
	assert_true(Fixtures.has_warning(bare, "without a usable"))
	var full := MapDocumentIO.parse(
		Fixtures.minimal_entries(
			{"manifest.json": Fixtures.manifest({"format": 6}), MapTerrainIO.ENTRY: section}
		)
	)
	_assert_same(_small(), full["document"].terra, "format 6 with its section")
	assert_null(
		MapDocumentIO.parse(
			Fixtures.minimal_entries({"manifest.json": Fixtures.manifest({"format": 7})})
		)["document"],
		"format 7 is refused"
	)


# --- hostile sections -----------------------------------------------------------------


func test_every_truncation_is_refused() -> void:
	var bytes := MapTerrainIO.encode(_small())
	for n in bytes.size():
		var read := _read(bytes.slice(0, n))
		assert_null(read["terra"], "cut at %d" % n)
		if read["terra"] != null:
			return
	assert_true(_warned(_read(bytes.slice(0, bytes.size() - 3)), "truncated"))
	var long := bytes.duplicate()
	long.append(0)
	assert_true(_warned(_read(long), "after the last primitive"), "trailing bytes refused")


func test_caps_are_checked_before_any_read() -> void:
	var kinds := [[0, "plane"], [3, "stroke"]]
	var over_count := _section([], kinds, 1, 100, MapDocument.MAX_TERRA_PRIMS + 1)
	assert_true(_warned(_read(over_count), "primitives, over"))
	# A primitive that claims 4 G floats with none behind it: refused for the cap, not read.
	var huge := _section([[1, 3, 0, [], 0xFFFFFFFF]], kinds)
	var read := _read(huge)
	assert_null(read["terra"])
	assert_true(_warned(read, "over its cap"))
	var just_over := _section([[1, 3, 0, [], MapDocument.MAX_TERRA_FLOATS_PER_PRIM + 1]], kinds)
	assert_true(_warned(_read(just_over), "over its cap"))
	# Within the per-primitive cap but not in the bytes: truncated, nothing allocated.
	var claims := _section([[1, 3, 0, [0, 0, 1, 0.1, 0], 1000]], kinds)
	assert_true(_warned(_read(claims), "truncated"))
	# Over the document's float cap across primitives, each within its own. Planes of the wrong
	# size, so each is dropped at its count check rather than scanned float by float.
	var per := 16
	assert_eq(MapDocument.MAX_TERRA_FLOATS, per * MapDocument.MAX_TERRA_FLOATS_PER_PRIM)
	var big := PackedFloat32Array()
	big.resize(MapDocument.MAX_TERRA_FLOATS_PER_PRIM)
	var total: Array = []
	for i in per + 1:
		total.append([i + 1, 0, 0, big])
	assert_true(_warned(_read(_section(total, kinds)), "floats in all"))


func test_the_entry_has_a_cap_in_the_archive() -> void:
	assert_true(MapTerrainIO.ENTRY in MapDocumentIO.KNOWN_ENTRIES)
	assert_eq(MapDocumentIO.ENTRY_CAPS[MapTerrainIO.ENTRY], MapTerrainIO.MAX_BYTES)
	assert_lt(MapTerrainIO.MAX_BYTES, MapDocumentIO.MAX_TOTAL_BYTES)


func test_a_bad_primitive_is_dropped_with_one_counted_warning() -> void:
	var kinds := [[0, "plane"], [1, "hill"]]
	var prims := [
		[1, 0, 0, [1.0, 0.0, 0.0]],
		[2, 1, 0, [NAN, 2.0, 3.0, 4.0, 2.0]],
		[3, 1, 0, [1.0, 2.0, 3.0, 4.0, 2.0]],
		[4, 1, 0, [1.0, 2.0, 3.0, 4.0]],
		[3, 0, 0, [1.0, 0.0, 0.0]],
		[5, 0, 1, [INF, 0.0, 0.0]],
	]
	var read := _read(_section(prims, kinds, 1, 6))
	var t: TerraDoc = read["terra"]
	assert_not_null(t)
	assert_eq(t.prims.map(func(p: Dictionary) -> int: return p["id"]), [1, 3])
	assert_eq(read["warnings"].size(), 1, "one warning for all of them")
	assert_true(_warned(read, "4 primitives dropped"))
	assert_true(_warned(read, "primitive 2"), "names the first cause")


func test_an_unknown_kind_refuses_the_whole_section() -> void:
	var prims := [[1, 0, 0, [1.0, 0.0, 0.0]], [2, 16, 0, [1.0, 2.0, 3.0, 4.0, 5.0]]]
	var read := _read(_section(prims, [[0, "plane"], [16, "terrace"]]))
	assert_null(read["terra"])
	assert_true(_warned(read, "terrace"))
	assert_true(_warned(read, MapTerrainIO.NEWER))
	var renamed := _read(_section([[1, 0, 0, [1.0, 0.0, 0.0]]], [[0, "slab"]]))
	assert_null(renamed["terra"], "a known id under another name")
	var unlisted := _read(_section([[1, 1, 0, [1.0, 2.0, 3.0, 4.0, 2.0]]], [[0, "plane"]]))
	assert_null(unlisted["terra"], "a kind missing from the table")
	var twice := _read(_section([], [[0, "plane"], [0, "plane"]]))
	assert_null(twice["terra"], "a kind listed twice")


func test_newer_versions_and_reserved_flags_are_refused() -> void:
	var kinds := [[0, "plane"]]
	var v2 := _read(_section([[1, 0, 0, [1.0, 0.0, 0.0]]], kinds, 2))
	assert_null(v2["terra"])
	assert_true(_warned(v2, MapTerrainIO.NEWER))
	var flag := _read(_section([[1, 0, 4, [1.0, 0.0, 0.0]]], kinds))
	assert_null(flag["terra"])
	assert_true(_warned(flag, "reserved flags"))
	var magic := _section([], kinds)
	magic[0] = 0x58
	assert_null(_read(magic)["terra"])


func test_next_id_is_kept_above_every_id() -> void:
	var read := _read(_section([[7, 0, 0, [1.0, 0.0, 0.0]]], [[0, "plane"]], 1, 3))
	assert_eq((read["terra"] as TerraDoc).next_id, 8)
	assert_null(_read(_section([], [], 1, 0))["terra"], "next_id 0")


func test_the_writer_refuses_what_the_reader_would_drop() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "", "v1", 1)
	doc.terra = _small()
	(doc.terra as TerraDoc).prims[1]["data"] = PackedFloat32Array([NAN, 2.0, 3.0, 4.0, 2.0])
	var packed := MapDocumentIO.serialize(doc)
	assert_string_contains(packed["error"], "terrain")
	assert_true((packed["entries"] as Dictionary).is_empty())


# --- snapshot and fingerprint ---------------------------------------------------------


func test_the_snapshot_is_copy_on_write() -> void:
	var c := TerraCorpus.build()
	var expected := MapTerrainIO.encode(c.terra)
	var snap := MapDocumentSnapshot.capture(c.map_doc)
	assert_eq(snap.error, "")
	var t := c.terra
	var stroke := int(t.prims[t.prims.size() - 1]["id"])
	t.append(stroke, PackedFloat32Array([0, 0, 1, 0.2, 0]))
	(t.prims[0]["data"] as PackedFloat32Array).set(0, 42.0)
	t.replace(t.prims[3]["id"], PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 2.0]))
	t.remove(t.prims[4]["id"])
	t.set_muted(t.prims[1]["id"], true)
	t.add(TerraCore.PLANE, PackedFloat32Array([0.0, 0.0, 0.0]))
	var packed := snap.encode()
	assert_eq(packed["error"], "")
	assert_eq(packed["entries"][MapTerrainIO.ENTRY], expected, "the snapshot kept the captured list")
	assert_ne(MapTerrainIO.encode(t), expected, "the live document did change")


func test_the_fingerprint_carries_the_terrain() -> void:
	var c := TerraCorpus.build()
	var bare := MapDocument.create_flat(Vector2i(10, 10), "", "v1", 1)
	assert_eq(MapFingerprint.of(null, bare)["terra"], "")
	var fp: String = MapFingerprint.of(null, c.map_doc)["terra"]
	assert_true(fp.begins_with("%d " % c.terra.prims.size()))
	c.terra.set_muted(c.terra.prims[1]["id"], true)
	assert_ne(MapFingerprint.of(null, c.map_doc)["terra"], fp)
