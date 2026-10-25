extends GutTest

## The manager's Needs list in plain language (LibraryInstall.dependency_line through
## LibraryReasons and LibraryNames): "Needs the Core collection, version 1.0 or newer. You have
## 1.0.0-dev." for a met or too-old dependency, and the reason after a comma when it is missing,
## turned off or broken. No range syntax ("^1.0") and no id-and-range pair reaches the player.


func _line(state: String, extra: Dictionary = {}) -> String:
	var dep := {"id": "core", "version": "^1.0", "installed": "1.0.0-dev", "state": state}
	dep.merge(extra, true)
	return LibraryInstall.dependency_line(dep)


func test_a_met_dependency_says_what_the_player_has() -> void:
	assert_eq(
		_line(LibraryInstall.DEP_OK),
		"Needs the Core collection, version 1.0 or newer. You have 1.0.0-dev."
	)


func test_a_too_old_dependency_says_what_the_player_has() -> void:
	assert_eq(
		_line(LibraryInstall.DEP_UNMET, {"installed": "0.9.0"}),
		"Needs the Core collection, version 1.0 or newer. You have 0.9.0."
	)


func test_a_missing_turned_off_or_broken_dependency_says_why() -> void:
	assert_eq(
		_line(LibraryInstall.DEP_MISSING, {"installed": ""}),
		"Needs the Core collection, version 1.0 or newer, which is not installed."
	)
	assert_eq(
		_line(LibraryInstall.DEP_DISABLED),
		"Needs the Core collection, version 1.0 or newer, which is turned off."
	)
	assert_eq(
		_line(LibraryInstall.DEP_BROKEN),
		"Needs the Core collection, version 1.0 or newer, which has a problem of its own."
	)


func test_any_version_names_no_version_and_other_ranges_read_plainly() -> void:
	assert_eq(
		_line(LibraryInstall.DEP_MISSING, {"version": "*", "id": "zzfrost", "installed": ""}),
		"Needs the zzfrost collection, which is not installed."
	)
	assert_eq(LibraryReasons.version_words("^1.0"), "version 1.0 or newer")
	assert_eq(LibraryReasons.version_words(">=2.1.0"), "version 2.1.0 or newer")
	assert_eq(LibraryReasons.version_words(""), "")
	assert_eq(LibraryReasons.version_words("*"), "")
	assert_false("^" in _line(LibraryInstall.DEP_UNMET))
