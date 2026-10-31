extends RefCounted

## Render-job probe (`call` op) for the global wind (card wind_a, docs/systems/wind.md).
## `action`:
## - `set`: puts the Wind autoload in a known state. `preset` (calm, breezy, windy, storm) or
##   `strength` (0..1); `dir_deg` (below 0 = the default, toward (0.707, 0, -0.707)); `seed`; `clock` (pins the wind
##   clock at that many seconds; `"unpin": true` releases it); `motion` (the player's wind
##   motion scale, 0..1); `sway` (false: holds every foliage material's sway and flutter speed
##   at 0 so only the gust field moves, the gust following the pinned clock). The state is
##   snapped, not eased, so a capture is repeatable.
## - `report`: logs the state, the clock and the three published globals read back.
## - `cost` (`n`, default 20000): CPU microseconds per Wind.publish call over `n` calls with a
##   moving clock (the per-frame autoload cost: the model plus three change-checked sets), and
##   per wind_at call.

static func run(base: Node, step: Dictionary) -> String:
	var wind: Node = Wind
	match String(step.get("action", "report")):
		"set":
			return _apply(base, wind, step)
		"cost":
			return _cost(wind, int(step.get("n", 20000)))
		"weather":
			return _weather(base, wind, step)
		"particle_cost":
			return _particle_cost(base, int(step.get("n", 20000)))
	return _report(wind)


## `weather` (card wind_b): rain, snow (0..1) and `preset` or `strength` (the wind dial, which is
## also the Wind tile's intensity) through GameMap.apply_weather_overrides, setting the weather
## renderer up first when the open map has none. The wind is snapped (and the clock pinned at
## `clock` when given) so a capture is repeatable; the renderer's smoothing needs about 1.5 s.
static func _weather(base: Node, wind: Node, step: Dictionary) -> String:
	var game_map: GameMap = base.get("_game_map")
	if game_map.get("_weather_renderer") == null:
		var manager: LevelEnvironmentManager = base.ctrl().get("_environment")
		game_map.setup_weather(manager)
	var strength := float(step.get("strength", 0.0))
	if step.has("preset"):
		strength = WindPresets.strength_of(String(step["preset"]))
	game_map.apply_weather_overrides(
		{
			"rain_intensity": float(step.get("rain", 0.0)),
			"snow_intensity": float(step.get("snow", 0.0)),
			"fog_intensity": 0.0,
			"wind_intensity": strength,
			"wind_direction_deg": float(step.get("dir_deg", -1.0)),
			"wind_seed": float(step.get("seed", 0)),
		}
	)
	wind.snap()
	if step.has("motion"):
		wind.set_wind_motion(float(step["motion"]))
	if bool(step.get("unpin", false)):
		wind.clear_clock_override()
	elif step.has("clock"):
		wind.set_clock_override(float(step["clock"]))
	wind.publish(wind.clock())
	return _particles_report(game_map)


static func _particles_report(game_map: GameMap) -> String:
	var renderer: WeatherRenderer = game_map.get("_weather_renderer")
	if renderer == null:
		return "no weather renderer"
	var rain := renderer._rain_emitter.process_material as ParticleProcessMaterial
	var snow := renderer._snow_emitter.process_material as ParticleProcessMaterial
	var streak := renderer._wind_emitter.process_material as ParticleProcessMaterial
	return (
		"particles: writes %d, wind %s; rain dir %s grav %s; snow grav %s turb %.2f; "
		% [renderer.wind_apply_count, renderer._wind_smooth, rain.direction, rain.gravity,
			snow.gravity, snow.turbulence_noise_strength]
		+ "streak dir %s v %.1f-%.1f visible %s ratio %.2f"
		% [streak.direction, streak.initial_velocity_min, streak.initial_velocity_max,
			renderer._wind_emitter.visible, renderer._wind_emitter.amount_ratio]
	)


## `particle_cost` (`n`): CPU microseconds of the renderer's per-frame wind work with the open
## map's weather renderer: wind_due alone (the common frame), the sample plus step_wind (one frame
## in six at 60 fps), and the whole _process for reference.
static func _particle_cost(base: Node, n: int) -> String:
	var game_map: GameMap = base.get("_game_map")
	var renderer: WeatherRenderer = game_map.get("_weather_renderer")
	if renderer == null:
		return "no weather renderer"
	var t0 := Time.get_ticks_usec()
	var due := 0
	for i in range(n):
		if renderer.wind_due(0.0):
			due += 1
	var due_us := float(Time.get_ticks_usec() - t0) / float(n)
	var state: WindState = Wind.state
	t0 = Time.get_ticks_usec()
	var writes := 0
	for i in range(n):
		var pos := Vector3(float(i % 40), 0.0, 3.0)
		var gust := WindModel.gust_at(state, pos, Wind.clock() + float(i) * 0.1)
		renderer._wind_accum = 0.1
		if renderer.step_wind(Wind.wind_at(pos), state.gust_amp * gust):
			writes += 1
	var step_us := float(Time.get_ticks_usec() - t0) / float(n)
	t0 = Time.get_ticks_usec()
	for i in range(n):
		renderer._process(0.016)
	var process_us := float(Time.get_ticks_usec() - t0) / float(n)
	return (
		"wind_due %.3f us/call, sample+step_wind %.2f us/call (%d of %d wrote), _process %.2f us/call; "
		% [due_us, step_us, writes, n, process_us]
		+ "amortized wind work at 60 fps %.3f us/frame" % [due_us + step_us / 6.0]
	)


static func _apply(base: Node, wind: Node, step: Dictionary) -> String:
	var weather := {}
	if step.has("preset"):
		weather["wind_intensity"] = WindPresets.strength_of(String(step["preset"]))
	elif step.has("strength"):
		weather["wind_intensity"] = float(step["strength"])
	weather["wind_direction_deg"] = float(step.get("dir_deg", -1.0))
	weather["wind_seed"] = float(step.get("seed", 0))
	wind.apply_weather_dict(weather)
	wind.snap()
	if step.has("motion"):
		wind.set_wind_motion(float(step["motion"]))
	if bool(step.get("unpin", false)):
		wind.clear_clock_override()
	elif step.has("clock"):
		wind.set_clock_override(float(step["clock"]))
	if not bool(step.get("sway", true)):
		var game_map: GameMap = base.get("_game_map")
		for material in WindFoliage.collect_foliage_shader_materials(game_map.map_container):
			material.set_shader_parameter("sway_speed", 0.0)
			material.set_shader_parameter("flutter_speed", 0.0)
	wind.publish(wind.clock())
	return _report(wind)


static func _report(wind: Node) -> String:
	var s: WindState = wind.state
	return (
		"wind speed %.2f gust %.2f ripple %.2f sway %.2f veer %.2f angle %.3f seed %d; "
		% [s.speed, s.gust_amp, s.gust_ripple, s.sway_scale, s.veer_amp, s.dir_angle, s.seed_id]
		+ "clock %.2f motion %.2f; " % [wind.clock(), wind.motion_scale()]
		+ "published (global_shader_parameter_get is editor-only) dir %s phase %s gust %s"
		% [wind._published[0], wind._published[1], wind._published[2]]
	)


static func _cost(wind: Node, n: int) -> String:
	var t0 := Time.get_ticks_usec()
	var start: float = wind.clock()
	for i in range(n):
		wind.publish(start + float(i) * 0.016)
	var publish_us := float(Time.get_ticks_usec() - t0) / float(n)
	var sets: int = wind.publish_count
	t0 = Time.get_ticks_usec()
	var acc := 0.0
	for i in range(n):
		acc += wind.wind_at(Vector3(float(i % 50), 0.0, 3.0)).x
	var at_us := float(Time.get_ticks_usec() - t0) / float(n)
	return "publish %.2f us/call, wind_at %.2f us/call (n %d, sets so far %d, acc %.1f)" % [
		publish_us, at_us, n, sets, acc
	]
