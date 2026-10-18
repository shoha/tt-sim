extends RefCounted

## Render-job probe (`call` op) for the game's glow (EnvironmentGlow; jobs firefeat_glow and
## firefeat_look_mobile). Actions:
##   env {preset, overrides}  applies `preset` ("" the level's own) with `overrides` as the Sky and
##                     Color panes do, so a capture shows a level override (the Glow slider)
##   report            every WorldEnvironment's glow as Godot holds it, and the renderer
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


static func _cleanup(folder: String) -> String:
	if not folder in FOLDERS:
		return "refused: %s is not one of %s" % [folder, str(FOLDERS)]
	var path := LevelManager.folder_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		return "no %s" % folder
	return "removed %s: %s" % [folder, str(LevelManager.delete_level_folder(path))]
