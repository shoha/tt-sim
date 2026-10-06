class_name AvatarBuilderPreview
extends SubViewportContainer

## The avatar builder's live preview: the figure AvatarKit assembles from the working
## recipe, drawn in its own small world through a camera with the game camera's angle
## (game_map.tscn's Camera3D basis, orthographic), on a slow turntable the player can spin
## by dragging. Lighting is one directional light from the camera's side; the figure shader
## takes the level's ambient from its global, so the preview sits in the same light as the
## board.
##
## set_recipe mirrors AvatarTokenFactory.set_recipe for a bare figure: colours and face
## cells swap materials, a stance re-poses, new parts or proportions build a new figure.
## `applies` counts the changes that touched the figure (tests and probes).

## The game camera's basis (game_map.tscn Camera3D), as axes.
const CAMERA_BASIS := Basis(
	Vector3(0.7071068, 0.0, -0.7071068),
	Vector3(-0.26030335, 0.9297765, -0.26030335),
	Vector3(0.6574513, 0.36812454, 0.6574513)
)
const CAMERA_DISTANCE_M := 12.0
## The view's height in metres: a tall figure (about 1.75 m) with headroom.
const VIEW_HEIGHT_M := 2.25
## Where the view centres, above the figure's soles.
const FOCUS_HEIGHT_M := 0.95
## The figure faces +Z; this turns it toward a camera at 45 degrees azimuth.
const FACING_RAD := PI / 4.0
const TURN_RAD_PER_S := 0.3
## Seconds without a drag before the turntable resumes.
const RESUME_DELAY_S := 2.0
const DRAG_RAD_PER_PX := 0.012
const FLOOR_RADIUS_M := 0.34
const FLOOR_COLOUR := Color(0.0, 0.0, 0.0, 0.28)

var recipe: Dictionary = {}
var figure: Node3D = null
## Changes that touched the figure since the preview was built.
var applies := 0
## Whether the turntable turns on its own.
var turning := true

var _viewport: SubViewport
var _pivot: Node3D
var _dragging := false
var _resume_at_s := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	_viewport = SubViewport.new()
	_viewport.name = "PreviewViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = VIEW_HEIGHT_M
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.05
	camera.far = 50.0
	camera.basis = CAMERA_BASIS
	camera.position = Vector3(0.0, FOCUS_HEIGHT_M, 0.0) + CAMERA_BASIS.z * CAMERA_DISTANCE_M
	_viewport.add_child(camera)

	var light := DirectionalLight3D.new()
	light.name = "KeyLight"
	light.light_energy = 1.0
	light.shadow_enabled = false
	# From high on the camera's left, so the lit side faces the viewer and the far side
	# keeps the paint's own shadow end.
	light.basis = Basis.looking_at(Vector3(0.35, -1.0, -0.8).normalized(), Vector3.UP)
	_viewport.add_child(light)

	var floor_disc := MeshInstance3D.new()
	floor_disc.name = "FloorShadow"
	var disc := CylinderMesh.new()
	disc.top_radius = FLOOR_RADIUS_M
	disc.bottom_radius = FLOOR_RADIUS_M
	disc.height = 0.01
	disc.radial_segments = 32
	floor_disc.mesh = disc
	var floor_material := StandardMaterial3D.new()
	floor_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	floor_material.albedo_color = FLOOR_COLOUR
	floor_disc.material_override = floor_material
	floor_disc.position.y = -0.005
	_viewport.add_child(floor_disc)

	_pivot = Node3D.new()
	_pivot.name = "Turntable"
	_pivot.rotation.y = FACING_RAD
	_viewport.add_child(_pivot)
	if not recipe.is_empty():
		_rebuild()


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
		changed = true
	if changed:
		applies += 1


## Turns the figure to face the camera again and restarts the turntable.
func reset_turn() -> void:
	if _pivot != null:
		_pivot.rotation.y = FACING_RAD
	turning = true
	_resume_at_s = 0.0


func _rebuild() -> void:
	var kit := AvatarTokenFactory.kit()
	if kit == null or _pivot == null:
		return
	if figure != null:
		_pivot.remove_child(figure)
		figure.queue_free()
	figure = kit.build_figure(recipe)
	_pivot.add_child(figure)
	applies += 1


func _process(delta: float) -> void:
	if _pivot == null or _dragging or not turning:
		return
	if _resume_at_s > 0.0:
		_resume_at_s -= delta
		return
	_pivot.rotation.y += TURN_RAD_PER_S * delta


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if not event.pressed:
			_resume_at_s = RESUME_DELAY_S
		accept_event()
	elif event is InputEventMouseMotion and _dragging and _pivot != null:
		_pivot.rotation.y += event.relative.x * DRAG_RAD_PER_PX
		accept_event()
