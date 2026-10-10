extends GutTest

## Saved tokens follow the ground (TokenGrounding): a token is set down where a drop at its
## spot would land when its ground was raised, lowered or buried it, and left alone when the
## ground did not move. Authoring's tokens (AuthoringTokens) record a move as one undoable
## history entry and write their transform back into the level's placements.

const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
const CAST_TOP := 60.0

var _old_scene: Node = null
var _scene: Node3D = null
var _ground: StaticBody3D = null


## DraggingObject3D waits on the current scene when it enters the tree; a bare node stands
## in for it, holding a 40 m slab of terrain-layer ground whose top is at Y = 0.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node3D.new()
	_scene.name = "TokenGroundingTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	_ground = StaticBody3D.new()
	_ground.collision_layer = WaterSurface.TERRAIN_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 40.0)
	shape.shape = box
	_ground.add_child(shape)
	_scene.add_child(_ground)
	_set_ground_top(0.0)


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


func _set_ground_top(y: float) -> void:
	_ground.global_position = Vector3(0.0, y - 0.5, 0.0)


## An avatar token resting on the ground at `xz` (placed, then set down once).
func _token_at(xz: Vector2) -> BoardToken:
	var token := AvatarTokenFactory.create(RECIPE, "Scout")
	_scene.add_child(token)
	token.rigid_body.global_position = Vector3(xz.x, 3.0, xz.y)
	return token


func _base_y(token: BoardToken) -> float:
	return token.rigid_body.global_position.y


func test_a_token_on_unchanged_ground_stays() -> void:
	var token := _token_at(Vector2(1.0, 2.0))
	await get_tree().physics_frame
	assert_true(TokenGrounding.reground(token, CAST_TOP), "first set down from the air")
	var rested := _base_y(token)
	assert_false(TokenGrounding.reground(token, CAST_TOP), "a resting token is left alone")
	assert_eq(_base_y(token), rested)


func test_a_token_follows_raised_lowered_and_burying_ground() -> void:
	var token := _token_at(Vector2(-3.0, 4.0))
	await get_tree().physics_frame
	TokenGrounding.reground(token, CAST_TOP)
	var on_zero := _base_y(token)
	# Lowered: the token was floating.
	_set_ground_top(-1.5)
	await get_tree().physics_frame
	assert_true(TokenGrounding.reground(token, CAST_TOP))
	assert_almost_eq(_base_y(token), on_zero - 1.5, 0.01, "dropped onto the lowered ground")
	# Raised a little: the token's feet were in the ground.
	_set_ground_top(-1.2)
	await get_tree().physics_frame
	assert_true(TokenGrounding.reground(token, CAST_TOP))
	assert_almost_eq(_base_y(token), on_zero - 1.2, 0.01, "lifted onto the raised ground")
	# Raised over its head: nothing under its top, so it is cast from above the map.
	_set_ground_top(8.0)
	await get_tree().physics_frame
	assert_true(TokenGrounding.reground(token, CAST_TOP))
	assert_almost_eq(_base_y(token), on_zero + 8.0, 0.01, "dug out onto the buried ground")


func test_a_token_over_no_ground_stays() -> void:
	var token := _token_at(Vector2(100.0, 100.0))
	await get_tree().physics_frame
	assert_false(TokenGrounding.reground(token, CAST_TOP))
	assert_eq(_base_y(token), 3.0)


func test_authoring_records_a_move_and_writes_the_placement() -> void:
	var history := AuthoringHistory.new()
	var tokens := AuthoringTokens.new(null, history)
	var token := _token_at(Vector2(0.0, 0.0))
	await get_tree().physics_frame
	TokenGrounding.reground(token, CAST_TOP)
	var start := token.rigid_body.global_position
	var placement := TokenPlacement.new()
	var level := LevelData.new()
	level.add_token_placement(placement)
	tokens.adopt(placement.placement_id, token)
	var edits := [0]
	tokens.edited.connect(func() -> void: edits[0] += 1)
	token.transform_changed.emit()
	assert_false(history.can_undo(), "nothing moved: no entry")
	token.rigid_body.global_position = start + Vector3(2.0, 0.0, 1.0)
	token.transform_changed.emit()
	assert_true(history.can_undo(), "a move is one entry")
	assert_eq(edits[0], 1)
	tokens.write_placements(level)
	assert_almost_eq(placement.position, start + Vector3(2.0, 0.0, 1.0), Vector3.ONE * 0.001)
	history.undo()
	assert_almost_eq(token.rigid_body.global_position, start, Vector3.ONE * 0.001)
	tokens.write_placements(level)
	assert_almost_eq(placement.position, start, Vector3.ONE * 0.001, "undo is what saves")
	tokens.clear()
	assert_true(tokens.tokens.is_empty())
