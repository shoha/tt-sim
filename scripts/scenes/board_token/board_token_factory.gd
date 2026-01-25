extends RefCounted
class_name BoardTokenFactory

## Factory for creating BoardToken instances from model scenes
## Centralizes all scene construction and component wiring logic
##
## Usage:
##   var token = BoardTokenFactory.create_from_scene(my_model_scene)
##   # or with config:
##   var token = BoardTokenFactory.create_from_config(my_token_config)

const BoardTokenScene = preload("uid://bev473ihcxqg8")

## Internal structure to hold extracted model components
class ModelComponents:
	var armature: Node3D
	var animation_player: AnimationPlayer
	var skeleton: Skeleton3D
	var mesh_model: MeshInstance3D
	var collision_shape: CollisionShape3D
	var original_scene: Node3D


## Create a BoardToken from a model scene (Node3D)
## This is the main entry point for runtime token creation
## @param config: Optional TokenConfig resource for customization
static func create_from_scene(model_scene: Node3D, config: Resource = null) -> iBoardToken:
	var components = _extract_model_components(model_scene)
	if not components:
		push_error("BoardTokenFactory: Failed to extract model components")
		return null

	var instance = BoardTokenScene.instantiate() as iBoardToken
	_clear_placeholder_children(instance)

	# Build the rigid body with collision
	var rigid_body = _build_rigid_body(components, config)

	# Attach the original scene to the rigid body
	rigid_body.add_child(components.original_scene)

	# Add animation tree if animation player exists
	if components.animation_player:
		var animation_tree_instance = null

		if config and config.animation_tree_scene:
			animation_tree_instance = config.animation_tree_scene.instantiate()
		else:
			animation_tree_instance = BoardTokenAnimationTreeFactory.create()

		rigid_body.add_child(animation_tree_instance)
		animation_tree_instance.anim_player = components.animation_player

	# Build draggable component
	var draggable = _build_draggable_token(rigid_body, components.collision_shape)
	draggable.add_child(rigid_body)
	instance.add_child(draggable)

	# Build token controller
	var controller = _build_token_controller(rigid_body, draggable)
	instance.add_child(controller)

	# Wire up references on BoardToken
	instance.rigid_body = rigid_body
	instance._dragging_object = draggable
	instance._token_controller = controller

	# Apply config properties if provided
	if config:
		_apply_config(instance, config)

	Utils.set_own_children(instance)

	return instance


## Create a BoardToken from a TokenConfig resource
static func create_from_config(config: Resource) -> iBoardToken:
	if not config.model_scene:
		push_error("BoardTokenFactory: TokenConfig has no model_scene")
		return null

	var model = config.model_scene.instantiate()
	return create_from_scene(model, config)


## Extract relevant components from a model scene
static func _extract_model_components(scene: Node3D) -> ModelComponents:
	var components = ModelComponents.new()
	components.original_scene = scene

	components.armature = scene.get_node_or_null("Armature")
	components.animation_player = scene.get_node_or_null("AnimationPlayer")
	components.skeleton = components.armature.get_node_or_null("Skeleton3D") if components.armature else null
	components.mesh_model = components.skeleton.get_node_or_null("Mesh") if components.skeleton else null

	# Try to find existing collision shape
	components.collision_shape = scene.get_node_or_null("Armature/Mesh/Mesh/CollisionShape3D")

	if not components.mesh_model:
		push_error("BoardTokenFactory: No mesh found in model scene")
		return null

	return components


## Clear placeholder children from the BoardToken scene
static func _clear_placeholder_children(instance: iBoardToken) -> void:
	var children = instance.get_children()
	for child in children:
		instance.remove_child(child)
		child.queue_free()


## Build and configure the RigidBody3D for the token
static func _build_rigid_body(components: ModelComponents, config: Resource = null) -> RigidBody3D:
	var rb = RigidBody3D.new()
	rb.name = "RigidBody3D"

	# Apply rotation locks (default: lock all axes for board tokens)
	var lock_rotation = true if not config else config.lock_rotation
	if lock_rotation:
		rb.axis_lock_angular_x = true
		rb.axis_lock_angular_y = true
		rb.axis_lock_angular_z = true

	# Handle collision shape
	var collision_shape = _get_or_create_collision_shape(components, config)
	rb.add_child(collision_shape)

	# Store the collision shape reference for later use
	components.collision_shape = collision_shape

	return rb


## Get existing collision shape or create one from mesh
static func _get_or_create_collision_shape(components: ModelComponents, config: Resource = null) -> CollisionShape3D:
	var use_convex = true if not config else config.use_convex_collision

	if components.collision_shape:
		# Use existing collision shape - detach from parent first
		_detach_existing_collision(components)
		components.collision_shape.owner = null
		return components.collision_shape

	# Create new collision shape from mesh
	var collision_shape = CollisionShape3D.new()
	collision_shape.name = "CollisionShape3D"

	if use_convex and components.mesh_model and components.mesh_model.mesh:
		collision_shape.shape = components.mesh_model.mesh.create_convex_shape()

	return collision_shape


## Detach an existing collision shape from its parent hierarchy
static func _detach_existing_collision(components: ModelComponents) -> void:
	if not components.collision_shape:
		return

	var collision_parent = components.collision_shape.get_parent()
	if collision_parent:
		collision_parent.remove_child(components.collision_shape)

	# Clean up the intermediate parent if it exists (e.g., Armature/Mesh)
	if components.armature:
		var mesh_parent = components.armature.get_node_or_null("Mesh")
		if mesh_parent and mesh_parent.get_child_count() == 0:
			components.armature.remove_child(mesh_parent)


## Build the DraggableToken component
static func _build_draggable_token(rigid_body: RigidBody3D, collision_shape: CollisionShape3D) -> DraggableToken:
	var draggable = DraggableToken.new()
	draggable.name = "DraggingObject3D"
	draggable.rigid_body = rigid_body
	draggable.collision_shape = collision_shape
	return draggable


## Build the BoardTokenController component
static func _build_token_controller(rigid_body: RigidBody3D, draggable: DraggableToken) -> BoardTokenController:
	var controller = BoardTokenController.new() as BoardTokenController
	controller.name = "BoardTokenController"
	controller.rigid_body = rigid_body
	controller.draggable_token = draggable
	return controller


## Apply TokenConfig properties to a BoardToken instance
static func _apply_config(token: iBoardToken, config: Resource) -> void:
	if config.token_name:
		token.token_name = config.token_name
	token.is_player_controlled = config.is_player_controlled
	token.max_health = config.max_health
	token.current_health = config.max_health
