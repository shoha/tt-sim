extends GutTest

## One sound per gesture: SoundRequestQueue coalesces a frame's requests per bus to the
## highest priority, honours per-sound cooldowns and warns once on an unknown name; the
## AudioManager autoload loads the shipped manifest, runs while paused and plays through
## the queue.


func _entry(bus: String, priority: int, cooldown_s: float = 0.0) -> Dictionary:
	return {
		"bus": bus,
		"path": "res://none.wav",
		"volume_db": -2.0,
		"pitch_jitter": 0.5,
		"cooldown_s": cooldown_s,
		"priority": priority,
	}


func _queue() -> SoundRequestQueue:
	return SoundRequestQueue.new(
		{
			&"tick": _entry("UI", 10, 0.08),
			&"click": _entry("UI", 20),
			&"close": _entry("UI", 30),
			&"confirm": _entry("UI", 40),
			&"success": _entry("UI", 40, 1.0),
			&"splash": _entry("SFX", 30),
		}
	)


func _played(requests: Array[Dictionary]) -> Array:
	return requests.map(func(r: Dictionary) -> StringName: return r["name"])


# --- coalescing ----------------------------------------------------------------


func test_two_requests_in_one_frame_play_only_the_higher_priority() -> void:
	var queue := _queue()
	queue.request(&"close", 0.0)
	queue.request(&"confirm", 0.0)
	assert_eq(_played(queue.flush(0.0)), [&"confirm"])


func test_a_lower_request_after_a_higher_one_is_dropped() -> void:
	var queue := _queue()
	assert_true(queue.request(&"confirm", 0.0))
	assert_false(queue.request(&"click", 0.0), "click is outranked")
	assert_false(queue.request(&"close", 0.0), "close is outranked")
	assert_eq(_played(queue.flush(0.0)), [&"confirm"])


func test_equal_priority_keeps_the_first_request() -> void:
	var queue := _queue()
	queue.request(&"confirm", 0.0)
	assert_false(queue.request(&"success", 0.0))
	assert_eq(_played(queue.flush(0.0)), [&"confirm"])


func test_buses_coalesce_separately() -> void:
	var queue := _queue()
	queue.request(&"click", 0.0)
	queue.request(&"splash", 0.0)
	assert_eq(_played(queue.flush(0.0)), [&"splash", &"click"], "SFX then UI, one each")


func test_flush_clears_the_frame() -> void:
	var queue := _queue()
	queue.request(&"confirm", 0.0)
	queue.flush(0.0)
	assert_false(queue.has_pending())
	assert_true(queue.request(&"click", 0.016), "a new frame starts empty")


# --- cooldown ------------------------------------------------------------------


func test_a_repeat_inside_the_cooldown_is_dropped() -> void:
	var queue := _queue()
	queue.request(&"tick", 0.0)
	queue.flush(0.0)
	assert_false(queue.request(&"tick", 0.05), "50 ms after a tick with an 80 ms cooldown")
	assert_eq(queue.flush(0.05).size(), 0)
	assert_true(queue.request(&"tick", 0.09), "after the cooldown")


func test_a_cooling_sound_does_not_silence_a_lower_one() -> void:
	var queue := _queue()
	queue.request(&"success", 0.0)
	queue.flush(0.0)
	queue.request(&"success", 0.5)
	queue.request(&"click", 0.5)
	assert_eq(_played(queue.flush(0.5)), [&"click"])


func test_an_outranked_request_does_not_start_its_cooldown() -> void:
	var queue := _queue()
	queue.request(&"tick", 0.0)
	queue.request(&"confirm", 0.0)
	queue.flush(0.0)
	assert_true(queue.request(&"tick", 0.016), "the tick never played, so it is not cooling")


# --- unknown names -------------------------------------------------------------


func test_an_unknown_name_warns_once_and_plays_nothing() -> void:
	var queue := _queue()
	assert_false(queue.request(&"klick", 0.0))
	assert_false(queue.request(&"klick", 0.1))
	assert_engine_error(1, "one warning for two requests")
	assert_eq(queue.warned_names(), [&"klick"])
	assert_false(queue.has_pending())


# --- gain and pitch ------------------------------------------------------------


func test_gain_offset_adds_and_pitch_scale_multiplies() -> void:
	var queue := _queue()
	queue.request(&"confirm", 0.0, 3.0, 0.8)
	var played: Dictionary = queue.flush(0.0)[0]
	assert_almost_eq(float(played["volume_db"]), 1.0, 0.0001, "-2 dB entry + 3 dB offset")
	var half_semitone := pow(2.0, 0.5 / 12.0)
	assert_between(float(played["pitch_scale"]), 0.8 / half_semitone, 0.8 * half_semitone)


func test_jittered_pitch_is_in_semitones() -> void:
	assert_almost_eq(SoundRequestQueue.jittered_pitch(1.0, 12.0, 1.0), 2.0, 0.0001)
	assert_almost_eq(SoundRequestQueue.jittered_pitch(1.0, 12.0, -1.0), 0.5, 0.0001)
	assert_eq(SoundRequestQueue.jittered_pitch(0.9, 0.0, 1.0), 0.9)


func test_parse_manifest_rejects_text_that_is_not_a_manifest() -> void:
	assert_eq(SoundRequestQueue.parse_manifest("[1, 2]"), {})
	assert_eq(SoundRequestQueue.parse_manifest("not json"), {})
	var entries := SoundRequestQueue.parse_manifest('{"sounds": {"click": {"bus": "UI"}}}')
	assert_true(entries.has(&"click"))


# --- the autoload --------------------------------------------------------------


func test_the_shipped_manifest_names_installed_files() -> void:
	var names := AudioManager.sound_names()
	assert_gt(names.size(), 0, "manifest loaded")
	for sound in names:
		var path := str(AudioManager.sound_entry(sound)["path"])
		assert_true(ResourceLoader.exists(path), "%s -> %s" % [sound, path])
	assert_true(AudioManager.sound_names(AudioManager.BUS_UI).has(&"click"))
	assert_true(AudioManager.sound_names(AudioManager.BUS_SFX).has(&"token_drop"))


func test_tick_jitter_stays_within_half_a_semitone() -> void:
	assert_lte(float(AudioManager.sound_entry(&"tick")["pitch_jitter"]), 0.5)


func test_runs_while_the_tree_is_paused() -> void:
	assert_eq(AudioManager.process_mode, Node.PROCESS_MODE_ALWAYS)


func test_a_gesture_that_clicks_confirms_and_closes_plays_the_confirm_alone() -> void:
	await wait_process_frames(1)
	watch_signals(AudioManager)
	AudioManager.play(&"click")
	AudioManager.play(&"confirm")
	AudioManager.play(&"close")
	await wait_process_frames(2)
	assert_signal_emit_count(AudioManager, "sound_played", 1)
	assert_eq(get_signal_parameters(AudioManager, "sound_played"), [&"confirm"])


func test_the_autoload_warns_once_per_unknown_name() -> void:
	AudioManager.play(&"_test_audio_manager_no_such_sound")
	AudioManager.play(&"_test_audio_manager_no_such_sound")
	assert_engine_error("unknown sound '_test_audio_manager_no_such_sound'")
	assert_engine_error(1, "and only one")
	var warned := AudioManager.warned_names().filter(
		func(n) -> bool: return n == &"_test_audio_manager_no_such_sound"
	)
	assert_eq(warned.size(), 1)
