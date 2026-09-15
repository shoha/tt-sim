extends SceneTree

## Regenerates themes/generated/dark_theme.tres from themes/dark_theme.gd
## without the editor (the theme_gen_save_sync plugin only runs on editor save).
## Run: godot --headless --editor --path . --script res://tools/regen_theme.gd --quit-after 3
## ProgrammaticTheme extends EditorScript, which can only be instantiated inside the editor, so
## --editor is required; this script's own quit() stops its SceneTree but not the surrounding
## editor process, so --quit-after is required to force the process to exit after generation.


func _init() -> void:
	var theme_script: GDScript = load("res://themes/dark_theme.gd")
	var generator: Object = theme_script.new()
	generator.call("_run")
	print("theme regenerated")
	quit()
