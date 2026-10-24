class_name TokenVisibilityDriver
extends Node

## Per-frame half of the token visibility prototypes (TokenVisibility, topic tokenvis): keeps
## the ghost overlay on every token (new tokens, rebuilt figures) and moves the canopy window
## onto the selected or hovered token. A child of the GameMap, made on first use.

const NAME := "TokenVisibilityDriver"
## Seconds between sweeps that dress new tokens with the ghost overlay.
const GHOST_SWEEP_S := 0.25
## Height above a token's base the anchored window aims at (the figure's chest).
const ANCHOR_HEIGHT_M := 0.9
## How far toward the camera the crown test looks, metres.
const CROWN_RAY_M := 60.0

var ghost := false
var anchor := false
## True dresses only the tokens a tree crown stands in front of (a CPU ray from the token
## toward the camera against the map's AvatarShadeCache), so the ghost's extra draw calls
## are spent where foliage hides a token. False dresses every token, which also covers
## rocks, walls and trunks that the crown test does not know.
var gate := false
## Uniform values (name -> value) the ghost material takes, from probes and tuning.
var ghost_params: Dictionary = {}

var _game_map: GameMap
var _sweep_s := 0.0


func _init() -> void:
	name = NAME


func setup(game_map: GameMap) -> void:
	_game_map = game_map


func _process(delta: float) -> void:
	if _game_map == null:
		return
	if anchor:
		_update_anchor()
	if ghost:
		_sweep_s += delta
		if _sweep_s >= GHOST_SWEEP_S:
			_sweep_s = 0.0
			dress_all(true)


## Dresses (or strips) the ghost overlay on every token now.
func dress_all(on: bool) -> void:
	for token in tokens():
		TokenVisibility.dress_token(token, on and (not gate or _under_crown(token)), ghost_params)


## Whether a tree crown stands between the token's chest and the camera.
func _under_crown(token: BoardToken) -> bool:
	if token.rigid_body == null:
		return false
	var map := _game_map.map_container
	var from := token.rigid_body.global_position + Vector3.UP * ANCHOR_HEIGHT_M
	var to := from + _game_map.camera_node.global_basis.z.normalized() * CROWN_RAY_M
	return not AvatarShadeCache.for_map(map).canopy_hit(from, to).is_empty()


func tokens() -> Array[BoardToken]:
	var out: Array[BoardToken] = []
	for node in _game_map.drag_and_drop_node.get_children():
		if node is BoardToken and not node.is_queued_for_deletion():
			out.append(node as BoardToken)
	return out


## Points the canopy window at the last highlighted (selected or hovered) token.
func _update_anchor() -> void:
	var picked: BoardToken = null
	for token in tokens():
		if token.is_highlighted and token.rigid_body != null:
			picked = token
	CanopyFade.anchor_has_point = picked != null
	if picked != null:
		CanopyFade.anchor_point = picked.rigid_body.global_position + Vector3.UP * ANCHOR_HEIGHT_M
