class_name ScatterRows
extends RefCounted

## Pure helpers over flat instance rows (MapDocument.ROW_STRIDE floats each, [lx, ly, lz,
## qx, qy, qz, qw, sx, sy, sz]) that AuthoredScatter builds its cells from: each row's
## identity, the order a cell's instances are written in, row-to-transform conversion, and a
## settled chunk node's data in one call (chunk: its MultiMesh buffer, where the library has it).
## Pure and static, so the math is testable headless, where MultiMesh reads every transform
## back as identity.

const _MASK32 := 0xFFFFFFFF
const _INDEX_BITS := 24
const _INDEX_MASK := (1 << _INDEX_BITS) - 1

## A stable 62-bit identity per row (from the bits of its X, Z and scale), so two rebuilds
## of a cell can tell which instances they share. Y and the rotation are left out on
## purpose: a height edit moves an instance's Y (and tilts a normal-aligned one) without
## making it a different instance, so the regeneration after a sculpt stroke keeps every
## plant that is still wanted where it is instead of shrinking it out and growing it back.
## X and Z already identify a generated instance (they come from its hashed candidate), and
## a placed prop is its own position. `bits` is rows.to_byte_array().to_int32_array(),
## passed in so a caller that also orders the rows converts once.
@warning_ignore("integer_division")
static func row_keys(bits: PackedInt32Array) -> PackedInt64Array:
	var stride := MapDocument.ROW_STRIDE
	var count := bits.size() / stride
	var keys := PackedInt64Array()
	keys.resize(count)
	for r in count:
		var base := r * stride
		var high := mix(bits[base] ^ mix(bits[base + 2]))
		var low := mix(bits[base + 2] ^ mix(bits[base + 7] ^ 0x5BD1E995) ^ mix(bits[base]))
		keys[r] = ((high & 0x3FFFFFFF) << 32) | low
	return keys


## The order a cell's instances are written in: `indices` (rows of the cell) sorted by a
## hash of each row's key seeded by `seed_source`. A prefix of it is a spatially even
## sample (what visible_instance_count draws), and the relative order of two rows depends
## on those two rows alone, so adding or removing rows never reorders the others. This is
## the authored path's counterpart to FoliageBudget.shuffled_order, which orders by index
## and so reshuffles a whole cell whenever its count changes.
static func instance_order(
	keys: PackedInt64Array, indices: PackedInt32Array, seed_source: String
) -> PackedInt32Array:
	return _order_seeded(keys, indices, order_seed(seed_source))


## The 32-bit seed instance_order draws from `seed_source` (a node name).
static func order_seed(seed_source: String) -> int:
	return seed_source.md5_buffer().decode_u32(0)


## Everything a settled chunk node is built from, in one call (card scatterload): {"keys":
## row_keys of every row, "order": instance_order of `indices` (null: every row) seeded by
## `seed_source`}, plus, natively (ScatterNative.chunk, where the library has it), "buffer", the
## MultiMesh buffer of those rows in that order, and "custom", whether it carries custom data;
## or, in GDScript (chunk_gdscript), "transforms" for the per-instance path. Either way
## ScatterGlbUtils.multimesh_from_chunk builds the same MultiMesh, byte for byte
## (test_scatter_native_chunk, and the foliage_perf `load` probe on the real renderer).
## `keys`, when the caller has them, spare the GDScript path computing them again.
static func chunk(
	rows: PackedFloat32Array,
	indices: Variant,
	seed_source: String,
	anchors: Dictionary,
	keys: Variant = null
) -> Dictionary:
	var seed_value := order_seed(seed_source)
	var built := ScatterNative.chunk(rows, indices, seed_value, anchors)
	if built.is_empty():
		built = chunk_gdscript(rows, indices, seed_value, keys)
	return built


## chunk() in GDScript, wherever the library is absent: keys, order and the transforms in that
## order (a buffer filled in GDScript is slower than build_multimesh's per-instance calls).
## `seed_value` is order_seed's word.
@warning_ignore("integer_division")
static func chunk_gdscript(
	rows: PackedFloat32Array, indices: Variant, seed_value: int, keys: Variant = null
) -> Dictionary:
	var all_keys: PackedInt64Array = (
		keys if keys != null else row_keys(rows.to_byte_array().to_int32_array())
	)
	var chosen := PackedInt32Array()
	if indices == null:
		chosen.resize(rows.size() / MapDocument.ROW_STRIDE)
		for i in chosen.size():
			chosen[i] = i
	else:
		chosen = indices
	var order := _order_seeded(all_keys, chosen, seed_value)
	return {"keys": all_keys, "order": order, "transforms": transforms_from_rows(rows, order)}


static func _order_seeded(
	keys: PackedInt64Array, indices: PackedInt32Array, seed_value: int
) -> PackedInt32Array:
	var packed := PackedInt64Array()
	packed.resize(indices.size())
	for i in indices.size():
		var index := indices[i]
		var rank := mix((keys[index] & _MASK32) ^ seed_value ^ (keys[index] >> 32))
		packed[i] = (rank << _INDEX_BITS) | index
	packed.sort()
	var order := PackedInt32Array()
	order.resize(packed.size())
	for i in packed.size():
		order[i] = packed[i] & _INDEX_MASK
	return order


## Transforms of the rows at `indices`, in that order (see row_transform).
static func transforms_from_rows(
	rows: PackedFloat32Array, indices: PackedInt32Array
) -> Array[Transform3D]:
	var transforms: Array[Transform3D] = []
	transforms.resize(indices.size())
	for i in indices.size():
		transforms[i] = row_transform(rows, indices[i])
	return transforms


## The transform of row `r`: the same conversion as ScatterGlbUtils._row_to_transform (a
## zero quaternion becomes no rotation).
static func row_transform(rows: PackedFloat32Array, r: int) -> Transform3D:
	var b := r * MapDocument.ROW_STRIDE
	var rotation := Quaternion(rows[b + 3], rows[b + 4], rows[b + 5], rows[b + 6])
	rotation = rotation.normalized() if rotation.length_squared() > 0.0 else Quaternion()
	var basis := Basis(rotation).scaled(Vector3(rows[b + 7], rows[b + 8], rows[b + 9]))
	return Transform3D(basis, Vector3(rows[b], rows[b + 1], rows[b + 2]))


## 32-bit integer hash (the same xorshift-multiply ScatterGenerator uses).
static func mix(value: int) -> int:
	var h := value & _MASK32
	h ^= h >> 16
	h = (h * 0x7FEB352D) & _MASK32
	h ^= h >> 15
	h = (h * 0x1B873593) & _MASK32
	h ^= h >> 16
	return h


## The generator's rows split per asset id: `rows` (ScatterGenerator.ROW_STRIDE floats each) with
## `assets[r]` the index into `asset_ids` of row r, written into `result` by asset id. Rows are
## snapped to the saved precision first (MapDocumentIO.snap_rows), so a reload is bit-equal.
static func split_by_asset(
	asset_ids: Array, rows: PackedFloat32Array, assets: PackedInt32Array, result: Dictionary
) -> void:
	if rows.is_empty():
		return
	MapDocumentIO.snap_rows(rows)  # The saved precision: a reload is bit-equal.
	if asset_ids.size() == 1:
		result[String(asset_ids[0])] = rows
		return
	var per_asset: Array[PackedFloat32Array] = []
	per_asset.resize(asset_ids.size())
	for r in assets.size():
		per_asset[assets[r]].append_array(
			rows.slice(r * ScatterGenerator.ROW_STRIDE, (r + 1) * ScatterGenerator.ROW_STRIDE)
		)
	for a in asset_ids.size():
		if not per_asset[a].is_empty():
			result[String(asset_ids[a])] = per_asset[a]
