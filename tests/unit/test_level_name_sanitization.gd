extends GutTest

## Regression tests for Paths.sanitize_level_name(), the defense used by
## AssetStreamer._rpc_request_asset() to stop a client-supplied level name from
## escaping user://levels/ via path traversal (see the path-traversal fix in
## autoloads/asset_streamer.gd). sanitize_level_name() uses a character
## whitelist (letters, digits, underscore, hyphen), so traversal sequences are
## not normalized -- they're stripped outright.


func test_strips_dot_dot_traversal_segments() -> void:
	var result := Paths.sanitize_level_name("../../etc/passwd")
	assert_false("." in result, "Dots must never survive sanitization")
	assert_false("/" in result, "Path separators must never survive sanitization")


func test_strips_windows_style_traversal() -> void:
	var result := Paths.sanitize_level_name("..\\..\\windows\\system32")
	assert_false("." in result)
	assert_false("\\" in result)


func test_strips_absolute_unix_path() -> void:
	var result := Paths.sanitize_level_name("/etc/passwd")
	assert_false("/" in result)


func test_strips_absolute_windows_path_with_drive_letter() -> void:
	var result := Paths.sanitize_level_name("C:\\Windows\\System32")
	assert_false(":" in result)
	assert_false("\\" in result)


func test_normal_level_name_survives_intact() -> void:
	var result := Paths.sanitize_level_name("my_dungeon")
	assert_eq(result, "my_dungeon")


func test_spaces_become_underscores() -> void:
	var result := Paths.sanitize_level_name("my dungeon")
	assert_eq(result, "my_dungeon")


func test_uppercase_is_lowercased() -> void:
	var result := Paths.sanitize_level_name("MyDungeon")
	assert_eq(result, "mydungeon")


func test_empty_string_falls_back_to_generated_name() -> void:
	var result := Paths.sanitize_level_name("")
	assert_true(result.begins_with("level_"), "Empty input should fall back to a generated name")


func test_purely_malicious_input_falls_back_to_generated_name() -> void:
	# After stripping all non-whitelisted characters, "../../.." leaves nothing behind.
	var result := Paths.sanitize_level_name("../../..")
	assert_true(
		result.begins_with("level_"), "Input that sanitizes to empty should fall back, not error"
	)


func test_shell_metacharacters_are_stripped() -> void:
	var result := Paths.sanitize_level_name("level; rm -rf /")
	assert_false(";" in result)
	assert_false("/" in result)


func test_resulting_path_stays_within_levels_dir() -> void:
	# End-to-end: whatever comes out of sanitize_level_name(), the resulting map
	# path must still resolve under Paths.LEVELS_DIR, never escaping it.
	var malicious_inputs := [
		"../../../etc/passwd",
		"..\\..\\..\\windows\\system32\\config",
		"/etc/shadow",
		"....//....//etc",
	]
	for input in malicious_inputs:
		var sanitized := Paths.sanitize_level_name(input)
		var map_path := Paths.get_level_map_path(sanitized)
		assert_true(
			map_path.begins_with(Paths.LEVELS_DIR),
			"Path for input '%s' escaped LEVELS_DIR: '%s'" % [input, map_path]
		)
