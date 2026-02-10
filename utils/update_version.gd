class_name UpdateVersion

## Version parsing and comparison utilities for the update system.
## Handles semantic versioning with support for dev builds (0.0.0-build.abc123).


## Get the current application version from project settings
static func get_current() -> String:
	return ProjectSettings.get_setting("application/config/version", "0.0.0-dev")


## Check if a version is a dev build (contains "build." in suffix)
static func is_dev_build(version: String) -> bool:
	return "-build." in version or version.begins_with("build.")


## Compare two semantic versions.
## Returns true if version_a is newer than version_b.
static func is_newer(version_a: String, version_b: String) -> bool:
	var parts_a = parse(version_a)
	var parts_b = parse(version_b)

	# Compare major.minor.patch
	for i in range(3):
		if parts_a[i] > parts_b[i]:
			return true
		elif parts_a[i] < parts_b[i]:
			return false

	# Same base version — check prerelease suffix
	# A release version (no suffix) is newer than a prerelease
	var suffix_a = parts_a[3]
	var suffix_b = parts_b[3]

	if suffix_a.is_empty() and not suffix_b.is_empty():
		return true  # a is release, b is prerelease
	if not suffix_a.is_empty() and suffix_b.is_empty():
		return false  # a is prerelease, b is release

	# Both have suffixes or both don't — compare lexically
	return suffix_a > suffix_b


## Parse a version string into [major, minor, patch, suffix].
## Handles formats: "1.2.3-beta", "1.2.3", "0.0.0-build.abc123"
static func parse(version: String) -> Array:
	var suffix = ""
	var base = version

	var dash_pos = version.find("-")
	if dash_pos >= 0:
		base = version.substr(0, dash_pos)
		suffix = version.substr(dash_pos + 1)

	var parts = base.split(".")
	var major = int(parts[0]) if parts.size() > 0 else 0
	var minor = int(parts[1]) if parts.size() > 1 else 0
	var patch = int(parts[2]) if parts.size() > 2 else 0

	return [major, minor, patch, suffix]


## Normalize a release tag into a version string.
##   "v1.0.0" -> "1.0.0"
##   "build-abc123" -> "0.0.0-build.abc123"
static func normalize_tag(tag: String) -> String:
	if tag.begins_with("v"):
		return tag.substr(1)
	elif tag.begins_with("build-"):
		return "0.0.0-build." + tag.substr(6)
	return tag


## Get the platform name for asset matching in release assets.
static func get_platform_name() -> String:
	match OS.get_name():
		"Windows":
			return "windows"
		"macOS":
			return "macos"
		"Linux":
			return "linux"
		_:
			return OS.get_name().to_lower()
