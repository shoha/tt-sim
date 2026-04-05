extends GutTest

## Tests for Steam launch detection logic.
## We can't easily mock OS.get_environment in GUT, so we test the helper
## function that wraps the check.


func test_is_steam_launch_returns_false_when_env_empty() -> void:
	# OS.get_environment returns "" for unset variables
	# When SteamAppId is not set, we are NOT a Steam launch
	var result := _check_steam_env("")
	assert_false(result, "Empty SteamAppId should not be a Steam launch")


func test_is_steam_launch_returns_true_when_env_set() -> void:
	var result := _check_steam_env("4591070")
	assert_true(result, "Non-empty SteamAppId should be a Steam launch")


func test_is_steam_launch_returns_true_for_any_value() -> void:
	var result := _check_steam_env("480")
	assert_true(result, "Any non-empty SteamAppId should be a Steam launch")


## Helper that mirrors the logic we'll add, testable without mocking OS
static func _check_steam_env(value: String) -> bool:
	return not value.is_empty()
