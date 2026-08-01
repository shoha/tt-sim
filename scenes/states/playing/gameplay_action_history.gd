class_name GameplayActionHistory
extends Node

## Undo stack for gameplay actions (damage, visibility, removal).
## Host/GM only. Records actions before they happen and replays reversals
## through the standard GameState API on undo, and (when a token lookup is
## registered) through the live token's real mutators as well — see
## set_token_lookup().

signal removal_undo_requested(action: Dictionary)

enum ActionType { PROPERTY_CHANGE, TOKEN_REMOVAL }

const MAX_HISTORY := 30

var _stack: Array[Dictionary] = []

## Optional lookup used to find the live token for a network_id so undo/redo
## can replay through the token's real mutators (heal(), take_damage(), etc.)
## instead of only writing to GameState. Set via set_token_lookup() by
## whoever owns the live tokens (LevelPlayController). Left unset in
## isolated unit tests, in which case undo falls back to GameState-only.
var _token_lookup: Callable = Callable()


## Provide a lookup Callable(network_id: String) -> BoardToken (or any object
## that responds to the relevant mutators) used to find live tokens for
## undo/redo replay.
func set_token_lookup(lookup: Callable) -> void:
	_token_lookup = lookup


## Record a single property change. Call BEFORE applying the mutation.
func record_property_change(
	network_id: String, property: String, old_value: Variant, new_value: Variant
) -> void:
	_push(
		{
			"type": ActionType.PROPERTY_CHANGE,
			"network_id": network_id,
			"property": property,
			"old_value": old_value,
			"new_value": new_value,
			"description": _describe_property_change(property, old_value, new_value),
		}
	)


## Record multiple property changes as one compound action (undone together).
func record_compound_property_change(changes: Array[Dictionary]) -> void:
	var desc: String = (
		changes[0].get("description", "property change")
		if changes.size() > 0
		else "compound change"
	)
	_push(
		{
			"type": ActionType.PROPERTY_CHANGE,
			"compound": true,
			"changes": changes,
			"description": desc,
		}
	)


## Record a token removal. Call BEFORE freeing the token.
## Captures the full TokenState plus asset IDs for re-creation.
func record_token_removal(token: BoardToken, token_state: TokenState) -> void:
	_push(
		{
			"type": ActionType.TOKEN_REMOVAL,
			"network_id": token_state.network_id,
			"token_state_dict": token_state.to_dict(),
			"pack_id": token.pack_id,
			"asset_id": token.asset_id,
			"variant_id": token.variant_id,
			"description": 'removed "%s"' % token_state.token_name,
		}
	)


## Undo the most recent action. Returns a description string, or "" if empty.
func undo() -> String:
	if _stack.is_empty():
		return ""
	var action: Dictionary = _stack.pop_back()
	match action.type:
		ActionType.PROPERTY_CHANGE:
			_undo_property_change(action)
		ActionType.TOKEN_REMOVAL:
			_undo_token_removal(action)
	return action.get("description", "action")


## Whether there are actions to undo.
func can_undo() -> bool:
	return not _stack.is_empty()


## Clear the entire stack (call on level change).
func clear() -> void:
	_stack.clear()


## Get the number of actions in the stack.
func get_count() -> int:
	return _stack.size()


func _push(action: Dictionary) -> void:
	_stack.append(action)
	if _stack.size() > MAX_HISTORY:
		_stack.pop_front()


func _undo_property_change(action: Dictionary) -> void:
	if action.get("compound", false):
		var changes: Array = action.changes
		GameState.begin_batch_update()
		for i in range(changes.size() - 1, -1, -1):
			var change: Dictionary = changes[i]
			GameState.update_token_property(change.network_id, change.property, change.old_value)
			_apply_property_to_live_token(change.network_id, change.property, change.old_value)
		GameState.end_batch_update()
	else:
		GameState.update_token_property(action.network_id, action.property, action.old_value)
		_apply_property_to_live_token(action.network_id, action.property, action.old_value)


## Replay a property reversal through the live token's real mutators (in
## addition to the GameState write above), so undo flows through the same
## signal chain as a forward action (local visual update, GameState sync via
## LevelPlayController._on_token_property_changed, and network broadcast).
## No-ops quietly if no lookup is registered, the token can't be found, or
## the property has no known live-token mutator.
func _apply_property_to_live_token(network_id: String, property: String, value: Variant) -> void:
	if not _token_lookup.is_valid():
		return
	var token = _token_lookup.call(network_id)
	if not is_instance_valid(token):
		return

	match property:
		"current_health":
			var diff: int = int(value) - int(token.current_health)
			if diff > 0:
				token.heal(diff)
			elif diff < 0:
				token.take_damage(diff)
		"max_health":
			token.set_max_health(int(value))
		"is_visible_to_players":
			token.set_visible_to_players(bool(value))
		"rotation":
			var rigid_body: RigidBody3D = token.get_rigid_body()
			var position: Vector3 = rigid_body.global_position if rigid_body else Vector3.ZERO
			var scale: Vector3 = rigid_body.scale if rigid_body else Vector3.ONE
			token.set_transform_immediate(position, value, scale)
		"scale":
			var rigid_body2: RigidBody3D = token.get_rigid_body()
			var position2: Vector3 = rigid_body2.global_position if rigid_body2 else Vector3.ZERO
			var rotation2: Vector3 = rigid_body2.global_rotation if rigid_body2 else Vector3.ZERO
			token.set_transform_immediate(position2, rotation2, value)
		_:
			pass  # No live-token mutator for this property; GameState write above still applies


func _undo_token_removal(action: Dictionary) -> void:
	removal_undo_requested.emit(action)


func _describe_property_change(property: String, old_value: Variant, new_value: Variant) -> String:
	match property:
		"current_health":
			var diff: int = int(new_value) - int(old_value)
			if diff > 0:
				return "healed %d HP" % diff
			return "dealt %d damage" % abs(diff)
		"max_health":
			return "max HP %d -> %d" % [old_value, new_value]
		"is_visible_to_players":
			return "toggled visibility"
		"is_alive":
			return "toggled alive state"
		_:
			return "%s changed" % property
