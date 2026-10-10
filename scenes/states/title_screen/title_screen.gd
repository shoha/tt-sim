class_name TitleScreen
extends CanvasLayer

## Title hub. Host and Join lead; the saved levels sit beside them as cards and
## the selected card is the level a host starts with (or Play Solo opens). Avatars opens
## the player's saved avatars (AvatarRoster).
## The d20 sub-viewport stays over a sky-coloured backdrop.

signal host_game_requested(level_info: Dictionary)
signal join_game_requested
signal play_solo_requested(level_info: Dictionary)
## Build Map: a new map in authoring mode (Root shows the new-map dialog).
signal build_map_requested
## A card's "Edit map": open that level's map in authoring mode.
signal edit_map_requested(level_info: Dictionary)

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := Constants.ANIM_ENTRANCE_STAGGER
const ENTRANCE_DURATION := Constants.ANIM_ENTRANCE
const EMPTY_CAPTION := "Build a map, or make a level in the Level Editor"
## The left column's rhythm. Its own separation (BoxContainerTight, 4) puts a caption under
## its button; every other gap is a spacer before a row, sized by _fit_to_canvas. A caption
## stands AFTER_CAPTION_GAP above the next control, so it reads with its own button; stacked
## buttons stand STACK_GAP_ROOMY apart, or STACK_GAP when the canvas is short; the three
## section gaps (under the wordmark, above and below the divider) take what is left, from
## their SECTION_GAPS size down to SECTION_GAP_MIN. The column is measured against the room
## the hub's margins leave it (they keep the bottom-left version label clear), and tightens
## only by what that room needs: the stacked gaps first, then the sections, evenly
## (docs/THEME_GUIDE.md, Interface size).
const AFTER_CAPTION_GAP := 12.0
const STACK_GAP := 8.0
const STACK_GAP_ROOMY := 12.0
## Under the wordmark, above the divider, below it.
const SECTION_GAPS: Array[float] = [36.0, 32.0, 32.0]
const SECTION_GAP_MIN := 12.0

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
var host_subtitle: Label
var play_subtitle: Label
var heading_count: Label
var empty_caption: Label
var grid: LevelGrid
## The left column's spacers: the three section gaps in order, and the gap before each
## button after Host's.
var _section_gaps: Array[Control] = []
var _row_gaps: Array[Control] = []

@onready var _hub: MarginContainer = %Hub
@onready var _left: VBoxContainer = %LeftColumn
@onready var _right: VBoxContainer = %RightZone
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	# The hub's text sits straight on the backdrop, so the backdrop takes the paper theme's
	# sky role (ink reads 9:1 on it) until the painted backdrop lands; the dark dim goes.
	var backdrop := $ColorRect as ColorRect
	backdrop.color = ThemeColors.of(backdrop, ThemeColors.BACKDROP)
	($Dim as CanvasItem).visible = false
	_build_left_column()
	_build_right_zone()
	_version_label.text = "v" + UpdateVersion.get_current()
	_version_label.modulate.a = 0.0
	grid.refresh()
	_preselect_most_recent()
	_refresh_actions()
	_play_entrance_animation()
	get_viewport().size_changed.connect(_fit_to_canvas)
	_fit_to_canvas()
	LevelManager.level_saved.connect(_on_level_saved)
	get_tree().node_added.connect(_on_node_added_or_removed)
	get_tree().node_removed.connect(_on_node_added_or_removed)


func _exit_tree() -> void:
	if LevelManager.level_saved.is_connected(_on_level_saved):
		LevelManager.level_saved.disconnect(_on_level_saved)


func selected_level() -> Dictionary:
	return grid.selected_info()


## Fit the left column to the canvas height: roomy when it fits, else stacked buttons at
## STACK_GAP, then the section gaps shrunk evenly by what is still over.
func _fit_to_canvas() -> void:
	if _section_gaps.is_empty():
		return
	var margins := (
		_hub.get_theme_constant(&"margin_top") + _hub.get_theme_constant(&"margin_bottom")
	)
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
## height is its gap less the column's separation above and below it.
func _set_gaps(stack: float, squeeze: float) -> void:
	var separation := float(_left.get_theme_constant(&"separation"))
	for i in _section_gaps.size():
		var gap := lerpf(SECTION_GAPS[i], SECTION_GAP_MIN, squeeze)
		_section_gaps[i].custom_minimum_size.y = maxf(gap - 2.0 * separation, 0.0)
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
	var wordmark := Label.new()
	wordmark.name = "Wordmark"
	wordmark.text = "TTSim"
	wordmark.theme_type_variation = &"Wordmark"
	_left.add_child(wordmark)
	_section_gaps.append(UiActions.spacer(0, _left))
	host_button = UiActions.primary(
		"Host Game", "network", "Start a table and invite players", _left
	)
	host_subtitle = UiActions.subtitle_of(host_button)
	host_button.pressed.connect(_on_host_pressed)
	# One persimmon fill per screen (C5): Host is the primary, Join stands beside it quietly.
	_row_gaps.append(UiActions.spacer(0, _left))
	join_button = UiActions.primary(
		"Join Game", "users", "Enter a room code", _left, &"Secondary"
	)
	join_button.pressed.connect(_on_join_pressed)
	_section_gaps.append(UiActions.spacer(0, _left))
	_left.add_child(HSeparator.new())
	_section_gaps.append(UiActions.spacer(0, _left))
	play_button = UiActions.secondary("Play Solo", "map", _left)
	play_subtitle = UiActions.subtitle_of(play_button)
	play_button.pressed.connect(_on_play_pressed)
	editor_button = _stacked("Level Editor", "wand")
	editor_button.pressed.connect(_on_editor_pressed)
	build_map_button = _stacked("Build Map", "brush")
	build_map_button.pressed.connect(_on_build_map_pressed)
	avatars_button = _stacked("Avatars", "mood-smile")
	avatars_button.tooltip_text = "Make your characters ahead of time; place them in any game"
	avatars_button.pressed.connect(_on_avatars_pressed)
	avatars_button.visible = DevFeatures.avatars
	settings_button = _stacked("Settings", "settings")
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = _stacked("Quit", "x")
	quit_button.pressed.connect(_on_quit_pressed)


## A Secondary button in the lower stack, after its row gap.
func _stacked(label: String, icon: String) -> Button:
	_row_gaps.append(UiActions.spacer(0, _left))
	return UiActions.secondary(label, icon, _left)


func _build_right_zone() -> void:
	var heading_row := HBoxContainer.new()
	heading_row.name = "Heading"
	heading_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var heading := Label.new()
	heading.text = "Your levels"
	heading.theme_type_variation = &"H2"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	heading_count = Label.new()
	heading_count.name = "Count"
	heading_count.theme_type_variation = &"Caption"
	heading_row.add_child(heading_count)
	_right.add_child(heading_row)
	empty_caption = Label.new()
	empty_caption.name = "Empty"
	empty_caption.text = EMPTY_CAPTION
	empty_caption.theme_type_variation = &"Caption"
	empty_caption.visible = false
	_right.add_child(empty_caption)
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


## Host and Play Solo name the selected level and are disabled without one.
func _refresh_actions() -> void:
	var count := grid.card_count()
	heading_count.text = "%d level%s" % [count, "" if count == 1 else "s"]
	empty_caption.visible = count == 0
	var info := grid.selected_info()
	var has_level := not info.is_empty()
	host_button.disabled = not has_level
	play_button.disabled = not has_level
	host_subtitle.visible = has_level
	play_subtitle.visible = has_level
	var name := String(info.get("name", ""))
	host_subtitle.text = "with %s" % name if has_level else ""
	play_subtitle.text = name
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
	version_tween.tween_property(_version_label, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(
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


func _on_host_pressed() -> void:
	var info := grid.selected_info()
	if info.is_empty():
		return
	host_game_requested.emit(info)


func _on_join_pressed() -> void:
	join_game_requested.emit()


func _on_play_pressed() -> void:
	var info := grid.selected_info()
	if info.is_empty():
		return
	play_solo_requested.emit(info)


func _on_editor_pressed() -> void:
	# The Level Editor button opens the editor with no particular level chosen; the
	# per-card Edit action is what names one.
	EventBus.open_editor_requested.emit("")


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
