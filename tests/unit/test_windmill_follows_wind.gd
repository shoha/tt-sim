extends GutTest

## A windmill's cap turns with the wind and its sails turn over time (check G2, 2026-10-31). Builds
## a real Dutch windmill, takes its MillMotion pivot from AuthoredStructures, sets the global Wind
## autoload to a direction and strength, runs the pivot's own per-frame step, and reads the cap's
## yaw and the wheel's spin off the nodes. Pure rules: test_structure_wind.gd and
## test_structure_mill.gd.

const SAIL_STEP_S := 0.05
const SETTLE_STEPS := 600

var _doc: MapDocument = null
var _pivot: MillMotion = null
var _axis := Vector3.ZERO


func before_each() -> void:
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureRecipes.ensure_served()
	var row := LibraryStructureStore.structure("core:windmill_dutch")
	var diameter := float((row.get("default_size_m", [6.0, 6.0]) as Array)[0])
	var plan := StructurePlacement.lot_plan(
		Vector2.ZERO, Vector2(diameter, diameter), 0.0, StructurePlacement.sides_of(row)
	)
	var parts := StructureGeometry.build_one(
		_doc, Structure.make(1, "core:windmill_dutch", plan, 5)
	)
	var nodes := AuthoredStructures.new()
	add_child_autofree(nodes)
	_axis = parts.mill.axis
	Wind.set_clock_override(10.0)
	_set_wind(0.0, 1.0)
	_pivot = nodes.mill_node(parts.mill, 1, "", "")
	add_child_autofree(_pivot)


func after_each() -> void:
	Wind.set_from_weather(WeatherSettings.default())
	Wind.snap()
	Wind.clear_clock_override()
	Wind.publish(Wind.clock())


func _set_wind(degrees: float, intensity: float) -> void:
	Wind.apply_weather_dict({"wind_direction_deg": degrees, "wind_intensity": intensity})
	Wind.snap()


## Runs the pivot's own step until its eased cap and speed have settled on the current wind.
func _settle() -> void:
	for i in SETTLE_STEPS:
		_pivot.step(SAIL_STEP_S)


## The unit direction the wind blows toward at the mill now.
func _toward() -> Vector3:
	return Wind.direction_at(_pivot.global_position)


## The direction the sails face now (horizontal, unit).
func _facing() -> Vector3:
	return _pivot.basis * _axis


func _angle_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))


func test_the_cap_faces_into_the_wind_within_the_cone_and_holds_the_edge_beyond_it() -> void:
	var cone_deg := rad_to_deg(StructureWind.MILL_CONE_RAD)
	var followed := 0
	var held := 0
	for degrees in range(0, 360, 15):
		_set_wind(float(degrees), 1.0)
		_settle()
		var into := -_toward()
		var facing := _facing()
		# Always inside the cone about the rest bearing.
		assert_lte(
			_angle_deg(facing, MillMotion.WIND_FROM.normalized()),
			cone_deg + 0.5,
			"wind %d: the sails stay within the cone about WIND_FROM" % degrees
		)
		var wanted := StructureWind.mill_cap_offset(_toward(), MillMotion.WIND_FROM)
		assert_almost_eq(
			_pivot.cap_offset(), wanted, 0.01, "wind %d: the eased cap has arrived" % degrees
		)
		if absf(wanted) < StructureWind.MILL_CONE_RAD - 0.01:
			followed += 1
			assert_lt(
				_angle_deg(facing, into), 1.5, "wind %d: the cap faces into the wind" % degrees
			)
		else:
			held += 1
			assert_almost_eq(
				absf(_pivot.cap_offset()),
				StructureWind.MILL_CONE_RAD,
				0.01,
				"wind %d: held at the edge" % degrees
			)
	gut.p(
		(
			"wind directions followed %d, held at the cone edge %d (cone %.0f degrees)"
			% [followed, held, cone_deg]
		)
	)
	assert_gt(followed, 0, "some directions are inside the cone")
	assert_gt(held, 0, "and some are beyond it")


func test_changing_the_wind_direction_turns_the_cap_after_it() -> void:
	# Two directions inside the cone, found by trying (the autoload's degree convention is its own).
	var inside: Array[float] = []
	for degrees in range(0, 360, 5):
		_set_wind(float(degrees), 1.0)
		if absf(StructureWind.mill_cap_offset(_toward(), MillMotion.WIND_FROM)) < 0.35:
			inside.append(float(degrees))
	assert_gt(inside.size(), 3, "several directions are well inside the cone")
	var a := inside[0]
	var b := inside[inside.size() - 1]
	_set_wind(a, 1.0)
	_settle()
	var yaw_a := _pivot.basis.get_euler().y
	_set_wind(b, 1.0)
	_pivot.step(0.1)
	var mid := _pivot.basis.get_euler().y
	assert_almost_eq(mid, yaw_a, 0.2, "it eases rather than snapping")
	_settle()
	var yaw_b := _pivot.basis.get_euler().y
	assert_gt(absf(wrapf(yaw_b - yaw_a, -PI, PI)), 0.1, "the cap turned (%.0f to %.0f)" % [a, b])
	assert_lt(_angle_deg(_facing(), -_toward()), 1.5, "and faces the new wind")
	_set_wind(a, 1.0)
	_settle()
	assert_almost_eq(_pivot.basis.get_euler().y, yaw_a, 0.02, "and turns back when the wind does")


func test_the_sails_turn_over_time_and_faster_in_a_stronger_wind() -> void:
	_set_wind(0.0, 0.3)
	_settle()
	var rate_breeze := _pivot.spin_rate()
	var spin := _pivot.spin()
	var wheel_basis := _pivot.wheel.basis
	for i in 20:
		_pivot.step(0.1)
	assert_ne(_pivot.spin(), spin, "the spin moved over two seconds")
	assert_ne(_pivot.wheel.basis, wheel_basis, "and the wheel node with it")
	_set_wind(0.0, 1.0)
	_settle()
	assert_gt(_pivot.spin_rate(), rate_breeze, "a stronger wind turns the sails faster")
	gut.p("sail rate breeze %.3f rad/s, strong %.3f rad/s" % [rate_breeze, _pivot.spin_rate()])
	# The axis itself does not move while the wheel turns.
	assert_lt((_pivot.wheel.basis * _axis - _axis).length(), 0.001)
