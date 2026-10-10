class_name MapDetailStrip
extends PanelContainer

## The selected map's detail strip, on a paper sheet of its own directly under its card's row
## in the library (LevelGrid places it, at most 960 wide and under its card): not a modal, so
## the library stays where it was and Tab, arrows and the pad reach it like any card. Its
## picture, then one column: the map's words, its facts, and right after them what can be done
## with it, so Play and Host stand by the map they act on.
##
## The words edit in place: the name, the description and the author are fields that read as
## text until clicked (flat LineEdits, each with its placeholder saying what goes there); the
## pointer over one, or the focus in it, shows its well, the cue that it can be typed in. The
## author reads "by Hannah" at the description's end. Enter saves the one field through
## LevelManager.update_meta (an empty name is refused and reverts, so a card never goes blank);
## Escape reverts it and gives the focus back to Play; leaving a field without Enter reverts it
## too, as a card's rename does. A map with no folder (an old single-file level) cannot be
## edited here and says so in its tooltip. Then the facts derived from disk (LibraryFacts): the
## source chip, the size, the tokens and when it was last played here, and, when Blender has
## written the map's source since (MapImport.is_updated_in_blender), "Updated in Blender" on a
## lake chip.
##
## The actions, one row of one height: Play (solo; the strip's lead, Framed: Host on the Play
## together card is the screen's one fill, C5), Host with this map (it opens a room with this
## map on the shelf), Edit map (authoring; a Bundled map cannot be edited and shows none),
## Reload from Blender while the source is newer (reachable without the menu); "..." at the
## strip's top right holds Set up tokens (the Level Editor), Duplicate, Replace map file...
## (the file picker, then the import check and Replace, as a drop on the card) and Delete. The
## menu opens leftward from it over the words, inside the strip and clear of Edit map.

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
const PICTURE_SIZE := Vector2(224, 126)
## Every action in the strip is one height (S6's controls).
const ACTION_HEIGHT := float(UiActions.SECONDARY_HEIGHT)
const NAME_HINT := "Name this map"
const DESCRIPTION_HINT := "Add a description"
const AUTHOR_HINT := "Add who made it"
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
## The fields, by the update_meta key each saves.
const FIELDS := ["name", "description", "author"]

## Saves `changes` for a level folder: func(folder: String, changes: Dictionary) -> bool.
var update_meta: Callable = LevelManager.update_meta
## Whether Blender wrote a folder's source since: func(folder: String) -> bool.
var is_updated: Callable = MapImport.is_updated_in_blender
## A map's footprint in feet: func(info: Dictionary) -> Vector2.
var footprint: Callable = LibraryFacts.footprint_ft
## Now, in unix seconds; tests pin it.
var clock: Callable = func() -> int: return int(Time.get_unix_time_from_system())

var info: Dictionary = {}
var picture_well: Panel
var name_edit: LineEdit
var description_edit: LineEdit
var author_edit: LineEdit
## "by", before the author while there is one.
var by_label: Label
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

var _picture_box: HBoxContainer
var _name_line: HBoxContainer
var _edits := {}


func _init() -> void:
	name = "MapDetailStrip"
	# A picture on a card of its own, as the New map card is, inside a card's text margin.
	theme_type_variation = &"PictureCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.theme_type_variation = &"CardText"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var row := HBoxContainer.new()
	row.name = "Row"
	row.theme_type_variation = &"BoxContainerSpaced"
	margin.add_child(row)
	_picture_box = HBoxContainer.new()
	_picture_box.name = "PictureBox"
	_picture_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_picture_box)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.theme_type_variation = &"BoxContainerTight"
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)
	_build_words(column)
	_build_actions(column)


func _build_words(column: VBoxContainer) -> void:
	# The name, and "..." at the strip's top right, its menu opening leftward over the words.
	_name_line = HBoxContainer.new()
	_name_line.name = "NameLine"
	_name_line.theme_type_variation = &"BoxContainerTight"
	_name_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(_name_line)
	name_edit = _field("Name", NAME_HINT, _name_line)
	name_edit.theme_type_variation = &"TitleField"
	# The description, then "by" and the author at its end, on one line.
	var line := HBoxContainer.new()
	line.name = "DescriptionLine"
	line.theme_type_variation = &"BoxContainerTight"
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(line)
	description_edit = _field("Description", DESCRIPTION_HINT, line)
	by_label = Label.new()
	by_label.name = "By"
	by_label.text = "by"
	by_label.theme_type_variation = &"Caption"
	by_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(by_label)
	author_edit = _field("Author", AUTHOR_HINT, line)
	author_edit.size_flags_horizontal = Control.SIZE_FILL
	author_edit.expand_to_text_length = true
	author_edit.custom_minimum_size.x = 120
	_edits = {"name": name_edit, "description": description_edit, "author": author_edit}
	# The facts on one line, a spaced step apart (they fit the 960 strip's column).
	var facts := HBoxContainer.new()
	facts.name = "Facts"
	facts.theme_type_variation = &"BoxContainerSpaced"
	facts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(facts)
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


func _build_actions(column: VBoxContainer) -> void:
	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.theme_type_variation = &"BoxContainerTight"
	column.add_child(actions)
	# Framed: the strip's lead reads first without taking the screen's one fill.
	play_button = UiActions.primary("Play", "player-play", "", actions, &"Framed")
	play_button.tooltip_text = "Play this map on your own"
	play_button.pressed.connect(func() -> void: play_requested.emit(info))
	host_button = UiActions.secondary("Host with this map", "network", actions)
	host_button.name = "HostWithThisMap"
	host_button.tooltip_text = HOST_TIP
	host_button.pressed.connect(func() -> void: host_requested.emit(info))
	edit_button = UiActions.secondary("Edit map", "brush", actions)
	edit_button.tooltip_text = "Shape, paint and dress this map"
	edit_button.pressed.connect(func() -> void: edit_map_requested.emit(info))
	reload_button = UiActions.secondary(RELOAD, LibraryFacts.UPDATED_ICON, actions)
	reload_button.name = "Reload"
	reload_button.tooltip_text = RELOAD_TIP
	reload_button.pressed.connect(func() -> void: action_requested.emit(info, ACTION_RELOAD))
	more_button = Button.new()
	more_button.name = "More"
	more_button.icon = IconButton.load_icon("dots-vertical")
	more_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	more_button.tooltip_text = "More"
	more_button.theme_type_variation = &"Secondary"
	more_button.pressed.connect(open_menu)
	more_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_name_line.add_child(more_button)
	menu = PopupMenu.new()
	menu.name = "Menu"
	menu.id_pressed.connect(_on_menu_id)
	more_button.add_child(menu)
	for button: Button in [play_button, host_button, edit_button, reload_button, more_button]:
		button.custom_minimum_size.y = ACTION_HEIGHT
	more_button.custom_minimum_size.x = ACTION_HEIGHT


func _field(field_name: String, hint: String, parent: Control) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = field_name
	edit.placeholder_text = hint
	edit.flat = true
	edit.select_all_on_focus = true
	edit.tooltip_text = EDIT_TIP
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(_text: String) -> void: commit(edit))
	edit.focus_entered.connect(_show_cue.bind(edit))
	edit.focus_exited.connect(
		func() -> void:
			revert(edit)
			_show_cue(edit)
	)
	edit.mouse_entered.connect(_show_cue.bind(edit, true))
	edit.mouse_exited.connect(_show_cue.bind(edit))
	edit.gui_input.connect(_on_field_input.bind(edit))
	parent.add_child(edit)
	return edit


## The cue that a field can be typed in: its well, while the pointer is over it or it has the
## focus (flat, reading as text, otherwise).
func _show_cue(edit: LineEdit, hovered := false) -> void:
	edit.flat = not (edit.editable and (hovered or edit.has_focus()))


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
	var folder := String(info.get("folder", ""))
	var editable := folder != ""
	for key: String in FIELDS:
		var edit: LineEdit = _edits[key]
		edit.text = String(info.get(key, ""))
		edit.editable = editable
		edit.tooltip_text = EDIT_TIP if editable else NO_FOLDER_TIP
		_show_cue(edit)
	by_label.visible = author_edit.text != ""
	_show_picture()
	var source := LibraryFacts.source_of(info)
	source_label.text = String(LibraryFacts.SOURCE_LABELS[source])
	size_label.text = LibraryFacts.size_text(footprint.call(info))
	size_label.visible = size_label.text != ""
	tokens_label.text = LibraryFacts.tokens_text(int(info.get("token_count", 0)))
	played_label.text = LibraryFacts.played_text(int(info.get("played_at", 0)), clock.call())
	edit_button.visible = source != LibraryFacts.SOURCE_BUNDLED
	var updated := can_reload() and bool(is_updated.call(folder))
	updated_chip.visible = updated
	reload_button.visible = updated


## Whether the map shown has a Blender source to reload: a folder map from Blender, edited
## here or not.
func can_reload() -> bool:
	var source := LibraryFacts.source_of(info)
	var blender := source == LibraryFacts.SOURCE_BLENDER or source == LibraryFacts.SOURCE_DRESSED
	return String(info.get("folder", "")) != "" and blender


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
		PICTURE_SIZE, texture, key, String(info.get("environment_preset", ""))
	)
	picture_well.name = "Picture"
	_picture_box.add_child(picture_well)


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


## Opens "..." inside the strip: from the button at its top right, leftward over the words, so
## it never covers the actions row and Edit map in it. Popups are placed in the window's
## pixels (get_screen_position, as a card's own menu is), and its width is known once shown.
func open_menu() -> void:
	menu.clear()
	for id in menu_items():
		menu.add_item(String(MENU_LABELS[id]), id)
	var corner := Vector2i(more_button.get_screen_position())
	menu.popup(Rect2i(corner, Vector2i.ZERO))
	menu.position = Vector2i(corner.x - menu.size.x - 4, corner.y)


func _on_menu_id(id: int) -> void:
	if MENU_ACTIONS.has(id):
		action_requested.emit(info, MENU_ACTIONS[id])


## Saves `edit`'s field through update_meta; a refused save (an empty name, a write that
## failed) puts the saved text back.
func commit(edit: LineEdit) -> void:
	var key := _key_of(edit)
	var saved := String(info.get(key, ""))
	var typed := edit.text.strip_edges()
	if typed == saved:
		edit.text = saved
		edit.release_focus()
		return
	if bool(update_meta.call(String(info.get("folder", "")), {key: typed})):
		info[key] = typed
		edit.text = typed
		meta_saved.emit(info)
	else:
		edit.text = saved
	by_label.visible = author_edit.text != ""
	edit.release_focus()


## Puts `edit`'s saved text back (Escape, or leaving the field without Enter).
func revert(edit: LineEdit) -> void:
	edit.text = String(info.get(_key_of(edit), ""))


func _key_of(edit: LineEdit) -> String:
	for key: String in _edits:
		if _edits[key] == edit:
			return key
	return ""


## Escape reverts the field and hands the focus back to Play, and is claimed so it never
## reaches a screen behind.
func _on_field_input(event: InputEvent, edit: LineEdit) -> void:
	if event.is_action_pressed("ui_cancel"):
		revert(edit)
		edit.accept_event()
		play_button.grab_focus()
