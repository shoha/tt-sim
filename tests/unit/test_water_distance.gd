extends GutTest

## The water_dist response axis (content library step S12c): the distance grid
## (ScatterTerrain.water_distance_grid, derived from the stored wet dressing), its bilinear sampler
## and the curve acting on a lake. The grid is a pure function of the document, so a cell
## generated alone, with neighbours or in the whole map reads the same distances; the native port
## is compared in test_scatter_native.gd and the landform parity files.

const LAKE_CENTRE := Vector2(-6.0, 1.0)
const LAKE_RADIUS := 3.0
## One sample step and a little: the grid measures to wet sample points, not to the true shore.
const GRID_TOLERANCE_M := 0.6


## A flat document of `cells` squares, all of one biome ("herbs"), with a round lake in its wet
## dressing: the wet-line byte (channel A) at 255 inside `radius` of `centre`, which is all the
## distance grid reads.
func _lake_document(cells: Vector2i, centre: Vector2, radius: float) -> MapDocument:
	var doc := MapDocument.create_flat(cells, "", "", 7)
	doc.biome_ids = PackedStringArray(["herbs"])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	var heights := PackedFloat32Array()
	var field := PackedByteArray()
	field.resize(doc.sample_count() * WaterDressing.CHANNELS)
	var columns := doc.samples_x()
	for z in doc.samples_z():
		for x in columns:
			slots.append(1)
			density.append(255)
			heights.append(0.0)
			if doc.sample_to_world(Vector2(x, z)).distance_to(centre) <= radius:
				field[(z * columns + x) * WaterDressing.CHANNELS + 3] = 255
	doc.biome_slots = slots
	doc.biome_density = density
	doc.heights = heights
	doc.water_dressing = field
	return doc


## Metres from `p` to the nearest wet sample of `doc`, by brute force, capped like the grid.
func _brute(wet: PackedVector2Array, p: Vector2) -> float:
	var best := ScatterTerrain.WATER_DIST_MAX_M
	for w in wet:
		best = minf(best, p.distance_to(w))
	return best


func _wet_points(doc: MapDocument) -> PackedVector2Array:
	var points := PackedVector2Array()
	var columns := doc.samples_x()
	for z in doc.samples_z():
		for x in columns:
			if doc.water_dressing[(z * columns + x) * WaterDressing.CHANNELS + 3] == 255:
				points.append(doc.sample_to_world(Vector2(x, z)))
	return points


func _rule(fields: Dictionary) -> Dictionary:
	var rule := {
		"key": "sedge",
		"kind": "grass",
		"size_class": "small",
		"density_per_m2": 4.0,
		"assets": ["test/sedge"],
	}
	rule.merge(fields, true)
	return rule


func _rows(doc: MapDocument, rule: Dictionary, cells: Array[Vector2i], window: Rect2) -> Dictionary:
	var fields := ScatterGenerator.document_fields(doc, "herbs", window)
	var species: Array[Dictionary] = [rule]
	var cells_by_species: Array = [cells]
	return ScatterGenerator.generate_species_cells(
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
		fields.wet_at,
		fields.water_dist_at
	)


func _points(rows: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for asset_id: String in rows:
		var flat: PackedFloat32Array = rows[asset_id]
		for start in range(0, flat.size(), ScatterGenerator.ROW_STRIDE):
			points.append(Vector2(flat[start], flat[start + 2]))
	return points


## Metres from the lake's edge (the analytic distance the grid approximates), 0 on the water.
func _from_lake(p: Vector2) -> float:
	return maxf(p.distance_to(LAKE_CENTRE) - LAKE_RADIUS, 0.0)


func _band_counts(points: PackedVector2Array, edges: Array) -> Array[int]:
	var counts: Array[int] = []
	counts.resize(edges.size() - 1)
	counts.fill(0)
	for point in points:
		var d := _from_lake(point)
		for i in counts.size():
			if d >= edges[i] and d < edges[i + 1]:
				counts[i] += 1
				break
	return counts


func test_the_grid_is_the_distance_to_the_nearest_water_sample_and_zero_on_water() -> void:
	var doc := _lake_document(Vector2i(12, 12), Vector2(-4.0, 2.0), 2.5)
	var grid := ScatterTerrain.water_distance_grid(doc)
	assert_eq(grid.size(), doc.sample_count())
	var wet := _wet_points(doc)
	assert_gt(wet.size(), 100)
	var columns := doc.samples_x()
	var worst := 0.0
	for z in range(0, doc.samples_z(), 3):
		for x in range(0, columns, 3):
			var p := doc.sample_to_world(Vector2(x, z))
			var expected := _brute(wet, p)
			worst = maxf(worst, absf(grid[z * columns + x] - expected))
			if wet.has(p):
				assert_eq(grid[z * columns + x], 0.0, "0 on the water itself")
	assert_lt(worst, 1e-4, "exact Euclidean distance to the nearest wet sample")


func test_the_grid_caps_at_64_metres_and_a_dry_map_reads_the_cap() -> void:
	var doc := _lake_document(Vector2i(64, 64), Vector2(-46.0, -46.0), 1.0)
	var grid := ScatterTerrain.water_distance_grid(doc)
	var wet := _wet_points(doc)
	var columns := doc.samples_x()
	var capped := 0
	var worst := 0.0
	for z in range(0, doc.samples_z(), 7):
		for x in range(0, columns, 7):
			var expected := _brute(wet, doc.sample_to_world(Vector2(x, z)))
			worst = maxf(worst, absf(grid[z * columns + x] - expected))
			if expected >= ScatterTerrain.WATER_DIST_MAX_M:
				capped += 1
				assert_eq(grid[z * columns + x], ScatterTerrain.WATER_DIST_MAX_M)
	assert_lt(worst, 1e-4, "exact up to the cap, a corner lake on the largest map")
	assert_gt(capped, 100, "the far corner is past 64 m")
	var far_lake := _lake_document(Vector2i(4, 4), Vector2(99, 99), 1.0)
	var dry := ScatterGenerator.document_fields(far_lake, "herbs")
	assert_eq(float(dry.water_dist_at.call(Vector2(1.0, 1.0))), 64.0, "no water reads the cap")
	var no_field := MapDocument.create_flat(Vector2i(4, 4), "", "", 7)
	assert_eq(ScatterTerrain.water_distance_grid(no_field).size(), 0, "no dressing, no grid")


func test_the_sampler_is_bilinear_clamped_and_matches_the_grid_at_samples() -> void:
	var doc := _lake_document(Vector2i(12, 12), Vector2(-4.0, 2.0), 2.5)
	var grid := ScatterTerrain.water_distance_grid(doc)
	var sample := ScatterTerrain.water_dist_sampler(doc)
	var columns := doc.samples_x()
	for at in [Vector2i(3, 4), Vector2i(40, 30), Vector2i(columns - 1, doc.samples_z() - 1)]:
		var p := doc.sample_to_world(Vector2(at))
		assert_almost_eq(float(sample.call(p)), grid[at.y * columns + at.x], 1e-6, str(at))
	var a := doc.sample_to_world(Vector2(50, 60))
	var b := doc.sample_to_world(Vector2(51, 60))
	var mid: float = sample.call((a + b) * 0.5)
	assert_almost_eq(mid, (grid[60 * columns + 50] + grid[60 * columns + 51]) * 0.5, 1e-5)
	var outside: float = sample.call(Vector2(500.0, 500.0))
	assert_eq(outside, grid[columns * doc.samples_z() - 1], "clamped to the edge sample")


func test_the_grid_follows_the_dressing_and_is_cached_by_its_content() -> void:
	var doc := _lake_document(Vector2i(12, 12), Vector2(-4.0, 2.0), 2.5)
	var first := ScatterTerrain.water_distance_grid(doc)
	assert_eq(ScatterTerrain.water_distance_grid(doc), first, "same dressing, same grid")
	var other := _lake_document(Vector2i(12, 12), Vector2(5.0, -3.0), 2.5)
	var moved := ScatterTerrain.water_distance_grid(other)
	assert_ne(moved, first, "a different dressing is a different grid")
	assert_eq(ScatterTerrain.water_distance_grid(doc), first, "and the first is not stale")
	var drained := _lake_document(Vector2i(12, 12), Vector2(-4.0, 2.0), 2.5)
	drained.water_dressing.fill(0)
	var all_far := ScatterTerrain.water_distance_grid(drained)
	assert_eq(all_far.size(), drained.sample_count())
	assert_eq(all_far[0], 64.0)
	assert_eq(all_far[all_far.size() / 2], 64.0, "wet-line bytes below 255 are not water")
	# A brush writing the stored field in place (packed arrays are shared by reference) must not
	# leave a stale grid behind.
	var edited := _lake_document(Vector2i(12, 12), Vector2(-4.0, 2.0), 2.5)
	var before := ScatterTerrain.water_distance_grid(edited)
	var corner := (edited.samples_x() * edited.samples_z() - 1) * WaterDressing.CHANNELS + 3
	edited.water_dressing[corner] = 255
	var after := ScatterTerrain.water_distance_grid(edited)
	assert_ne(after, before)
	assert_eq(after[after.size() - 1], 0.0, "the new water sample is at distance 0")


func test_an_identity_curve_gives_the_rows_of_no_curve() -> void:
	var doc := _lake_document(Vector2i(16, 16), LAKE_CENTRE, LAKE_RADIUS)
	var cells := ScatterGenerator.cells_in_bounds(Rect2(-12.0, -12.0, 24.0, 24.0))
	var base := _rows(doc, _rule({}), cells, Rect2())
	var identity := _rule({"response": {"water_dist": [[0, 1], [64, 1]]}})
	assert_gt(_points(base).size(), 1000)
	assert_eq(_rows(doc, identity, cells, Rect2()), base)


func test_curves_thin_thicken_and_ring_by_distance_to_the_lake() -> void:
	var doc := _lake_document(Vector2i(16, 16), LAKE_CENTRE, LAKE_RADIUS)
	var cells := ScatterGenerator.cells_in_bounds(Rect2(-12.0, -12.0, 24.0, 24.0))
	var edges := [0.0, 2.0, 4.0, 6.0, 8.0, 10.0]
	var base := _band_counts(_points(_rows(doc, _rule({}), cells, Rect2())), edges)
	var down := _band_counts(
		_points(_rows(doc, _rule({"response": {"water_dist": [[0, 1], [12, 0]]}}), cells, Rect2())),
		edges
	)
	var up := _band_counts(
		_points(
			_rows(doc, _rule({"response": {"water_dist": [[0, 0.1], [12, 1]]}}), cells, Rect2())
		),
		edges
	)
	var previous_down := 2.0
	var previous_up := -1.0
	for i in 5:
		var middle := (float(edges[i]) + float(edges[i + 1])) * 0.5
		var share_down := float(down[i]) / base[i]
		var share_up := float(up[i]) / base[i]
		assert_almost_eq(share_down, 1.0 - middle / 12.0, 0.12, "descending, band %d" % i)
		assert_almost_eq(share_up, 0.1 + 0.9 * middle / 12.0, 0.12, "ascending, band %d" % i)
		assert_lt(share_down, previous_down, "density falls with distance: band %d" % i)
		assert_gt(share_up, previous_up, "density rises with distance: band %d" % i)
		previous_down = share_down
		previous_up = share_up
	var ring := _points(
		_rows(
			doc,
			_rule({"response": {"water_dist": [[0, 0], [3, 0], [4, 1], [7, 1], [8, 0]]}}),
			cells,
			Rect2()
		)
	)
	assert_gt(ring.size(), 100, "a ring is placed")
	for point in ring:
		var d := _from_lake(point)
		assert_gt(d, 3.0 - GRID_TOLERANCE_M, "nothing inside the ring")
		assert_lt(d, 8.0 + GRID_TOLERANCE_M, "nothing beyond it")


func test_a_cell_is_identical_alone_with_neighbours_and_in_the_whole_map() -> void:
	var doc := _lake_document(Vector2i(16, 16), LAKE_CENTRE, LAKE_RADIUS)
	var rule := _rule({"response": {"water_dist": [[0, 1], [6, 0.4], [30, 0.1]]}})
	var cell := Vector2i(-1, 0)  # the lake's own cell: x -10..0
	var alone: Array[Vector2i] = [cell]
	var neighbours: Array[Vector2i] = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			neighbours.append(cell + Vector2i(dx, dz))
	var everything := ScatterGenerator.cells_in_bounds(Rect2(-12.0, -12.0, 24.0, 24.0))
	var box := Rect2(Vector2(cell) * 10.0, Vector2(10.0, 10.0))
	var runs := [
		_in_cell(_rows(doc, rule, alone, box.grow(3.0)), cell),
		_in_cell(_rows(doc, rule, neighbours, box.grow(13.0)), cell),
		_in_cell(_rows(doc, rule, everything, Rect2()), cell),
	]
	assert_gt(_points(runs[0]).size(), 100, "the cell holds plants")
	assert_eq(runs[1], runs[0], "with its neighbours and a wider window")
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


func test_the_distance_does_not_depend_on_any_window() -> void:
	var doc := _lake_document(Vector2i(16, 16), LAKE_CENTRE, LAKE_RADIUS)
	var whole := ScatterGenerator.document_fields(doc, "herbs")
	var cropped := ScatterGenerator.document_fields(doc, "herbs", Rect2(6.0, 6.0, 4.0, 4.0))
	for p: Vector2 in [Vector2(8.0, 8.0), Vector2(-5.0, 1.0), Vector2(-11.0, -11.0)]:
		assert_eq(float(cropped.water_dist_at.call(p)), float(whole.water_dist_at.call(p)))
