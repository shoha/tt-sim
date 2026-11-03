extends GutTest

## EyeRim: the eye view's hedgerows and copses past the map edge (card eyeedge).

const HALF := Vector2(38.1, 38.1)
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


func test_near_line() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	assert_true(EyeRim.near_line(Vector2(5, 2), line, 3.0))
	assert_false(EyeRim.near_line(Vector2(5, 4), line, 3.0))
	assert_true(EyeRim.near_line(Vector2(1, 1), PackedVector2Array([Vector2.ZERO]), 2.0))
