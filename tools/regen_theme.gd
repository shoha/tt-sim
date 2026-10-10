extends SceneTree

## Regenerates both Painted Table themes (themes/generated/paper_theme.tres and
## glass_theme.tres) from their leaf scripts by running the editor headlessly (the
## theme_gen_save_sync plugin only regenerates the leaf that is saved in the editor, and
## nothing when the shared base is edited).
## Run: godot --headless --editor --path . --script res://tools/regen_theme.gd --quit-after 3
## ProgrammaticTheme extends EditorScript, which can only be instantiated inside the editor, so
## --editor is required; this script's own quit() stops its SceneTree but not the surrounding
## editor process, so --quit-after is required to force the process to exit after generation.

const LEAVES := {
	"res://themes/paper_theme.gd": ThemeColors.PAPER_THEME_PATH,
	"res://themes/glass_theme.gd": ThemeColors.GLASS_THEME_PATH,
}


func _init() -> void:
	for script_path: String in LEAVES:
		_regenerate(script_path, LEAVES[script_path])
	print("themes regenerated")
	quit()


func _regenerate(script_path: String, theme_path: String) -> void:
	# ResourceSaver.save() (called by ProgrammaticTheme._run()) does not preserve the resource's
	# existing UID, so capture it beforehand and restore it afterward; scenes that reference a
	# theme by UID keep resolving on a fresh clone or CI with no .godot/ cache.
	var uid: int = ResourceLoader.get_resource_uid(theme_path)
	var theme_script: GDScript = load(script_path)
	var generator: Object = theme_script.new()
	generator.call("_run")
	if uid != ResourceUID.INVALID_ID:
		ResourceSaver.set_uid(theme_path, uid)
		print("kept uid: ", ResourceUID.id_to_text(uid), " for ", theme_path)
