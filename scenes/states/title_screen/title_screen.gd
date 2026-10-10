class_name TitleScreen
extends CanvasLayer

## The title is the library. A top bar holds the wordmark on its plaque at the left and, at
## the right end on a plaque of its own, Avatars, Settings and Quit beside the Play together
## card (PlayTogetherCard: Host and Join as two sides of one question, the screen's one
## persimmon fill, C5) with Resume under it when saved sessions exist (ResumeEntry). Under the
## bar, the maps as a grid of cards (LevelGrid), the most recently played or edited first and
## the Bundled maps last (LibraryFacts.ordered, LibraryPlays); each card's caption is the date
## that order uses, and a Blender map whose source is newer says "Updated in Blender". The
## first card is New map (NewMapCard: Generate and Import..., Advanced for size and seed in a
## popover); with no map of the player's own that card stands alone, larger and centred, and
## the Bundled maps are offered under it ("Or play one that comes with TTSim"), none selected.
##
## Selecting a card opens its detail strip (MapDetailStrip) directly under its row and under
## the card, and scrolls the grid so the row and the whole strip are in view: the map's
## picture, its name, description and author edited in place, its source, size, tokens and
## when it was last played (and Reload from Blender when its source is newer), then Play
## (solo), Host with this map (a room with this map on its shelf: the Host control beside
## what it acts on), Edit map and "..." (Set up tokens, Duplicate, Replace map file...,
## Delete). Accept on a card selects it first and plays it on a second Accept; a double click
## plays.
##
## A Blender map comes in through Import..., or a .glb dropped anywhere on the library (a new
## map) or on a map's card (Replace for that map); LibraryImports shows the import check
## before anything is written and the new or replaced map is selected after.
##
## Host opens a room with nothing on its shelf: a room needs no map (room first, user verdict
## 2026-10-09). Join happens in place on the card: the code goes to Root's SessionFlow, whose
## progress and errors come back to the card (show_join_status()). Resume reopens a saved
## session. The screen stands on the painted backdrop (PaintedBackdrop) in the selected map's
## mood and land, morning with none, making way for the paper (fit_around). No word stands
## straight on the painting: the wordmark, the tools and the card are on plaques, the strip on
## a sheet.

## Host: open a room. Empty `level_info` from the card (a room needs no map); a map's from the
## detail strip's Host with this map, to go on the shelf.
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

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := Constants.ANIM_ENTRANCE_STAGGER
const ENTRANCE_DURATION := Constants.ANIM_ENTRANCE
## The Level Editor's player-facing name, on the detail strip's menu and in the pause menu.
const SET_UP_TOKENS := "Set up tokens"
## A token on its square, its own icon: the wand stays with Generate, the Events rail item and
## Surprise me, where it means a little magic, not an editor.
const SET_UP_TOKENS_ICON := "chess"
## Quitting the game, in the same words and icon here and in the pause menu.
const QUIT := "Quit game"
const QUIT_ICON := "logout"
## The fewest cards to a line: four keep a row and the strip under it on a 1280x720 canvas.
const GRID_COLUMNS := 4

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
var settings_button: Button
var quit_button: Button
var grid: LevelGrid
var new_map_card: NewMapCard
var strip: MapDetailStrip
var imports: LibraryImports
var backdrop: PaintedBackdrop
## The version, a caption on the wordmark's baseline.
var version_label: Label
var wordmark_plaque: PanelContainer
## Avatars, Settings, Quit and the Play together card, on their plaque.
var tools_plaque: PanelContainer

@onready var _hub: MarginContainer = %Hub
@onready var _top_bar: HBoxContainer = %TopBar
@onready var _stack: VBoxContainer = %Stack


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
	# The painting makes way for the plaques, the cards and the strip: its sun, clouds and
	# poplars stand in the sky they leave open.
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


func selected_level() -> Dictionary:
	return grid.selected_info()


func _build_top_bar() -> void:
	# The version reads with the wordmark, a caption on its baseline, on the same paper.
	wordmark_plaque = _plaque("WordmarkPlaque")
	var wordmark_row := HBoxContainer.new()
	wordmark_row.name = "WordmarkRow"
	wordmark_row.theme_type_variation = &"BoxContainerSpaced"
	wordmark_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wordmark_plaque.add_child(wordmark_row)
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
	var open_sky := Control.new()
	open_sky.name = "OpenSky"
	open_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	open_sky.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_bar.add_child(open_sky)
	tools_plaque = _plaque("ToolsPlaque")
	var row := HBoxContainer.new()
	row.name = "ToolsRow"
	row.theme_type_variation = &"BoxContainerSpaced"
	tools_plaque.add_child(row)
	var tools := VBoxContainer.new()
	tools.name = "Tools"
	tools.theme_type_variation = &"BoxContainerTight"
	tools.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(tools)
	avatars_button = UiActions.secondary("Avatars", "mood-smile", tools)
	avatars_button.tooltip_text = "Make your characters ahead of time; place them in any game"
	avatars_button.pressed.connect(_on_avatars_pressed)
	avatars_button.visible = DevFeatures.avatars
	settings_button = UiActions.secondary("Settings", "settings", tools)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = UiActions.secondary(QUIT, QUIT_ICON, tools)
	quit_button.pressed.connect(_on_quit_pressed)
	# Host and Join as two sides of one question; its persimmon is the screen's one fill (C5).
	play_together = PlayTogetherCard.new()
	play_together.name = "PlayTogether"
	play_together.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(play_together)
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


func _plaque(node_name: String) -> PanelContainer:
	var plaque := PanelContainer.new()
	plaque.name = node_name
	plaque.theme_type_variation = &"Plaque"
	plaque.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_top_bar.add_child(plaque)
	return plaque


func _build_library() -> void:
	new_map_card = NewMapCard.new()
	new_map_card.generate_requested.connect(build_map_requested.emit)
	strip = MapDetailStrip.new()
	strip.play_requested.connect(play_solo_requested.emit)
	strip.host_requested.connect(host_game_requested.emit)
	strip.edit_map_requested.connect(edit_map_requested.emit)
	strip.action_requested.connect(_on_strip_action)
	strip.meta_saved.connect(_on_meta_saved)
	imports = LibraryImports.new()
	imports.name = "LibraryImports"
	add_child(imports)
	imports.imported.connect(_on_imported)
	imports.replaced.connect(func(folder: String, _result: Dictionary) -> void: _on_imported(folder))
	new_map_card.import_requested.connect(imports.pick)
	grid = LevelGrid.new()
	grid.name = "Grid"
	grid.columns = GRID_COLUMNS
	grid.manageable = false
	grid.select_before_activate = true
	grid.lead = new_map_card
	grid.detail = strip
	grid.provider = library
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# The strip is sized to the grid's width; a disabled horizontal scroll would make that its
	# minimum too and hold the grid at its old width when the window shrinks.
	grid.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	grid.selection_changed.connect(_on_selection_changed)
	grid.level_activated.connect(play_solo_requested.emit)
	grid.level_edit_requested.connect(_open_editor)
	grid.level_map_edit_requested.connect(edit_map_requested.emit)
	grid.levels_changed.connect(_refresh_actions)
	_stack.add_child(grid)


## The library's maps in its order (LibraryFacts.ordered), each with when it was last played
## and whether Blender has written its source since (LibraryFacts.UPDATED_KEY).
func library() -> Array[Dictionary]:
	var levels := LibraryFacts.ordered(level_provider.call(), plays_provider.call())
	for info in levels:
		var folder := String(info.get("folder", ""))
		var source := LibraryFacts.source_of(info)
		var blender := source == LibraryFacts.SOURCE_BLENDER or source == LibraryFacts.SOURCE_DRESSED
		info[LibraryFacts.UPDATED_KEY] = folder != "" and blender and updated_provider.call(folder)
	return levels


## Selects the map at the head of the library (the most recently played or edited) when it is
## the player's own; over Bundled maps alone nothing is selected (New map leads).
func _preselect_most_recent() -> void:
	var levels := LibraryFacts.ordered(grid.provider.call(), {})
	if not levels.is_empty() and not LibraryFacts.is_bundled(levels[0]):
		grid.select(String(levels[0].get("path", "")))


## The library's state: one with no map of the player's own is New map alone, larger; the
## strip shows the selected map; the backdrop takes its mood and land (morning with none).
func _refresh_actions() -> void:
	new_map_card.set_empty(grid.own_card_count() == 0)
	var info := grid.selected_info()
	if not info.is_empty():
		strip.show_map(info)
	var name := String(info.get("name", ""))
	var folder := String(info.get("folder", ""))
	backdrop.show_map(
		String(info.get("environment_preset", "")), folder if folder != "" else name
	)
	backdrop.refit()


## The top bar's plaques lift in, then the library (M4).
func _play_entrance_animation() -> void:
	var targets: Array[Control] = [wordmark_plaque, tools_plaque, grid]
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


## Files dropped on the window while the library is the screen (no sheet over it): a .glb on
## a map's card replaces that map; anywhere else it is a new map.
func _on_files_dropped(files: PackedStringArray) -> void:
	if not visible or Scrim.any_shown(get_tree()):
		return
	var info := card_at(_hub.get_viewport().get_mouse_position())
	imports.drop(files, String(info.get("folder", "")))


## A map written by an import or a replace: the library again, that map selected.
func _on_imported(folder: String) -> void:
	grid.refresh()
	grid.select(LevelManager.folder_path(folder))
	_refresh_actions()


func _on_strip_action(info: Dictionary, action: StringName) -> void:
	match action:
		MapDetailStrip.ACTION_SET_UP:
			_open_editor(info)
		MapDetailStrip.ACTION_RELOAD:
			imports.reload(info)
		MapDetailStrip.ACTION_REPLACE:
			imports.pick_replace(info)
		_:
			grid.act(info, action)


## A name, description or author saved in the strip shows on the card at once.
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


func _on_settings_pressed() -> void:
	var settings_menu := SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)


func _on_quit_pressed() -> void:
	get_tree().quit()
