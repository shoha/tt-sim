extends GutTest

## MapRowsCodec (utils/map_rows_codec.gd): the binary scatter rows and mass anchor offsets of
## map.ttmap format 4. Lossless on rows that sit on the MapDocumentIO.ROW_STEP grid (every
## generated row does), snapped to it otherwise; hostile entries are in
## test_map_document_validation.gd.

const STRIDE := MapDocument.ROW_STRIDE


## `count` random rows as the generator makes them: a position over a 100 m map, a height, a
## yaw-plus-lean rotation (up to 64 degrees, either sign of w), mostly uniform scales.
func _random_rows(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var flat := PackedFloat32Array()
	for i in count:
		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var rotation := Quaternion(axis.normalized(), rng.randf_range(0.0, TAU))
		if i % 3 == 0:
			rotation = Quaternion(Vector3.UP, rng.randf_range(0.0, TAU))
		var scale := rng.randf_range(0.3, 2.0)
		var sx := scale
		var sy := scale
		var sz := scale
		if i % 17 == 0:
			sy = rng.randf_range(0.2, 3.0)
			sz = rng.randf_range(0.2, 3.0)
		flat.append_array(
			PackedFloat32Array(
				[
					rng.randf_range(-50, 50),
					rng.randf_range(-9, 4),
					rng.randf_range(-50, 50),
					rotation.x,
					rotation.y,
					rotation.z,
					rotation.w,
					sx,
					sy,
					sz
				]
			)
		)
	return flat


func _round_trip(rows_by_asset: Dictionary) -> Dictionary:
	var typed: Dictionary[String, PackedFloat32Array] = {}
	typed.assign(rows_by_asset)
	var warnings := MapDocumentIO._WarningLog.new()
	var back := MapRowsCodec.decode_rows(
		MapRowsCodec.encode_rows(typed), MapDocumentIO.MAX_TOTAL_ROWS, "rows", warnings
	)
	assert_eq(warnings.result(), PackedStringArray(), "a written entry reads clean")
	return back


func test_snapped_random_rows_round_trip_bit_for_bit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026
	var all := {}
	for k in 12:
		var flat := _random_rows(rng, 500 + k * 311)
		MapDocumentIO.snap_rows(flat)
		all["pkg/Asset_%02d" % k] = flat
	var back := _round_trip(all)
	assert_eq(back.size(), all.size())
	for asset_id: String in all:
		assert_true(back[asset_id] == all[asset_id], "%s: every value equal" % asset_id)


func test_unsnapped_rows_come_back_snapped_within_half_a_step() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var flat := _random_rows(rng, 4000)
	var back: PackedFloat32Array = _round_trip({"a/b": flat})["a/b"]
	var snapped := flat.duplicate()
	MapDocumentIO.snap_rows(snapped)
	assert_true(back == snapped, "what comes back is what snap_rows makes")
	var worst_position := 0.0
	var worst_angle := 0.0
	var worst_scale := 0.0
	for start in range(0, flat.size(), STRIDE):
		for k in 3:
			worst_position = maxf(worst_position, absf(back[start + k] - flat[start + k]))
		var was := Quaternion(flat[start + 3], flat[start + 4], flat[start + 5], flat[start + 6])
		var now := Quaternion(back[start + 3], back[start + 4], back[start + 5], back[start + 6])
		worst_angle = maxf(worst_angle, rad_to_deg(was.angle_to(now.normalized())))
		for k in range(7, 10):
			worst_scale = maxf(worst_scale, absf(back[start + k] - flat[start + k]) / flat[start + k])
	assert_lt(worst_position, MapDocumentIO.ROW_STEP * 0.5 + 1e-6, "position within half a step")
	assert_lt(worst_angle, 0.2, "rotation within 0.2 degrees")
	assert_lt(worst_scale, 0.0035, "scale within a step of its smallest value")


func test_snapping_is_idempotent() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var once := _random_rows(rng, 2000)
	MapDocumentIO.snap_rows(once)
	var twice := once.duplicate()
	MapDocumentIO.snap_rows(twice)
	assert_true(once == twice)
	var back: PackedFloat32Array = _round_trip({"a/b": once})["a/b"]
	MapDocumentIO.snap_rows(back)
	assert_true(back == once)


## Rotations on the edges of the fourth-component prediction: exact ties, w = 0, w < 0, the
## identity, a lean near 180 degrees.
func test_edge_rotations_round_trip() -> void:
	var rotations := [
		Quaternion(),
		Quaternion(0, 0.70710678, 0, 0.70710678),
		Quaternion(0.5, 0.5, 0.5, 0.5),
		Quaternion(1, 0, 0, 0),
		Quaternion(0, 0, -1, 0),
		Quaternion(0.6, 0, 0, -0.8),
		Quaternion(0, -0.28, 0, -0.96),
		Quaternion(0.99999, 0.002, 0, 0.001),
	]
	var flat := PackedFloat32Array()
	for rotation: Quaternion in rotations:
		flat.append_array(
			PackedFloat32Array(
				[-3.5, 0.25, 40.0, rotation.x, rotation.y, rotation.z, rotation.w, 1.0, 1.0, 1.0]
			)
		)
	MapDocumentIO.snap_rows(flat)
	var back: PackedFloat32Array = _round_trip({"a/b": flat})["a/b"]
	assert_true(back == flat)


func test_extreme_values_within_the_caps_round_trip() -> void:
	var limit := MapDocumentIO.MAX_ROW_COMPONENT
	var flat := PackedFloat32Array([limit, -limit, limit, 0, 0, 0, 1, 1, 1, 1])
	flat.append_array(PackedFloat32Array([-limit, 0, 0, 0, 1, 0, 0, -2, 0.5, limit]))
	flat.append_array(PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 0, 0, 0]))
	MapDocumentIO.snap_rows(flat)
	var back: PackedFloat32Array = _round_trip({"a/b": flat})["a/b"]
	assert_true(back == flat)


func test_an_empty_entry_and_an_asset_of_one_row() -> void:
	assert_true(_round_trip({}).is_empty())
	var one := PackedFloat32Array([1, 2, 3, 0, 0, 0, 1, 1, 1, 1])
	assert_true(_round_trip({"a/one": one})["a/one"] == one)


func test_the_entry_is_stable_and_small() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var flat := _random_rows(rng, 20000)
	MapDocumentIO.snap_rows(flat)
	var typed: Dictionary[String, PackedFloat32Array] = {"x/a": flat, "a/b": flat.slice(0, 1000)}
	var first := MapRowsCodec.encode_rows(typed)
	assert_true(first == MapRowsCodec.encode_rows(typed), "same rows, same bytes")
	assert_lt(first.size(), 21000 * 40, "under the 40 bytes of raw float32 rows")


# --- mass anchor offsets ---------------------------------------------------------------


func _offsets(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var flat := PackedFloat32Array()
	for i in count * 2:
		flat.append(MapAnchorsIO.snap(rng.randf_range(-6.0, 6.0)))
	return flat


func test_offsets_round_trip_bit_for_bit() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var all: Dictionary[String, PackedFloat32Array] = {}
	for k in 4:
		all["g/grass_%d" % k] = _offsets(rng, 3000 + k)
	all["g/far"] = PackedFloat32Array([MapAnchorsIO.MAX_OFFSET_M, -MapAnchorsIO.MAX_OFFSET_M, 0, 0])
	var warnings := MapDocumentIO._WarningLog.new()
	var back := MapRowsCodec.decode_offsets(
		MapRowsCodec.encode_offsets(all, MapAnchorsIO.STEP),
		MapAnchorsIO.STEP,
		MapAnchorsIO.MAX_OFFSET_M,
		"anchors",
		warnings
	)
	assert_eq(warnings.result(), PackedStringArray())
	assert_eq(back.size(), all.size())
	for asset_id: String in all:
		assert_true(back[asset_id] == all[asset_id], asset_id)


func test_hostile_offset_entries_do_not_crash() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var all: Dictionary[String, PackedFloat32Array] = {"g/a": _offsets(rng, 300)}
	var bytes := MapRowsCodec.encode_offsets(all, MapAnchorsIO.STEP)
	for cut in bytes.size():
		_decode_offsets(bytes.slice(0, cut))
	for round in 200:
		var damaged := bytes.duplicate()
		damaged[rng.randi_range(0, damaged.size() - 1)] = rng.randi_range(0, 255)
		var back := _decode_offsets(damaged)
		for asset_id: String in back:
			for value in back[asset_id]:
				assert_true(absf(value) <= MapAnchorsIO.MAX_OFFSET_M)


func _decode_offsets(bytes: PackedByteArray) -> Dictionary:
	var warnings := MapDocumentIO._WarningLog.new()
	return MapRowsCodec.decode_offsets(
		bytes, MapAnchorsIO.STEP, MapAnchorsIO.MAX_OFFSET_M, "anchors", warnings
	)
