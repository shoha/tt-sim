extends RefCounted

## Render-job probe (`call` op) for the village-scale structure pass (card perf3, docs/systems/
## structure_performance.md "third round"). A village here is MapDocument.MAX_STRUCTURES (128)
## structures on a grid over a 97 m map: the 64 core recipes twice, each with a mix of ornaments
## (ivy, flower boxes, banners, vanes, awnings, signs), so decor, cloth, vanes and mills all stand.
## step.action:
##   fill {from, to}    lays lots from..to-1 through the editor (default 0..128), then flushes;
##                      logs the queue time on the main thread and the wait for the builds.
##   load {count}       builds a document of `count` lots as a load does (StructureGeometry.build,
##                      on workers) and then makes the nodes (AuthoredStructures.create): the two
##                      times are the worker phase and the main-thread phase of a load, and the
##                      longest frame the main-thread phase holds.
##   cap                times the 128th add, the refused 129th, one edit (a turn) and one removal,
##                      each as main-thread ms and as ms until the new node stands.
##   hitch_start {from, count, interval}  adds `count` lots from lot `from`, one every `interval`
##                      s, while recording every frame (wall clock between frames).
##   hitch_stop         logs the frames: count over 20 ms, worst, p95, and the per-add main ms.
##   consumers {n}      CPU microseconds per call of the per-frame consumers
##                      with everything standing:
##                      Wind.publish, every MillMotion and VaneMotion _process, and their counts.
##   profile            splits one add at the standing count into its parts (main-thread ms).
##   reset              removes every structure.

const SPAN_M := 88.0
const COLUMNS := 12
const MASKS: Array = [
	["ivy", "flower_boxes"],
	["banner", "vane"],
	["awning", "sign", "flower_boxes"],
	["ivy", "banner", "vane"],
	["flower_boxes", "awning"],
]
const HITCH := "Perf3Hitch"
const STAGED := "Perf4Staged"


## Records the frame times from a staged create until no structure is pending.
class StagedRecorder:
	extends Node
	var nodes: AuthoredStructures
	var create_ms := 0.0
	var frames := PackedFloat64Array()
	var done := false
	var total_ms := 0.0
	var _last_us := 0
	var _start_us := 0

	func begin() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = 97
		_start_us = Time.get_ticks_usec()
		_last_us = _start_us

	func _process(_delta: float) -> void:
		if done or not is_instance_valid(nodes):
			return
		var now := Time.get_ticks_usec()
		frames.append((now - _last_us) / 1000.0)
		_last_us = now
		if nodes.pending_count() == 0:
			done = true
			total_ms = (now - _start_us) / 1000.0


class Hitch:
	extends Node
	var base: Node
	var editor: AuthoringEditor
	var rows: Array
	var adder: Callable
	var from_lot := 0
	var count := 20
	var interval := 0.5
	var added := 0
	var since := 0.0
	var last_us := 0
	var frames := PackedFloat64Array()
	var add_ms := PackedFloat64Array()

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		process_priority = -97
		last_us = Time.get_ticks_usec()

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		frames.append((now - last_us) / 1000.0)
		last_us = now
		since += delta
		if added < count and since >= interval:
			since = 0.0
			var t0 := Time.get_ticks_usec()
			adder.call(editor, rows, from_lot + added)
			add_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
			added += 1


static func run(base: Node, step: Dictionary) -> String:
	var editor := _editor(base)
	if editor == null:
		return "no authoring editor"
	match String(step.get("action", "")):
		"fill":
			return _fill(base, editor, int(step.get("from", 0)), int(step.get("to", 128)))
		"load":
			return _load(editor, int(step.get("count", 128)))
		"load_staged":
			return _load_staged(base, editor, int(step.get("count", 128)))
		"load_staged_report":
			return _load_staged_report(base)
		"cap":
			return _cap(base, editor)
		"hitch_start":
			return _hitch_start(base, editor, step)
		"hitch_stop":
			return _hitch_stop(base)
		"profile":
			return _profile(base, editor)
		"consumers":
			return _consumers(base, int(step.get("n", 300)))
		"reset":
			return _reset(base, editor)
	return "unknown action %s" % step.get("action", "")


## The structure of lot `k`: recipe k of the served core library (cycling), a footprint fitted to
## its cell, a yaw from k and the ornament mask `k % 5`.
static func lot(rows: Array, k: int) -> Structure:
	var row: Dictionary = rows[k % rows.size()]
	var size: Array = row["default_size_m"]
	var spacing := SPAN_M / COLUMNS
	var at := Vector2(
		(float(k % COLUMNS) - (COLUMNS - 1) * 0.5) * spacing,
		(float(k / COLUMNS) - (COLUMNS - 1) * 0.5) * spacing
	)
	var fit := minf(1.0, (spacing - 1.5) / maxf(float(size[0]), float(size[1])))
	var plan := _rect(float(size[0]) * fit, float(size[1]) * fit, float((k * 37) % 360), at)
	var params := StructureOrnaments.with_kinds({}, MASKS[k % MASKS.size()])
	return Structure.make(0, String(row["ref"]), plan, 100 + k, params)


static func add_lot(editor: AuthoringEditor, rows: Array, k: int) -> int:
	return editor.structures.add(lot(rows, k))


static func _fill(base: Node, editor: AuthoringEditor, from: int, to: int) -> String:
	var rows := LibraryStructureStore.structures("core")
	var t0 := Time.get_ticks_usec()
	var laid := 0
	for k in range(from, to):
		if add_lot(editor, rows, k) >= 0:
			laid += 1
	var queue_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var nodes := _nodes(base)
	var t1 := Time.get_ticks_usec()
	nodes.flush()
	var flush_ms := (Time.get_ticks_usec() - t1) / 1000.0
	return (
		"fill %d..%d laid %d: queue %.0f ms main, flush %.0f ms, %d nodes"
		% [from, to, laid, queue_ms, flush_ms, nodes.get_child_count()]
	)


static func _load(editor: AuthoringEditor, count: int) -> String:
	var rows := LibraryStructureStore.structures("core")
	var doc := StructureGeometry.ground_snapshot(editor.document)
	doc.structures.clear()
	for k in count:
		var structure := lot(rows, k)
		structure.id = k + 1
		doc.structures.append(structure)
	StructureRecipes.ensure_served()
	var decor := StructureDecor.available()
	var t0 := Time.get_ticks_usec()
	var built := StructureGeometry.build(doc, true, decor)
	var worker_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var t1 := Time.get_ticks_usec()
	var nodes := AuthoredStructures.create(doc, built)
	var main_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var text := (
		"load %d: worker build %.0f ms (decor %s), main-thread create %.0f ms (%.1f ms each), %d nodes"
		% [count, worker_ms, str(decor), main_ms, main_ms / maxf(count, 1), nodes.get_child_count()]
	)
	nodes.free()
	return text


## `load` with the nodes staged (perf4, what a play load does now): a second AuthoredStructures
## `count` lots strong is created with staged = true under the map root and a sampler records
## every frame until nothing is pending. Read the result with `load_staged_report`.
static func _load_staged(base: Node, editor: AuthoringEditor, count: int) -> String:
	var rows := LibraryStructureStore.structures("core")
	var doc := StructureGeometry.ground_snapshot(editor.document)
	doc.structures.clear()
	for k in count:
		var structure := lot(rows, k)
		structure.id = k + 1
		doc.structures.append(structure)
	StructureRecipes.ensure_served()
	var built := StructureGeometry.build(doc, true, StructureDecor.available())
	var old := base.get_tree().root.get_node_or_null(STAGED)
	if old != null:
		old.free()
	var recorder := StagedRecorder.new()
	recorder.name = STAGED
	base.get_tree().root.add_child(recorder)
	var t0 := Time.get_ticks_usec()
	var nodes := AuthoredStructures.create(doc, built, PaletteLibrary.DEFAULT_ROOT, true)
	nodes.name = "AuthoredStructuresStaged"
	var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var t1 := Time.get_ticks_usec()
	StructureGeometry.keys_of(doc, StructureDecor.available())
	var keys_ms := (Time.get_ticks_usec() - t1) / 1000.0
	print("load_staged: keys_of %.1f ms of the create (the rest: plant plans, cache)" % keys_ms)
	ctrl.map_root.add_child(nodes)
	recorder.nodes = nodes
	recorder.create_ms = create_ms
	recorder.begin()
	return "load_staged %d: create %.1f ms main, %d pending" % [count, create_ms, nodes.pending_count()]


static func _load_staged_report(base: Node) -> String:
	var recorder := base.get_tree().root.get_node_or_null(STAGED) as StagedRecorder
	if recorder == null:
		return "no staged sampler"
	var sorted := recorder.frames.duplicate()
	sorted.sort()
	var over20 := 0
	for ms in sorted:
		over20 += 1 if ms > 20.0 else 0
	var text := (
		(
			"load_staged: done %s after %d frames (%.0f ms), create %.1f ms, worst frame %.1f ms, "
			+ "median %.1f, over 20 ms: %d, %d nodes, pending %d"
		)
		% [
			str(recorder.done),
			sorted.size(),
			recorder.total_ms,
			recorder.create_ms,
			sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0,
			sorted[sorted.size() / 2] if sorted.size() > 0 else 0.0,
			over20,
			recorder.nodes.get_child_count() if is_instance_valid(recorder.nodes) else -1,
			recorder.nodes.pending_count() if is_instance_valid(recorder.nodes) else -1
		]
	)
	if is_instance_valid(recorder.nodes):
		recorder.nodes.free()
	recorder.free()
	return text


static func _cap(base: Node, editor: AuthoringEditor) -> String:
	var rows := LibraryStructureStore.structures("core")
	var nodes := _nodes(base)
	nodes.flush()
	var standing := editor.document.structures.size()
	var out := PackedStringArray(["cap: %d standing" % standing])
	var t0 := Time.get_ticks_usec()
	var id := add_lot(editor, rows, standing)
	out.append("add #%d: %.1f ms main" % [standing + 1, (Time.get_ticks_usec() - t0) / 1000.0])
	var t1 := Time.get_ticks_usec()
	nodes.flush()
	out.append("lands after %.0f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	var t2 := Time.get_ticks_usec()
	var extra := add_lot(editor, rows, standing + 1)
	out.append(
		(
			"next add (id %d, standing now %d): %.1f ms main"
			% [extra, editor.document.structures.size(), (Time.get_ticks_usec() - t2) / 1000.0]
		)
	)
	nodes.flush()
	var t3 := Time.get_ticks_usec()
	var turned := editor.structures.turn(id, 0.2)
	out.append("edit (turn): %.1f ms main (%s)" % [(Time.get_ticks_usec() - t3) / 1000.0, turned])
	var t4 := Time.get_ticks_usec()
	nodes.flush()
	out.append("edit lands after %.0f ms" % ((Time.get_ticks_usec() - t4) / 1000.0))
	var t5 := Time.get_ticks_usec()
	editor.structures.remove(id)
	nodes.refresh(editor.document)
	out.append("remove: %.1f ms main" % ((Time.get_ticks_usec() - t5) / 1000.0))
	return " | ".join(out)


static func _hitch_start(base: Node, editor: AuthoringEditor, step: Dictionary) -> String:
	var old := base.get_tree().root.get_node_or_null(HITCH)
	if old != null:
		old.free()
	var hitch := Hitch.new()
	hitch.name = HITCH
	hitch.base = base
	hitch.editor = editor
	hitch.adder = add_lot
	hitch.rows = LibraryStructureStore.structures("core")
	hitch.from_lot = int(step.get("from", 100))
	hitch.count = int(step.get("count", 20))
	hitch.interval = float(step.get("interval", 0.5))
	base.get_tree().root.add_child(hitch)
	return (
		"hitch: adding %d lots from %d every %.2f s" % [hitch.count, hitch.from_lot, hitch.interval]
	)


static func _hitch_stop(base: Node) -> String:
	var hitch := base.get_tree().root.get_node_or_null(HITCH) as Hitch
	if hitch == null:
		return "no hitch sampler"
	var frames := hitch.frames.duplicate()
	var adds := hitch.add_ms.duplicate()
	var added := hitch.added
	hitch.queue_free()
	var over20 := 0
	var over33 := 0
	for ms in frames:
		over20 += 1 if ms > 20.0 else 0
		over33 += 1 if ms > 33.4 else 0
	var sorted := frames.duplicate()
	sorted.sort()
	adds.sort()
	var p95 := sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0.0
	var median := sorted[sorted.size() / 2] if sorted.size() > 0 else 0.0
	return (
		(
			"hitch: added %d, %d frames, median %.1f p95 %.1f worst %.1f ms, over 20 ms: %d, "
			+ "over 33 ms: %d; per-add main ms median %.1f max %.1f"
		)
		% [
			added,
			frames.size(),
			median,
			p95,
			sorted[sorted.size() - 1] if sorted.size() > 0 else 0.0,
			over20,
			over33,
			adds[adds.size() / 2] if adds.size() > 0 else 0.0,
			adds[adds.size() - 1] if adds.size() > 0 else 0.0
		]
	)


static func _profile(base: Node, editor: AuthoringEditor) -> String:
	var rows := LibraryStructureStore.structures("core")
	var nodes := _nodes(base)
	if nodes != null:
		nodes.flush()
	var doc := editor.document
	var out := PackedStringArray(["profile at %d standing" % doc.structures.size()])
	var memo := {}
	var t := Time.get_ticks_usec()
	StructureGeometry.keys_memoised(doc, memo, true)
	out.append("keys cold %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	StructureGeometry.keys_memoised(doc, memo, true)
	out.append("keys warm %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	StructureGeometry.ground_fingerprint(doc)
	out.append("fingerprint %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	nodes.refresh(doc)
	out.append("refresh unchanged %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	var boxes := {}
	for structure in doc.structures:
		boxes[structure.id] = StructureDressing.bounds_of(structure.footprint)
	t = Time.get_ticks_usec()
	var near_total := 0
	var near_lists := []
	for structure in doc.structures:
		var near := StructureDressing.neighbours(doc, structure, boxes)
		near_total += near.size()
		near_lists.append(near)
	out.append(
		(
			"neighbours all %.1f (avg %.1f each)"
			% [
				(Time.get_ticks_usec() - t) / 1000.0,
				near_total / float(maxi(1, doc.structures.size()))
			]
		)
	)
	t = Time.get_ticks_usec()
	for near in near_lists:
		hash(near)
	out.append("hash near %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for structure in doc.structures:
		JSON.stringify(structure.params, "", true)
	out.append("json %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	for structure in doc.structures:
		StructureRecipes.digest(structure.recipe)
	out.append("digest %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	var laid := lot(rows, doc.structures.size())
	laid.id = 9999
	t = Time.get_ticks_usec()
	var area := Rect2()
	area = StructureGeometry.clear_bounds(laid)
	out.append("clear_bounds %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	MapStructureIO.structure_problem(laid, doc.extent_m())
	out.append("problem %.2f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	if is_instance_valid(editor.scatter):
		editor.scatter.request_region(area.grow(2.0))
	out.append("scatter request %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	editor.commit_prop_edit()
	editor.finish_height_work()
	out.append("commit+finish %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	var id := add_lot(editor, rows, doc.structures.size())
	out.append("whole add %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	nodes.flush()
	out.append("flush %.0f" % ((Time.get_ticks_usec() - t) / 1000.0))
	t = Time.get_ticks_usec()
	editor.structures.remove(id)
	out.append("whole remove %.1f" % ((Time.get_ticks_usec() - t) / 1000.0))
	return " | ".join(out)


static func _consumers(base: Node, n: int) -> String:
	var nodes := _nodes(base)
	var mills: Array[Node] = nodes.find_children("*", "MillMotion", true, false)
	var vanes: Array[Node] = nodes.find_children("*", "VaneMotion", true, false)
	var out := PackedStringArray()
	var t0 := Time.get_ticks_usec()
	for i in n:
		Wind.publish(Wind.clock() + i * 0.016)
	out.append("Wind.publish %.2f us/call" % ((Time.get_ticks_usec() - t0) / float(n)))
	for group: Array in [mills, vanes]:
		if group.is_empty():
			continue
		var t1 := Time.get_ticks_usec()
		for i in n:
			for node: Node in group:
				node._process(0.016)
		var per_frame := (Time.get_ticks_usec() - t1) / float(n)
		out.append(
			(
				"%s x%d: %.1f us per frame for all (%.2f us each; only on-screen ones run)"
				% [group[0].name, group.size(), per_frame, per_frame / group.size()]
			)
		)
	out.append(
		"process monitor %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	)
	out.append("nodes in tree %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	return "consumers: " + ", ".join(out)


static func _reset(base: Node, editor: AuthoringEditor) -> String:
	for structure in editor.document.structures.duplicate():
		editor.structures.remove(structure.id)
	var nodes := _nodes(base)
	nodes.refresh(editor.document)
	nodes.flush()
	return "reset: %d structures" % editor.document.structures.size()


static func _rect(width: float, depth: float, yaw_deg: float, at: Vector2) -> PackedVector2Array:
	var half := Vector2(width, depth) * 0.5
	var turn := deg_to_rad(yaw_deg)
	var out := PackedVector2Array()
	for corner: Vector2 in [
		Vector2(-half.x, -half.y),
		Vector2(half.x, -half.y),
		Vector2(half.x, half.y),
		Vector2(-half.x, half.y)
	]:
		out.append(at + corner.rotated(turn))
	return out


static func _editor(base: Node) -> AuthoringEditor:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	return ctrl.editor if ctrl != null else null


static func _nodes(base: Node) -> AuthoredStructures:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.map_root == null:
		return null
	return ctrl.map_root.get_node_or_null(AuthoredStructures.NODE_NAME) as AuthoredStructures
