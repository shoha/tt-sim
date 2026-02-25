extends GutTest

## Tests for GameState drag lock methods.


func after_each() -> void:
	GameState.clear_all_drag_locks()


func test_claim_lock_when_free_returns_true() -> void:
	var result = GameState.claim_drag_lock("token_1", 42)
	assert_true(result)


func test_claim_lock_when_free_stores_peer() -> void:
	GameState.claim_drag_lock("token_1", 42)
	assert_eq(GameState.get_drag_lock("token_1"), 42)


func test_claim_lock_when_occupied_returns_false() -> void:
	GameState.claim_drag_lock("token_1", 42)
	var result = GameState.claim_drag_lock("token_1", 99)
	assert_false(result)


func test_claim_lock_when_occupied_does_not_change_owner() -> void:
	GameState.claim_drag_lock("token_1", 42)
	GameState.claim_drag_lock("token_1", 99)
	assert_eq(GameState.get_drag_lock("token_1"), 42)


func test_get_lock_returns_zero_when_free() -> void:
	assert_eq(GameState.get_drag_lock("token_1"), 0)


func test_release_lock_clears_entry() -> void:
	GameState.claim_drag_lock("token_1", 42)
	GameState.release_drag_lock("token_1")
	assert_eq(GameState.get_drag_lock("token_1"), 0)


func test_release_lock_on_free_token_is_noop() -> void:
	GameState.release_drag_lock("token_1")  # must not crash
	assert_eq(GameState.get_drag_lock("token_1"), 0)


func test_clear_for_peer_removes_only_that_peers_locks() -> void:
	GameState.claim_drag_lock("token_1", 42)
	GameState.claim_drag_lock("token_2", 99)
	GameState.clear_drag_locks_for_peer(42)
	assert_eq(GameState.get_drag_lock("token_1"), 0)
	assert_eq(GameState.get_drag_lock("token_2"), 99)


func test_clear_all_locks_removes_everything() -> void:
	GameState.claim_drag_lock("token_1", 42)
	GameState.claim_drag_lock("token_2", 99)
	GameState.clear_all_drag_locks()
	assert_eq(GameState.get_drag_lock("token_1"), 0)
	assert_eq(GameState.get_drag_lock("token_2"), 0)
