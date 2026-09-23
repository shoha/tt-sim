extends Control
## Standalone soundboard for auditioning candidate sound effects through Godot's real
## audio buses (UI / SFX), including their lo-fi filter + reverb effects.
##
## Candidate files are produced by a Python tool into a scratch directory (not part of
## the repo). Run this scene directly (F6 in editor, or via the CLI) to audition them.

const BUS_UI := "UI"
const BUS_SFX := "SFX"
const PLAY_ALL_INTERVAL_SEC := 0.6
const GRID_COLUMNS := 4

@export var candidates_dir: String = ""

var _resolved_dir: String = ""
var _ui_player: AudioStreamPlayer
var _sfx_player: AudioStreamPlayer
var _status_label: Label
var _play_all_buttons: Array[Button] = []
var _playing_all: bool = false


func _ready() -> void:
	_resolved_dir = (
		candidates_dir
		if not candidates_dir.is_empty()
		else OS.get_environment("TEMP").path_join("tt-sim-sfx")
	)
	print("Soundboard: resolved candidates directory: %s" % _resolved_dir)

	_ui_player = AudioStreamPlayer.new()
	_ui_player.bus = BUS_UI
	add_child(_ui_player)

	_sfx_player = AudioStreamPlayer.new()
	_sfx_player.bus = BUS_SFX
	add_child(_sfx_player)

	_build_ui()


func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(vbox)

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)

	# The AudioManager autoload's own sound dictionaries are the game's single source
	# of truth for which sounds exist and which bus each belongs to. Reading them
	# directly (rather than hardcoding a parallel list here) means this soundboard
	# can never drift out of sync with the real game. They are `_`-prefixed because
	# AudioManager treats them as implementation detail for everyone except this dev
	# tool, which the user has approved reaching in for exactly this reason.
	var ui_names: Array = AudioManager._ui_sounds.keys()
	ui_names.sort()
	var sfx_names: Array = AudioManager._sfx_sounds.keys()
	sfx_names.sort()

	var ui_tab := _build_bus_tab(ui_names, BUS_UI)
	ui_tab.name = "UI"
	tabs.add_child(ui_tab)

	var sfx_tab := _build_bus_tab(sfx_names, BUS_SFX)
	sfx_tab.name = "SFX"
	tabs.add_child(sfx_tab)

	_status_label = Label.new()
	if DirAccess.dir_exists_absolute(_resolved_dir):
		_status_label.text = "candidates directory: %s" % _resolved_dir
	else:
		_status_label.text = "candidates directory not found: %s" % _resolved_dir
	vbox.add_child(_status_label)


func _build_bus_tab(names: Array, bus_name: String) -> Control:
	var container := VBoxContainer.new()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var play_all_button := Button.new()
	play_all_button.set_meta("ui_silent", true)
	play_all_button.text = "Play all in order"
	play_all_button.pressed.connect(_on_play_all_pressed.bind(names, bus_name))
	container.add_child(play_all_button)
	_play_all_buttons.append(play_all_button)

	var grid := GridContainer.new()
	grid.columns = GRID_COLUMNS
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.add_child(grid)

	for sound_name in names:
		grid.add_child(_build_sound_button(sound_name, bus_name))

	return container


func _build_sound_button(sound_name: String, bus_name: String) -> Button:
	var button := Button.new()
	# CRITICAL: must be set before the button enters the tree, or AudioManager's
	# node_added-driven auto-connect will wire the currently-installed click.wav on
	# top of every candidate we're trying to audition.
	button.set_meta("ui_silent", true)

	if FileAccess.file_exists(_candidate_path(sound_name)):
		button.text = sound_name
		button.pressed.connect(_on_sound_button_pressed.bind(sound_name, bus_name))
	else:
		button.text = "%s (missing)" % sound_name
		button.disabled = true

	return button


func _candidate_path(sound_name: String) -> String:
	return _resolved_dir.path_join(sound_name + ".wav")


func _on_sound_button_pressed(sound_name: String, bus_name: String) -> void:
	_play_sound(sound_name, bus_name)


## Loads fresh from disk on every call -- no caching. These are 18 short (60-800 ms)
## mono files that get regenerated under the same filenames while this scene stays
## open (listen, retune, regenerate, listen again), so a cached stream would silently
## serve stale audio the user has already asked to change. Loading is cheap enough at
## this size that caching would be an optimization with no measurable benefit and a
## real correctness cost.
func _play_sound(sound_name: String, bus_name: String) -> void:
	var stream := AudioStreamWAV.load_from_file(_candidate_path(sound_name))
	if stream == null:
		_status_label.text = "%s  -  FAILED TO LOAD" % sound_name
		return

	var player := _ui_player if bus_name == BUS_UI else _sfx_player
	player.stream = stream
	player.play()

	var duration_ms := roundi(stream.get_length() * 1000.0)
	_status_label.text = "%s  -  %s bus  -  %d ms" % [sound_name, bus_name, duration_ms]


func _on_play_all_pressed(names: Array, bus_name: String) -> void:
	if _playing_all:
		return

	var existing_names: Array = []
	for sound_name in names:
		if FileAccess.file_exists(_candidate_path(sound_name)):
			existing_names.append(sound_name)

	_playing_all = true
	_set_play_all_buttons_disabled(true)

	for sound_name in existing_names:
		if not is_instance_valid(self):
			return
		_play_sound(sound_name, bus_name)
		await get_tree().create_timer(PLAY_ALL_INTERVAL_SEC).timeout

	if is_instance_valid(self):
		_playing_all = false
		_set_play_all_buttons_disabled(false)


func _set_play_all_buttons_disabled(disabled: bool) -> void:
	for button in _play_all_buttons:
		if is_instance_valid(button):
			button.disabled = disabled
