extends GutTest

## Unit tests for WaterZone.create_for_mesh() -- the Area3D shape/layer setup that
## detects tokens overlapping a `-water` mesh's footprint (see the design spec's
## "Token water detection" section) -- and for _on_body_entered()/_on_body_exited(),
## the token-crossing handlers wired in Task 7. Those handlers are called directly with
## a fake token body below, bypassing real Area3D physics overlap (GUT can't drive that
## deterministically); this covers the registry/submerged-state wiring. Splash particle
## spawning and the shared-material push are exercised end-to-end via the
## tt-sim-validator MCP bridge in Task 11.

var _original_current_scene: Node
var _dummy_scene_root: Node


## DraggableToken extends DraggingObject3D (addons/DragAndDrop3D), whose _ready() reads
## get_tree().current_scene.is_node_ready() unconditionally. gut_cmdln's headless runner
## never assigns a current_scene, so that call would crash on a null reference. See
## test_draggable_token_submerge.gd's before_each() for the full rationale -- same
## throwaway-root-node workaround, reused here since these tests also build a real
## DraggableToken hierarchy.
func before_each() -> void:
	WaterRippleRegistry.clear()
	_original_current_scene = get_tree().current_scene
	_dummy_scene_root = Node.new()
	get_tree().root.add_child(_dummy_scene_root)
	if not _dummy_scene_root.is_node_ready():
		await _dummy_scene_root.ready
	get_tree().current_scene = _dummy_scene_root


func after_each() -> void:
	get_tree().current_scene = _original_current_scene
	if is_instance_valid(_dummy_scene_root):
		_dummy_scene_root.queue_free()
	_dummy_scene_root = null


## DraggableToken's _ready() needs a real rigid_body/collision_shape to avoid its own
## early-return guards (see test_draggable_token_submerge.gd's _make_token() for why
## this shape is safe here).
func _make_token_with_rigid_body() -> DraggableToken:
	var rigid_body := RigidBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	rigid_body.add_child(collision_shape)
	rigid_body.add_child(Node3D.new())  # visual child

	var token := DraggableToken.new()
	token.rigid_body = rigid_body
	token.collision_shape = collision_shape
	token.add_child(rigid_body)
	return token


func test_body_entered_registers_token_and_marks_it_submerged() -> void:
	var token := _make_token_with_rigid_body()
	add_child_autofree(token)
	var zone := WaterZone.new()
	add_child_autofree(zone)

	zone._on_body_entered(token.rigid_body)

	assert_true(token._is_submerged)
	assert_eq(WaterRippleRegistry.build_disturbance_array()[0].w, 1.0)


func test_body_exited_unregisters_token_and_clears_submerged() -> void:
	var token := _make_token_with_rigid_body()
	add_child_autofree(token)
	var zone := WaterZone.new()
	add_child_autofree(zone)

	zone._on_body_entered(token.rigid_body)
	zone._on_body_exited(token.rigid_body)

	assert_false(token._is_submerged)
	for point in WaterRippleRegistry.build_disturbance_array():
		assert_eq(point.w, 0.0)


func test_creates_a_box_shape_matching_the_mesh_footprint() -> void:
	var mesh_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 6.0)
	mesh_node.mesh = plane

	var zone := WaterZone.create_for_mesh(mesh_node)
	add_child_autofree(zone)

	assert_not_null(zone)
	var collision_shape := zone.get_child(0) as CollisionShape3D
	assert_not_null(collision_shape)
	var shape := collision_shape.shape as BoxShape3D
	assert_not_null(shape)
	assert_almost_eq(shape.size.x, 4.0, 0.01)
	assert_almost_eq(shape.size.z, 6.0, 0.01)
	assert_almost_eq(shape.size.y, WaterZone.VERTICAL_BAND_HEIGHT, 0.01)

	mesh_node.free()


func test_sets_token_layer_mask_and_monitoring_flags() -> void:
	var mesh_node := MeshInstance3D.new()
	mesh_node.mesh = PlaneMesh.new()

	var zone := WaterZone.create_for_mesh(mesh_node)
	add_child_autofree(zone)

	assert_eq(zone.collision_mask, WaterZone.TOKEN_COLLISION_LAYER_MASK)
	assert_eq(zone.collision_layer, 0)
	assert_true(zone.monitoring)
	assert_false(zone.monitorable)

	mesh_node.free()


func test_returns_null_for_a_degenerate_mesh_footprint() -> void:
	var mesh_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.0, 0.0)
	mesh_node.mesh = plane

	var zone := WaterZone.create_for_mesh(mesh_node)

	assert_null(zone)

	mesh_node.free()


func test_returns_null_when_mesh_node_has_no_mesh() -> void:
	var mesh_node := MeshInstance3D.new()

	var zone := WaterZone.create_for_mesh(mesh_node)

	assert_null(zone)

	mesh_node.free()
