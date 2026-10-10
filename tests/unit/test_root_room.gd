extends GutTest

## Root's room transitions that run without the main scene: Set out refuses with no map
## (it used to enter an empty PLAYING that clients waited in), and only a host at a table
## can return everyone to the room. tests/net/enet_session_room.gd drives the whole flow
## between real peers.

const RootScript := preload("res://scenes/root.gd")


func before_each() -> void:
	NetworkManager.session.reset()
	NetworkManager._connection_state = NetworkManager.ConnectionState.HOSTING


func after_each() -> void:
	NetworkManager._connection_state = NetworkManager.ConnectionState.OFFLINE
	NetworkManager.clear_level_data()
	NetworkManager.session.reset()


func test_set_out_refuses_without_a_map() -> void:
	var root: Node = autofree(RootScript.new())
	NetworkManager.session.open()
	root.call("_on_lobby_start_game")
	assert_true(NetworkManager.session.is_open(), "the room stays open")
	assert_false(NetworkManager.is_game_in_progress(), "no client is told a game starts")
	assert_eq(root.call("get_current_state"), RootScript.State.TITLE_SCREEN, "no state change")


func test_returning_to_the_room_needs_a_table() -> void:
	var root: Node = autofree(RootScript.new())
	root.call("return_to_room")
	assert_false(NetworkManager.session.is_open(), "not at a table: nothing to put away")


func test_a_client_cannot_return_everyone_to_the_room() -> void:
	var root: Node = autofree(RootScript.new())
	NetworkManager._connection_state = NetworkManager.ConnectionState.JOINED
	(root.get("_state_stack") as Array).append(RootScript.State.PLAYING)
	root.call("return_to_room")
	assert_false(NetworkManager.session.is_open())
