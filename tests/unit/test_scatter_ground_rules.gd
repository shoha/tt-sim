extends GutTest

## ScatterGenerator.document_fields and the ground's automatic dressing (TerrainRules):
## plants thin on automatic rock and under painted built surfaces, a hand-painted ground
## surface yields to the rock on a face (P3-6), and rock species gather on the scree at a
## cliff's foot.

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
