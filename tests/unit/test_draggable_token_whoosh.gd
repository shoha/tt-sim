extends GutTest

## DraggableToken's whoosh sound rule: one whoosh per burst of speed above the threshold, re-armed
## only once the speed has dropped below it again.

var _original_current_scene: Node
var _dummy_scene_root: Node


## The same throwaway current scene as test_draggable_token_submerge.gd, in case DraggableToken's
## water setup reads it.
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


func test_whoosh_threshold_is_below_max_speed() -> void:
	# WHOOSH_SPEED_THRESHOLD was 48 while WHOOSH_SPEED_MAX was 18, so the sound could
	# never play and the pitch lerp always clamped to 0.
	assert_lt(
		DraggableToken.WHOOSH_SPEED_THRESHOLD,
		DraggableToken.WHOOSH_SPEED_MAX,
		"Whoosh threshold must be reachable and below the max-pitch speed"
	)


func _make_draggable_token() -> DraggableToken:
	var rigid_body := RigidBody3D.new()
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = BoxShape3D.new()
	rigid_body.add_child(collision_shape)
	var token := DraggableToken.new()
	token.rigid_body = rigid_body
	token.collision_shape = collision_shape
	token.add_child(rigid_body)
	add_child_autofree(token)
	return token


func test_whoosh_fires_once_per_burst_above_threshold() -> void:
	var token := _make_draggable_token()
	var fast := DraggableToken.WHOOSH_SPEED_THRESHOLD + 1.0
	assert_true(token._should_play_whoosh(fast, 0.016), "First crossing fires")
	assert_false(token._should_play_whoosh(fast, 0.016), "Sustained speed does not refire")
	assert_false(
		token._should_play_whoosh(fast, 1.0), "Still no refire even after the cooldown expires"
	)


func test_whoosh_rearms_after_speed_drops_below_threshold() -> void:
	var token := _make_draggable_token()
	var fast := DraggableToken.WHOOSH_SPEED_THRESHOLD + 1.0
	assert_true(token._should_play_whoosh(fast, 0.016))
	assert_false(token._should_play_whoosh(0.0, 1.0), "Slow frame re-arms without firing")
	assert_true(token._should_play_whoosh(fast, 0.016), "Next crossing fires again")


func test_whoosh_below_threshold_never_fires() -> void:
	var token := _make_draggable_token()
	assert_false(token._should_play_whoosh(DraggableToken.WHOOSH_SPEED_THRESHOLD - 0.01, 0.016))
