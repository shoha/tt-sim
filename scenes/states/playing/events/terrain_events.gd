class_name TerrainEvents
extends Node

## A table's terrain events (TerrainEvent: a bridge collapsing, a forest falling): the motion
## every board plays, and on the GM's side the map change it ends in. One per LiveEdits, on
## every peer (its child, made by LiveEdits.create, freed with it).
##
## The GM's side (the host, or solo play): start() checks the event can play on this map
## (refusal_for), stamps it with the table's key and the host's lead, broadcasts it
## (NetworkGameSync.broadcast_terrain_event, behind any op still queued) and plays it after
## the lead. Once it has played, the map change is made on the live editor as one ordinary
## history entry, labelled for the event ("Bridge collapse", "Forest fall"; the entry carries
## "preset": its kind, for PlayEvents' toast): the crossing removed, or a Clear over the area
## reaching CLEAR_REACH times the radius (the Clear's falloff is soft at its rim, so the trees
## that fell are well inside it). LiveEdits turns that entry into an op like any edit, so every
## client gets it after the motion, a late joiner gets only the op, and an undo restores the
## map without replaying anything.
##
## A client's side: an event from the host (NetworkGameSync.terrain_event_received) is decoded
## (TerrainEvent.decode refuses anything out of bounds), taken only for this table and only
## while the table takes ops, and played at once; the op follows on its own.
##
## The effects (BridgeCollapse, ForestFall) live under the map root, stepped here by one clock
## (advance(), which a test can call to jump ahead). Each stays, drawing nothing, until its
## change has landed (the crossing node gone, the scatter rebuilt) or RELEASE_AFTER_S has
## passed, and then lets go of what it hid. At most MAX_ACTIVE play at once.

## The GM's side started an event: its wire bytes (tests hand them to a client's service).
signal started(bytes: PackedByteArray)
## An event's change was made on the GM's side (its history entry recorded).
signal applied(event: TerrainEvent)

const MAX_ACTIVE := 4
const LABELS := {
	TerrainEvent.Kind.BRIDGE_COLLAPSE: "Bridge collapse",
	TerrainEvent.Kind.FOREST_FALL: "Forest fall",
}
const CLEAR_REACH := 1.3
## Exposure of the Clear's one dab: at the fall's radius (0.77 of the dab's) it clears
## 1 - exp(-18 * 0.17 * 2) = 99.8 % of the density (MaskBrush CLEAR rate and falloff).
const CLEAR_SECONDS := 2.0
## An effect whose change has not landed this long after it played lets go anyway (the op was
## refused, or never sent).
const RELEASE_AFTER_S := 8.0
const BUSY := "Something is already happening there."
const TOO_MANY := "Let the last events finish first."
const NO_BRIDGE := "Click a bridge to drop it."
const NO_TREES := "No trees stand there. Click in a forest."
const NOT_GM := "Only the GM starts events."

## The live edits this belongs to (its parent).
var edits: LiveEdits = null

var _clock := 0.0
## {"event": TerrainEvent, "begin": clock time it starts, "node": effect or null, "owns_op":
## the GM's side makes its change, "applied": bool}
var _active: Array[Dictionary] = []
## The event whose change is being recorded now (labels the history entry), or null.
var _applying: TerrainEvent = null


## Wires a new service to `owner_edits` (LiveEdits.create, before anything else watches its
## history, so the label is set before any other listener reads the entry).
func setup(owner_edits: LiveEdits) -> void:
	name = "TerrainEvents"
	edits = owner_edits
	if edits.sends:
		edits.history.recorded.connect(_on_recorded)


func _ready() -> void:
	if edits != null and not edits.sends:
		NetworkManager.game_sync.terrain_event_received.connect(receive)


func _exit_tree() -> void:
	var game_sync := NetworkManager.game_sync
	if game_sync.terrain_event_received.is_connected(receive):
		game_sync.terrain_event_received.disconnect(receive)
	for entry in _active:
		_free_effect(entry)
	_active.clear()


func _process(delta: float) -> void:
	advance(delta)


## Why `event` cannot play on this map now, or "": too many under way, the bridge gone, not a
## bridge or already falling, or no tree standing in the circle.
func refusal_for(event: TerrainEvent) -> String:
	if _active.size() >= MAX_ACTIVE:
		return TOO_MANY
	var editor := edits.editor
	match event.kind:
		TerrainEvent.Kind.BRIDGE_COLLAPSE:
			var crossing := editor.document.crossing(event.crossing_id)
			if crossing == null or not crossing.is_deck():
				return NO_BRIDGE
			for entry in _active:
				var other: TerrainEvent = entry.event
				if other.kind == event.kind and other.crossing_id == event.crossing_id:
					return BUSY
		TerrainEvent.Kind.FOREST_FALL:
			for entry in _active:
				var other: TerrainEvent = entry.event
				var reach := other.radius_m + event.radius_m
				if other.kind == event.kind and other.centre.distance_to(event.centre) < reach * 0.5:
					return BUSY
			if ForestFall.trees_near(editor.scatter, event.centre, event.radius_m, 1).is_empty():
				return NO_TREES
	return ""


## The GM's side: starts `event` (see the header). Returns "" or why it cannot play.
func start(event: TerrainEvent) -> String:
	if edits == null or not edits.sends:
		return NOT_GM
	var why := refusal_for(event)
	if why != "":
		return why
	event.table_key = edits.table_key
	event.lead_s = TerrainEvent.LEAD_S if NetworkManager.is_host() else 0.0
	var bytes := event.encode()
	NetworkManager.game_sync.broadcast_terrain_event(bytes)
	started.emit(bytes)
	_active.append({"event": event, "begin": _clock + event.lead_s, "node": null, "owns_op": true})
	return ""


## A client's side: plays the host's event `bytes` when they are an event of this table that
## can play here (anything else is dropped without a word: a hostile host cannot make a client
## print errors).
func receive(bytes: PackedByteArray) -> void:
	if edits == null or edits.sends or edits.problem != "" or edits.table_key == 0:
		return
	var event := TerrainEvent.decode(bytes)
	if event == null or event.table_key != edits.table_key or refusal_for(event) != "":
		return
	_active.append({"event": event, "begin": _clock, "node": null, "owns_op": false})


## How many events are playing or waiting on their change.
func active_count() -> int:
	return _active.size()


## The effect nodes playing now (tests).
func effects() -> Array[Node3D]:
	var nodes: Array[Node3D] = []
	for entry in _active:
		if entry.node != null:
			nodes.append(entry.node)
	return nodes


## Advances every event `delta` seconds: starts those whose lead has passed, steps them, makes
## the GM's side's change once one has played, and frees each once its change has landed.
func advance(delta: float) -> void:
	_clock += delta
	for entry in _active.duplicate():
		var event: TerrainEvent = entry.event
		var elapsed: float = _clock - float(entry.begin)
		if elapsed < 0.0:
			continue
		if entry.node == null and not entry.get("failed", false):
			entry.node = _make_effect(event)
			entry.failed = entry.node == null
		var node: Node3D = entry.node
		if node != null:
			node.call(&"step", elapsed, delta)
		if elapsed >= event.duration_s and entry.owns_op and not entry.get("applied", false):
			if edits.editor.is_stroking():
				continue
			entry.applied = true
			_apply(event)
		var played: bool = node == null or node.call(&"is_played", elapsed)
		var landed: bool = node == null or node.call(&"is_removed")
		var waited := elapsed >= event.duration_s + RELEASE_AFTER_S
		var applied_or_client: bool = not entry.owns_op or entry.get("applied", false)
		if played and applied_or_client and (landed or waited):
			_free_effect(entry)
			_active.erase(entry)


func _make_effect(event: TerrainEvent) -> Node3D:
	var editor := edits.editor
	if not is_instance_valid(editor.map_root):
		return null
	var node: Node3D = null
	match event.kind:
		TerrainEvent.Kind.BRIDGE_COLLAPSE:
			node = BridgeCollapse.new()
		TerrainEvent.Kind.FOREST_FALL:
			node = ForestFall.new()
	editor.map_root.add_child(node)
	if not node.call(&"setup", editor, event):
		node.queue_free()
		return null
	return node


func _free_effect(entry: Dictionary) -> void:
	var node: Node3D = entry.get("node")
	if node == null or not is_instance_valid(node):
		return
	node.call(&"release")
	node.queue_free()
	entry.node = null


## Makes `event`'s change on the live editor as one history entry (see the header).
func _apply(event: TerrainEvent) -> void:
	var editor := edits.editor
	_applying = event
	match event.kind:
		TerrainEvent.Kind.BRIDGE_COLLAPSE:
			editor.crossings.remove(event.crossing_id)
		TerrainEvent.Kind.FOREST_FALL:
			var at := editor.to_world(Vector3(event.centre.x, 0.0, event.centre.y))
			if editor.begin_stroke(MaskBrush.CLEAR):
				var radius := event.radius_m * CLEAR_REACH * editor.map_scale()
				editor.stroke_dab(at, at, radius, CLEAR_SECONDS)
				editor.end_stroke()
	_applying = null
	applied.emit(event)


func _on_recorded(entry: Dictionary) -> void:
	if _applying == null:
		return
	entry["label"] = LABELS[_applying.kind]
	entry["preset"] = _applying.kind
