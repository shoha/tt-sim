extends Node
class_name GameplayActionHistory

## Undo stack for gameplay actions (damage, visibility, removal).
## Host/GM only. Records actions before they happen and replays reversals
## through the standard GameState API on undo.

const MAX_HISTORY := 30

enum ActionType { PROPERTY_CHANGE, TOKEN_REMOVAL }

var _stack: Array[Dictionary] = []


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
		GameState.end_batch_update()
	else:
		GameState.update_token_property(action.network_id, action.property, action.old_value)


func _undo_token_removal(action: Dictionary) -> void:
	removal_undo_requested.emit(action)


signal removal_undo_requested(action: Dictionary)


func _describe_property_change(property: String, old_value: Variant, new_value: Variant) -> String:
	match property:
		"current_health":
			var diff: int = int(new_value) - int(old_value)
			if diff > 0:
				return "healed %d HP" % diff
			else:
				return "dealt %d damage" % abs(diff)
		"max_health":
			return "max HP %d -> %d" % [old_value, new_value]
		"is_visible_to_players":
			return "toggled visibility"
		"is_alive":
			return "toggled alive state"
		_:
			return "%s changed" % property
