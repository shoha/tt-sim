extends SceneTree

## Headless: writes the render job that redraws the tiles (thumbnails) of the named structures of
## a library, for `tools/render_jobs/run.gd`. It calls LibraryStructures.thumbnail_job on the
## library folder's own index and recipes, so it works from any worktree. Use it in place of
## tools/render_structure_thumbnails.gd, which fails to compile under `--script` in a worktree.
##
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/make_tile_job.gd -- \
##       <library folder> <dest folder> <job json> <id,id,...>
##   godot --path D:/dev/tabletop/tt-sim --windowed --resolution 1920x1080 --position 320,120 \
##       --script res://tools/render_jobs/run.gd -- <job json>
##
## `<library folder>` holds `structures/` (core-library, or libraries/core); the tiles are written
## to `<dest folder>/thumbnails/structures/<id>.jpg` (copy them beside the other tiles after a
## look). The job's output folder is its `out_dir` (set it to `render_jobs/<topic>_thumbs` by
## editing the JSON, so closing the topic removes it). docs/systems/library.md "Thumbnails".
func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("usage: -- <library folder> <dest folder> <job json> <id,id,...>")
		quit(1)
		return
	var source: String = args[0]
	var dest: String = args[1]
	var only := Array(String(args[3]).split(",", false))
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
	var items: Array = []
	for item: Dictionary in read["structures"]:
		if String(item["id"]) in only:
			items.append(item)
	var job := LibraryStructures.thumbnail_job("core", items, dest, "")
	var file := FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify(job, "\t"))
	file.close()
	print("JOB| %d tiles" % items.size())
	quit(0)
