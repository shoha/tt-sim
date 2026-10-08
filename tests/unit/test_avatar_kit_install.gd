extends GutTest

## tools/install_avatar_kit.gd's guard (docs/ASSET_PIPELINE.md section 10, Install): only a
## kit built with figurine's full check ships; iteration builds are refused before any copy.

const Installer := preload("res://tools/install_avatar_kit.gd")


func test_a_full_build_installs() -> void:
	assert_eq(Installer.refusal('{"check": "full", "parts": 12}'), "")


func test_a_report_without_the_check_field_still_installs() -> void:
	assert_eq(Installer.refusal('{"parts": 12}'), "", "a build from before the field")
	assert_eq(Installer.refusal(""), "", "no build_report.json at all")


func test_iteration_builds_are_refused() -> void:
	for check in ["fast", "incremental", "fast+incremental"]:
		var why := Installer.refusal('{"check": "%s"}' % check)
		assert_string_contains(why, check, "refused: %s" % check)


func test_a_report_that_is_not_an_object_is_refused() -> void:
	assert_ne(Installer.refusal("not json"), "")
	assert_ne(Installer.refusal("[1, 2]"), "")
