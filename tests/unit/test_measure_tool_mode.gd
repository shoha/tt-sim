extends GutTest

## Tests for MeasureTool mode cycling logic.


func test_mode_enum_order() -> void:
	assert_eq(MeasureTool.Mode.LINE, 0)
	assert_eq(MeasureTool.Mode.SPHERE, 1)
	assert_eq(MeasureTool.Mode.CYLINDER, 2)


func test_advance_mode_line_to_sphere() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.LINE), MeasureTool.Mode.SPHERE)


func test_advance_mode_sphere_to_cylinder() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.SPHERE), MeasureTool.Mode.CYLINDER)


func test_advance_mode_cylinder_wraps_to_line() -> void:
	assert_eq(MeasureTool.advance_mode(MeasureTool.Mode.CYLINDER), MeasureTool.Mode.LINE)


func test_initial_mode_is_line() -> void:
	var tool := MeasureTool.new()
	add_child_autofree(tool)
	assert_eq(tool._mode, MeasureTool.Mode.LINE)
