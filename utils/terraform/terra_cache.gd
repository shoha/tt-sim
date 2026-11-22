class_name TerraCache
extends RefCounted
## The derived record of a terrain document (docs/systems/terraform.md "The derived record";
## map_document.md "Terrain section (format 6)"): what the derive made from the primitives, as
## one digest per derived array and record, saved beside the document as terrain/derived.bin.
##
## Digests only (owner, 2026-11-22: "the checksum approach"): the record never holds the arrays,
## because a derive at the largest map takes tens of milliseconds and the arrays would add
## megabytes to every map and its late-join transfer. A load derives (derive_full) and compares;
## a digest that differs is the cross-machine determinism check peers rely on, and it warns once,
## naming the arrays. The record is keyed by TerraDoc.derive_key() (the primitives without
## next_id, the derive grid and the core version), so a changed primitive, grid or core misses the
## key and the map re-derives quietly: there is nothing to compare against.
##
## Digests (DIGESTS, the names TerraDerive.digests() returns plus "water"): FNV-1a 64 of each
## per-sample array (Hraw SW H0 H1 WL Hp H2 SL DW DP DF PW HB CV PM FM WM PI CT), of the fall
## records ("falls") and of the wall pads and openings ("walls"), all computed natively; and
## "water", the first 8 bytes of SHA-256 over the river and pond records (water_records(): ids,
## levels, lines, half widths, receivers), small enough to hash here.
##
## terrain/derived.bin, "TTDC" version 1, little-endian, canonical (one record, one byte string):
##   magic "TTDC", u16 version, the 32 key bytes (raw SHA-256), the 24 grid bytes
##   (TerraDoc.grid_bytes), u8 length + ASCII core version, u16 digest count, then per digest in
##   ascending name order u8 length + ASCII name and the u64 digest.
## It is untrusted input, read as MapTerrainIO reads prims.bin: every count is checked against
## its cap (MapDocument.MAX_TERRA_DIGESTS, entry MAX_TERRA_DERIVED_BYTES) and the bytes left
## before it is read. A bad record is refused with one warning and the map derives without the
## check; a record is never needed to load a map.

const MAGIC := "TTDC"
const VERSION := 1
const KEY_BYTES := 32
const GRID_BYTES := 24
## Longest digest name and core version string.
const MAX_NAME_LENGTH := 32
const MAX_VERSION_LENGTH := 64
## Bytes of the smallest digest entry (a one-letter name and its u64).
const MIN_DIGEST_BYTES := 10
const MAX_BYTES := MapDocument.MAX_TERRA_DERIVED_BYTES
## Every digest the record holds today (see the header), in the record's ascending order.
const DIGESTS: Array[String] = [
	"CT",
	"CV",
	"DF",
	"DP",
	"DW",
	"FM",
	"H0",
	"H1",
	"H2",
	"HB",
	"Hp",
	"Hraw",
	"PI",
	"PM",
	"PW",
	"SL",
	"SW",
	"WL",
	"WM",
	"falls",
	"walls",
	"water",
]

## check() statuses: no record; a record for other primitives, grid or core (quiet); every
## digest equal; at least one digest differs (warned).
const NONE := "none"
const MISS := "miss"
const MATCH := "match"
const MISMATCH := "mismatch"


## The record of `derive` (a TerraDerive after a derive of `terra` on `doc`'s grid):
## {"key": 64 hex digits, "grid": the 24 grid bytes, "version": core version, "digests":
## {name: int}}. Main thread or the derive's owner.
static func make_record(terra: TerraDoc, doc: MapDocument, derive: RefCounted) -> Dictionary:
	var gd := TerraCore.grid_for(doc)
	return {
		"key": terra.derive_key(gd["size"], gd["extent"]),
		"grid": TerraDoc.grid_bytes(gd["size"], gd["extent"]),
		"version": TerraCore.NATIVE_VERSION,
		"digests": digests_of(derive),
	}


## Every digest of `derive` (DIGESTS): {name: int}.
static func digests_of(derive: RefCounted) -> Dictionary:
	var out: Dictionary = (derive.call("digests") as Dictionary).duplicate()
	out["water"] = water_digest(derive.call("water_records"))
	return out


## The "water" digest of TerraDerive.water_records() `records`: the first 8 bytes of SHA-256
## over each river (id, receivers, half width, fall count, levels, line) and pond (id, level).
static func water_digest(records: Dictionary) -> int:
	var b := PackedByteArray()
	for r: Dictionary in records.get("rivers", []):
		_put_s64(b, int(r["id"]))
		_put_s64(b, int(r["recv_river"]))
		_put_s64(b, int(r["recv_pond"]))
		_put_s64(b, int(r["falls"]))
		_put_f64(b, float(r["hw"]))
		for key: String in ["level", "pts"]:
			var a: PackedFloat32Array = r[key]
			_put_s64(b, a.size())
			b.append_array(a.to_byte_array())
	for p: Dictionary in records.get("ponds", []):
		_put_s64(b, int(p["id"]))
		_put_f64(b, float(p["level"]))
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	# A map without water hashes nothing (update() refuses an empty buffer; the digest is the
	# same SHA-256 of no bytes it gave with the error).
	if not b.is_empty():
		ctx.update(b)
	return ctx.finish().decode_s64(0)


## A TerraDerive on `doc`'s grid with every primitive of `terra` that is not muted set in
## document order, after derive_full(); null without the library.
static func derive_for(terra: TerraDoc, doc: MapDocument) -> RefCounted:
	var derive := prepare(terra, doc)
	if derive != null:
		derive.call("derive_full")
	return derive


## A TerraDerive on `doc`'s grid with every primitive of `terra` that is not muted set in
## document order, not yet derived; null without the library. A primitive the native registry
## refuses (set_prim false: the two registries disagree, which test_terra_kinds rules out) is
## left out with one warning counting them.
static func prepare(terra: TerraDoc, doc: MapDocument) -> RefCounted:
	var derive := TerraCore.make_derive(doc)
	if derive == null:
		return null
	var refused := 0
	for p in terra.prims:
		if not TerraDoc.is_muted(p) and not derive.call("set_prim", p["id"], p["kind"], p["data"]):
			refused += 1
	if refused > 0:
		push_warning("terrain: the core refused %d primitives of kinds it does not know" % refused)
	return derive


## True when `record` was made from `terra` on `doc`'s grid by this core (its key matches).
static func key_matches(record: Dictionary, terra: TerraDoc, doc: MapDocument) -> bool:
	return String(record.get("key", "")) == terra.derive_key_for(doc)


## Why `record` does not belong to `terra` on `doc`'s grid with this core: "version", "grid",
## "primitives", or "" when its key matches. Version and grid are named first: the key covers
## them too.
static func miss_reason(record: Dictionary, terra: TerraDoc, doc: MapDocument) -> String:
	if key_matches(record, terra, doc):
		return ""
	if String(record.get("version", "")) != TerraCore.NATIVE_VERSION:
		return "version"
	var gd := TerraCore.grid_for(doc)
	if record.get("grid", PackedByteArray()) != TerraDoc.grid_bytes(gd["size"], gd["extent"]):
		return "grid"
	return "primitives"


## Compares `record` with `derive` (a derive of `terra` on `doc`'s grid): {"status": NONE, MISS,
## MATCH or MISMATCH, "reason": miss_reason() for a miss, "arrays": the names whose digests
## differ, ascending}. A mismatch calls `warn` (push_warning when invalid) once, naming them.
static func check(
	record: Dictionary,
	terra: TerraDoc,
	doc: MapDocument,
	derive: RefCounted,
	warn := Callable()
) -> Dictionary:
	var out := {"status": NONE, "reason": "", "arrays": PackedStringArray()}
	if record.is_empty():
		return out
	out["reason"] = miss_reason(record, terra, doc)
	if out["reason"] != "":
		out["status"] = MISS
		return out
	var saved: Dictionary = record["digests"]
	var now := digests_of(derive)
	var names := {}
	for n: String in saved.keys() + now.keys():
		if not saved.has(n) or not now.has(n) or int(saved[n]) != int(now[n]):
			names[n] = true
	var differ := PackedStringArray(names.keys())
	differ.sort()
	out["arrays"] = differ
	out["status"] = MATCH if differ.is_empty() else MISMATCH
	if not differ.is_empty():
		var line := (
			(
				"terrain: this derive disagrees with the map's derived record in %s (%d of %d "
				+ "digests): the core that saved the map derived it differently"
			)
			% [", ".join(differ), differ.size(), names.size() + _equal(saved, now)]
		)
		if warn.is_valid():
			warn.call(line)
		else:
			push_warning(line)
	return out


## The load-time check: derives `terra` on `doc`'s grid (derive_for) and compares the result with
## the document's own record (check). {"derive": the TerraDerive, or null without the library,
## and check()'s keys}; status NONE without the library.
static func derive_and_check(terra: TerraDoc, doc: MapDocument, warn := Callable()) -> Dictionary:
	var derive := derive_for(terra, doc)
	var out := {"status": NONE, "reason": "", "arrays": PackedStringArray()}
	if derive != null:
		out = check(terra.derived, terra, doc, derive, warn)
	out["derive"] = derive
	return out


## The canonical bytes of `record` (see the header). Pure.
static func encode(record: Dictionary) -> PackedByteArray:
	var out := PackedByteArray()
	out.append_array(MAGIC.to_ascii_buffer())
	_put_u16(out, VERSION)
	out.append_array(String(record["key"]).hex_decode())
	out.append_array(record["grid"])
	var version: PackedByteArray = String(record["version"]).to_ascii_buffer()
	out.append(version.size())
	out.append_array(version)
	var digests: Dictionary = record["digests"]
	var names := PackedStringArray(digests.keys())
	names.sort()
	_put_u16(out, names.size())
	for n in names:
		var ascii := n.to_ascii_buffer()
		out.append(ascii.size())
		out.append_array(ascii)
		_put_s64(out, int(digests[n]))
	return out


## Decodes `bytes`: {"record": the record (make_record's form), or {} when refused, "warnings":
## PackedStringArray}. Pure; never raises and never allocates from an unchecked size.
static func decode(bytes: PackedByteArray) -> Dictionary:
	var warnings := PackedStringArray()
	var cause := ""
	var record := {}
	if bytes.size() > MAX_BYTES:
		cause = "%d bytes, over %d" % [bytes.size(), MAX_BYTES]
	else:
		var read := _decode(bytes)
		record = read["record"]
		cause = read["error"]
	if cause != "":
		record = {}
		warnings.append(
			(
				"%s refused: %s; the map derives without the check"
				% [MapDocumentIO.TERRAIN_DERIVED_ENTRY, cause]
			)
		)
	return {"record": record, "warnings": warnings}


static func _decode(bytes: PackedByteArray) -> Dictionary:
	var fail := func(reason: String) -> Dictionary: return {"record": {}, "error": reason}
	var head := 4 + 2 + KEY_BYTES + GRID_BYTES + 1
	if bytes.size() < head:
		return fail.call("truncated header")
	if bytes.slice(0, 4) != MAGIC.to_ascii_buffer():
		return fail.call("not a TTDC record")
	var version := bytes.decode_u16(4)
	if version != VERSION:
		var newer := version > VERSION
		return fail.call("version %d, %s" % [version, "made by a newer version" if newer else "unknown"])
	var key := bytes.slice(6, 6 + KEY_BYTES).hex_encode()
	var grid := bytes.slice(6 + KEY_BYTES, head - 1)
	var at := head
	var vlen := bytes[head - 1]
	if vlen > MAX_VERSION_LENGTH or bytes.size() < at + vlen + 2:
		return fail.call("truncated or over-long core version")
	var core := bytes.slice(at, at + vlen).get_string_from_ascii()
	at += vlen
	var count := bytes.decode_u16(at)
	at += 2
	if count > MapDocument.MAX_TERRA_DIGESTS:
		return fail.call("%d digests, over %d" % [count, MapDocument.MAX_TERRA_DIGESTS])
	if bytes.size() - at < count * MIN_DIGEST_BYTES:
		return fail.call((
				"truncated: %d digests need at least %d bytes"
				% [count, count * MIN_DIGEST_BYTES]
			)
		)
	var digests := {}
	var last := ""
	for i in count:
		var n := bytes[at] if at < bytes.size() else 0
		if n < 1 or n > MAX_NAME_LENGTH or bytes.size() - at - 1 < n + 8:
			return fail.call("truncated or bad name at digest %d" % i)
		var digest_name := bytes.slice(at + 1, at + 1 + n).get_string_from_ascii()
		if not _is_name(digest_name) or digest_name.length() != n:
			return fail.call("digest %d has a malformed name" % i)
		if i > 0 and digest_name <= last:
			return fail.call("digest '%s' is out of order or repeated" % digest_name)
		at += 1 + n
		digests[digest_name] = bytes.decode_s64(at)
		at += 8
		last = digest_name
	if at != bytes.size():
		return fail.call("%d bytes after the last digest" % (bytes.size() - at))
	var record := {"key": key, "grid": grid, "version": core, "digests": digests}
	return {"record": record, "error": ""}


## True for a digest name: ASCII letters, digits and underscores.
static func _is_name(text: String) -> bool:
	for c in text:
		if not (c == "_" or (c >= "0" and c <= "9") or (c >= "A" and c <= "Z")):
			if not (c >= "a" and c <= "z"):
				return false
	return text != ""


## How many names both dictionaries hold with equal values (for the warning's count).
static func _equal(saved: Dictionary, now: Dictionary) -> int:
	var n := 0
	for k: String in saved:
		if now.has(k) and int(saved[k]) == int(now[k]):
			n += 1
	return n


static func _put_u16(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 2)
	out.encode_u16(at, v)


static func _put_s64(out: PackedByteArray, v: int) -> void:
	var at := out.size()
	out.resize(at + 8)
	out.encode_s64(at, v)


static func _put_f64(out: PackedByteArray, v: float) -> void:
	var at := out.size()
	out.resize(at + 8)
	out.encode_double(at, v)
