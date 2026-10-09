class_name SoundRequestQueue
extends RefCounted

## The playback policy behind AudioManager.play(): which requests become sounds.
##
## The table comes from assets/audio/sfx_manifest.json, which tools/generate_sfx.py
## writes from tools/sfx_spec.py, so nothing here names a sound. Each entry carries the
## sound's Godot bus, file path, gain (volume_db), pitch jitter in semitones, cooldown
## in seconds and coalescing priority.
##
## A request names a sound and may add a gain offset and a base pitch for sounds that
## follow a quantity (a drop's height, a drag's speed). Requests collect until flush(),
## which AudioManager calls once a frame, and on each bus only the highest-priority
## request of that frame plays: one gesture that clicks, confirms and closes a dialog is
## heard as the confirm alone. Ties keep the earlier request. Buses coalesce separately,
## so a splash in the world is never silenced by a click in the menus.
##
## A sound still inside its cooldown since it last played is dropped when requested,
## before coalescing, so it cannot outrank a lower sound that would otherwise play. An
## unknown name is dropped with one warning per name, never silently.

const MANIFEST_PATH := "res://assets/audio/sfx_manifest.json"

## name (StringName) -> manifest entry Dictionary.
var _entries: Dictionary = {}
## Godot bus name -> the request that currently wins that bus this frame.
var _pending: Dictionary = {}
## name -> seconds at which it last played, for cooldowns.
var _last_played_s: Dictionary = {}
## Unknown names already warned about, so each warns once.
var _warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _init(entries: Dictionary = {}) -> void:
	_entries = entries
	_rng.randomize()


## Parses manifest JSON text into the entry table keyed by StringName. Returns an empty
## table when the text is not a manifest.
static func parse_manifest(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary or not data.get("sounds") is Dictionary:
		return {}
	var entries := {}
	var sounds: Dictionary = data["sounds"]
	for key in sounds:
		entries[StringName(key)] = sounds[key]
	return entries


## Reads and parses the manifest file. Warns and returns an empty table when it is
## missing or malformed, so the game runs silent rather than failing to start.
static func load_manifest(path: String = MANIFEST_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("SoundRequestQueue: no sound manifest at %s" % path)
		return {}
	var entries := parse_manifest(FileAccess.get_file_as_string(path))
	if entries.is_empty():
		push_warning("SoundRequestQueue: %s holds no sounds" % path)
	return entries


## The pitch scale for one play: `base` moved by `unit` (in [-1, 1]) times the jitter
## range in semitones. Never below 0.01, which AudioStreamPlayer rejects.
static func jittered_pitch(base: float, jitter_semitones: float, unit: float) -> float:
	return maxf(0.01, base * pow(2.0, jitter_semitones * unit / 12.0))


## Every sound name in the table, sorted; restricted to one Godot bus when given.
func names(bus: String = "") -> Array[StringName]:
	var out: Array[StringName] = []
	for key in _entries:
		if bus.is_empty() or str(_entries[key].get("bus", "")) == bus:
			out.append(key)
	out.sort()
	return out


## True when the table declares the sound.
func has_sound(sound: StringName) -> bool:
	return _entries.has(sound)


## The manifest entry for a sound, or an empty Dictionary when unknown.
func entry(sound: StringName) -> Dictionary:
	return _entries.get(sound, {})


## Queues a request at time `now_s` (seconds). Returns true when the request now holds
## its bus for this frame; false when it is unknown, cooling down or outranked.
func request(
	sound: StringName, now_s: float, volume_offset_db: float = 0.0, pitch_scale: float = 1.0
) -> bool:
	if not _entries.has(sound):
		if not _warned.has(sound):
			_warned[sound] = true
			push_warning("AudioManager: unknown sound '%s'; see tools/sfx_spec.py" % sound)
		return false
	var spec: Dictionary = _entries[sound]
	if _last_played_s.has(sound) and now_s - _last_played_s[sound] < _cooldown(spec):
		return false
	var bus := str(spec.get("bus", ""))
	if _pending.has(bus):
		var held: Dictionary = _entries[_pending[bus]["name"]]
		if _priority(held) >= _priority(spec):
			return false
	_pending[bus] = {
		"name": sound, "volume_offset_db": volume_offset_db, "pitch_scale": pitch_scale
	}
	return true


## True while a request waits for the next flush.
func has_pending() -> bool:
	return not _pending.is_empty()


## Ends the frame at `now_s`: returns what plays, one Dictionary per bus (name, bus,
## path, volume_db, pitch_scale), starts each winner's cooldown and clears the queue.
func flush(now_s: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var buses: Array = _pending.keys()
	buses.sort()
	for bus in buses:
		var req: Dictionary = _pending[bus]
		var sound: StringName = req["name"]
		var spec: Dictionary = _entries[sound]
		_last_played_s[sound] = now_s
		var jitter := float(spec.get("pitch_jitter", 0.0))
		var pitch := jittered_pitch(req["pitch_scale"], jitter, _rng.randf_range(-1.0, 1.0))
		var gain := float(spec.get("volume_db", 0.0)) + float(req["volume_offset_db"])
		var played := {
			"name": sound,
			"bus": bus,
			"path": str(spec.get("path", "")),
			"volume_db": gain,
			"pitch_scale": pitch,
		}
		out.append(played)
	_pending.clear()
	return out


## Unknown names warned about so far, in the order they were first requested.
func warned_names() -> Array:
	return _warned.keys()


static func _priority(spec: Dictionary) -> int:
	return int(spec.get("priority", 0))


static func _cooldown(spec: Dictionary) -> float:
	return float(spec.get("cooldown_s", 0.0))
