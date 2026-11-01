class_name SettlementUnpaint
extends RefCounted

## Takes back the paint a Dress laid (villages3, docs/systems/settlements.md "Ground"), leaving
## the ground the author painted. The record keeps the strokes (`Settlement.ground`); this replays
## them, in order, on an empty scratch grid of the map's size through the very SurfaceStroke code
## that laid them, which gives the paint the Dress made on its own, per sample and per surface
## (what the strokes left, with the same rounding and the same scaling of later paint over
## earlier). Then, at each sample those strokes reach:
##
## - a surface the dressing laid loses that much weight (never below 0), so paint the author put
##   on the same surface keeps what is left over;
## - when the dressing's paint is intact there (the sample still holds all of it) and the sample was
##   full, the author's paint of other surfaces, which the dressing scaled down to make room, is
##   scaled back up by the room it gave (capped at what fits). A sample the dressing never reached,
##   or one the author painted over afterwards, is left as it is.
##
## The result is a SurfaceStroke diff (blocks of before and after bytes, the slot list before and
## after), applied to the document in place, so the removal records, undoes and reaches a live-edit
## peer as the ordinary `surface` edit (AuthoringEditor.apply_surface_diff). Limits: where two
## dressed streets cross on one surface, taking one back thins the other a little at the crossing;
## and where the author's own paint was squeezed to a sliver and a stroke then passed over it, the
## sliver is what comes back (the weight it had before is not recorded).

const BLOCK := MaskStroke.BLOCK
const COMPRESSION := SurfaceStroke.COMPRESSION
const CHANNELS := MapDocument.SURFACE_CHANNELS
const ENTRIES := MapDocument.SURFACE_ENTRIES
## A sample counts as full when its weights reach 255 less this (the scaling truncates).
const FULL_SLACK := 4
## The four quarters of the per-sample scratch buffer of _unpaint_sample, ENTRIES ints each.
const LAID_SLOT := 0
const LAID_WEIGHT := ENTRIES
const INDEX := ENTRIES * 2
const WEIGHT := ENTRIES * 3
const WORK_SIZE := ENTRIES * 4


## Removes the paint of `strokes` ({"surface", "from", "to", "radius", "seconds"} in paint order,
## SettlementGroundIO's form) from `doc` in place and returns the diff, or {} when nothing changed
## (no strokes, no paint, or the strokes' paint is already gone).
static func remove(doc: MapDocument, strokes: Array[Dictionary]) -> Dictionary:
	if strokes.is_empty() or not doc.has_surface_entries():
		return {}
	var ids_before := doc.surface_ids.duplicate()
	var scratch := _replay(doc, strokes)
	if scratch.surface_weights.is_empty():
		return {}
	# Real slot of each scratch slot, -1 when the map no longer paints that surface.
	var real_of := PackedInt32Array()
	for name in scratch.surface_ids:
		real_of.append(doc.surface_ids.find(name))
	var before := _capture(doc, strokes)
	var count := doc.sample_count()
	var width := doc.samples_x()
	var seen := PackedByteArray()
	seen.resize(count)
	# The weight plane of the replay: a sample it left bare (most of a capsule's rectangle) has
	# nothing to take back.
	var laid := scratch.surface_weights
	var plane := count * CHANNELS
	# One scratch buffer for every sample's entries (see _unpaint_sample), so the walk allocates
	# nothing per sample (hitches2: the walk was about half of a take-back).
	var work := PackedInt32Array()
	work.resize(WORK_SIZE)
	for stroke in strokes:
		var rect := MaskBrush.capsule_rect(doc, stroke["from"], stroke["to"], stroke["radius"])
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var i := z * width + x
				if seen[i] == 0:
					seen[i] = 1
					var at := plane + i * CHANNELS
					if laid[at] != 0 or laid[at + 1] != 0 or laid[at + 2] != 0 or laid[at + 3] != 0:
						_unpaint_sample(doc.surface_weights, laid, real_of, i, count, work)
	return _finish(doc, before, ids_before)


## The strokes painted alone on a grid like `doc`'s: a document whose painted surfaces are what
## the dressing left, its slots named by surface.
static func _replay(doc: MapDocument, strokes: Array[Dictionary]) -> MapDocument:
	var scratch := MapDocument.new()
	scratch.size_cells = doc.size_cells
	scratch.cell_size_m = doc.cell_size_m
	scratch.sample_spacing_m = doc.sample_spacing_m
	var run: SurfaceStroke = null
	var surface := ""
	for stroke in strokes:
		if run == null or str(stroke["surface"]) != surface:
			surface = str(stroke["surface"])
			run = SurfaceStroke.begin(scratch, surface, false)
		if run != null:
			run.dab(stroke["from"], stroke["to"], stroke["radius"], stroke["seconds"])
	return scratch


## One sample: lowers the weights of the surfaces the dressing laid, and gives the author's paint
## its room back where the dressing's paint was intact on a full sample. Reads `laid` (the replay's
## weights) and edits `planes` (the document's) in place, with SurfaceEntries' rules spelt out: the
## entries that carry weight, high to low with ties in entry order, written back in that canonical
## order. `work` (WORK_SIZE ints, reused by every sample) holds the replay's
## entries as real slots and weights, then the sample's own indices and weights; nothing is
## allocated per sample.
static func _unpaint_sample(
	planes: PackedByteArray,
	laid: PackedByteArray,
	real_of: PackedInt32Array,
	i: int,
	count: int,
	work: PackedInt32Array
) -> void:
	var at := i * CHANNELS
	var weight_at := count * CHANNELS + at
	# The dressing's entries (in any order: a slot appears once) and what it owes the map's slots.
	var laid_n := 0
	var owed := 0
	for e in ENTRIES:
		var lw := laid[weight_at + e]
		if lw > 0:
			var real := real_of[laid[at + e]]
			work[LAID_SLOT + laid_n] = real
			work[LAID_WEIGHT + laid_n] = lw
			laid_n += 1
			if real >= 0:
				owed += lw
	if laid_n == 0:
		return
	# The sample's entries that carry weight, high to low, ties in entry order (read_sample).
	var n := 0
	for e in ENTRIES:
		var w := planes[weight_at + e]
		if w > 0:
			var k := n - 1
			while k >= 0 and work[WEIGHT + k] < w:
				work[WEIGHT + k + 1] = work[WEIGHT + k]
				work[INDEX + k + 1] = work[INDEX + k]
				k -= 1
			work[WEIGHT + k + 1] = w
			work[INDEX + k + 1] = planes[at + e]
			n += 1
	var before_total := 0
	var removed := 0
	var laid_before := 0
	var laid_after := 0
	var mine := 0
	for e in n:
		var w := work[WEIGHT + e]
		before_total += w
		var found := -1
		for k in laid_n:
			if work[LAID_SLOT + k] == work[INDEX + e]:
				found = k
		if found < 0:
			continue
		var left := maxi(w - work[LAID_WEIGHT + found], 0)
		removed += w - left
		laid_before += w
		laid_after += left
		work[WEIGHT + e] = left
		mine |= 1 << e
	if removed == 0:
		return
	var others := before_total - laid_before
	if removed >= owed - FULL_SLACK and others > 0 and before_total >= 255 - FULL_SLACK:
		_give_room_back(work, n, mine, laid_before, laid_after)
	# Write back (write_sample): the entries left with weight, high to low, ties in their order,
	# then unused (0, 0). The laid half of `work` is free now and holds the sorted result.
	var kept := 0
	for e in n:
		var w := mini(work[WEIGHT + e], 255)
		if w <= 0:
			continue
		var k := kept - 1
		while k >= 0 and work[LAID_WEIGHT + k] < w:
			work[LAID_WEIGHT + k + 1] = work[LAID_WEIGHT + k]
			work[LAID_SLOT + k + 1] = work[LAID_SLOT + k]
			k -= 1
		work[LAID_WEIGHT + k + 1] = w
		work[LAID_SLOT + k + 1] = work[INDEX + e]
		kept += 1
	for e in ENTRIES:
		planes[at + e] = work[LAID_SLOT + e] if e < kept else 0
		planes[weight_at + e] = work[LAID_WEIGHT + e] if e < kept else 0


## Scales the weights of the sample's `n` entries in `work` that are not in `mine` (a bit per
## entry) up by the room the dressing's paint gave up (255 less what is laid now over 255 less what
## was laid), never past the room there is.
static func _give_room_back(
	work: PackedInt32Array, n: int, mine: int, laid_before: int, laid_after: int
) -> void:
	var room := 255 - laid_after
	var factor := float(room) / float(maxi(255 - laid_before, 1))
	var total := 0
	var largest := -1
	for e in n:
		if mine & (1 << e) != 0:
			continue
		var w := mini(roundi(work[WEIGHT + e] * factor), room)
		work[WEIGHT + e] = w
		total += w
		if largest < 0 or w > work[WEIGHT + largest]:
			largest = e
	if total > room and largest >= 0:
		work[WEIGHT + largest] -= total - room


## The sample blocks `strokes` reach, as {block: {"rect", "bytes"}} before any change.
static func _capture(doc: MapDocument, strokes: Array[Dictionary]) -> Dictionary:
	var out := {}
	for stroke in strokes:
		var rect := MaskBrush.capsule_rect(doc, stroke["from"], stroke["to"], stroke["radius"])
		if not rect.has_area():
			continue
		@warning_ignore("integer_division")
		var first := Vector2i(rect.position.x / BLOCK, rect.position.y / BLOCK)
		@warning_ignore("integer_division")
		var last := Vector2i((rect.end.x - 1) / BLOCK, (rect.end.y - 1) / BLOCK)
		for bz in range(first.y, last.y + 1):
			for bx in range(first.x, last.x + 1):
				var block := Vector2i(bx, bz)
				if out.has(block):
					continue
				var area := MaskStroke.block_rect(doc, block)
				out[block] = {"rect": area, "bytes": SurfaceStroke.read_block(doc, doc.surface_weights, area)}
	return out


## The diff of the blocks that changed (SurfaceStroke.finish()'s form), after dropping trailing
## slots left without paint; {} when no block changed.
static func _finish(
	doc: MapDocument, before: Dictionary, ids_before: PackedStringArray
) -> Dictionary:
	var blocks: Array[Dictionary] = []
	var whole := Rect2i()
	var total := 0
	for block: Vector2i in before:
		var rect: Rect2i = before[block]["rect"]
		var old: PackedByteArray = before[block]["bytes"]
		var now := SurfaceStroke.read_block(doc, doc.surface_weights, rect)
		if now == old:
			continue
		var packed_before := old.compress(COMPRESSION)
		var packed_after := now.compress(COMPRESSION)
		total += packed_before.size() + packed_after.size()
		blocks.append({"rect": rect, "before": packed_before, "after": packed_after})
		whole = MaskBrush.merge_rect(whole, rect)
	if blocks.is_empty():
		return {}
	var trimmed := doc.surface_ids.duplicate()
	doc.surface_ids = trimmed
	doc.trim_unused_surfaces()
	return {
		"blocks": blocks,
		"ids_before": ids_before,
		"ids_after": doc.surface_ids.duplicate(),
		"had_before": true,
		"has_after": not doc.surface_weights.is_empty(),
		"rect": whole,
		"bytes": total,
	}
