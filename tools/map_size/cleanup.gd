extends SceneTree

## Map-size measurement (see README.md): deletes its outputs (user://_msize_/ and
## user://render_jobs/_msize_/), nothing else.


func _init() -> void:
	for dir_path in ["user://_msize_", "user://render_jobs/_msize_"]:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for f in dir.get_files():
			DirAccess.remove_absolute("%s/%s" % [dir_path, f])
		DirAccess.remove_absolute(dir_path)
		print("MS| removed %s exists now %s" % [dir_path, str(DirAccess.dir_exists_absolute(dir_path))])
	quit()
