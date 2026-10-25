class_name DesignerCompareOverlay
extends Control

## The A/B view's divider (step S9), laid over the map window of the designer: a vertical line
## with a grip that is dragged left and right, "Draft" over the left side and the reference's name
## over the right. The line stands where the session's BiomeDesignerCompare says the divider is on
## the ground, seen through the game camera, so it follows a pan or a zoom; dragging it asks the
## compare for a new ground position (the repaint and the regeneration are throttled there). The
## rest of the overlay passes the pointer to the map. Nothing here sets a colour, a font or a
## size of its own: the theme's roles and variations do.

const GRIP_WIDTH := 28.0
const LINE_WIDTH := 3.0
const KNOB_RADIUS := 11.0
const LABEL_MARGIN := 12.0

var session: BiomeDesignerSession = null

var _grip: Control
var _left: Label
var _right: Label
var _left_chip: PanelContainer
var _right_chip: PanelContainer
var _line_x: float = -1.0
var _dragging: bool = false


func _init() -> void:
	name = "CompareOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	visible = false
	_left_chip = PanelContainer.new()
	_left = _side_label("DraftLabel", _left_chip)
	_left.text = "Draft"
	_right_chip = PanelContainer.new()
	_right = _side_label("ReferenceLabel", _right_chip)
	_grip = Control.new()
	_grip.name = "Grip"
	_grip.mouse_filter = Control.MOUSE_FILTER_STOP
	_grip.mouse_default_cursor_shape = Control.CURSOR_HSIZE
	_grip.tooltip_text = "Drag to move the divider. Left shows your draft, right the reference."
	_grip.gui_input.connect(_on_grip_input)
	add_child(_grip)
	resized.connect(_place)


func setup(designer: BiomeDesignerSession) -> void:
	session = designer
	session.compare.changed.connect(_refresh)
	set_process(true)
	_refresh()


## Where the divider is drawn, in this control's pixels (-1 while the view is off).
func line_x() -> float:
	return _line_x


func is_dragging() -> bool:
	return _dragging


func _process(_delta: float) -> void:
	if session == null or not session.compare.active:
		return
	var x := _window_x(session.compare.viewport_x())
	if not is_equal_approx(x, _line_x):
		_line_x = x
		_place()
		queue_redraw()


func _draw() -> void:
	if _line_x < 0.0:
		return
	var line := ThemeColors.of(self, ThemeColors.ACCENT)
	var rim := ThemeColors.of(self, ThemeColors.SURFACE)
	draw_line(Vector2(_line_x, 0.0), Vector2(_line_x, size.y), rim, LINE_WIDTH + 2.0)
	draw_line(Vector2(_line_x, 0.0), Vector2(_line_x, size.y), line, LINE_WIDTH)
	var middle := Vector2(_line_x, size.y * 0.5)
	draw_circle(middle, KNOB_RADIUS + 1.5, rim)
	draw_circle(middle, KNOB_RADIUS, line)
	var arrow := ThemeColors.of(self, ThemeColors.ON_ACCENT)
	draw_line(middle + Vector2(-6.0, 0.0), middle + Vector2(6.0, 0.0), arrow, 2.0)
	draw_line(middle + Vector2(-6.0, 0.0), middle + Vector2(-2.5, -3.5), arrow, 2.0)
	draw_line(middle + Vector2(-6.0, 0.0), middle + Vector2(-2.5, 3.5), arrow, 2.0)
	draw_line(middle + Vector2(6.0, 0.0), middle + Vector2(2.5, -3.5), arrow, 2.0)
	draw_line(middle + Vector2(6.0, 0.0), middle + Vector2(2.5, 3.5), arrow, 2.0)


func _refresh() -> void:
	var on := session != null and session.compare.active
	visible = on
	if not on:
		_line_x = -1.0
		_dragging = false
		return
	_right.text = session.compare.reference_label()
	_line_x = _window_x(session.compare.viewport_x())
	_place()
	_place.call_deferred()  # The chips have their final size a frame later.
	queue_redraw()


## Puts the grip on the line and the two labels at the top corners of their sides.
func _place() -> void:
	_grip.position = Vector2(_line_x - GRIP_WIDTH * 0.5, 0.0)
	_grip.size = Vector2(GRIP_WIDTH, size.y)
	_left_chip.position = Vector2(LABEL_MARGIN, LABEL_MARGIN)
	_right_chip.reset_size()
	_right_chip.position = Vector2(size.x - _right_chip.size.x - LABEL_MARGIN, LABEL_MARGIN)


## A label on a chip (glass with its rim, so it reads over the plants) added to this overlay.
func _side_label(node_name: String, chip: PanelContainer) -> Label:
	chip.name = node_name + "Chip"
	chip.theme_type_variation = &"Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := Label.new()
	label.name = node_name
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	add_child(chip)
	return label


## This control's x for world-viewport pixel column `x`.
func _window_x(x: float) -> float:
	var container := session.game_map.viewport_container
	var world := session.game_map.world_viewport
	var scale := container.size.x / maxf(float(world.size.x), 1.0)
	return container.global_position.x + x * scale - global_position.x


## The world-viewport pixel column under this control's x.
func _viewport_x(x: float) -> float:
	var container := session.game_map.viewport_container
	var world := session.game_map.world_viewport
	var scale := container.size.x / maxf(float(world.size.x), 1.0)
	return (x + global_position.x - container.global_position.x) / maxf(scale, 0.0001)


func _on_grip_input(event: InputEvent) -> void:
	if session == null or not session.compare.active:
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			_dragging = button.pressed
			if not button.pressed:
				_move_to(get_local_mouse_position().x, false)
			_grip.accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_move_to(get_local_mouse_position().x, true)
		_grip.accept_event()


func _move_to(x: float, dragging: bool) -> void:
	var t := session.compare.t_at_viewport_x(_viewport_x(clampf(x, 0.0, size.x)))
	session.compare.move_divider(t, dragging)
	_line_x = _window_x(session.compare.viewport_x())
	_place()
	queue_redraw()
