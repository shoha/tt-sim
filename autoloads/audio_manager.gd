extends Node

## Centralized audio management for UI and game sounds.
##
## Provides easy access to play common UI sounds and manages audio buses.
## Call AudioManager.play_ui_*() from anywhere to play sounds.

# Audio bus names
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

const SETTINGS_PATH := "user://settings.cfg"

# UI Sound effects (paths will be updated when actual audio files are added)
var _ui_sounds := {
	"click": null,  # "res://assets/audio/ui/click.wav"
	"hover": null,  # "res://assets/audio/ui/hover.wav"
	"open": null,  # "res://assets/audio/ui/open.wav"
	"close": null,  # "res://assets/audio/ui/close.wav"
	"success": null,  # "res://assets/audio/ui/success.wav"
	"error": null,  # "res://assets/audio/ui/error.wav"
	"confirm": null,  # "res://assets/audio/ui/confirm.wav"
	"cancel": null,  # "res://assets/audio/ui/cancel.wav"
	"tick": null,  # "res://assets/audio/ui/tick.wav" — slider/toggle feedback
	"transition": null,  # "res://assets/audio/ui/transition.wav" — scene transitions
}

# SFX Sound effects for game interactions (token pickup, drop, slide, etc.)
var _sfx_sounds := {
	"token_pickup": null,  # "res://assets/audio/sfx/token_pickup.wav"
	"token_drop": null,  # "res://assets/audio/sfx/token_drop.wav"
	"token_slide": null,  # "res://assets/audio/sfx/token_slide.wav"
	"token_hover": null,  # "res://assets/audio/sfx/token_hover.wav"
	"token_whoosh": null,  # "res://assets/audio/sfx/token_whoosh.wav"
}

# Audio players pool for UI sounds
var _ui_players: Array[AudioStreamPlayer] = []
const UI_PLAYER_POOL_SIZE := 4

# Audio players pool for SFX sounds
var _sfx_players: Array[AudioStreamPlayer] = []
const SFX_PLAYER_POOL_SIZE := 4


func _ready() -> void:
	# Create audio player pool for UI sounds
	for i in range(UI_PLAYER_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = BUS_UI
		add_child(player)
		_ui_players.append(player)

	# Create audio player pool for SFX sounds
	for i in range(SFX_PLAYER_POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_sfx_players.append(player)

	# Load sounds if they exist
	_load_ui_sounds()
	_load_sfx_sounds()

	# Apply saved audio settings (bus volumes) on startup
	_load_audio_settings()

	# Auto-connect button sounds so every button gets click/hover sounds
	# automatically. To opt a button out, call button.set_meta("ui_silent", true).
	get_tree().node_added.connect(_on_node_added)


# ---------------------------------------------------------------------------
# Auto-connect button sounds
# ---------------------------------------------------------------------------


## Called when any node is added to the scene tree.
## Automatically connects press/hover sounds to BaseButton descendants.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		# Defer so the node is fully ready and any meta set during _ready() is applied
		node.ready.connect(_auto_connect_button.bind(node), CONNECT_ONE_SHOT)


func _auto_connect_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if button.has_meta("ui_silent"):
		return

	# CheckButtons / CheckBoxes use toggle sounds instead of click
	if button is CheckButton or button is CheckBox:
		if not button.toggled.is_connected(_on_toggle_sound):
			button.toggled.connect(_on_toggle_sound)
	else:
		if not button.pressed.is_connected(play_click):
			button.pressed.connect(play_click)

	# Hover sounds for regular buttons only (toggles already have tick feedback)
	if not (button is CheckButton or button is CheckBox):
		if not button.mouse_entered.is_connected(_on_button_hover):
			button.mouse_entered.connect(_on_button_hover)

	# Set pointing-hand cursor on all buttons for clickability feedback
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _on_button_hover() -> void:
	play_hover()


## Plays a higher-pitch tick on toggle-on and a lower-pitch tick on toggle-off
func _on_toggle_sound(toggled_on: bool) -> void:
	if toggled_on:
		play_ui_sound("tick", -6.0, 0.0)
	else:
		play_ui_sound("tick", -8.0, 0.0)


func _load_sounds(sounds: Dictionary, directory: String) -> void:
	for key in sounds.keys():
		for ext in ["wav", "ogg"]:
			var path = "res://assets/audio/%s/%s.%s" % [directory, key, ext]
			if ResourceLoader.exists(path):
				sounds[key] = load(path)
				break


func _load_ui_sounds() -> void:
	_load_sounds(_ui_sounds, "ui")


func _load_sfx_sounds() -> void:
	_load_sounds(_sfx_sounds, "sfx")


## Load saved audio bus volumes from settings.cfg and apply them.
## Called once at startup so the game respects the user's previous volume choices.
func _load_audio_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err != OK:
		return  # No saved settings — buses stay at default (100%)

	var buses := {
		BUS_MASTER: config.get_value("audio", "master", 100.0),
		BUS_MUSIC: config.get_value("audio", "music", 100.0),
		BUS_SFX: config.get_value("audio", "sfx", 100.0),
		BUS_UI: config.get_value("audio", "ui", 100.0),
	}

	for bus_name in buses:
		set_bus_volume(bus_name, buses[bus_name] / 100.0)


## Play a UI sound by name
## pitch_variation: random pitch offset range (e.g. 0.08 = +/- 8%). Set to 0.0 for exact pitch.
func play_ui_sound(
	sound_name: String, volume_db: float = 0.0, pitch_variation: float = 0.08
) -> void:
	if not _ui_sounds.has(sound_name) or _ui_sounds[sound_name] == null:
		return

	var player = _get_available_player()
	if player:
		player.stream = _ui_sounds[sound_name]
		player.volume_db = volume_db
		player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
		player.play()


## Play button click sound
func play_click() -> void:
	play_ui_sound("click")


## Play button hover sound
func play_hover() -> void:
	play_ui_sound("hover", -6.0)


## Play menu/panel open sound
func play_open() -> void:
	play_ui_sound("open")


## Play menu/panel close sound
func play_close() -> void:
	play_ui_sound("close")


## Play success/confirm sound
func play_success() -> void:
	play_ui_sound("success")


## Play error sound
func play_error() -> void:
	play_ui_sound("error")


## Play confirmation dialog confirm sound
func play_confirm() -> void:
	play_ui_sound("confirm")


## Play cancel/back sound
func play_cancel() -> void:
	play_ui_sound("cancel")


## Play a subtle tick sound (slider / toggle / checkbox feedback)
func play_tick() -> void:
	play_ui_sound("tick", -8.0, 0.12)


## Play transition whoosh (scene / state transitions)
func play_transition() -> void:
	play_ui_sound("transition", -3.0, 0.0)


## Play a SFX sound by name
## pitch_variation: random pitch offset range (e.g. 0.08 = +/- 8%). Set to 0.0 for exact pitch.
func play_sfx(sound_name: String, volume_db: float = 0.0, pitch_variation: float = 0.08) -> void:
	if not _sfx_sounds.has(sound_name) or _sfx_sounds[sound_name] == null:
		return

	var player = _get_available_sfx_player()
	if player:
		player.stream = _sfx_sounds[sound_name]
		player.volume_db = volume_db
		player.pitch_scale = 1.0 + randf_range(-pitch_variation, pitch_variation)
		player.play()


## Play token pickup sound (short click/pop)
func play_token_pickup() -> void:
	play_sfx("token_pickup")


## Play token drop/place sound (soft thud)
func play_token_drop() -> void:
	play_sfx("token_drop")


## Play token slide sound (faint movement sound)
func play_token_slide() -> void:
	play_sfx("token_slide", -3.0)


## Play token hover sound (subtle highlight cue)
func play_token_hover() -> void:
	play_sfx("token_hover", -6.0)


## Play token whoosh sound (rapid drag movement)
## pitch_scale allows velocity-based pitch scaling for a natural feel.
func play_token_whoosh(pitch_scale: float = 1.0) -> void:
	var player = _get_available_sfx_player()
	if player and _sfx_sounds.has("token_whoosh") and _sfx_sounds["token_whoosh"] != null:
		player.stream = _sfx_sounds["token_whoosh"]
		player.volume_db = -3.0
		player.pitch_scale = pitch_scale + randf_range(-0.08, 0.08)
		player.play()


func _get_available_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_players:
		if not player.playing:
			return player
	return _sfx_players[0] if _sfx_players.size() > 0 else null


func _get_available_player() -> AudioStreamPlayer:
	for player in _ui_players:
		if not player.playing:
			return player
	# If all are busy, return the first one (it will interrupt)
	return _ui_players[0] if _ui_players.size() > 0 else null


## Set volume for a bus (0.0 to 1.0)
func set_bus_volume(bus_name: String, volume: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		var db = linear_to_db(clampf(volume, 0.0, 1.0))
		AudioServer.set_bus_volume_db(bus_idx, db)


## Get volume for a bus (0.0 to 1.0)
func get_bus_volume(bus_name: String) -> float:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		return db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	return 1.0


## Mute/unmute a bus
func set_bus_mute(bus_name: String, muted: bool) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_mute(bus_idx, muted)


## Check if a bus is muted
func is_bus_muted(bus_name: String) -> bool:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		return AudioServer.is_bus_mute(bus_idx)
	return false
