extends Node

## The one place the game plays a sound: `AudioManager.play(&"name")`.
##
## Every sound, its bus, gain, pitch jitter, cooldown and priority is declared once in
## tools/sfx_spec.py. tools/generate_sfx.py --install renders the files and writes
## assets/audio/sfx_manifest.json, which this autoload loads at startup; there is no
## per-sound method or table here. play() hands the request to a SoundRequestQueue, and
## _process() plays at most one sound per bus per frame, the highest-priority one, so a
## gesture that clicks, confirms and closes a dialog is heard once as the confirm.
##
## Buttons get their click automatically (_on_node_added) and panels play open and close
## from their base classes; a button that plays a sound of its own sets the `ui_silent`
## meta. AudioManager runs with PROCESS_MODE_ALWAYS and the last process priority: the
## pause menu's sounds play while the tree is paused, a sound already playing when the
## game pauses finishes instead of freezing, and every request of a frame is in before
## the flush. Bus volumes (the Settings sliders) are set here too, through set_bus_volume.

## Emitted when a requested sound actually starts, after coalescing and cooldowns.
signal sound_played(sound: StringName)
## Emitted for every play() call, before cooldowns and coalescing decide whether it is heard:
## what the game asked for, which is what call-site tests check.
signal sound_requested(sound: StringName)

# Audio bus names
const BUS_MASTER := "Master"
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_UI := "UI"

## Set to true to re-enable the hover sound on buttons.
const BUTTON_HOVER_SOUND_ENABLED := false

## Set to true to re-enable the whoosh sound on fast token drags.
const TOKEN_WHOOSH_SOUND_ENABLED := false

## Voices per bus. When all are busy the first is stolen.
const PLAYER_POOL_SIZE := 4

## Runs the flush after every other node's _process, so one frame's requests coalesce.
const FLUSH_PROCESS_PRIORITY := 1000

## settings.cfg's [audio] key naming the taper its volume percentages were saved for. A file
## without it predates the squared taper: its percentages were linear gains.
const VOLUME_TAPER_KEY := "taper"
## The squared taper of slider_to_db (taper 1, the linear one, is the absent marker).
const VOLUME_TAPER := 2
## The [audio] keys holding the volume sliders' percentages, 0 to 100.
const VOLUME_KEYS: PackedStringArray = ["master", "music", "sfx", "ui"]

var _queue: SoundRequestQueue
## name -> AudioStream, for every manifest entry whose file exists.
var _streams: Dictionary = {}
## Godot bus name -> Array of AudioStreamPlayer.
var _players: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = FLUSH_PROCESS_PRIORITY

	_queue = SoundRequestQueue.new(SoundRequestQueue.load_manifest())
	_load_streams()
	for bus in [BUS_UI, BUS_SFX]:
		var pool: Array[AudioStreamPlayer] = []
		for i in range(PLAYER_POOL_SIZE):
			var player := AudioStreamPlayer.new()
			player.bus = bus
			add_child(player)
			pool.append(player)
		_players[bus] = pool

	# Apply saved audio settings (bus volumes) on startup
	_load_audio_settings()

	# Auto-connect button sounds so every button gets click/hover sounds
	# automatically. To opt a button out, call button.set_meta("ui_silent", true).
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	if _queue.has_pending():
		_play_requests(_queue.flush(_now_s()))


## Plays the named sound as the manifest declares it. `volume_offset_db` adds to the
## sound's own gain and `pitch_scale` multiplies its pitch, for sounds that follow a
## quantity (a drop's height, a drag's speed). Requests made in one frame coalesce: on
## each bus only the highest-priority one plays. A sound inside its cooldown is skipped,
## and an unknown name warns once and plays nothing.
func play(sound: StringName, volume_offset_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	sound_requested.emit(sound)
	_queue.request(sound, _now_s(), volume_offset_db, pitch_scale)


## Every sound name the manifest declares, sorted; only those on `bus` when given.
func sound_names(bus: String = "") -> Array[StringName]:
	return _queue.names(bus)


## True when the manifest declares the sound.
func has_sound(sound: StringName) -> bool:
	return _queue.has_sound(sound)


## The manifest entry for a sound (bus, path, volume_db, pitch_jitter, cooldown_s,
## priority), or an empty Dictionary when unknown.
func sound_entry(sound: StringName) -> Dictionary:
	return _queue.entry(sound)


## Unknown names play() has warned about since startup.
func warned_names() -> Array:
	return _queue.warned_names()


# ---------------------------------------------------------------------------
# Auto-connect button sounds
# ---------------------------------------------------------------------------


## Called when any node is added to the scene tree.
## Automatically connects press/hover sounds to BaseButton descendants.
func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		# Defer so the node is fully ready and any meta set during _ready() is applied
		var callable := _auto_connect_button.bind(node)
		if not node.ready.is_connected(callable):
			node.ready.connect(callable, CONNECT_ONE_SHOT)


func _auto_connect_button(button: BaseButton) -> void:
	if not is_instance_valid(button):
		return
	if button.has_meta("ui_silent"):
		return

	# CheckButtons / CheckBoxes tick instead of clicking. The tick listens to `pressed`,
	# which only the user's click emits, not `toggled`, which also fires when code sets
	# button_pressed (Settings loading saved values, Reset): those changes stay silent.
	if button is CheckButton or button is CheckBox:
		var tick := _on_toggle_sound.bind(button)
		if not button.pressed.is_connected(tick):
			button.pressed.connect(tick)
	else:
		if not button.pressed.is_connected(_on_button_pressed):
			button.pressed.connect(_on_button_pressed)

	# Hover sounds for regular buttons only (toggles already have tick feedback)
	if BUTTON_HOVER_SOUND_ENABLED and not (button is CheckButton or button is CheckBox):
		if not button.mouse_entered.is_connected(_on_button_hover):
			button.mouse_entered.connect(_on_button_hover)

	# Set pointing-hand cursor on all buttons for clickability feedback
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


func _on_button_pressed() -> void:
	play(&"click")


func _on_button_hover() -> void:
	play(&"hover")


## Plays the tick for a toggle the user clicked, 2 dB louder when it turned on than when
## it turned off (`pressed` is emitted after the state flips).
func _on_toggle_sound(button: BaseButton) -> void:
	play(&"tick", 2.0 if button.button_pressed else 0.0)


# ---------------------------------------------------------------------------
# Playback
# ---------------------------------------------------------------------------


func _load_streams() -> void:
	for sound in _queue.names():
		var path := str(_queue.entry(sound).get("path", ""))
		if ResourceLoader.exists(path):
			_streams[sound] = load(path)


func _play_requests(requests: Array[Dictionary]) -> void:
	for req in requests:
		var sound: StringName = req["name"]
		var stream: AudioStream = _streams.get(sound)
		var player := _get_available_player(str(req["bus"]))
		if stream == null or player == null:
			continue
		player.stream = stream
		player.volume_db = req["volume_db"]
		player.pitch_scale = req["pitch_scale"]
		player.play()
		sound_played.emit(sound)


func _get_available_player(bus: String) -> AudioStreamPlayer:
	var pool: Array = _players.get(bus, [])
	for player in pool:
		if not player.playing:
			return player
	# If all are busy, return the first one (it will interrupt)
	return pool[0] if pool.size() > 0 else null


func _now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


# ---------------------------------------------------------------------------
# Bus volumes
# ---------------------------------------------------------------------------


## Load saved audio bus volumes from settings.cfg and apply them.
## Called once at startup so the game respects the user's previous volume choices. Every
## launch passes here before anything else reads the volumes, so this is where a file saved
## before the squared taper is migrated (load_migrated_settings).
func _load_audio_settings() -> void:
	var config := load_migrated_settings(Paths.SETTINGS_PATH)
	if config == null:
		return  # No saved settings — buses stay at default (100%)

	var buses := {
		BUS_MASTER: config.get_value("audio", "master", 100.0),
		BUS_MUSIC: config.get_value("audio", "music", 100.0),
		BUS_SFX: config.get_value("audio", "sfx", 100.0),
		BUS_UI: config.get_value("audio", "ui", 100.0),
	}

	for bus_name in buses:
		set_bus_volume(bus_name, buses[bus_name] / 100.0)


## The bus gain in dB for a volume slider position (0.0 to 1.0). The taper is squared:
## gain = position^2, so half way is -12 dB, a quarter is -24 dB, a tenth -40 dB and zero
## is silent. Loudness grows with roughly the 0.6 power of sound pressure (Stevens), so
## pressure ~ position^1.7 makes the slider track how loud it sounds; squared is the
## nearest simple curve. A linear taper put half way at only -6 dB, so the top half of
## the slider barely changed anything and the bottom tenth did everything.
static func slider_to_db(position: float) -> float:
	var p := clampf(position, 0.0, 1.0)
	return linear_to_db(p * p)


## The slider position (0.0 to 1.0) that slider_to_db maps to `db`.
static func db_to_slider(db: float) -> float:
	return clampf(sqrt(db_to_linear(db)), 0.0, 1.0)


## Loads the settings file at `path`, first migrating volumes saved for the linear taper
## (migrate_volume_taper) and writing the migration back, so it happens once. Returns null
## when there is no readable file: a fresh install has nothing to convert and gets no file
## here; SettingsMenu stamps the taper marker whenever it saves the volumes.
static func load_migrated_settings(path: String) -> ConfigFile:
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return null
	if migrate_volume_taper(config):
		var err := config.save(path)
		if err != OK:
			push_warning("AudioManager: could not save the volume taper migration: %d" % err)
	return config


## Converts the volume percentages in `config` from the linear taper they were saved for to
## the squared one at the same loudness, and stamps audio/taper so it never runs twice. A
## linear percentage p played at gain p/100 and the squared taper plays q at (q/100)^2, so
## q = 100 sqrt(p/100): a saved 50% (-6 dB) becomes 70.7%. The value stays unrounded, so the
## gain is exact; the slider shows it to its 1% step. Only the volume keys present change.
## Returns true when it changed `config`, false for a config already stamped.
static func migrate_volume_taper(config: ConfigFile) -> bool:
	if int(config.get_value("audio", VOLUME_TAPER_KEY, 1)) >= VOLUME_TAPER:
		return false
	for key in VOLUME_KEYS:
		if not config.has_section_key("audio", key):
			continue
		var saved: Variant = config.get_value("audio", key)
		if saved is float or saved is int:
			var gain := clampf(float(saved) / 100.0, 0.0, 1.0)
			config.set_value("audio", key, sqrt(gain) * 100.0)
	config.set_value("audio", VOLUME_TAPER_KEY, VOLUME_TAPER)
	return true


## Sets a bus's volume from a slider position (0.0 to 1.0), through slider_to_db.
func set_bus_volume(bus_name: String, volume: float) -> void:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		AudioServer.set_bus_volume_db(bus_idx, slider_to_db(volume))


## A bus's volume as a slider position (0.0 to 1.0), the inverse of set_bus_volume.
func get_bus_volume(bus_name: String) -> float:
	var bus_idx = AudioServer.get_bus_index(bus_name)
	if bus_idx >= 0:
		return db_to_slider(AudioServer.get_bus_volume_db(bus_idx))
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
