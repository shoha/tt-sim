extends GutTest

## Card exportbake: an exported game has no image compressor, so (1) SurfaceBake bakes the
## uncompressed fallback there without calling one, and the cache keeps it (it used to reject
## every export bake and re-bake it on every open), while an editor run re-bakes such a file to BC;
## (2) the export plugin's half (addons/surface_bake_export/surface_ship.gd) lists every official
## library map it ships, under the cache's key, and bakes it to the compressed format; and (3)
## SurfaceStore.load_map takes a shipped bake before the cache and writes nothing for it. A scratch
## library of 16 px PNGs under user:// stands in for a real one; the last test reads the real core.

const Ship := preload("res://addons/surface_bake_export/surface_ship.gd")
const ROOT := "user://test_surface_ship"
const LIBS := ROOT + "/libs"
const SHIPPED := ROOT + "/shipped"
const CACHE := ROOT + "/cache"
const LIBRARY_ID := "shiplib"
const SURFACE := "stone"
const SIDE := 16
## SurfaceBake.compressor: ask the binary (the editor here: it compresses), or forbid it (an export).
const AUTO := 0
const NONE := -1

var _saved_cache_root := ""
var _saved_shipped_root := ""


func before_all() -> void:
	_saved_cache_root = SurfaceCache.root
	_saved_shipped_root = SurfaceCache.shipped_root
	_write_library()


func after_all() -> void:
	SurfaceCache.root = _saved_cache_root
	SurfaceCache.shipped_root = _saved_shipped_root
	SurfaceBake.compressor = AUTO
	_remove_tree(ROOT)


func before_each() -> void:
	SurfaceBake.compressor = AUTO
	_remove_tree(CACHE)
	_remove_tree(SHIPPED)
	SurfaceCache.root = CACHE
	SurfaceCache.shipped_root = SHIPPED


func test_the_editor_binary_compresses_and_bakes_as_before() -> void:
	assert_true(SurfaceBake.can_compress(), "GUT runs on the editor binary")
	for kind in SurfaceBake.KINDS:
		var baked := SurfaceBake.bake(_source(kind), kind)
		assert_eq(baked.get_format(), SurfaceBake.format_of(kind), kind)


func test_without_a_compressor_the_bake_is_the_uncompressed_fallback() -> void:
	SurfaceBake.compressor = NONE
	assert_eq(SurfaceBake.fallback_format_of("albedo"), Image.FORMAT_RGBA8)
	assert_eq(SurfaceBake.fallback_format_of("normal"), Image.FORMAT_RG8)
	assert_eq(SurfaceBake.fallback_format_of("orm"), Image.FORMAT_RGBA8)
	assert_eq(SurfaceBake.fallback_format_of("height"), Image.FORMAT_L8)
	for kind in SurfaceBake.KINDS:
		var source := _source(kind)
		var baked := SurfaceBake.bake(source, kind)
		assert_eq(baked.get_format(), SurfaceBake.fallback_format_of(kind), kind + " format")
		assert_true(baked.has_mipmaps(), kind + " mips")
		assert_eq(
			baked.get_data().size(),
			SurfaceBake.data_size(baked.get_format(), SIDE, SIDE),
			kind + " size with its mip chain"
		)
	# Lossless at the top level: albedo keeps the source's colours, the normal its red and green.
	var albedo := _source("albedo")
	var top := SurfaceBake.bake(albedo, "albedo")
	top.clear_mipmaps()
	albedo.convert(Image.FORMAT_RGBA8)
	assert_eq(top.get_data(), albedo.get_data(), "albedo mip 0 is the source")
	var normal := _source("normal")
	var flat := SurfaceBake.bake(normal, "normal")
	flat.clear_mipmaps()
	assert_eq(flat.get_pixel(3, 5).r8, normal.get_pixel(3, 5).r8, "normal red")
	assert_eq(flat.get_pixel(3, 5).g8, normal.get_pixel(3, 5).g8, "normal green")


func test_what_each_binary_accepts() -> void:
	for kind in SurfaceBake.KINDS:
		SurfaceBake.compressor = 1
		assert_true(SurfaceBake.accepts(kind, SurfaceBake.format_of(kind)), kind + " editor: BC")
		if SurfaceBake.fallback_format_of(kind) != SurfaceBake.format_of(kind):
			assert_false(
				SurfaceBake.accepts(kind, SurfaceBake.fallback_format_of(kind)),
				kind + " editor: not the fallback"
			)
		SurfaceBake.compressor = NONE
		assert_true(SurfaceBake.accepts(kind, SurfaceBake.format_of(kind)), kind + " export: BC")
		assert_true(
			SurfaceBake.accepts(kind, SurfaceBake.fallback_format_of(kind)), kind + " export: fallback"
		)
	assert_false(SurfaceBake.accepts("albedo", Image.FORMAT_RGB8), "RGB8 never")


func test_the_fallback_formats_round_trip_the_cache_format() -> void:
	SurfaceBake.compressor = NONE
	for kind in ["albedo", "normal"]:
		var baked := SurfaceBake.bake(_source(kind), kind)
		var back := SurfaceCache.decode(SurfaceCache.encode(baked))
		assert_not_null(back, kind)
		if back != null:
			assert_eq(back.get_format(), baked.get_format(), kind)
			assert_eq(back.get_data(), baked.get_data(), kind)
	assert_eq(SurfaceBake.data_size(Image.FORMAT_RGBA8, 4, 4), 4 * (16 + 4 + 1))
	assert_eq(SurfaceBake.data_size(Image.FORMAT_RG8, 4, 4), 2 * (16 + 4 + 1))


func test_an_export_keeps_its_fallback_bake_in_the_cache() -> void:
	SurfaceBake.compressor = NONE
	var file := _map("albedo")
	var hash_text := _hash()
	var first := SurfaceStore.load_map(file, "albedo", LIBRARY_ID, SURFACE, hash_text)
	assert_eq(first["outcome"], "baked")
	assert_eq((first["image"] as Image).get_format(), Image.FORMAT_RGBA8)
	var second := SurfaceStore.load_map(file, "albedo", LIBRARY_ID, SURFACE, hash_text)
	assert_eq(second["outcome"], "hit", "the next open reads it (it re-baked every open before)")
	assert_false(second["rejected"])


func test_an_editor_rebakes_a_fallback_left_in_a_shared_cache() -> void:
	SurfaceBake.compressor = NONE
	var file := _map("normal")
	var hash_text := _hash()
	SurfaceStore.load_map(file, "normal", LIBRARY_ID, SURFACE, hash_text)
	SurfaceBake.compressor = AUTO
	var again := SurfaceStore.load_map(file, "normal", LIBRARY_ID, SURFACE, hash_text)
	assert_true(again["rejected"], "the RG8 file is not what an editor draws")
	assert_eq(again["outcome"], "baked")
	assert_eq((again["image"] as Image).get_format(), Image.FORMAT_RGTC_RG)


func test_entries_list_the_compressed_kinds_under_the_cache_key() -> void:
	var listed := Ship.entries(LIBS, SHIPPED)
	assert_eq(listed.size(), Ship.KINDS.size(), "albedo, normal and ORM; the height bakes in game")
	var hash_text := _hash()
	for entry in listed:
		assert_eq(entry["library"], LIBRARY_ID)
		assert_eq(entry["name"], SURFACE)
		assert_eq(entry["hash"], hash_text)
		assert_eq(
			entry["path"],
			SurfaceCache.shipped_path_for(LIBRARY_ID, hash_text, SURFACE, String(entry["kind"]))
		)
	assert_eq(Ship.library_id_of(ROOT), "", "a folder without library.json is no library")


func test_a_shipped_bake_is_read_first_and_never_written() -> void:
	SurfaceBake.compressor = AUTO
	for entry in Ship.entries(LIBS, SHIPPED):
		var bytes := Ship.bytes_for(entry)
		assert_false(bytes.is_empty(), String(entry["kind"]))
		_write_bytes(String(entry["path"]), bytes)
	# Even a binary that cannot compress gets BC maps for the shipped kinds.
	SurfaceBake.compressor = NONE
	var hash_text := _hash()
	for kind in Ship.KINDS:
		var loaded := SurfaceStore.load_map(_map(kind), kind, LIBRARY_ID, SURFACE, hash_text)
		assert_eq(loaded["outcome"], "hit", kind)
		assert_eq((loaded["image"] as Image).get_format(), SurfaceBake.format_of(kind), kind)
		var cached := SurfaceCache.path_for(LIBRARY_ID, hash_text, SURFACE, kind)
		assert_false(FileAccess.file_exists(cached), kind + " wrote no cache file")
	var height := SurfaceStore.load_map(_map("height"), "height", LIBRARY_ID, SURFACE, hash_text)
	assert_eq(height["outcome"], "baked", "the height is not shipped")
	assert_eq((height["image"] as Image).get_format(), Image.FORMAT_L8)


func test_a_shipped_bake_from_another_engine_is_taken() -> void:
	var baked := SurfaceBake.bake(_source("orm"), "orm")
	var bytes := SurfaceCache.encode(baked, "Godot 9.9 other")
	assert_null(SurfaceCache.decode(bytes), "the cache wants this engine's files")
	assert_eq(SurfaceCache.engine_of(bytes), "Godot 9.9 other")
	var path := SHIPPED.path_join("x.ttimg")
	_write_bytes(path, bytes)
	var shipped := SurfaceCache.read_shipped(path)
	assert_not_null(shipped, "pack content from the exporting editor")
	if shipped != null:
		assert_eq(shipped.get_data(), baked.get_data())
	assert_null(SurfaceCache.read_shipped(SHIPPED.path_join("missing.ttimg")))
	assert_eq(SurfaceCache.engine_of(PackedByteArray([1, 2, 3])), "")


func test_the_shipped_core_lists_every_set() -> void:
	var listed := Ship.entries()
	var sets := DirAccess.get_directories_at("res://libraries/core/surfaces")
	var core := listed.filter(func(e: Dictionary) -> bool: return e["library"] == "core")
	assert_eq(core.size(), sets.size() * Ship.KINDS.size(), "every core set ships its three BC maps")
	if core.is_empty():
		return
	var first: Dictionary = core[0]
	var dir := "res://libraries/core/surfaces".path_join(String(first["name"]))
	var files := {}
	for kind in SurfaceBake.KINDS:
		var file := SurfaceStore.map_file(dir, kind)
		if file != "":
			files[kind] = file
	assert_eq(first["hash"], SurfaceStore.files_hash(String(first["name"]), files), "the cache key")
	assert_true(String(first["path"]).begins_with(SurfaceCache.SHIPPED_ROOT + "/core/"))


# ---- helpers ----


func _source(kind: String) -> Image:
	var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for y in SIDE:
		for x in SIDE:
			match kind:
				"normal":
					var n := Vector3(rng.randf_range(-0.4, 0.4), rng.randf_range(-0.4, 0.4), 1.0)
					n = n.normalized() * 0.5 + Vector3.ONE * 0.5
					image.set_pixel(x, y, Color(n.x, n.y, n.z))
				_:
					image.set_pixel(x, y, Color(rng.randf(), rng.randf(), rng.randf()))
	if kind == "height":
		image.convert(Image.FORMAT_L8)
	return image


func _map(kind: String) -> String:
	return LIBS.path_join(LIBRARY_ID).path_join("surfaces").path_join(SURFACE).path_join(kind + ".png")


func _hash() -> String:
	var files := {}
	for kind in SurfaceBake.KINDS:
		files[kind] = _map(kind)
	return SurfaceStore.files_hash(SURFACE, files)


func _write_library() -> void:
	var folder := LIBS.path_join(LIBRARY_ID)
	_write_bytes(folder.path_join("library.json"), JSON.stringify({"id": LIBRARY_ID}).to_utf8_buffer())
	for kind in SurfaceBake.KINDS:
		_write_bytes(_map(kind), _source(kind).save_png_to_buffer())


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _remove_tree(path: String) -> void:
	if LibraryPaths.verify(path) != "":  # "" and "." mean the working directory (the project)
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)
