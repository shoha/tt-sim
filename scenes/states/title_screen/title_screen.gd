class_name TitleScreen
extends CanvasLayer

## Title hub. Host and Join lead; the saved levels sit beside them as cards and
## the selected card is the level a host starts with (or Play Solo opens). Avatars opens
## the player's saved avatars (AvatarRoster).
## The hub stands on the painted backdrop (PaintedBackdrop) in the selected map's mood and
## land, changing as the selection changes, and making way for the column's sheet, the plaque
## and the cards (fit_around); with no map selected, and over an empty library, it is
## morning. The backdrop is the empty library's picture too: the d20 that turned there was
## a glossy 3D object over a painting, so it went with the flat sky. No word stands straight on
## the painting: the column (with the version beside the wordmark) is on a paper sheet like
## the room's side sheet, ending at its content, and "Your maps" with its count (and the empty
## library's caption) on a paper plaque, so every caption keeps its contrast in every mood.
##
## Host opens a room, and the selected map is what goes on its shelf; Play solo and Set up
## tokens act on that map, and all three name it the same way, the bare name leading the line
## under the button. A room needs no map (room first, user verdict 2026-10-09), so over an
## empty library Host stays the screen's fill and says maps are added in the room, and the
## plaque where the cards would be says so once (no count of 0) beside a small painted picture
## of a map to come, and offers one action, New map's (Start a new map; I5). New map starts one
## from nothing. Set up tokens is the Level Editor by what it does (starting tokens, the map's
## details and its Blender file; W5 keeps "level" internal); with no map selected it opens on a
## new one, where a map exported from Blender is chosen, and its caption says so: it stays
## enabled, since that is how a Blender map comes into an empty library.

signal host_game_requested(level_info: Dictionary)
signal join_game_requested
signal play_solo_requested(level_info: Dictionary)
## New map: a new map in authoring mode (Root shows the new-map dialog).
signal build_map_requested
## A card's "Edit map": open that level's map in authoring mode.
signal edit_map_requested(level_info: Dictionary)

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := Constants.ANIM_ENTRANCE_STAGGER
const ENTRANCE_DURATION := Constants.ANIM_ENTRANCE
## The Level Editor's player-facing name, here, on a card's menu and in the pause menu.
const SET_UP_TOKENS := "Set up tokens"
## A token on its square, its own icon: the wand stays with the Events rail item and Surprise
## me, where it means a little magic, not an editor.
const SET_UP_TOKENS_ICON := "chess"
## Quitting the game, in the same words and icon here and in the pause menu.
const QUIT := "Quit game"
const QUIT_ICON := "logout"
const HOST_CAPTION := "Open a room and invite players"
## The line under Host once a map is selected: what Host does with it.
const HOST_MAP_LINE := "%s goes on the shelf"
## The line under Host with no map: a room needs none (room first, user verdict 2026-10-09).
const HOST_EMPTY_LINE := "Open a room; add maps there"
const NEW_MAP_CAPTION := "Pick a landform, then paint it"
## The empty library's plaque: one line and one action, New map's.
const EMPTY_CAPTION := "No maps yet. Paint your first one"
const EMPTY_ACTION := "Start a new map"
## The empty library's picture: a map to come, painted in the morning the backdrop shows.
const EMPTY_PICTURE := Vector2(128, 72)
const EMPTY_PICTURE_KEY := "Your first map"
## The line under Set up tokens with no map selected: what it opens there.
const SET_UP_TOKENS_EMPTY_LINE := "Bring in a map from Blender"
## The left column's rhythm. Its own separation (BoxContainerTight, 4) puts a caption under
## its button; every other gap is a spacer before a row, sized by _fit_to_canvas. A caption
## stands AFTER_CAPTION_GAP above the next control, so it reads with its own button; stacked
## buttons stand STACK_GAP_ROOMY apart, or STACK_GAP when the canvas is short; the three
## section gaps (under the wordmark, above and below the divider) take what is left, from
## their SECTION_GAPS size down to SECTION_GAP_MIN (8: on a 1280x720 canvas the two map
## actions' captions need the room). The column is measured against the room the hub's
## margins and its sheet's padding leave it (the hub's margins are the sheet's distance from
## the canvas edge, so the padding comes out of what used to be margin), and tightens only by
## what that room needs: the stacked gaps first, then the sections, evenly
## (docs/THEME_GUIDE.md, Interface size).
const AFTER_CAPTION_GAP := 12.0
const STACK_GAP := 8.0
const STACK_GAP_ROOMY := 12.0
## Under the wordmark, above the divider, below it.
const SECTION_GAPS: Array[float] = [36.0, 32.0, 32.0]
const SECTION_GAP_MIN := 8.0

## Returns the level info list; tests inject a fake before the node enters the tree.
var level_provider: Callable = LevelManager.get_saved_levels

var host_button: Button
var join_button: Button
var play_button: Button
var editor_button: Button
var build_map_button: Button
var avatars_button: Button
var settings_button: Button
var quit_button: Button
## Host's caption: what Host does, or with no map that maps are added in the room.
var host_caption: Label
var host_subtitle: Label
var play_subtitle: Label
var editor_subtitle: Label
var heading_count: Label
var empty_caption: Label
## The empty library's one action on its plaque: New map.
var empty_action: Button
var grid: LevelGrid
var backdrop: PaintedBackdrop
## The version, a caption on the wordmark's baseline.
var version_label: Label
## "Your maps" and its count, with the empty library's caption under them, on their plaque.
var heading_plaque: PanelContainer
var _heading_row: HBoxContainer
## The empty library's picture, line and action, under the heading on its plaque.
var _empty_row: HBoxContainer
## The left column's spacers: the three section gaps in order, and the gap before each
## button after Host's.
var _section_gaps: Array[Control] = []
var _row_gaps: Array[Control] = []

@onready var _hub: MarginContainer = %Hub
@onready var _sheet: PanelContainer = %ColumnSheet
@onready var _left: VBoxContainer = %LeftColumn
@onready var _right: VBoxContainer = %RightZone


func _ready() -> void:
	backdrop = PaintedBackdrop.new()
	add_child(backdrop)
	move_child(backdrop, 0)
	_build_left_column()
	_build_right_zone()
	version_label.text = "v" + UpdateVersion.get_current()
	version_label.modulate.a = 0.0
	grid.refresh()
	_preselect_most_recent()
	_refresh_actions()
	_play_entrance_animation()
	get_viewport().size_changed.connect(_fit_to_canvas)
	_fit_to_canvas()
	# The painting makes way for the sheet, the plaque and the cards: its sun, clouds and
	# poplars stand in the sky they leave open.
	backdrop.fit_around(self)
	grid.resized.connect(backdrop.refit)
	_sheet.resized.connect(backdrop.refit)
	LevelManager.level_saved.connect(_on_level_saved)
	get_tree().node_added.connect(_on_node_added_or_removed)
	get_tree().node_removed.connect(_on_node_added_or_removed)


func _exit_tree() -> void:
	if LevelManager.level_saved.is_connected(_on_level_saved):
		LevelManager.level_saved.disconnect(_on_level_saved)


func selected_level() -> Dictionary:
	return grid.selected_info()


## Fit the left column to the canvas height: roomy when it fits, else stacked buttons at
## STACK_GAP, then the section gaps shrunk evenly by what is still over. The room is the
## canvas less the hub's margins and the sheet's own padding.
func _fit_to_canvas() -> void:
	if _section_gaps.is_empty():
		return
	var margins := (
		_hub.get_theme_constant(&"margin_top") + _hub.get_theme_constant(&"margin_bottom")
	)
	margins += _sheet.get_theme_stylebox(&"panel").get_minimum_size().y
	var room := get_viewport().get_visible_rect().size.y - margins
	_set_gaps(STACK_GAP_ROOMY, 0.0)
	if _left.get_combined_minimum_size().y <= room:
		return
	_set_gaps(STACK_GAP, 0.0)
	var over := _left.get_combined_minimum_size().y - room
	if over <= 0.0:
		return
	var slack := 0.0
	for gap in SECTION_GAPS:
		slack += gap - SECTION_GAP_MIN
	_set_gaps(STACK_GAP, clampf(over / slack, 0.0, 1.0))


## Size every spacer: a row's gap is AFTER_CAPTION_GAP after a caption, else `stack`; each
## section gap gives up the share `squeeze` of its way down to SECTION_GAP_MIN. A spacer's
## height is its gap less the column's separation above and below it, in whole pixels, rounded
## down: the box rounds each child's height up, which put a fully squeezed column 2 px over.
func _set_gaps(stack: float, squeeze: float) -> void:
	var separation := float(_left.get_theme_constant(&"separation"))
	for i in _section_gaps.size():
		var gap := lerpf(SECTION_GAPS[i], SECTION_GAP_MIN, squeeze)
		_section_gaps[i].custom_minimum_size.y = floorf(maxf(gap - 2.0 * separation, 0.0))
	for spacer in _row_gaps:
		var row := _left.get_child(spacer.get_index() + 1) as Control
		spacer.visible = row.visible
		var gap := AFTER_CAPTION_GAP if _follows_caption(spacer) else stack
		spacer.custom_minimum_size.y = maxf(gap - 2.0 * separation, 0.0)


## Whether the nearest shown control above `spacer` is a caption line.
func _follows_caption(spacer: Control) -> bool:
	for i in range(spacer.get_index() - 1, -1, -1):
		var control := _left.get_child(i) as Control
		if control.visible:
			return control is Label
	return false


func _build_left_column() -> void:
	# The version reads with the wordmark, a caption on its baseline, on the same paper.
	var wordmark_row := HBoxContainer.new()
	wordmark_row.name = "WordmarkRow"
	wordmark_row.theme_type_variation = &"BoxContainerSpaced"
	wordmark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left.add_child(wordmark_row)
	var wordmark := Label.new()
	wordmark.name = "Wordmark"
	wordmark.text = "TTSim"
	wordmark.theme_type_variation = &"Wordmark"
	wordmark_row.add_child(wordmark)
	version_label = Label.new()
	version_label.name = "Version"
	version_label.theme_type_variation = &"Caption"
	version_label.size_flags_vertical = Control.SIZE_SHRINK_END
	wordmark_row.add_child(version_label)
	_section_gaps.append(UiActions.spacer(0, _left))
	host_button = UiActions.primary("Host game", "network", HOST_CAPTION, _left)
	host_caption = _left.get_child(host_button.get_index() + 1) as Label
	host_subtitle = UiActions.subtitle_of(host_button)
	host_button.pressed.connect(_on_host_pressed)
	# One persimmon fill per screen (C5): Host is the primary, Join stands beside it quietly.
	_row_gaps.append(UiActions.spacer(0, _left))
	join_button = UiActions.primary(
		"Join game", "users", "Enter a room code", _left, &"Secondary"
	)
	join_button.pressed.connect(_on_join_pressed)
	_section_gaps.append(UiActions.spacer(0, _left))
	_left.add_child(HSeparator.new())
	_section_gaps.append(UiActions.spacer(0, _left))
	play_button = UiActions.secondary("Play solo", "map", _left)
	play_subtitle = UiActions.subtitle_of(play_button)
	play_button.pressed.connect(_on_play_pressed)
	# The Level Editor, by what it does to the selected map (W5: "level" stays internal).
	editor_button = _stacked(SET_UP_TOKENS, SET_UP_TOKENS_ICON)
	editor_button.tooltip_text = "Starting tokens, details and the map file of the selected map"
	editor_subtitle = UiActions.subtitle_of(editor_button)
	editor_button.pressed.connect(_on_editor_pressed)
	build_map_button = _stacked("New map", "brush")
	var new_map_caption := UiActions.subtitle_of(build_map_button)
	new_map_caption.text = NEW_MAP_CAPTION
	new_map_caption.visible = true
	build_map_button.pressed.connect(_on_build_map_pressed)
	avatars_button = _stacked("Avatars", "mood-smile")
	avatars_button.tooltip_text = "Make your characters ahead of time; place them in any game"
	avatars_button.pressed.connect(_on_avatars_pressed)
	avatars_button.visible = DevFeatures.avatars
	# Settings and Quit share the last row: the two map actions' captions need its height.
	_row_gaps.append(UiActions.spacer(0, _left))
	var last_row := HBoxContainer.new()
	last_row.name = "SettingsAndQuit"
	last_row.theme_type_variation = &"BoxContainerSpaced"
	_left.add_child(last_row)
	settings_button = UiActions.secondary("Settings", "settings", last_row)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = UiActions.secondary(QUIT, QUIT_ICON, last_row)
	quit_button.pressed.connect(_on_quit_pressed)
	for button in [settings_button, quit_button]:
		(button as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL


## A Secondary button in the lower stack, after its row gap.
func _stacked(label: String, icon: String) -> Button:
	_row_gaps.append(UiActions.spacer(0, _left))
	return UiActions.secondary(label, icon, _left)


func _build_right_zone() -> void:
	# The heading's words stand on the painting, so they sit on a plaque of paper that ends at
	# them; its top edge lines up with the column's sheet.
	heading_plaque = PanelContainer.new()
	heading_plaque.name = "HeadingPlaque"
	heading_plaque.theme_type_variation = &"Plaque"
	heading_plaque.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	heading_plaque.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right.add_child(heading_plaque)
	var words := VBoxContainer.new()
	words.theme_type_variation = &"BoxContainerTight"
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading_plaque.add_child(words)
	_heading_row = HBoxContainer.new()
	_heading_row.name = "Heading"
	_heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The count reads with its heading as a bare number ("Your maps  3"), sitting on the
	# heading's baseline rather than pinned to the window's far edge.
	_heading_row.theme_type_variation = &"BoxContainerSpaced"
	var heading := Label.new()
	heading.text = "Your maps"
	heading.theme_type_variation = &"H2"
	_heading_row.add_child(heading)
	heading_count = Label.new()
	heading_count.name = "Count"
	heading_count.theme_type_variation = &"Caption"
	heading_count.size_flags_vertical = Control.SIZE_SHRINK_END
	_heading_row.add_child(heading_count)
	words.add_child(_heading_row)
	# The empty library: a small painted picture of a map to come beside one line and one
	# action, quiet beside Host's fill (C5): New map's.
	_empty_row = HBoxContainer.new()
	_empty_row.name = "EmptyLibrary"
	_empty_row.theme_type_variation = &"BoxContainerSpaced"
	_empty_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_row.visible = false
	words.add_child(_empty_row)
	var picture := RoomRows.map_well(EMPTY_PICTURE, null, EMPTY_PICTURE_KEY, "")
	picture.name = "Picture"
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_empty_row.add_child(picture)
	var empty_words := VBoxContainer.new()
	empty_words.theme_type_variation = &"BoxContainerSpaced"
	empty_words.alignment = BoxContainer.ALIGNMENT_CENTER
	empty_words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_empty_row.add_child(empty_words)
	empty_caption = Label.new()
	empty_caption.name = "Empty"
	empty_caption.text = EMPTY_CAPTION
	empty_caption.theme_type_variation = &"Caption"
	empty_words.add_child(empty_caption)
	empty_action = UiActions.secondary(EMPTY_ACTION, "brush", empty_words)
	empty_action.name = "StartNewMap"
	empty_action.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	empty_action.pressed.connect(_on_build_map_pressed)
	grid = LevelGrid.new()
	grid.name = "Grid"
	grid.columns = 3
	grid.provider = level_provider
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.selection_changed.connect(_on_selection_changed)
	grid.level_activated.connect(_on_level_activated)
	grid.level_edit_requested.connect(_on_level_edit_requested)
	grid.level_map_edit_requested.connect(edit_map_requested.emit)
	grid.levels_changed.connect(_refresh_actions)
	_right.add_child(grid)


func _preselect_most_recent() -> void:
	var levels: Array = level_provider.call()
	if levels.is_empty():
		return
	var newest: Dictionary = levels[0]
	for info in levels:
		if int(info.get("modified_at", 0)) > int(newest.get("modified_at", 0)):
			newest = info
	grid.select(String(newest.get("path", "")))


## Host, Play Solo and Set up tokens name the selected level. Host needs none (a room needs no
## map: its caption says maps are added there); Play Solo is disabled without one, and Set up
## tokens opens on a new map, where a Blender map is brought in, as its line then says.
func _refresh_actions() -> void:
	var count := grid.card_count()
	heading_count.text = str(count)
	# An empty library says so once, in its own line: no count of 0 above it.
	heading_count.visible = count > 0
	_empty_row.visible = count == 0
	empty_caption.visible = count == 0
	empty_action.visible = count == 0
	var info := grid.selected_info()
	var has_level := not info.is_empty()
	play_button.disabled = not has_level
	host_caption.text = HOST_CAPTION if has_level else HOST_EMPTY_LINE
	host_subtitle.visible = has_level
	play_subtitle.visible = has_level
	var name := String(info.get("name", ""))
	host_subtitle.text = HOST_MAP_LINE % name if has_level else ""
	play_subtitle.text = name
	editor_subtitle.text = name if has_level else SET_UP_TOKENS_EMPTY_LINE
	editor_subtitle.visible = true
	# The selected map's mood and land (morning with none); the first one shows at once.
	var folder := String(info.get("folder", ""))
	backdrop.show_map(
		String(info.get("environment_preset", "")), folder if folder != "" else name
	)
	backdrop.refit()
	# A caption shown or hidden changes the column's height and the gap after it.
	_fit_to_canvas()


## The rows lift in one after another; the spacers between them are skipped (M4).
func _play_entrance_animation() -> void:
	var targets: Array[Control] = []
	for control in UiMotion.visible_children(_left):
		if not (_section_gaps.has(control) or _row_gaps.has(control)):
			targets.append(control)
	targets.append_array(UiMotion.visible_children(_right))
	await UiMotion.stagger_in(targets, self)
	if not is_instance_valid(self):
		return
	var version_tween := create_tween()
	version_tween.set_ease(Tween.EASE_OUT)
	version_tween.set_trans(Tween.TRANS_CUBIC)
	version_tween.tween_property(version_label, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(
		targets.size() * ENTRANCE_STAGGER
	)


func _on_selection_changed(_info: Dictionary) -> void:
	_refresh_actions()


## One persimmon fill per screen (C5): while a sheet's scrim covers the title, the sheet's
## own primary (Apply, Create) is the fill, so Host steps down to the quiet secondary and
## takes its fill back when the last sheet closes. Deferred: a node is still in its groups
## while node_removed is emitted.
func _on_node_added_or_removed(node: Node) -> void:
	if node is Scrim:
		_refresh_host_fill.call_deferred()


func _refresh_host_fill() -> void:
	if not is_inside_tree() or host_button == null:
		return
	host_button.theme_type_variation = &"Secondary" if Scrim.any_shown(get_tree()) else &"Primary"


## A level saved from the Level Editor overlay (not through the title) must
## still show up here; refresh() notifies _refresh_actions via levels_changed.
func _on_level_saved(_path: String) -> void:
	grid.refresh()
	_preselect_most_recent()


func _on_level_activated(info: Dictionary) -> void:
	play_solo_requested.emit(info)


## Host opens a room with the selected map on its shelf, or with none (an empty info).
func _on_host_pressed() -> void:
	host_game_requested.emit(grid.selected_info())


func _on_join_pressed() -> void:
	join_game_requested.emit()


func _on_play_pressed() -> void:
	var info := grid.selected_info()
	if info.is_empty():
		return
	play_solo_requested.emit(info)


## Set up tokens opens the editor on the selected map, as its caption says; with none
## selected, on a new map (where a Blender map file can be chosen).
func _on_editor_pressed() -> void:
	EventBus.open_editor_requested.emit(String(grid.selected_info().get("path", "")))


func _on_build_map_pressed() -> void:
	build_map_requested.emit()


func _on_level_edit_requested(info: Dictionary) -> void:
	EventBus.open_editor_requested.emit(String(info.get("path", "")))


## Avatars: the player's saved avatars (AvatarRoster), made and edited here with no game
## running.
func _on_avatars_pressed() -> void:
	AvatarRoster.open(get_tree().root)


func _on_settings_pressed() -> void:
	var settings_menu := SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)


func _on_quit_pressed() -> void:
	get_tree().quit()
