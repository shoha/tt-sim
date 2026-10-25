class_name TitleScreen
extends CanvasLayer

## The title is the library, in one material: paper cards on the sky, and ink words where they
## stand on the sky itself (every mood keeps ink at 4.5:1: BackdropPaint.ink_reads_on). Two
## columns from the top of the window.
##
## The left column: the wordmark (the version a caption on its baseline) with Avatars, Settings
## and Quit game beside it in one row of quiet labelled tools (SkyButton); under it the heading
## of the section at the grid's top, which stays while the cards scroll (LevelGrid.top_section:
## "Your maps", then "Bundled with TTSim" once no line of the player's own maps is left under
## the clip, the in-flow Bundled heading's words hidden meanwhile); then the
## library's grid (LevelGrid), its clip just under that heading (no ScrollFade mask on it: the
## cards' picture wells clip with clip_children, and inside a masked scroll they draw blank,
## measured twice on 2026-10-10) and its scroll area running
## to the window's left and bottom edges, the room for the cards' shadows inside it (the theme's
## LibraryGrid), so a shadow never meets the clip. The grid: New map (NewMapCard: Generate and
## Import..., Advanced for size and seed in a popover) and the maps most recently played or
## edited first; "Bundled with TTSim" and the Bundled maps last (LibraryFacts.ordered,
## LibraryPlays). Each card's caption is LibraryFacts.when_text, as the panel's is, and a
## Blender map whose source is newer says "Updated in Blender" on its picture. With no map of
## the player's own nothing is selected: New map stands alone, larger and centred on the window
## (_centre_empty_library), and the
## Bundled maps are offered under it ("Or play one that comes with TTSim"); selecting one of
## them brings the panel in.
##
## The right column, one width (MapPanel.WIDTH, the Play together plaque's) and one left edge:
## the Play together card on its paper plaque (PlayTogetherCard: Host and Join as two sides of
## one question, the screen's one persimmon fill, C5) with Resume under it when saved sessions
## exist (ResumeEntry), Quit well away from Host; then, a step under the plaque, the selected
## map's panel (MapPanel), at most the height left above the window's foot (_fit_panel), which
## it fills on a short canvas by shortening its picture rather than scrolling.
##
## The panel shows any map the same way in the same place: its picture large, its name,
## description and author (edited in place on the player's own maps, plain text on a Bundled
## one), its source, size, tokens and date, then Play (solo), Host with this map (a room with
## this map on its shelf: the Host control beside what it acts on) and "..." (Set up tokens,
## Duplicate, Replace map file..., Delete); Edit map and Reload from Blender (when its source is
## newer) on a line under them on a map of the player's own. Accept on a card selects it first
## and plays it on a second Accept; a double click plays.
##
## A Blender map comes in through Import..., or a .glb dropped anywhere on the library (a new
## map) or on a map's card (Replace for that map); LibraryImports shows the import check
## before anything is written and the new or replaced map is selected after.
##
## Host opens a room with nothing on its shelf: a room needs no map (room first, user verdict
## 2026-10-09). Join happens in place on the card: the code goes to Root's SessionFlow, whose
## progress and errors come back to the card (show_join_status()). Resume reopens a saved
## session. The screen stands on the backdrop (PaintedBackdrop) in the selected map's mood,
## morning with none.

## Host: open a room. Empty `level_info` from the card (a room needs no map); a map's from the
## map panel's Host with this map, to go on the shelf.
signal host_game_requested(level_info: Dictionary)
## Join in place: join the room with `code`.
signal join_requested(code: String)
## Join mode closed while a join was under way: drop it.
signal join_cancel_requested
## Resume the saved session `id` (ResumeEntry).
signal resume_requested(id: String)
signal play_solo_requested(level_info: Dictionary)
## New map's Generate: a new map from `preset` ({"size_ft", "depth_ft", "seed"}), the rest
## asked by Root's new-map dialog.
signal build_map_requested(preset: Dictionary)
## A map's Edit map: open its map in authoring mode.
signal edit_map_requested(level_info: Dictionary)
## Design a biome: Root opens the designer's picker (BiomeDesignerPicker).
signal design_biome_requested

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := Constants.ANIM_ENTRANCE_STAGGER
const ENTRANCE_DURATION := Constants.ANIM_ENTRANCE
## The Level Editor's player-facing name, on the map panel's menu and in the pause menu.
const SET_UP_TOKENS := "Set up tokens"
## A token on its square, its own icon: the wand stays with Generate, the Events rail item and
## Surprise me, where it means a little magic, not an editor.
const SET_UP_TOKENS_ICON := "chess"
## Quitting the game, in the same words and icon here and in the pause menu.
const QUIT := "Quit game"
const QUIT_ICON := "logout"
## The fewest cards to a line beside the map panel (three on a 1280x720 canvas).
const GRID_COLUMNS := 3

## Returns the level info list; tests inject a fake before the node enters the tree.
var level_provider: Callable = LevelManager.get_saved_levels
## Returns {level folder: last played}; tests inject a fake.
var plays_provider: Callable = LibraryPlays.all
## Returns the saved sessions (SessionFile.list()); tests and the UI tour inject a fake.
var session_provider: Callable = SessionFile.list
## Whether Blender wrote a level folder's source since its copy: func(folder) -> bool.
var updated_provider: Callable = MapImport.is_updated_in_blender

## Host and Join, the top bar's right end and the screen's one fill.
var play_together: PlayTogetherCard
## Resume a saved session, under the card; hidden with none.
var resume_entry: ResumeEntry
var avatars_button: Button
## Opens the collections manager (LibraryManager); its word is LibraryNames.
var libraries_button: Button
## Opens the biome designer's picker (BiomeDesignerPicker).
var design_button: Button
var settings_button: Button
var quit_button: Button
var grid: LevelGrid
var new_map_card: NewMapCard
var map_panel: MapPanel
## The map panel's place in the right column, under the Play together plaque (hidden with
## nothing selected).
var panel_column: VBoxContainer
var imports: LibraryImports
## A collection (a .ttlib or a folder) dropped on the title goes through this flow's install card.
var library_flow: LibraryImportFlow
var backdrop: PaintedBackdrop
## The version, a caption on the wordmark's baseline.
var version_label: Label
## The wordmark and the tools in one row at the top of the left column, on the sky.
var masthead: HBoxContainer
## The heading of the section at the grid's top, over the grid's clip (LevelGrid.top_section);
## its row is hidden over an empty library, whose one heading scrolls with the cards.
var sticky_heading: Label
## The Play together card on its paper, at the top of the right column.
var play_plaque: PanelContainer

var _sticky_row: MarginContainer

@onready var _hub: MarginContainer = %Hub
@onready var _top_bar: HBoxContainer = %TopBar
@onready var _library_column: VBoxContainer = %LibraryColumn
@onready var _side_column: VBoxContainer = %SideColumn


func _ready() -> void:
	backdrop = PaintedBackdrop.new()
	add_child(backdrop)
	move_child(backdrop, 0)
	_build_top_bar()
	_build_library()
	version_label.text = "v" + UpdateVersion.get_current()
	version_label.modulate.a = 0.0
	grid.refresh()
	_preselect_most_recent()
	_refresh_actions()
	_play_entrance_animation()
	# The backdrop's layout hooks (no-ops while it is a plain gradient).
	backdrop.fit_around(self)
	grid.resized.connect(backdrop.refit)
	grid.content_resized.connect(backdrop.refit)
	_top_bar.resized.connect(backdrop.refit)
	LevelManager.level_saved.connect(_on_level_saved)
	get_tree().node_added.connect(_on_node_added_or_removed)
	get_tree().node_removed.connect(_on_node_added_or_removed)
	get_window().files_dropped.connect(_on_files_dropped)


func _exit_tree() -> void:
	if LevelManager.level_saved.is_connected(_on_level_saved):
		LevelManager.level_saved.disconnect(_on_level_saved)
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)
	if get_viewport().size_changed.is_connected(_fit_panel):
		get_viewport().size_changed.disconnect(_fit_panel)


func selected_level() -> Dictionary:
	return grid.selected_info()


func _build_top_bar() -> void:
	# The wordmark and the tools stand on the sky in ink, in one row; the version reads with the
	# wordmark, a caption on its baseline.
	masthead = HBoxContainer.new()
	masthead.name = "Masthead"
	masthead.theme_type_variation = &"BoxContainerApart"
	masthead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	masthead.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_top_bar.add_child(masthead)
	var wordmark_row := HBoxContainer.new()
	wordmark_row.name = "WordmarkRow"
	wordmark_row.theme_type_variation = &"BoxContainerSpaced"
	wordmark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	masthead.add_child(wordmark_row)
	var wordmark := Label.new()
	wordmark.name = "Wordmark"
	wordmark.text = "TTSim"
	wordmark.theme_type_variation = &"Wordmark"
	wordmark_row.add_child(wordmark)
	version_label = Label.new()
	version_label.name = "Version"
	version_label.theme_type_variation = &"SkyCaption"
	version_label.size_flags_vertical = Control.SIZE_SHRINK_END
	wordmark_row.add_child(version_label)
	var tools := HBoxContainer.new()
	tools.name = "Tools"
	tools.theme_type_variation = &"BoxContainerTight"
	tools.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tools.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	masthead.add_child(tools)
	avatars_button = _tool("Avatars", "mood-smile", tools)
	avatars_button.tooltip_text = "Make your characters ahead of time; place them in any game"
	avatars_button.pressed.connect(_on_avatars_pressed)
	avatars_button.visible = DevFeatures.avatars
	libraries_button = _tool(LibraryNames.title(2), "trees", tools)
	libraries_button.tooltip_text = "Add plants and ground to start new maps from"
	libraries_button.pressed.connect(_on_libraries_pressed)
	design_button = _tool("Design a biome", "leaf", tools)
	design_button.tooltip_text = "Shape how a place grows: its plants, where they stand, how dense"
	design_button.pressed.connect(design_biome_requested.emit)
	settings_button = _tool("Settings", "settings", tools)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = _tool(QUIT, QUIT_ICON, tools)
	quit_button.pressed.connect(_on_quit_pressed)
	# Host and Join as two sides of one question; its persimmon is the screen's one fill (C5).
	# The card's eyebrow and Resume are soft words, so the card stands on paper of its own, at
	# the top of the right column, the panel's width.
	_side_column.custom_minimum_size.x = MapPanel.WIDTH
	play_plaque = PanelContainer.new()
	play_plaque.name = "PlayPlaque"
	play_plaque.theme_type_variation = &"Plaque"
	play_plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_side_column.add_child(play_plaque)
	play_together = PlayTogetherCard.new()
	play_together.name = "PlayTogether"
	play_together.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	play_plaque.add_child(play_together)
	play_together.host_pressed.connect(_on_host_pressed)
	play_together.join_submitted.connect(join_requested.emit)
	play_together.join_cancelled.connect(join_cancel_requested.emit)
	# Resume belongs to the card: in the slot under it, where the join's line takes its place
	# while Join is open, so neither moves the card or anything below it.
	resume_entry = ResumeEntry.new()
	resume_entry.name = "ResumeEntry"
	resume_entry.provider = session_provider
	play_together.set_under(resume_entry)
	resume_entry.resume_requested.connect(resume_requested.emit)
	play_together.join_mode_changed.connect(resume_entry.hold)


## A quiet labelled tool on the sky: its icon and words in ink (SkyButton), a control's height.
func _tool(label: String, icon: String, parent: Control) -> Button:
	var button := UiActions.secondary(label, icon, parent)
	button.theme_type_variation = &"SkyButton"
	return button


func _build_library() -> void:
	new_map_card = NewMapCard.new()
	new_map_card.generate_requested.connect(build_map_requested.emit)
	map_panel = MapPanel.new()
	map_panel.play_requested.connect(play_solo_requested.emit)
	map_panel.host_requested.connect(host_game_requested.emit)
	map_panel.edit_map_requested.connect(edit_map_requested.emit)
	map_panel.action_requested.connect(_on_panel_action)
	map_panel.meta_saved.connect(_on_meta_saved)
	imports = LibraryImports.new()
	imports.name = "LibraryImports"
	add_child(imports)
	imports.imported.connect(_on_imported)
	imports.replaced.connect(
		func(folder: String, _result: Dictionary) -> void: _on_imported(folder)
	)
	new_map_card.import_requested.connect(imports.pick)
	library_flow = LibraryImportFlow.new()
	library_flow.name = "LibraryFlow"
	add_child(library_flow)
	grid = LevelGrid.new()
	grid.name = "Grid"
	grid.columns = GRID_COLUMNS
	grid.manageable = false
	grid.select_before_activate = true
	grid.sticky_headings = true
	grid.lead = new_map_card
	grid.provider = library
	grid.theme_type_variation = &"LibraryGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The headings are sized to the grid's width; a disabled horizontal scroll would make that
	# its minimum too and hold the grid at its old width when the window shrinks.
	grid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	grid.resized.connect(_centre_empty_library)
	grid.selection_changed.connect(_on_selection_changed)
	grid.level_activated.connect(play_solo_requested.emit)
	grid.level_edit_requested.connect(_open_editor)
	grid.level_map_edit_requested.connect(edit_map_requested.emit)
	grid.levels_changed.connect(_refresh_actions)
	grid.top_section_changed.connect(_show_top_section)
	# The heading of the section at the grid's top, on the cards' left edge, over the clip.
	_sticky_row = MarginContainer.new()
	_sticky_row.name = "StickyRow"
	_sticky_row.theme_type_variation = &"HubHeading"
	_sticky_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_library_column.add_child(_sticky_row)
	sticky_heading = Label.new()
	sticky_heading.name = "StickyHeading"
	sticky_heading.theme_type_variation = &"Heading"
	_sticky_row.add_child(sticky_heading)
	_show_top_section("")
	_library_column.add_child(grid)
	# The panel a step under the plaque, the column's width.
	panel_column = VBoxContainer.new()
	panel_column.name = "PanelColumn"
	panel_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_side_column.add_child(panel_column)
	panel_column.add_child(map_panel)
	play_plaque.resized.connect(_fit_panel)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()


## The panel at most the height left under the plaque above the window's foot; it shortens its
## picture to fit there (MapPanel.fit_height). Read from the canvas and the plaque alone, never
## from the column, whose height the panel itself would hold up.
func _fit_panel() -> void:
	var taken := float(_hub.get_theme_constant(&"margin_top"))
	taken += _hub.get_theme_constant(&"margin_bottom")
	taken += (_side_column.get_parent() as Control).get_theme_constant(&"margin_bottom")
	taken += play_plaque.get_combined_minimum_size().y
	taken += _side_column.get_theme_constant(&"separation")
	map_panel.max_height = _hub.get_viewport_rect().size.y - taken
	map_panel.fit_height()


## The empty library stands in the middle of the window, not of its column (the Play together
## plaque is the top bar's right end, not a column there): New map takes its width for the
## canvas (NewMapCard.empty_width_for) and centres, with the Bundled offer under it, on the
## window's middle line (LevelGrid.alone_centre).
func _centre_empty_library() -> void:
	var canvas := _hub.get_viewport_rect().size
	new_map_card.set_empty_width(NewMapCard.empty_width_for(canvas.x))
	grid.alone_centre = canvas.x * 0.5 - grid.get_global_rect().position.x


## The sticky heading says the section at the grid's top; its row takes no room with none.
func _show_top_section(words: String) -> void:
	sticky_heading.text = words
	_sticky_row.visible = words != ""


## The library's maps in its order (LibraryFacts.ordered), each with when it was last played
## and whether Blender has written its source since (LibraryFacts.UPDATED_KEY).
func library() -> Array[Dictionary]:
	var levels := LibraryFacts.ordered(level_provider.call(), plays_provider.call())
	for info in levels:
		var folder := String(info.get("folder", ""))
		var source := LibraryFacts.source_of(info)
		var blender := (
			source == LibraryFacts.SOURCE_BLENDER or source == LibraryFacts.SOURCE_DRESSED
		)
		info[LibraryFacts.UPDATED_KEY] = folder != "" and blender and updated_provider.call(folder)
	return levels


## Selects the map at the head of the library (the most recently played or edited) when it is
## the player's own; over Bundled maps alone nothing is selected (New map leads).
func _preselect_most_recent() -> void:
	var levels := LibraryFacts.ordered(grid.provider.call(), {})
	if not levels.is_empty() and not LibraryFacts.is_bundled(levels[0]):
		grid.select(String(levels[0].get("path", "")))


## The library's state: one with no map of the player's own is New map alone, larger; the
## panel shows the selected map, and with none selected the grid takes its place; the backdrop
## takes the map's mood (morning with none).
func _refresh_actions() -> void:
	new_map_card.set_empty(grid.own_card_count() == 0)
	var info := grid.selected_info()
	if not info.is_empty():
		map_panel.show_map(info)
	else:
		grid.scroll_vertical = 0
	panel_column.visible = not info.is_empty()
	var map_name := String(info.get("name", ""))
	var folder := String(info.get("folder", ""))
	backdrop.show_map(
		String(info.get("environment_preset", "")), folder if folder != "" else map_name
	)
	backdrop.refit()


## The wordmark row lifts in, then the plaque, the library and the panel (M4).
func _play_entrance_animation() -> void:
	var targets: Array[Control] = [masthead, play_plaque, _sticky_row, grid, panel_column]
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
## own primary (Apply, Create, Add to library) is the fill, so Host's wash steps back to paper
## and takes its fill back when the last sheet closes. Deferred: a node is still in its groups
## while node_removed is emitted.
func _on_node_added_or_removed(node: Node) -> void:
	if node is Scrim:
		_refresh_host_fill.call_deferred()


func _refresh_host_fill() -> void:
	if not is_inside_tree() or play_together == null:
		return
	play_together.step_back(Scrim.any_shown(get_tree()))


## A join under way, as Root's SessionFlow reports it (SessionFlow.JOIN_*): connecting,
## connected and waiting for the room, or failed with `message`. Only a code no room has
## selects the code to correct; any other failure leaves it as typed.
func show_join_status(state: StringName, message := "") -> void:
	match state:
		SessionFlow.JOIN_CONNECTING:
			play_together.show_connecting()
		SessionFlow.JOIN_JOINED:
			play_together.show_joining()
		SessionFlow.JOIN_FAILED:
			play_together.show_error(message, message == SessionFlow.NO_ROOM)


## The library entry of the card under `point` (canvas coordinates), or {} between cards.
func card_at(point: Vector2) -> Dictionary:
	for card: LevelCard in grid._cards:
		if card.is_visible_in_tree() and card.get_global_rect().has_point(point):
			return card.level_info
	return {}


## Files dropped on the window while the library is the screen (no sheet over it): a collection
## (a .ttlib or .zip holding a library.json, or a folder that does) opens its install card; a
## .glb on a map's card replaces that map; anywhere else it is a new map.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not visible or Scrim.any_shown(get_tree()):
		return
	if LibraryImportFlow.any_candidate(files):
		library_flow.drop(files)
		return
	var info := card_at(_hub.get_viewport().get_mouse_position())
	imports.drop(files, String(info.get("folder", "")))


## A map written by an import or a replace: the library again, that map selected.
func _on_imported(folder: String) -> void:
	grid.refresh()
	grid.select(LevelManager.folder_path(folder))
	_refresh_actions()


func _on_panel_action(info: Dictionary, action: StringName) -> void:
	match action:
		MapPanel.ACTION_SET_UP:
			_open_editor(info)
		MapPanel.ACTION_RELOAD:
			imports.reload(info)
		MapPanel.ACTION_REPLACE:
			imports.pick_replace(info)
		_:
			grid.act(info, action)


## A name, description or author saved in the panel shows on the card at once.
func _on_meta_saved(info: Dictionary) -> void:
	grid.update_info(info)


## A level saved from the Level Editor overlay (not through the title) must still show up
## here; refresh() notifies _refresh_actions via levels_changed.
func _on_level_saved(_path: String) -> void:
	grid.refresh()
	_preselect_most_recent()


## Host opens a room with nothing on its shelf (it acts on nothing selected; maps are added
## in the room).
func _on_host_pressed() -> void:
	host_game_requested.emit({})


## Set up tokens: the Level Editor on that map.
func _open_editor(info: Dictionary) -> void:
	EventBus.open_editor_requested.emit(String(info.get("path", "")))


## Avatars: the player's saved avatars (AvatarRoster), made and edited here with no game
## running.
func _on_avatars_pressed() -> void:
	AvatarRoster.open(get_tree().root)


## Collections: the manager over the title (list, import, switch, verify, remove).
func _on_libraries_pressed() -> void:
	LibraryManager.open(get_tree().root)


func _on_settings_pressed() -> void:
	var settings_menu := SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)


func _on_quit_pressed() -> void:
	get_tree().quit()
