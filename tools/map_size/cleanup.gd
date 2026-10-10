extends SceneTree

## Map-size measurement (see README.md): deletes its outputs (user://_msize_/,
## user://render_jobs/_msize_/ and the size sweep's user://levels/_psize_* levels), nothing
## else.

const LEVELS_DIR := "user://levels"
const LEVEL_PREFIX := "_psize_"


func _init() -> void:
	for dir_path in ["user://_msize_", "user://render_jobs/_msize_"]:
		if DirAccess.dir_exists_absolute(dir_path):
			_remove_tree(dir_path)
			print("MS| removed %s exists now %s" % [dir_path, str(DirAccess.dir_exists_absolute(dir_path))])
	var levels := DirAccess.open(LEVELS_DIR)
	if levels != null:
		for folder in levels.get_directories():
			if folder.begins_with(LEVEL_PREFIX):
				_remove_tree(LEVELS_DIR.path_join(folder))
				print("MS| removed level %s" % folder)
	quit()


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
