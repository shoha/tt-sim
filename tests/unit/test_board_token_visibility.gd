extends GutTest

## Tests for BoardToken visibility toggling. The hide path clears
## rigid_body.input_ray_pickable for players; the show path must restore it, otherwise a
## re-shown token can no longer be hovered or right-clicked until something else calls
## set_interactive().


func _make_token() -> BoardToken:
	var token := BoardToken.new()
	token._factory_created = true
	var body := RigidBody3D.new()
	token.add_child(body)
	token.rigid_body = body
	add_child_autofree(token)
	return token


func test_showing_a_token_restores_pickability_for_an_interactive_token() -> void:
	var token := _make_token()
	token.set_interactive(true)
	assert_true(token.rigid_body.input_ray_pickable, "Setup: interactive token is pickable")

	# Simulate the player-side hide branch, which clears pickability directly.
	token.is_visible_to_players = false
	token.rigid_body.visible = false
	token.rigid_body.input_ray_pickable = false

	token.set_visible_to_players(true)

	assert_true(token.rigid_body.visible)
	assert_true(
		token.rigid_body.input_ray_pickable, "Show must restore pickability for interactive tokens"
	)


func test_showing_a_token_keeps_non_interactive_tokens_unpickable_offline() -> void:
	var token := _make_token()
	token.set_interactive(false)

	token.is_visible_to_players = false
	token.rigid_body.input_ray_pickable = false

	token.set_visible_to_players(true)

	assert_false(
		token.rigid_body.input_ray_pickable,
		"Offline, a non-interactive token stays unpickable after show (matches set_interactive)"
	)
