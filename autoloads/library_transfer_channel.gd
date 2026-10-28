class_name LibraryTransferChannel
extends Node

## The network half of multiplayer library transfer (LibraryTransfer holds the rules, see
## docs/systems/library.md "Multiplayer"). A sub-component of AssetManager
## (AssetManager.library_transfer; RPCs live at /root/AssetManager/LibraryTransfer on every peer).
##
## Protocol (LibraryPartial.PROTOCOL 1; every peer runs the host's game version, the same-version
## gate, so a peer without this node never joins, and a reply with another protocol number is
## refused with a message):
##   1. client -> host `_rpc_library_quote(request_id, request)`: the library, the version and hash
##      the map names, the used asset, biome and surface ids and the libraries the client has.
##   2. host -> client `_rpc_library_quote_reply(request_id, reply)`: what it would send (names,
##      versions, authors, asset counts, bytes) or why not. The host only answers for ids that a
##      map it serves uses (the table's live document and the shelf maps), never an arbitrary
##      library file.
##   3. the client asks the player (LibraryTransferConsent / LibraryTransferUi), once per
##      collection and source hash (a collection kept from this host extends without a question
##      while the delta is small; a Skip lasts the session); on Download it requests the pack
##      `_library_parts`, asset id = the request number, from AssetStreamer: the same chunked,
##      windowed, resumable, cancellable stream as a map file. The host builds the bundle at that
##      moment (host_bundle) from the request it quoted. A copy kept from this host is asked for
##      what it lacks only (a delta); when the quote shows the host's copy changed, the whole
##      request is sent again.
##   4. the bytes come back as AssetStreamer.library_bundle_received and go through
##      LibraryTransfer.verify_and_install into the user's libraries (marked from host, merged
##      into a kept copy); then the libraries are served.
## A host that puts a new library into the table's map mid-session announces it
## (announce_document -> `_rpc_library_hint`), and a client runs the same request path for it.
## fetch_for_document() is what a map load calls (MapLibraryGate.run's `fetch`).

## Emitted when the last running transfer ends.
signal idle

const NODE_NAME := "LibraryTransfer"
const MAX_PENDING_PER_PEER := 8

## How long a client waits for the host's quote before it gives up, in seconds.
var quote_timeout_s: float = 15.0
## The most a client will download for one request, in bytes of the bundle (a quote over it is
## refused without a question).
var size_cap_bytes: int = LibraryTransfer.MAX_REQUEST_BYTES
## func() -> Array of MapDocument: the maps the host is playing in memory (LiveEdits sets it).
var documents_provider: Callable = Callable()
## The dialogs (LibraryTransferUi); a test sets its own object with the same methods.
var ui: Object = null
## AssetStreamer; set by tests, else AssetManager.streamer.
var streamer: Node = null
## LibraryRegistry.served() stand-in for tests; null reads the registry.
var served_override: Variant = null

## Host: peer id -> {request id -> request} the host quoted and may build.
var _host_requests: Dictionary = {}
## Host: shelf map file -> {stamp (modified time), usage}, so a file is parsed once per change.
var _usage_cache: Dictionary = {}
## Host: library id -> a signature of what was announced, so a hint goes out only on a change.
var _announced: Dictionary = {}
## Client: request id -> the host's reply, bundle bytes, failure text, progress 0..1, cancelled.
var _quotes: Dictionary = {}
var _bundles: Dictionary = {}
var _failures: Dictionary = {}
var _progress: Dictionary = {}
var _cancelled: Dictionary = {}
## Client: "<library id>|<source hash>" -> true for what the player skipped this session.
var _skipped: Dictionary = {}
var _next_id: int = 1
var _busy: int = 0
var _connected: bool = false


func _ready() -> void:
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_connect_session.call_deferred()


func _connect_session() -> void:
	if (
		is_instance_valid(NetworkManager)
		and not NetworkManager.connection_state_changed.is_connected(_on_connection_state_changed)
	):
		NetworkManager.connection_state_changed.connect(_on_connection_state_changed)


## The session ended: the channel forgets its requests and the Skips (what was downloaded stays
## on this computer, a collection like any other, until the player removes it).
func _on_connection_state_changed(
	_old_state: NetworkManager.ConnectionState, new_state: NetworkManager.ConnectionState
) -> void:
	if new_state != NetworkManager.ConnectionState.OFFLINE:
		return
	end_session()


## Forgets the session's requests and Skips.
func end_session() -> void:
	_host_requests.clear()
	_announced.clear()
	_skipped.clear()
	_quotes.clear()
	_bundles.clear()
	_failures.clear()
	_progress.clear()
	_cancelled.clear()


func is_busy() -> bool:
	return _busy > 0


# =============================================================================
# HOST
# =============================================================================

@rpc("any_peer", "reliable")
func _rpc_library_quote(request_id: int, request: Dictionary) -> void:
	if not _is_host():
		return
	await answer_quote(multiplayer.get_remote_sender_id(), request_id, request)


## Host: decides a peer's quote request and sends the reply. A request the host will serve is
## remembered (by peer and request id) for host_bundle().
func answer_quote(peer_id: int, request_id: int, request: Dictionary) -> void:
	var reply := await decide(peer_id, request_id, request)
	_send_quote_reply(peer_id, request_id, reply)


## The reply for a quote request: LibraryTransfer.quote's, or a refusal that says why.
func decide(peer_id: int, request_id: int, request: Dictionary) -> Dictionary:
	var problem := LibraryPartial.request_problem(request)
	if problem != "":
		return _refusal("request", problem)
	var usage := await _session_usage()
	var denied := LibraryTransfer.authorize(request, usage)
	if denied != "":
		return _refusal("not_used", denied)
	var reply := LibraryTransfer.quote(request, _served())
	if reply["ok"]:
		var pending: Dictionary = _host_requests.get(peer_id, {})
		while pending.size() >= MAX_PENDING_PER_PEER:
			pending.erase(pending.keys()[0])
		pending[request_id] = request
		_host_requests[peer_id] = pending
	return reply


## Host: the bundle for a request this peer was quoted, called by AssetStreamer when the peer
## asks for the stream. Empty when the peer has no such quote.
func host_bundle(peer_id: int, request_id_text: String) -> PackedByteArray:
	if not request_id_text.is_valid_int():
		return PackedByteArray()
	var request: Variant = _host_requests.get(peer_id, {}).get(int(request_id_text))
	if not request is Dictionary:
		return PackedByteArray()
	return LibraryTransfer.build_bundle(request, _served())


func _refusal(code: String, text: String) -> Dictionary:
	return {"ok": false, "protocol": LibraryPartial.PROTOCOL, "code": code, "error": text}


func _served() -> Dictionary:
	return served_override if served_override is Dictionary else LibraryRegistry.served()


func _is_host() -> bool:
	return NetworkManager.is_host()


func _is_client() -> bool:
	return NetworkManager.is_client()


func _send_quote_reply(peer_id: int, request_id: int, reply: Dictionary) -> void:
	rpc_id(peer_id, "_rpc_library_quote_reply", request_id, reply)


## What the maps being served use: the host's in-memory documents (the table's, with its live
## edits) and the shelf maps' files. Overridable in tests.
func _session_usage() -> Dictionary:
	var docs: Array = []
	if documents_provider.is_valid():
		docs.append_array(documents_provider.call())
	var usage := LibraryTransfer.usage_of(docs)
	for part: Dictionary in await _shelf_usage():
		LibraryTransfer.merge_usage(usage, part)
	return usage


## The usage of each shelf map's file, read on a worker and remembered by file and modified time
## (a peer asking again and again must not make the host parse a map each time).
func _shelf_usage() -> Array:
	var parts: Array = []
	for folder: Variant in NetworkManager.session.servable_folders():
		var path := Paths.get_level_map_document_path(str(folder))
		if not FileAccess.file_exists(path):
			continue
		var stamp := FileAccess.get_modified_time(path)
		var cached: Dictionary = _usage_cache.get(path, {})
		if cached.get("stamp") != stamp:
			var work := {}
			var task := WorkerThreadPool.add_task(
				func() -> void: work["document"] = MapDocumentIO.read(path)["document"],
				false,
				"LibraryTransferChannel authorize"
			)
			while not WorkerThreadPool.is_task_completed(task):
				await get_tree().process_frame
			WorkerThreadPool.wait_for_task_completion(task)
			cached = {"stamp": stamp, "usage": LibraryTransfer.usage_of([work.get("document")])}
			_usage_cache[path] = cached
		parts.append(cached["usage"])
	return parts


func _on_peer_disconnected(peer_id: int) -> void:
	_host_requests.erase(peer_id)


## Host: tells every client about the libraries `doc` uses, once for each change, so a client can
## fetch a library the host just started using before the edit arrives (LiveEdits calls this as
## it records an edit). A hint is a request without `have`.
func announce_document(doc: MapDocument) -> void:
	if doc == null or not _is_host():
		return
	var by_library := LibraryRegistry.assets_used_by(doc)
	for id in MapLibraries.used_ids(doc):
		if id == LibraryContracts.CORE_ID:
			continue
		var used: PackedStringArray = by_library.get(id, PackedStringArray())
		var refs: PackedStringArray = LibraryStructureStore.used_by(doc).get(
			id, PackedStringArray()
		)
		var signature := "%d:%d:%d" % [used.size(), doc.biome_ids.size(), refs.size()]
		if _announced.get(id) == signature:
			continue
		_announced[id] = signature
		var hint := LibraryTransfer.hint_of(doc, id)
		if not hint.is_empty():
			_send_hint(hint)


func _send_hint(hint: Dictionary) -> void:
	rpc("_rpc_library_hint", hint)


# =============================================================================
# CLIENT
# =============================================================================

@rpc("authority", "reliable")
func _rpc_library_quote_reply(request_id: int, reply: Dictionary) -> void:
	if _is_host():
		return
	_quotes[request_id] = reply


## Client: the host started using a library; fetch it through the ordinary request path.
@rpc("authority", "reliable")
func _rpc_library_hint(hint: Dictionary) -> void:
	if _is_host():
		return
	await handle_hint(hint)


func handle_hint(hint: Dictionary) -> Dictionary:
	var doc := LibraryTransfer.document_of_hint(hint)
	if doc == null:
		return {}
	return await fetch_for_document(doc)


## Client: asks the host for the libraries `doc` needs and this install lacks, one question and
## one download each, and serves what arrives. Returns {installed: [library ids], skipped: [ids
## the player said no to or that failed], results: [per request {library, phase, message}],
## plan}. Nothing is asked of a host or of the player when the plan has no request. A map load
## calls this before it checks its libraries (MapLibraryGate.run); the player's Skip and Cancel
## leave the existing "Open without those ..." choice.
func fetch_for_document(doc: MapDocument) -> Dictionary:
	var out := {
		"installed": [] as Array[String], "skipped": [] as Array[String], "results": [], "plan": {}
	}
	if doc == null or not _is_client():
		return out
	var plan := LibraryTransfer.plan(doc)
	out["plan"] = plan
	for request: Dictionary in plan["requests"]:
		_busy += 1
		var result := await _transfer(request)
		_busy -= 1
		(out["results"] as Array).append(result)
		if result["installed"]:
			(out["installed"] as Array).append_array(result["libraries"])
		else:
			(out["skipped"] as Array).append(String(request["library"]))
		if result["phase"] == LibraryTransferConsent.Phase.CANCELLED:
			break
	if _busy == 0:
		idle.emit()
	return out


## One request: quote, question, download, check, install.
func _transfer(request: Dictionary) -> Dictionary:
	var model := LibraryTransferConsent.new(size_cap_bytes)
	var result := {
		"library": request["library"],
		"phase": model.phase,
		"message": "",
		"installed": false,
		"libraries": [],
	}
	var screen := _ui()
	var kept := LibraryFromHost.record_of(String(request["library"]))
	var asked := await _ask_host(request)
	var reply: Dictionary = asked["reply"]
	if request.get("reason") == "more" and _host_copy_changed(reply, kept):
		# The host's copy is not the one the kept delta base came from: ask for the whole
		# request again; the answer replaces the kept copy.
		request = (request["full"] as Dictionary).duplicate(true)
		request["reason"] = "newer"
		asked = await _ask_host(request)
		reply = asked["reply"]
	var id := int(asked["id"])
	var main := LibraryTransferConsent.main_library(reply)
	var key := "%s|%s" % [request["library"], main.get("hash", "")]
	if reply.is_empty():
		model.fail("The host did not answer. Is it running the same version of the game?")
	elif int(reply.get("protocol", -1)) != LibraryPartial.PROTOCOL:
		model.fail(
			"The host speaks another library transfer version (%s)." % str(reply.get("protocol"))
		)
	elif _skipped.has(key):
		model.quote = reply
		model.skip_remembered()
	else:
		model.offer(reply, kept if not _host_copy_changed(reply, kept) else {})
	if model.phase == LibraryTransferConsent.Phase.ASKING:
		var download: bool = await screen.ask(model)
		model.answer(download)
		if not download:
			_skipped[key] = true
	var installed: Array = []
	if model.phase == LibraryTransferConsent.Phase.RECEIVING:
		installed = await _receive(id, request, model, screen)
	return _finish(model, result, screen, installed)


## Sends the quote request for `request` and waits for the answer: {id, reply} ({} on a timeout).
func _ask_host(request: Dictionary) -> Dictionary:
	var id := _next_id
	_next_id += 1
	var wire := request.duplicate(true)
	wire.erase("reason")
	wire.erase("full")
	_send_quote(id, wire)
	return {"id": id, "reply": await _await_quote(id)}


## True when the host's quote shows another version or source hash than the kept copy's.
func _host_copy_changed(reply: Dictionary, kept: Dictionary) -> bool:
	var main := LibraryTransferConsent.main_library(reply)
	if main.is_empty() or kept.is_empty():
		return false
	return (
		String(main.get("version", "")) != String(kept.get("version", ""))
		or String(main.get("hash", "")) != String(kept.get("source_hash", ""))
	)


## Downloads and installs the bundle of quote `id`; returns the library ids installed ([] on any
## failure, skip or cancel, with the model holding why).
func _receive(id: int, request: Dictionary, model: LibraryTransferConsent, screen: Object) -> Array:
	var installed: Array = []
	screen.begin_progress(model, func() -> void: _cancel(id))
	if not _cancelled.has(id):
		_request_bundle(id)
	var total := int(model.quote.get("bytes", 0))
	while not _bundles.has(id) and not _failures.has(id) and not _cancelled.has(id):
		var fraction: float = _progress.get(id, 0.0)
		model.progress(int(fraction * total), total)
		screen.set_progress(model, fraction)
		await get_tree().process_frame
	if _cancelled.has(id):
		model.cancel()
	elif _failures.has(id):
		model.fail("The download failed: %s" % _failures[id])
	else:
		model.installing()
		screen.set_progress(model, 1.0)
		var made := (
			LibraryTransfer
			. verify_and_install(
				_bundles[id],
				{
					"library": request["library"],
					"wanted_version": request["version"],
					"host": _host_label(),
				}
			)
		)
		if made["ok"]:
			model.done()
			installed = made["libraries"]
			_installed(made)
		else:
			model.fail(LibraryTransferConsent.error_text(made["errors"]))
	_bundles.erase(id)
	_progress.erase(id)
	_failures.erase(id)
	_cancelled.erase(id)
	screen.end_progress()
	return installed


## The collections are on disk: serve them (and let the registry forget any that were evicted to
## make room).
func _installed(_made: Dictionary) -> void:
	_reapply()


## What the record of a collection says about where it came from: the host's player name.
func _host_label() -> String:
	var host: Dictionary = NetworkManager.get_players().get(1, {})
	var label := String(host.get("name", ""))
	return label if label != "" else "the host"


func _finish(
	model: LibraryTransferConsent, result: Dictionary, screen: Object, installed: Array
) -> Dictionary:
	result["phase"] = model.phase
	result["message"] = model.message
	result["installed"] = model.installed()
	result["libraries"] = installed
	var quiet := model.phase == LibraryTransferConsent.Phase.SKIPPED
	if not quiet and model.message != "":
		screen.notify(model.message)
	return result


func _cancel(id: int) -> void:
	_cancelled[id] = true
	_streamer().cancel_download(_key(id))


func _key(id: int) -> String:
	return "%s/%d/bundle/bundle" % [Paths.LIBRARY_PARTS_PACK_ID, id]


func _send_quote(id: int, request: Dictionary) -> void:
	rpc_id(1, "_rpc_library_quote", id, request)


func _request_bundle(id: int) -> void:
	_connect_streamer()
	_streamer().request_from_host(Paths.LIBRARY_PARTS_PACK_ID, str(id), "bundle", "bundle")


## Waits for the host's reply to quote `id`, up to quote_timeout_s; {} on a timeout.
func _await_quote(id: int) -> Dictionary:
	var deadline := Time.get_ticks_msec() + int(quote_timeout_s * 1000.0)
	while not _quotes.has(id):
		if Time.get_ticks_msec() >= deadline:
			return {}
		await get_tree().process_frame
	var reply: Dictionary = _quotes[id]
	_quotes.erase(id)
	return reply


func _ui() -> Object:
	if ui == null:
		ui = LibraryTransferUi.new()
	return ui


func _streamer() -> Node:
	return streamer if streamer != null else AssetManager.streamer


func _connect_streamer() -> void:
	if _connected:
		return
	var source := _streamer()
	source.library_bundle_received.connect(_on_bundle_received)
	source.asset_failed.connect(_on_asset_failed)
	source.transfer_progress.connect(_on_transfer_progress)
	_connected = true


func _on_bundle_received(request_id: String, data: PackedByteArray) -> void:
	if request_id.is_valid_int():
		_bundles[int(request_id)] = data


## AssetStreamer's trailing file_type argument is part of the signal (a handler with fewer
## parameters is never called).
func _on_asset_failed(
	pack_id: String, asset_id: String, _variant_id: String, error: String, _file_type := ""
) -> void:
	if pack_id == Paths.LIBRARY_PARTS_PACK_ID and asset_id.is_valid_int():
		_failures[int(asset_id)] = error


func _on_transfer_progress(
	pack_id: String, asset_id: String, _variant_id: String, progress: float, _file_type := ""
) -> void:
	if pack_id == Paths.LIBRARY_PARTS_PACK_ID and asset_id.is_valid_int():
		_progress[int(asset_id)] = progress


## Serves the libraries again (the received ones appear or go), without announcing a rebuild: the
## map being loaded is not built yet.
func _reapply() -> void:
	FoliageLibrary.apply()
