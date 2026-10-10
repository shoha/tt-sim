class_name TokenSaveState
extends RefCounted

## Whether the tokens on a table differ from what was last saved to its map, so leaving can
## say "Token moves you have not saved to the map will be lost." only when that is true
## (docs/UI_TASTE.md W2).
##
## A snapshot is a Dictionary of placement_id -> entry, an entry the fields a placement
## persists (TokenPlacement.sync_from_board_token is the one place that knows them). The
## saved side is taken from the level's placements when it loads and right after a save;
## the live side from the spawned tokens, read through the same TokenPlacement sync, when
## asked. A token added or removed, renamed, hurt, hidden or moved past a small tolerance
## counts; the few centimetres a token settles by after it is set out do not.

## How far a token may sit from its saved place across the ground, in metres, and up or
## down (it settles onto the ground after it is set out), before it counts as moved.
const MOVE_TOLERANCE_M := 0.1
const HEIGHT_TOLERANCE_M := 0.3
## A turn or a scale change smaller than this is not a change.
const TURN_TOLERANCE_RAD := 0.05
const SCALE_TOLERANCE := 0.01


## The snapshot of `placements` (TokenPlacement), as saved.
static func of_placements(placements: Array) -> Dictionary:
	var snapshot := {}
	for placement in placements:
		var saved := placement as TokenPlacement
		if saved != null:
			snapshot[saved.placement_id] = entry(saved)
	return snapshot


## The snapshot of live `tokens` (placement_id -> BoardToken, TokenSpawner's spawned
## tokens), read through TokenPlacement.sync_from_board_token.
static func of_tokens(tokens: Dictionary) -> Dictionary:
	var snapshot := {}
	for placement_id in tokens:
		var token := tokens[placement_id] as BoardToken
		if not is_instance_valid(token):
			continue
		var live := TokenPlacement.new()
		live.sync_from_board_token(token)
		snapshot[placement_id] = entry(live)
	return snapshot


## The fields of `placement` a save keeps.
static func entry(placement: TokenPlacement) -> Dictionary:
	return {
		"position": placement.position,
		"rotation_y": placement.rotation_y,
		"scale": placement.scale,
		"name": placement.token_name,
		"player_controlled": placement.is_player_controlled,
		"max_health": placement.max_health,
		"current_health": placement.current_health,
		"visible": placement.is_visible_to_players,
		"status": placement.status_effects.duplicate(),
		"alive": placement.is_alive,
		"recipe": placement.avatar_recipe.duplicate(true),
	}


## Whether `live` differs from `saved`: a token added or removed, or one whose entry
## changed beyond the tolerances.
static func differs(saved: Dictionary, live: Dictionary) -> bool:
	if saved.size() != live.size():
		return true
	for placement_id in live:
		if not saved.has(placement_id):
			return true
		if entry_differs(saved[placement_id], live[placement_id]):
			return true
	return false


## Whether one token's live entry differs from its saved one.
static func entry_differs(saved: Dictionary, live: Dictionary) -> bool:
	var a: Vector3 = saved["position"]
	var b: Vector3 = live["position"]
	if Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z)) > MOVE_TOLERANCE_M:
		return true
	if absf(a.y - b.y) > HEIGHT_TOLERANCE_M:
		return true
	var turn := absf(angle_difference(float(saved["rotation_y"]), float(live["rotation_y"])))
	if turn > TURN_TOLERANCE_RAD:
		return true
	var scale_a: Vector3 = saved["scale"]
	var scale_b: Vector3 = live["scale"]
	if _max_abs(scale_a - scale_b) > SCALE_TOLERANCE:
		return true
	for key in ["name", "player_controlled", "max_health", "current_health", "visible", "alive"]:
		if saved[key] != live[key]:
			return true
	return saved["status"] != live["status"] or saved["recipe"] != live["recipe"]


static func _max_abs(v: Vector3) -> float:
	return maxf(absf(v.x), maxf(absf(v.y), absf(v.z)))
