class_name MapRowsCodec
extends RefCounted

## The binary form of scatter and prop rows in `map.ttmap` (topic mapformat, format 4): the
## `scatter.bin` and `props.bin` entries, and the grass-mass offsets of `mass_anchors.bin`
## (MapAnchorsIO), which share its column coding. Replaces the JSON entries of formats 1-3, where
## a row cost ~90 bytes of text (34 deflated); a row here costs ~10 bytes deflated.
##
## The grid. A row is ten floats (MapDocument.ROW_STRIDE). Every one is snapped to
## MapDocumentIO.ROW_STEP (2^-10: 0.98 mm in position, about 0.1 degree in rotation, 0.1 % in
## scale) wherever rows are made (MapDocumentIO.snap_rows, ScatterRows, the native generator's
## `row_step`), so a snapped value is a float32 that is an exact multiple of the step and the
## integer code k = value / step is exact. Saving and reading are therefore lossless for every
## row that was snapped, and a row that was not (a hand-placed prop) comes back snapped: at most
## half a step (0.49 mm) off in position.
##
## Layout (little-endian), one rows entry:
##   "TTRW" u8 version (1) u32 asset count, then per asset
##   u16 id length, the id (UTF-8), u32 row count n, u32 body size, the body:
##   11 columns, each u8 width (0-4 bytes per value; 0 = all zero, no data), s32 base, then
##   `width` byte planes of n bytes (all the low bytes of the column, then the next byte, ...).
##   A column's value is plane value + base. Planes keep each byte's entropy together so the
##   ZIP's deflate sees them as the long runs and small alphabets they are.
## Columns (k = a component's integer code, r = the row, previous row for r = 0 all zero):
##   0 1 2   zigzag(k_x, k_y, k_z minus the previous row's): rows are emitted cell by cell, so
##           neighbours are close
##   3 4 5   zigzag(k_qx, k_qy, k_qz)
##   6       zigzag(|k_qw| minus the prediction), the prediction being round(sqrt(U^2 - qx^2 - qy^2
##           - qz^2)) with U = 1 / ROW_STEP: the rotation is a unit quaternion, so its fourth
##           component is known to about a step. Integer arithmetic and one correctly rounded
##           sqrt, so every platform predicts the same number.
##   7       1 when k_qw is negative, else 0
##   8       k_sx minus the column's minimum
##   9 10    zigzag(k_sy - k_sx), zigzag(k_sz - k_sx): zero for the uniform scale every generated
##           row has, so the two columns cost nothing
##
## The mass anchor offsets (encode_offsets) are two columns of zigzag codes at MapAnchorsIO.STEP.
##
## Entries arrive from a host peer: decode_* check every count and length against what is left of
## the buffer before allocating, bound the work by the caller's row budget, and drop a row whose
## value is out of range or whose rotation does not normalise (MapDocumentIO.row_ok's rule, in
## integers). A structurally broken entry (bad magic or version, truncated, an inconsistent size)
## comes back empty with a warning. Nothing here raises.

const ROWS_MAGIC := "TTRW"
const ANCHORS_MAGIC := "TTAN"
const VERSION := 1
const COLUMNS := 11
const OFFSET_COLUMNS := 2
const MAX_WIDTH := 4
const HEADER_BYTES := 9
const COLUMN_HEADER_BYTES := 5
## k_qw's prediction: U^2 with U = 1 / ROW_STEP.
const UNIT_SQ := MapDocumentIO.ROW_UNIT * MapDocumentIO.ROW_UNIT
## The largest code a valid component has (MapDocumentIO.MAX_ROW_COMPONENT in steps).
const MAX_CODE := int(MapDocumentIO.MAX_ROW_COMPONENT) * MapDocumentIO.ROW_UNIT
## A rotation of fewer than this many squared steps is not a rotation (row_ok's 1e-6 in steps^2).
const MIN_ROTATION_SQ := 2


# --- rows -----------------------------------------------------------------------------


## The rows entry for `rows_by_asset` (asset id -> flat rows, validated by the caller:
## MapDocumentIO.data_problem). Asset ids sorted, so the bytes are stable. Any thread.
static func encode_rows(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> PackedByteArray:
	var ids := rows_by_asset.keys()
	ids.sort()
	var out := _header(ROWS_MAGIC, ids.size())
	for asset_id: String in ids:
		var id_bytes := asset_id.to_utf8_buffer()
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		var body := _encode_asset(flat)
		out.append_array(_u16(id_bytes.size()))
		out.append_array(id_bytes)
		out.append_array(_u32(flat.size() / MapDocument.ROW_STRIDE))
		out.append_array(_u32(body.size()))
		out.append_array(body)
	return out


## Asset id -> flat rows from a rows entry, at most `budget` rows in all (an asset past it keeps
## its first rows). Problems are added to `warn_log` under `label`.
static func decode_rows(
	bytes: PackedByteArray, budget: int, label: String, warn_log: MapDocumentIO._WarningLog
) -> Dictionary[String, PackedFloat32Array]:
	var result: Dictionary[String, PackedFloat32Array] = {}
	var count := _check_header(bytes, ROWS_MAGIC, label, warn_log)
	if count < 0:
		return result
	var at := HEADER_BYTES
	var remaining := budget
	var dropped := 0
	for _asset in count:
		if bytes.size() - at < 2:
			warn_log.add("%s is truncated; the rest ignored" % label)
			return result
		var id_length := bytes.decode_u16(at)
		at += 2
		if id_length < 1 or id_length > MapDocumentIO.MAX_ID_LENGTH or bytes.size() - at < id_length + 8:
			warn_log.add("%s is malformed after %d assets; the rest ignored" % [label, result.size()])
			return result
		var asset_id := bytes.slice(at, at + id_length).get_string_from_utf8()
		at += id_length
		var n := bytes.decode_u32(at)
		var body_size := bytes.decode_u32(at + 4)
		at += 8
		if body_size > bytes.size() - at or n < 1 or n > MapDocumentIO.MAX_ROWS_PER_ASSET:
			warn_log.add("%s: asset '%s' is malformed; the rest ignored" % [label, asset_id])
			return result
		var body_at := at
		at += body_size
		var take := mini(n, remaining)
		if take < n:
			warn_log.add("%s: total row cap reached at '%s'" % [label, asset_id])
		if take < 1:
			continue
		var decoded: Variant = _decode_asset(bytes, body_at, body_size, n, take)
		if decoded == null:
			warn_log.add("%s: asset '%s' skipped: malformed columns" % [label, asset_id])
			continue
		var flat: PackedFloat32Array = decoded
		var kept := flat.size() / MapDocument.ROW_STRIDE
		dropped += take - kept
		remaining -= take
		if not MapDocumentIO._is_id(asset_id):
			warn_log.add("%s: asset id '%s' skipped" % [label, MapDocumentIO._label(asset_id)])
		elif result.has(asset_id):
			warn_log.add("%s: asset '%s' repeated; the first kept" % [label, asset_id])
		elif kept > 0:
			result[asset_id] = flat
	if dropped > 0:
		warn_log.add("%s: %d malformed rows skipped" % [label, dropped])
	return result


static func _encode_asset(flat: PackedFloat32Array) -> PackedByteArray:
	var stride := MapDocument.ROW_STRIDE
	var n := flat.size() / stride
	var cols: Array[PackedInt64Array] = []
	for c in COLUMNS:
		var column := PackedInt64Array()
		column.resize(n)
		cols.append(column)
	var unit := float(MapDocumentIO.ROW_UNIT)
	var px := 0
	var py := 0
	var pz := 0
	var min_scale := 1 << 60
	var scales := PackedInt64Array()
	scales.resize(n)
	for r in n:
		var b := r * stride
		var kx := floori(flat[b] * unit + 0.5)
		var ky := floori(flat[b + 1] * unit + 0.5)
		var kz := floori(flat[b + 2] * unit + 0.5)
		var qx := floori(flat[b + 3] * unit + 0.5)
		var qy := floori(flat[b + 4] * unit + 0.5)
		var qz := floori(flat[b + 5] * unit + 0.5)
		var qw := floori(flat[b + 6] * unit + 0.5)
		var sx := floori(flat[b + 7] * unit + 0.5)
		var sy := floori(flat[b + 8] * unit + 0.5)
		var sz := floori(flat[b + 9] * unit + 0.5)
		cols[0][r] = _zigzag(kx - px)
		cols[1][r] = _zigzag(ky - py)
		cols[2][r] = _zigzag(kz - pz)
		px = kx
		py = ky
		pz = kz
		cols[3][r] = _zigzag(qx)
		cols[4][r] = _zigzag(qy)
		cols[5][r] = _zigzag(qz)
		cols[6][r] = _zigzag(absi(qw) - _w_prediction(qx * qx + qy * qy + qz * qz))
		cols[7][r] = 1 if qw < 0 else 0
		scales[r] = sx
		min_scale = mini(min_scale, sx)
		cols[9][r] = _zigzag(sy - sx)
		cols[10][r] = _zigzag(sz - sx)
	var base := 0 if n == 0 else min_scale
	for r in n:
		cols[8][r] = scales[r] - base
	var body := PackedByteArray()
	for c in COLUMNS:
		body.append_array(_column(cols[c], base if c == 8 else 0))
	return body


## The valid rows among the first `take` of one asset's `n`, from the body at `at` (empty when
## every row was invalid), or null when the columns do not fit the body.
static func _decode_asset(
	bytes: PackedByteArray, at: int, body_size: int, n: int, take: int
) -> Variant:
	var cols: Array[PackedInt64Array] = []
	var cursor := at
	var end := at + body_size
	for c in COLUMNS:
		if end - cursor < COLUMN_HEADER_BYTES:
			return null
		var width := bytes[cursor]
		var base := bytes.decode_s32(cursor + 1)
		cursor += COLUMN_HEADER_BYTES
		if width > MAX_WIDTH or end - cursor < width * n:
			return null
		cols.append(_read_column(bytes, cursor, n, take, width, base))
		cursor += width * n
	if cursor != end:
		return null
	var stride := MapDocument.ROW_STRIDE
	var flat := PackedFloat32Array()
	flat.resize(take * stride)
	var step := MapDocumentIO.ROW_STEP
	var kept := 0
	var kx := 0
	var ky := 0
	var kz := 0
	var c0 := cols[0]
	var c1 := cols[1]
	var c2 := cols[2]
	var c3 := cols[3]
	var c4 := cols[4]
	var c5 := cols[5]
	var c6 := cols[6]
	var c7 := cols[7]
	var c8 := cols[8]
	var c9 := cols[9]
	var c10 := cols[10]
	for r in take:
		kx += _unzigzag(c0[r])
		ky += _unzigzag(c1[r])
		kz += _unzigzag(c2[r])
		var qx := _unzigzag(c3[r])
		var qy := _unzigzag(c4[r])
		var qz := _unzigzag(c5[r])
		var sx := c8[r]
		var sy := sx + _unzigzag(c9[r])
		var sz := sx + _unzigzag(c10[r])
		if (
			absi(kx) > MAX_CODE
			or absi(ky) > MAX_CODE
			or absi(kz) > MAX_CODE
			or absi(qx) > MAX_CODE
			or absi(qy) > MAX_CODE
			or absi(qz) > MAX_CODE
			or absi(sx) > MAX_CODE
			or absi(sy) > MAX_CODE
			or absi(sz) > MAX_CODE
		):
			continue
		var sq := qx * qx + qy * qy + qz * qz
		var qw := _w_prediction(sq) + _unzigzag(c6[r])
		if qw > MAX_CODE or qw < 0 or sq + qw * qw < MIN_ROTATION_SQ:
			continue
		if c7[r] != 0:
			qw = -qw
		var o := kept * stride
		flat[o] = kx * step
		flat[o + 1] = ky * step
		flat[o + 2] = kz * step
		flat[o + 3] = qx * step
		flat[o + 4] = qy * step
		flat[o + 5] = qz * step
		flat[o + 6] = qw * step
		flat[o + 7] = sx * step
		flat[o + 8] = sy * step
		flat[o + 9] = sz * step
		kept += 1
	flat.resize(kept * stride)
	return flat


# --- anchor offsets -------------------------------------------------------------------


## The offsets entry for `offsets_by_asset` (asset id -> (dx, dz) per row, flat), each value
## snapped to `step` (MapAnchorsIO.STEP). Ids sorted. Any thread.
static func encode_offsets(
	offsets_by_asset: Dictionary[String, PackedFloat32Array], step: float
) -> PackedByteArray:
	var ids := offsets_by_asset.keys()
	ids.sort()
	var out := _header(ANCHORS_MAGIC, ids.size())
	var unit := 1.0 / step
	for asset_id: String in ids:
		var id_bytes := asset_id.to_utf8_buffer()
		var offsets: PackedFloat32Array = offsets_by_asset[asset_id]
		var n := offsets.size() / OFFSET_COLUMNS
		var body := PackedByteArray()
		for c in OFFSET_COLUMNS:
			var column := PackedInt64Array()
			column.resize(n)
			for r in n:
				column[r] = _zigzag(floori(offsets[r * OFFSET_COLUMNS + c] * unit + 0.5))
			body.append_array(_column(column, 0))
		out.append_array(_u16(id_bytes.size()))
		out.append_array(id_bytes)
		out.append_array(_u32(n))
		out.append_array(_u32(body.size()))
		out.append_array(body)
	return out


## Asset id -> (dx, dz) per row (flat) from an offsets entry written at `step`; each asset's
## offsets are checked by the caller against its rows. Rows are not dropped here (an offset keeps
## its row's place), so a value beyond `max_abs` makes its asset malformed and it is skipped.
static func decode_offsets(
	bytes: PackedByteArray,
	step: float,
	max_abs: float,
	label: String,
	warn_log: MapDocumentIO._WarningLog
) -> Dictionary[String, PackedFloat32Array]:
	var result: Dictionary[String, PackedFloat32Array] = {}
	var count := _check_header(bytes, ANCHORS_MAGIC, label, warn_log)
	if count < 0:
		return result
	var at := HEADER_BYTES
	var remaining := MapDocumentIO.MAX_TOTAL_ROWS
	for _asset in count:
		if bytes.size() - at < 2:
			warn_log.add("%s is truncated; the rest ignored" % label)
			return result
		var id_length := bytes.decode_u16(at)
		at += 2
		if id_length < 1 or id_length > MapDocumentIO.MAX_ID_LENGTH or bytes.size() - at < id_length + 8:
			warn_log.add("%s is malformed after %d assets; the rest ignored" % [label, result.size()])
			return result
		var asset_id := bytes.slice(at, at + id_length).get_string_from_utf8()
		at += id_length
		var n := bytes.decode_u32(at)
		var body_size := bytes.decode_u32(at + 4)
		at += 8
		if body_size > bytes.size() - at or n > MapDocumentIO.MAX_ROWS_PER_ASSET or n > remaining:
			warn_log.add("%s: asset '%s' is malformed; the rest ignored" % [label, asset_id])
			return result
		var body_at := at
		at += body_size
		remaining -= n
		var offsets := _decode_offsets(bytes, body_at, body_size, n, step, max_abs)
		if offsets.is_empty() and n > 0:
			warn_log.add("%s: asset '%s' skipped: malformed columns" % [label, asset_id])
		elif MapDocumentIO._is_id(asset_id) and not result.has(asset_id):
			result[asset_id] = offsets
	return result


static func _decode_offsets(
	bytes: PackedByteArray, at: int, body_size: int, n: int, step: float, max_abs: float
) -> PackedFloat32Array:
	var cols: Array[PackedInt64Array] = []
	var cursor := at
	var end := at + body_size
	for c in OFFSET_COLUMNS:
		if end - cursor < COLUMN_HEADER_BYTES:
			return PackedFloat32Array()
		var width := bytes[cursor]
		var base := bytes.decode_s32(cursor + 1)
		cursor += COLUMN_HEADER_BYTES
		if width > MAX_WIDTH or end - cursor < width * n:
			return PackedFloat32Array()
		cols.append(_read_column(bytes, cursor, n, n, width, base))
		cursor += width * n
	if cursor != end:
		return PackedFloat32Array()
	var out := PackedFloat32Array()
	out.resize(n * OFFSET_COLUMNS)
	var limit := int(max_abs / step)
	for r in n:
		for c in OFFSET_COLUMNS:
			var k := _unzigzag(cols[c][r])
			if absi(k) > limit:
				return PackedFloat32Array()
			out[r * OFFSET_COLUMNS + c] = k * step
	return out


# --- columns --------------------------------------------------------------------------


## [u8 width][s32 base][planes] for `values` (each >= 0 once `base` is added back).
static func _column(values: PackedInt64Array, base: int) -> PackedByteArray:
	var n := values.size()
	var top := 0
	for v in values:
		top = maxi(top, v)
	var width := 0
	while width < MAX_WIDTH and (top >> (8 * width)) > 0:
		width += 1
	var out := PackedByteArray()
	out.resize(COLUMN_HEADER_BYTES + width * n)
	out[0] = width
	out.encode_s32(1, base)
	var o := COLUMN_HEADER_BYTES
	for p in width:
		var shift := 8 * p
		for r in n:
			out[o + r] = (values[r] >> shift) & 0xFF
		o += n
	return out


## The first `take` values of a column of `n` stored at `at` with `width` planes, base added.
static func _read_column(
	bytes: PackedByteArray, at: int, n: int, take: int, width: int, base: int
) -> PackedInt64Array:
	var out := PackedInt64Array()
	out.resize(take)
	match width:
		0:
			if base != 0:
				out.fill(base)
		1:
			for r in take:
				out[r] = bytes[at + r] + base
		2:
			var p1 := at + n
			for r in take:
				out[r] = (bytes[at + r] | (bytes[p1 + r] << 8)) + base
		3:
			var p1 := at + n
			var p2 := p1 + n
			for r in take:
				out[r] = (bytes[at + r] | (bytes[p1 + r] << 8) | (bytes[p2 + r] << 16)) + base
		_:
			var p1 := at + n
			var p2 := p1 + n
			var p3 := p2 + n
			for r in take:
				out[r] = (
					(bytes[at + r] | (bytes[p1 + r] << 8) | (bytes[p2 + r] << 16) | (bytes[p3 + r] << 24))
					+ base
				)
	return out


static func _zigzag(value: int) -> int:
	return value * 2 if value >= 0 else -value * 2 - 1


static func _unzigzag(code: int) -> int:
	return code >> 1 if code & 1 == 0 else -((code + 1) >> 1)


## round(sqrt(U^2 - sum)) for the squared codes `sum` of a rotation's first three components.
static func _w_prediction(sum: int) -> int:
	var rest := UNIT_SQ - sum
	return int(sqrt(float(rest)) + 0.5) if rest > 0 else 0


static func _header(magic: String, count: int) -> PackedByteArray:
	var out := magic.to_ascii_buffer()
	out.append(VERSION)
	out.append_array(_u32(count))
	return out


## The asset count of an entry whose header is right, or -1 (with a warning).
static func _check_header(
	bytes: PackedByteArray, magic: String, label: String, warn_log: MapDocumentIO._WarningLog
) -> int:
	if bytes.size() < HEADER_BYTES or bytes.slice(0, 4).get_string_from_ascii() != magic:
		warn_log.add("%s is not a %s entry; ignored" % [label, magic])
		return -1
	if bytes[4] != VERSION:
		warn_log.add("%s is version %d, this build reads %d; ignored" % [label, bytes[4], VERSION])
		return -1
	var count := bytes.decode_u32(5)
	if count > MapDocumentIO.MAX_ASSETS:
		warn_log.add(
			(
				"%s: %d asset ids over the cap of %d ignored"
				% [label, count - MapDocumentIO.MAX_ASSETS, MapDocumentIO.MAX_ASSETS]
			)
		)
		return MapDocumentIO.MAX_ASSETS
	return count


static func _u16(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(2)
	out.encode_u16(0, value)
	return out


static func _u32(value: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(4)
	out.encode_u32(0, value)
	return out
