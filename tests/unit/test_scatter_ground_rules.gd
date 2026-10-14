extends GutTest

## ScatterGenerator.document_fields and the ground's automatic dressing (TerrainRules):
## plants thin on automatic rock and under painted built surfaces, a hand-painted ground
## surface yields to the rock on a face (P3-6), rock species gather on the scree at a
## cliff's foot, and trees keep back from tier faces (P3-7).

const FOREST := "temperate_forest_summer_s1"
const DENSITY := 128
## The step runs along world x = STEP_X.
const STEP_X := 3.0


func _doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 21)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(doc.sample_count())
	density.resize(doc.sample_count())
	slots.fill(1)
	density.fill(DENSITY)
	doc.biome_slots = slots
	doc.biome_density = density
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x > STEP_X:
				doc.heights[doc.sample_index(x, z)] = 1.524
	return doc


func _paint(doc: MapDocument, surface: String, low: Vector2, high: Vector2) -> void:
	var slot := doc.ensure_surface(surface)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x >= low.x and p.x <= high.x and p.y >= low.y and p.y <= high.y:
				doc.set_surface_weight(doc.sample_index(x, z), slot, 255)


## The middle of the face: halfway between the last low and first high sample columns.
func _face_x(doc: MapDocument) -> float:
	var s := doc.world_to_sample(Vector2(STEP_X, 0.0)).x
	return doc.sample_to_world(Vector2(floorf(s) + 0.5, 0.0)).x


func test_plants_thin_on_rock_and_under_built_paint() -> void:
	var doc := _doc()
	_paint(doc, "cobblestone", Vector2(-12, -3), Vector2(-8, 3))
	var fields := ScatterGenerator.document_fields(
		doc, FOREST, Rect2(), PackedStringArray(["cobblestone"])
	)
	var base := DENSITY / 255.0
	var open: float = fields.density_at.call(Vector2(-3.0, 0.0))
	assert_almost_eq(open, base, 1e-6, "flat, unpainted ground keeps its density")
	var face_x := _face_x(doc)
	var worst_face := 0.0
	for z in range(-8, 9):
		worst_face = maxf(worst_face, fields.density_at.call(Vector2(face_x, z)))
	assert_lt(worst_face, 0.01, "nothing grows on the rock face")
	assert_eq(fields.density_at.call(Vector2(-10.0, 0.0)), 0.0, "a road clears its plants")
	assert_eq(fields.rock_density_at.call(Vector2(-10.0, 0.0)), 0.0, "rocks too")


func test_painted_ground_yields_to_the_rock_on_faces() -> void:
	# The user's cliff-face decision (2026-09-27): ground paint covers walkable ground only.
	var doc := _doc()
	_paint(doc, "grass", Vector2(STEP_X - 2.0, -4), Vector2(STEP_X + 2.0, 4))
	var fields := ScatterGenerator.document_fields(
		doc, FOREST, Rect2(), PackedStringArray(["cobblestone"])
	)
	var face: float = fields.density_at.call(Vector2(_face_x(doc), 0.0))
	assert_lt(face, 0.01, "grass painted over the face: still rock, nothing grows")


func test_rocks_gather_on_the_scree() -> void:
	var doc := _doc()
	var fields := ScatterGenerator.document_fields(doc, FOREST, Rect2(), PackedStringArray())
	var base := DENSITY / 255.0
	var gathered := 0
	var wrong := 0
	var foot_x := _face_x(doc) - 0.6
	for k in 80:
		var p := Vector2(foot_x, -10.0 + k * 0.25)
		var plants: float = fields.density_at.call(p)
		var rocks: float = fields.rock_density_at.call(p)
		if rocks > base + 0.01:
			gathered += 1
			if plants >= base:
				wrong += 1
		elif not is_equal_approx(rocks, plants) and rocks < plants:
			wrong += 1
	assert_gt(gathered, 10, "along the foot, rock species are denser than painted")
	assert_eq(wrong, 0, "where rocks gather the other plants thin, never the reverse")
	var far: float = fields.rock_density_at.call(Vector2(-10.0, 0.0))
	assert_almost_eq(far, base, 1e-6, "no boost away from cliffs")


func _tree_rule() -> Dictionary:
	return {
		"key": "tree",
		"kind": "tree",
		"size_class": "large",
		"density_per_m2": 0.6,
		"min_spacing_m": 0.6,
		"assets": ["test/Tree"],
		"width_m": 5.0,
	}


func test_footing_sag_is_large_on_a_rim_and_zero_back_from_it_and_on_slopes() -> void:
	var doc := _doc()
	var fields := ScatterGenerator.document_fields(doc, FOREST)
	var r := GroundSnap.footing_radius(_tree_rule())
	var top_edge := _face_x(doc) + 0.25
	var sag_rim := GroundSnap.footing_sag(fields.height_at, Vector2(top_edge, 0.0), r)
	assert_gt(sag_rim, GroundSnap.FOOTING_SAG_M, "a trunk on the rim hangs over the drop")
	var back := GroundSnap.footing_sag(fields.height_at, Vector2(top_edge + 1.0, 0.0), r)
	assert_almost_eq(back, 0.0, 1e-5, "a metre back it stands on flat ground")
	var slope := func(p: Vector2) -> float: return p.x * 0.7
	assert_almost_eq(GroundSnap.footing_sag(slope, Vector2(1, 2), r), 0.0, 1e-5, "even slope")
	assert_eq(GroundSnap.footing_radius({"size_class": "ground", "width_m": 1.5}), 0.0)
	assert_eq(
		GroundSnap.footing_radius({"kind": "rock", "size_class": "small", "width_m": 0.2}), 0.0
	)
	assert_gt(
		GroundSnap.footing_radius({"kind": "rock", "size_class": "medium", "width_m": 1.7}), 0.4
	)


func test_no_generated_tree_stands_on_a_rim_and_trees_a_metre_back_remain() -> void:
	var doc := _doc()
	var fields := ScatterGenerator.document_fields(doc, FOREST)
	var species: Array[Dictionary] = [_tree_rule()]
	var bounds := Rect2(-10, -10, 20, 20)
	var one := func(_p: Vector2) -> float: return 1.0
	var rows := ScatterGenerator.generate(
		"test",
		species,
		one,
		fields.height_at,
		fields.normal_at,
		5,
		ScatterGenerator.cells_in_bounds(bounds),
		bounds
	)
	var flat: PackedFloat32Array = rows.get("test/Tree", PackedFloat32Array())
	var r := GroundSnap.footing_radius(_tree_rule())
	var face_x := _face_x(doc)
	var near_rim := 0
	var back := 0
	for i in range(0, flat.size(), MapDocument.ROW_STRIDE):
		var p := Vector2(flat[i], flat[i + 2])
		assert_lt(GroundSnap.footing_sag(fields.height_at, p, r), GroundSnap.FOOTING_SAG_M)
		if p.x > face_x and p.x < face_x + r * 0.8:
			near_rim += 1
		if p.x > face_x + 1.0 and p.x < face_x + 2.0:
			back += 1
	assert_eq(near_rim, 0, "no tree with its trunk over the rim")
	assert_gt(back, 3, "trees a metre back from the rim remain")


func test_a_prop_at_a_rim_beds_on_the_lowest_ground_under_its_base() -> void:
	var doc := _doc()
	var grid := GroundSnap.grid_of(doc)
	var r := GroundSnap.footing_radius(_tree_rule())
	var rim := Vector2(_face_x(doc) + 0.25, 0.0)
	assert_almost_eq(GroundSnap.lowest_under(doc.heights, grid, rim, r), 0.0, 1e-5, "base low")
	assert_almost_eq(GroundSnap.lowest_under(doc.heights, grid, rim, 0.0), 1.524, 1e-5)
	# Re-bedding after a sculpt stroke: a prop on flat ground that is now a rim sinks.
	var flat := PackedFloat32Array()
	flat.resize(doc.sample_count())
	var row := PropRows.make_row(Vector3(rim.x, 0.0, rim.y), Vector3.UP, false, 0.3, 1.0)
	var window := Rect2(-20, -20, 40, 40)
	var sunk := GroundSnap.rebed_props(row, row, flat, doc.heights, grid, false, window, r)
	assert_almost_eq(sunk.rows[1], 0.0, 1e-5, "its base touches the low ground")
	var origin := GroundSnap.rebed_props(row, row, flat, doc.heights, grid, false, window)
	assert_almost_eq(origin.rows[1], 1.524, 1e-5, "without a footprint: the origin's height")


func test_tall_cover_and_shrubs_thin_beside_paths_and_short_cover_stays() -> void:
	# P3-7: tall grass on a path's shoulder hid a narrow path from the game camera.
	var doc := _doc()
	_paint(doc, "cobblestone", Vector2(-12, -0.5), Vector2(-4, 0.5))
	var fields := ScatterGenerator.document_fields(
		doc, FOREST, Rect2(), PackedStringArray(["cobblestone"])
	)
	var at: Callable = fields.species_density_at
	var base := DENSITY / 255.0
	var shoulder := Vector2(-8.0, 1.0)
	var clear := Vector2(-8.0, 3.0)
	assert_lt(at.call(shoulder, ScatterGround.ROLE_TALL_COVER), 0.01, "no tall grass on it")
	assert_lt(at.call(shoulder, ScatterGround.ROLE_SHRUB), 0.01, "nor shrubs")
	assert_almost_eq(at.call(shoulder, ScatterGround.ROLE_COVER), base, 1e-6, "short cover")
	assert_almost_eq(at.call(shoulder, ScatterGround.ROLE_TREE), base, 1e-6, "trees stay")
	assert_almost_eq(at.call(clear, ScatterGround.ROLE_TALL_COVER), base, 1e-6, "3 m out")
	# The real meadow. Since treecube 20d9451 (the grass rework) its grass stands 0.35 to 0.58 m,
	# under TALL_COVER_M, so grass clumps have their own line (GRASS_TALL_COVER_M, user
	# 2026-10-14): the clumps, the tall grass and the gold drift thin beside paths again, the
	# sprig (0.25 m) stays.
	var tall := ScatterGround.ROLE_TALL_COVER
	var cover := ScatterGround.ROLE_COVER
	var flower := ScatterGround.FLOWER_BIT
	var meadow := _roles("grassland_meadow_summer_s1")
	assert_eq(meadow.get("grass"), tall, "meadow clumps")
	assert_eq(meadow.get("tall_grass"), tall, "meadow tall grass")
	assert_eq(meadow.get("dry_drift"), tall, "meadow gold drift")
	assert_eq(meadow.get("sprig"), cover, "meadow sprig")
	# Flowers carry the water rules' flower bit (P4-3) on top of their ground role, and keep
	# TALL_COVER_M: the poppy and lavender were tall cover before the rework too; the daisy
	# (0.72 then, 0.77 now) crossed the line in the rework, not here.
	assert_eq(meadow.get("buttercup"), cover | flower)
	assert_eq(meadow.get("carpet"), cover | flower)
	assert_eq(meadow.get("daisy"), tall | flower)
	assert_eq(meadow.get("poppy"), tall | flower)
	assert_eq(meadow.get("lavender"), tall | flower)
	assert_eq(meadow.get("bush"), ScatterGround.ROLE_SHRUB)
	# Temperate forest: the tall grass (0.47 m) thins again, the clumps (0.33) and sprig stay,
	# as before the rework; the fern stays a bank species.
	var forest := _roles(FOREST)
	assert_eq(forest.get("tall_grass"), tall, "forest tall grass")
	assert_eq(forest.get("grass"), cover, "forest clumps")
	assert_eq(forest.get("sprig"), cover, "forest sprig")
	assert_eq(forest.get("fern"), cover | ScatterGround.EDGE_BANK, "fern")
	assert_eq(forest.get("daisy"), cover | flower, "forest daisy")
	# Wetland: the sedge (0.53 m) thins again, the grass (0.31) and sprig stay.
	var wetland := _roles("wetland_riparian_summer_s1")
	assert_eq(wetland.get("sedge"), tall | ScatterGround.EDGE_EMERGENT, "sedge")
	assert_eq(wetland.get("reeds"), tall | ScatterGround.EDGE_EMERGENT, "reeds")
	assert_eq(wetland.get("grass"), cover, "wetland grass")
	assert_eq(wetland.get("sprig"), cover, "wetland sprig")
	# Savanna and badlands: their tall grass as before, and now their short grass too.
	var savanna := _roles("savanna_summer_s1")
	for key in ["dry_grass", "seed_grass", "short_grass", "rust_grass"]:
		assert_eq(savanna.get(key), tall, "savanna %s" % key)
	assert_eq(savanna.get("flower"), cover | flower, "savanna flower")
	var badlands := _roles("rocky_badlands_summer_s1")
	assert_eq(badlands.get("dry_grass"), tall, "badlands dry grass")
	assert_eq(badlands.get("dry_tall"), tall, "badlands tall grass")
	# The low grass of the woodland, alpine and burnt biomes stays, as before.
	var low := {
		"birch_woodland_summer_s1": ["grass"],
		"boreal_taiga_summer_s1": ["grass"],
		"alpine_meadow_summer_s1": ["turf", "tundra_sprig"],
		"burnt_forest_summer_s1": ["burnt_stubble"],
	}
	for biome_id in low:
		var roles := _roles(biome_id)
		for key in low[biome_id]:
			assert_eq(roles.get(key), cover, "%s %s" % [biome_id, key])
	# The line itself: grass clumps against GRASS_TALL_COVER_M, the rest against TALL_COVER_M.
	var line := ScatterGround.GRASS_TALL_COVER_M
	var grass := {"kind": "grass", "size_class": "ground", "height_m": line}
	assert_eq(ScatterGround.role_of(grass), tall)
	grass.height_m = line - 0.01
	assert_eq(ScatterGround.role_of(grass), cover)
	assert_eq(
		ScatterGround.role_of({"kind": "flower", "size_class": "ground", "height_m": 0.7}), cover
	)
	assert_eq(
		ScatterGround.role_of({"kind": "grass", "size_class": "small", "height_m": 0.5}), cover
	)


## Each species key of `biome_id` to its plan ground_role.
func _roles(biome_id: String) -> Dictionary:
	var roles := {}
	for rule in PaletteLibrary.species(biome_id):
		roles[rule.key] = ScatterPlan.build("g", [rule], 1).species[0].ground_role
	return roles


func test_trees_keep_back_from_tier_faces_and_ground_cover_does_not() -> void:
	# P3-7: terraces must read under a forest, so trees (and shrubs, less) keep back from a
	# face and its lip; ground cover still grows up to the rock.
	var doc := _doc()
	var fields := ScatterGenerator.document_fields(doc, FOREST, Rect2(), PackedStringArray())
	var at: Callable = fields.species_density_at
	var base := DENSITY / 255.0
	var face_x := _face_x(doc)
	for side in [-1.0, 1.0]:
		var lip := Vector2(face_x + side * 1.0, 0.0)
		var clear := Vector2(face_x + side * 5.0, 0.0)
		assert_lt(at.call(lip, ScatterGround.ROLE_TREE), 0.01, "no tree a metre from the face")
		# (Below the face the scree thins it a little, as before P3-7.)
		assert_gt(at.call(lip, ScatterGround.ROLE_COVER), base * 0.9, "cover stays")
		assert_almost_eq(at.call(clear, ScatterGround.ROLE_TREE), base, 1e-6, "trees 5 m out")
		assert_almost_eq(at.call(clear, ScatterGround.ROLE_SHRUB), base, 1e-6, "shrubs 5 m out")
	var three := Vector2(face_x - 3.0, 0.0)
	var two := Vector2(face_x - 2.0, 0.0)
	assert_gt(at.call(three, ScatterGround.ROLE_TREE), at.call(two, ScatterGround.ROLE_TREE))
	assert_gt(
		at.call(two, ScatterGround.ROLE_SHRUB),
		at.call(two, ScatterGround.ROLE_TREE),
		"shrubs come closer than trees"
	)
	assert_eq(fields.density_at.call(two), at.call(two, ScatterGround.ROLE_COVER))
	assert_eq(
		ScatterGround.role_of({"kind": "tree", "size_class": "large"}), ScatterGround.ROLE_TREE
	)
	assert_eq(
		ScatterGround.role_of({"kind": "rock", "size_class": "medium"}), ScatterGround.ROLE_ROCK
	)
	assert_eq(
		ScatterGround.role_of({"kind": "bush", "size_class": "medium"}), ScatterGround.ROLE_SHRUB
	)
	assert_eq(
		ScatterGround.role_of({"kind": "grass", "size_class": "ground"}), ScatterGround.ROLE_COVER
	)
