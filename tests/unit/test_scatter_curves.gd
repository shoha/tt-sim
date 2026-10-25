extends GutTest

## The terrain response of a rule (step S12a): `slope_min_deg` and the `response` curves on the
## slope, height and wet axes, in the GDScript generator. Analytic ramps give exact expectations;
## the identity and region-independence tests run on real palette biomes. The library chain
## (reader, compiler, validator) is test_library_response.gd.

const ALPINE := "alpine_meadow_summer_s1"
const BOREAL := "boreal_taiga_summer_s1"
const EPSILON := 1e-3
const IDENTITY := {
	"slope": [[0.0, 1.0], [90.0, 1.0]],
	"height": [[-500.0, 1.0], [5000.0, 1.0]],
	"wet": [[0.0, 1.0], [1.0, 1.0]],
}


func before_all() -> void:
	PaletteLibrary.clear_cache()


func after_all() -> void:
	PaletteLibrary.clear_cache()


func _one(_p: Vector2) -> float:
	return 1.0


func _flat(_p: Vector2) -> float:
	return 0.0


func _up(_p: Vector2) -> Vector3:
	return Vector3.UP


## Surface angle x + 45 degrees: 0 at x = -45, 90 at x = 45.
func _ramp(p: Vector2) -> Vector3:
	var angle := deg_to_rad(clampf(p.x + 45.0, 0.0, 89.0))
	return Vector3(sin(angle), cos(angle), 0.0)


## Rolling ground: angles between 5 and 55 degrees, heights within +-2 m, a wet band.
func _hills(p: Vector2) -> Vector3:
	var angle := deg_to_rad(30.0 + 25.0 * sin(p.x * 0.3) * cos(p.y * 0.2))
	return Vector3(sin(angle), cos(angle), 0.0)


func _hill_height(p: Vector2) -> float:
	return 2.0 * sin(p.x * 0.2) + cos(p.y * 0.15)


func _hill_wet(p: Vector2) -> float:
	return absf(sin(p.y * 0.1))


func _species(key: String, fields: Dictionary) -> Dictionary:
	var rule := {
		"key": key,
		"kind": "grass",
		"size_class": "small",
		"density_per_m2": 2.0,
		"assets": ["test/" + key]
	}
	rule.merge(fields, true)
	return rule


func _square(half: float) -> Rect2:
	return Rect2(-half, -half, 2.0 * half, 2.0 * half)


func _run(
	species: Array[Dictionary],
	bounds: Rect2,
	normal_at: Callable = _up,
	height_at: Callable = _flat,
	wet_at: Callable = Callable(),
	cells: Array[Vector2i] = []
) -> Dictionary[String, PackedFloat32Array]:
	var use := cells if not cells.is_empty() else ScatterGenerator.cells_in_bounds(bounds)
	var cells_by_species: Array = []
	cells_by_species.resize(species.size())
	cells_by_species.fill(use)
	return ScatterGenerator.generate_species_cells(
		"test",
		species,
		_one,
		height_at,
		normal_at,
		1,
		cells_by_species,
		bounds,
		Callable(),
		PackedFloat32Array(),
		{},
		Callable(),
		null,
		wet_at
	)


func _points(rows: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for asset_id: String in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			points.append(Vector2(flat[start], flat[start + 2]))
	return points


## How many of `points` fall in each [edges[i], edges[i + 1]) of `value(point)`.
func _bins(points: PackedVector2Array, edges: Array, value: Callable) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(edges.size() - 1)
	counts.fill(0)
	for point in points:
		var v: float = value.call(point)
		for i in counts.size():
			if v >= edges[i] and v < edges[i + 1]:
				counts[i] += 1
				break
	return counts


func _angle(p: Vector2) -> float:
	return p.x + 45.0


func _subset(small: PackedVector2Array, big: PackedVector2Array) -> bool:
	var seen := {}
	for point in big:
		seen[point] = true
	for point in small:
		if not seen.has(point):
			return false
	return true


func test_curve_value_interpolates_holds_its_ends_and_clamps() -> void:
	var curve := ScatterPlan.flatten_curve([[10.0, 1.0], [20.0, 0.5], [40.0, 0.0]])
	assert_eq(curve.size(), 6)
	assert_eq(ScatterPlan.curve_value(curve, -5.0), 1.0, "flat before the first point")
	assert_eq(ScatterPlan.curve_value(curve, 10.0), 1.0)
	assert_almost_eq(ScatterPlan.curve_value(curve, 15.0), 0.75, 1e-12)
	assert_eq(ScatterPlan.curve_value(curve, 20.0), 0.5)
	assert_almost_eq(ScatterPlan.curve_value(curve, 30.0), 0.25, 1e-12)
	assert_eq(ScatterPlan.curve_value(curve, 40.0), 0.0)
	assert_eq(ScatterPlan.curve_value(curve, 99.0), 0.0, "flat after the last point")
	assert_eq(ScatterPlan.curve_value(PackedFloat64Array(), 5.0), 1.0, "no curve is 1")
	assert_eq(ScatterPlan.flatten_curve(null).size(), 0)
	assert_eq(ScatterPlan.flatten_curve([[1.0, 1.0]]).size(), 0, "one point is no curve")
	var raised := ScatterPlan.flatten_curve([[0.0, 2.0], [1.0, -1.0]])
	assert_eq(ScatterPlan.curve_value(raised, 0.0), 1.0, "y clamped to 0..1")
	assert_eq(ScatterPlan.curve_value(raised, 1.0), 0.0)


func test_legacy_rules_plan_neutral_terrain_values() -> void:
	for rule in PaletteLibrary.species(ALPINE):
		var entry: Dictionary = ScatterPlan.build(ALPINE, [rule], 1).species[0]
		assert_false(entry.has_response, rule.key)
		assert_eq(entry.slope_min_cos, -2.0, rule.key)
		for curve: String in ["curve_slope", "curve_height", "curve_wet", "curve_water_dist"]:
			assert_eq((entry[curve] as PackedFloat64Array).size(), 0, "%s %s" % [rule.key, curve])
	var curved := _species("a", {"slope_min_deg": 20.0, "response": {"slope": [[0, 1], [60, 0]]}})
	var entry: Dictionary = ScatterPlan.build("test", [curved], 1).species[0]
	assert_true(entry.has_response)
	assert_almost_eq(entry.slope_min_cos, cos(deg_to_rad(20.0)), 1e-12)
	assert_eq(entry.curve_slope, PackedFloat64Array([0.0, 1.0, 60.0, 0.0]))


func test_an_identity_curve_gives_the_bytes_of_no_curve_on_real_biomes() -> void:
	var bounds := _square(20.0)
	for biome_id in [ALPINE, BOREAL]:
		var plain: Array[Dictionary] = PaletteLibrary.species(biome_id)
		var curved: Array[Dictionary] = []
		for rule in plain:
			var copy := rule.duplicate(true)
			copy["response"] = IDENTITY.duplicate(true)
			curved.append(copy)
		var before := _run(plain, bounds, _hills, _hill_height, _hill_wet)
		var after := _run(curved, bounds, _hills, _hill_height, _hill_wet)
		assert_gt(_points(before).size(), 200, biome_id)
		assert_eq(after, before, "%s: identity curves leave every row alone" % biome_id)


func test_a_slope_curve_thins_in_proportion_and_never_adds() -> void:
	var bounds := Rect2(-45.0, -10.0, 90.0, 20.0)
	var base_rule := _species("shrub", {"density_per_m2": 2.0})
	var curved_rule := _species("shrub", {"response": {"slope": [[0, 1], [60, 0]]}})
	curved_rule["density_per_m2"] = 2.0
	var base := _points(_run([base_rule], bounds, _ramp))
	var curved := _points(_run([curved_rule], bounds, _ramp))
	var edges := [0.0, 10.0, 20.0, 30.0, 40.0, 50.0, 60.0]
	var base_bins := _bins(base, edges, _angle)
	var curved_bins := _bins(curved, edges, _angle)
	var previous := 2.0
	for i in 6:
		var share := float(curved_bins[i]) / base_bins[i]
		var expected: float = 1.0 - (float(edges[i]) + 5.0) / 60.0
		assert_almost_eq(share, expected, 0.1, "band %d keeps about %.2f" % [i, expected])
		assert_lt(share, previous, "density falls with slope: band %d" % i)
		previous = share
	var steep := 0
	for point in curved:
		if _angle(point) >= 60.0 + EPSILON:
			steep += 1
	assert_eq(steep, 0, "nothing where the curve is zero")
	assert_true(_subset(curved, base), "a curve only removes what was there")


func test_slope_min_leaves_nothing_below_the_fade_band_and_fades_in_over_five_degrees() -> void:
	var bounds := Rect2(-45.0, -10.0, 90.0, 20.0)
	var base := _points(_run([_species("shrub", {"density_per_m2": 4.0})], bounds, _ramp))
	var banded := _points(
		_run([_species("shrub", {"density_per_m2": 4.0, "slope_min_deg": 20.0})], bounds, _ramp)
	)
	var edges := [0.0, 15.0, 17.5, 20.0, 90.0]
	var base_bins := _bins(base, edges, _angle)
	var banded_bins := _bins(banded, edges, _angle)
	assert_eq(banded_bins[0], 0, "no instance below 15 degrees")
	assert_almost_eq(float(banded_bins[1]) / base_bins[1], 0.25, 0.15, "a quarter at 15..17.5")
	assert_almost_eq(float(banded_bins[2]) / base_bins[2], 0.75, 0.15, "three quarters at 17.5..20")
	assert_eq(banded_bins[3], base_bins[3], "full density from the minimum up")
	assert_true(_subset(banded, base))


func test_slope_min_and_max_make_a_band_and_the_max_keeps_its_allowance() -> void:
	var bounds := Rect2(-45.0, -10.0, 90.0, 20.0)
	var rule := _species(
		"shrub", {"density_per_m2": 3.0, "slope_min_deg": 20.0, "slope_max_deg": 30.0}
	)
	var points := _points(_run([rule], bounds, _ramp))
	var edges := [0.0, 15.0, 20.0, 40.0, 50.0, 90.0]
	var bins := _bins(points, edges, _angle)
	assert_eq(bins[0], 0, "under the minimum's fade")
	assert_gt(bins[1], 0, "the fade band holds some")
	assert_almost_eq(float(bins[2]), 1200.0, 120.0, "the band itself is full (30 + 10 allowance)")
	assert_gt(bins[3], 0, "the maximum fades over the next ten degrees")
	assert_eq(bins[4], 0, "nothing past the maximum, its allowance and its fade")


func test_the_height_curve_follows_the_ground_height() -> void:
	var bounds := Rect2(-20.0, -10.0, 40.0, 20.0)
	var height := func(p: Vector2) -> float: return p.x
	var base_rule := _species("shrub", {"density_per_m2": 3.0})
	var rule := _species("shrub", {"density_per_m2": 3.0})
	rule["response"] = {"height": [[0, 1], [10, 0]]}
	var base := _points(_run([base_rule], bounds, _up, height))
	var curved := _points(_run([rule], bounds, _up, height))
	var edges := [-20.0, 0.0, 5.0, 10.0, 20.0]
	var base_bins := _bins(base, edges, func(p: Vector2) -> float: return p.x)
	var curved_bins := _bins(curved, edges, func(p: Vector2) -> float: return p.x)
	assert_eq(curved_bins[0], base_bins[0], "full at and below the first point")
	assert_almost_eq(float(curved_bins[1]) / base_bins[1], 0.75, 0.1)
	assert_almost_eq(float(curved_bins[2]) / base_bins[2], 0.25, 0.1)
	assert_eq(curved_bins[3], 0, "none from the last point up")


func test_axes_multiply() -> void:
	var bounds := Rect2(-20.0, -10.0, 40.0, 20.0)
	var base := _points(_run([_species("shrub", {"density_per_m2": 4.0})], bounds))
	var rule := _species("shrub", {"density_per_m2": 4.0})
	rule["response"] = {"slope": [[0, 0.5], [90, 0.5]], "height": [[-500, 0.5], [5000, 0.5]]}
	var halves := _points(_run([rule], bounds))
	assert_almost_eq(float(halves.size()) / base.size(), 0.25, 0.04)
	assert_true(_subset(halves, base))


func test_the_wet_curve_reads_the_shore_weight_and_is_zero_without_one() -> void:
	var bounds := Rect2(-20.0, -10.0, 40.0, 20.0)
	var wet := func(p: Vector2) -> float: return clampf((p.x + 20.0) / 40.0, 0.0, 1.0)
	var base_rule := _species("rush", {"density_per_m2": 4.0})
	var rule := _species("rush", {"density_per_m2": 4.0})
	rule["response"] = {"wet": [[0, 0], [1, 1]]}
	var base := _points(_run([base_rule], bounds))
	var curved := _points(_run([rule], bounds, _up, _flat, wet))
	var edges := [-20.0, -10.0, 0.0, 10.0, 20.0]
	var value := func(p: Vector2) -> float: return p.x
	var base_bins := _bins(base, edges, value)
	var curved_bins := _bins(curved, edges, value)
	for i in 4:
		var expected := 0.125 + 0.25 * i
		assert_almost_eq(float(curved_bins[i]) / base_bins[i], expected, 0.07, "band %d" % i)
	assert_eq(_points(_run([rule], bounds)).size(), 0, "no wet field reads 0 everywhere")


func test_water_dist_is_planned_but_acts_as_one() -> void:
	var bounds := _square(15.0)
	var rule := _species("sedge", {"density_per_m2": 3.0})
	var base := _run([rule], bounds, _hills, _hill_height)
	var curved := rule.duplicate(true)
	curved["response"] = {"water_dist": [[0, 1], [20, 0]]}
	ScatterPlan._warned_unsupported.clear()
	var entry: Dictionary = ScatterPlan.build("test", [curved], 1).species[0]
	ScatterPlan.build("test", [curved], 1)
	assert_engine_error(1, "one warning per rule, not one per plan")
	assert_eq(entry.curve_water_dist.size(), 4, "the curve is planned")
	assert_false(entry.has_response, "and not evaluated")
	assert_false(ScatterPlan.has_terrain_response(curved))
	assert_eq(_run([curved], bounds, _hills, _hill_height), base)


func test_a_cell_with_curves_is_identical_alone_with_neighbours_and_in_the_whole_map() -> void:
	var curved: Array[Dictionary] = []
	for rule in PaletteLibrary.species(ALPINE):
		var copy := rule.duplicate(true)
		copy["slope_min_deg"] = 8.0
		copy["response"] = {
			"slope": [[0, 1], [40, 0.4], [70, 0]],
			"height": [[-5, 1], [5, 0.4]],
			"wet": [[0, 0.6], [1, 1]],
		}
		curved.append(copy)
	var bounds := _square(15.0)
	var cell := Vector2i(0, 0)
	var alone: Array[Vector2i] = [cell]
	var neighbours: Array[Vector2i] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			neighbours.append(cell + Vector2i(dx, dz))
	var runs := []
	for cells: Array[Vector2i] in [alone, neighbours, ScatterGenerator.cells_in_bounds(bounds)]:
		runs.append(_in_cell(_run(curved, bounds, _hills, _hill_height, _hill_wet, cells), cell))
	assert_gt(runs[0].size(), 3, "the cell holds several species")
	assert_eq(runs[1], runs[0], "with its neighbours")
	assert_eq(runs[2], runs[0], "inside the whole map")


func _in_cell(rows: Dictionary, cell: Vector2i) -> Dictionary:
	var chunk := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var kept := {}
	for asset_id: String in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		var out := PackedFloat32Array()
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			var at := Vector3(flat[start], 0.0, flat[start + 2])
			if ScatterChunker.cell_for(at, chunk) == cell:
				out.append_array(flat.slice(start, start + ScatterGenerator.ROW_STRIDE))
		if not out.is_empty():
			kept[asset_id] = out
	return kept


func _ramp_document() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(16, 16), "", "", 7)
	doc.biome_ids = PackedStringArray(["herbs"])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	var heights := PackedFloat32Array()
	for z in doc.samples_z():
		for x in doc.samples_x():
			slots.append(1)
			density.append(255)
			heights.append(0.5 * doc.sample_to_world(Vector2(x, z)).x)
	doc.biome_slots = slots
	doc.biome_density = density
	doc.heights = heights
	return doc


func _document_rows(doc: MapDocument, rule: Dictionary) -> PackedVector2Array:
	var fields := ScatterGenerator.document_fields(doc, "herbs")
	var species: Array[Dictionary] = [rule]
	var cells_by_species: Array = [ScatterGenerator.cells_in_bounds(fields.bounds)]
	return _points(
		ScatterGenerator.generate_species_cells(
			"herbs",
			species,
			fields.density_at,
			fields.height_at,
			fields.normal_at,
			doc.map_seed,
			cells_by_species,
			fields.bounds,
			fields.species_density_at,
			PackedFloat32Array(),
			{},
			fields.density_ceiling_at,
			null,
			fields.wet_at
		)
	)


func test_on_a_document_the_curve_multiplies_the_ground_rules_and_the_wet_field_is_read() -> void:
	var doc := _ramp_document()
	var base_rule := _species("herb", {"density_per_m2": 6.0})
	var rule := _species("herb", {"density_per_m2": 6.0})
	# The ground rises 0.5 m per metre: 26.57 degrees, so the curve answers 1 - 6.57 / 20.
	rule["response"] = {"slope": [[0, 1], [20, 1], [40, 0]]}
	var base := _document_rows(doc, base_rule)
	var curved := _document_rows(doc, rule)
	assert_gt(base.size(), 500)
	assert_almost_eq(float(curved.size()) / base.size(), 1.0 - 6.57 / 20.0, 0.06)
	assert_true(_subset(curved, base), "on top of the painted, rock and scree terms, not instead")
	var shore := PackedByteArray()
	shore.resize(doc.sample_count() * WaterDressing.CHANNELS)
	for i in shore.size():
		shore[i] = (i * 37) % 256
	doc.water_dressing = shore
	var fields := ScatterGenerator.document_fields(doc, "herbs")
	var samples := doc.samples_x()
	for at in [Vector2i(3, 4), Vector2i(10, 7), Vector2i(0, 0)]:
		var p := doc.sample_to_world(Vector2(at))
		var stored := float(shore[(at.y * samples + at.x) * WaterDressing.CHANNELS + 1]) / 255.0
		assert_almost_eq(float(fields.wet_at.call(p)), stored, 1e-5, str(at))
	var dry := ScatterGenerator.document_fields(_ramp_document(), "herbs")
	assert_eq(float(dry.wet_at.call(Vector2(3.0, 3.0))), 0.0, "no dressing reads 0")


func test_native_jobs_with_terrain_response_are_refused_without_the_capability() -> void:
	var legacy: Array[Dictionary] = [_species("a", {})]
	var curved: Array[Dictionary] = [_species("a", {"slope_min_deg": 12.0})]
	var water_only: Array[Dictionary] = [
		_species("a", {"response": {"water_dist": [[0, 1], [9, 0]]}})
	]
	if not ScatterNative.available():
		assert_eq(ScatterNative._refusal(curved), "missing")
		return
	if ScatterNative.force_gdscript:
		pending("forced to GDScript")
		return
	assert_eq(ScatterNative._refusal(legacy), "")
	assert_eq(ScatterNative._refusal(water_only), "", "an unevaluated axis does not matter")
	if ScatterNative.version().contains(ScatterNative.CAPABILITY_CURVES):
		assert_eq(ScatterNative._refusal(curved), "")
	else:
		assert_eq(ScatterNative._refusal(curved), "curves", ScatterNative.version())
