class_name LevelGrid
extends ScrollContainer

## Saved levels as a grid of LevelCards. The provider is a Callable returning
## the level info list (LevelManager.get_saved_levels by default; tests inject
## a fake). Selection is single; programmatic select() is silent. Card actions
## write through LevelManager and refresh.

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

var _flow: HFlowContainer
var _cards: Array[LevelCard] = []
var _selected_path: String = ""


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
	for card in _cards:
		card.queue_free()
	_cards.clear()
	var levels: Array = provider.call()
	for info in levels:
		var card := LevelCard.new()
		card.setup(info)
		card.locked = not locked_path.is_empty() and info.get("path", "") == locked_path
		card.manageable = manageable
		card.selected.connect(_on_card_selected)
		card.activated.connect(_on_card_activated)
		card.action_requested.connect(_on_card_action)
		card.rename_committed.connect(_on_card_rename)
		_flow.add_child(card)
		_cards.append(card)
	_fit_columns()
	_apply_selection()
	levels_changed.emit()


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


func selected_info() -> Dictionary:
	for card in _cards:
		if card.level_info.get("path", "") == _selected_path:
			return card.level_info
	return {}


func _apply_selection() -> void:
	for card in _cards:
		card.set_selected(card.level_info.get("path", "") == _selected_path)


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
