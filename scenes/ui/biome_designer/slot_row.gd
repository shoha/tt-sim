class_name DesignerSlotRow
extends VBoxContainer

## One slot of the slot list: a header and the flow of its rule chips. It is the drop target of
## the slot: an asset dropped on it starts a rule of the slot's role from the asset, a rule chip
## dropped on it moves the rule into the slot.

signal asset_dropped(group_id: String, ref: String)
signal rule_dropped(group_id: String, key: String)

var group_id: String = ""


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var kind: Variant = (data as Dictionary).get("type")
	return kind == DesignerAssetTile.DRAG_TYPE or kind == DesignerSlotChip.DRAG_TYPE


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var held := data as Dictionary
	if held["type"] == DesignerAssetTile.DRAG_TYPE:
		asset_dropped.emit(group_id, String(held["ref"]))
	else:
		rule_dropped.emit(group_id, String(held["key"]))
