extends GutTest

## The seam check for the SHIPPED palette: the core library under res://libraries/core (built by
## plantgen, docs/systems/library.md "The core library") served through PaletteLibrary with its
## default root. Since step S10 (2026-10-25) this replaces the check of treecube's committed
## palette (assets/palette and its editor-import sidecars, retired). test_palette_library.gd covers
## the loader's rules against a synthetic palette; this file fails when a core rebuild breaks what
## tt-sim relies on: the counts, the roles, the sidecars that ship the raw files in the pack, and
## every asset resolving with its wind data.
##
## Headless CI has no GPU, so everything here asserts on structure (meshes, vertex colour arrays,
## harvested material parameters, chunk nodes), never on pixels.

const CORE_FOLDER := "res://libraries/core"
const BIOME_COUNT := 9
const ASSET_COUNT := 268
## The palette lists an asset once per biome that places it (shared stems appear several times).
const PALETTE_ASSET_COUNT := 288
const SURFACE_COUNT := 36
## Surfaces per role; the rest of SURFACE_COUNT is ground.
const CLIFF_SURFACE_COUNT := 3
const BUILT_SURFACE_COUNT := 7
const WIND_CATEGORIES := ["tree", "grass"]
## The constant sidecar beside every PNG, GLB and JPG of the folder: the raw file ships in the pack.
const KEEP_SIDECAR := '[remap]\n\nimporter="keep"\n'


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _asset_ids() -> Array:
	return PaletteLibrary.get_palette()["assets"].keys()


func _rows(count: int, spacing: float) -> Array:
	var rows: Array = []
	for i in count:
		rows.append([float(i) * spacing, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


## Every file of `folder` (a res:// path) with extension `extension`, recursively.
func _files(folder: String, extension: String) -> Array[String]:
	var out: Array[String] = []
	for file_name in DirAccess.get_files_at(folder):
		if file_name.get_extension() == extension:
			out.append(folder.path_join(file_name))
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_files(folder.path_join(sub), extension))
	return out


func test_the_palette_is_the_served_core_library() -> void:
	var palette := PaletteLibrary.get_palette()
	assert_eq(palette["biomes"].size(), BIOME_COUNT)
	assert_eq(palette["assets"].size(), PALETTE_ASSET_COUNT)
	assert_eq(palette["surfaces"].size(), SURFACE_COUNT)
	assert_eq(LibraryRegistry.served().keys(), ["core"])
	var core: Dictionary = LibraryRegistry.info("core")
	assert_eq(core["source"], "official")
	assert_true(core["official"])
	assert_eq(core["asset_count"], ASSET_COUNT)
	# A validation warning is a push_warning, which GUT fails as an unexpected error.


func test_core_is_a_folder_with_no_palette_json_and_the_default_root_is_virtual() -> void:
	assert_true(FileAccess.file_exists(CORE_FOLDER.path_join("library.json")))
	assert_false(FileAccess.file_exists(PaletteLibrary.DEFAULT_ROOT.path_join("palette.json")))
	assert_false(DirAccess.dir_exists_absolute("res://assets/palette"), "treecube's palette is gone")


func test_every_png_glb_and_jpg_ships_raw_through_a_constant_keep_sidecar() -> void:
	var checked := 0
	for extension in ["png", "glb", "jpg"]:
		for path in _files(CORE_FOLDER, extension):
			assert_eq(
				FileAccess.get_file_as_string(path + ".import"), KEEP_SIDECAR, path + ".import"
			)
			checked += 1
	assert_gt(checked, 400, "268 GLBs, 144 surface maps and 9 thumbnails")
	for sidecar in _files(CORE_FOLDER, "import"):
		assert_true(FileAccess.file_exists(sidecar.trim_suffix(".import")), sidecar + " has a file")


func test_the_fire_entries_are_shipped() -> void:
	var surfaces := PaletteLibrary.surfaces()
	assert_true(surfaces.has("ash"), "ash surface")
	if surfaces.has("ash"):
		assert_eq(surfaces["ash"].role, "ground")
	var burnt := PaletteLibrary.biome("burnt_forest_summer_s1")
	assert_eq(burnt.get("ground_surface"), "ash")
	assert_eq(LibraryBindings.fire_burnt_biome(), "burnt_forest")
	assert_eq(LibraryBindings.fire_ash_surface(), "ash")


func test_every_biome_names_a_shipped_ground_surface_and_thumbnail() -> void:
	var surfaces := PaletteLibrary.surfaces()
	for biome in PaletteLibrary.biomes():
		assert_true(surfaces.has(biome.ground_surface), biome.id)
		assert_true(
			SurfaceStore.is_library_thumbnail(PaletteLibrary.DEFAULT_ROOT, biome.thumbnail),
			biome.id
		)
		assert_gt(biome.species.size(), 0, biome.id)


func test_surfaces_carry_their_roles() -> void:
	var cliffs := PaletteLibrary.surfaces_with_role("cliff")
	var built := PaletteLibrary.surfaces_with_role("built")
	var ground := PaletteLibrary.surfaces_with_role("ground")
	assert_eq(cliffs.size(), CLIFF_SURFACE_COUNT, str(cliffs))
	assert_eq(built.size(), BUILT_SURFACE_COUNT, str(built))
	assert_eq(ground.size(), SURFACE_COUNT - CLIFF_SURFACE_COUNT - BUILT_SURFACE_COUNT, str(ground))
	for surface_name in PaletteLibrary.surfaces():
		assert_ne(PaletteLibrary.surfaces()[surface_name].kind, "", surface_name)


## The loader falls back (with a warning GUT fails on) when a biome names a missing or
## wrong-role surface, so a resolved, role-correct name here is the one the library gave.
func test_every_biome_resolves_its_cliff_and_scree_surfaces() -> void:
	var surfaces := PaletteLibrary.surfaces()
	for biome in PaletteLibrary.biomes():
		assert_true(surfaces.has(biome.cliff_surface), "%s cliff" % biome.id)
		assert_true(surfaces.has(biome.scree_surface), "%s scree" % biome.id)
		if surfaces.has(biome.cliff_surface):
			assert_eq(surfaces[biome.cliff_surface].role, "cliff", biome.id)
		if surfaces.has(biome.scree_surface):
			assert_eq(surfaces[biome.scree_surface].role, "ground", biome.id)
		if surfaces.has(biome.ground_surface):
			assert_eq(surfaces[biome.ground_surface].role, "ground", biome.id)


## Every biome gives path surfaces and ground accents; the loader drops a wrong-role or missing
## name with a warning GUT fails on.
func test_every_biome_resolves_its_path_surfaces_and_ground_accents() -> void:
	var surfaces := PaletteLibrary.surfaces()
	for biome in PaletteLibrary.biomes():
		var paths := PaletteLibrary.path_surfaces(biome.id)
		assert_gt(paths.size(), 0, "%s path_surfaces" % biome.id)
		for surface_name in paths:
			assert_true(surfaces.has(surface_name), "%s path %s" % [biome.id, surface_name])
			if surfaces.has(surface_name):
				assert_eq(surfaces[surface_name].role, "built", "%s %s" % [biome.id, surface_name])
		var accents := PaletteLibrary.ground_accents(biome.id)
		assert_gt(accents.size(), 0, "%s ground_accents" % biome.id)
		for accent in accents:
			var surface_name: String = accent.surface
			var label := "%s accent %s" % [biome.id, surface_name]
			assert_true(surfaces.has(surface_name), label)
			if surfaces.has(surface_name):
				assert_eq(surfaces[surface_name].role, "ground", label)
			assert_ne(surface_name, biome.ground_surface, label)
			assert_gt(accent.coverage, 0.0, label)
			assert_gt(accent.scale_m, 0.0, label)


func test_every_surface_map_is_a_raw_png_the_surface_store_can_read() -> void:
	for surface_name in PaletteLibrary.surfaces():
		var surface: Dictionary = PaletteLibrary.surfaces()[surface_name]
		for map_name in PaletteLibrary.SURFACE_MAPS:
			assert_true(
				SurfaceStore.available(PaletteLibrary.DEFAULT_ROOT, String(surface[map_name])),
				"%s %s" % [surface_name, map_name]
			)


## Every one of the palette's assets: resolves to a mesh, keeps the catalog's wind category, and
## carries COLOR_0 on every surface when it sways (contract section 5). A still asset (a rock, a
## log) may carry COLOR_0 too: the wind shader reads the category, not the attribute.
func test_every_asset_resolves_with_its_manifest_wind_data() -> void:
	for asset_id in _asset_ids():
		var template := PaletteLibrary.resolve(asset_id)
		assert_true(template.get("mesh") is Mesh, asset_id)
		if not template.get("mesh") is Mesh:
			continue
		var category: String = PaletteLibrary.asset(asset_id).wind_category
		assert_eq(template.wind_category, category, asset_id)
		var mesh: Mesh = template.mesh
		if not category in WIND_CATEGORIES:
			continue
		for surface in mesh.get_surface_count():
			assert_true(
				WindFoliage.surface_has_vertex_colors(mesh, surface),
				"%s surface %d vertex colours" % [asset_id, surface]
			)


## One species per biome (the first, a large class) placed through build_scatter: chunks
## are built, tagged with the manifest category, and every swaying surface harvests the
## albedo and packed ORM WindFoliage needs with the authored wind weights switched on.
func test_one_species_per_biome_builds_chunks_with_a_full_harvest() -> void:
	var level := Node3D.new()
	var groups := {}
	for biome in PaletteLibrary.biomes():
		groups[biome.species[0].assets[0]] = _rows(12, 2.0)
	var built := ScatterGlbUtils.build_scatter(level, groups, PaletteLibrary.resolver(), {}, 10.0)
	assert_eq(built.size(), BIOME_COUNT)
	for asset_id in groups:
		var category: String = PaletteLibrary.asset(asset_id).wind_category
		var stem := String(asset_id.validate_node_name()) + "_MultiMesh"
		var chunks := level.get_children().filter(
			func(child: Node) -> bool: return String(child.name).begins_with(stem)
		)
		assert_eq(chunks.size(), 3, "%s: x = 0..22 m at chunk 10 is three cells" % asset_id)
		for chunk in chunks:
			assert_eq(chunk.get_meta("wind_foliage_category"), category, asset_id)
		if chunks.is_empty() or category == "":
			continue
		var mesh: Mesh = (chunks[0] as MultiMeshInstance3D).multimesh.mesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as ShaderMaterial
			assert_not_null(material, asset_id)
			if material == null:
				continue
			# Leaf cards carry no ORM map (only bark does), so only the albedo is required.
			assert_not_null(material.get_shader_parameter("albedo_texture"), asset_id)
			assert_true(material.get_shader_parameter("use_vertex_wind"), asset_id)
	level.free()
