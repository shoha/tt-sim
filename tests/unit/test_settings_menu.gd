extends GutTest

## Unit tests for SettingsMenu's pure renderer-method helpers
## (scenes/ui/settings_menu.gd). The RenderingServer/relaunch-process-spawning
## path is not covered here -- not meaningfully testable headlessly, and
## dangerous to even try (a test that accidentally invoked the real relaunch
## path would spawn processes during CI). See the design spec's manual smoke
## test for that coverage.


func test_rendering_method_values_round_trip_for_every_item() -> void:
	for i in range(SettingsMenu._RENDERING_METHOD_VALUES.size()):
		var value := SettingsMenu._RENDERING_METHOD_VALUES[i]
		assert_eq(SettingsMenu._RENDERING_METHOD_VALUES.find(value), i)


func test_rendering_method_values_has_the_exact_required_order() -> void:
	assert_eq(SettingsMenu._RENDERING_METHOD_VALUES[0], "")
	assert_eq(SettingsMenu._RENDERING_METHOD_VALUES[1], "forward_plus")
	assert_eq(SettingsMenu._RENDERING_METHOD_VALUES[2], "mobile")
	assert_eq(SettingsMenu._RENDERING_METHOD_VALUES[3], "gl_compatibility")
	assert_eq(SettingsMenu._RENDERING_METHOD_VALUES.size(), 4)


func test_needs_relaunch_is_false_for_default() -> void:
	assert_false(SettingsMenu._rendering_method_needs_relaunch("", "forward_plus"))
	assert_false(SettingsMenu._rendering_method_needs_relaunch("", "mobile"))


func test_needs_relaunch_is_false_when_already_matching() -> void:
	assert_false(SettingsMenu._rendering_method_needs_relaunch("mobile", "mobile"))


func test_needs_relaunch_is_true_when_mismatched() -> void:
	assert_true(SettingsMenu._rendering_method_needs_relaunch("forward_plus", "mobile"))


func test_build_relaunch_args_appends_when_no_existing_flag() -> void:
	var args := PackedStringArray(["--fullscreen"])
	var result := SettingsMenu._build_relaunch_args(args, "mobile")
	assert_eq(
		result,
		PackedStringArray(
			[
				"--fullscreen",
				"--rendering-method",
				"mobile",
				"--",
				SettingsMenu._RELAUNCH_SENTINEL_ARG,
			]
		),
	)


func test_build_relaunch_args_replaces_existing_flag() -> void:
	var args := PackedStringArray(["--rendering-method", "forward_plus", "--fullscreen"])
	var result := SettingsMenu._build_relaunch_args(args, "mobile")
	assert_eq(
		result,
		PackedStringArray(
			[
				"--fullscreen",
				"--rendering-method",
				"mobile",
				"--",
				SettingsMenu._RELAUNCH_SENTINEL_ARG,
			]
		),
	)


func test_build_relaunch_args_preserves_other_flags_and_order() -> void:
	var args := PackedStringArray(
		["--quit-after", "1", "--rendering-method", "mobile", "--verbose"]
	)
	var result := SettingsMenu._build_relaunch_args(args, "gl_compatibility")
	assert_eq(
		result,
		PackedStringArray(
			[
				"--quit-after",
				"1",
				"--verbose",
				"--rendering-method",
				"gl_compatibility",
				"--",
				SettingsMenu._RELAUNCH_SENTINEL_ARG,
			]
		),
	)


func test_build_relaunch_args_handles_existing_flag_at_the_very_end() -> void:
	var args := PackedStringArray(["--fullscreen", "--rendering-method", "forward_plus"])
	var result := SettingsMenu._build_relaunch_args(args, "mobile")
	assert_eq(
		result,
		PackedStringArray(
			[
				"--fullscreen",
				"--rendering-method",
				"mobile",
				"--",
				SettingsMenu._RELAUNCH_SENTINEL_ARG,
			]
		),
	)


func test_build_relaunch_args_appends_sentinel_exactly_once() -> void:
	var args := PackedStringArray(["--rendering-method", "forward_plus"])
	var result := SettingsMenu._build_relaunch_args(args, "mobile")
	var sentinel_count := 0
	for arg in result:
		if arg == SettingsMenu._RELAUNCH_SENTINEL_ARG:
			sentinel_count += 1
	assert_eq(sentinel_count, 1)


func test_active_rendering_method_is_a_known_nonempty_value() -> void:
	var active := SettingsMenu._get_active_rendering_method()
	assert_true(active != "")
	assert_true(SettingsMenu._RENDERING_METHOD_VALUES.has(active))
