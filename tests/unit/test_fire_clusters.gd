extends GutTest

## FireClusters (where the persistent fire's lights and smoke stand; card F4b-1): clusters are
## deterministic whatever order the blocks were planned in, the four largest take the lights
## with ties in row order, a cluster keeps its light across a re-plan, the smoke rises over the
## blaze only and over at most eight, re-planning one block leaves far clusters exactly as they
## were; the lights' gate follows the sun; each smoke column spreads its billows over a life
## with no gap, and the biggest fire raises the biggest column, taller than it is wide.

var _sun := Vector4.ZERO


func before_each() -> void:
	_sun = FoliageLight.last_sun


func after_each() -> void:
	FoliageLight.last_sun = _sun


## A flat 40-cell map (about 61 m) burning in discs of `radius` metres at `centres` with mask
## byte `heat`.
func _doc(centres: Array, radius: float, heat: int = 255) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	var half := doc.extent_m() * 0.5
	var step := doc.sample_step()
	for iz in doc.samples_z():
		for ix in doc.samples_x():
			var p := -half + Vector2(ix, iz) * step
			for centre: Vector2 in centres:
				if p.distance_to(centre) <= radius:
					mask[doc.sample_index(ix, iz)] = heat
	doc.fire_mask = mask
	return doc


## Each burning block's cells, the blocks in the order `reverse` picks.
func _cells_by_block(doc: MapDocument, reverse := false) -> Dictionary:
	var blocks := FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	if reverse:
		blocks.reverse()
	var out := {}
	for block in blocks:
		var plan := FireField.plan_block(doc, block)
		if not plan.is_empty():
			out[block] = FireClusters.cells_of(plan)
	return out


## One grid cell's sums for flames of total height `size` at the cell's middle (the blaze's
## too when `blaze`).
func _cell(cell: Vector2i, size: float, blaze := false) -> PackedFloat64Array:
	var sums := PackedFloat64Array()
	sums.resize(FireClusters.FIELDS)
	var at := (Vector2(cell) + Vector2(0.5, 0.5)) * FireClusters.CELL_M
	var offsets := [0, FireClusters.BLAZE] if blaze else [0]
	for o: int in offsets:
		sums[o + FireClusters.SIZE] = size
		sums[o + 1] = at.x * size
		sums[o + 3] = at.y * size
		sums[o + FireClusters.TOP] = 1.0
	return sums


func test_clusters_are_deterministic_whatever_order_blocks_were_planned() -> void:
	var doc := _doc([Vector2(-6.0, -4.0), Vector2(9.0, 7.0)], 5.0)
	var cells := FireClusters.merge(_cells_by_block(doc))
	var found := FireClusters.find(cells, false)
	assert_gt(found.size(), 1, "two fires, more than one cluster")
	assert_eq(FireClusters.find(FireClusters.merge(_cells_by_block(doc)), false), found)
	var reversed := FireClusters.merge(_cells_by_block(doc, true))
	assert_eq(FireClusters.find(reversed, false), found, "the same clusters, to the bit")
	assert_eq(FireClusters.find(reversed, true), FireClusters.find(cells, true))
	for k in found.size() - 1:
		assert_gte(float(found[k]["size"]), float(found[k + 1]["size"]), "largest first")


func test_the_four_largest_take_the_lights_ties_in_row_order() -> void:
	var cells := {}
	var sizes := [5.0, 9.0, 9.0, 3.0, 7.0, 1.0]
	var at: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(8, 4), Vector2i(4, 4), Vector2i(0, 8), Vector2i(8, 8), Vector2i(4, 0)
	]
	for k in sizes.size():
		cells[at[k]] = _cell(at[k], sizes[k])
	var lit := FireClusters.lights(cells)
	assert_eq(lit.size(), FireClusters.MAX_LIGHTS)
	var picked: Array[Vector2i] = []
	for cluster in lit:
		picked.append(cluster["cell"])
	var expected: Array[Vector2i] = [Vector2i(4, 4), Vector2i(8, 4), Vector2i(8, 8), Vector2i(0, 0)]
	assert_eq(picked, expected, "the four largest, the tie in row order")
	var middle := (Vector2(4, 4) + Vector2(0.5, 0.5)) * FireClusters.CELL_M
	assert_almost_eq(lit[0]["at"].x, middle.x, 0.001, "at the flames' centroid")
	assert_almost_eq(lit[0]["at"].z, middle.y, 0.001)


func test_a_hot_spot_tops_its_neighbours_and_a_lit_cluster_keeps_its_light() -> void:
	var cells := {}
	cells[Vector2i(0, 0)] = _cell(Vector2i(0, 0), 2.0)
	cells[Vector2i(1, 0)] = _cell(Vector2i(1, 0), 6.0)
	cells[Vector2i(2, 0)] = _cell(Vector2i(2, 0), 3.0)
	var found := FireClusters.find(cells, false)
	assert_eq(found.size(), 1, "one hot spot for three touching cells")
	assert_eq(found[0]["cell"], Vector2i(1, 0))
	assert_almost_eq(float(found[0]["size"]), 11.0, 0.0001, "its size sums its neighbours")
	var none := FireLights.NONE
	var previous: Array[Vector2i] = [Vector2i(5, 5), Vector2i(1, 1), none, Vector2i(9, 9)]
	var wanted: Array[Vector2i] = [Vector2i(7, 7), Vector2i(1, 1), Vector2i(5, 5)]
	var slots := FireClusters.keep_slots(previous, wanted)
	assert_eq(slots, PackedInt32Array([2, 1, 0, -1]), "kept where shown, the new one in a free slot")


func test_the_smoke_rises_over_the_blaze_only_and_at_most_eight() -> void:
	var flames := _doc([Vector2(0.0, 0.0)], 8.0, 160)
	var cells := FireClusters.merge(_cells_by_block(flames))
	assert_gt(FireClusters.lights(cells).size(), 0, "the flames band is lit")
	assert_eq(FireClusters.smoke(cells).size(), 0, "and raises no smoke")
	var blaze := _doc([Vector2(0.0, 0.0)], 8.0, 255)
	var smoky := FireClusters.smoke(FireClusters.merge(_cells_by_block(blaze)))
	assert_gt(smoky.size(), 0, "a blaze smokes")
	var many := {}
	for k in 12:
		var cell := Vector2i((k % 4) * 4, floori(k / 4.0) * 4)
		many[cell] = _cell(cell, 5.0 + k, true)
	many[Vector2i(40, 40)] = _cell(Vector2i(40, 40), 30.0)
	var capped := FireClusters.smoke(many)
	assert_eq(capped.size(), FireClusters.MAX_SMOKE)
	assert_eq(float(capped[0]["size"]), 16.0, "the largest blaze first, the bigger flames not")
	for cluster in capped:
		assert_gte(float(cluster["blaze"]), FireClusters.SMOKE_MIN_SIZE)
	# The biggest fire is the biggest smoker: ranked by all its flames, not by its blaze alone.
	var mixed := {}
	mixed[Vector2i(0, 0)] = _cell(Vector2i(0, 0), 40.0)
	mixed[Vector2i(1, 0)] = _cell(Vector2i(1, 0), 10.0, true)
	mixed[Vector2i(10, 0)] = _cell(Vector2i(10, 0), 20.0, true)
	var ranked := FireClusters.smoke(mixed)
	assert_eq(ranked.size(), 2)
	assert_eq(ranked[0]["cell"], Vector2i(0, 0), "the big fire with a blaze in it first")
	assert_eq(float(ranked[0]["size"]), 50.0)


func test_a_replan_of_one_block_leaves_far_clusters_alone() -> void:
	var doc := _doc([Vector2(-18.0, -18.0), Vector2(18.0, 18.0)], 7.0)
	var per_block := _cells_by_block(doc)
	var before := FireClusters.find(FireClusters.merge(per_block), false)
	# Put out part of the first fire and re-plan only the block that holds its middle.
	var half := doc.extent_m() * 0.5
	var step := doc.sample_step()
	var centre := (Vector2(-18.0, -18.0) + half) / step
	var block := Vector2i(centre) / MaskStroke.BLOCK
	var rect := MaskStroke.block_rect(doc, block)
	for iz in range(rect.position.y, rect.end.y):
		for ix in range(rect.position.x, rect.end.x):
			if ix % 3 != 0:
				doc.fire_mask[doc.sample_index(ix, iz)] = 0
	per_block[block] = FireClusters.cells_of(FireField.plan_block(doc, block))
	var after := FireClusters.find(FireClusters.merge(per_block), false)
	assert_ne(after, before, "the re-planned fire changed")
	var far := 0
	for cluster in before:
		var at: Vector3 = cluster["at"]
		if Vector2(at.x, at.z).distance_to(Vector2(-18.0, -18.0)) < 25.0:
			continue
		far += 1
		assert_has(after, cluster, "a far cluster is exactly as it was")
	assert_gt(far, 0, "the far fire has clusters")


func test_the_lights_show_only_while_the_sun_is_low() -> void:
	var sun := DirectionalLight3D.new()
	autofree(sun)
	var gates := PackedFloat32Array()
	for hour in [12.0, 14.0, 16.0, 17.0, 18.0, 19.0, 23.0]:
		DefaultSun.apply(sun, DefaultSun.settings_for_time(hour))
		gates.append(FireLook.light_gate(FoliageLight.sun_value(sun)))
	assert_eq(gates[1], 0.0, "off by day")
	assert_eq(gates[5], 1.0, "full at dusk")
	assert_eq(gates[6], 1.0, "and at night")
	for k in 6:
		assert_lte(gates[k], gates[k + 1], "fading in as the sun sinks")
	assert_eq(FireLook.light_gate(FoliageLight.NO_SUN), 1.0, "and with no sun")
	for t in [0.0, 0.7, 1.9, 5.3, 11.0]:
		for slot in 4:
			var f := FireLook.flicker(t, slot)
			assert_between(f, 1.0 - FireLook.FLICKER_DEPTH - 0.0001, 1.0001)
	var field := FireField.create(_doc([Vector2(0.0, 0.0)], 6.0))
	add_child_autofree(field)
	var lights := field.lights()
	assert_not_null(lights, "a fire stands lights")
	assert_between(lights.count(), 1, FireClusters.MAX_LIGHTS)
	DefaultSun.apply(sun, DefaultSun.settings_for_time(14.0))
	FoliageLight.last_sun = FoliageLight.sun_value(sun)
	lights._process(0.1)
	for light in lights.lights():
		assert_false(light.visible, "hidden by day")
	DefaultSun.apply(sun, DefaultSun.settings_for_time(19.0))
	FoliageLight.last_sun = FoliageLight.sun_value(sun)
	lights._process(0.1)
	var shown := 0
	for light in lights.lights():
		if light.visible:
			shown += 1
			assert_gt(light.light_energy, 0.0)
			assert_false(light.shadow_enabled)
			assert_eq(light.omni_range, FireLights.RANGE_M)
	assert_eq(shown, lights.count(), "every placed light shows at dusk")


func test_the_fire_lights_are_not_the_maps_own() -> void:
	# Counted as the map's lights, they would turn the level's sun off in "auto" mode.
	var map := Node3D.new()
	add_child_autofree(map)
	var field := FireField.create(_doc([Vector2(0.0, 0.0)], 6.0))
	map.add_child(field)
	assert_gt(field.lights().count(), 0)
	var environment := LevelEnvironmentManager.new()
	environment.store_original_light_energies(map)
	assert_eq(environment.get("_original_light_energies").size(), 0)


func test_each_smoke_column_spreads_its_billows_over_a_life() -> void:
	var smoke := FireFieldSmoke.new()
	autofree(smoke)
	assert_eq(smoke.multimesh.instance_count, FireFieldSmoke.capacity())
	var sites: Array[Dictionary] = []
	for k in 3:
		sites.append(
			{"cell": Vector2i(k * 3, 0), "size": 60.0 - k * 20.0, "at": Vector3(k * 8, 0, 0), "top": 3.0}
		)
	smoke.place(sites)
	assert_eq(smoke.live_count(), 3 * FireFieldSmoke.PER_SITE, "a column of billows per site")
	# The headless renderer keeps no MultiMesh data to read back, so the pure buffer is read.
	var buffer := FireFieldSmoke.instance_buffer(sites)
	assert_eq(buffer.size(), FireFieldSmoke.capacity() * FireLook.INSTANCE_FLOATS)
	for site in sites.size():
		var phases: Array[float] = []
		for k in FireFieldSmoke.PER_SITE:
			var i := (site * FireFieldSmoke.PER_SITE + k) * FireLook.INSTANCE_FLOATS
			var born := Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11])
			assert_almost_eq(born, FireFieldSmoke.source(sites[site]), Vector3.ONE * 1e-4)
			assert_almost_eq(buffer[i], FireFieldSmoke.column_unit(sites[site]), 1e-4)
			assert_between(buffer[i + 14], 10.0, 14.0, "a slow climb of about 12 s")
			phases.append(buffer[i + 12])
		phases.sort()
		phases.append(phases[0] + 1.0)
		for k in FireFieldSmoke.PER_SITE:
			assert_lt(phases[k + 1] - phases[k], 2.0 / FireFieldSmoke.PER_SITE, "no gap in the column")
	var unused := 3 * FireFieldSmoke.PER_SITE * FireLook.INSTANCE_FLOATS
	assert_eq(buffer[unused], 0.0, "the rest of the pool stays empty")
	smoke.place([] as Array[Dictionary])
	assert_eq(smoke.live_count(), 0)


func test_the_biggest_fire_raises_the_biggest_column_taller_than_wide() -> void:
	var big := {"cell": Vector2i.ZERO, "size": 80.0, "at": Vector3.ZERO, "top": 3.2}
	var small := {"cell": Vector2i(4, 0), "size": 9.0, "at": Vector3(14, 0, 0), "top": 2.4}
	assert_gt(FireFieldSmoke.column_unit(big), FireFieldSmoke.column_unit(small))
	for cluster: Dictionary in [big, small]:
		var extent := FireFieldSmoke.column_extent(cluster)
		assert_gt(extent.x, extent.y * 1.5, "a column, not a squat puff")
		assert_between(
			FireFieldSmoke.source(cluster).y + extent.x,
			2.0 * float(cluster["top"]),
			3.2 * float(cluster["top"]),
			"up to two or three flame heights"
		)
	var box := FireFieldSmoke.bounds([big, small] as Array[Dictionary])
	assert_true(box.has_point(FireFieldSmoke.source(small)))
	assert_gt(box.end.y, FireFieldSmoke.source(big).y + FireFieldSmoke.column_extent(big).x)
