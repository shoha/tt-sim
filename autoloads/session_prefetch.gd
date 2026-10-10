class_name SessionPrefetch
extends Node

## Session sub-component: every client fetches the shelf maps it lacks in the background,
## while it waits in the room or plays at a table, so a map is already here when the GM sets
## it out, and the room shows each player's real progress instead of have / don't have.
##
## The order (order()): the map on the table first, then the GM's selected shelf map
## (SessionChannel.get_selected()), then the shelf's own order. A client fetches one map at a
## time, every missing file of it at once (map.glb and map.ttmap, SessionChannel's
## missing_variants()), through AssetStreamer as prefetch requests, so both headers arrive
## together and the map's progress is by bytes (map_percent()). A finished map lands in the
## download cache, where the table's load finds it (LevelPlayLoader._resolve_map_sources) with
## no second transfer, and the client reports its holdings at once. A map that leaves the
## shelf is cancelled (its downloads dropped, the host told to stop); a map whose fetch fails
## is not tried again this session (the table's load tries it again).
##
## Bandwidth: a prefetch never holds the table up. It takes none of the client's concurrent
## download slots, and the host serves every table transfer (a token asset, a file of the map
## on the table) before any prefetch (AssetStreamer.is_prefetch_transfer, at every send), so a
## prefetch yields to the table and resumes after; a prefetch of the map just set out becomes a
## table transfer in place, and the table's load takes it over rather than asking again.
##
## Progress: each client reports {ref key: percent} for the maps it is getting, 0 for one that
## waits (behind another map, or for its turn at the host), at most every REPORT_S and only
## when it changed. The host keeps the reports by session id, only for shelf maps
## (note_progress()), and sends every client the whole map on each change; it also rides in the
## session summary. progress_changed fires on every peer. A map held is in the holdings, not
## here.
##
## A child of SessionChannel (NetworkManager.session.prefetch); its RPCs live at
## /root/NetworkManager/Session/Prefetch on every peer.

## Emitted on every peer when a player's progress changed.
signal progress_changed

## How often a client may report its progress, in seconds.
const REPORT_S := 0.25
## The most a map in progress reports; 100 is a map held, which the holdings say.
const MAX_PERCENT := 99

## The AssetStreamer the client fetches through (AssetManager.streamer); tests set a double.
var streamer: Node = null

## Host and clients: session id -> {ref key: percent} (clients keep the host's copy)
var _progress: Dictionary = {}

## Client: the ref key of the map being fetched, its folder, and its files: variant id ->
## {"size": bytes once known, "done": bool}
var _current := ""
var _folder := ""
var _files: Dictionary = {}
## Client: the keys of the maps waiting behind it, reported at 0
var _queued: Array = []
## Client: ref keys whose fetch failed this session
var _failed: Dictionary = {}
## Client: the last report sent, and when the next may go
var _sent: Dictionary = {}
var _report_due_ms := 0
var _refresh_queued := false
var _watching := false


func _ready() -> void:
	var session := get_parent() as SessionChannel
	if session:
		session.session_changed.connect(queue_refresh)
		session.room_opened.connect(queue_refresh)


func _process(_delta: float) -> void:
	if _current != "" and _now_ms() >= _report_due_ms:
		_report()


# =============================================================================
# READ (host and clients)
# =============================================================================


## session id -> {ref key: percent} for the maps each player is getting (a copy).
func get_progress() -> Dictionary:
	return _progress.duplicate(true)


## The ref key of the map this client is fetching, or "".
func current_key() -> String:
	return _current


## Client: the host's progress as a summary carried it (already sanitized).
func set_progress(progress: Dictionary) -> void:
	_progress = progress.duplicate(true)


# =============================================================================
# CLIENT
# =============================================================================


## Bring the fetch in line with the session once this frame's messages are in (several
## summaries often arrive together).
func queue_refresh() -> void:
	if _refresh_queued:
		return
	_refresh_queued = true
	_refresh.call_deferred()


func _refresh() -> void:
	_refresh_queued = false
	var session := get_parent() as SessionChannel
	if session == null or not _is_client():
		return
	step(session.get_shelf(), session.get_table(), session.get_selected())


## Client: cancel the map being fetched when it left the shelf, then start the first map of
## order() that is missing here (unless one is under way) and report what waits behind it.
func step(shelf: Array, table: String, selected: String) -> void:
	var keys := shelf.map(func(ref: Dictionary) -> String: return SessionChannel.ref_key(ref))
	if _current != "" and not keys.has(_current):
		_cancel_current()
	var cached := _cached_file_fn()
	var queued: Array = []
	for ref: Dictionary in order(shelf, table, selected):
		var key := SessionChannel.ref_key(ref)
		if key == _current or _failed.has(key):
			continue
		var missing := SessionChannel.missing_variants(ref, cached)
		if missing.is_empty():
			continue
		if _current == "":
			_start(ref, missing)
		else:
			queued.append(key)
	_queued = queued
	_report(true)


func _start(ref: Dictionary, missing: Array) -> void:
	_watch()
	var key := SessionChannel.ref_key(ref)
	_current = key
	_folder = str(ref.get("folder", ""))
	_files = {}
	for variant: String in missing:
		_files[variant] = {"size": 0, "done": false}
	print("SessionPrefetch: fetching %s (%s)" % [key, ", ".join(missing)])
	for variant: String in missing:
		_get_streamer().request_map_file_from_host(_folder, variant, 50, true)
		# A request can fail at once (no connection, P2P off), which ends this fetch.
		if _current != key:
			return


## Stop fetching the current map: its prefetch downloads are dropped (never a download the
## table's load took over).
func _cancel_current() -> void:
	var source := _get_streamer()
	for variant: String in _files:
		var key := stream_key(_folder, variant)
		var status: Dictionary = source.get_download_status(key)
		if not _files[variant].done and bool(status.get("prefetch", false)):
			source.cancel_download(key)
	print("SessionPrefetch: stopped fetching %s" % _current)
	_clear_current()


func _clear_current() -> void:
	_current = ""
	_folder = ""
	_files = {}


func _watch() -> void:
	if _watching:
		return
	var source := _get_streamer()
	source.asset_received.connect(_on_received)
	source.asset_failed.connect(_on_failed)
	_watching = true


func _is_mine(pack_id: String, asset_id: String, variant_id: String) -> bool:
	return (
		_current != ""
		and pack_id == Paths.LEVEL_MAPS_PACK_ID
		and asset_id == _folder
		and _files.has(variant_id)
	)


## A file of the current map arrived (from this fetch or the table's load, the same file).
## Every listener takes AssetStreamer's trailing file_type.
func _on_received(
	pack_id: String, asset_id: String, variant_id: String, local_path: String, _file_type := ""
) -> void:
	if not _is_mine(pack_id, asset_id, variant_id):
		return
	var entry: Dictionary = _files[variant_id]
	entry.done = true
	if int(entry.size) <= 0:
		var file := FileAccess.open(local_path, FileAccess.READ)
		entry.size = file.get_length() if file else 0
	if _files.values().all(func(e: Dictionary) -> bool: return e.done):
		print("SessionPrefetch: %s is here" % _current)
		_clear_current()
		_note_held()
		_report(true)
		queue_refresh()


func _on_failed(
	pack_id: String, asset_id: String, variant_id: String, error: String, _file_type := ""
) -> void:
	if not _is_mine(pack_id, asset_id, variant_id):
		return
	push_warning(
		"SessionPrefetch: %s of %s failed (%s); it comes at the table" % [variant_id, _current, error]
	)
	_failed[_current] = true
	_files[variant_id].done = true
	_cancel_current()
	_report(true)
	queue_refresh()


## Tell the host what this client holds now. Separate so tests can see it.
func _note_held() -> void:
	var session := get_parent() as SessionChannel
	if session:
		session.report_holdings()


## Report {key: percent} for the map being fetched and 0 for each waiting behind it, when it
## changed and, unless `now`, no sooner than REPORT_S after the last.
func _report(now := false) -> void:
	var report := {}
	if _current != "":
		report[_current] = _percent()
	for key: String in _queued:
		report[key] = 0
	var ms := _now_ms()
	if report == _sent or (not now and ms < _report_due_ms):
		return
	_sent = report
	_report_due_ms = ms + int(REPORT_S * 1000.0)
	_send_report(report)


## The current map's percent here, by bytes across its files.
func _percent() -> int:
	var files: Array = []
	var source := _get_streamer()
	for variant: String in _files:
		var entry: Dictionary = _files[variant]
		var status: Dictionary = source.get_download_status(stream_key(_folder, variant))
		if int(status.get("original_size", 0)) > 0:
			entry.size = int(status.original_size)
		var total := int(status.get("total_chunks", 0))
		var fraction := 1.0
		if not entry.done:
			fraction = float(status.get("received_chunks", 0)) / total if total > 0 else 0.0
		files.append({"size": int(entry.size), "fraction": fraction})
	return map_percent(files)


## Send a report to the host. Separate so tests can capture it.
func _send_report(report: Dictionary) -> void:
	if _is_client():
		_rpc_report_progress.rpc_id(1, report)


func _is_client() -> bool:
	# Only a connected client fetches: GUT's offline peer is peer 1, the host itself.
	return (
		NetworkManager.is_client()
		and multiplayer.multiplayer_peer != null
		and multiplayer.get_unique_id() != 1
	)


func _get_streamer() -> Node:
	if streamer == null:
		streamer = AssetManager.streamer
	return streamer


func _cached_file_fn() -> Callable:
	var source := _get_streamer()
	return func(folder: String, variant: String, expected: String) -> String:
		return source.get_cached_map_file(folder, variant, expected) if source else ""


## Milliseconds clock for the report interval. Separate so tests can drive time.
func _now_ms() -> int:
	return Time.get_ticks_msec()


# =============================================================================
# HOST
# =============================================================================


## Host: record what `session_id` reports it is getting, keeping only maps in `shelf_keys`,
## and tell every client when that changed.
func note_progress(session_id: String, raw: Variant, shelf_keys: Array) -> void:
	var report := clean_report(raw)
	for key: String in report.keys():
		if not shelf_keys.has(key):
			report.erase(key)
	if _progress.get(session_id, {}) == report:
		return
	if report.is_empty():
		_progress.erase(session_id)
	else:
		_progress[session_id] = report
	_send_progress()


## Host: forget every player's progress on the map `key` (it left the shelf). The summary
## that follows carries the change.
func forget_map(key: String) -> void:
	for session_id: String in _progress.keys():
		var report: Dictionary = _progress[session_id]
		report.erase(key)
		if report.is_empty():
			_progress.erase(session_id)


## Host: forget the progress of a player who left.
func forget_player(session_id: String) -> void:
	if _progress.erase(session_id):
		_send_progress()


func _send_progress() -> void:
	if multiplayer.multiplayer_peer != null and NetworkManager.is_host():
		_rpc_progress.rpc(_progress)
	progress_changed.emit()


## Forget the session's progress and stop fetching (the session ended or this peer left).
func reset() -> void:
	_progress.clear()
	_clear_current()
	_queued = []
	_failed.clear()
	_sent = {}


# =============================================================================
# PURE
# =============================================================================


## The shelf (MapRefs) in fetch order: the map on the table (`table`), then the GM's
## selected map (`selected`), then the rest in shelf order. Keys not on the shelf are
## ignored. Pure.
static func order(shelf: Array, table: String, selected: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var taken: Array = []
	for wanted: String in [table, selected]:
		for ref: Dictionary in shelf:
			var key := SessionChannel.ref_key(ref)
			if wanted != "" and key == wanted and not taken.has(key):
				out.append(ref)
				taken.append(key)
	for ref: Dictionary in shelf:
		var key := SessionChannel.ref_key(ref)
		if not taken.has(key):
			out.append(ref)
			taken.append(key)
	return out


## A map's percent from its files, each {"size": bytes, "fraction": 0..1 of it here}: by
## bytes, 0 until every size is known, at most MAX_PERCENT. Pure.
static func map_percent(files: Array) -> int:
	var total := 0.0
	var here := 0.0
	for file: Dictionary in files:
		var size := float(file.get("size", 0))
		if size <= 0.0:
			return 0
		total += size
		here += size * clampf(float(file.get("fraction", 0.0)), 0.0, 1.0)
	if total <= 0.0:
		return 0
	return clampi(int(floor(100.0 * here / total)), 0, MAX_PERCENT)


## AssetStreamer's key for one map file of `folder` ("map" or "ttmap"). Pure.
static func stream_key(folder: String, variant: String) -> String:
	return (
		"%s/%s/%s/%s"
		% [Paths.LEVEL_MAPS_PACK_ID, folder, variant, Paths.get_level_map_file_type(variant)]
	)


## One player's report as the session may keep it: string keys (clipped, at most
## SessionChannel.MAX_SHELF), whole percents 0 to MAX_PERCENT. Pure.
static func clean_report(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for key: Variant in (raw as Dictionary).keys().slice(0, SessionChannel.MAX_SHELF):
		var value: Variant = raw[key]
		if key is String and (value is int or value is float):
			out[(key as String).left(SessionChannel.MAX_TEXT)] = clampi(int(value), 0, MAX_PERCENT)
	return out


## The host's progress as a client may keep it (untrusted): session id -> clean_report(),
## at most SessionChannel.MAX_SESSION_PLAYERS players, none empty. Pure.
static func sanitize_progress(raw: Variant) -> Dictionary:
	var out := {}
	if not raw is Dictionary:
		return out
	for id: Variant in (raw as Dictionary).keys().slice(0, SessionChannel.MAX_SESSION_PLAYERS):
		if not id is String:
			continue
		var report := clean_report(raw[id])
		if not report.is_empty():
			out[(id as String).left(SessionChannel.MAX_TEXT)] = report
	return out


# =============================================================================
# RPCS
# =============================================================================


## RPC: client -> host, the shelf maps the sender is getting (untrusted: kept under the
## sender's own session id, shelf maps only).
@rpc("any_peer", "reliable")
func _rpc_report_progress(raw: Variant) -> void:
	var session := get_parent() as SessionChannel
	if session == null or not NetworkManager.is_host():
		return
	var session_id := session.session_id_of(multiplayer.get_remote_sender_id())
	if session_id == "":
		return
	var keys := session.get_shelf().map(
		func(ref: Dictionary) -> String: return SessionChannel.ref_key(ref)
	)
	note_progress(session_id, raw, keys)


## RPC: host -> clients, every player's progress after a change.
@rpc("authority", "reliable")
func _rpc_progress(raw: Variant) -> void:
	if NetworkManager.is_host():
		return
	_progress = sanitize_progress(raw)
	progress_changed.emit()
