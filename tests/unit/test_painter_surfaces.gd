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
## The core biomes that paint in a derived ground role (painter-coverage).
const DRY_BIOMES := {"savanna": "dry", "burnt_forest": "ash", "rocky_badlands": "earth"}
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
		var role := PainterGroundRoles.biome_role(id)
		if DRY_BIOMES.has(id):
			# painter-coverage: these three paint in a derived tone of their own, not their
			# surface's role (a lush meadow green in a savanna, a burnt forest and the badlands).
			assert_eq(role, DRY_BIOMES[id], "%s paints in its own derived role" % id)
		else:
			assert_eq(
				role,
				PainterGroundRoles.surface_role(surface),
				"%s paints as its ground surface %s" % [id, surface]
			)
		seen += 1
	assert_eq(seen, 9, "the nine core biomes")
	assert_eq(PainterGroundRoles.biome_role(BIOME), "floor", "a compiled biome id")


func test_a_dry_biome_derives_its_tone_from_the_role_it_comes_from_and_follows_the_mood() -> void:
	var sheet := PainterSheet.load_sheet("core")
	for role: String in PainterGroundRoles.DERIVED:
		var spec: Array = PainterGroundRoles.DERIVED[role]
		var base := PainterSheet.tone_lch(sheet, "summer", str(spec[0]), 60.0)
		var got := PainterGroundRoles.derived(sheet, "summer", role, 60.0)
		assert_ne(snappedf(got.z, 1.0), snappedf(base.z, 1.0), "%s turns its hue" % role)
		var night := PainterGroundRoles.derived(sheet, "summer", role, -8.0)
		assert_lt(night.x, got.x, "%s is darker at night" % role)
		var snow := PainterGroundRoles.derived(sheet, "winter", role, 60.0)
		assert_ne(snow.snappedf(0.01), got.snappedf(0.01), "%s follows the mood" % role)
	# dry reads straw, ash a dull warm grey, earth a baked orange (hue in degrees).
	assert_between(PainterGroundRoles.derived(sheet, "summer", "dry", 60.0).z, 70.0, 100.0)
	assert_lt(PainterGroundRoles.derived(sheet, "summer", "ash", 60.0).y, 0.05)
	assert_between(PainterGroundRoles.derived(sheet, "summer", "earth", 60.0).z, 35.0, 70.0)


func test_the_biome_zone_map_exists_only_for_a_map_with_a_dry_biome() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	doc.biome_ids = PackedStringArray(["temperate_forest_summer_s1"])
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	doc.biome_slots.fill(1)
	doc.biome_density.fill(255)
	assert_null(PainterSurfaces.biome_zone_image(doc), "no dry biome, no second map")
	doc.biome_ids = PackedStringArray(["savanna_summer_s1", "rocky_badlands_summer_s1"])
	var image := PainterSurfaces.biome_zone_image(doc)
	assert_not_null(image)
	assert_almost_eq(image.get_pixel(3, 3).r, 1.0, 0.01, "slot 1 is savanna: r dry")
	assert_almost_eq(image.get_pixel(3, 3).b, 0.0, 0.01)
	doc.biome_slots.fill(2)
	image = PainterSurfaces.biome_zone_image(doc)
	assert_almost_eq(image.get_pixel(3, 3).b, 1.0, 0.01, "slot 2 is the badlands: b earth")


func test_a_dry_biomes_tufts_are_straw_and_the_others_stay_green() -> void:
	var dry := PainterPlantRoles.of("savanna_summer_s1/Grass_Grass_v1", "grass")
	assert_eq(dry["role"], PainterPlantRoles.DRY_GRASS_ROLE)
	assert_eq(dry["kind"], PainterPlantRoles.KIND_GRASS)
	var badlands := PainterPlantRoles.of("rocky_badlands_summer_s1/Grass_Grass_v1", "grass")
	assert_eq(badlands["role"], "dry-grass")
	var meadow := PainterPlantRoles.of("grassland_meadow_summer_s1/Grass_Grass_v1", "grass")
	assert_eq(meadow["role"], "grass")
	var rock := PainterPlantRoles.of("savanna_summer_s1/Rock_Medium_summer_06", "")
	assert_eq(rock["role"], "stone")


func test_every_ground_role_paints_a_sheet_role() -> void:
	for role in PainterGroundRoles.ROLES:
		var tone: String = PainterGroundRoles.TONE_ROLE[role]
		assert_true((PainterSheet.COLOR_ROLES + PainterSheet.DEFAULT_ROLES).has(tone), tone)


func test_plants_take_a_kind_and_trees_stay_classic() -> void:
	assert_eq(PainterPlantRoles.of(OAK, "tree"), {})
	# A bush sways as a tree but is a leaf mass the plant shader paints (one season in winter), in
	# the crowns' hand and tones.
	var bush := PainterPlantRoles.of(BIOME + "/Bush_BerryBush_v0_temperate_forest", "tree")
	assert_eq(bush["kind"], PainterPlantRoles.KIND_CROWN)
	assert_eq(bush["role"], "leaf")
	assert_eq(PainterPlantRoles.of("x/Shrub_Box", "grass")["kind"], PainterPlantRoles.KIND_CROWN)
	# painter-trees-fix: a fern is a low leaf mass in the crowns' hand too (as a plain leaf mass its
	# frond cards read as streaky shards); ivy and moss stay plain leaf masses.
	var fern := BIOME + "/Fern_Fern_v0_temperate_forest"
	assert_eq(PainterPlantRoles.of(fern, "grass")["kind"], PainterPlantRoles.KIND_CROWN)
	assert_eq(PainterPlantRoles.of("x/Ivy_Wall", "grass")["kind"], PainterPlantRoles.KIND_MASS)
	var ramp: Array = (load(PainterPlantRoles.CROWN_TONES) as GDScript).call(
		"bush_ramp", PainterSheet.load_sheet("core"), "summer", 60.0
	)
	assert_eq(ramp.size(), 6, "a bush's ramp: shade, mid and lit of two variants")
	var leaf := PainterSheet.tone_lch(PainterSheet.load_sheet("core"), "summer", "leaf", 60.0)
	var mid := PainterSheet.lch_of_color(ramp[1])
	assert_lt(mid.x, leaf.x, "a bush is deeper than the sheet's leaf")
	assert_lt(mid.y, leaf.y, "and less saturated")
	assert_eq(PainterPlantRoles.of(GRASS, "grass")["kind"], PainterPlantRoles.KIND_GRASS)
	assert_eq(PainterPlantRoles.of(BOULDER, "")["role"], "stone")
	# painter-trees-fix2: the words are the asset's own, not its biome's ("grassland").
	var meadow_stone := PainterPlantRoles.of("grassland_meadow_summer_s1/Stone_Small_summer_04", "")
	assert_eq(meadow_stone["role"], "stone", "a meadow's stone is not a grass tuft")
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


func test_a_scatter_made_later_is_followed_and_its_painted_trees_go_with_its_visibility() -> void:
	# The eye view's rim (EyeRim) is an AuthoredScatter made on entering the eye view, after the
	# map was painted; its trees are painted too, and drawn only while it is shown.
	_terrain()
	var main := _scatter()
	main.build_all({GRASS: _rows([Vector2(1, 1)])})
	var surfaces := PainterSurfaces.new()
	surfaces.paint(_map, STATE)
	var host: RefCounted = surfaces.trees()
	assert_eq(host.trees.size(), 0, "no tree row yet")

	var rim := _scatter()
	rim.build_all({OAK: _rows([Vector2(30, 30), Vector2(33, 31)])})
	host.call("complete")
	assert_eq(host.trees.size(), 2, "the rim's trees are drawn painted")
	rim.visible = false
	assert_eq(host.trees.size(), 0, "hidden: none drawn")
	rim.visible = true
	host.call("complete")
	assert_eq(host.trees.size(), 2, "shown again: drawn again")
	surfaces.release()
	assert_true(rim.visibility_changed.get_connections().is_empty(), "released: no watch left")


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
	var ramp := PainterTones.ramp(sheet, "summer", "grass", 45.0, "grass-")
	assert_eq(grass.get_shader_parameter(&"c_lit1"), PainterTones.linear(ramp[5]))
	var plain := PainterTones.ramp(sheet, "summer", "grass", 45.0)
	assert_ne(ramp[5], plain[5], "grass has its own lit step")
	var ground_ramp := PainterTones.ramp(sheet, "summer", "ground", 45.0, "ground-")
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


func test_shade_keep_scales_the_roles_own_chroma_under_the_pull() -> void:
	var shape := {
		"shade-hue": 290.0,
		"shade-pull": 0.5,
		"shade-depth": 0.6,
		"lit-hue": 45.0,
		"lit-pull": 0.0,
		"lit-lift": 0.1,
	}
	var lch := Vector3(0.7, 0.06, 60.0)
	var full: Vector3 = PainterTones.steps(lch, shape)[0]
	shape["shade-keep"] = 1.0
	assert_eq(PainterTones.steps(lch, shape)[0], full, "keep 1 is the old ramp, and the default")
	shape["shade-keep"] = 0.0
	var none: Vector3 = PainterTones.steps(lch, shape)[0]
	assert_almost_eq(none.y, 0.5 * PainterTones.PULL_CHROMA, 0.0001, "only the pull is left")
	assert_almost_eq(none.z, 290.0, 0.01, "at the shade hue, whatever the role's own")
	var core := PainterSheet.load_sheet("core")
	var path := PainterSheet.lch_of_color(PainterTones.ramp(core, "dusk", "path", 20.0, "ground-")[0])
	assert_lt(path.y, 0.07, "dusk's path shade is a quiet lilac, not magenta")
	assert_between(path.z, 270.0, 310.0, "dusk's path shade leans lilac")


func test_the_zone_map_reads_the_document() -> void:
	var doc := MapDocument.create_flat(Vector2i(10, 10), "forest_floor", "test", 7)
	var image := PainterSurfaces.zone_image(doc)
	assert_eq(image.get_size(), Vector2i(doc.samples_x(), doc.samples_z()))
	assert_almost_eq(image.get_pixel(3, 3).r, 0.0, 0.01, "forest floor is not meadow")
	doc.base_surface = "grass_meadow"
	assert_almost_eq(PainterSurfaces.zone_image(doc).get_pixel(3, 3).r, 1.0, 0.01)


func test_the_zone_map_matches_the_plain_loop_on_a_painted_document() -> void:
	# painter-perf-cpu: zone_image reads the document's arrays once, skips the blur of a channel
	# nothing touched and blurs radius 1 in three-tap passes; the bytes are the plain loop's.
	var doc := MapDocument.create_flat(Vector2i(14, 11), "grass_meadow", "test", 7)
	var n := doc.samples_x() * doc.samples_z()
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	doc.biome_ids = PackedStringArray(
		["temperate_forest", "grassland_meadow", "desert_dunes", "unknown_x"]
	)
	doc.surface_ids = PackedStringArray(
		["dirt_road_packed", "cliff_rock", "sand_beach", "unknown_y"]
	)
	doc.biome_slots.resize(n)
	doc.biome_density.resize(n)
	doc.surface_weights.resize(n * MapDocument.SURFACE_BYTES)
	doc.water_dressing.resize(n * 4)
	for i in n:
		doc.biome_slots[i] = rng.randi_range(0, 5)
		doc.biome_density[i] = rng.randi_range(0, 255)
		doc.water_dressing[i * 4] = rng.randi_range(0, 255) if rng.randf() < 0.1 else 0
	for i in n * MapDocument.SURFACE_BYTES:
		var is_index := i < n * 4
		doc.surface_weights[i] = (
			rng.randi_range(0, 4) if is_index else rng.randi_range(0, 255) * (rng.randi() % 2)
		)
	var got := PainterSurfaces.zone_image(doc)
	var want := _zone_plain(doc)
	assert_eq(got.get_size(), want.get_size())
	var off := 0
	var a := got.get_data()
	var b := want.get_data()
	for i in a.size():
		off += int(absi(int(a[i]) - int(b[i])) > 1)
	assert_eq(off, 0, "no byte more than one step from the plain loop")
	assert_lt(_differing(a, b), a.size() / 50, "and almost none at all")


func _differing(a: PackedByteArray, b: PackedByteArray) -> int:
	var count := 0
	for i in a.size():
		count += int(a[i] != b[i])
	return count


## The zone map as the document's arrays read one property at a time, the blur's general loop.
func _zone_plain(doc: MapDocument) -> Image:
	var sx := doc.samples_x()
	var sz := doc.samples_z()
	var n := sx * sz
	var base := PainterSurfaces._mix_role(
		Vector4.ZERO, PainterGroundRoles.surface_role(doc.base_surface), 1.0
	)
	var channels: Array[PackedFloat32Array] = []
	for c in 4:
		var plane := PackedFloat32Array()
		plane.resize(n)
		channels.append(plane)
	for i in n:
		var v := base
		var slot: int = doc.biome_slots[i]
		if slot > 0 and slot <= doc.biome_ids.size():
			var pull := clampf(doc.biome_density[i] / 255.0 * PainterSurfaces.BIOME_PULL, 0.0, 1.0)
			v = PainterSurfaces._mix_role(v, PainterGroundRoles.biome_role(doc.biome_ids[slot - 1]), pull)
		for e in 4:
			var w := doc.surface_weights[n * 4 + i * 4 + e] / 255.0
			var at := doc.surface_weights[i * 4 + e]
			if w > 0.0 and at < doc.surface_ids.size():
				v = PainterSurfaces._mix_role(v, PainterGroundRoles.surface_role(doc.surface_ids[at]), w)
		v.w = maxf(v.w, maxf(doc.water_dressing[i * 4], doc.water_dressing[i * 4 + 1]) / 255.0)
		for c in 4:
			channels[c][i] = v[c]
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for c in 4:
		var plane := PainterSurfaces._box_generic(channels[c], sx, sz, PainterSurfaces.ZONE_BLUR)
		for i in n:
			bytes[i * 4 + c] = clampi(roundi(plane[i] * 255.0), 0, 255)
	return Image.create_from_data(sx, sz, false, Image.FORMAT_RGBA8, bytes)


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


# --- the tuft dabs ------------------------------------------------------------------------


func test_a_wide_tuft_is_cut_by_the_dab_layouts_and_a_reed_is_not() -> void:
	# Core's meadow tuft: 0.91 m across, 0.39 m tall.
	var array := PainterTuftAtlas.for_tuft(Vector3(0.455, 0.195, 0.445), 0.39)
	assert_not_null(array, "a meadow tuft is wide")
	assert_eq(array.get_layers(), PainterTuftAtlas.LAYERS)
	assert_eq(array.get_width(), PainterTuftAtlas.SIZE)
	assert_null(PainterTuftAtlas.for_tuft(Vector3(0.1, 0.5, 0.1), 1.0), "a reed keeps its texture")
	assert_eq(
		PainterTuftAtlas.for_tuft(Vector3(0.46, 0.2, 0.45), 0.39),
		array,
		"a near aspect shares the array"
	)
	var src := FileAccess.get_file_as_string("res://painter/shaders/painter_selector.gdshaderinc")
	assert_true(src.contains("TUFT_LAYERS = %.1f;" % PainterTuftAtlas.LAYERS), "the shader's layers")
	assert_true(src.contains("TUFT_RANGE = %.1f;" % PainterTuftAtlas.RANGE), "the shader's range")
	for layer in PainterTuftAtlas.LAYERS:
		var image := PainterTuftAtlas.layer_image(1.17, layer)
		var mid := PainterTuftAtlas.SIZE >> 1
		assert_lt(image.get_pixel(0, 0).r, 0.5, "layer %d: the card's top corner is cut" % layer)
		assert_gt(image.get_pixel(mid, mid).r, 0.5, "layer %d: its middle drawn" % layer)
		assert_gt(
			image.get_pixel(mid, PainterTuftAtlas.SIZE - 1).r, 0.5, "layer %d: its foot drawn" % layer
		)
