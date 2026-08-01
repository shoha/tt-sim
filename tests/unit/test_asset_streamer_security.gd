extends GutTest

## Regression tests for AssetManager.streamer.is_level_request_authorized() -- the check that
## stops a client from requesting any level map other than the one the host currently
## has active (see the path-traversal fix in autoloads/asset_streamer.gd). This is
## extracted as a static function specifically so it's unit-testable: AssetStreamer is a
## live autoload (can't be doubled -- see test_asset_manager_needs_download.gd for the
## established precedent), and its @rpc handler has no other externally observable side
## effect to assert against without a real second multiplayer peer.


func test_denied_when_no_level_is_active() -> void:
	assert_false(AssetManager.streamer.is_level_request_authorized("my_dungeon", ""))


func test_allowed_when_name_matches_active_level_exactly() -> void:
	assert_true(AssetManager.streamer.is_level_request_authorized("my_dungeon", "my_dungeon"))


func test_denied_when_name_does_not_match_active_level() -> void:
	assert_false(
		AssetManager.streamer.is_level_request_authorized("some_other_level", "my_dungeon")
	)


func test_traversal_prefix_that_sanitizes_to_the_active_name_is_correctly_allowed() -> void:
	# "../my_dungeon" sanitizes to "my_dungeon" (dots/slash stripped, underscore kept) --
	# identical to the real active level name. This is NOT a bypass: the sanitized result
	# is exactly the resource the host already intends to share, so serving it is correct,
	# not a vulnerability. The real defense is that sanitization can never be steered to
	# produce a DIFFERENT authorized-sounding name than what it deterministically strips to.
	assert_true(AssetManager.streamer.is_level_request_authorized("../my_dungeon", "my_dungeon"))


func test_denied_for_absolute_path_traversal() -> void:
	assert_false(
		AssetManager.streamer.is_level_request_authorized("../../../etc/passwd", "my_dungeon")
	)


func test_denied_when_traversal_payload_would_sanitize_to_a_different_active_level() -> void:
	# Guards against a coincidental match: sanitizing "../../etc/passwd" strips all
	# dots and slashes, producing "etcpasswd" -- confirm that specific collision case
	# is still denied unless the active level is actually named "etcpasswd".
	var sanitized := Paths.sanitize_level_name("../../etc/passwd")
	assert_false(
		AssetManager.streamer.is_level_request_authorized("../../etc/passwd", "my_dungeon")
	)
	assert_true(AssetManager.streamer.is_level_request_authorized("../../etc/passwd", sanitized))


func test_case_and_whitespace_variants_of_the_active_level_are_allowed() -> void:
	# sanitize_level_name() lowercases and converts spaces to underscores, so these are
	# legitimate equivalent spellings of the same active level, not a bypass attempt.
	assert_true(AssetManager.streamer.is_level_request_authorized("My Dungeon", "my_dungeon"))
	assert_true(AssetManager.streamer.is_level_request_authorized("MY_DUNGEON", "my_dungeon"))
