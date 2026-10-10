class_name AuthoringTokens
extends RefCounted

## The level's tokens in authoring mode, so what the author sees on the map is what players
## get on it, figures included. The placements spawn the way a play-time load spawns them
## (LevelPlayLoader: models preloaded, BoardTokenFactory.create_from_placement_async, set
## down on ground that moved, TokenGrounding), into the same DragAndDrop3D, so occlusion
## fade, drag landing on tiers, decks and stones, the float rule and grid snap all come from
## GameMap as in play. Drag is on while no brush is active (GameMap._update_dragging_enabled).
##
## A token moved, turned or resized is an edit: it goes into the authoring history (undo
## puts it back) and marks the session unsaved. Before a save every token is set down on its
## ground again and copied back into its placement (write_placements), so the level saves
## where the tokens stand. Authoring adds and removes no tokens; that stays in play.
##
## Re-grounding is not an edit of its own: it follows the ground, so after an edit settles
## (regrounded after a physics frame, once the collision has the new ground) a token stands
## on the new ground, and undoing the edit sets it back down on the old.

## Emitted when the author moved, turned or resized a token (or undid or redid that).
signal edited

## placement_id -> BoardToken.
var tokens: Dictionary = {}

var _game_map: GameMap = null
var _history: AuthoringHistory = null
## BoardToken -> [position, rotation, scale] where it last rested, for the history entry of
## its next move.
var _rest: Dictionary = {}


func _init(game_map: GameMap, history: AuthoringHistory) -> void:
	_game_map = game_map
	_history = history


## Spawns `level`'s placements, after loading the models they use (as play does, so no
## placeholder stands in with another size). Waits a physics frame so each is set down on
## the map's collision. `is_superseded` () -> bool drops the spawn when a newer open began.
func spawn_async(level: LevelData, is_superseded: Callable) -> void:
	clear()
	if level == null or level.token_placements.is_empty():
		return
	var assets: Array[Dictionary] = []
	for placement in level.token_placements:
		if not placement.is_avatar():
			assets.append(
				{
					"pack_id": placement.pack_id,
					"asset_id": placement.asset_id,
					"variant_id": placement.variant_id,
				}
			)
	if not assets.is_empty():
		await AssetManager.preload_models(assets, func(_done: int, _total: int) -> void: pass, false)
	if is_superseded.call() or not is_instance_valid(_game_map):
		return
	await _game_map.get_tree().physics_frame
	if is_superseded.call() or not is_instance_valid(_game_map):
		return
	var cast_top := TokenGrounding.cast_top(_game_map)
	for placement in level.token_placements:
		var token: BoardToken = BoardTokenFactory.create_from_placement_async(placement).token
		if token == null:
			continue
		_game_map.drag_and_drop_node.add_child(token)
		TokenGrounding.reground(token, cast_top)
		adopt(placement.placement_id, token)


## Takes `token` (in the tree, where it rests) as the one standing for `placement_id`: the
## author may drag it, and its moves become history entries.
func adopt(placement_id: String, token: BoardToken) -> void:
	token.set_interactive(true)
	token.transform_changed.connect(_on_transform_changed.bind(token))
	tokens[placement_id] = token
	_rest[token] = _pose(token)


## Sets every token down on the ground as it is now (TokenGrounding). Returns how many moved.
func reground_all() -> int:
	if tokens.is_empty() or not is_instance_valid(_game_map):
		return 0
	var cast_top := TokenGrounding.cast_top(_game_map)
	var moved := 0
	for token in tokens.values():
		if is_instance_valid(token) and TokenGrounding.reground(token, cast_top):
			_rest[token] = _pose(token)
			moved += 1
	return moved


## reground_all() once the physics space has the ground an edit just left (one physics
## frame on).
func reground_after_physics() -> void:
	if tokens.is_empty() or not is_instance_valid(_game_map):
		return
	await _game_map.get_tree().physics_frame
	reground_all()


## Copies each token's transform and stats into its placement in `level`.
func write_placements(level: LevelData) -> void:
	for placement_id in tokens:
		var token: BoardToken = tokens[placement_id]
		var placement := level.get_token_placement(placement_id)
		if placement and is_instance_valid(token):
			placement.sync_from_board_token(token)


## Frees the tokens (a new open, or leaving).
func clear() -> void:
	for token in tokens.values():
		if is_instance_valid(token):
			token.queue_free()
	tokens.clear()
	_rest.clear()


## A drop, turn or resize finished: one history entry from where the token last rested.
func _on_transform_changed(token: BoardToken) -> void:
	var before: Array = _rest.get(token, [])
	var after := _pose(token)
	_rest[token] = after
	if before.is_empty() or _same_pose(before, after):
		return  # A cancelled drag, or a click that moved nothing.
	_history.record(
		{
			"label": "Move token",
			"undo": _apply_pose.bind(token, before),
			"redo": _apply_pose.bind(token, after),
		}
	)
	edited.emit()


func _apply_pose(token: BoardToken, pose: Array) -> void:
	if not is_instance_valid(token):
		return
	token.set_transform_immediate(pose[0], pose[1], pose[2])
	_rest[token] = pose
	token.get_dragging_object().water.update_floating()
	edited.emit()


static func _same_pose(a: Array, b: Array) -> bool:
	for i in a.size():
		if not (a[i] as Vector3).is_equal_approx(b[i]):
			return false
	return true


static func _pose(token: BoardToken) -> Array:
	return [
		token.rigid_body.global_position, token.rigid_body.global_rotation, token.get_logical_scale()
	]
