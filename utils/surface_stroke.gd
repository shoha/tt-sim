class_name SurfaceStroke
extends RefCounted

## One stroke of the Paint tool on a MapDocument's painted surfaces (surface_ids /
## surface_weights; phase 3, P3-6): paints one palette surface, or erases every painted
## surface back toward the automatic ground, with MaskBrush's soft falloff and exposure, and
## records what it changed so the stroke can be undone, redone or cancelled. The MaskStroke
## pattern, on the eight weight channels.
##
## Paint. The painted slot's coverage v (0..1, a float per touched sample, started from its
## byte) approaches 1 by MaskBrush.amount() each dab, faster than a biome by SURFACE_GAIN. The
## newest paint wins, as MapDocument.set_surface_weight() says: the other slots keep their
## weights from the stroke's start while they fit in 255 - the painted weight, and scale down
## together once they do not. Computing them from the start bytes every dab (not from last
## dab's rounded bytes) keeps a long dwell from eroding them by rounding.
##
## Erase (Ctrl at the press). Every slot at a touched sample fades toward 0 by the same
## factor: a remaining fraction f per sample (1 at the start) is multiplied by 1 - amount()
## and each slot's weight is its start byte times f. The ground returns to the automatic
## dressing and the biome ground as the paint fades.
##
## Slots. A paint stroke claims its surface's slot on begin (MapDocument.ensure_surface():
## the surface's slot, a new one, or a slot whose paint was fully erased, renamed); begin()
## returns null when all MAX_SURFACES slots hold paint, and the caller tells the author why.
## finish() drops trailing slots left without paint (trim_unused_surfaces), so erasing a
## surface completely frees its slot. The slot list before and after, and whether the
## weights existed, are part of the diff. The list and the weights are replaced by new arrays
## rather than edited in place when they change size (worker snapshots may hold the old).
##
## Diffs. Before a stroke first writes a sample of a BLOCK x BLOCK block it copies that
## block's weights (both planes, 8 bytes a sample); finish() pairs the copies with the final
## bytes, ZSTD-compressed, so history holds only touched blocks. apply_diff() puts either side
## back. pending / changed are sample rectangles, as in MaskStroke.

const BLOCK := MaskStroke.BLOCK
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
const AMOUNT_STEPS := 256
const CHANNELS := MapDocument.SURFACE_CHANNELS
const SLOTS := MapDocument.MAX_SURFACES
## Paint rate over MaskBrush.RATE. A surface is a single layer rather than a density that
## thins trees, and a path should read after one pass at a natural speed: about 0.75 of full
## cover under the centre of a brush that crosses a point in a third of a second.
const SURFACE_GAIN := 1.5
## Erase moves this much faster than paint, so one pass clears the core of a stroke.
const ERASE_GAIN := 2.0
## Why a surface cannot be painted when every slot holds paint (slot_refusal()).
const FULL_REASON := (
	"All 8 paint slots hold paint. Erase one surface completely" + " (Ctrl+drag) to free a slot."
)
## Surface roles whose paint changes what grows (ScatterGround): built and painted rock.
const PLANT_ROLES := ["built", "cliff"]

var doc: MapDocument = null
var erasing: bool = false
## The slot a paint stroke writes; -1 while erasing.
var slot: int = -1
## Samples changed since the last take_pending(), and during the whole stroke.
var pending: Rect2i = Rect2i()
var changed: Rect2i = Rect2i()

## Paint: the slot's coverage; erase: the remaining fraction. Per sample, once loaded.
var _value := PackedFloat32Array()
## Every slot's weight when the sample was first touched (sample * SLOTS + slot).
var _start := PackedByteArray()
var _loaded := PackedByteArray()
var _captured := PackedByteArray()
## block Vector2i -> {"rect": Rect2i, "bytes": PackedByteArray before the stroke}.
var _before: Dictionary = {}
var _ids_before := PackedStringArray()
var _had_weights: bool = false
var _blocks_x: int = 0


## Starts a stroke on `document`: painting palette surface `surface` or, with `erase`,
## erasing all painted surfaces. Returns null when there is nothing to do: erase on a
## document without paint, or paint when every slot holds paint (see the header).
static func begin(document: MapDocument, surface: String, erase: bool) -> SurfaceStroke:
	var stroke := SurfaceStroke.new()
	stroke.doc = document
	stroke.erasing = erase
	stroke._ids_before = document.surface_ids.duplicate()
	stroke._had_weights = not document.surface_weights.is_empty()
	var count := document.sample_count()
	if erase:
		if not stroke._had_weights or document.surface_ids.is_empty():
			return null
		document.surface_ids = document.surface_ids.duplicate()
	else:
		if surface == "":
			return null
		if not stroke._had_weights:
			var fresh := PackedByteArray()
			fresh.resize(count * CHANNELS * 2)
			document.surface_weights = fresh
		document.surface_ids = document.surface_ids.duplicate()
		stroke.slot = document.ensure_surface(surface)
		if stroke.slot < 0:
			stroke._restore_list()
			return null
	stroke._value.resize(count)
	stroke._start.resize(count * SLOTS)
	stroke._loaded.resize(count)
	stroke._blocks_x = ceili(float(document.samples_x()) / BLOCK)
	stroke._captured.resize(stroke._blocks_x * ceili(float(document.samples_z()) / BLOCK))
	return stroke


## "" when `surface` can take a slot on `document` (it has one, a slot is free, or a slot's
## paint was fully erased), else FULL_REASON. The walk over each slot's weights
## (MapDocument.surface_slot_unused) only runs when all MAX_SURFACES slots are taken.
static func slot_refusal(document: MapDocument, surface: String) -> String:
	var ids := document.surface_ids
	if surface in ids or ids.size() < MapDocument.MAX_SURFACES:
		return ""
	for s in ids.size():
		if document.surface_slot_unused(s):
			return ""
	return FULL_REASON


## True when a finish() diff involves a surface whose paint changes what grows (a built or
## cliff-role surface in the slot list before or after), so the scatter must follow it.
## `surfaces` is the palette's surface table (PaletteLibrary.surfaces()).
static func changes_plants(diff: Dictionary, surfaces: Dictionary) -> bool:
	var ids := PackedStringArray(diff.get("ids_before", PackedStringArray()))
	ids.append_array(PackedStringArray(diff.get("ids_after", PackedStringArray())))
	for surface in ids:
		if String(surfaces.get(surface, {}).get("role", "ground")) in PLANT_ROLES:
			return true
	return false


## Applies `seconds` of exposure along the capsule of `radius` around `from`-`to`
## (document-local XZ metres), weighted by MaskBrush's falloff. Returns true when any byte
## changed.
func dab(from: Vector2, to: Vector2, radius: float, seconds: float) -> bool:
	if radius <= 0.0 or seconds <= 0.0:
		return false
	var rect := MaskBrush.capsule_rect(doc, from, to, radius)
	if not rect.has_area():
		return false
	_capture_blocks(rect)
	var steps := _amount_table(seconds)
	var width := doc.samples_x()
	var count := doc.sample_count()
	var plane := count * CHANNELS
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	var weights := doc.surface_weights
	var used := doc.surface_ids.size()
	var values := _value
	var start := _start
	var loaded := _loaded
	var mine := slot
	var erase := erasing
	var lut_top := float(AMOUNT_STEPS - 1)
	var low := Vector2i(rect.end)
	var high := Vector2i(-1, -1)
	# Inlined per sample, as in MaskStroke: a GDScript call per sample doubles the cost.
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
			var t_sq := (dx * dx + dz * dz) / radius_sq
			if t_sq >= 1.0:
				continue
			var a: float = steps[int((1.0 - t_sq) * (1.0 - t_sq) * lut_top)]
			if a <= 0.0:
				continue
			var i := row + x
			var base := i * SLOTS
			if loaded[i] == 0:
				loaded[i] = 1
				for s in used:
					start[base + s] = weights[(s >> 2) * plane + i * CHANNELS + (s & 3)]
				values[i] = 1.0 if erase else start[base + mine] / 255.0
			var touched := false
			if erase:
				var f: float = values[i] * (1.0 - a)
				values[i] = f
				for s in used:
					var at := (s >> 2) * plane + i * CHANNELS + (s & 3)
					var byte := roundi(start[base + s] * f)
					if byte != weights[at]:
						weights[at] = byte
						touched = true
			else:
				var v: float = values[i]
				v += (1.0 - v) * a
				values[i] = v
				var painted := clampi(roundi(v * 255.0), 0, 255)
				var others := 0
				for s in used:
					if s != mine:
						others += start[base + s]
				var room := 255 - painted
				for s in used:
					var at := (s >> 2) * plane + i * CHANNELS + (s & 3)
					var byte := painted
					if s != mine:
						byte = start[base + s]
						if others > room:
							@warning_ignore("integer_division")
							byte = byte * room / others
					if byte != weights[at]:
						weights[at] = byte
						touched = true
			if touched:
				low = low.min(Vector2i(x, z))
				high = high.max(Vector2i(x, z))
	if high.x < 0:
		return false
	var dirty := Rect2i(low, high - low + Vector2i.ONE)
	pending = MaskBrush.merge_rect(pending, dirty)
	changed = MaskBrush.merge_rect(changed, dirty)
	return true


func _amount_table(seconds: float) -> PackedFloat32Array:
	var rate := MaskBrush.RATE * SURFACE_GAIN * (ERASE_GAIN if erasing else 1.0)
	var table := PackedFloat32Array()
	table.resize(AMOUNT_STEPS)
	for q in AMOUNT_STEPS:
		table[q] = MaskBrush.amount(float(q) / float(AMOUNT_STEPS - 1), seconds, rate)
	return table


func _capture_blocks(rect: Rect2i) -> void:
	@warning_ignore("integer_division")
	var first := Vector2i(rect.position.x / BLOCK, rect.position.y / BLOCK)
	@warning_ignore("integer_division")
	var last := Vector2i((rect.end.x - 1) / BLOCK, (rect.end.y - 1) / BLOCK)
	for bz in range(first.y, last.y + 1):
		for bx in range(first.x, last.x + 1):
			var index := bz * _blocks_x + bx
			if _captured[index] != 0:
				continue
			_captured[index] = 1
			var block := Vector2i(bx, bz)
			var area := MaskStroke.block_rect(doc, block)
			_before[block] = {"rect": area, "bytes": read_block(doc, doc.surface_weights, area)}


## The rectangle changed since the last call (empty when nothing changed), then forgets it.
func take_pending() -> Rect2i:
	var rect := pending
	pending = Rect2i()
	return rect


## Ends the stroke: the diff history keeps, or {} when the stroke changed nothing (the
## document is then exactly as before, slot list included). Slots left without paint at the
## end of the list are dropped first (trim_unused_surfaces). A diff is {"blocks": Array of
## {"rect", "before", "after"} (compressed read_block() bytes), "ids_before", "ids_after",
## "had_before", "has_after" (weights allocated), "rect", "bytes"}.
func finish() -> Dictionary:
	if not changed.has_area():
		_restore_list()
		return {}
	var blocks: Array[Dictionary] = []
	var whole := Rect2i()
	var total := 0
	for block in _before:
		var entry: Dictionary = _before[block]
		var rect: Rect2i = entry.rect
		var old: PackedByteArray = entry.bytes
		var now := read_block(doc, doc.surface_weights, rect)
		if now == old:
			continue
		var packed_before := old.compress(COMPRESSION)
		var packed_after := now.compress(COMPRESSION)
		total += packed_before.size() + packed_after.size()
		blocks.append({"rect": rect, "before": packed_before, "after": packed_after})
		whole = MaskBrush.merge_rect(whole, rect)
	if blocks.is_empty():
		_restore_list()
		return {}
	var trimmed := doc.surface_ids.duplicate()
	doc.surface_ids = trimmed
	doc.trim_unused_surfaces()
	return {
		"blocks": blocks,
		"ids_before": _ids_before.duplicate(),
		"ids_after": doc.surface_ids.duplicate(),
		"had_before": _had_weights,
		"has_after": not doc.surface_weights.is_empty(),
		"rect": whole,
		"bytes": total,
	}


## Reverts everything the stroke wrote (a cancelled stroke). Returns the sample rectangle to
## refresh.
func revert() -> Rect2i:
	for block in _before:
		var entry: Dictionary = _before[block]
		write_block(doc, doc.surface_weights, entry.rect, entry.bytes)
	_restore_list()
	var rect := changed
	changed = Rect2i()
	pending = Rect2i()
	return rect


## The slot list (and the weights, when the stroke allocated them) as they were at begin.
func _restore_list() -> void:
	doc.surface_ids = _ids_before.duplicate()
	if not _had_weights:
		doc.surface_weights = PackedByteArray()


## Puts one side of a finish() diff back into `document` (`redo` true: the stroke's result;
## false: the state before it). Returns the sample rectangle it touched.
static func apply_diff(document: MapDocument, diff: Dictionary, redo: bool) -> Rect2i:
	var keep: bool = diff.get("has_after" if redo else "had_before", true)
	if document.surface_weights.is_empty():
		var fresh := PackedByteArray()
		fresh.resize(document.sample_count() * CHANNELS * 2)
		document.surface_weights = fresh
	var side := "after" if redo else "before"
	for block in diff.get("blocks", []):
		var rect: Rect2i = block.rect
		var packed: PackedByteArray = block[side]
		var raw := packed.decompress(rect.size.x * rect.size.y * CHANNELS * 2, COMPRESSION)
		write_block(document, document.surface_weights, rect, raw)
	document.surface_ids = (diff.ids_after if redo else diff.ids_before).duplicate()
	if not keep:
		document.surface_weights = PackedByteArray()
	return diff.get("rect", Rect2i())


## Both weight planes' bytes of `rect` (plane A's rows, then plane B's; 4 bytes a sample).
static func read_block(
	document: MapDocument, weights: PackedByteArray, rect: Rect2i
) -> PackedByteArray:
	var out := PackedByteArray()
	var width := document.samples_x()
	var plane := document.sample_count() * CHANNELS
	var run := rect.size.x * CHANNELS
	for p in 2:
		for z in range(rect.position.y, rect.end.y):
			var start := p * plane + (z * width + rect.position.x) * CHANNELS
			out.append_array(weights.slice(start, start + run))
	return out


## Writes read_block() output back into `weights` (in place).
static func write_block(
	document: MapDocument, weights: PackedByteArray, rect: Rect2i, block: PackedByteArray
) -> void:
	var width := document.samples_x()
	var plane := document.sample_count() * CHANNELS
	var run := rect.size.x * CHANNELS
	var source := 0
	for p in 2:
		for z in range(rect.position.y, rect.end.y):
			var start := p * plane + (z * width + rect.position.x) * CHANNELS
			for k in run:
				weights[start + k] = block[source + k]
			source += run
