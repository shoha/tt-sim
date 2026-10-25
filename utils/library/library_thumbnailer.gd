class_name LibraryThumbnailer
extends RefCounted

## The pure half of the biome thumbnails (docs/systems/library.md "Biome thumbnails"): which
## biomes of a library get a picture, where the file goes, the one standard scene it is
## rendered in, how a frame of the game's view becomes the 512 px JPG, what a JPG must meet
## to be accepted, and how a written file is recorded in its library (the biome-def's
## `thumbnail` field and `stats.file_sha256` of a built library).
##
## The pictures themselves are rendered by the real game: `tools/render_library_thumbnails.gd`
## (a render job over a built library folder) and the biome designer's "Update thumbnail"
## button both build the same standard scene (`NewMap` over `MAP_SIZE_FT`, one fixed seed, the
## game camera at `CAMERA_ZOOM`), freeze the wind and hold the fades off, so two runs on one
## machine draw the same pixels. This file never renders, never lists a folder and never
## deletes anything; the files are written by `LibraryWriter.write_thumbnail`.

## The picture's side in pixels and the folder it lives in (a library-relative path).
const SIZE_PX := 512
const DIR := "thumbnails"
## JPEG quality (0 to 1). The installed treecube renders were 10 to 15 KB; the plantgen scenes
## are busier, so the cap below is the rule that matters.
const JPG_QUALITY := 0.8
## The most a thumbnail may weigh: 128 KB (the reader's own cap is 4 MiB).
const MAX_BYTES := 131072
## The standard scene: a new map this many feet wide, painted with the biome (the starting
## cover: a glade ringed by groves), this map seed and placement seed, the camera this far out
## (orthographic size, metres) looking at the map's centre. Fixed so a rebuild is reproducible.
const MAP_SIZE_FT := 100
const MAP_SEED := 1234
const PLACE_SEED := 1234
const CAMERA_ZOOM := 20.0
const LOOK_AT := Vector2(0.0, 0.0)
## The render job's ceiling in seconds, and how long a biome waits for its plants.
const JOB_TIMEOUT_S := 900
const SETTLE_S := 3.0


## The season a thumbnail is rendered in: `wanted` when the biome-def has it, else the first
## season (every biome-def has at least one; the default is summer, seed 1).
static func season_of(def: Dictionary, wanted: String = "") -> Dictionary:
	var seasons: Variant = def.get("seasons")
	if seasons is Array and not (seasons as Array).is_empty():
		for entry: Variant in seasons as Array:
			if not entry is Dictionary or wanted == "":
				continue
			if String((entry as Dictionary).get("id", "")) == wanted:
				return {"id": wanted, "seed": int((entry as Dictionary).get("seed", 1))}
		var first: Variant = (seasons as Array)[0]
		if first is Dictionary:
			return {
				"id": String((first as Dictionary).get("id", "summer")),
				"seed": int((first as Dictionary).get("seed", 1)),
			}
	return {"id": "summer", "seed": 1}


## The new-map spec (NewMap.from_spec) of the standard scene painted with the palette biome
## `runtime_id`: the render job's `new_map` step and the designer both build this document.
static func map_spec(runtime_id: String) -> Dictionary:
	return {"size_ft": MAP_SIZE_FT, "biome_id": runtime_id, "seed": MAP_SEED}


## The library-relative file of biome `biome_id`: the biome-def's own `thumbnail` when it is a
## valid `thumbnails/` JPG path, else `thumbnails/<id>.jpg`.
static func file_of(def: Dictionary, biome_id: String) -> String:
	var named: Variant = def.get("thumbnail")
	if named is String and file_problem(String(named)) == "":
		return String(named)
	return "%s/%s.jpg" % [DIR, biome_id]


## Why `relative` cannot be a biome thumbnail's file, or "": a portable library-relative path
## directly under `thumbnails/` that ends in .jpg.
static func file_problem(relative: String) -> String:
	var problems := LibraryIds.path_problems(relative)
	if not problems.is_empty():
		return problems[0]
	if not relative.begins_with(DIR + "/") or relative.count("/") != 1:
		return "'%s' is not directly under %s/" % [relative, DIR]
	if not relative.ends_with(".jpg"):
		return "'%s' is not a .jpg" % relative
	return ""


## What to render for `library_id`: one entry per biome-def in `defs` (biome-def dictionaries),
## sorted by id, limited to `only` (local ids; empty is all): {biome, name, season, seed,
## runtime (the palette biome id the map is painted with), file, has_field}. `season` names the
## season to draw ("" is each biome's first).
static func plan(
	library_id: String, defs: Array, only: Array = [], season: String = ""
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Variant in defs:
		if not item is Dictionary:
			continue
		var def := item as Dictionary
		var biome_id := String(def.get("id", ""))
		if biome_id == "" or (not only.is_empty() and not only.has(biome_id)):
			continue
		var chosen := season_of(def, season)
		out.append(
			{
				"biome": biome_id,
				"name": String(def.get("name", biome_id)),
				"season": chosen["id"],
				"seed": chosen["seed"],
				"runtime": LibraryIds.runtime_biome(
					library_id, biome_id, String(chosen["id"]), int(chosen["seed"])
				),
				"file": file_of(def, biome_id),
				"has_field": String(def.get("thumbnail", "")) != "",
			}
		)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["biome"] < b["biome"])
	return out


## Why `folder` is not a place thumbnails may be written, or "": an absolute path that is not
## `res://` (a shipped library is a read-only pack), not empty and not "." (Godot reads both
## as the working directory), with no `..` segment. Whether it is a library at all is the
## caller's check (it has a library.json).
static func target_problem(folder: String) -> String:
	var clean := folder.replace("\\", "/").strip_edges()
	if clean == "" or clean == "." or clean == "./":
		return "no folder given"
	if clean.begins_with("res://"):
		return "'%s' is inside the game's pack, which is read-only" % folder
	if not clean.is_absolute_path() or clean == "user://":
		return "'%s' is not an absolute folder" % folder
	if ".." in clean.split("/"):
		return "'%s' has a '..' segment" % folder
	return ""


## Whether the designer may write the thumbnail of a biome of a library served from `source`
## ("user", "dev" or "official") out of `folder`: the player's own libraries and the
## developer-override folder, `core` included in the override (its pictures are rendered by this
## very step), never an official library's shipped folder, and never a folder that is no place
## for files (target_problem).
static func designer_writable(source: String, folder: String) -> bool:
	return (source == "user" or source == "dev") and target_problem(folder) == ""


## `image` (any size, any aspect) as the thumbnail picture: the largest centred square, scaled
## to SIZE_PX with Lanczos. A copy; the input is not touched.
static func frame(image: Image) -> Image:
	var side := mini(image.get_width(), image.get_height())
	var cropped := image.get_region(
		Rect2i((image.get_width() - side) / 2, (image.get_height() - side) / 2, side, side)
	)
	cropped.convert(Image.FORMAT_RGB8)
	if side != SIZE_PX:
		cropped.resize(SIZE_PX, SIZE_PX, Image.INTERPOLATE_LANCZOS)
	return cropped


## The JPEG bytes of a rendered frame (`frame`, then JPG_QUALITY); empty when it cannot encode.
static func encode(image: Image) -> PackedByteArray:
	if image == null or image.is_empty():
		return PackedByteArray()
	return frame(image).save_jpg_to_buffer(JPG_QUALITY)


## Why `bytes` is not an acceptable thumbnail, or "": a JPEG (start-of-image marker) that
## decodes, is square, at most SIZE_PX a side, not blank, and at most MAX_BYTES.
static func jpg_problem(bytes: PackedByteArray) -> String:
	if bytes.size() < 4 or bytes[0] != 0xFF or bytes[1] != 0xD8:
		return "is not a JPEG (no start-of-image marker)"
	if bytes.size() > MAX_BYTES:
		return "is %d bytes, over the %d cap" % [bytes.size(), MAX_BYTES]
	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK or image.is_empty():
		return "does not decode as a JPEG"
	if image.get_width() != image.get_height():
		return "is %dx%d, not square" % [image.get_width(), image.get_height()]
	if image.get_width() > SIZE_PX:
		return "is %d px, over the %d px cap" % [image.get_width(), SIZE_PX]
	return "" if not is_blank(image) else "is one flat colour (nothing rendered)"


## Whether `image` is a single flat colour (a capture of an empty or failed render).
static func is_blank(image: Image) -> bool:
	var small := image.duplicate() as Image
	small.resize(16, 16, Image.INTERPOLATE_NEAREST)
	var first := small.get_pixel(0, 0)
	for y in 16:
		for x in 16:
			var other := small.get_pixel(x, y)
			if absf(other.r - first.r) + absf(other.g - first.g) + absf(other.b - first.b) > 0.02:
				return false
	return true


## The lowercase sha256 of `bytes`.
static func sha256(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


## `library` (the library.json dictionary) with the hashes in `hashes` ({relative path: sha256})
## recorded in `stats.file_sha256`, when the library carries one (a built library does; a
## library's sources do not, and are returned unchanged); `byte_delta` (new file size minus the
## old one) moves `stats.surface_bytes` with them. A copy.
static func record_hashes(
	library: Dictionary, hashes: Dictionary, byte_delta: int = 0
) -> Dictionary:
	var out := library.duplicate(true)
	var stats: Variant = out.get("stats")
	if not stats is Dictionary or not (stats as Dictionary).get("file_sha256") is Dictionary:
		return out
	var listed := (stats as Dictionary)["file_sha256"] as Dictionary
	for relative: String in hashes:
		listed[relative] = hashes[relative]
	# stats.surface_bytes counts the surface and biome picture files: follow a changed picture.
	if byte_delta != 0 and (stats as Dictionary).has("surface_bytes"):
		(stats as Dictionary)["surface_bytes"] = int((stats as Dictionary)["surface_bytes"]) + byte_delta
	return out


## `def` (a biome-def) naming `relative` as its `thumbnail`; a copy. A biome-def that already
## names another valid file keeps it (the file written is that one, see `file_of`).
static func with_field(def: Dictionary, relative: String) -> Dictionary:
	var out := def.duplicate(true)
	out["thumbnail"] = relative
	return out


## The render job (the render-job harness's JSON form, tools/render_jobs/REFERENCE.md) that
## draws `entries` (from `plan`) over the library folder `source` and writes each picture to
## `dest_folder`/<file> through the driver's `thumbnail` op. One biome after the other, each in
## the standard scene.
static func job(
	source: String, dest_folder: String, entries: Array, frame_options: Dictionary = {}
) -> Dictionary:
	var steps: Array = [
		{"op": "wait", "s": 1.0},
		{"op": "wait_title"},
		{"op": "library_dev", "path": source},
		{"op": "wait", "s": 2.0},
	]
	for entry: Dictionary in entries:
		steps.append_array(_scene_steps(entry, dest_folder, frame_options))
	steps.append({"op": "title"})
	steps.append({"op": "wait", "s": 0.5})
	return {
		"out_dir": "render_jobs/library_thumbnails",
		"timeout_s": JOB_TIMEOUT_S,
		"hang_s": 120,
		"steps": steps,
	}


static func _scene_steps(
	entry: Dictionary, dest_folder: String, frame_options: Dictionary
) -> Array:
	return [
		{
			"op": "new_map",
			"biome": entry["runtime"],
			"size": MAP_SIZE_FT,
			"seed": MAP_SEED,
		},
		{"op": "wait_ready", "settle": SETTLE_S},
		{"op": "no_autosave"},
		{"op": "call", "script": "res://tools/render_jobs/probes/tree_fade.gd", "factor": 0},
		{"op": "hide_ui"},
		{"op": "place_seed", "seed": PLACE_SEED},
		{
			"op": "thumbnail_prepare",
			"zoom": float(frame_options.get("zoom", CAMERA_ZOOM)),
			"at": [
				float(frame_options.get("look_x", LOOK_AT.x)),
				float(frame_options.get("look_z", LOOK_AT.y))
			],
		},
		{"op": "settle"},
		{"op": "thumbnail", "biome": entry["biome"], "folder": dest_folder},
		{"op": "title"},
		{"op": "wait", "s": 1.0},
	]
