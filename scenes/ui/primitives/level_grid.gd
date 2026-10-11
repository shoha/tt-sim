class_name LevelGrid
extends ScrollContainer

## Saved levels as a grid of LevelCards. The provider is a Callable returning
## the level info list (LevelManager.get_saved_levels by default; tests inject
## a fake). Selection is single; programmatic select() is silent. Card actions
## write through LevelManager and refresh.
##
## The grid fills its width: it adds a column rather than stretch a card past max_card_width,
## and never shows fewer than `columns`. Selecting a card, by a click or select(), scrolls the
## grid so the card is in view. The grid clips at its own edge (a hard edge under the title's
## sticky heading); its scroll bar is the handle alone, shown only while the pointer is over the
## cards or for a moment after a scroll (ScrollBarFade, user verdict 2026-10-10).
##
## The title's library adds `lead`, the New map card, first in the flow at a card's width (null
## in a picker), and section headings in text on lines of their own (the heading face at the
## section size, a step more room above than below, S4): "Your maps" over New map and the
## player's maps, "Bundled with TTSim" over the Bundled maps (LibraryFacts.is_bundled), which
## come after every other. With no map of the player's own the lead stands alone, larger and
## centred (on alone_centre when the owner gives one: the title's window middle), and the
## heading under it offers the Bundled maps instead (EMPTY_HEADING). A picker
## shows the Bundled heading alone, and only when other maps come before it. With
## `sticky_headings` (the title) "Your maps" is not in the flow: the owner shows top_section(),
## the heading of the section at the grid's top, over the clip, so a section stays named while
## its cards scroll.
##
## A line is as tall as a map card (every map card at one width is one height): the lead is
## asked to fit that height (its fit_row(), where New map's face takes up the difference), so no
## card is stretched and a selected card's caption band hugs its two lines.

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
## The section at the grid's top changed (top_section(): its heading's words, or "").
signal top_section_changed(words: String)

const GAP := 12
## The widest a card grows by default; past it the grid adds a column.
const MAX_CARD_WIDTH := 400
## Frames a reveal is repeated over, while the flow lays the selected card out.
const REVEAL_FRAMES := 3
const OWN_HEADING := "Your maps"
const BUNDLED_HEADING := "Bundled with TTSim"
## The heading over the Bundled maps when the player has no map of their own yet.
const EMPTY_HEADING := "Or play one that comes with TTSim"
## The room over a section heading's words, with the 4 px step to them more than the GAP under
## them.
const HEADING_ABOVE := 20

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
## Accept (Enter, pad A) on a card that is not selected selects it rather than activating it,
## so a pad can open the map's panel; a second Accept activates (the library).
var select_before_activate: bool = false
## The widest a card grows before the grid adds a column.
var max_card_width: float = MAX_CARD_WIDTH
## The owner names the section at the top (top_section()), so "Your maps" stays out of the flow.
var sticky_headings: bool = false
## Where a lone lead and the Bundled maps under it centre, in the grid's own x (the title: the
## window's middle, so the empty library stands in the middle of the screen and not of its
## column); a negative value centres them in the grid.
var alone_centre: float = -1.0:
	set(value):
		alone_centre = value
		_fit_columns()

var _flow: HFlowContainer
## Pushes the flow right of the grid's middle while the lead stands alone (alone_centre).
var _alone_pad: Control
var _cards: Array[LevelCard] = []
var _selected_path: String = ""
## Cards per line at the current width (_fit_columns).
var _per_line: int = 1
## "Your maps" (library only) and the Bundled maps' heading, each on a line of its own.
var _own_heading: VBoxContainer = null
var _bundled_heading: VBoxContainer = null
var _heading_words: Label = null
## Frames left in the current reveal.
var _reveal_frames := 0
## The words top_section() last reported.
var _top_words := ""


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The CardGrid panel's margins keep a focused card's ring inside the scroll clip.
	theme_type_variation = &"CardGrid"
	# The bar is its handle alone (the theme's lane is clear), shown only while it is wanted.
	ScrollBarFade.attach(self)
	get_v_scroll_bar().value_changed.connect(_check_top_section.unbind(1))
	# The flow beside a pad that is empty but for a lone lead (alone_centre).
	var room := HBoxContainer.new()
	room.name = "Room"
	room.theme_type_variation = &"BoxContainerFlush"
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(room)
	_alone_pad = Control.new()
	_alone_pad.name = "AlonePad"
	_alone_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alone_pad.visible = false
	room.add_child(_alone_pad)
	_flow = HFlowContainer.new()
	_flow.name = "Flow"
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_flow.add_theme_constant_override("h_separation", GAP)
	_flow.add_theme_constant_override("v_separation", GAP)
	_flow.resized.connect(content_resized.emit)
	_flow.resized.connect(_check_top_section)
	room.add_child(_flow)


func _ready() -> void:
	resized.connect(_fit_columns)


func refresh() -> void:
	for card in _cards:
		_flow.remove_child(card)
		card.queue_free()
	_cards.clear()
	if lead != null and lead.get_parent() == null:
		_flow.add_child(lead)
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
		# A card keeps its own height; the line is that tall (the lead fits it, _fit_columns).
		card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		card.selected.connect(_on_card_selected)
		card.activated.connect(_on_card_activated)
		card.action_requested.connect(_on_card_action)
		card.rename_committed.connect(_on_card_rename)
		_flow.add_child(card)
		_cards.append(card)
	_place_own_heading()
	_place_bundled_heading(first_bundled)
	_fit_columns()
	_apply_selection()
	_check_top_section()
	levels_changed.emit()


## Runs a card action on `info` as its own menu would ("duplicate", "delete", "edit",
## "edit_map"): the title's map panel's "..." menu acts through this.
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


## The section headings' words in the flow, in order (for tests and the contrast walk).
func headings() -> Array[Label]:
	var out: Array[Label] = []
	for heading: VBoxContainer in [_own_heading, _bundled_heading]:
		if heading != null and heading.visible:
			out.append(heading.get_node("Words") as Label)
	return out


## A section heading: its words in the heading face (ink on the sky, which every mood keeps at
## 4.5:1 or better: BackdropPaint.ink_reads_on) on a line of its own, HEADING_ABOVE over them
## and the flow's GAP under them.
func _heading(node_name: String) -> VBoxContainer:
	var heading := VBoxContainer.new()
	heading.name = node_name
	heading.theme_type_variation = &"BoxContainerTight"
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var above := Control.new()
	above.name = "Above"
	above.custom_minimum_size.y = HEADING_ABOVE
	above.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(above)
	var words := Label.new()
	words.name = "Words"
	words.theme_type_variation = &"Heading"
	heading.add_child(words)
	_flow.add_child(heading)
	return heading


## "Your maps" first in the library, over New map and the player's maps; none in a picker, over
## an empty library, or with sticky_headings (the owner shows it over the clip). The first line
## of the grid needs no room above it.
func _place_own_heading() -> void:
	if lead == null:
		return
	if _own_heading == null:
		_own_heading = _heading("OwnHeading")
		(_own_heading.get_node("Words") as Label).text = OWN_HEADING
		(_own_heading.get_node("Above") as Control).visible = false
	_own_heading.visible = own_card_count() > 0 and not sticky_headings
	_flow.move_child(_own_heading, 0)


## The heading of the section at the grid's top, for an owner that shows it over the clip
## (sticky_headings): "Your maps" until the Bundled heading's words have scrolled up to the
## clip, then that heading's; "" over an empty library (its one heading scrolls with the cards)
## and in a picker.
func top_section() -> String:
	if lead == null or own_card_count() == 0:
		return ""
	if _bundled_heading != null and _bundled_heading.visible:
		var words := _bundled_heading.get_node("Words") as Control
		if _bundled_heading.position.y + words.position.y <= float(scroll_vertical):
			return BUNDLED_HEADING
	return OWN_HEADING


func _check_top_section() -> void:
	var words := top_section()
	if words != _top_words:
		_top_words = words
		top_section_changed.emit(words)


## The heading before the first Bundled card, or hidden with none, or in a picker when every
## map is Bundled (nothing to set them apart from). Over an empty library it offers the Bundled
## maps instead (EMPTY_HEADING), centred under the lone New map card.
func _place_bundled_heading(first_bundled: LevelCard) -> void:
	if first_bundled == null or (lead == null and first_bundled == _cards[0]):
		if _bundled_heading != null:
			_bundled_heading.visible = false
		return
	if _bundled_heading == null:
		_bundled_heading = _heading("BundledHeading")
		_heading_words = _bundled_heading.get_node("Words") as Label
	var own := own_card_count() > 0
	_heading_words.text = BUNDLED_HEADING if own else EMPTY_HEADING
	_heading_words.horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_LEFT if own else HORIZONTAL_ALIGNMENT_CENTER
	)
	_bundled_heading.visible = true
	# From the end, so taking it out shifts nothing before the card it goes in front of.
	_flow.move_child(_bundled_heading, -1)
	_flow.move_child(_bundled_heading, first_bundled.get_index())


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


## Scrolls the grid so the selected card is in view, over the next REVEAL_FRAMES frames while
## the flow lays it out.
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
	scroll_vertical = roundi(
		reveal_scroll(float(scroll_vertical), _reveal_top(card), bottom, _view_height())
	)


## Where a reveal of `card` starts: its top, or the top of the section heading directly over
## its line, so a card on a section's first line never stands under a heading scrolled away.
func _reveal_top(card: LevelCard) -> float:
	var top := card.position.y
	for heading: VBoxContainer in [_own_heading, _bundled_heading]:
		if heading == null or not heading.visible:
			continue
		var under := heading.position.y + heading.size.y + float(GAP)
		if absf(under - top) < 1.0:
			return heading.position.y
	return top


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


## The number of columns for a grid `span` wide inside its margins (the gaps included): enough
## that no card passes `widest`, never fewer than `fewest`. Pure.
static func columns_for(span: float, widest: float, fewest: int) -> int:
	return maxi(fewest, ceili((span + float(GAP)) / (widest + float(GAP))))


func _fit_columns() -> void:
	if columns <= 0 or size.x <= 0.0:
		return
	# Always reserve the vertical scrollbar's width so the column count does not
	# flip when the bar appears (a visible-only rule oscillates at the boundary:
	# narrower cards are shorter, which can hide the bar, which widens them again).
	var reserved := get_v_scroll_bar().get_combined_minimum_size().x
	reserved += get_theme_stylebox(&"panel").get_minimum_size().x
	# A wide grid adds columns rather than stretch a card past max_card_width (S5).
	var count := columns_for(size.x - reserved, max_card_width, columns)
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
	# A line is a map card's height: the lead fits it (0: its own height, alone).
	if lead != null and lead.has_method(&"fit_row"):
		lead.call(&"fit_row", 0.0 if alone or _cards.is_empty() else _cards[0].height_for(width))
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER if alone else FlowContainer.ALIGNMENT_BEGIN
	var pad := 0.0
	if alone and alone_centre >= 0.0:
		var left := get_theme_stylebox(&"panel").get_margin(SIDE_LEFT)
		var narrowest := lead.get_combined_minimum_size().x if lead != null else 0.0
		# The room the scroll gives the flow: its bar takes a lane only while it shows.
		var bar := get_v_scroll_bar()
		var room := size.x - get_theme_stylebox(&"panel").get_minimum_size().x
		room -= bar.get_combined_minimum_size().x if bar.visible else 0.0
		pad = alone_pad(alone_centre - left, room, narrowest)
	_alone_pad.custom_minimum_size.x = pad
	_alone_pad.visible = pad > 0.0
	for wide: Control in [_own_heading, _bundled_heading]:
		if wide != null:
			wide.custom_minimum_size.x = size.x - reserved - pad


## The pad before a flow `span` wide whose centred lines should centre on `centre` (both from
## the flow's left): twice the distance from the flow's middle, so the narrowed flow's middle
## is `centre`; none when `centre` is left of the middle, and never so much that the flow is
## narrower than `narrowest`. Pure.
static func alone_pad(centre: float, span: float, narrowest: float) -> float:
	var pad := 2.0 * (centre - span * 0.5)
	return clampf(floorf(pad), 0.0, maxf(span - narrowest, 0.0))


## Cards per line at the current width.
func per_line() -> int:
	return _per_line


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
