extends GutTest

## SurfaceStore.prebake (SurfacePrebake, card sysbake): maps baked on the worker lane are the
## same bytes as main-thread bakes, and so are the cache files they write; a map asked for while
## the lane holds it is taken over or waited for, never baked twice; forgetting drops the lane's
## results. Real core surfaces, each run with its own scratch cache so every bake is cold.

const ROOT := "user://test_surface_prebake"
const KINDS: Array[String] = ["albedo", "normal", "orm", "height"]

var _saved_cache_root: String = ""
var _names: PackedStringArray = PackedStringArray()


func before_all() -> void:
	_saved_cache_root = SurfaceCache.root
	var surfaces := PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT)
	var found: Array = []
	for name: String in surfaces:
		if SurfaceStore.is_library_surface(name):
			found.append(name)
	found.sort()
	_names = PackedStringArray(found.slice(0, 2))


func after_all() -> void:
	for cache in ["main", "lane", "claim", "forget"]:
		SurfaceCache.root = ROOT.path_join(cache)
		SurfaceCache.remove_library(LibraryContracts.CORE_ID)
		DirAccess.remove_absolute(ROOT.path_join(cache))
	DirAccess.remove_absolute(ROOT)
	SurfaceCache.root = _saved_cache_root
	SurfaceStore.clear_memory()
	SurfaceStore.reset_stats()


## A cold start: an empty scratch cache, nothing in memory, counters at zero.
func _cold(cache: String) -> void:
	SurfaceCache.root = ROOT.path_join(cache)
	SurfaceCache.remove_library(LibraryContracts.CORE_ID)
	SurfaceStore.clear_memory()
	SurfaceStore.reset_stats()


func _wait_lane() -> void:
	var frames := 0
	while SurfaceStore.is_prebaking() and frames < 1200:
		await wait_frames(1)
		frames += 1


## {"<surface> <kind>": SHA-256 of the baked map's data} through image_of.
func _digests() -> Dictionary:
	var out := {}
	for name in _names:
		for kind in KINDS:
			var image := SurfaceStore.image_of(PaletteLibrary.DEFAULT_ROOT, name, kind)
			out["%s %s" % [name, kind]] = _sha(image.get_data()) if image != null else ""
	return out


## {path under the cache root: SHA-256 of the file} of every cache file.
func _cache_files(cache: String) -> Dictionary:
	var out := {}
	_collect(ROOT.path_join(cache), ROOT.path_join(cache), out)
	return out


func _collect(base: String, path: String, out: Dictionary) -> void:
	for file_name in DirAccess.get_files_at(path):
		if file_name.get_extension() == SurfaceCache.FILE_EXTENSION:
			var full := path.path_join(file_name)
			out[full.substr(base.length())] = _sha(FileAccess.get_file_as_bytes(full))
	for sub in DirAccess.get_directories_at(path):
		_collect(base, path.path_join(sub), out)


func _sha(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


func test_lane_bakes_the_same_bytes_and_cache_files_as_the_main_thread() -> void:
	assert_eq(_names.size(), 2, "two core library surfaces")
	_cold("main")
	var main := _digests()
	assert_eq(SurfaceStore.stats["bakes"], 8, "the main thread baked every map")
	var main_files := _cache_files("main")
	_cold("lane")
	SurfaceStore.prebake(_names)
	assert_true(SurfaceStore.is_prebaking(), "the lane is working")
	await _wait_lane()
	assert_false(SurfaceStore.is_prebaking(), "the lane finished")
	var lane := _digests()
	assert_eq(SurfaceStore.stats["bakes"], 0, "nothing baked on the main thread")
	assert_eq(SurfaceStore.stats["prebakes"], 8, "every map came from the lane")
	assert_eq(lane, main, "byte-identical maps")
	assert_eq(_cache_files("lane"), main_files, "byte-identical cache files at the same paths")
	assert_eq(main_files.size(), 8)
	# A second prebake of maps in memory queues nothing.
	SurfaceStore.prebake(_names)
	assert_false(SurfaceStore.is_prebaking(), "maps in memory are not queued again")


func test_a_map_asked_for_while_queued_or_baking_is_baked_once() -> void:
	_cold("main")
	var main := _digests()
	_cold("claim")
	SurfaceStore.prebake(_names)
	# At once: the first albedo is baking or queued, the last height queued.
	var claimed := _digests()
	await _wait_lane()
	assert_eq(claimed, main, "the same bytes whoever baked them")
	var stats := SurfaceStore.stats
	assert_eq(int(stats["bakes"]) + int(stats["prebakes"]), 8, "each map baked once")
	assert_eq(_cache_files("claim").size(), 8)


func test_forget_drops_the_lane_results() -> void:
	_cold("forget")
	SurfaceStore.prebake(PackedStringArray([_names[0]]))
	await _wait_lane()
	SurfaceStore.clear_memory()
	SurfaceStore.reset_stats()
	var image := SurfaceStore.image_of(PaletteLibrary.DEFAULT_ROOT, _names[0], "albedo")
	assert_not_null(image)
	assert_eq(SurfaceStore.stats["prebakes"], 0, "the forgotten result was not handed out")
	assert_eq(SurfaceStore.stats["cache_hits"], 1, "the map came from the cache the lane wrote")


func test_unknown_and_plain_names_are_skipped() -> void:
	_cold("forget")
	SurfaceStore.prebake(PackedStringArray(["", "no_such_surface", "lib://nolib/none"]))
	assert_false(SurfaceStore.is_prebaking())
