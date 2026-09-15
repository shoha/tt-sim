extends GutTest

## Tests for BoardToken health mutators. A bare BoardToken.new() is enough here: heal,
## take_damage and revive touch only fields and signals, not the scene structure the
## factory builds.


func _make_token(max_health: int = 10) -> BoardToken:
	var token := BoardToken.new()
	# Silence the factory-misuse push_error: _enter_tree() only warns to catch a bare
	# BoardToken.new() in production code paths. These tests deliberately bypass the
	# factory (per the class doc, that warning is about scene structure these health
	# methods never touch), so mark it factory-created to avoid an unrelated
	# "Unexpected Errors" failure from GUT's push_error tracking.
	token._factory_created = true
	token.max_health = max_health
	token.current_health = max_health
	add_child_autofree(token)
	return token


func test_heal_on_dead_token_revives_with_the_healed_amount() -> void:
	var token := _make_token(10)
	token.take_damage(-10)
	assert_false(token.is_alive, "Setup: token should be dead after lethal damage")

	watch_signals(token)
	token.heal(4)

	assert_true(token.is_alive, "Healing a dead token must revive it")
	assert_eq(token.current_health, 4)
	assert_signal_emitted(token, "revived")


func test_heal_on_dead_token_clamps_to_max_health() -> void:
	var token := _make_token(10)
	token.take_damage(-10)

	token.heal(50)

	assert_true(token.is_alive)
	assert_eq(token.current_health, 10)


func test_heal_on_live_token_does_not_emit_revived() -> void:
	var token := _make_token(10)
	token.take_damage(-3)

	watch_signals(token)
	token.heal(2)

	assert_eq(token.current_health, 9)
	assert_signal_not_emitted(token, "revived")


func test_undo_style_heal_from_zero_restores_previous_health() -> void:
	# GameplayActionHistory undoes a lethal hit by calling heal(old - current), i.e.
	# heal(old_health) from 0. That must bring the token back at exactly old_health.
	var token := _make_token(30)
	token.take_damage(-30)

	token.heal(30 - token.current_health)

	assert_true(token.is_alive)
	assert_eq(token.current_health, 30)
