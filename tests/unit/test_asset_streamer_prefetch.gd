extends GutTest

## AssetStreamer's prefetch path (SessionPrefetch's transfers): the host serves every table
## transfer (a token asset, a file of the map on the table) before any prefetch, across peers
## and within one peer's window, and a prefetch of the map just set out becomes a table
## transfer in place; on the client a prefetch takes no download slot, a table request takes a
## prefetch of the same file over, and a cancel drops it at both ends; a prefetched file lands
## in the download cache, where the table's load finds it with no second download. Driven
## through a double that records the chunk, request and cancel RPCs and sets the table folder.

const StreamerScript := preload("res://autoloads/asset_streamer.gd")
const PEER := 7
## The map on the table and a shelf map (folders no real level has).
const CAMP := "_prefetch_camp"
const MILL := "_prefetch_mill"
const TABLE_MAP := ["_level_maps", CAMP, "map", "model"]
const SHELF_MAP := ["_level_maps", MILL, "map", "model"]
const SHELF_DOC := ["_level_maps", MILL, "ttmap", "map_document"]
const TOKEN := ["some_pack", "hero", "default", "model"]
const DOCUMENT := "a prefetched map document"


class StreamerDouble:
	extends "res://autoloads/asset_streamer.gd"
	var sent: Array = []
	var requests: Array = []
	var cancels: Array = []
	var table := ""

	func _send_chunk_rpc(peer_id: int, parts: Array, index: int, _chunk: PackedByteArray) -> void:
		sent.append({"peer": peer_id, "key": "/".join(parts), "index": index})

	func _send_chunk_ack(_download: Dictionary, _received_chunks: int) -> void:
		pass

	func _send_request(request: Dictionary, _resume_from: int) -> void:
		requests.append(request.key)

	func _send_cancel(download: Dictionary) -> void:
		cancels.append(download.asset_id)

	func _table_folder() -> String:
		return table


var _streamer: StreamerDouble
var _window: int


func before_each() -> void:
	_streamer = StreamerDouble.new()
	# In the tree: a client request reads the scene multiplayer's peer (GUT's offline one).
	add_child_autofree(_streamer)
	_streamer.setup(AssetManager.cache, AssetManager)
	_streamer.set_enabled(true)
	_window = _streamer.SEND_WINDOW_BYTES / _streamer.CHUNK_SIZE


func after_each() -> void:
	AssetManager.cache.remove_cached(
		Paths.LEVEL_MAPS_PACK_ID, MILL, "ttmap", Paths.LEVEL_MAP_DOCUMENT_FILE_TYPE
	)


func _data(chunks: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(chunks * _streamer.CHUNK_SIZE)
	return data


func _keys_sent_to(peer: int) -> Array:
	return _streamer.sent.filter(func(s: Dictionary) -> bool: return s.peer == peer).map(
		func(s: Dictionary) -> String: return s.key
	)


## Acks everything sent to `peer` for `parts` so far.
func _ack_all(peer: int, parts: Array) -> void:
	var key := "/".join(parts)
	var count := _keys_sent_to(peer).filter(func(k: String) -> bool: return k == key).size()
	_streamer._on_chunk_ack(peer, key, count)


func test_a_prefetch_is_a_level_map_off_the_table() -> void:
	assert_true(StreamerScript.is_prefetch_transfer(SHELF_MAP, CAMP))
	assert_false(StreamerScript.is_prefetch_transfer(TABLE_MAP, CAMP), "the table's map")
	assert_true(StreamerScript.is_prefetch_transfer(TABLE_MAP, ""), "in the room")
	assert_false(StreamerScript.is_prefetch_transfer(TOKEN, ""), "a token asset")
	assert_false(StreamerScript.is_prefetch_transfer(TOKEN, CAMP))


func test_another_peers_table_transfer_is_served_before_a_prefetch() -> void:
	_streamer._begin_host_transfer(PEER, SHELF_MAP, _data(40), 0)
	assert_eq(_keys_sent_to(PEER).size(), _window, "the prefetch goes while nothing else waits")
	_streamer._begin_host_transfer(PEER + 1, TOKEN, _data(20), 0)
	assert_eq(_streamer._active_peer, PEER + 1, "the table transfer is served at once")
	assert_eq(_keys_sent_to(PEER + 1).size(), _window)
	_ack_all(PEER, SHELF_MAP)
	assert_eq(_keys_sent_to(PEER).size(), _window, "the prefetch waits; its acks are kept")
	assert_eq(_streamer._host_transfers[PEER]["/".join(SHELF_MAP)].acked_chunks, _window)
	var guard := 0
	while _streamer._host_transfers.has(PEER + 1) and guard < 50:
		_ack_all(PEER + 1, TOKEN)
		guard += 1
	assert_eq(_streamer._active_peer, PEER, "the prefetch resumes once the table is served")
	var resumed: Array = _streamer.sent.filter(func(s: Dictionary) -> bool: return s.peer == PEER)
	assert_eq(resumed[_window].index, _window, "from where it was")
	assert_eq(_streamer._host_queue, [PEER], "it kept its place")


func test_within_one_peer_the_table_takes_the_window_first() -> void:
	_streamer.table = CAMP
	_streamer._begin_host_transfer(PEER, SHELF_MAP, _data(40), 0)
	_streamer._begin_host_transfer(PEER, TABLE_MAP, _data(40), 0)
	assert_eq(_keys_sent_to(PEER).size(), _window, "the window is full")
	_ack_all(PEER, SHELF_MAP)
	var after: Array = _keys_sent_to(PEER).slice(_window)
	assert_eq(after.size(), _window)
	assert_true(after.all(func(k: String) -> bool: return k == "/".join(TABLE_MAP)))


func test_setting_a_map_out_makes_its_prefetch_a_table_transfer() -> void:
	_streamer._begin_host_transfer(PEER, SHELF_MAP, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, TABLE_MAP, _data(40), 0)
	assert_eq(_streamer._active_peer, PEER, "in the room both are prefetches: first come")
	_streamer.table = CAMP
	_ack_all(PEER, SHELF_MAP)
	assert_eq(_streamer._active_peer, PEER + 1, "set out: the table's map goes first")


func test_a_cancelled_transfer_serves_the_next_peer() -> void:
	_streamer._begin_host_transfer(PEER, SHELF_MAP, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, SHELF_MAP, _data(40), 0)
	_streamer.drop_transfer(PEER, "/".join(SHELF_MAP))
	assert_eq(_streamer._host_queue, [PEER + 1])
	assert_eq(_streamer._active_peer, PEER + 1)


func test_a_map_that_leaves_the_shelf_stops_for_everyone() -> void:
	_streamer.table = CAMP
	_streamer._begin_host_transfer(PEER, SHELF_MAP, _data(40), 0)
	_streamer._begin_host_transfer(PEER + 1, SHELF_DOC, _data(4), 0)
	_streamer._begin_host_transfer(PEER + 1, TABLE_MAP, _data(4), 0)
	_streamer.drop_level_transfers(MILL)
	assert_false(_streamer._host_transfers.has(PEER))
	assert_eq(_streamer._host_transfers[PEER + 1].keys(), ["/".join(TABLE_MAP)])
	assert_eq(_streamer._host_queue, [PEER + 1])


func test_a_prefetch_takes_no_download_slot() -> void:
	_streamer.request_map_file_from_host(MILL, "map", 50, true)
	_streamer.request_map_file_from_host(MILL, "ttmap", 50, true)
	_streamer.request_map_file_from_host(CAMP, "map")
	_streamer.request_from_host(TOKEN[0], TOKEN[1], TOKEN[2])
	_streamer.request_from_host(TOKEN[0], "villain", TOKEN[2])
	assert_eq(_streamer.requests.size(), 4, "both prefetches and two table requests go")
	assert_eq(_streamer.get_queued_request_count(), 1, "the third table request waits")
	assert_true(_streamer.get_download_status(SessionPrefetch.stream_key(MILL, "map")).prefetch)


func test_a_table_request_takes_a_prefetch_over() -> void:
	_streamer.request_map_file_from_host(MILL, "map", 50, true)
	_streamer.request_map_file_from_host(MILL, "map")
	assert_eq(_streamer.requests.size(), 1, "not asked for twice")
	assert_false(_streamer.get_download_status(SessionPrefetch.stream_key(MILL, "map")).prefetch)
	_streamer.request_map_file_from_host(MILL, "map", 50, true)
	assert_false(
		_streamer.get_download_status(SessionPrefetch.stream_key(MILL, "map")).prefetch,
		"a later prefetch request never takes it back"
	)


func test_a_cancel_drops_the_download_and_tells_the_host() -> void:
	_streamer.request_map_file_from_host(MILL, "map", 50, true)
	var key := SessionPrefetch.stream_key(MILL, "map")
	assert_true(_streamer.cancel_download(key))
	assert_eq(_streamer.get_download_status(key), {})
	assert_eq(_streamer.cancels, [MILL])
	assert_false(_streamer.cancel_download(key), "nothing left to cancel")


## A prefetched document lands in the download cache; the shelf counts it held and the table's
## load takes it from there, with nothing left to download.
func test_a_prefetched_map_is_used_at_set_out() -> void:
	var data := DOCUMENT.to_utf8_buffer()
	var digest := MapFileHash.hash_bytes(data)
	var compressed := data.compress(FileAccess.COMPRESSION_ZSTD)
	_streamer.request_map_file_from_host(MILL, "ttmap", 50, true)
	watch_signals(_streamer)
	_streamer._rpc_asset_header(SHELF_DOC[0], MILL, "ttmap", SHELF_DOC[3], 1, data.size())
	_streamer._rpc_asset_chunk(SHELF_DOC[0], MILL, "ttmap", SHELF_DOC[3], 0, compressed)
	assert_signal_emitted(_streamer, "asset_received")
	var cached := func(folder: String, variant: String, expected: String) -> String:
		return _streamer.get_cached_map_file(folder, variant, expected)
	var ref := {"folder": MILL, "map_path": "", "hashes": {"ttmap": digest}, "name": "Mill"}
	assert_true(SessionChannel.holds_map(ref, cached), "held once it is here")

	var controller := LevelPlayController.new()
	add_child_autofree(controller)
	var loader: LevelPlayLoader = controller._level_loader
	loader.setup(controller)
	controller._map_download_coordinator.streamer = _streamer
	var level := LevelData.new()
	level.level_folder = MILL
	level.map_document = Paths.LEVEL_MAP_DOCUMENT_NAME
	level.map_hashes = {"ttmap": digest}
	var sources := loader._resolve_map_sources(level)
	assert_eq(sources.missing, [], "no second download")
	assert_true(str(sources.found.get("ttmap", "")).ends_with(".ttmap"), "the cached copy")
	assert_eq(_streamer.requests.size(), 1)
