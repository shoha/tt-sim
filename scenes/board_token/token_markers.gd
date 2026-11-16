class_name TokenMarkers
extends Node3D

## The token marker: from straight above an avatar is a 20 px speck at the usual zoom
## (camera-2, 2026-11-02), so every token gets a map pin drawn on top of the board: a round head
## holding the token's own picture (TokenPortraits) with a short tail whose tip touches the top
## edge of the token, so the token itself is never covered. The head is HEAD_PX across whatever
## the zoom; the tip stands on the token's edge as it looks from the camera (a large token's
## footprint edge, a standing figure's head), found from the token's footprint and height.
##
## When it shows is Settings > Graphics > "Token pins" (`mode`, graphics/token_pins): ALWAYS
## (the default since painter-look-ghost2, 2026-11-15: a small token such as Eevee under foliage
## or behind a wall is found by its pin, whatever the camera) or TOP_DOWN (the earlier rule: off
## below 55 degrees of camera pitch, full from 70, CameraRig.marker_strength, where the model
## reads and the token ghost shows a token under cover). In ALWAYS the pin is quiet at low pitch,
## a QUIET_HEAD_PX head at QUIET_ALPHA opacity so it does not clutter the table view, and grows
## to the full HEAD_PX head and opacity as the camera climbs from 55 to 70 degrees (the same
## smoothstep); the hovered pin is full strength at any pitch. The quiet pin is still a target.
##
## Hover and click (camerarig-5): the pin is large (44 px, constant in the world viewport's own
## pixels, which under the canvas_items stretch are the UI's pixels, so it grows and shrinks
## with the window as the UI does) and is a target. The pin whose head the pointer is over
## draws in front of every other (it is moved to the end of the instance order, still one draw
## call), a tenth larger with a brighter rim; where several heads overlap the pointer, the one
## whose centre is nearest wins. A left press on a pin hands that token's DraggableToken the
## same press a click on its body would (Draggable3D.press_at), so it picks the token up with
## the same permission rules, and the press is consumed only when that press took; a hit test
## is the head circle, never the quad. Both work only while the pin is solid enough to be a
## target (HIT_MIN_STRENGTH) and a token with no pin (hidden from a player) is no target.
##
## One MultiMesh of camera-facing quads with a no-depth-test shader (shaders/token_marker.gdshader):
## one draw call whatever the token count (the pictures are cells of one atlas texture); in
## TOP_DOWN nothing at all while the pitch is low (the node does no work below the threshold, and
## the atlas is not even made). Pins are drawn from the top of the screen down, so a pin lower on
## the screen lies over one above it. The pin's body colour is the token's own: the most vivid
## colour of its palette texture, material or vertex colours (what the token ghost is dressed
## in), made readable; it is the disc a token shows until its picture is ready.
##
## A token the players cannot see (BoardToken.is_visible_to_players false) gets no pin for a
## player and a dimmed one for the GM, as the token itself is drawn; one that is not drawn at
## all (hidden body, spawning) gets none. The pins belong to the local view: nothing is synced.
##
## The eye view (a perspective camera; card eyepin) has its own rule: pins show whatever the
## pitch, with a distance fade (a token nearer than EYE_PIN_NEAR_M shows its model and no pin),
## and a token out of frame gets a chevron on the screen edge (TokenEdgeArrows). Both are on in the
## eye and never in the orbit view; `eye_pins` and `eye_arrows` are probe switches, as
## CanopyFade.eye_grass_enabled is. A click on an arrow asks for the eye to turn toward that
## token (`turn_requested`; CameraController turns the view, CameraRig.yaw_toward).

## A click on an edge arrow: turn the view toward this world point (the token's position).
signal turn_requested(world_position: Vector3)

## When the pins show (Settings > Graphics > "Token pins", graphics/token_pins): at every pitch
## (the item ids of the option are these values) or only from above.
enum PinMode { ALWAYS = 0, TOP_DOWN = 1 }

const SHADER := preload("res://shaders/token_marker.gdshader")
## The pin head's diameter on screen, in pixels, whatever the zoom or the token's size.
const HEAD_PX := 44.0
## The pin's quad in head diameters, and the height of the tip above its bottom edge; the same
## numbers as the shader's QUAD_W, QUAD_H and TIP_Y.
const QUAD_W := 1.3
const QUAD_H := 1.65
const TIP_Y := 0.14
## How far the head's centre stands above the tip, in head diameters (the shader's TAIL_H + TIP_R).
const HEAD_ABOVE_TIP := 0.83
## The hovered pin is this much larger (about its tip, which stays on the token).
const HOVER_SCALE := 1.1
## A pin takes hover and clicks only once the fade has brought it to this strength, so a barely
## visible pin never catches a click meant for the token or ground under it.
const HIT_MIN_STRENGTH := 0.5
const RENDER_PRIORITY := 20
## Where a pin's token id sits in the per-frame pin arrays [depth, tip, colour, cell, id].
const PIN_ID := 4
## How often the tokens' sizes and colours are read again, seconds.
const REFRESH_PERIOD_S := 0.5
## The alpha a token hidden from the players has in the GM's view (as the token's own 0.4).
const GM_HIDDEN_ALPHA := 0.4
## The disc of a token whose colours cannot be read at all: a soft periwinkle, never white.
const NO_COLOUR := TokenColours.NO_COLOUR
## Most vertex colours sampled from a mesh surface.
const VERTEX_SAMPLES := TokenColours.VERTEX_SAMPLES
## The eye view's far pins: a token nearer than EYE_PIN_NEAR_M shows its own
## model and has no pin, one farther than EYE_PIN_FULL_M has the whole pin, smooth between.
const EYE_PIN_NEAR_M := 9.0
const EYE_PIN_FULL_M := 18.0
## The pin's index of its eye-view fade in the per-frame pin arrays.
const PIN_FADE := 5
## The pin's alpha before the quiet scaling (the hovered pin is drawn at it), in the pin arrays.
const PIN_FULL_ALPHA := 6
## The saved key (graphics/token_pins, the PinMode value) and the default mode.
const SETTINGS_KEY := "token_pins"
const DEFAULT_MODE := PinMode.ALWAYS
## The quiet pin of a low camera: a smaller head, a little translucent, so the table view is
## not cluttered (ALWAYS mode, orbit camera, below 55 degrees of pitch; full from 70).
const QUIET_HEAD_PX := 30.0
const QUIET_ALPHA := 0.8

## The mode in force (a probe or the Settings menu changes it; the saved value is read at setup).
static var mode: int = DEFAULT_MODE

## The eye view shows pins for far tokens and edge arrows for tokens out of frame (card eyepin;
## on by the owner's verdict of 2026-11-04). Switches for probes and tests.
var eye_pins: bool = true
var eye_arrows: bool = true

## Set by the owner: Callable() -> bool, true while the pointer is over interface (not the
## world), when pins take neither hover nor clicks.
var gui_blocked: Callable = Callable()

var _camera: Camera3D = null
var _viewport: SubViewport = null
var _instances: MultiMeshInstance3D = null
var _arrows: TokenEdgeArrows = null
var _portraits: TokenPortraits = null
var _since_refresh: float = REFRESH_PERIOD_S
## This frame's pin head size in pixels and opacity factor (head_px_for, alpha_scale_for).
var _head_px: float = HEAD_PX
var _alpha_scale: float = 1.0
## The pointer in the world viewport's pixels, from the motion events that reach the viewport,
## and whether it is inside the window.
var _pointer: Vector2 = Vector2.ZERO
var _pointer_in: bool = false
## Instance id of the BoardToken whose pin the pointer is over (0 for none).
var _hovered: int = 0
## This frame's pin targets, parallel: head centre (viewport px), head radius (px), token id.
var _hit_centres: PackedVector2Array = PackedVector2Array()
var _hit_radii: PackedFloat32Array = PackedFloat32Array()
var _hit_ids: Array[int] = []
## BoardToken instance id -> {"offset": Vector3, "radius": float, "half_height": float,
## "colour": Color, "key": String ("" while the model is not loaded)}.
var _look: Dictionary = {}


## A TokenMarkers under `viewport` (the world SubViewport), looking through `camera`.
## `over_gui` (Callable() -> bool) says when the pointer is over interface.
static func attach(
	viewport: SubViewport, camera: Camera3D, over_gui: Callable = Callable()
) -> TokenMarkers:
	var markers := TokenMarkers.new()
	markers.name = "TokenMarkers"
	markers.gui_blocked = over_gui
	markers.process_priority = 10  # after the camera controller has placed the camera
	markers._camera = camera
	markers._viewport = viewport
	viewport.add_child(markers)
	return markers


func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = RENDER_PRIORITY
	mesh.material = material
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.use_custom_data = true
	multi.mesh = mesh
	_instances = MultiMeshInstance3D.new()
	_instances.multimesh = multi
	_instances.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instances.custom_aabb = AABB(Vector3(-1000.0, -1000.0, -1000.0), Vector3(2000.0, 2000.0, 2000.0))
	_instances.visible = false
	add_child(_instances)


# --- pure rules ---


## The pin's alpha for a token: `strength` (CameraRig.marker_strength) when it is drawn and the
## players can see it, GM_HIDDEN_ALPHA of it for the GM's view of a hidden token, 0 for none (a
## player must not learn where a hidden token stands, so nothing is drawn for them).
static func pin_alpha(
	strength: float, visible_to_players: bool, body_visible: bool, gm_access: bool
) -> float:
	if not body_visible:
		return 0.0
	if visible_to_players:
		return strength
	return strength * GM_HIDDEN_ALPHA if gm_access else 0.0


## The pin head's diameter in metres: `head_px` pixels at `camera_size` metres across
## `viewport_px` pixels.
static func head_metres(camera_size: float, viewport_px: float, head_px: float = HEAD_PX) -> float:
	return head_px * camera_size / maxf(viewport_px, 1.0)


## Where a pin's head centre is on screen: straight above its tip by HEAD_ABOVE_TIP head
## diameters (screen up is negative y). `tip_px` and the result are viewport pixels.
static func pin_head_centre(tip_px: Vector2, head_px: float = HEAD_PX) -> Vector2:
	return tip_px + Vector2(0.0, -HEAD_ABOVE_TIP * head_px)


## Whether a pin is a target at all: it is drawn (alpha above 0, so a token hidden from a
## player has none) and the fade has brought it to HIT_MIN_STRENGTH.
static func is_hittable(strength: float, alpha: float) -> bool:
	return alpha > 0.0 and strength >= HIT_MIN_STRENGTH


## The eye view's pin fade for a token `distance_m` from the eye (times the map `scale`): none up
## close where the model reads, whole from EYE_PIN_FULL_M out.
static func eye_pin_fade(distance_m: float, scale: float = 1.0) -> float:
	return smoothstep(EYE_PIN_NEAR_M * scale, EYE_PIN_FULL_M * scale, distance_m)


## The pins' strength: the eye view (a perspective camera) with `eye_pins_on` has them whole at
## any pitch; every other view keeps the pitch rule's `pitch_strength` (CameraRig.marker_strength).
## ALWAYS mode has them whole at any pitch too (quiet below the threshold, see head_px_for).
static func strength_for(
	pitch_strength: float, perspective: bool, eye_pins_on: bool, pin_mode: int = PinMode.TOP_DOWN
) -> float:
	if pin_mode == PinMode.ALWAYS or (perspective and eye_pins_on):
		return 1.0
	return pitch_strength


## The head diameter in pixels: HEAD_PX, except in ALWAYS mode with the orbit camera, where it
## shrinks to QUIET_HEAD_PX as the pitch falls (`pitch_strength` is CameraRig.marker_strength).
## The eye view (perspective) keeps the full head: its pins are far tokens.
static func head_px_for(pitch_strength: float, perspective: bool, pin_mode: int) -> float:
	if pin_mode != PinMode.ALWAYS or perspective:
		return HEAD_PX
	return lerpf(QUIET_HEAD_PX, HEAD_PX, pitch_strength)


## The factor on a pin's opacity: 1, except in ALWAYS mode with the orbit camera, where it falls
## to QUIET_ALPHA as the pitch falls.
static func alpha_scale_for(pitch_strength: float, perspective: bool, pin_mode: int) -> float:
	if pin_mode != PinMode.ALWAYS or perspective:
		return 1.0
	return lerpf(QUIET_ALPHA, 1.0, pitch_strength)


## Whether the edge arrows are shown: only in the eye view (a perspective camera), when on.
static func arrows_wanted(perspective: bool, eye_arrows_on: bool) -> bool:
	return perspective and eye_arrows_on


## The pin under `point`: the index of the head circle (centre `centres[i]`, radius `radii[i]`)
## that contains it, and where several do, the one whose centre is nearest. -1 for none.
static func pick_pin(
	centres: PackedVector2Array, radii: PackedFloat32Array, point: Vector2
) -> int:
	var best := -1
	var best_d2 := INF
	for i in centres.size():
		var d2 := centres[i].distance_squared_to(point)
		if d2 <= radii[i] * radii[i] and d2 < best_d2:
			best_d2 = d2
			best = i
	return best


## `pins` (in draw order, the last drawn on top) with the entry whose id (element `id_at`) is
## `id` moved to the end, so it draws in front of the rest. Unchanged when `id` is not there.
static func bring_to_front(pins: Array[Array], id: int, id_at: int) -> Array[Array]:
	for i in pins.size():
		if pins[i][id_at] == id:
			var out := pins.duplicate()
			out.remove_at(i)
			out.append(pins[i])
			return out
	return pins


## How far a token's top edge lies from its centre along the unit screen-up vector `up`, in
## metres: a standing cylinder of `radius` and `half_height` (its footprint and body), so seen
## from straight above it is the footprint's edge and seen from the side it is the head.
static func top_edge_metres(radius: float, half_height: float, up: Vector3) -> float:
	return radius * Vector2(up.x, up.z).length() + half_height * absf(up.y)


## The world box of `body`'s collision shapes (an empty AABB when it has none).
static func shape_box(body: Node) -> AABB:
	var box := AABB()
	var first := true
	for node in body.find_children("*", "CollisionShape3D", true, false):
		var shape_node := node as CollisionShape3D
		if shape_node.shape == null or shape_node.disabled or not shape_node.is_inside_tree():
			continue
		var world := shape_node.global_transform * shape_extent(shape_node.shape)
		box = world if first else box.merge(world)
		first = false
	return box


## A shape's box in its own space.
static func shape_extent(shape: Shape3D) -> AABB:
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var r := capsule.radius
		return AABB(Vector3(-r, -capsule.height * 0.5, -r), Vector3(2.0 * r, capsule.height, 2.0 * r))
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var s := (shape as SphereShape3D).radius
		return AABB(Vector3.ONE * -s, Vector3.ONE * 2.0 * s)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var c := cylinder.radius
		return AABB(Vector3(-c, -cylinder.height * 0.5, -c), Vector3(2.0 * c, cylinder.height, 2.0 * c))
	return TokenShape.extent_of(shape)


## The pin's transform: its tip at `tip`, `head` metres across, turned to `camera_basis`.
static func pin_transform(tip: Vector3, head: float, camera_basis: Basis) -> Transform3D:
	var up := camera_basis.y.normalized()
	var scaled := camera_basis * Basis.from_scale(Vector3(QUAD_W * head, QUAD_H * head, 1.0))
	return Transform3D(scaled, tip + up * (QUAD_H * 0.5 - TIP_Y) * head)


## The most vivid of `colours` (saturation times value, ignoring near-white and near-black),
## made readable on the board: at least half saturated (unless it is grey) and bright.
## NO_COLOUR when there are none.
static func vivid(colours: PackedColorArray) -> Color:
	return TokenColours.vivid(colours)


## Up to `count` colours spread over a vertex colour array, each times `tint` (the material's
## albedo colour).
static func sample_colours(
	vertex_colours: PackedColorArray, tint: Color, count: int = VERTEX_SAMPLES
) -> PackedColorArray:
	return TokenColours.sample_colours(vertex_colours, tint, count)


# --- input ---


## Follow the pointer in the world viewport's pixels (never consumes the event).
func _input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_pointer = motion.position
		_pointer_in = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_MOUSE_EXIT:
		_pointer_in = false


## A left press on an edge arrow turns the eye toward its token (consumed). A left press on a pin
## picks its token up as a press on the token's body would, and is consumed only when that press
## took (a refused one, no permission or a tool in use, falls through to whatever lies beneath).
func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	if _arrows != null and _arrows.visible and pointer_free():
		var pointed := _arrows.token_at(button.position)
		if pointed != null:
			turn_requested.emit(pointed.rigid_body.global_position)
			_viewport.set_input_as_handled()
			return
	var token := token_at(button.position)
	if token == null:
		return
	var draggable := token.get_dragging_object()
	if draggable != null and draggable.press_at(button.position):
		_viewport.set_input_as_handled()


## The token whose pin head is under `point` (viewport pixels) as of the last frame drawn, or
## null: nothing while the pins are not targets (too faint, or off).
func token_at(point: Vector2) -> BoardToken:
	var i := pick_pin(_hit_centres, _hit_radii, point)
	if i < 0:
		return null
	var token := instance_from_id(_hit_ids[i]) as BoardToken
	return token if token != null and is_instance_valid(token) else null


## The token whose pin is hovered now, or null.
func hovered_token() -> BoardToken:
	return instance_from_id(_hovered) as BoardToken if _hovered != 0 else null


# --- per frame ---


func _process(delta: float) -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var eye := _camera.projection == Camera3D.PROJECTION_PERSPECTIVE
	var pitch_strength := CameraRig.marker_strength(
		CameraRig.pitch_of_back_y(_camera.global_basis.z.y)
	)
	var strength := strength_for(pitch_strength, eye, eye_pins, mode)
	_head_px = head_px_for(pitch_strength, eye, mode)
	_alpha_scale = alpha_scale_for(pitch_strength, eye, mode)
	_sync_arrows()
	if strength <= 0.0:
		if _instances.visible:
			_instances.visible = false
			_instances.multimesh.visible_instance_count = 0
			_clear_hits()
		return
	_since_refresh += delta
	var refresh := _since_refresh >= REFRESH_PERIOD_S
	if refresh:
		_since_refresh = 0.0
	_draw(strength, refresh)


func _draw(strength: float, refresh: bool) -> void:
	if _portraits == null:
		_portraits = TokenPortraits.new()
		add_child(_portraits)
		(_instances.multimesh.mesh.material as ShaderMaterial).set_shader_parameter(
			"atlas", _portraits.atlas
		)
	var gm_access := NetworkManager.has_gm_access()
	var multi := _instances.multimesh
	var tokens := get_tree().get_nodes_in_group(BoardToken.GROUP_NAME)
	if multi.instance_count < tokens.size():
		multi.instance_count = maxi(tokens.size() * 2, 8)
	var camera_basis := _camera.global_basis
	var up := camera_basis.y.normalized()
	var pins: Array[Array] = []
	for node in tokens:
		var token := node as BoardToken
		if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
			continue
		var alpha := pin_alpha(
			strength, token.is_visible_to_players, token.rigid_body.visible, gm_access
		)
		var fade := 1.0
		if eye_pins and _camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
			var away := token.rigid_body.global_position.distance_to(_camera.global_position)
			fade = eye_pin_fade(away)
			alpha *= fade
		if alpha <= 0.0:
			continue
		var id := token.get_instance_id()
		if refresh or not _look.has(id):
			_look[id] = _read_look(token)
		var look: Dictionary = _look[id]
		var cell := -1
		var key: String = look.key
		if key != "":
			cell = _portraits.cell_of(key)
			if cell < 0 and not _portraits.knows(key):
				_portraits.request(key, _source_for(token))
		var centre := token.rigid_body.global_position + (look.offset as Vector3)
		var tip := centre + up * top_edge_metres(look.radius, look.half_height, up)
		var colour: Color = look.colour
		colour.a = alpha * _alpha_scale
		pins.append([tip.dot(up), tip, colour, cell, id, fade, alpha])
	# Higher on the screen first, so a lower pin lies over the one above it.
	pins.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	_update_hits(pins, strength)
	# The pin under the pointer is drawn last: in front of every pin it overlaps.
	pins = bring_to_front(pins, _hovered, PIN_ID)
	for i in pins.size():
		var pin: Array = pins[i]
		var hover: bool = _hovered != 0 and pin[PIN_ID] == _hovered
		var scale := _head_at(pin[1]) * (HOVER_SCALE if hover else 1.0)
		multi.set_instance_transform(i, pin_transform(pin[1], scale, camera_basis))
		var colour: Color = pin[2]
		if hover:
			colour.a = pin[PIN_FULL_ALPHA]  # the hovered pin is never quiet
		multi.set_instance_color(i, colour)
		var cell: int = pin[3]
		var uv := TokenPortraits.picture_uv(maxi(cell, 0))
		multi.set_instance_custom_data(
			i, Color(uv.x, uv.y, 1.0 if cell >= 0 else 0.0, 1.0 if hover else 0.0)
		)
	multi.visible_instance_count = pins.size()
	_instances.visible = not pins.is_empty()


## Build this frame's pin targets from `pins` (in the sorted pin arrays) and find the hovered
## one. Nothing is a target below HIT_MIN_STRENGTH, with the pointer outside the window or over
## interface, or while a token is held.
func _update_hits(pins: Array[Array], strength: float) -> void:
	var was := _hovered
	_clear_hits()
	if strength < HIT_MIN_STRENGTH:
		return
	for pin in pins:
		if not is_hittable(strength, (pin[2] as Color).a) or pin[PIN_FADE] < HIT_MIN_STRENGTH:
			continue
		var id: int = pin[PIN_ID]
		# The hovered pin is tested at its enlarged size, so the pointer on its rim does not
		# make it flicker between the two sizes.
		var scale := HOVER_SCALE if id == was else 1.0
		var tip_px: Variant = CameraRig.screen_of(_camera, pin[1])
		if tip_px == null:
			continue  # behind the eye: not a target
		_hit_centres.append(pin_head_centre(tip_px, _head_px * scale))
		_hit_radii.append(_head_px * 0.5 * scale)
		_hit_ids.append(id)
	if not _pointer_in or _is_blocked():
		return
	var i := pick_pin(_hit_centres, _hit_radii, _pointer)
	_hovered = _hit_ids[i] if i >= 0 else 0


## The pin head's diameter in metres at `tip`: this frame's head size in pixels (HEAD_PX, or the
## quiet size) across whatever the zoom. Orthographic: from the camera size, the same everywhere;
## perspective (the eye view): from the field of view at the tip's distance in front of the
## camera, so a near pin is small in metres and a far one large.
func _head_at(tip: Vector3) -> float:
	if _camera.projection != Camera3D.PROJECTION_PERSPECTIVE:
		return head_metres(_camera.size, WorldView.canvas_size(_viewport).y, _head_px)
	var depth := maxf((-_camera.global_basis.z).dot(tip - _camera.global_position), 0.0)
	return _head_px * CameraRig.metres_per_pixel(_camera, WorldView.canvas_size(_viewport), depth)


## The edge arrows node (TokenEdgeArrows): made on first need in the eye view, null before.
func arrows_node() -> TokenEdgeArrows:
	return _arrows


## Makes, shows or hides the edge arrows (see `arrows_wanted`) and hands them the pointer.
func _sync_arrows() -> void:
	var wanted := arrows_wanted(_camera.projection == Camera3D.PROJECTION_PERSPECTIVE, eye_arrows)
	if wanted and _arrows == null:
		_arrows = TokenEdgeArrows.new()
		_arrows.name = "TokenEdgeArrows"
		_arrows.camera = _camera
		_arrows.colour_of = colour_of
		add_child(_arrows)
	if _arrows != null:
		_arrows.visible = wanted
		_arrows.set_process(wanted)
		_arrows.pointer = _pointer if wanted and pointer_free() else null


## Whether the pointer is in the window, not over interface and no token is held: free to hover
## and click what is drawn on the world.
func pointer_free() -> bool:
	return _pointer_in and not _is_blocked()


## A token's marker colour (what its pin and the edge arrow are painted in), read on demand.
func colour_of(token: BoardToken) -> Color:
	var id := token.get_instance_id()
	if not _look.has(id):
		_look[id] = _read_look(token)
	return (_look[id] as Dictionary).colour


func _clear_hits() -> void:
	_hovered = 0
	_hit_centres.clear()
	_hit_radii.clear()
	_hit_ids.clear()


## Whether the pointer is over interface, outside the world viewport, or holding a token.
func _is_blocked() -> bool:
	if not Rect2(Vector2.ZERO, WorldView.canvas_size(_viewport)).has_point(_pointer):
		return true
	if gui_blocked.is_valid() and gui_blocked.call():
		return true
	var drag := get_tree().get_first_node_in_group(DragController.GROUP) as DragController
	return drag != null and drag.is_dragging()


## What a token's picture is made from (see TokenPortraits): the avatar's recipe, the pack's icon
## when it has one, else the token's own meshes.
func _source_for(token: BoardToken) -> Dictionary:
	if token.is_avatar():
		return {"kind": TokenPortraits.Kind.AVATAR, "recipe": token.avatar_recipe}
	if token.pack_id != "" and token.asset_id != "" and AssetManager.resolver != null:
		var path: String = AssetManager.resolver.resolve_icon_sync(
			token.pack_id, token.asset_id, token.variant_id
		)
		if path != "":
			return {"kind": TokenPortraits.Kind.ICON, "path": path}
	return {"kind": TokenPortraits.Kind.MODEL, "token": token.get_instance_id()}


## A token's pin centre (relative to its body), footprint radius, half height, colour and
## picture key, from its meshes. The key is empty while it has none (a placeholder is not a
## model worth a portrait).
func _read_look(token: BoardToken) -> Dictionary:
	var meshes := TokenGhost.meshes_of(token.rigid_body)
	var box := AABB()
	var first := true
	var colours := PackedColorArray()
	var first_mesh: Mesh = null
	for mi in meshes:
		if not mi.is_inside_tree():
			continue
		var world_box := mi.global_transform * mi.get_aabb()
		box = world_box if first else box.merge(world_box)
		first = false
		first_mesh = first_mesh if first_mesh != null else mi.mesh
		colours.append_array(_colours_of(TokenGhost.source_of(mi), mi.mesh))
	if first:
		return {
			"offset": Vector3.UP * 0.5,
			"radius": 0.4,
			"half_height": 0.5,
			"colour": vivid(colours),
			"key": "",
		}
	var key := TokenPortraits.identity_key(
		token.pack_id,
		token.asset_id,
		token.variant_id,
		token.avatar_recipe,
		first_mesh.get_instance_id()
	)
	# The footprint is the token's collision shape: an avatar's capsule (AvatarExtent: the body
	# core; the skinned meshes' rest-pose bounds, arms out, would put the pin well above the
	# figure) and a pack token's hull of its meshes (TokenShape), the same box as the mesh
	# bounds. The mesh bounds stand only for a token with no shape.
	var footprint := shape_box(token.rigid_body)
	if footprint.has_volume():
		box = footprint
	return {
		"offset": box.get_center() - token.rigid_body.global_position,
		"radius": maxf(box.size.x, box.size.z) * 0.5,
		"half_height": box.size.y * 0.5,
		"colour": vivid(colours),
		"key": key,
	}


## The colours a mesh source (a palette texture or a material) shows, a few dozen at most. A
## material that takes its colour from the vertices (the free "chunky" game art does, its
## albedo is plain white) is read from the mesh's vertex colours, which was the white pin.
func _colours_of(source: Variant, mesh: Mesh) -> PackedColorArray:
	return TokenColours.colours_of(source, mesh)
