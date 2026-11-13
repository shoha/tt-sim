extends GutTest

## The painted look's surfaces (PainterSurfaces, PainterGroundRoles, PainterPlantRoles,
## PainterTones; docs/systems/painter.md "Surfaces"): every core surface and biome has a ground
## role, painting swaps the terrain's and the scatter's materials and releasing puts the very
## same ones back, chunks and species built later are painted by the events, a stand-in survives
## the foliage AA swap on entering and leaving the eye view, the tones and the thinning are the
## sheet's, and LevelEnvironmentManager's painted_look_changed fires on entering and leaving
## Painted only. Uses the built-in palette's temperate forest assets.

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_v0"
const GRASS := BIOME + "/Grass_Grass_v0_temperate_forest"
const BOULDER := BIOME + "/Rock_Boulder_summer_08_temperate_forest"
const SURFACES_DIR := "res://libraries/core/surfaces"
const BIOMES_DIR := "res://libraries/core/biomes"
const STATE := {"sheet": "core", "mood": "summer", "elevation": 45.0}

var _container: Node3D = null
var _map: Node3D = null
var _choice: int = RenderStyle.DEFAULT_CHOICE


func before_each() -> void:
	PainterSheet.clear_cache()
	_choice = RenderStyle.choice
	_container = Node3D.new()
	add_child_autofree(_container)
	_map = Node3D.new()
	_map.name = "LevelMap"
	_container.add_child(_map)


func after_each() -> void:
	RenderStyle.choice = _choice


func _rows(points: Array) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p: Vector2 in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0])
	return rows


func _scatter() -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = 1_000_000_000
	scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	return scatter


func _terrain() -> AuthoredTerrain:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass_meadow", "test", 7)
	var terrain := AuthoredTerrain.create(doc)
	_map.add_child(terrain)
	return terrain


func _chunks(terrain: AuthoredTerrain) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for cell in terrain.chunk_cells():
		out.append(terrain.get_chunk(cell))
	return out


func _mesh_of(scatter: AuthoredScatter, asset_id: String) -> Mesh:
	return scatter.resolved_species()[asset_id]["mesh"]


func _materials(mesh: Mesh) -> Array[Material]:
	var out: Array[Material] = []
	for i in mesh.get_surface_count():
		out.append(mesh.surface_get_material(i))
	return out


# --- roles --------------------------------------------------------------------------------


func test_every_core_surface_has_a_ground_role() -> void:
	var ids := DirAccess.get_directories_at(SURFACES_DIR)
	assert_gt(ids.size(), 30, "the core library's surfaces are listed")
	for id in ids:
		assert_gt(PainterGroundRoles.surface_rule(id), -1, "%s resolves by a rule" % id)
	assert_eq(PainterGroundRoles.surface_role("gravel_sandstone"), "path")
	assert_eq(PainterGroundRoles.surface_role("cliff_sandstone"), "rock")
	assert_eq(PainterGroundRoles.surface_role("dirt_mud"), "shore")
	assert_eq(PainterGroundRoles.surface_role("forest_floor_litter"), "floor")
	assert_eq(PainterGroundRoles.surface_role("grass_meadow"), "meadow")
	assert_eq(PainterGroundRoles.surface_role("someone_elses_tarmac"), "meadow", "default")


func test_every_core_biome_paints_in_its_own_ground_surface_role() -> void:
	var files := DirAccess.get_files_at(BIOMES_DIR)
	var seen := 0
	for file in files:
		if not file.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BIOMES_DIR + "/" + file))
		var id := file.get_basename()
		var surface: String = (data.get("ground", {}) as Dictionary).get("surface", "")
		assert_gt(PainterGroundRoles.biome_rule(id), -1, "%s resolves by a rule" % id)
		assert_eq(
			PainterGroundRoles.biome_role(id),
			PainterGroundRoles.surface_role(surface),
			"%s paints as its ground surface %s" % [id, surface]
		)
		seen += 1
	assert_eq(seen, 9, "the nine core biomes")
	assert_eq(PainterGroundRoles.biome_role(BIOME), "floor", "a compiled biome id")


func test_every_ground_role_paints_a_sheet_role() -> void:
	for role in PainterGroundRoles.ROLES:
		var tone: String = PainterGroundRoles.TONE_ROLE[role]
		assert_true((PainterSheet.COLOR_ROLES + PainterSheet.DEFAULT_ROLES).has(tone), tone)


func test_plants_take_a_kind_and_trees_stay_classic() -> void:
	assert_eq(PainterPlantRoles.of(OAK, "tree"), {})
	assert_eq(PainterPlantRoles.of(GRASS, "grass")["kind"], PainterPlantRoles.KIND_GRASS)
	assert_eq(PainterPlantRoles.of(BOULDER, "")["role"], "stone")
	assert_true(PainterPlantRoles.of("x/Clump_Sprig", "grass", true)["ground_cover"], "a flower")


# --- swapping -----------------------------------------------------------------------------


func test_painting_swaps_the_surfaces_and_release_restores_the_originals_exactly() -> void:
	var terrain := _terrain()
	var scatter := _scatter()
	scatter.build_all(
		{
			GRASS: _rows([Vector2(1, 1)]),
			BOULDER: _rows([Vector2(2, 2)]),
			OAK: _rows([Vector2(3, 3)]),
		}
	)
	var grass := _mesh_of(scatter, GRASS)
	var boulder := _mesh_of(scatter, BOULDER)
	var oak := _mesh_of(scatter, OAK)
	var before := {"grass": _materials(grass), "boulder": _materials(boulder), "oak": _materials(oak)}
	var skirt := terrain.get_skirt()
	var surfaces := PainterSurfaces.new()

	assert_true(surfaces.paint(_map, STATE))

	for chunk in _chunks(terrain):
		assert_eq(chunk.material_override, surfaces.ground_material(), "chunk painted")
	assert_not_null(skirt.material_override, "skirt painted")
	for material in _materials(grass) + _materials(boulder):
		assert_true(material.has_meta(PainterSurfaces.META), "scatter painted")
		var original: Variant = material.get_meta(WindFoliage.META_STAND_IN)
		assert_true(original in before["grass"] + before["boulder"], "stand-in keeps its original")
	var grass_shader := (grass.surface_get_material(0) as ShaderMaterial).shader
	var boulder_shader := (boulder.surface_get_material(0) as ShaderMaterial).shader
	assert_eq(grass_shader.resource_path, PainterSurfaces.PLANT_SHADER, "grass sways painted")
	assert_eq(boulder_shader.resource_path, PainterSurfaces.SOLID_SHADER, "boulder is solid")
	assert_eq(_materials(oak), before["oak"], "trees stay Classic")

	surfaces.release()

	for chunk in _chunks(terrain):
		assert_null(chunk.material_override, "chunk restored")
	assert_null(skirt.material_override, "skirt restored")
	assert_eq(_materials(grass), before["grass"], "the same grass materials back")
	assert_eq(_materials(boulder), before["boulder"], "the same boulder materials back")
	assert_false(surfaces.is_active())


func test_species_and_chunks_built_later_are_painted_by_the_events() -> void:
	var terrain := _terrain()
	var scatter := _scatter()
	scatter.build_all({GRASS: _rows([Vector2(1, 1)])})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)

	scatter.set_cells({Vector2i(0, 0): {BOULDER: _rows([Vector2(2, 2)])}})
	var boulder := _mesh_of(scatter, BOULDER)
	assert_true(boulder.surface_get_material(0).has_meta(PainterSurfaces.META), "a later species")
	terrain.build(terrain.document)
	for chunk in _chunks(terrain):
		assert_eq(chunk.material_override, surfaces.ground_material(), "a rebuilt chunk")
	surfaces.release()


func test_a_stand_in_survives_the_foliage_aa_swap_entering_and_leaving_the_eye_view() -> void:
	var scatter := _scatter()
	scatter.build_all({GRASS: _rows([Vector2(1, 1)])})
	var game_map: GameMap = autofree(GameMap.new())
	game_map.map_container = _container
	var effects: VisualEffectsController = autofree(VisualEffectsController.new())
	effects._game_map = game_map
	effects._foliage_antialiasing_level = Viewport.MSAA_DISABLED
	var grass := _mesh_of(scatter, GRASS)
	var original := grass.surface_get_material(0) as ShaderMaterial
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var stand_in := grass.surface_get_material(0) as ShaderMaterial

	for eye: bool in [true, false]:
		effects.set_eye_view_antialiasing(eye)
		assert_eq(grass.surface_get_material(0), stand_in, "still the stand-in (eye %s)" % eye)
		assert_eq(stand_in.shader.resource_path, PainterSurfaces.PLANT_SHADER, "its shader kept")
		var antialiased := FoliageEdges.uses_antialiased_shader(
			effects.effective_antialiasing_level(), FoliageEdges.current
		)
		assert_eq(original.shader, WindFoliage.shader_for(original, antialiased), "original swapped")
	surfaces.release()
	assert_eq(grass.surface_get_material(0), original)


# --- tones --------------------------------------------------------------------------------


func test_the_tones_and_the_thinning_are_the_sheets() -> void:
	_terrain()
	var scatter := _scatter()
	scatter.build_all({GRASS: _rows([Vector2(1, 1)]), BOULDER: _rows([Vector2(2, 2)])})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var sheet := PainterSheet.load_sheet("core")
	var keep := PainterSheet.number(sheet, "summer", "keep-grass", 45.0)
	assert_almost_eq(keep, 0.6, 1e-6, "core.sheet keeps 60 % of the grass")
	var grass := _mesh_of(scatter, GRASS).surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(grass.get_shader_parameter(&"keep")), keep, 1e-6)
	assert_false(grass.get_shader_parameter(&"casts_shadow"), "ground cover casts none")
	var boulder := _mesh_of(scatter, BOULDER).surface_get_material(0) as ShaderMaterial
	assert_almost_eq(float(boulder.get_shader_parameter(&"keep")), 1.0, 1e-6, "rocks all stay")
	var ramp := PainterTones.ramp(sheet, "summer", "grass", 45.0)
	assert_eq(grass.get_shader_parameter(&"c_lit1"), PainterTones.linear(ramp[5]))
	var ground_ramp := PainterTones.ramp(sheet, "summer", "ground", 45.0, true)
	var lit: PackedVector3Array = surfaces.ground_material().get_shader_parameter(&"g_lit")
	assert_eq(lit[0], PainterTones.linear(ground_ramp[2]), "the meadow's lit tone")
	surfaces.paint(_map, {"sheet": "core", "mood": "summer", "elevation": -8.0})
	assert_ne(grass.get_shader_parameter(&"c_lit1"), PainterTones.linear(ramp[5]), "re-toned")
	surfaces.release()


func test_a_ramp_steps_from_shade_to_lit() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for role in ["ground", "leaf", "stone", "grass", "floor", "path"]:
		var ramp := PainterTones.ramp(sheet, "summer", role, 60.0)
		for variant in 2:
			var shade := PainterSheet.lch_of_color(ramp[variant * 3]).x
			var mid := PainterSheet.lch_of_color(ramp[variant * 3 + 1]).x
			var lit := PainterSheet.lch_of_color(ramp[variant * 3 + 2]).x
			assert_lt(shade, mid, "%s shade under its middle" % role)
			assert_lt(mid, lit, "%s middle under its lit" % role)


func test_the_zone_map_reads_the_document() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "forest_floor", "test", 7)
	var image := PainterSurfaces.zone_image(doc)
	assert_eq(image.get_size(), Vector2i(doc.samples_x(), doc.samples_z()))
	assert_almost_eq(image.get_pixel(3, 3).r, 0.0, 0.01, "forest floor is not meadow")
	doc.base_surface = "grass_meadow"
	assert_almost_eq(PainterSurfaces.zone_image(doc).get_pixel(3, 3).r, 1.0, 0.01)


# --- the signal ---------------------------------------------------------------------------


func test_the_signal_fires_on_entering_and_leaving_painted_only() -> void:
	var manager := LevelEnvironmentManager.new()
	var got: Array = []
	manager.painted_look_changed.connect(func(state: Dictionary) -> void: got.append(state))
	RenderStyle.choice = RenderStyle.CHOICE_PAINTED
	manager.set_look({"style": RenderStyle.PAINTED, "mood": "summer"})
	assert_eq(got, [STATE], "entering Painted")
	manager.apply_render_style()
	assert_eq(got.size(), 1, "the same state again emits nothing")
	RenderStyle.choice = RenderStyle.CHOICE_CLASSIC
	manager.apply_render_style()
	assert_eq(got, [STATE, {}], "leaving Painted")
	manager.clear()
	assert_eq(got.size(), 2, "already Classic")
