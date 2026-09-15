extends SceneTree

## Regenerates themes/generated/dark_theme.tres from themes/dark_theme.gd
## without the editor (the theme_gen_save_sync plugin only runs on editor save).
## Run: godot --headless --path . --script res://tools/regen_theme.gd


func _init() -> void:
	var theme_script: GDScript = load("res://themes/dark_theme.gd")
	var generator: Object = theme_script.new()
	generator.call("_run")
	print("theme regenerated")
	quit()
