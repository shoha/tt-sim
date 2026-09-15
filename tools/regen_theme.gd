extends SceneTree

## Regenerates themes/generated/dark_theme.tres from themes/dark_theme.gd by running the
## editor headlessly (the theme_gen_save_sync plugin only regenerates on an editor save).
## Run: godot --headless --editor --path . --script res://tools/regen_theme.gd --quit-after 3
## ProgrammaticTheme extends EditorScript, which can only be instantiated inside the editor, so
## --editor is required; this script's own quit() stops its SceneTree but not the surrounding
## editor process, so --quit-after is required to force the process to exit after generation.

const THEME_PATH: String = "res://themes/generated/dark_theme.tres"


func _init() -> void:
	# ResourceSaver.save() (called by ProgrammaticTheme._run()) does not preserve the resource's
	# existing UID, so capture it beforehand and restore it afterward. Without this,
	# project.godot's `theme/custom="uid://..."` reference breaks on a fresh clone or CI where
	# there is no .godot/ cache to fall back on.
	var uid: int = ResourceLoader.get_resource_uid(THEME_PATH)

	# One-time bootstrap: if the saved resource has no UID yet (as happened when this bug first
	# shipped), recover it from project.godot's `gui/theme/custom` setting, which is the
	# authoritative pointer to what UID this file must keep.
	if uid == ResourceUID.INVALID_ID:
		var expected_uid_text: String = ProjectSettings.get_setting("gui/theme/custom", "")
		if expected_uid_text.begins_with("uid://"):
			uid = ResourceUID.text_to_id(expected_uid_text)

	var theme_script: GDScript = load("res://themes/dark_theme.gd")
	var generator: Object = theme_script.new()
	generator.call("_run")

	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(THEME_PATH, uid)
		print("kept uid: ", ResourceUID.id_to_text(uid))

	print("theme regenerated")
	quit()
