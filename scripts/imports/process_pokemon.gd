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
	
	for child in scene.get_children():
		if child.name == "AnimationPlayer":
			animation_player = child
			
		if child.name == "Armature":
			armature = child
			skeleton = armature.get_child(0)
			mesh_model = skeleton.get_child(0)

	if !mesh_model:
		push_error("No mesh found.")
		return scene
	
	# Create a new RigidBody3D and configure it
	# This will be the root node of the returned scene
	var rigid_body = RigidBody3D.new()
	rigid_body.name = scene.name + "_rigid"
	rigid_body.axis_lock_angular_x = true
	rigid_body.axis_lock_angular_y = true
	rigid_body.axis_lock_angular_z = true

	var dragging_object: DraggingObject3D = DraggingObject3D.new()
	dragging_object.name = 'DraggingObject3D'
	dragging_object.add_child(rigid_body)

	# Iterate through MeshInstance3D children to create individual collision shapes
	var mesh_shape = mesh_model.mesh.create_convex_shape()
	var collision_shape = CollisionShape3D.new()
	collision_shape.shape = mesh_shape
	collision_shape.name = scene.name + "_collision"
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
	var tree = animation_tree_instance.get_node("AnimationTree")
	animation_tree_instance.anim_player = animation_player
		
	for node in [rigid_body, animation_player, collision_shape, armature, skeleton, mesh_model, animation_tree_instance]:
		node.set_owner(dragging_object)
		
	# Create and save scene
	var packed_scene = PackedScene.new()
	packed_scene.pack(dragging_object)
	var save_path = "res://scenes/pokemon/" + scene.name + ".tscn"
	print("Saving scene... " + save_path)
	ResourceSaver.save(packed_scene, save_path)
	
	return dragging_object
