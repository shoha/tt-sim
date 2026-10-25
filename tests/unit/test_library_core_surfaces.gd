extends GutTest

## Step S5: the core library's surfaces, thumbnails and bindings against the installed palette
## they were copied from. The library folder lives outside this repo, so the test reads it from
##   PLANTGEN_LIB_CORE   the exported library (plantgen out/lib_core)
## and is pending without it (the checked-in miniature of the same path is
## test_library_row_parity.gd and test_surface_store.gd). Run (PowerShell):
##   $env:PLANTGEN_LIB_CORE='D:/dev/plantgen/out/lib_core'
##   godot --headless --path <project> --script res://addons/gut/gut_cmdln.gd --
##     '-gconfig=tests/.gutconfig.json' -gselect=test_library_core_surfaces
## Every surface of the library is baked from its PNGs and compared with the editor import of
## the installed surface (normal, ORM and height byte for byte, albedo by decoded colour); then
## the library is served over the installed palette and every biome's ground, cliff, scree,
## water, accents, paths and look, the surface table and the thumbnails must read the same, and
## the library's bindings must equal the constants the game held before bindings existed.

const ENV_CORE := "PLANTGEN_LIB_CORE"
const ROOT := "user://test_library_core_surfaces"
const SETTINGS := ROOT + "/settings.cfg"
const BIOME_FIELDS: Array[String] = [
	"ground_surface",
	"cliff_surface",
	"scree_surface",
	"water_bed_surface",
	"shore_surface",
	"ground_accents",
	"path_surfaces",
	"ground_look",
	"thumbnail",
	"name",
	"climate",
]
const SURFACE_FIELDS: Array[String] = ["kind", "role", "tile_m", "albedo_mean_linear"]

var _saved_settings_path: String = ""


func before_all() -> void:
	_saved_settings_path = LibraryRegistry.settings_path
	LibraryRegistry.settings_path = SETTINGS
	DirAccess.make_dir_recursive_absolute(ROOT)


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings_path
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	DirAccess.remove_absolute(SETTINGS)
	DirAccess.remove_absolute(ROOT)


func before_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	DirAccess.remove_absolute(SETTINGS)


func after_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


func _library() -> String:
	return OS.get_environment(ENV_CORE)


func test_every_surface_of_the_library_equals_the_editor_import() -> void:
	if _library() == "":
		pending("set %s to run the core surface proof" % ENV_CORE)
		return
	var names: Array = PaletteLibrary.surfaces().keys()
	names.sort()
	assert_eq(names.size(), 36, "the 36 installed surfaces")
	for name: String in names:
		var folder := _library().path_join("surfaces").path_join(name)
		var loaded := SurfaceStore.load_set(folder, "core_proof")
		assert_true(loaded["ok"], "%s: %s" % [name, str(loaded["errors"])])
		assert_eq((loaded["warnings"] as Array).size(), 0, name + ": 1024 px maps, clean info")
		var imported := SurfaceStore.load_installed(PaletteLibrary.DEFAULT_ROOT, name)
		for kind in SurfaceBake.KINDS:
			var mine: Image = loaded["images"][kind]
			var theirs: Image = imported[kind]
			assert_eq(mine.get_format(), theirs.get_format(), "%s %s format" % [name, kind])
			assert_eq(mine.get_size(), theirs.get_size(), "%s %s size" % [name, kind])
			assert_eq(
				mine.get_mipmap_count(), theirs.get_mipmap_count(), "%s %s mips" % [name, kind]
			)
			if kind != "albedo":
				assert_true(
					mine.get_data() == theirs.get_data(), "%s %s is byte for byte" % [name, kind]
				)
			else:
				_assert_same_colours(mine, theirs, name)
		var listed: Array = PaletteLibrary.surfaces()[name]["albedo_mean_linear"]
		var mean: Color = loaded["mean_albedo_linear"]
		assert_almost_eq(mean.g, float(listed[1]), 0.0001, name + ": mean albedo as listed")


## Mean (limit 0.1 of 255) and largest (limit 8) per-channel difference of the first mip.
func _assert_same_colours(a: Image, b: Image, label: String) -> void:
	var left := a.duplicate() as Image
	var right := b.duplicate() as Image
	left.decompress()
	right.decompress()
	var x := left.get_data()
	var y := right.get_data()
	assert_eq(x.size(), y.size(), label + " albedo size")
	var total := 0
	var worst := 0
	var seen := 0
	for i in range(0, x.size(), 7):
		var d := absi(x[i] - y[i])
		total += d
		worst = maxi(worst, d)
		seen += 1
	assert_lt(float(total) / seen, 0.1, label + " albedo mean difference of 255")
	assert_lte(worst, 8, label + " albedo largest difference of 255")


## {biome id: {field: value}} and {surface: {field: value}} of the palette now cached.
func _read_palette() -> Dictionary:
	var biomes := {}
	for entry: Dictionary in PaletteLibrary.biomes():
		var fields := {}
		for field in BIOME_FIELDS:
			fields[field] = entry.get(field)
		biomes[entry["id"]] = fields
	var surfaces := {}
	var table := PaletteLibrary.surfaces()
	for name: String in table:
		var fields := {}
		for field in SURFACE_FIELDS:
			fields[field] = (table[name] as Dictionary).get(field)
		surfaces[name] = fields
	return {"biomes": biomes, "surfaces": surfaces}


func test_the_served_library_reads_like_the_installed_palette() -> void:
	if _library() == "":
		pending("set %s to run the core surface proof" % ENV_CORE)
		return
	var before := _read_palette()
	var names: Array = before["surfaces"].keys()
	var used := {}
	for biome_id: String in before["biomes"]:
		var fields: Dictionary = before["biomes"][biome_id]
		for field in [
			"ground_surface", "cliff_surface", "scree_surface", "water_bed_surface", "shore_surface"
		]:
			used[String(fields[field])] = true
		for accent: Dictionary in fields["ground_accents"]:
			used[String(accent["surface"])] = true
		for path: String in fields["path_surfaces"]:
			used[path] = true
	used.erase("")
	var images_before := _images(used.keys())
	var thumbs_before := _thumbnails(before["biomes"])
	LibraryRegistry.set_dev_override(_library())
	var applied := LibraryRegistry.apply()
	assert_true(applied["ok"], str(applied["error"]))
	assert_eq(applied["warnings"], [], "no read, compile or palette warnings")
	assert_eq((applied["biomes"] as Array).size(), 9)
	var after := _read_palette()
	assert_eq(after["surfaces"].keys().size(), names.size(), "the same 36 surfaces")
	for name: String in names:
		assert_true(SurfaceStore.is_library_surface(name), name + " is served by the library")
		var legacy_label: String = AuthoringPanel.SURFACE_LABELS.get(
			name, AuthoringPanel.species_label(name)
		)
		assert_eq(SurfaceStore.label_of(name), legacy_label, name + " shows the same label")
	for biome_id: String in before["biomes"]:
		var thumbnail := String(after["biomes"][biome_id]["thumbnail"])
		assert_true(
			SurfaceStore.is_library_thumbnail(PaletteLibrary.DEFAULT_ROOT, thumbnail),
			biome_id + " thumbnail comes from the library folder"
		)
	for name: String in names:
		assert_eq(after["surfaces"].get(name), before["surfaces"][name], "surface " + name)
	for biome_id: String in before["biomes"]:
		for field in BIOME_FIELDS:
			assert_eq(
				after["biomes"][biome_id][field],
				before["biomes"][biome_id][field],
				"%s %s" % [biome_id, field]
			)
	var images_after := _images(used.keys())
	for key: String in images_before:
		var was: Image = images_before[key]
		var is_now: Image = images_after[key]
		assert_eq(is_now.get_format(), was.get_format(), key + " format")
		assert_eq(is_now.get_size(), was.get_size(), key + " size")
		if not key.ends_with("|albedo"):
			assert_true(is_now.get_data() == was.get_data(), key + " is byte for byte")
		else:
			_assert_same_colours(is_now, was, key)
	var thumbs_after := _thumbnails(after["biomes"])
	for biome_id: String in thumbs_before:
		_assert_thumbnail(thumbs_after[biome_id], thumbs_before[biome_id], biome_id)
	gut.p("%d surfaces and %d biomes compared, %d images" % [names.size(), 9, images_before.size()])


## {"name|kind": Image} of the maps of the surfaces `names` as SurfaceStore serves them now.
func _images(names: Array) -> Dictionary:
	var out := {}
	for name: String in names:
		for kind in SurfaceBake.KINDS:
			var image := SurfaceStore.image_of(PaletteLibrary.DEFAULT_ROOT, name, kind)
			assert_not_null(image, "%s %s resolves" % [name, kind])
			if image != null:
				out["%s|%s" % [name, kind]] = image
	return out


## {biome id: Image} of each biome's thumbnail as the palette path resolves it now.
func _thumbnails(biomes: Dictionary) -> Dictionary:
	var out := {}
	for biome_id: String in biomes:
		var texture := SurfaceStore.texture(
			PaletteLibrary.DEFAULT_ROOT, String(biomes[biome_id]["thumbnail"])
		)
		assert_not_null(texture, biome_id + " thumbnail resolves")
		if texture != null:
			out[biome_id] = texture.get_image()
	return out


func _assert_thumbnail(now: Image, was: Image, biome_id: String) -> void:
	assert_eq(now.get_size(), was.get_size(), biome_id + " thumbnail size")
	var a := now.duplicate() as Image
	var b := was.duplicate() as Image
	a.decompress()
	b.decompress()
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var x := a.get_data()
	var y := b.get_data()
	var total := 0
	for i in x.size():
		total += absi(x[i] - y[i])
	assert_lt(float(total) / x.size(), 1.5, biome_id + " thumbnail mean difference of 255")


func test_the_libraries_bindings_equal_the_constants_the_game_held() -> void:
	if _library() == "":
		pending("set %s to run the core surface proof" % ENV_CORE)
		return
	var library: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(_library().path_join("library.json"))
	)
	var flat := LibraryBindings.flatten(library.get("bindings"), library.get("default_biome"))
	assert_eq(flat["problems"], [], "every binding is known and well formed")
	var values: Dictionary = flat["values"]
	assert_eq(values.size(), LibraryBindings.TABLE.size(), "every binding is written")
	for key: String in LibraryBindings.TABLE:
		if key == "default_biome":
			assert_eq(values[key], "temperate_forest_summer_s1", key)
		else:
			assert_eq(
				values[key], LibraryBindings.default_of(key), key + " equals the legacy value"
			)
	LibraryRegistry.set_dev_override(_library())
	assert_true(LibraryRegistry.apply()["ok"])
	for key: String in LibraryBindings.TABLE:
		assert_eq(LibraryBindings.value(key), LibraryBindings.default_of(key), "served " + key)
	assert_eq(LibraryBindings.fire_ash_surface(), "ash")
	assert_eq(LibraryBindings.fire_burnt_biome(), "burnt_forest")
	assert_eq(LibraryBindings.crossing_planks(), "planks")
	assert_eq(LibraryBindings.water_defaults(), PackedStringArray(["riverbed", "mud"]))
	assert_eq(LibraryBindings.default_biome(), "temperate_forest_summer_s1")
	var table := PaletteLibrary.surfaces()
	for key: String in LibraryBindings.TABLE:
		if String((LibraryBindings.TABLE[key] as Dictionary)["kind"]) == "surface":
			assert_true(table.has(LibraryBindings.value(key)), key + " names a served surface")
	assert_eq(table[LibraryBindings.crossing_planks()]["role"], "built")
	assert_eq(table[LibraryBindings.fire_ash_surface()]["role"], "ground")
