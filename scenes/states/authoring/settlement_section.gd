class_name SettlementSection
extends VBoxContainer

## The "Dress this street" section of a picked street's bar (WallToolPane.selection_box): four
## chips for the character (Farming hamlet, Market town, Harbour town, Hill fort village), one
## slider for how rich the street is and one for how busy, "Dress this street" (it reads "Re-dress"
## once dressed, and draws a new arrangement) and "Clear". Every press is one request; the editor
## makes it one history entry (SettlementEditor). No state beyond what show_for was last given:
## the record is the truth. Built in code; every interactive Control is named.

## Dress the street (or dress it again) with character `kit`, `wealth` 0..1 and `density` 0..1.5.
signal dress_requested(kit: String, wealth: float, density: float)
## The dressed street takes another character.
signal kit_requested(kit: String)
## The wealth or density slider was let go (or keyed) at these values.
signal feel_requested(wealth: float, density: float)
signal clear_requested

const TITLE := "Dress this street"
const HINT := (
	"Furnish the street with barrels, wells, stalls and lamps that fit a kind of place. Undo takes"
	+ " it all away in one step."
)
const CHIPS: Array[Dictionary] = [
	{
		"kit": "farming_hamlet",
		"label": "Farming hamlet",
		"tip": "Hay, woodpiles, carts, troughs and field gates along a quiet lane",
	},
	{
		"kit": "market_town",
		"label": "Market town",
		"tip": "Stalls, benches, lamps, washing lines and wells: a busy trading street",
	},
	{
		"kit": "harbour_town",
		"label": "Harbour town",
		"tip": "Crates, barrels, carts and lamps for a street by the water",
	},
	{
		"kit": "hill_fort_village",
		"label": "Hill fort village",
		"tip": "Woodpiles, shrines, troughs and gates for a hard, quiet hill village",
	},
]
const DRESS_TIP := "Furnish this street with the chosen character"
const REDRESS_TIP := "Furnish this street again: the same character, a new arrangement"
const CLEAR_TIP := "Take the furnishings away"
const WEALTH_TIP := "How well off the street is: bare to the left, lamps and awnings to the right"
const DENSITY_TIP := "How much stands in the street: a few things to the left, crowded to the right"

## Chip buttons by kit.
var chips: Dictionary = {}
var dress_button: Button
var clear_button: Button
var wealth_slider: HSlider
var density_slider: HSlider

var _kit: String = Settlement.KIND_NAMES[0]
var _dressed := false
var _syncing := false
var _dragging := false


func _init() -> void:
	name = "SettlementSection"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSnug"
	var title := Label.new()
	title.name = "SettlementTitle"
	title.text = TITLE
	title.theme_type_variation = &"SectionHeader"
	add_child(title)
	var hint := Label.new()
	hint.name = "SettlementHint"
	hint.text = HINT
	hint.theme_type_variation = &"Caption"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(1, 0)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(hint)
	var flow := HFlowContainer.new()
	flow.name = "SettlementChips"
	flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flow.theme_type_variation = &"FactsFlow"
	add_child(flow)
	var group := ButtonGroup.new()
	for item in CHIPS:
		var chip := Button.new()
		chip.name = "Settlement_" + String(item["kit"])
		chip.text = String(item["label"])
		chip.toggle_mode = true
		chip.button_group = group
		chip.theme_type_variation = &"ToggleChip"
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.tooltip_text = String(item["tip"])
		chip.toggled.connect(_on_chip.bind(String(item["kit"])))
		flow.add_child(chip)
		chips[String(item["kit"])] = chip
	(chips[_kit] as Button).set_pressed_no_signal(true)
	wealth_slider = _slider(
		"SettlementWealth", "Shabby to wealthy", WEALTH_TIP, 1.0, Settlement.DEFAULT_WEALTH
	)
	density_slider = _slider(
		"SettlementDensity",
		"Sparse to busy",
		DENSITY_TIP,
		Settlement.MAX_DENSITY,
		Settlement.DEFAULT_DENSITY
	)
	var actions := HBoxContainer.new()
	actions.name = "SettlementActions"
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(actions)
	dress_button = _action("SettlementDress", "Dress this street", DRESS_TIP, actions)
	dress_button.pressed.connect(_on_dress)
	clear_button = _action("SettlementClear", "Clear", CLEAR_TIP, actions)
	clear_button.pressed.connect(func() -> void: clear_requested.emit())
	clear_button.disabled = true


## Shows the street's state: `settlement` (a copy of the record dressing it) or null when it is
## undressed. No signal fires.
func show_for(settlement: Settlement) -> void:
	_syncing = true
	_dressed = settlement != null
	if settlement != null:
		_kit = settlement.kit
		wealth_slider.value = settlement.wealth
		density_slider.value = settlement.density
	(chips[_kit] as Button).set_pressed_no_signal(true)
	dress_button.text = "Re-dress" if _dressed else "Dress this street"
	dress_button.tooltip_text = REDRESS_TIP if _dressed else DRESS_TIP
	clear_button.disabled = not _dressed
	_syncing = false


## The character the chips show.
func kit() -> String:
	return _kit


func _slider(
	slider_name: String, caption_text: String, tip: String, high: float, start: float
) -> HSlider:
	var row := HBoxContainer.new()
	row.name = slider_name + "Row"
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.tooltip_text = tip
	add_child(row)
	var caption := Label.new()
	caption.text = caption_text
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(caption)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = 0.0
	slider.max_value = high
	slider.step = Settlement.WEALTH_STEP
	slider.value = start
	slider.custom_minimum_size = Vector2(110, 0)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = tip
	slider.drag_started.connect(func() -> void: _dragging = true)
	slider.drag_ended.connect(_on_drag_ended)
	slider.value_changed.connect(_on_value)
	row.add_child(slider)
	return slider


func _action(node_name: String, text: String, tip: String, parent: Control) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	parent.add_child(button)
	return button


func _on_chip(on: bool, kit_name: String) -> void:
	if not on or _syncing:
		return
	_kit = kit_name
	if _dressed:
		kit_requested.emit(kit_name)


func _on_dress() -> void:
	dress_requested.emit(_kit, wealth_slider.value, density_slider.value)


func _on_value(_value: float) -> void:
	# A key press changes the value without a drag; a drag commits when it is let go.
	if _syncing or _dragging or not _dressed:
		return
	feel_requested.emit(wealth_slider.value, density_slider.value)


func _on_drag_ended(changed: bool) -> void:
	_dragging = false
	if changed and _dressed and not _syncing:
		feel_requested.emit(wealth_slider.value, density_slider.value)
