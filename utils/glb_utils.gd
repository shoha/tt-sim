extends RefCounted
class_name GlbUtils

## Shared utilities for loading and processing GLB files at runtime.
## Used by BoardTokenFactory, LevelPlayController, and any future streaming asset systems.
##
## Usage:
##   # Synchronous (blocking):
##   var model = GlbUtils.load_glb(path)
##   GlbUtils.process_collision_meshes(model, true)  # true = create StaticBody3D
##   GlbUtils.process_animations(model)
##
##   # Asynchronous (non-blocking, runs entirely on background thread):
##   var result = await GlbUtils.load_glb_async(path)
##   if result.scene:
##       GlbUtils.process_collision_meshes(result.scene, true)
##
## The async loader performs file I/O, GLB parsing (append_from_buffer), and scene
## generation (generate_scene) entirely on a WorkerThreadPool thread, so the main
## thread is never blocked. Godot 4's RenderingServer command buffer makes this safe.


## Result structure for async loading
class AsyncLoadResult:
	var scene: Node3D = null
	var error: String = ""
	var success: bool = false


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


## Load a GLB file asynchronously using WorkerThreadPool
## The entire heavy lifting (file I/O, GLB parsing, scene generation) runs on
## a background thread. Only the finished Node3D scene is passed back to the
## main thread, avoiding any cross-thread intermediate object issues.
##
## In Godot 4, RenderingServer uses a thread-safe command buffer, so mesh/texture
## creation from generate_scene() is safe from worker threads. The resulting
## scene tree is not yet in the SceneTree so Node operations are also safe.
## @param path: Path to the GLB file
## @return: AsyncLoadResult with scene or error
static func load_glb_async(path: String) -> AsyncLoadResult:
	var result = AsyncLoadResult.new()

	var scene_tree = Engine.get_main_loop() as SceneTree
	if not scene_tree:
		result.error = "No scene tree available"
		return result

	# Do ALL heavy work on the background thread:
	# file I/O + append_from_buffer + generate_scene
	var thread_result: Dictionary = {"scene": null, "error": ""}

	var task_id = WorkerThreadPool.add_task(func(): _load_glb_thread_work(path, thread_result))

	# Wait for thread to complete without blocking the main thread
	while not WorkerThreadPool.is_task_completed(task_id):
		await scene_tree.process_frame

	# Ensure task is fully cleaned up
	WorkerThreadPool.wait_for_task_completion(task_id)

	# Check for errors from thread
	if thread_result.error != "":
		result.error = thread_result.error
		push_error("GlbUtils: " + result.error)
		return result

	if not thread_result.scene:
		result.error = "Thread produced no scene for: " + path
		push_error("GlbUtils: " + result.error)
		return result

	result.scene = thread_result.scene
	result.success = true
	return result


## Thread worker function for async GLB loading
## Performs file I/O, GLB binary parsing (append_from_buffer), and scene
## generation (generate_scene) entirely on the background thread.
## Only the final Node3D scene crosses the thread boundary — no intermediate
## GLTFDocument/GLTFState objects are shared, avoiding reference issues.
static func _load_glb_thread_work(path: String, result: Dictionary) -> void:
	# 1. Read the file bytes
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		result.error = "Could not open GLB file: " + path
		return

	var buffer = file.get_buffer(file.get_length())
	file.close()

	if buffer.size() == 0:
		result.error = "GLB file is empty: " + path
		return

	# 2. Parse the GLB binary (creates intermediate mesh/material/image data)
	var gltf_document = GLTFDocument.new()
	var gltf_state = GLTFState.new()
	gltf_state.create_animations = true

	var error = gltf_document.append_from_buffer(buffer, "", gltf_state)
	if error != OK:
		result.error = "Failed to parse GLB: " + path + " (error: " + str(error) + ")"
		return

	# 3. Generate the scene tree (creates Nodes, ArrayMesh, textures, etc.)
	# In Godot 4, RenderingServer calls are thread-safe (command buffer).
	# The scene is not in the SceneTree yet, so Node ops are also safe.
	var scene = gltf_document.generate_scene(gltf_state, 30.0)
	if not scene:
		result.error = "Failed to generate scene from GLB: " + path
		return

	result.scene = scene


## Load a GLB and apply all standard post-processing
## @param path: Path to the GLB file
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes (for maps)
##                              If false, just hides collision mesh indicators (for tokens)
## @param light_intensity_scale: Multiplier for light energies (1.0 = no change, use < 1.0 for Blender "Standard" mode exports)
## @return: The fully processed Node3D scene, or null on failure
static func load_glb_with_processing(
	path: String, create_static_bodies: bool = false, light_intensity_scale: float = 1.0
) -> Node3D:
	var scene = load_glb(path)
	if not scene:
		return null

	flatten_non_node3d_parents(scene)
	process_collision_meshes(scene, create_static_bodies)
	process_animations(scene)
	process_lights(scene, light_intensity_scale)

	return scene


## Load a GLB asynchronously and apply all standard post-processing
## @param path: Path to the GLB file
## @param create_static_bodies: If true, creates StaticBody3D for collision meshes (for maps)
##                              If false, just hides collision mesh indicators (for tokens)
## @param light_intensity_scale: Multiplier for light energies (1.0 = no change, use < 1.0 for Blender "Standard" mode exports)
## @return: AsyncLoadResult with fully processed scene or error
static func load_glb_with_processing_async(
	path: String, create_static_bodies: bool = false, light_intensity_scale: float = 1.0
) -> AsyncLoadResult:
	var result = await load_glb_async(path)

	if result.success and result.scene:
		flatten_non_node3d_parents(result.scene)
		# Process collision meshes - yield periodically for large scenes
		await _process_collision_meshes_async(result.scene, create_static_bodies)
		process_animations(result.scene)
		process_lights(result.scene, light_intensity_scale)

	return result


## Process collision meshes with periodic yielding for large scenes
static func _process_collision_meshes_async(node: Node, create_static_bodies: bool) -> void:
	var scene_tree = Engine.get_main_loop() as SceneTree

	# Collect nodes to process
	var collision_nodes: Array[Dictionary] = []
	_find_collision_mesh_nodes(node, collision_nodes)

	var processed = 0
	for col_info in collision_nodes:
		var mesh_node = col_info.node as MeshInstance3D
		var suffix = col_info.suffix as String

		if not mesh_node:
			continue

		var is_only = suffix.contains("only")

		if create_static_bodies and mesh_node.mesh:
			var is_convex = suffix.contains("conv")

			var static_body = StaticBody3D.new()
			static_body.name = mesh_node.name.replace(suffix, "") + "_collision"

			var collision_shape = CollisionShape3D.new()
			collision_shape.name = "CollisionShape3D"

			# Shape creation can be slow for complex meshes
			if is_convex:
				collision_shape.shape = mesh_node.mesh.create_convex_shape()
			else:
				collision_shape.shape = mesh_node.mesh.create_trimesh_shape()

			static_body.add_child(collision_shape)

			var parent = mesh_node.get_parent()
			if parent:
				static_body.transform = mesh_node.transform
				parent.add_child(static_body)

			if is_only:
				mesh_node.get_parent().remove_child(mesh_node)
				mesh_node.free()
			else:
				mesh_node.visible = false
		else:
			# For tokens: convert collision meshes to CollisionShape3D nodes
			# so the token factory can attach them to the RigidBody3D.
			if mesh_node.mesh:
				var is_convex = suffix.contains("conv")
				var collision_shape = CollisionShape3D.new()
				collision_shape.name = "CollisionShape3D"

				if is_convex:
					collision_shape.shape = mesh_node.mesh.create_convex_shape()
				else:
					collision_shape.shape = mesh_node.mesh.create_trimesh_shape()

				var parent = mesh_node.get_parent()
				if parent:
					collision_shape.transform = mesh_node.transform
					parent.add_child(collision_shape)

			if is_only:
				mesh_node.get_parent().remove_child(mesh_node)
				mesh_node.free()
			else:
				mesh_node.visible = false

		processed += 1
		# Yield every few collision meshes to prevent frame drops
		if processed % 3 == 0 and scene_tree:
			await scene_tree.process_frame


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
	# NOTE: We use immediate free() instead of queue_free() because the scene may be
	# cached as a Node3D template and duplicated before queue_free() executes.
	# If we used queue_free(), the duplicate would still contain the collision meshes.
	for col_info in collision_nodes:
		var mesh_node = col_info.node as MeshInstance3D
		var suffix = col_info.suffix as String

		if not mesh_node:
			continue

		var is_only = suffix.contains("only")  # -colonly, -convcolonly means no visual

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
				mesh_node.get_parent().remove_child(mesh_node)
				mesh_node.free()
			else:
				mesh_node.visible = false
		else:
			# For tokens: convert collision meshes to CollisionShape3D nodes
			# so the token factory can attach them to the RigidBody3D.
			# Without this, the factory falls back to creating a convex shape from
			# the visual mesh, which is wrong for skinned meshes (bind-pose vertices).
			if mesh_node.mesh:
				var is_convex = suffix.contains("conv")
				var collision_shape = CollisionShape3D.new()
				collision_shape.name = "CollisionShape3D"

				if is_convex:
					collision_shape.shape = mesh_node.mesh.create_convex_shape()
				else:
					collision_shape.shape = mesh_node.mesh.create_trimesh_shape()

				# Place collision shape as sibling with same transform
				var parent = mesh_node.get_parent()
				if parent:
					collision_shape.transform = mesh_node.transform
					parent.add_child(collision_shape)

			# Remove or hide the original mesh node
			if is_only:
				mesh_node.get_parent().remove_child(mesh_node)
				mesh_node.free()
			else:
				mesh_node.visible = false


## Recursively find nodes that are collision meshes based on naming convention
## Godot standard suffixes: https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_3d_scenes/node_type_customization.html
static func _find_collision_mesh_nodes(node: Node, result: Array[Dictionary]) -> void:
	var name_lower = node.name.to_lower()

	# Standard Godot collision mesh suffixes (order matters - check longer suffixes first)
	var collision_suffixes = [
		"-convcolonly",  # Convex collision only (no visual)
		"-convco",  # Convex collision only (short form)
		"-convcol",  # Convex collision (keeps visual)
		"-colonly",  # Trimesh collision only (no visual)
		"-trimesh",  # Trimesh collision
		"-col",  # Generic collision
	]

	for suffix in collision_suffixes:
		if name_lower.ends_with(suffix):
			if node is MeshInstance3D:
				result.append({"node": node, "suffix": suffix})
			break

	# Recurse into children
	for child in node.get_children():
		_find_collision_mesh_nodes(child, result)


## Fix broken transform chains in a scene loaded from GLB.
## GLB files can contain non-Node3D nodes (e.g. WorldEnvironment) as intermediate
## parents. In Godot 4, a Node3D whose direct parent is NOT a Node3D loses
## transform inheritance — scaling/moving the root has no effect on those children.
## This reparents Node3D children of non-Node3D nodes to the nearest Node3D ancestor.
static func flatten_non_node3d_parents(root: Node3D) -> void:
	var non_3d_nodes: Array[Node] = []
	_find_non_node3d_with_3d_children(root, non_3d_nodes)

	for wrapper in non_3d_nodes:
		var target_parent: Node = wrapper.get_parent()
		while target_parent and not (target_parent is Node3D):
			target_parent = target_parent.get_parent()
		if not target_parent:
			target_parent = root

		var children_to_move: Array[Node] = []
		for child in wrapper.get_children():
			if child is Node3D:
				children_to_move.append(child)

		for child in children_to_move:
			var child_transform = child.transform
			child.owner = null
			wrapper.remove_child(child)
			target_parent.add_child(child)
			child.transform = child_transform


## Recursively find non-Node3D nodes that have Node3D children
static func _find_non_node3d_with_3d_children(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is Node3D:
			_find_non_node3d_with_3d_children(child, result)
		else:
			var has_3d_child = false
			for grandchild in child.get_children():
				if grandchild is Node3D:
					has_3d_child = true
					break
			if has_3d_child:
				result.append(child)
			_find_non_node3d_with_3d_children(child, result)


## Process lights in a runtime-loaded GLB
## Applies an intensity scale factor to all lights in the scene
## Use scale < 1.0 for GLBs exported with "Standard" lighting mode in Blender
## Use scale = 1.0 for GLBs exported with "Unitless" lighting mode
## @param node: The root node to process
## @param intensity_scale: Multiplier for all light energies (default 1.0 = no change)
static func process_lights(node: Node, intensity_scale: float = 1.0) -> void:
	if intensity_scale == 1.0:
		return  # No processing needed

	var lights: Array[Light3D] = []
	_find_lights_recursive(node, lights)

	for light in lights:
		light.light_energy *= intensity_scale


## Recursively find all Light3D nodes in the scene tree
static func _find_lights_recursive(node: Node, result: Array[Light3D]) -> void:
	if node is Light3D:
		result.append(node as Light3D)

	for child in node.get_children():
		_find_lights_recursive(child, result)


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
				var new_name = name_str.substr(0, name_str.length() - 5)  # Strip "_loop"
				var anim = lib.get_animation(anim_name)
				if anim:
					anim.loop_mode = Animation.LOOP_LINEAR
					anims_to_rename.append(
						{"old_name": anim_name, "new_name": new_name, "animation": anim}
					)

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


## Debug: Load a GLB and print a report of all nodes including lights
## Call this from the console or a test script to verify light import
## Example: GlbUtils.debug_load_glb("user://levels/my_map/map.glb")
static func debug_load_glb(path: String) -> void:
	print("=== GLB Debug Load: ", path, " ===")

	var scene = load_glb(path)
	if not scene:
		print("ERROR: Failed to load GLB")
		return

	var stats = {
		"total_nodes": 0,
		"mesh_instances": 0,
		"lights": [],
		"cameras": 0,
		"animation_players": 0,
		"other_nodes": []
	}

	_debug_analyze_node(scene, stats, 0)

	print("\n--- Summary ---")
	print("Total nodes: ", stats.total_nodes)
	print("MeshInstance3D: ", stats.mesh_instances)
	print("Cameras: ", stats.cameras)
	print("AnimationPlayers: ", stats.animation_players)

	if stats.lights.size() > 0:
		print("\n*** LIGHTS FOUND (%d) ***" % stats.lights.size())
		for light_info in stats.lights:
			print("  - ", light_info)
	else:
		print("\n*** NO LIGHTS FOUND ***")
		print("If your GLB should have lights, ensure:")
		print(
			"  1. Lights are included in export (Blender: check 'Punctual Lights' in glTF export)"
		)
		print("  2. The GLB uses KHR_lights_punctual extension")

	print("\n=== End Debug ===")

	# Clean up
	scene.queue_free()


## Recursively analyze nodes for debug output
static func _debug_analyze_node(node: Node, stats: Dictionary, depth: int) -> void:
	stats.total_nodes += 1
	var indent = "  ".repeat(depth)
	var node_info = "%s%s (%s)" % [indent, node.name, node.get_class()]

	if node is Light3D:
		var light_type = "Unknown"
		if node is DirectionalLight3D:
			light_type = "DirectionalLight3D"
		elif node is OmniLight3D:
			light_type = "OmniLight3D"
		elif node is SpotLight3D:
			light_type = "SpotLight3D"

		var light_desc = (
			"%s '%s' (color: %s, energy: %.2f)"
			% [light_type, node.name, node.light_color, node.light_energy]
		)
		stats.lights.append(light_desc)
		print(node_info, " ** LIGHT **")
	elif node is MeshInstance3D:
		stats.mesh_instances += 1
		print(node_info)
	elif node is Camera3D:
		stats.cameras += 1
		print(node_info)
	elif node is AnimationPlayer:
		stats.animation_players += 1
		print(node_info)
	else:
		print(node_info)

	for child in node.get_children():
		_debug_analyze_node(child, stats, depth + 1)
