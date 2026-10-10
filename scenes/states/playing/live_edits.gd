class_name LiveEdits
extends Node

## A table's live map edits (v0.2: the GM's terrain events during play, such as a bridge
## collapsing, a forest falling, fire, or a biome or terrain change with the authoring
## brushes). One per table set out from a map document, on every peer: LevelPlayController
## makes it once the map is installed and frees it with the map. It holds a play-side
## AuthoringEditor (no UI) over the peer's own copy of the map and document.
##
## The GM's side (the host, or solo play): the brushes run on `editor`, which records into
## `history`. Every entry recorded, undone or redone becomes one op (LiveEditCodec.op_of: its
## after side, or its before side for an undo) once the editor's height work has drained, in
## the order they happened; each is appended to `op_log` and broadcast. A client's side: ops
## arrive through NetworkGameSync, are checked against its own document and applied in order
## through a LiveEditCodec.Queue stepped once a frame. Clients never send edits.
##
## Catching up. A client's service asks the host for the log as soon as it exists; the host
## answers with a header (its table key, the op count) and every op so far, and the ops it
## broadcasts later follow on the same reliable channel. A service takes ops only of the table
## whose header it has, and only in index order: ops that came before the header, or twice, are
## dropped, and the log fills every gap. When the catch-up's last op is in, the queue applies
## it all at once (Queue.drain), before the full state a late joiner gets behind it
## (LateJoinerSync), so its tokens land on the edited ground. A host whose service starts after
## a client's (a client that loaded first) announces its header to every client.
##
## The log is plain bytes, one PackedByteArray an op, so a session file can keep it as the
## table's events. Live edits change this session's copy of the map, never the map file. A
## refused op stops the table taking more (`problem`): the map is out of step from there, and
## a hostile host cannot make a client print engine errors for every op.

## The GM's side logged op `index` (and broadcast it when hosting).
signal op_logged(index: int, bytes: PackedByteArray)
## A client's catch-up is applied: `count` ops of the log.
signal caught_up(count: int)
## An op was refused; the table takes no more (see `problem`).
signal refused(why: String)

## Why a map built without a document takes no live edits (refusal()).
const NO_DOCUMENT := (
	"This map was made in Blender and has no map document, so it cannot change during play."
	+ " Open it in the map editor and save it once to give it one."
)

## The play-side editor over the map; the GM's side runs the brushes on it.
var editor: AuthoringEditor = null
## The GM's side's history (undo and redo of live edits); a client's stays empty.
var history: AuthoringHistory = null
## Every op of this table so far, in order (the GM's side's, or as a client received them).
var op_log: Array[PackedByteArray] = []
## The table this log belongs to: the GM's side draws it; a client takes the host's header's.
var table_key: int = 0
## True on the GM's side (the host, or solo play); false on a client.
var sends: bool = true
## Why the table stopped taking ops (a refused op), or "".
var problem: String = ""
## The table's terrain events (a bridge collapsing, a forest falling): their motion on this
## board, and on the GM's side the edit each ends in (TerrainEvents, a child).
var events: TerrainEvents = null

## The GM's side: {"entry", "undo"} recorded but not yet sent, in order.
var _pending: Array[Dictionary] = []
## A client's queue of checked ops.
var _queue: LiveEditCodec.Queue = null
## A client's catch-up: the log length its header promised until it is in, else -1.
var _catch_up: int = -1


## Why `doc`'s map takes no live edits, or "" when it does.
static func refusal(doc: MapDocument) -> String:
	return NO_DOCUMENT if doc == null else ""


## The live edits of map `root`, built from `doc` (the loaded copy the table plays on): the
## GM's side with `gm_side` (the host, or solo play), else a client's. Add it to the tree to
## start it. The GM's side starts from `replay` when it is given: the ops this session made
## to the map before it left the table (TableStates), applied at once and kept as the log, so
## the tokens that follow land on the edited ground and every client catches up on them.
static func create(
	root: Node3D, doc: MapDocument, gm_side: bool, replay: Array[PackedByteArray] = []
) -> LiveEdits:
	var service := LiveEdits.new()
	service.name = "LiveEdits"
	service.sends = gm_side
	service.history = AuthoringHistory.new()
	var scatter := root.get_node_or_null(NodePath(MapSourceLoader.SCATTER_NODE)) as AuthoredScatter
	if scatter != null:
		scatter.attach_document(doc)
	service.editor = AuthoringEditor.create(doc, root, service.history)
	# Water edits compute on a worker, as the Water tool's do, so none freezes a frame.
	service.editor.water.use_worker = true
	if service.sends:
		# Before the history is watched: a replayed op is the session's past, not a new edit.
		service._replay(replay)
		service.table_key = randi() | 1
		service.history.recorded.connect(service._on_recorded)
		service.history.undone.connect(service._on_undone)
		service.history.redone.connect(service._on_recorded)
	else:
		service._queue = LiveEditCodec.Queue.new(service.editor)
	service.events = TerrainEvents.new()
	service.events.setup(service)
	service.add_child(service.events)
	return service


func _ready() -> void:
	var game_sync := NetworkManager.game_sync
	if sends:
		game_sync.live_edit_log_requested.connect(send_log_to)
		# A client that loaded first asked before this existed: tell every client the table.
		game_sync.send_live_edit_log(0, table_key, op_log)
	else:
		game_sync.live_edit_received.connect(receive_op)
		game_sync.live_edit_log_received.connect(receive_log)
		game_sync.request_live_edit_log()


func _exit_tree() -> void:
	var game_sync := NetworkManager.game_sync
	for connection in [
		[game_sync.live_edit_log_requested, send_log_to],
		[game_sync.live_edit_received, receive_op],
		[game_sync.live_edit_log_received, receive_log],
	]:
		if (connection[0] as Signal).is_connected(connection[1]):
			(connection[0] as Signal).disconnect(connection[1])


func _process(_delta: float) -> void:
	if sends:
		editor.step_height_work()
		_send_pending()
	elif _queue != null:
		_queue.step()


## True when nothing is left to do: every recorded entry sent (the GM's side) or every
## received op applied (a client), and the editor's height work done.
func is_settled() -> bool:
	if sends:
		return _pending.is_empty() and not editor.has_height_work()
	return _queue.is_idle()


# =============================================================================
# THE GM'S SIDE
# =============================================================================


## Sends `peer_id` (0: every client) this table's header and log (the host's answer to a
## client's request, NetworkGameSync.live_edit_log_requested).
func send_log_to(peer_id: int) -> void:
	if sends:
		NetworkManager.game_sync.send_live_edit_log(peer_id, table_key, op_log)


## Every entry recorded, undone or redone so far, as ops now: the editor's height work is
## finished first (a sculpt's record is complete only once its kept rocks have landed). The
## frame loop does this by itself once the work has drained; this is for a caller that needs
## the log at once.
func send_now() -> void:
	if sends and not editor.is_stroking():
		editor.finish_height_work()
		_send_pending()


## Applies `ops` in order, each through a LiveEditCodec.Queue over the editor with its height
## work finished, and keeps the ones applied as the log. A refused op stops it there (`problem`
## says why): the ops after it were made on ground this one would have left.
func _replay(ops: Array[PackedByteArray]) -> void:
	var queue := LiveEditCodec.Queue.new(editor)
	for bytes in ops:
		var why := queue.push(bytes)
		if why != "":
			problem = why
			push_warning("LiveEdits: a kept op was refused, the map is restored up to it: " + why)
			return
		queue.drain()
		op_log.append(bytes)


func _on_recorded(entry: Dictionary) -> void:
	_pending.append({"entry": entry, "undo": false})


func _on_undone(entry: Dictionary) -> void:
	_pending.append({"entry": entry, "undo": true})


## The pending entries as ops, in order, once the editor has no height work left and no
## stroke under way (op_of would otherwise finish that work at once, the hitch the spread
## avoids).
func _send_pending() -> void:
	if _pending.is_empty() or editor.has_height_work() or editor.is_stroking():
		return
	var items := _pending.duplicate()
	_pending.clear()
	for item: Dictionary in items:
		var op := LiveEditCodec.op_of(item.entry, editor, item.undo)
		if op.is_empty():
			continue
		var bytes := LiveEditCodec.encode(op)
		op_log.append(bytes)
		op_logged.emit(op_log.size() - 1, bytes)
		if NetworkManager.is_host():
			NetworkManager.game_sync.broadcast_live_edit(table_key, op_log.size() - 1, bytes)


# =============================================================================
# A CLIENT'S SIDE
# =============================================================================


## The host's log header (NetworkGameSync.live_edit_log_received): the first one sets the table
## and how many ops the catch-up holds; any later one (another table's, or a second answer) is
## ignored.
func receive_log(key: int, count: int) -> void:
	if sends or table_key != 0 or key == 0:
		return
	table_key = key
	_catch_up = count if count > op_log.size() else -1
	if _catch_up < 0:
		caught_up.emit(op_log.size())


## One op from the host (NetworkGameSync.live_edit_received): queued when it is this table's
## next one, else dropped (another table's, before the header, twice, or past a gap).
func receive_op(key: int, index: int, bytes: PackedByteArray) -> void:
	if sends or problem != "" or table_key == 0 or key != table_key:
		return
	if index != op_log.size():
		return
	var why := _queue.push(bytes)
	if why != "":
		problem = why
		push_warning("LiveEdits: op %d refused, the map is out of step from here: %s" % [index, why])
		refused.emit(why)
		return
	op_log.append(bytes)
	if op_log.size() == _catch_up:
		_catch_up = -1
		_queue.drain()
		caught_up.emit(op_log.size())
