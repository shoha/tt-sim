extends GutTest

## EyeRim: the eye view's hedgerows and copses past the map edge (card eyeedge).

const HALF := Vector2(38.1, 38.1)
const BIOME := "grassland_meadow_summer_s1"

var _kinds := {
	"trees": PackedStringArray(["oak_a", "oak_b"]), "shrubs": PackedStringArray(["bush_a"])
}


func _flat(_p: Vector2) -> float:
	return 0.0


func _never(_p: Vector2) -> bool:
	return false


func _rows(seed_value: int, kinds: Dictionary = {}, edge_y: Callable = Callable()) -> Dictionary:
	var heights := edge_y if edge_y.is_valid() else _flat
	return EyeRim.plan(HALF, seed_value, _kinds if kinds.is_empty() else kinds, heights, _never)


func _points(rows: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id: String in rows:
		var list: PackedFloat32Array = rows[id]
		for r in list.size() / MapDocument.ROW_STRIDE:
			var b := r * MapDocument.ROW_STRIDE
			out.append(Vector3(list[b], list[b + 1], list[b + 2]))
	return out


func test_species_by_kind_and_size() -> void:
	var biome := {
		"species":
		[
			{"kind": "tree", "size_class": "large", "assets": ["oak"]},
			{"kind": "tree", "size_class": "medium", "assets": ["bush", "rose"]},
			{"kind": "rock", "size_class": "medium", "assets": ["boulder"]},
			{"kind": "grass", "size_class": "ground", "assets": ["grass"]},
		]
	}
	var kinds := EyeRim.species(biome)
	assert_eq(kinds.trees, PackedStringArray(["oak"]))
	assert_eq(kinds.shrubs, PackedStringArray(["bush", "rose"]))


func test_the_core_grassland_has_rim_species() -> void:
	var kinds := EyeRim.species(PaletteLibrary.biome("grassland_meadow_summer_s1"))
	assert_false((kinds.trees as PackedStringArray).is_empty(), "the meadow's oaks")
	assert_false((kinds.shrubs as PackedStringArray).is_empty(), "its bushes")


func test_every_plant_stands_past_the_edge_and_near_it() -> void:
	var points := _points(_rows(1234))
	assert_gt(points.size(), 40, "a 250 ft map's rim holds several hedges and copses")
	for p in points:
		var outside := RiverExits.outside_distance(Vector2(p.x, p.z), HALF)
		assert_gt(outside, 0.5, "past the edge: %s" % p)
		assert_lt(outside, 16.0, "within the opaque skirt: %s" % p)


func test_the_rim_has_gaps_hedges_and_copses_on_every_side() -> void:
	var points := _points(_rows(7))
	var sides := [0, 0, 0, 0]
	for p in points:
		if p.z > HALF.y:
			sides[0] += 1
		elif p.x > HALF.x:
			sides[1] += 1
		elif p.z < -HALF.y:
			sides[2] += 1
		else:
			sides[3] += 1
	for count in sides:
		assert_gt(count, 3, "each side gets something: %s" % [sides])


func test_deterministic_and_seeded() -> void:
	assert_eq(_rows(42), _rows(42), "the same seed plants the same rim")
	assert_ne(_rows(42), _rows(43), "another seed another rim")


func test_no_species_plants_nothing() -> void:
	var none := {"trees": PackedStringArray(), "shrubs": PackedStringArray()}
	assert_eq(_rows(1, none), {})


func test_shrubs_only_still_plants() -> void:
	var shrubs := {"trees": PackedStringArray(), "shrubs": PackedStringArray(["bush_a"])}
	var rows := _rows(5, shrubs)
	assert_eq(rows.keys(), ["bush_a"])


func test_plants_stand_on_the_skirt_falling_from_a_raised_edge() -> void:
	var raised := func(_p: Vector2) -> float: return 3.0
	for p in _points(_rows(9, _kinds, raised)):
		var outside := RiverExits.outside_distance(Vector2(p.x, p.z), HALF)
		var want := TerrainMeshBuilder.skirt_height(3.0, outside, AuthoredTerrain.SKIRT_FADE_M)
		assert_almost_eq(p.y, want - 0.05, 0.6, "on the skirt's fall at %s" % p)


func test_a_blocked_edge_stays_open() -> void:
	var all_blocked := func(_p: Vector2) -> bool: return true
	assert_eq(EyeRim.plan(HALF, 3, _kinds, _flat, all_blocked), {})


# --- plan_for and show: the rim of a real map document ---------------------------------------

## A flat 20 x 20 cell map (30.48 m) in `BIOME`, with a waist river from the middle to the +z edge
## (planned and carved as the Water tool does) when `with_river`.
func _doc(seed_value: int, with_river: bool = false) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", seed_value)
	doc.biome_ids = PackedStringArray([BIOME])
	if not with_river:
		return doc
	var start := doc.heights.duplicate()
	var half := doc.extent_m() * 0.5
	var from := Vector2(0.0, -4.0)
	var to := Vector2(0.0, half.y - 0.2)
	var bodies := WaterEdit.plan_river(
		doc,
		PackedVector2Array([from, (from + to) * 0.5, to]),
		PackedFloat32Array([1.5]),
		WaterBody.Depth.WAIST
	)
	var goals := WaterCarve.river_goals(doc, bodies, start)
	var rect: Rect2i = goals.rect
	var carved := doc.heights.duplicate()
	for j in rect.size.y:
		for i in rect.size.x:
			var goal: float = goals.goals[j * rect.size.x + i]
			var at := (rect.position.y + j) * doc.samples_x() + rect.position.x + i
			if not is_inf(goal):
				carved[at] = minf(carved[at], goal)
	doc.heights = carved
	doc.water_bodies = WaterEdit.with_bodies(doc, bodies)
	return doc


## The distance from the nearest planted point to the river's course past the edge.
func _closest_to_course(rows: Dictionary, doc: MapDocument) -> float:
	var course: PackedVector2Array = RiverExits.exits(doc)[0].course
	var best := INF
	for p in _points(rows):
		for i in range(course.size() - 1):
			var q := Geometry2D.get_closest_point_to_segment(
				Vector2(p.x, p.z), course[i], course[i + 1]
			)
			best = minf(best, Vector2(p.x, p.z).distance_to(q))
	return best


func test_plan_for_plants_the_dominant_biomes_species_past_the_edge() -> void:
	var doc := _doc(1234)
	var rows := EyeRim.plan_for(doc, PaletteLibrary.DEFAULT_ROOT)
	assert_false(rows.is_empty(), "the meadow's trees and bushes make a rim")
	var kinds := EyeRim.species(PaletteLibrary.biome(BIOME))
	var known := PackedStringArray(kinds.trees)
	known.append_array(kinds.shrubs)
	for id: String in rows:
		assert_true(id in known, "%s is one of the biome's rim species" % id)
	var half := doc.extent_m() * 0.5
	for p in _points(rows):
		assert_gt(RiverExits.outside_distance(Vector2(p.x, p.z), half), 0.5, "past the edge: %s" % p)
	assert_eq(rows, EyeRim.plan_for(_doc(1234), PaletteLibrary.DEFAULT_ROOT), "deterministic")


func test_plan_for_a_map_without_a_biome_plants_nothing() -> void:
	var doc := _doc(5)
	doc.biome_ids = PackedStringArray()
	assert_eq(EyeRim.plan_for(doc, PaletteLibrary.DEFAULT_ROOT), {})


func test_plan_for_samples_the_edge_height_of_the_document() -> void:
	var doc := _doc(9)
	doc.heights.fill(3.0)
	var half := doc.extent_m() * 0.5
	var points := _points(EyeRim.plan_for(doc, PaletteLibrary.DEFAULT_ROOT))
	assert_gt(points.size(), 10, "a rim to measure")
	for p in points:
		var outside := RiverExits.outside_distance(Vector2(p.x, p.z), half)
		var want := TerrainMeshBuilder.skirt_height(3.0, outside, AuthoredTerrain.SKIRT_FADE_M)
		assert_almost_eq(p.y, want - 0.05, 0.6, "on the raised skirt at %s" % p)


func test_plan_for_keeps_a_rivers_mouth_open() -> void:
	var half := _doc(1).extent_m() * 0.5
	var biome_species := EyeRim.species(PaletteLibrary.biome(BIOME))
	assert_false((biome_species.trees as PackedStringArray).is_empty(), "the rim has species")
	var with_river_doc := _doc(1, true)
	var reach: float = (
		float(RiverExits.exits(with_river_doc)[0].half_width) + EyeRim.RIVER_CLEAR_M
	)
	var plain_inside := 0
	for seed_value in range(1, 13):
		var river_doc := _doc(seed_value, true)
		assert_eq(RiverExits.exits(river_doc).size(), 1, "the river leaves the map")
		var river_rows := EyeRim.plan_for(river_doc, PaletteLibrary.DEFAULT_ROOT)
		assert_gte(
			_closest_to_course(river_rows, river_doc),
			reach,
			"seed %d: nothing within %.1f m of the river's course" % [seed_value, reach]
		)
		# The same map and seed without the river does plant there, so the test can fail.
		var plain_rows := EyeRim.plan_for(_doc(seed_value), PaletteLibrary.DEFAULT_ROOT)
		for p in _points(plain_rows):
			if absf(p.x) < reach and p.z > half.y:
				plain_inside += 1
	assert_gt(plain_inside, 0, "without the river some seed plants in the river's mouth")


func test_show_makes_the_node_once_and_only_hides_it_after() -> void:
	var level_map := Node3D.new()
	add_child_autofree(level_map)
	var doc := _doc(1234)
	EyeRim.show(level_map, doc, true)
	var rim := level_map.get_node_or_null(EyeRim.NODE_NAME) as AuthoredScatter
	assert_not_null(rim, "an AuthoredScatter named EyeRim under the map root")
	assert_true(rim.visible)
	assert_false(rim.warm_pipelines, "the rim does not warm pipelines for its own nodes")
	assert_eq(rim.palette_root, PaletteLibrary.DEFAULT_ROOT, "no main scatter: the default root")
	EyeRim.show(level_map, doc, false)
	assert_false(rim.visible, "hidden when the eye is left")
	assert_eq(level_map.get_node_or_null(EyeRim.NODE_NAME), rim, "kept, not freed")
	EyeRim.show(level_map, doc, true)
	assert_eq(level_map.get_node_or_null(EyeRim.NODE_NAME), rim, "the same node on the next entry")
	assert_true(rim.visible)
	var rims := level_map.get_children().filter(
		func(c: Node) -> bool: return c.name == EyeRim.NODE_NAME
	)
	assert_eq(rims.size(), 1, "one rim per map")


func test_show_takes_the_main_scatters_foliage_overrides() -> void:
	var level_map := Node3D.new()
	add_child_autofree(level_map)
	var main := AuthoredScatter.create(PaletteLibrary.DEFAULT_ROOT, {"tree_sway_speed": 2.0})
	level_map.add_child(main)
	EyeRim.show(level_map, _doc(3), true)
	var rim := level_map.get_node(EyeRim.NODE_NAME) as AuthoredScatter
	assert_eq(rim.palette_root, main.palette_root, "the rim reads the map's own palette")
	assert_eq(rim.foliage_overrides, {"tree_sway_speed": 2.0}, "and bakes its wind tuning")


func test_show_off_builds_nothing() -> void:
	var level_map := Node3D.new()
	add_child_autofree(level_map)
	EyeRim.show(level_map, _doc(3), false)
	assert_null(level_map.get_node_or_null(EyeRim.NODE_NAME), "hiding a rim never made makes none")
	EyeRim.show(level_map, null, true)
	assert_null(level_map.get_node_or_null(EyeRim.NODE_NAME), "no document: nothing to build")
	EyeRim.show(null, _doc(3), true)
	assert_eq(level_map.get_child_count(), 0, "a missing map root is ignored")


func test_show_without_a_document_hides_a_rim_that_exists() -> void:
	var level_map := Node3D.new()
	add_child_autofree(level_map)
	EyeRim.show(level_map, _doc(3), true)
	var rim := level_map.get_node(EyeRim.NODE_NAME) as AuthoredScatter
	EyeRim.show(level_map, null, true)
	assert_false(rim.visible, "no document hides it rather than showing a stale rim")


func test_show_hands_new_species_materials_to_the_game_map() -> void:
	var level_map := Node3D.new()
	add_child_autofree(level_map)
	var game_map: GameMap = autofree(GameMap.new())
	var spy: AdoptSpy = autofree(AdoptSpy.new())
	game_map._visual_effects = spy
	EyeRim.show(level_map, _doc(3), true, game_map)
	assert_gt(spy.batches, 0, "the rim's species materials reached GameMap.adopt_foliage_materials")
	assert_gt(spy.materials, 0)


func test_near_line() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	assert_true(EyeRim.near_line(Vector2(5, 2), line, 3.0))
	assert_false(EyeRim.near_line(Vector2(5, 4), line, 3.0))
	assert_true(EyeRim.near_line(Vector2(1, 1), PackedVector2Array([Vector2.ZERO]), 2.0))


## A VisualEffectsController that only counts the materials it is handed.
class AdoptSpy:
	extends VisualEffectsController
	var batches := 0
	var materials := 0

	func adopt_foliage_materials(list: Array[ShaderMaterial]) -> void:
		batches += 1
		materials += list.size()
