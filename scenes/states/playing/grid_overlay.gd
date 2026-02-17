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

var _material: ShaderMaterial


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


## Show the grid overlay and start updating the fade center.
func show_grid() -> void:
	visible = true
	set_process(true)


## Hide the grid overlay and stop per-frame updates.
func hide_grid() -> void:
	visible = false
	set_process(false)


func is_grid_visible() -> bool:
	return visible


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if not _material:
		return
	# Update the fade center to where the camera is looking on the ground plane.
	# For orthographic/isometric cameras the camera position itself is high up
	# and offset — project its forward ray onto Y=0 for an accurate center.
	var cam := get_parent() as Camera3D
	if cam:
		var vp_size := cam.get_viewport().get_visible_rect().size
		var center_screen := vp_size * 0.5
		var ray_origin := cam.project_ray_origin(center_screen)
		var ray_dir := cam.project_ray_normal(center_screen)
		# Intersect with Y=0 ground plane
		var look_center := ray_origin
		if absf(ray_dir.y) > 0.001:
			var t := -ray_origin.y / ray_dir.y
			if t > 0.0:
				look_center = ray_origin + ray_dir * t
		_material.set_shader_parameter("grid_center", look_center)
