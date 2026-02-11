extends RefCounted
class_name BoardTokenFactory

## Factory for creating BoardToken instances from model scenes.
## Centralizes all scene construction and component wiring logic.
## Supports placeholder tokens for assets that are downloading or still loading.
##
## Usage:
##   var token = BoardTokenFactory.create_from_scene(my_model_scene)
##   # or with config:
##   var token = BoardTokenFactory.create_from_config(my_token_config)
##   # or from asset pack (with automatic placeholder & async upgrade):
##   var result = BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)
##
## Model Loading:
##   Uses AssetManager for model loading and caching.
##   GLB parsing runs entirely on a background thread (via GlbUtils.load_glb_async)
##   so creating tokens never blocks the main thread.
##   When a model isn't in the memory cache, a placeholder token is returned
##   immediately and auto-upgrades once the background load completes.
##   Call AssetManager.preload_models() before batch spawning for best performance.
##   Call AssetManager.clear_model_cache() when switching levels to free memory.

const BoardTokenScene = preload("uid://bev473ihcxqg8")
const PlaceholderTokenScript = preload("res://scenes/board_token/placeholder_token.gd")

## Tokens waiting for their model to download (network_id -> token reference)
static var _pending_tokens: Dictionary = {}

## Whether we've connected to AssetManager signals
static var _signals_connected: bool = false


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
static func create_from_scene(model_scene: Node3D, config: Resource = null) -> BoardToken:
	var components = _extract_model_components(model_scene)
	if not components:
		push_error("BoardTokenFactory: Failed to extract model components")
		return null

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

		animation_tree_instance.anim_player = components.animation_player  # Set BEFORE add_child
		rigid_body.add_child(animation_tree_instance)

	# Assemble the full token from the rigid body
	var instance = _assemble_token(rigid_body, components.collision_shape)

	# Apply config properties if provided
	if config:
		_apply_config(instance, config)

	return instance


## Create a BoardToken from a TokenConfig resource
static func create_from_config(config: Resource) -> BoardToken:
	if not config.model_scene:
		push_error("BoardTokenFactory: TokenConfig has no model_scene")
		return null

	var model = config.model_scene.instantiate()
	return create_from_scene(model, config)


## Assemble a complete BoardToken from a pre-built rigid body.
## Shared by create_from_scene and _create_placeholder_token to avoid duplication.
static func _assemble_token(rigid_body: RigidBody3D, collision_shape: CollisionShape3D) -> BoardToken:
	var instance = BoardTokenScene.instantiate() as BoardToken
	instance._factory_created = true
	_clear_placeholder_children(instance)

	# Build selection glow component (added to rigid body so it moves with token)
	var selection_glow = _build_selection_glow(collision_shape)
	rigid_body.add_child(selection_glow)

	# Build draggable component
	var draggable = _build_draggable_token(rigid_body, collision_shape)
	draggable.add_child(rigid_body)
	instance.add_child(draggable)

	# Build token controller
	var controller = _build_token_controller(rigid_body, draggable)
	instance.add_child(controller)

	# Wire up references on BoardToken
	instance.rigid_body = rigid_body
	instance._dragging_object = draggable
	instance._token_controller = controller
	instance._selection_glow = selection_glow

	NodeUtils.set_own_children(instance)

	return instance


## Extract relevant components from a model scene
## Searches recursively to handle different scene structures (imported vs runtime-loaded)
static func _extract_model_components(scene: Node3D) -> ModelComponents:
	var components = ModelComponents.new()
	components.original_scene = scene

	# Try fixed paths first (for Godot-imported scenes)
	components.armature = scene.get_node_or_null("Armature")
	components.animation_player = scene.get_node_or_null("AnimationPlayer")
	components.skeleton = (
		components.armature.get_node_or_null("Skeleton3D") if components.armature else null
	)
	components.mesh_model = (
		components.skeleton.get_node_or_null("Mesh") if components.skeleton else null
	)
	components.collision_shape = scene.get_node_or_null("Armature/Mesh/Mesh/CollisionShape3D")

	# If not found, search recursively (for GLTFDocument-loaded scenes)
	# Uses shared GlbUtils for node finding
	if not components.collision_shape:
		var found = GlbUtils.find_node_of_type(scene, "CollisionShape3D")
		if found is CollisionShape3D:
			components.collision_shape = found
	if not components.animation_player:
		components.animation_player = GlbUtils.find_node_of_type(scene, "AnimationPlayer")
	if not components.armature:
		components.armature = GlbUtils.find_node_by_name(scene, "Armature")
	if not components.skeleton:
		components.skeleton = GlbUtils.find_node_of_type(scene, "Skeleton3D")
	if not components.mesh_model:
		components.mesh_model = GlbUtils.find_first_mesh_instance(scene)

	if not components.mesh_model:
		push_error("BoardTokenFactory: No mesh found in model scene")
		return null

	return components


## Clear placeholder children from the BoardToken scene
static func _clear_placeholder_children(instance: BoardToken) -> void:
	var children = instance.get_children()
	for child in children:
		instance.remove_child(child)
		child.queue_free()


## Build and configure the RigidBody3D for the token
static func _build_rigid_body(components: ModelComponents, config: Resource = null) -> RigidBody3D:
	var rb = RigidBody3D.new()
	rb.name = "RigidBody3D"

	# Tokens never use physics gravity - position is always explicitly controlled
	# (settle animations handle placement, not physics)
	rb.gravity_scale = 0.0

	# Tokens are on layer 2 so drag raycasts (layer 1 = terrain) don't hit them.
	# Tokens don't physically collide with anything (no pushing other tokens).
	rb.collision_layer = 2
	rb.collision_mask = 0

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
static func _get_or_create_collision_shape(
	components: ModelComponents, config: Resource = null
) -> CollisionShape3D:
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
static func _build_draggable_token(
	rigid_body: RigidBody3D, collision_shape: CollisionShape3D
) -> DraggableToken:
	var draggable = DraggableToken.new()
	draggable.name = "DraggingObject3D"
	draggable.rigid_body = rigid_body
	draggable.collision_shape = collision_shape
	return draggable


## Build the BoardTokenController component
static func _build_token_controller(
	rigid_body: RigidBody3D, draggable: DraggableToken
) -> BoardTokenController:
	var controller = BoardTokenController.new() as BoardTokenController
	controller.name = "BoardTokenController"
	controller.rigid_body = rigid_body
	controller.draggable_token = draggable
	return controller


## Build the SelectionGlowRenderer component
static func _build_selection_glow(collision_shape: CollisionShape3D) -> SelectionGlowRenderer:
	var glow = SelectionGlowRenderer.new()
	glow.name = "SelectionGlow"
	# Size will be updated in _ready after collision shape is available
	# We defer the size update since the collision shape may not be in the tree yet
	if collision_shape:
		glow.call_deferred("update_size_from_collision", collision_shape)
	return glow


## Apply TokenConfig properties to a BoardToken instance
static func _apply_config(token: BoardToken, config: Resource) -> void:
	if config.token_name:
		token.token_name = config.token_name
	token.is_player_controlled = config.is_player_controlled
	token.max_health = config.max_health
	token.current_health = config.max_health


## Internal: Create a BoardToken from a specific model path
## Uses AssetManager for model loading and caching
static func _create_from_model_path(
	scene_path: String, pack_id: String, asset_id: String, config: Resource = null
) -> BoardToken:
	# Use AssetManager for loading (handles caching internally)
	# create_static_bodies=false because tokens use RigidBody3D for physics
	var model = AssetManager.get_model_instance_from_path_sync(scene_path, false)

	if not model:
		push_error("BoardTokenFactory: Failed to load asset scene: " + scene_path)
		return null

	var token = create_from_scene(model, config)

	if not token:
		push_error(
			"BoardTokenFactory: Failed to create token for asset %s/%s" % [pack_id, asset_id]
		)
		return null

	# Set the node name and display name
	var display_name = AssetManager.get_asset_display_name(pack_id, asset_id)
	token.name = display_name
	token.token_name = display_name

	# Generate a network_id if not set (will be overwritten by placement if applicable)
	if token.network_id == "":
		token.network_id = _generate_network_id()

	return token


## Generate a unique network ID for tokens
static func _generate_network_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 100000)


## Create a BoardToken from a TokenPlacement resource with async download support
## If the asset is available locally, returns the token immediately
## If the asset needs downloading, returns a placeholder token that will be upgraded later
## @param placement: The TokenPlacement containing spawn data
## @return: Dictionary with "token" and "is_placeholder" keys
static func create_from_placement_async(placement: TokenPlacement) -> Dictionary:
	if placement.pack_id == "" or placement.asset_id == "":
		push_error("BoardTokenFactory: TokenPlacement has no asset assigned")
		return {"token": null, "is_placeholder": false}

	var result = create_from_asset_async(
		placement.pack_id, placement.asset_id, placement.variant_id
	)
	var token = result.token as BoardToken

	if not token:
		return {"token": null, "is_placeholder": false}

	# Set network_id from placement_id for network synchronization
	token.network_id = placement.placement_id

	# Store placement metadata for later reference
	token.set_meta("placement_id", placement.placement_id)
	token.set_meta("pack_id", placement.pack_id)
	token.set_meta("asset_id", placement.asset_id)
	token.set_meta("variant_id", placement.variant_id)

	# Apply placement data (position, rotation, scale, properties)
	placement.apply_to_token(token)

	return {"token": token, "is_placeholder": result.is_placeholder}


## Create a BoardToken from an asset pack with async download support
## If the model is already in the memory cache, creates the token synchronously (fast).
## If the model file exists locally but isn't cached, returns a placeholder token that
## auto-upgrades once the model finishes loading asynchronously (avoids main-thread hitch).
## If the asset needs downloading, returns a placeholder that upgrades after download.
## @param pack_id: The pack identifier
## @param asset_id: The asset identifier within the pack
## @param variant_id: The variant to use
## @param priority: Download priority (lower = higher priority, used for visible tokens)
## @return: Dictionary with "token" and "is_placeholder" keys
static func create_from_asset_async(
	pack_id: String,
	asset_id: String,
	variant_id: String = "default",
	priority: int = Constants.ASSET_PRIORITY_DEFAULT
) -> Dictionary:
	_ensure_signals_connected()

	# Try to resolve the model path (checks local + cache, triggers download if needed)
	var model_path = AssetManager.resolve_model_path(pack_id, asset_id, variant_id, priority)
	print(
		(
			"BoardTokenFactory: create_from_asset_async %s/%s/%s → model_path='%s'"
			% [pack_id, asset_id, variant_id, model_path]
		)
	)

	if model_path != "":
		# Asset file is available locally
		if AssetManager.is_model_cached(model_path):
			# Fast path: model is in memory cache, create synchronously (no hitch)
			print("BoardTokenFactory: model cached, creating synchronously")
			var ready_token = _create_from_model_path(model_path, pack_id, asset_id)
			return {"token": ready_token, "is_placeholder": false}
		else:
			# Model file exists but needs loading — use a placeholder to avoid
			# blocking the main thread with GLB parsing. The placeholder will
			# auto-upgrade once the async load finishes.
			print("BoardTokenFactory: model on disk, creating placeholder for async load")
			var loading_token = _create_placeholder_token(pack_id, asset_id, variant_id)
			if loading_token:
				var upgrade_path = model_path
				loading_token.tree_entered.connect(
					func(): loading_token._async_upgrade_placeholder(upgrade_path), CONNECT_ONE_SHOT
				)
			return {"token": loading_token, "is_placeholder": true}

	# Asset needs downloading - check if download was queued
	var needs_dl = AssetManager.needs_download(pack_id, asset_id, variant_id)
	print("BoardTokenFactory: model_path empty, needs_download=%s" % str(needs_dl))
	if not needs_dl:
		# No URL available, can't create token
		push_error(
			(
				"BoardTokenFactory: Asset not available and no download URL: %s/%s/%s"
				% [pack_id, asset_id, variant_id]
			)
		)
		return {"token": null, "is_placeholder": false}

	# Create a placeholder token for download
	var placeholder_token = _create_placeholder_token(pack_id, asset_id, variant_id)
	if placeholder_token:
		# Register for upgrade when download completes
		_pending_tokens[placeholder_token.network_id] = {
			"token": placeholder_token,
			"pack_id": pack_id,
			"asset_id": asset_id,
			"variant_id": variant_id
		}
		placeholder_token.tree_exiting.connect(
			_on_pending_token_removed.bind(placeholder_token.network_id)
		)

	return {"token": placeholder_token, "is_placeholder": true}


## Create a placeholder token that shows a loading indicator
static func _create_placeholder_token(
	pack_id: String, asset_id: String, variant_id: String
) -> BoardToken:
	# Create placeholder model
	var placeholder = PlaceholderTokenScript.new()
	placeholder.name = "PlaceholderModel"

	# Build simplified rigid body with placeholder
	var rb = RigidBody3D.new()
	rb.name = "RigidBody3D"
	rb.gravity_scale = 0.0
	rb.collision_layer = 2
	rb.collision_mask = 0
	rb.axis_lock_angular_x = true
	rb.axis_lock_angular_y = true
	rb.axis_lock_angular_z = true

	# Add collision from placeholder
	var collision = placeholder.create_collision()
	rb.add_child(collision)
	rb.add_child(placeholder)

	# Assemble the full token structure
	var instance = _assemble_token(rb, collision)

	# Set metadata
	instance.network_id = _generate_network_id()
	instance.set_meta("pack_id", pack_id)
	instance.set_meta("asset_id", asset_id)
	instance.set_meta("variant_id", variant_id)
	instance.set_meta("is_placeholder", true)

	# Set display name
	var display_name = AssetManager.get_asset_display_name(pack_id, asset_id)
	instance.name = display_name + " (Loading...)"
	instance.token_name = display_name

	return instance


## Ensure we're connected to AssetManager signals for download completion
static func _ensure_signals_connected() -> void:
	if _signals_connected:
		return

	# We need to defer this because autoloads may not be ready yet
	if Engine.get_main_loop():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.root.has_node("AssetManager"):
			var manager = scene_tree.root.get_node("AssetManager")
			if not manager.asset_available.is_connected(_on_asset_available):
				manager.asset_available.connect(_on_asset_available)
			_signals_connected = true


## Called when a remote asset becomes available after download
static func _on_asset_available(
	pack_id: String, asset_id: String, variant_id: String, local_path: String
) -> void:
	# Find any pending tokens waiting for this asset
	var tokens_to_upgrade: Array = []

	for network_id in _pending_tokens:
		var pending = _pending_tokens[network_id]
		if (
			pending.pack_id == pack_id
			and pending.asset_id == asset_id
			and pending.variant_id == variant_id
		):
			tokens_to_upgrade.append(network_id)

	# Upgrade each pending token (async: load model off the main thread, then swap)
	for network_id in tokens_to_upgrade:
		var pending = _pending_tokens[network_id]
		var token = pending.token as BoardToken

		if is_instance_valid(token) and token.is_inside_tree():
			# Kick off async load on the token (a Node that can await).
			# The coroutine runs across multiple frames, then calls back to
			# _apply_model_upgrade() for the fast synchronous swap.
			token._async_upgrade_placeholder(local_path)

		_pending_tokens.erase(network_id)


## Apply a pre-loaded model to a placeholder token (fast synchronous swap).
## Called from BoardToken._async_upgrade_placeholder() after the model has been
## loaded asynchronously so there is no main-thread stall.
static func apply_model_upgrade(token: BoardToken, model: Node3D) -> void:
	if not is_instance_valid(token) or not token.rigid_body:
		if model:
			model.queue_free()
		return

	print("BoardTokenFactory: Upgrading placeholder token: " + token.token_name)

	# Extract components from new model
	var components = _extract_model_components(model)
	if not components:
		push_error("BoardTokenFactory: Failed to extract model components for upgrade")
		model.queue_free()
		return

	var rb = token.rigid_body

	# Store current transform
	var current_pos = rb.global_position
	var current_rot = rb.global_rotation
	var current_scale = rb.scale

	# Calculate where the placeholder's collision bottom was in world space
	# This is the floor position we need to preserve
	var old_floor_y: float = current_pos.y
	for child in rb.get_children():
		if child is CollisionShape3D and child.shape:
			var old_aabb: AABB = child.shape.get_debug_mesh().get_aabb()
			var old_scaled_aabb_pos = old_aabb.position * current_scale
			var old_collision_pos = child.position * current_scale
			old_floor_y = current_pos.y + old_collision_pos.y + old_scaled_aabb_pos.y
			break

	# Find and remove placeholder model
	for child in rb.get_children():
		if child.has_method("set_placeholder_color") or child.name == "PlaceholderModel":
			child.queue_free()

	# Add real model to rigid body
	rb.add_child(components.original_scene)

	# Add animation tree if available
	if components.animation_player:
		var animation_tree = BoardTokenAnimationTreeFactory.create()
		animation_tree.anim_player = components.animation_player  # Set BEFORE add_child
		rb.add_child(animation_tree)

	# Update collision shape with the real model's shape
	var old_collision: CollisionShape3D = null
	for child in rb.get_children():
		if child is CollisionShape3D:
			old_collision = child
			break

	# Use the collision shape from the model if available (e.g. from -convcolonly mesh),
	# otherwise fall back to creating one from the visual mesh
	var new_collision = _get_or_create_collision_shape(components)
	if old_collision:
		old_collision.position = new_collision.position if new_collision else Vector3.ZERO
		old_collision.shape = new_collision.shape if new_collision else null
		if new_collision and new_collision != old_collision:
			new_collision.queue_free()
	var collision_shape = old_collision

	# Calculate where the new collision bottom would be and adjust Y to match old floor position
	var new_y: float = current_pos.y
	if collision_shape and collision_shape.shape:
		var new_aabb: AABB = collision_shape.shape.get_debug_mesh().get_aabb()
		var new_scaled_aabb_pos = new_aabb.position * current_scale
		# new_floor_y = new_y + new_scaled_aabb_pos.y = old_floor_y
		# Therefore: new_y = old_floor_y - new_scaled_aabb_pos.y
		new_y = old_floor_y - new_scaled_aabb_pos.y

	# Restore transform with corrected Y position
	rb.global_position = Vector3(current_pos.x, new_y, current_pos.z)
	rb.global_rotation = current_rot
	rb.scale = current_scale

	# Update the DraggableToken's height offset now that collision shape has changed
	if token._dragging_object:
		token._dragging_object.update_height_offset()

	# Resize the selection glow to match the new collision shape
	if token._selection_glow and collision_shape:
		token._selection_glow.update_size_from_collision(collision_shape)

	# Update metadata
	token.set_meta("is_placeholder", false)
	token.name = token.token_name

	print("BoardTokenFactory: Successfully upgraded token: " + token.token_name)


## Called when a pending token is removed from the tree
static func _on_pending_token_removed(network_id: String) -> void:
	_pending_tokens.erase(network_id)


## Check if a token is still a placeholder waiting for download
static func is_placeholder(token: BoardToken) -> bool:
	return token.has_meta("is_placeholder") and token.get_meta("is_placeholder") == true


## Get the number of tokens waiting for downloads
static func get_pending_count() -> int:
	return _pending_tokens.size()
