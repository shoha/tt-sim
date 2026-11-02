class_name CameraCompass
extends Control

## The on-screen compass of the camera rig: a dial whose wedge points at world north (-Z) as
## the view is turned now, with a turn button either side. It is the always-live way to turn
## the view (Q / E and `[` / `]` depend on what the pointer or a brush owns), and the place the
## live key mapping is written out. Glass, as the rest of the play HUD (UI_TASTE C8): a plum
## disc with a chalk rim, the north wedge in lake light (cool means "is": it shows state), the
## buttons chalk, deepening on hover.
##
## A plain Control that draws itself and hit-tests its two buttons, so it needs no theme
## and costs nothing while it is still. It stops mouse events (mouse_filter STOP) over its own
## rectangle only, which also makes GameMap's pointer handling step around it (a hovered
## control is "over the GUI"). CameraController owns it and feeds it the yaw.

## Emitted with +1 (clockwise on the compass, the E turn) or -1 (the Q turn).
signal turn_requested(direction: int)

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

var _slide: Tween = null
var _yaw: float = CameraRig.HOME_YAW
var _hover: int = 0  # -1 left button, 1 right button, 0 none
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
	custom_minimum_size = Vector2((BUTTON_REACH + BUTTON_RADIUS) * 2.0, DIAL_RADIUS * 2.0 + 8.0)
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


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over := button_at((event as InputEventMouseMotion).position)
		if over != _hover:
			_hover = over
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.button_index == MOUSE_BUTTON_LEFT and click.pressed:
			var side := button_at(click.position)
			if side != 0:
				turn_requested.emit(side)
		accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var side := button_at(at_position)
	var how := "Turn the view %s (%s)" % ["left" if side < 0 else "right", _keys_label]
	if side == 0:
		return "North is toward the wedge. Turn the view with %s or the buttons." % _keys_label
	return how


func _on_mouse_exited() -> void:
	if _hover != 0:
		_hover = 0
		queue_redraw()


func _dial_centre() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.5)


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
