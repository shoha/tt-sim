extends GutTest

## The pure parts of how buildings follow the wind (utils/structure_wind.gd) and the windmill node
## that uses them (scenes/terrain/mill_motion.gd). Topic wind_c; docs/systems/wind.md "Phase (c)".

const CENTRE := Vector3(0.2, 0.0, 1.0)


func _dir(deg: float) -> Vector3:
	return Vector3(cos(deg_to_rad(deg)), 0.0, sin(deg_to_rad(deg)))


func test_wrap_angle_crosses_plus_minus_180() -> void:
	assert_almost_eq(StructureWind.wrap_angle(PI + 0.1), -PI + 0.1, 0.0001)
	assert_almost_eq(StructureWind.wrap_angle(-PI - 0.1), PI - 0.1, 0.0001)
	assert_almost_eq(StructureWind.wrap_angle(3.0 * TAU + 0.5), 0.5, 0.0001)


func test_cap_offset_is_clamped_to_the_cone_for_every_wind_direction() -> void:
	for deg in range(0, 360, 5):
		var offset := StructureWind.mill_cap_offset(_dir(float(deg)), CENTRE)
		assert_true(absf(offset) <= StructureWind.MILL_CONE_RAD + 0.0001, "wind %d" % deg)


func test_cap_follows_the_wind_inside_the_cone_and_holds_the_edge_outside() -> void:
	# A wind blowing straight away from the centre bearing faces the cap exactly onto the centre.
	assert_almost_eq(StructureWind.mill_cap_offset(-CENTRE, CENTRE), 0.0, 0.0001)
	# 20 degrees round from the centre bearing: follows.
	var from_dir := Basis(Vector3.UP, deg_to_rad(20.0)) * CENTRE.normalized()
	assert_almost_eq(
		absf(StructureWind.mill_cap_offset(-from_dir, CENTRE)), deg_to_rad(20.0), 0.0001
	)
	# 120 degrees round, either way: pinned at the edge, with the sign of the side.
	var left := Basis(Vector3.UP, deg_to_rad(120.0)) * CENTRE.normalized()
	var right := Basis(Vector3.UP, deg_to_rad(-120.0)) * CENTRE.normalized()
	var a := StructureWind.mill_cap_offset(-left, CENTRE)
	var b := StructureWind.mill_cap_offset(-right, CENTRE)
	assert_almost_eq(absf(a), StructureWind.MILL_CONE_RAD, 0.0001)
	assert_almost_eq(absf(b), StructureWind.MILL_CONE_RAD, 0.0001)
	assert_lt(a * b, 0.0, "opposite sides")
	assert_eq(StructureWind.mill_cap_offset(Vector3.ZERO, CENTRE), 0.0, "no wind, no turn")


func test_cap_offset_has_no_jump_across_the_back_of_the_wind() -> void:
	# Sweeping the wind through the direction opposite the cone's centre: the offset flips from one
	# edge to the other only there (the clamp), and is continuous elsewhere.
	var previous := StructureWind.mill_cap_offset(_dir(0.0), CENTRE)
	var jumps := 0
	for deg in range(1, 361):
		var offset := StructureWind.mill_cap_offset(_dir(float(deg)), CENTRE)
		if absf(offset - previous) > 0.3:
			jumps += 1
		previous = offset
	assert_lte(jumps, 1)


func test_sail_speed_is_monotone_and_capped() -> void:
	var last := -1.0
	for s in range(0, 60):
		var v := StructureWind.mill_speed(float(s))
		assert_gte(v, last, "monotone at %d" % s)
		assert_lte(v, StructureWind.MILL_SPEED_MAX)
		last = v
	assert_almost_eq(StructureWind.mill_speed(0.0), StructureWind.MILL_SPEED_BASE, 0.0001)
	assert_almost_eq(StructureWind.mill_speed(1000.0), StructureWind.MILL_SPEED_MAX, 0.0001)
	assert_gt(StructureWind.mill_speed(14.0), 2.0 * StructureWind.mill_speed(1.5) * 0.9)


func test_ease_converges_and_never_overshoots() -> void:
	var x := 0.0
	for i in 600:
		x = StructureWind.ease_toward(x, 1.0, 0.016, StructureWind.EASE_SECONDS)
		assert_lte(x, 1.0)
	assert_gt(x, 0.99)
	var one := StructureWind.ease_toward(
		0.0, 1.0, StructureWind.EASE_SECONDS, StructureWind.EASE_SECONDS
	)
	assert_almost_eq(one, 1.0 - exp(-1.0), 0.0001, "one time constant covers 63 percent")


func test_ease_angle_takes_the_short_way_across_180() -> void:
	var a := StructureWind.ease_angle(PI - 0.1, -PI + 0.1, 0.5, 1.0)
	assert_true(absf(a) > PI - 0.1, "moved on through 180, not back through 0")
	var angle := PI - 0.3
	for i in 1000:
		angle = StructureWind.ease_angle(angle, -PI + 0.3, 0.02, 1.0)
	assert_almost_eq(absf(wrapf(angle - (-PI + 0.3), -PI, PI)), 0.0, 0.001, "settles on it")


func test_mill_target_is_zero_at_motion_zero() -> void:
	var t := MillMotion.target_of(Vector3(10.0, 0.0, -10.0), 0.0)
	assert_eq(t, Vector2.ZERO)


func test_mill_eases_and_stills() -> void:
	var pivot := MillMotion.new()
	add_child_autofree(pivot)
	var wheel := Node3D.new()
	pivot.add_child(wheel)
	pivot.setup(wheel, Vector3(0.0, 0.0, 1.0), 3)
	var storm := Vector3(9.9, 0.0, -9.9)
	pivot.snap_to(Vector3(0.7, 0.0, -0.7), 1.0)
	var calm_rate := pivot.spin_rate()
	pivot.step_wind(0.1, storm, 1.0)
	assert_gt(pivot.spin_rate(), calm_rate)
	assert_lt(pivot.spin_rate(), StructureWind.mill_speed(14.0) * pivot.spin_speed * 0.5, "eased")
	for i in 600:
		pivot.step_wind(0.05, storm, 1.0)
	assert_almost_eq(pivot.spin_rate(), StructureWind.mill_speed(14.0) * pivot.spin_speed, 0.01)
	assert_true(absf(pivot.cap_offset()) <= StructureWind.MILL_CONE_RAD + 0.0001)
	for i in 600:
		pivot.step_wind(0.05, storm, 0.0)
	assert_almost_eq(pivot.spin_rate(), 0.0, 0.001, "motion 0 stills the sails")
	assert_almost_eq(pivot.cap_offset(), 0.0, 0.001, "and rests the cap on the centre bearing")
	var spin := pivot.spin()
	pivot.step_wind(0.5, storm, 0.0)
	assert_almost_eq(pivot.spin(), spin, 0.001)


func test_cost_of_ten_mills_and_thirty_vanes_per_frame() -> void:
	# The card's budget is 0.05 ms for the three consumers (the cloth costs the CPU nothing). The
	# assert is loose (a loaded machine runs this); the printed numbers are the measurement.
	var mills: Array[MillMotion] = []
	for i in 10:
		var m := MillMotion.new()
		var wheel := Node3D.new()
		m.add_child(wheel)
		m.position = Vector3(i * 9.0, 0.0, i * 3.0)
		m.setup(wheel, Vector3(0.0, 0.0, 1.0), i)
		add_child_autofree(m)
		mills.append(m)
	var vanes: Array[VaneMotion] = []
	for i in 30:
		var v := VaneMotion.new()
		v.position = Vector3(i * 7.0, 0.0, -i * 2.0)
		v.setup(Vector3.RIGHT)
		add_child_autofree(v)
		vanes.append(v)
	var frames := 2000
	var t0 := Time.get_ticks_usec()
	for f in frames:
		for m in mills:
			m.step(0.016)
	var t1 := Time.get_ticks_usec()
	for f in frames:
		for v in vanes:
			v.step(0.016)
	var t2 := Time.get_ticks_usec()
	var mill_us := float(t1 - t0) / frames
	var vane_us := float(t2 - t1) / frames
	gut.p("10 mills %.1f us/frame, 30 vanes %.1f us/frame" % [mill_us, vane_us])
	assert_lt(mill_us + vane_us, 500.0)
