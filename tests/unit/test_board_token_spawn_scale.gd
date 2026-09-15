extends GutTest

## The pop-in spawn animation drives rigid_body.scale from near zero up to the
## intended scale. Any state snapshot taken while it runs (a property sync, a
## duplicate's visibility copy) must report the intended scale, not the
## transient one, or GameState and the network record a near-zero token.


func _make_token() -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child_autofree(token)
	return token


func test_logical_scale_matches_the_body_when_idle() -> void:
	var token := _make_token()
	token.rigid_body.scale = Vector3(2, 2, 2)
	assert_eq(token.get_logical_scale(), Vector3(2, 2, 2))


func test_logical_scale_reports_the_tween_target_mid_spawn() -> void:
	var token := _make_token()
	token.rigid_body.scale = Vector3(2, 2, 2)

	token.play_spawn_animation()

	assert_almost_eq(token.rigid_body.scale.x, 0.01, 0.001, "Setup: the tween starts near zero")
	assert_eq(token.get_logical_scale(), Vector3(2, 2, 2))
	assert_eq(TokenState.from_board_token(token).scale, Vector3(2, 2, 2))
