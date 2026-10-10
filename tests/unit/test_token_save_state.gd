extends GutTest

## TokenSaveState: the table's tokens against the map as saved. A token moved, renamed, hurt,
## added or removed counts; the few centimetres a token settles by after it is set out do not.


func _placement(id: String, position: Vector3) -> TokenPlacement:
	var placement := TokenPlacement.new()
	placement.placement_id = id
	placement.position = position
	placement.token_name = id
	return placement


func _snapshot(placements: Array) -> Dictionary:
	return TokenSaveState.of_placements(placements)


func test_the_same_tokens_are_saved() -> void:
	var saved := _snapshot([_placement("a", Vector3(1, 0, 1)), _placement("b", Vector3.ZERO)])
	var live := _snapshot([_placement("a", Vector3(1, 0, 1)), _placement("b", Vector3.ZERO)])
	assert_false(TokenSaveState.differs(saved, live))


func test_settling_onto_the_ground_is_not_a_move() -> void:
	var saved := _snapshot([_placement("a", Vector3(1, 0.5, 1))])
	var live := _snapshot([_placement("a", Vector3(1.03, 0.3, 1))])
	assert_false(TokenSaveState.differs(saved, live))


func test_a_move_a_rename_an_add_and_a_removal_count() -> void:
	var saved := _snapshot([_placement("a", Vector3(1, 0, 1))])
	assert_true(TokenSaveState.differs(saved, _snapshot([_placement("a", Vector3(2, 0, 1))])))
	var renamed := _placement("a", Vector3(1, 0, 1))
	renamed.token_name = "Marigold"
	assert_true(TokenSaveState.differs(saved, _snapshot([renamed])))
	var hurt := _placement("a", Vector3(1, 0, 1))
	hurt.current_health = 40
	assert_true(TokenSaveState.differs(saved, _snapshot([hurt])))
	var added := [_placement("a", Vector3(1, 0, 1)), _placement("b", Vector3.ZERO)]
	assert_true(TokenSaveState.differs(saved, _snapshot(added)))
	assert_true(TokenSaveState.differs(saved, {}))
