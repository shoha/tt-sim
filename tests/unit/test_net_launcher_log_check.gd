extends GutTest

## The net launcher's teardown check of the peers' engine logs (tests/net/net_log_check.gd):
## a send to a closed peer from script and a closed peer asked for its id fail a run; the
## engine's own relay send to a closed peer is only counted. The samples are cut from real
## scenario logs.

const LogCheck := preload("res://tests/net/net_log_check.gd")

const SCRIPT_SEND := """ERROR: Unable to send packet on channel 0, max channels: 0
   at: send (modules/enet/enet_packet_peer.cpp:64)
   GDScript backtrace (most recent call first):
       [0] _publish (res://autoloads/session_channel.gd:519)
       [1] _on_player_left (res://autoloads/session_channel.gd:496)
"""
const ENGINE_SEND := """ERROR: Unable to send packet on channel 0, max channels: 0
   at: send (modules/enet/enet_packet_peer.cpp:64)
"""
const INACTIVE := """ERROR: The multiplayer instance isn't currently active.
   at: get_unique_id (modules/enet/enet_multiplayer_peer.cpp:438)
   GDScript backtrace (most recent call first):
       [0] refresh (res://scenes/states/room/room_panel.gd:158)
"""
const OTHER := """WARNING: NetworkManager: Host disconnected
   at: push_warning (core/variant/variant_utility.cpp:1033)
[   1512 ms] went offline in phase wait_end
"""


func test_a_clean_log_has_none() -> void:
	var counts := LogCheck.teardown_errors(OTHER)
	assert_eq(counts, {"script_sends": 0, "engine_sends": 0, "inactive": 0})
	assert_false(LogCheck.fails(counts))


func test_a_send_from_script_fails_and_one_from_the_engine_is_counted() -> void:
	var counts := LogCheck.teardown_errors(ENGINE_SEND + ENGINE_SEND + SCRIPT_SEND + OTHER)
	assert_eq(counts.script_sends, 1)
	assert_eq(counts.engine_sends, 2, "the backtrace under the third is not the first two's")
	assert_true(LogCheck.fails(counts))


func test_engine_sends_alone_pass() -> void:
	var counts := LogCheck.teardown_errors(OTHER + ENGINE_SEND + OTHER + ENGINE_SEND)
	assert_eq(counts.engine_sends, 2)
	assert_false(LogCheck.fails(counts))


func test_a_closed_peer_asked_for_its_id_fails() -> void:
	var counts := LogCheck.teardown_errors(OTHER + INACTIVE.replace("\n", "\r\n"))
	assert_eq(counts.inactive, 1)
	assert_true(LogCheck.fails(counts))
