class_name TitleScreen
extends CanvasLayer

## Title hub. Host and Join lead; the saved levels sit beside them as cards and
## the selected card is the level a host starts with (or Play Solo opens).
## The d20 sub-viewport stays as a dimmed backdrop.

signal host_game_requested(level_info: Dictionary)
signal join_game_requested
signal play_solo_requested(level_info: Dictionary)

const SettingsMenuScene := preload("res://scenes/ui/settings_menu.tscn")
const ENTRANCE_STAGGER := 0.08
const ENTRANCE_DURATION := 0.3
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
	_left.add_child(_spacer(12))
	host_button = _primary_action("Host Game", "network", "Start a table and invite players")
	host_subtitle = _subtitle_of(host_button)
	host_button.pressed.connect(_on_host_pressed)
	join_button = _primary_action("Join Game", "users", "Enter a room code")
	join_button.pressed.connect(_on_join_pressed)
	_left.add_child(_spacer(8))
	_left.add_child(HSeparator.new())
	_left.add_child(_spacer(8))
	play_button = _secondary_action("Play Solo", "map")
	play_subtitle = _subtitle_of(play_button)
	play_button.pressed.connect(_on_play_pressed)
	editor_button = _secondary_action("Level Editor", "wand")
	editor_button.pressed.connect(_on_editor_pressed)
	settings_button = _secondary_action("Settings", "settings")
	settings_button.pressed.connect(_on_settings_pressed)
	quit_button = _secondary_action("Quit", "x")
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
	_right.add_child(grid)


## A tall accent button with an icon, a bold label and a caption underneath.
func _primary_action(label: String, icon: String, caption: String) -> Button:
	var button := AnimatedButton.new()
	button.name = label.replace(" ", "")
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 56)
	button.expand_icon = false
	_left.add_child(button)
	var caption_label := Label.new()
	caption_label.name = "Caption"
	caption_label.text = caption
	caption_label.theme_type_variation = &"Caption"
	caption_label.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	_left.add_child(caption_label)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = &"Caption"
	subtitle.visible = false
	_left.add_child(subtitle)
	button.set_meta("subtitle", subtitle)
	return button


func _secondary_action(label: String, icon: String) -> Button:
	var button := AnimatedButton.new()
	button.name = label.replace(" ", "")
	button.text = label
	button.icon = IconButton.load_icon(icon)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.theme_type_variation = &"Secondary"
	button.custom_minimum_size = Vector2(0, 36)
	_left.add_child(button)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = &"Caption"
	subtitle.add_theme_color_override("font_color", ThemeColors.TEXT_MUTED)
	subtitle.visible = false
	_left.add_child(subtitle)
	button.set_meta("subtitle", subtitle)
	return button


func _subtitle_of(button: Button) -> Label:
	return button.get_meta("subtitle") as Label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


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
	var targets: Array[Control] = []
	for child in _left.get_children():
		if child is Control and child.visible:
			targets.append(child)
	for child in _right.get_children():
		if child is Control and child.visible:
			targets.append(child)
	for control in targets:
		control.modulate.a = 0.0
	# Let every container in both columns settle its layout (the right column's
	# sort cascades from the Columns HBox sizing it) before capturing target
	# positions; capturing early leaves the grid tweened onto the heading.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self):
		return
	for i in range(targets.size()):
		var control := targets[i]
		var target_y := control.position.y
		control.position.y = target_y + 12.0
		var tween := create_tween()
		tween.set_parallel(true)
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		var delay := i * ENTRANCE_STAGGER
		tween.tween_property(control, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(delay)
		tween.tween_property(control, "position:y", target_y, ENTRANCE_DURATION).set_delay(delay)
	var version_tween := create_tween()
	version_tween.set_ease(Tween.EASE_OUT)
	version_tween.set_trans(Tween.TRANS_CUBIC)
	version_tween.tween_property(_version_label, "modulate:a", 1.0, ENTRANCE_DURATION).set_delay(
		targets.size() * ENTRANCE_STAGGER
	)


func _on_selection_changed(_info: Dictionary) -> void:
	_refresh_actions()


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
