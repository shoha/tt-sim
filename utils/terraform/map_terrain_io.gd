class_name MapTerrainIO
extends RefCounted
## Reads and writes the terrain section of `map.ttmap` (MapDocument.terra, a TerraDoc; summary in
## docs/systems/map_document.md "Terrain section (format 6)"):
##   terrain/prims.bin   the primitive list, "TTPR" version 1, little-endian:
##     header   magic "TTPR", u16 version, u8 length + ASCII writer core version (informational,
##              TerraCore.NATIVE_VERSION), u32 primitive count, u32 next_id, u16 kind count,
##              then per kind used (ascending id) u16 id, u8 length, ASCII name
##     per primitive, in document order (the order compose applies): u32 id, u16 kind, u16 flags,
##              u32 float count, then that many float32
## The bytes are canonical: one document encodes to one byte string (kinds ascending, nothing
## optional), so TerraDoc.digest() hashes them.
##   terrain/derived.bin the derived record (TerraCache: its bytes, caps and refusals), read only
##              beside prims.bin and written only while its key matches the document
##
## A document with a section is format 6 (MapDocument.FORMAT_TERRAIN), so a build that knows no
## terrain refuses it rather than dropping the section on its next save; one without a section
## writes 4 or 5 as before, byte for byte.
##
## The section is untrusted input, read in MapDocumentIO's style: every count is checked against
## its cap and every size against the bytes left before anything is read or allocated, NaN and
## Inf are rejected, and nothing here raises. What happens to a bad section:
## - truncated, over a cap, a malformed kind table or trailing bytes: the section is refused (the
##   map loads without terrain) with a warning naming the cause;
## - a kind this version does not know (or knows by another name), a version above VERSION or a
##   reserved flag bit set: the section is refused with a warning that says it was made by a newer
##   version, so no save of this build can drop part of its primitives without the author told;
## - a primitive that fails its kind's validate() (TerraKinds) or repeats an id: that primitive is
##   dropped, with one warning counting the dropped primitives and naming the first cause.

## The entry's name, owned by MapDocumentIO (which reads this script by path, on first use).
const ENTRY := MapDocumentIO.TERRAIN_ENTRY
## The derived record's entry (TerraCache: digests of the derived arrays, keyed by the document).
const DERIVED_ENTRY := MapDocumentIO.TERRAIN_DERIVED_ENTRY
const MAGIC := "TTPR"
const VERSION := 1
## Bytes of one primitive's fixed part (id, kind, flags, float count).
const PRIM_HEADER_BYTES := 12
## Longest core version string and kind name the header may carry.
const MAX_NAME_LENGTH := 64
## Kinds a kind table may list (u16 ids; far more than any version defines).
const MAX_KINDS := 1024
## The entry's cap (MapDocument.MAX_TERRA_SECTION_BYTES, about 16.1 MB).
const MAX_BYTES := MapDocument.MAX_TERRA_SECTION_BYTES
## The phrase of every refusal for a section this version cannot read in full.
const NEWER := "made by a newer version"


## Adds the entry to `entries` when `doc` has a terrain document, and the derived record
## (TerraCache, DERIVED_ENTRY) when it has one whose key matches the document now: a record left
## from before an edit is dropped rather than written stale. Run after `doc` passed problem(); any
## thread.
static func serialize(doc: MapDocument, entries: Dictionary) -> void:
	if doc.terra == null:
		return
	var terra := doc.terra as TerraDoc
	entries[ENTRY] = encode(terra)
	if not terra.derived.is_empty() and TerraCache.key_matches(terra.derived, terra, doc):
		entries[DERIVED_ENTRY] = TerraCache.encode(terra.derived)


## The first rule the reader enforces that `doc`'s terrain breaks, or "" (none, or a valid
## one): TerraDoc.problem(). Reads only the terrain document, so any thread.
static func problem(doc: MapDocument) -> String:
	if doc.terra == null:
		return ""
	if not doc.terra is TerraDoc:
		return "terra is not a TerraDoc"
	return (doc.terra as TerraDoc).problem()


## The canonical bytes of `terra` (see the header). Pure. `with_next_id` false writes next_id as 0
## (TerraDoc.derive_key's bytes; never a section, which the reader refuses for it).
static func encode(terra: TerraDoc, with_next_id := true) -> PackedByteArray:
	var kinds := {}
	for p in terra.prims:
		kinds[int(p["kind"])] = true
	var kind_ids := kinds.keys()
	kind_ids.sort()
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	_put_u16(out, VERSION)
	_put_name(out, TerraCore.NATIVE_VERSION)
	_put_u32(out, terra.prims.size())
	_put_u32(out, terra.next_id if with_next_id else 0)
	_put_u16(out, kind_ids.size())
	for kind: int in kind_ids:
		_put_u16(out, kind)
		_put_name(out, TerraKinds.name_of(kind))
	for p in terra.prims:
		var data: PackedFloat32Array = p["data"]
		_put_u32(out, int(p["id"]))
		_put_u16(out, int(p["kind"]))
		_put_u16(out, int(p["flags"]))
		_put_u32(out, data.size())
		out.append_array(data.to_byte_array())
	return out


## Reads the entry from `blobs` into `doc.terra` (null when absent or refused). Only a format 6
## document carries one: in format 6 a missing section is a warning, and an entry in an older
## format is ignored with one.
static func parse(
	blobs: Dictionary, doc: MapDocument, format: int, warn_log: MapDocumentIO._WarningLog
) -> void:
	doc.terra = null
	var has_entry := blobs.has(ENTRY)
	if format < MapDocument.FORMAT_TERRAIN:
		for entry: String in [ENTRY, DERIVED_ENTRY]:
			if blobs.has(entry):
				warn_log.add("%s in a format %d document; ignored" % [entry, format])
		return
	if not has_entry:
		warn_log.add("format %d without a usable %s; the map has no terrain" % [format, ENTRY])
		return
	var read := decode(blobs[ENTRY])
	for line: String in read["warnings"]:
		warn_log.add(line)
	doc.terra = read["terra"]
	if doc.terra != null and blobs.has(DERIVED_ENTRY):
		var record := TerraCache.decode(blobs[DERIVED_ENTRY])
		for line: String in record["warnings"]:
			warn_log.add(line)
		(doc.terra as TerraDoc).derived = record["record"]


## Decodes `bytes` (see the header): {"terra": TerraDoc or null, "warnings": PackedStringArray}.
## Pure; never raises and never allocates from a size it has not checked against the caps and
## the bytes left.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var r := _Reader.new(bytes)
	var warnings := PackedStringArray()
	var terra := _decode(r)
	if terra == null:
		warnings.append("%s refused: %s; the map has no terrain" % [ENTRY, r.error])
	elif r.dropped > 0:
		warnings.append(
			(
				"%s: %d primitives dropped (the first: %s)"
				% [ENTRY, r.dropped, r.first_drop]
			)
		)
	return {"terra": terra, "warnings": warnings}


static func _decode(r: _Reader) -> TerraDoc:
	if r.take(4) != MAGIC.to_ascii_buffer():
		return r.fail("not a TTPR section")
	var version := r.u16()
	if r.ok and version != VERSION:
		return r.fail("version %d, %s" % [version, NEWER if version > VERSION else "unknown"])
	r.text()
	var count := r.u32()
	var next_id := r.u32()
	var kind_count := r.u16()
	if not r.ok:
		return r.fail("truncated header")
	if count > MapDocument.MAX_TERRA_PRIMS:
		return r.fail("%d primitives, over %d" % [count, MapDocument.MAX_TERRA_PRIMS])
	if next_id < 1 or next_id > TerraDoc.MAX_ID + 1:
		return r.fail("next_id %d is out of range" % next_id)
	if kind_count > MAX_KINDS:
		return r.fail("%d kinds, over %d" % [kind_count, MAX_KINDS])
	var kinds := _kind_table(r, kind_count)
	if kinds.is_empty() and kind_count > 0:
		return null
	if r.left() < count * PRIM_HEADER_BYTES:
		return r.fail(
			"truncated: %d primitives need at least %d bytes" % [count, count * PRIM_HEADER_BYTES]
		)
	var terra := TerraDoc.new()
	var seen := {}
	var total := 0
	var top := 0
	for i in count:
		var id := r.u32()
		var kind := r.u16()
		var flags := r.u16()
		var floats := r.u32()
		if not r.ok:
			return r.fail("truncated at primitive %d" % i)
		if not kinds.has(kind):
			return r.fail("primitive %d names kind %d, not in its kind table" % [id, kind])
		if flags & ~TerraDoc.KNOWN_FLAGS != 0:
			return r.fail("primitive %d sets reserved flags %d, %s" % [id, flags, NEWER])
		if floats > MapDocument.MAX_TERRA_FLOATS_PER_PRIM:
			return r.fail("primitive %d holds %d floats, over its cap" % [id, floats])
		total += floats
		if total > MapDocument.MAX_TERRA_FLOATS:
			return r.fail("over %d floats in all" % MapDocument.MAX_TERRA_FLOATS)
		if r.left() < floats * 4:
			return r.fail("truncated in primitive %d's floats" % id)
		var data := r.take(floats * 4).to_float32_array()
		var reason := TerraKinds.problem(kind, data)
		if reason == "" and (id < 1 or id > TerraDoc.MAX_ID or seen.has(id)):
			reason = "id %d is out of range or repeated" % id
		if reason != "":
			r.drop("primitive %d: %s" % [id, reason])
			continue
		seen[id] = true
		top = maxi(top, id)
		terra.prims.append({"id": id, "kind": kind, "flags": flags, "data": data})
	if r.left() != 0:
		return r.fail("%d bytes after the last primitive" % r.left())
	terra.next_id = maxi(next_id, top + 1)
	return terra


## The kind table: {kind id: true} for each listed kind this version knows by the same name, or
## {} with `r.error` set (truncated, repeated, or a kind of a newer version).
static func _kind_table(r: _Reader, kind_count: int) -> Dictionary:
	var kinds := {}
	for k in kind_count:
		var kind := r.u16()
		var kind_name := r.text()
		if not r.ok:
			r.fail("truncated kind table")
			return {}
		if kinds.has(kind):
			r.fail("kind %d listed twice" % kind)
			return {}
		if not TerraKinds.has(kind) or TerraKinds.name_of(kind) != kind_name:
			r.fail("kind '%s' (%d) is unknown here, %s" % [kind_name.c_escape(), kind, NEWER])
			return {}
		kinds[kind] = true
	return kinds


static func _put_u16(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 2)
	out.encode_u16(at, v)


static func _put_u32(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 4)
	out.encode_u32(at, v)


static func _put_name(out: PackedByteArray, text: String) -> void:
	var ascii := text.to_ascii_buffer()
	out.append(mini(ascii.size(), MAX_NAME_LENGTH))
	out.append_array(ascii.slice(0, MAX_NAME_LENGTH))


## A bounds-checked cursor over the section: a read past the end sets `ok` false and returns
## zero, so the parser checks once per group of reads.
class _Reader:
	var bytes: PackedByteArray
	var at := 0
	var ok := true
	var error := ""
	var dropped := 0
	var first_drop := ""

	func _init(data: PackedByteArray) -> void:
		bytes = data

	func left() -> int:
		return bytes.size() - at

	func take(n: int) -> PackedByteArray:
		if not ok or n < 0 or left() < n:
			ok = false
			return PackedByteArray()
		at += n
		return bytes.slice(at - n, at)

	func u16() -> int:
		if not ok or left() < 2:
			ok = false
			return 0
		at += 2
		return bytes.decode_u16(at - 2)

	func u32() -> int:
		if not ok or left() < 4:
			ok = false
			return 0
		at += 4
		return bytes.decode_u32(at - 4)

	## A u8 length, then that many ASCII bytes.
	func text() -> String:
		if not ok or left() < 1:
			ok = false
			return ""
		var n := bytes[at]
		at += 1
		return take(n).get_string_from_ascii()

	## Records the reason the section is refused and returns null (for `return r.fail(...)`).
	func fail(reason: String) -> TerraDoc:
		ok = false
		if error == "":
			error = reason
		return null

	func drop(reason: String) -> void:
		dropped += 1
		if first_drop == "":
			first_drop = reason
