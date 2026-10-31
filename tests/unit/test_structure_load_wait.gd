extends GutTest

## The staged install of a play load's structures (topic perf4):
## MapSourceLoader.add_authored_structures with `staged` leaves the nodes to the install queue, and
## StructureLoadWait holds the load until none is left, cancels the queue when the load is
## superseded, and settles it before an edit.

const LOT_SPACING := 7.0
const COLUMNS := 12
## Per-frame spacing a staged load may show in this harness (headless, no rendering): the install
## budget is 3 ms, so a frame far beyond it means a lump of work came back onto one frame.
const FRAME_LIMIT_MS := 400.0

var _map: Node3D = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(64, 64), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _lay(count: int) -> void:
	for k in count:
		var at := Vector2(
			(float(k % COLUMNS) - (COLUMNS - 1) * 0.5) * LOT_SPACING,
			(float(k / COLUMNS) - 5.0) * LOT_SPACING
		)
		var plan := PackedVector2Array(
			[at + Vector2(-2, -1.5), at + Vector2(2, -1.5), at + Vector2(2, 1.5), at + Vector2(-2, 1.5)]
		)
		_doc.structures.append(Structure.make(k + 1, "core:cottage", plan, 5 + k, {}))


func _built() -> Dictionary:
	return StructureGeometry.build(_doc, true, StructureDecor.available())


func test_a_staged_load_of_128_structures_finishes_with_nothing_pending() -> void:
	_lay(128)
	var built := _built()
	var t0 := Time.get_ticks_usec()
	var nodes := MapSourceLoader.add_authored_structures(_map, _doc, built, true)
	var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
	assert_not_null(nodes)
	assert_eq(nodes.get_child_count(), 0, "create made no node")
	assert_eq(StructureLoadWait.pending_of(_map), 128)
	var seen := {"frames": 0, "worst": 0.0, "last": Time.get_ticks_usec(), "done": 0, "total": 0}
	var progress := func(done: int, total: int) -> void:
		var now := Time.get_ticks_usec()
		seen["worst"] = maxf(float(seen["worst"]), (now - int(seen["last"])) / 1000.0)
		seen["last"] = now
		seen["frames"] += 1
		seen["done"] = done
		seen["total"] = total
	var ok: bool = await StructureLoadWait.wait_async(
		get_tree(), _map, func() -> bool: return false, progress
	)
	assert_true(ok)
	assert_eq(StructureLoadWait.pending_of(_map), 0, "nothing is left to install")
	assert_eq(nodes.get_child_count(), 128)
	assert_eq(seen["done"], 128)
	assert_eq(seen["total"], 128)
	assert_lte(int(seen["frames"]), 130, "at least one structure a frame, so 128 frames at most")
	assert_lt(float(seen["worst"]), FRAME_LIMIT_MS, "no frame holds the whole install")
	gut.p(
		"staged create %.0f ms main, %d frames, worst gap %.1f ms"
		% [create_ms, seen["frames"], seen["worst"]]
	)
	assert_eq(nodes.keys(), StructureGeometry.keys_of(_doc, StructureDecor.available()))


func test_cancelling_midway_clears_the_queue() -> void:
	_lay(40)
	var nodes := MapSourceLoader.add_authored_structures(_map, _doc, _built(), true)
	var frames := {"n": 0}
	var superseded := func() -> bool:
		frames["n"] += 1
		return int(frames["n"]) > 3
	var ok: bool = await StructureLoadWait.wait_async(get_tree(), _map, superseded)
	assert_false(ok, "a superseded load reports it")
	assert_eq(nodes.pending_count(), 0, "the queue is cleared")
	var made := nodes.get_child_count()
	assert_lt(made, 40, "stopped part way")
	await get_tree().process_frame
	assert_eq(nodes.get_child_count(), made, "nothing is installed after the cancel")


func test_the_unstaged_path_still_stands_at_once() -> void:
	_lay(3)
	var nodes := MapSourceLoader.add_authored_structures(_map, _doc, _built())
	assert_eq(nodes.get_child_count(), 3)
	assert_eq(StructureLoadWait.pending_of(_map), 0)
	var ok: bool = await StructureLoadWait.wait_async(get_tree(), _map, func() -> bool: return false)
	assert_true(ok, "nothing to wait for")


func test_a_map_without_structures_has_nothing_to_wait_for() -> void:
	var ok: bool = await StructureLoadWait.wait_async(get_tree(), _map, func() -> bool: return false)
	assert_true(ok)
	assert_eq(StructureLoadWait.pending_of(_map), 0)
	assert_eq(StructureLoadWait.settle(_map), 0)


func test_settle_installs_the_queue_so_an_edit_rebuilds_nothing() -> void:
	_lay(6)
	var nodes := MapSourceLoader.add_authored_structures(_map, _doc, _built(), true)
	nodes.set_process(false)
	assert_eq(StructureLoadWait.settle(_map), 6)
	assert_eq(nodes.get_child_count(), 6)
	AuthoredStructures.refresh_map(_map, _doc)
	assert_eq(nodes.pending_count(), 0, "no structure was rebuilt for the edit")


func test_a_structure_node_outside_the_tree_is_made_at_once() -> void:
	_lay(4)
	var loose := Node3D.new()
	loose.name = "LevelMap"
	var nodes := MapSourceLoader.add_authored_structures(loose, _doc, _built(), true)
	assert_not_null(nodes)
	var ok: bool = await StructureLoadWait.wait_async(get_tree(), loose, func() -> bool: return false)
	assert_true(ok)
	assert_eq(nodes.get_child_count(), 4, "flushed, not waited for")
	loose.free()
