extends RefCounted

## Test cleanup that cannot reach outside its own scratch folder. Not a test file (GUT only
## collects test_*.gd); preload it as a const. Every recursive delete in the tests goes through
## `clear`: it refuses an empty, relative, `res://` or outside-the-user-folder path (Godot treats
## "" and "." as the working directory, which in a developer run is the project itself), only
## accepts `user://test_*` folders, and removes a link as itself, never its target.

const PREFIX := "user://test_"
const MAX_DEPTH := 32


## Removes the folder `path` and everything in it. A refused path is reported and left alone.
static func clear(path: String) -> void:
	if LibraryPaths.verify(path) != "" or not path.begins_with(PREFIX):
		printerr("ScratchDir: refusing to clear '%s'" % path)
		return
	_remove(path, 0)


static func _remove(path: String, depth: int) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for sub in dir.get_directories():
		var full := path.path_join(sub)
		if dir.is_link(full):
			DirAccess.remove_absolute(full)
		elif depth < MAX_DEPTH:
			_remove(full, depth + 1)
	for file_name in dir.get_files():
		var file_path := path.path_join(file_name)
		if not dir.is_link(file_path):
			dir.remove(file_name)
	DirAccess.remove_absolute(path)
