extends GutTest

## Avatar tokens (AvatarTokenFactory): the recipe travels wherever a pack token's asset ids
## do (TokenPlacement, TokenState, level.json, the network payload), old levels load
## unchanged, a recipe from a newer kit still builds, each token gets a capsule round its
## figure's body core, a hidden avatar dithers, and the shade cache answers as the walk does.

const RECIPE := {
	"format": 1,
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
const LEVEL_FILE := "user://_avatartoken_test_level.json"

var _old_scene: Node = null
var _scene: Node = null


## DragAndDrop3D's DraggingObject3D waits on the current scene when it enters the tree, and
## a GUT run has none: a bare node under the root stands in for it, and holds the tokens.
func before_each() -> void:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "AvatarTokenTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene


func after_each() -> void:
	get_tree().current_scene = _old_scene
	_scene.free()


func _in_tree(token: BoardToken) -> BoardToken:
	_scene.add_child(token)
	return token


func after_all() -> void:
	if FileAccess.file_exists(LEVEL_FILE):
		DirAccess.remove_absolute(LEVEL_FILE)


func _token(recipe: Dictionary = RECIPE) -> BoardToken:
	return _in_tree(AvatarTokenFactory.create(recipe, "Plum"))


func _shape_box(token: BoardToken) -> AABB:
	for child in token.rigid_body.get_children():
		if child is CollisionShape3D:
			return (child as CollisionShape3D).shape.get_debug_mesh().get_aabb()
	return AABB()


# --- the recipe on every path ---------------------------------------------------------------


func test_placement_round_trips_the_recipe_through_json() -> void:
	var placement := TokenPlacement.new()
	placement.avatar_recipe = RECIPE.duplicate(true)
	placement.token_name = "Plum"
	var text := JSON.stringify(placement.to_dict())
	var restored := TokenPlacement.from_dict(JSON.parse_string(text))
	assert_true(restored.is_avatar())
	# JSON reads every number back as a float; the recipe is normalized to the contract's types.
	assert_eq(restored.avatar_recipe, RECIPE)
	assert_eq(typeof(restored.avatar_recipe.colours.skin), TYPE_INT)
	assert_eq(restored.pack_id, "")


func test_state_round_trips_the_recipe_and_from_placement_carries_it() -> void:
	var placement := TokenPlacement.new()
	placement.avatar_recipe = RECIPE.duplicate(true)
	var state := TokenState.from_placement(placement)
	assert_eq(state.avatar_recipe, RECIPE)
	var restored := TokenState.from_dict(state.to_dict())
	assert_eq(restored.avatar_recipe, RECIPE)
	assert_eq(restored.duplicate_state().avatar_recipe, RECIPE)


func test_level_save_and_load_keeps_the_avatar() -> void:
	var level := LevelData.new()
	level.level_name = "_avatartoken_test"
	var pack := TokenPlacement.new()
	pack.pack_id = "pokemon"
	pack.asset_id = "bulbasaur"
	var avatar := TokenPlacement.new()
	avatar.avatar_recipe = RECIPE.duplicate(true)
	avatar.token_name = "Plum"
	avatar.position = Vector3(1, 0.5, -2)
	level.token_placements.append(pack)
	level.token_placements.append(avatar)

	assert_true(LevelManager.export_level_json(level, LEVEL_FILE))
	var loaded := LevelManager.import_level_json(LEVEL_FILE)

	assert_eq(loaded.token_placements.size(), 2)
	assert_false(loaded.token_placements[0].is_avatar())
	assert_eq(loaded.token_placements[0].asset_id, "bulbasaur")
	var restored: TokenPlacement = loaded.token_placements[1]
	assert_eq(restored.avatar_recipe, RECIPE)
	assert_eq(restored.token_name, "Plum")
	assert_eq(restored.position, Vector3(1, 0.5, -2))
	for error in loaded.validate():
		assert_false(error.begins_with("Token"), "an avatar placement validates: %s" % error)


func test_old_level_without_the_field_loads_unchanged() -> void:
	var old := {
		"level_name": "old",
		"token_placements":
		[
			{
				"placement_id": "1_1",
				"pack_id": "pokemon",
				"asset_id": "bulbasaur",
				"variant_id": "shiny",
				"token_name": "Bulba",
			}
		],
	}
	var level := LevelData.from_dict(JSON.parse_string(JSON.stringify(old)))
	var placement: TokenPlacement = level.token_placements[0]
	assert_false(placement.is_avatar())
	assert_eq(placement.avatar_recipe, {})
	assert_eq(placement.variant_id, "shiny")
	assert_false(placement.to_dict().has("avatar_recipe"), "a pack token's entry is unchanged")
	assert_false(TokenState.from_placement(placement).to_dict().has("avatar_recipe"))


func test_network_payload_of_an_avatar_token_carries_the_recipe() -> void:
	var token := _token()
	var payload := TokenState.from_board_token(token).to_dict()
	assert_eq(payload.get("avatar_recipe"), RECIPE)
	# What a client does with it (RootNetworkHandler.create_token_from_state).
	var state := TokenState.from_dict(payload)
	var rebuilt := _in_tree(RootNetworkHandler.create_token_from_state(state))
	assert_not_null(rebuilt)
	assert_true(rebuilt.is_avatar())
	assert_eq(rebuilt.network_id, token.network_id)
	assert_not_null(AvatarTokenFactory.view_of(rebuilt))


func test_sync_and_diff_carry_a_changed_recipe() -> void:
	var token := _token()
	var placement := TokenPlacement.new()
	placement.sync_from_board_token(token)
	assert_eq(placement.avatar_recipe, RECIPE)
	var before := TokenState.from_board_token(token)
	var changed := RECIPE.duplicate(true)
	changed.stance = "stance_heroic"
	assert_true(AvatarTokenFactory.set_recipe(token, changed))
	var after := TokenState.from_board_token(token)
	assert_eq(before.diff(after).get("avatar_recipe"), changed)
	# A client applying that state rebuilds its figure.
	var client := _token()
	after.apply_to_token(client, false)
	assert_eq(client.avatar_recipe.stance, "stance_heroic")
	var resolved: Dictionary = AvatarTokenFactory.view_of(client).figure.get_meta("avatar_recipe")
	assert_eq(resolved.stance, "stance_heroic")


# --- building ---------------------------------------------------------------------------------


func test_a_recipe_with_an_unknown_part_still_builds_a_token() -> void:
	var recipe := RECIPE.duplicate(true)
	recipe.parts = {"body": "body_from_a_newer_kit", "head": "head_round", "hat": "wizard"}
	recipe.stance = "stance_moonwalk"
	var token := _token(recipe)
	assert_not_null(token)
	assert_eq(token.avatar_recipe.parts.body, "body_from_a_newer_kit", "the recipe is kept")
	var figure := AvatarTokenFactory.view_of(token).figure
	var resolved: Dictionary = figure.get_meta("avatar_recipe")
	assert_eq(resolved.parts.body, "body_a", "the body fell back to the kit's first")
	assert_eq(AvatarKit.figure_parts(figure).size(), 2, "body and head; no hat in the kit")


func test_placement_spawns_an_avatar_through_the_factory() -> void:
	var placement := TokenPlacement.new()
	placement.avatar_recipe = RECIPE.duplicate(true)
	placement.token_name = "Plum"
	placement.rotation_y = 1.2
	var result := BoardTokenFactory.create_from_placement_async(placement)
	var token := _in_tree(result.token)
	assert_false(result.is_placeholder)
	assert_eq(token.network_id, placement.placement_id)
	assert_eq(token.token_name, "Plum")
	assert_almost_eq(token.rigid_body.rotation.y, 1.2, 0.0001, "the figure turns with the token")


func test_collision_capsule_wraps_the_body_core() -> void:
	var box := _shape_box(_token())
	# The figure is about 1.6 m tall with its hair; soles on the origin.
	assert_almost_eq(box.position.y, 0.0, 0.01, "the capsule's bottom is the token's origin")
	assert_between(box.size.y, 1.4, 1.9, "height %.3f" % box.size.y)
	var diameter := maxf(box.size.x, box.size.z)
	assert_between(
		diameter, 2.0 * AvatarExtent.MIN_RADIUS_M, 2.0 * AvatarExtent.MAX_RADIUS_M + 0.01
	)


func test_capsule_follows_the_stance_and_ignores_outstretched_arms() -> void:
	var sneaky := RECIPE.duplicate(true)
	sneaky.stance = "stance_sneaky"
	var standing := _shape_box(_token())
	var crouched := _shape_box(_token(sneaky))
	assert_lt(crouched.size.y, standing.size.y, "a crouch is shorter than the ready stance")
	for stance in ["stance_heroic", "stance_casting", "stance_cheerful"]:
		var recipe := RECIPE.duplicate(true)
		recipe.stance = stance
		var box := _shape_box(_token(recipe))
		assert_lte(maxf(box.size.x, box.size.z), 2.0 * AvatarExtent.MAX_RADIUS_M + 0.01, stance)


func test_hidden_avatar_dithers_and_shows_again() -> void:
	var token := _token()
	var figure := AvatarTokenFactory.view_of(token).figure
	token.set_visible_to_players(false)
	for mi in AvatarKit.figure_parts(figure):
		assert_almost_eq(
			float(mi.get_instance_shader_parameter("hidden_fade")),
			AvatarTokenView.HIDDEN_FADE,
			0.001,
			"%s dithered" % mi.name
		)
	token.set_visible_to_players(true)
	for mi in AvatarKit.figure_parts(figure):
		assert_almost_eq(float(mi.get_instance_shader_parameter("hidden_fade")), 0.0, 0.001)


func test_a_rebuilt_figure_keeps_the_hidden_fade() -> void:
	var token := _token()
	token.set_visible_to_players(false)
	var changed := RECIPE.duplicate(true)
	changed.colours.hair = 3
	AvatarTokenFactory.set_recipe(token, changed)
	var figure := AvatarTokenFactory.view_of(token).figure
	for mi in AvatarKit.figure_parts(figure):
		assert_almost_eq(
			float(mi.get_instance_shader_parameter("hidden_fade")),
			AvatarTokenView.HIDDEN_FADE,
			0.001
		)


func test_set_recipe_rebuilds_only_what_changed() -> void:
	var token := _token()
	var view := AvatarTokenFactory.view_of(token)
	var figure := view.figure
	var colours := RECIPE.duplicate(true)
	colours.colours.primary = 5
	AvatarTokenFactory.set_recipe(token, colours)
	assert_same(view.figure, figure, "a colour change keeps the figure")
	assert_eq((figure.get_meta("avatar_recipe") as Dictionary).colours.primary, 5)
	var stance := colours.duplicate(true)
	stance.stance = "stance_sneaky"
	var shape_before: Shape3D = token.get_dragging_object().collision_shape.shape
	AvatarTokenFactory.set_recipe(token, stance)
	assert_same(view.figure, figure, "a stance change keeps the figure")
	assert_eq((figure.get_meta("avatar_recipe") as Dictionary).stance, "stance_sneaky")
	assert_ne(
		token.get_dragging_object().collision_shape.shape, shape_before, "a crouch, a new capsule"
	)
	var taller := stance.duplicate(true)
	taller.proportions.height = 0.95
	AvatarTokenFactory.set_recipe(token, taller)
	assert_ne(view.figure, figure, "new proportions build a new figure")


func test_figures_share_cached_skins_and_materials() -> void:
	var kit := AvatarTokenFactory.kit()
	var a := kit.build_figure(RECIPE)
	var b := kit.build_figure(RECIPE)
	var parts_a := AvatarKit.figure_parts(a)
	var parts_b := AvatarKit.figure_parts(b)
	assert_same(parts_a[0].skin, parts_b[0].skin)
	assert_same(parts_a[0].material_override, parts_b[0].material_override)
	a.free()
	b.free()


# --- shade cache ------------------------------------------------------------------------------


## A test map: a row of tall "trees" in one MultiMesh, a short MultiMesh (grass), one tall
## MeshInstance3D crown, a wide low slab (ground) and a skinned-like figure-height box.
func _map() -> Node3D:
	var root := Node3D.new()
	add_child_autofree(root)
	var tree_mesh := BoxMesh.new()
	tree_mesh.size = Vector3(3, 6, 3)
	var trees := MultiMeshInstance3D.new()
	trees.name = "Trees"
	trees.multimesh = MultiMesh.new()
	trees.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	trees.multimesh.mesh = tree_mesh
	trees.multimesh.instance_count = 6
	for i in 6:
		var xf := Transform3D(Basis().rotated(Vector3.UP, i * 0.7), Vector3(i * 4.0 - 10, 3, 2))
		trees.multimesh.set_instance_transform(i, xf.scaled_local(Vector3.ONE * (0.8 + i * 0.1)))
	root.add_child(trees)
	var grass := MultiMeshInstance3D.new()
	grass.name = "Grass"
	grass.multimesh = MultiMesh.new()
	grass.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	var blade := BoxMesh.new()
	blade.size = Vector3(0.2, 0.5, 0.2)
	grass.multimesh.mesh = blade
	grass.multimesh.instance_count = 20
	for i in 20:
		grass.multimesh.set_instance_transform(i, Transform3D(Basis(), Vector3(i - 10, 0.25, -3)))
	root.add_child(grass)
	var oak := MeshInstance3D.new()
	oak.name = "Oak"
	var oak_mesh := BoxMesh.new()
	oak_mesh.size = Vector3(4, 7, 4)
	oak.mesh = oak_mesh
	oak.position = Vector3(6, 3.5, -6)
	root.add_child(oak)
	var slab := MeshInstance3D.new()
	slab.name = "Ground"
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(40, 3, 40)
	slab.mesh = slab_mesh
	root.add_child(slab)
	return root


func test_shade_cache_answers_as_the_walk_does() -> void:
	var root := _map()
	var cache := AvatarShadeCache.build(root)
	assert_eq(cache.crown_count, 7, "six trees and the oak; no grass, no ground")
	var suns := [
		Vector3(0.3, 0.8, 0.5),
		Vector3(-0.6, 0.5, -0.2),
		Vector3(0.1, 0.3, -0.9),
		Vector3(0.9, 0.2, 0.1),
	]
	var hits := 0
	var count := 0
	for sun in suns:
		for x in range(-14, 15, 2):
			for z in range(-10, 9, 2):
				var from := Vector3(x, AvatarShade.RAY_ORIGIN_HEIGHT, z)
				var to: Vector3 = from + (sun as Vector3).normalized() * AvatarShade.RAY_LENGTH
				var walked := AvatarShade.canopy_hit(root, from, to)
				assert_eq(cache.canopy_hit(from, to), walked, "%s toward %s" % [from, sun])
				hits += 0 if walked.is_empty() else 1
				count += 1
	assert_gt(hits, 10, "the test map shades some points (%d of %d)" % [hits, count])
	assert_lt(hits, count, "and leaves some in sun")


func test_shade_cache_is_kept_per_map_until_cleared() -> void:
	var root := _map()
	AvatarShadeCache.clear()
	var first := AvatarShadeCache.for_map(root)
	assert_same(AvatarShadeCache.for_map(root), first)
	AvatarShadeCache.clear()
	assert_ne(AvatarShadeCache.for_map(root), first)
	AvatarShadeCache.clear()


func test_presets_resolve_without_fallbacks() -> void:
	var kit := AvatarTokenFactory.kit()
	for i in AvatarPresets.PRESETS.size():
		var resolved := kit.resolve(AvatarPresets.recipe(i))
		assert_eq(
			resolved.fallbacks.size(),
			0,
			"%s: %s" % [AvatarPresets.PRESETS[i].name, resolved.fallbacks]
		)
	assert_eq(AvatarPresets.recipe(0, "stance_sneaky").stance, "stance_sneaky")
	assert_eq(AvatarPresets.stance_label("stance_cheerful"), "Cheerful")
