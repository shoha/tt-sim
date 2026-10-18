extends GutTest

## FireFires' placement (fewer, bigger fires): a centre tops its CENTRE_REACH neighbourhood and
## no two centres stand within it; every burning flames-band point is covered by a centre or
## stands a straggler or climbs to one; blaze points stand FireField's own flames at
## SIM_BLAZE_SCALE with a SIM_BLAZE_SHARE width; sizes stay in range and the rasters' reach
## (FireField.HEAT_GROW) covers the largest fire's; neighbouring blocks' windows agree on every
## point both decide.


func _doc(cells: int = 30, heat: int = 0) -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(cells, cells), "grass", "v", 5)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	mask.fill(heat)
	doc.fire_mask = mask
	return doc


## A ragged fire: the flames band in broad stripes of rising strength, a blaze patch, and
## holes, so the burn has edges, thin parts and big clumps.
func _ragged(cells: int = 30) -> MapDocument:
	var doc := _doc(cells)
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var mask := doc.fire_mask.duplicate()
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := Vector2(x, z) * step - half
			var value := 0
			if absf(p.y) < 12.0:
				value = FireField.FLAME_MIN + int(clampf((p.x + half.x) / (2.0 * half.x), 0.0, 1.0) * 89)
			if p.distance_to(Vector2(6.0, -4.0)) < 3.0:
				value = 230
			if p.distance_to(Vector2(-8.0, 3.0)) < 1.5 or absf(p.y + 8.0) < 0.4:
				value = 0
			mask[doc.sample_index(x, z)] = value
	doc.fire_mask = mask
	return doc


## The window, scores, centres and cover of `block`, and its own lattice range:
## {"window", "score", "centre", "covered", "first", "end"}.
func _decide(doc: MapDocument, block: Vector2i) -> Dictionary:
	var rect := MaskStroke.block_rect(doc, block)
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var low := -half + Vector2(rect.position) * step
	var high := -half + Vector2(rect.end) * step
	var s := FireField.FLAME_SPACING_M
	var first := Vector2i(ceili(low.x / s), ceili(low.y / s))
	var end := Vector2i(ceili(high.x / s), ceili(high.y / s))
	var window := FireField.LatticeWindow.new(doc, first, end, FireFires.MARGIN)
	var score := FireFires.scores(window)
	var centre := FireFires.centres(window, score)
	var covered := FireFires.covers(window, score, centre)
	return {
		"window": window,
		"score": score,
		"centre": centre,
		"covered": covered,
		"first": first,
		"end": end
	}


func _blocks(doc: MapDocument) -> Array[Vector2i]:
	return FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z()))


func test_a_centre_tops_its_neighbourhood() -> void:
	var doc := _ragged()
	var r := FireFires.CENTRE_REACH
	var spots: Array[Vector2i] = []
	for block in _blocks(doc):
		var d := _decide(doc, block)
		var window: FireField.LatticeWindow = d.window
		var score: PackedFloat32Array = d.score
		for iz in range(d.first.y, d.end.y):
			for ix in range(d.first.x, d.end.x):
				var i := window.index(ix, iz)
				if not d.centre[i]:
					continue
				spots.append(Vector2i(ix, iz))
				assert_gte(score[i], 0.0, "a centre burns")
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if (dx != 0 or dz != 0) and dx * dx + dz * dz <= r * r + 1:
							assert_true(score[window.index(ix + dx, iz + dz)] <= score[i])
	assert_gt(spots.size(), 4, "a ragged burn has several fires")
	# No two fires within 2.7 m of lattice, across block lines too.
	for k in spots.size():
		for m in range(k + 1, spots.size()):
			var gap := spots[k] - spots[m]
			assert_gt(gap.x * gap.x + gap.y * gap.y, r * r + 1, "%s and %s" % [spots[k], spots[m]])


func test_every_burning_flames_point_is_covered_or_climbs_to_a_straggler() -> void:
	var doc := _ragged()
	var burning := 0
	var stragglers := 0
	for block in _blocks(doc):
		var d := _decide(doc, block)
		var window: FireField.LatticeWindow = d.window
		var score: PackedFloat32Array = d.score
		var covered: Array[bool] = d.covered
		for iz in range(d.first.y, d.end.y):
			for ix in range(d.first.x, d.end.x):
				var i := window.index(ix, iz)
				if score[i] < 0.0:
					continue
				burning += 1
				if covered[i]:
					continue
				if FireFires.tops_uncovered(window, score, covered, i):
					stragglers += 1
					continue
				# An uncovered point that does not top its neighbours has a higher uncovered
				# burning neighbour, so a climb ends on a straggler.
				var higher := false
				for j in [i - window.width - 1, i - window.width, i - window.width + 1, i - 1]:
					higher = higher or (score[j] >= 0.0 and not covered[j] and score[j] >= score[i])
				for j in [i + 1, i + window.width - 1, i + window.width, i + window.width + 1]:
					higher = higher or (score[j] >= 0.0 and not covered[j] and score[j] >= score[i])
				assert_true(higher, "point %d, %d" % [ix, iz])
	assert_gt(burning, 100)
	assert_gt(stragglers, 0, "the ragged edges keep stragglers")


func test_blaze_points_stand_shrunk_and_widened_flames() -> void:
	var doc := _doc(20, 255)
	var block := Vector2i(1, 1)
	var plan := FireField.plan_block(doc, block)
	var by_spot := {}
	for k in plan.size() / FireField.STRIDE:
		var o := k * FireField.STRIDE
		by_spot[Vector2(plan[o], plan[o + 2])] = plan.slice(o, o + FireField.STRIDE)
	var d := _decide(doc, block)
	var window: FireField.LatticeWindow = d.window
	var matched := 0
	for iz in range(d.first.y, d.end.y):
		for ix in range(d.first.x, d.end.x):
			var i := window.index(ix, iz)
			assert_eq(d.score[i], -1.0, "a blaze point is never a centre")
			var own := FireField._flame(doc.map_seed, FireField._key(ix, iz), window.heat[i], window, i)
			var spot := Vector2(window.px[i], window.pz[i])
			if own.is_empty():
				assert_false(by_spot.has(spot), "nothing where FireField stands nothing")
				continue
			var entry: PackedFloat32Array = by_spot[spot]
			var height := own[FireField.HEIGHT] * FireFires.SIM_BLAZE_SCALE
			assert_almost_eq(entry[FireField.HEIGHT], height, 1e-4)
			assert_almost_eq(entry[FireField.WIDTH], height * FireFires.SIM_BLAZE_SHARE, 1e-4)
			matched += 1
	assert_eq(matched * FireField.STRIDE, plan.size(), "every blaze flame is a point's own")
	assert_gt(matched, 50)


func test_sizes_stay_in_range() -> void:
	var tallest := FireFires.largest_height_m()
	var weakest := FireField.FLAME_HEIGHT_M.x * FireFires.SINGLE_SCALE.x
	var straggler := FireField.FLAME_HEIGHT_M.y * FireFires.SINGLE_SCALE.y
	var fire := FireFires.FIRE_HEIGHT_M.x * FireFires.BAND_SCALE.x * FireFires.OWN_SCALE.x
	var top := 0.0
	var fires := 0
	var spill := 0.0
	for doc in [_ragged(), _doc(20, 150), _doc(20, FireField.BLAZE_MIN - 1), _doc(20, 255)]:
		var half: Vector2 = doc.extent_m() * 0.5
		var step: Vector2 = doc.sample_step()
		for block in _blocks(doc):
			var plan := FireField.plan_block(doc, block)
			var rect := MaskStroke.block_rect(doc, block)
			var low := -half + Vector2(rect.position) * step
			var high := -half + Vector2(rect.end) * step
			for k in plan.size() / FireField.STRIDE:
				var o := k * FireField.STRIDE
				if plan[o + FireField.KIND] != FireField.FLAME:
					continue
				var height := plan[o + FireField.HEIGHT]
				var share := plan[o + FireField.WIDTH] / height
				var at := Vector2(plan[o], plan[o + 2])
				var off := (low - at).max(at - high).max(Vector2.ZERO)
				var kernel := FireField.HEAT_REACH.x + FireField.HEAT_REACH.y * plan[o + FireField.WIDTH]
				spill = maxf(spill, maxf(off.x, off.y))
				assert_lte(maxf(off.x, off.y), FireFires.spill_m() + 1e-4, "near its block")
				assert_lte(maxf(off.x, off.y) + kernel, FireFires.heat_reach_m() + 1e-4)
				top = maxf(top, height)
				assert_between(height, weakest - 1e-4, tallest + 1e-4, "height")
				assert_between(share, FireFires.SINGLE_WIDTH.x - 1e-4, FireFires.FIRE_WIDTH.y + 1e-4)
				var band := FireField.band(roundi(plan[o + FireField.INTENSITY] * 255.0))
				if band == 2 and height > straggler + 1e-4:
					fires += 1
					assert_gte(height, fire - 1e-4, "a fire is bigger than any straggler")
	gut.p("the farthest fire off its block: %.2f m (bound %.2f)" % [spill, FireFires.spill_m()])
	assert_gt(fires, 10, "the flames band stands big fires")
	assert_gt(top, 2.9, "some near the top of the range")
	assert_lt(fire, tallest)
	var reach := FireField.HEAT_GROW * FireField.HEAT_STEP_M
	assert_gte(reach, FireFires.heat_reach_m(), "the rasters' cleared rect covers every fire")
	var feet := FireField.FEET_GROW * FireField.HEAT_STEP_M
	assert_gte(feet, FireFires.spill_m() + FireField.HEAT_STEP_M, "and every foot's heat read")


func test_neighbouring_blocks_agree() -> void:
	var doc := _ragged()
	var compared := 0
	for pair in [[Vector2i(1, 1), Vector2i(2, 1)], [Vector2i(2, 2), Vector2i(2, 3)]]:
		var one := _decide(doc, pair[0])
		var two := _decide(doc, pair[1])
		var w1: FireField.LatticeWindow = one.window
		var w2: FireField.LatticeWindow = two.window
		# Every point both windows see: the same score; a centre where both see its whole
		# neighbourhood, the cover where both see its centres' neighbourhoods.
		var lo := w1.origin.max(w2.origin)
		var hi := (w1.origin + _span(w1)).min(w2.origin + _span(w2))
		for iz in range(lo.y, hi.y):
			for ix in range(lo.x, hi.x):
				var i := w1.index(ix, iz)
				var j := w2.index(ix, iz)
				assert_eq(one.score[i], two.score[j])
				var reach := FireFires.CENTRE_REACH
				if _inside(w1, ix, iz, reach) and _inside(w2, ix, iz, reach):
					assert_eq(one.centre[i], two.centre[j], "centre at %d, %d" % [ix, iz])
					compared += 1
				reach += FireFires.COVER_REACH
				if _inside(w1, ix, iz, reach) and _inside(w2, ix, iz, reach):
					assert_eq(one.covered[i], two.covered[j], "cover at %d, %d" % [ix, iz])
	assert_gt(compared, 100)


## The lattice points `window` spans (columns, rows).
func _span(window: FireField.LatticeWindow) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(window.width, window.heat.size() / window.width)


## Whether lattice point (`ix`, `iz`) lies at least `inset` points inside `window`'s edge.
func _inside(window: FireField.LatticeWindow, ix: int, iz: int, inset: int) -> bool:
	@warning_ignore("integer_division")
	var rows := window.heat.size() / window.width
	var x := ix - window.origin.x
	var z := iz - window.origin.y
	return x >= inset and z >= inset and x < window.width - inset and z < rows - inset
