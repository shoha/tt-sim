class_name AvatarTokenFactory
extends RefCounted

## Builds avatar tokens: board tokens whose model is a figure AvatarKit assembles from a
## recipe (docs/ASSET_PIPELINE.md section 10 "Recipe") and the kit every client ships under
## res://assets/avatar_kit/, so nothing is downloaded and a peer needs only the recipe.
##
## An avatar token is an ordinary BoardToken (same rigid body, drag, controller and glow,
## assembled by BoardTokenFactory._assemble_token) with:
## - `avatar_recipe` set (BoardToken.is_avatar) and empty pack ids; the recipe rides along
##   wherever a pack token's ids do (TokenPlacement, TokenState, level.json, the host's
##   state sync, undo);
## - an AvatarTokenView under the rigid body holding the figure (hidden fade and shade);
## - its own collision capsule round the figure's posed body core (AvatarExtent), which
##   sizes the selection glow, the drag height and the landing.
##
## The kit is loaded once per session (kit()). A recipe naming what this kit lacks still
## builds: AvatarRecipe falls back per slot and AvatarKit prints each fallback.
##
## For the builder: set_recipe(token, recipe) rebuilds a placed token's figure and capsule
## in place; LevelPlayController.set_avatar_recipe also syncs GameState and the network.

const DEFAULT_NAME := "Avatar"

static var _kit: AvatarKit = null
static var _kit_tried := false


## The session's avatar kit, loaded on first use; null when the kit is missing or broken.
static func kit() -> AvatarKit:
	if not _kit_tried:
		_kit_tried = true
		_kit = AvatarKit.load_kit()
		if _kit == null:
			push_error("AvatarTokenFactory: the avatar kit did not load")
	return _kit


## A token showing the figure `recipe` describes, named `token_name` (DEFAULT_NAME when
## empty), with a fresh network id; null when there is no kit.
static func create(recipe: Dictionary, token_name: String = "") -> BoardToken:
	var avatar_kit := kit()
	if avatar_kit == null:
		return null
	var normalized := AvatarRecipe.normalized(recipe)
	var figure := avatar_kit.build_figure(normalized)
	var view := AvatarTokenView.new()
	view.set_figure(figure)

	# The same body as every token (BoardTokenFactory._build_rigid_body): no gravity, layer 2
	# so drag rays (layer 1) miss it, no collisions, rotation set only by code.
	var rb := RigidBody3D.new()
	rb.name = "RigidBody3D"
	rb.gravity_scale = 0.0
	rb.collision_layer = 2
	rb.collision_mask = 0
	rb.axis_lock_angular_x = true
	rb.axis_lock_angular_y = true
	rb.axis_lock_angular_z = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = _capsule_for(avatar_kit, figure)
	rb.add_child(collision)
	rb.add_child(view)

	var token := BoardTokenFactory._assemble_token(rb, collision)
	token.avatar_recipe = normalized
	token.network_id = BoardTokenFactory._generate_network_id()
	token.token_name = token_name if not token_name.is_empty() else DEFAULT_NAME
	token.name = token.token_name
	return token


## A token for a level placement that carries a recipe (TokenPlacement.is_avatar), with the
## placement's id as its network id and the placement's transform and stats applied.
static func create_from_placement(placement: TokenPlacement) -> BoardToken:
	var token := create(placement.avatar_recipe, placement.token_name)
	if token == null:
		return null
	token.network_id = placement.placement_id
	token.set_meta("placement_id", placement.placement_id)
	placement.apply_to_token(token)
	return token


## Rebuilds `token`'s figure from `recipe` and resizes its capsule, glow and drag height to
## the new figure, keeping its transform, hidden fade and everything else. Returns false for
## a token that is not an avatar or when there is no kit. Local only: callers that need the
## change saved and synced use LevelPlayController.set_avatar_recipe.
static func set_recipe(token: BoardToken, recipe: Dictionary) -> bool:
	var view := view_of(token)
	var avatar_kit := kit()
	if view == null or avatar_kit == null:
		return false
	var normalized := AvatarRecipe.normalized(recipe)
	view.set_figure(avatar_kit.build_figure(normalized))
	token.avatar_recipe = normalized
	var collision := _collision_of(token)
	if collision != null:
		collision.shape = _capsule_for(avatar_kit, view.figure)
		# Before it enters the tree the glow sizes itself from the same node (deferred).
		if token.get_selection_glow() and token.is_inside_tree():
			token.get_selection_glow().update_size_from_collision(collision)
		if token.get_dragging_object():
			token.get_dragging_object().update_height_offset()
	return true


## The token's AvatarTokenView, or null for a pack token.
static func view_of(token: BoardToken) -> AvatarTokenView:
	if token == null or token.rigid_body == null:
		return null
	return token.rigid_body.get_node_or_null(AvatarTokenView.NODE_NAME) as AvatarTokenView


static func _collision_of(token: BoardToken) -> CollisionShape3D:
	for child in token.rigid_body.get_children():
		if child is CollisionShape3D:
			return child
	return null


static func _capsule_for(avatar_kit: AvatarKit, figure: Node3D) -> Shape3D:
	var size := AvatarExtent.capsule(avatar_kit, figure)
	return AvatarExtent.capsule_shape(size.radius, size.height)
