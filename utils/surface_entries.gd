class_name SurfaceEntries
extends RefCounted

## The byte rules of a MapDocument's painted surface entries (format 2; the layout and the
## canonical form are in MapDocument's header): each sample keeps up to ENTRIES (index,
## weight) pairs in two RGBA8 planes of `count` samples each, the index plane and then the
## weight plane. Shared by MapDocument's accessors, MapDocumentIO's reader (canonical() for
## a format 2 document, from_slots() to migrate format 1) and the paint tools. Everything
## here is static; write_sample() edits the `planes` it is handed in place, the rest return
## new arrays and leave their input as it was.

const ENTRIES := MapDocument.SURFACE_ENTRIES
const CHANNELS := MapDocument.SURFACE_CHANNELS
const SLOTS_1 := MapDocument.FORMAT_1_SLOTS


## Sample `sample`'s entries that carry weight, high to low (ties keep their entry order):
## [indices, weights] as two PackedInt32Arrays. Every entry is read, so a sample that is not
## canonical comes back sorted (duplicates and out-of-range indices are left to the caller).
static func read_sample(planes: PackedByteArray, sample: int, count: int) -> Array:
	var indices := PackedInt32Array()
	var weights := PackedInt32Array()
	var at := sample * CHANNELS
	var weight_at := count * CHANNELS + at
	for e in ENTRIES:
		var weight := planes[weight_at + e]
		if weight > 0:
			indices.append(planes[at + e])
			weights.append(weight)
	_sort(indices, weights)
	return [indices, weights]


## Writes the entries `indices` / `weights` (any order; those of weight 0 are left out, and
## of more than ENTRIES only the strongest kept) into sample `sample` of `planes` in
## canonical order, the unused entries (0, 0). The caller keeps the indices distinct and the
## sum within 255. Returns true when a byte changed.
static func write_sample(
	planes: PackedByteArray,
	sample: int,
	count: int,
	indices: PackedInt32Array,
	weights: PackedInt32Array
) -> bool:
	var kept_indices := PackedInt32Array()
	var kept_weights := PackedInt32Array()
	for e in weights.size():
		if weights[e] > 0:
			kept_indices.append(indices[e])
			kept_weights.append(mini(weights[e], 255))
	_sort(kept_indices, kept_weights)
	var at := sample * CHANNELS
	var weight_at := count * CHANNELS + at
	var changed := false
	for e in ENTRIES:
		var index := kept_indices[e] if e < kept_weights.size() else 0
		var weight := kept_weights[e] if e < kept_weights.size() else 0
		if planes[at + e] != index:
			planes[at + e] = index
			changed = true
		if planes[weight_at + e] != weight:
			planes[weight_at + e] = weight
			changed = true
	return changed


## One byte per slot 0..`used` - 1: 1 when some entry of that slot carries weight. Walks
## each sample's entries up to its first unused one (canonical entries are high to low).
static func used_slots(planes: PackedByteArray, count: int, used: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(used)
	var weight_base := count * CHANNELS
	var found := 0
	for sample in count:
		var at := sample * CHANNELS
		for e in ENTRIES:
			if planes[weight_base + at + e] == 0:
				break
			var index := planes[at + e]
			if index < used and out[index] == 0:
				out[index] = 1
				found += 1
		if found == used:
			break
	return out


## `planes` (the entries of `count` samples; the caller checked the size) in canonical form
## for a document listing `used` slots, and what had to be fixed: {"weights": the entries,
## "dropped": entries dropped for naming slot `used` or later, "merged": samples naming one
## slot twice (the weights added), "over": samples summing past 255 (scaled down), "fixed":
## samples changed in any way, re-sorted or a loose unused entry included}. `planes` is
## duplicated before the first fix.
@warning_ignore("integer_division")
static func canonical(planes: PackedByteArray, count: int, used: int) -> Dictionary:
	var out := planes
	var copied := false
	var weight_base := count * CHANNELS
	var dropped := 0
	var merged := 0
	var over := 0
	var fixed := 0
	for sample in count:
		var at := sample * CHANNELS
		var ok := true
		var sum := 0
		var previous := 256
		var seen := 0
		for e in ENTRIES:
			var weight := out[weight_base + at + e]
			var index := out[at + e]
			if weight == 0:
				ok = ok and index == 0
				previous = 0
				continue
			if weight > previous or index >= used or (seen & (1 << index)) != 0:
				ok = false
				break
			seen |= 1 << index
			previous = weight
			sum += weight
		if ok and sum <= 255:
			continue
		if not copied:
			out = out.duplicate()
			copied = true
		var indices := PackedInt32Array()
		var weights := PackedInt32Array()
		var doubled := false
		for e in ENTRIES:
			var weight := out[weight_base + at + e]
			var index := out[at + e]
			if weight == 0:
				continue
			if index >= used:
				dropped += 1
				continue
			var known := indices.find(index)
			if known >= 0:
				weights[known] = mini(weights[known] + weight, 255)
				doubled = true
			else:
				indices.append(index)
				weights.append(weight)
		var total := 0
		for weight in weights:
			total += weight
		if total > 255:
			for e in weights.size():
				weights[e] = weights[e] * 255 / total
			over += 1
		merged += 1 if doubled else 0
		fixed += 1
		write_sample(out, sample, count, indices, weights)
	return {"weights": out, "dropped": dropped, "merged": merged, "over": over, "fixed": fixed}


## Format 1's painted surfaces as entries. `slot_planes` holds SLOTS_1 weight channels per
## sample in two RGBA8 planes (slots 0-3, then slots 4-7) for `count` samples, of which
## `used` slots are listed. Per sample, the non-zero weights of the listed slots high to
## low, the strongest ENTRIES kept and scaled so they keep the sample's painted total
## (capped at 255). Returns {"weights": the entries (MapDocument.SURFACE_BYTES per sample),
## "stray": samples with weight in a slot not listed (cleared), "over": samples summing past
## 255 (scaled down), "crowded": samples with more than ENTRIES surfaces (the weakest
## dropped, the rest scaled up to keep the total)}.
@warning_ignore("integer_division")
static func from_slots(slot_planes: PackedByteArray, count: int, used: int) -> Dictionary:
	var out := PackedByteArray()
	out.resize(count * MapDocument.SURFACE_BYTES)
	var plane := count * CHANNELS
	var stray := 0
	var over := 0
	var crowded := 0
	for sample in count:
		var at := sample * CHANNELS
		if (
			slot_planes[at] == 0
			and slot_planes[at + 1] == 0
			and slot_planes[at + 2] == 0
			and slot_planes[at + 3] == 0
			and slot_planes[plane + at] == 0
			and slot_planes[plane + at + 1] == 0
			and slot_planes[plane + at + 2] == 0
			and slot_planes[plane + at + 3] == 0
		):
			continue
		var indices := PackedInt32Array()
		var weights := PackedInt32Array()
		var stray_here := false
		var total := 0
		for slot in SLOTS_1:
			var weight := slot_planes[(slot >> 2) * plane + sample * CHANNELS + (slot & 3)]
			if weight == 0:
				continue
			if slot >= used:
				stray_here = true
				continue
			indices.append(slot)
			weights.append(weight)
			total += weight
		stray += 1 if stray_here else 0
		if weights.is_empty():
			continue
		if total > 255:
			over += 1
			total = 255
		_sort(indices, weights)
		if weights.size() > ENTRIES:
			crowded += 1
			indices.resize(ENTRIES)
			weights.resize(ENTRIES)
		var kept := 0
		for weight in weights:
			kept += weight
		if kept != total:
			for e in weights.size():
				weights[e] = weights[e] * total / kept
		write_sample(out, sample, count, indices, weights)
	return {"weights": out, "stray": stray, "over": over, "crowded": crowded}


## Sorts the pairs by weight, high to low; equal weights keep their order (insertion sort:
## at most a handful of pairs).
static func _sort(indices: PackedInt32Array, weights: PackedInt32Array) -> void:
	for e in range(1, weights.size()):
		var weight := weights[e]
		var index := indices[e]
		var k := e - 1
		while k >= 0 and weights[k] < weight:
			weights[k + 1] = weights[k]
			indices[k + 1] = indices[k]
			k -= 1
		weights[k + 1] = weight
		indices[k + 1] = index
