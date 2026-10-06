extends GutTest

## The avatar builder (AvatarBuilder, AvatarSurprise): a surprise recipe is always valid
## and drawn from the curated sets, a committed edit is one undo entry that syncs and
## undoes, a cancelled edit puts the token back exactly, only an avatar's owner or the GM
## may open "Edit Avatar", proportion drags reach the figure once a frame, and a recipe
## the builder made round-trips through a level file.

const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
const LEVEL_FILE := "user://_avatarbuilder_test_level.json"
const TOKEN_ID := "avatarbuilder_token"
const PEER := 4242

var _old_scene: Node = null
var _scene: Node = null


## DragAndDrop3D's DraggingObject3D waits on the current scene when it enters the tree, and
## a GUT run has none: a bare node under the root stands in for it, and holds the tokens.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "AvatarBuilderTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()
	GameState.remove_token_state(TOKEN_ID)
	GameState.clear_all_permissions()
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE


func after_all() -> void:
	if FileAccess.file_exists(LEVEL_FILE):
		DirAccess.remove_absolute(LEVEL_FILE)


func _token(recipe: Dictionary = RECIPE) -> BoardToken:
	var token := AvatarTokenFactory.create(recipe, "Plum")
	token.network_id = TOKEN_ID
	_scene.add_child(token)
	return token


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


# --- surprise me -------------------------------------------------------------------------------


func test_surprise_recipes_are_valid_and_within_the_curated_sets() -> void:
	var kit := AvatarTokenFactory.kit()
	var sets: Dictionary = kit.manifest.colour_sets
	var counts := kit.face_counts()
	var rng := _rng(7)
	for i in 200:
		var recipe := AvatarSurprise.recipe(kit, rng)
		var resolved := kit.resolve(recipe)
		assert_eq(resolved.fallbacks.size(), 0, "draw %d: %s" % [i, resolved.fallbacks])
		for slot in recipe.colours:
			var size: int = (sets[AvatarPalette.SET_FOR_SLOT[slot]] as Array).size()
			assert_between(int(recipe.colours[slot]), 0, size - 1, "colour %s" % slot)
		for kind in recipe.face:
			assert_between(int(recipe.face[kind]), 0, int(counts[kind]) - 1, "face %s" % kind)
		for control in recipe.proportions:
			var value: float = recipe.proportions[control]
			assert_between(value, AvatarSurprise.SHAPE_MIN, AvatarSurprise.SHAPE_MAX)
			assert_almost_eq(value, AvatarSurprise.quantize(value), 1e-6, "on the step")
		assert_true(kit.stance_names().has(recipe.stance))
		assert_ne(recipe.colours.primary, recipe.colours.secondary, "trim differs from cloth")
		assert_ne(recipe.colours.accent, recipe.colours.primary, "accent differs from cloth")
		assert_ne(recipe.colours.accent, recipe.colours.secondary, "accent differs from trim")


func test_surprise_outfits_are_harmonious_and_seeded_draws_repeat() -> void:
	var kit := AvatarTokenFactory.kit()
	var cloth: Array = kit.manifest.colour_sets.cloth
	var rng := _rng(3)
	for i in 100:
		var outfit := AvatarSurprise.harmonious_outfit(cloth, rng)
		var main := Color.html(cloth[outfit.primary][0])
		var trim := Color.html(cloth[outfit.secondary][0])
		var neutral := (
			main.s < AvatarSurprise.NEUTRAL_SATURATION or trim.s < AvatarSurprise.NEUTRAL_SATURATION
		)
		assert_true(
			neutral or AvatarSurprise.hue_distance(main, trim) >= AvatarSurprise.TRIM_HUE_DEG,
			(
				"draw %d: trim %d sits across the wheel from cloth %d"
				% [i, outfit.secondary, outfit.primary]
			)
		)
	assert_eq(AvatarSurprise.recipe(kit, _rng(11)), AvatarSurprise.recipe(kit, _rng(11)))
	var rerolled := AvatarSurprise.reroll(kit, RECIPE, &"stance", _rng(5))
	assert_ne(rerolled.stance, RECIPE.stance, "a stance reroll picks another stance")
	assert_eq(rerolled.colours, RECIPE.colours, "and keeps the rest")
	assert_eq(AvatarSurprise.quantize(0.62), 0.6)
	assert_eq(AvatarSurprise.quantize(1.4), 1.0)


# --- edit: confirm, cancel, undo ---------------------------------------------------------------


func test_cancel_puts_the_token_back_exactly() -> void:
	var token := _token()
	var figure := AvatarTokenFactory.view_of(token).figure
	var builder := AvatarBuilder.open_for_token(_scene, token)
	builder.pick_stance("stance_sneaky")
	builder.pick_colour("hair", 3)
	builder.pick_face("eyes", 4)
	assert_eq(token.avatar_recipe.stance, "stance_sneaky", "picks preview on the token")
	assert_eq((figure.get_meta("avatar_recipe") as Dictionary).colours.hair, 3)
	watch_signals(builder)
	builder.cancel()
	assert_signal_emitted(builder, "cancelled")
	assert_signal_not_emitted(builder, "edit_confirmed")
	assert_eq(token.avatar_recipe, AvatarRecipe.normalized(RECIPE))
	var built: Dictionary = AvatarTokenFactory.view_of(token).figure.get_meta("avatar_recipe")
	assert_eq(built.stance, "stance_ready")
	assert_eq(built.colours.hair, 0)
	assert_eq(built.face.eyes, 1)


func test_confirm_emits_the_edit_once_and_it_records_one_undo_entry_that_syncs() -> void:
	var token := _token()
	var builder := AvatarBuilder.open_for_token(_scene, token)
	builder.pick_stance("stance_heroic")
	builder.pick_colour("primary", 5)
	builder.name_input.text = "Rook"
	watch_signals(builder)
	builder.confirm()
	builder.confirm()
	assert_signal_emit_count(builder, "edit_confirmed", 1)
	var args: Array = get_signal_parameters(builder, "edit_confirmed")
	assert_same(args[0], token)
	assert_eq(args[1], AvatarRecipe.normalized(RECIPE), "the original for undo")
	assert_eq(args[2].stance, "stance_heroic")
	assert_eq(args[4], "Rook")

	# What the context menu controller does with it: one compound entry, the synced change.
	var changes := AvatarBuilder.undo_changes(TOKEN_ID, args[1], args[2], args[3], args[4])
	assert_eq(changes.size(), 2, "the recipe and the name, undone together")
	assert_eq(
		AvatarBuilder.undo_changes(TOKEN_ID, args[1], args[1], "Plum", "Plum").size(),
		0,
		"nothing changed, nothing recorded"
	)
	var level := LevelData.new()
	var placement := TokenPlacement.new()
	placement.placement_id = TOKEN_ID
	placement.avatar_recipe = RECIPE.duplicate(true)
	placement.token_name = "Plum"
	level.add_token_placement(placement)
	token.set_meta("placement_id", TOKEN_ID)
	var spawner := TokenSpawner.new()
	spawner.setup(null, func() -> LevelData: return level)
	spawner.track_network_token(token)
	GameState.register_token_from_board_token(token)
	var history := GameplayActionHistory.new()
	add_child_autofree(history)
	history.set_token_lookup(spawner.find_token_by_network_id)
	history.set_rename_callable(spawner.rename_token)
	history.set_recipe_callable(
		func(target: BoardToken, recipe: Dictionary) -> bool:
			var ok := AvatarTokenFactory.set_recipe(target, recipe)
			spawner.notify_token_properties_changed(target)
			return ok
	)
	history.record_compound_property_change(changes)
	assert_eq(history.get_count(), 1, "one undo entry per committed edit")
	AvatarTokenFactory.set_recipe(token, args[2])
	spawner.rename_token(token, args[4])
	assert_eq(GameState.get_token_state(TOKEN_ID).avatar_recipe.stance, "stance_heroic", "synced")
	assert_eq(GameState.get_token_state(TOKEN_ID).token_name, "Rook")

	assert_eq(history.undo(), "edited avatar")
	assert_eq(history.get_count(), 0)
	assert_eq(token.avatar_recipe, AvatarRecipe.normalized(RECIPE), "undo restores the figure")
	assert_eq(token.token_name, "Plum")
	assert_eq(GameState.get_token_state(TOKEN_ID).avatar_recipe, AvatarRecipe.normalized(RECIPE))
	assert_eq(
		(AvatarTokenFactory.view_of(token).figure.get_meta("avatar_recipe") as Dictionary).stance,
		"stance_ready"
	)


# --- permissions -------------------------------------------------------------------------------


func test_only_the_owner_or_the_gm_can_edit_an_avatar() -> void:
	var token := _token()
	assert_true(TokenContextMenu.can_edit_avatar(token, true, true, PEER), "the GM edits any")
	assert_true(TokenContextMenu.can_edit_avatar(token, false, false, PEER), "single player")
	assert_false(
		TokenContextMenu.can_edit_avatar(token, false, true, PEER), "a player without CONTROL"
	)
	GameState.grant_token_permission(TOKEN_ID, PEER, TokenPermissions.Permission.CONTROL)
	assert_true(TokenContextMenu.can_edit_avatar(token, false, true, PEER), "the owner")
	assert_false(TokenContextMenu.can_edit_avatar(token, false, true, PEER + 1), "another player")
	var pack := BoardToken.new()
	pack._factory_created = true
	add_child_autofree(pack)
	assert_false(TokenContextMenu.can_edit_avatar(pack, true, false, PEER), "not an avatar")
	assert_false(TokenContextMenu.can_edit_avatar(null, true, false, PEER))


# --- proportion throttle -----------------------------------------------------------------------


func test_proportion_drags_reach_the_figure_once_a_frame_and_quantised() -> void:
	var builder := AvatarBuilder.open_for_new(_scene, RECIPE, "Plum")
	var preview: AvatarBuilderPreview = builder._preview
	var before := preview.applies
	builder.set_proportion("height", 0.31)
	builder.set_proportion("height", 0.62)
	builder.set_proportion("build", 0.2)
	assert_eq(preview.applies, before, "nothing until the frame")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(preview.applies, before + 1, "three drag steps, one rebuild")
	assert_eq(builder.recipe.proportions.height, 0.6, "quantised to the step")
	assert_eq(builder.recipe.proportions.build, 0.2)
	assert_eq(preview.recipe.proportions, builder.recipe.proportions)
	builder.set_proportion("height", 0.61)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(preview.applies, before + 1, "the same step again does not rebuild")
	builder.cancel()


# --- round trip --------------------------------------------------------------------------------


func test_a_builder_recipe_round_trips_through_save_and_load() -> void:
	var builder := AvatarBuilder.open_for_new(_scene)
	assert_false(builder.recipe.is_empty(), "a new avatar never starts blank")
	assert_false(builder.token_name.is_empty())
	builder.surprise()
	builder.pick_face("mouths", 2)
	var recipe: Dictionary = builder.recipe.duplicate(true)
	var level := LevelData.new()
	level.level_name = "_avatarbuilder_test"
	var placement := TokenPlacement.new()
	placement.avatar_recipe = recipe
	placement.token_name = builder.token_name
	level.token_placements.append(placement)
	assert_true(LevelManager.export_level_json(level, LEVEL_FILE))
	var loaded := LevelManager.import_level_json(LEVEL_FILE)
	assert_eq(loaded.token_placements.size(), 1)
	assert_eq(loaded.token_placements[0].avatar_recipe, recipe)
	var restored := AvatarTokenFactory.create_from_placement(loaded.token_placements[0])
	_scene.add_child(restored)
	assert_eq(restored.avatar_recipe, recipe)
	assert_eq(AvatarTokenFactory.kit().resolve(restored.avatar_recipe).fallbacks.size(), 0)
	builder.cancel()
