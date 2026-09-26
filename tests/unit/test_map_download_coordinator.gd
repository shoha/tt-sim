extends GutTest

## MapDownloadCoordinator with the AssetStreamer replaced by a double: a map loads only
## once every expected file (map.glb, map.ttmap) is here, failures route like the host's
## loader (GLB failure fails the map, a document failure beside a GLB loads the GLB alone),
## other downloads are ignored, and a load that finishes after a reset is discarded.
## Nothing here goes over a real network; the Steam transport itself is not exercised.

const FOLDER := "clearing"


class FakeStreamer:
	extends Node
	signal asset_received(
		pack_id: String, asset_id: String, variant_id: String, local_path: String, file_type: String
	)
	signal asset_failed(
		pack_id: String, asset_id: String, variant_id: String, error: String, file_type: String
	)
	signal transfer_progress(
		pack_id: String, asset_id: String, variant_id: String, progress: float, file_type: String
	)

	var enabled := true
	var requests: Array = []
	var cached: Dictionary = {}

	func is_enabled() -> bool:
		return enabled

	func request_map_file_from_host(level_folder: String, variant_id: String) -> void:
		requests.append([level_folder, variant_id])

	func get_cached_map_file(level_folder: String, variant_id: String, _hash: String) -> String:
		return cached.get(level_folder + "/" + variant_id, "")

	func receive(variant_id: String, path: String, folder: String = FOLDER) -> void:
		asset_received.emit(Paths.LEVEL_MAPS_PACK_ID, folder, variant_id, path, "model")

	func fail(variant_id: String) -> void:
		asset_failed.emit(Paths.LEVEL_MAPS_PACK_ID, FOLDER, variant_id, "gone", "model")


var _streamer: FakeStreamer
var _coordinator: MapDownloadCoordinator
var _loads: Array = []
var _finalized: Array = []
var _failures: Array = []


func before_each() -> void:
	_streamer = FakeStreamer.new()
	add_child_autofree(_streamer)
	_loads.clear()
	_finalized.clear()
	_failures.clear()
	_coordinator = MapDownloadCoordinator.new()
	_coordinator.streamer = _streamer
	_coordinator.setup(_load, func(map: Node3D) -> void: _finalized.append(map))
	_coordinator.connect_asset_streamer()
	_coordinator.map_download_failed.connect(
		func(folder: String, error: String) -> void: _failures.append([folder, error])
	)


func after_each() -> void:
	_coordinator.reset()
	for map in _finalized:
		if is_instance_valid(map):
			map.free()


## The injected load: a coroutine like LevelPlayLoader.load_map_sources_async.
func _load(glb_path: String, document_path: String) -> Node3D:
	_loads.append([glb_path, document_path])
	await get_tree().process_frame
	return Node3D.new()


func test_waits_for_both_files_before_loading() -> void:
	var missing := [Paths.LEVEL_MAP_VARIANT, Paths.LEVEL_MAP_DOCUMENT_VARIANT]
	assert_true(_coordinator.request_map_download(FOLDER, missing))
	assert_eq(_streamer.requests, [[FOLDER, "map"], [FOLDER, "ttmap"]])
	_streamer.receive("map", "user://cache/map.glb")
	assert_eq(_loads, [], "one of two files is not enough")
	assert_eq(_coordinator.waiting_variants(), ["ttmap"])
	_streamer.receive("ttmap", "user://cache/map.ttmap")
	assert_eq(_loads, [["user://cache/map.glb", "user://cache/map.ttmap"]])
	await wait_process_frames(2)
	assert_eq(_finalized.size(), 1)
	assert_false(_coordinator.is_map_downloading())


func test_files_already_here_join_the_downloaded_ones() -> void:
	_coordinator.request_map_download(FOLDER, ["ttmap"], {"map": "user://levels/x/map.glb"})
	assert_eq(_streamer.requests, [[FOLDER, "ttmap"]])
	_streamer.receive("ttmap", "user://cache/map.ttmap")
	assert_eq(_loads, [["user://levels/x/map.glb", "user://cache/map.ttmap"]])
	await wait_process_frames(2)
	assert_eq(_finalized.size(), 1)


func test_a_failed_glb_fails_the_map() -> void:
	_coordinator.request_map_download(FOLDER, ["map", "ttmap"])
	_streamer.receive("ttmap", "user://cache/map.ttmap")
	_streamer.fail("map")
	assert_eq(_failures, [[FOLDER, "gone"]])
	assert_eq(_loads, [])
	assert_false(_coordinator.is_map_downloading())
	# A late arrival for the abandoned request is ignored.
	_streamer.receive("ttmap", "user://cache/map.ttmap")
	assert_eq(_loads, [])
	assert_push_error(1)


func test_a_failed_document_beside_a_glb_loads_the_glb_alone() -> void:
	_coordinator.request_map_download(FOLDER, ["map", "ttmap"])
	_streamer.fail("ttmap")
	assert_eq(_loads, [], "still waiting for the GLB")
	_streamer.receive("map", "user://cache/map.glb")
	assert_eq(_loads, [["user://cache/map.glb", ""]])
	assert_eq(_failures, [])
	await wait_process_frames(2)
	assert_eq(_finalized.size(), 1)
	assert_engine_error(2)


func test_a_failed_document_of_a_document_only_map_fails_it() -> void:
	_coordinator.request_map_download(FOLDER, ["ttmap"])
	_streamer.fail("ttmap")
	assert_eq(_failures, [[FOLDER, "gone"]])
	assert_eq(_loads, [])
	assert_push_error(1)


func test_other_levels_packs_and_variants_are_ignored() -> void:
	_coordinator.request_map_download(FOLDER, ["ttmap"])
	_streamer.receive("ttmap", "user://cache/other.ttmap", "other_level")
	_streamer.receive("map", "user://cache/map.glb")
	_streamer.asset_received.emit("pokemon", FOLDER, "ttmap", "user://x.glb", "model")
	assert_eq(_loads, [])
	assert_eq(_coordinator.waiting_variants(), ["ttmap"])


func test_a_load_finishing_after_a_reset_is_discarded() -> void:
	_coordinator.request_map_download(FOLDER, ["map"])
	_streamer.receive("map", "user://cache/map.glb")
	assert_eq(_loads.size(), 1)
	_coordinator.reset()
	await wait_process_frames(2)
	assert_eq(_finalized, [])


func test_disabled_streaming_refuses_the_request() -> void:
	_streamer.enabled = false
	assert_false(_coordinator.request_map_download(FOLDER, ["map"]))
	assert_eq(_streamer.requests, [])
	assert_push_error(1)


func test_cached_lookup_goes_through_the_streamer() -> void:
	_streamer.cached = {FOLDER + "/ttmap": "user://cache/map.ttmap"}
	assert_eq(_coordinator.get_cached_map_file(FOLDER, "ttmap", ""), "user://cache/map.ttmap")
	assert_eq(_coordinator.get_cached_map_path(FOLDER), "")
