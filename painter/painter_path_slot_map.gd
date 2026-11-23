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
##
## The worker build (card painter-path-open). A map OPENED with one path surface painted has
## planes that nothing followed, and the second surface's first dab built them all in its frame
## (about 105 ms at 320 ft). So a follow() that finds no kept planes with paint under them starts
## that build on a WorkerThreadPool task (low priority: it runs behind the load's own work) over a
## snapshot of the document (copies of the arrays it reads), into a slot map of its own. The main
## thread never waits for it: a frame poll collects the task once it has completed, and the next
## bind's keeps() adopts its planes, after applying the rows any update changed since the
## snapshot, so they are the planes of the presence's weights, bit for bit. A follow() under
## another surface list, base or grid starts it again; a texture() that needs the planes before it
## lands builds them itself, as before; either lets the task go. A task let go before it completed
## (cancel(), the predelete) is waited for only once it has (_reap(), as PainterZoneMaps does).
const NONE := 255
## A start from zero whose painted spans cover more than 1 / WHOLE_SHARE of the samples builds
## the planes whole instead (_build_whole: the full pass's planes, then each stage over the grid):
## a span's sample costs several times a whole pass's (measured: about 500 ms on a broadly painted
## 320 ft map from spans).
const WHOLE_SHARE := 8

## The tasks let go of before they completed, waited for once each has (_reap()); process wide,
## since a slot map may be gone by then.
static var _abandoned := PackedInt64Array()

## How many times it started from zero, and how many of those were built whole (tests, probes);
## a worker build counts in both when it lands.
var starts: int = 0
var whole_builds: int = 0
## How many worker builds started, and how many of them were adopted (tests, probes).
var async_starts: int = 0
var async_lands: int = 0
## The worker build in flight (-1 for none), and its job: {"map" (the slot map it builds),
## "doc" (the snapshot), "ids", "key" (_key()), "updates" (the presence's at the snapshot),
## "done" (its task collected)}.
var _task: int = -1
var _job: Dictionary = {}
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


## Drops the kept planes (the next texture() starts from zero) and lets any worker build go.
func invalidate() -> void:
	cancel()
	_drop()


func _drop() -> void:
	_valid = false
	_plane = PackedFloat32Array()
	_tmp = PackedFloat32Array()
	_blur = PackedFloat32Array()


## Whether the kept planes are those of `presence`'s weights before its next update, for the slots
## `ids` of `doc`: the same document and grid, every update seen, and no entry painted in those
## weights (presence.counts) that changes slot. Call before presence.update(); adopts the new list,
## and first the worker build's planes when it has landed (_adopt()).
func keeps(doc: MapDocument, ids: PackedStringArray, presence: PainterPathPresence) -> bool:
	_adopt(doc, presence)
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
	if kept:
		_apply(doc.surface_weights, spans)
	else:
		# Needed now: a worker build that has not landed is let go, and the planes built here.
		cancel()
		_rebuild(doc, ids)
	_synced = presence.updates
	# A new texture a call, as the full pass makes: one upload of an R8 image.
	return ImageTexture.create_from_image(
		Image.create_from_data(_sx, _sz, false, Image.FORMAT_R8, _bytes)
	)


## Keeps the planes in step through a bind that needs no slot map, `painted` (presence
## .painted_slots) holding fewer than two slots, with the arguments texture() takes (card
## painter-path-first): kept planes take the spans; with no slot painted at all (the base no
## path) the planes start where they are, all 0 and every byte NONE whatever else is painted, at no
## cost; else (a map opened with a path painted) they are built on a worker (build_async(), card
## painter-path-open). So the second surface's first dab finds its planes kept, where that frame
## built them whole (about 105 ms at 320 ft). True when the planes are in step after the call.
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
		cancel()
		_start(doc, ids)
	else:
		_drop()
		build_async(doc, ids, presence)
		return false
	_synced = presence.updates
	return true


## The planes of `doc` for slots `ids` from zero, on this thread: every painted row's spans, or the
## whole grid's pass where the paint covers much of it.
func _rebuild(doc: MapDocument, ids: PackedStringArray) -> void:
	var weights := doc.surface_weights
	_start(doc, ids)
	var zero := PackedByteArray()
	zero.resize(weights.size())
	var spans := PainterPathPresence.row_spans(weights, zero, _sx, _sz)
	var covered := 0
	for s in range(0, spans.size(), 3):
		covered += (spans[s + 2] - spans[s + 1]) / MapDocument.SURFACE_CHANNELS
	if covered * WHOLE_SHARE > _n:
		# Paint over much of the grid: one whole pass costs less than the spans would.
		_build_whole(doc, ids)
		spans = PackedInt32Array()
	_apply(weights, spans)


# --- the worker build (the class header) -------------------------------------------------------


## Starts the planes of `doc` for slots `ids` on a worker, over a snapshot of `doc` as `presence`
## last saw it (call after presence.update()). A build in flight for the same surfaces, base and
## grid is kept (the rows that changed since are applied when it lands); any other is let go.
func build_async(doc: MapDocument, ids: PackedStringArray, presence: PainterPathPresence) -> void:
	var key := _key(doc, ids)
	if not _job.is_empty() and _job["key"] == key:
		return
	cancel()
	# Copies: a packed array is shared by assignment, so a kept reference would see, mid-read, an
	# edit made meanwhile (PainterZoneMaps._start).
	var snapshot := MapDocument.new()
	snapshot.size_cells = doc.size_cells
	snapshot.cell_size_m = doc.cell_size_m
	snapshot.sample_spacing_m = doc.sample_spacing_m
	snapshot.base_surface = doc.base_surface
	snapshot.surface_ids = doc.surface_ids.duplicate()
	snapshot.surface_weights = doc.surface_weights.duplicate()
	_job = {
		"map": PainterPathSlotMap.new(),
		"doc": snapshot,
		"ids": ids.duplicate(),
		"key": key,
		"updates": presence.updates,
		"done": false,
	}
	async_starts += 1
	# The script's static function, never a method of this object, which may be freed meanwhile (the
	# predelete lets the task go). Low priority: the load's own tasks go first.
	_task = WorkerThreadPool.add_task(
		PainterPathSlotMap._run.bind(_job), false, "PainterPathSlotMap.build_async"
	)
	_watch()


## Whether a worker build is in flight or waits to be adopted (tests, probes).
func building() -> bool:
	return not _job.is_empty()


## Lands the worker build now (tests, and a caller that needs the planes now): its result when the
## task has completed, else the same snapshot built on this thread (the task is let go, never
## waited for). The next keeps() adopts it. False when none is in flight.
func finish() -> bool:
	if _job.is_empty():
		return false
	if not _collect():
		# Into a slot map of its own: the task let go may still be writing the job's.
		var job := _job.duplicate()
		cancel()
		var built := PainterPathSlotMap.new()
		built._rebuild(job["doc"], job["ids"])
		job["map"] = built
		job["done"] = true
		_job = job
	return true


## Lets the worker build go without waiting for it; its task is reaped once it completes.
func cancel() -> void:
	if _task >= 0:
		_abandon(_task)
	_task = -1
	_job = {}
	_unwatch()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		_abandon(_task)
		_task = -1


## What a worker build is valid for: the document, its grid, its surface list and base, the slots.
static func _key(doc: MapDocument, ids: PackedStringArray) -> Array:
	return [
		doc.get_instance_id(),
		doc.samples_x(),
		doc.samples_z(),
		doc.base_surface,
		doc.surface_ids.duplicate(),
		ids.duplicate()
	]


## The worker's body: the planes of the job's snapshot, into the job's own slot map.
static func _run(job: Dictionary) -> void:
	(job["map"] as PainterPathSlotMap)._rebuild(job["doc"], job["ids"])


## Collects the worker build's task once it has completed (the wait returns at once); true when the
## job is done.
func _collect() -> bool:
	if _job.is_empty():
		return false
	if _task >= 0:
		if not WorkerThreadPool.is_task_completed(_task):
			return false
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_job["done"] = true
		_unwatch()
	return bool(_job["done"])


## Takes the landed worker build's planes when they still belong to `doc` as `presence` holds it:
## the rows any update changed since the snapshot applied on top (the presence's copy of the
## weights against the snapshot's), and every update counted seen. Before keeps()' own checks,
## which take a surface list changed for the coming update as they do for any kept planes: every
## update since the snapshot had the job's list, base and slots (a follow() under another key
## starts the build again, a texture() lets it go).
func _adopt(doc: MapDocument, presence: PainterPathPresence) -> void:
	if not _collect():
		return
	var job := _job
	_job = {}
	var built := job["map"] as PainterPathSlotMap
	var snapshot := job["doc"] as MapDocument
	var key: Array = job["key"]
	if key.slice(0, 3) != _key(doc, job["ids"]).slice(0, 3) or not presence.holds(doc):
		return
	var now := presence.last_weights()
	if now.size() != snapshot.surface_weights.size():
		return
	starts += built.starts
	whole_builds += built.whole_builds
	async_lands += 1
	_valid = true
	_doc_id = doc.get_instance_id()
	_sx = built._sx
	_sz = built._sz
	_n = built._n
	_slots = built._slots
	_slot_of = built._slot_of
	_base_slot = built._base_slot
	_plane = built._plane
	_tmp = built._tmp
	_blur = built._blur
	_bytes = built._bytes
	_vals = built._vals
	_dirty = built._dirty
	if presence.updates != int(job["updates"]):
		_apply(now, PainterPathPresence.row_spans(now, snapshot.surface_weights, _sx, _sz))
	_synced = presence.updates


func _watch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_on_frame):
		tree.process_frame.connect(_on_frame)


func _unwatch() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_on_frame):
		tree.process_frame.disconnect(_on_frame)


## A frame while the worker build runs: collects its task once it has completed, so no completed
## task waits for the next bind to be waited for.
func _on_frame() -> void:
	_collect()


## How many let-go tasks wait to be reaped (tests).
static func abandoned_count() -> int:
	return _abandoned.size()


static func _abandon(task: int) -> void:
	_abandoned.append(task)
	_reap()
	if _abandoned.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and not tree.process_frame.is_connected(_reap):
		tree.process_frame.connect(_reap)


## Waits for each let-go task that has completed (at once: it has), keeps the rest, and stops
## polling when none is left.
static func _reap() -> void:
	var left := PackedInt64Array()
	for task in _abandoned:
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
		else:
			left.append(task)
	_abandoned = left
	if not left.is_empty():
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.process_frame.is_connected(_reap):
		tree.process_frame.disconnect(_reap)


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
