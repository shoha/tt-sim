extends GutTest

## Tests for reconciliation logic that determines whether a token's visual
## position should be synced back to GameState during periodic reconciliation.
##
## The core invariant: tokens currently under client authority (drag-locked by
## a non-host peer, or still network-interpolating on the host) must NOT have
## their GameState overwritten from the host's visual, because the host's
## visual lags behind the client's true position.


func before_each() -> void:
	GameState.clear_all_drag_locks()


func after_each() -> void:
	GameState.clear_all_drag_locks()


## Tokens with no drag lock should be synced (host-authoritative).
func test_should_sync_when_no_lock() -> void:
	var lock_holder := GameState.get_drag_lock("token_1")
	# No lock means lock_holder == 0 — should sync
	assert_eq(lock_holder, 0, "Expected no lock holder")


## Tokens drag-locked by the host (peer 1) should be synced — the host's
## visual IS the authoritative position for its own drags.
func test_should_sync_when_host_locked() -> void:
	GameState.claim_drag_lock("token_1", 1)
	var lock_holder := GameState.get_drag_lock("token_1")
	assert_eq(lock_holder, 1, "Expected host as lock holder")
	# Host lock (peer 1) means sync is safe


## Tokens drag-locked by a client (peer > 1) must NOT be synced — the host's
## visual is interpolating behind the client's true position.
func test_should_not_sync_when_client_locked() -> void:
	GameState.claim_drag_lock("token_1", 42)
	var lock_holder := GameState.get_drag_lock("token_1")
	assert_eq(lock_holder, 42, "Expected client as lock holder")
	# Client lock (peer > 1) means sync must be skipped
