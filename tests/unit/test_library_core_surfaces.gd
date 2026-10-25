extends GutTest

## Step S5, kept alive by step S10: the SHIPPED core library's surfaces, thumbnails and bindings
## (res://libraries/core, served as the palette). Until 2026-10-25 this proved the library's 36
## surfaces equal to the installed treecube palette they were copied from and was pending without
## plantgen's out/lib_core; the installed palette is retired, so the comparison is gone and what
## remains are the facts the game relies on: every surface bakes to the imported formats at the
## expected size, each carries the label the game showed for it (the retired table is frozen
## below), the biome thumbnails read, and the library's bindings equal the constants the game held
## before bindings existed.

const SURFACE_COUNT := 36
## The labels the retired AuthoringPanel.SURFACE_LABELS table gave; a surface not in it was shown
## as its id spelled out (AuthoringPanel.species_label).
const LEGACY_LABELS := {
	"cliff": "Rock",
	"cliff_basalt": "Basalt",
	"cliff_sandstone": "Sandstone",
	"cobblestone": "Cobblestone",
	"dirt": "Dirt",
	"dirt_peat": "Peat",
	"dirt_road_packed": "Dirt track",
	"flagstone": "Flagstone",
	"forest_floor": "Forest floor",
	"grass": "Grass",
	"grass_alpine": "Alpine grass",
	"grass_savanna": "Dry grass",
	"gravel": "Gravel",
	"gravel_sandstone": "Red gravel",
	"moss": "Moss",
	"mud": "Mud",
	"pine_duff": "Pine needles",
	"planks": "Planks",
	"riverbed": "Riverbed",
	"sand": "Sand",
	"sand_red": "Red sand",
	"snow": "Snow",
	"stone_tiles": "Stone tiles",
}

var _core: Dictionary = {}


func before_all() -> void:
	PaletteLibrary.clear_cache()
	_core = JSON.parse_string(FileAccess.get_file_as_string("res://libraries/core/library.json"))


func after_all() -> void:
	PaletteLibrary.clear_cache()


func test_core_serves_its_surfaces_and_labels() -> void:
	var names := PaletteLibrary.surfaces().keys()
	assert_eq(names.size(), SURFACE_COUNT, "the 36 surfaces")
	for name: String in names:
		assert_true(SurfaceStore.is_library_surface(name), name + " is served by the library")
		var legacy_label: String = LEGACY_LABELS.get(name, AuthoringPanel.species_label(name))
		assert_eq(SurfaceStore.label_of(name), legacy_label, name + " shows the same label")
		assert_eq(AuthoringPanel.surface_label(name), legacy_label, name + " panel label")


func test_every_surface_bakes_to_the_imported_formats() -> void:
	for name: String in PaletteLibrary.surfaces():
		for kind in SurfaceBake.KINDS:
			var image := SurfaceStore.image_of(PaletteLibrary.DEFAULT_ROOT, name, kind)
			assert_not_null(image, "%s %s" % [name, kind])
			if image == null:
				continue
			assert_eq(image.get_format(), SurfaceBake.format_of(kind), "%s %s" % [name, kind])
			assert_eq(image.get_size(), Vector2i(1024, 1024), "%s %s" % [name, kind])
			assert_eq(image.get_mipmap_count(), 10, "%s %s mips" % [name, kind])
		var entry: Dictionary = PaletteLibrary.surfaces()[name]
		assert_gt(float(entry["tile_m"]), 0.0, name)
		assert_true(entry["albedo_mean_linear"] is Array, name + " carries its measured mean")


func test_the_biome_thumbnails_read() -> void:
	var seen := 0
	for biome in PaletteLibrary.biomes():
		var thumbnail := String(biome["thumbnail"])
		assert_true(
			SurfaceStore.is_library_thumbnail(PaletteLibrary.DEFAULT_ROOT, thumbnail), thumbnail
		)
		var texture := SurfaceStore.texture(PaletteLibrary.DEFAULT_ROOT, thumbnail)
		assert_not_null(texture, thumbnail)
		if texture != null:
			assert_eq(texture.get_size(), Vector2(512, 512), thumbnail)
			seen += 1
	assert_eq(seen, 9, "all nine biomes have a picture")


func test_the_libraries_bindings_equal_the_constants_the_game_held() -> void:
	var flat := LibraryBindings.flatten(_core.get("bindings"), _core.get("default_biome"))
	assert_eq(flat["problems"], [], "every binding is known and well formed")
	var values: Dictionary = flat["values"]
	assert_eq(values.size(), LibraryBindings.TABLE.size(), "every binding is written")
	for key: String in LibraryBindings.TABLE:
		assert_eq(values[key], LibraryBindings.default_of(key), key + " equals the legacy value")
		assert_eq(LibraryBindings.value(key), LibraryBindings.default_of(key), "served " + key)
	assert_eq(_core["default_biome"], "temperate_forest_summer_s1", "the New map default")
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
