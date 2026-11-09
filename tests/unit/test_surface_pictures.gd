extends GutTest

## Pictures of library surface maps (card coldopen): a Paint swatch and a biome picture's ground
## colour come from the map's decoded file (SurfaceStore.picture_image), never from a bake, so a
## picture neither queues nor waits for the 200 ms compression a cold albedo costs. They match the
## pictures the baked map made within the compression's error; the swatches warmed on workers are
## the ones palette_thumbnail makes on the main thread; the new-map dialog starts baking its
## chosen place's ground while the author looks. Real core surfaces, a scratch cache.

const ROOT := "user://test_surface_pictures"
const SWATCH_PX := 52
## The most one channel of a 52 px swatch may differ between the file's and the baked map's
## picture, in 8-bit levels: BC7's error after the 1024 -> 52 px Lanczos. Measured over all 39
## core albedos (card coldopen, 2026-11-09): 26 at most 1, 12 at most 2, one 3.
const MAX_SWATCH_LEVELS := 4
## The most one channel of an albedo's mean colour may move (0..1): measured at most 0.00196 (half
## a level), and the biome pictures' lifted ground colours at most 0.00202.
const MAX_MEAN_DIFF := 0.003

var _saved_cache_root := ""
var _albedos := PackedStringArray()


func before_all() -> void:
	_saved_cache_root = SurfaceCache.root
	SurfaceCache.root = ROOT
	SurfaceStore.clear_memory()
	SurfaceStore.reset_stats()
	var surfaces := PaletteLibrary.surfaces(PaletteLibrary.DEFAULT_ROOT)
	var names: Array = []
	for name: String in surfaces:
		if SurfaceStore.is_library_surface(name):
			names.append(name)
	names.sort()
	for name: String in names.slice(0, 3):
		_albedos.append(String(surfaces[name]["albedo"]))


func after_all() -> void:
	await _wait_lane()
	SurfaceCache.remove_library(LibraryContracts.CORE_ID)
	DirAccess.remove_absolute(ROOT)
	SurfaceCache.root = _saved_cache_root
	SurfaceStore.clear_memory()
	SurfaceStore.reset_stats()
	SwatchTextures._cache.clear()
	BiomeThumbnail._means.clear()


func _queued() -> int:
	return SurfaceStore._prebake.queued().size() if SurfaceStore._prebake != null else -1


func _wait_lane() -> void:
	var frames := 0
	while SurfaceStore.is_prebaking() and frames < 1200:
		await wait_frames(1)
		frames += 1


## The largest channel difference of two pictures' top levels (a baked map's picture carries the
## mips its source had; the top level is what a tile shows at its size).
func _max_level_diff(a: Image, b: Image) -> int:
	var x := a.duplicate() as Image
	var y := b.duplicate() as Image
	x.clear_mipmaps()
	y.clear_mipmaps()
	x.convert(Image.FORMAT_RGBA8)
	y.convert(Image.FORMAT_RGBA8)
	var dx := x.get_data()
	var dy := y.get_data()
	var worst := 0
	for i in dx.size():
		worst = maxi(worst, absi(dx[i] - dy[i]))
	return worst


## The decompressed albedo bake of `source`, as SurfaceStore.texture() handed it to pictures.
func _baked(source: Image) -> Image:
	var baked := SurfaceBake.bake(source, "albedo")
	baked.decompress()
	return baked


func test_a_picture_is_the_decoded_file_and_bakes_nothing() -> void:
	SurfaceStore.reset_stats()
	var root := PaletteLibrary.DEFAULT_ROOT
	var picture := SurfaceStore.picture_image(root, _albedos[0])
	assert_not_null(picture)
	assert_false(picture.is_compressed())
	var file := String(SurfaceStore.picture_source(root, _albedos[0])["file"])
	var decoded := SurfaceBake.decode(FileAccess.get_file_as_bytes(file), file.get_extension())
	assert_eq(picture.get_data(), decoded.get_data(), "the file's own pixels")
	var stats := SurfaceStore.stats
	assert_eq(int(stats["bakes"]) + int(stats["cache_hits"]) + int(stats["prebakes"]), 0)
	assert_false(SurfaceStore.is_prebaking(), "nothing queued on the lane")
	assert_eq(SurfaceStore.picture_source(root, "no/such/path.png"), {})


func test_a_hostile_or_missing_file_gives_no_picture() -> void:
	assert_null(SurfaceStore.decode_picture(ROOT.path_join("missing.webp"), "albedo"))
	DirAccess.make_dir_recursive_absolute(ROOT)
	var garbled := ROOT.path_join("garbled.webp")
	var f := FileAccess.open(garbled, FileAccess.WRITE)
	f.store_buffer("RIFF0000WEBPVP8 not really".to_utf8_buffer())
	f.close()
	assert_null(SurfaceStore.decode_picture(garbled, "albedo"))
	DirAccess.remove_absolute(garbled)


func test_a_swatch_and_a_mean_match_the_baked_maps_within_the_compression_error() -> void:
	var root := PaletteLibrary.DEFAULT_ROOT
	BiomeThumbnail._means.clear()
	for albedo in _albedos:
		var source := SurfaceStore.picture_image(root, albedo)
		var baked := _baked(source)
		var levels := _max_level_diff(
			SwatchTextures.square_tile(baked, SWATCH_PX), SwatchTextures.square_tile(source, SWATCH_PX)
		)
		assert_lte(levels, MAX_SWATCH_LEVELS, "%s swatch within %d levels" % [albedo, levels])
		var small := baked.duplicate() as Image
		small.clear_mipmaps()
		small.resize(8, 8, Image.INTERPOLATE_LANCZOS)
		var sum := Vector3.ZERO
		for y in 8:
			for x in 8:
				var p := small.get_pixel(x, y)
				sum += Vector3(p.r, p.g, p.b)
		sum /= 64.0
		var mean := BiomeThumbnail._mean(root, albedo)
		for c in 3:
			assert_almost_eq(mean[c], sum[c], MAX_MEAN_DIFF, "%s mean channel %d" % [albedo, c])


func test_swatches_warmed_on_workers_are_the_main_threads() -> void:
	var root := PaletteLibrary.DEFAULT_ROOT
	SwatchTextures._cache.clear()
	SurfaceStore.reset_stats()
	var never := func() -> bool: return false
	await SwatchTextures.warm_async(_albedos, SWATCH_PX, root, get_tree(), never)
	var warmed: Array[PackedByteArray] = []
	for albedo in _albedos:
		var tile := SwatchTextures.palette_thumbnail(albedo, SWATCH_PX, root)
		warmed.append(tile.get_image().get_data())
	SwatchTextures._cache.clear()
	for i in _albedos.size():
		var direct := SwatchTextures.palette_thumbnail(_albedos[i], SWATCH_PX, root).get_image()
		assert_eq(direct.get_data(), warmed[i], "%s the same swatch" % _albedos[i])
	var stats := SurfaceStore.stats
	assert_eq(int(stats["bakes"]) + int(stats["prebakes"]), 0, "nothing baked for a swatch")
	assert_false(SurfaceStore.is_prebaking(), "nothing queued on the lane")


func test_the_new_map_dialog_starts_baking_its_places_ground() -> void:
	await _wait_lane()
	SurfaceStore.clear_memory()
	var dialog: Node = load("res://scenes/states/authoring/new_map_dialog.tscn").instantiate()
	add_child_autofree(dialog)
	# Process frames: the dialog queues them a frame after it is built.
	await wait_process_frames(3)
	var planned := NewMap.planned_surfaces({"biome_id": String(dialog.get("_biome_id"))})
	assert_false(planned.is_empty())
	assert_true(
		SurfaceStore.prebaking(planned),
		(
			"the chosen place's ground is on the lane: planned %s, lane busy %s, queued %d"
			% [planned, SurfaceStore.is_prebaking(), _queued()]
		)
	)
	# Drops the queued jobs (the one baking finishes into the scratch cache).
	SurfaceStore.clear_memory()
	await _wait_lane()
