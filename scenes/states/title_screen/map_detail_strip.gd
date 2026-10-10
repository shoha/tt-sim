class_name MapDetailStrip
extends PanelContainer

## The selected map's detail strip, on a paper sheet of its own directly under its card's row
## in the library (LevelGrid places it): not a modal, so the library stays where it was and
## Tab, arrows and the pad reach it like any card. Its picture, then the map's words, then what
## can be done with it.
##
## The words edit in place: the name, the description and the author are fields that read as
## text until clicked (flat LineEdits, each with its placeholder saying what goes there).
## Enter saves the one field through LevelManager.update_meta (an empty name is refused and
## reverts, so a card never goes blank); Escape reverts it and gives the focus back to the
## strip; leaving a field without Enter reverts it too, as a card's rename does. A map with no
## folder (an old single-file level) cannot be edited here and says so in its tooltip. Under
## them, the facts derived from disk (LibraryFacts): the source chip, the size, the tokens
## and when it was last played here.
##
## The actions: Play (solo; the strip's lead, tall and paper: Host on the Play together card is
## the screen's one fill, C5), Host with this map (quiet: it opens a room with this map on the
## shelf, the Host control beside what it acts on), Edit map (authoring; a Bundled map cannot
## be edited and shows none), and "..." with Set up tokens (the Level Editor), Duplicate,
## Delete and, when Blender has written its source since (MapImport.is_updated_in_blender),
## Reload from Blender.

signal play_requested(info: Dictionary)
signal host_requested(info: Dictionary)
signal edit_map_requested(info: Dictionary)
## A "..." item: ACTION_SET_UP, ACTION_DUPLICATE, ACTION_DELETE or ACTION_RELOAD.
signal action_requested(info: Dictionary, action: StringName)
## A field was saved: `info` with the change applied.
signal meta_saved(info: Dictionary)

enum { MENU_SET_UP, MENU_DUPLICATE, MENU_DELETE, MENU_RELOAD }

const ACTION_SET_UP := &"edit"
const ACTION_DUPLICATE := &"duplicate"
const ACTION_DELETE := &"delete"
const ACTION_RELOAD := &"reload"
const PICTURE_SIZE := Vector2(224, 126)
## Play leads the actions, a step taller than the quiet rows under it.
const PLAY_HEIGHT := 48.0
const NAME_HINT := "Name this map"
const DESCRIPTION_HINT := "Add a description"
const AUTHOR_HINT := "Add who made it"
const EDIT_TIP := "Click to edit; Enter saves, Escape puts it back"
const NO_FOLDER_TIP := "This older map cannot be renamed here"
const HOST_TIP := "Open a room with this map on its shelf"
const RELOAD := "Reload from Blender"
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
var source_label: Label
var size_label: Label
var tokens_label: Label
var played_label: Label
var play_button: Button
var host_button: Button
var edit_button: Button
var more_button: MenuButton

var _picture_box: HBoxContainer
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
	_build_words(row)
	_build_actions(row)


func _build_words(row: HBoxContainer) -> void:
	var words := VBoxContainer.new()
	words.name = "Words"
	words.theme_type_variation = &"BoxContainerTight"
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	name_edit = _field("Name", NAME_HINT, words)
	name_edit.theme_type_variation = &"TitleField"
	description_edit = _field("Description", DESCRIPTION_HINT, words)
	# The author shares its line with the facts, so the strip stays as short as its actions.
	var facts := HBoxContainer.new()
	facts.name = "Facts"
	facts.theme_type_variation = &"BoxContainerSpaced"
	words.add_child(facts)
	author_edit = _field("Author", AUTHOR_HINT, facts)
	_edits = {"name": name_edit, "description": description_edit, "author": author_edit}
	var chip := PanelContainer.new()
	chip.name = "Source"
	chip.theme_type_variation = &"Inset"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	facts.add_child(chip)
	source_label = _caption("SourceLabel", chip)
	size_label = _caption("Size", facts)
	tokens_label = _caption("Tokens", facts)
	played_label = _caption("Played", facts)


func _build_actions(row: HBoxContainer) -> void:
	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.theme_type_variation = &"BoxContainerTight"
	actions.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	actions.custom_minimum_size.x = 220
	row.add_child(actions)
	# Framed: the strip's lead reads first without taking the screen's one fill.
	play_button = UiActions.primary("Play", "player-play", "", actions, &"Framed")
	play_button.custom_minimum_size.y = PLAY_HEIGHT
	play_button.tooltip_text = "Play this map on your own"
	play_button.pressed.connect(func() -> void: play_requested.emit(info))
	host_button = UiActions.secondary("Host with this map", "network", actions)
	host_button.name = "HostWithThisMap"
	host_button.tooltip_text = HOST_TIP
	host_button.pressed.connect(func() -> void: host_requested.emit(info))
	var last := HBoxContainer.new()
	last.name = "EditRow"
	last.theme_type_variation = &"BoxContainerTight"
	actions.add_child(last)
	edit_button = UiActions.secondary("Edit map", "brush", last)
	edit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_button.tooltip_text = "Shape, paint and dress this map"
	edit_button.pressed.connect(func() -> void: edit_map_requested.emit(info))
	more_button = MenuButton.new()
	more_button.name = "More"
	more_button.icon = IconButton.load_icon("dots-vertical")
	more_button.tooltip_text = "More"
	more_button.flat = false
	more_button.focus_mode = Control.FOCUS_ALL
	more_button.theme_type_variation = &"Secondary"
	more_button.custom_minimum_size = Vector2(UiActions.SECONDARY_HEIGHT, UiActions.SECONDARY_HEIGHT)
	more_button.about_to_popup.connect(_fill_menu)
	more_button.get_popup().id_pressed.connect(_on_menu_id)
	last.add_child(more_button)


func _field(field_name: String, hint: String, parent: Control) -> LineEdit:
	var edit := LineEdit.new()
	edit.name = field_name
	edit.placeholder_text = hint
	edit.flat = true
	edit.select_all_on_focus = true
	edit.tooltip_text = EDIT_TIP
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text_submitted.connect(func(_text: String) -> void: commit(edit))
	edit.focus_exited.connect(func() -> void: revert(edit))
	edit.gui_input.connect(_on_field_input.bind(edit))
	parent.add_child(edit)
	return edit


func _caption(node_name: String, parent: Control) -> Label:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = &"Caption"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


## Shows the map `level_info` describes (a library entry with "played_at", LibraryFacts).
func show_map(level_info: Dictionary) -> void:
	info = level_info.duplicate()
	var editable := String(info.get("folder", "")) != ""
	for key: String in FIELDS:
		var edit: LineEdit = _edits[key]
		edit.text = String(info.get(key, ""))
		edit.editable = editable
		edit.tooltip_text = EDIT_TIP if editable else NO_FOLDER_TIP
	_show_picture()
	var source := LibraryFacts.source_of(info)
	source_label.text = String(LibraryFacts.SOURCE_LABELS[source])
	size_label.text = LibraryFacts.size_text(footprint.call(info))
	size_label.visible = size_label.text != ""
	tokens_label.text = LibraryFacts.tokens_text(int(info.get("token_count", 0)))
	played_label.text = LibraryFacts.played_text(int(info.get("played_at", 0)), clock.call())
	edit_button.visible = source != LibraryFacts.SOURCE_BUNDLED


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


## The "..." items for the map shown: Set up tokens, Duplicate (a folder map), Delete, and
## Reload from Blender when its source is newer than its copy.
func menu_items() -> Array[int]:
	var items: Array[int] = [MENU_SET_UP]
	var folder := String(info.get("folder", ""))
	if folder != "":
		items.append(MENU_DUPLICATE)
	items.append(MENU_DELETE)
	if folder != "" and LibraryFacts.source_of(info) != LibraryFacts.SOURCE_MADE:
		if bool(is_updated.call(folder)):
			items.append(MENU_RELOAD)
	return items


func _fill_menu() -> void:
	var menu := more_button.get_popup()
	menu.clear()
	var labels := {
		MENU_SET_UP: TitleScreen.SET_UP_TOKENS,
		MENU_DUPLICATE: "Duplicate",
		MENU_DELETE: "Delete",
		MENU_RELOAD: RELOAD,
	}
	for id in menu_items():
		menu.add_item(String(labels[id]), id)


func _on_menu_id(id: int) -> void:
	var actions := {
		MENU_SET_UP: ACTION_SET_UP,
		MENU_DUPLICATE: ACTION_DUPLICATE,
		MENU_DELETE: ACTION_DELETE,
		MENU_RELOAD: ACTION_RELOAD,
	}
	if actions.has(id):
		action_requested.emit(info, actions[id])


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
