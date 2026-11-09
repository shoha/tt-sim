extends GutTest

## A pack token's collision shape is the model's own size and place (scenes/board_token/
## token_shape.gd). The cause of the old wrong shape: the shape was made from the mesh resource
## alone, in raw mesh units, while the mesh node sits under nodes that carry scale (a horse's
## 0.435, a pig's 0.197 under an armature of 100), so the shape came out 2.3 times a horse and a
## speck for a pig. The built-in models are checked against their own mesh bounds, the cause
## against a model built to have it.

const PACKS := ["beasts", "folk"]
## The shape's width and length may differ from the mesh bounds by this fraction.
const TOLERANCE := 0.15
## How far from the ground the shape's base may be, metres (the model's own base is at 0).
const BASE_TOLERANCE := 0.05

var _scene: Node = null
var _old_scene: Node = null


## DraggingObject3D waits on the current scene when it enters the tree, and a GUT run has none:
## a bare node under the root stands in for it, and holds the tokens.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "TokenShapeTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


## The world box of a token's visible meshes, merged: a skinned mesh as the skeleton poses it.
func _mesh_box(token: BoardToken) -> AABB:
	var box := AABB()
	var first := true
	for mi in TokenGhost.meshes_of(token.rigid_body):
		var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin != null else null
		var world := (
			mi.global_transform * mi.get_aabb()
			if skeleton == null
			else skeleton.global_transform * _blended_box(mi, skeleton)
		)
		box = world if first else box.merge(world)
		first = false
	return box


## A skinned mesh's box in its skeleton's space, every vertex blended over all its bones (the
## shape follows each vertex's main bone only).
func _blended_box(mi: MeshInstance3D, skeleton: Skeleton3D) -> AABB:
	var matrices: Array[Transform3D] = []
	for bind in mi.skin.get_bind_count():
		var bone := mi.skin.get_bind_bone(bind)
		if bone < 0:
			bone = skeleton.find_bone(mi.skin.get_bind_name(bind))
		matrices.append(skeleton.get_bone_global_pose(bone) * mi.skin.get_bind_pose(bind))
	var points := PackedVector3Array()
	for surface in mi.mesh.get_surface_count():
		var arrays := mi.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := bones.size() / vertices.size()
		for i in vertices.size():
			var p := Vector3.ZERO
			for k in stride:
				p += weights[i * stride + k] * (matrices[bones[i * stride + k]] * vertices[i])
			points.append(p)
	return TokenShape.bounds_of(points)


func _shape_node(token: BoardToken) -> CollisionShape3D:
	return token.rigid_body.find_child("CollisionShape3D", true, false) as CollisionShape3D


## A pack model's token in the scene (as the game makes it from the pack's resolved path).
func _pack_token(pack: String, asset: String) -> BoardToken:
	var path: String = AssetManager.resolve_model_path(pack, asset, "default")
	assert_ne(path, "", "%s/%s resolves" % [pack, asset])
	var token := BoardTokenFactory._create_from_model_path(path, pack, asset)
	_scene.add_child(token)
	return token


## A model: a mesh of `size` standing on y = 0 (centred in x and z), `depth` plain nodes deep, the
## nodes carrying `scales` from the outside in.
func _model(size: Vector3, scales: Array[float]) -> Node3D:
	var root := Node3D.new()
	var parent: Node3D = root
	for s in scales:
		var node := Node3D.new()
		node.scale = Vector3.ONE * s
		parent.add_child(node)
		parent = node
	var part := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	part.mesh = box
	part.position = Vector3(0.0, size.y * 0.5, 0.0)
	parent.add_child(part)
	return root


func _built_in_assets() -> Array[String]:
	var out: Array[String] = []
	for pack in PACKS:
		var manifest: Dictionary = JSON.parse_string(
			FileAccess.get_file_as_string("res://builtin_packs/%s/manifest.json" % pack)
		)
		for asset: String in manifest.assets:
			out.append("%s/%s" % [pack, asset])
	return out


func test_every_built_in_model_has_a_shape_that_fits_it() -> void:
	var names := _built_in_assets()
	assert_gt(names.size(), 30, "both built-in packs are listed")
	for entry in names:
		var parts := entry.split("/")
		var token := _pack_token(parts[0], parts[1])
		var shape := TokenMarkers.shape_box(token.rigid_body)
		var mesh := _mesh_box(token)
		assert_true(shape.has_volume(), "%s has a shape" % entry)
		assert_almost_eq(shape.size.x, mesh.size.x, mesh.size.x * TOLERANCE, "%s width" % entry)
		assert_almost_eq(shape.size.z, mesh.size.z, mesh.size.z * TOLERANCE, "%s length" % entry)
		assert_almost_eq(shape.size.y, mesh.size.y, mesh.size.y * TOLERANCE, "%s height" % entry)
		assert_almost_eq(shape.position.y, 0.0, BASE_TOLERANCE, "%s stands on the ground" % entry)
		assert_almost_eq(
			shape.get_center().x, mesh.get_center().x, mesh.size.x * TOLERANCE, "%s centred in x" % entry
		)
		assert_almost_eq(
			shape.get_center().z, mesh.get_center().z, mesh.size.z * TOLERANCE, "%s centred in z" % entry
		)
		token.free()


## board_token.tscn is the BoardToken script on one node (it was a 5.9 MB placeholder with an
## armature, 60 animations and a tree that every token instanced and threw away): a pack token
## holds only what the factory built, and its model and tree are the pack model's own.
func test_the_token_scene_is_one_node_and_a_pack_token_holds_only_the_factorys_parts() -> void:
	var bare := BoardTokenFactory.BoardTokenScene.instantiate()
	assert_true(bare is BoardToken, "the scene's root is a BoardToken")
	assert_eq(bare.get_child_count(), 0, "the scene has no placeholder children")
	bare.free()
	var token := _pack_token("beasts", "cow")
	var names: Array[String] = []
	for child in token.get_children():
		names.append(String(child.name))
	assert_eq(names, ["Draggable3D", "BoardTokenController"], "the factory's parts only")
	var trees := token.rigid_body.find_children("*", "AnimationTree", true, false)
	assert_eq(trees.size(), 1, "one animation tree, the factory's")
	var tree := trees[0] as AnimationTree
	var player := tree.get_node_or_null(tree.anim_player)
	assert_true(player is AnimationPlayer, "the tree plays an animation player")
	assert_true(token.rigid_body.is_ancestor_of(player), "the model's own player")
	token.free()


func test_the_shape_follows_the_scale_of_the_nodes_above_the_mesh() -> void:
	# The cause: the mesh is 100 x 0.01 = 1 times its data, 0.5 times, and 20 times.
	var cases: Array[Array] = [[1.0], [0.5], [100.0, 0.2], [0.01, 4.0, 0.25]]
	for scales in cases:
		var factor := 1.0
		var chain: Array[float] = []
		for s: float in scales:
			factor *= s
			chain.append(s)
		var token := BoardTokenFactory.create_from_scene(_model(Vector3(0.4, 1.0, 0.8), chain))
		_scene.add_child(token)
		var box := TokenMarkers.shape_box(token.rigid_body)
		assert_almost_eq(box.size.x, 0.4 * factor, 0.001, "width at %s" % [scales])
		assert_almost_eq(box.size.y, 1.0 * factor, 0.001, "height at %s" % [scales])
		assert_almost_eq(box.size.z, 0.8 * factor, 0.001, "length at %s" % [scales])
		assert_almost_eq(box.position.y, 0.0, 0.001, "base on the ground at %s" % [scales])
		token.free()


func test_the_shape_keeps_the_models_offset_and_the_tokens_scale() -> void:
	var model := _model(Vector3(1.0, 1.0, 1.0), [0.5])
	model.position = Vector3(0.3, 0.0, -0.2)
	var token := BoardTokenFactory.create_from_scene(model)
	_scene.add_child(token)
	token.rigid_body.scale = Vector3.ONE * 2.0
	var box := TokenMarkers.shape_box(token.rigid_body)
	var mesh := _mesh_box(token)
	assert_almost_eq(box.size, mesh.size, Vector3.ONE * 0.001, "the shape is the mesh, scaled")
	assert_almost_eq(box.get_center(), mesh.get_center(), Vector3.ONE * 0.001, "and in place")
	var node := _shape_node(token)
	assert_eq(node.transform, Transform3D.IDENTITY, "the node stays at the origin")


func test_an_authored_shape_moves_into_the_bodys_space_and_the_shared_one_stays() -> void:
	var points := PackedVector3Array(
		[
			Vector3(0, 0, 0),
			Vector3(1, 0, 0),
			Vector3(0, 0, 1),
			Vector3(1, 0, 1),
			Vector3(0, 1, 0),
			Vector3(1, 1, 0),
			Vector3(0, 1, 1),
			Vector3(1, 1, 1),
		]
	)
	var shared := ConvexPolygonShape3D.new()
	shared.points = points
	var boxes: Array[AABB] = []
	for i in 2:
		var model := _model(Vector3(1.0, 1.0, 1.0), [0.25])
		var holder: Node3D = model.get_child(0)
		var authored := CollisionShape3D.new()
		authored.name = "CollisionShape3D"
		authored.shape = shared
		holder.add_child(authored)
		var token := BoardTokenFactory.create_from_scene(model)
		_scene.add_child(token)
		boxes.append(TokenMarkers.shape_box(token.rigid_body))
		token.free()
	assert_eq(shared.points, points, "the shared resource is left as the model has it")
	for box in boxes:
		assert_almost_eq(box.size, Vector3.ONE * 0.25, Vector3.ONE * 0.001, "scaled with its parent")


func test_moving_or_leaning_a_token_keeps_the_scale_of_its_model() -> void:
	# The lean reset set a model root's whole basis to the identity, which dropped the scale that
	# sizes a pack animal: a pig stood five times as big after any placement or drag.
	var token := _pack_token("beasts", "pig")
	var before := _mesh_box(token)
	token.set_transform_immediate(Vector3(2.0, 0.0, 3.0), Vector3(0.0, 0.5, 0.0), Vector3.ONE)
	var after := _mesh_box(token)
	assert_almost_eq(after.size.y, before.size.y, 0.01, "the pig is the height it was")
	assert_almost_eq(
		TokenMarkers.shape_box(token.rigid_body).size.y, after.size.y, after.size.y * TOLERANCE
	)
	var child := Node3D.new()
	child.scale = Vector3.ONE * 0.2
	DraggableToken.set_lean(child, Basis(Vector3.RIGHT, 0.3))
	assert_almost_eq(child.transform.basis.get_scale(), Vector3.ONE * 0.2, Vector3.ONE * 0.0001)
	assert_almost_eq(child.transform.basis.orthonormalized().get_euler().x, 0.3, 0.0001)
	child.free()


func test_a_pin_footprint_is_the_shape_for_a_pack_token() -> void:
	var token := _pack_token("beasts", "pig")
	var markers := TokenMarkers.new()
	add_child_autofree(markers)
	var look := markers._read_look(token)
	var mesh := _mesh_box(token)
	assert_almost_eq(look.radius, maxf(mesh.size.x, mesh.size.z) * 0.5, 0.05, "the pig's own size")
	assert_almost_eq(look.half_height, mesh.size.y * 0.5, 0.05)
