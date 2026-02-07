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

# UI Sound effects (paths will be updated when actual audio files are added)
var _ui_sounds := {
	"click": null, # "res://assets/audio/ui/click.wav"
	"hover": null, # "res://assets/audio/ui/hover.wav"
	"open": null, # "res://assets/audio/ui/open.wav"
	"close": null, # "res://assets/audio/ui/close.wav"
	"success": null, # "res://assets/audio/ui/success.wav"
	"error": null, # "res://assets/audio/ui/error.wav"
	"confirm": null, # "res://assets/audio/ui/confirm.wav"
	"cancel": null, # "res://assets/audio/ui/cancel.wav"
}

# SFX Sound effects for game interactions (token pickup, drop, slide, etc.)
var _sfx_sounds := {
	"token_pickup": null, # "res://assets/audio/sfx/token_pickup.wav"
	"token_drop": null, # "res://assets/audio/sfx/token_drop.wav"
	"token_slide": null, # "res://assets/audio/sfx/token_slide.wav"
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


func _load_ui_sounds() -> void:
	for key in _ui_sounds.keys():
		var path = "res://assets/audio/ui/%s.wav" % key
		if ResourceLoader.exists(path):
			_ui_sounds[key] = load(path)


func _load_sfx_sounds() -> void:
	for key in _sfx_sounds.keys():
		# Try .wav first, then .ogg
		for ext in ["wav", "ogg"]:
			var path = "res://assets/audio/sfx/%s.%s" % [key, ext]
			if ResourceLoader.exists(path):
				_sfx_sounds[key] = load(path)
				break


## Play a UI sound by name
func play_ui_sound(sound_name: String, volume_db: float = 0.0) -> void:
	if not _ui_sounds.has(sound_name) or _ui_sounds[sound_name] == null:
		return

	var player = _get_available_player()
	if player:
		player.stream = _ui_sounds[sound_name]
		player.volume_db = volume_db
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


## Play a SFX sound by name
func play_sfx(sound_name: String, volume_db: float = 0.0) -> void:
	if not _sfx_sounds.has(sound_name) or _sfx_sounds[sound_name] == null:
		return

	var player = _get_available_sfx_player()
	if player:
		player.stream = _sfx_sounds[sound_name]
		player.volume_db = volume_db
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
