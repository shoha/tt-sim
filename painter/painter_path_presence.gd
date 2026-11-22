class_name PainterPathPresence
extends RefCounted

## Which painted surfaces of a map document are painted anywhere, kept up to date without a pass
## over every sample (card painter-wall-path): PainterGroundPaths.bind needs the slot weight planes
## only when two or more path slots are painted; with one or none it binds `path_only` alone, and
## learning which slots those are cost a GDScript pass over every sample's four entries on every
## frame of a path stroke (42 ms at 320 ft).
##
## The model. `counts[j]` is the number of (sample, entry) pairs whose index byte is j and whose
## weight byte is above 0 (index bytes 0..255; an index past the document's slots counts but maps
## to no slot). update() compares the document's weights with its own copy of the last ones row by
## row (native slice compares), and in each row that differs finds the first and last differing
## byte of each plane by halving (more slice compares), then subtracts the old entries and adds the
## new ones over that span alone. A new document, a resize or a first call starts from an all-zero
## copy, so a map with little paint counts little. The answer equals the pass it replaces exactly:
## the same pairs counted, by any writer, since every byte that changed is in a span.

## A plane row shorter than this is scanned byte by byte rather than halved further.
const SCAN_BYTES := 32

## Painted pairs per index byte (256 entries).
var counts := PackedInt32Array()
## The weights the counts are of (a copy), and the document they belong to.
var _copy := PackedByteArray()
var _doc_id: int = 0
var _sx: int = 0
var _sz: int = 0


func _init() -> void:
	counts.resize(256)


## Brings the counts up to `doc`'s surface weights (MapDocument header: an index plane, then a
## weight plane, four bytes a sample each).
func update(doc: MapDocument) -> void:
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var weights := doc.surface_weights
	if weights.size() != sx * sz * MapDocument.SURFACE_BYTES:
		_reset(doc, sx, sz, 0)
		return
	if doc.get_instance_id() != _doc_id or sx != _sx or sz != _sz or _copy.size() != weights.size():
		_reset(doc, sx, sz, weights.size())
	if weights == _copy:
		return
	var n4 := sx * sz * MapDocument.SURFACE_CHANNELS
	var row := sx * MapDocument.SURFACE_CHANNELS
	for r in sz:
		var at := r * row
		var span := _span(weights, at, at + row)
		var weight_span := _span(weights, n4 + at, n4 + at + row)
		if span.x < 0 and weight_span.x < 0:
			continue
		var lo := at + row
		var hi := at - 1
		if span.x >= 0:
			lo = mini(lo, span.x)
			hi = maxi(hi, span.y)
		if weight_span.x >= 0:
			lo = mini(lo, weight_span.x - n4)
			hi = maxi(hi, weight_span.y - n4)
		# Whole samples: an entry's index and weight sit at the same offset in their planes.
		var first := lo - lo % MapDocument.SURFACE_CHANNELS
		var last := hi - hi % MapDocument.SURFACE_CHANNELS + MapDocument.SURFACE_CHANNELS
		_count(_copy, n4, first, last, -1)
		_count(weights, n4, first, last, 1)
	_copy = weights.duplicate()


## The slots of `ids` (PainterGroundPaths.slots) whose weight plane would hold any value
## (PainterGroundPaths._planes: the base surface's slot always, a painted surface's slot when
## any pair of its index is painted), in slot order. Call update() first.
func painted_slots(doc: MapDocument, ids: PackedStringArray) -> PackedInt32Array:
	var seen := PackedByteArray()
	seen.resize(ids.size())
	var base_slot := ids.find(doc.base_surface)
	if base_slot >= 0:
		seen[base_slot] = 1
	var has_surfaces := (
		doc.surface_weights.size()
		== doc.samples_x() * doc.samples_z() * MapDocument.SURFACE_BYTES
	)
	if has_surfaces:
		for j in doc.surface_ids.size():
			if j < counts.size() and counts[j] > 0:
				var k := ids.find(doc.surface_ids[j])
				if k >= 0:
					seen[k] = 1
	var out := PackedInt32Array()
	for k in seen.size():
		if seen[k] == 1:
			out.append(k)
	return out


func _reset(doc: MapDocument, sx: int, sz: int, size: int) -> void:
	_doc_id = doc.get_instance_id()
	_sx = sx
	_sz = sz
	counts.fill(0)
	_copy = PackedByteArray()
	_copy.resize(size)


## The first and last byte in [lo, hi) where `weights` and the copy differ, as Vector2i, or
## (-1, -1) where they are the same.
func _span(weights: PackedByteArray, lo: int, hi: int) -> Vector2i:
	if weights.slice(lo, hi) == _copy.slice(lo, hi):
		return Vector2i(-1, -1)
	# Invariant: [a, b) holds a difference; halve toward the first one, then toward the last.
	var a := lo
	var b := hi
	while b - a > SCAN_BYTES:
		var mid := (a + b) >> 1
		if weights.slice(a, mid) != _copy.slice(a, mid):
			b = mid
		else:
			a = mid
	var first := a
	while weights[first] == _copy[first]:
		first += 1
	a = first
	b = hi
	while b - a > SCAN_BYTES:
		var mid := (a + b) >> 1
		if weights.slice(mid, b) != _copy.slice(mid, b):
			a = mid
		else:
			b = mid
	var last := b - 1
	while weights[last] == _copy[last]:
		last -= 1
	return Vector2i(first, last)


## Adds `sign` to counts for every painted pair of `bytes` from index-plane byte `first` to `last`
## (exclusive; whole samples), whose weights sit `n4` bytes further on.
func _count(bytes: PackedByteArray, n4: int, first: int, last: int, sign: int) -> void:
	for i in range(first, last):
		if bytes[n4 + i] > 0:
			counts[bytes[i]] += sign
