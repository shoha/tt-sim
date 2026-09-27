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
	# The real meadow: tall grass is tall cover, flowers and short grass are not.
	var roles := {}
	for rule in PaletteLibrary.species("grassland_meadow_summer_s1"):
		roles[rule.key] = ScatterPlan.build("g", [rule], 1).species[0].ground_role
	assert_eq(roles.get("tall_grass"), ScatterGround.ROLE_TALL_COVER)
	assert_eq(roles.get("grass"), ScatterGround.ROLE_COVER)
	# Flowers carry the water rules' flower bit (P4-3) on top of their ground role.
	assert_eq(roles.get("daisy"), ScatterGround.ROLE_COVER | ScatterGround.FLOWER_BIT)
	assert_eq(roles.get("bush"), ScatterGround.ROLE_SHRUB)


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
