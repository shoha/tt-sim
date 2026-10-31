extends RefCounted

## Render-job probe (`call` op) for the global wind (card wind_a, docs/systems/wind.md).
## `action`:
## - `set`: puts the Wind autoload in a known state. `preset` (calm, breezy, windy, storm) or
##   `strength` (0..1); `dir_deg` (below 0 = the default, -z); `seed`; `clock` (pins the wind
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
	return _report(wind)


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
