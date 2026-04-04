extends GutTest

## Tests for the LobbyCode base-36 encode/decode utility.


func test_encode_returns_nonempty_string() -> void:
	var result := LobbyCode.encode(109775241895133184)
	assert_typeof(result, TYPE_STRING)
	assert_true(result.length() > 0, "Encoded string should not be empty")


func test_decode_reverses_encode() -> void:
	var lobby_id := 109775241895133184
	var encoded := LobbyCode.encode(lobby_id)
	var decoded := LobbyCode.decode(encoded)
	assert_eq(decoded, lobby_id)


func test_decode_is_case_insensitive() -> void:
	var lobby_id := 109775241895133184
	var encoded := LobbyCode.encode(lobby_id)
	var upper := encoded.to_upper()
	var lower := encoded.to_lower()
	assert_eq(LobbyCode.decode(upper), lobby_id)
	assert_eq(LobbyCode.decode(lower), lobby_id)


func test_decode_invalid_returns_negative() -> void:
	assert_eq(LobbyCode.decode("!!!invalid!!!"), -1)
	assert_eq(LobbyCode.decode(""), -1)


func test_encode_zero() -> void:
	assert_eq(LobbyCode.encode(0), "0")
	assert_eq(LobbyCode.decode("0"), 0)


func test_encode_small_values() -> void:
	assert_eq(LobbyCode.encode(35), "z")
	assert_eq(LobbyCode.encode(36), "10")


func test_roundtrip_various_ids() -> void:
	var ids := [1, 100, 999999, 76561198000000000, 109775241895133184]
	for id in ids:
		var encoded := LobbyCode.encode(id)
		var decoded := LobbyCode.decode(encoded)
		assert_eq(decoded, id, "Roundtrip failed for id=%d, encoded='%s'" % [id, encoded])
