extends SceneTree

## Recomputes stats.file_sha256, stats.surface_bytes and stats.thumb_bytes of a built library's
## library.json from the files beside it (LibraryHashes), after a tile or picture was regenerated
## without touching library.json. No asset file is changed.
##   godot --headless --path <tt-sim> --script res://tools/recompute_library_hashes.gd -- \
##       --library <folder holding library.json> [--check 1]
## With --check 1 nothing is written and the exit code says whether the stats agree.


func _init() -> void:
	var folder := ""
	var check := false
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--library" and i + 1 < args.size():
			folder = args[i + 1]
		if args[i] == "--check":
			check = true
	if folder == "":
		printerr("--library <folder> is required")
		quit(2)
		return
	var path := "%s/library.json" % folder
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("cannot read %s" % path)
		quit(2)
		return
	var library: Dictionary = parsed
	var measured := LibraryHashes.measure(folder)
	var lines := LibraryHashes.differences(library, measured)
	for line in lines:
		print(line)
	if lines.is_empty():
		print("library.json already agrees with the files")
		quit(0)
		return
	if check:
		quit(1)
		return
	var fixed: Variant = LibraryHashes.whole_numbers_as_ints(
		LibraryHashes.reconciled(library, measured)
	)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(fixed, "\t", true) + "\n")
	file.close()
	print("rewrote %s (%d differences)" % [path, lines.size()])
	quit(0)
