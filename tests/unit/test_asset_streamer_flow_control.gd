extends GutTest

## AssetStreamer's ack-based flow control and one-peer-at-a-time queue, driven through a
## double that records the chunk and ack RPCs instead of sending them and runs on a test
## clock. Over real Steam, sending a whole map at once
## overflowed the send buffer and lost chunks silently (tests/net/steam_map_download.gd).

const PEER := 7
const PARTS := ["_level_maps", "lvl", "map", "model"]
const KEY := "_level_maps/lvl/map/model"


class StreamerDouble:
	extends "res://autoloads/asset_streamer.gd"
	var sent: Array = []
	var acks: Array = []
	var now: int = 0

	func _send_chunk_rpc(peer_id: int, parts: Array, index: int, chunk: PackedByteArray) -> void:
		sent.append({"peer": peer_id, "key": "/".join(parts), "index": index, "size": chunk.size()})

	func _send_chunk_ack(_download: Dictionary, received_chunks: int) -> void:
		acks.append(received_chunks)

	func _now_ms() -> int:
		return now


var _streamer: StreamerDouble
var _window_chunks: int


func before_each() -> void:
	_streamer = autofree(StreamerDouble.new())
	_window_chunks = _streamer.SEND_WINDOW_BYTES / _streamer.CHUNK_SIZE


func _data(chunks: int, tail: int = 0) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(chunks * _streamer.CHUNK_SIZE + tail)
	return data


func _indices() -> Array:
	return _streamer.sent.map(func(s): return s.index)


func test_window_stays_under_steams_send_buffer() -> void:
	assert_lt(_streamer.SEND_WINDOW_BYTES, 512 * 1024)


func test_first_send_fills_only_the_window() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	assert_eq(_streamer.sent.size(), _window_chunks)
	assert_eq(_indices(), range(_window_chunks))


func test_each_ack_releases_as_many_chunks_as_it_frees() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._on_chunk_ack(PEER, KEY, 3)
	assert_eq(_streamer.sent.size(), _window_chunks + 3)
	assert_eq(_streamer.sent.back().index, _window_chunks + 2)


func test_acks_deliver_every_chunk_once_in_order_then_drop_the_transfer() -> void:
	var total := 25
	_streamer._begin_host_transfer(PEER, PARTS, _data(total - 1, 100), 0)
	var guard := 0
	while _streamer._host_transfers.has(PEER) and guard < 100:
		_streamer._on_chunk_ack(PEER, KEY, _streamer.sent.size())
		guard += 1
	assert_eq(_indices(), range(total))
	assert_eq(_streamer.sent.back().size, 100, "short last chunk")
	assert_false(_streamer._host_transfers.has(PEER), "finished transfer dropped")


func test_acks_never_move_backwards_or_past_what_was_sent() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._on_chunk_ack(PEER, KEY, 1000)
	var state: Dictionary = _streamer._host_transfers[PEER][KEY]
	assert_eq(state.acked_chunks, _window_chunks, "clamped to the chunks sent")
	assert_eq(_streamer.sent.size(), 2 * _window_chunks, "one window refilled, no more")
	_streamer._on_chunk_ack(PEER, KEY, 1)
	assert_eq(state.acked_chunks, _window_chunks, "a stale ack is ignored")


func test_transfers_to_one_peer_share_its_window() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER, ["_level_maps", "lvl", "ttmap", "ttmap"], _data(40), 0)
	assert_eq(_streamer.sent.size(), _window_chunks, "second transfer waits")
	_streamer._on_chunk_ack(PEER, KEY, _window_chunks)
	assert_eq(_streamer.sent.size(), 2 * _window_chunks)


func _peers_sent() -> Array:
	return _streamer.sent.map(func(s): return s.peer)


## Acks every chunk sent to `peer` so far, until its transfer is done (bounded).
func _ack_until_done(peer: int) -> void:
	var guard := 0
	while _streamer._host_transfers.has(peer) and guard < 100:
		var sent_to_peer := _streamer.sent.filter(func(s): return s.peer == peer).size()
		_streamer._on_chunk_ack(peer, KEY, sent_to_peer)
		guard += 1


func test_only_the_first_peer_is_served() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(40), 0)
	assert_eq(_streamer.sent.size(), _window_chunks, "the second peer waits")
	assert_false(_peers_sent().has(PEER + 1))
	assert_eq(_streamer._host_queue, [PEER, PEER + 1])


func test_the_next_peer_is_served_when_the_first_finishes() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(20), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(20), 0)
	_streamer._begin_host_transfer(PEER + 2, PARTS, _data(20), 0)
	_ack_until_done(PEER)
	assert_eq(_streamer._host_queue, [PEER + 1, PEER + 2])
	assert_eq(_streamer.sent.back().peer, PEER + 1)
	_ack_until_done(PEER + 1)
	_ack_until_done(PEER + 2)
	assert_eq(_streamer._host_queue, [])
	assert_eq(_streamer._active_peer, 0)
	for peer in [PEER, PEER + 1, PEER + 2]:
		var indices := (
			_streamer.sent.filter(func(s): return s.peer == peer).map(func(s): return s.index)
		)
		assert_eq(indices, range(20), "each peer gets the whole file once")


func test_a_waiting_peers_ack_sends_nothing() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(40), 0)
	_streamer._on_chunk_ack(PEER + 1, KEY, 5)
	assert_eq(_streamer.sent.size(), _window_chunks)
	assert_eq(_streamer._host_transfers[PEER + 1][KEY].acked_chunks, 0)


func test_disconnect_of_the_served_peer_serves_the_next() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(40), 0)
	_streamer._on_peer_disconnected(PEER)
	assert_eq(_streamer._host_queue, [PEER + 1])
	assert_eq(_streamer._active_peer, PEER + 1)
	assert_eq(_streamer.sent.back().peer, PEER + 1)


func test_disconnect_of_a_waiting_peer_leaves_the_served_one() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(40), 0)
	_streamer._on_peer_disconnected(PEER + 1)
	assert_eq(_streamer._host_queue, [PEER])
	assert_eq(_streamer._active_peer, PEER)
	assert_eq(_streamer.sent.size(), _window_chunks, "nothing resent")


func test_a_stalled_peer_goes_to_the_back_and_keeps_its_position() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, PARTS, _data(40), 0)
	_streamer._on_chunk_ack(PEER, KEY, 3)
	_streamer.now = _streamer.STALL_TIMEOUT_MS - 1
	_streamer._check_stall(_streamer.now)
	assert_eq(_streamer._active_peer, PEER, "not yet stalled")
	_streamer.now = _streamer.STALL_TIMEOUT_MS
	_streamer._check_stall(_streamer.now)
	assert_eq(_streamer._host_queue, [PEER + 1, PEER])
	assert_eq(_streamer._active_peer, PEER + 1)
	assert_eq(_streamer.sent.back().peer, PEER + 1)
	var state: Dictionary = _streamer._host_transfers[PEER][KEY]
	assert_eq(state.next_chunk, 3, "rewound to the last ack")
	var before := _streamer.sent.size()
	_ack_until_done(PEER + 1)
	assert_eq(_streamer._active_peer, PEER)
	var resent: Array = _streamer.sent.slice(before).filter(func(s): return s.peer == PEER)
	assert_eq(resent.front().index, 3, "resumes from the last ack")
	assert_engine_error(1, "the stall is logged")


func test_ack_progress_restarts_the_stall_clock() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer.now = _streamer.STALL_TIMEOUT_MS - 1
	_streamer._on_chunk_ack(PEER, KEY, 2)
	_streamer.now = _streamer.STALL_TIMEOUT_MS + 5
	_streamer._check_stall(_streamer.now)
	assert_eq(_streamer._host_transfers[PEER][KEY].next_chunk, _window_chunks + 2, "no rewind")


func test_a_lone_stalled_peer_is_resent_from_its_last_ack() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._on_chunk_ack(PEER, KEY, 2)
	_streamer.sent.clear()
	_streamer.now = _streamer.STALL_TIMEOUT_MS
	_streamer._check_stall(_streamer.now)
	assert_eq(_indices(), range(2, 2 + _window_chunks))
	assert_engine_error(1, "the stall is logged")


func test_ack_for_an_unknown_transfer_is_ignored() -> void:
	_streamer._on_chunk_ack(PEER, KEY, 5)
	assert_eq(_streamer.sent.size(), 0)


func test_resume_starts_at_the_requested_chunk() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 30)
	assert_eq(_indices(), range(30, 30 + _window_chunks))


func test_disconnect_drops_the_peers_transfers() -> void:
	_streamer._begin_host_transfer(PEER, PARTS, _data(40), 0)
	_streamer._on_peer_disconnected(PEER)
	assert_false(_streamer._host_transfers.has(PEER))


func _start_client_download(total_chunks: int) -> Dictionary:
	_streamer._client_downloads[KEY] = {
		"pack_id": PARTS[0],
		"asset_id": PARTS[1],
		"variant_id": PARTS[2],
		"file_type": PARTS[3],
		"chunks": [],
		"total_chunks": 0,
		"received_count": 0,
		"original_size": 0,
	}
	_streamer._rpc_asset_header(PARTS[0], PARTS[1], PARTS[2], PARTS[3], total_chunks, 1000)
	return _streamer._client_downloads[KEY]


func _receive(index: int) -> void:
	var chunk := PackedByteArray([1, 2, 3])
	_streamer._rpc_asset_chunk(PARTS[0], PARTS[1], PARTS[2], PARTS[3], index, chunk)


func test_client_acks_the_unbroken_run_of_chunks() -> void:
	_start_client_download(5)
	_receive(0)
	_receive(1)
	_receive(3)
	_receive(2)
	assert_eq(_streamer.acks, [1, 2, 2, 4])
	var status: Dictionary = _streamer.get_download_status(KEY)
	assert_eq(status.received_chunks, 4)
	assert_eq(status.received_bytes, 12)


func test_client_counts_a_repeated_chunk_once() -> void:
	_start_client_download(5)
	_receive(0)
	_receive(0)
	assert_eq(_streamer.get_download_status(KEY).received_chunks, 1)


func test_resumed_download_keeps_its_chunks_and_asks_from_the_first_gap() -> void:
	_start_client_download(5)
	_receive(0)
	_receive(1)
	_streamer._save_partial_transfers()
	var partial: Dictionary = _streamer._partial_transfers[KEY]
	assert_eq(_streamer.first_missing_chunk(partial.chunks), 2)
	_streamer._client_downloads[KEY] = partial.duplicate(true)
	_streamer._rpc_asset_header(PARTS[0], PARTS[1], PARTS[2], PARTS[3], 5, 1000)
	assert_eq(_streamer.get_download_status(KEY).received_chunks, 2, "chunks kept")
	_receive(2)
	assert_eq(_streamer.acks.back(), 3, "acks continue from the kept run")


func test_a_changed_file_restarts_a_resumed_download() -> void:
	_start_client_download(5)
	_receive(0)
	_streamer._rpc_asset_header(PARTS[0], PARTS[1], PARTS[2], PARTS[3], 6, 1200)
	assert_eq(_streamer.get_download_status(KEY).received_chunks, 0)
