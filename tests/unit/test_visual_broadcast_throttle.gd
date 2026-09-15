extends GutTest

## Tests for VisualBroadcastThrottle: live Visuals-drawer edits used to fire one reliable
## RPC per slider tick (dozens per second). The throttle merges pending settings and sends
## once per interval; save/cancel drop pending partials because their full snapshot
## supersedes them.

var _sent: Array[Dictionary] = []


func _capture(settings: Dictionary) -> void:
	_sent.append(settings.duplicate(true))


func _make_throttle() -> VisualBroadcastThrottle:
	_sent = []
	var throttle := VisualBroadcastThrottle.new()
	throttle.send = _capture
	add_child_autofree(throttle)
	return throttle


func test_queue_does_not_send_immediately() -> void:
	var throttle := _make_throttle()
	throttle.queue({"light_intensity": 0.5})
	assert_eq(_sent.size(), 0)
	assert_true(throttle.has_pending())


func test_sends_once_after_interval_with_merged_keys() -> void:
	var throttle := _make_throttle()
	throttle.queue({"light_intensity": 0.5})
	throttle.queue({"light_intensity": 0.7})
	throttle.queue({"water_style": "realistic"})

	throttle._process(throttle.interval * 0.5)
	assert_eq(_sent.size(), 0, "Not yet")
	throttle._process(throttle.interval * 0.6)

	assert_eq(_sent.size(), 1)
	assert_eq(_sent[0], {"light_intensity": 0.7, "water_style": "realistic"})
	assert_false(throttle.has_pending())


func test_flush_sends_now() -> void:
	var throttle := _make_throttle()
	throttle.queue({"foliage_overrides": {"tree_sway_speed": 2.0}})
	throttle.flush()
	assert_eq(_sent.size(), 1)
	assert_false(throttle.has_pending())


func test_flush_with_nothing_pending_sends_nothing() -> void:
	var throttle := _make_throttle()
	throttle.flush()
	assert_eq(_sent.size(), 0)


func test_drop_discards_pending() -> void:
	var throttle := _make_throttle()
	throttle.queue({"light_intensity": 0.5})
	throttle.drop()
	throttle._process(throttle.interval * 2.0)
	assert_eq(_sent.size(), 0)
	assert_false(throttle.has_pending())


func test_new_queue_after_send_starts_a_fresh_interval() -> void:
	var throttle := _make_throttle()
	throttle.queue({"light_intensity": 0.5})
	throttle._process(throttle.interval * 1.1)
	assert_eq(_sent.size(), 1)
	throttle.queue({"light_intensity": 0.9})
	throttle._process(throttle.interval * 0.5)
	assert_eq(_sent.size(), 1, "Second batch waits its own interval")
	throttle._process(throttle.interval * 0.6)
	assert_eq(_sent.size(), 2)
	assert_eq(_sent[1], {"light_intensity": 0.9})
