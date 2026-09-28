class_name SubmergedMarker
extends Node3D

## The cue on the water surface above a token the water hides (WaterSurface.is_submerged():
## a small creature wading waist-deep water, anything on the bed of deeper wadeable water),
## so a token is never lost under the surface. A soft shadow disc, a bright ring at the
## token's footprint with a dark keyline, and a slow ripple spreading from it
## (shaders/submerged_marker.gdshader); it fades in and out.
##
## A child of the token's RigidBody3D, so it hides with the token (a token hidden from
## players hides its marker too), but top_level, so it stands on the water in world space
## whatever the token's sink, bob, lean or drag scale do; DraggableToken leaves it out of
## the visual children those move. DraggableToken decides when it shows
## (_update_submerged_cue): after every landing and synced move, and while a drag moves (at
## the predicted landing), so the cue follows a token dragged along a river.
## Summary: docs/UI_SYSTEMS.md "Submerged token marker".

const SHADER := preload("res://shaders/submerged_marker.gdshader")
const NODE_NAME := "SubmergedMarker"
## The ring's radius against the token's footprint (half its widest collision extent),
## clamped to MIN..MAX metres so a tiny token still gets a readable ring and a huge one a
## compact cue.
const FOOTPRINT_SCALE := 1.15
const MIN_RADIUS_M := 0.3
const MAX_RADIUS_M := 1.4
## How far above the surface the quad lies (the water writes no depth; this only keeps it
## clear of the surface's vertex bob).
const LIFT_M := 0.03
const FADE_S := 0.18
## Drawn after the water's transparent pass.
const RENDER_PRIORITY := 2
## The ring's share of the quad's half size (the shader's RING_R; a test keeps them equal).
const RING_R := 0.7

var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _radius: float = 0.5
var _fade: Tween = null
var _shown: bool = false


func _init() -> void:
	name = NODE_NAME
	top_level = true
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.render_priority = RENDER_PRIORITY
	_material.set_shader_parameter("opacity", 0.0)
	var quad := QuadMesh.new()
	quad.orientation = PlaneMesh.FACE_Y
	quad.size = Vector2(2.0, 2.0)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Ring"
	_mesh.mesh = quad
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)
	visible = false
	set_radius(_radius)


## The ring radius for a token's collision footprint `footprint_m` (half its widest
## horizontal extent, scaled). Pure.
static func radius_for(footprint_m: float) -> float:
	return clampf(footprint_m * FOOTPRINT_SCALE, MIN_RADIUS_M, MAX_RADIUS_M)


## radius_for() a token's scaled collision box (token_box()).
static func radius_for_box(box: AABB) -> float:
	return radius_for(maxf(box.size.x, box.size.z) * 0.5)


## A token's collision box in its rigid body's frame, scaled by `token_scale`: the shape's
## bounds offset by the CollisionShape3D's position (position.y is the base's offset from the
## body's origin, size.y the height). An empty box without a shape.
static func token_box(shape: CollisionShape3D, token_scale: Vector3) -> AABB:
	if shape == null or shape.shape == null:
		return AABB()
	var box := shape.shape.get_debug_mesh().get_aabb()
	box.position += shape.position
	return AABB(box.position * token_scale, box.size * token_scale)


func set_radius(radius: float) -> void:
	_radius = radius
	_mesh.scale = Vector3.ONE * (radius / RING_R)
	_material.set_shader_parameter("radius_m", radius)


func get_radius() -> float:
	return _radius


## True while shown or fading in.
func is_shown() -> bool:
	return _shown


## Shows the marker on the water surface at world `at` (the surface's Y), fading in when it
## was hidden.
func show_at(at: Vector3) -> void:
	if is_inside_tree():
		global_position = at + Vector3.UP * LIFT_M
	else:
		position = at + Vector3.UP * LIFT_M
	if _shown:
		return
	_shown = true
	visible = true
	_fade_to(1.0)


## Fades the marker out (at once with `immediate`).
func hide_marker(immediate: bool = false) -> void:
	if not _shown and not visible:
		return
	_shown = false
	if immediate or not is_inside_tree():
		_kill_fade()
		_material.set_shader_parameter("opacity", 0.0)
		visible = false
		return
	_fade_to(0.0)


func _fade_to(target: float) -> void:
	_kill_fade()
	if not is_inside_tree():
		_material.set_shader_parameter("opacity", target)
		visible = target > 0.0
		return
	var from: float = _material.get_shader_parameter("opacity")
	_fade = create_tween()
	_fade.tween_method(_set_opacity, from, target, FADE_S)
	if target <= 0.0:
		_fade.tween_callback(func() -> void: visible = _shown)


func _set_opacity(value: float) -> void:
	_material.set_shader_parameter("opacity", value)


func _kill_fade() -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = null
