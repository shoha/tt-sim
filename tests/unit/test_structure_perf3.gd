extends GutTest

## Village-scale structure performance (topic perf3, docs/systems/structure_performance.md "third
## round"): the neighbour grid that replaced the all-pairs search in every key, the decor plan a
## build worker makes (placement, triangle cap and grouping, StructureDecor.plan) against the old
## main-thread path, and the install queue that spreads node making over frames.

const KINDS: Array = ["ivy", "flower_boxes", "banner", "vane"]

var _map: Node3D = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func _structure(ref: String, structure_id: int, at: Vector2, kinds: Array = KINDS) -> Structure:
	var plan := PackedVector2Array(
		[at + Vector2(-3, -2), at + Vector2(3, -2), at + Vector2(3, 2), at + Vector2(-3, 2)]
	)
	var params := StructureOrnaments.with_kinds({}, kinds)
	return Structure.make(structure_id, ref, plan, 5 + structure_id, params)


## The decor path as it was before perf3: placements, plant costs, the cap, the groups.
func _legacy_groups(anchors: Array[Dictionary], info: Dictionary) -> Dictionary:
	var rows: Array[Dictionary] = info.rows
	var placed := StructureDecor.placements(anchors, rows, true)
	var cost := {}
	for placement in placed:
		if not cost.has(placement.id) and (info.by_id as Dictionary).has(placement.id):
			cost[placement.id] = int((info.cost as Dictionary).get(placement.id, 0))
	var groups := {}
	for placement in StructureDecor.cap_triangles(placed, cost):
		if not groups.has(placement.id):
			groups[placement.id] = [] as Array[Dictionary]
		(groups[placement.id] as Array[Dictionary]).append(placement)
	return groups


func _info() -> Dictionary:
	var holder := AuthoredStructures.new()
	var info := holder._decor_info()
	holder.free()
	return info


func _triangles(groups: Dictionary, cost: Dictionary) -> int:
	var total := 0
	for id: String in groups:
		total += (groups[id] as Array).size() * int(cost.get(id, 0))
	return total


# --- neighbour grid ----------------------------------------------------------------------


func test_the_grid_finds_the_same_neighbours_in_the_same_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for k in 60:
		var at := Vector2(rng.randf_range(-45.0, 45.0), rng.randf_range(-45.0, 45.0))
		_doc.structures.append(_structure("core:cottage", k + 1, at))
	# One degenerate footprint is never a neighbour, either way.
	var bad := _structure("core:cottage", 99, Vector2.ZERO)
	bad.footprint = PackedVector2Array([Vector2.ZERO, Vector2.ONE])
	_doc.structures.append(bad)
	var boxes := {}
	for structure in _doc.structures:
		boxes[structure.id] = StructureDressing.bounds_of(structure.footprint)
	var grid := StructureDressing.neighbour_grid(_doc, boxes)
	for structure in _doc.structures:
		var plain := StructureDressing.neighbours(_doc, structure, boxes)
		var fast := StructureDressing.neighbours(_doc, structure, boxes, grid)
		assert_eq(fast, plain, "structure %d" % structure.id)


func test_keys_with_the_grid_equal_the_keys_of_one_structure_at_a_time() -> void:
	for k in 24:
		var at := Vector2((float(k % 6) - 2.5) * 7.0, (float(k / 6) - 1.5) * 7.0)
		_doc.structures.append(_structure("core:cottage", k + 1, at, []))
	var keys := StructureGeometry.keys_of(_doc)
	var memo := {}
	assert_eq(StructureGeometry.keys_memoised(_doc, memo), keys, "memoised")
	for structure in _doc.structures:
		assert_eq(keys[structure.id], StructureGeometry.key_of(_doc, structure), "one at a time")


# --- decor plan --------------------------------------------------------------------------


func test_a_workers_plan_equals_the_old_main_thread_path() -> void:
	var info := _info()
	assert_false(info.is_empty())
	for ref in [
		"core:cottage", "core:townhouse_trimmed", "core:castle_keep", "core:tudor_townhouse"
	]:
		var structure := _structure(ref, 1, Vector2.ZERO)
		var parts := StructureGeometry.build_one(_doc, structure, true, info)
		var anchors: Array[Dictionary] = []
		anchors.assign(parts.get("anchors", []))
		if anchors.is_empty():
			continue
		assert_true(parts.has("decor_plan"), "%s has a plan" % ref)
		var plan: Dictionary = parts.decor_plan
		var legacy := _legacy_groups(anchors, info)
		var legacy_ids: Array = legacy.keys()
		legacy_ids.sort()
		assert_eq(plan.ids, legacy_ids, "%s ids" % ref)
		assert_eq(plan.groups, legacy, "%s placements" % ref)
		assert_eq(
			_triangles(plan.groups, info.cost), _triangles(legacy, info.cost), "%s triangles" % ref
		)
		assert_true(
			_triangles(plan.groups, info.cost) <= StructureDecor.MAX_TRIANGLES, "%s is capped" % ref
		)
		var again := StructureGeometry.build_one(_doc, structure, true, info)
		assert_eq(again.decor_plan, plan, "%s: the plan is deterministic" % ref)


func test_a_plan_is_not_part_of_the_digest() -> void:
	var info := _info()
	var structure := _structure("core:cottage", 1, Vector2.ZERO)
	var with_plan := StructureGeometry.build_one(_doc, structure, true, info)
	var without := StructureGeometry.build_one(_doc, structure, true)
	assert_false(without.has("decor_plan"))
	assert_eq(StructureGeometry.digest_of(with_plan), StructureGeometry.digest_of(without))


func test_the_node_of_a_planned_build_equals_the_node_of_an_unplanned_one() -> void:
	var info := _info()
	var structure := _structure("core:cottage", 1, Vector2.ZERO)
	var planned := StructureGeometry.build_one(_doc, structure, true, info)
	var plain := StructureGeometry.build_one(_doc, structure, true)
	var stale := StructureGeometry.build_one(_doc, structure, true, info)
	(stale.decor_plan as Dictionary)["sig"] = int(info.sig) + 1
	(stale.decor_plan as Dictionary)["groups"] = {}
	var shapes: Array = []
	for parts: Dictionary in [planned, plain, stale]:
		var nodes := AuthoredStructures.new()
		nodes.apply({"structures": [parts], "decor": true})
		var baked := nodes.get_structure_node(1).get_node_or_null(AuthoredStructures.DECOR_NODE)
		assert_not_null(baked, "decor stands")
		var arrays: Array = []
		for s in (baked as MeshInstance3D).mesh.get_surface_count():
			arrays.append(((baked as MeshInstance3D).mesh.surface_get_arrays(s))[Mesh.ARRAY_VERTEX])
		shapes.append(arrays)
		nodes.free()
	assert_eq(shapes[0], shapes[1], "the plan gives the plain path's plants")
	assert_eq(shapes[2], shapes[1], "a stale plan is made again")


func test_a_loaders_parts_get_their_plans_before_the_nodes() -> void:
	for k in 4:
		_doc.structures.append(_structure("core:cottage", k + 1, Vector2(k * 10.0 - 15.0, 0.0)))
	var built := StructureGeometry.build(_doc, true, true)
	for parts: Dictionary in built.structures:
		assert_false(parts.has("decor_plan"), "a loader worker has no library info")
	var nodes := AuthoredStructures.create(_doc, built)
	add_child_autofree(nodes)
	for parts: Dictionary in built.structures:
		if not (parts.anchors as Array).is_empty():
			assert_true(parts.has("decor_plan"), "create placed the plants as a group")


# --- install queue -----------------------------------------------------------------------


func _staged(count: int) -> AuthoredStructures:
	for k in count:
		_doc.structures.append(_structure("core:cottage", k + 1, Vector2((k - 2) * 1.5, 0.0), []))
	var decor := StructureDecor.available()
	var built := StructureGeometry.build(_doc, true, decor)
	var nodes := AuthoredStructures.create(_doc, built, PaletteLibrary.DEFAULT_ROOT, true)
	_map.add_child(nodes)
	nodes.set_process(false)
	return nodes


func test_a_staged_load_makes_its_nodes_by_the_budget_newest_first() -> void:
	var nodes := _staged(5)
	assert_eq(nodes.get_child_count(), 0, "nothing is made by create")
	assert_eq(nodes.pending_count(), 5)
	assert_eq(nodes.install_pending(0.0), 1, "an empty budget still makes one")
	assert_not_null(nodes.get_structure_node(5), "the newest first")
	nodes.prioritize(1)
	assert_eq(nodes.install_pending(0.0), 1)
	assert_not_null(nodes.get_structure_node(1), "a prioritised one jumps the line")
	assert_eq(nodes.pending_count(), 3)
	assert_eq(nodes.flush(), 3, "flush makes the rest")
	assert_eq(nodes.get_child_count(), 5)
	assert_eq(nodes.pending_count(), 0)
	assert_eq(nodes.keys(), StructureGeometry.keys_of(_doc, StructureDecor.available()))


func test_an_edit_that_replaces_a_node_goes_before_new_structures() -> void:
	var nodes := _staged(4)
	nodes.install_pending(0.0)
	var shown := -1
	for child in nodes.get_children():
		shown = nodes._id_of(child)
	assert_gt(shown, 0)
	var parts := StructureGeometry.build_one(
		_doc, _doc.structure(shown), StructureDecor.available()
	)
	nodes._enqueue(shown, 123, parts, 0)
	assert_eq(nodes.install_pending(0.0), 1)
	assert_eq(nodes.keys()[shown], 123, "the replacement was made before the new ones")
	assert_eq(nodes.get_child_count(), 1)
	assert_eq(nodes.pending_count(), 3)


func test_an_edit_back_to_what_is_shown_drops_the_queued_install() -> void:
	var nodes := _staged(2)
	nodes.install_pending(0.0)
	assert_eq(nodes.pending_count(), 1)
	nodes._drop_job(1)
	nodes._drop_job(2)
	assert_eq(nodes.pending_count(), 0, "a dropped job takes its queued install with it")
