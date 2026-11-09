extends GutTest

## Per-token work that grew with the number of tokens on the table (card tokenscale):
## - a pack token leaves its model's shared idle clip alone once the clip loops, since writing
##   loop_mode emits `changed` and every mixer playing the clip then rebuilds its caches.

const IDLE := BoardTokenAnimationTree.IDLE


func _idle_player(token: BoardToken) -> AnimationPlayer:
	for node in token.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		if player.has_animation(IDLE):
			return player
	return null


func test_a_second_token_of_a_model_leaves_the_shared_idle_clip_alone() -> void:
	var path: String = AssetManager.resolve_model_path("beasts", "cow", "default")
	assert_ne(path, "", "the shipped Beasts pack has a cow")
	if path == "":
		return
	var first := BoardTokenFactory._create_from_model_path(path, "beasts", "cow")
	add_child_autofree(first)
	var player := _idle_player(first)
	assert_not_null(player, "the cow has the idle clip")
	if player == null:
		return
	var clip := player.get_animation(IDLE)
	assert_eq(clip.loop_mode, Animation.LOOP_LINEAR, "the first token makes the idle loop")
	var changes := [0]
	var count := func() -> void: changes[0] += 1
	clip.changed.connect(count)
	var second := BoardTokenFactory._create_from_model_path(path, "beasts", "cow")
	add_child_autofree(second)
	clip.changed.disconnect(count)
	var second_player := _idle_player(second)
	assert_same(second_player.get_animation(IDLE), clip, "the tokens share the model's clip")
	assert_eq(changes[0], 0, "the second token left the shared clip alone")
	assert_eq(second_player.get_animation(IDLE).loop_mode, Animation.LOOP_LINEAR)
