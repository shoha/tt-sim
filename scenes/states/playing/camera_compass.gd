class_name CameraCompass
extends Control

## The on-screen compass of the camera rig: a dial whose wedge points at world north (-Z) as
## the view is turned now, with a turn button either side. It is the always-live way to turn
## the view (Q / E and `[` / `]` depend on what the pointer or a brush owns), and the place the
## live key mapping is written out. A second row tilts it: a flatter and a steeper arrow either
## side of a small elevation gauge that doubles as the top-down button (O). Glass, as the rest
## of the play HUD (UI_TASTE C8): a plum disc with a chalk rim, the north wedge and the gauge's
## elevation ray in lake light (cool means "is": it shows state), the buttons chalk, deepening
## on hover. The gauge's ray reads below home too: the street (EyeView) looks from 35 degrees up
## to 60 down, and a flatter press at home glides down to it (CameraView.tilt_by).
##
## A plain Control that draws itself and hit-tests its buttons, so it needs no theme
## and costs nothing while it is still. It stops mouse events (mouse_filter STOP) over its own
## rectangle only, which also makes GameMap's pointer handling step around it (a hovered
## control is "over the GUI"). CameraController owns it and feeds it the yaw and pitch.

## Emitted with +1 (clockwise on the compass, the E turn) or -1 (the Q turn).
signal turn_requested(direction: int)
## Emitted with the degrees to tilt by: negative flatter, positive steeper (TILT_STEP).
signal tilt_requested(degrees: float)
## Emitted by the elevation gauge: the O key's toggle.
signal top_down_requested

## The hit areas of the tilt row.
enum Tilt { NONE, FLATTER, TOP_DOWN, STEEPER }

## The canvas layer it lives on: above the board, below the menu.
const LAYER := 1
const DIAL_RADIUS := 26.0
const BUTTON_RADIUS := 17.0
## Distance from the dial's centre to a button's centre.
const BUTTON_REACH := 54.0
const MARGIN := 16.0
## The width of the rail of drawer tabs at the right edge, which the compass stands left of.
const RAIL_WIDTH := 44.0
const SLIDE_SECONDS := 0.25
## The tilt row below the dial: arrows TILT_REACH either side of the gauge, one TILT_STEP each.
const TILT_ROW_GAP := 6.0
const TILT_BUTTON_RADIUS := 13.0
const GAUGE_RADIUS := 15.0
const TILT_REACH := 38.0
const TILT_STEP := 15.0

var _slide: Tween = null
var _yaw: float = CameraRig.HOME_YAW
var _pitch: float = CameraRig.HOME_PITCH
var _hover: int = 0  # -1 left button, 1 right button, 0 none
var _tilt_hover: Tilt = Tilt.NONE
var _keys_label: String = "Q E"
var _brush_owns_keys: bool = false


## A compass in its own CanvasLayer under `parent`: above the board and below the menus, so
## its buttons are real GUI the map's pointer handling already steps around.
static func attach(parent: Node) -> CameraCompass:
	var layer := CanvasLayer.new()
	layer.name = "CameraCompassLayer"
	layer.layer = LAYER
	parent.add_child(layer)
	var compass := CameraCompass.new()
	compass.name = "CameraCompass"
	layer.add_child(compass)
	return compass


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var row_bottom := _tilt_row_y() + GAUGE_RADIUS + 4.0
	custom_minimum_size = Vector2((BUTTON_REACH + BUTTON_RADIUS) * 2.0, row_bottom)
	size = custom_minimum_size
	mouse_exited.connect(_on_mouse_exited)
	add_to_group(DrawerContainer.WATCHERS)
	get_viewport().size_changed.connect(on_drawers_moved, CONNECT_DEFERRED)
	on_drawers_moved.call_deferred()


## Keep clear of the right edge's rail and of an open right drawer: the compass sits in the
## top corner of the span the drawers leave free, and slides when one opens or closes (the
## drawers call this on every node in DrawerContainer.WATCHERS, as for InputHints).
func on_drawers_moved() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var span := DrawerContainer.free_span(viewport)
	var closed := is_equal_approx(span.y, viewport.get_visible_rect().end.x)
	var edge := span.y - MARGIN - (RAIL_WIDTH if closed else 0.0)
	var target := Vector2(edge - size.x, MARGIN)
	if _slide != null and _slide.is_valid():
		_slide.kill()
	if not is_inside_tree() or not visible or position == Vector2.ZERO:
		position = target
		return
	_slide = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_slide.tween_property(self, "position", target, SLIDE_SECONDS)


## Show the heading of the view (CameraRig yaw, degrees).
func set_yaw(yaw_deg: float) -> void:
	if is_equal_approx(yaw_deg, _yaw):
		return
	_yaw = yaw_deg
	queue_redraw()


## Show the elevation of the view (CameraRig pitch, degrees) on the gauge.
func set_pitch(pitch_deg: float) -> void:
	if is_equal_approx(pitch_deg, _pitch):
		return
	_pitch = pitch_deg
	queue_redraw()


## Show the heading and the elevation of the view.
func set_view(yaw_deg: float, pitch_deg: float) -> void:
	set_yaw(yaw_deg)
	set_pitch(pitch_deg)


## Follow who owns Q / E: with a brush out they are its footprint turn and the view turns on
## Alt + Q / E. Keeps the tooltip and the hint bar's turn-keys chip naming the live mapping.
func sync_keys(brush_owns_keys: bool) -> void:
	if brush_owns_keys == _brush_owns_keys:
		return
	var old := CameraRig.turn_hint(_brush_owns_keys)
	var live := CameraRig.turn_hint(brush_owns_keys)
	_brush_owns_keys = brush_owns_keys
	_keys_label = live.key
	UIManager.replace_hint(old.key, live.key, live.action)


## -1 or 1 for a point over the left or right button, 0 elsewhere. Pure but for the size.
func button_at(point: Vector2) -> int:
	var centre := _dial_centre()
	for side in [-1, 1]:
		if point.distance_to(centre + Vector2(BUTTON_REACH * side, 0.0)) <= BUTTON_RADIUS:
			return side
	return 0


## Which tilt-row control a point is over (Tilt.NONE elsewhere). Pure but for the size.
func tilt_at(point: Vector2) -> Tilt:
	var centre := Vector2(size.x * 0.5, _tilt_row_y())
	if point.distance_to(centre) <= GAUGE_RADIUS:
		return Tilt.TOP_DOWN
	for side in [-1, 1]:
		var at := centre + Vector2(TILT_REACH * side, 0.0)
		if point.distance_to(at) <= TILT_BUTTON_RADIUS:
			return Tilt.FLATTER if side < 0 else Tilt.STEEPER
	return Tilt.NONE


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var at := (event as InputEventMouseMotion).position
		var over := button_at(at)
		var tilt_over := tilt_at(at)
		if over != _hover or tilt_over != _tilt_hover:
			_hover = over
			_tilt_hover = tilt_over
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			_press(click.position)
		accept_event()


func _press(at: Vector2) -> void:
	var side := button_at(at)
	if side != 0:
		turn_requested.emit(side)
		return
	match tilt_at(at):
		Tilt.FLATTER:
			tilt_requested.emit(-TILT_STEP)
		Tilt.STEEPER:
			tilt_requested.emit(TILT_STEP)
		Tilt.TOP_DOWN:
			top_down_requested.emit()


func _get_tooltip(at_position: Vector2) -> String:
	match tilt_at(at_position):
		Tilt.FLATTER:
			return "Tilt flatter (Alt + drag down to up). Past home it steps down to the street (V)."
		Tilt.STEEPER:
			return "Tilt steeper (Alt + drag up to down). From the street the steepest look climbs up (V)."
		Tilt.TOP_DOWN:
			return "Top-down view (O); press again to go back"
	var side := button_at(at_position)
	if side == 0:
		return "North is toward the wedge. Turn the view with %s or the buttons." % _keys_label
	return "Turn the view %s (%s)" % ["left" if side < 0 else "right", _keys_label]


func _on_mouse_exited() -> void:
	if _hover != 0 or _tilt_hover != Tilt.NONE:
		_hover = 0
		_tilt_hover = Tilt.NONE
		queue_redraw()


func _dial_centre() -> Vector2:
	return Vector2(size.x * 0.5, DIAL_RADIUS + 4.0)


## The y of the tilt row's centre: below the dial and the turn buttons.
func _tilt_row_y() -> float:
	return DIAL_RADIUS * 2.0 + 8.0 + TILT_ROW_GAP + GAUGE_RADIUS


func _draw() -> void:
	var centre := _dial_centre()
	draw_circle(centre, DIAL_RADIUS, ThemeColors.GLASS)
	draw_arc(centre, DIAL_RADIUS, 0.0, TAU, 48, ThemeColors.GLASS_RIM, 1.5, true)
	# North wedge: a tip at the rim and a notched tail, rotated to the heading.
	var angle := CameraRig.north_angle(_yaw)
	var tip := Vector2(0.0, -DIAL_RADIUS + 5.0).rotated(angle)
	var left := Vector2(-6.5, 5.0).rotated(angle)
	var right := Vector2(6.5, 5.0).rotated(angle)
	var notch := Vector2(0.0, 1.0).rotated(angle)
	draw_colored_polygon(
		PackedVector2Array([centre + tip, centre + right, centre + notch, centre + left]),
		ThemeColors.LAKE_LIGHT
	)
	# The tail, opposite the tip, a short chalk tick so the wedge reads as an arrow.
	draw_line(centre - tip * 0.45, centre - tip * 0.1, ThemeColors.CHALK_SOFT, 2.0, true)
	for side in [-1, 1]:
		_draw_button(centre + Vector2(BUTTON_REACH * side, 0.0), side)
	_draw_tilt_row()


## The tilt row: a flatter arrow (chevron down), the elevation gauge, a steeper arrow (chevron up).
func _draw_tilt_row() -> void:
	var centre := Vector2(size.x * 0.5, _tilt_row_y())
	for side in [-1, 1]:
		var at := centre + Vector2(TILT_REACH * side, 0.0)
		var tilt := Tilt.FLATTER if side < 0 else Tilt.STEEPER
		var lit := _tilt_hover == tilt
		draw_circle(at, TILT_BUTTON_RADIUS, ThemeColors.GLASS_RAISED if lit else ThemeColors.GLASS)
		draw_arc(at, TILT_BUTTON_RADIUS, 0.0, TAU, 32, ThemeColors.GLASS_RIM, 1.5, true)
		var lean := 3.0 if side > 0 else -3.0  # chevron up when steeper, down when flatter
		var colour := ThemeColors.CHALK if lit else ThemeColors.CHALK_SOFT
		draw_polyline(
			PackedVector2Array(
				[at + Vector2(-5.0, lean), at + Vector2(0.0, -lean), at + Vector2(5.0, lean)]
			),
			colour,
			2.5,
			true
		)
	var gauge_lit := _tilt_hover == Tilt.TOP_DOWN
	draw_circle(centre, GAUGE_RADIUS, ThemeColors.GLASS_RAISED if gauge_lit else ThemeColors.GLASS)
	var top_down := _pitch >= CameraRig.TOP_DOWN_PITCH - 0.5
	var rim := ThemeColors.LAKE_LIGHT if top_down else ThemeColors.GLASS_RIM
	draw_arc(centre, GAUGE_RADIUS, 0.0, TAU, 40, rim, 1.5, true)
	# The elevation: a horizon tick and the camera's ray from its foot, rising with the pitch.
	var foot := centre + Vector2(-5.0, 6.0)
	draw_line(foot + Vector2(-4.0, 0.0), foot + Vector2(15.0, 0.0), ThemeColors.CHALK_SOFT, 1.5, true)
	var ray := Vector2.from_angle(-deg_to_rad(_pitch)) * 15.0
	draw_line(foot, foot + ray, ThemeColors.LAKE_LIGHT, 2.5, true)
	draw_circle(foot + ray, 2.2, ThemeColors.LAKE_LIGHT)


func _draw_button(at: Vector2, side: int) -> void:
	var lit := _hover == side
	draw_circle(at, BUTTON_RADIUS, ThemeColors.GLASS_RAISED if lit else ThemeColors.GLASS)
	draw_arc(at, BUTTON_RADIUS, 0.0, TAU, 32, ThemeColors.GLASS_RIM, 1.5, true)
	# A chevron pointing the way the north wedge will go: left button counter-clockwise.
	var colour := ThemeColors.CHALK if lit else ThemeColors.CHALK_SOFT
	var s := float(side)
	draw_polyline(
		PackedVector2Array(
			[at + Vector2(-3.5 * s, -6.0), at + Vector2(3.5 * s, 0.0), at + Vector2(-3.5 * s, 6.0)]
		),
		colour,
		2.5,
		true
	)
