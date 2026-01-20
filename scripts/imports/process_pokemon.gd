@tool
extends EditorScenePostImport

const AnimationTreeScene = preload("res://animations/pokemon_animation_tree.tscn")

func _post_import(scene):
	print(scene.name)
	scene.print_tree_pretty()

	print("Starting post-import processing.")

	var animation_player: AnimationPlayer
	var armature: Node3D;
	var skeleton: Skeleton3D;
	var mesh_model: MeshInstance3D;
	var collision_shape: CollisionShape3D;

	armature = scene.get_node_or_null("Armature")
	animation_player = scene.get_node_or_null("AnimationPlayer")
	skeleton = armature.get_node_or_null("Skeleton3D") if armature else null
	mesh_model = skeleton.get_node_or_null("Mesh") if armature else null
	collision_shape = scene.get_node_or_null("Armature/Mesh/Mesh/CollisionShape3D")

	if !mesh_model:
		push_error("No mesh found.")
		return scene

	# Create a new RigidBody3D and configure it
	# This will be the root node of the returned scene
	var rigid_body = RigidBody3D.new()
	rigid_body.name = "RigidBody3D"
	rigid_body.axis_lock_angular_x = true
	rigid_body.axis_lock_angular_y = true
	rigid_body.axis_lock_angular_z = true


	if collision_shape:
		if armature:
			var collision_parent = armature.get_node("Mesh")
			armature.remove_child(collision_parent)
			collision_shape.get_parent().remove_child(collision_shape)
	else:
		# Iterate through MeshInstance3D children to create individual collision shapes
		var mesh_shape = mesh_model.mesh.create_convex_shape()
		collision_shape = CollisionShape3D.new()
		collision_shape.shape = mesh_shape
		collision_shape.name = "CollisionShape3D"

	# Apply the original mesh child's transform to the collision shape
	#collision_shape.transform = armature.transform
	# Add the collision shape to the RigidBody3D
	rigid_body.add_child(collision_shape)
	# Set the owner to ensure it's saved with the rigid_body # scene
	print("Added CollisionShape3D for: ", mesh_model.name)
	print("Finished setting up RigidBody3D and collision shapes.")

	scene.remove_child(armature)
	armature.set_owner(null)
	rigid_body.add_child(armature)

	scene.remove_child(animation_player)
	animation_player.set_owner(null)
	rigid_body.add_child(animation_player)

	var animation_tree_instance = AnimationTreeScene.instantiate()
	rigid_body.add_child(animation_tree_instance)
	animation_tree_instance.anim_player = animation_player

	# Ensure all nodes are owned by rigid_body
	_set_ownership_recursive(rigid_body, rigid_body)

	return rigid_body

func _set_ownership_recursive(node: Node, owner_node: Node) -> void:
	if node != owner_node:
		node.owner = owner_node
	for child in node.get_children():
		_set_ownership_recursive(child, owner_node)
