class_name StructureToolPane
extends VBoxContainer

## The Structure tool's pane in AuthoringPanel and the GM's Events pane: the structures the served
## libraries offer, one tile each (the library's rendered picture and the structure's name),
## grouped by family under the family's name, and a "Mix afresh" button that draws the next lot's
## look again (R). The picked tile is the brush's structure. No numbers: a lot is dragged to its
## size. Built in code; every interactive Control is named. docs/systems/structures.md "The tool".

## A tile was picked: the structure's reference (`<library>:<id>`).
signal structure_selected(ref: String)
## "Mix afresh" was pressed.
signal reroll_requested
## The selected building's bar (card S5): a variant tile (the reference), a stepper pressed (the
## parameter and -1 or 1), the door, redraw, copy, remove and done buttons.
signal variant_picked(ref: String)
signal param_stepped(param: String, direction: int)
signal door_requested
signal redraw_requested
signal copy_requested
signal remove_requested
signal done_requested
## The Decorate row (StructureOrnamentsSection): the ornaments now asked for and the history label,
## and the ivy amount let go at.
signal ornaments_requested(kinds: Array, label: String)
signal ivy_requested(amount: float)

## The panel's subtitle (the title is the tool's label, "Buildings"): the whole catalogue, not only
## houses.
const SUMMARY := "Cottages, castles, windmills and more: click to place, drag to size."
const VARIANT_THUMB_PX := 56
## Tall enough for a Style name on two lines (long names wrap rather than end in dots).
const VARIANT_TILE_SIZE := Vector2(96, 94)
const PLACE_THUMB_PX := 40
const PLACE_CAPTION := "Next one down"
const PLACE_BROWSE := "Change"
const PLACE_BACK := "Back"
const PLACE_BROWSE_TIP := "Choose another building to put down next, from the whole list"
const PLACE_BACK_TIP := "Back to the selected building"
## The keys are the hint bar's key caps (StructureHints); the pane keeps one line of what to reach.
const SELECTION_HINT := (
	"Corner dots resize, tabs push a side (click one for the door), the body moves it."
)
## The recipe parameters the bar steps, in order, with their captions and how a value reads
## (value 0 of floors is the recipe's own, "Auto").
const STEPPED := [
	{"param": "floors", "caption": "Floors", "auto_zero": true},
	{"param": "roof_pitch", "caption": "Roof pitch", "auto_zero": false},
	{"param": "chimneys", "caption": "Chimneys", "auto_zero": false},
	{"param": "ridge", "caption": "Ridge", "auto_zero": true},
	{"param": "jetty", "caption": "Jetty", "auto_zero": false},
	{"param": "ruin", "caption": "Ruin", "auto_zero": false},
]
## The pane's width before it has been laid out (the drawer's), for the first column count.
const FALLBACK_WIDTH_PX := 196.0
## One line: the gestures are key caps on the hint bar (StructureHints), not prose.
const HINT := "Pick a building, then click the ground, or drag out a corner to size it."
const EMPTY := "No library this map uses offers a building."
const SEARCH_PLACEHOLDER := "Find a building"
const NO_MATCH := "No building matches that. Try a family such as cottage, inn or ruin."
const NO_MATCH_CHIPS := "No building has all of those. Switch one off, or clear them."
const CLEAR_CHIPS_TIP := "Switch every filter off and clear the search"
const SMALL_TILES_TIP := "Smaller pictures, so more of the list shows at once"
## How long the hover card waits before it shows (seconds), so a sweep across tiles stays calm.
const CARD_DELAY_S := 0.12
const CARD_PICTURE_PX := 128
const REROLL_TOOLTIP := "Draw the next building's look afresh (R); over a building, redraw that one"

## The family fields, in tile order.
var family_fields: Array[TileField] = []
var reroll_button: Button
## Filters the tiles by name, family and tags (StructurePalette.matches).
var search_edit: LineEdit
## The filter chips by id (StructurePalette.CHIPS), the toggle buttons of the row above the tiles.
var chip_buttons: Dictionary = {}
var clear_button: Button
var small_tiles_button: Button
## The hover card: the structure's picture, name, family and size, beside the tile pointed at.
var card: PanelContainer
var card_picture: TextureRect
var card_title: Label
var card_detail: Label
var card_size: Label

## The selected building's bar, shown in place of the palette while a building is selected.
var selection_box: VBoxContainer
var selection_title: Label
var variant_field: TileField
## Stepper rows by parameter name: {"row", "value" (Label), "minus", "plus" (Buttons)}.
var steppers: Dictionary = {}
var door_button: Button
var redraw_button: Button
var copy_button: Button
var remove_button: Button
var done_button: Button
## The Decorate row, between the steppers and the Style tiles.
var ornaments_section: StructureOrnamentsSection

## "Place another": the strip under the header while a building is selected, so the palette is
## never lost. It names the armed pick (the next building a click on bare ground lays) and
## opens the whole palette in place of the bar until a tile is chosen.
var place_strip: HBoxContainer
var place_thumb: TextureRect
var place_name: Label
var place_button: Button

var _browsing: bool = false
var _has_selection: bool = false
var _hint: Label
var _empty: Label
var _no_match: Label
## The building picked (kept while a search hides its tile), how many the libraries serve, and
## whether the search found none.
var _picked: String = ""
var _served: int = 0
var _found_none: bool = false
var _tools_row: HBoxContainer
var _chip_flow: VBoxContainer
var _filter_row: HBoxContainer
## The chips switched on (ids, in StructurePalette.CHIPS order), whether the tiles are the small
## size, the rows the libraries serve, and the hover card's pending show.
var _active_chips: Array[String] = []
var _small_tiles: bool = false
var _columns: int = 0
var _card_tween: Tween
var _card_for: String = ""
var _refs: Array[String] = []
var _variant_refs: Array[String] = []
var _selected_ref: String = ""


func _init() -> void:
	name = "StructurePane"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# SPACE_2, the step every tool pane keeps between its parts.
	theme_type_variation = &"BoxContainerSnug"
	var header := MenuHeader.new()
	header.name = "StructureHeader"
	header.setup(StructureTool.LABEL, SUMMARY)
	# The subtitle wraps to the pane's width: a long line must not widen the pane under the rail.
	header.caption_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.caption_label.custom_minimum_size = Vector2(1, 0)
	add_child(header)
	_build_place_strip()
	_build_selection()
	_hint = _caption("StructureHint", HINT)
	add_child(_hint)
	_empty = _caption("StructureEmpty", EMPTY)
	add_child(_empty)
	# Search and Mix afresh share one row above the tiles, so neither is lost below 60 of them.
	_tools_row = HBoxContainer.new()
	_tools_row.name = "StructureTools"
	_tools_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tools_row)
	search_edit = LineEdit.new()
	search_edit.name = "StructureSearch"
	search_edit.placeholder_text = SEARCH_PLACEHOLDER
	search_edit.tooltip_text = "Type part of a name, a family or a tag to narrow the tiles"
	search_edit.clear_button_enabled = true
	search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_edit.text_changed.connect(func(_text: String) -> void: refresh())
	_tools_row.add_child(search_edit)
	reroll_button = Button.new()
	reroll_button.name = "StructureReroll"
	reroll_button.text = "Mix afresh"
	reroll_button.tooltip_text = REROLL_TOOLTIP
	reroll_button.focus_mode = Control.FOCUS_NONE
	reroll_button.pressed.connect(reroll_requested.emit)
	_tools_row.add_child(reroll_button)
	_build_filters()
	_no_match = _caption("StructureNoMatch", NO_MATCH)
	_no_match.visible = false
	add_child(_no_match)
	_build_card()
	resized.connect(_fit_tiles)
	visibility_changed.connect(_hide_card)
	_small_tiles = UiPreferences.load_structure_tiles_small()
	small_tiles_button.set_pressed_no_signal(_small_tiles)
	refresh()


## True when the libraries serve `ref` (whether or not the search shows its tile).
func has_ref(ref: String) -> bool:
	return not LibraryStructureStore.structure(ref).is_empty()


## The references the pane lists, in tile order.
func refs() -> Array[String]:
	return _refs


## Fills the tiles from the served libraries again (after a library was imported or removed).
## The tile picked stays picked when its structure is still offered.
func refresh() -> void:
	var picked := picked_ref()
	for field in family_fields:
		remove_child(field)
		field.queue_free()
	family_fields.clear()
	_refs.clear()
	StructureRecipes.ensure_served()
	_hide_card()
	var rows := LibraryStructureStore.structures()
	var found := StructurePalette.sections(rows, search_edit.text, _active_chips)
	var metrics := _metrics()
	var shown := 0
	for section: Dictionary in found:
		var key := String(section["key"])
		var members: Array = section["rows"]
		var field := TileField.new()
		field.name = "StructureFamily_" + key.replace(":", "_")
		field.caption = StructurePalette.section_caption(String(section["family"]), members.size())
		field.tiles.photo_icons = true
		field.tiles.tile_min_size = metrics["tile"]
		field.tiles.columns = int(metrics["columns"])
		for row: Dictionary in members:
			var ref := String(row["ref"])
			# No tooltip: the hover card (below) says more, sooner.
			field.tiles.add_tile(
				StringName(ref), String(row["name"]), "", "", StructureThumbnail.of(row, int(metrics["thumb"]))
			)
			_refs.append(ref)
			shown += 1
		field.tiles.selection_changed.connect(_on_tile.bind(field))
		field.tiles.tile_hovered.connect(_on_tile_hovered.bind(field))
		field.tiles.tile_unhovered.connect(func(_id: StringName) -> void: _hide_card())
		add_child(field)
		family_fields.append(field)
	_served = rows.size()
	_found_none = found.is_empty()
	_update_filters(rows, shown)
	var served_refs := PackedStringArray()
	for row: Dictionary in rows:
		served_refs.append(String(row["ref"]))
	if picked != "" and picked in served_refs:
		select_ref(picked)
	elif not _refs.is_empty():
		select_ref(_refs[0])
	else:
		_picked = ""
	_show_palette(not selection_box.visible)


## Shows `ref` picked, without emitting structure_selected. A pick the search hides stays the
## pane's pick (the brush still lays it); its tile shows again when the search lets it through.
func select_ref(ref: String) -> void:
	_picked = ref
	for field in family_fields:
		if field.tiles.has_tile(StringName(ref)):
			field.tiles.select(StringName(ref))
		else:
			field.tiles.clear_selection()
	_update_place_strip()


## The reference of the building picked, or "".
func picked_ref() -> String:
	return _picked


## Shows the bar for `structure` (a record of the open document: its recipe and parameters), or,
## with null, the palette again. The palette steps aside while a building is selected, since a
## click then edits that building rather than laying a new one.
func show_selection(structure: Structure) -> void:
	_has_selection = structure != null
	# A click on the board (another building selected, or none) ends browsing the palette.
	_browsing = false
	selection_box.visible = _has_selection and not _browsing
	_show_palette(not selection_box.visible)
	_update_place_strip()
	if structure == null:
		_selected_ref = ""
		return
	StructureRecipes.ensure_served()
	_selected_ref = structure.recipe
	var row := LibraryStructureStore.structure(structure.recipe)
	selection_title.text = String(row.get("name", structure.recipe.get_slice(":", 1).capitalize()))
	_show_variants(structure.recipe)
	ornaments_section.show_for(structure)
	var recipe := StructureRecipes.document(structure.recipe)
	var interface: Array = recipe.interface if recipe != null else []
	var exposed: Array = row.get("expose", [])
	for item: Dictionary in STEPPED:
		var param := String(item["param"])
		var stepper: Dictionary = steppers[param]
		var spec := StructureEdit.param_spec(interface, param)
		var offered := not spec.is_empty() and param in exposed
		(stepper["row"] as Control).visible = offered
		if not offered:
			continue
		var value := StructureEdit.param_value(structure.params, interface, param)
		(stepper["value"] as Label).text = _value_text(item, value)
		(stepper["minus"] as Button).disabled = value <= float(spec.get("min", value)) + 0.001
		(stepper["plus"] as Button).disabled = value >= float(spec.get("max", value)) - 0.001


## How a stepped value reads: whole numbers plain, floors and the ridge 0 as "Auto", pitch in
## degrees, the ridge 1 as "Eave" (the eave to the front) and 2 as "Gable" (a gable to it), a ruin
## in percent and a jetty in metres.
static func _value_text(item: Dictionary, value: float) -> String:
	if bool(item["auto_zero"]) and value < 0.5:
		return "Auto"
	if String(item["param"]) == "ridge":
		return "Eave" if value < 1.5 else "Gable"
	if String(item["param"]) == "ruin":
		return "%d %%" % roundi(value * 100.0)
	if String(item["param"]) == "jetty":
		return "%.1f m" % value
	var text := str(roundi(value)) if is_equal_approx(value, roundf(value)) else "%.1f" % value
	return text + " deg" if String(item["param"]) == "roof_pitch" else text


## The tiles of the selected building's family (its variants), the building's own picked; none
## when it has no other recipe in its family.
func _show_variants(ref: String) -> void:
	var rows := StructureEdit.variants_of(ref)
	var refs: Array[String] = []
	for row in rows:
		refs.append(String(row["ref"]))
	if refs != _variant_refs:
		_variant_refs = refs
		if variant_field != null:
			selection_box.remove_child(variant_field)
			variant_field.queue_free()
			variant_field = null
		if not rows.is_empty():
			variant_field = TileField.new()
			variant_field.name = "StructureVariants"
			variant_field.caption = "Style"
			variant_field.tiles.photo_icons = true
			variant_field.tiles.tile_min_size = VARIANT_TILE_SIZE
			variant_field.tiles.columns = 2
			for row in rows:
				var tile := variant_field.tiles.add_tile(
					StringName(String(row["ref"])),
					String(row["variant"]),
					"",
					"%s: swap the look, keep the footprint." % row["name"],
					StructureThumbnail.of(row, VARIANT_THUMB_PX)
				)
				# A long Style name wraps to a second line (the full name is also the tooltip).
				tile.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			variant_field.tiles.selection_changed.connect(
				func(id: StringName) -> void: variant_picked.emit(String(id))
			)
			selection_box.add_child(variant_field)
	if variant_field != null:
		variant_field.tiles.select(StringName(ref))


## The tile measures for the pane's width now (StructurePalette.tile_metrics).
func _metrics() -> Dictionary:
	var width := size.x if size.x > 1.0 else FALLBACK_WIDTH_PX
	var metrics := StructurePalette.tile_metrics(_small_tiles, width)
	_columns = int(metrics["columns"])
	return metrics


## Sets every family's column count from the pane's width again (a resize, a drawer opening or
## closing): as many tiles as fit across, two at least.
func _fit_tiles() -> void:
	var before := _columns
	var metrics := _metrics()
	if _columns == before:
		return
	for field in family_fields:
		if is_instance_valid(field):
			field.tiles.columns = int(metrics["columns"])


## The chip row, then the row with Clear and the small-tiles switch. Chips are toggles: one group's
## chips widen the choice, another group's narrow it (StructurePalette.CHIPS).
func _build_filters() -> void:
	_chip_flow = VBoxContainer.new()
	_chip_flow.name = "StructureChips"
	_chip_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chip_flow.theme_type_variation = &"BoxContainerSnug"
	add_child(_chip_flow)
	# One captioned wrapping row per axis (Kind, Material), so the two axes never read as one list.
	for group: Dictionary in StructurePalette.GROUPS:
		var group_id := String(group["id"])
		var caption := _caption("ChipGroup_" + group_id, String(group["caption"]))
		_chip_flow.add_child(caption)
		var flow := HFlowContainer.new()
		flow.name = "ChipRow_" + group_id
		flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		flow.theme_type_variation = &"FactsFlow"
		_chip_flow.add_child(flow)
		for item: Dictionary in StructurePalette.CHIPS:
			if String(item["group"]) != group_id:
				continue
			var id := String(item["id"])
			var chip := Button.new()
			chip.name = "Chip_" + id
			chip.text = String(item["label"])
			chip.toggle_mode = true
			chip.theme_type_variation = &"ToggleChip"
			chip.focus_mode = Control.FOCUS_NONE
			chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			chip.toggled.connect(_on_chip_toggled.bind(id))
			flow.add_child(chip)
			chip_buttons[id] = chip
	_filter_row = HBoxContainer.new()
	_filter_row.name = "StructureFilterRow"
	_filter_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_filter_row)
	clear_button = Button.new()
	clear_button.name = "StructureClear"
	clear_button.text = "Clear"
	clear_button.tooltip_text = CLEAR_CHIPS_TIP
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clear_button.pressed.connect(clear_filters)
	_filter_row.add_child(clear_button)
	small_tiles_button = Button.new()
	small_tiles_button.name = "StructureSmallTiles"
	small_tiles_button.text = "Small tiles"
	small_tiles_button.toggle_mode = true
	small_tiles_button.tooltip_text = SMALL_TILES_TIP
	small_tiles_button.focus_mode = Control.FOCUS_NONE
	small_tiles_button.toggled.connect(
		func(on: bool) -> void:
			_small_tiles = on
			UiPreferences.save_structure_tiles_small(on)
			refresh()
	)
	_filter_row.add_child(small_tiles_button)


## The chips switched on (ids).
func active_chips() -> Array[String]:
	return _active_chips


## Switches chip `chip_id` on or off, as a click would.
func set_chip(chip_id: String, on: bool) -> void:
	_active_chips = StructurePalette.toggled(_active_chips, chip_id, on)
	refresh()


## Switches every chip off and empties the search.
func clear_filters() -> void:
	_active_chips = []
	search_edit.text = ""
	refresh()


func _on_chip_toggled(on: bool, chip_id: String) -> void:
	set_chip(chip_id, on)


## Shows each chip's count (what it would show with the search and the other groups' chips), greys
## one that would show nothing, and shows Clear with the tally while a filter is on.
func _update_filters(rows: Array, shown: int) -> void:
	var counts := StructurePalette.chip_counts(rows, search_edit.text, _active_chips)
	for item: Dictionary in StructurePalette.CHIPS:
		var id := String(item["id"])
		var chip: Button = chip_buttons[id]
		var count := int(counts[id])
		chip.text = "%s %d" % [item["label"], count]
		chip.set_pressed_no_signal(id in _active_chips)
		chip.disabled = count == 0 and not id in _active_chips
	var filtering := not _active_chips.is_empty() or search_edit.text.strip_edges() != ""
	clear_button.disabled = not filtering
	var tally := StructurePalette.tally(shown, rows.size(), filtering)
	clear_button.text = "Clear (%s)" % tally if filtering else "Clear"
	_no_match.text = NO_MATCH_CHIPS if not _active_chips.is_empty() else NO_MATCH


## The hover card: built once, shown beside the tile under the pointer.
func _build_card() -> void:
	card = PanelContainer.new()
	card.name = "StructureCard"
	card.theme_type_variation = &"Plaque"
	card.top_level = true
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.visible = false
	add_child(card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.theme_type_variation = &"BoxContainerSnug"
	box.custom_minimum_size = Vector2(CARD_PICTURE_PX, 0)
	card.add_child(box)
	card_picture = TextureRect.new()
	card_picture.name = "CardPicture"
	card_picture.custom_minimum_size = Vector2(CARD_PICTURE_PX, CARD_PICTURE_PX)
	card_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	card_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	card_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(card_picture)
	card_title = Label.new()
	card_title.name = "CardTitle"
	card_title.theme_type_variation = &"Heading"
	box.add_child(card_title)
	card_detail = _caption("CardDetail", "")
	card_detail.custom_minimum_size = Vector2(CARD_PICTURE_PX, 0)
	box.add_child(card_detail)
	card_size = _caption("CardSize", "")
	card_size.custom_minimum_size = Vector2(CARD_PICTURE_PX, 0)
	box.add_child(card_size)


## The card for the tile `id` of `from_field` shows after CARD_DELAY_S, beside the tile.
func _on_tile_hovered(id: StringName, from_field: TileField) -> void:
	_card_for = String(id)
	if _card_tween != null:
		_card_tween.kill()
	_card_tween = create_tween()
	_card_tween.tween_interval(CARD_DELAY_S)
	_card_tween.tween_callback(_show_card.bind(String(id), from_field))


func _show_card(ref: String, from_field: TileField) -> void:
	if _card_for != ref or not is_instance_valid(from_field):
		return
	var row := LibraryStructureStore.structure(ref)
	if row.is_empty():
		return
	var lines := StructurePalette.card(row)
	card_picture.texture = StructureThumbnail.of(row, CARD_PICTURE_PX)
	card_title.text = lines["title"]
	card_detail.text = lines["detail"]
	card_size.text = lines["size"]
	var tile_rect := from_field.tiles.tile_global_rect(StringName(ref))
	card.reset_size()
	var view := get_viewport_rect().size
	# On the board beside the drawer (and its rail), never over the tiles it is about.
	var board := DrawerContainer.free_span(get_viewport())
	var at := Vector2(maxf(tile_rect.end.x + 8.0, board.x + 8.0), tile_rect.position.y)
	at.y = clampf(at.y, 4.0, maxf(4.0, view.y - card.size.y - 4.0))
	at.x = minf(at.x, maxf(board.x, view.x - card.size.x - 4.0))
	card.global_position = at
	card.visible = true


func _hide_card() -> void:
	_card_for = ""
	if _card_tween != null:
		_card_tween.kill()
		_card_tween = null
	if card != null:
		card.visible = false


## Shows or hides the palette parts (the hint, the chips, the family tiles, Mix afresh).
func _show_palette(shown: bool) -> void:
	_hint.visible = shown
	for field in family_fields:
		if is_instance_valid(field):
			field.visible = shown
	_tools_row.visible = shown and _served > 0
	reroll_button.visible = _tools_row.visible
	_chip_flow.visible = _tools_row.visible
	_filter_row.visible = _tools_row.visible
	if not shown:
		_hide_card()
	_no_match.visible = shown and _served > 0 and _found_none
	_empty.visible = shown and _served == 0


## The "Place another" strip: the armed pick's picture and name, and the button that opens the
## whole palette in place of the bar. Shown while a building is selected.
func _build_place_strip() -> void:
	place_strip = HBoxContainer.new()
	place_strip.name = "StructurePlaceStrip"
	place_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_strip.visible = false
	add_child(place_strip)
	place_thumb = TextureRect.new()
	place_thumb.name = "PlaceThumb"
	place_thumb.custom_minimum_size = Vector2(PLACE_THUMB_PX, PLACE_THUMB_PX)
	place_thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	place_thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	place_thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_strip.add_child(place_thumb)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.theme_type_variation = &"BoxContainerSnug"
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place_strip.add_child(words)
	words.add_child(_caption("PlaceCaption", PLACE_CAPTION))
	place_name = Label.new()
	place_name.name = "PlaceName"
	place_name.clip_text = true
	place_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	place_name.custom_minimum_size = Vector2(1, 0)
	words.add_child(place_name)
	place_button = Button.new()
	place_button.name = "PlaceBrowse"
	place_button.text = PLACE_BROWSE
	place_button.tooltip_text = PLACE_BROWSE_TIP
	place_button.focus_mode = Control.FOCUS_NONE
	place_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	place_button.pressed.connect(func() -> void: set_browsing(not _browsing))
	place_strip.add_child(place_button)


## Opens the whole palette in place of the selected building's bar (`on`), or closes it again. A
## pick made in it closes it. No effect without a selection.
func set_browsing(on: bool) -> void:
	_browsing = on and _has_selection
	selection_box.visible = _has_selection and not _browsing
	_show_palette(not selection_box.visible)
	_update_place_strip()


func is_browsing() -> bool:
	return _browsing


func _update_place_strip() -> void:
	place_strip.visible = _has_selection
	var row := LibraryStructureStore.structure(_picked)
	place_name.text = String(row.get("name", ""))
	place_thumb.texture = StructureThumbnail.of(row, PLACE_THUMB_PX) if not row.is_empty() else null
	place_button.text = PLACE_BACK if _browsing else PLACE_BROWSE
	place_button.tooltip_text = PLACE_BACK_TIP if _browsing else PLACE_BROWSE_TIP


## The selected building's bar: its name, the variant tiles (made when a selection shows), a
## stepper per recipe parameter the library exposes, and the buttons.
func _build_selection() -> void:
	selection_box = VBoxContainer.new()
	selection_box.name = "StructureSelection"
	selection_box.theme_type_variation = &"BoxContainerSnug"
	selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.visible = false
	add_child(selection_box)
	selection_title = Label.new()
	selection_title.name = "SelectionTitle"
	selection_title.theme_type_variation = &"Heading"
	selection_box.add_child(selection_title)
	selection_box.add_child(_caption("SelectionHint", SELECTION_HINT))
	for item: Dictionary in STEPPED:
		var param := String(item["param"])
		var row := HBoxContainer.new()
		row.name = "Stepper_" + param
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var caption := Label.new()
		caption.text = String(item["caption"])
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var minus := _stepper_button("Stepper_%s_less" % param, "-", "Fewer or less")
		minus.pressed.connect(func() -> void: param_stepped.emit(param, -1))
		row.add_child(minus)
		var value := Label.new()
		value.name = "Stepper_%s_value" % param
		value.custom_minimum_size = Vector2(64, 0)
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(value)
		var plus := _stepper_button("Stepper_%s_more" % param, "+", "More or higher")
		plus.pressed.connect(func() -> void: param_stepped.emit(param, 1))
		row.add_child(plus)
		selection_box.add_child(row)
		steppers[param] = {"row": row, "value": value, "minus": minus, "plus": plus}
	ornaments_section = StructureOrnamentsSection.new()
	ornaments_section.ornaments_requested.connect(ornaments_requested.emit)
	ornaments_section.ivy_requested.connect(ivy_requested.emit)
	add_selection_section(ornaments_section)
	# The buttons sit in pairs, the safe ones first, Remove apart from Done. New actions add a row
	# or a section to selection_box before the buttons: use add_selection_section().
	var door_row := _button_row("SelectionRowDoor")
	door_button = _action_button(
		door_row,
		"SelectionDoor",
		"Door to the next side",
		"Put the door on the next side round (or click a side tab)",
		door_requested
	)
	var make_row := _button_row("SelectionRowMake")
	redraw_button = _action_button(
		make_row, "SelectionRedraw", "Redraw", "Draw this building afresh (R)", redraw_requested
	)
	copy_button = _action_button(
		make_row, "SelectionCopy", "Copy", "A copy beside it (Ctrl+D)", copy_requested
	)
	var end_row := _button_row("SelectionRowEnd")
	remove_button = _action_button(
		end_row, "SelectionRemove", "Remove", "Take this building away (Delete)", remove_requested
	)
	done_button = _action_button(
		end_row, "SelectionDone", "Done", "Let go of the building (Escape)", done_requested
	)
	# The buttons go right under the name (Redraw and Copy, the door, then Remove and Done): the
	# Style tiles below are long, and a button must never be a scroll away.
	for at in 3:
		selection_box.move_child([make_row, door_row, end_row][at], 1 + at)


func _stepper_button(button_name: String, text: String, tip: String) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(32, 0)
	return button


## The extension point for the selected building's bar: adds `section` (a Control, named and
## built by the caller, filled in show_selection's wake from selection_changed) below the
## steppers and above the Style tiles, and returns it. The buttons stay at the top, so Done and
## Remove never scroll away behind a long tile grid.
func add_selection_section(section: Control) -> Control:
	selection_box.add_child(section)
	if variant_field != null:
		selection_box.move_child(section, variant_field.get_index())
	return section


func _button_row(row_name: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = row_name
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	selection_box.add_child(row)
	return row


func _action_button(
	row: HBoxContainer, button_name: String, text: String, tip: String, done: Signal
) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = text
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(done.emit)
	row.add_child(button)
	return button


func _on_tile(id: StringName, from_field: TileField) -> void:
	_picked = String(id)
	for field in family_fields:
		if field != from_field:
			field.tiles.clear_selection()
	structure_selected.emit(String(id))
	# A pick made while browsing from a selected building is the answer: back to the bar.
	if _browsing:
		set_browsing(false)
	_update_place_strip()


func _caption(node_name: String, text: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(1, 0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label
