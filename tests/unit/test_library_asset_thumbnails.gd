extends GutTest

## The shipped core library's asset thumbnails (res://libraries/core/assets/thumbs, one 256 px PNG
## per catalog asset) and what draws them: every catalog `thumb` resolves to a valid PNG of at
## most 256 px whose sha256 equals library.json's stats.file_sha256, the picker's records carry the
## file, AssetThumbnails decodes it (size-capped, cached, LRU-bounded, null on a bad file) and the
## designer's asset tile shows the picture or falls back to its category icon.

const CORE := "res://libraries/core"
const SCRATCH := "user://test_library_asset_thumbnails"

var _catalog: Array = []
var _library: Dictionary = {}


func before_all() -> void:
	_library = JSON.parse_string(FileAccess.get_file_as_string(CORE + "/library.json"))
	var catalog: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(CORE + "/assets/catalog.json")
	)
	_catalog = catalog["assets"]
	DirAccess.make_dir_recursive_absolute(SCRATCH)


func after_all() -> void:
	for file in DirAccess.get_files_at(SCRATCH):
		DirAccess.remove_absolute(SCRATCH.path_join(file))
	DirAccess.remove_absolute(SCRATCH)
	AssetThumbnails.clear()


func before_each() -> void:
	AssetThumbnails.clear()


func test_every_catalog_thumb_is_a_valid_png_of_at_most_256_px_with_its_recorded_hash() -> void:
	var hashes: Dictionary = (_library["stats"] as Dictionary)["file_sha256"]
	var total := 0
	var checked := 0
	for entry: Dictionary in _catalog:
		var relative := String(entry.get("thumb", ""))
		assert_ne(relative, "", "%s names a thumb" % entry["id"])
		if relative == "":
			continue
		var file := CORE.path_join(relative)
		var header := SurfaceStore.png_header_of(file)
		assert_true(bool(header.get("ok", false)), "%s is a PNG" % relative)
		if not bool(header.get("ok", false)):
			continue
		assert_between(int(header["width"]), 1, 256, relative + " width")
		assert_between(int(header["height"]), 1, 256, relative + " height")
		assert_true(hashes.has(relative), relative + " is in stats.file_sha256")
		assert_eq(FileAccess.get_sha256(file), String(hashes.get(relative, "")), relative)
		total += FileAccess.get_file_as_bytes(file).size()
		checked += 1
	var stats: Dictionary = _library["stats"]
	assert_eq(checked, int(stats["thumbs"]), "stats.thumbs counts the pictures")
	assert_eq(total, int(stats["thumb_bytes"]), "stats.thumb_bytes sums them")
	assert_eq(checked, _catalog.size(), "every asset has one")


func test_the_pickers_records_carry_the_cores_thumbnail_files() -> void:
	var catalog := {}
	for entry: Dictionary in _catalog:
		catalog[String(entry["id"])] = entry
	var context := {"library": "core", "catalog": catalog, "folder": CORE}
	var records := DesignerCatalog.groups(LibraryQuery.candidates(context))
	assert_gt(records.size(), 20, "the core has many groups")
	for record in records:
		var thumb := String(record["thumb"])
		assert_ne(thumb, "", "%s has a picture" % record["name"])
		assert_true(FileAccess.file_exists(thumb), thumb)
		assert_not_null(AssetThumbnails.texture(thumb), thumb)


func test_a_thumbnail_decodes_to_a_texture_and_is_cached() -> void:
	var file := CORE.path_join(String((_catalog[0] as Dictionary)["thumb"]))
	var first := AssetThumbnails.texture(file)
	assert_not_null(first)
	assert_lte(first.get_width(), 256)
	assert_eq(AssetThumbnails.texture(file), first, "the second read is the cached texture")
	assert_eq(AssetThumbnails.stats["decodes"], 1)
	assert_eq(AssetThumbnails.stats["hits"], 1)


func test_missing_and_bad_files_give_null_and_are_not_retried() -> void:
	assert_null(AssetThumbnails.texture(""))
	assert_null(AssetThumbnails.texture(SCRATCH + "/nope.png"))
	var junk := SCRATCH + "/junk.png"
	var handle := FileAccess.open(junk, FileAccess.WRITE)
	handle.store_string("this is not a png")
	handle.close()
	assert_null(AssetThumbnails.texture(junk))
	var decodes := int(AssetThumbnails.stats["decodes"])
	assert_null(AssetThumbnails.texture(junk))
	assert_eq(AssetThumbnails.stats["decodes"], decodes, "a failed file is remembered")


func test_a_picture_over_the_texture_limit_is_refused_and_a_big_one_is_shrunk() -> void:
	var huge := SCRATCH + "/huge.png"
	Image.create_empty(LibraryContracts.MAX_GLB_TEXTURE_PX + 1, 4, false, Image.FORMAT_RGBA8).save_png(
		huge
	)
	assert_null(AssetThumbnails.texture(huge), "over the limit")
	var big := SCRATCH + "/big.png"
	Image.create_empty(512, 512, false, Image.FORMAT_RGBA8).save_png(big)
	var shrunk := AssetThumbnails.texture(big)
	assert_not_null(shrunk)
	assert_lte(shrunk.get_width(), AssetThumbnails.MAX_SIDE)


func test_the_cache_drops_the_least_recently_used_picture_past_its_cap() -> void:
	AssetThumbnails.cap = 3
	var files: Array[String] = []
	for i in 4:
		var file := "%s/lru_%d.png" % [SCRATCH, i]
		Image.create_empty(8, 8, false, Image.FORMAT_RGBA8).save_png(file)
		files.append(file)
	AssetThumbnails.texture(files[0])
	AssetThumbnails.texture(files[1])
	AssetThumbnails.texture(files[2])
	AssetThumbnails.texture(files[0])  # 0 is now the freshest, 1 the oldest
	AssetThumbnails.texture(files[3])
	assert_eq(AssetThumbnails.cached_count(), 3)
	var decodes := int(AssetThumbnails.stats["decodes"])
	AssetThumbnails.texture(files[0])
	assert_eq(AssetThumbnails.stats["decodes"], decodes, "0 survived")
	AssetThumbnails.texture(files[1])
	assert_eq(AssetThumbnails.stats["decodes"], decodes + 1, "1 was dropped and decodes again")


func test_a_tile_shows_its_picture_and_falls_back_to_the_icon() -> void:
	var file := CORE.path_join(String((_catalog[0] as Dictionary)["thumb"]))
	var with_picture := DesignerAssetTile.new()
	add_child_autofree(with_picture)
	with_picture.setup({"ref": "a", "name": "a", "category": "bush", "thumb": file})
	assert_true(with_picture.has_picture())
	var without := DesignerAssetTile.new()
	add_child_autofree(without)
	without.setup({"ref": "b", "name": "b", "category": "bush", "thumb": SCRATCH + "/gone.png"})
	assert_false(without.has_picture(), "a missing file falls back")
	var unnamed := DesignerAssetTile.new()
	add_child_autofree(unnamed)
	unnamed.setup({"ref": "c", "name": "c", "category": "rock"})
	assert_false(unnamed.has_picture(), "no thumb falls back")
	await get_tree().process_frame  # both draw paths run without an error
	assert_true(with_picture.is_inside_tree() and without.is_inside_tree())
