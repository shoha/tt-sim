class_name NetworkGameSync
extends Node

## Table-play sub-component of NetworkManager: the RPCs that move tokens, hand out drag
## locks and carry live visual settings and live map edits once a level is loaded.
##
## Host -> clients: token transforms (one token, or a batch; unreliable), a token's full
## state and its removal (reliable), drag-lock grants, denials and releases, live visual
## settings, live map edits (LiveEdits; reliable) and the terrain events the GM starts
## (TerrainEvents, through the same outbox; reliable). Client -> host: a controlled token's
## transform (dropped when it arrives faster than CLIENT_TRANSFORM_RATE_LIMIT for that
## token), drag-lock claims and releases, and a request for the table's live edit log (one
## answered per LIVE_EDIT_LOG_REQUEST_INTERVAL a peer). Each RPC re-emits as a typed signal;
## callers send through the methods here, never through the RPCs themselves.
##
## Live edits travel as chunks (LiveEditCodec.chunks) queued in one outbox that sends at most
## LIVE_EDIT_BYTES_PER_SECOND, in order, whoever they go to; a client reassembles them
## (LiveEditCodec.Assembler, capped at LiveEditCodec.MAX_BYTES) and emits each whole op. Only
## the host sends them (the RPCs are authority-only).
##
## The inbound client RPCs only act on the host and take the sender from the transport, so
## a client can only speak for itself. What a client may do with a token (CONTROL, who holds
## its lock) is checked by the listener, NetworkTokenSync on the host.
##
## Accessed via NetworkManager.game_sync -- do not add as a standalone autoload. Its RPCs
## live at /root/NetworkManager/GameSync, the same path on every peer of one build (the
## version gate keeps builds from mixing).

## Emitted on clients for a host transform update (unreliable channel)
signal token_transform_received(
	network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)
## Emitted on clients when a token's full state arrives (reliable channel)
signal token_state_received(network_id: String, token_dict: Dictionary)
## Emitted on clients when the host removed a token
signal token_removed_received(network_id: String)
## Emitted on clients for a batch of queued transforms: network_id -> {"position",
## "rotation", "scale"}, each an [x, y, z] array
signal transform_batch_received(batch: Dictionary)
## Emitted on clients for a live visual-settings edit (environment_overrides decoded)
signal visual_settings_received(settings: Dictionary)
## Emitted on every peer when a drag lock is granted: on the host by grant_drag_lock(), on
## clients by the host's broadcast (another peer is now dragging)
signal drag_lock_granted(network_id: String, locker_peer_id: int)
## Emitted on the denied client when its lock claim was rejected
signal drag_lock_denied(network_id: String)
## Emitted on every peer when a drag lock is released (the token is free again): on the
## host by release_drag_lock(), on clients by the host's broadcast
signal drag_lock_released(network_id: String)
## Emitted on the host for a client's token transform (CONTROL not yet checked)
signal client_token_transform_received(
	sender_id: int, network_id: String, position: Vector3, rotation: Vector3, scale: Vector3
)
## Emitted on the host when a client claims a token's drag lock
signal client_drag_lock_claimed(sender_id: int, network_id: String)
## Emitted on the host when a client releases a token's drag lock
signal client_drag_lock_released(sender_id: int, network_id: String)
## Emitted on clients when a live map edit has arrived whole (not yet checked): the host's
## table key, the op's index in that table's log, and its bytes
signal live_edit_received(table_key: int, index: int, bytes: PackedByteArray)
## Emitted on clients when the header of the host's live edit log arrives: its table key and
## how many ops follow it
signal live_edit_log_received(table_key: int, count: int)
## Emitted on the host when a client asks for the table's live edit log (rate-limited)
signal live_edit_log_requested(sender_id: int)
## Emitted on clients when the host started a terrain event (TerrainEvent's wire bytes, not
## yet decoded): its motion plays on every board, and the live edit it ends in follows as an op
signal terrain_event_received(bytes: PackedByteArray)

## Rate limiting for inbound client-sent token transform RPCs (mirrors
## NetworkStateSync.TRANSFORM_SEND_INTERVAL). Bounds how often a single token's
## transform is processed regardless of how fast a client sends updates.
const CLIENT_TRANSFORM_RATE_LIMIT := 0.05
## Live edits leave at most this many bytes a second (a broadcast counted once), in chunks of
## at most LiveEditCodec.CHUNK_BYTES: Steam drops reliable messages past about 512 KB queued,
## so a whole-map sculpt or a long catch-up is spread over a fraction of a second or more.
const LIVE_EDIT_BYTES_PER_SECOND := 512 * 1024
## A peer's request for the live edit log is answered at most once in this many seconds; the
## answer can be megabytes, so a client cannot make the host resend it in a loop.
const LIVE_EDIT_LOG_REQUEST_INTERVAL := 2.0

## Last-received timestamp per token, checked against CLIENT_TRANSFORM_RATE_LIMIT
var _client_transform_throttle: Dictionary = {}  # network_id -> last_received_time (float)
## Host: live edit messages waiting to leave
var _live_outbox := LiveEditCodec.Outbox.new(LIVE_EDIT_BYTES_PER_SECOND)
## Client: the op being reassembled from its chunks
var _live_assembler := LiveEditCodec.Assembler.new()
## Host: peer id -> when its last live edit log request was answered (seconds)
var _live_log_requests: Dictionary = {}


## Forget per-connection state (the inbound transform throttle, live edits queued or half
## received, log request times). NetworkManager calls this when the game disconnects.
func reset() -> void:
	_client_transform_throttle.clear()
	_live_outbox = LiveEditCodec.Outbox.new(LIVE_EDIT_BYTES_PER_SECOND)
	_live_assembler = LiveEditCodec.Assembler.new()
	_live_log_requests.clear()


func _process(delta: float) -> void:
	if _live_outbox.size() > 0:
		_live_outbox.drain(delta)


# =============================================================================
# HOST -> CLIENTS
# =============================================================================


## Host: send a token's transform to every client (unreliable).
func broadcast_token_transform(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	_rpc_receive_token_transform.rpc(network_id, _to_array(pos), _to_array(rot), _to_array(scl))


## Host: send a token's transform to one client (unreliable). Relays a client's drag to
## the other clients.
func send_token_transform_to_peer(
	peer_id: int, network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	_rpc_receive_token_transform.rpc_id(
		peer_id, network_id, _to_array(pos), _to_array(rot), _to_array(scl)
	)


## Host: send a batch of queued transforms to every client (unreliable), in the shape
## transform_batch_received documents.
func broadcast_transform_batch(batch: Dictionary) -> void:
	_rpc_receive_transform_batch.rpc(batch)


## Host: send a token's full state (TokenState.to_dict()) to every client (reliable).
func broadcast_token_state(network_id: String, token_dict: Dictionary) -> void:
	_rpc_receive_token_state.rpc(network_id, token_dict)


## Host: tell every client a token was removed (reliable).
func broadcast_token_removed(network_id: String) -> void:
	_rpc_receive_token_removed.rpc(network_id)


## Host: broadcast live visual settings to all clients, and keep the level snapshot that
## late joiners receive in step with them.
## Accepts a dictionary with any subset of keys: "map_scale", "light_intensity",
## "environment_preset", "environment_overrides", "lofi_overrides", "weather_overrides",
## "foliage_overrides", "sun_settings", "water_style", "water_overrides".
func broadcast_visual_settings(settings: Dictionary) -> void:
	if not NetworkManager.is_host():
		return
	# Serialize environment overrides (Color to hex) for network transmission
	var net_settings = settings.duplicate()
	if net_settings.has("environment_overrides"):
		net_settings["environment_overrides"] = EnvironmentPresets.overrides_to_json(
			net_settings["environment_overrides"]
		)
	_rpc_receive_visual_settings.rpc(net_settings)

	# Keep the late-joiner snapshot in sync -- broadcast_level_data() only runs at
	# level start, so without this a client joining after a live visual-settings
	# edit (before the next full level broadcast) would see stale values.
	NetworkManager.update_level_snapshot(
		func(level_dict: Dictionary) -> Dictionary:
			return LevelVisualState.patch_level_dict(level_dict, net_settings)
	)


## Host: give `peer_id` the drag lock on `network_id` -- the host itself (peer 1) when the
## GM starts a drag, or a client whose claim passed its CONTROL check. Claims the lock in
## GameState, emits drag_lock_granted here (the host's own copy of the token locks through
## the same listener as every client's) and broadcasts the grant. Returns false, with
## nothing emitted or sent, when this peer is not the host or another peer holds the lock.
func grant_drag_lock(network_id: String, peer_id: int) -> bool:
	if not NetworkManager.is_host():
		return false
	if not GameState.claim_drag_lock(network_id, peer_id):
		return false
	drag_lock_granted.emit(network_id, peer_id)
	_rpc_drag_lock_granted.rpc(network_id, peer_id)
	return true


## Host: tell one client its drag-lock claim was denied.
func send_drag_lock_denied(peer_id: int, network_id: String) -> void:
	_rpc_drag_lock_denied.rpc_id(peer_id, network_id)


## Host: free `peer_id`'s drag lock on `network_id`, the mirror of grant_drag_lock() -- the
## GM dropping its own drag (peer 1), a client's release, or the host releasing for a
## client that left mid-drag. Releases the lock in GameState, emits drag_lock_released here
## (the host's own copy of the token unlocks through the same listener as every client's)
## and broadcasts the release. Returns false, with nothing emitted or sent, when this peer
## is not the host or `peer_id` does not hold the lock.
func release_drag_lock(network_id: String, peer_id: int) -> bool:
	if not NetworkManager.is_host():
		return false
	var holder := GameState.get_drag_lock(network_id)
	if holder == 0 or holder != peer_id:
		return false
	GameState.release_drag_lock(network_id)
	drag_lock_released.emit(network_id)
	_rpc_drag_lock_released.rpc(network_id)
	return true


## Host: send live edit op `bytes`, index `index` of table `table_key`'s log, to every client,
## behind whatever live edit traffic is already queued (reliable).
func broadcast_live_edit(table_key: int, index: int, bytes: PackedByteArray) -> void:
	if not NetworkManager.is_host():
		return
	_queue_live_edit(0, table_key, index, bytes)
	_live_outbox.drain(0.0)


## Host: send `peer_id` (0: every client) the header of table `table_key`'s live edit log and
## every op in `ops` (indices from 0), queued as one run so an op broadcast later reaches the
## peer after them (reliable).
func send_live_edit_log(peer_id: int, table_key: int, ops: Array[PackedByteArray]) -> void:
	if not NetworkManager.is_host():
		return
	var count := ops.size()
	_live_outbox.push(
		func() -> void:
			if peer_id == 0:
				_rpc_live_edit_log.rpc(table_key, count)
			elif peer_id in multiplayer.get_peers():
				_rpc_live_edit_log.rpc_id(peer_id, table_key, count),
		0
	)
	for index in count:
		_queue_live_edit(peer_id, table_key, index, ops[index])
	_live_outbox.drain(0.0)


## Host: send terrain event `bytes` (TerrainEvent.encode) to every client, through the live
## edit outbox so it never overtakes an op queued before it (the crossing it takes down is
## there when it arrives), reliable.
func broadcast_terrain_event(bytes: PackedByteArray) -> void:
	if not NetworkManager.is_host() or bytes.size() != TerrainEvent.EVENT_BYTES:
		return
	_live_outbox.push(func() -> void: _rpc_terrain_event.rpc(bytes), bytes.size())
	_live_outbox.drain(0.0)


## Host: call `then` once every live edit message queued before it has been sent, at once when
## none is waiting. LateJoinerSync sends a late joiner's full state this way, behind the
## catch-up its table's live edits asked for, so its tokens land on the edited ground.
func after_live_edits(then: Callable) -> void:
	_live_outbox.push(then, 0)
	_live_outbox.drain(0.0)


## Live edit messages still waiting to leave (the outbox; for tests and measurement).
func live_edits_waiting() -> int:
	return _live_outbox.size()


## Queues the chunks of one op for `peer_id` (0: every client).
func _queue_live_edit(peer_id: int, table_key: int, index: int, bytes: PackedByteArray) -> void:
	var parts := LiveEditCodec.chunks(bytes)
	var count := parts.size()
	for part in count:
		var data: PackedByteArray = parts[part]
		_live_outbox.push(
			func() -> void:
				if peer_id == 0:
					_rpc_live_edit_chunk.rpc(table_key, index, part, count, data)
				elif peer_id in multiplayer.get_peers():
					_rpc_live_edit_chunk.rpc_id(peer_id, table_key, index, part, count, data),
			data.size()
		)


# =============================================================================
# CLIENT -> HOST
# =============================================================================


## Client: send a controlled token's transform to the host (unreliable).
func send_client_token_transform(
	network_id: String, pos: Vector3, rot: Vector3, scl: Vector3
) -> void:
	if not NetworkManager.is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_token_transform.rpc_id(
		1, network_id, [pos.x, pos.y, pos.z], [rot.x, rot.y, rot.z], [scl.x, scl.y, scl.z]
	)


## Client: send a drag lock claim to the host.
func send_drag_lock_claim(network_id: String) -> void:
	if not NetworkManager.is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_claim_drag_lock.rpc_id(1, network_id)


## Client: send a drag lock release to the host.
func send_drag_lock_release(network_id: String) -> void:
	if not NetworkManager.is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_client_release_drag_lock.rpc_id(1, network_id)


## Client: ask the host for its table's live edit log (LiveEdits, once its map is installed).
func request_live_edit_log() -> void:
	if not NetworkManager.is_client() or not multiplayer.multiplayer_peer:
		return
	_rpc_request_live_edit_log.rpc_id(1)


# =============================================================================
# RPC METHODS
# =============================================================================


@rpc("authority", "unreliable")
func _rpc_receive_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	var pos := SerializationUtils.array_to_vec3(pos_arr)
	var rot := SerializationUtils.array_to_vec3(rot_arr)
	var scl := SerializationUtils.array_to_vec3(scale_arr, Vector3.ONE)
	token_transform_received.emit(network_id, pos, rot, scl)


@rpc("authority", "unreliable")
func _rpc_receive_transform_batch(batch: Dictionary) -> void:
	transform_batch_received.emit(batch)


@rpc("authority", "reliable")
func _rpc_receive_token_state(network_id: String, token_dict: Dictionary) -> void:
	token_state_received.emit(network_id, token_dict)


@rpc("authority", "reliable")
func _rpc_receive_token_removed(network_id: String) -> void:
	token_removed_received.emit(network_id)


@rpc("authority", "reliable")
func _rpc_receive_visual_settings(settings: Dictionary) -> void:
	# Deserialize environment overrides (Color from hex)
	if settings.has("environment_overrides"):
		settings["environment_overrides"] = EnvironmentPresets.overrides_from_json(
			settings["environment_overrides"]
		)
	visual_settings_received.emit(settings)


## RPC: Player sends token transform to host for validation (client -> host)
@rpc("any_peer", "unreliable")
func _rpc_client_token_transform(
	network_id: String, pos_arr: Array, rot_arr: Array, scale_arr: Array
) -> void:
	if not NetworkManager.is_host():
		return

	# Rate limit: drop (don't error) inbound updates for a token that arrive
	# faster than the host's own broadcast interval. Prevents a misbehaving or
	# malicious client from flooding the host with more transform updates than
	# the game ever needs to process.
	var now = Time.get_ticks_msec() / 1000.0
	var last_received = _client_transform_throttle.get(network_id, 0.0)
	if now - last_received < CLIENT_TRANSFORM_RATE_LIMIT:
		return
	_client_transform_throttle[network_id] = now

	var sender_id = multiplayer.get_remote_sender_id()
	var pos := SerializationUtils.array_to_vec3(pos_arr)
	var rot := SerializationUtils.array_to_vec3(rot_arr)
	var scl := SerializationUtils.array_to_vec3(scale_arr, Vector3.ONE)
	client_token_transform_received.emit(sender_id, network_id, pos, rot, scl)


## RPC: Client claims a drag lock for a token (client -> host)
@rpc("any_peer", "reliable")
func _rpc_client_claim_drag_lock(network_id: String) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	client_drag_lock_claimed.emit(sender_id, network_id)


## RPC: Client releases a drag lock (client -> host)
@rpc("any_peer", "reliable")
func _rpc_client_release_drag_lock(network_id: String) -> void:
	if not NetworkManager.is_host():
		return
	var sender_id = multiplayer.get_remote_sender_id()
	client_drag_lock_released.emit(sender_id, network_id)


## RPC: Host broadcasts that a token is now locked by a peer (host -> all clients)
@rpc("authority", "reliable")
func _rpc_drag_lock_granted(network_id: String, locker_peer_id: int) -> void:
	drag_lock_granted.emit(network_id, locker_peer_id)


## RPC: Host tells a specific client its claim was denied (host -> requester)
@rpc("authority", "reliable")
func _rpc_drag_lock_denied(network_id: String) -> void:
	drag_lock_denied.emit(network_id)


## RPC: Host broadcasts that a token's lock has been released (host -> all clients)
@rpc("authority", "reliable")
func _rpc_drag_lock_released(network_id: String) -> void:
	drag_lock_released.emit(network_id)


## RPC: one chunk of a live map edit (host -> clients). A refused chunk drops its op; the
## receiving LiveEdits then sees a gap and takes no later op until a log fills it.
@rpc("authority", "reliable")
func _rpc_live_edit_chunk(
	table_key: int, index: int, part: int, parts: int, data: PackedByteArray
) -> void:
	if NetworkManager.is_host():
		return
	var whole := _live_assembler.add(table_key, index, part, parts, data)
	if _live_assembler.problem != "":
		push_warning("NetworkGameSync: live edit %d refused: %s" % [index, _live_assembler.problem])
	elif not whole.is_empty():
		live_edit_received.emit(table_key, index, whole)


## RPC: the header of the host's live edit log, its ops following (host -> client or all)
@rpc("authority", "reliable")
func _rpc_live_edit_log(table_key: int, count: int) -> void:
	if NetworkManager.is_host():
		return
	live_edit_log_received.emit(table_key, count)


## RPC: a terrain event started (host -> clients). Anything but an event's length is dropped
## here; TerrainEvent.decode checks the rest where it is played.
@rpc("authority", "reliable")
func _rpc_terrain_event(bytes: PackedByteArray) -> void:
	if NetworkManager.is_host() or bytes.size() != TerrainEvent.EVENT_BYTES:
		return
	terrain_event_received.emit(bytes)


## RPC: Client asks for the table's live edit log (client -> host), answered at most once a
## LIVE_EDIT_LOG_REQUEST_INTERVAL per peer, for players past the version gate only.
@rpc("any_peer", "reliable")
func _rpc_request_live_edit_log() -> void:
	_take_log_request(multiplayer.get_remote_sender_id())


## Host: emits live_edit_log_requested for `sender_id` unless it is no player or asked less
## than LIVE_EDIT_LOG_REQUEST_INTERVAL ago. True when it did.
func _take_log_request(sender_id: int) -> bool:
	if not NetworkManager.is_host() or not NetworkManager.get_players().has(sender_id):
		return false
	var now := Time.get_ticks_msec() / 1000.0
	if (
		_live_log_requests.has(sender_id)
		and now - float(_live_log_requests[sender_id]) < LIVE_EDIT_LOG_REQUEST_INTERVAL
	):
		return false
	_live_log_requests[sender_id] = now
	live_edit_log_requested.emit(sender_id)
	return true


## Vector3 as the compact [x, y, z] array the transform RPCs carry.
static func _to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]
