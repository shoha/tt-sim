extends GutTest

## FireField's placement (pure plan_block, FireFires' fires; test_fire_fires has their own
## rules): deterministic, each fire in one block only, nothing below the ember band, nothing on
## wet or steep ground, heights from the document's triangles, no flames in the ember band; its
## trigonometry held in literals; the bands; the budget shared in proportion past the cap; the
## LOD half; the warm-up covering the fire's shaders; the ground bakes' frames and redraw region;
## a re-plan on a worker landing what the main thread plans; and a refresh by dabs landing
## exactly what a rebuild plans (plan_digest and the rasters' bytes).


func _doc(cells: int = 20, heat: int = 255) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(cells, cells), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	mask.fill(heat)
	doc.fire_mask = mask
	return doc


## Every planned entry of the whole map of `doc`.
func _whole(doc: MapDocument) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for block in FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z())):
		out.append_array(FireField.plan_block(doc, block))
	return out


func _lattice_points(doc: MapDocument) -> float:
	return doc.extent_m().x * doc.extent_m().y / pow(FireField.FLAME_SPACING_M, 2)


## Sets the mask to `value` over the disc of `radius` metres round document point `at` (a hard
## dab); returns the samples' rect it covers.
func _dab(doc: MapDocument, at: Vector2, radius: float, value: int) -> Rect2i:
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var lo := Vector2i(((at - Vector2.ONE * radius + half) / step).floor())
	var hi := Vector2i(((at + Vector2.ONE * radius + half) / step).ceil()) + Vector2i.ONE
	var rect := Rect2i(lo, hi - lo).intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	var mask := doc.fire_mask.duplicate()
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var p := Vector2(x, z) * step - half
			if p.distance_to(at) <= radius:
				mask[doc.sample_index(x, z)] = value
	doc.fire_mask = mask
	return rect


func test_the_plan_is_deterministic_and_burns_where_painted() -> void:
	var doc := _doc()
	var plan := FireField.plan_block(doc, Vector2i(1, 1))
	assert_gt(plan.size(), 0)
	assert_eq(plan.size() % FireField.STRIDE, 0)
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)), plan, "the same plan every time")
	var other := _doc()
	other.map_seed = 6
	assert_ne(FireField.plan_block(other, Vector2i(1, 1)), plan, "another seed, another plan")
	for k in plan.size() / FireField.STRIDE:
		assert_almost_eq(plan[k * FireField.STRIDE + 3], 1.0, 0.001, "full intensity")


func test_blocks_share_no_flame() -> void:
	var doc := _doc()
	var seen := {}
	var total := 0
	for block in FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z())):
		var plan := FireField.plan_block(doc, block)
		for k in plan.size() / FireField.STRIDE:
			var key := Vector2(plan[k * FireField.STRIDE], plan[k * FireField.STRIDE + 2])
			assert_false(seen.has(key), "a flame belongs to one block")
			seen[key] = true
			total += 1
	# A blaze everywhere: most lattice points stand, the clumps' gaps open the rest.
	var expected := _lattice_points(doc)
	assert_lt(float(total), expected * 1.05)
	assert_gt(float(total), expected * 0.6)


func test_nothing_burns_below_the_ember_band_or_without_a_mask() -> void:
	assert_eq(FireField.plan_block(_doc(20, FireField.EMBER_MIN - 1), Vector2i(1, 1)).size(), 0)
	assert_gt(FireField.plan_block(_doc(20, FireField.EMBER_MIN), Vector2i(1, 1)).size(), 0)
	var doc := _doc()
	doc.fire_mask = PackedByteArray()
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0)


func test_wet_ground_does_not_burn() -> void:
	var doc := _doc()
	var dressing := PackedByteArray()
	dressing.resize(doc.sample_count() * 4)
	for i in doc.sample_count():
		dressing[i * 4 + 3] = 255
	doc.water_dressing = dressing
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0)
	for i in doc.sample_count():
		dressing[i * 4 + 3] = FireField.WET_LINE_MIN - 1
	doc.water_dressing = dressing
	assert_gt(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0, "a damp shore still burns")


func test_steep_ground_does_not_burn_and_flames_stand_on_the_ground() -> void:
	var doc := _doc()
	var step := doc.sample_step().x
	var steep := doc.heights.duplicate()
	var gentle := doc.heights.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			steep[doc.sample_index(x, z)] = x * step * 2.0
			gentle[doc.sample_index(x, z)] = x * step * 0.2
	doc.heights = steep
	assert_eq(FireField.plan_block(doc, Vector2i(1, 1)).size(), 0, "a 63 degree face")
	doc.heights = gentle
	var plan := FireField.plan_block(doc, Vector2i(1, 1))
	assert_gt(plan.size(), 0, "an 11 degree slope burns")
	var half := doc.extent_m().x * 0.5
	for k in plan.size() / FireField.STRIDE:
		var x := plan[k * FireField.STRIDE]
		var y := plan[k * FireField.STRIDE + 1]
		assert_almost_eq(y, (x + half) * 0.2, 0.01, "on the ground")


func test_the_ember_band_draws_no_flames_only_sparks() -> void:
	var doc := _doc(30, 80)
	var plan := _whole(doc)
	var sparks := plan.size() / FireField.STRIDE
	assert_gt(sparks, 0, "a few sparks")
	assert_lt(float(sparks), _lattice_points(doc) / FireField.SPARK_EVERY * 1.3, "sparse")
	for k in sparks:
		assert_eq(plan[k * FireField.STRIDE + FireField.KIND], FireField.SPARK, "no flame")


func test_the_plans_trigonometry_is_held_in_literals() -> void:
	var tolerance := Vector2.ONE * 1e-6
	var turn := FireField.CLUMP_TURN
	assert_almost_eq(FireField.CLUMP_TURN_A, Vector2(cos(turn.x), sin(turn.x)), tolerance)
	assert_almost_eq(FireField.CLUMP_TURN_B, Vector2(cos(turn.y), sin(turn.y)), tolerance)
	var p := Vector2(3.7, -11.2)
	assert_almost_eq(FireField._turn(p, FireField.CLUMP_TURN_A), p.rotated(turn.x), tolerance * 20)
	var flat := cos(deg_to_rad(FireField.STEEP_DEG))
	assert_almost_eq(FireField.STEEP_NORMAL_Y, flat, 1e-9, "the cliff rule's cosine")


func test_bands() -> void:
	assert_eq(FireField.band(0), 0)
	assert_eq(FireField.band(FireField.EMBER_MIN - 1), 0)
	assert_eq(FireField.band(FireField.EMBER_MIN), 1)
	assert_eq(FireField.band(FireBrush.EMBERS), 1, "the Embers tile is embers")
	assert_eq(FireField.band(FireBrush.FLAMES), 2, "the Flames tile is flames")
	assert_eq(FireField.band(FireBrush.BLAZE), 3, "the Blaze tile is a blaze")
	assert_eq(FireField.base_height(FireBrush.EMBERS / 255.0), 0.0, "embers stand no flame")
	assert_lt(FireField.base_height(FireBrush.FLAMES / 255.0), FireField.base_height(1.0))


func test_thin_keeps_the_shuffled_prefix() -> void:
	var plan := PackedFloat32Array()
	for k in 10:
		plan.append_array([k, 0, 0, 1, 0, 1, 0.5, 0])
	var kept := FireField.thin(plan, 5)
	assert_eq(kept.size(), 5 * FireField.STRIDE)
	assert_eq(kept, plan.slice(0, 5 * FireField.STRIDE))
	assert_eq(FireField.thin(plan, 20), plan)


func test_budget_shares_are_proportional() -> void:
	var under := FireField.budget_shares({Vector2i(0, 0): 10, Vector2i(1, 0): 20}, 100)
	assert_eq(under, {Vector2i(0, 0): 10, Vector2i(1, 0): 20}, "all of each under the cap")
	var over := FireField.budget_shares({Vector2i(0, 0): 100, Vector2i(1, 0): 300}, 200)
	assert_eq(over, {Vector2i(0, 0): 50, Vector2i(1, 0): 150}, "the same fraction of each")
	var ties := FireField.budget_shares(
		{Vector2i(0, 1): 1, Vector2i(1, 0): 1, Vector2i(0, 0): 1}, 2
	)
	assert_eq(ties, {Vector2i(0, 1): 0, Vector2i(1, 0): 1, Vector2i(0, 0): 1}, "row order")


func test_a_fire_past_the_cap_fills_every_block_evenly() -> void:
	var doc := _doc(48)
	var field := FireField.create(doc)
	add_child_autofree(field)
	var planned := 0
	for block in field._plans:
		planned += (field._plans[block] as PackedFloat32Array).size() / FireField.STRIDE
	assert_gt(planned, FireField.MAX_FLAMES, "a whole 48-cell map past the cap")
	assert_eq(field.flame_count(), FireField.MAX_FLAMES, "exactly the cap")
	var ratio := float(FireField.MAX_FLAMES) / planned
	for block in field._plans:
		var own := (field._plans[block] as PackedFloat32Array).size() / FireField.STRIDE
		assert_almost_eq(float(field._counts.get(block, 0)), own * ratio, 1.0, str(block))
	var mask := doc.fire_mask.duplicate()
	mask.fill(0)
	doc.fire_mask = mask
	field.rebuild()
	assert_eq(field.flame_count(), 0)
	var chunks := 0
	for child in field.get_children():
		chunks += 1 if child.name.begins_with("Fire_") else 0
	assert_eq(chunks, 0, "no chunk without fire")
	assert_eq(field.lights().count(), 0, "no light without fire")
	assert_eq(field.smoke().site_count(), 0, "no smoke without fire")


func test_the_heat_raster_sums_flames_into_one_bed() -> void:
	var doc := _doc(20, 150)
	var size := FireField.heat_size(doc)
	var half := doc.extent_m() * 0.5
	var whole := Rect2i(Vector2i.ZERO, size)
	var heat := PackedFloat32Array()
	heat.resize(size.x * size.y)
	var one := PackedFloat32Array([0, 0, 0, 0.6, 0.5, 1.0, 0.5, FireField.FLAME])
	FireField.splat_heat(heat, size, half, one, whole)
	var lone := FireField.heat_at(heat, size, half, Vector2.ZERO)
	# Read between texels, so a little under the kernel's peak.
	assert_almost_eq(lone, 1.0 / FireField.HEAT_FULL_M, 0.035, "a lone flame: its height")
	FireField.splat_heat(heat, size, half, one, whole)
	var both := FireField.heat_at(heat, size, half, Vector2.ZERO)
	assert_almost_eq(both, 2.0 * lone, 0.001, "two overlapping flames: twice as hot")
	var far := half * 0.6
	assert_eq(FireField.heat_at(heat, size, half, far), 0.0, "nothing past the kernel")
	var spark := PackedFloat32Array([far.x, 0, far.y, 0.2, 0.5, 0.16, 0.16, FireField.SPARK])
	FireField.splat_heat(heat, size, half, spark, whole)
	assert_eq(FireField.heat_at(heat, size, half, far), 0.0, "a spark adds no heat")
	var shown := FireLook.instance_buffer(one, 1, Vector3.FORWARD, PackedFloat32Array([0.5]))
	assert_almost_eq(fmod(shown[14], 1.0), 0.5 * FireLook.FOOT_SHARE, 0.001, "the foot's heat")
	assert_eq(floori(shown[14]), int(FireField.FLAME), "the kind")


func test_every_foot_stands_in_a_pool_narrower_than_its_heat() -> void:
	var doc := _doc(20, 150)
	var size := FireField.heat_size(doc)
	var half := doc.extent_m() * 0.5
	var whole := Rect2i(Vector2i.ZERO, size)
	var heat := PackedFloat32Array()
	heat.resize(size.x * size.y)
	var pools := PackedFloat32Array()
	pools.resize(size.x * size.y)
	# A tall flame and a small one, each on a texel.
	var foot := Vector2i((half / FireField.HEAT_STEP_M).round())
	var o := Vector2(foot) * FireField.HEAT_STEP_M - half
	var tall := PackedFloat32Array([o.x, 0, o.y, 0.9, 0.5, 2.0, 0.5, FireField.FLAME])
	var small := PackedFloat32Array([o.x + 4.0, 0, o.y, 0.5, 0.5, 0.4, 0.5, FireField.FLAME])
	FireField.splat_heat(heat, size, half, tall, whole, pools)
	FireField.splat_heat(heat, size, half, small, whole, pools)
	var at := func(p: Vector2) -> int:
		var t := Vector2i(((p + half) / FireField.HEAT_STEP_M).round())
		return t.y * size.x + t.x
	assert_almost_eq(pools[at.call(o)], 1.0, 0.001, "a tall flame's foot: a full pool")
	assert_almost_eq(pools[at.call(o + Vector2(4.0, 0.0))], 1.0, 0.001, "a small one's too")
	var out := o + Vector2(1.0, 0.0)
	assert_eq(pools[at.call(out)], 0.0, "the pool ends before the heat does")
	assert_gt(heat[at.call(out)], 0.0)
	var texture := FireLook.heat_texture(heat, size, FireField.HEAT_FULL_M, null, pools)
	var image := texture.get_image()
	assert_eq(image.get_format(), Image.FORMAT_RG8, "heat red, pools green")
	assert_almost_eq(image.get_pixelv(foot).g, 1.0, 0.01)


func test_a_straight_pass_stands_its_flames_off_its_axis() -> void:
	var doc := _doc(30, 0)
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var mask := doc.fire_mask.duplicate()
	for z in doc.samples_z():
		var zm := -half.y + z * step.y
		for x in doc.samples_x():
			mask[doc.sample_index(x, z)] = 150 if absf(zm) < 1.5 else 0
	doc.fire_mask = mask
	var plan := _whole(doc)
	var reach := 0.0
	for k in plan.size() / FireField.STRIDE:
		if plan[k * FireField.STRIDE + FireField.KIND] == FireField.FLAME:
			reach = maxf(reach, absf(plan[k * FireField.STRIDE + 2]))
	assert_gt(plan.size(), 0)
	# Read straight, the band's flames stand within a sample step of its edge; the warp carries
	# them further, at most PLACE_WARP.y.
	assert_gt(reach, 1.5 + step.y + 0.3, "the band wanders")
	assert_lt(reach, 1.5 + step.y + FireField.PLACE_WARP.y + 0.1, "but stays near its stroke")


func test_lod_keeps_half_and_draws_back_to_front() -> void:
	assert_eq(FireLook.far_count(7), 4)
	assert_eq(FireLook.far_count(8), 4)
	var plan := FireField.plan_block(_doc(), Vector2i(1, 1))
	var count := plan.size() / FireField.STRIDE
	var forward := FireLook.DEFAULT_FORWARD.normalized()
	var buffer := FireLook.instance_buffer(plan, count, forward)
	assert_eq(buffer.size(), count * FireLook.INSTANCE_FLOATS)
	var kept := 0
	var last := INF
	for slot in count:
		var i := slot * FireLook.INSTANCE_FLOATS
		kept += int(buffer[i + 15])
		var depth := Vector3(buffer[i + 3], buffer[i + 7], buffer[i + 11]).dot(forward)
		assert_lte(depth, last + 0.0001, "the far flames first")
		last = depth
	assert_eq(kept, FireLook.far_count(count), "half show past the LOD zoom")


func test_the_warmup_covers_the_fire_shaders() -> void:
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/fire_field.gdshader")
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/fire_field_smoke.gdshader")
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/fire_glow_bake.gdshader")
	assert_has(GraphicsWarmup.COVERED_SHADERS, "res://shaders/fire_ground_bake.gdshader")
	var sources := "\n".join(GraphicsWarmup.shader_sources())
	assert_true(sources.contains("res://shaders/fire_glow.gdshaderinc\n"), "the ground's glow")


func test_the_ground_bakes_cover_the_map_at_their_spacing() -> void:
	var extent := Vector2(60.96, 45.0)
	var size := FireNoiseBake.tile_size(extent, 8.0)
	var span := extent + Vector2.ONE * FireNoiseBake.MARGIN_M * 2.0
	assert_eq(size, Vector2i(ceili(span.x * 8.0), ceili(span.y * 8.0)), "8 texels a metre")
	var rect := FireNoiseBake.rect_for(extent, 8.0)
	assert_almost_eq(rect.z, size.x / 8.0, 1e-4, "whole texels")
	assert_almost_eq(rect.x, -rect.z * 0.5, 1e-4, "centred on the map")
	assert_lte(rect.x, -span.x * 0.5 + 1e-4, "the map and its margin inside")
	assert_lte(rect.y, -span.y * 0.5 + 1e-4)
	var fine := FireNoiseBake.rect_for(extent, FireNoiseBake.FINE_PER_M)
	var fine_px := FireNoiseBake.tile_size(extent, FireNoiseBake.FINE_PER_M)
	assert_almost_eq(fine.z, fine_px.x / FireNoiseBake.FINE_PER_M, 1e-4, "the fine bake too")
	var big := Vector2(400.0, 300.0)
	assert_eq(FireNoiseBake.tile_size(big, 8.0), Vector2i(FireNoiseBake.MAX_PX, FireNoiseBake.MAX_PX))
	var big_rect := FireNoiseBake.rect_for(big, 8.0)
	assert_almost_eq(big_rect.z, 402.0, 1e-4, "a coarser bake over the same span")
	assert_almost_eq(big_rect.w, 302.0, 1e-4)


func test_a_refresh_redraws_the_bake_only_where_it_reaches() -> void:
	var doc := _doc(20)
	var blocks: Array[Vector2i] = [Vector2i(1, 1)]
	var region := FireField.bake_region(doc, blocks)
	var r := MaskStroke.block_rect(doc, Vector2i(1, 1))
	var step := doc.sample_step()
	var low := -doc.extent_m() * 0.5 + Vector2(r.position) * step
	assert_almost_eq(region.position.x, low.x - FireField.BAKE_REACH_M, 1e-4, "the block, grown")
	assert_almost_eq(region.size.x, r.size.x * step.x + FireField.BAKE_REACH_M * 2.0, 1e-4)
	var frame := FireNoiseBake.rect_for(doc.extent_m(), 8.0)
	var size := FireNoiseBake.tile_size(doc.extent_m(), 8.0)
	var box := FireNoiseBake.texels_of(region, frame, size)
	assert_true(box.has_area())
	assert_true(Rect2i(Vector2i.ZERO, size).encloses(box), "within the tile")
	var expect := Vector2i(((region.position - Vector2(frame.x, frame.y)) * 8.0).floor())
	assert_eq(box.position, expect.max(Vector2i.ZERO), "whole texels from the frame's corner")
	var everything := FireNoiseBake.texels_of(Rect2(-1000, -1000, 2000, 2000), frame, size)
	assert_eq(everything, Rect2i(Vector2i.ZERO, size), "clipped to the tile")


func test_a_worker_refresh_plans_what_the_main_thread_does() -> void:
	var doc := _doc(20, 0)
	var at_once := FireField.create(doc)
	add_child_autofree(at_once)
	var threaded := FireField.create(doc)
	threaded.use_worker = true
	add_child_autofree(threaded)
	var mask := doc.fire_mask.duplicate()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	@warning_ignore("integer_division")
	var dab := Rect2i(columns / 5, rows / 4, columns / 2, rows / 2)
	for z in range(dab.position.y, dab.end.y):
		for x in range(dab.position.x, dab.end.x):
			mask[doc.sample_index(x, z)] = 230
	doc.fire_mask = mask
	threaded.refresh(dab)
	assert_true(threaded.is_working(), "the re-plan runs on a worker")
	threaded.refresh(Rect2i(dab.position + Vector2i(2, 2), Vector2i(4, 4)))
	threaded.finish_work()
	assert_false(threaded.is_working(), "a refresh asked for meanwhile lands too")
	at_once.refresh(dab)
	assert_gt(at_once.flame_count(), 0, "a fire burns")
	assert_eq(threaded.flame_count(), at_once.flame_count(), "the same flames")
	assert_eq(threaded._plans, at_once._plans, "the same plans")
	assert_eq(threaded._heat, at_once._heat, "the same rasters")
	assert_eq(threaded._pools, at_once._pools)
	assert_eq(threaded._cells, at_once._cells, "the same cluster sums")
	assert_eq(threaded.plan_digest(), at_once.plan_digest(), "the same digest")


func test_a_refresh_lands_exactly_what_a_rebuild_plans() -> void:
	var doc := _doc(30, 0)
	var half := doc.extent_m() * 0.5
	var block_m := MaskStroke.BLOCK * doc.sample_step().x
	# Block lines (metres) near the middle of the map.
	var a := -half.x + block_m * 2.0
	var b := a + block_m
	# A strong flames band over most of the map (big fires), a blaze across a block line.
	_dab(doc, Vector2.ZERO, 17.0, 190)
	_dab(doc, Vector2(a, b - 4.0), 3.0, 235)
	var field := FireField.create(doc)
	add_child_autofree(field)
	var tallest := 0.0
	for block in field._plans:
		var plan: PackedFloat32Array = field._plans[block]
		for k in plan.size() / FireField.STRIDE:
			tallest = maxf(tallest, plan[k * FireField.STRIDE + FireField.HEIGHT])
	assert_gt(tallest, 2.9, "big fires beside the dabs")
	# [centre, radius, mask value]: inside a block, on a block line, across a corner, putting
	# out the edge of a big fire across a line, a blaze across a line, a weak flame's corner;
	# then small dabs about 3 m short of a block line, whose fires' neighbourhoods reach across.
	var dabs := [
		[Vector2((a + b) * 0.5, (a + b) * 0.5), 2.0, 0],
		[Vector2(a, (a + b) * 0.5 + 1.0), 2.0, 199],
		[Vector2(b, b), 2.5, 120],
		[Vector2(b + 0.6, a - 3.0), 1.5, 0],
		[Vector2(b, a + 2.0), 2.0, 240],
		[Vector2(a - 0.3, a - 0.2), 1.0, 150],
		[Vector2(a + 4.3, -6.0), 1.2, 0],
		[Vector2(a + 4.3, 1.0), 1.2, 199],
		[Vector2(b - 4.4, b - 5.0), 1.0, 0],
		[Vector2(-3.0, a + 4.2), 1.3, 120],
	]
	for dab: Array in dabs:
		var label := "dab at %s r %.1f to %d" % [str(dab[0]), dab[1], dab[2]]
		field.refresh(_dab(doc, dab[0], dab[1], dab[2]))
		var fresh: FireField = autofree(FireField.create(doc))
		assert_eq(field.plan_digest(), fresh.plan_digest(), label)
		assert_eq(field._plans.size(), fresh._plans.size(), label + ": the burning blocks")
		for block in fresh._plans:
			assert_eq(field._plans.get(block), fresh._plans[block], label + ": " + str(block))
		assert_eq(field._heat.to_byte_array(), fresh._heat.to_byte_array(), label + ": heat")
		assert_eq(field._pools.to_byte_array(), fresh._pools.to_byte_array(), label + ": pools")
		assert_eq(field._counts, fresh._counts, label + ": the shown flames")
		for block in fresh._chunks:
			var mine := (field._chunks[block] as MultiMeshInstance3D).multimesh.buffer
			var theirs := (fresh._chunks[block] as MultiMeshInstance3D).multimesh.buffer
			assert_eq(theirs.size(), int(fresh._counts[block]) * FireLook.INSTANCE_FLOATS)
			assert_eq(mine, theirs, label + ": the drawn flames of " + str(block))
