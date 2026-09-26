extends GutTest

## Unit tests for VersionGate, the same-version rule for joining a hosted game.


func test_equal_versions_have_no_mismatch() -> void:
	assert_eq(VersionGate.mismatch_message("0.1.28", "0.1.28"), "")


func test_different_versions_are_a_mismatch() -> void:
	assert_ne(VersionGate.mismatch_message("0.1.28", "0.1.27"), "")


func test_mismatch_message_names_both_versions() -> void:
	var message := VersionGate.mismatch_message("0.1.28", "0.1.27")
	assert_string_contains(message, "0.1.28")
	assert_string_contains(message, "0.1.27")


func test_newer_host_tells_the_player_to_update() -> void:
	var message := VersionGate.mismatch_message("0.1.28", "0.1.27")
	assert_string_contains(message, "Update TTSim")


func test_older_host_tells_the_player_the_host_must_update() -> void:
	var message := VersionGate.mismatch_message("0.1.27", "0.1.28")
	assert_string_contains(message, "host needs to update")


func test_dev_suffix_alone_is_a_mismatch() -> void:
	# Exact string equality: a dev build never joins a release of the same number.
	assert_ne(VersionGate.mismatch_message("0.1.28", "0.1.28-build.abc123"), "")


func test_empty_host_version_is_a_mismatch_worded_as_older() -> void:
	# A host from before the gate publishes no lobby version at all.
	var message := VersionGate.mismatch_message("", "0.1.28")
	assert_ne(message, "")
	assert_string_contains(message, "older version")
	assert_string_contains(message, "0.1.28")


func test_player_info_with_matching_version_is_accepted() -> void:
	var info := {"name": "Ann", VersionGate.PLAYER_INFO_KEY: "0.1.28"}
	assert_true(VersionGate.is_player_info_accepted(info, "0.1.28"))


func test_player_info_with_different_version_is_rejected() -> void:
	var info := {"name": "Ann", VersionGate.PLAYER_INFO_KEY: "0.1.27"}
	assert_false(VersionGate.is_player_info_accepted(info, "0.1.28"))


func test_player_info_without_version_is_rejected() -> void:
	# A client from before the gate sends only name and role.
	assert_false(VersionGate.is_player_info_accepted({"name": "Ann"}, "0.1.28"))


func test_player_info_with_non_string_version_is_rejected() -> void:
	var info := {"name": "Ann", VersionGate.PLAYER_INFO_KEY: 28}
	assert_false(VersionGate.is_player_info_accepted(info, "28"))


func test_reported_version_reads_string_or_empty() -> void:
	assert_eq(VersionGate.reported_version({VersionGate.PLAYER_INFO_KEY: "0.1.27"}), "0.1.27")
	assert_eq(VersionGate.reported_version({VersionGate.PLAYER_INFO_KEY: 5}), "")
	assert_eq(VersionGate.reported_version({}), "")
