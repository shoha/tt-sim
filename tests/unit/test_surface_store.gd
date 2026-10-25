extends GutTest

## Content-library surfaces (step S3): SurfaceBake / SurfaceReader / SurfaceCache / SurfaceStore
## and the library bindings (utils/library/). A surface set that comes from PNG files with no
## editor import must give the textures the import gives the installed palette's surfaces (same
## format, size and mip chain; normal, ORM and height byte for byte, albedo the same colours), a
## second load must come from the raw cache, a cache from another engine or a damaged one must be
## ignored and baked again, hostile files must be refused, and the library reader, compiler,
## registry and the ground code must carry a library's own surfaces and bindings through.
##
## Fixture: tests/fixtures/library_surfaces (JSON and 16 px PNGs; this test copies it under
## user:// and writes its one GLB there). The shipped core's `ash` surface stands for a real set;
## the fixture's own editor-imported PNGs stand for the legacy form (a path ResourceLoader loads).

const FIXTURE := "res://tests/fixtures/library_surfaces"
const INSTALLED := "res://libraries/core/surfaces"
const ROOT := "user://test_surface_store"
const LIBRARY := ROOT + "/surf"
const BASE := ROOT + "/base"
const CACHE := ROOT + "/cache"
const SETTINGS := ROOT + "/settings.cfg"
const FIXTURE_FILES: Array[String] = [
	"library.json",
	"assets/catalog.json",
	"biomes/meadow.json",
	"surfaces/lilac/surface.json",
	"surfaces/slate/surface.json",
	"surfaces/boards/surface.json",
]
const PURE_MODULES: Array[String] = [
	"surface_bake", "surface_reader", "library_bindings", "library_ids"
]

var _saved_settings_path: String = ""
var _saved_cache_root: String = ""
var _saved_official: String = ""


func before_all() -> void:
	_saved_settings_path = LibraryRegistry.settings_path
	_saved_cache_root = SurfaceCache.root
	_saved_official = LibraryRegistry.official_root
	LibraryRegistry.settings_path = SETTINGS
	# The shipped core is not part of these scratch worlds.
	LibraryRegistry.official_root = ROOT + "/no_official"
	SurfaceCache.root = CACHE
	_write_base()
	_copy_fixture()


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings_path
	LibraryRegistry.official_root = _saved_official
	SurfaceCache.root = _saved_cache_root
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	_remove_tree(ROOT)


func before_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	SurfaceStore.clear_libraries()
	SurfaceStore.reset_stats()
	_remove_tree(CACHE)


# ---- fixtures ----


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(bytes)
	file.close()


## The fixture library under user://, its three surfaces' PNGs copied byte for byte and its
## one GLB written (the reader checks that every catalog file exists).
func _copy_fixture() -> void:
	for relative in FIXTURE_FILES:
		_write_text(
			LIBRARY.path_join(relative), FileAccess.get_file_as_string(FIXTURE.path_join(relative))
		)
	for surface in ["lilac", "slate", "boards"]:
		for kind in SurfaceBake.KINDS:
			var relative := "surfaces/%s/%s.png" % [surface, kind]
			_write_bytes(
				LIBRARY.path_join(relative),
				FileAccess.get_file_as_bytes(FIXTURE.path_join(relative))
			)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(
		[Vector3(0, 0, 0), Vector3(0.5, 0, 0.2), Vector3(0, 2, 0.1)]
	)
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, StandardMaterial3D.new())
	var root := Node3D.new()
	root.name = "Root"
	var node := MeshInstance3D.new()
	node.name = "Tree_Oak_v0_LOD0"
	node.mesh = mesh
	root.add_child(node)
	node.owner = root
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	document.append_from_scene(root, state)
	DirAccess.make_dir_recursive_absolute(LIBRARY.path_join("assets/tree"))
	document.write_to_filesystem(state, LIBRARY.path_join("assets/tree/Tree_Oak_v0.glb"))
	root.free()


## A palette root of its own with the surfaces the fixture biome names from the installed
## palette (grass_meadow, flagstone, grass) and a forest biome the library must leave be.
func _write_base() -> void:
	var surfaces := {}
	for name in ["grass", "grass_meadow", "flagstone"]:
		surfaces[name] = {
			"albedo": "surfaces/%s/albedo.png" % name,
			"normal": "surfaces/%s/normal.png" % name,
			"orm": "surfaces/%s/orm.png" % name,
			"height": "surfaces/%s/height.png" % name,
			"tile_m": 2.0,
			"kind": name,
			"role": "built" if name == "flagstone" else "ground",
		}
	var document := {
		"format": 1,
		"palette_version": "base",
		"surfaces": surfaces,
		"biomes":
		[
			{
				"id": "forest_summer_s1",
				"biome": "forest",
				"season": "summer",
				"seed": 1,
				"name": "Forest",
				"ground_surface": "grass",
				"species":
				[
					{
						"key": "oak",
						"kind": "tree",
						"size_class": "large",
						"density_per_m2": 0.01,
						"assets": ["forest_summer_s1/Oak"],
					}
				],
			}
		],
		"assets":
		{
			"forest_summer_s1/Oak":
			{
				"file": "assets/forest_summer_s1/Oak.glb",
				"node": "Oak",
				"wind_category": "tree",
				"size_class": "large",
				"dimensions_m": [5, 7, 5],
			}
		},
	}
	_write_text(BASE.path_join("palette.json"), JSON.stringify(document))


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


## The shipped core's `ash` surface as a library surface folder (albedo.png ... plus surface.json).
func _install_as_set(name: String, folder: String) -> void:
	for kind in SurfaceBake.KINDS:
		var source := INSTALLED.path_join("%s/%s.png" % [name, kind])
		_write_bytes(folder.path_join(kind + ".png"), FileAccess.get_file_as_bytes(source))
	var info := _core_info(name)
	_write_text(folder.path_join("surface.json"), JSON.stringify(info))


## The shipped core surface `name`'s surface.json, parsed.
func _core_info(name: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(INSTALLED.path_join("%s/surface.json" % name))
	return JSON.parse_string(text)


func _read_fixture_sources() -> Dictionary:
	var sources := LibraryRegistry.read_sources(LIBRARY)
	assert_false(sources.has("error"), "the fixture copy is a folder")
	return sources


# ---- PNG headers and surface.json ----


func test_png_header_reads_a_real_png_and_refuses_hostile_bytes() -> void:
	var good := FileAccess.get_file_as_bytes(FIXTURE.path_join("surfaces/lilac/albedo.png"))
	var header := SurfaceBake.png_header(good)
	assert_true(header["ok"])
	assert_eq([header["width"], header["height"], header["bit_depth"]], [16, 16, 8])
	assert_false(SurfaceBake.png_header(PackedByteArray())["ok"], "empty")
	assert_false(SurfaceBake.png_header(good.slice(0, 20))["ok"], "truncated")
	var wrong := good.duplicate()
	wrong[1] = 0x51
	assert_false(SurfaceBake.png_header(wrong)["ok"], "bad signature")
	var no_ihdr := good.duplicate()
	no_ihdr[12] = 0x58
	assert_false(SurfaceBake.png_header(no_ihdr)["ok"], "no IHDR chunk")


func test_png_sizes_depths_and_normal_colour_types_are_checked() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var huge := {"ok": true, "width": 4096, "height": 4096, "bit_depth": 8, "color_type": 2}
	SurfaceBake.check_png(huge, "albedo", "surface x", errors, warnings)
	assert_eq(errors.size(), 1, "4096 is over the 2048 cap")
	errors.clear()
	var tiny := {"ok": true, "width": 2, "height": 2, "bit_depth": 8, "color_type": 2}
	SurfaceBake.check_png(tiny, "albedo", "surface x", errors, warnings)
	assert_eq(errors.size(), 1, "2 px is under one block")
	errors.clear()
	var deep := {"ok": true, "width": 1024, "height": 1024, "bit_depth": 4, "color_type": 2}
	SurfaceBake.check_png(deep, "orm", "surface x", errors, warnings)
	assert_eq(errors.size(), 1, "4 bit")
	errors.clear()
	var grey := {"ok": true, "width": 1024, "height": 1024, "bit_depth": 8, "color_type": 0}
	SurfaceBake.check_png(grey, "normal", "surface x", errors, warnings)
	assert_eq(errors.size(), 1, "a grey normal map has no red and green")
	errors.clear()
	warnings.clear()
	var odd := {"ok": true, "width": 512, "height": 512, "bit_depth": 16, "color_type": 0}
	SurfaceBake.check_png(odd, "height", "surface x", errors, warnings)
	assert_eq(errors.size(), 0, "a 16 bit grey height map at 512 is usable")
	assert_eq(warnings.size(), 1, "but not the 1024 the arrays expect")
	errors.clear()
	SurfaceBake.check_png({"ok": false, "error": "not a PNG"}, "albedo", "s", errors, warnings)
	assert_eq(errors.size(), 1)


func test_surface_json_fields_ranges_and_hostile_text() -> void:
	var ok := SurfaceBake.check_info(
		(
			'{"label": "Crystal sand", "kind": "sand", "role": "ground", "tile_m": 4.0,'
			+ ' "albedo_mean_linear": [0.3, 0.2, 0.2]}'
		),
		"crystal_sand"
	)
	assert_true(ok["ok"])
	assert_eq(ok["info"]["label"], "Crystal sand")
	assert_eq(ok["info"]["albedo_mean_linear"], [0.3, 0.2, 0.2])
	var bare := SurfaceBake.check_info('{"tile_m": 2}', "crystal_sand")
	assert_true(bare["ok"])
	assert_eq(bare["info"]["label"], "Crystal sand", "the name prettified")
	assert_eq(bare["info"]["role"], "ground")
	assert_eq((bare["warnings"] as Array).size(), 1, "no role is a warning")
	for text in [
		"",
		"[]",
		"not json",
		'{"role": "ground"}',
		'{"tile_m": 0}',
		'{"tile_m": 20000}',
		'{"tile_m": "4"}',
		'{"tile_m": null}',
		'{"tile_m": true}',
	]:
		assert_false(SurfaceBake.check_info(text, "x")["ok"], "refused: " + text)
	var odd := SurfaceBake.check_info(
		'{"tile_m": 2, "role": "lava", "albedo_mean_linear": [2, 0, 0], "extra": 1, "label": 5}',
		"x"
	)
	assert_true(odd["ok"], "bad optional fields degrade to warnings")
	assert_eq(odd["info"]["role"], "ground")
	assert_false(odd["info"].has("albedo_mean_linear"))
	assert_eq(odd["info"]["label"], "X", "a non-string label falls back")
	assert_eq((odd["warnings"] as Array).size(), 3)
	var big := '{"tile_m": 2, "label": "%s"}' % "a".repeat(SurfaceBake.MAX_INFO_BYTES)
	assert_false(SurfaceBake.check_info(big, "x")["ok"], "over the byte cap")


# ---- the bake and the formats ----


func test_bake_gives_the_imported_formats_and_full_mip_chains() -> void:
	for kind in SurfaceBake.KINDS:
		var source := Image.load_from_file(
			ProjectSettings.globalize_path(FIXTURE.path_join("surfaces/lilac/%s.png" % kind))
		)
		var baked := SurfaceBake.bake(source, kind)
		assert_not_null(baked, kind)
		assert_eq(baked.get_format(), SurfaceBake.format_of(kind), kind)
		assert_eq(baked.get_size(), Vector2i(16, 16))
		assert_eq(baked.get_mipmap_count(), 4, "16, 8, 4, 2, 1")
		assert_eq(baked.get_data().size(), SurfaceBake.data_size(baked.get_format(), 16, 16), kind)
	assert_eq(SurfaceBake.format_of("albedo"), Image.FORMAT_BPTC_RGBA)
	assert_eq(SurfaceBake.format_of("normal"), Image.FORMAT_RGTC_RG)
	assert_eq(SurfaceBake.format_of("orm"), Image.FORMAT_DXT1)
	assert_eq(SurfaceBake.format_of("height"), Image.FORMAT_L8)
	assert_null(SurfaceBake.bake(null, "albedo"))
	assert_null(SurfaceBake.bake(Image.create(8, 8, false, Image.FORMAT_RGB8), "specular"))
	assert_null(
		SurfaceBake.bake(Image.create(2049, 8, false, Image.FORMAT_RGB8), "albedo"), "over the cap"
	)


func test_data_size_matches_a_baked_core_surface() -> void:
	var folder := ROOT + "/inst/ash_size"
	_install_as_set("ash", folder)
	var loaded := SurfaceStore.load_set(folder, "inst")
	assert_true(loaded["ok"], str(loaded["errors"]))
	var image: Image = loaded["images"]["albedo"]
	assert_eq(SurfaceBake.data_size(image.get_format(), 1024, 1024), image.get_data().size())
	assert_eq(SurfaceBake.data_size(Image.FORMAT_DXT1, 1024, 1024), 699064)
	assert_eq(SurfaceBake.data_size(Image.FORMAT_L8, 1024, 1024), 1398101)
	assert_eq(SurfaceBake.data_size(Image.FORMAT_RGBA8, 4, 4), -1, "not a baked format")


func test_a_real_png_set_bakes_to_the_imported_formats_and_uses_the_given_mean() -> void:
	var folder := ROOT + "/inst/ash"
	_install_as_set("ash", folder)
	var loaded := SurfaceStore.load_set(folder, "inst")
	assert_true(loaded["ok"], str(loaded["errors"]))
	assert_eq((loaded["warnings"] as Array).size(), 0, "1024 px maps, a clean surface.json")
	for kind in SurfaceBake.KINDS:
		var mine: Image = loaded["images"][kind]
		assert_eq(mine.get_format(), SurfaceBake.format_of(kind), kind + " format")
		assert_eq(mine.get_size(), Vector2i(1024, 1024), kind + " size")
		assert_eq(mine.get_mipmap_count(), 10, kind + " mips below the first: 512 down to 1")
		assert_eq(
			mine.get_data().size(),
			SurfaceBake.data_size(mine.get_format(), 1024, 1024),
			kind + " bytes"
		)
	var mean: Color = loaded["mean_albedo_linear"]
	var listed: Array = _core_info("ash")["albedo_mean_linear"]
	assert_almost_eq(mean.r, float(listed[0]), 0.0001, "the surface.json mean is used as given")


func test_the_measured_mean_matches_the_surface_json_mean() -> void:
	var folder := ROOT + "/inst/ash_no_mean"
	_install_as_set("ash", folder)
	var info: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(folder.path_join("surface.json"))
	)
	info.erase("albedo_mean_linear")
	_write_text(folder.path_join("surface.json"), JSON.stringify(info))
	var loaded := SurfaceStore.load_set(folder, "inst")
	assert_true(loaded["ok"])
	var mean: Color = loaded["mean_albedo_linear"]
	var listed: Array = _core_info("ash")["albedo_mean_linear"]
	assert_almost_eq(mean.r, float(listed[0]), 0.01)
	assert_almost_eq(mean.g, float(listed[1]), 0.01)
	assert_almost_eq(mean.b, float(listed[2]), 0.01)


# ---- the raw cache ----


func test_the_second_load_comes_from_the_cache() -> void:
	var folder := LIBRARY.path_join("surfaces/lilac")
	var first := SurfaceStore.load_set(folder, "surf")
	assert_true(first["ok"], str(first["errors"]))
	assert_eq(SurfaceStore.stats["bakes"], 4)
	assert_eq(SurfaceStore.stats["cache_hits"], 0)
	var second := SurfaceStore.load_set(folder, "surf")
	assert_true(second["ok"])
	assert_eq(SurfaceStore.stats["bakes"], 4, "nothing baked again")
	assert_eq(SurfaceStore.stats["cache_hits"], 4)
	for kind in SurfaceBake.KINDS:
		assert_true(first["images"][kind].get_data() == second["images"][kind].get_data(), kind)
		assert_eq(second["images"][kind].get_format(), SurfaceBake.format_of(kind))
	var files := _cache_files()
	assert_eq(files.size(), 4, "one file a map")
	for file in files:
		assert_true(file.begins_with(CACHE + "/surf/"), "under the library's folder")
		assert_true(file.ends_with("." + SurfaceCache.FILE_EXTENSION))


func test_editing_a_png_changes_the_cache_folder() -> void:
	var folder := ROOT + "/edit/lilac"
	for kind in SurfaceBake.KINDS:
		_write_bytes(
			folder.path_join(kind + ".png"),
			FileAccess.get_file_as_bytes(FIXTURE.path_join("surfaces/lilac/%s.png" % kind))
		)
	_write_text(folder.path_join("surface.json"), '{"tile_m": 3, "role": "ground"}')
	assert_true(SurfaceStore.load_set(folder, "edit")["ok"])
	var edited := Image.create(16, 16, false, Image.FORMAT_RGB8)
	edited.fill(Color(0.9, 0.1, 0.1))
	edited.save_png(folder.path_join("albedo.png"))
	SurfaceStore.reset_stats()
	assert_true(SurfaceStore.load_set(folder, "edit")["ok"])
	assert_eq(SurfaceStore.stats["bakes"], 4, "a new hash, so a new bake")
	assert_eq(SurfaceStore.stats["cache_hits"], 0)


func test_a_cache_from_another_engine_is_ignored_and_replaced() -> void:
	var folder := LIBRARY.path_join("surfaces/slate")
	assert_true(SurfaceStore.load_set(folder, "surf")["ok"])
	var files := _cache_files()
	var path := ""
	for file in files:
		if file.ends_with("slate_orm.ttimg"):
			path = file
	assert_ne(path, "")
	var image := SurfaceCache.read(path)
	assert_not_null(image, "this engine reads its own cache")
	assert_null(
		SurfaceCache.decode(SurfaceCache.encode(image, "Godot v3.0.0 abc")), "another engine"
	)
	_write_bytes(path, SurfaceCache.encode(image, "Godot v3.0.0 abc"))
	assert_null(SurfaceCache.read(path), "a cache of another engine does not decode")
	SurfaceStore.reset_stats()
	var again := SurfaceStore.load_set(folder, "surf")
	assert_true(again["ok"])
	assert_eq(SurfaceStore.stats["cache_hits"], 3)
	assert_eq(SurfaceStore.stats["cache_rejects"], 1)
	assert_eq(SurfaceStore.stats["bakes"], 1, "the mismatched map is baked anew")
	assert_not_null(SurfaceCache.read(path), "and the file now carries this engine")


func test_a_damaged_cache_is_refused() -> void:
	var source := SurfaceBake.bake(
		Image.load_from_file(
			ProjectSettings.globalize_path(FIXTURE.path_join("surfaces/boards/albedo.png"))
		),
		"albedo"
	)
	var good := SurfaceCache.encode(source)
	assert_not_null(SurfaceCache.decode(good), "the intact file decodes")
	assert_true(SurfaceCache.decode(good).get_data() == source.get_data())
	assert_null(SurfaceCache.decode(PackedByteArray()), "empty")
	assert_null(SurfaceCache.decode(good.slice(0, good.size() - 1)), "one byte short")
	assert_null(SurfaceCache.decode(good.slice(0, 30)), "cut in the header")
	var padded := good.duplicate()
	padded.append(0)
	assert_null(SurfaceCache.decode(padded), "one byte long")
	var flipped := good.duplicate()
	flipped[flipped.size() - 5] = flipped[flipped.size() - 5] ^ 0xFF
	assert_null(SurfaceCache.decode(flipped), "a payload byte changed")
	var magic := good.duplicate()
	magic[0] = 0x58
	assert_null(SurfaceCache.decode(magic), "wrong magic")
	var version := good.duplicate()
	version[5] = 99
	assert_null(SurfaceCache.decode(version), "wrong version")
	var engine_length := good.decode_u16(6)
	var at := 8 + engine_length
	for patch in [[at, 0xFFFFFFFF, "format"], [at + 4, 0xFFFFFFFF, "width"], [at + 8, 0, "height"]]:
		var broken := good.duplicate()
		broken.encode_u32(patch[0], patch[1])
		assert_null(SurfaceCache.decode(broken), "hostile " + patch[2])
	var lying := good.duplicate()
	lying.encode_u32(at + 13, 4)
	assert_null(SurfaceCache.decode(lying), "a data length that is not the format's size")
	var long_engine := good.duplicate()
	long_engine.encode_u16(6, 60000)
	assert_null(SurfaceCache.decode(long_engine), "an engine string longer than the file")


func test_a_corrupted_cache_file_is_baked_again() -> void:
	var folder := LIBRARY.path_join("surfaces/boards")
	assert_true(SurfaceStore.load_set(folder, "surf")["ok"])
	for file in _cache_files():
		var bytes := FileAccess.get_file_as_bytes(file)
		bytes[bytes.size() - 3] = bytes[bytes.size() - 3] ^ 0xFF
		_write_bytes(file, bytes)
	SurfaceStore.reset_stats()
	var again := SurfaceStore.load_set(folder, "surf")
	assert_true(again["ok"], "damaged caches never fail a load")
	assert_eq(SurfaceStore.stats["cache_rejects"], 4)
	assert_eq(SurfaceStore.stats["bakes"], 4)
	assert_eq(again["images"]["albedo"].get_format(), Image.FORMAT_BPTC_RGBA)


func _cache_files() -> Array[String]:
	var out: Array[String] = []
	_collect(CACHE, out)
	return out


func _collect(path: String, out: Array[String]) -> void:
	for file_name in DirAccess.get_files_at(path):
		if file_name != SafeDelete.MARKER:  # the ownership marker is not a cache file
			out.append(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_collect(path.path_join(sub), out)


# ---- hostile sets ----


func test_a_set_with_a_hostile_header_is_refused_before_it_is_decoded() -> void:
	var folder := ROOT + "/hostile/bomb"
	for kind in SurfaceBake.KINDS:
		_write_bytes(
			folder.path_join(kind + ".png"),
			FileAccess.get_file_as_bytes(FIXTURE.path_join("surfaces/lilac/%s.png" % kind))
		)
	_write_text(folder.path_join("surface.json"), '{"tile_m": 3}')
	var bomb := FileAccess.get_file_as_bytes(folder.path_join("albedo.png"))
	bomb.encode_u32(16, 60000)
	bomb.encode_u32(20, 60000)
	_write_bytes(folder.path_join("albedo.png"), bomb)
	var loaded := SurfaceStore.load_set(folder, "hostile")
	assert_false(loaded["ok"])
	assert_eq((loaded["images"] as Dictionary).size(), 0)
	assert_eq(SurfaceStore.stats["bakes"], 0, "nothing was decoded")
	var text := _write_png_with_text(folder.path_join("height.png"))
	assert_true(text, "a non-PNG file in a map slot")
	var not_png := SurfaceStore.load_set(folder, "hostile")
	assert_false(not_png["ok"])


func _write_png_with_text(path: String) -> bool:
	_write_text(path, "this is not a png at all, just a long enough line of text to pass 33 bytes")
	return true


func test_a_set_missing_its_albedo_or_surface_json_is_refused() -> void:
	var folder := ROOT + "/hostile/bare"
	_write_text(folder.path_join("surface.json"), '{"tile_m": 3}')
	assert_false(SurfaceStore.load_set(folder, "hostile")["ok"], "no maps at all")
	assert_false(SurfaceStore.load_set(ROOT + "/hostile/nothing", "hostile")["ok"], "no folder")
	assert_false(SurfaceStore.load_set(ROOT + "/hostile/Bad_Name", "hostile")["ok"], "upper case")


func test_surface_names_and_references_cannot_climb_or_smuggle() -> void:
	for name in ["", "..", ".", "a/b", "a\\b", "Crystal", "con", "nul", "a__b", "x:y", "a b", "-a"]:
		assert_gt(LibraryIds.surface_problems(name).size(), 0, "refused: '%s'" % name)
	for name in ["crystal_sand", "a", "grass_alpine2"]:
		assert_eq(LibraryIds.surface_problems(name).size(), 0, name)
	for ref in [
		"lib://",
		"lib://core",
		"lib://core/",
		"lib:///x",
		"lib://../x",
		"lib://core/../x",
		"lib://core/a/b",
		"lib://a__b/x",
		"lib://Core/x",
		"lib://core/X",
		"lib://core/con",
		"LIB://core/x",
		"file://core/x",
		"ash",
	]:
		assert_true(LibraryIds.parse_surface_ref(ref).is_empty(), "not a reference: " + ref)
	var parsed := LibraryIds.parse_surface_ref("lib://my-lib/crystal_sand")
	assert_eq(parsed, {"library": "my-lib", "name": "crystal_sand"})


# ---- names ----


func test_references_and_runtime_names_round_trip() -> void:
	assert_eq(SurfaceStore.runtime_name("ash"), "ash", "a legacy name stays")
	assert_eq(SurfaceStore.runtime_name("lib://core/ash"), "ash", "core is bare")
	assert_eq(SurfaceStore.runtime_name("lib://mylib/crystal"), "mylib__crystal")
	assert_eq(SurfaceStore.runtime_name("lib://../x"), "lib://../x", "a hostile one is left alone")
	assert_eq(SurfaceStore.ref_of("ash"), "lib://core/ash")
	assert_eq(SurfaceStore.ref_of("mylib__crystal"), "lib://mylib/crystal")
	assert_eq(LibraryIds.surface_ref("core", "ash"), "lib://core/ash")


# ---- the reader ----


func test_the_reader_reads_the_surfaces_folder() -> void:
	var read := LibraryReader.read(_read_fixture_sources())
	assert_true(read["ok"], str(read["errors"]))
	assert_eq(read["surface_order"], ["boards", "lilac", "slate"])
	assert_eq(read["surfaces"]["slate"]["info"]["role"], "cliff")
	assert_eq(read["surfaces"]["lilac"]["maps"], ["albedo", "normal", "orm", "height"])
	var odd_size: Array = (read["warnings"] as Array).filter(
		func(w: String) -> bool: return "is not 1024" in w
	)
	assert_eq(odd_size.size(), 12, "every 16 px map says the arrays expect 1024")


func test_the_reader_refuses_hostile_surface_folders() -> void:
	var sources := _read_fixture_sources()
	var files: Array = sources["files"]
	var cases := {
		"traversal": files + ["surfaces/../escape/albedo.png"],
		"upper case": files + ["surfaces/Rock/albedo.png"],
		"double underscore": files + ["surfaces/a__b/albedo.png"],
		"device name": files + ["surfaces/con/albedo.png"],
		"case twin": files + ["surfaces/lilac/ALBEDO.png"],
		"backslash": files + ["surfaces/a\\b/albedo.png"],
	}
	for label: String in cases:
		var broken := sources.duplicate()
		broken["files"] = cases[label]
		assert_false(LibraryReader.read(broken)["ok"], label)
	var no_albedo := sources.duplicate()
	no_albedo["files"] = files.filter(
		func(f: String) -> bool: return f != "surfaces/lilac/albedo.png"
	)
	assert_false(LibraryReader.read(no_albedo)["ok"], "a surface needs its albedo")
	var no_info := sources.duplicate(true)
	(no_info["surfaces"] as Dictionary).erase("slate")
	assert_false(LibraryReader.read(no_info)["ok"], "a surface needs its surface.json")
	var bomb := sources.duplicate(true)
	bomb["png"]["surfaces/lilac/albedo.png"] = {
		"ok": true, "width": 9999, "height": 9999, "bit_depth": 8, "color_type": 2
	}
	assert_false(LibraryReader.read(bomb)["ok"], "an oversize header")
	var not_png := sources.duplicate(true)
	not_png["png"]["surfaces/lilac/normal.png"] = {"ok": false, "error": "not a PNG"}
	assert_false(LibraryReader.read(not_png)["ok"], "a file that is not a PNG")
	var many := sources.duplicate()
	var crowd: Array = files.duplicate()
	for i in SurfaceBake.MAX_SURFACES + 1:
		crowd.append("surfaces/s%d/surface.json" % i)
	many["files"] = crowd
	assert_false(LibraryReader.read(many)["ok"], "over the surface cap")


func test_missing_optional_maps_and_stray_files_are_warnings() -> void:
	var sources := _read_fixture_sources()
	var files: Array = sources["files"].filter(
		func(f: String) -> bool: return f != "surfaces/boards/height.png"
	)
	files.append("surfaces/boards/notes.txt")
	files.append("surfaces/loose.png")
	files.append("surfaces/boards/deep/albedo.png")
	sources["files"] = files
	var read := LibraryReader.read(sources)
	assert_true(read["ok"], str(read["errors"]))
	assert_eq(read["surfaces"]["boards"]["maps"], ["albedo", "normal", "orm"])
	var text := "\n".join(read["warnings"])
	assert_string_contains(text, "height.png is missing")
	assert_string_contains(text, "unexpected file 'notes.txt'")
	assert_string_contains(text, "one folder per surface")


func test_a_biome_def_says_legacy_or_library_and_anything_else_is_legacy() -> void:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var def: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(FIXTURE.path_join("biomes/meadow.json"))
	)
	assert_true(LibraryReader.check_biome(def, "meadow.json", errors, warnings), str(errors))
	assert_eq(warnings, [], "library is a supported value")
	def["surfaces"] = "legacy"
	assert_true(LibraryReader.check_biome(def, "meadow.json", errors, warnings))
	assert_eq(warnings, [])
	for bad: Variant in ["elsewhere", 3, null, ["library"]]:
		def["surfaces"] = bad
		var found: Array[String] = []
		assert_true(LibraryReader.check_biome(def, "meadow.json", errors, found), str(bad))
		assert_eq(found.size(), 1, "warned, treated as legacy: " + str(bad))
		assert_string_contains(found[0], "treated as legacy")


# ---- the compiler ----


func _compile_fixture(mutate: Callable = Callable()) -> Dictionary:
	var sources := _read_fixture_sources()
	if mutate.is_valid():
		mutate.call(sources)
	var read := LibraryReader.read(sources)
	assert_true(read["ok"], str(read["errors"]))
	return BiomeCompiler.compile(
		read, {"folder": LIBRARY, "surfaces": PaletteLibrary.get_palette(BASE)["surfaces"]}
	)


func test_a_library_biome_resolves_its_surfaces_by_name() -> void:
	var compiled := _compile_fixture()
	assert_eq(
		(compiled["warnings"] as Array).filter(func(w: String) -> bool: return "surface" in w), []
	)
	assert_eq(compiled["palette_warnings"], [])
	var biome: Dictionary = compiled["palette"]["biomes"][0]
	assert_eq(biome["id"], "surf__meadow_summer_s1")
	assert_eq(biome["ground_surface"], "surf__lilac")
	assert_eq(biome["cliff_surface"], "surf__slate")
	assert_eq(biome["scree_surface"], "surf__lilac", "a lib:// reference to the library's own")
	assert_eq(biome["ground_accents"][0]["surface"], "grass_meadow", "a legacy name stays")
	assert_eq(biome["path_surfaces"], ["surf__boards", "flagstone"])
	var table: Dictionary = compiled["palette"]["surfaces"]
	assert_true(table.has("grass") and table.has("surf__lilac"), "base table plus the library's")
	assert_eq(table["surf__lilac"]["albedo"], "surfaces/surf__lilac/albedo.png")
	assert_eq(table["surf__slate"]["role"], "cliff")
	assert_eq(table["surf__lilac"]["tile_m"], 3.0)
	assert_eq((compiled["surfaces"] as Dictionary).keys().size(), 3)
	assert_eq(compiled["surfaces"]["surf__boards"]["name"], "boards")


func test_a_legacy_biome_keeps_its_names_and_a_missing_surface_warns() -> void:
	var legacy := _compile_fixture(
		func(sources: Dictionary) -> void:
			var text := String(sources["biomes"]["meadow.json"]).replace('"library"', '"legacy"')
			sources["biomes"]["meadow.json"] = text
	)
	var biome: Dictionary = legacy["palette"]["biomes"][0]
	assert_eq(biome["ground_surface"], "lilac", "legacy names pass through unresolved")
	assert_eq(biome["scree_surface"], "lib://surf/lilac")
	var missing := _compile_fixture(
		func(sources: Dictionary) -> void:
			sources["biomes"]["meadow.json"] = String(sources["biomes"]["meadow.json"]).replace(
				'"slate"', '"granite"'
			)
	)
	var text := "\n".join(missing["warnings"])
	assert_string_contains(
		text, "surface 'granite' is not in the library's surfaces/ or the palette"
	)
	assert_true("\n".join(missing["palette_warnings"]).length() > 0, "the validator blanks it too")
	var other := _compile_fixture(
		func(sources: Dictionary) -> void:
			sources["biomes"]["meadow.json"] = String(sources["biomes"]["meadow.json"]).replace(
				'"lib://surf/lilac"', '"lib://elsewhere/sand"'
			)
	)
	assert_string_contains(
		"\n".join(other["warnings"]), "names a library this one does not depend on"
	)
	var core := _compile_fixture(
		func(sources: Dictionary) -> void:
			sources["biomes"]["meadow.json"] = String(sources["biomes"]["meadow.json"]).replace(
				'"lib://surf/lilac"', '"lib://core/grass"'
			)
	)
	assert_eq(core["palette"]["biomes"][0]["scree_surface"], "grass", "core names are bare")


# ---- the registry and the ground code ----


func _serve() -> Dictionary:
	LibraryRegistry.set_dev_override(LIBRARY)
	var result := LibraryRegistry.apply(BASE)
	assert_true(result["ok"], str(result["errors"]) + str(result["error"]))
	return result


func test_the_registry_serves_library_surfaces_to_the_ground_code() -> void:
	_serve()
	var surfaces := PaletteLibrary.surfaces(BASE)
	assert_true(surfaces.has("surf__lilac") and surfaces.has("grass"), "added beside the base's")
	assert_eq(PaletteLibrary.surfaces_with_role("cliff", BASE), ["surf__slate"])
	assert_true(SurfaceStore.is_library_surface("surf__lilac"))
	assert_true(SurfaceStore.is_library_surface("lib://surf/lilac"))
	assert_false(SurfaceStore.is_library_surface("grass"))
	assert_eq(SurfaceStore.label_of("surf__slate"), "Slate")
	assert_eq(SurfaceStore.label_of("lib://surf/slate"), "Slate")
	assert_eq(AuthoringPanel.surface_label("surf__boards"), "Boards")
	assert_eq(
		AuthoringPanel.surface_label("cliff_basalt"), "Cliff basalt", "no label: the id spelled out"
	)
	# The three ways in give the same bytes.
	var relative: String = surfaces["surf__lilac"]["albedo"]
	var texture := GroundPalette.load_texture(BASE, relative)
	assert_not_null(texture)
	assert_eq(texture.get_image().get_format(), Image.FORMAT_BPTC_RGBA)
	var by_name := SurfaceStore.image_of(BASE, "surf__lilac", "albedo")
	var by_ref := SurfaceStore.image_of(BASE, "lib://surf/lilac", "albedo")
	assert_true(by_name.get_data() == by_ref.get_data())
	assert_true(by_name.get_data() == texture.get_image().get_data())
	assert_true(GroundPalette.surface_available("surf__lilac", BASE))
	assert_true(GroundPalette.surface_available("lib://surf/lilac", BASE))
	assert_false(GroundPalette.surface_available("grass", BASE), "the base's PNG is not there")
	var material := GroundPalette.build_ground_material("lib://surf/lilac", 7, BASE)
	assert_false(material.has_meta(AuthoredTerrain.FALLBACK_META), "a real surface, no fallback")
	var mean: Variant = GroundPalette.surface_mean_albedo("surf__slate", BASE)
	assert_true(mean is Color)
	assert_gt((mean as Color).b, (mean as Color).r, "slate is bluish")
	var image := GroundLayerArrays.surface_image("surf__slate", "normal", BASE)
	assert_eq(image.get_format(), Image.FORMAT_RGTC_RG)
	image.clear_mipmaps()
	assert_eq(SurfaceStore.image_of(BASE, "surf__slate", "normal").get_mipmap_count(), 4, "a copy")
	assert_null(GroundLayerArrays.surface_image("surf__nothing", "normal", BASE))


func test_library_surfaces_fill_the_ground_arrays_in_the_imported_formats() -> void:
	_serve()
	var arrays := GroundLayerArrays.new()
	arrays.sync(PackedStringArray(["surf__lilac", "lib://surf/slate", "surf__boards"]), BASE)
	for kind in GroundLayerArrays.KINDS:
		var array: Texture2DArray = arrays.textures[kind]
		assert_eq(array.get_format(), SurfaceBake.format_of(kind), kind)
		assert_eq(array.get_layers(), 16)
		assert_eq(array.get_width(), 16)


func test_the_registry_bakes_lazily_and_then_reads_the_cache() -> void:
	_serve()
	assert_eq(SurfaceStore.stats["bakes"], 0, "serving a library bakes nothing")
	var surfaces := PaletteLibrary.surfaces(BASE)
	SurfaceStore.texture(BASE, surfaces["surf__lilac"]["albedo"])
	assert_eq(SurfaceStore.stats["bakes"], 1, "only the map asked for")
	SurfaceStore.texture(BASE, surfaces["surf__lilac"]["albedo"])
	assert_eq(SurfaceStore.stats["bakes"], 1, "the texture is kept")
	SurfaceStore.clear_memory()
	SurfaceStore.texture(BASE, surfaces["surf__lilac"]["albedo"])
	assert_eq(SurfaceStore.stats["bakes"], 1)
	assert_eq(SurfaceStore.stats["cache_hits"], 1, "the cache answers after the memory is dropped")


func test_a_legacy_path_goes_through_the_import_unchanged() -> void:
	# A palette root whose PNGs the editor imported (the fixture folder has .import sidecars).
	var root := FIXTURE
	for kind in SurfaceBake.KINDS:
		var relative := "surfaces/lilac/%s.png" % kind
		var through_store := SurfaceStore.texture(root, relative)
		var direct := ResourceLoader.load(root.path_join(relative)) as Texture2D
		assert_not_null(direct, kind)
		assert_same(through_store, direct, kind + " is ResourceLoader's cached texture")
		assert_true(SurfaceStore.available(root, relative))
	assert_null(SurfaceStore.texture(root, ""))
	assert_null(SurfaceStore.texture(root, "surfaces/none/none.png"))
	assert_false(SurfaceStore.available(root, "surfaces/none/none.png"))
	assert_false(SurfaceStore.available(root, ""))
	assert_eq(SurfaceStore.stats["bakes"], 0, "a legacy path is never baked")
	var image := SurfaceStore.image(root, "surfaces/lilac/albedo.png")
	assert_eq(image.get_size(), Vector2i(16, 16))


func test_clearing_the_registry_forgets_surfaces_and_bindings() -> void:
	_serve()
	assert_true(SurfaceStore.is_library_surface("surf__lilac"))
	assert_eq(LibraryBindings.paint_default(), "surf__boards")
	LibraryRegistry.clear()
	assert_false(SurfaceStore.is_library_surface("surf__lilac"))
	assert_eq(LibraryBindings.paint_default(), "dirt_road_packed")
	assert_eq(SurfaceStore.label_of("surf__boards"), "")


func test_a_failed_apply_serves_no_surfaces() -> void:
	_serve()
	LibraryRegistry.set_dev_override(ROOT + "/no_such_library")
	var result := LibraryRegistry.apply(BASE)
	assert_false(result["ok"])
	assert_false(SurfaceStore.is_library_surface("surf__lilac"), "the earlier library is dropped")
	assert_eq(LibraryBindings.fire_ash_surface(), "ash")


# ---- bindings ----


func test_bindings_default_to_the_values_the_code_used_to_hold() -> void:
	assert_eq(LibraryBindings.fire_burnt_biome(), FireSweep.BURNT_BIOME)
	assert_eq(LibraryBindings.fire_ash_surface(), FireSweep.ASH)
	assert_eq(LibraryBindings.fire_ash_fallback(), FireSweep.ASH_FALLBACK)
	assert_eq(LibraryBindings.crossing_planks(), AuthoredCrossings.WOOD_SURFACE)
	assert_eq(LibraryBindings.crossing_moss(), AuthoredCrossings.MOSS_SURFACE)
	assert_eq(LibraryBindings.crossing_gravel(), AuthoredCrossings.DEFAULT_GRAVEL_SURFACE)
	assert_eq(LibraryBindings.crossing_stone_default(), AuthoredCrossings.DEFAULT_STONE_SURFACE)
	assert_eq(LibraryBindings.crossing_paving(), AuthoredCrossings.DEFAULT_PAVING_SURFACE)
	assert_eq(LibraryBindings.paint_default(), AuthoringPanel.DEFAULT_PAINT_SURFACE)
	assert_eq(
		LibraryBindings.water_defaults(), PackedStringArray(PaletteLibrary.DEFAULT_WATER_SURFACES)
	)
	assert_eq(LibraryBindings.default_biome(), NewMapDialog.DEFAULT_BIOME)
	assert_eq(LibraryBindings.value("no.such.key"), "")


func test_bindings_flatten_hostile_input_into_warnings() -> void:
	var flat := (
		LibraryBindings
		. flatten(
			{
				"fire": {"ash_surface": "ash", "burnt_biome": "../x", "colour": "red"},
				"crossings": ["planks"],
				"water": {"bed": 5, "shore": "Mud"},
				"paint": {"default": "a".repeat(100)},
			},
			"temperate_forest"
		)
	)
	assert_eq(flat["values"], {"fire.ash_surface": "ash", "default_biome": "temperate_forest"})
	assert_eq((flat["problems"] as Array).size(), 6)
	assert_eq(LibraryBindings.flatten(null, null)["values"], {})
	assert_eq((LibraryBindings.flatten("fire", null)["problems"] as Array).size(), 1)


func test_the_default_biome_takes_a_local_or_a_runtime_id() -> void:
	var compiled := [{"id": "savanna_summer_s1", "biome": "savanna"}]
	for given in ["savanna", "savanna_summer_s1"]:
		var runtime := LibraryBindings.to_runtime("core", {"default_biome": given}, [], compiled)
		assert_eq(runtime["default_biome"], "savanna_summer_s1", given)
	assert_false(
		LibraryBindings.to_runtime("core", {"default_biome": "tundra"}, [], compiled).has(
			"default_biome"
		),
		"a biome that did not compile binds nothing"
	)
	var own := LibraryBindings.to_runtime(
		"mylib",
		{"paint.default": "sand", "fire.ash_surface": "ash", "fire.burnt_biome": "char"},
		["sand"],
		[]
	)
	assert_eq(own["paint.default"], "mylib__sand", "the library's own surface by runtime name")
	assert_eq(own["fire.ash_surface"], "ash", "any other name as written")
	assert_eq(own["fire.burnt_biome"], "mylib__char", "a biome as its palette field")


func test_a_served_library_overrides_the_defaults() -> void:
	_serve()
	assert_eq(LibraryBindings.fire_ash_surface(), "surf__slate", "the library's own surface")
	assert_eq(LibraryBindings.fire_ash_fallback(), "dirt_peat", "unbound keys keep the default")
	assert_eq(LibraryBindings.paint_default(), "surf__boards")
	assert_eq(LibraryBindings.water_defaults(), PackedStringArray(["surf__lilac", "grass"]))
	assert_eq(LibraryBindings.default_biome(), "surf__meadow_summer_s1")
	var plan := FireSweep.plan_for(PaletteLibrary.biomes(BASE), PaletteLibrary.surfaces(BASE))
	assert_eq(plan["surface"], "surf__slate", "fire lays the library's ash")
	var water := GroundPalette.base_water_surfaces("unknown_ground", BASE)
	assert_eq(water, PackedStringArray(["surf__lilac", "grass"]))


# ---- architecture ----


func test_the_pure_modules_touch_no_files_and_the_stores_load_no_resources() -> void:
	var forbidden := ["FileAccess", "DirAccess", "EventBus", "ResourceLoader", "get_tree", "load("]
	for module in PURE_MODULES:
		var code := _code("res://utils/library/%s.gd" % module)
		for word: String in forbidden:
			assert_false(word in code, "%s must not use %s" % [module, word])
	for module in ["surface_store", "surface_cache"]:
		var code := _code("res://utils/library/%s.gd" % module)
		for word in [
			"preload(", "ClassDB", "set_script", "Script.new", "load_threaded", "EventBus"
		]:
			assert_false(word in code, "%s must not use %s" % [module, word])
		assert_false("\tload(" in code or " load(" in code, "%s must not call load()" % module)
	var store := _code("res://utils/library/surface_store.gd")
	assert_false(
		"ResourceLoader.exists(file" in store, "a library file is never loaded as a resource"
	)
	assert_false("DirAccess" in store, "the store lists nothing")


func _code(path: String) -> String:
	var code := ""
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	return code
