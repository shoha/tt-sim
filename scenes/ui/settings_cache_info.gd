class_name SettingsCacheInfo
extends RefCounted

## The Network tab's "Cache size: ..." line: how much the downloaded-asset cache holds, split out
## of settings_menu.gd to keep that file under the lint budget.


## The two-line text of the cache caption: the cache's size, then what clearing does.
static func caption() -> String:
	return (
		"Cache size: %s\nClearing will force re-download of assets." % format_size(cache_size())
	)


## The bytes under the asset cache folder (0 when there is none).
static func cache_size() -> int:
	if not DirAccess.dir_exists_absolute(Paths.ASSET_CACHE_DIR):
		return 0
	return dir_size(Paths.ASSET_CACHE_DIR)


## The bytes of every file under `path`, hidden folders left out.
static func dir_size(path: String) -> int:
	var total_size := 0
	var dir := DirAccess.open(path)
	if not dir:
		return 0

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		var full_path := path + "/" + file_name
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				total_size += dir_size(full_path)
		else:
			var file := FileAccess.open(full_path, FileAccess.READ)
			if file:
				total_size += file.get_length()
				file.close()
		file_name = dir.get_next()
	dir.list_dir_end()

	return total_size


static func format_size(bytes: int) -> String:
	if bytes < 1024:
		return "%d B" % bytes
	if bytes < 1024 * 1024:
		return "%.1f KB" % (bytes / 1024.0)
	if bytes < 1024 * 1024 * 1024:
		return "%.1f MB" % (bytes / (1024.0 * 1024.0))
	return "%.1f GB" % (bytes / (1024.0 * 1024.0 * 1024.0))
