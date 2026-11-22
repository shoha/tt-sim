class_name TerraDoc
extends RefCounted
## The terrain document (docs/systems/terraform.md, map_document.md "Terrain section"): only
## what the author made, as an ordered list of typed primitives. Everything the map shows is
## derived from this list by TerraDerive's stages, so erase is "remove (or mute) the primitive"
## and nothing is ever frozen. List order is document order, the order compose applies.
##
## A primitive is {"id": int, "kind": int, "flags": int, "data": PackedFloat32Array}. Ids are
## stable within a document (1 up, never reused while next_id grows); kinds are the stable ids
## of the kind registry, TerraKinds (0 to 8 built in, 9 to 15 reserved, 16 up for new kinds),
## and each kind's script holds its float layout and validate(). Flag bit 0 is MUTED:
## the primitive stays in the document but the derive skips it, so erase can weaken a
## primitive rather than delete it. Other flag bits are reserved and must be 0.
##
## Bounded: at most MapDocument.MAX_TERRA_PRIMS primitives, MAX_TERRA_FLOATS_PER_PRIM floats in
## one and MAX_TERRA_FLOATS in all. The mutators refuse an edit past a cap (add returns -1,
## append and replace false), so a session can never build a document the writer refuses for
## its size.
##
## Copy-on-write: duplicate() copies the list and each primitive's dictionary, and gives each a
## copy-on-write copy of the float array (the live array copies itself on its next write), so
## the map document snapshot captures a terrain document in microseconds per primitive.
##
## digest() is the key the derived cache and peer agreement use: SHA-256 over the canonical
## prims.bin bytes (MapTerrainIO.encode), the derive grid (samples per axis and the steps as
## float64 bits) and TerraCore.NATIVE_VERSION. derive_key() is the same hash with next_id written
## as 0: the derived result depends on the primitives (ids, kinds, flags, floats, order), never on
## the id the next add would take, so an add followed by its undo keeps the derived record's key.
##
## `derived` is the derived record read with the map (TerraCache, terrain/derived.bin): the
## digests of the derived arrays keyed by derive_key(), or {} for none. It is not part of the
## document (no digest covers it) and is written only while its key matches the document.

## Flag bit 0: the primitive is kept but not derived.
const MUTED := 1
## Every flag bit this version knows; a set bit outside it is from a newer version.
const KNOWN_FLAGS := MUTED
## Largest primitive id (ids are u32 on disk, kept within a positive int32).
const MAX_ID := 0x7FFFFFFF

## The primitives in document order (see the header for the form).
var prims: Array[Dictionary] = []
## The id the next add() takes; always above every id in the list.
var next_id := 1
## The derived record (see the header; TerraCache.make_record's form), or {}.
var derived: Dictionary = {}
## Called by MapDocumentSnapshot.capture() before it copies this document, on the main thread:
## the attached TerraSession refreshes `derived` there (TerraSession.capture_for_save). Not part
## of the document: duplicate() leaves the copy's empty, and a callable whose session was freed
## is no longer valid.
var before_save := Callable()


## Adds a primitive at the end of the document and returns its id, or -1 when the document
## holds MapDocument.MAX_TERRA_PRIMS primitives, `data` is over a float cap or the ids ran out.
func add(kind: int, data: PackedFloat32Array, flags := 0) -> int:
	if prims.size() >= MapDocument.MAX_TERRA_PRIMS or next_id > MAX_ID:
		return -1
	if not _fits(data.size(), 0):
		return -1
	var id := next_id
	next_id += 1
	prims.append({"id": id, "kind": kind, "flags": flags, "data": data})
	return id


## Appends floats (whole items) to a primitive. False, and nothing changed, when there is no
## primitive `id` or the result would pass a float cap.
func append(id: int, data: PackedFloat32Array) -> bool:
	var p := find(id)
	if p.is_empty():
		return false
	var d: PackedFloat32Array = p["data"]
	if not _fits(d.size() + data.size(), d.size()):
		return false
	d.append_array(data)
	p["data"] = d
	return true


## Replaces a primitive's floats, keeping its place in the order. False, and nothing changed,
## when there is no primitive `id` or `data` would pass a float cap.
func replace(id: int, data: PackedFloat32Array) -> bool:
	var p := find(id)
	if p.is_empty():
		return false
	var d: PackedFloat32Array = p["data"]
	if not _fits(data.size(), d.size()):
		return false
	p["data"] = data
	return true


## Removes a primitive; its id is not reused.
func remove(id: int) -> void:
	var at := index_of(id)
	if at >= 0:
		prims.remove_at(at)


## Mutes or unmutes a primitive (flag bit 0).
func set_muted(id: int, muted: bool) -> void:
	var p := find(id)
	if not p.is_empty():
		p["flags"] = (int(p["flags"]) | MUTED) if muted else (int(p["flags"]) & ~MUTED)


## Moves a primitive to position `to` in the document order (clamped).
func move(id: int, to: int) -> void:
	var at := index_of(id)
	if at < 0:
		return
	var p := prims[at]
	prims.remove_at(at)
	prims.insert(clampi(to, 0, prims.size()), p)


## The primitive with `id`, or an empty Dictionary. The dictionary is the document's own.
func find(id: int) -> Dictionary:
	var at := index_of(id)
	return prims[at] if at >= 0 else {}


## The position of primitive `id` in the document order, or -1.
func index_of(id: int) -> int:
	for i in prims.size():
		if int(prims[i]["id"]) == id:
			return i
	return -1


## True when primitive `p` (a list entry) is muted.
static func is_muted(p: Dictionary) -> bool:
	return int(p.get("flags", 0)) & MUTED != 0


## Floats over every primitive.
func float_count() -> int:
	var total := 0
	for p in prims:
		total += (p["data"] as PackedFloat32Array).size()
	return total


## A copy-on-write copy (see the header): a later edit of either never reaches the other.
func duplicate() -> TerraDoc:
	var copy := TerraDoc.new()
	copy.next_id = next_id
	copy.derived = derived.duplicate(true)
	for p in prims:
		# Deep: a shallow duplicate would share the packed array, appends included (probed on
		# 4.7.2, MapDocumentSnapshot's header); a packed array's own duplicate() is the O(1) copy.
		copy.prims.append(p.duplicate(true))
	return copy


## The first rule of the section that this document breaks, or "": the caps, ids unique within
## 1..MAX_ID and below next_id, every kind registered, no reserved flag set and every
## primitive valid for its kind (TerraKinds.problem). A document that passes reads back the
## same, bit for bit.
func problem() -> String:
	if prims.size() > MapDocument.MAX_TERRA_PRIMS:
		return "terrain: %d primitives, over %d" % [prims.size(), MapDocument.MAX_TERRA_PRIMS]
	if next_id < 1 or next_id > MAX_ID + 1:
		return "terrain: next_id %d is out of range" % next_id
	var seen := {}
	var total := 0
	for p in prims:
		var id := int(p["id"])
		if id < 1 or id >= next_id or seen.has(id):
			return "terrain: primitive id %d is out of range or repeated" % id
		seen[id] = true
		if int(p["flags"]) & ~KNOWN_FLAGS != 0:
			return "terrain: primitive %d sets a reserved flag" % id
		var data: PackedFloat32Array = p["data"]
		total += data.size()
		if data.size() > MapDocument.MAX_TERRA_FLOATS_PER_PRIM:
			return "terrain: primitive %d holds %d floats, over its cap" % [id, data.size()]
		var reason := TerraKinds.problem(int(p["kind"]), data)
		if reason != "":
			return "terrain: primitive %d: %s" % [id, reason]
	if total > MapDocument.MAX_TERRA_FLOATS:
		return "terrain: %d floats, over %d" % [total, MapDocument.MAX_TERRA_FLOATS]
	return ""


## The digest of this document on a derive grid of `size` samples over `extent` metres (see
## the header), as 64 hex digits.
func digest(size: Vector2i, extent: Vector2) -> String:
	return _hash(MapTerrainIO.encode(self), size, extent, TerraCore.NATIVE_VERSION)


## The digest on the derive grid of map document `doc` (TerraCore.grid_for).
func digest_for(doc: MapDocument) -> String:
	var grid := TerraCore.grid_for(doc)
	return digest(grid["size"], grid["extent"])


## The derived record's key (see the header): digest() with next_id as 0, for core `version`
## (the running core's by default; a test passes another to stand for an older build).
func derive_key(size: Vector2i, extent: Vector2, version := TerraCore.NATIVE_VERSION) -> String:
	return _hash(MapTerrainIO.encode(self, false), size, extent, version)


## The derived record's key on the derive grid of map document `doc`.
func derive_key_for(doc: MapDocument) -> String:
	var grid := TerraCore.grid_for(doc)
	return derive_key(grid["size"], grid["extent"])


## SHA-256 over the section bytes, the grid (u32 samples per axis, the steps as float64 bits)
## and the core version, as 64 hex digits.
static func _hash(
	bytes: PackedByteArray, size: Vector2i, extent: Vector2, version: String
) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	ctx.update(grid_bytes(size, extent))
	ctx.update(version.to_utf8_buffer())
	return ctx.finish().hex_encode()


## The 24 bytes a digest and the derived record hold for a derive grid of `size` samples over
## `extent` metres: u32 samples per axis, then extent / (n - 1) per axis as float64. Pure.
static func grid_bytes(size: Vector2i, extent: Vector2) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(24)
	grid.encode_u32(0, size.x)
	grid.encode_u32(4, size.y)
	grid.encode_double(8, float(extent.x) / float(maxi(size.x - 1, 1)))
	grid.encode_double(16, float(extent.y) / float(maxi(size.y - 1, 1)))
	return grid


## True when a primitive of `floats` floats, replacing one of `old` floats, stays within the
## per-primitive and the document's float caps.
func _fits(floats: int, old: int) -> bool:
	if floats > MapDocument.MAX_TERRA_FLOATS_PER_PRIM:
		return false
	return float_count() - old + floats <= MapDocument.MAX_TERRA_FLOATS
