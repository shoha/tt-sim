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
## row's last item at the current column count), hidden with nothing selected. The strip is at
## most DETAIL_MAX_WIDTH wide (the 960 sheet token) and stands under its card, centred on it
## and clamped to the grid, so its Play and Host sit by the map they act on. Selecting a card,
## by a click or select(), scrolls the grid so the card's row and the whole strip are in view.
## Bundled maps (LibraryFacts.is_bundled) follow a heading on a line of their own, after every
## other; with no map of the player's own the lead stands alone, larger and centred, and the
## heading under it offers the Bundled maps instead (EMPTY_HEADING).
##
## Where the grid's edge cuts a card, the card fades by how much of it lies out of view
## (CUT_ALPHA at the least), so the grid ends in a fade rather than a straight cut.

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
## The detail strip's widest (S5's 960 sheet).
const DETAIL_MAX_WIDTH := 960.0
## The least an item the grid's edge cuts fades to (_fade_cut_items).
const CUT_ALPHA := 0.35
## How long the scroll bar stays after a scroll with the pointer elsewhere.
const BAR_LINGER_S := 0.8
## Frames a reveal is repeated over, while the flow lays the strip out under its new row.
const REVEAL_FRAMES := 3
const BUNDLED_HEADING := "Bundled with TTSim"
## The heading over the Bundled maps when the player has no map of their own yet.
const EMPTY_HEADING := "Or play one that comes with TTSim"

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
var _bundled_heading: VBoxContainer = null
var _heading_words: Label = null
## The detail strip's line: the grid's full width, the strip placed in it by _lay_detail().
var _detail_line: Control = null
## Frames left in the current reveal.
var _reveal_frames := 0
## The scroll bar's fade (_show_bar), whether the pointer is over the cards, and the time the
## bar stays after a scroll.
var _bar_tween: Tween = null
var _pointer_over := false
var _linger: Timer


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The CardGrid panel's margins keep a focused card's ring inside the scroll clip.
	theme_type_variation = &"CardGrid"
	# The bar is its handle alone (the theme's lane is clear), shown only while it is wanted
	# (user verdict 2026-10-10): _show_bar().
	var bar := get_v_scroll_bar()
	bar.modulate.a = 0.0
	bar.value_changed.connect(_on_scrolled)
	mouse_entered.connect(_on_pointer.bind(true))
	mouse_exited.connect(_on_pointer.bind(false))
	_linger = Timer.new()
	_linger.name = "BarLinger"
	_linger.one_shot = true
	_linger.wait_time = BAR_LINGER_S
	_linger.timeout.connect(_show_bar.bind(false))
	add_child(_linger)
	_flow = HFlowContainer.new()
	_flow.name = "Flow"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", GAP)
	_flow.add_theme_constant_override("v_separation", GAP)
	_flow.resized.connect(content_resized.emit)
	_flow.sort_children.connect(_lay_detail)
	_flow.sort_children.connect(_fade_cut_items)
	add_child(_flow)


func _on_scrolled(_value: float) -> void:
	_fade_cut_items()
	_show_bar(true)
	if not _pointer_over:
		_linger.start()


func _on_pointer(inside: bool) -> void:
	_pointer_over = inside
	if inside:
		_show_bar(true)
	else:
		_linger.start()


## The scroll bar fades in while the pointer is over the cards and for BAR_LINGER_S after a
## wheel, pad or drag scrolls them, then out (M1). Hidden, it still takes a click or a drag
## where it stands, so a pointer always finds it; the pad scrolls by focus.
func _show_bar(on: bool) -> void:
	if not on and _pointer_over:
		return
	if not is_inside_tree():
		return
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	var duration := Constants.ANIM_HOVER_SOFT_IN if on else Constants.ANIM_HOVER_SOFT_OUT
	_bar_tween = create_tween()
	_bar_tween.tween_property(get_v_scroll_bar(), "modulate:a", 1.0 if on else 0.0, duration)


## An item the grid's edge cuts fades by how much of it is out of view, down to CUT_ALPHA, so
## the grid ends in a fade rather than a straight cut through whole cards. (A mask over the
## cards, clip_children, blanked their clipped picture wells.)
func _fade_cut_items() -> void:
	var view := _view_height()
	for child in _flow.get_children():
		var item := child as Control
		if item == null or item.size.y <= 0.0:
			continue
		var top := item.position.y - float(scroll_vertical)
		var shown := clampf(minf(top + item.size.y, view) - maxf(top, 0.0), 0.0, item.size.y)
		item.modulate.a = lerpf(CUT_ALPHA, 1.0, shown / item.size.y)


func _ready() -> void:
	resized.connect(_fit_columns)
	resized.connect(_fade_cut_items)


func refresh() -> void:
	# Out of the flow at once, so the detail strip's row is found among the new cards only.
	for card in _cards:
		_flow.remove_child(card)
		card.queue_free()
	_cards.clear()
	if lead != null and lead.get_parent() == null:
		_flow.add_child(lead)
	if detail != null and _detail_line == null:
		_detail_line = Control.new()
		_detail_line.name = "DetailLine"
		_detail_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_detail_line.add_child(detail)
		_flow.add_child(_detail_line)
		detail.minimum_size_changed.connect(_lay_detail)
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
		# Every item fills its line's height, so a row's bottoms line up (the New map card is
		# taller than a map's).
		card.size_flags_vertical = Control.SIZE_FILL
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


## The number of cards that are the player's own maps (not Bundled).
func own_card_count() -> int:
	var own := _cards.filter(
		func(card: LevelCard) -> bool: return not LibraryFacts.is_bundled(card.level_info)
	)
	return own.size()


## The heading before the first Bundled card, or hidden with none, or in a picker when every
## map is Bundled (nothing to set them apart from). Over an empty library it offers the Bundled
## maps instead (EMPTY_HEADING), centred under the lone New map card.
func _place_bundled_heading(first_bundled: LevelCard) -> void:
	if first_bundled == null or (lead == null and first_bundled == _cards[0]):
		if _bundled_heading != null:
			_bundled_heading.visible = false
		return
	if _bundled_heading == null:
		# A line of its own (the row's full width, no paper) with the heading's words on a plaque
		# that ends at them, a gap's more room above it than below (S4).
		_bundled_heading = VBoxContainer.new()
		_bundled_heading.name = "BundledHeading"
		_bundled_heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var above := Control.new()
		above.custom_minimum_size.y = GAP
		above.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bundled_heading.add_child(above)
		var row := HBoxContainer.new()
		row.name = "Row"
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bundled_heading.add_child(row)
		var plaque := PanelContainer.new()
		plaque.theme_type_variation = &"Plaque"
		plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(plaque)
		_heading_words = Label.new()
		_heading_words.name = "Words"
		_heading_words.theme_type_variation = &"H2"
		plaque.add_child(_heading_words)
		_flow.add_child(_bundled_heading)
	var own := own_card_count() > 0
	_heading_words.text = BUNDLED_HEADING if own else EMPTY_HEADING
	(_bundled_heading.get_node("Row") as HBoxContainer).alignment = (
		BoxContainer.ALIGNMENT_BEGIN if own else BoxContainer.ALIGNMENT_CENTER
	)
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
	if _detail_line == null:
		return
	var card := card_for(_selected_path)
	_detail_line.visible = card != null
	if card == null:
		return
	_flow.move_child(_detail_line, -1)
	var items: Array[Control] = []
	var wides: Array = []
	for child in _flow.get_children():
		var item := child as Control
		if item == _detail_line or not item.visible:
			continue
		items.append(item)
		wides.append(item == _bundled_heading)
	var end := line_end(wides, items.find(card), _per_line)
	_flow.move_child(_detail_line, items[end].get_index() + 1)
	_lay_detail()


## The strip in its line: at most DETAIL_MAX_WIDTH wide, centred under the selected card and
## clamped to the grid, the line as tall as the strip. Runs whenever the flow lays out.
func _lay_detail() -> void:
	if _detail_line == null or not _detail_line.visible:
		return
	var full := _detail_line.custom_minimum_size.x
	var width := minf(DETAIL_MAX_WIDTH, full)
	var height := detail.get_combined_minimum_size().y
	if not is_equal_approx(_detail_line.custom_minimum_size.y, height):
		_detail_line.custom_minimum_size.y = height
	var card := card_for(_selected_path)
	var x := 0.0
	if card != null:
		x = card.position.x + card.size.x * 0.5 - width * 0.5
	detail.position = Vector2(clampf(x, 0.0, maxf(full - width, 0.0)), 0.0)
	detail.size = Vector2(width, height)


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
	reveal_selected()


## Scrolls the grid so the selected card's row and the strip under it are in view (the card's
## row first when both cannot fit), over the next REVEAL_FRAMES frames while the flow lays the
## strip out under its new row.
func reveal_selected() -> void:
	_reveal_frames = REVEAL_FRAMES
	if is_inside_tree() and not get_tree().process_frame.is_connected(_on_reveal_frame):
		get_tree().process_frame.connect(_on_reveal_frame)


func _on_reveal_frame() -> void:
	_reveal_frames -= 1
	if _reveal_frames <= 0:
		get_tree().process_frame.disconnect(_on_reveal_frame)
	var card := card_for(_selected_path)
	if card == null or not card.is_inside_tree():
		return
	var bottom := card.position.y + card.size.y
	if _detail_line != null and _detail_line.visible:
		bottom = maxf(bottom, _detail_line.position.y + _detail_line.size.y)
	scroll_vertical = roundi(
		reveal_scroll(float(scroll_vertical), card.position.y, bottom, _view_height())
	)


## The scroll that shows content from `top` to `bottom` (flow coordinates) in a view
## `view` tall, moving as little as it can from `current`; `top` when it cannot all fit. Pure.
static func reveal_scroll(current: float, top: float, bottom: float, view: float) -> float:
	if bottom - top > view:
		return top
	return clampf(current, bottom - view, top)


## The height the cards are seen through (the grid inside its panel's margins).
func _view_height() -> float:
	return size.y - get_theme_stylebox(&"panel").get_minimum_size().y


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
	# The library's lead takes a card's width beside the player's maps; with none of their own
	# it keeps the size its owner gave it, centred, the Bundled maps centred under it.
	var alone := lead != null and own_card_count() == 0
	if lead != null and not alone:
		lead.custom_minimum_size.x = width
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER if alone else FlowContainer.ALIGNMENT_BEGIN
	for wide: Control in [_detail_line, _bundled_heading]:
		if wide != null:
			wide.custom_minimum_size.x = size.x - reserved
	_place_detail()


func _on_card_selected(info: Dictionary) -> void:
	_selected_path = info.get("path", "")
	_apply_selection()
	selection_changed.emit(info)
	reveal_selected()


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
