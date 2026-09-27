class_name GridOverlay
extends MeshInstance3D

## Full-screen quad that projects a grid onto all visible geometry via a
## depth-buffer shader. Parented to Camera3D inside the SubViewport so the
## grid receives the lo-fi post-processing effect.
##
## Usage:
##   var grid = GridOverlay.create(camera_node)
##   grid.configure(cell_size, grid_origin, grid_color)
##   grid.show_grid()  /  grid.hide_grid()
##
## Which surfaces get the grid. Without a ground field the grid keeps a fixed height band
## around Y = 0 (set_floor_level). With one (set_ground, a GroundHeightField: authored terrain
## with sculpted relief and tiers, or a Blender map's ground sampled from its collision) the
## shader reads the field's height texture and draws only where a pixel lies within
## GROUND_TOLERANCE_M of the ground under it, interpolated on the field's triangles, so every
## tier top and slope gets the grid while tokens and plants standing on it do not; the
## existing steep-face normal filter keeps cliff faces clean. The fade centre follows the
## ground too (look_center()). Where the field is a water surface (GroundHeightField, phase 4)
## the grid lies on the water, not on the bed under it.

const FADE_DURATION := 0.2
## Height above or below the ground (metres, world) a pixel may be and still get the grid.
## On authored terrain the shader's ground height matches the terrain mesh exactly (same
## triangles), so this only has to absorb depth reconstruction error and the grid's own line
## width; it is kept below a token base's rim and the bulk of grass and flowers. Judged in
## the P3-3b renders (tier tops, slopes, tokens and meadow plants at the game camera). A
## Blender map's sampled ground is within a few centimetres of its collision
## (GroundHeightField.SPACING_M), which leaves most of this margin.
const GROUND_TOLERANCE_M := 0.2
## Fixed-point steps projecting the view centre onto the terrain (look_center()).
const CENTER_ITERATIONS := 4
## Transparent sort priority above the water material's (0), so the grid composites over a
## water surface it lies on.
const RENDER_PRIORITY := 10

var _material: ShaderMaterial
var _fade_tween: Tween
var _showing := false
## The ground the grid follows (set_ground), or null for the fixed band.
var _ground: GroundHeightField = null
## What was last pushed to the shader for _ground: its transform and height texture.
var _ground_transform: Transform3D = Transform3D()
var _ground_texture: Texture2D = null


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
	# Drawn after the water (both are transparent), so the grid lies on its surface.
	instance._material.render_priority = RENDER_PRIORITY
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


## Follow the ground `field` (its height texture, sample grid and transform), or with null
## go back to the fixed band of set_floor_level(). A field whose source is freed later
## (level clear) turns the ground test off by itself.
func set_ground(field: GroundHeightField) -> void:
	_ground = field
	_ground_texture = null
	_sync_ground()


## True while the grid follows a ground field rather than the fixed band.
func follows_ground() -> bool:
	return _ground != null and _ground.is_valid()


## Pushes the field's height texture and transform to the shader when either changed (a
## level scale edit moves the map; a new texture only comes with a rebuilt terrain).
func _sync_ground() -> void:
	if not _material:
		return
	if not follows_ground():
		_ground = null
		_ground_texture = null
		_material.set_shader_parameter("ground_heights_enabled", false)
		return
	var texture := _ground.get_texture()
	var xform := _ground.get_transform()
	if texture == _ground_texture and xform == _ground_transform:
		return
	_ground_texture = texture
	_ground_transform = xform
	_material.set_shader_parameter("ground_heights", texture)
	_material.set_shader_parameter("ground_world_to_map", xform.affine_inverse())
	_material.set_shader_parameter("ground_map_to_world", xform)
	_material.set_shader_parameter("ground_grid_origin", _ground.origin)
	_material.set_shader_parameter("ground_grid_step", _ground.step)
	_material.set_shader_parameter("ground_tolerance", GROUND_TOLERANCE_M)
	_material.set_shader_parameter("ground_heights_enabled", true)


## Where the ray from `origin` along `direction` meets the ground: first the plane
## Y = `floor_y`, then, when `height_at` (func(world_xz: Vector2) -> float, world Y) is
## valid, CENTER_ITERATIONS fixed-point steps onto the height it reports under the last
## point. Only the grid's fade centre uses it, so an approximate answer beside a cliff is
## fine. Returns `origin` when the ray never reaches the plane. Pure.
static func look_center(
	origin: Vector3, direction: Vector3, floor_y: float, height_at: Callable = Callable()
) -> Vector3:
	if absf(direction.y) <= 0.001:
		return origin
	var y := floor_y
	var point := origin
	var steps := CENTER_ITERATIONS if height_at.is_valid() else 1
	for i in steps:
		var t := (y - origin.y) / direction.y
		if t <= 0.0:
			break
		point = origin + direction * t
		if i + 1 < steps:
			y = height_at.call(Vector2(point.x, point.z))
	return point


## Compute the integer grid cell (floor-divided by cell_size, offset by grid_origin) that
## [param world_pos] falls into, reading cell_size/grid_origin from the same material
## set_drag_highlight() writes to -- the single source of truth for "which cell is this
## world position in" so callers never keep their own copy of this formula. Returns
## Vector2.INF (never equal to a real cell) when the material is missing or cell_size is
## non-positive, so a degenerate config always falls through to a write rather than
## silently sticking.
func snapped_cell(world_pos: Vector3) -> Vector2:
	if not _material:
		return Vector2.INF
	var cell_size: float = _material.get_shader_parameter("cell_size")
	if cell_size <= 0.0:
		return Vector2.INF
	var origin: Vector2 = _material.get_shader_parameter("grid_origin")
	return Vector2(
		floorf((world_pos.x - origin.x) / cell_size), floorf((world_pos.z - origin.y) / cell_size)
	)


## Activate cell highlighting for a drag in progress.
## [param current_pos] World position of the hovered/snapped cell center.
## [param start_pos] World position of the drag origin cell center.
func set_drag_highlight(current_pos: Vector3, start_pos: Vector3) -> void:
	if not _material:
		return
	var current_cell := snapped_cell(current_pos)
	if current_cell == Vector2.INF:
		return
	var start_cell := snapped_cell(start_pos)
	_material.set_shader_parameter("drag_active", true)
	_material.set_shader_parameter("drag_current_cell", current_cell)
	_material.set_shader_parameter("drag_start_cell", start_cell)


## Clear cell highlighting (call when drag ends).
func clear_drag_highlight() -> void:
	if not _material:
		return
	_material.set_shader_parameter("drag_active", false)


## Apply user visual settings that are independent of per-level configuration.
## These control how the grid looks (opacity, thickness, distance) without
## affecting grid scale, origin, or color set by the GM.
func apply_visual_settings(
	cell_tint_opacity: float, line_thickness: float, fade_radius: float
) -> void:
	if not _material:
		return
	var current_tint = _material.get_shader_parameter("cell_tint_color")
	if current_tint is Color:
		current_tint.a = cell_tint_opacity
		_material.set_shader_parameter("cell_tint_color", current_tint)
	_material.set_shader_parameter("line_thickness", line_thickness)
	_material.set_shader_parameter("fade_radius", fade_radius)


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
	PerformanceMonitor.start_timer(&"perf/grid_overlay_ms")
	if _ground != null:
		_sync_ground()
	# Update the fade center to where the camera is looking on the ground. For
	# orthographic/isometric cameras the camera position itself is high up and offset:
	# project its forward ray onto the grid_y_level plane, then onto the ground field.
	var cam := get_parent() as Camera3D
	if cam:
		var floor_y: float = _material.get_shader_parameter("grid_y_level")
		var vp_size := cam.get_viewport().get_visible_rect().size
		var center_screen := vp_size * 0.5
		var height_at := Callable()
		if _ground != null:
			height_at = _ground.world_height_at
		var center := look_center(
			cam.project_ray_origin(center_screen),
			cam.project_ray_normal(center_screen),
			floor_y,
			height_at
		)
		_material.set_shader_parameter("grid_center", center)
	PerformanceMonitor.stop_timer(&"perf/grid_overlay_ms")
