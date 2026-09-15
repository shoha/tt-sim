extends GutTest

## TokenSpawner wires token signals to one property handler for GameState sync and
## network broadcast. died/revived must not be wired: health_changed already fires
## with is_alive in its final state, so wiring both produced two syncs (and on a host,
## two reliable RPCs) per death or revive.

const TOKEN_ID := "wiring_token"


func after_each() -> void:
	GameState.remove_token_state(TOKEN_ID)


func test_died_and_revived_are_not_wired_to_the_property_handler() -> void:
	var spawner := TokenSpawner.new()
	var token := BoardToken.new()
	token._factory_created = true
	token.network_id = TOKEN_ID
	add_child_autofree(token)

	spawner._connect_token_state_signals(token)

	assert_eq(token.health_changed.get_connections().size(), 1)
	assert_eq(token.died.get_connections().size(), 0)
	assert_eq(token.revived.get_connections().size(), 0)

	spawner._disconnect_token_state_signals(token)
	assert_eq(token.health_changed.get_connections().size(), 0)
