extends MultiplayerPeerExtension

## A MultiplayerPeer that wraps another one (ENetMultiplayerPeer in the perfaudit net harness,
## tests/net/perfaudit_net.gd) and counts every packet SceneMultiplayer hands it or takes from
## it, by message: the RPC's method name, decoded from SceneMultiplayer's packet header, or the
## engine's own command (path cache, relay). It can also play a slow link on the receive side.
##
## Decoding. SceneMultiplayer (Godot 4.7, modules/multiplayer) frames a remote call as one meta
## byte (bits 0-2 the command, 4-5 the node id width 8/16/32, bit 6 the method id width 8/16,
## bit 7 "one PackedByteArray argument or none"), the node id, the method id, then the
## arguments. The node id is a path cache id the SENDER announced in a SIMPLIFY_PATH packet
## ([command][methods md5 cstring][u32 id][path cstring]), so outbound names use this process's
## own announcements and inbound names the remote's; a 32-bit id with the top bit set instead
## points at the path written inline. The method id is the index among the node's RPC names
## sorted as Strings (NETWORKING.md "Same-version gate").
##
## Counting. A packet counts once per direction with its payload size; `wire` multiplies an
## outbound packet sent to every peer (target 0) by the peers it reaches. SceneMultiplayer
## sends an RPC broadcast as one packet per peer, so for RPCs the two agree. Bytes below this
## layer (ENet's protocol headers, acks, pings; UDP and IP) are not seen here: cut() reads
## ENet's own host counters for them when the inner peer is ENet.
##
## Link play (rtt_ms, kbps > 0): received packets wait in one FIFO per process as if they had
## crossed a link of that one-way delay (rtt / 2) and rate, PACKET_OVERHEAD bytes each. Both
## peers apply it to what they receive, so each direction sees the delay once. The sender is
## not slowed (its queue is unbounded), so it models a deep buffer, not loss or back pressure.

## The bytes a packet costs below this layer that link play charges: IPv4 20, UDP 8, an ENet
## header and send command about 16.
const PACKET_OVERHEAD := 44
const MODE_NAMES := ["unrel", "unseq", "rel"]
const CMD_NAMES := ["rpc", "~path_simplify", "~path_confirm", "~raw", "~spawn", "~despawn", "~sync"]
const SYS_NAMES := ["~sys_auth", "~sys_add_peer", "~sys_del_peer", "~sys_relay"]

var inner: MultiplayerPeer
var root: Node
var rtt_ms := 0.0
var kbps := 0.0
## dir|name|mode -> [count, payload bytes, wire bytes]
var counters: Dictionary = {}
## The longest a received packet waited in the link play queue, ms.
var max_wait_ms := 0.0
var _target := 0
var _mode := MultiplayerPeer.TRANSFER_MODE_RELIABLE
var _channel := 0
var _peers: Dictionary = {}
var _queue: Array[Dictionary] = []
var _link_free_ms := 0.0
var _out_paths: Dictionary = {}
var _in_paths: Dictionary = {}
var _rpc_names: Dictionary = {}
var _last: Dictionary = {}
var _last_ms := 0
var _enet_totals := PackedInt64Array([0, 0, 0, 0])
var _enet_last := PackedInt64Array([0, 0, 0, 0])


func _init(p_inner: MultiplayerPeer, p_root: Node, p_rtt_ms := 0.0, p_kbps := 0.0) -> void:
	inner = p_inner
	root = p_root
	rtt_ms = p_rtt_ms
	kbps = p_kbps
	_last_ms = Time.get_ticks_msec()
	inner.peer_connected.connect(_on_inner_connected)
	inner.peer_disconnected.connect(_on_inner_disconnected)


func _on_inner_connected(id: int) -> void:
	_peers[id] = true
	peer_connected.emit(id)


func _on_inner_disconnected(id: int) -> void:
	_peers.erase(id)
	_queue = _queue.filter(func(p: Dictionary) -> bool: return p.peer != id)
	peer_disconnected.emit(id)


# --- MultiplayerPeer -----------------------------------------------------------------------


func _poll() -> void:
	inner.poll()
	var now := Time.get_ticks_usec() / 1000.0
	while inner.get_available_packet_count() > 0:
		var peer := inner.get_packet_peer()
		var mode := inner.get_packet_mode()
		var channel := inner.get_packet_channel()
		var data := inner.get_packet()
		var ready := now
		if rtt_ms > 0.0 or kbps > 0.0:
			var serialise := (data.size() + PACKET_OVERHEAD) * 8.0 / kbps if kbps > 0.0 else 0.0
			_link_free_ms = maxf(_link_free_ms, now) + serialise
			ready = _link_free_ms + rtt_ms * 0.5
		_queue.append(
			{
				"data": data,
				"peer": peer,
				"mode": mode,
				"channel": channel,
				"at": now,
				"ready": ready,
			}
		)
		_count("in", data, peer, mode, 1)


func _get_available_packet_count() -> int:
	var now := Time.get_ticks_usec() / 1000.0
	var n := 0
	for p in _queue:
		if p.ready > now:
			break
		n += 1
	return n


func _get_packet_script() -> PackedByteArray:
	if _queue.is_empty():
		return PackedByteArray()
	var p: Dictionary = _queue.pop_front()
	max_wait_ms = maxf(max_wait_ms, Time.get_ticks_usec() / 1000.0 - float(p.at))
	return p.data


func _get_packet_peer() -> int:
	return int(_queue[0].peer) if not _queue.is_empty() else 0


func _get_packet_mode() -> MultiplayerPeer.TransferMode:
	return _queue[0].mode if not _queue.is_empty() else MultiplayerPeer.TRANSFER_MODE_RELIABLE


func _get_packet_channel() -> int:
	return int(_queue[0].channel) if not _queue.is_empty() else 0


func _put_packet_script(buffer: PackedByteArray) -> Error:
	var recipients := 1
	if _target == 0:
		recipients = _peers.size()
	elif _target < 0:
		recipients = maxi(_peers.size() - 1, 0)
	_count("out", buffer, _target, _mode, recipients)
	return inner.put_packet(buffer)


func _set_transfer_mode(mode: MultiplayerPeer.TransferMode) -> void:
	_mode = mode
	inner.transfer_mode = mode


func _get_transfer_mode() -> MultiplayerPeer.TransferMode:
	return _mode


func _set_transfer_channel(channel: int) -> void:
	_channel = channel
	inner.transfer_channel = channel


func _get_transfer_channel() -> int:
	return _channel


func _set_target_peer(peer: int) -> void:
	_target = peer
	inner.set_target_peer(peer)


func _get_max_packet_size() -> int:
	return 1 << 24


func _get_unique_id() -> int:
	return inner.get_unique_id()


func _is_server() -> bool:
	return inner.get_unique_id() == 1


func _is_server_relay_supported() -> bool:
	return inner.is_server_relay_supported()


func _get_connection_status() -> MultiplayerPeer.ConnectionStatus:
	return inner.get_connection_status()


func _set_refuse_new_connections(enable: bool) -> void:
	inner.refuse_new_connections = enable


func _is_refusing_new_connections() -> bool:
	return inner.refuse_new_connections


func _disconnect_peer(peer: int, force: bool) -> void:
	inner.disconnect_peer(peer, force)


func _close() -> void:
	inner.close()
	_queue.clear()
	_peers.clear()


# --- counting --------------------------------------------------------------------------------


func _count(dir: String, data: PackedByteArray, peer: int, mode: int, recipients: int) -> void:
	var key := "%s|%s|%s" % [dir, _name_of(data, dir, peer), MODE_NAMES[clampi(mode, 0, 2)]]
	var c: PackedInt64Array = counters.get(key, PackedInt64Array([0, 0, 0]))
	c[0] += 1
	c[1] += data.size()
	c[2] += data.size() * recipients
	counters[key] = c


func _name_of(data: PackedByteArray, dir: String, peer: int) -> String:
	if data.is_empty():
		return "~empty"
	var b0 := data[0]
	var cmd := b0 & 7
	if cmd == 1:
		_learn_path(data, dir, peer)
	if cmd == 7:
		var sys := data[1] if data.size() > 1 else 255
		return SYS_NAMES[sys] if sys < SYS_NAMES.size() else "~sys"
	if cmd != 0:
		return CMD_NAMES[cmd]
	var node_width := (b0 >> 4) & 3
	var ofs := 1
	var node_id := 0
	if node_width == 0:
		node_id = data[ofs]
		ofs += 1
	elif node_width == 1:
		node_id = data.decode_u16(ofs)
		ofs += 2
	else:
		node_id = data.decode_u32(ofs)
		ofs += 4
	if ofs >= data.size():
		return "rpc#short"
	var method_id := data[ofs] if ((b0 >> 6) & 1) == 0 else data.decode_u16(ofs)
	var path := ""
	if node_width == 2 and (node_id & 0x80000000) != 0:
		path = _cstring(data, node_id & 0x7fffffff)
	else:
		var table: Dictionary = _out_paths if dir == "out" else _in_paths.get(peer, {})
		path = str(table.get(node_id, ""))
	if path == "":
		return "rpc#%d.%d" % [node_id, method_id]
	return _method_name(path, method_id)


## Records the path a SIMPLIFY_PATH packet announces under its cache id.
func _learn_path(data: PackedByteArray, dir: String, peer: int) -> void:
	var md5_end := data.find(0, 1)
	if md5_end < 0 or md5_end + 5 > data.size():
		return
	var id := data.decode_u32(md5_end + 1)
	var path := _cstring(data, md5_end + 5)
	if dir == "out":
		_out_paths[id] = path
	else:
		var table: Dictionary = _in_paths.get(peer, {})
		table[id] = path
		_in_paths[peer] = table


func _cstring(data: PackedByteArray, ofs: int) -> String:
	if ofs < 0 or ofs >= data.size():
		return ""
	var end := data.find(0, ofs)
	if end < 0:
		end = data.size()
	return data.slice(ofs, end).get_string_from_utf8()


func _method_name(path: String, method_id: int) -> String:
	if not _rpc_names.has(path):
		var names := PackedStringArray()
		var node := root.get_node_or_null(NodePath(path)) if root else null
		if node != null and node.get_script() != null:
			var config: Variant = (node.get_script() as Script).call("get_rpc_config")
			if config is Dictionary:
				for k in (config as Dictionary).keys():
					names.append(String(k))
		names.sort()
		_rpc_names[path] = names
	var sorted: PackedStringArray = _rpc_names[path]
	if (method_id & 0x8000) == 0 and method_id < sorted.size():
		return sorted[method_id]
	return "%s#%d" % [path.get_file(), method_id]


# --- windows ---------------------------------------------------------------------------------


## The counts since the previous cut (or the start) as {label, ms, rows: [{dir, name, mode,
## count, bytes, wire}] sorted by wire bytes, out_bytes, out_wire, in_bytes, enet: [sent bytes,
## received bytes, sent packets, received packets] (ENet's own counters, headers included;
## zeros when the inner peer is not ENet)}, and starts the next window.
func cut(label: String) -> Dictionary:
	var now := Time.get_ticks_msec()
	var rows: Array[Dictionary] = []
	var totals := {"out_bytes": 0, "out_wire": 0, "in_bytes": 0, "out_count": 0, "in_count": 0}
	for key: String in counters:
		var c: PackedInt64Array = counters[key]
		var was: PackedInt64Array = _last.get(key, PackedInt64Array([0, 0, 0]))
		var n := c[0] - was[0]
		if n == 0:
			continue
		var parts := key.split("|")
		var row := {
			"dir": parts[0],
			"name": parts[1],
			"mode": parts[2],
			"count": n,
			"bytes": c[1] - was[1],
			"wire": c[2] - was[2],
		}
		rows.append(row)
		if parts[0] == "out":
			totals.out_bytes += row.bytes
			totals.out_wire += row.wire
			totals.out_count += n
		else:
			totals.in_bytes += row.bytes
			totals.in_count += n
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.wire > b.wire)
	_last = counters.duplicate(true)
	var enet := _enet_delta()
	var window := {"label": label, "ms": now - _last_ms, "rows": rows, "enet": enet}
	window.merge(totals)
	_last_ms = now
	return window


func _enet_delta() -> Array:
	var enet := inner as ENetMultiplayerPeer
	if enet == null or enet.host == null:
		return [0, 0, 0, 0]
	var stats := [
		ENetConnection.HOST_TOTAL_SENT_DATA,
		ENetConnection.HOST_TOTAL_RECEIVED_DATA,
		ENetConnection.HOST_TOTAL_SENT_PACKETS,
		ENetConnection.HOST_TOTAL_RECEIVED_PACKETS,
	]
	var out := []
	for i in stats.size():
		_enet_totals[i] += int(enet.host.pop_statistic(stats[i]))
		out.append(_enet_totals[i] - _enet_last[i])
		_enet_last[i] = _enet_totals[i]
	return out


## One window as text lines for a log: a header, then one line per message.
static func window_lines(role: String, w: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	var seconds := maxf(float(w.ms) / 1000.0, 0.001)
	lines.append(
		(
			(
				"NETW|%s|%s|%d ms|out %d B (%d on wire, %.0f B/s) in %d B (%.0f B/s)"
				+ "|enet sent %d B %d pkts, recv %d B %d pkts"
			)
			% [
				role,
				w.label,
				w.ms,
				w.out_bytes,
				w.out_wire,
				w.out_wire / seconds,
				w.in_bytes,
				w.in_bytes / seconds,
				w.enet[0],
				w.enet[2],
				w.enet[1],
				w.enet[3],
			]
		)
	)
	for r: Dictionary in w.rows:
		lines.append(
			(
				"NETM|%s|%s|%s|%s|%s|n=%d|bytes=%d|wire=%d|avg=%.0f|per_s=%.1f"
				% [
					role,
					w.label,
					r.dir,
					r.name,
					r.mode,
					r.count,
					r.bytes,
					r.wire,
					float(r.bytes) / maxf(r.count, 1),
					r.count / seconds,
				]
			)
		)
	return lines
