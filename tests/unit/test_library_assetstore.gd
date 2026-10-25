extends GutTest

## AssetStore and GlbGuard (step S4): a library asset's mesh is keyed by (library, asset id),
## parsed lazily from its file with GLTFDocument and cached; a GLB of a library that is not
## official must match the catalog's sha256 and byte count or it is refused (an official one is
## only hashed by verify()); a texture over the size cap is refused from its header before any
## decode; the mesh a map draws gets the game's own materials (WindFoliage.apply_material);
## nothing is read through ResourceLoader.

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_library_assetstore"
const SETTINGS := ROOT + "/settings.cfg"
const SPIRE := World.ALIEN_RUNTIME + "/Crystal_Spire_v0"
const SHARD := World.ALIEN_RUNTIME + "/Crystal_Shard_v0"
const SHARED_OAK := World.ALIEN_RUNTIME + "/core__Tree_Oak_v0"
const CORE_OAK := "forest_summer_s1/Tree_Oak_v0"

var _paths: Dictionary = {}
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	AssetStore.reset_stats()
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply(_paths["base"])


func _mesh(library: String, asset_id: String) -> Mesh:
	return AssetStore.mesh(library, asset_id, _paths["base"])


# ---- lazy, keyed, cached ----


func test_nothing_is_parsed_until_a_mesh_is_asked_for() -> void:
	assert_eq(AssetStore.stats["parses"], 0, "serving a library reads no GLB")
	assert_eq(AssetStore.assets_of("alienworld", _paths["base"]).size(), 2)
	assert_eq(AssetStore.assets_of("core", _paths["base"]).size(), 3, "its own two and the shared oak")
	assert_true(AssetStore.serves(SPIRE, _paths["base"]))
	assert_eq(AssetStore.stats["parses"], 0)
	var first := _mesh("alienworld", SPIRE)
	assert_not_null(first)
	assert_eq(AssetStore.stats["parses"], 1)
	assert_true(first is ArrayMesh)
	assert_eq((first as ArrayMesh).get_surface_count(), 1)


func test_a_second_ask_is_the_cached_mesh() -> void:
	var first := _mesh("alienworld", SPIRE)
	var second := _mesh("alienworld", SPIRE)
	assert_same(second, first)
	assert_eq(AssetStore.stats["parses"], 1)
	assert_eq(AssetStore.stats["cache_hits"], 1)
	# PaletteLibrary.resolve goes through the same store and hands out a duplicate.
	var resolved := PaletteLibrary.resolve(SPIRE, _paths["base"])
	assert_false(resolved.is_empty())
	assert_ne(resolved["mesh"], first, "resolve duplicates, as for a built-in asset")
	assert_eq(AssetStore.stats["parses"], 1, "and does not read the file again")


func test_the_pair_is_the_key() -> void:
	assert_null(_mesh("core", SPIRE), "the spire is not core's")
	assert_null(_mesh("alienworld", "alienworld__crystal_basin_summer_s1/Nope"))
	assert_null(_mesh("ghost", SPIRE))
	assert_eq(AssetStore.library_of(SHARED_OAK, _paths["base"]), "core", "a dependency's own asset")
	assert_not_null(_mesh("core", SHARED_OAK))
	assert_not_null(_mesh("core", CORE_OAK))
	assert_eq(AssetStore.library_of("forest_summer_s1/Oak", _paths["base"]), "", "built-in assets")
	assert_false(AssetStore.serves("forest_summer_s1/Oak", _paths["base"]))


func test_clear_forgets_registrations_and_meshes() -> void:
	_mesh("alienworld", SPIRE)
	AssetStore.clear()
	assert_false(AssetStore.serves(SPIRE, _paths["base"]))
	assert_null(_mesh("alienworld", SPIRE))
	LibraryRegistry.apply(_paths["base"])
	assert_true(AssetStore.serves(SPIRE, _paths["base"]))
	assert_eq(PaletteLibrary.resolve(SPIRE, _paths["base"]).is_empty(), false)


# ---- integrity ----


func test_a_user_library_glb_that_does_not_match_the_catalog_is_refused() -> void:
	# Replace the file with a valid GLB of another size: the catalog's sha256 no longer fits.
	World.write_glb(_paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb", "Crystal_Spire_v0_LOD0_x")
	var refused := _mesh("alienworld", SPIRE)
	assert_null(refused)
	assert_engine_error(1)
	assert_eq(AssetStore.stats["refused"], 1)
	assert_eq(AssetStore.stats["parses"], 0, "nothing was decoded")
	assert_string_contains(AssetStore.error_of(SPIRE, _paths["base"]), "catalog")
	assert_null(_mesh("alienworld", SPIRE), "refused once: the answer is cached")
	assert_eq(AssetStore.stats["refused"], 1)
	assert_not_null(_mesh("alienworld", SHARD), "the other assets of the library still load")


func test_a_byte_count_that_does_not_match_is_refused() -> void:
	World.edit_json(
		_paths["alien"] + "/assets/catalog.json",
		func(d: Dictionary) -> void: d["assets"][0]["bytes"] = int(d["assets"][0]["bytes"]) + 1
	)
	LibraryRegistry.apply(_paths["base"])
	assert_null(_mesh("alienworld", SPIRE))
	assert_engine_error(1)
	assert_string_contains(AssetStore.error_of(SPIRE, _paths["base"]), "bytes")


func test_an_official_library_is_not_hashed_on_load_but_verify_checks_it() -> void:
	var file: String = _paths["core"] + "/assets/tree/Tree_Oak_v0.glb"
	World.write_glb(file, "Tree_Oak_v0_LOD0")
	World.write_bytes(file, FileAccess.get_file_as_bytes(file) + PackedByteArray([0, 0, 0, 0]))
	# The tail bytes break the sha256 and the byte count, which official libraries are not
	# checked against on load.
	var hashes_before: int = AssetStore.stats["hash_checks"]
	assert_not_null(_mesh("core", CORE_OAK), "official: loads")
	assert_eq(AssetStore.stats["hash_checks"], hashes_before)
	var verdict := AssetStore.verify(CORE_OAK, _paths["base"])
	assert_false(verdict["ok"], "verify hashes it too")
	assert_string_contains(verdict["error"], "catalog")
	assert_eq(verdict["library"], "core")
	assert_true(AssetStore.verify(SPIRE, _paths["base"])["ok"])


func test_a_missing_file_is_a_cached_null_with_a_reason() -> void:
	DirAccess.remove_absolute(_paths["alien"] + "/assets/rock/Crystal_Shard_v0.glb")
	assert_null(_mesh("alienworld", SHARD))
	assert_engine_error(1)
	assert_string_contains(AssetStore.error_of(SHARD, _paths["base"]), "missing")
	assert_null(PaletteLibrary.resolve(SHARD, _paths["base"]).get("mesh"))


func test_a_glb_without_the_named_node_is_refused() -> void:
	World.edit_json(
		_paths["alien"] + "/assets/catalog.json",
		func(d: Dictionary) -> void: d["assets"][0]["node"] = "NoSuchNode"
	)
	LibraryRegistry.apply(_paths["base"])
	assert_null(_mesh("alienworld", SPIRE))
	assert_engine_error(1)
	assert_string_contains(AssetStore.error_of(SPIRE, _paths["base"]), "NoSuchNode")


# ---- materials ----


func test_the_mesh_a_map_draws_gets_the_games_materials() -> void:
	var source := _mesh("alienworld", SPIRE)
	assert_true(source.surface_get_material(0) is BaseMaterial3D, "glTF carries no shader")
	var dressed := AssetStore.instance("alienworld", SPIRE, "tree", _paths["base"])
	assert_not_null(dressed)
	assert_true(dressed.surface_get_material(0) is ShaderMaterial, "replaced by the wind shader")
	assert_true(source.surface_get_material(0) is BaseMaterial3D, "the shared source is untouched")
	var plain := AssetStore.instance("alienworld", SHARD, "", _paths["base"])
	assert_true(plain.surface_get_material(0) is BaseMaterial3D, "no wind category, no shader")
	# The same call a scatter build makes for a built-in asset.
	var template := PaletteLibrary.resolve(SPIRE, _paths["base"])
	WindFoliage.apply_material(template["mesh"], template["wind_category"])
	assert_true((template["mesh"] as Mesh).surface_get_material(0) is ShaderMaterial)


func test_sanitize_replaces_a_material_that_is_not_a_base_material() -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, ShaderMaterial.new())
	assert_eq(AssetStore.sanitize(mesh), 1)
	assert_true(mesh.surface_get_material(0) is StandardMaterial3D)
	assert_eq(AssetStore.sanitize(mesh), 0)


# ---- GlbGuard ----


## A GLB container: `json` (a glTF dictionary) and one BIN chunk of `bin`.
func _glb(json: Dictionary, bin: PackedByteArray = PackedByteArray()) -> PackedByteArray:
	var text := JSON.stringify(json).to_utf8_buffer()
	while text.size() % 4 != 0:
		text.append(0x20)
	var padded := bin.duplicate()
	while padded.size() % 4 != 0:
		padded.append(0)
	var out := PackedByteArray()
	out.resize(20)
	out.encode_u32(0, GlbGuard.MAGIC)
	out.encode_u32(4, 2)
	out.encode_u32(12, text.size())
	out.encode_u32(16, GlbGuard.CHUNK_JSON)
	out.append_array(text)
	if not padded.is_empty():
		var head := PackedByteArray()
		head.resize(8)
		head.encode_u32(0, padded.size())
		head.encode_u32(4, GlbGuard.CHUNK_BIN)
		out.append_array(head)
		out.append_array(padded)
	out.encode_u32(8, out.size())
	return out


## The first bytes of a PNG that says it is `size` px (no pixel data follows).
func _png_head(size: Vector2i) -> PackedByteArray:
	var out := PackedByteArray([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13])
	out.append_array("IHDR".to_utf8_buffer())
	for value in [size.x, size.y]:
		var big_endian := PackedByteArray([0, 0, 0, 0])
		big_endian.encode_u32(0, value)
		big_endian.reverse()
		out.append_array(big_endian)
	out.append_array(PackedByteArray([8, 6, 0, 0, 0]))
	return out


func _with_image(head: PackedByteArray) -> PackedByteArray:
	var doc := {
		"asset": {"version": "2.0"},
		"buffers": [{"byteLength": head.size()}],
		"bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": head.size()}],
		"images": [{"bufferView": 0, "mimeType": "image/png"}],
	}
	return _glb(doc, head)


func test_the_guard_reads_a_real_glb_clean() -> void:
	var bytes := FileAccess.get_file_as_bytes(_paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb")
	var verdict := GlbGuard.inspect(bytes)
	assert_true(verdict["ok"], str(verdict["error"]))
	assert_eq(verdict["images"], [] as Array[Vector2i])


func test_the_guard_reads_texture_sizes_from_the_header_only() -> void:
	var small := GlbGuard.inspect(_with_image(_png_head(Vector2i(256, 128))))
	assert_true(small["ok"], str(small["error"]))
	assert_eq(small["images"], [Vector2i(256, 128)] as Array[Vector2i])
	var at_cap := GlbGuard.inspect(_with_image(_png_head(Vector2i(4096, 4096))))
	assert_true(at_cap["ok"])
	var huge := GlbGuard.inspect(_with_image(_png_head(Vector2i(20000, 20000))))
	assert_false(huge["ok"])
	assert_string_contains(huge["error"], "20000 x 20000")
	var wide := GlbGuard.inspect(_with_image(_png_head(Vector2i(4097, 8))))
	assert_false(wide["ok"], "one side over the cap")


func test_the_guard_refuses_what_is_not_self_contained_or_not_an_image() -> void:
	var external := _glb({"asset": {"version": "2.0"}, "images": [{"uri": "evil.png"}]})
	assert_string_contains(GlbGuard.inspect(external)["error"], "uri")
	var buffers := [{"uri": "data:x", "byteLength": 1}]
	var data_uri := _glb({"asset": {"version": "2.0"}, "buffers": buffers})
	assert_false(GlbGuard.inspect(data_uri)["ok"])
	assert_string_contains(
		GlbGuard.inspect(_with_image(PackedByteArray([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])))["error"],
		"neither PNG nor JPEG"
	)
	assert_false(GlbGuard.inspect(PackedByteArray([1, 2, 3]))["ok"])
	assert_false(GlbGuard.inspect("not a glb at all, just text bytes".to_utf8_buffer())["ok"])
	var lying := _with_image(_png_head(Vector2i(8, 8)))
	lying.encode_u32(8, lying.size() + 100)
	assert_false(GlbGuard.inspect(lying)["ok"], "a header that claims more than the file holds")


func test_the_guard_counts_images_and_total_pixels() -> void:
	var head := _png_head(Vector2i(10, 10))
	var views: Array = []
	var images: Array = []
	for i in LibraryContracts.MAX_GLB_IMAGES + 1:
		views.append({"buffer": 0, "byteOffset": 0, "byteLength": head.size()})
		images.append({"bufferView": i})
	var doc := {"asset": {"version": "2.0"}, "bufferViews": views, "images": images}
	assert_string_contains(GlbGuard.inspect(_glb(doc, head))["error"], "images")
	var big := _png_head(Vector2i(4096, 4096))
	var heavy_views: Array = []
	var heavy_images: Array = []
	for i in 3:
		heavy_views.append({"buffer": 0, "byteOffset": 0, "byteLength": big.size()})
		heavy_images.append({"bufferView": i})
	var heavy := {"asset": {"version": "2.0"}, "bufferViews": heavy_views, "images": heavy_images}
	assert_string_contains(GlbGuard.inspect(_glb(heavy, big))["error"], "pixels")


func test_a_jpeg_size_is_read_from_its_frame_header() -> void:
	var jpeg := PackedByteArray([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 0, 0, 0xFF, 0xC0, 0, 17, 8])
	jpeg.append_array(PackedByteArray([0x01, 0x00, 0x02, 0x00]))  # height 256, width 512
	jpeg.append_array(PackedByteArray([3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1]))
	assert_eq(GlbGuard.image_size(jpeg), Vector2i(512, 256))
	assert_eq(GlbGuard.image_size(PackedByteArray([0xFF, 0xD8, 0xFF])), Vector2i.ZERO)


func test_an_oversized_texture_in_a_library_glb_is_refused_before_decoding() -> void:
	var path: String = _paths["alien"] + "/assets/tree/Crystal_Spire_v0.glb"
	var bomb := _with_image(_png_head(Vector2i(30000, 30000)))
	World.write_bytes(path, bomb)
	World.edit_json(
		_paths["alien"] + "/assets/catalog.json",
		func(d: Dictionary) -> void:
			d["assets"][0]["bytes"] = bomb.size()
			d["assets"][0]["sha256"] = World.sha256_of(bomb)
	)
	LibraryRegistry.apply(_paths["base"])
	assert_null(_mesh("alienworld", SPIRE))
	assert_engine_error(1)
	assert_string_contains(AssetStore.error_of(SPIRE, _paths["base"]), "30000 x 30000")
	assert_eq(AssetStore.stats["parses"], 0)


# ---- the architecture rule ----


func test_asset_store_never_loads_library_files_as_resources() -> void:
	var code := ""
	for line in FileAccess.get_file_as_string("res://utils/library/asset_store.gd").split("\n"):
		if not line.strip_edges().begins_with("#"):
			code += line + "\n"
	for word in ["ResourceLoader", "preload(", "ClassDB", "set_script", "load_threaded", "DirAccess"]:
		assert_false(word in code, "AssetStore must not use " + word)
	assert_false("\tload(" in code or " load(" in code, "no load() call")
	assert_true("GLTFDocument" in code)
