extends GutTest

## TokenStateWire (card netspawn): the compressed token state message, its chunks, and the
## add path's idempotence in GameState (upsert_state_dict against merge_full_state_dict).


func before_each() -> void:
	GameState.clear_all_tokens()


func after_each() -> void:
	GameState.clear_all_tokens()


func _token(network_id: String, x: float = 1.0) -> Dictionary:
	var state := TokenState.new()
	state.network_id = network_id
	state.pack_id = "core"
	state.asset_id = "goblin"
	state.token_name = "Goblin " + network_id
	state.position = Vector3(x, 0.5, -2.0)
	return state.to_dict()


func _state(ids: Array, permissions: Dictionary = {}) -> Dictionary:
	var tokens := {}
	for network_id: String in ids:
		tokens[network_id] = _token(network_id)
	return {"tokens": tokens, "permissions": permissions}


# =============================================================================
# ENCODING
# =============================================================================


func test_full_and_add_round_trip() -> void:
	var state := _state(["a", "b"], {"a": {"2": [0]}})
	for kind in [TokenStateWire.Kind.FULL, TokenStateWire.Kind.ADD]:
		var back := TokenStateWire.decode(TokenStateWire.encode(state, kind))
		assert_eq(back.problem, "")
		assert_eq(back.kind, kind)
		assert_eq(back.state, state)


func test_encoding_is_smaller_than_the_variant() -> void:
	var ids: Array = []
	for i in 50:
		ids.append("1762650000.%d_%d" % [i, i * 7])
	var state := _state(ids)
	var wire := TokenStateWire.encode(state, TokenStateWire.Kind.FULL)
	assert_lt(wire.size() * 5, var_to_bytes(state).size(), "50 tokens compress at least 5x")


func test_decode_refuses_malformed_bytes() -> void:
	var good := TokenStateWire.encode(_state(["a"]), TokenStateWire.Kind.FULL)
	assert_ne(TokenStateWire.decode(PackedByteArray()).problem, "", "empty")
	var header_only := good.slice(0, TokenStateWire.HEADER_BYTES)
	assert_ne(TokenStateWire.decode(header_only).problem, "", "no payload")
	var bad_format := good.duplicate()
	bad_format[0] = TokenStateWire.FORMAT + 1
	assert_ne(TokenStateWire.decode(bad_format).problem, "", "format")
	var bad_kind := good.duplicate()
	bad_kind[1] = 9
	assert_ne(TokenStateWire.decode(bad_kind).problem, "", "kind")
	var huge := good.duplicate()
	huge.encode_u32(2, TokenStateWire.MAX_RAW_BYTES + 1)
	assert_ne(TokenStateWire.decode(huge).problem, "", "raw size past the cap")


func test_decode_refuses_a_value_that_is_no_state() -> void:
	var raw := var_to_bytes([1, 2, 3])
	var bytes := PackedByteArray([TokenStateWire.FORMAT, TokenStateWire.Kind.FULL, 0, 0, 0, 0])
	bytes.encode_u32(2, raw.size())
	bytes.append_array(raw.compress(TokenStateWire.COMPRESSION))
	assert_eq(TokenStateWire.decode(bytes).problem, "not a state")


# =============================================================================
# CHUNKS
# =============================================================================


func _noise(size: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var out := PackedByteArray()
	out.resize(size)
	for i in size:
		out[i] = rng.randi() & 255
	return out


func test_chunks_split_at_the_cap_and_reassemble() -> void:
	var bytes := _noise(TokenStateWire.CHUNK_BYTES * 3 + 17)
	var parts := TokenStateWire.chunks(bytes)
	assert_eq(parts.size(), 4)
	for part in parts:
		assert_lte(part.size(), TokenStateWire.CHUNK_BYTES)
	var assembler := TokenStateWire.Assembler.new()
	var whole := PackedByteArray()
	for i in parts.size():
		whole = assembler.add(5, i, parts.size(), parts[i])
		assert_eq(assembler.problem, "")
		assert_eq(whole.is_empty(), i < parts.size() - 1)
	assert_eq(whole, bytes)


func test_assembler_refuses_out_of_order_and_oversized_runs() -> void:
	var parts := TokenStateWire.chunks(_noise(TokenStateWire.CHUNK_BYTES * 2))
	var assembler := TokenStateWire.Assembler.new()
	assembler.add(1, 0, 2, parts[0])
	assembler.add(2, 1, 2, parts[1])
	assert_ne(assembler.problem, "", "a chunk of another message")
	assembler.add(3, 0, TokenStateWire.MAX_CHUNKS + 1, parts[0])
	assert_ne(assembler.problem, "", "too many chunks")
	assembler.add(4, 0, 1, _noise(TokenStateWire.CHUNK_BYTES + 1))
	assert_ne(assembler.problem, "", "a chunk past the cap")
	var whole := assembler.add(6, 0, 1, parts[0])
	assert_eq(assembler.problem, "", "a fresh message starts clean after a refusal")
	assert_eq(whole, parts[0])


# =============================================================================
# IDEMPOTENT ADD
# =============================================================================


func test_an_add_applied_twice_holds_one_token() -> void:
	var added: Array = []
	var on_added := func(network_id: String, _state: TokenState) -> void: added.append(network_id)
	GameState.token_added.connect(on_added)
	GameState.upsert_state_dict(_state(["x"]))
	GameState.upsert_state_dict(_state(["x"]))
	GameState.token_added.disconnect(on_added)
	assert_eq(GameState.get_token_count(), 1)
	assert_eq(added, ["x"], "token_added once")


func test_an_add_after_a_full_state_with_the_token_changes_nothing_twice() -> void:
	GameState.apply_full_state_dict(_state(["x", "y"]))
	var ids := GameState.upsert_state_dict(_state(["x"]))
	assert_eq(ids, ["x"] as Array[String])
	assert_eq(GameState.get_token_count(), 2)


func test_an_add_before_the_full_state_that_includes_it_keeps_it() -> void:
	GameState.apply_full_state_dict(_state(["x"]))
	GameState.upsert_state_dict(_state(["y"]))
	GameState.merge_full_state_dict(_state(["x", "y"]))
	assert_true(GameState.has_token("x"))
	assert_true(GameState.has_token("y"))
	assert_eq(GameState.get_token_count(), 2)


func test_an_add_does_not_remove_other_tokens() -> void:
	GameState.apply_full_state_dict(_state(["x", "y"]))
	GameState.upsert_state_dict(_state(["z"]))
	assert_eq(GameState.get_token_count(), 3)


func test_an_add_carries_its_tokens_permissions_only() -> void:
	GameState.apply_full_state_dict(_state(["x"], {"x": {"3": [0]}}))
	GameState.upsert_state_dict(_state(["z"], {"z": {"2": [0]}}))
	var control := TokenPermissions.Permission.CONTROL
	assert_true(GameState.has_token_permission("z", 2, control))
	assert_true(GameState.has_token_permission("x", 3, control), "another token's grant stays")


func test_tokens_state_dict_is_the_full_states_entry() -> void:
	var state := TokenState.from_dict(_token("x"))
	GameState.set_token_state("x", state)
	GameState.set_token_state("y", TokenState.from_dict(_token("y", 4.0)))
	GameState.grant_token_permission("x", 2, TokenPermissions.Permission.CONTROL)
	var full := GameState.get_full_state_dict()
	var one := GameState.get_tokens_state_dict(["x", "missing"])
	assert_eq(one.tokens.keys(), ["x"])
	assert_eq(one.tokens.x, full.tokens.x)
	assert_eq(one.permissions, full.permissions)
