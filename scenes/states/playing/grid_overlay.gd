extends MeshInstance3D
class_name GridOverlay

## Full-screen quad that projects a grid onto all visible geometry via a
## depth-buffer shader. Parented to Camera3D inside the SubViewport so the
## grid receives the lo-fi post-processing effect.
##
## Usage:
##   var grid = GridOverlay.create(camera_node)
##   grid.configure(cell_size, grid_origin, grid_color)
##   grid.show_grid()  /  grid.hide_grid()

const FADE_DURATION := 0.2

var _material: ShaderMaterial
var _fade_tween: Tween
var _showing := false


## Factory — creates a GridOverlay and parents it to the given camera.
static func create(camera: Camera3D) -> GridOverlay:
	var instance := GridOverlay.new()
	instance.name = "GridOverlay"

	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	quad.flip_faces = true
	instance.mesh = quad

	instance.extra_cull_margin = 16384.0

	var shader := load("res://shaders/grid_overlay.gdshader") as Shader
	instance._material = ShaderMaterial.new()
	instance._material.shader = shader
	instance.material_override = instance._material

	camera.add_child(instance)

	instance.visible = false
	instance.set_process(false)
	instance._material.set_shader_parameter("opacity", 0.0)
	return instance


## Update grid scale and appearance. Call after level load and when the GM
## changes scale settings.
func configure(
	cell_size: float,
	origin: Vector2 = Vector2.ZERO,
	color: Color = Color(1.0, 1.0, 1.0, 0.35),
) -> void:
	if not _material:
		return
	_material.set_shader_parameter("cell_size", cell_size)
	_material.set_shader_parameter("grid_origin", origin)
	_material.set_shader_parameter("line_color", color)


## Set the floor Y level for height-based filtering.
## The grid only renders on surfaces within [y_level - tolerance, y_level + tolerance].
## This prevents the grid from projecting onto tokens and ceilings.
func set_floor_level(y_level: float, tolerance: float = 0.5) -> void:
	if not _material:
		return
	_material.set_shader_parameter("grid_y_level", y_level)
	_material.set_shader_parameter("grid_y_tolerance", tolerance)


## Activate cell highlighting for a drag in progress.
## [param current_pos] World position of the hovered/snapped cell center.
## [param start_pos] World position of the drag origin cell center.
func set_drag_highlight(current_pos: Vector3, start_pos: Vector3) -> void:
	if not _material:
		return
	var cell_size: float = _material.get_shader_parameter("cell_size")
	var origin: Vector2 = _material.get_shader_parameter("grid_origin")
	if cell_size <= 0.0:
		return
	# Convert world positions to integer cell indices
	var current_cell := Vector2(
		floorf((current_pos.x - origin.x) / cell_size),
		floorf((current_pos.z - origin.y) / cell_size),
	)
	var start_cell := Vector2(
		floorf((start_pos.x - origin.x) / cell_size),
		floorf((start_pos.z - origin.y) / cell_size),
	)
	_material.set_shader_parameter("drag_active", true)
	_material.set_shader_parameter("drag_current_cell", current_cell)
	_material.set_shader_parameter("drag_start_cell", start_cell)


## Clear cell highlighting (call when drag ends).
func clear_drag_highlight() -> void:
	if not _material:
		return
	_material.set_shader_parameter("drag_active", false)


## Show the grid overlay with a fade-in animation.
func show_grid() -> void:
	_showing = true
	_kill_fade_tween()
	visible = true
	set_process(true)
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_opacity, _get_opacity(), 1.0, FADE_DURATION)


## Hide the grid overlay with a fade-out animation.
func hide_grid() -> void:
	_showing = false
	_kill_fade_tween()
	_fade_tween = create_tween()
	_fade_tween.tween_method(_set_opacity, _get_opacity(), 0.0, FADE_DURATION)
	_fade_tween.tween_callback(_on_fade_out_finished)


## Hide immediately without animation (for level clear / reset).
func hide_grid_immediate() -> void:
	_showing = false
	_kill_fade_tween()
	_set_opacity(0.0)
	visible = false
	set_process(false)


## Returns true if the grid is logically shown (may still be animating).
func is_grid_visible() -> bool:
	return _showing


func _set_opacity(value: float) -> void:
	if _material:
		_material.set_shader_parameter("opacity", value)


func _get_opacity() -> float:
	if _material:
		return _material.get_shader_parameter("opacity")
	return 0.0


func _on_fade_out_finished() -> void:
	visible = false
	set_process(false)


func _kill_fade_tween() -> void:
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not _material:
		return
	# Update the fade center to where the camera is looking on the floor plane.
	# For orthographic/isometric cameras the camera position itself is high up
	# and offset — project its forward ray onto the grid_y_level plane.
	var cam := get_parent() as Camera3D
	if cam:
		var floor_y: float = _material.get_shader_parameter("grid_y_level")
		var vp_size := cam.get_viewport().get_visible_rect().size
		var center_screen := vp_size * 0.5
		var ray_origin := cam.project_ray_origin(center_screen)
		var ray_dir := cam.project_ray_normal(center_screen)
		var look_center := ray_origin
		if absf(ray_dir.y) > 0.001:
			var t := (floor_y - ray_origin.y) / ray_dir.y
			if t > 0.0:
				look_center = ray_origin + ray_dir * t
		_material.set_shader_parameter("grid_center", look_center)
