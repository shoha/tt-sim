extends RefCounted
class_name BoardTokenFactory

## Factory for creating BoardToken instances from model scenes
## Centralizes all scene construction and component wiring logic
## Supports placeholder tokens for remote assets that need downloading
##
## Usage:
##   var token = BoardTokenFactory.create_from_scene(my_model_scene)
##   # or with config:
##   var token = BoardTokenFactory.create_from_config(my_token_config)
##   # or from asset pack (with automatic download support):
##   var result = BoardTokenFactory.create_from_asset_async(pack_id, asset_id, variant_id)

const BoardTokenScene = preload("uid://bev473ihcxqg8")
const PlaceholderTokenScript = preload("res://scenes/board_token/placeholder_token.gd")

## Tokens waiting for their model to download (network_id -> token reference)
static var _pending_tokens: Dictionary = {}

## Whether we've connected to AssetPackManager signals
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

	var instance = BoardTokenScene.instantiate() as BoardToken
	instance._factory_created = true
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

		animation_tree_instance.anim_player = components.animation_player # Set BEFORE add_child
		rigid_body.add_child(animation_tree_instance)

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

	NodeUtils.set_own_children(instance)

	return instance


## Create a BoardToken from a TokenConfig resource
static func create_from_config(config: Resource) -> BoardToken:
	if not config.model_scene:
		push_error("BoardTokenFactory: TokenConfig has no model_scene")
		return null

	var model = config.model_scene.instantiate()
	return create_from_scene(model, config)


## Extract relevant components from a model scene
## Searches recursively to handle different scene structures (imported vs runtime-loaded)
static func _extract_model_components(scene: Node3D) -> ModelComponents:
	var components = ModelComponents.new()
	components.original_scene = scene

	# Try fixed paths first (for Godot-imported scenes)
	components.armature = scene.get_node_or_null("Armature")
	components.animation_player = scene.get_node_or_null("AnimationPlayer")
	components.skeleton = components.armature.get_node_or_null("Skeleton3D") if components.armature else null
	components.mesh_model = components.skeleton.get_node_or_null("Mesh") if components.skeleton else null
	components.collision_shape = scene.get_node_or_null("Armature/Mesh/Mesh/CollisionShape3D")

	# If not found, search recursively (for GLTFDocument-loaded scenes)
	if not components.animation_player:
		components.animation_player = _find_node_of_type(scene, "AnimationPlayer")
	if not components.armature:
		components.armature = _find_node_by_name(scene, "Armature")
	if not components.skeleton:
		components.skeleton = _find_node_of_type(scene, "Skeleton3D")
	if not components.mesh_model:
		components.mesh_model = _find_first_mesh_instance(scene)

	if not components.mesh_model:
		push_error("BoardTokenFactory: No mesh found in model scene")
		return null

	return components


## Find a node by class type recursively
static func _find_node_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
		var found = _find_node_of_type(child, type_name)
		if found:
			return found
	return null


## Find a node by name recursively
static func _find_node_by_name(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
		var found = _find_node_by_name(child, node_name)
		if found:
			return found
	return null


## Find the first MeshInstance3D recursively
static func _find_first_mesh_instance(root: Node) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child
		var found = _find_first_mesh_instance(child)
		if found:
			return found
	return null


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
static func _apply_config(token: BoardToken, config: Resource) -> void:
	if config.token_name:
		token.token_name = config.token_name
	token.is_player_controlled = config.is_player_controlled
	token.max_health = config.max_health
	token.current_health = config.max_health


## Create a BoardToken from an asset pack
## @param pack_id: The pack identifier (e.g., "pokemon")
## @param asset_id: The asset identifier within the pack
## @param variant_id: The variant to use (e.g., "default", "shiny")
## @param config: Optional TokenConfig for additional customization
## @return: A configured BoardToken, or null if creation failed
static func create_from_asset(pack_id: String, asset_id: String, variant_id: String = "default", config: Resource = null) -> BoardToken:
	# Use resolve_model_path to check local, cache, and trigger download if needed
	var scene_path = AssetPackManager.resolve_model_path(pack_id, asset_id, variant_id)

	if scene_path == "":
		push_error("BoardTokenFactory: Asset not found or not yet downloaded: %s/%s/%s" % [pack_id, asset_id, variant_id])
		return null

	return _create_from_model_path(scene_path, pack_id, asset_id, config)


## Internal: Create a BoardToken from a specific model path
static func _create_from_model_path(scene_path: String, pack_id: String, asset_id: String, config: Resource = null) -> BoardToken:
	var model: Node3D = null

	# For user:// paths (cached downloads), use GLTFDocument to load GLB files
	if scene_path.begins_with("user://") and scene_path.ends_with(".glb"):
		if not FileAccess.file_exists(scene_path):
			push_error("BoardTokenFactory: Cached asset not found: " + scene_path)
			return null
		model = _load_glb_from_user_path(scene_path)
	else:
		# For res:// paths, use standard resource loading
		if not ResourceLoader.exists(scene_path):
			push_error("BoardTokenFactory: Asset scene not found: " + scene_path)
			return null
		var asset_scene = load(scene_path)
		if asset_scene:
			model = asset_scene.instantiate()

	if not model:
		push_error("BoardTokenFactory: Failed to load asset scene: " + scene_path)
		return null

	var token = create_from_scene(model, config)

	if not token:
		push_error("BoardTokenFactory: Failed to create token for asset %s/%s" % [pack_id, asset_id])
		return null

	# Set the node name and display name
	var display_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)
	token.name = display_name
	token.token_name = display_name

	# Generate a network_id if not set (will be overwritten by placement if applicable)
	if token.network_id == "":
		token.network_id = _generate_network_id()

	return token


## Load a GLB file from user:// path using GLTFDocument
static func _load_glb_from_user_path(path: String) -> Node3D:
	var gltf_document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	
	# Configure GLTFState to create animations
	gltf_state.create_animations = true

	# Read the file bytes
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("BoardTokenFactory: Could not open GLB file: " + path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	# Parse the GLB
	var error = gltf_document.append_from_buffer(buffer, "", gltf_state)
	if error != OK:
		push_error("BoardTokenFactory: Failed to parse GLB: " + path + " (error: " + str(error) + ")")
		return null

	# Generate the scene with animation baking at 30 FPS
	var scene = gltf_document.generate_scene(gltf_state, 30.0)
	if not scene:
		push_error("BoardTokenFactory: Failed to generate scene from GLB: " + path)
		return null

	# Post-process: handle collision meshes that Godot's import system would normally process
	_process_collision_meshes(scene)
	
	# Post-process: handle animation naming conventions (strip _loop suffix, set loop mode)
	_process_animations(scene)

	return scene


## Process animations in a runtime-loaded GLB
## Godot's import system strips _loop suffix and sets loop mode - replicate that behavior
static func _process_animations(scene: Node) -> void:
	var anim_player = _find_node_of_type(scene, "AnimationPlayer") as AnimationPlayer
	if not anim_player:
		return
	
	# Process each library
	for lib_name in anim_player.get_animation_library_list():
		var lib = anim_player.get_animation_library(lib_name)
		var anims_to_rename: Array[Dictionary] = []
		
		# Find animations with _loop suffix
		for anim_name in lib.get_animation_list():
			var name_str = String(anim_name)
			if name_str.ends_with("_loop"):
				var new_name = name_str.substr(0, name_str.length() - 5) # Strip "_loop"
				var anim = lib.get_animation(anim_name)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
					anims_to_rename.append({
						"old_name": anim_name,
						"new_name": new_name,
						"animation": anim
					})
		
		# Rename animations (can't modify while iterating)
		for rename_info in anims_to_rename:
			lib.remove_animation(rename_info.old_name)
			# Only add if the non-loop version doesn't already exist
			if not lib.has_animation(rename_info.new_name):
				lib.add_animation(rename_info.new_name, rename_info.animation)


## Process collision mesh nodes in a runtime-loaded GLB
## Godot's import system handles these automatically, but GLTFDocument doesn't
## Standard Godot collision mesh suffixes: -col, -convcol, -colonly, -convcolonly
static func _process_collision_meshes(node: Node) -> void:
	# Collect nodes to process (can't modify tree while iterating)
	var nodes_to_hide: Array[Node] = []
	_find_collision_mesh_nodes(node, nodes_to_hide)
	
	# Hide collision mesh nodes (they're meant to be invisible collision geometry)
	for col_node in nodes_to_hide:
		if col_node is MeshInstance3D:
			col_node.visible = false


## Recursively find nodes that are collision meshes based on naming convention
## Godot standard suffixes: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
static func _find_collision_mesh_nodes(node: Node, result: Array[Node]) -> void:
	var name_lower = node.name.to_lower()
	
	# Standard Godot collision mesh suffixes (order matters - check longer suffixes first)
	var collision_suffixes = [
		"-convcolonly", # Convex collision only (no visual)
		"-convco", # Convex collision only (short form)
		"-convcol", # Convex collision (keeps visual)
		"-colonly", # Trimesh collision only (no visual)
		"-trimesh", # Trimesh collision
		"-col", # Generic collision
	]
	
	for suffix in collision_suffixes:
		if name_lower.ends_with(suffix):
			result.append(node)
			break
	
	# Recurse into children
	for child in node.get_children():
		_find_collision_mesh_nodes(child, result)


## Generate a unique network ID for tokens
static func _generate_network_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi() % 100000)


## Create a BoardToken from a TokenPlacement resource
## Applies all placement data (position, rotation, scale, properties)
## @param placement: The TokenPlacement containing spawn data
## @return: A fully configured BoardToken at the specified position
## @deprecated: Use create_from_placement_async for remote asset support
static func create_from_placement(placement: TokenPlacement) -> BoardToken:
	var result = create_from_placement_async(placement)
	return result.token


## Create a BoardToken from a TokenPlacement resource with async download support
## If the asset is available locally, returns the token immediately
## If the asset needs downloading, returns a placeholder token that will be upgraded later
## @param placement: The TokenPlacement containing spawn data
## @return: Dictionary with "token" and "is_placeholder" keys
static func create_from_placement_async(placement: TokenPlacement) -> Dictionary:
	if placement.pack_id == "" or placement.asset_id == "":
		push_error("BoardTokenFactory: TokenPlacement has no asset assigned")
		return {"token": null, "is_placeholder": false}

	var result = create_from_asset_async(placement.pack_id, placement.asset_id, placement.variant_id)
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
## If the asset is available locally, returns the token immediately
## If the asset needs downloading, returns a placeholder token that will be upgraded later
## @param pack_id: The pack identifier
## @param asset_id: The asset identifier within the pack
## @param variant_id: The variant to use
## @param priority: Download priority (lower = higher priority, used for visible tokens)
## @return: Dictionary with "token" and "is_placeholder" keys
static func create_from_asset_async(pack_id: String, asset_id: String, variant_id: String = "default", priority: int = 100) -> Dictionary:
	_ensure_signals_connected()

	# Try to resolve the model path (checks local + cache, triggers download if needed)
	var model_path = AssetPackManager.resolve_model_path(pack_id, asset_id, variant_id, priority)

	if model_path != "":
		# Asset is available - create using the resolved path directly
		var ready_token = _create_from_model_path(model_path, pack_id, asset_id)
		return {"token": ready_token, "is_placeholder": false}

	# Asset needs downloading - check if download was queued
	if not AssetPackManager.needs_download(pack_id, asset_id, variant_id):
		# No URL available, can't create token
		push_error("BoardTokenFactory: Asset not available and no download URL: %s/%s/%s" % [pack_id, asset_id, variant_id])
		return {"token": null, "is_placeholder": false}

	# Create a placeholder token
	var placeholder_token = _create_placeholder_token(pack_id, asset_id, variant_id)
	if placeholder_token:
		# Register for upgrade when download completes
		_pending_tokens[placeholder_token.network_id] = {
			"token": placeholder_token,
			"pack_id": pack_id,
			"asset_id": asset_id,
			"variant_id": variant_id
		}
		placeholder_token.tree_exiting.connect(_on_pending_token_removed.bind(placeholder_token.network_id))

	return {"token": placeholder_token, "is_placeholder": true}


## Create a placeholder token that shows a loading indicator
static func _create_placeholder_token(pack_id: String, asset_id: String, variant_id: String) -> BoardToken:
	# Create placeholder model
	var placeholder = PlaceholderTokenScript.new()
	placeholder.name = "PlaceholderModel"

	# Create a minimal BoardToken structure manually
	var instance = BoardTokenScene.instantiate() as BoardToken
	instance._factory_created = true
	_clear_placeholder_children(instance)

	# Build simplified rigid body with placeholder
	var rb = RigidBody3D.new()
	rb.name = "RigidBody3D"
	rb.axis_lock_angular_x = true
	rb.axis_lock_angular_y = true
	rb.axis_lock_angular_z = true

	# Add collision from placeholder
	var collision = placeholder.create_collision()
	rb.add_child(collision)
	rb.add_child(placeholder)

	# Build draggable component
	var draggable = _build_draggable_token(rb, collision)
	draggable.add_child(rb)
	instance.add_child(draggable)

	# Build controller
	var controller = _build_token_controller(rb, draggable)
	instance.add_child(controller)

	# Wire up references
	instance.rigid_body = rb
	instance._dragging_object = draggable
	instance._token_controller = controller

	# Set metadata
	instance.network_id = _generate_network_id()
	instance.set_meta("pack_id", pack_id)
	instance.set_meta("asset_id", asset_id)
	instance.set_meta("variant_id", variant_id)
	instance.set_meta("is_placeholder", true)

	# Set display name
	var display_name = AssetPackManager.get_asset_display_name(pack_id, asset_id)
	instance.name = display_name + " (Loading...)"
	instance.token_name = display_name

	NodeUtils.set_own_children(instance)

	return instance


## Ensure we're connected to AssetPackManager signals for download completion
static func _ensure_signals_connected() -> void:
	if _signals_connected:
		return

	# We need to defer this because autoloads may not be ready yet
	if Engine.get_main_loop():
		var scene_tree = Engine.get_main_loop() as SceneTree
		if scene_tree and scene_tree.root.has_node("AssetPackManager"):
			var manager = scene_tree.root.get_node("AssetPackManager")
			if not manager.asset_available.is_connected(_on_asset_available):
				manager.asset_available.connect(_on_asset_available)
			_signals_connected = true


## Called when a remote asset becomes available after download
static func _on_asset_available(pack_id: String, asset_id: String, variant_id: String, local_path: String) -> void:
	# Find any pending tokens waiting for this asset
	var tokens_to_upgrade: Array = []

	for network_id in _pending_tokens:
		var pending = _pending_tokens[network_id]
		if pending.pack_id == pack_id and pending.asset_id == asset_id and pending.variant_id == variant_id:
			tokens_to_upgrade.append(network_id)

	# Upgrade each pending token
	for network_id in tokens_to_upgrade:
		var pending = _pending_tokens[network_id]
		var token = pending.token as BoardToken

		if is_instance_valid(token) and token.is_inside_tree():
			_upgrade_placeholder_token(token, local_path)

		_pending_tokens.erase(network_id)


## Upgrade a placeholder token with the real model
static func _upgrade_placeholder_token(token: BoardToken, model_path: String) -> void:
	if not is_instance_valid(token) or not token.rigid_body:
		return

	print("BoardTokenFactory: Upgrading placeholder token: " + token.token_name)

	# Load the real model (handle user:// paths with GLTFDocument)
	var model: Node3D = null
	if model_path.begins_with("user://") and model_path.ends_with(".glb"):
		model = _load_glb_from_user_path(model_path)
	else:
		var asset_scene = load(model_path)
		if asset_scene:
			model = asset_scene.instantiate()

	if not model:
		push_error("BoardTokenFactory: Failed to load downloaded asset: " + model_path)
		return

	# Extract components from new model
	var components = _extract_model_components(model)
	if not components:
		push_error("BoardTokenFactory: Failed to extract model components for upgrade")
		model.queue_free()
		return

	# Store current transform
	var current_pos = token.rigid_body.global_position
	var current_rot = token.rigid_body.global_rotation
	var current_scale = token.rigid_body.scale

	# Find and remove placeholder model
	var rb = token.rigid_body
	for child in rb.get_children():
		if child.has_method("set_placeholder_color") or child.name == "PlaceholderModel":
			child.queue_free()

	# Add real model to rigid body
	rb.add_child(components.original_scene)

	# Add animation tree if available
	if components.animation_player:
		var animation_tree = BoardTokenAnimationTreeFactory.create()
		animation_tree.anim_player = components.animation_player # Set BEFORE add_child
		rb.add_child(animation_tree)

	# Update collision shape if needed
	for child in rb.get_children():
		if child is CollisionShape3D:
			if components.mesh_model and components.mesh_model.mesh:
				child.shape = components.mesh_model.mesh.create_convex_shape()
			break

	# Restore transform
	rb.global_position = current_pos
	rb.global_rotation = current_rot
	rb.scale = current_scale

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
