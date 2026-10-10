extends GutTest

## SessionPrefetch: the order a client fetches the shelf maps it lacks (the table's map, the
## GM's selected map, then shelf order), one map at a time with every missing file at once as
## prefetch requests, its progress by bytes and reports, cancel when the map leaves the shelf,
## the next map once one is here, and the host's keeping of the reports. Driven through a
## streamer double that records the requests and cancels; the host's side of a transfer is in
## test_asset_streamer_prefetch.gd and the RPCs between real peers in tests/net/enet_prefetch.gd.

const HASH_A := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const HASH_B := "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
## Folders no real level has; nothing is written under them.
const MILL := "_prefetch_mill"
const FEN := "_prefetch_fen"
const CAMP := "_prefetch_camp"


class FakeStreamer:
	extends Node
	signal asset_received(
		pack_id: String, asset_id: String, variant_id: String, local_path: String, file_type: String
	)
	signal asset_failed(
		pack_id: String, asset_id: String, variant_id: String, error: String, file_type: String
	)
	var requests: Array = []
	var cancels: Array = []
	## stream key -> get_download_status() result
	var status: Dictionary = {}
	## "folder/variant" -> cached path
	var cached: Dictionary = {}

	func request_map_file_from_host(
		folder: String, variant: String, _priority: int = 50, prefetch := false
	) -> void:
		requests.append([folder, variant, prefetch])
		var key := SessionPrefetch.stream_key(folder, variant)
		if not status.has(key):
			status[key] = {"received_chunks": 0, "total_chunks": 0, "original_size": 0}
			status[key]["prefetch"] = prefetch

	func get_download_status(key: String) -> Dictionary:
		return status.get(key, {})

	func cancel_download(key: String) -> bool:
		cancels.append(key)
		return status.erase(key)

	func get_cached_map_file(folder: String, variant: String, _hash: String) -> String:
		return cached.get(folder + "/" + variant, "")

	## The host's header and `received` of `total` chunks of a file of `size` bytes.
	func progress(folder: String, variant: String, received: int, total: int, size: int) -> void:
		var key := SessionPrefetch.stream_key(folder, variant)
		status[key]["received_chunks"] = received
		status[key]["total_chunks"] = total
		status[key]["original_size"] = size

	func finish(folder: String, variant: String) -> void:
		status.erase(SessionPrefetch.stream_key(folder, variant))
		cached[folder + "/" + variant] = "user://cache/%s.%s" % [folder, variant]
		var file_type := Paths.get_level_map_file_type(variant)
		asset_received.emit(Paths.LEVEL_MAPS_PACK_ID, folder, variant, "", file_type)

	func fail(folder: String, variant: String) -> void:
		status.erase(SessionPrefetch.stream_key(folder, variant))
		var file_type := Paths.get_level_map_file_type(variant)
		asset_failed.emit(Paths.LEVEL_MAPS_PACK_ID, folder, variant, "Asset not found", file_type)


class PrefetchDouble:
	extends "res://autoloads/session_prefetch.gd"
	var reports: Array = []
	var held := 0
	var now := 0

	func _send_report(report: Dictionary) -> void:
		reports.append(report)

	func _note_held() -> void:
		held += 1

	func _now_ms() -> int:
		return now


var _streamer: FakeStreamer
var _prefetch: PrefetchDouble


func before_each() -> void:
	_streamer = FakeStreamer.new()
	add_child_autofree(_streamer)
	_prefetch = PrefetchDouble.new()
	_prefetch.streamer = _streamer
	add_child_autofree(_prefetch)


func _ref(folder: String, hashes := {"map": HASH_A, "ttmap": HASH_B}) -> Dictionary:
	return {"folder": folder, "map_path": "", "hashes": hashes, "name": folder}


func _keys(refs: Array) -> Array:
	return refs.map(func(r: Dictionary) -> String: return SessionChannel.ref_key(r))


func test_order_is_the_table_then_the_gms_pick_then_the_shelf() -> void:
	var shelf := [_ref(CAMP), _ref(MILL), _ref(FEN)]
	assert_eq(_keys(SessionPrefetch.order(shelf, "", "")), [CAMP, MILL, FEN])
	assert_eq(_keys(SessionPrefetch.order(shelf, "", FEN)), [FEN, CAMP, MILL])
	assert_eq(_keys(SessionPrefetch.order(shelf, MILL, FEN)), [MILL, FEN, CAMP])
	assert_eq(_keys(SessionPrefetch.order(shelf, FEN, FEN)), [FEN, CAMP, MILL], "once each")
	assert_eq(_keys(SessionPrefetch.order(shelf, "gone", "")), [CAMP, MILL, FEN])


func test_a_maps_percent_is_by_bytes_and_never_100() -> void:
	var glb := {"size": 9000, "fraction": 0.5}
	var doc := {"size": 1000, "fraction": 1.0}
	assert_eq(SessionPrefetch.map_percent([glb, doc]), 55)
	assert_eq(SessionPrefetch.map_percent([{"size": 0, "fraction": 1.0}, glb]), 0, "size unknown")
	assert_eq(SessionPrefetch.map_percent([{"size": 10, "fraction": 1.0}]), 99, "held says 100")
	assert_eq(SessionPrefetch.map_percent([]), 0)


func test_a_client_fetches_the_first_missing_map_with_every_file_at_once() -> void:
	_streamer.cached[CAMP + "/map"] = "user://cache/camp.glb"
	_streamer.cached[CAMP + "/ttmap"] = "user://cache/camp.ttmap"
	var shelf := [_ref(CAMP), _ref(MILL), _ref(FEN)]
	_prefetch.step(shelf, "", FEN)
	assert_eq(_prefetch.current_key(), FEN, "the GM's pick first; camp is here already")
	assert_eq(_streamer.requests, [[FEN, "map", true], [FEN, "ttmap", true]])
	assert_eq(_prefetch.reports, [{FEN: 0, MILL: 0}], "the map and the one behind it wait")
	_prefetch.step(shelf, "", MILL)
	assert_eq(_streamer.requests.size(), 2, "a fetch under way is not switched")
	assert_eq(_prefetch.reports.size(), 1, "an unchanged report is not sent")


func test_progress_is_reported_at_most_every_interval() -> void:
	_prefetch.step([_ref(MILL)], "", "")
	_streamer.progress(MILL, "map", 5, 10, 9000)
	_streamer.progress(MILL, "ttmap", 0, 2, 1000)
	_prefetch._process(0.0)
	assert_eq(_prefetch.reports.size(), 1, "not before the interval")
	_prefetch.now = int(SessionPrefetch.REPORT_S * 1000.0)
	_prefetch._process(0.0)
	assert_eq(_prefetch.reports.back(), {MILL: 45})


func test_a_finished_map_is_reported_held_and_the_next_one_starts() -> void:
	var shelf := [_ref(MILL), _ref(FEN, {"map": HASH_A})]
	_prefetch.step(shelf, "", "")
	_streamer.finish(MILL, "map")
	assert_eq(_prefetch.current_key(), MILL, "one file still to come")
	_streamer.finish(MILL, "ttmap")
	assert_eq(_prefetch.held, 1, "holdings reported at once")
	assert_eq(_prefetch.current_key(), "")
	assert_eq(_prefetch.reports.back(), {FEN: 0})
	_prefetch.step(shelf, "", "")
	assert_eq(_prefetch.current_key(), FEN)
	assert_eq(_streamer.requests.back(), [FEN, "map", true])


func test_a_map_that_leaves_the_shelf_is_cancelled() -> void:
	_prefetch.step([_ref(MILL), _ref(FEN)], "", "")
	_streamer.progress(MILL, "map", 3, 10, 9000)
	_prefetch.step([_ref(FEN)], "", "")
	assert_eq(
		_streamer.cancels,
		[SessionPrefetch.stream_key(MILL, "map"), SessionPrefetch.stream_key(MILL, "ttmap")]
	)
	assert_eq(_prefetch.current_key(), FEN, "the next map starts")
	assert_eq(_prefetch.reports.back(), {FEN: 0})


## The table's load may have taken the file over (AssetStreamer clears its prefetch flag): a
## cancel never drops a download the table needs.
func test_a_cancel_leaves_a_download_the_table_took_over() -> void:
	_prefetch.step([_ref(MILL)], "", "")
	_streamer.status[SessionPrefetch.stream_key(MILL, "map")]["prefetch"] = false
	_prefetch.step([], "", "")
	assert_eq(_streamer.cancels, [SessionPrefetch.stream_key(MILL, "ttmap")])


func test_a_failed_map_is_left_for_the_table() -> void:
	var shelf := [_ref(MILL), _ref(FEN)]
	_prefetch.step(shelf, "", "")
	_streamer.fail(MILL, "map")
	assert_eq(_streamer.cancels, [SessionPrefetch.stream_key(MILL, "ttmap")], "its other file")
	assert_eq(_prefetch.current_key(), "")
	_prefetch.step(shelf, "", "")
	assert_eq(_prefetch.current_key(), FEN, "not tried again; the next map instead")
	assert_eq(_prefetch.reports.back(), {FEN: 0})
	assert_engine_error(1, "the failure is logged")


func test_a_map_with_nothing_missing_or_shipped_is_not_fetched() -> void:
	var shipped := {"folder": "", "map_path": "res://x.glb", "hashes": {}, "name": "Shipped"}
	_prefetch.step([shipped, _ref(CAMP, {})], "", "")
	assert_eq(_streamer.requests, [])
	assert_eq(_prefetch.reports, [], "nothing to report")


func test_the_host_keeps_reports_of_shelf_maps_only() -> void:
	watch_signals(_prefetch)
	_prefetch.note_progress("enet-ana", {MILL: 40, "elsewhere": 3, FEN: 250.0}, [MILL, FEN])
	assert_eq(_prefetch.get_progress(), {"enet-ana": {MILL: 40, FEN: SessionPrefetch.MAX_PERCENT}})
	assert_signal_emit_count(_prefetch, "progress_changed", 1)
	_prefetch.note_progress("enet-ana", {MILL: 40, FEN: 99}, [MILL, FEN])
	assert_signal_emit_count(_prefetch, "progress_changed", 1, "unchanged")
	_prefetch.note_progress("enet-ana", {}, [MILL, FEN])
	assert_eq(_prefetch.get_progress(), {}, "an empty report clears the player")
	_prefetch.note_progress("enet-ana", "junk", [MILL])
	assert_eq(_prefetch.get_progress(), {})


func test_reports_are_bounded() -> void:
	var raw := {}
	for i in SessionChannel.MAX_SHELF + 10:
		raw["m%d" % i] = i
	assert_eq(SessionPrefetch.clean_report(raw).size(), SessionChannel.MAX_SHELF)
	assert_eq(SessionPrefetch.clean_report({"x".repeat(1000): 5}).keys()[0].length(), 256)
	assert_eq(SessionPrefetch.sanitize_progress({"a": {}, "b": {"m": -4}}), {"b": {"m": 0}})
