extends GutTest

## FireField's placement (pure plan_block): deterministic, each lattice point in one block
## only, nothing below the ember band, nothing on wet or steep ground, heights from the
## document's triangles; the look card's clumps (scale range, gaps, a blaze's big flames and
## licks, no flames in the ember band); the bands; the budget shared in proportion past the
## cap; the LOD half; and the warm-up covering the fire's shaders.


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


## Each flame's height over its band's base height (its clump, big or lick scale).
func _scales(plan: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in plan.size() / FireField.STRIDE:
		var o := k * FireField.STRIDE
		if plan[o + FireField.KIND] == FireField.FLAME:
			var base := FireField.base_height(plan[o + FireField.INTENSITY])
			out.append(plan[o + FireField.HEIGHT] / base)
	return out


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


func test_clumps_scale_the_flames_and_leave_gaps() -> void:
	var doc := _doc(30, 150)
	var plan := _whole(doc)
	var scales := _scales(plan)
	assert_eq(scales.size() * FireField.STRIDE, plan.size(), "a flames band has no sparks")
	var low := 99.0
	var high := 0.0
	for s in scales:
		low = minf(low, s)
		high = maxf(high, s)
	assert_gte(low, FireField.CLUMP_SCALE.x - 0.001, "no flame under the clump range")
	assert_lte(high, FireField.CLUMP_SCALE.y + 0.001, "no flame over it")
	assert_gt(high / low, 1.8, "small flames and big ones")
	var points := _lattice_points(doc)
	assert_lt(float(scales.size()), points * 0.85, "open ground between the clumps")
	assert_gt(float(scales.size()), points * 0.35, "but most of a flames band stands")


func test_the_ember_band_draws_no_flames_only_sparks() -> void:
	var doc := _doc(30, 80)
	var plan := _whole(doc)
	var sparks := plan.size() / FireField.STRIDE
	assert_gt(sparks, 0, "a few sparks")
	assert_lt(float(sparks), _lattice_points(doc) / FireField.SPARK_EVERY * 1.3, "sparse")
	for k in sparks:
		assert_eq(plan[k * FireField.STRIDE + FireField.KIND], FireField.SPARK, "no flame")


func test_weak_flames_have_fewer_tongues_than_a_blaze() -> void:
	var weak := _whole(_doc(20, FireField.FLAME_MIN + 5))
	for k in weak.size() / FireField.STRIDE:
		var layout := floori(weak[k * FireField.STRIDE + FireField.SEED])
		assert_lte(layout, FireField.LAYOUT_TWO, "one or two tongues")
	var blaze := _whole(_doc(20, 255))
	var crowns := 0
	for k in blaze.size() / FireField.STRIDE:
		crowns += 1 if floori(blaze[k * FireField.STRIDE + FireField.SEED]) == 3 else 0
	assert_gt(crowns, 0, "a blaze has crowns of four tongues")


func test_a_blaze_has_big_flames_with_licks_at_their_feet() -> void:
	var plan := _whole(_doc(30, 255))
	var scales := _scales(plan)
	var big := 0
	var licks := 0
	for s in scales:
		big += 1 if s >= FireField.BIG_SCALE.x - 0.001 else 0
		licks += 1 if s <= FireField.LICK_SCALE.y + 0.001 else 0
	assert_gt(big, 0, "big flames")
	assert_lt(big, scales.size() / 5, "one per clump, not everywhere")
	assert_gt(licks, big, "licks around them")


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
	assert_eq(field.get_child_count(), 0, "no chunk without fire")


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
	var sources := "\n".join(GraphicsWarmup.shader_sources())
	assert_true(sources.contains("res://shaders/fire_glow.gdshaderinc\n"), "the ground's glow")
