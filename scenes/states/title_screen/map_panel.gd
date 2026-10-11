class_name MapPanel
extends PanelContainer

## The selected map's panel, pinned at the right of the library (TitleScreen): one place and
## one shape for every map, whatever its source (UI_TASTE verdict 2026-10-10). It is a paper
## card as the map cards are, always WIDTH wide, as tall as what it shows (scrolling inside when
## a short canvas cannot hold it), and not a modal: Tab, arrows and the pad reach it like any
## card. Top to bottom: the map's picture, large at 16:9 (its thumbnail, or its placeholder);
## its name in the title face; its description; "by" its author; the facts derived from disk
## (LibraryFacts: the source chip, the size, the tokens, when it was last played here, and
## "Updated in Blender" on a lake chip when Blender has written its source since); then what can
## be done with it.
##
## The words read as text. On a map of the player's own they edit in place: the pointer over a
## field, or the focus on it, shows its well; a click or Accept opens it for typing (the hint
## shows only then, never a grey placeholder at rest). Enter saves the one field through
## LevelManager.update_meta (an empty name is refused and reverts, so a card never goes blank);
## Escape reverts it and gives the focus back to its words; leaving a field without Enter
## reverts it too, as a card's rename does. An empty description or author takes no line: one
## quiet "Add details" opens the first empty one. A Bundled map, and an old single-file level
## with no folder, show the same fields in the same order as plain text, the empty ones absent.
##
## The actions, every one a control of one height: Play (solo; the panel's lead, Framed: Host on
## the Play together card is the screen's one fill, C5) and Host with this map (a room with this
## map on its shelf) on the first line; Edit map (authoring; absent for a Bundled map) and "..."
## at its end on the second; Reload from Blender on a line of its own, only while the source is
## newer. "..." holds Set up tokens
## (the Level Editor), Duplicate, Replace map file... (not for a Bundled map: the file picker,
## then the import check and Replace, as a drop on the card) and Delete.

signal play_requested(info: Dictionary)
signal host_requested(info: Dictionary)
signal edit_map_requested(info: Dictionary)
## A "..." item or Reload: ACTION_SET_UP, ACTION_DUPLICATE, ACTION_REPLACE, ACTION_DELETE or
## ACTION_RELOAD.
signal action_requested(info: Dictionary, action: StringName)
## A field was saved: `info` with the change applied.
signal meta_saved(info: Dictionary)

enum { MENU_SET_UP, MENU_DUPLICATE, MENU_REPLACE, MENU_DELETE }

const ACTION_SET_UP := &"edit"
const ACTION_DUPLICATE := &"duplicate"
const ACTION_DELETE := &"delete"
const ACTION_RELOAD := &"reload"
const ACTION_REPLACE := &"replace_file"
## The panel's width on every canvas (TitleScreen keeps at least three columns of cards beside
## it on a 1280x720 canvas).
const WIDTH := 360.0
const PICTURE_ASPECT := 16.0 / 9.0
## The words' and actions' inset from the inside of the paper (the picture's 4 px inset, as a
## card's): room for a field's well to reach out round its words.
const TEXT_INSET := 12
## Every action in the panel is one height (S6's controls).
const ACTION_HEIGHT := float(UiActions.SECONDARY_HEIGHT)
const NAME_HINT := "Name this map"
const DESCRIPTION_HINT := "A line about this place"
const AUTHOR_HINT := "Who made it"
const ADD_DETAILS := "Add details"
const ADD_DETAILS_TIP := "Add a description and who made it"
const EDIT_TIP := "Click to edit; Enter saves, Escape puts it back"
const NO_FOLDER_TIP := "This older map cannot be renamed here"
const HOST_TIP := "Open a room with this map on its shelf"
const RELOAD := "Reload from Blender"
const RELOAD_TIP := "Bring in the newer file from Blender, through the import check"
const REPLACE_FILE := "Replace map file..."
const MENU_LABELS := {
	MENU_SET_UP: TitleScreen.SET_UP_TOKENS,
	MENU_DUPLICATE: "Duplicate",
	MENU_REPLACE: REPLACE_FILE,
	MENU_DELETE: "Delete",
}
const MENU_ACTIONS := {
	MENU_SET_UP: ACTION_SET_UP,
	MENU_DUPLICATE: ACTION_DUPLICATE,
	MENU_REPLACE: ACTION_REPLACE,
	MENU_DELETE: ACTION_DELETE,
}
## The fields, by the update_meta key each saves, in the order they stand.
const FIELDS := ["name", "description", "author"]
const HINTS := {"name": NAME_HINT, "description": DESCRIPTION_HINT, "author": AUTHOR_HINT}

## Saves `changes` for a level folder: func(folder: String, changes: Dictionary) -> bool.
var update_meta: Callable = LevelManager.update_meta
## Whether Blender wrote a folder's source since: func(folder: String) -> bool.
var is_updated: Callable = MapImport.is_updated_in_blender
## A map's footprint in feet: func(info: Dictionary) -> Vector2.
var footprint: Callable = LibraryFacts.footprint_ft
## Now, in unix seconds; tests pin it.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())

## The tallest the panel stands (its column's height); 0 for as tall as what it shows.
var max_height := 0.0
var info: Dictionary = {}
var picture_well: Panel
## Each field as it reads (a wrapping label) and as it is typed in (a line edit, shown only
## while it is open).
var name_label: Label
var description_label: Label
var author_label: Label
var name_edit: LineEdit
var description_edit: LineEdit
var author_edit: LineEdit
var add_details_button: Button
var source_label: Label
var size_label: Label
var tokens_label: Label
var played_label: Label
## "Updated in Blender" and Reload from Blender, shown while the source is newer.
var updated_chip: PanelContainer
var reload_button: Button
var play_button: Button
var host_button: Button
var edit_button: Button
var more_button: Button
var menu: PopupMenu

var _scroll: ScrollContainer
var _column: VBoxContainer
var _picture_box: Control
var _second_row: HBoxContainer
var _push: Control
var _actions: VBoxContainer
var _labels := {}
var _edits := {}
var _cues := {}
var _editable := false
## The fields under the pointer.
var _hovered := {}


func _init() -> void:
	name = "MapPanel"
	theme_type_variation = &"PictureCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.x = WIDTH
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	# The picture and the words scroll when a short canvas cannot hold them; the actions stay
	# pinned at the foot, always in view.
	var frame := VBoxContainer.new()
	frame.name = "Frame"
	frame.theme_type_variation = &"BoxContainerSpaced"
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	frame.add_child(_scroll)
	_column = VBoxContainer.new()
	_column.name = "Column"
	_column.theme_type_variation = &"BoxContainerSpaced"
	_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.minimum_size_changed.connect(fit_height)
	_scroll.add_child(_column)
	_picture_box = Control.new()
	_picture_box.name = "PictureBox"
	_picture_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_box.resized.connect(_fit_picture)
	_column.add_child(_picture_box)
	# The words stand TEXT_INSET in from the paper's edge, room for a field's well to reach out.
	var body := VBoxContainer.new()
	body.name = "Body"
	body.theme_type_variation = &"BoxContainerSpaced"
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_column.add_child(_inset(body, &"PanelText"))
	_build_words(body)
	_build_facts(body)
	_actions = VBoxContainer.new()
	_actions.name = "Actions"
	_actions.theme_type_variation = &"BoxContainerTight"
	_actions.minimum_size_changed.connect(fit_height)
	frame.add_child(_inset(_actions, &"PanelTextFoot"))
	_build_actions(_actions)


## `child` in a margin in from the paper's sides (the theme's PanelText, or PanelTextFoot with
## room under it too).
func _inset(child: Control, margins: StringName) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.name = child.name + "Margin"
	margin.theme_type_variation = margins
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(child)
	return margin


func _build_words(body: VBoxContainer) -> void:
	var words := VBoxContainer.new()
	words.name = "Words"
	words.theme_type_variation = &"BoxContainerTight"
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(words)
	name_label = _field("name", &"Title", &"TitleField", words)
	name_edit = _edits.name
	description_label = _field("description", &"Body", &"InlineField", words)
	description_edit = _edits.description
	author_label = _field("author", &"Caption", &"InlineField", words)
	author_edit = _edits.author
	add_details_button = Button.new()
	add_details_button.name = "AddDetails"
	add_details_button.text = ADD_DETAILS
	add_details_button.icon = IconButton.load_icon("plus")
	add_details_button.theme_type_variation = &"Ghost"
	add_details_button.tooltip_text = ADD_DETAILS_TIP
	add_details_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_details_button.pressed.connect(_on_add_details)
	words.add_child(add_details_button)


## A field `key`: its label (in `label_type`) and its line edit (in `edit_type`), one shown at a
## time, on the cue that shows its well (FieldCue). Returns the label; the edit is in _edits.
func _field(key: String, label_type: StringName, edit_type: StringName, parent: Control) -> Label:
	var cue := PanelContainer.new()
	cue.name = key.capitalize() + "Cue"
	cue.theme_type_variation = &"FieldCue"
	cue.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cue)
	_cues[key] = cue
	parent = cue
	var label := Label.new()
	label.name = key.capitalize()
	label.theme_type_variation = label_type
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_entered.connect(_on_hover.bind(key, true))
	label.mouse_exited.connect(_on_hover.bind(key, false))
	label.focus_entered.connect(_show_cue.bind(key))
	label.focus_exited.connect(_show_cue.bind(key))
	label.gui_input.connect(_on_label_input.bind(key))
	parent.add_child(label)
	var edit := LineEdit.new()
	edit.name = key.capitalize() + "Edit"
	edit.theme_type_variation = edit_type
	edit.select_all_on_focus = true
	edit.visible = false
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(_text: String) -> void: commit(edit))
	edit.focus_exited.connect(_on_edit_left.bind(key))
	edit.gui_input.connect(_on_field_input.bind(edit))
	parent.add_child(edit)
	_labels[key] = label
	_edits[key] = edit
	return label


func _build_facts(body: VBoxContainer) -> void:
	# The facts flow onto a second line when they do not fit the panel's width.
	var facts := HFlowContainer.new()
	facts.name = "Facts"
	facts.theme_type_variation = &"FactsFlow"
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(facts)
	var chip := PanelContainer.new()
	chip.name = "Source"
	chip.theme_type_variation = &"Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	facts.add_child(chip)
	source_label = _caption("SourceLabel", chip)
	size_label = _caption("Size", facts)
	tokens_label = _caption("Tokens", facts)
	played_label = _caption("Played", facts)
	updated_chip = LevelCard.state_chip(LibraryFacts.UPDATED, LibraryFacts.UPDATED_ICON)
	updated_chip.name = "Updated"
	updated_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	facts.add_child(updated_chip)


func _build_actions(actions: VBoxContainer) -> void:
	var first := HBoxContainer.new()
	first.name = "First"
	first.theme_type_variation = &"BoxContainerTight"
	actions.add_child(first)
	# Framed: the panel's lead reads first without taking the screen's one fill.
	play_button = UiActions.primary("Play", "player-play", "", first, &"Framed")
	play_button.tooltip_text = "Play this map on your own"
	play_button.pressed.connect(func() -> void: play_requested.emit(info))
	host_button = UiActions.secondary("Host with this map", "network", first)
	host_button.name = "HostWithThisMap"
	host_button.tooltip_text = HOST_TIP
	host_button.pressed.connect(func() -> void: host_requested.emit(info))
	_second_row = HBoxContainer.new()
	_second_row.name = "Second"
	_second_row.theme_type_variation = &"BoxContainerTight"
	actions.add_child(_second_row)
	edit_button = UiActions.secondary("Edit map", "brush", _second_row)
	edit_button.tooltip_text = "Shape, paint and dress this map"
	edit_button.pressed.connect(func() -> void: edit_map_requested.emit(info))
	# With no Edit map (a Bundled map) "..." keeps its place at the line's end.
	var push := Control.new()
	push.name = "Push"
	push.mouse_filter = Control.MOUSE_FILTER_IGNORE
	push.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_second_row.add_child(push)
	more_button = Button.new()
	more_button.name = "More"
	more_button.icon = IconButton.load_icon("dots-vertical")
	more_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	more_button.tooltip_text = "More"
	more_button.theme_type_variation = &"Secondary"
	more_button.pressed.connect(open_menu)
	_second_row.add_child(more_button)
	menu = PopupMenu.new()
	menu.name = "Menu"
	menu.id_pressed.connect(_on_menu_id)
	more_button.add_child(menu)
	_push = push
	# Reload from Blender on a line of its own, only while the source is newer.
	reload_button = UiActions.secondary(RELOAD, LibraryFacts.UPDATED_ICON, actions)
	reload_button.name = "Reload"
	reload_button.tooltip_text = RELOAD_TIP
	reload_button.pressed.connect(func() -> void: action_requested.emit(info, ACTION_RELOAD))
	for button: Button in [play_button, host_button, edit_button, reload_button]:
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.size_flags_stretch_ratio = 1.8
	for button: Button in [play_button, host_button, edit_button, reload_button, more_button]:
		button.custom_minimum_size.y = ACTION_HEIGHT
	more_button.custom_minimum_size.x = ACTION_HEIGHT


func _caption(node_name: String, parent: Control) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = &"Caption"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label


## Shows the map `level_info` describes (a library entry with "played_at", LibraryFacts).
func show_map(level_info: Dictionary) -> void:
	info = level_info.duplicate()
	var source := LibraryFacts.source_of(info)
	_editable = String(info.get("folder", "")) != "" and source != LibraryFacts.SOURCE_BUNDLED
	for key: String in FIELDS:
		var edit: LineEdit = _edits[key]
		edit.visible = false
		edit.text = String(info.get(key, ""))
		_refresh_label(key)
	name_label.tooltip_text = EDIT_TIP if _editable else ""
	if String(info.get("folder", "")) == "":
		name_label.tooltip_text = NO_FOLDER_TIP
	_show_picture()
	source_label.text = String(LibraryFacts.SOURCE_LABELS[source])
	size_label.text = LibraryFacts.size_text(footprint.call(info))
	size_label.visible = size_label.text != ""
	tokens_label.text = LibraryFacts.tokens_text(int(info.get("token_count", 0)))
	played_label.text = LibraryFacts.played_text(int(info.get("played_at", 0)), clock.call())
	edit_button.visible = source != LibraryFacts.SOURCE_BUNDLED
	var updated := can_reload() and bool(is_updated.call(String(info.get("folder", ""))))
	updated_chip.visible = updated
	reload_button.visible = updated
	_push.visible = not edit_button.visible
	_scroll.scroll_vertical = 0
	fit_height()


## Whether the map shown has a Blender source to reload: a folder map from Blender, edited
## here or not.
func can_reload() -> bool:
	var source := LibraryFacts.source_of(info)
	var blender := source == LibraryFacts.SOURCE_BLENDER or source == LibraryFacts.SOURCE_DRESSED
	return String(info.get("folder", "")) != "" and blender


## Whether the map shown can have its words edited here: a folder map that is not Bundled.
func is_editable() -> bool:
	return _editable


## The field `key`'s label as the saved text says: its words (the author as "by" them), shown
## when there are any (the name always); on a map of the player's own it takes the pointer and
## the focus, the cue that it can be typed in. "Add details" shows while a field is empty.
func _refresh_label(key: String) -> void:
	var label: Label = _labels[key]
	var words := String(info.get(key, ""))
	label.text = ("by " + words) if key == "author" and words != "" else words
	label.visible = words != "" or key == "name"
	(_cues[key] as Control).visible = label.visible
	label.mouse_filter = Control.MOUSE_FILTER_STOP if _editable else Control.MOUSE_FILTER_IGNORE
	label.focus_mode = Control.FOCUS_ALL if _editable else Control.FOCUS_NONE
	label.mouse_default_cursor_shape = (Control.CURSOR_IBEAM if _editable else Control.CURSOR_ARROW)
	if key != "name":
		label.tooltip_text = EDIT_TIP if _editable else ""
	_show_cue(key)
	var empty := String(info.get("description", "")) == "" or String(info.get("author", "")) == ""
	add_details_button.visible = _editable and empty


## The cue that a field can be typed in: its well reaching out round its words while the
## pointer is over them or they have the focus (FieldCueLit), nothing at rest (FieldCue). The
## well takes no room, so the words never move.
func _show_cue(key: String) -> void:
	var label: Label = _labels[key]
	var lit := _editable and label.visible and (label.has_focus() or _hovered.has(key))
	(_cues[key] as PanelContainer).theme_type_variation = &"FieldCueLit" if lit else &"FieldCue"


func _on_hover(key: String, inside: bool) -> void:
	if inside:
		_hovered[key] = true
	else:
		_hovered.erase(key)
	_show_cue(key)


## Whether field `key`'s well shows (the pointer over it or the focus on it).
func cue_shown(key: String) -> bool:
	return (_cues[key] as PanelContainer).theme_type_variation == &"FieldCueLit"


## Opens field `key` for typing: its line edit in its label's place, with the saved text (or
## the hint in an empty one) and the focus.
func begin_edit(key: String) -> void:
	if not _editable:
		return
	var label: Label = _labels[key]
	var edit: LineEdit = _edits[key]
	edit.text = String(info.get(key, ""))
	edit.placeholder_text = String(HINTS[key])
	label.visible = false
	var cue: PanelContainer = _cues[key]
	cue.visible = true
	cue.theme_type_variation = &"FieldCue"
	edit.visible = true
	edit.grab_focus()
	edit.edit()


## Closes field `key`: its label again, as the saved text says.
func _end_edit(key: String) -> void:
	(_edits[key] as LineEdit).visible = false
	_refresh_label(key)


func _on_label_input(event: InputEvent, key: String) -> void:
	var click := event as InputEventMouseButton
	var pressed := click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT
	if pressed or event.is_action_pressed("ui_accept"):
		(_labels[key] as Label).accept_event()
		begin_edit(key)


## "Add details": the first empty one of the description and the author, open for typing.
func _on_add_details() -> void:
	for key: String in ["description", "author"]:
		if String(info.get(key, "")) == "":
			begin_edit(key)
			return


func _on_edit_left(key: String) -> void:
	var edit: LineEdit = _edits[key]
	if not edit.visible:
		return
	revert(edit)
	_end_edit.call_deferred(key)


func _show_picture() -> void:
	for child in _picture_box.get_children():
		_picture_box.remove_child(child)
		child.queue_free()
	var texture: Texture2D = null
	var thumbnail := String(info.get("thumbnail", ""))
	if thumbnail != "":
		var image := Image.load_from_file(ProjectSettings.globalize_path(thumbnail))
		if image != null:
			texture = ImageTexture.create_from_image(image)
	var folder := String(info.get("folder", ""))
	var key := folder if folder != "" else String(info.get("name", ""))
	picture_well = RoomRows.map_well(
		Vector2.ZERO,
		texture,
		key,
		String(info.get("environment_preset", "")),
		String(info.get("name", ""))
	)
	picture_well.name = "Picture"
	picture_well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_picture_box.add_child(picture_well)
	_fit_picture()


## The picture at 16:9 across the panel's width.
func _fit_picture() -> void:
	var height := floorf(_picture_box.size.x / PICTURE_ASPECT)
	if height > 0.0 and not is_equal_approx(_picture_box.custom_minimum_size.y, height):
		_picture_box.custom_minimum_size.y = height


## The panel's height: what it shows, but never past max_height (its column's, when one is
## set), where it scrolls inside instead.
func fit_height() -> void:
	if _actions == null:
		return
	var frame := _scroll.get_parent() as BoxContainer
	var want := _column.get_combined_minimum_size().y + frame.get_theme_constant(&"separation")
	want += (_actions.get_parent() as Control).get_combined_minimum_size().y
	want += get_theme_stylebox(&"panel").get_minimum_size().y
	var height := minf(want, max_height) if max_height > 0.0 else want
	if not is_equal_approx(custom_minimum_size.y, height):
		custom_minimum_size.y = height


## The "..." items for the map shown: Set up tokens, Duplicate and Replace map file... (a
## folder map that is not Bundled), Delete.
func menu_items() -> Array[int]:
	var items: Array[int] = [MENU_SET_UP]
	var folder := String(info.get("folder", ""))
	if folder != "":
		items.append(MENU_DUPLICATE)
		if not LibraryFacts.is_bundled(info):
			items.append(MENU_REPLACE)
	items.append(MENU_DELETE)
	return items


## Opens "..." under its button, its right edge at the button's, inside the panel. Popups are
## placed in the window's pixels (get_screen_position, as a card's own menu is), and its width
## is known once shown.
func open_menu() -> void:
	menu.clear()
	for id in menu_items():
		menu.add_item(String(MENU_LABELS[id]), id)
	var corner := Vector2i(more_button.get_screen_position())
	var below := corner.y + roundi(more_button.size.y * get_viewport().get_final_transform().y.y)
	menu.popup(Rect2i(Vector2i(corner.x, below + 4), Vector2i.ZERO))
	var right := corner.x + roundi(more_button.size.x * get_viewport().get_final_transform().x.x)
	menu.position = Vector2i(right - menu.size.x, below + 4)


func _on_menu_id(id: int) -> void:
	if MENU_ACTIONS.has(id):
		action_requested.emit(info, MENU_ACTIONS[id])


## Saves `edit`'s field through update_meta; a refused save (an empty name, a write that
## failed) puts the saved text back. The field closes either way.
func commit(edit: LineEdit) -> void:
	var key := _key_of(edit)
	var saved := String(info.get(key, ""))
	var typed := edit.text.strip_edges()
	if typed != saved and bool(update_meta.call(String(info.get("folder", "")), {key: typed})):
		info[key] = typed
		meta_saved.emit(info)
	edit.text = String(info.get(key, ""))
	_end_edit(key)
	_focus_after(key)


## Puts `edit`'s saved text back (Escape, or leaving the field without Enter).
func revert(edit: LineEdit) -> void:
	edit.text = String(info.get(_key_of(edit), ""))


func _key_of(edit: LineEdit) -> String:
	for key: String in _edits:
		if _edits[key] == edit:
			return key
	return ""


## Escape reverts the field, closes it and gives the focus back to its words (Play when an
## empty field's words take no line), and is claimed so it never reaches a screen behind.
func _on_field_input(event: InputEvent, edit: LineEdit) -> void:
	if event.is_action_pressed("ui_cancel"):
		var key := _key_of(edit)
		revert(edit)
		edit.accept_event()
		_end_edit(key)
		_focus_after(key)


## The focus back on field `key`'s words, or on Play when an empty field takes no line.
func _focus_after(key: String) -> void:
	var label: Label = _labels[key]
	if label.visible and label.is_inside_tree():
		label.grab_focus()
	elif play_button.is_inside_tree():
		play_button.grab_focus()
