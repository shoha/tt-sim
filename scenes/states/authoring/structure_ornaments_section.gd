class_name StructureOrnamentsSection
extends VBoxContainer

## The "Decorate" row of the selected building's bar (StructureToolPane.add_selection_section): nine
## chips for the ornaments of StructureOrnaments (ivy, corner turret, buttresses, rose window,
## weathervane, hanging sign, flower boxes, awning, banners), "Surprise me" for a pleasing set
## drawn for the building's kind, "Clear", and, while ivy is on, one slider for how much. A click on
## a chip is one request (a history entry and a live preview); a chip the building cannot take is
## greyed with the reason in its tooltip, and one its own style already draws shows on and locked.
## Built in code; every interactive Control is named. No state of its own beyond what show_for
## was last given: the record is the truth.

## The set of ornaments the player wants has changed: the kinds now asked for (every one, in mask
## order) and the history label ("Add ivy to", "Surprise ornaments on").
signal ornaments_requested(kinds: Array, label: String)
## The ivy slider was let go (or keyed) at `amount`.
signal ivy_requested(amount: float)

const TITLE := "Decorate"
const SURPRISE_TIP := (
	"Draw a pleasing set of ornaments for this kind of building. Press again for another."
)
const CLEAR_TIP := "Take away the ornaments you added."
const NO_ROOM_TIP := "No room for it on this building, so nothing was added."
const NO_ROOM_ALPHA := 0.5
const IVY_TIP :="How far the ivy climbs and how thickly it grows."

## Chip buttons by kind.
var chips: Dictionary = {}
var surprise_button: Button
var clear_button: Button
var ivy_row: HBoxContainer
var ivy_slider: HSlider
var ivy_value: Label

var _flow: HFlowContainer
## The kinds the player has on (not the style's own), in mask order.
var _asked: Array[String] = []
var _theme_name := "home"
var _built_in: Array[String] = []
var _can_decorate := false
var _dragging := false
var _syncing := false
## Counts the presses of Surprise me, so each gives another set (the draw is seeded by it and the
## building's seed, not by the clock, so a test can ask for the same set).
var _draws := 0
var _seed := 0


func _init() -> void:
	name = "StructureOrnaments"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme_type_variation = &"BoxContainerSnug"
	var title := Label.new()
	title.name = "OrnamentsTitle"
	title.text = TITLE
	title.theme_type_variation = &"SectionHeader"
	add_child(title)
	_flow = HFlowContainer.new()
	_flow.name = "OrnamentChips"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The theme's own spacing for a wrapping row of chips.
	_flow.theme_type_variation = &"FactsFlow"
	add_child(_flow)
	for item: Dictionary in StructureOrnaments.CHIPS:
		var kind := String(item["kind"])
		var chip := Button.new()
		chip.name = "Ornament_" + kind
		chip.text = String(item["label"])
		chip.toggle_mode = true
		chip.theme_type_variation = &"Chip"
		chip.focus_mode = Control.FOCUS_NONE
		chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		chip.tooltip_text = String(item["tip"])
		chip.toggled.connect(_on_chip.bind(kind))
		_flow.add_child(chip)
		chips[kind] = chip
	var tail := HBoxContainer.new()
	tail.name = "OrnamentActions"
	tail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tail)
	surprise_button = _action("OrnamentSurprise", "Surprise me", SURPRISE_TIP, tail)
	surprise_button.pressed.connect(_on_surprise)
	clear_button = _action("OrnamentClear", "Clear", CLEAR_TIP, tail)
	clear_button.pressed.connect(_on_clear)
	ivy_row = HBoxContainer.new()
	ivy_row.name = "OrnamentIvyRow"
	ivy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ivy_row.tooltip_text = IVY_TIP
	ivy_row.visible = false
	add_child(ivy_row)
	var caption := Label.new()
	caption.text = "Amount of ivy"
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ivy_row.add_child(caption)
	ivy_slider = HSlider.new()
	ivy_slider.name = "OrnamentIvyAmount"
	ivy_slider.min_value = StructureOrnaments.IVY_MIN
	ivy_slider.max_value = StructureOrnaments.IVY_MAX
	ivy_slider.step = StructureOrnaments.IVY_STEP
	ivy_slider.value = StructureOrnaments.IVY_DEFAULT
	ivy_slider.custom_minimum_size = Vector2(110, 0)
	ivy_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ivy_slider.focus_mode = Control.FOCUS_NONE
	ivy_slider.tooltip_text = IVY_TIP
	ivy_slider.drag_started.connect(func() -> void: _dragging = true)
	ivy_slider.drag_ended.connect(_on_drag_ended)
	ivy_slider.value_changed.connect(_on_ivy_value)
	ivy_row.add_child(ivy_slider)
	ivy_value = Label.new()
	ivy_value.name = "OrnamentIvyValue"
	ivy_value.custom_minimum_size = Vector2(40, 0)
	ivy_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ivy_row.add_child(ivy_value)


## Shows the chips for `structure` (a record of the open document): which are on, which are greyed
## and why, the ivy amount. No signal fires.
func show_for(structure: Structure) -> void:
	StructureRecipes.ensure_served()
	var recipe := StructureRecipes.document(structure.recipe)
	var states := StructureOrnaments.chip_states(recipe, structure.params)
	_asked = StructureOrnaments.kinds_of(structure.params)
	_built_in = StructureOrnaments.built_in(recipe)
	_theme_name = StructureOrnaments.theme_of(LibraryStructureStore.structure(structure.recipe))
	_seed = structure.seed_value
	_can_decorate = false
	var tips := {}
	for item: Dictionary in StructureOrnaments.CHIPS:
		tips[String(item["kind"])] = String(item["tip"])
	for kind: String in chips:
		var chip: Button = chips[kind]
		var state: Dictionary = states[kind]
		chip.set_pressed_no_signal(bool(state["on"]))
		chip.disabled = not bool(state["enabled"])
		chip.tooltip_text = (
			String(tips[kind])
			if bool(state["enabled"])
			else "%s %s" % [tips[kind], state["reason"]]
		)
		_can_decorate = _can_decorate or bool(state["enabled"])
		chip.modulate = Color.WHITE
		chip.set_meta(&"base_tip", chip.tooltip_text)
	surprise_button.disabled = not _can_decorate
	clear_button.disabled = _asked.is_empty()
	var ivy_on := _asked.has("ivy")
	ivy_row.visible = ivy_on
	_syncing = true
	ivy_slider.value = StructureOrnaments.ivy_amount(structure.params)
	_syncing = false
	_update_ivy_text()


## Marks the chips of `kinds` (requested, but the build found no room for them: the host reads
## ProcgenOrnaments.placed_kinds off the built structure) in a muted "no room" state with a tooltip
## that says so; the chip stays pressed and clickable (a click takes it off). Every other chip is
## shown as show_for left it. Call it with [] to clear.
func show_missing(kinds: Array) -> void:
	for kind: String in chips:
		var chip: Button = chips[kind]
		var base := String(chip.get_meta(&"base_tip", chip.tooltip_text))
		if kinds.has(kind) and chip.button_pressed:
			chip.modulate = Color.WHITE
			chip.modulate.a = NO_ROOM_ALPHA
			chip.tooltip_text = "%s %s" % [base, NO_ROOM_TIP]
		else:
			chip.modulate = Color.WHITE
			chip.tooltip_text = base


## The kinds a Surprise me press would draw next for the building last shown (the building's own
## kinds left out), without pressing it.
func next_surprise() -> Array[String]:
	return StructureOrnaments.surprise(_theme_name, _seed * 31 + _draws, _built_in)


func _action(node_name: String, text: String, tip: String, row: HBoxContainer) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(button)
	return button


func _on_chip(pressed: bool, kind: String) -> void:
	var next := _asked.duplicate()
	if pressed and not next.has(kind):
		next.append(kind)
	elif not pressed:
		next.erase(kind)
	var title := _label_of(kind)
	ornaments_requested.emit(next, ("Add %s to" if pressed else "Take %s off") % title)


func _on_surprise() -> void:
	var kinds := next_surprise()
	_draws += 1
	# A draw that equals what is on would change nothing: take the next one (a few tries).
	for _try in 4:
		if kinds != _asked:
			break
		kinds = next_surprise()
		_draws += 1
	ornaments_requested.emit(kinds, "Surprise ornaments on")


func _on_clear() -> void:
	ornaments_requested.emit([] as Array[String], "Clear ornaments of")


func _on_ivy_value(_amount: float) -> void:
	_update_ivy_text()
	# A drag commits when it is let go; a key press or a click on the bar commits at once.
	if not _syncing and not _dragging:
		ivy_requested.emit(ivy_slider.value)


func _on_drag_ended(_changed: bool) -> void:
	_dragging = false
	ivy_requested.emit(ivy_slider.value)


func _update_ivy_text() -> void:
	ivy_value.text = "%d %%" % roundi(ivy_slider.value * 100.0)


func _label_of(kind: String) -> String:
	for item: Dictionary in StructureOrnaments.CHIPS:
		if String(item["kind"]) == kind:
			return String(item["label"]).to_lower()
	return kind
