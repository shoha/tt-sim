extends "res://tools/render_jobs/run.gd"

## Renders the tiles of a library's structures with the real game (docs/systems/library.md
## "Structures"): one 512 px JPG per structure, `thumbnails/structures/<id>.jpg`, the building
## alone on an open meadow at the game camera (LibraryStructures.thumbnail_job), taken through the
## render-job harness so the picture shows tt-sim's own materials, light and ground. Windowed: it
## needs a GPU and a real window, never --headless. The same plan as render_library_thumbnails.gd,
## for the `structures/` kind.
##
##   godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120
##     --script res://tools/render_structure_thumbnails.gd -- --library <folder> [--out <folder>]
##     [--serve 1] [--only a,b] [--list 1]
##
## --library is a folder holding structures/index.json and library.json (core: tt-sim's
## `libraries/core`, which is already served). --out is the folder the tiles go to
## (thumbnails/structures/<id>.jpg inside it; default the --library folder; for core it is the
## core-library repo). --serve 1 lays --library over the game as the developer override first
## (a user library that is not installed; it must be a complete, servable library). --only draws
## the named structures. --list 1 prints the plan and writes nothing (works headless). A shipped
## folder (res://) is never written. Exit code 0 when every tile was written, 1 otherwise.

var _entries: Array[Dictionary] = []
var _destination: String = ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source := _folder_of(_option(args, "--library"))
	var dest := _folder_of(_option(args, "--out")) if _option(args, "--out") != "" else source
	var listing := _option(args, "--list") != ""
	var problem := _check(source, dest, listing)
	if problem != "":
		printerr("render_structure_thumbnails: %s" % problem)
		quit(2)
		return
	# The files are read here, not through LibraryRegistry: this script is compiled before the
	# autoloads exist, and the registry's dependencies use them (render_library_thumbnails.gd
	# keeps clear of it for the same reason).
	var recipes := {}
	for file_name in DirAccess.get_files_at(source.path_join("structures")):
		if file_name.ends_with(LibraryStructures.RECIPE_SUFFIX):
			recipes[file_name] = (
				FileAccess
				. get_file_as_string(source.path_join("structures").path_join(file_name))
				. replace("\r\n", "\n")
			)
	var index := FileAccess.get_file_as_string(source.path_join(LibraryStructures.INDEX_FILE))
	var read := {"warnings": [] as Array[String]}
	LibraryStructures.read(
		{"index": index.replace("\r\n", "\n"), "recipes": recipes}, [], false, read
	)
	for line: String in read["warnings"]:
		printerr("THUMBS| warning: %s" % line)
	var only := Array(_option(args, "--only").split(",", false))
	for item: Dictionary in read["structures"]:
		if only.is_empty() or String(item["id"]) in only:
			_entries.append(item)
	var library: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(source.path_join("library.json"))
	)
	var library_id := String((library as Dictionary).get("id", "")) if library is Dictionary else ""
	for item in _entries:
		print("THUMBS| plan %s -> %s" % [item["id"], LibraryStructures.thumb_path(item["id"])])
	if _entries.is_empty():
		printerr("render_structure_thumbnails: no structure to render in %s" % source)
		quit(2)
		return
	if listing:
		quit(0)
		return
	_destination = dest
	var serve := source if _option(args, "--serve") != "" else ""
	_begin(
		LibraryStructures.thumbnail_job(library_id, _entries, dest, serve),
		"structure_thumbnails",
		_option(args, "--log-out")
	)


func _process(delta: float) -> bool:
	var finished := super(delta)
	if finished and not _entries.is_empty() and _option(OS.get_cmdline_user_args(), "--list") == "":
		_report()
	return finished


## Prints one line per tile and the summary; sets the exit code.
func _report() -> void:
	var written := 0
	for result: Dictionary in root.get_meta("thumbnail_results", []):
		if result["ok"]:
			written += 1
			print(
				(
					"THUMBS| wrote %s %s %d bytes %s"
					% [result["biome"], result["file"], result["bytes"], result["sha256"]]
				)
			)
		else:
			printerr("THUMBS| FAILED %s: %s" % [result["biome"], result["error"]])
	print("THUMBS| %d of %d written to %s" % [written, _entries.size(), _destination])
	if written != _entries.size():
		quit(1)


## Why this run cannot go ahead, or "".
func _check(source: String, dest: String, listing: bool) -> String:
	if source == "":
		return "--library <folder> is required"
	if not FileAccess.file_exists(source.path_join(LibraryStructures.INDEX_FILE)):
		return "%s has no %s" % [source, LibraryStructures.INDEX_FILE]
	if DisplayServer.get_name() == "headless" and not listing:
		return "rendering needs a window: run without --headless"
	var refused := LibraryThumbnailer.target_problem(dest)
	if refused != "":
		return refused
	if not FileAccess.file_exists(dest.path_join("library.json")):
		return "%s has no library.json: not a library folder" % dest
	return ""


## The folder of `arg` (a folder, or a library.json inside one), forward slashes, no trailing
## slash; "" for nothing. A res:// folder is read through its absolute path.
static func _folder_of(arg: String) -> String:
	var clean := arg.replace("\\", "/").strip_edges()
	if clean.ends_with("/library.json"):
		clean = clean.get_base_dir()
	return clean.trim_suffix("/") if clean.length() > 3 else clean
