extends GutTest

## The seam check for the real built-in palette: treecube's committed output under
## res://assets/palette (docs/ASSET_PIPELINE.md section 9) loaded through PaletteLibrary
## with its default root, the first committed golden fixture from a producer (section 8).
## test_palette_library.gd covers the loader's rules against a synthetic palette; this
## file fails when a palette refresh breaks what tt-sim relies on.
##
## Headless CI has no GPU, so everything here asserts on structure (meshes, vertex
## colour arrays, harvested material parameters, chunk nodes), never on pixels. CI
## imports the project before running tests, so the imported resources exist there.

const BIOME_COUNT := 8
const SURFACE_COUNT := 25
## Surfaces per role (section 9 "Surface role"); the rest of SURFACE_COUNT is ground.
const CLIFF_SURFACE_COUNT := 3
const BUILT_SURFACE_COUNT := 7
const WIND_CATEGORIES := ["tree", "grass"]
## Committed surface-map sidecar settings per map (section 9 "Import path"), all
## mipmapped: albedo BC7 (VRAM, high quality), normal BC5 (VRAM, normal-map flag), ORM
## BC1 (VRAM, normal quality), height lossless with detect_3d off so an editor session
## cannot silently switch it to VRAM compression. A new surface whose sidecar Godot
## generated with defaults (lossless, no mipmaps) fails here.
const SURFACE_IMPORT_PARAMS := {
	"albedo":
	{
		"compress/mode": 2,
		"compress/high_quality": true,
		"compress/normal_map": 0,
		"mipmaps/generate": true,
	},
	"normal":
	{
		"compress/mode": 2,
		"compress/high_quality": false,
		"compress/normal_map": 1,
		"mipmaps/generate": true,
	},
	"orm":
	{
		"compress/mode": 2,
		"compress/high_quality": false,
		"compress/normal_map": 0,
		"mipmaps/generate": true,
	},
	"height":
	{
		"compress/mode": 0,
		"detect_3d/compress_to": 0,
		"mipmaps/generate": true,
	},
}
## Sidecar settings the export path depends on (section 9 "Import path"). A palette
## refresh that drops the committed .import files falls back to Godot's defaults, which
## extract every embedded texture next to the GLB as a mipmapped PNG (small flowers fade
## at game scale) and generate LODs that decimate leaf cards. 3 is "Embed as
## Uncompressed": the textures match the runtime GLTFDocument load pixel for pixel.
const GLB_IMPORT_PARAMS := {
	"gltf/embedded_image_handling": 3,
	"meshes/generate_lods": false,
	"meshes/create_shadow_meshes": false,
}


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


func test_the_palette_loads_without_warnings() -> void:
	var palette := PaletteLibrary.get_palette()
	assert_ne(palette["palette_version"], "", "treecube stamps its commit")
	assert_eq(palette["biomes"].size(), BIOME_COUNT)
	assert_eq(palette["surfaces"].size(), SURFACE_COUNT)
	# A validation warning is a push_warning, which GUT fails as an unexpected error.


func test_every_biome_names_a_shipped_ground_surface_and_thumbnail() -> void:
	var surfaces := PaletteLibrary.surfaces()
	for biome in PaletteLibrary.biomes():
		assert_true(surfaces.has(biome.ground_surface), biome.id)
		assert_true(
			ResourceLoader.exists(PaletteLibrary.DEFAULT_ROOT.path_join(biome.thumbnail)), biome.id
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
## wrong-role surface, so a resolved, role-correct name here is the one palette.json gave.
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


## The raw palette.json biome entry for an id, to compare against what the loader kept.
func _raw_biome(biome_id: String) -> Dictionary:
	var path := PaletteLibrary.DEFAULT_ROOT.path_join("palette.json")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	for entry in raw["biomes"]:
		if entry["id"] == biome_id:
			return entry
	return {}


## Palette v5 gives every biome path surfaces and ground accents (section 9). The loader
## drops a wrong-role or missing name with a warning GUT fails on; comparing against the
## raw lists also catches a silently ignored duplicate.
func test_every_biome_resolves_its_path_surfaces_and_ground_accents() -> void:
	var surfaces := PaletteLibrary.surfaces()
	for biome in PaletteLibrary.biomes():
		var raw := _raw_biome(biome.id)
		var paths := PaletteLibrary.path_surfaces(biome.id)
		assert_gt(paths.size(), 0, "%s path_surfaces" % biome.id)
		assert_eq(paths.size(), raw.get("path_surfaces", []).size(), "%s paths kept" % biome.id)
		for surface_name in paths:
			assert_true(surfaces.has(surface_name), "%s path %s" % [biome.id, surface_name])
			if surfaces.has(surface_name):
				assert_eq(surfaces[surface_name].role, "built", "%s %s" % [biome.id, surface_name])
		var accents := PaletteLibrary.ground_accents(biome.id)
		assert_gt(accents.size(), 0, "%s ground_accents" % biome.id)
		assert_eq(accents.size(), raw.get("ground_accents", []).size(), "%s kept" % biome.id)
		for accent in accents:
			var surface_name: String = accent.surface
			var label := "%s accent %s" % [biome.id, surface_name]
			assert_true(surfaces.has(surface_name), label)
			if surfaces.has(surface_name):
				assert_eq(surfaces[surface_name].role, "ground", label)
			assert_ne(surface_name, biome.ground_surface, label)
			assert_gt(accent.coverage, 0.0, label)
			assert_gt(accent.scale_m, 0.0, label)


func test_every_surface_map_is_an_imported_texture_with_the_committed_settings() -> void:
	for surface_name in PaletteLibrary.surfaces():
		var surface: Dictionary = PaletteLibrary.surfaces()[surface_name]
		for map_name in PaletteLibrary.SURFACE_MAPS:
			var path := PaletteLibrary.DEFAULT_ROOT.path_join(surface[map_name])
			assert_true(ResourceLoader.exists(path, "Texture2D"), path)
			var sidecar := ConfigFile.new()
			assert_eq(sidecar.load(path + ".import"), OK, path)
			var params: Dictionary = SURFACE_IMPORT_PARAMS[map_name]
			for param in params:
				assert_eq(sidecar.get_value("params", param), params[param], path + " " + param)


func test_every_asset_is_an_editor_import_with_the_committed_settings() -> void:
	for asset_id in _asset_ids():
		var path := PaletteLibrary.DEFAULT_ROOT.path_join(PaletteLibrary.asset(asset_id).file)
		# What an export ships: the imported scene, reachable through ResourceLoader.
		assert_true(ResourceLoader.exists(path, "PackedScene"), path)
		var sidecar := ConfigFile.new()
		assert_eq(sidecar.load(path + ".import"), OK, path)
		for param in GLB_IMPORT_PARAMS:
			assert_eq(
				sidecar.get_value("params", param), GLB_IMPORT_PARAMS[param], path + " " + param
			)


## Every one of the 180 assets: resolves to a mesh, keeps the manifest's wind category,
## and carries COLOR_0 on every surface exactly when it sways (contract section 5).
func test_every_asset_resolves_with_its_manifest_wind_data() -> void:
	for asset_id in _asset_ids():
		var template := PaletteLibrary.resolve(asset_id)
		assert_true(template.get("mesh") is Mesh, asset_id)
		if not template.get("mesh") is Mesh:
			continue
		var category: String = PaletteLibrary.asset(asset_id).wind_category
		assert_eq(template.wind_category, category, asset_id)
		var mesh: Mesh = template.mesh
		for surface in mesh.get_surface_count():
			assert_eq(
				WindFoliage.surface_has_vertex_colors(mesh, surface),
				category in WIND_CATEGORIES,
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
			assert_not_null(material.get_shader_parameter("albedo_texture"), asset_id)
			assert_not_null(material.get_shader_parameter("orm_texture"), asset_id)
			assert_true(material.get_shader_parameter("use_vertex_wind"), asset_id)
	level.free()
