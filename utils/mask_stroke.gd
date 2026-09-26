class_name MaskStroke
extends RefCounted

## One stroke of the Biome or Thin / Clear brush on a MapDocument: applies MaskBrush's rules
## to the document's masks in place, sample by sample, and records what it changed so the
## stroke can be undone, redone or cancelled.
##
## Masks written. Paint and thin write biome_slots / biome_density; on a document that
## dresses a map.glb (has_base_map) every mode also writes erase_mask, so painting a biome
## over Blender scatter replaces it by the same contest as over another biome, and thinning
## thins it (MaskBrush header). A mask the stroke needs and the document lacks is allocated
## (a new array, never a resize in place, since worker jobs may hold the old one).
##
## Working values. Densities and thin amounts are tracked as floats for the samples the
## stroke touched (initialised from the bytes on first touch), and written back as bytes
## after every dab. Accumulating in bytes would stall wherever one frame's step rounds to
## nothing, which is exactly the soft rim a dwelling brush is meant to fill in.
##
## Diffs. Before a stroke first writes a sample of a BLOCK x BLOCK block of the grid, it
## copies that block of every mask it writes. finish() pairs those copies with the blocks'
## final bytes and compresses both (ZSTD; masks compress well), so history holds only the
## touched blocks, never whole documents. apply_diff() puts either side back. Undo and redo
## return the sample rectangle they touched, for the terrain and scatter updates.
##
## Changed rectangles. Every dab grows `pending` by the samples whose bytes actually
## changed; the owner takes it once per frame (take_pending()) to update the ground and
## regenerate scatter, which coalesces every dab of a frame into one request.

## Diff block edge in samples (10 m at the default 0.25 m spacing, one scatter cell).
const BLOCK := 40
const SLOTS := &"biome_slots"
const DENSITY := &"biome_density"
const ERASE := &"erase_mask"
const COMPRESSION := FileAccess.COMPRESSION_ZSTD
## Weight steps of the per-dab amount table (see _amount_table).
const AMOUNT_STEPS := 256

var doc: MapDocument = null
var mode: int = MaskBrush.PAINT
## Biome slot the paint mode writes (index into biome_ids + 1); 0 in thin and clear.
var slot: int = 0
## Target density (0..1) paint approaches.
var target: float = 1.0
## Samples changed since the last take_pending().
var pending: Rect2i = Rect2i()
## Samples changed during the whole stroke.
var changed: Rect2i = Rect2i()

var _writes_biomes: bool = false
var _writes_erase: bool = false
var _density := PackedFloat32Array()
var _challenger := PackedFloat32Array()
var _thinned := PackedFloat32Array()
## Erase noise thresholds (MaskBrush.sample_noise) of the loaded samples.
var _noise := PackedFloat32Array()
## Per sample: 1 once its working values are loaded.
var _loaded := PackedByteArray()
## Per block: 1 once its "before" bytes are captured.
var _captured := PackedByteArray()
## block Vector2i -> {"rect": Rect2i, mask name -> PackedByteArray before the stroke}.
var _before: Dictionary = {}
var _ids_before := PackedStringArray()
## Mask names that were empty before this stroke allocated them.
var _allocated: Array[StringName] = []
var _blocks_x: int = 0


## Starts a stroke of `stroke_mode` on `document`. Paint needs `biome_id`, which is added to
## the document's biome list on its first use. Returns null when paint cannot add another
## biome (MapDocument.MAX_BIOMES).
static func begin(document: MapDocument, stroke_mode: int, biome_id: String = "") -> MaskStroke:
	var stroke := MaskStroke.new()
	stroke.doc = document
	stroke.mode = stroke_mode
	stroke._ids_before = document.biome_ids.duplicate()
	var count := document.sample_count()
	if stroke_mode == MaskBrush.PAINT:
		var index := document.biome_ids.find(biome_id)
		if index < 0:
			if biome_id == "" or document.biome_ids.size() >= MapDocument.MAX_BIOMES:
				return null
			var ids := document.biome_ids.duplicate()
			ids.append(biome_id)
			document.biome_ids = ids
			index = ids.size() - 1
		stroke.slot = index + 1
		stroke._writes_biomes = true
	else:
		stroke._writes_biomes = (
			document.biome_slots.size() == count and document.biome_density.size() == count
		)
	stroke._writes_erase = document.has_base_map
	if stroke._writes_biomes:
		stroke._ensure_mask(SLOTS)
		stroke._ensure_mask(DENSITY)
	if stroke._writes_erase:
		stroke._ensure_mask(ERASE)
	stroke._density.resize(count)
	stroke._challenger.resize(count)
	stroke._thinned.resize(count)
	stroke._noise.resize(count)
	stroke._loaded.resize(count)
	stroke._blocks_x = ceili(float(document.samples_x()) / BLOCK)
	stroke._captured.resize(stroke._blocks_x * ceili(float(document.samples_z()) / BLOCK))
	return stroke


## True when the stroke writes anything at all (thin on an unpainted map without a base
## writes nothing).
func writes_anything() -> bool:
	return _writes_biomes or _writes_erase


func _ensure_mask(mask: StringName) -> void:
	var current: PackedByteArray = doc.get(mask)
	if current.size() == doc.sample_count():
		return
	var fresh := PackedByteArray()
	fresh.resize(doc.sample_count())
	doc.set(mask, fresh)
	_allocated.append(mask)


## Applies `seconds` of exposure (already weighted by any dwell gain) along the capsule of
## `radius` around `from`-`to` (document-local XZ metres). Each sample is weighted by the
## falloff of its distance to the segment. Returns true when any byte changed.
func dab(from: Vector2, to: Vector2, radius: float, seconds: float) -> bool:
	if radius <= 0.0 or seconds <= 0.0 or not writes_anything():
		return false
	var rect := MaskBrush.capsule_rect(doc, from, to, radius)
	if not rect.has_area():
		return false
	_capture_blocks(rect)
	var steps := _amount_table(seconds)
	var width := doc.samples_x()
	var step := doc.sample_step()
	var origin := -doc.extent_m() * 0.5
	var segment := to - from
	var length_sq := segment.length_squared()
	var radius_sq := radius * radius
	var slots := doc.biome_slots
	var density := doc.biome_density
	var erase := doc.erase_mask
	var values := _density
	var challengers := _challenger
	var thinned := _thinned
	var loaded := _loaded
	var noise := _noise
	var biomes := _writes_biomes
	var erasing := _writes_erase
	var painting := mode == MaskBrush.PAINT
	var reach := MaskBrush.CLEAR_REACH if mode == MaskBrush.CLEAR else 1.0
	var mine := slot
	var goal := target
	var levels := float(MaskBrush.ERASE_LEVELS)
	var threshold := MapDocument.ERASE_THRESHOLD
	var lut_top := float(AMOUNT_STEPS - 1)
	var low := Vector2i(rect.end)
	var high := Vector2i(-1, -1)
	# Everything per sample is inlined: a GDScript call per sample doubled the cost.
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
			if loaded[i] == 0:
				loaded[i] = 1
				if biomes:
					values[i] = density[i] / 255.0
				if erasing:
					thinned[i] = MaskBrush.erase_amount(erase[i])
					noise[i] = MaskBrush.sample_noise(doc.map_seed, i)
			var touched := false
			if biomes:
				var owner := slots[i]
				var value: float = values[i]
				var new_slot := owner
				if not painting:
					value *= 1.0 - a
				elif owner == mine or owner == 0 or value <= 0.0:
					value += (goal - value) * a
					new_slot = mine
				else:
					value *= 1.0 - a
					var grown: float = challengers[i] + (goal - challengers[i]) * a
					challengers[i] = grown
					if grown >= value:
						value = grown
						new_slot = mine
				values[i] = value
				var byte := clampi(roundi(value * 255.0), 0, 255)
				if byte == 0:
					new_slot = 0
				if byte != density[i] or new_slot != owner:
					density[i] = byte
					slots[i] = new_slot
					touched = true
			if erasing and erase[i] <= threshold:
				var amount_now: float = thinned[i] + (1.0 - thinned[i]) * a
				thinned[i] = amount_now
				var erased_byte := clampi(roundi(amount_now * levels), 0, threshold)
				if amount_now >= noise[i] * reach:
					erased_byte = MaskBrush.ERASED
				if erased_byte != erase[i]:
					erase[i] = erased_byte
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


## MaskBrush.amount() for `seconds` at AMOUNT_STEPS evenly spaced weights, index 0 = weight
## 0; one exp() per entry instead of one per sample.
func _amount_table(seconds: float) -> PackedFloat32Array:
	var rate := MaskBrush.RATE * (MaskBrush.CLEAR_GAIN if mode == MaskBrush.CLEAR else 1.0)
	var table := PackedFloat32Array()
	table.resize(AMOUNT_STEPS)
	for q in AMOUNT_STEPS:
		table[q] = MaskBrush.amount(float(q) / float(AMOUNT_STEPS - 1), seconds, rate)
	return table


## Captures the "before" bytes of every diff block `rect` overlaps that this stroke has not
## captured yet.
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
			var block_area := block_rect(doc, block)
			var entry := {"rect": block_area}
			for mask in _written_masks():
				entry[mask] = read_block(doc.get(mask), doc.samples_x(), block_area)
			_before[block] = entry


func _written_masks() -> Array[StringName]:
	var masks: Array[StringName] = []
	if _writes_biomes:
		masks.append_array([SLOTS, DENSITY])
	if _writes_erase:
		masks.append(ERASE)
	return masks


## The rectangle changed since the last call (empty when nothing changed), then forgets it.
func take_pending() -> Rect2i:
	var rect := pending
	pending = Rect2i()
	return rect


## Ends the stroke: the diff history keeps, or {} when the stroke changed nothing (the
## document is then exactly as before, biome list included). A diff is {"blocks": Array of
## {"rect", "before": {mask: compressed}, "after": {mask: compressed}}, "ids_before",
## "ids_after", "allocated": Array[StringName], "rect": Rect2i (every block), "bytes": int}.
func finish() -> Dictionary:
	if not changed.has_area():
		_restore_list_and_allocations()
		return {}
	var blocks: Array[Dictionary] = []
	var whole := Rect2i()
	var total := 0
	for block in _before:
		var entry: Dictionary = _before[block]
		var rect: Rect2i = entry.rect
		var before := {}
		var after := {}
		for mask in _written_masks():
			var old: PackedByteArray = entry[mask]
			var now := read_block(doc.get(mask), doc.samples_x(), rect)
			if now == old:
				continue
			before[mask] = old.compress(COMPRESSION)
			after[mask] = now.compress(COMPRESSION)
			total += before[mask].size() + after[mask].size()
		if before.is_empty():
			continue
		blocks.append({"rect": rect, "before": before, "after": after})
		whole = MaskBrush.merge_rect(whole, rect)
	return {
		"blocks": blocks,
		"ids_before": _ids_before,
		"ids_after": doc.biome_ids.duplicate(),
		"allocated": _allocated.duplicate(),
		"rect": whole,
		"bytes": total,
	}


## Reverts everything the stroke wrote (a cancelled stroke). Returns the sample rectangle to
## refresh.
func revert() -> Rect2i:
	for block in _before:
		var entry: Dictionary = _before[block]
		for mask in _written_masks():
			var bytes: PackedByteArray = doc.get(mask)
			write_block(bytes, doc.samples_x(), entry.rect, entry[mask])
	_restore_list_and_allocations()
	var rect := changed
	changed = Rect2i()
	pending = Rect2i()
	return rect


func _restore_list_and_allocations() -> void:
	doc.biome_ids = _ids_before.duplicate()
	for mask in _allocated:
		doc.set(mask, PackedByteArray())


## Puts one side of a finish() diff back into `document` (`redo` true: the stroke's result;
## false: the state before it). Returns the sample rectangle it touched.
static func apply_diff(document: MapDocument, diff: Dictionary, redo: bool) -> Rect2i:
	var allocated: Array = diff.get("allocated", [])
	if redo:
		for mask in allocated:
			var fresh := PackedByteArray()
			fresh.resize(document.sample_count())
			document.set(mask, fresh)
	var side := "after" if redo else "before"
	for block in diff.get("blocks", []):
		var rect: Rect2i = block.rect
		var source: Dictionary = block[side]
		for mask in source:
			var bytes: PackedByteArray = document.get(mask)
			if bytes.size() != document.sample_count():
				continue
			var packed: PackedByteArray = source[mask]
			var raw := packed.decompress(rect.size.x * rect.size.y, COMPRESSION)
			write_block(bytes, document.samples_x(), rect, raw)
	document.biome_ids = (diff.ids_after if redo else diff.ids_before).duplicate()
	if not redo:
		for mask in allocated:
			document.set(mask, PackedByteArray())
	return diff.get("rect", Rect2i())


## The grid rectangle of diff block `block`, clipped to the document.
static func block_rect(document: MapDocument, block: Vector2i) -> Rect2i:
	var rect := Rect2i(block * BLOCK, Vector2i(BLOCK, BLOCK))
	return rect.intersection(Rect2i(0, 0, document.samples_x(), document.samples_z()))


## The bytes of `rect` of a row-major grid `width` samples wide, row by row.
static func read_block(bytes: PackedByteArray, width: int, rect: Rect2i) -> PackedByteArray:
	var out := PackedByteArray()
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		out.append_array(bytes.slice(start, start + rect.size.x))
	return out


## Writes read_block() output back into `bytes` (in place).
static func write_block(
	bytes: PackedByteArray, width: int, rect: Rect2i, block: PackedByteArray
) -> void:
	var source := 0
	for z in range(rect.position.y, rect.end.y):
		var start := z * width + rect.position.x
		for x in rect.size.x:
			bytes[start + x] = block[source + x]
		source += rect.size.x
