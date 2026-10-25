extends GutTest

## The whole library transfer in one process: a client channel and a host channel exchange the
## quote, the player's answer, the chunked stream (two AssetStreamer doubles with the real
## windowed send, acks, header caps and finalize) and the install, over a message queue that
## stands for the network. Covered: the happy path, Skip, a quote over the size cap, Cancel, a
## host that denies, never answers, speaks another protocol, sends a tampered file or a library
## nobody asked for, the map gate (no mismatch dialog after a transfer, the old dialog after a
## Skip), a host that starts using a library mid-session (the hint, and the delta request that
## replaces the first partial), and the end of the session.

const Tw := preload("res://tests/unit/library_transfer_world.gd")
const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_library_transfer_flow"
const SETTINGS := ROOT + "/settings.cfg"
const CLIENT := 7


## The network: messages wait here until the test pumps them.
class Wire:
	extends RefCounted
	var queue: Array[Callable] = []
	var log: Array[String] = []

	func send(label: String, call: Callable) -> void:
		log.append(label)
		queue.append(call)

	func flush() -> int:
		var count := 0
		while not queue.is_empty():
			queue.pop_front().call()
			count += 1
		return count


class ManagerStub:
	extends Node
	var library_transfer: LibraryTransferChannel = null


class StreamerDouble:
	extends "res://autoloads/asset_streamer.gd"
	var wire: Wire
	var peer: Node = null  # the other end's streamer
	var cancelled: Array[String] = []
	var deny: bool = false

	func _send_chunk_rpc(_peer_id: int, parts: Array, index: int, chunk: PackedByteArray) -> void:
		wire.send(
			"chunk",
			func() -> void:
				peer._rpc_asset_chunk(parts[0], parts[1], parts[2], parts[3], index, chunk)
		)

	func _send_header_rpc(_peer_id: int, parts: Array, total: int, size: int) -> void:
		wire.send(
			"header",
			func() -> void:
				peer._rpc_asset_header(parts[0], parts[1], parts[2], parts[3], total, size)
		)

	func _send_chunk_ack(download: Dictionary, received: int) -> void:
		var key := (
			"%s/%s/%s/%s"
			% [download.pack_id, download.asset_id, download.variant_id, download.file_type]
		)
		wire.send("ack", func() -> void: peer._on_chunk_ack(CLIENT, key, received))

	func _send_request(request: Dictionary, resume_from: int) -> void:
		wire.send(
			"request",
			func() -> void:
				if deny:
					_rpc_asset_not_found(
						request.pack_id, request.asset_id, request.variant_id, request.file_type
					)
				else:
					peer._serve_library_parts(
						CLIENT,
						[request.pack_id, request.asset_id, request.variant_id, request.file_type],
						resume_from
					)
		)

	func _send_cancel(download: Dictionary) -> void:
		cancelled.append(str(download.asset_id))
		var key := (
			"%s/%s/%s/%s"
			% [download.pack_id, download.asset_id, download.variant_id, download.file_type]
		)
		wire.send("cancel", func() -> void: peer.drop_transfer(CLIENT, key))


class ChannelDouble:
	extends LibraryTransferChannel
	var wire: Wire
	var other: LibraryTransferChannel
	var base_root: String = ""
	var usage: Dictionary = {}
	var role_host: bool = false
	var reply_protocol: int = -1
	var tamper: bool = false
	var wrong_library: bool = false
	var silent: bool = false
	var quotes_seen: Array = []

	func _is_host() -> bool:
		return role_host

	func _is_client() -> bool:
		return not role_host

	func _send_quote(id: int, request: Dictionary) -> void:
		wire.send("quote", func() -> void: other.answer_quote(CLIENT, id, request))

	func _send_quote_reply(_peer_id: int, request_id: int, reply: Dictionary) -> void:
		if silent:
			return
		var sent := reply.duplicate(true)
		if reply_protocol >= 0:
			sent["protocol"] = reply_protocol
		wire.send("reply", func() -> void: other._rpc_library_quote_reply(request_id, sent))

	func _session_usage() -> Dictionary:
		return usage

	func _send_hint(hint: Dictionary) -> void:
		wire.send("hint", func() -> void: other.handle_hint(hint))

	func _reapply() -> void:
		PaletteLibrary.clear_cache()
		LibraryRegistry.apply(base_root)

	func host_bundle(peer_id: int, request_id_text: String) -> PackedByteArray:
		var bytes := super.host_bundle(peer_id, request_id_text)
		if bytes.is_empty():
			return bytes
		if wrong_library:
			var files: Dictionary = LibraryPartial.decode(bytes)["files"]
			var moved := {}
			for path: String in files:
				moved[path.replace("alienworld/", "intruder/")] = files[path]
			return LibraryPartial.encode(moved)
		if tamper:
			var copy := bytes.duplicate()
			copy[copy.size() - 3] = (copy[copy.size() - 3] + 1) % 256
			# Flip inside a GLB so the digest fails: find the GLB's magic.
			var at := bytes.find(0x67)  # 'g' of glTF
			if at >= 0:
				copy = bytes.duplicate()
				copy[at + 20] = (copy[at + 20] + 1) % 256
			return copy
		return bytes


class UiDouble:
	extends RefCounted
	var answer: bool = true
	var asked: Array[String] = []
	var progress: Array[float] = []
	var notices: Array[String] = []
	var began: int = 0
	var ended: int = 0
	var cancel_now: bool = false
	var on_cancel: Callable

	func ask(model: LibraryTransferConsent) -> bool:
		asked.append(model.message)
		return answer

	func begin_progress(_model: LibraryTransferConsent, cancel: Callable) -> void:
		began += 1
		on_cancel = cancel
		if cancel_now:
			cancel.call()

	func set_progress(_model: LibraryTransferConsent, fraction: float) -> void:
		progress.append(fraction)

	func end_progress() -> void:
		ended += 1

	func notify(text: String) -> void:
		notices.append(text)


var _paths: Dictionary = {}
var _client_user: String = ROOT + "/client_user"
var _wire: Wire
var _host: ChannelDouble
var _client: ChannelDouble
var _host_streamer: StreamerDouble
var _client_streamer: StreamerDouble
var _ui: UiDouble
var _served: Dictionary = {}
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryFromHost.auto_delta_limit = LibraryFromHost.AUTO_DELTA_BYTES
	LibraryFromHost.open_ids = {}
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = Tw.build(ROOT)
	DirAccess.make_dir_recursive_absolute(_client_user)
	LibraryFromHost.auto_delta_limit = LibraryFromHost.AUTO_DELTA_BYTES
	LibraryFromHost.open_ids = {}
	LibraryRegistry.settings_path = SETTINGS
	LibraryRegistry.official_root = _paths["official"]
	# The host serves its library once; its folders stay absolute in `_served`.
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(_paths["base"])
	_served = LibraryRegistry.served()
	# Then this process becomes the client.
	LibraryRegistry.user_root = _client_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(_paths["base"])
	_wire = Wire.new()
	_ui = UiDouble.new()
	_host = _channel(true)
	_client = _channel(false)
	_host.other = _client
	_client.other = _host
	_host.served_override = _served
	_host.usage = LibraryTransfer.usage_of([Tw.map_using_spire()])
	_client.ui = _ui
	_host_streamer = _streamer(_host)
	_client_streamer = _streamer(_client)
	_host_streamer.peer = _client_streamer
	_client_streamer.peer = _host_streamer
	_client.streamer = _client_streamer
	_client.quote_timeout_s = 5.0


func _channel(is_host: bool) -> ChannelDouble:
	var channel := ChannelDouble.new()
	channel.wire = _wire
	channel.role_host = is_host
	channel.base_root = _paths["base"]
	add_child_autofree(channel)
	return channel


func _streamer(channel: ChannelDouble) -> StreamerDouble:
	var streamer := StreamerDouble.new()
	streamer.wire = _wire
	add_child_autofree(streamer)
	var manager := ManagerStub.new()
	manager.library_transfer = channel
	add_child_autofree(manager)
	streamer.setup(AssetManager.cache, manager)
	streamer.set_enabled(true)
	return streamer


func after_each() -> void:
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


## Runs `work` (a coroutine) while pumping the wire, a frame at a time; returns its result.
func _run(work: Callable, frames: int = 600) -> Variant:
	var box := {"done": false, "result": null}
	var runner := func() -> void:
		box["result"] = await work.call()
		box["done"] = true
	runner.call()
	var guard := 0
	while not box["done"] and guard < frames:
		_wire.flush()
		await get_tree().process_frame
		guard += 1
	assert_true(box["done"], "the transfer finished (wire: %s)" % str(_wire.log))
	return box["result"]


func _fetch(doc: MapDocument) -> Dictionary:
	return await _run(func() -> Dictionary: return await _client.fetch_for_document(doc))


func _client_assets() -> Dictionary:
	return PaletteLibrary.get_palette(_paths["base"])["assets"]


## The client's libraries folder: a downloaded collection is an ordinary user library there.
func _received() -> String:
	return _client_user


# ---- the path ----


func test_a_client_asks_is_asked_downloads_and_serves_the_items() -> void:
	assert_false(_client_assets().has(Tw.SPIRE))
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], ["alienworld"])
	assert_eq(out["skipped"], [])
	assert_eq(_ui.asked.size(), 1)
	assert_string_contains(_ui.asked[0], "The host uses the collection Alien World v0.3.1 by Test")
	assert_string_contains(_ui.asked[0], "(1 item,")
	assert_eq(_ui.began, 1)
	assert_eq(_ui.ended, 1)
	assert_gt(_ui.progress.size(), 0)
	assert_eq(_ui.progress.back(), 1.0)
	assert_eq(_ui.notices.size(), 1, "one line says it is kept and where to manage it")
	assert_string_contains(_ui.notices[0], "Received Alien World (1 item) from the host")
	assert_false("Keep" in _ui.notices[0])
	assert_true(_client_assets().has(Tw.SPIRE), "served")
	assert_true(DirAccess.dir_exists_absolute(_client_user.path_join("alienworld")), "kept")
	assert_false(DirAccess.dir_exists_absolute(_client_user.path_join(".received")))
	assert_true(_wire.log.has("quote") and _wire.log.has("request") and _wire.log.has("header"))
	assert_eq(LibraryFromHost.record_of("alienworld")["host"], "the host")
	assert_false(_client.is_busy())
	assert_true(_host._host_requests.has(CLIENT), "the host remembers what it quoted")


func test_what_arrives_is_the_hosts_bytes_checked_end_to_end() -> void:
	await _fetch(Tw.map_using_spire())
	assert_not_null(AssetStore.mesh_for(Tw.SPIRE, _paths["base"]))
	var info := LibraryRegistry.info("alienworld", _paths["base"])
	assert_eq(info["source"], "user", "an ordinary collection")
	assert_true(info["received"], "marked from host")
	assert_false(info["partial"].is_empty())


func test_a_map_that_needs_nothing_asks_nothing() -> void:
	var doc := MapDocument.new()
	doc.scatter["forest_summer_s1/Oak"] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	var out := await _fetch(doc)
	assert_eq(out["installed"], [])
	assert_eq(_wire.log, [], "no message at all")
	assert_eq(_ui.asked, [])


func test_a_host_is_never_asked_of_a_host() -> void:
	_client.role_host = true
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(_wire.log, [])


func test_skip_downloads_nothing_and_leaves_the_old_choice() -> void:
	_ui.answer = false
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(out["skipped"], ["alienworld"])
	assert_false(_wire.log.has("request"), "no bytes were asked for")
	assert_eq(_ui.began, 0)
	assert_false(DirAccess.dir_exists_absolute(_received().path_join("alienworld")))
	assert_eq(_ui.notices, [], "a Skip is quiet")


func test_a_quote_over_the_size_cap_is_refused_with_a_clear_text() -> void:
	_client.size_cap_bytes = 1000
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(_ui.asked, [], "no question for what cannot be downloaded")
	assert_eq(_ui.notices.size(), 1)
	assert_string_contains(_ui.notices[0], "over the")
	assert_string_contains(_ui.notices[0], "limit")
	assert_false(_wire.log.has("request"))


func test_cancel_stops_the_download_and_installs_nothing() -> void:
	_ui.cancel_now = true
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(out["results"][0]["phase"], LibraryTransferConsent.Phase.CANCELLED)
	assert_eq(_client_streamer.get_active_download_count(), 0)
	assert_false(DirAccess.dir_exists_absolute(_received().path_join("alienworld")))
	assert_eq(_ui.ended, 1)


func test_cancel_drops_the_download_in_flight_at_both_ends() -> void:
	# Start the download, then cancel from the sheet before the host has sent anything.
	var box := {"out": null}
	var runner := func() -> void:
		box["out"] = await _client.fetch_for_document(Tw.map_using_spire())
	runner.call()
	var guard := 0
	while _ui.began == 0 and guard < 200:
		_wire.flush()
		await get_tree().process_frame
		guard += 1
	assert_eq(_ui.began, 1)
	_ui.on_cancel.call()
	guard = 0
	while box["out"] == null and guard < 200:
		_wire.flush()
		await get_tree().process_frame
		guard += 1
	assert_eq(box["out"]["installed"], [])
	_wire.flush()
	assert_eq(_client_streamer.cancelled.size(), 1, "the host is told to drop it")
	assert_eq(_host_streamer._host_transfers.size(), 0, "and does")


func test_a_host_that_denies_the_ids_sends_nothing() -> void:
	_host.usage = LibraryTransfer.usage_of([])
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(_ui.asked, [])
	assert_string_contains(_ui.notices[0], "not used by any map")
	assert_false(_host._host_requests.has(CLIENT))


func test_a_host_that_never_answers_ends_with_a_visible_message() -> void:
	_host.silent = true
	_client.quote_timeout_s = 0.1
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_string_contains(_ui.notices[0], "did not answer")
	assert_string_contains(_ui.notices[0], "same version")


func test_a_host_on_another_protocol_fails_visibly() -> void:
	_host.reply_protocol = 99
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_string_contains(_ui.notices[0], "another library transfer version")
	assert_eq(_ui.asked, [])


func test_a_bundle_the_host_never_quoted_is_not_sent() -> void:
	assert_eq(_host.host_bundle(CLIENT, "5").size(), 0)
	assert_eq(_host.host_bundle(CLIENT, "not a number").size(), 0)
	assert_eq(_host.host_bundle(99, "1").size(), 0)


func test_a_tampered_file_fails_the_check_and_nothing_is_installed() -> void:
	_host.tamper = true
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_eq(out["results"][0]["phase"], LibraryTransferConsent.Phase.FAILED)
	assert_string_contains(_ui.notices[0], "not installed")
	assert_false(DirAccess.dir_exists_absolute(_received().path_join("alienworld")))
	assert_false(_client_assets().has(Tw.SPIRE))


func test_a_host_that_sends_another_library_than_the_one_quoted_is_refused() -> void:
	_host.wrong_library = true
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["installed"], [])
	assert_string_contains(_ui.notices[0], "did not send the library")


func test_a_failed_stream_is_reported_and_leaves_no_trace() -> void:
	_client_streamer.deny = true
	var out := await _fetch(Tw.map_using_spire())
	assert_push_error("Asset not found on host")
	assert_eq(out["installed"], [])
	assert_string_contains(_ui.notices[0], "download failed")
	assert_false(DirAccess.dir_exists_absolute(_received().path_join("alienworld")))


func test_the_host_keeps_at_most_a_few_quotes_per_peer() -> void:
	var request := Tw.request_for(Tw.map_using_spire(), {}, {})
	for id in range(1, LibraryTransferChannel.MAX_PENDING_PER_PEER + 4):
		await _host.decide(CLIENT, id, request)
	assert_eq(_host._host_requests[CLIENT].size(), LibraryTransferChannel.MAX_PENDING_PER_PEER)
	assert_false(_host._host_requests[CLIENT].has(1), "the oldest went")


func test_a_peer_leaving_drops_its_quotes() -> void:
	var request := Tw.request_for(Tw.map_using_spire(), {}, {})
	await _host.decide(CLIENT, 1, request)
	_host._on_peer_disconnected(CLIENT)
	assert_false(_host._host_requests.has(CLIENT))


func test_the_host_refuses_a_malformed_request_with_a_reason() -> void:
	var reply := await _host.decide(CLIENT, 1, {"protocol": 1, "library": "alienworld"})
	assert_false(reply["ok"])
	assert_eq(reply["code"], "request")


func test_a_library_header_over_the_caps_is_refused_before_anything_is_allocated() -> void:
	var pack := Paths.LIBRARY_PARTS_PACK_ID
	_client_streamer.request_from_host(pack, "9", "bundle", "bundle")
	var failures: Array = []
	_client_streamer.asset_failed.connect(
		func(_p: String, _a: String, _v: String, error: String, _t: String) -> void:
			failures.append(error)
	)
	_client_streamer._rpc_asset_header(pack, "9", "bundle", "bundle", 99999999, 4000000000)
	assert_eq(failures.size(), 1)
	assert_eq(_client_streamer.get_active_download_count(), 0)


func test_a_chunk_bigger_than_the_chunk_size_is_ignored() -> void:
	var pack := Paths.LIBRARY_PARTS_PACK_ID
	_client_streamer.request_from_host(pack, "10", "bundle", "bundle")
	_client_streamer._rpc_asset_header(pack, "10", "bundle", "bundle", 2, 40000)
	var big := PackedByteArray()
	big.resize(_client_streamer.CHUNK_SIZE + 1)
	_client_streamer._rpc_asset_chunk(pack, "10", "bundle", "bundle", 0, big)
	var status := _client_streamer.get_download_status("%s/10/bundle/bundle" % pack)
	assert_eq(status["received_chunks"], 0)


func test_a_clients_live_edit_op_is_held_while_a_transfer_runs() -> void:
	var service := LiveEdits.new()
	service.sends = false
	service.table_key = 5
	# The live node's channel is the autoload's; make it busy for the held check.
	AssetManager.library_transfer._busy = 1
	service.receive_op(5, 0, PackedByteArray([1]))
	AssetManager.library_transfer._busy = 0
	assert_eq(service._held.size(), 1)
	assert_eq(service.op_log.size(), 0, "not applied yet")
	assert_true(AssetManager.library_transfer.idle.is_connected(service._flush_held))
	AssetManager.library_transfer.idle.disconnect(service._flush_held)
	service.free()


# ---- the map gate ----


func test_the_gate_does_not_show_the_mismatch_dialog_after_a_transfer() -> void:
	var doc := Tw.map_using_spire()
	var asked: Array = []
	var choose := func(report: Dictionary) -> bool:
		asked.append(report)
		return true
	var gate: Dictionary = await _run(
		func() -> Dictionary:
			return await MapLibraryGate.run(doc, choose, _paths["base"], _client.fetch_for_document)
	)
	assert_eq(asked, [], "the plants arrived, nothing is missing")
	assert_true(gate["proceed"])
	assert_eq(gate["fetched"], ["alienworld"])
	assert_true(gate["report"]["ok"])
	assert_true(doc.scatter.has(Tw.SPIRE), "the map keeps its plants")


func test_the_gate_falls_back_to_open_without_after_a_skip() -> void:
	_ui.answer = false
	var doc := Tw.map_using_spire()
	var asked: Array = []
	var choose := func(report: Dictionary) -> bool:
		asked.append(report)
		return true
	var gate: Dictionary = await _run(
		func() -> Dictionary:
			return await MapLibraryGate.run(doc, choose, _paths["base"], _client.fetch_for_document)
	)
	assert_eq(asked.size(), 1, "the existing dialog follows a Skip")
	assert_eq(gate["fetched"], [])
	assert_false(doc.scatter.has(Tw.SPIRE), "open without those plants")


func test_the_gate_without_a_fetch_is_unchanged() -> void:
	var doc := Tw.map_using_spire()
	var asked: Array = []
	var choose := func(report: Dictionary) -> bool:
		asked.append(report)
		return false
	var gate: Dictionary = await _run(
		func() -> Dictionary: return await MapLibraryGate.run(doc, choose, _paths["base"])
	)
	assert_eq(asked.size(), 1)
	assert_false(gate["proceed"])


# ---- late edits: a host that starts using a library ----


func test_a_host_announcing_a_new_library_makes_the_client_fetch_it() -> void:
	var host_doc := Tw.map_using_spire()
	_host.announce_document(host_doc)
	assert_eq(_wire.log.count("hint"), 1)
	var guard := 0
	while guard < 400 and (guard < 3 or not _wire.queue.is_empty() or _client.is_busy()):
		_wire.flush()
		await get_tree().process_frame
		guard += 1
	assert_eq(_ui.asked.size(), 1, "the player is asked before anything arrives")
	assert_true(_client_assets().has(Tw.SPIRE))
	# The same state is not announced twice.
	_host.announce_document(host_doc)
	assert_eq(_wire.log.count("hint"), 1)


func test_a_later_edit_adds_assets_through_the_same_path_and_merges_into_the_partial() -> void:
	var doc := Tw.map_using_spire()
	await _fetch(doc)
	assert_false(_client_assets().has(Tw.SHARD))
	# The host's table now also uses the shard.
	var grown := Tw.map_using_spire()
	grown.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	_host.usage = LibraryTransfer.usage_of([grown])
	var again := await _fetch(grown)
	assert_eq(again["installed"], ["alienworld"])
	assert_eq(again["results"][0]["library"], "alienworld")
	assert_true(_client_assets().has(Tw.SHARD))
	assert_true(_client_assets().has(Tw.SPIRE), "what came first stays")
	assert_eq(_ui.asked.size(), 1, "the same collection is not asked about twice")


func test_client_ops_wait_while_a_library_transfer_runs() -> void:
	assert_false(_client.is_busy())
	var box := {"out": null}
	var runner := func() -> void:
		box["out"] = await _client.fetch_for_document(Tw.map_using_spire())
	runner.call()
	assert_true(_client.is_busy(), "busy from the first await on")
	var guard := 0
	while box["out"] == null and guard < 300:
		_wire.flush()
		await get_tree().process_frame
		guard += 1
	assert_false(_client.is_busy())


# ---- the end of the session ----


func test_the_session_ending_keeps_what_was_downloaded() -> void:
	await _fetch(Tw.map_using_spire())
	assert_true(_client_assets().has(Tw.SPIRE))
	_client.end_session()
	assert_true(DirAccess.dir_exists_absolute(_received().path_join("alienworld")), "kept")
	assert_true(_client_assets().has(Tw.SPIRE), "still served")
	assert_eq(LibraryRegistry.info("alienworld", _paths["base"])["source"], "user")


func test_a_collection_downloaded_once_is_served_in_the_next_session_without_the_host() -> void:
	await _fetch(Tw.map_using_spire())
	_client.end_session()
	# A new process: nothing in memory, no host reachable. The map's plan needs nothing.
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.apply(_paths["base"])
	var alone := _channel(false)
	alone.ui = _ui
	var asked_before := _ui.asked.size()
	var out: Dictionary = await _run(
		func() -> Dictionary: return await alone.fetch_for_document(Tw.map_using_spire())
	)
	assert_eq(out["plan"]["requests"], [])
	assert_eq(_ui.asked.size(), asked_before, "nothing is asked of anyone")
	assert_true(_client_assets().has(Tw.SPIRE))


# ---- ask once, and what is missing ----


func test_a_second_request_for_the_same_collection_downloads_only_the_delta_without_asking(
) -> void:
	await _fetch(Tw.map_using_spire())
	assert_eq(_ui.asked.size(), 1)
	var grown := Tw.map_using_spire()
	grown.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	_host.usage = LibraryTransfer.usage_of([grown])
	var again := await _fetch(grown)
	assert_eq(again["installed"], ["alienworld"])
	assert_eq(_ui.asked.size(), 1, "the player agreed to this collection already")
	assert_eq(again["results"][0]["phase"], LibraryTransferConsent.Phase.DONE)
	var request: Dictionary = (_host._host_requests[CLIENT] as Dictionary).values().back()
	assert_eq(request["assets"], [Tw.SHARD], "only what was missing was asked for")
	assert_true(_client_assets().has(Tw.SHARD) and _client_assets().has(Tw.SPIRE))
	assert_eq(LibraryFromHost.record_of("alienworld")["assets"].size(), 2)
	assert_eq(_ui.notices.size(), 2, "told each time what arrived")


func test_a_delta_over_the_threshold_asks_again() -> void:
	await _fetch(Tw.map_using_spire())
	LibraryFromHost.auto_delta_limit = 1
	var grown := Tw.map_using_spire()
	grown.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	_host.usage = LibraryTransfer.usage_of([grown])
	var again := await _fetch(grown)
	assert_eq(again["installed"], ["alienworld"])
	assert_eq(_ui.asked.size(), 2, "a big delta is asked about again")
	assert_string_contains(_ui.asked[1], "needs 1 item more from the collection Alien World")


func test_a_skip_is_remembered_for_the_session_and_asked_again_in_the_next() -> void:
	_ui.answer = false
	var first := await _fetch(Tw.map_using_spire())
	assert_eq(first["skipped"], ["alienworld"])
	assert_eq(_ui.asked.size(), 1)
	var second := await _fetch(Tw.map_using_spire())
	assert_eq(second["skipped"], ["alienworld"])
	assert_eq(_ui.asked.size(), 1, "not asked twice in a session")
	assert_eq(_ui.notices, [], "and quiet")
	_client.end_session()
	_ui.answer = true
	var third := await _fetch(Tw.map_using_spire())
	assert_eq(third["installed"], ["alienworld"])
	assert_eq(_ui.asked.size(), 2, "a new session asks again")


func test_a_changed_host_copy_is_asked_about_and_replaces_the_kept_one() -> void:
	await _fetch(Tw.map_using_spire())
	var grown := Tw.map_using_spire()
	grown.scatter[Tw.SHARD] = PackedFloat32Array([0, 0, 0, 0, 0, 0, 1, 1, 1, 1])
	_host.usage = LibraryTransfer.usage_of([grown])
	# The host's library is another build now (its source hash is not the one the kept copy has).
	_served["alienworld"]["hash"] = "changed1"
	var again := await _fetch(grown)
	assert_eq(again["installed"], ["alienworld"])
	assert_eq(_ui.asked.size(), 2, "another source hash is another question")
	assert_string_contains(_ui.asked[1], "The host uses the collection Alien World")
	assert_eq(LibraryFromHost.record_of("alienworld")["source_hash"], "changed1")
	assert_true(
		_client_assets().has(Tw.SPIRE) and _client_assets().has(Tw.SHARD), "the whole request"
	)
	var request: Dictionary = (_host._host_requests[CLIENT] as Dictionary).values().back()
	assert_gt(request["assets"].size(), 1, "the full request was sent again, not a delta")


func test_the_players_own_copy_is_never_asked_over() -> void:
	World.write_alien(_client_user.path_join("alienworld"))
	LibraryRegistry.apply(_paths["base"])
	var out := await _fetch(Tw.map_using_spire())
	assert_eq(out["plan"]["requests"], [])
	assert_eq(_ui.asked, [])
	assert_eq(_wire.log, [])
	assert_true(LibraryFromHost.record_of("alienworld").is_empty())
