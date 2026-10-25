extends GutTest

## The biome thumbnails (docs/systems/library.md "Biome thumbnails"): the pure plan (which biome
## draws in which season, under which runtime id, into which file), the standard scene's
## constants and render job, the picture's frame, encoding and caps, the targets that are
## refused, the files `LibraryWriter.write_thumbnail` writes and records, and the shipped core
## pictures. The rendering itself needs a window and is covered by the render job
## (tools/render_jobs/jobs/library_thumbnails.json).

const SCRATCH := "user://test_library_thumbnailer"
const CORE := "res://libraries/core"
const NO_DELETE_SOURCES: Array[String] = [
	"res://utils/library/library_thumbnailer.gd",
	"res://tools/render_library_thumbnails.gd",
	"res://scenes/states/authoring/designer/thumbnail_shot.gd",
]


func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH)


func before_each() -> void:
	_clear_scratch()


func after_all() -> void:
	_clear_scratch()
	for folder in ["lib/thumbnails", "lib/biomes", "lib", ""]:
		DirAccess.remove_absolute(SCRATCH.path_join(folder) if folder != "" else SCRATCH)


## Removes the files (never a folder tree) the tests wrote under the scratch library.
func _clear_scratch() -> void:
	for folder in ["lib/thumbnails", "lib/biomes", "lib", ""]:
		_remove_files(SCRATCH.path_join(folder) if folder != "" else SCRATCH)


# ---- the plan ----


func _defs() -> Array:
	return [
		{"id": "savanna", "name": "Savanna", "seasons": [{"id": "dry", "seed": 4}, {"id": "wet"}]},
		{"id": "alpine", "name": "Alpine", "thumbnail": "thumbnails/alpine_pic.jpg"},
		{"id": "bog", "name": "Bog", "thumbnail": "elsewhere/bog.png", "seasons": []},
	]


func test_the_plan_lists_every_biome_sorted_with_its_first_season_and_runtime_id() -> void:
	var plan := LibraryThumbnailer.plan("core", _defs())
	assert_eq(plan.size(), 3)
	assert_eq(plan.map(func(e: Dictionary) -> String: return e["biome"]), ["alpine", "bog", "savanna"])
	assert_eq(plan[0]["runtime"], "alpine_summer_s1", "no seasons: summer, seed 1")
	assert_eq(plan[2]["runtime"], "savanna_dry_s4", "the first season, with its seed")
	assert_eq(plan[2]["file"], "thumbnails/savanna.jpg")


func test_a_biome_def_naming_a_valid_file_keeps_it_and_a_bad_name_falls_back() -> void:
	var plan := LibraryThumbnailer.plan("core", _defs())
	assert_eq(plan[0]["file"], "thumbnails/alpine_pic.jpg")
	assert_true(plan[0]["has_field"])
	assert_eq(plan[1]["file"], "thumbnails/bog.jpg", "a path outside thumbnails/ is not used")


func test_another_librarys_runtime_ids_carry_its_prefix() -> void:
	var plan := LibraryThumbnailer.plan("alienworld", _defs(), ["savanna"])
	assert_eq(plan.size(), 1, "only limits the plan")
	assert_eq(plan[0]["runtime"], "alienworld__savanna_dry_s4")


func test_a_named_season_is_used_when_the_biome_has_it() -> void:
	var plan := LibraryThumbnailer.plan("core", _defs(), [], "wet")
	assert_eq(plan[2]["season"], "wet")
	assert_eq(plan[2]["seed"], 1, "a season without a seed has seed 1")
	assert_eq(LibraryThumbnailer.plan("core", _defs(), [], "winter")[2]["season"], "dry")


func test_file_problems() -> void:
	assert_eq(LibraryThumbnailer.file_problem("thumbnails/a.jpg"), "")
	for bad in ["", "a.jpg", "thumbnails/a.png", "thumbnails/x/a.jpg", "../thumbnails/a.jpg"]:
		assert_ne(LibraryThumbnailer.file_problem(bad), "", "'%s' is refused" % bad)


# ---- the standard scene and the job ----


func test_the_standard_scene_is_fixed() -> void:
	var spec := LibraryThumbnailer.map_spec("savanna_summer_s1")
	assert_eq(spec, LibraryThumbnailer.map_spec("savanna_summer_s1"), "no clock, no random seed")
	assert_eq(spec["seed"], LibraryThumbnailer.MAP_SEED)
	assert_eq(spec["size_ft"], LibraryThumbnailer.MAP_SIZE_FT)
	assert_eq(spec["biome_id"], "savanna_summer_s1")
	var doc := NewMap.from_spec(spec)
	assert_not_null(doc, "the spec builds a document")


func test_the_job_draws_each_biome_in_the_standard_scene_and_is_reproducible() -> void:
	var plan := LibraryThumbnailer.plan("core", _defs())
	var job := LibraryThumbnailer.job("D:/built", "D:/out", plan)
	assert_eq(job, LibraryThumbnailer.job("D:/built", "D:/out", plan), "the same job twice")
	var steps: Array = job["steps"]
	var ops := steps.map(func(s: Dictionary) -> String: return s["op"])
	assert_eq(ops.count("new_map"), 3)
	assert_eq(ops.count("thumbnail"), 3)
	assert_eq(ops.count("library_dev"), 1)
	assert_eq(steps[ops.find("library_dev")]["path"], "D:/built")
	for step: Dictionary in steps:
		if step["op"] == "new_map":
			assert_eq(int(step["seed"]), LibraryThumbnailer.MAP_SEED)
			assert_eq(int(step["size"]), LibraryThumbnailer.MAP_SIZE_FT)
		if step["op"] == "thumbnail":
			assert_eq(step["folder"], "D:/out")
		assert_false(String(step["op"]).contains("delete"), "no step deletes")
	assert_lt(ops.find("thumbnail_prepare"), ops.find("thumbnail"), "frozen and framed first")


func test_no_source_of_the_thumbnailer_deletes_anything() -> void:
	for path in NO_DELETE_SOURCES:
		var text := FileAccess.get_file_as_string(path)
		assert_ne(text, "", path + " is readable")
		for word in ["remove_absolute", "remove_recursive", "SafeDelete", "OS.move_to_trash"]:
			assert_false(text.contains(word), "%s has no %s" % [path.get_file(), word])


# ---- targets ----


func test_a_target_that_is_no_place_for_files_is_refused() -> void:
	for bad in ["", ".", "./", "res://libraries/core", "relative/folder", "D:/a/../b", "user://"]:
		assert_ne(LibraryThumbnailer.target_problem(bad), "", "'%s' is refused" % bad)
	assert_eq(LibraryThumbnailer.target_problem("D:/dev/tabletop/core-library"), "")
	assert_eq(LibraryThumbnailer.target_problem("user://libraries/mine"), "")


func test_only_user_libraries_and_the_dev_override_may_take_a_picture() -> void:
	assert_true(LibraryThumbnailer.designer_writable("user", "user://libraries/mine"))
	assert_true(LibraryThumbnailer.designer_writable("dev", "D:/built/core"), "core, in the override")
	assert_false(LibraryThumbnailer.designer_writable("official", "res://libraries/core"))
	assert_false(LibraryThumbnailer.designer_writable("dev", ""), "no folder")
	assert_false(LibraryThumbnailer.designer_writable("user", "res://x"), "never the pack")


func test_write_thumbnail_refuses_the_pack_and_an_empty_folder() -> void:
	var bytes := _jpg()
	for bad in ["", ".", "res://libraries/core"]:
		var written := LibraryWriter.write_thumbnail(bad, "savanna", bytes)
		assert_false(written["ok"], "'%s' refused" % bad)
	assert_false(FileAccess.file_exists("res://libraries/core/thumbnails/zz_probe.jpg"))


# ---- the picture ----


func _noise(side: int) -> Image:
	var image := Image.create(side, side, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for y in side:
		for x in side:
			image.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	return image


func _scene(width: int, height: int) -> Image:
	var image := Image.create(width, height, false, Image.FORMAT_RGB8)
	for y in height:
		for x in width:
			var shade := 0.3 + 0.5 * float(y) / height
			image.set_pixel(x, y, Color(shade * 0.5, shade, 0.2 + 0.3 * float(x % 97) / 97.0))
	return image


func _jpg() -> PackedByteArray:
	return LibraryThumbnailer.encode(_scene(960, 540))


func test_frame_is_the_centred_square_at_512() -> void:
	var image := _scene(1920, 1080)
	image.set_pixel(960, 540, Color.RED)
	var framed := LibraryThumbnailer.frame(image)
	assert_eq(framed.get_size(), Vector2i(512, 512))
	assert_eq(image.get_size(), Vector2i(1920, 1080), "the input is untouched")


func test_encode_is_deterministic_and_passes_the_caps() -> void:
	var first := _jpg()
	assert_eq(first, _jpg(), "the same frame gives the same bytes")
	assert_eq(LibraryThumbnailer.jpg_problem(first), "")
	assert_gt(first.size(), 1000)
	assert_lt(first.size(), LibraryThumbnailer.MAX_BYTES)
	var decoded := Image.new()
	assert_eq(decoded.load_jpg_from_buffer(first), OK)
	assert_eq(decoded.get_size(), Vector2i(512, 512))


func test_a_bad_picture_is_named_and_refused() -> void:
	assert_ne(LibraryThumbnailer.jpg_problem(PackedByteArray()), "")
	assert_ne(LibraryThumbnailer.jpg_problem(PackedByteArray([1, 2, 3, 4, 5])), "")
	var flat := Image.create(512, 512, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.5, 0.5, 0.5))
	assert_string_contains(
		LibraryThumbnailer.jpg_problem(flat.save_jpg_to_buffer(0.8)), "flat colour"
	)
	var heavy := _noise(512).save_jpg_to_buffer(1.0)
	assert_string_contains(LibraryThumbnailer.jpg_problem(heavy), "cap")
	var wide := _scene(600, 600).save_jpg_to_buffer(0.8)
	assert_string_contains(LibraryThumbnailer.jpg_problem(wide), "px, over")
	var oblong := _scene(512, 256).save_jpg_to_buffer(0.8)
	assert_string_contains(LibraryThumbnailer.jpg_problem(oblong), "not square")


# ---- recording ----


func test_hashes_are_recorded_only_where_a_library_lists_them() -> void:
	var built := {"id": "x", "stats": {"file_sha256": {"a": "1"}, "thumbs": 2}}
	var recorded := LibraryThumbnailer.record_hashes(built, {"thumbnails/b.jpg": "ff"})
	assert_eq(recorded["stats"]["file_sha256"], {"a": "1", "thumbnails/b.jpg": "ff"})
	assert_eq(built["stats"]["file_sha256"], {"a": "1"}, "the input is untouched")
	var source := {"id": "x"}
	assert_eq(LibraryThumbnailer.record_hashes(source, {"thumbnails/b.jpg": "ff"}), source)


func test_with_field_names_the_file_and_leaves_the_input_alone() -> void:
	var def := {"id": "bog"}
	var named := LibraryThumbnailer.with_field(def, "thumbnails/bog.jpg")
	assert_eq(named["thumbnail"], "thumbnails/bog.jpg")
	assert_false(def.has("thumbnail"))


func _make_library(with_stats: bool) -> String:
	var folder := SCRATCH.path_join("lib")
	DirAccess.make_dir_recursive_absolute(folder.path_join("biomes"))
	var library := {"id": "mine", "name": "Mine", "version": "0.1.0"}
	if with_stats:
		library["stats"] = {"file_sha256": {"thumbnails/other.jpg": "aa"}}
	_put(folder.path_join("library.json"), LibraryWriter.json_text(library))
	_put(
		folder.path_join("biomes/savanna.json"),
		LibraryWriter.json_text({"id": "savanna", "name": "Savanna"})
	)
	return ProjectSettings.globalize_path(folder)


func _put(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))


func test_write_thumbnail_writes_the_file_names_it_in_the_def_and_records_the_hash() -> void:
	var folder := _make_library(true)
	var bytes := _jpg()
	var written := LibraryWriter.write_thumbnail(folder, "savanna", bytes)
	assert_true(written["ok"], str(written))
	assert_eq(written["file"], "thumbnails/savanna.jpg")
	assert_eq(FileAccess.get_file_as_bytes(folder + "/thumbnails/savanna.jpg"), bytes)
	assert_eq(_json(folder + "/biomes/savanna.json")["thumbnail"], "thumbnails/savanna.jpg")
	var hashes: Dictionary = _json(folder + "/library.json")["stats"]["file_sha256"]
	var file := folder + "/thumbnails/savanna.jpg"
	assert_eq(hashes["thumbnails/savanna.jpg"], FileAccess.get_sha256(file))
	assert_eq(hashes["thumbnails/other.jpg"], "aa", "the other entries stay")
	assert_false(FileAccess.file_exists(folder + "/thumbnails/savanna.jpg.tmp"), "no temp left")


func test_a_library_without_stats_gets_no_hash_table() -> void:
	var folder := _make_library(false)
	assert_true(LibraryWriter.write_thumbnail(folder, "savanna", _jpg())["ok"])
	assert_false(_json(folder + "/library.json").has("stats"))


func test_writing_the_same_picture_twice_changes_nothing_on_disk() -> void:
	var folder := _make_library(true)
	LibraryWriter.write_thumbnail(folder, "savanna", _jpg())
	var library_text := FileAccess.get_file_as_string(folder + "/library.json")
	var def_text := FileAccess.get_file_as_string(folder + "/biomes/savanna.json")
	LibraryWriter.write_thumbnail(folder, "savanna", _jpg())
	assert_eq(FileAccess.get_file_as_string(folder + "/library.json"), library_text)
	assert_eq(FileAccess.get_file_as_string(folder + "/biomes/savanna.json"), def_text)


func test_a_bad_picture_or_biome_id_writes_nothing() -> void:
	var folder := _make_library(true)
	var refused := LibraryWriter.write_thumbnail(folder, "savanna", PackedByteArray([1, 2, 3, 4]))
	assert_false(refused["ok"])
	assert_false(FileAccess.file_exists(folder + "/thumbnails/savanna.jpg"))
	assert_false(LibraryWriter.write_thumbnail(folder, "../escape", _jpg())["ok"])
	assert_false(LibraryWriter.write_thumbnail(folder, "", _jpg())["ok"])


func test_saving_a_draft_without_the_field_keeps_the_picture_that_was_taken() -> void:
	var folder := _make_library(false)
	LibraryWriter.write_thumbnail(folder, "savanna", _jpg())
	var draft := {"id": "savanna", "name": "Savanna, edited"}
	assert_true(LibraryWriter.write_biome(folder, "savanna", draft, {})["ok"])
	var after := _json(folder + "/biomes/savanna.json")
	assert_eq(after["name"], "Savanna, edited", "the edit is written")
	assert_eq(after["thumbnail"], "thumbnails/savanna.jpg", "the picture's field is kept")


# ---- the shipped pictures ----


func test_the_shipped_core_pictures_meet_the_caps_and_carry_their_hashes() -> void:
	var library: Dictionary = _json(CORE + "/library.json")
	var hashes: Dictionary = library["stats"]["file_sha256"]
	var checked := 0
	for file in DirAccess.get_files_at(CORE + "/biomes"):
		if not file.ends_with(".json") or file.ends_with(LibraryReader.LOCK_SUFFIX):
			continue
		var def := _json(CORE.path_join("biomes").path_join(file))
		var relative := String(def.get("thumbnail", ""))
		assert_eq(LibraryThumbnailer.file_problem(relative), "", "%s names a picture" % file)
		var bytes := FileAccess.get_file_as_bytes(CORE.path_join(relative))
		assert_eq(LibraryThumbnailer.jpg_problem(bytes), "", relative)
		assert_eq(hashes.get(relative), LibraryThumbnailer.sha256(bytes), relative + " hash")
		checked += 1
	assert_eq(checked, 9, "one picture per core biome")


func _remove_files(folder: String) -> void:
	for file in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(file))
