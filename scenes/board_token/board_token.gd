extends Node3D
class_name BoardToken

## Represents a PC or NPC token on the game board.
## Manages entity data like health, visibility, and status.
## Separated from interaction logic (BoardTokenController) and drag mechanics (DraggableToken).
##
## @warning Do not create with BoardToken.new() - use BoardTokenFactory instead.
## This class requires its scene structure to function properly.
##
## Runtime Scene Tree Structure (built by BoardTokenFactory):
## BoardToken (Node3D) - this script
## ├── DraggingObject3D (DraggableToken)
## │   └── RigidBody3D
## │       ├── CollisionShape3D
## │       ├── Model Scene (Armature, etc.)
## │       └── AnimationTree
## └── BoardTokenController
##
## Usage:
##   Use BoardTokenFactory.create_from_scene() or BoardTokenFactory.create_from_config()
##   to create properly configured BoardToken instances.

## Set to true by BoardTokenFactory - detects improper instantiation
var _factory_created: bool = false

# Network identification - stable unique ID for network synchronization
@export var network_id: String = ""

# Entity identification
@export var token_name: String = "Token"
@export var is_player_controlled: bool = false
@export var character_id: String = ""

# Health and status
@export var max_health: int = 100
@export var current_health: int = 100
@export var is_alive: bool = true

# Visibility and game state
@export var is_visible_to_players: bool = true
@export var is_hidden_from_gm: bool = false

# Status effects (could be expanded to a proper status effect system)
@export var status_effects: Array[String] = []

# References to child components (set by BoardTokenFactory)
var _dragging_object: DraggableToken
var _token_controller: BoardTokenController
var rigid_body: RigidBody3D

# Network interpolation (for smooth client-side motion)
var _interpolation_enabled: bool = false
var _target_position: Vector3 = Vector3.ZERO
var _target_rotation: Vector3 = Vector3.ZERO
var _target_scale: Vector3 = Vector3.ONE
const INTERPOLATION_SPEED: float = 15.0  # How fast to lerp towards target


# Signals for game state changes
signal health_changed(new_health: int, max_health: int)
signal health_depleted()
signal died()
signal revived()
signal token_visibility_changed(is_visible: bool)
signal status_effect_added(effect: String)
signal status_effect_removed(effect: String)
signal position_changed()
signal rotation_changed()
signal scale_changed()
signal transform_updated()  # Emitted during continuous manipulation (drag/rotate/scale)


func _enter_tree() -> void:
	if not _factory_created:
		push_error("BoardToken: Use BoardTokenFactory.create_from_scene(), not .new()")


func _process(delta: float) -> void:
	# Interpolate towards target transforms on clients
	if not _interpolation_enabled or not rigid_body:
		return
	
	# Smoothly lerp position, rotation, and scale
	rigid_body.global_position = rigid_body.global_position.lerp(_target_position, INTERPOLATION_SPEED * delta)
	rigid_body.global_rotation = rigid_body.global_rotation.lerp(_target_rotation, INTERPOLATION_SPEED * delta)
	rigid_body.scale = rigid_body.scale.lerp(_target_scale, INTERPOLATION_SPEED * delta)


## Set interpolation target (called by network sync on clients)
func set_interpolation_target(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	_target_position = p_position
	_target_rotation = p_rotation
	_target_scale = p_scale
	_interpolation_enabled = true


## Directly set transform without interpolation (for initial placement or host)
func set_transform_immediate(p_position: Vector3, p_rotation: Vector3, p_scale: Vector3) -> void:
	_interpolation_enabled = false
	if rigid_body:
		rigid_body.global_position = p_position
		rigid_body.global_rotation = p_rotation
		rigid_body.scale = p_scale
	_target_position = p_position
	_target_rotation = p_rotation
	_target_scale = p_scale


# Health management
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	var old_health = current_health
	current_health = max(0, current_health + amount)
	health_changed.emit(current_health, max_health, old_health)

	if current_health == 0 and old_health > 0:
		health_depleted.emit()
		_on_health_depleted()


func heal(amount: int) -> void:
	if not is_alive:
		return

	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health, old_health)

func set_max_health(new_max: int) -> void:
	max_health = new_max
	current_health = min(current_health, max_health)
	health_changed.emit(current_health, max_health)

func _on_health_depleted() -> void:
	is_alive = false
	died.emit()

func revive(health_amount: int = -1) -> void:
	if is_alive:
		return

	is_alive = true
	if health_amount < 0:
		current_health = max_health
	else:
		current_health = min(health_amount, max_health)

	revived.emit()
	health_changed.emit(current_health, max_health)

# Visibility management
func set_visible_to_players(is_visible_value: bool) -> void:
	is_visible_to_players = is_visible_value
	token_visibility_changed.emit(is_visible_value)
	_update_visibility_visuals()

func toggle_visibility() -> void:
	set_visible_to_players(not is_visible_to_players)

func _update_visibility_visuals() -> void:
	# Apply visual feedback when visibility is toggled
	if rigid_body:
		var alpha := 1.0 if is_visible_to_players else 0.5
		_set_mesh_transparency(rigid_body, alpha)


func _set_mesh_transparency(node: Node, alpha: float) -> void:
	# Recursively find all MeshInstance3D nodes and set their transparency
	for child in node.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			# Modify transparency on each surface material
			for i in range(mesh_instance.get_surface_override_material_count()):
				var mat = mesh_instance.get_surface_override_material(i)
				if mat == null and mesh_instance.mesh:
					# Get the mesh's material and create an override
					mat = mesh_instance.mesh.surface_get_material(i)
					if mat:
						mat = mat.duplicate()
						mesh_instance.set_surface_override_material(i, mat)
				if mat is StandardMaterial3D:
					var std_mat := mat as StandardMaterial3D
					std_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
					std_mat.albedo_color.a = alpha
		# Recurse into children
		_set_mesh_transparency(child, alpha)

# Status effect management
func add_status_effect(effect: String) -> void:
	if not status_effects.has(effect):
		status_effects.append(effect)
		status_effect_added.emit(effect)

func remove_status_effect(effect: String) -> void:
	if status_effects.has(effect):
		status_effects.erase(effect)
		status_effect_removed.emit(effect)

func has_status_effect(effect: String) -> bool:
	return status_effects.has(effect)

func clear_status_effects() -> void:
	for effect in status_effects:
		status_effect_removed.emit(effect)
	status_effects.clear()

# Getters for component access
func get_draggable_component() -> DraggableToken:
	return _dragging_object

func get_controller_component() -> Node:
	return _token_controller

func get_rigid_body() -> RigidBody3D:
	return rigid_body
