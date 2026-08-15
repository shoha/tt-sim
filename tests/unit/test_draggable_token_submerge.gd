extends GutTest

## Unit tests for DraggableToken.set_submerged() -- the visual-only "sink into water"
## effect driven by WaterZone (see the design spec's "Visual submersion sink" section).

var _original_current_scene: Node
var _dummy_scene_root: Node


## DraggableToken extends DraggingObject3D (addons/DragAndDrop3D), whose _ready() reads
## get_tree().current_scene.is_node_ready() unconditionally. gut_cmdln's headless runner never
## assigns a current_scene, so that call would crash on a null reference.
##
## SceneTree.set_current_scene() only accepts a node that is a direct child of the tree root
## (engine-side assertion) -- this test script itself is nested under GUT's runner, so pointing
## current_scene at `self` silently fails. Instead, spin up a throwaway root-level Node for the
## duration of the test so DraggingObject3D's _ready() path runs the way it does in a real game
## scene, then tear it down and restore the original value so other test scripts in the same run
## aren't affected.
func before_each() -> void:
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


func _make_token() -> DraggableToken:
	var rigid_body := RigidBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	rigid_body.add_child(collision_shape)
	var visual_child := Node3D.new()
	rigid_body.add_child(visual_child)

	var token := DraggableToken.new()
	token.rigid_body = rigid_body
	token.collision_shape = collision_shape
	token.add_child(rigid_body)
	return token


func test_set_submerged_true_then_false_toggles_state_and_is_idempotent() -> void:
	var token := _make_token()
	add_child_autofree(token)

	token.set_submerged(true)
	assert_true(token._is_submerged)

	var tween_after_first_call := token._submerge_tween
	token.set_submerged(true)  # no-op, same state
	assert_eq(token._submerge_tween, tween_after_first_call)

	token.set_submerged(false)
	assert_false(token._is_submerged)
