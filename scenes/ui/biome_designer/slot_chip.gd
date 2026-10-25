class_name DesignerSlotChip
extends Button

## One rule in the slot list: a toggle button named after the rule, with the number of assets it
## selects, a mark when the validators have a complaint about it, and a lock mark. It takes an
## asset dropped on it (the asset is added to the rule's query, with Shift pinned) and can itself
## be dragged to another slot, which changes the rule's role.

signal asset_dropped(rule_key: String, ref: String, pin: bool)
signal menu_requested(rule_key: String, at: Vector2)

const DRAG_TYPE := "designer_rule"

var rule_key: String = ""


func _init() -> void:
	toggle_mode = true
	theme_type_variation = &"Chip"
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	alignment = HORIZONTAL_ALIGNMENT_LEFT


func setup(key: String) -> void:
	rule_key = key
	name = "Chip_" + key.validate_node_name()


## Sets the chip's words: "oak (3)", with " !" for a complaint and a lock icon when locked.
func show_state(assets: int, problem: String, locked: bool) -> void:
	text = "%s (%d)%s" % [rule_key, assets, " !" if problem != "" else ""]
	icon = IconButton.load_icon("device-floppy") if locked else null
	var lines: Array[String] = [rule_key]
	lines.append("%d assets" % assets)
	if locked:
		lines.append("Selection locked: Save writes it to the lock file.")
	if problem != "":
		lines.append(problem)
	lines.append("Drop an asset here to add it (Shift pins it). Right-click for more.")
	tooltip_text = "\n".join(PackedStringArray(lines))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			menu_requested.emit(rule_key, get_global_mouse_position())
			accept_event()


func _get_drag_data(_at_position: Vector2) -> Variant:
	var preview := Label.new()
	preview.text = rule_key
	preview.theme_type_variation = &"Chip"
	if get_viewport() != null and get_viewport().gui_is_dragging():
		set_drag_preview(preview)
	else:
		preview.free()
	return {"type": DRAG_TYPE, "key": rule_key}


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).get("type") == DesignerAssetTile.DRAG_TYPE


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	asset_dropped.emit(
		rule_key, String((data as Dictionary)["ref"]), Input.is_key_pressed(KEY_SHIFT)
	)
