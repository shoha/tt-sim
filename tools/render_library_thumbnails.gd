extends "res://tools/render_jobs/run.gd"

## Renders the biome thumbnails of a library with the real game (docs/systems/library.md
## "Biome thumbnails"): one 512 px JPG per biome, `thumbnails/<biome>.jpg`, each the standard
## scene (a new 100 ft map painted with the biome, one fixed seed, the game camera, the wind
## frozen; LibraryThumbnailer) taken through the render-job harness, so the pictures show the
## plants, the ground look, the light and the scatter exactly as the game draws them. Windowed:
## it needs a GPU and a real window, never --headless.
##
##   godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120
##     --script res://tools/render_library_thumbnails.gd -- --library <built library folder>
##     [--out <library folder to write into>] [--biome a,b] [--season summer] [--list 1]
##     [--zoom 24 --look_x 0 --look_z -1]   (framing experiments; the defaults are the standard)
##
## --library is the BUILT library to draw (a folder with library.json, assets/ and biomes/, as
## plantgen's build_library_cli writes it; a library.json path works too). --out is the folder
## the pictures go to: thumbnails/<biome>.jpg inside it, the biome-def gets its `thumbnail`
## field when it lacks one, and library.json's stats.file_sha256 takes the hashes when the
## library has them (default: the --library folder itself). A shipped folder (res://) is
## refused. --list 1 prints the plan and writes nothing (works headless). Exit code 0 when
## every picture was written, 1 otherwise. Nothing is deleted.

var _entries: Array[Dictionary] = []
var _destination: String = ""


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var source := _folder_of(_option(args, "--library"))
	var dest := _folder_of(_option(args, "--out")) if _option(args, "--out") != "" else source
	var problem := _check(source, dest, args)
	if problem != "":
		printerr("render_library_thumbnails: %s" % problem)
		quit(2)
		return
	var library: Dictionary = _read_json(source.path_join("library.json"))
	var defs := _biome_defs(source)
	var only := Array(_option(args, "--biome").split(",", false))
	_entries = LibraryThumbnailer.plan(
		String(library.get("id", "")), defs, only, _option(args, "--season")
	)
	for entry in _entries:
		print("THUMBS| plan %s -> %s (%s)" % [entry["biome"], entry["file"], entry["runtime"]])
	if _entries.is_empty():
		printerr("render_library_thumbnails: no biome to render in %s" % source)
		quit(2)
		return
	if _option(args, "--list") != "":
		quit(0)
		return
	_destination = dest
	var framing := {}
	for key in ["zoom", "look_x", "look_z"]:
		if _option(args, "--" + key) != "":
			framing[key] = float(_option(args, "--" + key))
	var job := LibraryThumbnailer.job(source, dest, _entries, framing)
	_begin(job, "library_thumbnails", _option(args, "--log-out"))


func _process(delta: float) -> bool:
	var finished := super(delta)
	if finished and not _entries.is_empty() and _option(OS.get_cmdline_user_args(), "--list") == "":
		_report()
	return finished


## Prints one line per picture and the summary; sets the exit code.
func _report() -> void:
	var results: Array = root.get_meta("thumbnail_results", [])
	var written := 0
	for result: Dictionary in results:
		if result["ok"]:
			written += 1
			print(
				"THUMBS| wrote %s %s %d bytes %s"
				% [result["biome"], result["file"], result["bytes"], result["sha256"]]
			)
		else:
			printerr("THUMBS| FAILED %s: %s" % [result["biome"], result["error"]])
	print("THUMBS| %d of %d written to %s" % [written, _entries.size(), _destination])
	if written != _entries.size():
		quit(1)


## Why this run cannot go ahead, or "".
func _check(source: String, dest: String, args: PackedStringArray) -> String:
	if source == "":
		return "--library <built library folder> is required"
	if not FileAccess.file_exists(source.path_join("library.json")):
		return "%s has no library.json" % source
	var listing := _option(args, "--list") != ""
	if DisplayServer.get_name() == "headless" and not listing:
		return "rendering needs a window: run without --headless"
	var refused := LibraryThumbnailer.target_problem(dest)
	if refused != "":
		return refused
	if not FileAccess.file_exists(dest.path_join("library.json")):
		return "%s has no library.json: not a library folder" % dest
	return ""


## The folder of `arg` (a folder, or a library.json inside one), forward slashes, no trailing
## slash; "" for nothing.
static func _folder_of(arg: String) -> String:
	var clean := arg.replace("\\", "/").strip_edges()
	if clean.ends_with("/library.json"):
		clean = clean.get_base_dir()
	return clean.trim_suffix("/") if clean.length() > 3 else clean


## Every `biomes/*.json` biome-def of `folder` (lock files left out).
static func _biome_defs(folder: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(folder.path_join("biomes"))
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for file_name in names:
		if file_name.ends_with(".json") and not file_name.ends_with(LibraryReader.LOCK_SUFFIX):
			var def := _read_json(folder.path_join("biomes").path_join(file_name))
			if not def.is_empty():
				out.append(def)
	return out


static func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}
