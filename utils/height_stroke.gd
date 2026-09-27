class_name HeightStroke
extends RefCounted

## One sculpt stroke on a MapDocument's heights: applies a HeightBrush operation over the
## capsule each frame's brush swept, in place, and records what it changed so the stroke can
## be undone, redone or cancelled. The height counterpart of MaskStroke, with the same shape:
## begin(), dab(), take_pending(), finish(), revert(), apply_diff().
##
## Stroke start. begin() keeps a copy of the whole height grid as it was (start_heights;
## 4 bytes per sample, 240 KB and about 0.05 ms for a 200 ft map). It is what the "before"
## side of the diff is cut from (every 40 x 40 block the stroke writes, before its first
## write), and what AuthoringEditor snaps plants and props against: a row's ground at the
## start of the stroke against its ground now.
##
## Changed rectangles. Every dab grows `pending` by the samples whose height actually
## changed; the owner takes it once per frame (take_pending()) to update the terrain,
## collision and plants, so all dabs of a frame make one update.
##
## Tiers (TIER, TIER_CUT). Every dab raises each sample's inset (how far inside the ring
## grown by HeightBrush.TIER_SOFTEN_M the stroke has reached it, metres: the soft profile's
## toe starts that far outside the ring; `_reach`, the largest over the stroke) and moves the
## sample toward HeightBrush.tier_goal() of its start height, the target and that inset
## (computed only when the inset grows and kept in `_aim`, since the soft profile costs a
## few function calls; test_tier_stroke_matches_tier_goal holds them together).
## TIER only raises samples that began below the target and TIER_CUT only cuts samples that
## began above it. complete() puts every reached sample exactly on its goal; the owner calls
## it when the stroke ends, so a quick stroke still leaves a finished tier.
##
## Diffs. finish() pairs the start and final floats of every touched block and compresses
## both (ZSTD over the float bytes; sculpted ground is smooth and compresses well), so
## history holds only the touched blocks. apply_diff() writes either side back.

## Diff block edge in samples (10 m at the default 0.25 m spacing), as MaskStroke.
const BLOCK := 40
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
## Weight steps of the per-dab amount table (see _amount_table).
const AMOUNT_STEPS := 256

var doc: MapDocument = null
## HeightBrush operation.
var op: int = HeightBrush.RAISE
## Goal height (document metres) of FLATTEN and TIER.
var target: float = 0.0
## The heights when the stroke began. Do not modify.
var start_heights: PackedFloat32Array = PackedFloat32Array()
## Samples changed since the last take_pending().
var pending: Rect2i = Rect2i()
## Samples changed during the whole stroke.
var changed: Rect2i = Rect2i()
## Lowest and highest height the stroke has written (Vector2(INF, -INF) before any).
var written_span: Vector2 = Vector2(INF, -INF)

## Per block: 1 once the stroke has written a sample in it.
var _touched := PackedByteArray()
var _blocks_x: int = 0
## Tier strokes: per sample, the inset the stroke has reached (0: not reached), and the
## rectangle of samples reached.
var _reach := PackedFloat32Array()
var _reach_rect: Rect2i = Rect2i()
## Tier strokes: per reached sample, HeightBrush.tier_goal() of its start and `_reach`.
var _aim := PackedFloat32Array()


## Starts a stroke of HeightBrush operation `operation` on `document`; `goal` is the target
## height (document metres) of FLATTEN and TIER. Null when the document has no height grid.
static func begin(document: MapDocument, operation: int, goal: float = 0.0) -> HeightStroke:
	if document.heights.size() != document.sample_count():
		return null
	var stroke := HeightStroke.new()
	stroke.doc = document
	stroke.op = operation
	stroke.target = HeightBrush.clamp_height(goal)
	stroke.start_heights = document.heights.duplicate()
	stroke._blocks_x = ceili(float(document.samples_x()) / BLOCK)
	stroke._touched.resize(stroke._blocks_x * ceili(float(document.samples_z()) / BLOCK))
	if HeightBrush.is_tier(operation):
		stroke._reach.resize(document.sample_count())
		stroke._reach.fill(0.0)
		stroke._aim.resize(document.sample_count())
	return stroke


## Applies `seconds` of exposure along the capsule of `radius` around `from`-`to`
## (document-local XZ metres), each sample weighted by the operation's profile of its
## distance to the segment. Returns true when any height changed.
@warning_ignore("integer_division")
func dab(from: Vector2, to: Vector2, radius: float, seconds: float) -> bool:
	if radius <= 0.0 or seconds <= 0.0:
		return false
	if HeightBrush.is_tier(op):
		# The soft profile's toe starts TIER_SOFTEN_M outside the ring, so the face stands
		# where the sharp one did: centred a face's half-width inside the ring's edge.
		var outer := radius + HeightBrush.TIER_SOFTEN_M
		var tier_rect := MaskBrush.capsule_rect(doc, from, to, outer)
		if not tier_rect.has_area():
			return false
		return _tier_dab(tier_rect, from, to, outer, seconds)
	var rect := MaskBrush.capsule_rect(doc, from, to, radius)
	if not rect.has_area():
		return false
	var width := doc.samples_x()
	var step := doc.sample_step()
	var means := PackedFloat32Array()
	if op == HeightBrush.SMOOTH:
		# Means from the heights before this dab, so the result does not depend on the
		# order samples are visited in.
		var k := HeightBrush.smooth_kernel(radius, maxf(step.x, step.y))
		means = HeightBrush.box_mean(doc.heights, width, doc.samples_z(), rect, k)
	var steps := _amount_table(seconds)
	var linear := op == HeightBrush.RAISE or op == HeightBrush.LOWER
	var metres := (
		HeightBrush.raise_speed(radius) * seconds * (-1.0 if op == HeightBrush.LOWER else 1.0)
	)
	var goal := target
	var limit := MapDocument.MAX_ABS_HEIGHT_M
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	var heights := doc.heights
	var touched := _touched
	var blocks_x := _blocks_x
	var lut_top := float(AMOUNT_STEPS - 1)
	var low := Vector2i(rect.end)
	var high := Vector2i(-1, -1)
	var lowest := INF
	var highest := -INF
	# Everything per sample is inlined, as in MaskStroke: a call per sample doubles the cost.
	for z in range(rect.position.y, rect.end.y):
		var pz := origin.y + z * step.y - from.y
		var row := z * width
		var mean_row := (z - rect.position.y) * rect.size.x - rect.position.x
		for x in range(rect.position.x, rect.end.x):
			var px := origin.x + x * step.x - from.x
			var along := 0.0
			if length_sq > 0.0:
				along = clampf((px * segment.x + pz * segment.y) / length_sq, 0.0, 1.0)
			var dx := px - segment.x * along
			var dz := pz - segment.y * along
			var t_sq := (dx * dx + dz * dz) / radius_sq
			if t_sq >= 1.0:
				continue
			var w := (1.0 - t_sq) * (1.0 - t_sq)
			if w <= 0.0:
				continue
			var i := row + x
			var old := heights[i]
			var value := old
			if linear:
				value = old + metres * w
			else:
				var a: float = steps[int(w * lut_top)]
				var aim := means[mean_row + x] if means.size() > 0 else goal
				value = old + (aim - old) * a
			value = clampf(value, -limit, limit)
			if value == old:
				continue
			touched[(z / BLOCK) * blocks_x + x / BLOCK] = 1
			heights[i] = value
			low = low.min(Vector2i(x, z))
			high = high.max(Vector2i(x, z))
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	if high.x < 0:
		return false
	written_span = Vector2(minf(written_span.x, lowest), maxf(written_span.y, highest))
	var dirty := Rect2i(low, high - low + Vector2i.ONE)
	pending = MaskBrush.merge_rect(pending, dirty)
	changed = MaskBrush.merge_rect(changed, dirty)
	return true


## A tier dab over `rect`: raises each sample's inset and moves it toward its goal (see the
## header), recomputing the goal only where the inset grew.
@warning_ignore("integer_division")
func _tier_dab(rect: Rect2i, from: Vector2, to: Vector2, radius: float, seconds: float) -> bool:
	var width := doc.samples_x()
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	var heights := doc.heights
	var starts := start_heights
	var reach := _reach
	var aims := _aim
	var touched := _touched
	var blocks_x := _blocks_x
	var goal := target
	var up := op == HeightBrush.TIER
	var a := MaskBrush.amount(1.0, seconds, HeightBrush.TIER_RATE)
	var snap := HeightBrush.TIER_SNAP_M
	var low := Vector2i(rect.end)
	var high := Vector2i(-1, -1)
	var lowest := INF
	var highest := -INF
	var reached := false
	for z in range(rect.position.y, rect.end.y):
		var pz := origin.y + z * step.y - from.y
		var row := z * width
		for x in range(rect.position.x, rect.end.x):
			var px := origin.x + x * step.x - from.x
			var along := 0.0
			if length_sq > 0.0:
				along = clampf((px * segment.x + pz * segment.y) / length_sq, 0.0, 1.0)
			var dx := px - segment.x * along
			var dz := pz - segment.y * along
			var d_sq := dx * dx + dz * dz
			if d_sq >= radius_sq:
				continue
			var i := row + x
			var start := starts[i]
			if (up and start >= goal) or (not up and start <= goal):
				continue
			var now := radius - sqrt(d_sq)
			if now > reach[i]:
				reach[i] = now
				reached = true
				# The inset read back as stored (float32), so complete() computes the same goal.
				aims[i] = HeightBrush.tier_goal(start, goal, reach[i])
			var aim := aims[i]
			var old := heights[i]
			var value := old + (aim - old) * a
			if absf(aim - value) <= snap:
				value = aim
			if value == old:
				continue
			touched[(z / BLOCK) * blocks_x + x / BLOCK] = 1
			heights[i] = value
			low = low.min(Vector2i(x, z))
			high = high.max(Vector2i(x, z))
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	if reached:
		_reach_rect = MaskBrush.merge_rect(_reach_rect, rect)
	if high.x < 0:
		return false
	written_span = Vector2(minf(written_span.x, lowest), maxf(written_span.y, highest))
	var dirty := Rect2i(low, high - low + Vector2i.ONE)
	pending = MaskBrush.merge_rect(pending, dirty)
	changed = MaskBrush.merge_rect(changed, dirty)
	return true


## Tier strokes: puts every sample the stroke reached exactly on its goal (a no-op for the
## other operations, and for samples already there). Grows `pending` like a dab.
@warning_ignore("integer_division")
func complete() -> void:
	if not HeightBrush.is_tier(op) or not _reach_rect.has_area():
		return
	var width := doc.samples_x()
	var up := op == HeightBrush.TIER
	var low := Vector2i(_reach_rect.end)
	var high := Vector2i(-1, -1)
	var lowest := INF
	var highest := -INF
	for z in range(_reach_rect.position.y, _reach_rect.end.y):
		for x in range(_reach_rect.position.x, _reach_rect.end.x):
			var i := z * width + x
			if _reach[i] <= 0.0:
				continue
			var start := start_heights[i]
			if (up and start >= target) or (not up and start <= target):
				continue
			var aim := HeightBrush.tier_goal(start, target, _reach[i])
			if doc.heights[i] == aim:
				continue
			doc.heights[i] = aim
			_touched[(z / BLOCK) * _blocks_x + x / BLOCK] = 1
			low = low.min(Vector2i(x, z))
			high = high.max(Vector2i(x, z))
			lowest = minf(lowest, aim)
			highest = maxf(highest, aim)
	if high.x < 0:
		return
	written_span = Vector2(minf(written_span.x, lowest), maxf(written_span.y, highest))
	var dirty := Rect2i(low, high - low + Vector2i.ONE)
	pending = MaskBrush.merge_rect(pending, dirty)
	changed = MaskBrush.merge_rect(changed, dirty)


## Lowers every sample of `rect` (grid coordinates) to its goal in `goals` (row-major over
## the rect; INF leaves a sample alone) where the goal is below the sample's height, all at
## once: a one-shot carve (WaterCarve's channel and basin goals) recorded like a dab, so
## finish(), revert() and apply_diff() work unchanged. Never raises ground. Returns true
## when any height changed.
@warning_ignore("integer_division")
func lower_to(rect: Rect2i, goals: PackedFloat32Array) -> bool:
	var grid := Rect2i(0, 0, doc.samples_x(), doc.samples_z())
	if not rect.has_area() or goals.size() != rect.size.x * rect.size.y:
		return false
	var width := doc.samples_x()
	var heights := doc.heights
	var limit := MapDocument.MAX_ABS_HEIGHT_M
	var low := Vector2i(grid.end)
	var high := Vector2i(-1, -1)
	var lowest := INF
	var highest := -INF
	for j in rect.size.y:
		var z := rect.position.y + j
		if z < 0 or z >= grid.size.y:
			continue
		for i in rect.size.x:
			var x := rect.position.x + i
			if x < 0 or x >= grid.size.x:
				continue
			var goal := goals[j * rect.size.x + i]
			var at := z * width + x
			if is_inf(goal) or goal >= heights[at]:
				continue
			var value := maxf(goal, -limit)
			if value >= heights[at]:
				continue
			heights[at] = value
			_touched[(z / BLOCK) * _blocks_x + x / BLOCK] = 1
			low = low.min(Vector2i(x, z))
			high = high.max(Vector2i(x, z))
			lowest = minf(lowest, value)
			highest = maxf(highest, value)
	if high.x < 0:
		return false
	written_span = Vector2(minf(written_span.x, lowest), maxf(written_span.y, highest))
	var dirty := Rect2i(low, high - low + Vector2i.ONE)
	pending = MaskBrush.merge_rect(pending, dirty)
	changed = MaskBrush.merge_rect(changed, dirty)
	return true


## MaskBrush.amount() of this operation's rate for `seconds` at AMOUNT_STEPS evenly spaced
## weights, index 0 = weight 0 (empty for raise and lower, which are linear).
func _amount_table(seconds: float) -> PackedFloat32Array:
	var table := PackedFloat32Array()
	var rate := HeightBrush.rate(op)
	if rate <= 0.0:
		return table
	table.resize(AMOUNT_STEPS)
	for q in AMOUNT_STEPS:
		table[q] = MaskBrush.amount(float(q) / float(AMOUNT_STEPS - 1), seconds, rate)
	return table


## The rectangle changed since the last call (empty when nothing changed), then forgets it.
func take_pending() -> Rect2i:
	var rect := pending
	pending = Rect2i()
	return rect


## The height at sample index `i` when the stroke began.
func start_height(i: int) -> float:
	return start_heights[i]


## Ends the stroke: the diff history keeps, or {} when no height changed. A diff is
## {"blocks": Array of {"rect", "before": PackedByteArray, "after": PackedByteArray} (ZSTD
## float bytes), "rect": Rect2i (every block), "bytes": int}.
@warning_ignore("integer_division")
func finish() -> Dictionary:
	if not changed.has_area():
		return {}
	var blocks: Array[Dictionary] = []
	var whole := Rect2i()
	var total := 0
	var width := doc.samples_x()
	for index in _touched.size():
		if _touched[index] == 0:
			continue
		var block := Vector2i(index % _blocks_x, index / _blocks_x)
		var rect := MaskStroke.block_rect(doc, block)
		var old := read_block(start_heights, width, rect)
		var now := read_block(doc.heights, width, rect)
		if old == now:
			continue
		var before := old.to_byte_array().compress(COMPRESSION)
		var after := now.to_byte_array().compress(COMPRESSION)
		total += before.size() + after.size()
		blocks.append({"rect": rect, "before": before, "after": after})
		whole = MaskBrush.merge_rect(whole, rect)
	if blocks.is_empty():
		return {}
	return {"blocks": blocks, "rect": whole, "bytes": total}


## Puts every height the stroke wrote back (a cancelled stroke). Returns the sample
## rectangle to refresh.
@warning_ignore("integer_division")
func revert() -> Rect2i:
	var width := doc.samples_x()
	for index in _touched.size():
		if _touched[index] == 0:
			continue
		var rect := MaskStroke.block_rect(doc, Vector2i(index % _blocks_x, index / _blocks_x))
		write_block(doc.heights, width, rect, read_block(start_heights, width, rect))
	var rect := changed
	changed = Rect2i()
	pending = Rect2i()
	return rect


## Writes one side of a finish() diff into `document` (`redo` true: the stroke's result;
## false: the heights before it). Returns the sample rectangle it touched.
static func apply_diff(document: MapDocument, diff: Dictionary, redo: bool) -> Rect2i:
	if document.heights.size() != document.sample_count():
		return Rect2i()
	var side := "after" if redo else "before"
	for block in diff.get("blocks", []):
		var rect: Rect2i = block.rect
		var packed: PackedByteArray = block[side]
		var raw := packed.decompress(rect.size.x * rect.size.y * 4, COMPRESSION)
		write_block(document.heights, document.samples_x(), rect, raw.to_float32_array())
	return diff.get("rect", Rect2i())


## The floats of `rect` of a row-major grid `width` samples wide, row by row.
static func read_block(values: PackedFloat32Array, width: int, rect: Rect2i) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		out.append_array(values.slice(start, start + rect.size.x))
	return out


## Writes read_block() output back into `values` (in place).
static func write_block(
	values: PackedFloat32Array, width: int, rect: Rect2i, block: PackedFloat32Array
) -> void:
	var source := 0
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		for x in rect.size.x:
			values[start + x] = block[source + x]
		source += rect.size.x
