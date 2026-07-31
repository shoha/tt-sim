extends GutTest

## Tests for GameplayActionHistory undo stack.

const TEST_TOKEN_ID := "test_token_1"


## Minimal stand-in for BoardToken's relevant public API. Used to verify that
## undo replays through a live token's real mutators (not just GameState),
## without standing up a full BoardToken scene tree.
class FakeToken:
	var current_health: int = 100
	var max_health: int = 100
	var is_visible_to_players: bool = true
	var heal_calls: Array[int] = []
	var take_damage_calls: Array[int] = []
	var set_max_health_calls: Array[int] = []
	var set_visible_calls: Array[bool] = []

	func heal(amount: int) -> void:
		heal_calls.append(amount)
		current_health = min(max_health, current_health + amount)

	func take_damage(amount: int) -> void:
		take_damage_calls.append(amount)
		current_health = max(0, current_health + amount)

	func set_max_health(new_max: int) -> void:
		set_max_health_calls.append(new_max)
		max_health = new_max

	func set_visible_to_players(is_visible_value: bool) -> void:
		set_visible_calls.append(is_visible_value)
		is_visible_to_players = is_visible_value


var _history: GameplayActionHistory


func before_each() -> void:
	_history = GameplayActionHistory.new()
	add_child(_history)
	_register_test_token(TEST_TOKEN_ID)


func after_each() -> void:
	_history.queue_free()
	GameState.remove_token_state(TEST_TOKEN_ID)


func _register_test_token(nid: String) -> void:
	var state := TokenState.new()
	state.network_id = nid
	state.current_health = 100
	state.max_health = 100
	state.is_visible_to_players = true
	state.is_alive = true
	GameState.register_token(state)


func test_empty_stack_cannot_undo() -> void:
	assert_false(_history.can_undo())
	assert_eq(_history.undo(), "")


func test_record_and_undo_property_change() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 80)
	assert_true(_history.can_undo())
	assert_eq(_history.get_count(), 1)


func test_undo_returns_description() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 80)
	var desc := _history.undo()
	assert_string_contains(desc, "damage")


func test_undo_pops_from_stack() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 80)
	_history.undo()
	assert_false(_history.can_undo())
	assert_eq(_history.get_count(), 0)


func test_max_history_evicts_oldest() -> void:
	for i in range(GameplayActionHistory.MAX_HISTORY + 5):
		_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 100 - i)
	assert_eq(_history.get_count(), GameplayActionHistory.MAX_HISTORY)


func test_clear_empties_stack() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 80)
	_history.record_property_change(TEST_TOKEN_ID, "is_visible_to_players", true, false)
	_history.clear()
	assert_false(_history.can_undo())
	assert_eq(_history.get_count(), 0)


func test_compound_action_records_as_one() -> void:
	var changes: Array[Dictionary] = [
		{
			"network_id": "t1",
			"property": "current_health",
			"old_value": 100,
			"new_value": 50,
			"description": "dealt 50 damage",
		},
		{
			"network_id": "t1",
			"property": "max_health",
			"old_value": 100,
			"new_value": 50,
			"description": "max HP change",
		},
	]
	_history.record_compound_property_change(changes)
	assert_eq(_history.get_count(), 1)


func test_removal_record_and_undo_emits_signal() -> void:
	var received := []
	_history.removal_undo_requested.connect(func(a: Dictionary) -> void: received.append(a))
	# Directly push a removal record (bypassing the BoardToken-based API)
	var removal_action := {
		"type": GameplayActionHistory.ActionType.TOKEN_REMOVAL,
		"network_id": TEST_TOKEN_ID,
		"token_state_dict": {},
		"pack_id": "test_pack",
		"asset_id": "test_asset",
		"variant_id": "default",
		"description": 'removed "Goblin"',
	}
	_history._push(removal_action)
	_history.undo()
	assert_eq(received.size(), 1)
	assert_eq(received[0].network_id, TEST_TOKEN_ID)


func test_visibility_description() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "is_visible_to_players", true, false)
	var desc := _history.undo()
	assert_eq(desc, "toggled visibility")


func test_heal_description() -> void:
	_history.record_property_change(TEST_TOKEN_ID, "current_health", 80, 100)
	var desc := _history.undo()
	assert_string_contains(desc, "healed")


func test_undo_applies_to_live_token_not_just_game_state() -> void:
	# Regression test: undo must mutate the live token through its real
	# public API (heal/take_damage/etc.), not just GameState's copy —
	# otherwise Ctrl+Z shows a toast but nothing visibly changes.
	var fake_token := FakeToken.new()
	fake_token.current_health = 80
	_history.set_token_lookup(
		func(nid: String): return fake_token if nid == TEST_TOKEN_ID else null
	)

	_history.record_property_change(TEST_TOKEN_ID, "current_health", 100, 80)
	_history.undo()

	assert_eq(fake_token.current_health, 100)
	assert_eq(fake_token.heal_calls, [20])


func test_undo_applies_visibility_to_live_token() -> void:
	var fake_token := FakeToken.new()
	fake_token.is_visible_to_players = false
	_history.set_token_lookup(
		func(nid: String): return fake_token if nid == TEST_TOKEN_ID else null
	)

	_history.record_property_change(TEST_TOKEN_ID, "is_visible_to_players", true, false)
	_history.undo()

	assert_true(fake_token.is_visible_to_players)
	assert_eq(fake_token.set_visible_calls, [true])
