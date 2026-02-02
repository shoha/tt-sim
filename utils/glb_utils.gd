extends RefCounted
class_name GlbUtils

## Shared utilities for loading and processing GLB files at runtime.
## Used by BoardTokenFactory, LevelPlayController, and any future streaming asset systems.
##
## Usage:
##   var model = GlbUtils.load_glb(path)
##   GlbUtils.process_collision_meshes(model, true)  # true = create StaticBody3D
##   GlbUtils.process_animations(model)


## Load a GLB file from a user:// or res:// path using GLTFDocument
## @param path: Path to the GLB file
## @return: The loaded Node3D scene, or null on failure
static func load_glb(path: String) -> Node3D:
	var gltf_document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	
	# Configure GLTFState to create animations
	gltf_state.create_animations = true

	# Read the file bytes
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("GlbUtils: Could not open GLB file: " + path)
		return null

	var buffer = file.get_buffer(file.get_length())
	file.close()

	# Parse the GLB
	var error = gltf_document.append_from_buffer(buffer, "", gltf_state)
	if error != OK:
		push_error("GlbUtils: Failed to parse GLB: " + path + " (error: " + str(error) + ")")
		return null

	# Generate the scene with animation baking at 30 FPS
	var scene = gltf_document.generate_scene(gltf_state, 30.0)
	if not scene:
		push_error("GlbUtils: Failed to generate scene from GLB: " + path)
		return null

	return scene


## Load a GLB and apply all standard post-processing
## @param path: Path to the GLB file
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes (for maps)
##                              If false, just hides collision mesh indicators (for tokens)
## @return: The fully processed Node3D scene, or null on failure
static func load_glb_with_processing(path: String, create_static_bodies: bool = false) -> Node3D:
	var scene = load_glb(path)
	if not scene:
		return null
	
	process_collision_meshes(scene, create_static_bodies)
	process_animations(scene)
	
	return scene


## Process collision mesh nodes in a runtime-loaded GLB
## Godot's import system handles these automatically, but GLTFDocument doesn't
## Standard Godot collision mesh suffixes: -col, -convcol, -colonly, -convcolonly
##
## @param node: The root node to process
## @param create_static_bodies: If true, creates StaticBody3D with CollisionShape3D (for maps)
##                              If false, just hides the collision mesh indicators (for tokens)
static func process_collision_meshes(node: Node, create_static_bodies: bool = false) -> void:
	# Collect nodes to process (can't modify tree while iterating)
	var collision_nodes: Array[Dictionary] = []
	_find_collision_mesh_nodes(node, collision_nodes)
	
	# Process each collision mesh node
	for col_info in collision_nodes:
		var mesh_node = col_info.node as MeshInstance3D
		var suffix = col_info.suffix as String
		
		if not mesh_node:
			continue
		
		var is_only = suffix.contains("only") # -colonly, -convcolonly means no visual
		
		if create_static_bodies and mesh_node.mesh:
			# Create actual collision geometry (for maps)
			var is_convex = suffix.contains("conv")
			
			var static_body = StaticBody3D.new()
			static_body.name = mesh_node.name.replace(suffix, "") + "_collision"
			
			var collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"
			
			if is_convex:
				collision_shape.shape = mesh_node.mesh.create_convex_shape()
			else:
				collision_shape.shape = mesh_node.mesh.create_trimesh_shape()
			
			static_body.add_child(collision_shape)
			
			# Add the static body as a sibling to the mesh node
			var parent = mesh_node.get_parent()
			if parent:
				# Copy transform from mesh node
				static_body.transform = mesh_node.transform
				parent.add_child(static_body)
			
			# Hide or remove the visual mesh based on suffix type
			if is_only:
				mesh_node.queue_free()
			else:
				mesh_node.visible = false
		else:
			# Just hide the collision mesh indicator (for tokens where RigidBody handles collision)
			if is_only:
				mesh_node.queue_free()
			else:
				mesh_node.visible = false


## Recursively find nodes that are collision meshes based on naming convention
## Godot standard suffixes: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
static func _find_collision_mesh_nodes(node: Node, result: Array[Dictionary]) -> void:
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
			if node is MeshInstance3D:
				result.append({"node": node, "suffix": suffix})
			break
	
	# Recurse into children
	for child in node.get_children():
		_find_collision_mesh_nodes(child, result)


## Process animations in a runtime-loaded GLB
## Godot's import system strips _loop suffix and sets loop mode - replicate that behavior
static func process_animations(scene: Node) -> void:
	var anim_player = find_node_of_type(scene, "AnimationPlayer") as AnimationPlayer
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


## Find a node by class type recursively
static func find_node_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.get_class() == type_name:
			return child
		var found = find_node_of_type(child, type_name)
		if found:
			return found
	return null


## Find a node by name recursively
static func find_node_by_name(root: Node, node_name: String) -> Node:
	for child in root.get_children():
		if child.name == node_name:
			return child
		var found = find_node_by_name(child, node_name)
		if found:
			return found
	return null


## Find the first MeshInstance3D recursively
static func find_first_mesh_instance(root: Node) -> MeshInstance3D:
	for child in root.get_children():
		if child is MeshInstance3D:
			return child
		var found = find_first_mesh_instance(child)
		if found:
			return found
	return null
