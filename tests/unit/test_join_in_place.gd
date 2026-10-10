extends GutTest

## Join in place and Resume, Root's side (SessionFlow, Root): a join from the title reports its
## progress and failure for the card in W3 words, going back drops it, and the title's Resume
## reaches SessionKeeper.resume(). tests/net/enet_session_room.gd joins through the card between
## real peers; test_play_together_card.gd covers the card itself.

const RootScript := preload("res://scenes/root.gd")
const SESSION_ID := "_join_in_place_resume"

var _states: Array = []


func _flow() -> SessionFlow:
	var root: Node = autofree(RootScript.new())
	var flow: SessionFlow = autofree(SessionFlow.new())
	flow.setup(root, null, null)
	_states.clear()
	flow.join_status.connect(
		func(state: StringName, message: String) -> void: _states.append([state, message])
	)
	return flow


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	SessionFile.remove(SESSION_ID)


## NetworkManager's engine words become the player's (no codes); messages that already speak
## to the player, the version gate's, pass through.
func test_join_failures_read_in_w3_words() -> void:
	assert_eq(SessionFlow.join_error_text("Invalid room code"), SessionFlow.NO_ROOM)
	assert_eq(
		SessionFlow.join_error_text("Failed to join Steam lobby (result=2)"), SessionFlow.NO_ROOM
	)
	assert_eq(SessionFlow.join_error_text("Connection timed out"), SessionFlow.NO_ANSWER)
	assert_eq(
		SessionFlow.join_error_text("Steam is not running. Please start Steam and try again."),
		SessionFlow.NO_STEAM
	)
	var version := VersionGate.mismatch_message("0.2.9", "0.2.10")
	assert_eq(SessionFlow.join_error_text(version), version)
	assert_eq(SessionFlow.join_error_text(""), SessionFlow.LOST)
	for text in [SessionFlow.NO_ROOM, SessionFlow.NO_ANSWER, SessionFlow.LOST]:
		assert_false(text.contains("result"), "no codes")
		assert_true(text.ends_with("."), "a whole sentence")


func test_a_join_reports_connecting_then_joined() -> void:
	var flow := _flow()
	flow.begin_join()
	assert_true(flow.is_joining())
	var offline := NetworkManager.ConnectionState.OFFLINE
	var joined := NetworkManager.ConnectionState.JOINED
	flow._on_network_state_changed(offline, NetworkManager.ConnectionState.CONNECTING)
	flow._on_network_state_changed(NetworkManager.ConnectionState.CONNECTING, joined)
	assert_eq(_states, [[SessionFlow.JOIN_CONNECTING, ""], [SessionFlow.JOIN_JOINED, ""]])
	assert_true(flow.is_joining(), "until the host places this player")
	flow.end_join()
	assert_false(flow.is_joining())


## A failure with a reason reports it once (the OFFLINE that follows says nothing more); an
## OFFLINE with no reason reports the connection lost.
func test_a_failed_join_reports_why_once() -> void:
	var flow := _flow()
	flow.begin_join()
	flow._on_network_connection_failed("Invalid room code")
	flow._on_network_state_changed(
		NetworkManager.ConnectionState.CONNECTING, NetworkManager.ConnectionState.OFFLINE
	)
	assert_eq(_states.size(), 2)
	assert_eq(_states[1], [SessionFlow.JOIN_FAILED, SessionFlow.NO_ROOM])
	assert_false(flow.is_joining())
	flow.begin_join()
	flow._on_network_state_changed(
		NetworkManager.ConnectionState.JOINED, NetworkManager.ConnectionState.OFFLINE
	)
	assert_eq(_states.back(), [SessionFlow.JOIN_FAILED, SessionFlow.LOST])


## Going back on the card drops the join: nothing more is reported for it.
func test_cancelling_a_join_stops_reporting_it() -> void:
	var flow := _flow()
	flow.begin_join()
	flow.cancel_join()
	assert_false(flow.is_joining())
	flow._on_network_connection_failed("Connection timed out")
	assert_eq(_states.size(), 1, "only the connecting report")


## A join is refused while connected (hosting or joined already).
func test_no_join_while_connected() -> void:
	var flow := _flow()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING
	flow.join_session("2kq9xw")
	assert_false(flow.is_joining())
	assert_eq(_states.size(), 0)


## The title's Resume reaches the keeper: a saved session reads, and the keeper asks the flow
## to host it (host_requested).
func test_resume_from_the_title_asks_the_keeper() -> void:
	var data := {"format": SessionFile.FORMAT, "id": SESSION_ID, "name": "Old Mill"}
	assert_eq(SessionFile.write_json(SessionFile.session_path(SESSION_ID), data), OK)
	var root: Node = autofree(RootScript.new())
	var mover: TableMover = autofree(TableMover.new())
	mover.keeper = autofree(SessionKeeper.new())
	root.set("_table_mover", mover)
	watch_signals(mover.keeper)
	root.call("_on_resume_requested", SESSION_ID)
	assert_signal_emitted(mover.keeper, "host_requested")
