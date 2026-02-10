extends GutTest

## Unit tests for UpdateVersion.


func test_parse_simple_version() -> void:
	var result = UpdateVersion.parse("1.2.3")
	assert_eq(result[0], 1)
	assert_eq(result[1], 2)
	assert_eq(result[2], 3)
	assert_eq(result[3], "")


func test_parse_version_with_suffix() -> void:
	var result = UpdateVersion.parse("1.0.0-beta")
	assert_eq(result[0], 1)
	assert_eq(result[1], 0)
	assert_eq(result[2], 0)
	assert_eq(result[3], "beta")


func test_parse_dev_build_version() -> void:
	var result = UpdateVersion.parse("0.0.0-build.abc123")
	assert_eq(result[0], 0)
	assert_eq(result[1], 0)
	assert_eq(result[2], 0)
	assert_eq(result[3], "build.abc123")


func test_is_newer_major() -> void:
	assert_true(UpdateVersion.is_newer("2.0.0", "1.0.0"))
	assert_false(UpdateVersion.is_newer("1.0.0", "2.0.0"))


func test_is_newer_minor() -> void:
	assert_true(UpdateVersion.is_newer("1.1.0", "1.0.0"))
	assert_false(UpdateVersion.is_newer("1.0.0", "1.1.0"))


func test_is_newer_patch() -> void:
	assert_true(UpdateVersion.is_newer("1.0.1", "1.0.0"))
	assert_false(UpdateVersion.is_newer("1.0.0", "1.0.1"))


func test_is_newer_release_beats_prerelease() -> void:
	# A release (no suffix) is newer than a prerelease with same base
	assert_true(UpdateVersion.is_newer("1.0.0", "1.0.0-beta"))
	assert_false(UpdateVersion.is_newer("1.0.0-beta", "1.0.0"))


func test_is_newer_same_version() -> void:
	assert_false(UpdateVersion.is_newer("1.0.0", "1.0.0"))


func test_is_dev_build() -> void:
	assert_true(UpdateVersion.is_dev_build("0.0.0-build.abc123"))
	assert_false(UpdateVersion.is_dev_build("1.0.0"))
	assert_false(UpdateVersion.is_dev_build("1.0.0-beta"))


func test_normalize_tag_v_prefix() -> void:
	assert_eq(UpdateVersion.normalize_tag("v1.0.0"), "1.0.0")


func test_normalize_tag_build_prefix() -> void:
	assert_eq(UpdateVersion.normalize_tag("build-abc123"), "0.0.0-build.abc123")


func test_normalize_tag_plain() -> void:
	assert_eq(UpdateVersion.normalize_tag("1.0.0"), "1.0.0")


func test_get_platform_name_not_empty() -> void:
	# Should always return something
	assert_ne(UpdateVersion.get_platform_name(), "")
