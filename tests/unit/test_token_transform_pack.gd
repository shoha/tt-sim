extends GutTest

## TokenTransformPack (card netspawn): the packed transform layout and the reconciliation's
## dirty set.


func _floats(x: float, yaw: float = 0.0) -> PackedFloat32Array:
	return TokenTransformPack.floats_of(Vector3(x, 0.5, -3.25), Vector3(0, yaw, 0), Vector3.ONE)


func _table(n: int) -> Dictionary:
	var out := {}
	for i in n:
		out["1762650000.%d_%d" % [i, i * 13]] = _floats(i * 1.5, i * 0.1)
	return out


# =============================================================================
# LAYOUT
# =============================================================================


func test_round_trip_is_exact_in_float32() -> void:
	var table := _table(5)
	var messages := TokenTransformPack.encode(table)
	assert_eq(messages.size(), 1)
	var back := TokenTransformPack.decode(messages[0])
	assert_eq(back.problem, "")
	assert_eq(back.transforms, table)


func test_entry_size_is_fixed_plus_the_id() -> void:
	var table := {"abc": _floats(1.0)}
	var bytes := TokenTransformPack.encode(table)[0]
	var expected := TokenTransformPack.HEADER_BYTES + TokenTransformPack.ENTRY_FIXED_BYTES + 3
	assert_eq(bytes.size(), expected)


func test_split_keeps_every_message_under_the_cap() -> void:
	var table := _table(200)
	var messages := TokenTransformPack.encode(table, TokenTransformPack.UNRELIABLE_BYTES)
	assert_gt(messages.size(), 1)
	var merged := {}
	for bytes in messages:
		assert_lte(bytes.size(), TokenTransformPack.UNRELIABLE_BYTES)
		var back := TokenTransformPack.decode(bytes)
		assert_eq(back.problem, "")
		merged.merge(back.transforms)
	assert_eq(merged, table, "every token in exactly one message")


func test_to_batch_has_the_transform_batch_shape() -> void:
	var batch := TokenTransformPack.to_batch({"a": _floats(2.0, 0.5)})
	assert_eq(batch.a.position, [2.0, 0.5, -3.25])
	assert_almost_eq(float(batch.a.rotation[1]), 0.5, 0.0001)
	assert_eq(batch.a.scale, [1.0, 1.0, 1.0])


func test_decode_refuses_malformed_bytes() -> void:
	var good := TokenTransformPack.encode(_table(2))[0]
	assert_ne(TokenTransformPack.decode(PackedByteArray()).problem, "", "empty")
	assert_ne(TokenTransformPack.decode(good.slice(0, good.size() - 1)).problem, "", "short")
	var trailing := good.duplicate()
	trailing.append(0)
	assert_ne(TokenTransformPack.decode(trailing).problem, "", "bytes past the last entry")
	var too_many := good.duplicate()
	too_many.encode_u16(1, TokenTransformPack.MAX_ENTRIES + 1)
	assert_ne(TokenTransformPack.decode(too_many).problem, "", "count past the cap")
	var nan := TokenTransformPack.encode({"a": _floats(NAN)})[0]
	assert_ne(TokenTransformPack.decode(nan).problem, "", "not finite")


# =============================================================================
# DIRTY SET
# =============================================================================


func test_dirty_set_sends_each_token_once_until_it_moves() -> void:
	var dirty := TokenTransformPack.DirtySet.new()
	var table := _table(3)
	assert_eq(dirty.take_changed(table).size(), 3, "first tick: everything is new")
	assert_true(dirty.take_changed(table).is_empty(), "at rest: nothing")
	var moved := table.duplicate()
	var key: String = table.keys()[1]
	moved[key] = _floats(40.0)
	assert_eq(dirty.take_changed(moved).keys(), [key], "only the moved token")


func test_dirty_set_ignores_movement_under_epsilon() -> void:
	var dirty := TokenTransformPack.DirtySet.new()
	dirty.take_changed({"a": _floats(1.0)})
	var nudged := _floats(1.0)
	nudged[0] += TokenTransformPack.EPSILON * 0.5
	assert_true(dirty.take_changed({"a": nudged}).is_empty())


func test_dirty_set_retain_forgets_removed_tokens() -> void:
	var dirty := TokenTransformPack.DirtySet.new()
	dirty.take_changed({"a": _floats(1.0), "b": _floats(2.0)})
	dirty.retain({"a": true})
	assert_eq(dirty.size(), 1)
	assert_eq(dirty.take_changed({"b": _floats(2.0)}).keys(), ["b"], "re-added: sent again")


func test_mark_sent_counts_a_full_state_as_sent() -> void:
	var dirty := TokenTransformPack.DirtySet.new()
	dirty.mark_sent({"a": _floats(1.0)})
	assert_true(dirty.take_changed({"a": _floats(1.0)}).is_empty())
