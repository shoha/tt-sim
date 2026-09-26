extends GutTest

## ScatterGenerator's rules, each on a small synthetic or real-palette setup that runs in
## well under a second: region independence, Matern III spacing near the packing limit,
## painted density, slope, relations, transforms, asset choice and the MapDocument
## adapter. The full-palette density table and the timings are in
## test_scatter_generator_calibration.gd.

## The authoring maximum, 200 ft = 40 cells of 1.524 m, centred on the origin.
const HALF_200FT := 30.48
const BOREAL := "boreal_taiga_summer_s1"
const ALPINE := "alpine_meadow_summer_s1"
## Float32 rows: distances recomputed from them are good to about a micrometre.
const EPSILON := 1e-4


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


func _square(half: float) -> Rect2:
	return Rect2(-half, -half, 2.0 * half, 2.0 * half)


func _generate(
	species: Array[Dictionary], bounds: Rect2, density: Callable = Callable(), map_seed: int = 1
) -> Dictionary[String, PackedFloat32Array]:
	return ScatterGenerator.generate(
		"test",
		species,
		density if density.is_valid() else _one,
		_flat,
		_up,
		map_seed,
		ScatterGenerator.cells_in_bounds(bounds),
		bounds
	)


func _species(key: String, fields: Dictionary) -> Dictionary:
	var rule := {"key": key, "kind": "grass", "size_class": "small", "assets": ["test/" + key]}
	rule.merge(fields, true)
	return rule


## Species of a palette biome up to and including `last_class` (large -> ground). Earlier
## species never depend on later ones, so a prefix generates the same rows for them.
func _prefix(biome_id: String, last_class: String) -> Array[Dictionary]:
	var last := ScatterPlan.SIZE_CLASSES.find(last_class)
	var kept: Array[Dictionary] = []
	for rule in PaletteLibrary.species(biome_id):
		if ScatterPlan.SIZE_CLASSES.find(rule.size_class) <= last:
			kept.append(rule)
	return kept


## Instance positions (XZ) of the given asset ids.
func _positions(rows: Dictionary, asset_ids: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for asset_id in asset_ids:
		var flat: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array())
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			points.append(Vector2(flat[start], flat[start + 2]))
	return points


func _count(rows: Dictionary, asset_ids: Array) -> int:
	return _positions(rows, asset_ids).size()


## The rows whose origin lies in `cell`, per asset, in their original order.
func _rows_in_cell(rows: Dictionary, cell: Vector2i) -> Dictionary[String, PackedFloat32Array]:
	var chunk := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var kept: Dictionary[String, PackedFloat32Array] = {}
	for asset_id in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		var out := PackedFloat32Array()
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			var at := Vector3(flat[start], 0.0, flat[start + 2])
			if ScatterChunker.cell_for(at, chunk) == cell:
				out.append_array(flat.slice(start, start + ScatterGenerator.ROW_STRIDE))
		if not out.is_empty():
			kept[asset_id] = out
	return kept


## The smallest distance between any two points (grid hashed at `cell` size, which must
## be at least the distance of interest).
func _min_distance(points: PackedVector2Array, cell: float) -> float:
	var grid := {}
	for i in points.size():
		var key := Vector2i(floori(points[i].x / cell), floori(points[i].y / cell))
		if not grid.has(key):
			grid[key] = PackedInt32Array()
		grid[key].append(i)
	var best := INF
	for i in points.size():
		var key := Vector2i(floori(points[i].x / cell), floori(points[i].y / cell))
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for j in grid.get(key + Vector2i(dx, dz), PackedInt32Array()):
					if j > i:
						best = minf(best, points[i].distance_to(points[j]))
	return best


func _all_assets(species: Array[Dictionary]) -> Array:
	var ids: Array = []
	for rule in species:
		ids.append_array(rule.assets)
	return ids


func test_a_cell_is_identical_alone_with_neighbours_and_in_the_whole_map() -> void:
	# The alpine meadow has everything that crosses a chunk border: spaced trees,
	# boulders, clumps, patterns, and stones and gentians that seek boulders.
	var species := PaletteLibrary.species(ALPINE)
	var bounds := _square(15.0)
	var cell := Vector2i(0, 0)
	var alone: Array[Vector2i] = [cell]
	var neighbours: Array[Vector2i] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			neighbours.append(cell + Vector2i(dx, dz))
	var all_cells := ScatterGenerator.cells_in_bounds(bounds)
	var runs := []
	for cells in [alone, neighbours, all_cells]:
		runs.append(
			_rows_in_cell(
				ScatterGenerator.generate(ALPINE, species, _one, _flat, _up, 5, cells, bounds), cell
			)
		)
	assert_gt(runs[0].size(), 3, "the cell holds several species")
	assert_eq(runs[1], runs[0], "with its neighbours")
	assert_eq(runs[2], runs[0], "inside the whole map")


func test_region_independence_holds_for_a_saturated_packing_and_relations() -> void:
	# Boreal large trees pack near the jamming limit (long survival chains), and young
	# pines avoid boulders and keep clear of trees.
	var species := _prefix(BOREAL, "medium")
	var bounds := _square(HALF_200FT)
	var cell := Vector2i(-1, 0)
	var alone: Array[Vector2i] = [cell]
	var whole := ScatterGenerator.generate(
		BOREAL, species, _one, _flat, _up, 9, ScatterGenerator.cells_in_bounds(bounds), bounds
	)
	var single := ScatterGenerator.generate(BOREAL, species, _one, _flat, _up, 9, alone, bounds)
	assert_eq(_rows_in_cell(single, cell), _rows_in_cell(whole, cell))
	assert_eq(_rows_in_cell(single, cell), single, "nothing outside the asked cell")


func test_a_species_prefix_generates_the_same_rows_for_its_species() -> void:
	var bounds := _square(HALF_200FT)
	var cells: Array[Vector2i] = [Vector2i(0, -1)]
	var large := _prefix(BOREAL, "large")
	var full := ScatterGenerator.generate(
		BOREAL, PaletteLibrary.species(BOREAL), _one, _flat, _up, 3, cells, bounds
	)
	var partial := ScatterGenerator.generate(BOREAL, large, _one, _flat, _up, 3, cells, bounds)
	for asset_id in _all_assets(large):
		assert_eq(full.get(asset_id), partial.get(asset_id), asset_id)


func test_boreal_large_trees_reach_the_packing_target_without_breaking_spacing() -> void:
	var species := _prefix(BOREAL, "large")
	var bounds := _square(HALF_200FT)
	var rows := _generate(species, bounds)
	var target := 0.0
	var spacing := 0.0
	for rule in species:
		target += rule.density_per_m2
		spacing = maxf(spacing, rule.min_spacing_m)
	var points := _positions(rows, _all_assets(species))
	var ratio := points.size() / bounds.get_area() / target
	gut.p(
		(
			"boreal large trees: %d, %.4f per m2 against %.4f (%.2fx)"
			% [points.size(), points.size() / bounds.get_area(), target, ratio]
		)
	)
	assert_gte(ratio, 0.85, "Matern III packs past Matern II's 0.016 per m2")
	assert_gte(_min_distance(points, spacing), spacing - EPSILON, "trees of either species")


func test_ground_cover_keeps_its_children_spacing() -> void:
	var rule := _species(
		"turf",
		{
			"size_class": "ground",
			"density_per_m2": 6.0,
			"min_spacing_m": 0.15,
			"clump":
			{
				"parents_per_m2": 0.5,
				"radius_m": 1.0,
				"transition_m": 0.6,
				"children_spacing_m": 0.15
			},
		}
	)
	var species: Array[Dictionary] = [rule]
	var points := _positions(_generate(species, _square(8.0)), rule.assets)
	assert_gt(points.size(), 500)
	assert_gte(_min_distance(points, 0.15), 0.15 - EPSILON)


func test_painted_density_scales_the_local_density() -> void:
	var herb := _species("herb", {"density_per_m2": 4.0})
	var species: Array[Dictionary] = [herb]
	var bounds := _square(10.0)
	var full := _count(_generate(species, bounds), herb.assets)
	var half := _count(
		_generate(species, bounds, func(_p: Vector2) -> float: return 0.5), herb.assets
	)
	var none := _generate(species, bounds, func(_p: Vector2) -> float: return 0.0)
	assert_almost_eq(full / (bounds.get_area() * 4.0), 1.0, 0.1, "full paint delivers the target")
	assert_almost_eq(float(half) / full, 0.5, 0.05, "half paint delivers half")
	assert_true(none.is_empty(), "no paint, no instances")


func test_half_paint_halves_even_a_saturated_packing() -> void:
	# Thinning after spacing: candidates thinned before packing would repack to almost
	# the same density, so a soft brush edge would not read as thinner.
	var species := _prefix(BOREAL, "large")
	var bounds := _square(HALF_200FT)
	var ids := _all_assets(species)
	var full := _count(_generate(species, bounds), ids)
	var half := _count(_generate(species, bounds, func(_p: Vector2) -> float: return 0.5), ids)
	assert_almost_eq(float(half) / full, 0.5, 0.1)


func test_a_soft_brush_edge_thins_out_gradually() -> void:
	var herb := _species("herb", {"density_per_m2": 4.0})
	var species: Array[Dictionary] = [herb]
	var bounds := Rect2(0.0, -5.0, 20.0, 10.0)
	var ramp := func(p: Vector2) -> float: return clampf(p.x / 20.0, 0.0, 1.0)
	var points := _positions(_generate(species, bounds, ramp), herb.assets)
	var bands := [0, 0, 0, 0]
	for point in points:
		bands[mini(floori(point.x / 5.0), 3)] += 1
	for i in 3:
		assert_lt(bands[i], bands[i + 1], "band %d thinner than band %d" % [i, i + 1])


func test_slope_limit_with_falloff_on_an_analytic_ramp() -> void:
	# The surface angle is x + 45 degrees: 0 at x = -45, 90 at x = 45.
	var shrub := _species("shrub", {"density_per_m2": 2.0, "slope_max_deg": 30.0})
	var species: Array[Dictionary] = [shrub]
	var bounds := Rect2(-45.0, -10.0, 90.0, 20.0)
	var ramp := func(p: Vector2) -> Vector3:
		var angle := deg_to_rad(clampf(p.x + 45.0, 0.0, 89.0))
		return Vector3(sin(angle), cos(angle), 0.0)
	var rows := ScatterGenerator.generate(
		"test", species, _one, _flat, ramp, 1, ScatterGenerator.cells_in_bounds(bounds), bounds
	)
	var gentle := 0
	var falloff := 0
	var steep := 0
	for point in _positions(rows, shrub.assets):
		var angle := point.x + 45.0
		if angle < 25.0:
			gentle += 1
		elif angle >= 30.0 and angle < 40.0:
			falloff += 1
		elif angle >= 40.0 + EPSILON:
			steep += 1
	assert_almost_eq(gentle / (25.0 * 20.0 * 2.0), 1.0, 0.1, "full density well below the limit")
	assert_eq(steep, 0, "nothing past the limit plus the 10 degree falloff")
	assert_almost_eq(falloff / (10.0 * 20.0 * 2.0), 0.5, 0.12, "linear falloff in between")


func _boulder() -> Dictionary:
	return _species(
		"boulder",
		{"kind": "rock", "size_class": "medium", "density_per_m2": 0.05, "min_spacing_m": 2.0}
	)


## Share of `points` within `reach` of any of `targets`.
func _share_within(points: PackedVector2Array, targets: PackedVector2Array, reach: float) -> float:
	if points.is_empty():
		return 0.0
	var inside := 0
	for point in points:
		for target in targets:
			if point.distance_to(target) <= reach:
				inside += 1
				break
	return float(inside) / points.size()


func test_near_and_avoid_relations_pull_and_push_with_their_influence() -> void:
	var boulder := _boulder()
	var relation := {"species": "boulder", "distance_m": 1.5, "transition_m": 0.0}
	var free := _species("free", {"density_per_m2": 0.5})
	var near_all := _species("near_all", {"density_per_m2": 0.5, "near": [relation]})
	var near_half := _species(
		"near_half", {"density_per_m2": 0.5, "near": [relation.merged({"influence": 0.5})]}
	)
	var avoid_all := _species("avoid_all", {"density_per_m2": 0.5, "avoid": [relation]})
	var avoid_half := _species(
		"avoid_half", {"density_per_m2": 0.5, "avoid": [relation.merged({"influence": 0.5})]}
	)
	var species: Array[Dictionary] = [boulder, free, near_all, near_half, avoid_all, avoid_half]
	var rows := _generate(species, _square(25.0))
	var boulders := _positions(rows, boulder.assets)
	var share := {}
	for rule in species.slice(1):
		share[rule.key] = _share_within(_positions(rows, rule.assets), boulders, 1.5 + EPSILON)
	gut.p("share within 1.5 m of a boulder: %s" % share)
	assert_gt(share.free, 0.1, "the baseline sees some boulders")
	assert_almost_eq(share.near_all, 1.0, 0.001, "full affinity keeps only near instances")
	assert_between(share.near_half, share.free + 0.1, 0.99, "half affinity leans near")
	assert_eq(share.avoid_all, 0.0, "full repulsion keeps none near")
	assert_between(share.avoid_half, 0.01, share.free - 0.05, "half repulsion leans away")
	var delivered: float = _count(rows, near_all.assets) / _square(25.0).get_area()
	assert_almost_eq(delivered / 0.5, 1.0, 0.3, "the keep model compensates the affinity")


func test_clumped_affinity_keeps_whole_clumps_near_the_target() -> void:
	var boulder := _boulder()
	var stones := _species(
		"stones",
		{
			"density_per_m2": 0.3,
			"clump":
			{
				"parents_per_m2": 0.05,
				"radius_m": 1.0,
				"transition_m": 0.5,
				"children_spacing_m": 0.25
			},
			"near": [{"species": "boulder", "distance_m": 1.0, "transition_m": 0.0}],
		}
	)
	var species: Array[Dictionary] = [boulder, stones]
	var rows := _generate(species, _square(25.0))
	var points := _positions(rows, stones.assets)
	assert_gt(points.size(), 50)
	# A kept parent lies within 1 m of a boulder; its children lie within its jittered
	# radius plus transition of it.
	var reach := 1.0 + 1.0 * (1.0 + ScatterPlan.CLUMP_RADIUS_JITTER) + 0.5
	assert_eq(_share_within(points, _positions(rows, boulder.assets), reach + EPSILON), 1.0)


func test_smaller_classes_keep_clear_of_larger_ones() -> void:
	var tree := _species(
		"tree",
		{"kind": "tree", "size_class": "large", "density_per_m2": 0.03, "min_spacing_m": 4.5}
	)
	var bush := _species(
		"bush",
		{"kind": "tree", "size_class": "medium", "density_per_m2": 0.1, "min_spacing_m": 2.0}
	)
	var species: Array[Dictionary] = [tree, bush]
	var rows := _generate(species, _square(25.0))
	var clearance := 2.0 * ScatterPlan.CLEARANCE_FRACTION
	var bushes := _positions(rows, bush.assets)
	assert_gt(bushes.size(), 100)
	assert_eq(_share_within(bushes, _positions(rows, tree.assets), clearance - EPSILON), 0.0)


func _transforms(rule: Dictionary, normal: Vector3) -> Array[Transform3D]:
	var species: Array[Dictionary] = [rule]
	var bounds := _square(8.0)
	var height := func(p: Vector2) -> float: return 0.1 * p.x + 0.2 * p.y + 3.0
	var tilted := func(_p: Vector2) -> Vector3: return normal
	var rows := ScatterGenerator.generate(
		"test", species, _one, height, tilted, 1, ScatterGenerator.cells_in_bounds(bounds), bounds
	)
	var out: Array[Transform3D] = []
	for asset_id in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			var row := Array(flat.slice(start, start + ScatterGenerator.ROW_STRIDE))
			out.append(ScatterGlbUtils._row_to_transform(row))
			assert_almost_eq(row[1], 0.1 * row[0] + 0.2 * row[2] + 3.0, EPSILON, "Y is height_at")
	return out


func test_upright_species_stand_on_plus_y_with_yaw_and_scale_in_range() -> void:
	var normal := Vector3(0.3, 1.0, 0.2).normalized()
	var tree := _species(
		"tree",
		{"kind": "tree", "density_per_m2": 3.0, "yaw_random_deg": 90.0, "scale_spread": 0.15}
	)
	var transforms := _transforms(tree, normal)
	assert_gt(transforms.size(), 300)
	var widest_yaw := 0.0
	var smallest := INF
	var largest := 0.0
	for xform in transforms:
		var scale := xform.basis.get_scale().x
		smallest = minf(smallest, scale)
		largest = maxf(largest, scale)
		var up := xform.basis.y / scale
		assert_true(up.is_equal_approx(Vector3.UP), "upright ignores the ground normal")
		var yaw := absf(xform.basis.get_rotation_quaternion().get_euler().y)
		widest_yaw = maxf(widest_yaw, yaw)
	assert_lte(widest_yaw, deg_to_rad(45.0) + EPSILON, "yaw within +-yaw_random_deg / 2")
	assert_gt(widest_yaw, deg_to_rad(40.0), "and it uses the range")
	assert_between(smallest, 0.85 - EPSILON, 0.87, "scale spread reaches 1 - spread")
	assert_between(largest, 1.13, 1.15 + EPSILON, "and 1 + spread")


func test_no_yaw_range_means_no_rotation() -> void:
	var post := _species("post", {"kind": "tree", "density_per_m2": 1.0, "yaw_random_deg": 0.0})
	for xform in _transforms(post, Vector3.UP):
		assert_true(xform.basis.is_equal_approx(Basis.IDENTITY))


func test_normal_aligned_species_follow_the_normal_and_respect_the_scale_floor() -> void:
	var normal := Vector3(0.3, 1.0, 0.2).normalized()
	var rock := _species(
		"rock",
		{
			"kind": "rock",
			"align": "normal",
			"density_per_m2": 3.0,
			"scale_spread": 0.8,
			"scale_floor": 0.5,
		}
	)
	var transforms := _transforms(rock, normal)
	var floored := 0
	for xform in transforms:
		var scale := xform.basis.get_scale().x
		assert_gte(scale, 0.5 - EPSILON, "never below scale_floor")
		assert_lte(scale, 1.8 + EPSILON)
		floored += 1 if absf(scale - 0.5) < EPSILON else 0
		var up := (xform.basis.y / scale).normalized()
		assert_gte(up.dot(normal), cos(ScatterGenerator.NORMAL_TILT_MAX_RAD) - EPSILON)
	# Uniform in 1 +- 0.8 puts 0.3 / 1.6 of the instances under the 0.5 floor.
	assert_almost_eq(floored / float(transforms.size()), 0.1875, 0.05, "the floor clamps them")


func test_asset_choice_is_deterministic_and_spread_over_the_assets() -> void:
	var assets := ["test/a", "test/b", "test/c", "test/d"]
	var herb := _species("herb", {"density_per_m2": 5.0, "assets": assets})
	var species: Array[Dictionary] = [herb]
	var first := _generate(species, _square(10.0))
	assert_eq(_generate(species, _square(10.0)), first, "same inputs, same rows")
	var total := _count(first, assets)
	for asset_id in assets:
		assert_almost_eq(_count(first, [asset_id]) / float(total), 0.25, 0.05, asset_id)
	assert_ne(_generate(species, _square(10.0), _one, 2), first, "another map seed differs")


func test_cells_in_bounds_covers_the_200ft_map_with_64_chunks() -> void:
	var cells := ScatterGenerator.cells_in_bounds(_square(HALF_200FT))
	assert_eq(cells.size(), 64)
	assert_eq(cells[0], Vector2i(-4, -4))
	assert_eq(cells[-1], Vector2i(3, 3))


func test_packing_time_inverts_the_coverage_curve() -> void:
	for t in [0.05, 0.3, 1.0, 4.0, 10.0]:
		var theta := ScatterPlan.packing_coverage(t)
		assert_almost_eq(ScatterPlan.packing_time(theta), t, 1e-6)
	assert_eq(ScatterPlan.packing_time(0.6), ScatterPlan.MAX_PACKING_TIME, "capped")


func test_plan_reports_a_target_past_the_packing_cap() -> void:
	var crowded := _species("crowded", {"density_per_m2": 0.04, "min_spacing_m": 4.5})
	var species: Array[Dictionary] = [crowded]
	var entry: Dictionary = ScatterPlan.build("test", species, 1).species[0]
	assert_lt(entry.reachable, 0.9, "0.04 per m2 at 4.5 m is past jamming")


func _document() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(8, 8), "", "", 7)
	doc.biome_ids = PackedStringArray(["other", "herbs"])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	var heights := PackedFloat32Array()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			slots.append(2 if world.x < 0.0 else 1)
			density.append(255)
			heights.append(0.5 * world.x)
	doc.biome_slots = slots
	doc.biome_density = density
	doc.heights = heights
	return doc


func test_document_fields_sample_the_painted_biome_heights_and_normals() -> void:
	var doc := _document()
	var fields := ScatterGenerator.document_fields(doc, "herbs")
	assert_eq(fields.density_at.call(Vector2(-3.0, 1.0)), 1.0, "painted with this biome")
	assert_eq(fields.density_at.call(Vector2(3.0, 1.0)), 0.0, "another biome")
	assert_eq(fields.density_at.call(Vector2(-30.0, 0.0)), 0.0, "off the map")
	assert_almost_eq(fields.height_at.call(Vector2(2.1, -1.3)), 1.05, 1e-4)
	var normal: Vector3 = fields.normal_at.call(Vector2(1.0, 1.0))
	assert_true(normal.is_equal_approx(Vector3(-0.5, 1.0, 0.0).normalized()), str(normal))
	assert_eq(fields.bounds, Rect2(-doc.extent_m() * 0.5, doc.extent_m()))


func test_generate_for_document_places_only_where_the_biome_is_painted() -> void:
	var doc := _document()
	doc.biome_ids = PackedStringArray(["other", ALPINE])
	var cells := ScatterGenerator.cells_in_bounds(
		ScatterGenerator.document_fields(doc, ALPINE).bounds
	)
	var rows := ScatterGenerator.generate_for_document(doc, ALPINE, cells)
	var points := PackedVector2Array()
	for asset_id in rows:
		points.append_array(_positions(rows, [asset_id]))
	assert_gt(points.size(), 100)
	var step := doc.sample_step().x
	for point in points:
		assert_lt(point.x, step, "instances stay on the painted half (bilinear edge aside)")
