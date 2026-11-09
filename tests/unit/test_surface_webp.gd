extends GutTest

## WebP surface maps (card texwebp, 2026-11-09): a library surface's maps may be lossless (or
## lossy) WebP as well as PNG, and core ships lossless WebP. A map served as WebP must bake to the
## same decompressed pixels as the same map served as PNG (within the BC7 bake's own 0 to 2 level
## run-to-run noise, card bakedet; height exactly), a set may mix the two, a folder holding both
## for one kind uses the WebP, and a corrupt, truncated or mislabelled WebP is refused the way a
## corrupt PNG is: by the header before anything is decoded, or by the decode.
##
## Fixture: the 16 px PNGs of tests/fixtures/library_surfaces/surfaces/lilac, re-encoded here as
## lossless WebP from their decoded pixels, as core's were.

const FIXTURE := "res://tests/fixtures/library_surfaces/surfaces/lilac"
const ROOT := "user://test_surface_webp"
const CACHE := ROOT + "/cache"
## The bakedet tolerance: two BC7 bakes of one input differ by 0 to 2 levels in a few blocks.
const BC_TOLERANCE := 4
## The first byte after a lossless WebP's 5-byte VP8L header (RIFF 12 + chunk 8 + 5).
const WEBP_PAYLOAD_START := 25

var _saved_cache_root: String = ""


func before_all() -> void:
	_saved_cache_root = SurfaceCache.root
	SurfaceCache.root = CACHE


func after_all() -> void:
	SurfaceCache.root = _saved_cache_root
	_remove_tree(ROOT)


func before_each() -> void:
	SurfaceStore.reset_stats()
	_remove_tree(CACHE)


# ---- helpers ----


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	for file_name in dir.get_files():
		dir.remove(file_name)
	DirAccess.remove_absolute(path)


func _png_bytes(kind: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(FIXTURE.path_join(kind + ".png"))


## The fixture map of `kind` as lossless WebP, encoded from its decoded pixels.
func _webp_bytes(kind: String) -> PackedByteArray:
	return SurfaceBake.decode(_png_bytes(kind), "png").save_webp_to_buffer(false, 1.0)


## A surface folder whose map of each kind is written as `formats[kind]` ("png" or "webp").
func _make_set(folder: String, formats: Dictionary) -> void:
	for kind: String in formats:
		var bytes := _webp_bytes(kind) if formats[kind] == "webp" else _png_bytes(kind)
		_write_bytes(folder.path_join("%s.%s" % [kind, formats[kind]]), bytes)
	_write_bytes(
		folder.path_join("surface.json"), '{"tile_m": 3, "role": "ground"}'.to_utf8_buffer()
	)


func _all(format: String) -> Dictionary:
	var out := {}
	for kind in SurfaceBake.KINDS:
		out[kind] = format
	return out


## The largest per-channel level difference between the top mips of two baked maps.
func _max_level_difference(a: Image, b: Image) -> int:
	var one := _mip0_rgba(a).get_data()
	var two := _mip0_rgba(b).get_data()
	if one.size() != two.size():
		return 256
	var worst := 0
	for i in one.size():
		worst = maxi(worst, absi(int(one[i]) - int(two[i])))
	return worst


func _mip0_rgba(baked: Image) -> Image:
	var image := baked.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


# ---- headers ----


func test_the_webp_header_reads_lossless_lossy_and_alpha_files() -> void:
	var lossless := _webp_bytes("albedo")
	var header := SurfaceBake.map_header(lossless, "webp", lossless.size())
	assert_true(header["ok"], str(header))
	assert_eq([header["width"], header["height"], header["bit_depth"]], [16, 16, 8])
	assert_eq(header["color_type"], 2, "no alpha reads as RGB")
	assert_eq(lossless.slice(12, 16).get_string_from_ascii(), "VP8L", "lossless")
	var lossy := SurfaceBake.decode(_png_bytes("albedo"), "png").save_webp_to_buffer(true, 0.9)
	var lossy_header := SurfaceBake.webp_header(lossy, lossy.size())
	assert_true(lossy_header["ok"], str(lossy_header))
	assert_eq([lossy_header["width"], lossy_header["height"]], [16, 16])
	var clear := Image.create(24, 8, false, Image.FORMAT_RGBA8)
	clear.fill(Color(1, 0, 0, 0.5))
	var with_alpha := SurfaceBake.webp_header(clear.save_webp_to_buffer(false, 1.0))
	assert_eq([with_alpha["width"], with_alpha["height"]], [24, 8])
	assert_eq(with_alpha["color_type"], 6, "alpha reads as RGBA")


func test_hostile_webp_headers_are_refused() -> void:
	var good := _webp_bytes("albedo")
	assert_false(SurfaceBake.webp_header(PackedByteArray())["ok"], "empty")
	assert_false(SurfaceBake.webp_header(good.slice(0, 20))["ok"], "too short")
	assert_false(SurfaceBake.webp_header(good, good.size() - 1)["ok"], "truncated: RIFF runs past")
	var wrong := good.duplicate()
	wrong[8] = 0x58
	assert_false(SurfaceBake.webp_header(wrong)["ok"], "not WEBP")
	var chunk := good.duplicate()
	chunk[15] = 0x58
	assert_false(SurfaceBake.webp_header(chunk)["ok"], "unknown first chunk")
	var animated := good.slice(0, 30)
	animated.encode_u32(12, 0x58385056)  # "VP8X"
	animated[20] = 0x02
	assert_false(SurfaceBake.webp_header(animated)["ok"], "an animation")
	assert_false(SurfaceBake.map_header(_png_bytes("albedo"), "webp")["ok"], "a PNG named .webp")
	assert_false(SurfaceBake.map_header(good, "png")["ok"], "a WebP named .png")
	assert_true(SurfaceBake.map_header(_png_bytes("albedo"), "png")["ok"])
	var errors: Array[String] = []
	var huge := {"ok": true, "width": 4096, "height": 16, "bit_depth": 8, "color_type": 2}
	SurfaceBake.check_png(huge, "albedo", "surface x", errors, [] as Array[String])
	assert_eq(errors.size(), 1, "a WebP header goes through the same size cap")


# ---- the same pixels ----


func test_a_webp_set_bakes_to_the_pixels_of_the_png_set() -> void:
	var png := SurfaceStore.load_set(ROOT + "/png/lilac", "a")
	assert_false(png["ok"], "nothing written yet")
	_make_set(ROOT + "/png/lilac", _all("png"))
	_make_set(ROOT + "/webp/lilac", _all("webp"))
	png = SurfaceStore.load_set(ROOT + "/png/lilac", "a")
	var webp := SurfaceStore.load_set(ROOT + "/webp/lilac", "b")
	assert_true(png["ok"], str(png["errors"]))
	assert_true(webp["ok"], str(webp["errors"]))
	assert_eq(SurfaceStore.stats["bakes"], 8, "both baked, nothing from a cache")
	for kind in SurfaceBake.KINDS:
		var a: Image = png["images"][kind]
		var b: Image = webp["images"][kind]
		assert_eq(b.get_format(), SurfaceBake.format_of(kind), kind + " format")
		assert_eq(b.get_mipmap_count(), a.get_mipmap_count(), kind + " mips")
		var limit := 0 if kind == "height" else BC_TOLERANCE
		assert_lte(_max_level_difference(a, b), limit, kind + " decompressed pixels")
	assert_eq(png["images"]["height"].get_data(), webp["images"]["height"].get_data(), "exact")


func test_the_decoded_webp_equals_the_decoded_png_exactly() -> void:
	for kind in SurfaceBake.KINDS:
		var source := SurfaceBake.decode(_png_bytes(kind), "png")
		var back := SurfaceBake.decode(_webp_bytes(kind), "webp")
		assert_not_null(back, kind)
		if back.get_format() != source.get_format():
			back.convert(source.get_format())
		assert_eq(back.get_data(), source.get_data(), kind + ": lossless means the same pixels")


# ---- mixed and doubled sets ----


func test_a_mixed_set_loads_every_map() -> void:
	var folder := ROOT + "/mixed/lilac"
	_make_set(folder, {"albedo": "webp", "normal": "png", "orm": "webp", "height": "png"})
	var loaded := SurfaceStore.load_set(folder, "mixed")
	assert_true(loaded["ok"], str(loaded["errors"]))
	for kind in SurfaceBake.KINDS:
		assert_eq((loaded["images"][kind] as Image).get_format(), SurfaceBake.format_of(kind))
	assert_eq(SurfaceStore.map_file(folder, "albedo").get_extension(), "webp")
	assert_eq(SurfaceStore.map_file(folder, "normal").get_extension(), "png")
	assert_eq(SurfaceStore.map_file(folder, "specular"), "")


func test_a_kind_with_both_files_uses_the_webp() -> void:
	var folder := ROOT + "/both/lilac"
	_make_set(folder, _all("webp"))
	var red := Image.create(16, 16, false, Image.FORMAT_RGB8)
	red.fill(Color(1, 0, 0))
	_write_bytes(folder.path_join("albedo.png"), red.save_png_to_buffer())
	var loaded := SurfaceStore.load_set(folder, "both")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var only_webp := SurfaceStore.load_set(ROOT + "/webp_only/lilac", "x")
	assert_false(only_webp["ok"])
	_make_set(ROOT + "/webp_only/lilac", _all("webp"))
	only_webp = SurfaceStore.load_set(ROOT + "/webp_only/lilac", "x")
	assert_lte(
		_max_level_difference(loaded["images"]["albedo"], only_webp["images"]["albedo"]),
		BC_TOLERANCE,
		"the red PNG beside it is not used"
	)
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var files := ["surfaces/lilac/surface.json", "surfaces/lilac/albedo.png"]
	files.append("surfaces/lilac/albedo.webp")
	var read := SurfaceReader.read(
		files, {"lilac": '{"tile_m": 3, "role": "ground"}'}, {}, errors, warnings
	)
	assert_eq(errors, [] as Array[String])
	assert_eq(read["surfaces"]["lilac"]["files"], {"albedo": "albedo.webp"})
	assert_string_contains("\n".join(warnings), "albedo.png is ignored (albedo.webp is used)")


func test_the_palette_entry_names_the_file_the_reader_found() -> void:
	var info := {"tile_m": 3.0, "role": "ground"}
	var maps := ["albedo", "normal"]
	var entry := SurfaceBake.palette_entry(
		"lib__x", info, maps, {"albedo": "albedo.webp", "normal": "normal.png"}
	)
	assert_eq(entry["albedo"], "surfaces/lib__x/albedo.webp")
	assert_eq(entry["normal"], "surfaces/lib__x/normal.png")
	assert_eq(entry["orm"], "")
	var plain := SurfaceBake.palette_entry("x", info, maps)
	assert_eq(plain["albedo"], "surfaces/x/albedo.png", "no files given: a PNG as before")


# ---- corrupt files ----


func test_a_truncated_or_corrupt_webp_is_refused_like_a_corrupt_png() -> void:
	var folder := ROOT + "/bad/lilac"
	_make_set(folder, _all("webp"))
	var good := FileAccess.get_file_as_bytes(folder.path_join("albedo.webp"))
	_write_bytes(folder.path_join("albedo.webp"), good.slice(0, good.size() / 2))
	var truncated := SurfaceStore.load_set(folder, "bad")
	assert_false(truncated["ok"], "a truncated WebP")
	assert_eq(SurfaceStore.stats["bakes"], 0, "refused by its header, nothing decoded")
	assert_string_contains(str(truncated["errors"]), "truncated")
	var garbled := good.duplicate()
	for i in range(WEBP_PAYLOAD_START, garbled.size()):
		garbled[i] = 0xFF
	_write_bytes(folder.path_join("albedo.webp"), garbled)
	var corrupt := SurfaceStore.load_set(folder, "bad")
	assert_false(corrupt["ok"], "a WebP whose data does not decode")
	assert_eq((corrupt["images"] as Dictionary).size(), 0)
	_write_bytes(folder.path_join("albedo.webp"), _png_bytes("albedo"))
	assert_false(SurfaceStore.load_set(folder, "bad")["ok"], "PNG bytes named .webp")
	_write_bytes(
		folder.path_join("albedo.webp"),
		"this is not a webp at all, just a long enough line of text".to_utf8_buffer()
	)
	assert_false(SurfaceStore.load_set(folder, "bad")["ok"], "text named .webp")
	var outcome := SurfaceStore.load_map(folder.path_join("albedo.webp"), "albedo", "bad", "x", "h")
	assert_null(outcome["image"])
	assert_eq(outcome["outcome"], "failed")
	# The garbled file: the WebP decoder's three errors and the store's warning; the text file:
	# the store's warning naming the header.
	assert_engine_error(5, "the decode failure and the two refusals are reported")
