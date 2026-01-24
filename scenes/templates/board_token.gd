extends Node3D
class_name BoardToken

## Represents a PC or NPC token on the game board
## Manages entity data like health, visibility, and status
## Separated from interaction logic (TokenController) and drag mechanics (DraggableToken)
##
## Runtime Scene Tree Structure:
## BoardToken (Node3D) - this script
## ├── DraggingObject3D (DraggableToken) - created at runtime
## │   └── RigidBody3D (from rigid_body export or Placeholder)
## │       ├── CollisionShape3D
## │       ├── Armature
## │       ├── AnimationPlayer
## │       └── AnimationTree
## └── TokenController - created at runtime
##
## Usage:
## - Set the @export rigid_body to an existing RigidBody3D with model/collision
## - Or leave it unset to use the Placeholder node from the scene
## - The script will automatically create DraggableToken and TokenController components

# Preload the controller script since it's not a global class yet when this loads
const TokenControllerScript = preload("res://scenes/templates/token_controller.gd")

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

# References to child components
var _dragging_object: DraggableToken
var _token_controller: Node # TokenController
@export var rigid_body: RigidBody3D

@onready var placeholder: Node3D = $Placeholder

# Signals for game state changes
signal health_changed(new_health: int, max_health: int)
signal health_depleted()
signal died()
signal revived()
signal token_visibility_changed(is_visible: bool)
signal status_effect_added(effect: String)
signal status_effect_removed(effect: String)

func _ready() -> void:
	if not rigid_body:
		push_warning("BoardToken: No RigidBody3D found in Token node.")
		rigid_body = placeholder
		return

	_construct_tree()

func _construct_tree() -> void:
	# Remove placeholder from scene tree
	placeholder.set_owner(null)
	remove_child(placeholder)

	# Create draggable component
	_dragging_object = DraggableToken.new()
	_dragging_object.name = "DraggingObject3D"
	_dragging_object.add_child(rigid_body)
	add_child(_dragging_object)

	# Create interaction controller
	_token_controller = TokenControllerScript.new()
	_token_controller.name = "TokenController"
	_token_controller.rigid_body = rigid_body
	_token_controller.draggable_token = _dragging_object
	add_child(_token_controller)

# Health management
func take_damage(amount: int) -> void:
	if not is_alive:
		return

	var old_health = current_health
	current_health = max(0, current_health + amount)
	health_changed.emit(current_health, max_health)

	if current_health == 0 and old_health > 0:
		health_depleted.emit()
		_on_health_depleted()


func heal(amount: int) -> void:
	if not is_alive:
		return

	current_health = min(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

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
		if is_visible_to_players:
			# Fully visible
			rigid_body.modulate = Color(1.0, 1.0, 1.0, 1.0)
		else:
			# Semi-transparent to indicate hidden
			rigid_body.modulate = Color(0.5, 0.5, 0.5, 0.5)

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
