extends GutTest

## MaskBrush (utils/mask_brush.gd): the pure rules of the Biome and Thin / Clear brushes.


func test_falloff_is_one_at_the_centre_and_zero_at_the_rim() -> void:
	assert_almost_eq(MaskBrush.falloff(0.0), 1.0, 1e-6)
	assert_almost_eq(MaskBrush.falloff(1.0), 0.0, 1e-6)
	assert_almost_eq(MaskBrush.falloff(1.5), 0.0, 1e-6)


func test_falloff_is_smooth_not_linear() -> void:
	# (1 - t^2)^2: well above a linear ramp inside, flat at both ends.
	assert_almost_eq(MaskBrush.falloff(0.5), 0.5625, 1e-6)
	assert_gt(MaskBrush.falloff(0.25), 0.75 + 0.1, "flat-topped core")
	var near_centre := (1.0 - MaskBrush.falloff(0.01)) / 0.01
	var near_rim := MaskBrush.falloff(0.99) / 0.01
	assert_lt(near_centre, 0.05, "zero slope at the centre")
	assert_lt(near_rim, 0.05, "zero slope at the rim: no edge line")


func test_falloff_decreases_monotonically() -> void:
	var previous := 2.0
	for i in 101:
		var value := MaskBrush.falloff(i / 100.0)
		assert_true(value <= previous)
		previous = value


func test_amount_composes_over_time() -> void:
	# Two half exposures move a sample exactly as far as one whole one: frame-rate independent.
	var whole := MaskBrush.amount(0.7, 0.2)
	var half := MaskBrush.amount(0.7, 0.1)
	var value := MaskBrush.approach(MaskBrush.approach(0.0, 1.0, half), 1.0, half)
	assert_almost_eq(value, MaskBrush.approach(0.0, 1.0, whole), 1e-6)
	assert_eq(MaskBrush.amount(0.0, 1.0), 0.0)
	assert_eq(MaskBrush.amount(1.0, 0.0), 0.0)


func test_repeated_exposure_approaches_the_target_without_overshoot() -> void:
	var value := 0.0
	var gains: Array[float] = []
	for i in 30:
		var before := value
		value = MaskBrush.approach(value, 1.0, MaskBrush.amount(1.0, 0.25))
		gains.append(value - before)
		assert_true(value <= 1.0)
	assert_gt(value, 0.99)
	# Each pass adds less than the last: no plateau builds up in steps.
	for i in range(1, gains.size()):
		assert_true(gains[i] <= gains[i - 1] + 1e-6)


func test_contest_fades_the_owner_and_hands_over_when_the_challenger_is_denser() -> void:
	var light := MaskBrush.contest(0.9, 0.0, 1.0, 0.2)
	assert_almost_eq(light.x, 0.72, 1e-5, "owner fades by the step")
	assert_almost_eq(light.y, 0.2, 1e-5, "challenger grows as on bare ground")
	assert_eq(light.z, 0.0, "a light touch keeps the owner")
	var owner := 0.9
	var challenger := 0.0
	var steps := 0
	while steps < 50:
		var result := MaskBrush.contest(owner, challenger, 1.0, 0.2)
		owner = result.x
		challenger = result.y
		steps += 1
		if result.z > 0.0:
			break
	assert_lt(steps, 10, "a firm pass replaces the owner")
	assert_true(challenger >= owner)


func test_erase_byte_thins_below_the_threshold_and_erases_past_the_noise() -> void:
	assert_eq(MaskBrush.erase_byte(0.3, 0.8, false), roundi(0.3 * MaskBrush.ERASE_LEVELS))
	assert_true(MaskBrush.erase_byte(0.3, 0.8, false) <= MapDocument.ERASE_THRESHOLD)
	assert_eq(MaskBrush.erase_byte(0.81, 0.8, false), MaskBrush.ERASED)
	# Clearing compresses the thresholds: 0.7 thinned clears a 0.8-noise sample.
	assert_eq(MaskBrush.erase_byte(0.7, 0.8, true), MaskBrush.ERASED)
	assert_eq(MaskBrush.erase_amount(MaskBrush.ERASED), 1.0)
	assert_almost_eq(MaskBrush.erase_amount(MaskBrush.ERASE_LEVELS), 1.0, 1e-6)


func test_sample_noise_is_deterministic_and_spread() -> void:
	var total := 0.0
	for i in 2000:
		var value := MaskBrush.sample_noise(42, i)
		assert_true(value >= 0.0 and value < 1.0)
		total += value
	assert_almost_eq(total / 2000.0, 0.5, 0.03)
	assert_eq(MaskBrush.sample_noise(42, 17), MaskBrush.sample_noise(42, 17))
	assert_ne(MaskBrush.sample_noise(42, 17), MaskBrush.sample_noise(43, 17))


func test_capsule_rect_covers_the_brush_and_clips_to_the_map() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 1)
	var rect := MaskBrush.capsule_rect(doc, Vector2.ZERO, Vector2(2, 0), 1.0)
	var low := doc.world_to_sample(Vector2(-1, -1))
	var high := doc.world_to_sample(Vector2(3, 1))
	assert_true(rect.position.x <= floori(low.x) and rect.end.x >= ceili(high.x))
	var edge := MaskBrush.capsule_rect(doc, Vector2(-15.2, 0), Vector2(-15.2, 0), 3.0)
	assert_eq(edge.position.x, 0, "clipped to the grid")
	var off := MaskBrush.capsule_rect(doc, Vector2(100, 100), Vector2(100, 100), 2.0)
	assert_false(off.has_area())
