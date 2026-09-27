class_name BrushTool
extends Node

## Authoring mode's brush: the gestures of the Biome, Thin / Clear, Place and Sculpt tools
## and the cursor that shows them. What a gesture does to the map is AuthoringEditor's; this
## node turns input into calls on it.
##
## Modal tool contract (MeasureTool, SunGizmoTool): `toggled`, is_active(), idempotent
## activate() / deactivate(), toggle(), handle_input() -> bool, is_dragging(), setup().
## GameMap owns it (setup_brush_tool()), dispatches input to it from _input() with the GUI
## click guard, keeps it exclusive with the other two tools, and CameraController does not
## start a right-button pan while it is active (RMB belongs to the brush).
##
## Pointer. Handlers read `event.position` (never the viewport's cached mouse position,
## which injected events do not update) and only record it; _process raycasts once per frame
## on collision layer 1, which both AuthoredTerrain and a Blender map's collision use. A
## press waits for that raycast too, unless it is released in the same frame (a click),
## which then resolves at once.
##
## Gestures (decide() is the pure input table):
##   LMB drag           paint / thin; with Ctrl held at the press, clear
##   hold still         strength builds: exposure is multiplied by 1 + DWELL_GAIN * dwell,
##                      dwell being how long the brush has stayed within DWELL_RADIUS of its
##                      anchor (capped at DWELL_MAX); moving resets it, so moving spreads
##   plain wheel        camera zoom (not consumed)
##   Shift+wheel, [ ]   brush size (MIN_RADIUS..MAX_RADIUS, remembered for the app session)
##   RMB press          cancel the stroke in progress (reverting it); when idle, deselect
##   Escape             while a stroke is held, cancel it as RMB does (idle: not taken)
##   Place: click       place a prop, bedded and turned at random; drag while pressed to
##                      turn it toward the pointer; Shift+wheel over a prop scales it;
##                      RMB or Delete over a prop removes it
##   Sculpt: LMB drag   the picked tile's operation (sculpt_op(): Raise, Smooth, Flatten,
##                      Tier); Ctrl at the press lowers (Raise) or cuts a tier down (Tier);
##                      Shift at the press smooths whichever tile is picked. Flatten holds
##                      the ground height under the press; Tier builds toward the tier
##                      AuthoringEditor.tier_target() picks at the press.
##
## Sculpting moves the ground under a still pointer, so while a sculpt stroke is held and
## the pointer has not moved the brush keeps its ground point (only its height follows the
## ground) instead of re-casting the ray, which would walk a growing hill toward the camera.
##
## Cursor. A ring on the ground at the hit point with the brush radius, conforming to the
## ground (one downward ray per ring point, cached until the brush moves; while sculpting,
## the document's own heights every frame, since the ground under a still ring moves), drawn
## on the measure overlay layer so it stays crisp above the lo-fi pass: a dark under-stroke
## and a light over-stroke read on any ground in either lo-fi theme. The tint hints the tool
## (the biome's own colour, warm white to thin, red to clear, sand to raise, blue-grey to
## lower), a faint fill shows the reach (a fan from the centre, never a triangulated
## outline: a ring conformed over steep ground projects to a self-intersecting outline,
## which the canvas cannot triangulate and reports "Invalid polygon data, triangulation
## failed"), and an inner ring brightens as dwell builds strength. Tier and Flatten show a
## small readout under the ring: the tier the stroke builds and its elevation in the
## level's units ("Tier 1  +5 ft"), or the height Flatten holds.

signal toggled(active: bool)
## The brush radius changed (world metres), by gesture or set_radius().
signal radius_changed(radius: float)

enum Mode { BIOME, THIN, PLACE, SCULPT }
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
## Pointer travel (px) after a Place press before the drag turns the prop.
const TURN_START_PX := 10.0
const RING_SEGMENTS := 48
## Ring points re-conform to the ground when the centre moves this fraction of the radius.
const RING_REFRESH := 0.04
const RAY_LENGTH := 500.0
const DOWNCAST_HEIGHT := 200.0
const TERRAIN_LAYER := 1
const SHADOW_COLOR := Color(0.05, 0.04, 0.05, 0.55)
const THIN_TINT := Color(0.98, 0.93, 0.82)
const CLEAR_TINT := Color(1.0, 0.52, 0.42)
const PLACE_TINT := ThemeColors.ACCENT
const RAISE_TINT := Color(1.0, 0.86, 0.62)
const LOWER_TINT := Color(0.66, 0.78, 1.0)
const SMOOTH_TINT := Color(0.86, 0.96, 0.9)
const PLACE_MARKER_M := 0.6
## The Tier / Flatten readout under the ring (MapOverlayUtils.create_label_panel's look,
## smaller: it accompanies the cursor rather than reporting a measurement).
const READOUT_FONT_SIZE := 13
const READOUT_COLOR := Color(1.0, 0.95, 0.6)
const READOUT_GAP_PX := 14.0
## Thin / Clear canopy fade radius as a multiple of the brush radius (view-plane metres).
## The fade falls off from the centre to this radius, so it has to reach past the ring for
## the canopy over the ring's edge to open up.
const FADE_RADIUS_FACTOR := 1.35

## Remembered for the whole app session, like the Visuals drawer's last pane.
static var session_radius: float = DEFAULT_RADIUS
static var session_flow: float = 1.0

var mode: Mode = Mode.BIOME
## The biome the Biome tool paints.
var biome_id: String = ""
## The species rule the Place tool places (AuthoringEditor.species_rule), or {}.
var place_rule: Dictionary = {}
## Ring tint of the Biome tool (the biome's colour).
var biome_tint: Color = Color(0.7, 0.9, 0.6)
## The Sculpt tile picked: HeightBrush.RAISE, SMOOTH, FLATTEN or TIER (sculpt_op() applies
## the modifiers).
var sculpt_tile: int = HeightBrush.RAISE
## The level's units for the readout (ScaleUtils): metres per grid cell, display units per
## cell, and their label. AuthoringController sets them from the level.
var unit_cell_m: float = LevelData.DEFAULT_GRID_CELL_SIZE
var unit_per_cell: float = LevelData.DEFAULT_DISPLAY_UNIT_PER_CELL
var unit_label: String = LevelData.DEFAULT_DISPLAY_UNIT
var editor: AuthoringEditor = null
## While Thin / Clear is the tool, the ring is this manager's focus (set_focus), so canopies
## between the camera and the ground being thinned fade like geometry over a token. Set by
## GameMap.setup_brush_tool(); null for none.
var occlusion_fade: OcclusionFadeManager = null
## FADE_RADIUS_FACTOR, as a var so a tuning probe can change it in a running game.
var fade_radius_factor: float = FADE_RADIUS_FACTOR

var _camera: Camera3D = null
var _world_viewport: SubViewport = null
var _over_gui: Callable = Callable()
var _canvas_layer: CanvasLayer = null
var _draw_control: Control = null

var _active: bool = false
## LMB is down on the 3D view (a stroke or a placement in progress, or waiting to start).
var _pressed: bool = false
var _press_pending: bool = false
var _press_position: Vector2 = Vector2.ZERO
var _press_ctrl: bool = false
var _press_shift: bool = false
var _stroking: bool = false
## The sculpt stroke in progress: its HeightBrush operation and target (world Y; tier level
## for Tier), for the tint and the readout.
var _stroke_op: int = -1
var _stroke_target_y: float = 0.0
var _stroke_level: int = 0
## The pointer the last sculpt hit was cast from (a still pointer keeps its ground point).
var _hit_pointer: Vector2 = Vector2.INF
## Tier readout while hovering, recomputed when the sample under the brush, the radius or
## Ctrl change: {"key": Array, "level": int}.
var _tier_hover: Dictionary = {}
var _readout_box: StyleBoxFlat = null
var _pointer: Vector2 = Vector2.ZERO
var _has_pointer: bool = false
var _ctrl: bool = false
var _shift: bool = false
var _hit: Vector3 = Vector3.INF
var _hit_normal: Vector3 = Vector3.UP
var _last_dab: Vector3 = Vector3.INF
var _dwell: float = 0.0
var _dwell_anchor: Vector3 = Vector3.INF
## Place: the prop being placed and turned, and the prop under the pointer.
var _placing: Dictionary = {}
var _turning: bool = false
var _hover: Dictionary = {}
var _ring_world := PackedVector3Array()
var _ring_centre: Vector3 = Vector3.INF
var _ring_radius: float = -1.0


## What an input event means to the brush in `tool_mode`, given whether a stroke or
## placement is in progress and whether a placed prop is under the pointer. Pure: the whole
## input table in one place, and what the tests exercise.
static func decide(event: InputEvent, tool_mode: int, pressed: bool, over_prop: bool) -> Action:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if not button.pressed or not button.shift_pressed:
					return Action.NONE
				if tool_mode == Mode.PLACE and not over_prop:
					return Action.NONE
				return (
					Action.GROW if button.button_index == MOUSE_BUTTON_WHEEL_UP else Action.SHRINK
				)
			MOUSE_BUTTON_RIGHT:
				if not button.pressed:
					return Action.SWALLOW
				if pressed:
					return Action.CANCEL
				if tool_mode == Mode.PLACE and over_prop:
					return Action.REMOVE
				return Action.DESELECT
			MOUSE_BUTTON_LEFT:
				if button.pressed:
					return Action.BEGIN
				return Action.END if pressed else Action.NONE
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
				if tool_mode == Mode.PLACE and over_prop and not pressed:
					return Action.REMOVE
			KEY_ESCAPE:
				# While a stroke or placement is held, Escape cancels it like RMB; otherwise
				# it goes on to the drawer (close, then leave).
				if pressed:
					return Action.CANCEL
	return Action.NONE


## The HeightBrush operation a Sculpt press makes with tile `tile` picked and Ctrl / Shift
## held at the press: Shift smooths from any tile; Ctrl lowers with Raise and cuts with
## Tier (Smooth and Flatten have no Ctrl variant). Pure.
static func sculpt_op(tile: int, ctrl: bool, shift: bool) -> int:
	if shift:
		return HeightBrush.SMOOTH
	match tile:
		HeightBrush.RAISE, HeightBrush.LOWER:
			return HeightBrush.LOWER if ctrl else HeightBrush.RAISE
		HeightBrush.TIER, HeightBrush.TIER_CUT:
			return HeightBrush.TIER_CUT if ctrl else HeightBrush.TIER
		HeightBrush.FLATTEN:
			return HeightBrush.FLATTEN
	return HeightBrush.SMOOTH


## A height (metres above the map's base ground) in the level's display units, signed:
## "+5 ft", "0 ft", "-10 ft". Pure.
static func format_elevation(
	height_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var value := roundi(ScaleUtils.world_to_display(height_m, cell_m, per_cell))
	if value == 0:
		return "0 %s" % label
	return "%+d %s" % [value, label]


## The readout under the ring for a Tier stroke toward tier `level` of height `height_m`
## ("Tier 1  +5 ft"; level 0 reads "Ground"), in the given units. Pure.
static func tier_readout(
	level: int, height_m: float, cell_m: float, per_cell: float, label: String
) -> String:
	var title := "Ground" if level == 0 else "Tier %d" % level
	return "%s  %s" % [title, format_elevation(height_m, cell_m, per_cell, label)]


## Triangle-fan indices filling a closed outline of `outline_count` points (the last one
## repeating the first, as the ring's do) around a centre vertex at index `outline_count`:
## drawn with explicit indices, so it never needs triangulating. Pure.
static func fan_indices(outline_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for i in outline_count - 1:
		indices.append_array([outline_count, i, i + 1])
	return indices


## The exposure multiplier after `dwell` seconds of holding still.
static func dwell_gain(dwell: float) -> float:
	return 1.0 + DWELL_GAIN * clampf(dwell, 0.0, DWELL_MAX)


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
	var overlay: Dictionary = MapOverlayUtils.create_overlay(
		overlay_parent, Constants.LAYER_MEASURE_OVERLAY, _on_draw
	)
	_canvas_layer = overlay.canvas_layer
	_draw_control = overlay.draw_control
	_canvas_layer.visible = false


func is_active() -> bool:
	return _active


## True while the left button is down on the 3D view: GameMap still hands this gesture its
## release when the pointer has wandered over a panel.
func is_dragging() -> bool:
	return _pressed


func activate() -> void:
	if _active:
		return
	_active = true
	if _canvas_layer:
		_canvas_layer.visible = true
	set_process(true)
	toggled.emit(true)


func deactivate() -> void:
	if not _active:
		return
	finish_gesture()
	_active = false
	_hover = {}
	if occlusion_fade != null:
		occlusion_fade.clear_focus()
	if _canvas_layer:
		_canvas_layer.visible = false
	set_process(false)
	toggled.emit(false)


func toggle() -> void:
	if _active:
		deactivate()
	else:
		activate()


## Switches tool. A gesture in progress is finished first.
func set_mode(new_mode: Mode) -> void:
	if new_mode == mode:
		return
	finish_gesture()
	mode = new_mode
	_hover = {}
	_redraw()


func get_radius() -> float:
	return session_radius


func set_radius(radius: float) -> void:
	var clamped := clampf(radius, MIN_RADIUS, MAX_RADIUS)
	if is_equal_approx(clamped, session_radius):
		return
	session_radius = clamped
	_redraw()
	radius_changed.emit(session_radius)


func get_flow() -> float:
	return session_flow


func set_flow(flow: float) -> void:
	session_flow = clampf(flow, MIN_FLOW, MAX_FLOW)


## Ends whatever gesture is in progress, keeping its result (before an undo, a tool switch,
## or deactivation).
func finish_gesture() -> void:
	_pressed = false
	_press_pending = false
	if editor != null:
		if _stroking:
			editor.end_stroke()
		editor.commit_prop_edit()
	_stroking = false
	_stroke_op = -1
	_placing = {}
	_turning = false


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false
	if event is InputEventWithModifiers:
		var ctrl := (event as InputEventWithModifiers).ctrl_pressed
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_CTRL:
			ctrl = (event as InputEventKey).pressed
		var shift := (event as InputEventWithModifiers).shift_pressed
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_SHIFT:
			shift = (event as InputEventKey).pressed
		if ctrl != _ctrl or shift != _shift:
			_ctrl = ctrl
			_shift = shift
			_redraw()
	var action := decide(event, mode, _pressed, not _hover.is_empty())
	match action:
		Action.POINTER:
			_pointer = (event as InputEventMouseMotion).position
			_has_pointer = true
			return false
		Action.BEGIN:
			_pointer = (event as InputEventMouseButton).position
			_has_pointer = true
			_pressed = true
			_press_pending = true
			_press_position = _pointer
			_press_ctrl = (event as InputEventMouseButton).ctrl_pressed
			_press_shift = (event as InputEventMouseButton).shift_pressed
			return true
		Action.END:
			if _press_pending:
				# Released within the frame it was pressed: resolve the click now.
				_resolve_hit()
				_start_gesture(CLICK_SECONDS)
			finish_gesture()
			return true
		Action.CANCEL:
			_cancel_gesture()
			return true
		Action.DESELECT:
			deactivate()
			return true
		Action.GROW, Action.SHRINK:
			var steps := 1 if action == Action.GROW else -1
			if mode == Mode.PLACE:
				_scale_hovered(steps)
			else:
				set_radius(stepped_radius(session_radius, steps))
			return true
		Action.REMOVE:
			if editor != null and not _hover.is_empty():
				editor.remove_prop(_hover)
				_hover = {}
				_redraw()
			return true
		Action.SWALLOW:
			return true
	return false


func _cancel_gesture() -> void:
	if editor != null:
		if _stroking:
			editor.cancel_stroke()
		if not _placing.is_empty():
			editor.cancel_prop_edit()
	_pressed = false
	_press_pending = false
	_stroking = false
	_stroke_op = -1
	_placing = {}
	_turning = false
	_redraw()


func _scale_hovered(steps: int) -> void:
	if editor == null or _hover.is_empty():
		return
	var rule := place_rule
	var asset_rule := editor.rule_for_asset(String(_hover.asset_id))
	if not asset_rule.is_empty():
		rule = asset_rule
	var radius: float = _hover.get("radius", 0.0)
	var old_scale: float = (_hover.row as PackedFloat32Array)[7]
	_hover = editor.scale_prop(_hover, steps, rule)
	var new_scale: float = (_hover.row as PackedFloat32Array)[7]
	_hover["radius"] = radius * new_scale / maxf(old_scale, 0.0001)
	_redraw()


func _process(delta: float) -> void:
	var seconds := minf(delta, MAX_FRAME_SECONDS)
	_resolve_hit()
	_update_fade()
	if _press_pending and _hit != Vector3.INF:
		_start_gesture(0.0)
	if _stroking and _hit != Vector3.INF:
		_paint(seconds)
	elif not _placing.is_empty():
		_turn_placing()
	elif mode == Mode.PLACE and not _pressed:
		_update_hover()
	if editor != null:
		editor.tick(seconds)
	_redraw()


## Starts the gesture a press asked for, now that the pointer's ground point is known.
## `click_seconds` > 0 is a click already released: a paint stroke gets that much exposure.
func _start_gesture(click_seconds: float) -> void:
	_press_pending = false
	if editor == null or _hit == Vector3.INF:
		return
	if mode == Mode.PLACE:
		# The hover is from the last frame; the pointer may have jumped since (a press that
		# arrives with its own motion), so look again at the press point.
		_update_hover()
		if _hover.is_empty() and not place_rule.is_empty():
			_placing = editor.place_prop(place_rule, _bedded(_hit), _hit_normal)
		return
	if mode == Mode.SCULPT:
		if not _begin_sculpt():
			return
	else:
		var stroke_mode := MaskBrush.PAINT
		if mode == Mode.THIN:
			stroke_mode = MaskBrush.CLEAR if _press_ctrl else MaskBrush.THIN
		if not editor.begin_stroke(stroke_mode, biome_id):
			return
	_stroking = true
	_last_dab = _hit
	_dwell = 0.0
	_dwell_anchor = _hit
	if click_seconds > 0.0:
		editor.stroke_dab(_hit, _hit, session_radius, click_seconds * session_flow)
		editor.flush()


## Starts the sculpt stroke of the picked tile and the press's modifiers, with its target:
## the ground height under the press for Flatten, the tier tier_target() picks for Tier.
func _begin_sculpt() -> bool:
	var op := sculpt_op(sculpt_tile, _press_ctrl, _press_shift)
	var target_y := 0.0
	_stroke_level = 0
	if op == HeightBrush.FLATTEN:
		target_y = editor.ground_height_at(_hit)
	elif HeightBrush.is_tier(op):
		var tier := editor.tier_target(_hit, session_radius, op == HeightBrush.TIER_CUT)
		target_y = tier.y
		_stroke_level = tier.level
	if not editor.begin_height_stroke(op, target_y):
		return false
	_stroke_op = op
	_stroke_target_y = target_y
	_hit_pointer = _pointer
	return true


func _paint(seconds: float) -> void:
	if _dwell_anchor.distance_to(_hit) <= session_radius * DWELL_RADIUS:
		_dwell += seconds
	else:
		_dwell = 0.0
		_dwell_anchor = _hit
	var exposure := seconds * session_flow * dwell_gain(_dwell)
	editor.stroke_dab(_last_dab, _hit, session_radius, exposure)
	editor.flush()
	_last_dab = _hit


## Place drag: once the pointer has moved TURN_START_PX, the prop turns to face it.
func _turn_placing() -> void:
	if _hit == Vector3.INF or editor == null:
		return
	if not _turning and _pointer.distance_to(_press_position) < TURN_START_PX:
		return
	_turning = true
	var centre := editor.prop_position(_placing)
	var toward := _hit - centre
	if Vector2(toward.x, toward.z).length() < 0.05:
		return
	_placing = editor.turn_prop(_placing, atan2(-toward.x, -toward.z))


func _update_hover() -> void:
	if editor == null or _hit == Vector3.INF:
		_hover = {}
		return
	var found := editor.prop_at(_hit)
	if found.get("row") != _hover.get("row"):
		editor.commit_prop_edit()
	_hover = found


## Where the pointer meets the ground this frame (layer 1), or Vector3.INF.
func _resolve_hit() -> void:
	var previous := _hit
	_hit = Vector3.INF
	if not _has_pointer or _camera == null or _world_viewport == null:
		return
	if _over_gui.is_valid() and _over_gui.call() and not _pressed:
		return
	var origin := _camera.project_ray_origin(_pointer)
	if editor != null and editor.is_sculpting():
		if _pointer == _hit_pointer and previous != Vector3.INF:
			# A still pointer keeps its ground point; only its height follows the ground.
			_hit = Vector3(previous.x, editor.ground_height_at(previous), previous.z)
			return
		_hit_pointer = _pointer
		# The collision is brought up to date when the stroke ends; until then the ground
		# the brush is shaping is only in the document, so the ray marches its heights.
		var ground := editor.raycast_ground(origin, _camera.project_ray_normal(_pointer))
		if not ground.is_empty():
			_hit = ground.position
			_hit_normal = ground.normal
		return
	var space := _world_viewport.find_world_3d().direct_space_state
	if space == null:
		return
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + _camera.project_ray_normal(_pointer) * RAY_LENGTH
	)
	query.collision_mask = TERRAIN_LAYER
	var result := space.intersect_ray(query)
	if result.is_empty():
		return
	_hit = result.position
	_hit_normal = result.normal


## Thin / Clear and Sculpt: the ring is the occlusion fade's focus, so the canopy over it
## opens up (the ground being thinned or shaped stays in view under a forest). Any other
## tool, or no ground under the pointer, clears it.
func _update_fade() -> void:
	if occlusion_fade == null:
		return
	if _active and (mode == Mode.THIN or mode == Mode.SCULPT) and _hit != Vector3.INF:
		occlusion_fade.set_focus(_hit, session_radius * fade_radius_factor)
	else:
		occlusion_fade.clear_focus()


## A point bedded on the ground below `point`: DragPlaceController's downward terrain ray,
## so a placed prop stands on the ground rather than on whatever the camera ray met.
func _bedded(point: Vector3) -> Vector3:
	var space := _world_viewport.find_world_3d().direct_space_state
	var ground := DragPlaceController.raycast_terrain_down(space, point, point.y + DOWNCAST_HEIGHT)
	return ground if ground != Vector3.INF else point


func _redraw() -> void:
	if _draw_control:
		_draw_control.queue_redraw()


# ============================================================================
# Cursor
# ============================================================================


func _tint() -> Color:
	match mode:
		Mode.BIOME:
			return biome_tint
		Mode.THIN:
			var clearing := _press_ctrl if _stroking else _ctrl
			return CLEAR_TINT if clearing else THIN_TINT
		Mode.SCULPT:
			match _cursor_op():
				HeightBrush.RAISE, HeightBrush.TIER:
					return RAISE_TINT
				HeightBrush.LOWER, HeightBrush.TIER_CUT:
					return LOWER_TINT
				HeightBrush.FLATTEN:
					return PLACE_TINT
			return SMOOTH_TINT
	return PLACE_TINT


## The sculpt operation the cursor stands for: the stroke's while one is held, else what a
## press would make now (the modifiers held at this moment).
func _cursor_op() -> int:
	if _stroke_op >= 0:
		return _stroke_op
	return sculpt_op(sculpt_tile, _ctrl, _shift)


func _on_draw() -> void:
	if not _active or _camera == null or _hit == Vector3.INF:
		return
	if mode == Mode.PLACE:
		_draw_place_cursor()
		return
	_conform_ring(_hit, session_radius)
	var tint := _tint()
	var outline := _project(_ring_world, Vector3.ZERO, 1.0)
	_fill_fan(outline, _camera.unproject_position(_hit), Color(tint, 0.10))
	_stroke_ring(outline, tint, 2.0)
	if _stroking:
		# The half-strength contour, brightening as dwell builds strength.
		var strength := clampf(_dwell / DWELL_MAX, 0.0, 1.0)
		var inner := _project(_ring_world, _hit, 0.54)
		_draw_control.draw_polyline(inner, Color(tint, 0.25 + 0.6 * strength), 1.5, true)
	var centre := _camera.unproject_position(_hit)
	_draw_control.draw_circle(centre, 2.5, SHADOW_COLOR)
	_draw_control.draw_circle(centre, 1.5, tint)
	if mode == Mode.SCULPT:
		var text := _readout_text()
		if text != "":
			_draw_readout(text, outline)


## The ring's reach, filled as a fan from `centre` (see the header: an outline conformed
## over steep ground can cross itself, which a triangulated polygon cannot draw).
func _fill_fan(outline: PackedVector2Array, centre: Vector2, color: Color) -> void:
	var points := outline.duplicate()
	points.append(centre)
	var colors := PackedColorArray()
	colors.resize(points.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(
		_draw_control.get_canvas_item(), fan_indices(outline.size()), points, colors
	)


## The Tier or Flatten readout for the cursor now, or "" (other operations show none).
func _readout_text() -> String:
	var op := _cursor_op()
	if HeightBrush.is_tier(op):
		var level := _stroke_level if _stroke_op >= 0 else _hover_tier_level(op)
		var tier_m := editor.document.tier_height_m if editor != null else unit_cell_m
		return tier_readout(
			level, HeightBrush.tier_height(level, tier_m), unit_cell_m, unit_per_cell, unit_label
		)
	if op == HeightBrush.FLATTEN:
		var y := _stroke_target_y if _stroke_op >= 0 else _hit.y
		return "Flatten  " + format_elevation(y, unit_cell_m, unit_per_cell, unit_label)
	return ""


## The tier a press here would build (cached per brush sample, radius and Ctrl).
func _hover_tier_level(op: int) -> int:
	if editor == null:
		return 0
	var at := editor.document.world_to_sample(editor.to_map_xz(_hit)).round()
	var key := [at, session_radius, op]
	if _tier_hover.get("key") != key:
		var tier := editor.tier_target(_hit, session_radius, op == HeightBrush.TIER_CUT)
		_tier_hover = {"key": key, "level": tier.level}
	return int(_tier_hover.level)


## Draws `text` in a small dark pill just below the ring's lowest point on screen.
func _draw_readout(text: String, outline: PackedVector2Array) -> void:
	var font := _draw_control.get_theme_default_font()
	if font == null:
		return
	var bottom := -INF
	var centre_x := 0.0
	for point in outline:
		bottom = maxf(bottom, point.y)
		centre_x += point.x
	centre_x /= maxf(1.0, float(outline.size()))
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE)
	var pad := Vector2(7.0, 3.0)
	var box := Rect2(
		Vector2(centre_x - size.x * 0.5, bottom + READOUT_GAP_PX) - pad, size + pad * 2.0
	)
	if _readout_box == null:
		_readout_box = StyleBoxFlat.new()
		_readout_box.bg_color = Color(0.0, 0.0, 0.0, 0.6)
		_readout_box.set_corner_radius_all(4)
	_draw_control.draw_style_box(_readout_box, box)
	var baseline := box.position + pad + Vector2(0.0, font.get_ascent(READOUT_FONT_SIZE))
	_draw_control.draw_string(
		font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, READOUT_FONT_SIZE, READOUT_COLOR
	)


func _draw_place_cursor() -> void:
	if not _hover.is_empty() and _placing.is_empty():
		var centre := editor.prop_position(_hover)
		_draw_flat_ring(centre, float(_hover.get("radius", 1.0)), PLACE_TINT, 2.5)
		return
	if not _placing.is_empty():
		_draw_flat_ring(editor.prop_position(_placing), PLACE_MARKER_M, PLACE_TINT, 2.0)
		return
	_draw_flat_ring(_hit, PLACE_MARKER_M, Color(PLACE_TINT, 0.8), 1.5)


## Re-conforms the ring's world points to the ground when the brush moved or resized; while
## sculpting, every frame from the document's heights (the ground moves under a still ring,
## and the collision only catches up when the stroke ends).
func _conform_ring(centre: Vector3, radius: float) -> void:
	if mode == Mode.SCULPT and editor != null and editor.can_sculpt():
		_ring_world.resize(RING_SEGMENTS + 1)
		for i in RING_SEGMENTS + 1:
			var angle := TAU * float(i % RING_SEGMENTS) / float(RING_SEGMENTS)
			var point := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
			point.y = editor.ground_height_at(point) + 0.05
			_ring_world[i] = point
		# Forces the cached path to re-conform when the tool changes.
		_ring_radius = -1.0
		return
	if (
		_ring_world.size() == RING_SEGMENTS + 1
		and is_equal_approx(radius, _ring_radius)
		and _ring_centre.distance_to(centre) < radius * RING_REFRESH
	):
		return
	_ring_centre = centre
	_ring_radius = radius
	_ring_world.resize(RING_SEGMENTS + 1)
	var space := _world_viewport.find_world_3d().direct_space_state
	for i in RING_SEGMENTS + 1:
		var angle := TAU * float(i % RING_SEGMENTS) / float(RING_SEGMENTS)
		var point := centre + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var ground := DragPlaceController.raycast_terrain_down(
			space, point, centre.y + DOWNCAST_HEIGHT
		)
		_ring_world[i] = (ground if ground != Vector3.INF else point) + Vector3.UP * 0.05


## The ring's points on screen, scaled about `pivot` by `scale` (1: the ring itself).
func _project(points: PackedVector3Array, pivot: Vector3, scale: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		var at := point if scale == 1.0 else pivot + (point - pivot) * scale
		out.append(_camera.unproject_position(at))
	return out


func _stroke_ring(points: PackedVector2Array, tint: Color, width: float) -> void:
	_draw_control.draw_polyline(points, SHADOW_COLOR, width + 2.0, true)
	_draw_control.draw_polyline(points, tint, width, true)


func _draw_flat_ring(centre: Vector3, radius: float, tint: Color, width: float) -> void:
	var points := PackedVector2Array()
	for i in RING_SEGMENTS + 1:
		var angle := TAU * float(i) / float(RING_SEGMENTS)
		points.append(
			_camera.unproject_position(
				centre + Vector3(cos(angle), 0.05, sin(angle)) * Vector3(radius, 1.0, radius)
			)
		)
	_stroke_ring(points, tint, width)
