extends SceneTree

## Offline map-size measurement (see README.md). Reads the documents dump.gd wrote
## under user://_msize_/, reports per-entry raw and in-ZIP sizes (from the central
## directory), the whole file on disk and zstd-compressed (what AssetStreamer sends), and
## prototypes a packed binary scatter entry, a fewer-decimals JSON, and a quantized
## height.bin, with round-trip errors. Writes alternative archives beside the originals to
## measure what each would cost to send. Prints lines prefixed MS|.

const DIR := "user://_msize_"
const MAPS := [
	"grass_valley_200",
	"forest_valley_200",
	"forest_flat_100",
	"bare_flat_200",
	"grass_valley_200_full",
	"forest_valley_200_full",
	"grass_flat_200_full",
]
const PROTO_MAPS := [
	"grass_valley_200",
	"forest_valley_200",
	"grass_valley_200_full",
	"forest_valley_200_full",
	"grass_flat_200_full",
]
const RATE := 1048576.0
## Lean (degrees) reported as "small"; the encoding range is _lean_max (user arg 1) and the
## lean components are int8 or int16 (user arg 2).
const LEAN_SMALL_DEG := 30.0
const LOG2_RANGE := 8.0

var _stats := {}
var _lean_max := 90.0
var _lean_bits := 8
var _only_proto := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2:
		_lean_max = float(args[0])
		_lean_bits = int(args[1])
		_only_proto = args.size() >= 3
	print("MS| lean range %.0f deg, %d-bit lean components" % [_lean_max, _lean_bits])
	if _only_proto:
		for map_name in PROTO_MAPS:
			_measure_map(map_name)
		quit()
		return
	for map_name in MAPS:
		_measure_map(map_name)
	var glb := FileAccess.get_file_as_bytes("user://oakslabpainted.glb")
	if not glb.is_empty():
		var z := glb.compress(FileAccess.COMPRESSION_ZSTD).size()
		print("MS| GLB oakslabpainted raw %d zstd %d (%.1f s)" % [glb.size(), z, z / RATE])
	quit()


# --- per map -------------------------------------------------------------------------------


func _measure_map(map_name: String) -> void:
	var path := "%s/%s.ttmap" % [DIR, map_name]
	var file := FileAccess.get_file_as_bytes(path)
	if file.is_empty():
		print("MS| %s missing" % map_name)
		return
	var dir := _central_directory(file)
	var read := MapDocumentIO.read(path)
	var doc: MapDocument = read.document
	print(
		(
			"MS| == %s  scatter rows %d (%d assets)  props rows %d  water %d crossings %d"
			% [
				map_name,
				MapDocument.row_count(doc.scatter),
				doc.scatter.size(),
				MapDocument.row_count(doc.props),
				doc.water_bodies.size(),
				doc.crossings.size(),
			]
		)
	)
	var total_zip := 0
	for entry in dir:
		total_zip += int(entry.comp)
	for entry in dir:
		print(
			(
				"MS| entry %-22s raw %9d zipped %9d share %5.1f%%"
				% [entry.name, entry.raw, entry.comp, 100.0 * entry.comp / maxf(file.size(), 1)]
			)
		)
	var sent := file.compress(FileAccess.COMPRESSION_ZSTD).size()
	print(
		(
			"MS| total on disk %d (entries zipped %d, zip overhead %d) sent zstd %d -> %.2f s at 1 MiB/s"
			% [file.size(), total_zip, file.size() - total_zip, sent, sent / RATE]
		)
	)
	# What zstd does with the raw entries (a STORE zip, then zstd), for comparison.
	var packed := MapDocumentIO.serialize(doc)
	var raw_cat := PackedByteArray()
	for k in packed.entries:
		raw_cat.append_array(packed.entries[k])
	var raw_z := raw_cat.compress(FileAccess.COMPRESSION_ZSTD).size()
	print("MS| raw entries concatenated %d zstd %d" % [raw_cat.size(), raw_z])
	_height_proto(doc, packed.entries)
	if map_name in PROTO_MAPS:
		_scatter_proto(map_name, doc, packed.entries)


## Entries of a ZIP from its central directory: [{name, raw, comp}].
func _central_directory(file: PackedByteArray) -> Array:
	var eocd := -1
	for i in range(file.size() - 22, maxi(file.size() - 65558, -1), -1):
		if file.decode_u32(i) == 0x06054b50:
			eocd = i
			break
	var out := []
	if eocd < 0:
		return out
	var count := file.decode_u16(eocd + 10)
	var at := file.decode_u32(eocd + 16)
	for n in count:
		var comp := file.decode_u32(at + 20)
		var raw := file.decode_u32(at + 24)
		var name_len := file.decode_u16(at + 28)
		var extra_len := file.decode_u16(at + 30)
		var comment_len := file.decode_u16(at + 32)
		var entry_name := file.slice(at + 46, at + 46 + name_len).get_string_from_utf8()
		out.append({"name": entry_name, "raw": raw, "comp": comp})
		at += 46 + name_len + extra_len + comment_len
	return out


# --- height ----------------------------------------------------------------------------------


func _height_proto(doc: MapDocument, entries: Dictionary) -> void:
	var h := doc.heights
	var lo := INF
	var hi := -INF
	for v in h:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	var f32: PackedByteArray = entries[MapDocumentIO.HEIGHT_ENTRY]
	var nx := doc.samples_x()
	var q := PackedInt32Array()
	q.resize(h.size())
	var max_err := 0.0
	for i in h.size():
		q[i] = roundi((h[i] - lo) * 1000.0)
		max_err = maxf(max_err, absf(lo + q[i] / 1000.0 - h[i]))
	var plain := PackedByteArray()
	var dx := PackedByteArray()
	var dz := PackedByteArray()
	plain.resize(h.size() * 2)
	dx.resize(h.size() * 2)
	dz.resize(h.size() * 2)
	for i in h.size():
		plain.encode_u16(i * 2, q[i] & 0xffff)
		var left := q[i - 1] if i % nx != 0 else (q[i - nx] if i >= nx else 0)
		dx.encode_u16(i * 2, (q[i] - left) & 0xffff)
		var up := q[i - nx] if i >= nx else (q[i - 1] if i > 0 else 0)
		dz.encode_u16(i * 2, (q[i] - up) & 0xffff)
	print(
		(
			"MS| height range %.3f..%.3f m (%.3f m span, u16 mm fits %s) max err %.2f mm"
			% [lo, hi, hi - lo, str(hi - lo < 65.5), max_err * 1000.0]
		)
	)
	print(
		(
			"MS| height f32 raw %d zstd %d deflate %d | u16 zstd %d | u16 dx zstd %d deflate %d | u16 dz(row) zstd %d deflate %d"
			% [
				f32.size(),
				_z(f32),
				_d(f32),
				_z(plain),
				_z(dx),
				_d(dx),
				_z(dz),
				_d(dz),
			]
		)
	)
	_stats["height_dz"] = dz


# --- scatter ---------------------------------------------------------------------------------


func _scatter_proto(map_name: String, doc: MapDocument, entries: Dictionary) -> void:
	var ext := doc.extent_m()
	var pos_lo := -ext * 0.5 - Vector2.ONE
	var pos_span := ext + Vector2.ONE * 2.0
	var k_lean := sin(deg_to_rad(_lean_max) * 0.5)
	var lean_steps := 127.0 if _lean_bits == 8 else 32767.0
	var small := 0
	var leans := PackedFloat32Array()
	var fit_lean := 0
	var uniform := 0
	var rows_total := 0
	var dy_abs := PackedFloat32Array()
	var dy_over := 0
	var err := {"pos_mm": 0.0, "rot_deg": 0.0, "scale_rel": 0.0}
	var err_j := {"pos_mm": 0.0, "rot_deg": 0.0, "scale_rel": 0.0}
	var col_blobs := []
	var row_blobs := []
	for set_name in ["scatter", "props"]:
		var rows_by_asset: Dictionary[String, PackedFloat32Array] = (
			doc.scatter if set_name == "scatter" else doc.props
		)
		var col := StreamPeerBuffer.new()
		var rowb := StreamPeerBuffer.new()
		col.put_u16(rows_by_asset.size())
		rowb.put_u16(rows_by_asset.size())
		var ids := rows_by_asset.keys()
		ids.sort()
		for asset_id in ids:
			var flat: PackedFloat32Array = rows_by_asset[asset_id]
			var n := flat.size() / MapDocument.ROW_STRIDE
			rows_total += n
			# Quantize every row, decide per-asset modes.
			var recs := []
			var all_lean := true
			var all_uniform := true
			for r in n:
				var o := r * MapDocument.ROW_STRIDE
				var p := Vector3(flat[o], flat[o + 1], flat[o + 2])
				var quat := Quaternion(flat[o + 3], flat[o + 4], flat[o + 5], flat[o + 6]).normalized()
				var s := Vector3(flat[o + 7], flat[o + 8], flat[o + 9])
				var xq := clampi(roundi((p.x - pos_lo.x) / pos_span.x * 65535.0), 0, 65535)
				var zq := clampi(roundi((p.z - pos_lo.y) / pos_span.y * 65535.0), 0, 65535)
				var twist := Quaternion(0.0, quat.y, 0.0, quat.w)
				if twist.length() < 1e-6:
					twist = Quaternion.IDENTITY
				twist = twist.normalized()
				if twist.w < 0.0:
					twist = -twist
				var swing := quat * twist.inverse()
				if swing.w < 0.0:
					swing = -swing
				var lean := rad_to_deg(2.0 * acos(clampf(swing.w, -1.0, 1.0)))
				leans.append(lean)
				if lean <= LEAN_SMALL_DEG:
					small += 1
				var fits := lean <= _lean_max and absf(swing.y) < 1e-3
				if fits:
					fit_lean += 1
				else:
					all_lean = false
				var uni := absf(s.x - s.y) <= 1e-4 and absf(s.x - s.z) <= 1e-4
				if uni:
					uniform += 1
				else:
					all_uniform = false
				recs.append(
					{
						"p": p,
						"q": quat,
						"s": s,
						"xq": xq,
						"zq": zq,
						"twist": twist,
						"swing": swing
					}
				)
			recs.sort_custom(
				func(a: Dictionary, b: Dictionary) -> bool:
					return a.zq < b.zq or (a.zq == b.zq and a.xq < b.xq)
			)
			# Encode columns and rows; decode and measure as we go.
			var c_dz := StreamPeerBuffer.new()
			var c_x := StreamPeerBuffer.new()
			var c_y := StreamPeerBuffer.new()
			var c_rot := StreamPeerBuffer.new()
			var c_lean := StreamPeerBuffer.new()
			var c_scale := StreamPeerBuffer.new()
			var rows_out := StreamPeerBuffer.new()
			var prev_z := 0
			for rec in recs:
				var xq: int = rec.xq
				var zq: int = rec.zq
				var dx := pos_lo.x + xq / 65535.0 * pos_span.x
				var dzv := pos_lo.y + zq / 65535.0 * pos_span.y
				var ground := _height_at(doc, Vector2(dx, dzv))
				var p: Vector3 = rec.p
				var dy_mm := roundi((p.y - ground) * 1000.0)
				dy_abs.append(absf(p.y - ground))
				if absi(dy_mm) > 32767:
					dy_over += 1
				dy_mm = clampi(dy_mm, -32768, 32767)
				var dec_p := Vector3(dx, ground + dy_mm / 1000.0, dzv)
				err.pos_mm = maxf(err.pos_mm, dec_p.distance_to(p) * 1000.0)
				c_dz.put_u16(zq - prev_z)
				c_x.put_u16(xq)
				c_y.put_16(dy_mm)
				rows_out.put_u16(zq - prev_z)
				rows_out.put_u16(xq)
				rows_out.put_16(dy_mm)
				prev_z = zq
				var dec_q: Quaternion
				var orig_q: Quaternion = rec.q
				if all_lean:
					var twist: Quaternion = rec.twist
					var swing: Quaternion = rec.swing
					var yaw := 2.0 * atan2(twist.y, twist.w)
					var yq := posmod(roundi((yaw + PI) / TAU * 65536.0), 65536)
					var lim := int(lean_steps)
					var a := clampi(roundi(swing.x / k_lean * lean_steps), -lim, lim)
					var b := clampi(roundi(swing.z / k_lean * lean_steps), -lim, lim)
					c_rot.put_u16(yq)
					rows_out.put_u16(yq)
					for buf in [c_lean, rows_out]:
						if _lean_bits == 8:
							buf.put_8(a)
							buf.put_8(b)
						else:
							buf.put_16(a)
							buf.put_16(b)
					var sx := a / lean_steps * k_lean
					var sz := b / lean_steps * k_lean
					var sw := sqrt(maxf(0.0, 1.0 - sx * sx - sz * sz))
					var tw := Quaternion(Vector3.UP, yq / 65536.0 * TAU - PI)
					dec_q = Quaternion(sx, 0.0, sz, sw) * tw
				else:
					var packed_q := _smallest_three(orig_q)
					c_rot.put_u32(packed_q)
					rows_out.put_u32(packed_q)
					dec_q = _unpack_three(packed_q)
				var ang := rad_to_deg(2.0 * acos(clampf(absf(dec_q.dot(orig_q)), 0.0, 1.0)))
				err.rot_deg = maxf(err.rot_deg, ang)
				var s: Vector3 = rec.s
				var dec_s: Vector3
				if all_uniform:
					var sq := _scale_q(s.x)
					c_scale.put_u16(sq)
					rows_out.put_u16(sq)
					dec_s = Vector3.ONE * _scale_dq(sq)
				else:
					var sv := [_scale_q(s.x), _scale_q(s.y), _scale_q(s.z)]
					for v in sv:
						c_scale.put_u16(v)
						rows_out.put_u16(v)
					dec_s = Vector3(_scale_dq(sv[0]), _scale_dq(sv[1]), _scale_dq(sv[2]))
				for axis in 3:
					err.scale_rel = maxf(err.scale_rel, absf(dec_s[axis] / s[axis] - 1.0))
				# Fewer-decimals JSON error.
				var pj := Vector3(snappedf(p.x, 1e-3), snappedf(p.y, 1e-3), snappedf(p.z, 1e-3))
				err_j.pos_mm = maxf(err_j.pos_mm, pj.distance_to(p) * 1000.0)
				var qj := Quaternion(
					snappedf(orig_q.x, 1e-4),
					snappedf(orig_q.y, 1e-4),
					snappedf(orig_q.z, 1e-4),
					snappedf(orig_q.w, 1e-4)
				)
				var qjn := qj.normalized()
				var angj := rad_to_deg(2.0 * acos(clampf(absf(qjn.dot(orig_q)), 0.0, 1.0)))
				err_j.rot_deg = maxf(err_j.rot_deg, angj)
				for axis in 3:
					err_j.scale_rel = maxf(
						err_j.scale_rel, absf(snappedf(s[axis], 1e-4) / s[axis] - 1.0)
					)
			var id_bytes := String(asset_id).to_utf8_buffer()
			var mode := (1 if all_lean else 0) | (2 if all_uniform else 0)
			for buf in [col, rowb]:
				buf.put_u8(id_bytes.size())
				buf.put_data(id_bytes)
				buf.put_u32(n)
				buf.put_u8(mode)
			for part in [c_dz, c_x, c_y, c_rot, c_lean, c_scale]:
				col.put_data(part.data_array)
			rowb.put_data(rows_out.data_array)
		col_blobs.append(col.data_array)
		row_blobs.append(rowb.data_array)
	# Sizes.
	var json_cur := PackedByteArray()
	json_cur.append_array(entries[MapDocumentIO.SCATTER_ENTRY])
	json_cur.append_array(entries[MapDocumentIO.PROPS_ENTRY])
	var json_less := PackedByteArray()
	json_less.append_array(_rows_json_less(doc.scatter).to_utf8_buffer())
	json_less.append_array(_rows_json_less(doc.props).to_utf8_buffer())
	var col_all := PackedByteArray()
	col_all.append_array(col_blobs[0])
	col_all.append_array(col_blobs[1])
	var row_all := PackedByteArray()
	row_all.append_array(row_blobs[0])
	row_all.append_array(row_blobs[1])
	leans.sort()
	dy_abs.sort()
	var nl := leans.size()
	print(
		(
			"MS| proto %s rows %d | lean <= 30 deg %d (%.1f%%), in range %d (%.1f%%) lean p50 %.2f p99 %.2f max %.2f deg | uniform scale %d (%.1f%%)"
			% [
				map_name,
				rows_total,
				small,
				100.0 * small / maxf(rows_total, 1),
				fit_lean,
				100.0 * fit_lean / maxf(rows_total, 1),
				leans[nl / 2] if nl else 0.0,
				leans[mini(nl - 1, int(nl * 0.99))] if nl else 0.0,
				leans[nl - 1] if nl else 0.0,
				uniform,
				100.0 * uniform / maxf(rows_total, 1),
			]
		)
	)
	print(
		(
			"MS| proto %s dy from ground |dy| p50 %.4f p99 %.4f max %.4f m, %d rows over int16 mm"
			% [
				map_name,
				dy_abs[nl / 2] if nl else 0.0,
				dy_abs[mini(nl - 1, int(nl * 0.99))] if nl else 0.0,
				dy_abs[nl - 1] if nl else 0.0,
				dy_over,
			]
		)
	)
	for line in [
		["json current (6 dp)", json_cur, {}],
		["json fewer dp (3/4/4)", json_less, err_j],
		["binary columns", col_all, err],
		["binary rows", row_all, err],
	]:
		var blob: PackedByteArray = line[1]
		var e: Dictionary = line[2]
		print(
			(
				"MS| proto %s %-22s raw %8d deflate %8d zstd %8d | max pos %s mm rot %s deg scale %s"
				% [
					map_name,
					line[0],
					blob.size(),
					_d(blob),
					_z(blob),
					("%.3f" % e.pos_mm) if e else "-",
					("%.4f" % e.rot_deg) if e else "-",
					("%.6f" % e.scale_rel) if e else "-",
				]
			)
		)
	_alt_archives(map_name, entries, col_blobs, json_less)


## Writes the alternative archives and reports their size on disk and as sent.
func _alt_archives(
	map_name: String, entries: Dictionary, col_blobs: Array, json_less: PackedByteArray
) -> void:
	var variants := {
		"bin scatter": {"scatter.json": null, "props.json": null, "scatter.bin": col_blobs[0], "props.bin": col_blobs[1]},
		"bin scatter + u16 height": {
			"scatter.json": null,
			"props.json": null,
			"scatter.bin": col_blobs[0],
			"props.bin": col_blobs[1],
			"height.bin": null,
			"height_q.bin": _stats["height_dz"],
		},
		"json fewer dp": {"scatter.json": null, "props.json": null, "rows_less.json": json_less},
	}
	for label in variants:
		var e := entries.duplicate()
		var changes: Dictionary = variants[label]
		for k in changes:
			if changes[k] == null:
				e.erase(k)
			else:
				e[k] = changes[k]
		var path := "%s/alt_%s.zip" % [DIR, map_name]
		var packer := ZIPPacker.new()
		packer.open(path)
		for k in e:
			packer.start_file(k)
			packer.write_file(e[k])
			packer.close_file()
		packer.close()
		var bytes := FileAccess.get_file_as_bytes(path)
		var sent := _z(bytes)
		print(
			(
				"MS| alt %s %-26s on disk %8d sent zstd %8d -> %.2f s"
				% [map_name, label, bytes.size(), sent, sent / RATE]
			)
		)
		DirAccess.remove_absolute(path)


# --- helpers ---------------------------------------------------------------------------------


func _z(b: PackedByteArray) -> int:
	return b.compress(FileAccess.COMPRESSION_ZSTD).size()


func _d(b: PackedByteArray) -> int:
	return b.compress(FileAccess.COMPRESSION_DEFLATE).size()


func _height_at(doc: MapDocument, xz: Vector2) -> float:
	var s := doc.world_to_sample(xz)
	var nx := doc.samples_x()
	var nz := doc.samples_z()
	s.x = clampf(s.x, 0.0, nx - 1.0)
	s.y = clampf(s.y, 0.0, nz - 1.0)
	var x0 := mini(int(floor(s.x)), nx - 2)
	var z0 := mini(int(floor(s.y)), nz - 2)
	var fx := s.x - x0
	var fz := s.y - z0
	var h := doc.heights
	var a := lerpf(h[doc.sample_index(x0, z0)], h[doc.sample_index(x0 + 1, z0)], fx)
	var b := lerpf(h[doc.sample_index(x0, z0 + 1)], h[doc.sample_index(x0 + 1, z0 + 1)], fx)
	return lerpf(a, b, fz)


func _scale_q(s: float) -> int:
	var l := log(maxf(s, 1e-6)) / log(2.0)
	return clampi(roundi((l + LOG2_RANGE) / (2.0 * LOG2_RANGE) * 65535.0), 0, 65535)


func _scale_dq(q: int) -> float:
	return pow(2.0, q / 65535.0 * 2.0 * LOG2_RANGE - LOG2_RANGE)


func _smallest_three(q: Quaternion) -> int:
	var c := [q.x, q.y, q.z, q.w]
	var big := 0
	for i in 4:
		if absf(c[i]) > absf(c[big]):
			big = i
	var sign_v := 1.0 if c[big] >= 0.0 else -1.0
	var out := big
	var shift := 2
	for i in 4:
		if i == big:
			continue
		var v: float = c[i] * sign_v
		var qv := clampi(roundi((v + 0.70710678) / 1.41421356 * 1023.0), 0, 1023)
		out |= qv << shift
		shift += 10
	return out


func _unpack_three(packed: int) -> Quaternion:
	var big := packed & 3
	var c := [0.0, 0.0, 0.0, 0.0]
	var shift := 2
	var sum := 0.0
	for i in 4:
		if i == big:
			continue
		var v := ((packed >> shift) & 1023) / 1023.0 * 1.41421356 - 0.70710678
		c[i] = v
		sum += v * v
		shift += 10
	c[big] = sqrt(maxf(0.0, 1.0 - sum))
	return Quaternion(c[0], c[1], c[2], c[3])


## MapDocumentIO's row JSON with 3 decimals for positions, 4 for quaternions and scales.
func _rows_json_less(rows_by_asset: Dictionary[String, PackedFloat32Array]) -> String:
	var assets := PackedStringArray()
	var ids := rows_by_asset.keys()
	ids.sort()
	for asset_id in ids:
		var flat: PackedFloat32Array = rows_by_asset[asset_id]
		var rows := PackedStringArray()
		for start in range(0, flat.size(), MapDocument.ROW_STRIDE):
			var numbers := PackedStringArray()
			for k in MapDocument.ROW_STRIDE:
				numbers.append(String.num(flat[start + k], 3 if k < 3 else 4))
			rows.append("[" + ",".join(numbers) + "]")
		assets.append(JSON.stringify(asset_id) + ":[" + ",".join(rows) + "]")
	return "{" + ",".join(assets) + "}"
