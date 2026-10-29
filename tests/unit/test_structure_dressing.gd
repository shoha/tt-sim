extends GutTest

## The yard of a building (StructureDressing, probe B): a soft ground patch, a path and plants,
## derived from the record, its door and the ground, never stored. Summary:
## docs/systems/structures.md "Dressing".

const FIXTURES := preload("res://tests/unit/map_document_fixtures.gd")

var _doc: MapDocument = null


## The fixtures' river and pond (the pond covers x -12.7..-5.5, z 4.8..9.8), the pond's ground dug
## to -3 m so it holds water.
func _dig_pond() -> void:
	FIXTURES.add_water(_doc)
	var dug := _doc.heights.duplicate()
	for z in range(80, 100):
		for x in range(10, 40):
			dug[_doc.sample_index(x, z)] = -3.0
	_doc.heights = dug


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func after_each() -> void:
	StructureDressing.enabled = true


func _plan(centre: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array(
		[
			centre + Vector2(-3, -2),
			centre + Vector2(3, -2),
			centre + Vector2(3, 2),
			centre + Vector2(-3, 2)
		]
	)


func _structure(recipe: String, structure_id: int = 1, seed_value: int = 5) -> Structure:
	return Structure.make(structure_id, recipe, _plan(), seed_value)


func _vertices(mesh: Dictionary) -> PackedVector3Array:
	return (mesh.arrays as Array)[Mesh.ARRAY_VERTEX] as PackedVector3Array


func test_family_follows_the_recipe_name() -> void:
	assert_eq(StructureDressing.family_of("core:cottage_hip"), "cottage")
	assert_eq(StructureDressing.family_of("core:townhouse_end"), "townhouse")
	assert_eq(StructureDressing.family_of("core:stone_house"), "house")
	assert_eq(StructureDressing.family_of("core:house_flat"), "house")


func test_same_record_same_yard_new_seed_new_yard() -> void:
	var a := StructureDressing.build(_doc, _structure("core:cottage"), null)
	var b := StructureDressing.build(_doc, _structure("core:cottage"), null)
	assert_eq(_vertices(a.props), _vertices(b.props), "derived, not random")
	assert_eq(_vertices(a.ground), _vertices(b.ground))
	var c := StructureDressing.build(_doc, _structure("core:cottage", 1, 6), null)
	assert_ne(_vertices(a.props), _vertices(c.props), "a re-roll draws a new yard")


func test_every_family_has_ground_and_props_within_budget() -> void:
	for recipe in ["core:cottage", "core:stone_house", "core:townhouse"]:
		var yard := StructureDressing.build(_doc, _structure(recipe), null)
		assert_false((yard.ground as Dictionary).is_empty(), recipe)
		assert_false((yard.props as Dictionary).is_empty(), recipe)
		assert_lt(int(yard.triangles), 1200, "%s stays light" % recipe)


func test_the_yard_follows_the_ground_and_stays_off_the_building() -> void:
	var slope := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			slope[_doc.sample_index(x, z)] = 0.1 * _doc.sample_to_world(Vector2(x, z)).x
	_doc.heights = slope
	var yard := StructureDressing.build(_doc, _structure("core:stone_house"), null)
	for p in _vertices(yard.ground):
		var ground := WaterGeometry.ground_at(_doc, Vector2(p.x, p.z))
		assert_between(p.y - ground, 0.0, 0.2, "the patch lies on the ground")
	# A bush may lean 0.3 m into a wall (the wall hides it), never into the room.
	var inside := Geometry2D.offset_polygon(_plan(), -0.3)[0]
	for p in _vertices(yard.props):
		assert_false(
			Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), inside),
			"no plant stands in the building"
		)


func test_the_door_side_is_left_open() -> void:
	# The door is in the middle of edge 0 (z = -2 here): no cluster within the clear radius.
	for seed_value in 12:
		var yard := StructureDressing.build(
			_doc, _structure("core:stone_house", 1, seed_value), null
		)
		for p in _vertices(yard.props):
			if p.y > WaterGeometry.ground_at(_doc, Vector2(p.x, p.z)) + 0.1:
				var d := Vector2(p.x, p.z).distance_to(Vector2(0.0, -2.0))
				assert_gt(d, 0.5, "nothing grows in the doorway (seed %d)" % seed_value)


func test_off_builds_nothing_and_the_key_follows_the_ground_beside_the_walls() -> void:
	var structure := _structure("core:cottage")
	var before := StructureGeometry.key_of(_doc, structure)
	var raised := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			# A mound 1.6 m past the front wall (edge 0 is at z = -2), outside the footprint.
			if _doc.sample_to_world(Vector2(x, z)).distance_to(Vector2(0.0, -3.6)) < 0.7:
				raised[_doc.sample_index(x, z)] += 2.0
	_doc.heights = raised
	assert_ne(
		StructureGeometry.key_of(_doc, structure), before, "a sculpt beside the walls rebuilds"
	)
	StructureDressing.enabled = false
	var off := StructureDressing.build(_doc, structure, null)
	assert_eq(int(off.triangles), 0)
	assert_true((off.ground as Dictionary).is_empty())


func test_dressing_is_not_in_the_digest_or_the_building_budget() -> void:
	var parts := StructureGeometry.build_one(_doc, _structure("core:cottage"))
	assert_false((parts.dressing as Dictionary).is_empty())
	assert_eq(int(parts.triangles), StructureGeometry.triangle_count(parts))
	var digest := StructureGeometry.digest_of(parts)
	parts.dressing = {}
	assert_eq(StructureGeometry.digest_of(parts), digest, "pins stay put")


func test_a_yard_never_reaches_into_a_neighbours_footprint() -> void:
	var mine := _structure("core:cottage")
	_doc.structures.append(mine)
	# A terrace-like neighbour one metre from the east wall (x = 3): its footprint is x 4..10.
	var next_door := Structure.make(2, "core:townhouse", _plan(Vector2(7, 0)), 5)
	_doc.structures.append(next_door)
	var key := StructureGeometry.key_of(_doc, mine)
	for seed_value in 6:
		mine.seed_value = seed_value
		var yard := StructureDressing.build(_doc, mine, null)
		for mesh in [yard.ground, yard.props]:
			for p in _vertices(mesh):
				var inside := Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), next_door.footprint)
				assert_false(inside, "seed %d: a yard vertex stands in the next house" % seed_value)
	var moved := Structure.make(2, "core:townhouse", _plan(Vector2(7, 8)), 5)
	_doc.structures[1] = moved
	mine.seed_value = 5
	assert_ne(
		StructureGeometry.key_of(_doc, mine),
		key,
		"a neighbour moving away redraws the yard (it is part of the key)"
	)


func test_the_workers_snapshot_draws_the_same_yard_as_the_document() -> void:
	_dig_pond()
	var mine := Structure.make(1, "core:cottage", _plan(Vector2(-9, 1.5)), 5)
	_doc.structures.append(mine)
	_doc.structures.append(Structure.make(2, "core:townhouse", _plan(Vector2(-3, 1.5)), 5))
	var direct := StructureDressing.build(_doc, mine, null)
	var snapshot := StructureDressing.build(StructureGeometry.ground_snapshot(_doc), mine, null)
	assert_eq(_vertices(direct.ground), _vertices(snapshot.ground), "the worker sees the water")
	assert_eq(_vertices(direct.props), _vertices(snapshot.props), "and the neighbour")


func test_a_yard_stays_out_of_water() -> void:
	# The fixture's pond covers x -12.7..-5.5, z 4.8..9.8 (dug below its level here); a house whose
	# back wall is a metre and a quarter from it.
	_dig_pond()
	assert_true(WaterGeometry.is_wet_at(_doc, Vector2(-9, 7)), "the pond holds water")
	var plan := _plan(Vector2(-9, 1.5))
	for recipe in ["core:cottage", "core:stone_house", "core:townhouse"]:
		for seed_value in 4:
			var structure := Structure.make(1, recipe, plan, seed_value)
			var yard := StructureDressing.build(_doc, structure, null)
			assert_false((yard.ground as Dictionary).is_empty(), "%s has a yard" % recipe)
			for p in _vertices(yard.ground):
				assert_false(
					WaterGeometry.is_wet_at(_doc, Vector2(p.x, p.z)),
					"%s seed %d: the patch or path is in the pond at %s" % [recipe, seed_value, p]
				)
