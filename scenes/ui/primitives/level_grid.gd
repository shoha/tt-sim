class_name LevelGrid
extends ScrollContainer

## Saved levels as a grid of LevelCards. The provider is a Callable returning
## the level info list (LevelManager.get_saved_levels by default; tests inject
## a fake). Selection is single; programmatic select() is silent. Card actions
## write through LevelManager and refresh.
##
## The title's library adds two controls of its own (both null in a picker): `lead`, the New
## map card, first in the flow at a card's width, and `detail`, the selected card's detail
## strip, on a line of its own directly under the selected card's row (line_end() finds the
## row's last item at the current column count), hidden with nothing selected. Bundled maps
## (LibraryFacts.is_bundled) follow a heading on a line of their own, after every other.

signal selection_changed(level_info: Dictionary)
signal level_activated(level_info: Dictionary)
## Opening the level editor is an app-level action, so unlike duplicate/delete this
## one is forwarded to the owner rather than written through LevelManager here.
signal level_edit_requested(level_info: Dictionary)
## The card's "Edit map": open the level's map in authoring mode (forwarded like Edit).
signal level_map_edit_requested(level_info: Dictionary)
signal levels_changed
## The cards' laid-out height changed (content_height()).
signal content_resized

const GAP := 12
## The widest a card grows; past it the grid adds a column.
const MAX_CARD_WIDTH := 400

## The fewest columns; a wide grid adds more.
@export var columns: int = 3:
	set(value):
		columns = value
		_fit_columns()

var provider: Callable = LevelManager.get_saved_levels
## func(title: String, message: String, on_confirm: Callable) -> void
var confirm_delete: Callable = _default_confirm_delete
## The level being played: its card cannot be deleted.
var locked_path: String = ""
## False for a grid that only chooses (a picker): its cards drop the overflow menu.
var manageable: bool = true
## The library's first card (the title's New map card), or null. Set before the first refresh.
var lead: Control = null
## The selected card's detail strip (the title's MapDetailStrip), or null. Set before the first
## refresh.
var detail: Control = null
## Accept (Enter, pad A) on a card that is not selected selects it rather than activating it,
## so a pad can open the detail strip; a second Accept activates (the library).
var select_before_activate: bool = false

var _flow: HFlowContainer
var _cards: Array[LevelCard] = []
var _selected_path: String = ""
## Cards per line at the current width (_fit_columns).
var _per_line: int = 1
## The Bundled maps' heading, on a line of its own before them (library only).
var _bundled_heading: HBoxContainer = null


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The CardGrid panel's margins keep a focused card's ring inside the scroll clip.
	theme_type_variation = &"CardGrid"
	# Over the painted backdrop the bar stands on a paper strip of its own (3:1 in every mood).
	get_v_scroll_bar().theme_type_variation = &"CardGridBar"
	_flow = HFlowContainer.new()
	_flow.name = "Flow"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", GAP)
	_flow.add_theme_constant_override("v_separation", GAP)
	_flow.resized.connect(content_resized.emit)
	add_child(_flow)


func _ready() -> void:
	resized.connect(_fit_columns)


func refresh() -> void:
	# Out of the flow at once, so the detail strip's row is found among the new cards only.
	for card in _cards:
		_flow.remove_child(card)
		card.queue_free()
	_cards.clear()
	for extra in [lead, detail]:
		if extra != null and (extra as Control).get_parent() == null:
			_flow.add_child(extra)
	if lead != null:
		_flow.move_child(lead, 0)
	var levels: Array = provider.call()
	var first_bundled: LevelCard = null
	for info: Dictionary in levels:
		var card := LevelCard.new()
		if lead != null and first_bundled == null and LibraryFacts.is_bundled(info):
			first_bundled = card
		card.setup(info)
		card.locked = not locked_path.is_empty() and info.get("path", "") == locked_path
		card.manageable = manageable
		card.accept_selects_first = select_before_activate
		# A taller card in the row (the New map card with Advanced open) leaves these at their
		# own height.
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.selected.connect(_on_card_selected)
		card.activated.connect(_on_card_activated)
		card.action_requested.connect(_on_card_action)
		card.rename_committed.connect(_on_card_rename)
		_flow.add_child(card)
		_cards.append(card)
	_place_bundled_heading(first_bundled)
	_fit_columns()
	_apply_selection()
	levels_changed.emit()


## Runs a card action on `info` as its own menu would ("duplicate", "delete", "edit",
## "edit_map"): the detail strip's "..." menu acts through this.
func act(info: Dictionary, action: StringName) -> void:
	_on_card_action(info, action)


## Shows `info` (an edited name or description) on its card without rebuilding the grid.
func update_info(info: Dictionary) -> void:
	for card in _cards:
		if card.level_info.get("path", "") == info.get("path", ""):
			card.setup(info)


## The card showing level `path`, or null.
func card_for(path: String) -> LevelCard:
	for card in _cards:
		if card.level_info.get("path", "") == path:
			return card
	return null


## The heading before the first Bundled card, or hidden with none, or when every map is
## Bundled (nothing to set them apart from).
func _place_bundled_heading(first_bundled: LevelCard) -> void:
	if first_bundled == null or first_bundled == _cards[0]:
		if _bundled_heading != null:
			_bundled_heading.visible = false
		return
	if _bundled_heading == null:
		# A line of its own (the row's full width, no paper) with the words on a plaque that
		# ends at them.
		_bundled_heading = HBoxContainer.new()
		_bundled_heading.name = "BundledHeading"
		_bundled_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var plaque := PanelContainer.new()
		plaque.theme_type_variation = &"Plaque"
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bundled_heading.add_child(plaque)
		var words := Label.new()
		words.text = "Bundled with TTSim"
		words.theme_type_variation = &"Caption"
		plaque.add_child(words)
		_flow.add_child(_bundled_heading)
	_bundled_heading.visible = true
	# From the end, so taking it out shifts nothing before the card it goes in front of.
	_flow.move_child(_bundled_heading, -1)
	_flow.move_child(_bundled_heading, first_bundled.get_index())


## The flow index of the last item on the line that holds item `target`, items laid out
## `per_line` to a line in order and each item `wides` marks on a line of its own. Pure.
static func line_end(wides: Array, target: int, per_line: int) -> int:
	var lines: Array[int] = []
	var line := 0
	var column := 0
	for wide: bool in wides:
		if wide:
			line += 1 if column > 0 else 0
			lines.append(line)
			line += 1
			column = 0
			continue
		if column >= maxi(per_line, 1):
			line += 1
			column = 0
		lines.append(line)
		column += 1
	var end := target
	while end + 1 < lines.size() and lines[end + 1] == lines[target]:
		end += 1
	return end


## The detail strip directly under the selected card's row, or hidden with none selected.
func _place_detail() -> void:
	if detail == null or detail.get_parent() != _flow:
		return
	var card := card_for(_selected_path)
	detail.visible = card != null
	if card == null:
		return
	_flow.move_child(detail, -1)
	var items: Array[Control] = []
	var wides: Array = []
	for child in _flow.get_children():
		var item := child as Control
		if item == detail or not item.visible:
			continue
		items.append(item)
		wides.append(item == _bundled_heading)
	var end := line_end(wides, items.find(card), _per_line)
	_flow.move_child(detail, items[end].get_index() + 1)


func card_count() -> int:
	return _cards.size()


## The height the cards take laid out at the grid's width, with the grid's own margins: how
## tall the grid must be to show them all without scrolling.
func content_height() -> float:
	return _flow.get_combined_minimum_size().y + get_theme_stylebox(&"panel").get_minimum_size().y


## Silent selection by level path; an unknown path clears the selection. The selected card
## scrolls into view once the grid has laid it out (the newest map may sit past the fold).
func select(path: String) -> void:
	_selected_path = path
	_apply_selection()
	if is_inside_tree() and not get_tree().process_frame.is_connected(_reveal_selected):
		get_tree().process_frame.connect(_reveal_selected, CONNECT_ONE_SHOT)


func _reveal_selected() -> void:
	for card in _cards:
		if card.level_info.get("path", "") == _selected_path and card.is_inside_tree():
			ensure_control_visible(card)
			# The strip under the row is part of what the selection shows.
			if detail != null and detail.is_visible_in_tree():
				ensure_control_visible(detail)
				ensure_control_visible(card)


func selected_info() -> Dictionary:
	for card in _cards:
		if card.level_info.get("path", "") == _selected_path:
			return card.level_info
	return {}


func _apply_selection() -> void:
	for card in _cards:
		card.set_selected(card.level_info.get("path", "") == _selected_path)
	_place_detail()


func _fit_columns() -> void:
	if columns <= 0 or size.x <= 0.0:
		return
	# Always reserve the vertical scrollbar's width so the column count does not
	# flip when the bar appears (a visible-only rule oscillates at the boundary:
	# narrower cards are shorter, which can hide the bar, which widens them again).
	var reserved := get_v_scroll_bar().get_combined_minimum_size().x
	reserved += get_theme_stylebox(&"panel").get_minimum_size().x
	# A wide grid adds columns rather than stretch a card past MAX_CARD_WIDTH (S5).
	var span := size.x - reserved + float(GAP)
	var count := maxi(columns, ceili(span / float(MAX_CARD_WIDTH + GAP)))
	var available := size.x - reserved - float(GAP * (count - 1))
	var width := floorf(available / float(count))
	for card in _cards:
		card.custom_minimum_size.x = width
	_per_line = count
	# The library's lead takes a card's width beside cards; alone (an empty library) it keeps
	# the size its owner gave it, centred.
	if lead != null and not _cards.is_empty():
		lead.custom_minimum_size.x = width
	_flow.alignment = (
		FlowContainer.ALIGNMENT_CENTER
		if lead != null and _cards.is_empty()
		else FlowContainer.ALIGNMENT_BEGIN
	)
	for wide: Control in [detail, _bundled_heading]:
		if wide != null:
			wide.custom_minimum_size.x = size.x - reserved
	_place_detail()


func _on_card_selected(info: Dictionary) -> void:
	_selected_path = info.get("path", "")
	_apply_selection()
	selection_changed.emit(info)


func _on_card_activated(info: Dictionary) -> void:
	_selected_path = info.get("path", "")
	_apply_selection()
	level_activated.emit(info)


func _on_card_action(info: Dictionary, action: StringName) -> void:
	match action:
		&"edit":
			level_edit_requested.emit(info)
		&"edit_map":
			level_map_edit_requested.emit(info)
		&"duplicate":
			var new_path := LevelManager.duplicate_level(info)
			if new_path.is_empty():
				UIManager.show_error(
					"Could not duplicate “%s”: the copy was not written. Try again." % _name(info)
				)
				return
			refresh()
			select(new_path)
		&"delete":
			confirm_delete.call(
				"Delete %s?" % info.get("name", "this map"),
				"The map and its tokens are removed from this computer. This cannot be undone.",
				_delete.bind(info)
			)


## The card's map name for an error line, or "this map".
static func _name(info: Dictionary) -> String:
	return String(info.get("name", "this map"))


func _delete(info: Dictionary) -> void:
	var path: String = info.get("path", "")
	var index := _index_of(path)
	if not LevelManager.delete_level(path):
		UIManager.show_error(
			(
				"Could not delete “%s”: its files could not be removed. Try again in a moment."
				% _name(info)
			)
		)
		return
	refresh()
	if _cards.is_empty():
		select("")
	elif path == _selected_path:
		select(_cards[mini(index, _cards.size() - 1)].level_info.get("path", ""))


func _on_card_rename(info: Dictionary, new_name: String) -> void:
	var new_path := LevelManager.rename_level(info, new_name)
	if new_path.is_empty():
		UIManager.show_error("Could not rename “%s”. Try another name." % _name(info))
		return
	refresh()
	select(new_path)


func _index_of(path: String) -> int:
	for i in range(_cards.size()):
		if _cards[i].level_info.get("path", "") == path:
			return i
	return 0


func _default_confirm_delete(title: String, message: String, on_confirm: Callable) -> void:
	UIManager.show_danger_confirmation(title, message, on_confirm)
