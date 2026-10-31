extends Node

## The one global wind (docs/systems/wind.md). Holds the current immutable WindState, eases
## it toward a new target when a level's weather changes, and publishes three global shader
## uniforms (wind_dir, wind_phase, wind_gust) that the foliage shaders read. The wind is a pure
## function of the wind clock, the state and its seed (WindModel), so every peer that receives
## the same weather settings draws the same gusts with no per-frame traffic.
##
## Every uniform is pushed only when its value changed (the canopy_fade.gd pattern). The phases
## move every frame, the direction while it veers or blends, the amplitudes only on a change.

## Seconds a change of weather takes to arrive (exponential approach, about 95 percent by then).
const BLEND_SECONDS := 2.5
## How often the OS reduce-motion setting is polled.
const REDUCED_POLL_SECONDS := 1.0
## The per-player [graphics] setting key and its default (a scale on amplitudes, never the clock).
const SETTING_KEY := "wind_motion"
const DEFAULT_WIND_MOTION := 1.0

const GLOBAL_DIR := "wind_dir"
const GLOBAL_PHASE := "wind_phase"
const GLOBAL_GUST := "wind_gust"

## The state being drawn now (eased toward [member target]).
var state: WindState = WindPresets.state_for(0.0, -1.0, 0)
## The state the weather asks for.
var target: WindState = state
## Number of global_shader_parameter_set calls made (tests assert update-only-on-change).
var publish_count: int = 0

var _wind_motion: float = DEFAULT_WIND_MOTION
var _reduced: bool = false
var _reduce_timer: float = 0.0
var _pinned: bool = false
var _pinned_clock: float = 0.0
var _published: Array[Vector4] = []
var _weather: Dictionary = WeatherSettings.default().to_dict()


func _ready() -> void:
	load_settings()
	_reduced = UiMotion.reduced()
	set_process(true)


func _process(delta: float) -> void:
	_reduce_timer += delta
	if _reduce_timer >= REDUCED_POLL_SECONDS:
		_reduce_timer = 0.0
		_reduced = UiMotion.reduced()
	if state != target:
		state = _step_toward(state, target, delta)
	publish(clock())


## Seconds on the wind clock: the unix clock since 2026-01-01 (every peer's OS agrees to
## within its skew), or the pinned value a test or render job set.
func clock() -> float:
	if _pinned:
		return _pinned_clock
	return Time.get_unix_time_from_system() - WindModel.EPOCH_UNIX


## Pins the clock at [param seconds] (render jobs and tests), so two runs draw one field.
func set_clock_override(seconds: float) -> void:
	_pinned = true
	_pinned_clock = seconds


func clear_clock_override() -> void:
	_pinned = false


func is_clock_pinned() -> bool:
	return _pinned


## 0 when the OS asks for reduced motion, else the player's wind motion scale.
func motion_scale() -> float:
	return 0.0 if _reduced else _wind_motion


## The player's wind motion scale (0..1), the [graphics] wind_motion setting (the Settings
## menu's Wind motion slider calls this as it moves, so the change shows at once).
func set_wind_motion(value: float) -> void:
	_wind_motion = clampf(value, 0.0, 1.0)


## The player's scale before the OS reduce-motion override.
func wind_motion() -> float:
	return _wind_motion


## Reads [graphics] wind_motion from the settings file at [param path] (tests pass their own).
func load_settings(path: String = Paths.SETTINGS_PATH) -> void:
	var config := ConfigFile.new()
	if config.load(path) == OK:
		set_wind_motion(float(config.get_value("graphics", SETTING_KEY, DEFAULT_WIND_MOTION)))


## Makes [param preset_name] (calm, breezy, windy, storm) the target wind. Unknown names are
## ignored. Keeps the current direction override and seed.
func set_preset(preset_name: String) -> void:
	var strength := WindPresets.strength_of(preset_name)
	if strength < 0.0:
		return
	_weather["wind_intensity"] = strength
	_retarget("")


## Sets the target from a level's weather settings: wind_intensity is the strength dial,
## wind_direction_deg (below 0 = default) the direction, wind_seed the phase. [param level_key]
## seeds a level that sets none (seed 0), so two levels never share a wind; "" leaves it 0.
func set_from_weather(settings: WeatherSettings, level_key: String = "") -> void:
	_weather = settings.to_dict()
	_retarget(level_key)


## Same as set_from_weather for a (possibly sparse) weather dictionary: keys it lacks keep
## their last value.
func apply_weather_dict(overrides: Dictionary, level_key: String = "") -> void:
	for key: String in WeatherSettings.KEYS:
		if overrides.has(key):
			_weather[key] = float(overrides[key])
	_retarget(level_key)


## Makes the target the current state at once, with no easing (tests, render jobs).
func snap() -> void:
	state = target


## The wind vector (m/s) at [param pos] now.
func wind_at(pos: Vector3) -> Vector3:
	return WindModel.wind_at(state, pos, clock())


## The unit direction the wind blows toward at [param pos] now (y = 0).
func direction_at(pos: Vector3) -> Vector3:
	var w := wind_at(pos)
	return w.normalized() if w.length_squared() > 0.0 else Vector3.ZERO


## Pushes the three uniforms for wind-clock time [param t], each only if it changed. With
## motion 0 the phases stop (plants stand still, the GPU sees one constant frame).
func publish(t: float) -> void:
	var motion := motion_scale()
	var values := WindModel.uniforms(state, t, motion)
	var names: Array[String] = [GLOBAL_DIR, GLOBAL_PHASE, GLOBAL_GUST]
	if _published.is_empty():
		_published.resize(names.size())
	for i in range(names.size()):
		if motion <= 0.0 and i == 1:
			continue
		if values[i] == _published[i]:
			continue
		_published[i] = values[i]
		publish_count += 1
		RenderingServer.global_shader_parameter_set(names[i], values[i])


func _retarget(level_key: String) -> void:
	var seed_id := int(_weather.get("wind_seed", 0.0))
	if seed_id == 0 and level_key != "":
		seed_id = absi(level_key.hash()) % 0xFFFFFF
	target = WindPresets.state_for(
		float(_weather.get("wind_intensity", 0.0)),
		float(_weather.get("wind_direction_deg", -1.0)),
		seed_id
	)


func _step_toward(from: WindState, to: WindState, delta: float) -> WindState:
	var u := 1.0 - exp(-delta * 3.0 / BLEND_SECONDS)
	var next := WindPresets.blend(from, to, u)
	return to if WindPresets.near(next, to) else next
