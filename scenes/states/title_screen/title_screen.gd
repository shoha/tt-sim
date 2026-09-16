class_name TitleScreen
extends CanvasLayer

## Title hub. Host and Join lead; the saved levels sit beside them as cards and
## the selected card is the level a host starts with (or Play Solo opens).
## The d20 sub-viewport stays as a dimmed backdrop.

signal host_game_requested(level_info: Dictionary)
signal join_game_requested
signal play_solo_requested(level_info: Dictionary)

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := Constants.ANIM_ENTRANCE_STAGGER
const ENTRANCE_DURATION := Constants.ANIM_ENTRANCE
const EMPTY_CAPTION := "Make a level in the Level Editor first"

## Returns the level info list; tests inject a fake before the node enters the tree.
var level_provider: Callable = LevelManager.get_saved_levels

var host_button: Button
var join_button: Button
var play_button: Button
var editor_button: Button
var settings_button: Button
var quit_button: Button
var host_subtitle: Label
var play_subtitle: Label
var heading_count: Label
var empty_caption: Label
var grid: LevelGrid

@onready var _left: VBoxContainer = %LeftColumn
@onready var _right: VBoxContainer = %RightZone
@onready var _version_label: Label = %VersionLabel


func _ready() -> void:
	_build_left_column()
	_build_right_zone()
	_version_label.text = "v" + UpdateVersion.get_current()
	_version_label.modulate.a = 0.0
	grid.refresh()
	_preselect_most_recent()
	_refresh_actions()
	_play_entrance_animation()
	LevelManager.level_saved.connect(_on_level_saved)


func _exit_tree() -> void:
	if LevelManager.level_saved.is_connected(_on_level_saved):
		LevelManager.level_saved.disconnect(_on_level_saved)


func selected_level() -> Dictionary:
	return grid.selected_info()


func _build_left_column() -> void:
	var wordmark := Label.new()
	wordmark.name = "Wordmark"
	wordmark.text = "TTSim"
	wordmark.theme_type_variation = &"H1"
	# H1 is 18 px in this theme; the wordmark is the one place a display size
	# is wanted, so override rather than add a variation for a single label.
	wordmark.add_theme_font_size_override("font_size", 36)
	_left.add_child(wordmark)
	UiActions.spacer(12, _left)
	host_button = UiActions.primary(
		"Host Game", "network", "Start a table and invite players", _left
	)
	host_subtitle = UiActions.subtitle_of(host_button)
	host_button.pressed.connect(_on_host_pressed)
	join_button = UiActions.primary("Join Game", "users", "Enter a room code", _left)
	join_button.pressed.connect(_on_join_pressed)
	UiActions.spacer(8, _left)
	_left.add_child(HSeparator.new())
	UiActions.spacer(8, _left)
	play_button = UiActions.secondary("Play Solo", "map", _left)
	play_subtitle = UiActions.subtitle_of(play_button)
	play_button.pressed.connect(_on_play_pressed)
	editor_button = UiActions.secondary("Level Editor", "wand", _left)
	editor_button.pressed.connect(_on_editor_pressed)
	settings_button = UiActions.secondary("Settings", "settings", _left)
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = UiActions.secondary("Quit", "x", _left)
	quit_button.pressed.connect(_on_quit_pressed)


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
	heading_count.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
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


func _play_entrance_animation() -> void:
	var targets := UiMotion.visible_children(_left)
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
	EventBus.open_editor_requested.emit()


func _on_settings_pressed() -> void:
	var settings_menu := SettingsMenuScene.instantiate()
	get_tree().root.add_child(settings_menu)


func _on_quit_pressed() -> void:
	get_tree().quit()
