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
	var info := {
		"name": "Ann",
		VersionGate.PLAYER_INFO_KEY: "0.1.28",
		VersionGate.PLAYER_INFO_PROTOCOL_KEY: VersionGate.PROTOCOL,
	}
	assert_true(VersionGate.is_player_info_accepted(info, "0.1.28"))


func test_player_info_with_another_protocol_is_rejected() -> void:
	# Two dev builds of one version with different wire formats.
	var info := {
		"name": "Ann",
		VersionGate.PLAYER_INFO_KEY: "0.1.28",
		VersionGate.PLAYER_INFO_PROTOCOL_KEY: VersionGate.PROTOCOL - 1,
	}
	assert_false(VersionGate.is_player_info_accepted(info, "0.1.28"))
	info.erase(VersionGate.PLAYER_INFO_PROTOCOL_KEY)
	assert_false(VersionGate.is_player_info_accepted(info, "0.1.28"), "a build from before it")
	info[VersionGate.PLAYER_INFO_PROTOCOL_KEY] = str(VersionGate.PROTOCOL)
	assert_false(VersionGate.is_player_info_accepted(info, "0.1.28"), "a String is not trusted")


func test_reported_protocol_reads_int_or_zero() -> void:
	assert_eq(VersionGate.reported_protocol({VersionGate.PLAYER_INFO_PROTOCOL_KEY: 7}), 7)
	assert_eq(VersionGate.reported_protocol({VersionGate.PLAYER_INFO_PROTOCOL_KEY: "7"}), 0)
	assert_eq(VersionGate.reported_protocol({}), 0)


func test_lobby_protocol_parses_the_published_string() -> void:
	assert_eq(VersionGate.lobby_protocol("2"), 2)
	assert_eq(VersionGate.lobby_protocol(""), 0, "a host from before the number")
	assert_eq(VersionGate.lobby_protocol("x2"), 0)


func test_same_version_other_protocol_names_the_build_and_both_protocols() -> void:
	var message := VersionGate.mismatch_message("0.4.2", "0.4.2", 1, 2)
	assert_string_contains(message, "different build of TTSim 0.4.2")
	assert_string_contains(message, "network protocol 1, yours is 2")
	assert_string_contains(message, "same build")
	assert_eq(VersionGate.mismatch_message("0.4.2", "0.4.2", 2, 2), "")


func test_a_host_without_a_protocol_is_worded_as_an_older_build() -> void:
	var message := VersionGate.mismatch_message("0.4.2", "0.4.2", 0, 2)
	assert_string_contains(message, "older build of TTSim 0.4.2")
	assert_string_contains(message, "before network protocol 2")


func test_a_version_difference_is_reported_before_the_protocol() -> void:
	var message := VersionGate.mismatch_message("0.4.3", "0.4.2", 1, 2)
	assert_string_contains(message, "Update TTSim")


func test_rejection_message_explains_an_equal_version_as_another_build() -> void:
	var message := VersionGate.rejection_message("0.4.2", "0.4.2")
	assert_string_contains(message, "different build of TTSim 0.4.2")
	assert_eq(
		VersionGate.rejection_message("0.4.3", "0.4.2"),
		VersionGate.mismatch_message("0.4.3", "0.4.2"),
		"a version difference keeps its own message"
	)


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
