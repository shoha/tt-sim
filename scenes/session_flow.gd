class_name SessionFlow
extends Node

## The way into a hosted session and out of it (Root's helper): Host, Join, the room's screen,
## Set out, leaving, and the network events that move Root between TITLE_SCREEN, ROOM and
## PLAYING. Root keeps the state machine and calls this flow at each session step; this flow
## changes Root's state (Root.change_state()) and shares Root's pending level
## (Root.pending_level), the one slot every path into play sets out from.
##
## A hosted session is a room first (NetworkManager.session, SessionChannel): a room of people
## that can exist with no map, where the GM sets maps out and everyone returns between them, on
## one connection throughout. Entering ROOM never connects; the action that leads there does:
## - TITLE > ROOM: Host (host_session(): ROOM once hosting, with "Opening a room..." and its
##   Cancel meanwhile), Resume (SessionKeeper.resume(), which hosts the same way), or Join in
##   place on the title's Play together card (join_session(): ROOM on room_opened, or PLAYING
##   on game_starting when a table is out; the card shows the join's progress and failure
##   through join_status, in W3 words, join_error_text()).
## - ROOM > PLAYING: the room's Set out this map (TableMover.set_out(), then Root hands the
##   level here: set_out_pending(), refused with no map).
## - PLAYING > ROOM: TableMover's move to the room ends in _open_room() (host); every client
##   follows on room_opened.
## - ROOM > TITLE: Leave (a client leaves the session, the host ends it). A connection lost at
##   a table or in the room shows "Disconnected", whose only way on is the title.
## The room's screen is Root's child, as every state's view is.

## A join from the title moved on: JOIN_CONNECTING, JOIN_JOINED (connected, waiting for the
## host to place this player), or JOIN_FAILED with the reason in W3 words. Root passes it to
## the title's card.
signal join_status(state: StringName, message: String)

const RootScript := preload("res://scenes/root.gd")
const DISCONNECT_INDICATOR_SCENE := preload("res://scenes/ui/disconnect_indicator.tscn")
const JOIN_CONNECTING := &"connecting"
const JOIN_JOINED := &"joined"
const JOIN_FAILED := &"failed"
## Join failures in W3 words (what failed, then how to recover; no codes). A bad code and a
## lobby Steam cannot join (gone, or never there) read the same to the player.
const NO_ROOM := "No room has that code. Check it with your host."
const NO_ANSWER := "The room did not answer. Check your connection, then try again."
const LOST := "The connection to the room was lost. Try joining again."
const NO_STEAM := "Steam is not running. Start Steam, then try again."

var _root: RootScript = null
var _table_mover: TableMover = null
var _loading_overlay: LoadingOverlay = null
var _disconnect_indicator: DisconnectIndicator = null
## The room's view in ROOM (the RoomPanel full screen)
var _room_screen: RoomScreen = null
## True from a join on the title (begin_join()) until the host places this client in the room
## or at a table, or the join fails or is dropped
var _joining := false
## True from host_session() until hosting starts (ROOM) or fails (back to the title)
var _hosting_requested := false
## True after the player cancelled the "Opening a room..." wait, until a late HOSTING is closed
var _host_cancelled := false


## Root, its TableMover and its loading overlay, which live as long as Root does. Call before
## adding this flow to the tree; entering it listens to the network and the room's moves.
func setup(root: RootScript, table_mover: TableMover, loading_overlay: LoadingOverlay) -> void:
	_root = root
	_table_mover = table_mover
	_loading_overlay = loading_overlay


func _ready() -> void:
	_disconnect_indicator = DISCONNECT_INDICATOR_SCENE.instantiate()
	add_child(_disconnect_indicator)
	# After TableMover's and SessionKeeper's handlers: a resumed session's kept states are
	# restored before ROOM opens on HOSTING.
	NetworkManager.connection_state_changed.connect(_on_network_state_changed)
	NetworkManager.connection_failed.connect(_on_network_connection_failed)
	NetworkManager.player_left.connect(_on_network_player_left)
	NetworkManager.game_starting.connect(_on_network_game_starting)
	NetworkManager.session.room_opened.connect(_on_session_room_opened)
	_table_mover.room_chosen.connect(_open_room)
	_table_mover.keeper.host_requested.connect(host_session.bind(null))
	_loading_overlay.cancel_requested.connect(_on_room_wait_cancelled)


## The title hands over the level the host picked; it goes on the shelf when the room opens,
## selected for Set out. With none (an empty library) the room opens with an empty shelf.
func host_from_title(level_info: Dictionary) -> void:
	if String(level_info.get("path", "")) == "":
		host_session(null)
		return
	var level := LevelManager.load_level(String(level_info.get("path", "")), false)
	if level == null:
		UIManager.show_error(MapLoadError.for_info(level_info))
		return
	host_session(level)


## TITLE > ROOM for the host: start hosting with `level` (null: none chosen yet) as the map
## to set out first. ROOM opens once NetworkManager is HOSTING, or the title stays with the
## reason when hosting fails (_on_network_connection_failed).
func host_session(level: LevelData) -> void:
	if NetworkManager.connection_state != NetworkManager.ConnectionState.OFFLINE:
		return
	_root.pending_level = level
	_hosting_requested = true
	_host_cancelled = false
	if _loading_overlay:
		_loading_overlay.show_indeterminate(RoomScreen.OPENING, true, RoomScreen.OPENING_STEP)
	NetworkManager.host_game()


## The "Opening a room..." wait's Cancel: stop hosting and stay on the title. Hosting may
## still finish after this (Steam answers late); _on_network_state_changed drops it then.
func _on_room_wait_cancelled() -> void:
	if not _hosting_requested:
		return
	_hosting_requested = false
	_host_cancelled = true
	_root.pending_level = null
	_end_room_wait()
	NetworkManager.disconnect_game()


## Hide the "Opening a room..." wait (and any level loading a client had under way when the
## room opened). The next map load lays its own sky and bar (LoadingOverlay.show_loading).
func _end_room_wait() -> void:
	if _loading_overlay and _loading_overlay.visible:
		_loading_overlay.hide_loading()


## Entering ROOM: the room, full screen (RoomScreen), the same for the GM and the players. A
## map the GM hosted with (Host with this map) goes on the shelf, selected, ready to set out.
## Entering never connects; hosting or joining has already happened.
func enter_room() -> void:
	_end_room_wait()
	var first := ""
	if NetworkManager.is_host() and _root.pending_level:
		first = NetworkManager.session.shelve(_root.pending_level.to_dict())
	_room_screen = RoomScreen.new()
	_root.add_child(_room_screen)
	_room_screen.panel.set_out_requested.connect(_table_mover.set_out)
	_room_screen.panel.leave_requested.connect(_on_lobby_cancel)
	_table_mover.attach_panel(_room_screen.panel)
	if first != "":
		_room_screen.panel.select(first)


## Leaving ROOM: the room's screen goes.
func exit_room() -> void:
	if _room_screen:
		_room_screen.queue_free()
		_room_screen = null


## Put the table away for everyone, once TableMover has settled it. The connection, the
## players and the Steam lobby stay; GameMap is torn down as on any move, and every client is
## sent to the room (SessionChannel.open). The party (the players' avatars) is taken first and
## set out on the next map (SessionParty). The next map is chosen in the room.
func _open_room() -> void:
	if not NetworkManager.is_host() or not _root.is_in_state(RootScript.State.PLAYING):
		return
	_root.pending_level = null
	NetworkManager.session.party.take()
	NetworkManager.session.open()
	_root.change_state(RootScript.State.ROOM)


## Client: the host opened the room, from the table or as this client joined it.
func _on_session_room_opened() -> void:
	if (
		NetworkManager.is_client()
		and _root.get_current_state() != RootScript.State.ROOM
	):
		_joining = false
		_root.change_state(RootScript.State.ROOM)


## Title > Join in place: the card's Join connects to the room with `code` (over Steam). Root
## moves on when the host places this client: ROOM on room_opened, or PLAYING on
## game_starting when a table is out. A failure, or a host that rejects this client, comes
## back to the card with the reason (join_status).
func join_session(code: String) -> void:
	if NetworkManager.connection_state != NetworkManager.ConnectionState.OFFLINE:
		return
	begin_join()
	NetworkManager.join_game(code)


## A join from the title is under way: from here its progress and failure go to the card
## (join_status). join_session() starts one; the ENet scenarios start theirs here and connect
## over ENet themselves, as join_game() does over Steam.
func begin_join() -> void:
	_joining = true
	join_status.emit(JOIN_CONNECTING, "")


## The card went back while a join was under way: drop it and stay on the title.
func cancel_join() -> void:
	if not _joining:
		return
	_joining = false
	NetworkManager.disconnect_game()


## Whether a join from the title is under way.
func is_joining() -> bool:
	return _joining


## The title is left (to the room, a table or anything else): a join under way has landed.
func end_join() -> void:
	_joining = false


## A join failure's reason as the player reads it (W3). NetworkManager's own reasons name the
## failure in engine terms ("Invalid room code", "Failed to join Steam lobby (result=...)",
## "Connection timed out"); the version gate's and any other already speak to the player and
## pass through. Pure.
static func join_error_text(reason: String) -> String:
	if reason.begins_with("Invalid room code") or reason.begins_with("Failed to join Steam lobby"):
		return NO_ROOM
	if reason.begins_with("Connection timed out"):
		return NO_ANSWER
	if reason.begins_with("Steam is not running"):
		return NO_STEAM
	return reason if reason.strip_edges() != "" else LOST


## ROOM > PLAYING (host): set the pending map out. Refused with no map, which used to enter
## an empty PLAYING where clients waited for a level that never came.
func set_out_pending() -> void:
	if _root.pending_level == null:
		UIManager.show_warning("Choose a map to set out first")
		return
	NetworkManager.session.close()
	NetworkManager.notify_game_starting()
	_root.change_state(RootScript.State.PLAYING)


## ROOM > TITLE: a client leaves the session, the host ends it for everyone. The title
## comes first, so the disconnect that follows is not read as a lost connection.
func _on_lobby_cancel() -> void:
	_root.pending_level = null
	_root.change_state(RootScript.State.TITLE_SCREEN)
	NetworkManager.disconnect_game()


## Client: the host set a map out from the room, or this client joined while one is out.
func _on_network_game_starting() -> void:
	if NetworkManager.is_client() and not _root.is_in_state(RootScript.State.PLAYING):
		_joining = false
		_root.change_state(RootScript.State.PLAYING)


func _on_network_state_changed(
	old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	# A join from the title connected, or went offline with no reason given (a reason comes
	# first, through connection_failed, and ends the join there).
	if _joining and new_state == NetworkManager.ConnectionState.JOINED:
		AudioManager.play(&"success")
		join_status.emit(JOIN_JOINED, "")
	elif _joining and new_state == NetworkManager.ConnectionState.OFFLINE:
		_joining = false
		join_status.emit(JOIN_FAILED, LOST)
	# Hosting started from the title: the session opens in the room.
	if new_state == NetworkManager.ConnectionState.HOSTING and _hosting_requested:
		_hosting_requested = false
		_root.change_state(RootScript.State.ROOM)
		return
	# Hosting the player cancelled finished late: close it again.
	if new_state == NetworkManager.ConnectionState.HOSTING and _host_cancelled:
		_host_cancelled = false
		NetworkManager.disconnect_game.call_deferred()
		return
	# Handle a disconnect at a table or in the room.
	# PAUSED is pushed on top of PLAYING (not swapped), so check the whole
	# stack rather than just the top — otherwise pausing hides this branch.
	if new_state != NetworkManager.ConnectionState.OFFLINE:
		return
	if (
		_root.is_in_state(RootScript.State.PLAYING)
		or _root.is_in_state(RootScript.State.ROOM)
	):
		_disconnect_indicator.hide_indicator()
		# Show disconnect dialog if we were in any networked state.
		# Exclude OFFLINE→OFFLINE (redundant) and HOSTING (the host only goes offline by
		# leaving, and every leave path changes to the title first).
		if (
			old_state != NetworkManager.ConnectionState.OFFLINE
			and old_state != NetworkManager.ConnectionState.HOSTING
		):
			_show_disconnect_dialog()


## Hosting from the title failed (Steam not running, no lobby): the title stays, with the
## reason. A join from the title failed: the card shows why, in W3 words.
func _on_network_connection_failed(reason: String) -> void:
	if _joining:
		_joining = false
		AudioManager.play(&"error")
		join_status.emit(JOIN_FAILED, join_error_text(reason))
		return
	if not _hosting_requested:
		return
	_hosting_requested = false
	_root.pending_level = null
	_end_room_wait()
	UIManager.show_error(reason)


func _on_network_player_left(_peer_id: int, player_info: Dictionary) -> void:
	var player_name: String = player_info.get("name", "A player")
	UIManager.show_warning("%s disconnected" % player_name)


func _show_disconnect_dialog() -> void:
	var go_to_title := func(): _root.change_state(RootScript.State.TITLE_SCREEN)
	var dialog = (
		UIManager
		. show_confirmation(
			"Disconnected",
			"The connection to the host was lost.",
			"Return to Title",
			"",  # No cancel text
			go_to_title,
			go_to_title,  # ESC also returns to title — can't continue without host
		)
	)
	# Hide the cancel button since there's only one valid action
	if dialog:
		var cancel_btn = dialog.get_node_or_null("%CancelButton")
		if cancel_btn:
			cancel_btn.hide()
