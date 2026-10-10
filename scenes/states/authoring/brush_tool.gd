class_name BrushTool
extends Node

## Authoring mode's brush: the pointer, the ground under it, the brush size and the dab stroke
## every map tool shares, and the dispatch of each tool's own gestures to its BrushMode. What
## a gesture does to the map is AuthoringEditor's; the tool's mode turns the press, the frames
## after it and the release into calls on it, and BrushCursor draws the cursor the mode asks
## for.
##
## Modal tool contract (MeasureTool, SunGizmoTool): `toggled`, is_active(), idempotent
## activate() / deactivate(), toggle(), handle_input() -> bool, is_dragging(), setup().
## GameMap owns it (setup_brush_tool()), dispatches input to it from _input() with the GUI
## click guard, keeps it exclusive with the other two tools, and CameraController does not
## start a right-button pan while it is active (RMB belongs to the brush).
##
## Tools. use_tool() switches to a ToolDescriptor's mode: the BrushMode subclass its
## `brush_mode` names, made once per tool by mode_for() and kept, so what its pane picked
## survives switching away. The brush knows no tool by name; a new tool brings its gestures
## (and, if it wants one, its own cursor) in its mode class.
##
## Pointer. Handlers read `event.position` (never the viewport's cached mouse position,
## which injected events do not update) and only record it; _process raycasts once per frame
## on collision layer 1, which both AuthoredTerrain and a Blender map's collision use, past
## the map's crossings unless the mode `sees_crossings`. A press waits for that raycast too,
## unless it is released in the same frame (a click), which then resolves at once.
## Sculpting moves the ground under a still pointer, so while a sculpt stroke is held and the
## pointer has not moved the brush keeps its ground point (only its height follows the
## ground) instead of re-casting the ray, which would walk a growing hill toward the camera.
##
## Gestures every tool shares (decide() is the pure input table; the modes' headers say what
## their own presses do):
##   LMB press, drag    the mode's press (BrushMode.press); a dab stroke it begins is painted
##                      along the pointer's path every frame, at the mode's stroke radius
##   hold still         strength builds: exposure is multiplied by 1 + DWELL_GAIN * dwell,
##                      dwell being how long the brush has stayed within DWELL_RADIUS of its
##                      anchor (capped at DWELL_MAX); moving resets it, so moving spreads
##   plain wheel        camera zoom (not consumed)
##   Shift+wheel, [ ]   the mode's step: by default the brush size (min_radius()..MAX_RADIUS,
##                      remembered for the app session); a picking mode's target, only over one
##   RMB press          cancel the gesture in progress (reverting it); idle over a picking
##                      mode's target, remove it; otherwise put the brush down
##   Escape             while a press is held, cancel it as RMB does (idle: not taken)
##   Delete             idle over a picking mode's target, remove it
## A press or release a mode refuses says why through `refused`, which the controller toasts.

signal toggled(active: bool)
## The brush radius changed (world metres), by gesture or set_radius().
signal radius_changed(radius: float)
## A press or release made nothing; `reason` says why, for a toast.
signal refused(reason: String)

enum Action { NONE, POINTER, BEGIN, END, CANCEL, DESELECT, GROW, SHRINK, REMOVE, SWALLOW }

const MIN_RADIUS := 1.0
const MAX_RADIUS := 12.0
const DEFAULT_RADIUS := 4.0
## Size change per wheel notch or bracket key: multiplicative, so small brushes step finely.
const RADIUS_STEP := 1.15
## Dwell: within this fraction of the radius of the anchor the brush counts as holding still.
const DWELL_RADIUS := 0.2
## Extra exposure per second of dwell, up to DWELL_MAX seconds (so at most 1 + 1.5 * 2 = 4x).
const DWELL_GAIN := 1.5
const DWELL_MAX := 2.0
## Exposure a click that is released in the same frame still gets, so a tap plants a copse.
const CLICK_SECONDS := 0.12
## A frame longer than this (a hitch) paints as if it were this long.
const MAX_FRAME_SECONDS := 0.1
## Flow (the Advanced strength multiplier) range.
const MIN_FLOW := 0.25
const MAX_FLOW := 2.0
const RAY_LENGTH := 500.0
const DOWNCAST_HEIGHT := 200.0
const TERRAIN_LAYER := 1
## Canopy fade radius as a multiple of the mode's reach (BrushMode.fade_focus; view-plane
## metres). The fade falls off from the centre to this radius, so it has to reach past the
## ring for the canopy over the ring's edge to open up.
const FADE_RADIUS_FACTOR := 1.35

## Remembered for the whole app session, like the Visuals drawer's last pane.
static var session_radius: float = DEFAULT_RADIUS
static var session_flow: float = 1.0

## The tool whose gestures the brush runs (null before one is picked), and its mode (a plain
## ring that starts nothing until then).
var tool: ToolDescriptor = null
var mode: BrushMode = BrushMode.new()
## The level's units for the modes' readouts (ScaleUtils): metres per grid cell, display
## units per cell, and their label. AuthoringController sets them from the level.
var unit_cell_m: float = LevelData.DEFAULT_GRID_CELL_SIZE
var unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL
var unit_label: String = LevelData.DEFAULT_DISPLAY_UNIT
var editor: AuthoringEditor = null
## While a mode that `fades` is the tool, the cursor is this manager's focus (set_focus), so
## canopies between the camera and the ground being worked fade like geometry over a token.
## Set by GameMap.setup_brush_tool(); null for none.
var occlusion_fade: OcclusionFadeManager = null
## FADE_RADIUS_FACTOR, as a var so a tuning probe can change it in a running game.
var fade_radius_factor: float = FADE_RADIUS_FACTOR
## The cursor's overlay and the drawing the modes share.
var cursor := BrushCursor.new()

## The pointer and the press, which the modes read (render jobs set them to drive the brush
## without input events): the pointer (screen), LMB down on the 3D view (a gesture in
## progress, or waiting for its ground point), where it was pressed and the modifiers held at
## the press, and the modifiers held now.
var pointer: Vector2 = Vector2.ZERO
var has_pointer: bool = false
var pressed: bool = false
var press_pending: bool = false
var press_position: Vector2 = Vector2.ZERO
var press_ctrl: bool = false
var press_shift: bool = false
var ctrl: bool = false
var shift: bool = false
## Where the pointer meets the ground this frame (Vector3.INF: nowhere), and the normal there.
var hit: Vector3 = Vector3.INF
var hit_normal: Vector3 = Vector3.UP
## A dab stroke is in progress, and how long the brush has dwelt (seconds).
var stroking: bool = false
var dwell: float = 0.0

var _camera: Camera3D = null
var _world_viewport: SubViewport = null
var _over_gui: Callable = Callable()
var _active: bool = false
## The modes made so far, by tool id (mode_for).
var _modes: Dictionary = {}
## The pointer the last sculpt hit was cast from (a still pointer keeps its ground point).
var _hit_pointer: Vector2 = Vector2.INF
var _last_dab: Vector3 = Vector3.INF
var _dwell_anchor: Vector3 = Vector3.INF


## What an input event means to the brush, given whether the mode `picks` targets, whether a
## press is held and whether a target is under the pointer. Pure: the whole input table in
## one place, and what the tests exercise.
static func decide(event: InputEvent, picks: bool, held: bool, over_target: bool) -> Action:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not button.pressed or not button.shift_pressed:
					return Action.NONE
				if picks and not over_target:
					return Action.NONE
				return (
					Action.GROW if button.button_index == MOUSE_BUTTON_WHEEL_UP else Action.SHRINK
				)
			MOUSE_BUTTON_RIGHT:
				if not button.pressed:
					return Action.SWALLOW
				if held:
					return Action.CANCEL
				if picks and over_target:
					return Action.REMOVE
				return Action.DESELECT
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					return Action.BEGIN
				return Action.END if held else Action.NONE
		return Action.NONE
	if event is InputEventMouseMotion:
		return Action.POINTER
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed:
			return Action.NONE
		match key.keycode:
			KEY_BRACKETRIGHT:
				return Action.GROW
			KEY_BRACKETLEFT:
				return Action.SHRINK
			KEY_DELETE, KEY_BACKSPACE:
				if picks and over_target and not held:
					return Action.REMOVE
			KEY_ESCAPE:
				# While a stroke or placement is held, Escape cancels it like RMB; otherwise
				# it goes on to the drawer (close, then leave).
				if held:
					return Action.CANCEL
	return Action.NONE


## The exposure multiplier after `seconds` of holding still.
static func dwell_gain(seconds: float) -> float:
	return 1.0 + DWELL_GAIN * clampf(seconds, 0.0, DWELL_MAX)


## `radius` stepped `steps` notches (positive grows), clamped to the brush range.
static func stepped_radius(radius: float, steps: int) -> float:
	return clampf(radius * pow(RADIUS_STEP, steps), MIN_RADIUS, MAX_RADIUS)


func _ready() -> void:
	set_process(false)
	# After GameMap and the camera controller, so the ray and the ring use this frame's
	# camera.
	process_priority = 1


func setup(cam: Camera3D, viewport: SubViewport, overlay_parent: Node, over_gui: Callable) -> void:
	_camera = cam
	_world_viewport = viewport
	_over_gui = over_gui
	cursor.setup(cam, viewport, overlay_parent, _on_draw)


func is_active() -> bool:
	return _active


## True while the left button is down on the 3D view: GameMap still hands this gesture its
## release when the pointer has wandered over a panel.
func is_dragging() -> bool:
	return pressed


func activate() -> void:
	if _active:
		return
	_active = true
	cursor.set_visible(true)
	set_process(true)
	toggled.emit(true)


func deactivate() -> void:
	if not _active:
		return
	finish_gesture()
	_active = false
	mode.leave(self)
	if occlusion_fade != null:
		occlusion_fade.clear_focus()
	cursor.set_visible(false)
	set_process(false)
	toggled.emit(false)


func toggle() -> void:
	if _active:
		deactivate()
	else:
		activate()


## The mode of `of_tool`, made on first use and kept for the brush's life, or null for a tool
## without brush gestures.
func mode_for(of_tool: ToolDescriptor) -> BrushMode:
	if of_tool == null or of_tool.brush_mode == null:
		return null
	if not _modes.has(of_tool.id):
		_modes[of_tool.id] = of_tool.brush_mode.new() as BrushMode
	return _modes[of_tool.id]


## Switches to `new_tool`'s mode (a tool without one is ignored). A gesture in progress is
## finished first.
func use_tool(new_tool: ToolDescriptor) -> void:
	var new_mode := mode_for(new_tool)
	if new_mode == null or new_tool == tool:
		return
	finish_gesture()
	mode.leave(self)
	tool = new_tool
	mode = new_mode
	# A water brush may be narrower than the other brushes (a brook); they start from MIN_RADIUS.
	set_radius(session_radius)
	redraw()


func get_radius() -> float:
	return session_radius


## Sets the brush size, clamped to the mode's min_radius() (MIN_RADIUS but for the Water
## tool, whose ankle-deep brook can be narrower) up to MAX_RADIUS.
func set_radius(radius: float) -> void:
	var clamped := clampf(radius, mode.min_radius(), MAX_RADIUS)
	if is_equal_approx(clamped, session_radius):
		return
	session_radius = clamped
	redraw()
	radius_changed.emit(session_radius)


func get_flow() -> float:
	return session_flow


func set_flow(flow: float) -> void:
	session_flow = clampf(flow, MIN_FLOW, MAX_FLOW)


## Ends whatever gesture is in progress, keeping its result (before an undo, a tool switch,
## or deactivation): a dab stroke is ended, and the mode keeps its own (BrushMode.end: a
## river being drawn is carved, a crossing's line placed, a prop edit committed).
func finish_gesture() -> void:
	pressed = false
	press_pending = false
	if editor != null and stroking:
		editor.end_stroke()
	mode.end(self)
	stroking = false


## Drops the gesture in progress, reverting it (RMB or Escape while a press is held).
func cancel_gesture() -> void:
	if editor != null and stroking:
		editor.cancel_stroke()
	mode.cancel(self)
	pressed = false
	press_pending = false
	stroking = false
	redraw()


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false
	if event is InputEventWithModifiers:
		var ctrl_now := (event as InputEventWithModifiers).ctrl_pressed
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_CTRL:
			ctrl_now = (event as InputEventKey).pressed
		var shift_now := (event as InputEventWithModifiers).shift_pressed
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_SHIFT:
			shift_now = (event as InputEventKey).pressed
		if ctrl_now != ctrl or shift_now != shift:
			ctrl = ctrl_now
			shift = shift_now
			redraw()
	var action := decide(event, mode.picks, pressed, mode.has_target())
	match action:
		Action.POINTER:
			pointer = (event as InputEventMouseMotion).position
			has_pointer = true
			return false
		Action.BEGIN:
			pointer = (event as InputEventMouseButton).position
			has_pointer = true
			pressed = true
			press_pending = true
			press_position = pointer
			press_ctrl = (event as InputEventMouseButton).ctrl_pressed
			press_shift = (event as InputEventMouseButton).shift_pressed
			return true
		Action.END:
			if press_pending:
				# Released within the frame it was pressed: resolve the click now.
				_resolve_hit()
				_start_gesture(CLICK_SECONDS)
			finish_gesture()
			return true
		Action.CANCEL:
			cancel_gesture()
			return true
		Action.DESELECT:
			deactivate()
			return true
		Action.GROW, Action.SHRINK:
			mode.step(self, 1 if action == Action.GROW else -1)
			return true
		Action.REMOVE:
			mode.remove_target(self)
			return true
		Action.SWALLOW:
			return true
	return false


func _process(delta: float) -> void:
	var seconds := minf(delta, MAX_FRAME_SECONDS)
	_resolve_hit()
	_update_fade()
	if press_pending and hit != Vector3.INF:
		_start_gesture(0.0)
	mode.frame(self)
	if stroking and hit != Vector3.INF:
		_paint(seconds)
	if editor != null:
		editor.tick(seconds)
	redraw()


## Starts the gesture a press asked for, now that the pointer's ground point is known.
## `click_seconds` > 0 is a click already released: a dab stroke gets that much exposure.
func _start_gesture(click_seconds: float) -> void:
	press_pending = false
	if editor == null or hit == Vector3.INF:
		return
	if not mode.press(self):
		return
	stroking = true
	_hit_pointer = pointer
	_last_dab = hit
	dwell = 0.0
	_dwell_anchor = hit
	if click_seconds > 0.0:
		editor.stroke_dab(hit, hit, mode.stroke_radius(self), click_seconds * session_flow)
		editor.flush()
		mode.dabbed(self)


func _paint(seconds: float) -> void:
	if _dwell_anchor.distance_to(hit) <= session_radius * DWELL_RADIUS:
		dwell += seconds
	else:
		dwell = 0.0
		_dwell_anchor = hit
	var exposure := seconds * session_flow * dwell_gain(dwell)
	editor.stroke_dab(_last_dab, hit, mode.stroke_radius(self), exposure)
	editor.flush()
	_last_dab = hit
	mode.dabbed(self)


## Where the pointer meets the ground this frame (layer 1), or Vector3.INF.
func _resolve_hit() -> void:
	var previous := hit
	hit = Vector3.INF
	if not has_pointer or _camera == null or _world_viewport == null:
		return
	if _over_gui.is_valid() and _over_gui.call() and not pressed:
		return
	var origin := _camera.project_ray_origin(pointer)
	var direction := _camera.project_ray_normal(pointer)
	if editor != null and editor.is_sculpting():
		if pointer == _hit_pointer and previous != Vector3.INF:
			# A still pointer keeps its ground point; only its height follows the ground.
			hit = Vector3(previous.x, editor.ground_height_at(previous), previous.z)
			return
		_hit_pointer = pointer
		# The collision is brought up to date when the stroke ends; until then the ground
		# the brush is shaping is only in the document, so the ray marches its heights.
		var ground := editor.raycast_ground(origin, direction)
		if not ground.is_empty():
			hit = ground.position
			hit_normal = ground.normal
		return
	var space := _world_viewport.find_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * RAY_LENGTH)
	query.collision_mask = TERRAIN_LAYER
	# Every brush edits the ground under a bridge or its stones, never their tops; the Bridge
	# tool picks a crossing where it is drawn (a deck stands well above the bed under it).
	if not mode.sees_crossings:
		query.exclude = _crossing_bodies()
	var result := space.intersect_ray(query)
	if result.is_empty():
		# A mode may meet its own ground past the map edge (a river drawn on past it, P6-1).
		hit = mode.hit_past_edge(origin, direction)
		if hit != Vector3.INF:
			hit_normal = Vector3.UP
		return
	hit = result.position
	hit_normal = result.normal


## A mode that `fades` makes the cursor the occlusion fade's focus (BrushMode.fade_focus), so
## the canopy over it opens up; any other mode, or no ground under the pointer, clears it.
func _update_fade() -> void:
	if occlusion_fade == null:
		return
	if _active and mode.fades and hit != Vector3.INF:
		var focus := mode.fade_focus(self)
		occlusion_fade.set_focus(
			Vector3(focus.x, focus.y, focus.z), focus.w * fade_radius_factor
		)
	else:
		occlusion_fade.clear_focus()


## A point bedded on the ground below `point`: DragPlaceController's downward terrain ray,
## so a placed prop stands on the ground rather than on whatever the camera ray met.
func bedded(point: Vector3) -> Vector3:
	var space := _world_viewport.find_world_3d().direct_space_state
	var down := WaterSurface.cast_down(
		space, point, point.y + DOWNCAST_HEIGHT, TERRAIN_LAYER, _crossing_bodies()
	)
	return down.position if not down.is_empty() else point


## The map's crossing bodies (AuthoredCrossings.exclude_of), which the brush rays skip.
func _crossing_bodies() -> Array[RID]:
	if editor == null:
		return []
	return AuthoredCrossings.exclude_of(editor.map_root)


func redraw() -> void:
	cursor.redraw()


## The cursor is the mode's to draw, at the pointer's ground point.
func _on_draw() -> void:
	if not _active or _camera == null or hit == Vector3.INF:
		return
	mode.draw_cursor(self, cursor)
