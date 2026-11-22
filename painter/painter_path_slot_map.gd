class_name PainterPathSlotMap
extends RefCounted

## The path slot map (PainterGroundPaths.slot_image) kept up to date over the rows that changed
## (card painter-path-many): with two or more path surfaces painted, a path stroke's frame paid a
## GDScript pass over every sample for the slot weight planes, then their blur and the largest slot
## of each texel (about 42 ms at 320 ft), every frame.
##
## The model. It keeps what slot_image() builds on the way: each slot's weight plane
## (PainterGroundPaths._planes), its horizontal blur pass and its blurred plane
## (PainterFieldBlur.box at radius 1, the zone blur), and the slot bytes; one flat float array
## per stage, a slot's plane at slot * samples. A sample's planes depend on that sample's four
## entries alone, a blurred texel on the 3 x 3 samples about it, and a slot byte on the blurred
## texels under it, so the rows an update
## changed (PainterPathPresence.row_spans, sample spans) redo only: the planes over the spans, the
## horizontal pass over each span grown one sample, the vertical pass and the bytes over those grown
## spans one row up and down. Each value is computed by the same expression in the same order as the
## full pass, so the bytes are the full pass's, bit for bit.
##
## It starts from all-zero weights (every plane 0 but the base surface's, 1 where nothing is
## painted, so its blur is 1 and its byte the base slot), then applies the spans from zero: a map's
## first frame with two painted path slots costs its painted rows, not its grid. A changed slot
## list keeps the planes when no painted entry changes slot (a new surface appended: a new path's
## first dab), else it starts again from zero. It holds only while it saw every presence update
## (`_synced`); PainterGroundPaths.bind drops it (invalidate) whenever it binds without it.
##
## It is kept in step before it is needed too (follow(), card painter-path-first): with fewer than
## two slots painted, a bind binds no slot map, but the planes still take each update's spans, and
## on a map with no path painted they start at no cost (all 0). The second surface's first dab then
## costs its spans like any other dab, where it built every plane whole in its own frame.

## The value of a byte where no path lies (PainterGroundPaths.NONE).
const NONE := 255
## A start from zero whose painted spans cover more than 1 / WHOLE_SHARE of the samples builds
## the planes whole instead (_build_whole: the full pass's planes, then each stage over the grid):
## a span's sample costs several times a whole pass's (measured: about 500 ms on a broadly painted
## 320 ft map from spans).
const WHOLE_SHARE := 8

## How many times it started from zero, and how many of those were built whole (tests, probes).
var starts: int = 0
var whole_builds: int = 0
var _valid := false
var _synced: int = -1
var _doc_id: int = 0
var _sx: int = 0
var _sz: int = 0
var _n: int = 0
var _slots: int = 0
var _slot_of := PackedInt32Array()
var _base_slot: int = -1
## Weight planes, horizontal passes and blurred planes, slot * _n + sample.
var _plane := PackedFloat32Array()
var _tmp := PackedFloat32Array()
var _blur := PackedFloat32Array()
var _bytes := PackedByteArray()
## A sample's new plane values (a slot each), and the slots whose plane an update changed.
var _vals := PackedFloat64Array()
var _dirty := PackedByteArray()


## Whether the region form holds for `doc`: the radius-1 zone blur on a grid at least 2 x 2 (the
## three-tap form of PainterFieldBlur.box).
static func supports(doc: MapDocument) -> bool:
	return PainterSurfaces.ZONE_BLUR == 1 and doc.samples_x() >= 2 and doc.samples_z() >= 2


## Drops the kept planes (the next texture() starts from zero).
func invalidate() -> void:
	_valid = false
	_plane = PackedFloat32Array()
	_tmp = PackedFloat32Array()
	_blur = PackedFloat32Array()


## Whether the kept planes are those of `presence`'s weights before its next update, for the slots
## `ids` of `doc`: the same document and grid, every update seen, and no entry painted in those
## weights (presence.counts) that changes slot. Call before presence.update(); adopts the new list.
func keeps(doc: MapDocument, ids: PackedStringArray, presence: PainterPathPresence) -> bool:
	if not _valid or _synced != presence.updates or doc.get_instance_id() != _doc_id:
		return false
	if doc.samples_x() != _sx or doc.samples_z() != _sz:
		return false
	var slot_of := _slot_list(doc, ids)
	if ids.find(doc.base_surface) != _base_slot:
		return false
	for j in maxi(slot_of.size(), _slot_of.size()):
		var was := _slot_of[j] if j < _slot_of.size() else -1
		var now := slot_of[j] if j < slot_of.size() else -1
		if was != now and j < presence.counts.size() and presence.counts[j] > 0:
			return false
	_slot_of = slot_of
	_grow(ids.size())
	return true


## The slot map of `doc` for slots `ids` after `presence.update()` returned `spans`, with `kept`
## (keeps(), asked before that update): the spans applied to the kept planes, or every painted row
## applied from zero. The same bytes as PainterGroundPaths.slot_image(); the caller has checked
## that two or more slots are painted and supports().
func texture(
	doc: MapDocument,
	ids: PackedStringArray,
	presence: PainterPathPresence,
	spans: PackedInt32Array,
	kept: bool
) -> ImageTexture:
	var weights := doc.surface_weights
	if not kept:
		_start(doc, ids)
		var zero := PackedByteArray()
		zero.resize(weights.size())
		spans = PainterPathPresence.row_spans(weights, zero, _sx, _sz)
		var covered := 0
		for s in range(0, spans.size(), 3):
			covered += (spans[s + 2] - spans[s + 1]) / MapDocument.SURFACE_CHANNELS
		if covered * WHOLE_SHARE > _n:
			# Paint over much of the grid: one whole pass costs less than the spans would.
			_build_whole(doc, ids)
			spans = PackedInt32Array()
	_apply(weights, spans)
	_synced = presence.updates
	# A new texture a call, as the full pass makes: one upload of an R8 image.
	return ImageTexture.create_from_image(
		Image.create_from_data(_sx, _sz, false, Image.FORMAT_R8, _bytes)
	)


## Keeps the planes in step through a bind that needs no slot map, `painted` (presence
## .painted_slots) holding fewer than two slots, with the arguments texture() takes (card
## painter-path-first): kept planes take the spans; with no slot painted at all (the base no
## path) the planes start where they are, all 0 and every byte NONE whatever else is painted, at no
## cost; else they are dropped. So a map whose first path is painted in this session holds its
## planes when the second surface's first dab needs them, where that frame built them whole (about
## 105 ms at 320 ft). True when the planes are in step after the call.
func follow(
	doc: MapDocument,
	ids: PackedStringArray,
	presence: PainterPathPresence,
	spans: PackedInt32Array,
	kept: bool,
	painted: PackedInt32Array
) -> bool:
	if kept:
		_apply(doc.surface_weights, spans)
	elif painted.is_empty():
		_start(doc, ids)
	else:
		invalidate()
		return false
	_synced = presence.updates
	return true


## The slot of each of `doc`'s painted surface indices in `ids` (-1 for none).
static func _slot_list(doc: MapDocument, ids: PackedStringArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id in doc.surface_ids:
		out.append(ids.find(id))
	return out


## The all-zero state of `doc`'s grid for slots `ids`.
func _start(doc: MapDocument, ids: PackedStringArray) -> void:
	starts += 1
	_valid = true
	_doc_id = doc.get_instance_id()
	_sx = doc.samples_x()
	_sz = doc.samples_z()
	_n = _sx * _sz
	_slot_of = _slot_list(doc, ids)
	_base_slot = ids.find(doc.base_surface)
	_slots = 0
	_plane = PackedFloat32Array()
	_tmp = PackedFloat32Array()
	_blur = PackedFloat32Array()
	_grow(ids.size())
	if _base_slot >= 0:
		_plane = _filled(_slots, _base_slot)
		_tmp = _filled(_slots, _base_slot)
		_blur = _filled(_slots, _base_slot)
	_bytes.resize(_n)
	_bytes.fill(_base_slot if _base_slot >= 0 else NONE)


## Every stage over the whole grid: the planes the full pass makes (PainterGroundPaths._planes),
## then the blur of each painted one and the bytes. Call after _start().
func _build_whole(doc: MapDocument, ids: PackedStringArray) -> void:
	whole_builds += 1
	var planes := PainterGroundPaths._planes(doc, ids)
	var flat := PackedFloat32Array()
	var zero := PackedFloat32Array()
	zero.resize(_n)
	for k in _slots:
		var painted := k < planes.size() and not planes[k].is_empty()
		flat.append_array(planes[k] if painted else zero)
	_plane = flat
	for k in _slots:
		if k < planes.size() and not planes[k].is_empty():
			for r in _sz:
				_pass_x(k * _n, r, 0, _sx - 1)
			for r in _sz:
				_pass_y(k * _n, r, 0, _sx - 1)
	for r in _sz:
		_pick(r, 0, _sx - 1)


## `slots` planes, all 0 but plane `k`, all 1.
func _filled(slots: int, k: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(k * _n)
	var one := PackedFloat32Array()
	one.resize(_n)
	one.fill(1.0)
	out.append_array(one)
	out.resize(slots * _n)
	return out


## Room for `slots` slots (new planes all 0, as a slot painted nowhere has).
func _grow(slots: int) -> void:
	if slots > _slots:
		_slots = slots
		_plane.resize(_slots * _n)
		_tmp.resize(_slots * _n)
		_blur.resize(_slots * _n)
	_vals.resize(_slots)
	_dirty.resize(_slots)


## Redoes the planes, the blur and the bytes over `spans` (row, first and end index-plane byte).
func _apply(weights: PackedByteArray, spans: PackedInt32Array) -> void:
	# No slot: no planes, and every byte stays NONE.
	if spans.is_empty() or _slots == 0:
		return
	var n4 := _n * MapDocument.SURFACE_CHANNELS
	_dirty.fill(0)
	# The planes over the spans; the rows' grown column ranges for the blur.
	var lo := PackedInt32Array()
	lo.resize(_sz)
	lo.fill(_sx)
	var hi := PackedInt32Array()
	hi.resize(_sz)
	hi.fill(-1)
	var row_lo := _sz
	var row_hi := -1
	for s in range(0, spans.size(), 3):
		var r := spans[s]
		var base := r * _sx * MapDocument.SURFACE_CHANNELS
		var c0 := (spans[s + 1] - base) / MapDocument.SURFACE_CHANNELS
		var c1 := (spans[s + 2] - base) / MapDocument.SURFACE_CHANNELS
		for c in range(c0, c1):
			_sample(weights, n4, r * _sx + c)
		lo[r] = maxi(c0 - 1, 0)
		hi[r] = mini(c1, _sx - 1)
		row_lo = mini(row_lo, r)
		row_hi = maxi(row_hi, r)
	for k in _slots:
		if _dirty[k] == 1:
			for r in range(row_lo, row_hi + 1):
				if hi[r] >= 0:
					_pass_x(k * _n, r, lo[r], hi[r])
	# The vertical pass and the bytes: each changed row's range, one row up and down.
	var out_lo := PackedInt32Array()
	out_lo.resize(_sz)
	out_lo.fill(_sx)
	var out_hi := PackedInt32Array()
	out_hi.resize(_sz)
	out_hi.fill(-1)
	for r in range(row_lo, row_hi + 1):
		if hi[r] < 0:
			continue
		for rr in range(maxi(r - 1, 0), mini(r + 1, _sz - 1) + 1):
			out_lo[rr] = mini(out_lo[rr], lo[r])
			out_hi[rr] = maxi(out_hi[rr], hi[r])
	var first := maxi(row_lo - 1, 0)
	var last := mini(row_hi + 1, _sz - 1)
	for k in _slots:
		if _dirty[k] == 1:
			for r in range(first, last + 1):
				if out_hi[r] >= 0:
					_pass_y(k * _n, r, out_lo[r], out_hi[r])
	for r in range(first, last + 1):
		if out_hi[r] >= 0:
			_pick(r, out_lo[r], out_hi[r])


## Sample `i`'s planes, as PainterGroundPaths._planes sets them: a painted surface's largest weight
## at its slot, the base surface's share left under the paint at its slot.
func _sample(weights: PackedByteArray, n4: int, i: int) -> void:
	_vals.fill(0.0)
	var painted := 0.0
	for e in 4:
		var w := weights[n4 + i * 4 + e] / 255.0
		if w <= 0.0:
			continue
		painted += w
		var at := weights[i * 4 + e]
		var k := _slot_of[at] if at < _slot_of.size() else -1
		if k < 0:
			continue
		_vals[k] = maxf(_vals[k], w)
	if _base_slot >= 0:
		_vals[_base_slot] = maxf(0.0, 1.0 - painted)
	for k in _slots:
		var at := k * _n + i
		var old := _plane[at]
		_plane[at] = _vals[k]
		if _plane[at] != old:
			_dirty[k] = 1


## The horizontal pass of the plane at `off` over row `r`, columns `x0` to `x1`
## (PainterFieldBlur.box).
func _pass_x(off: int, r: int, x0: int, x1: int) -> void:
	var row := off + r * _sx
	for x in range(x0, x1 + 1):
		var i := row + x
		if x == 0:
			_tmp[i] = (_plane[row] * 2.0 + _plane[row + 1]) / 3.0
		elif x == _sx - 1:
			_tmp[i] = (_plane[row + _sx - 2] + _plane[row + _sx - 1] * 2.0) / 3.0
		else:
			_tmp[i] = (_plane[i - 1] + _plane[i] + _plane[i + 1]) / 3.0


## The vertical pass of the plane at `off` over row `r`, columns `x0` to `x1`
## (PainterFieldBlur.box).
func _pass_y(off: int, r: int, x0: int, x1: int) -> void:
	var above := off + maxi(r - 1, 0) * _sx
	var here := off + r * _sx
	var below := off + mini(r + 1, _sz - 1) * _sx
	for x in range(x0, x1 + 1):
		_blur[here + x] = (_tmp[above + x] + _tmp[here + x] + _tmp[below + x]) / 3.0


## The slot bytes of row `r`, columns `x0` to `x1`: the slot whose blurred weight is largest
## (PainterGroundPaths._slot_image_of; a slot painted nowhere is all 0 and never wins).
func _pick(r: int, x0: int, x1: int) -> void:
	for x in range(x0, x1 + 1):
		var i := r * _sx + x
		var best := 0.004
		var slot := NONE
		for k in _slots:
			var v: float = _blur[k * _n + i]
			if v > best:
				best = v
				slot = k
		_bytes[i] = slot
