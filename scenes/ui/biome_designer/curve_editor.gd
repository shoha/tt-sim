class_name CurveEditor
extends Control

## The designer's response-curve widget: one rule's curve on one axis (slope, height or
## wetness) drawn as a small plot, with 2 to 8 draggable points. The rules (snapping, the point
## limits, the order of the points, the engine's sampling) are ResponseCurve's; this draws and
## turns pointer events into new point lists.
##
## Press a point and drag it (snapped to the axis' step, Shift for free); double-click empty
## plot to add a point on the curve there; right-click a point, or press Delete with one
## selected, to remove it (the curve keeps two). A rule with no curve shows the flat line it
## stands for, muted; its first edit makes the curve. `curve_changed(points, final)` fires while
## a point moves (final false) and when the edit ends (true). The widget keeps its own copy of the
## points between set_curve() calls so a drag is smooth; the host stores each final curve.

signal curve_changed(points: Array, final: bool)
## The point under the pointer or selected changed (-1 for none), for a readout.
signal point_selected(index: int)

const POINT_RADIUS := 6.0
const HIT_RADIUS := 11.0
const MARGIN_LEFT := 34.0
const MARGIN_RIGHT := 10.0
const MARGIN_TOP := 8.0
const MARGIN_BOTTOM := 22.0
const PLOT_HEIGHT := 150.0
const LINE_WIDTH := 2.5
const GRID_WIDTH := 1.0
const SAMPLE_STEPS := 96

var axis: String = "slope"
var points: Array = []
var selected: int = -1
## Set by the host when the engine does not evaluate the axis (water distance): the plot is drawn
## muted and takes no input.
var disabled: bool = false

var _drag: int = -1
var _drag_moved: bool = false
var _hover: int = -1


func _init() -> void:
	custom_minimum_size = Vector2(120.0, PLOT_HEIGHT)
	focus_mode = Control.FOCUS_CLICK
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Shows `curve` (a copy) on `new_axis` without emitting; [] means the rule has no curve.
func set_curve(new_axis: String, curve: Array) -> void:
	axis = new_axis
	points = []
	for point: Array in curve:
		points.append([float(point[0]), float(point[1])])
	if selected >= points.size():
		selected = -1
	queue_redraw()


## Whether a point is being dragged right now.
func is_dragging() -> bool:
	return _drag >= 0


func plot_rect() -> Rect2:
	return Rect2(
		MARGIN_LEFT,
		MARGIN_TOP,
		maxf(size.x - MARGIN_LEFT - MARGIN_RIGHT, 1.0),
		maxf(size.y - MARGIN_TOP - MARGIN_BOTTOM, 1.0)
	)


## Plot pixels of the curve coordinates (x in axis units, y 0 to 1).
func to_plot(point: Vector2) -> Vector2:
	var span := ResponseCurve.display_range(axis, points)
	var rect := plot_rect()
	var tx := (point.x - span.x) / maxf(span.y - span.x, 0.0001)
	return Vector2(rect.position.x + tx * rect.size.x, rect.end.y - point.y * rect.size.y)


## Curve coordinates of a pixel in the control.
func from_plot(pixel: Vector2) -> Vector2:
	var span := ResponseCurve.display_range(axis, points)
	var rect := plot_rect()
	var tx := (pixel.x - rect.position.x) / rect.size.x
	return Vector2(span.x + tx * (span.y - span.x), (rect.end.y - pixel.y) / rect.size.y)


## The index of the point within HIT_RADIUS of `pixel`, -1 for none.
func point_at(pixel: Vector2) -> int:
	var best := -1
	var best_distance := HIT_RADIUS
	for i in points.size():
		var distance := to_plot(Vector2(points[i][0], points[i][1])).distance_to(pixel)
		if distance <= best_distance:
			best = i
			best_distance = distance
	return best


func _gui_input(event: InputEvent) -> void:
	if disabled:
		return
	if event is InputEventMouseButton:
		_on_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_on_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		if (event as InputEventKey).keycode == KEY_DELETE and selected >= 0:
			_remove(selected)
			accept_event()


func _on_button(event: InputEventMouseButton) -> void:
	var hit := point_at(event.position)
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		grab_focus()
		if event.double_click and hit < 0:
			_add(event.position)
		elif hit >= 0:
			_drag = hit
			_drag_moved = false
			_select(hit)
		else:
			_select(-1)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if _drag >= 0 and _drag_moved:
			curve_changed.emit(points.duplicate(true), true)
		_drag = -1
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and hit >= 0:
		_remove(hit)
		accept_event()


func _on_motion(event: InputEventMouseMotion) -> void:
	if _drag >= 0:
		var at := from_plot(event.position)
		points = ResponseCurve.move_point(axis, points, _drag, at.x, at.y, not event.shift_pressed)
		_drag_moved = true
		curve_changed.emit(points.duplicate(true), false)
		queue_redraw()
		return
	var hover := point_at(event.position)
	if hover != _hover:
		_hover = hover
		queue_redraw()


func _add(pixel: Vector2) -> void:
	var at := from_plot(pixel)
	var base: Array = points if not points.is_empty() else ResponseCurve.flat(axis)
	var grown := ResponseCurve.add_point(axis, base, at.x, clampf(at.y, 0.0, 1.0))
	if grown.size() == base.size() and not points.is_empty():
		return
	points = grown
	_select(point_at(pixel))
	curve_changed.emit(points.duplicate(true), true)
	queue_redraw()


func _remove(index: int) -> void:
	var fewer := ResponseCurve.remove_point(points, index)
	if fewer.size() == points.size():
		return
	points = fewer
	_select(-1)
	curve_changed.emit(points.duplicate(true), true)
	queue_redraw()


func _select(index: int) -> void:
	if index != selected:
		selected = index
		point_selected.emit(index)
	queue_redraw()


func _draw() -> void:
	var rect := plot_rect()
	var edge := ThemeColors.of(self, ThemeColors.EDGE)
	var soft := ThemeColors.of(self, ThemeColors.TEXT_SOFT)
	var text := ThemeColors.of(self, ThemeColors.TEXT)
	var state := ThemeColors.of(self, ThemeColors.STATE)
	var accent := ThemeColors.of(self, ThemeColors.ACCENT)
	var fill := ThemeColors.of(self, ThemeColors.SURFACE_INSET)
	var line_color := soft if disabled or points.is_empty() else state
	draw_rect(rect, fill)
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size() - 2
	var span := ResponseCurve.display_range(axis, points)
	_draw_grid(rect, span, edge, soft, font, font_size)
	var shown: Array = points if not points.is_empty() else ResponseCurve.flat(axis)
	var line := PackedVector2Array()
	for i in SAMPLE_STEPS + 1:
		var x := span.x + (span.y - span.x) * float(i) / SAMPLE_STEPS
		line.append(to_plot(Vector2(x, ResponseCurve.sample(shown, x))))
	draw_polyline(line, line_color, LINE_WIDTH, true)
	if points.is_empty():
		var hint := "No curve: full density. Double-click to add a point."
		draw_string(
			font, rect.position + Vector2(8.0, rect.size.y * 0.5), hint, 0, -1, font_size, soft
		)
		return
	for i in points.size():
		var centre := to_plot(Vector2(points[i][0], points[i][1]))
		var picked := i == selected or i == _drag
		draw_circle(
			centre, POINT_RADIUS + (2.0 if i == _hover else 0.0), accent if picked else state
		)
		draw_circle(centre, POINT_RADIUS - 2.5, fill)
	if selected >= 0 and selected < points.size():
		var label := "%s, %s" % [_number(points[selected][0]), _number(points[selected][1])]
		var centre := to_plot(Vector2(points[selected][0], points[selected][1]))
		var width := font.get_string_size(label, 0, -1, font_size).x
		var anchor := Vector2(
			clampf(centre.x - width * 0.5, rect.position.x, rect.end.x - width), centre.y - 12.0
		)
		if anchor.y < rect.position.y + font_size:
			anchor.y = centre.y + font_size + 10.0
		draw_string(font, anchor, label, 0, -1, font_size, text)


func _draw_grid(
	rect: Rect2, span: Vector2, edge: Color, soft: Color, font: Font, font_size: int
) -> void:
	for value: float in [0.0, 0.5, 1.0]:
		var y := rect.end.y - value * rect.size.y
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), edge, GRID_WIDTH)
		draw_string(
			font, Vector2(2.0, y + font_size * 0.35), _number(value), 0, -1, font_size, soft
		)
	var step := _tick_step(span.y - span.x)
	var tick := ceilf(span.x / step) * step
	while tick <= span.y + 0.0001:
		var x := to_plot(Vector2(tick, 0.0)).x
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), edge, GRID_WIDTH)
		var label := _number(tick)
		var width := font.get_string_size(label, 0, -1, font_size).x
		draw_string(font, Vector2(x - width * 0.5, size.y - 4.0), label, 0, -1, font_size, soft)
		tick += step


## A tick step that gives about four to six lines across `length` axis units.
static func _tick_step(length: float) -> float:
	var raw := length / 5.0
	var magnitude := pow(10.0, floorf(log(raw) / log(10.0)))
	for factor in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if raw <= magnitude * factor:
			return magnitude * factor
	return magnitude * 10.0


static func _number(value: float) -> String:
	return str(snappedf(value, 0.01))
