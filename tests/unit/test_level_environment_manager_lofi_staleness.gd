extends GutTest

## Regression test for the "stale lo-fi shader" bug: GameMap's lo-fi
## ShaderMaterial (owned by VisualEffectsController) is a single persistent
## resource reused across every level loaded in a GameMap's lifetime -- unlike
## WorldEnvironment and the sun light, which are always fully reconfigured on
## every apply_level_environment() call regardless of override emptiness.
##
## apply_level_environment() used to only call _game_map.apply_lofi_overrides()
## when level_data.lofi_overrides was non-empty. Since apply_lofi_overrides()
## only sets the keys present in the dict it's given, that meant a level with
## NO lofi_overrides never touched the shared material at all -- so it kept
## whatever a previous level (or a live edit-panel slider drag) last set,
## instead of resetting to Constants.LOFI_DEFAULTS. The fix always calls
## apply_lofi_overrides() with a fully merged (defaults + this level's
## overrides) dictionary, so every key is explicitly reset every load.


class FakeGameMap:
	extends Node

	var last_overrides: Dictionary = {}

	func apply_lofi_overrides(overrides: Dictionary) -> void:
		last_overrides = overrides


func test_apply_level_environment_resets_lofi_to_defaults_when_new_level_has_no_overrides() -> void:
	var manager := LevelEnvironmentManager.new()
	var game_map := FakeGameMap.new()
	manager.setup(game_map)
	var root := Node3D.new()

	# Level A: pixelation explicitly turned up (simulates a live edit or a
	# saved level with a nonzero pixelation override).
	var level_a := LevelData.new()
	level_a.lofi_overrides = {"pixelation": 0.05}
	manager.apply_level_environment(level_a, root)
	assert_eq(game_map.last_overrides.get("pixelation"), 0.05)

	# Level B: no overrides at all -- the shared material must reset
	# pixelation back to the default (0.0), not silently keep Level A's 0.05.
	var level_b := LevelData.new()
	manager.apply_level_environment(level_b, root)

	assert_eq(
		game_map.last_overrides.get("pixelation"),
		Constants.LOFI_DEFAULTS["pixelation"],
		"Level B has no lofi_overrides, so pixelation must reset to the default, not stay at Level A's 0.05"
	)

	root.free()
	game_map.free()


func test_apply_level_environment_merges_level_overrides_over_full_defaults() -> void:
	var manager := LevelEnvironmentManager.new()
	var game_map := FakeGameMap.new()
	manager.setup(game_map)
	var root := Node3D.new()

	var level_a := LevelData.new()
	level_a.lofi_overrides = {"pixelation": 0.05}
	manager.apply_level_environment(level_a, root)

	# Level B only overrides vignette_strength -- every other key (including
	# pixelation) must still come from Constants.LOFI_DEFAULTS, not be left
	# untouched or partially stale.
	var level_b := LevelData.new()
	level_b.lofi_overrides = {"vignette_strength": 0.5}
	manager.apply_level_environment(level_b, root)

	assert_eq(game_map.last_overrides.get("pixelation"), Constants.LOFI_DEFAULTS["pixelation"])
	assert_eq(game_map.last_overrides.get("vignette_strength"), 0.5)

	root.free()
	game_map.free()
