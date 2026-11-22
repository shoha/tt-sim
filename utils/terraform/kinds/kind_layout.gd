extends RefCounted
## The checks and boxes every kind script shares (utils/terraform/terra_kinds.gd): a kind's float
## layout is HEADER floats, then whole items of STRIDE floats, at least MIN_ITEMS of them (STRIDE
## 0: exactly the header). Each kind's validate() is fits() plus its own field ranges; each
## bounds() mirrors its native kernel's (native/src/kinds/), reaches included, so the two agree
## (test_terra_kinds).

## A float beyond this is corrupt: positions are metres on a map of at most about 100 m.
const MAX_ABS_VALUE := 100000.0
## The reaches past a line's half width that the native stage table declares
## (native/src/terra_stage_table.h): a river's carve and bank, a path's bench, a wall's pad.
const CARVE_REACH_M := 5.5
const PATH_REACH_M := 1.7
const PAD_REACH_M := 2.0
## A pond's reach past its outline (terra_stages.h POND_REACH, plus half a metre).
const POND_REACH_M := 6.5


## True when `data` holds the header and whole items (at least `min_items`), every float finite
## and within MAX_ABS_VALUE.
static func fits(data: PackedFloat32Array, header: int, stride: int, min_items: int) -> bool:
	if stride == 0:
		if data.size() != header:
			return false
	elif data.size() < header or (data.size() - header) % stride != 0:
		return false
	elif items(data, header, stride) < min_items:
		return false
	for v in data:
		if is_nan(v) or is_inf(v) or absf(v) > MAX_ABS_VALUE:
			return false
	return true


## The whole items after the header.
static func items(data: PackedFloat32Array, header: int, stride: int) -> int:
	if stride == 0:
		return 0
	@warning_ignore("integer_division")
	return maxi(data.size() - header, 0) / stride


## True when every header float at `indices` is > 0.
static func positive(data: PackedFloat32Array, indices: Array) -> bool:
	for k: int in indices:
		if not data[k] > 0.0:
			return false
	return true


## True when field `k` of every item is > 0.
static func item_positive(data: PackedFloat32Array, header: int, stride: int, k: int) -> bool:
	for i in items(data, header, stride):
		if not data[header + i * stride + k] > 0.0:
			return false
	return true


## True when field `k` of every item is a whole number in 0..top.
static func item_enum(data: PackedFloat32Array, header: int, stride: int, k: int, top: int) -> bool:
	for i in items(data, header, stride):
		var v := data[header + i * stride + k]
		if v != floorf(v) or v < 0.0 or v > float(top):
			return false
	return true


## The box of the dabs [cx, cz, radius, ...] of `stride` floats each.
static func dab_bounds(data: PackedFloat32Array, stride: int) -> Rect2:
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	var k := 0
	while k + stride <= data.size():
		var r := data[k + 2]
		lo = Vector2(minf(lo.x, data[k] - r), minf(lo.y, data[k + 1] - r))
		hi = Vector2(maxf(hi.x, data[k] + r), maxf(hi.y, data[k + 1] + r))
		k += stride
	return Rect2(lo, hi - lo)


## The box of the (x, z) points after `skip` header floats, grown by `grow` metres.
static func line_bounds(data: PackedFloat32Array, skip: int, grow: float) -> Rect2:
	var lo := Vector2(1e30, 1e30)
	var hi := Vector2(-1e30, -1e30)
	var k := skip
	while k + 1 < data.size():
		lo = Vector2(minf(lo.x, data[k] - grow), minf(lo.y, data[k + 1] - grow))
		hi = Vector2(maxf(hi.x, data[k] + grow), maxf(hi.y, data[k + 1] + grow))
		k += 2
	return Rect2(lo, hi - lo)
