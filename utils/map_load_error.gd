class_name MapLoadError
extends RefCounted

## The player-facing error when a saved map will not open (UI_TASTE W3: what failed, why,
## and how to recover; W5: a level is a "map" to the player). LevelManager.load_level returns
## null for two reasons a player can act on: the map's folder or file is gone (deleted or moved
## outside the game) or it is there but will not read (a damaged or hand-edited save). Both
## recover the same way, by choosing another map; the reason tells them which it was.


const GONE := "%s could not be opened: it is no longer in your maps folder. Choose another map."
const DAMAGED := "%s could not be opened: its save file is damaged. Choose another map."


## The error for the map at `path`, named `map_name` (empty: "That map").
static func text(path: String, map_name: String = "") -> String:
	var subject := "“%s”" % map_name if not map_name.is_empty() else "That map"
	return (DAMAGED if exists(path) else GONE) % subject


## The same, for a map info dictionary as the title and the pickers carry ("path", "name").
static func for_info(info: Dictionary) -> String:
	return text(String(info.get("path", "")), String(info.get("name", "")))


## Whether anything is still at `path`: a level folder, its level.json or a legacy file.
static func exists(path: String) -> bool:
	if path.is_empty():
		return false
	var clean := path.rstrip("/")
	return DirAccess.dir_exists_absolute(clean) or FileAccess.file_exists(clean)
