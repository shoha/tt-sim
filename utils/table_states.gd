class_name TableStates
extends RefCounted

## Per-map session state: what a session did to each map it set out, kept so that returning
## to a map restores it (docs/plans/2026-10-09-v0.2-evaluation/design/flow_recommendation_v2.md,
## "The model"). A map is a template, a level folder nothing in a session changes unless the GM
## picks Save into map; this is the session's side of it, by shelf key (SessionChannel.ref_key()),
## in memory until a session file keeps it. Host only (TableMover owns one).
##
## An entry is what a table had become when it left: its token placements (TokenPlacement
## dicts, each synced from its live token as a save would), its look (a LevelVisualState) and
## its live edits' op log (LiveEdits.op_log). The party is never in it: SessionParty takes a
## player's avatar out of the placements when it adopts it, and the avatar travels with the
## session instead.
##
## Restoring overlays the placements and the look on the template's LevelData before it is
## set out (overlay()), so every peer gets them in the level broadcast and a late joiner in the
## level snapshot, and hands the op log to the table's live edits (LevelPlayController
## .replay_log), which apply it before the tokens land and serve it to every client as a late
## joiner's catch-up.

## shelf key -> {"placements": Array[Dictionary], "look": LevelVisualState, "op_log":
## Array[PackedByteArray]}
var _entries: Dictionary = {}


## Keep `entry` (capture()'s shape) as the state of map `key`.
func store(key: String, entry: Dictionary) -> void:
	if key != "":
		_entries[key] = entry


## The state kept for map `key`, or {} when the session has none (the template is as it is).
func entry_for(key: String) -> Dictionary:
	return _entries.get(key, {})


## True when the session keeps a state for map `key`.
func has(key: String) -> bool:
	return _entries.has(key)


## Forget map `key`'s state: it comes back as its template.
func erase(key: String) -> void:
	_entries.erase(key)


## The keys of the maps with a kept state.
func keys() -> Array:
	return _entries.keys()


## Forget every map's state (the session ended or a new one began).
func clear() -> void:
	_entries.clear()


## A table's state as it stands: `level`'s placements, each synced from its live token in
## `tokens` (placement id -> BoardToken, TokenSpawner's spawned tokens) without touching
## `level`, its look, and a copy of `op_log`. Pure apart from reading the tokens.
static func capture(
	level: LevelData, tokens: Dictionary, op_log: Array[PackedByteArray]
) -> Dictionary:
	var placements: Array[Dictionary] = []
	for placement in level.token_placements:
		var copy := TokenPlacement.from_dict(placement.to_dict())
		var token := tokens.get(placement.placement_id) as BoardToken
		if is_instance_valid(token):
			copy.sync_from_board_token(token)
		placements.append(copy.to_dict())
	return {
		"placements": placements,
		"look": LevelVisualState.from_level_data(level),
		"op_log": op_log.duplicate(),
	}


## Writes `entry`'s placements and look into `level` (a template just read from its folder),
## so the table is set out as the session left it. The op log is the caller's to hand on.
static func overlay(level: LevelData, entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var placements: Array[TokenPlacement] = []
	for data: Dictionary in entry.get("placements", []):
		placements.append(TokenPlacement.from_dict(data))
	level.token_placements = placements
	var look := entry.get("look") as LevelVisualState
	if look != null:
		look.apply_to_level_data(level)


## The op log of `entry`, or none.
static func op_log_of(entry: Dictionary) -> Array[PackedByteArray]:
	var ops: Array[PackedByteArray] = []
	ops.assign(entry.get("op_log", []))
	return ops


## What `level` looks like, for telling whether its look changed: every live-synced visual
## field (LevelVisualState.to_broadcast_dict()) and the grid scale. Pure.
static func look_of(level: LevelData) -> Dictionary:
	var state := LevelVisualState.from_level_data(level)
	var look := state.to_broadcast_dict()
	look["grid_cell_size"] = state.grid_cell_size
	look["display_unit"] = state.display_unit
	look["display_unit_per_cell"] = state.display_unit_per_cell
	return look
