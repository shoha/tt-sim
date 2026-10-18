extends RefCounted

## Render-job probe (`call` op) for the game's glow (EnvironmentGlow; jobs firefeat_glow and
## firefeat_look_mobile). Actions:
##   env {preset, overrides}  applies `preset` ("" the level's own) with `overrides` as the Sky and
##                     Color panes do, so a capture shows a level override (the Glow slider)
##   report            every WorldEnvironment's glow as Godot holds it, and the renderer
##   variant {variant, preset}  the glow alone switched in place on the live Environment, for an
##                     in-run A/B (job fire_c7b_glow): new (EnvironmentGlow, the game's own), old
##                     (main's glow before card C5b: the preset's intensity, strength and bloom over
##                     Godot's Environment defaults for the rest) or off; `preset` names the
##                     environment the shot key applied ("" the level's own, with its overrides),
##                     and a "#2" suffix on the variant is ignored (palindrome windows)
##   cleanup {folder}  deletes that one FOLDERS test level (fire.gd's cleanup deletes every
##                     _firefeat_ level, _firefeat_look included)

## The test levels this probe may delete.
const FOLDERS: Array[String] = ["_firefeat_glow"]
const KEYS: Array[String] = [
	"glow_enabled",
	"glow_intensity",
	"glow_strength",
	"glow_bloom",
	"glow_hdr_threshold",
	"glow_hdr_scale",
	"glow_blend_mode",
]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"report":
			return _report(base)
		"cleanup":
			return _cleanup(String(step.get("folder", "")))
		"variant":
			var variant := String(step.get("variant", "new")).get_slice("#", 0)
			return _variant(base, variant, String(step.get("preset", "")))
		"env":
			var ctrl: AuthoringController = base.get("_authoring_controller")
			if ctrl == null:
				return "no authoring controller"
			var manager: LevelEnvironmentManager = ctrl.get("_environment")
			if manager == null:
				return "no environment manager"
			var preset := String(step.get("preset", ""))
			var overrides: Dictionary = step.get("overrides", {})
			if preset == "":
				preset = ctrl.level.environment_preset
				var merged: Dictionary = ctrl.level.environment_overrides.duplicate()
				merged.merge(overrides, true)
				overrides = merged
			manager.apply_environment_settings(preset, overrides)
			return "env %s %s; %s" % [preset, str(overrides), _report(base)]
	return "unknown action"


static func _report(base: Node) -> String:
	var lines := PackedStringArray(["renderer %s" % RenderingServer.get_current_rendering_method()])
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		var line := PackedStringArray()
		for key: String in KEYS:
			line.append("%s %s" % [key.trim_prefix("glow_"), str(env.get(key))])
		var levels := PackedStringArray()
		for k in 7:
			levels.append("%.2f" % env.get_glow_level(k))
		line.append("levels [%s]" % ", ".join(levels))
		lines.append("%s: %s" % [node.name, ", ".join(line)])
	return "; ".join(lines)


## Sets glow variant `variant` (new, old, off) on the live Environment without re-applying the
## preset, so the sky, the sun and everything else stay as the shot left them. The config is the
## one the Sky pane resolves for `preset` ("" the level's own preset and overrides).
static func _variant(base: Node, variant: String, preset: String) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null:
		return "no authoring controller"
	var manager: LevelEnvironmentManager = ctrl.get("_environment")
	if manager == null:
		return "no environment manager"
	var world_env := manager.get("_world_environment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return "no environment"
	var overrides: Dictionary = {}
	if preset == "":
		preset = ctrl.level.environment_preset
		overrides = ctrl.level.environment_overrides
	var raw: Variant = manager.get("_map_environment_config")
	var map_defaults: Dictionary = raw if raw is Dictionary else {}
	var config := EnvironmentPresets.get_environment_config(preset, overrides, map_defaults)
	var env := world_env.environment
	match variant:
		"new":
			var reference := EnvironmentPresets.glow_reference(preset, map_defaults)
			EnvironmentGlow.apply(env, config, reference)
		"old":
			# What _apply_config_to_environment set before card C5b; the rest Godot's defaults.
			var defaults := Environment.new()
			env.glow_enabled = bool(config.get("glow_enabled", false))
			env.glow_intensity = float(config.get("glow_intensity", 0.8))
			env.glow_strength = float(config.get("glow_strength", 1.0))
			env.glow_bloom = float(config.get("glow_bloom", 0.0))
			env.glow_hdr_threshold = defaults.glow_hdr_threshold
			env.glow_hdr_scale = defaults.glow_hdr_scale
			env.glow_blend_mode = defaults.glow_blend_mode
			for k in 7:
				env.set_glow_level(k, defaults.get_glow_level(k))
		"off":
			env.glow_enabled = false
		_:
			return "unknown variant %s" % variant
	return "glow %s (%s); %s" % [variant, preset, _report(base)]


static func _cleanup(folder: String) -> String:
	if not folder in FOLDERS:
		return "refused: %s is not one of %s" % [folder, str(FOLDERS)]
	var path := LevelManager.folder_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		return "no %s" % folder
	return "removed %s: %s" % [folder, str(LevelManager.delete_level_folder(path))]
