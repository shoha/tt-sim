extends GutTest

## ScatterGenerator against the real built-in palette: delivered density per species for
## every biome, fully painted and flat, against the palette targets (treecube's audit
## bands: 0.8 to 1.3x for random species, +-45 percent for clumped ones), spacing held
## everywhere, and the timings the brush budget is judged by. Prints the table.
##
## Where the density is measured. Dense species (ground cover, stones) are measured on the
## 200 ft map itself. A sparse species cannot be: the whole map holds six grassland oaks,
## so one map's count swings by +-40 percent on the seed alone (measured: 0.50 to 1.55x
## across species on seed 1, while twelve seeds average 0.84 to 1.07x). Each size class
## is therefore also generated, on its own species prefix (earlier species never depend
## on later ones, so their rows are the same), over the smallest square that expects at
## least MIN_EXPECTED of its sparsest species or clumps, capped at MAX_TIER_AREA; the
## band is asserted on that measurement, and the table shows both.

const HALF_200FT := 30.48
const RANDOM_BAND := Vector2(0.8, 1.3)
const CLUMP_BAND := Vector2(0.55, 1.45)
const MIN_EXPECTED := 150.0
const MAX_TIER_AREA := 160000.0
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
	biome_id: String, species: Array[Dictionary], bounds: Rect2
) -> Dictionary[String, PackedFloat32Array]:
	return ScatterGenerator.generate(
		biome_id, species, _one, _flat, _up, 1, ScatterGenerator.cells_in_bounds(bounds), bounds
	)


func _positions(rows: Dictionary, asset_ids: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for asset_id in asset_ids:
		var flat: PackedFloat32Array = rows.get(asset_id, PackedFloat32Array())
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			points.append(Vector2(flat[start], flat[start + 2]))
	return points


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


## The species of `biome_id` up to and including size class `last`.
func _prefix(species: Array[Dictionary], last: String) -> Array[Dictionary]:
	var limit := ScatterPlan.SIZE_CLASSES.find(last)
	var kept: Array[Dictionary] = []
	for rule in species:
		if ScatterPlan.SIZE_CLASSES.find(rule.size_class) <= limit:
			kept.append(rule)
	return kept


## Area that expects MIN_EXPECTED of a class's sparsest species (or clumps).
func _tier_area(species: Array[Dictionary], size_class: String) -> float:
	var area := 0.0
	for rule in species:
		if rule.size_class != size_class:
			continue
		area = maxf(area, MIN_EXPECTED / rule.density_per_m2)
		if rule.clump is Dictionary and rule.clump.parents_per_m2 > 0.0:
			area = maxf(area, MIN_EXPECTED / rule.clump.parents_per_m2)
	return minf(area, MAX_TIER_AREA)


## Instances of each spacing rule are never closer than it: a clumped species' children
## spacing, and a random class's shared spacing across all its species.
func _assert_spacing(biome_id: String, the_plan: Dictionary, rows: Dictionary) -> void:
	var groups := {}
	for entry in the_plan.species:
		if entry.spacing <= 0.0 or entry.field < 0:
			continue
		if not groups.has(entry.field):
			groups[entry.field] = {"spacing": 0.0, "assets": [], "keys": []}
		var group: Dictionary = groups[entry.field]
		group.spacing = maxf(group.spacing, entry.spacing)
		group.assets.append_array(entry.rule.assets)
		group.keys.append(entry.key)
	for group in groups.values():
		var points := _positions(rows, group.assets)
		var closest := _min_distance(points, group.spacing)
		assert_gte(closest, group.spacing - EPSILON, "%s %s" % [biome_id, group.keys])


func test_every_biome_delivers_the_palette_density() -> void:
	var map_bounds := _square(HALF_200FT)
	var map_area := map_bounds.get_area()
	var table: Array[String] = [
		(
			"%-26s %-13s %-6s %-6s %8s %8s %6s %8s %9s"
			% ["biome", "species", "class", "dist", "target", "200ft", "ratio", "measured", "at m2"]
		)
	]
	var timings: Array[String] = []
	for biome in PaletteLibrary.biomes():
		var species := PaletteLibrary.species(biome.id)
		var the_plan := ScatterPlan.build(biome.id, species, 1)
		var started := Time.get_ticks_usec()
		var rows := _generate(biome.id, species, map_bounds)
		var elapsed := (Time.get_ticks_usec() - started) / 1000.0
		var total := 0
		for asset_id in rows:
			total += rows[asset_id].size() / ScatterGenerator.ROW_STRIDE
		timings.append("%-26s %6d instances %8.1f ms" % [biome.id, total, elapsed])
		_assert_spacing(biome.id, the_plan, rows)
		var tiers := {}
		for size_class in ["large", "medium", "small"]:
			var area := _tier_area(species, size_class)
			if area > map_area:
				var bounds := _square(sqrt(area) * 0.5)
				tiers[size_class] = {
					"rows": _generate(biome.id, _prefix(species, size_class), bounds),
					"area": bounds.get_area(),
				}
		for i in species.size():
			var rule := species[i]
			var entry: Dictionary = the_plan.species[i]
			var on_map := _positions(rows, rule.assets).size() / map_area
			var measured := on_map
			var measured_area := map_area
			if tiers.has(rule.size_class):
				var tier: Dictionary = tiers[rule.size_class]
				measured = _positions(tier.rows, rule.assets).size() / tier.area
				measured_area = tier.area
			var target: float = rule.density_per_m2
			var ratio := measured / target
			var band := CLUMP_BAND if entry.clumped else RANDOM_BAND
			var note := ""
			if entry.reachable < 1.0:
				note = " unreachable: packing cap allows %.2fx" % entry.reachable
			(
				table
				. append(
					(
						"%-26s %-13s %-6s %-6s %8.4f %8.4f %6.2f %8.2f %9.0f%s"
						% [
							biome.id,
							rule.key,
							rule.size_class,
							"clump" if entry.clumped else "random",
							target,
							on_map,
							on_map / target,
							ratio,
							measured_area,
							note,
						]
					)
				)
			)
			assert_between(
				ratio, band.x * minf(entry.reachable, 1.0), band.y, "%s %s" % [biome.id, rule.key]
			)
	for line in table:
		gut.p(line)
	for line in timings:
		gut.p("whole 200 ft map: " + line)


func test_timing_of_one_chunk_four_chunks_and_the_whole_map() -> void:
	# The densest biome by total target density is the worst case for a brush dab.
	var densest := ""
	var most := 0.0
	for biome in PaletteLibrary.biomes():
		var total := 0.0
		for rule in biome.species:
			total += rule.density_per_m2
		if total > most:
			most = total
			densest = biome.id
	var species := PaletteLibrary.species(densest)
	var bounds := _square(HALF_200FT)
	var runs := {
		"one chunk": [Vector2i(0, 0)] as Array[Vector2i],
		"four chunks":
		[Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)] as Array[Vector2i],
		"whole map": ScatterGenerator.cells_in_bounds(bounds),
	}
	for label in runs:
		var best := INF
		for _rep in 2:
			var started := Time.get_ticks_usec()
			ScatterGenerator.generate(densest, species, _one, _flat, _up, 1, runs[label], bounds)
			best = minf(best, (Time.get_ticks_usec() - started) / 1000.0)
		gut.p("%s (%s, %.2f per m2): %.1f ms" % [label, densest, most, best])
		# A regression guard an order of magnitude above the measurement, not a budget.
		assert_lt(best, 15000.0, label)
