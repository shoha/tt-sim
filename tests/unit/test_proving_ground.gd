extends GutTest

## ProvingGround (step S8a): the designer's test map is built from the authoring document API
## and carries every feature a rule's fields answer to: a dome whose slope grows from 0 to 60
## degrees, a ridge, a path band, a river with banks and a meadow in three density zones. It is
## deterministic, and the real scatter solver places plants on it.

const BIOME := "temperate_forest_summer_s1"

var _doc: MapDocument = null


func before_all() -> void:
	_doc = ProvingGround.build(BIOME)


func _height_at(p: Vector2) -> float:
	var s := _doc.world_to_sample(p).round()
	return _doc.heights[_doc.sample_index(int(s.x), int(s.y))]


func _slope_deg(p: Vector2) -> float:
	var step := 0.5
	var dx := (_height_at(p + Vector2(step, 0)) - _height_at(p - Vector2(step, 0))) / (2.0 * step)
	var dz := (_height_at(p + Vector2(0, step)) - _height_at(p - Vector2(0, step))) / (2.0 * step)
	return rad_to_deg(atan(sqrt(dx * dx + dz * dz)))


func test_the_document_is_a_150_ft_map_of_the_biome() -> void:
	assert_not_null(_doc)
	assert_eq(_doc.size_cells, Vector2i(30, 30))
	assert_almost_eq(_doc.extent_m().x, 45.72, 0.01)
	assert_eq(_doc.biome_ids, PackedStringArray([BIOME]))
	assert_eq(_doc.map_seed, ProvingGround.SEED)
	assert_eq(_doc.biome_slots.size(), _doc.sample_count())
	assert_eq(_doc.base_surface, String(PaletteLibrary.biome(BIOME)["ground_surface"]))


func test_it_is_deterministic() -> void:
	var again := ProvingGround.build(BIOME)
	assert_eq(hash(again.heights), hash(_doc.heights))
	assert_eq(hash(again.biome_density), hash(_doc.biome_density))
	assert_eq(hash(again.surface_weights), hash(_doc.surface_weights))
	var other := ProvingGround.build(BIOME, {"seed": 7})
	assert_eq(hash(other.heights), hash(_doc.heights), "the terrain does not depend on the seed")
	assert_eq(other.map_seed, 7)


func test_the_dome_slope_grows_from_flat_summit_to_sixty_degrees() -> void:
	var regions := ProvingGround.layout(_doc)
	var centre: Vector2 = regions["dome"]["centre"]
	var radius: float = regions["dome"]["radius"]
	assert_true(_slope_deg(centre) < 3.0, "flat at the summit")
	for share in [0.25, 0.5, 0.75]:
		var expected := ProvingGround.dome_slope_deg(radius * share, radius)
		var measured := _slope_deg(centre + Vector2(radius * share, 0.0))
		assert_almost_eq(measured, expected, 3.0, "slope at %d%% of the radius" % [share * 100])
	assert_true(_slope_deg(centre + Vector2(radius * 0.96, 0.0)) > 50.0, "steep at the foot")
	assert_true(_height_at(centre) > 4.0 and _height_at(centre) < 8.0, "about 6 m high")
	assert_almost_eq(_height_at(centre + Vector2(radius * 1.05, 0.0)), 0.0, 0.2)


func test_the_ridge_stands_in_the_north_east() -> void:
	var regions := ProvingGround.layout(_doc)
	var line: PackedVector2Array = regions["ridge"]["line"]
	var middle := (line[0] + line[1]) * 0.5
	assert_almost_eq(_height_at(middle), ProvingGround.RIDGE_HEIGHT_M, 0.3)
	var flank := middle + Vector2(float(regions["ridge"]["half_width"]) * 0.5, 0.0)
	var slope := _slope_deg(flank)
	assert_true(slope > 25.0 and slope < 55.0, "a flank of %.0f degrees" % slope)
	assert_almost_eq(
		_height_at(middle + Vector2(float(regions["ridge"]["half_width"]) * 1.2, 0.0)), 0.0, 0.2
	)


func test_the_water_channel_has_banks_and_a_wet_dressing() -> void:
	assert_false(_doc.water_bodies.is_empty(), "a river was carved")
	assert_eq(_doc.water_bodies[0].kind, WaterBody.Kind.RIVER)
	assert_false(_doc.water_dressing.is_empty(), "the wet dressing was computed")
	var regions := ProvingGround.layout(_doc)
	var bed := _height_at(regions["points"]["river"])
	assert_true(bed < -0.3, "the channel is below the plain: %.2f" % bed)
	assert_true(_doc.heights.size() == _doc.sample_count())


func test_the_path_is_painted_as_a_built_surface() -> void:
	assert_false(_doc.surface_ids.is_empty())
	var surface := _doc.surface_ids[0]
	assert_true(surface in PaletteLibrary.surfaces_with_role("built"), surface)
	var slot := 0
	var regions := ProvingGround.layout(_doc)
	var on_path: Vector2 = regions["points"]["path"]
	var s := _doc.world_to_sample(on_path).round()
	assert_true(_doc.surface_weight(_doc.sample_index(int(s.x), int(s.y)), slot) > 200)
	var off := _doc.world_to_sample(on_path + Vector2(0.0, 6.0)).round()
	assert_eq(_doc.surface_weight(_doc.sample_index(int(off.x), int(off.y)), slot), 0)


func test_the_meadow_has_three_density_zones() -> void:
	var regions := ProvingGround.layout(_doc)
	var zones: Array = regions["zones"]
	assert_eq(zones.size(), 3)
	var seen: Array[int] = []
	for zone: Dictionary in zones:
		var rect: Rect2 = zone["rect"]
		var s := _doc.world_to_sample(rect.get_center()).round()
		seen.append(_doc.biome_density[_doc.sample_index(int(s.x), int(s.y))])
	assert_eq(seen, [255, 128, 51])
	var far := _doc.world_to_sample(regions["points"]["dome"]).round()
	assert_eq(_doc.biome_density[_doc.sample_index(int(far.x), int(far.y))], 255, "full elsewhere")


func test_every_region_is_on_the_map() -> void:
	var regions := ProvingGround.layout(_doc)
	var half := _doc.extent_m() * 0.5
	for name: String in regions["points"]:
		var p: Vector2 = regions["points"][name]
		assert_true(absf(p.x) <= half.x and absf(p.y) <= half.y, "%s on the map" % name)


func test_the_real_scatter_places_plants_on_it() -> void:
	var rows := ScatterGenerator.generate_for_document(
		_doc, BIOME, ScatterGenerator.cells_in_bounds(Rect2(-12, -12, 24, 24))
	)
	var total := 0
	for asset_id: String in rows:
		total += (rows[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
	assert_true(total > 100, "%d plants" % total)


func test_the_spec_builds_it_through_new_map() -> void:
	var made := NewMap.from_spec({"proving_ground": BIOME, "seed": 99})
	assert_eq(made.map_seed, 99)
	assert_eq(hash(made.heights), hash(_doc.heights))
	assert_eq(NewMap.opening_status({"proving_ground": BIOME}), "Setting up the proving ground...")
