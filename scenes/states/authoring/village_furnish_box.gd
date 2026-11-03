class_name VillageFurnishBox
extends VBoxContainer

## The furnishing part of the Village tool's pane (VillageToolPane embeds one in its plaza box): for
## the picked piece its name and three buttons (Swap, Back to its spot, Remove), and, once the
## picked village has had pieces taken away, one button that brings them all back. It stands in
## the place of the size row, which is only for a picked plaza or field, so the pane is no taller
## with a piece picked. Shows what show_state was last given (VillageProps.pane_state); no state
## of its own. Docs: docs/systems/villages.md section 14.

signal swap_requested
signal unpin_requested
signal remove_requested
signal restore_requested

const SWAP_TIP := "Swap this piece for another that belongs in this kind of place"
const SWAP_NONE_TIP := "Nothing else belongs in this kind of place"
const UNPIN_TIP := "Send this piece back to the spot the village's own rules give it"
const UNPIN_TEXT := "Back to its spot"
const REMOVE_TIP := "Take this piece away (Delete); the button below brings it back"
const RESTORE_TIP := "Bring back every piece taken away from this village"
const RESTORE_ONE := "Put back 1 removed piece"
const RESTORE_MANY := "Put back %d removed pieces"

var title: Label
var row: HBoxContainer
var swap_button: Button
var unpin_button: Button
var remove_button: Button
var restore_button: Button


func _init() -> void:
	name = "VillageFurnish"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSnug"
	title = Label.new()
	title.name = "FurnishTitle"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(1, 0)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(title)
	row = HBoxContainer.new()
	row.name = "FurnishRow"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swap_button = _button("FurnishSwap", "Swap", SWAP_TIP, swap_requested)
	unpin_button = _button("FurnishPutBack", UNPIN_TEXT, UNPIN_TIP, unpin_requested)
	remove_button = _button("FurnishRemove", "Remove", REMOVE_TIP, remove_requested)
	row.add_child(swap_button)
	row.add_child(unpin_button)
	row.add_child(remove_button)
	add_child(row)
	restore_button = _button("FurnishRestore", "", RESTORE_TIP, restore_requested)
	restore_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(restore_button)
	show_state({})


## Shows `state` (VillageProps.pane_state): hidden when no piece is picked and none was taken away.
func show_state(state: Dictionary) -> void:
	var picked := bool(state.get("picked", false))
	var removed := int(state.get("removed", 0))
	var label := str(state.get("label", ""))
	title.visible = picked
	row.visible = picked
	title.text = label
	var field := bool(state.get("field", false))
	swap_button.visible = not field
	swap_button.disabled = not bool(state.get("swappable", false))
	swap_button.tooltip_text = SWAP_TIP if not swap_button.disabled else SWAP_NONE_TIP
	unpin_button.visible = bool(state.get("pinned", false))
	restore_button.visible = removed > 0
	restore_button.text = RESTORE_ONE if removed == 1 else RESTORE_MANY % removed
	visible = picked or removed > 0


func _button(node_name: String, text: String, tip: String, pressed_signal: Signal) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(pressed_signal.emit)
	return button
