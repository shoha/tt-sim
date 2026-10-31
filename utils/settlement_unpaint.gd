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
## A sample counts as full when its weights reach 255 less this (the scaling truncates).
const FULL_SLACK := 4


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
	var real_of: Array[int] = []
	for name in scratch.surface_ids:
		real_of.append(doc.surface_ids.find(name))
	var before := _capture(doc, strokes)
	var count := doc.sample_count()
	var width := doc.samples_x()
	var seen := PackedByteArray()
	seen.resize(count)
	for stroke in strokes:
		var rect := MaskBrush.capsule_rect(doc, stroke["from"], stroke["to"], stroke["radius"])
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var i := z * width + x
				if seen[i] == 0:
					seen[i] = 1
					_unpaint_sample(doc, scratch, real_of, i, count)
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
## its room back where the dressing's paint was intact on a full sample.
static func _unpaint_sample(
	doc: MapDocument, scratch: MapDocument, real_of: Array[int], i: int, count: int
) -> void:
	var laid := SurfaceEntries.read_sample(scratch.surface_weights, i, count)
	var laid_index: PackedInt32Array = laid[0]
	if laid_index.is_empty():
		return
	var laid_weight: PackedInt32Array = laid[1]
	var current := SurfaceEntries.read_sample(doc.surface_weights, i, count)
	var index: PackedInt32Array = current[0]
	var weight: PackedInt32Array = current[1]
	var owed := 0
	for k in laid_index.size():
		if real_of[laid_index[k]] >= 0:
			owed += laid_weight[k]
	var before_total := 0
	var removed := 0
	var laid_before := 0
	var laid_after := 0
	var mine := PackedInt32Array()
	for e in index.size():
		before_total += weight[e]
		var found := -1
		for k in laid_index.size():
			if real_of[laid_index[k]] == index[e]:
				found = k
		if found < 0:
			continue
		var left := maxi(weight[e] - laid_weight[found], 0)
		removed += weight[e] - left
		laid_before += weight[e]
		laid_after += left
		weight[e] = left
		mine.append(e)
	if removed == 0:
		return
	var others := before_total - laid_before
	if removed >= owed - FULL_SLACK and others > 0 and before_total >= 255 - FULL_SLACK:
		_give_room_back(weight, mine, laid_before, laid_after)
	SurfaceEntries.write_sample(doc.surface_weights, i, count, index, weight)


## Scales the weights of the entries not in `mine` up by the room the dressing's paint gave up
## (255 less what is laid now over 255 less what was laid), never past the room there is.
static func _give_room_back(
	weight: PackedInt32Array, mine: PackedInt32Array, laid_before: int, laid_after: int
) -> void:
	var room := 255 - laid_after
	var factor := float(room) / float(maxi(255 - laid_before, 1))
	var total := 0
	var largest := -1
	for e in weight.size():
		if mine.has(e):
			continue
		weight[e] = mini(roundi(weight[e] * factor), room)
		total += weight[e]
		if largest < 0 or weight[e] > weight[largest]:
			largest = e
	if total > room and largest >= 0:
		weight[largest] -= total - room


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
