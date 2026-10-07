class_name AvatarBuilderPreview
extends Control

## The avatar builder's live preview: the figure AvatarKit assembles from the working
## recipe, drawn in its own small world on a slow turntable the player can spin by dragging,
## over a softly lit backdrop that separates it from the panel.
##
## The view is orthographic, at the game camera's azimuth and a little lower than its pitch
## (FULL_PITCH_DEG), and is fitted to the posed figure (AvatarBuilderFraming) so every
## stance fills it. focus_face(true), for the Face pane, eases the view to a portrait of the
## head (lower still, so the eyes read) and turns the figure to face the camera; false eases
## back to the whole figure and the turntable resumes.
##
## The light is the board's under the default environment: the world has that environment's
## tonemapper and ambient (EnvironmentPresets defaults), a sun where DefaultSun puts it at
## the default time of day relative to the same camera azimuth, and every part's
## ambient_override instance uniform holds the default ambient, so the preview does not
## take the open level's figure_ambient (a dungeon level would darken it).
##
## set_recipe mirrors AvatarTokenFactory.set_recipe for a bare figure: colours and face
## cells swap materials, a stance re-poses, new parts or proportions build a new figure.
## `applies` counts the changes that touched the figure (tests and probes).

## The game camera's azimuth (game_map.tscn Camera3D; its pitch is about 21.6 degrees).
const AZIMUTH_RAD := PI / 4.0
## Pitch above the horizon for the whole figure and for the face portrait.
const FULL_PITCH_DEG := 14.0
const FACE_PITCH_DEG := 4.0
const CAMERA_DISTANCE_M := 12.0
## The head and hair's share of the view height in the face portrait.
const FACE_CROWN_SHARE := 0.9
## How fast the view eases between the figure and the face (per second).
const EASE_RATE := 5.0
## The figure faces +Z; this turns it toward a camera at 45 degrees azimuth.
const FACING_RAD := PI / 4.0
const TURN_RAD_PER_S := 0.3
## Seconds without a drag before the turntable resumes.
const RESUME_DELAY_S := 2.0
const DRAG_RAD_PER_PX := 0.012
## The floor: a soft pool of light under the figure and a contact shadow at its feet.
const FLOOR_GLOW_RADIUS_M := 0.95
const FLOOR_GLOW := Color(1.0, 0.94, 0.84, 0.26)
const FLOOR_SHADOW_RADIUS_M := 0.36
const FLOOR_SHADOW := Color(0.08, 0.04, 0.08, 0.42)
## The backdrop: a warm glow behind the figure fading to the panel's inset tone.
const BACKDROP_CENTRE := Color("#7d6479")
const BACKDROP_EDGE := Color("#2a1d29")

var recipe: Dictionary = {}
var figure: Node3D = null
## Changes that touched the figure since the preview was built.
var applies := 0
## Whether the turntable turns on its own.
var turning := true
## The figure's measured extent (AvatarBuilderFraming.measure).
var bounds: Dictionary = {}
## Whether the view is on (or easing to) the face portrait.
var face_view := false

var _viewport: SubViewport
var _camera: Camera3D
var _pivot: Node3D
var _ambient := Vector4.ZERO
## 0 the whole figure, 1 the face portrait.
var _blend := 0.0
var _dragging := false
var _resume_at_s := 0.0


## The camera basis at the game's azimuth and `pitch_deg` above the horizon.
static func view_basis(pitch_deg: float) -> Basis:
	return Basis.from_euler(Vector3(-deg_to_rad(pitch_deg), AZIMUTH_RAD, 0.0))


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	clip_contents = true
	var backdrop := TextureRect.new()
	backdrop.name = "Backdrop"
	backdrop.texture = _backdrop_texture()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var container := SubViewportContainer.new()
	container.name = "View"
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)

	var environment := _environment()
	var ambient := environment.ambient_light_color * environment.ambient_light_energy
	_ambient = Vector4(ambient.r, ambient.g, ambient.b, 1.0)
	_camera = Camera3D.new()
	_camera.name = "Camera3D"
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.near = 0.05
	_camera.far = 50.0
	_camera.environment = environment
	_viewport.add_child(_camera)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	DefaultSun.apply(sun, DefaultSun.settings_for_time(DefaultSun.DEFAULT_TIME_OF_DAY))
	sun.shadow_enabled = false
	_viewport.add_child(sun)
	_viewport.add_child(_floor_disc("FloorGlow", FLOOR_GLOW_RADIUS_M, FLOOR_GLOW, -0.006))
	_viewport.add_child(_floor_disc("FloorShadow", FLOOR_SHADOW_RADIUS_M, FLOOR_SHADOW, -0.004))

	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	_pivot.rotation.y = FACING_RAD
	_viewport.add_child(_pivot)
	resized.connect(_place_camera)
	if not recipe.is_empty():
		_rebuild()
	_place_camera()


## The default environment (EnvironmentPresets with no preset or overrides) for a
## transparent view: its tonemapper, exposure and ambient, without a background or glow.
static func _environment() -> Environment:
	var environment := EnvironmentPresets.create_environment()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.glow_enabled = false
	environment.fog_enabled = false
	return environment


static func _backdrop_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, BACKDROP_CENTRE)
	gradient.set_color(1, BACKDROP_EDGE)
	gradient.add_point(0.45, BACKDROP_CENTRE.lerp(BACKDROP_EDGE, 0.45))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.42)
	texture.fill_to = Vector2(1.15, 1.05)
	texture.width = 128
	texture.height = 128
	return texture


## A flat disc on the floor whose colour fades from `colour` at its centre to nothing at
## `radius`.
static func _floor_disc(node_name: String, radius: float, colour: Color, y: float) -> Node3D:
	var gradient := Gradient.new()
	gradient.set_color(0, colour)
	gradient.set_color(1, Color(colour, 0.0))
	gradient.add_point(0.55, Color(colour, colour.a * 0.55))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = texture
	material.disable_receive_shadows = true
	var quad := PlaneMesh.new()
	quad.size = Vector2(radius, radius) * 2.0
	var disc := MeshInstance3D.new()
	disc.name = node_name
	disc.mesh = quad
	disc.material_override = material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.position.y = y
	return disc


## Shows `new_recipe`, rebuilding only what changed from the figure shown now.
func set_recipe(new_recipe: Dictionary) -> void:
	recipe = AvatarRecipe.normalized(new_recipe)
	if _pivot == null:
		return
	var kit := AvatarTokenFactory.kit()
	if kit == null:
		return
	if figure == null:
		_rebuild()
		return
	var built: Dictionary = figure.get_meta("avatar_recipe", {})
	var fresh := kit.resolve(recipe)
	if built.is_empty() or fresh.parts != built.parts or fresh.proportions != built.proportions:
		_rebuild()
		return
	var changed := false
	if fresh.colours != built.colours or fresh.face != built.face:
		kit.apply_look(figure, recipe)
		changed = true
	if fresh.stance != built.stance:
		kit.apply_stance(figure, recipe)
		bounds = AvatarBuilderFraming.measure(figure)
		changed = true
	if changed:
		applies += 1


## Eases the view to a portrait of the face, turned to the camera (`on`), or back to the
## whole figure on its turntable.
func focus_face(on: bool) -> void:
	face_view = on
	_resume_at_s = 0.0


## Turns the figure to face the camera again and restarts the turntable.
func reset_turn() -> void:
	if _pivot != null:
		_pivot.rotation.y = FACING_RAD
	turning = true
	_resume_at_s = 0.0


## The view (height, focus point) for the whole figure and for the face at blend `t`.
func view_at(t: float) -> Dictionary:
	var aspect := size.x / size.y if size.y > 0.0 else 0.75
	var full := AvatarBuilderFraming.fit(bounds, deg_to_rad(FULL_PITCH_DEG), aspect)
	var full_focus := Vector3(0.0, full.y, 0.0)
	var face := AvatarBuilderFraming.face_view(bounds, FACE_CROWN_SHARE, aspect)
	if t <= 0.0 or face.is_empty():
		return {"size": full.x, "focus": full_focus, "pitch": FULL_PITCH_DEG}
	var face_focus: Vector3 = face.focus
	if _pivot != null:
		face_focus = _pivot.basis * face_focus
	var eased := smoothstep(0.0, 1.0, t)
	return {
		"size": lerpf(full.x, float(face.size), eased),
		"focus": full_focus.lerp(face_focus, eased),
		"pitch": lerpf(FULL_PITCH_DEG, FACE_PITCH_DEG, eased),
	}


func _place_camera() -> void:
	if _camera == null:
		return
	var view := view_at(_blend)
	_camera.size = float(view.size)
	_camera.basis = view_basis(float(view.pitch))
	_camera.position = (view.focus as Vector3) + _camera.basis.z * CAMERA_DISTANCE_M


func _rebuild() -> void:
	var kit := AvatarTokenFactory.kit()
	if kit == null or _pivot == null:
		return
	if figure != null:
		_pivot.remove_child(figure)
		figure.queue_free()
	figure = kit.build_figure(recipe)
	for part in AvatarKit.figure_parts(figure):
		part.set_instance_shader_parameter("ambient_override", _ambient)
	_pivot.add_child(figure)
	bounds = AvatarBuilderFraming.measure(figure)
	applies += 1


func _process(delta: float) -> void:
	if _pivot == null:
		return
	var target := 1.0 if face_view else 0.0
	_blend = move_toward(_blend, target, delta * EASE_RATE * 0.5)
	if not _dragging and _resume_at_s > 0.0:
		_resume_at_s -= delta
	elif not _dragging and face_view:
		var step := 1.0 - exp(-delta * EASE_RATE)
		_pivot.rotation.y = lerp_angle(_pivot.rotation.y, FACING_RAD, step)
	elif not _dragging and turning:
		_pivot.rotation.y += TURN_RAD_PER_S * delta
	_place_camera()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			_resume_at_s = RESUME_DELAY_S
		accept_event()
	elif event is InputEventMouseMotion and _dragging and _pivot != null:
		_pivot.rotation.y += event.relative.x * DRAG_RAD_PER_PX
		accept_event()
