class_name LiveEditGround
extends Node

## The table follows the ground a live edit leaves, on every peer. LevelPlayController makes
## one beside the table's LiveEdits (start_live_edits) and it goes with them.
##
## Once the edits so far have settled (LiveEdits.is_settled: sent on the GM's side, applied on
## a client's; the terrain's chunks rebuilt) and the physics space has the new collision
## (PHYSICS_FRAMES on), it:
##   - refits the camera, pan and shadow bounds and the reflection probe when the ground's range
##     moved (LevelPlayController.refit_view_to_ground; authoring's
##     AuthoringController._refresh_bounds_after_edit). An authored map's grid follows its
##     ground by itself (GroundHeightField.from_terrain reads the terrain's heights, water and
##     decks); a Blender map's grid ground was sampled from its collision once, so it is
##     sampled again when the map's water or crossings changed
##     (MapSourceLoader.fit_grid_ground_async);
##   - on the GM's side, sets every token down on the ground as it is now (TokenGrounding) and
##     sends each one that moved to every peer (NetworkStateSync.broadcast_token_properties:
##     reliable, GameState kept in step), so a token on raised ground stands on it everywhere
##     and one on a bridge that went sits in the water. Clients only take the host's positions.

## The GM's side set `moved` tokens down on the ground the edits left.
signal regrounded(moved: int)

## Physics frames to wait after the edits settle before casting onto the new collision.
const PHYSICS_FRAMES := 2

var _edits: LiveEdits = null
var _lpc: LevelPlayController = null
## The log length the table last followed.
var _followed: int = 0
## Physics frames left before following (-1: none due).
var _wait: int = -1
## A Blender map's water and crossings versions its grid ground was sampled at.
var _glb_key: Vector2i = Vector2i(-1, -1)


## The follower of `edits` on `lpc`'s table. Add it to the tree to start it.
static func create(edits: LiveEdits, lpc: LevelPlayController) -> LiveEditGround:
	var follower := LiveEditGround.new()
	follower.name = "LiveEditGround"
	follower._edits = edits
	follower._lpc = lpc
	return follower


func _ready() -> void:
	_glb_key = _glb_versions()


func _process(_delta: float) -> void:
	if _wait >= 0 or not is_instance_valid(_edits) or _edits.op_log.size() == _followed:
		return
	if not _edits.is_settled() or _terrain_unsettled():
		return
	_wait = PHYSICS_FRAMES


func _physics_process(_delta: float) -> void:
	if _wait < 0:
		return
	_wait -= 1
	if _wait < 0:
		_follow()


## True while nothing is left for the follower to do (tests and the ENet scenario wait on it).
func is_idle() -> bool:
	return _wait < 0 and (not is_instance_valid(_edits) or _edits.op_log.size() == _followed)


func _follow() -> void:
	if not is_instance_valid(_edits) or not is_instance_valid(_lpc):
		return
	_followed = _edits.op_log.size()
	_lpc.refit_view_to_ground()
	_refit_glb_grid()
	if _edits.sends:
		regrounded.emit(reground_tokens(_lpc.get_game_map()))


## Sets every token on `game_map`'s board down on its ground (TokenGrounding); each one that
## moved goes to every peer when hosting, or into GameState in solo play. Returns how many
## moved.
static func reground_tokens(game_map: GameMap) -> int:
	if not is_instance_valid(game_map):
		return 0
	var cast_top := TokenGrounding.cast_top(game_map)
	var moved := 0
	for child in game_map.drag_and_drop_node.get_children():
		var token := child as BoardToken
		if token == null or not TokenGrounding.reground(token, cast_top):
			continue
		moved += 1
		if NetworkManager.is_host():
			NetworkStateSync.broadcast_token_properties(token)
		else:
			GameState.sync_from_board_token(token)
	return moved


func _terrain_unsettled() -> bool:
	var root := _lpc.loaded_map_instance if is_instance_valid(_lpc) else null
	if not is_instance_valid(root):
		return false
	var terrain := root.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	return terrain != null and terrain.has_unsettled_chunks()


## A Blender map's grid ground sampled again when its water or crossings changed.
func _refit_glb_grid() -> void:
	var root := _lpc.loaded_map_instance
	if not is_instance_valid(root) or root.get_node_or_null(^"AuthoredTerrain") != null:
		return
	var key := _glb_versions()
	if key == _glb_key:
		return
	_glb_key = key
	MapSourceLoader.new(get_tree()).fit_grid_ground_async(root, _lpc.get_game_map())


func _glb_versions() -> Vector2i:
	var root := _lpc.loaded_map_instance if is_instance_valid(_lpc) else null
	if not is_instance_valid(root):
		return Vector2i(-1, -1)
	var water := root.get_node_or_null(AuthoredWater.NODE_NAME) as AuthoredWater
	var crossings := root.get_node_or_null(AuthoredCrossings.NODE_NAME) as AuthoredCrossings
	return Vector2i(water.version if water else -1, crossings.version if crossings else -1)
