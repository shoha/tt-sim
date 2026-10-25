extends SceneTree

## Headless: reads a content library folder, validates it and prints the compiled palette
## (the `biomes` and `assets` a palette.json would carry, plus the authoring fields) as JSON.
## plantgen's tools/library_diff_cli.gd reads the --out file against a package.
##
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/compile_library_cli.gd -- \
##       --library <folder> [--out <file.json>] [--biome <runtime id>] [--surfaces 1]
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/compile_library_cli.gd -- \
##       --contract <file.json>      (writes LibraryContracts.export_json, for plantgen)
##
## Problems go to stderr (errors, warnings, validate_palette's warnings). Exit 0 when the library
## read cleanly and compiled to at least one biome, 1 when it did not, 2 on bad arguments.


func _initialize() -> void:
	var args := _args()
	if args.has("contract"):
		var file := FileAccess.open(String(args["contract"]), FileAccess.WRITE)
		if file == null:
			printerr("cannot write %s" % args["contract"])
			quit(2)
			return
		file.store_string(LibraryContracts.export_json())
		file.close()
		print("contract %d written to %s" % [LibraryContracts.CONTRACT_VERSION, args["contract"]])
		quit(0)
		return
	var folder := String(args.get("library", ""))
	if folder == "":
		printerr("--library <folder> (or --contract <file>) is required")
		quit(2)
		return
	var built := LibraryRegistry.compile_folder(folder)
	for error: String in built["errors"]:
		printerr("error: " + error)
	for warning: String in built["warnings"]:
		printerr("warning: " + warning)
	if not built["ok"]:
		printerr("not compiled: %d errors" % (built["errors"] as Array).size())
		quit(1)
		return
	var compiled: Dictionary = built["compiled"]
	var palette: Dictionary = (compiled["palette"] as Dictionary).duplicate()
	if not String(args.get("surfaces", "")) in ["1", "true"]:
		palette.erase("surfaces")
	var wanted := String(args.get("biome", ""))
	if wanted != "":
		palette["biomes"] = (palette["biomes"] as Array).filter(
			func(b: Dictionary) -> bool: return b["id"] == wanted
		)
	var text := JSON.stringify(palette, "\t", true)
	if args.has("out"):
		var out := FileAccess.open(String(args["out"]), FileAccess.WRITE)
		if out == null:
			printerr("cannot write %s" % args["out"])
			quit(2)
			return
		out.store_string(text)
		out.close()
		print(
			(
				"%s %s: %d biomes, %d assets, %d palette warnings -> %s"
				% [
					compiled["library"],
					built["hash"],
					(compiled["biome_ids"] as Array).size(),
					(compiled["palette"]["assets"] as Dictionary).size(),
					(compiled["palette_warnings"] as Array).size(),
					args["out"],
				]
			)
		)
	else:
		print(text)
	quit(0)


func _args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var token := String(raw[i]).trim_prefix("--")
		if "=" in token:
			out[token.get_slice("=", 0)] = token.substr(token.find("=") + 1)
		elif i + 1 < raw.size() and not String(raw[i + 1]).begins_with("--"):
			out[token] = String(raw[i + 1])
			i += 1
		else:
			out[token] = "1"
		i += 1
	return out
