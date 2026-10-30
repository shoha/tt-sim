extends GutTest

## Structures built into the game (card S2): StructureRecipes (the temporary resolver),
## StructureGeometry (record + ground -> procgen inputs -> parts), AuthoredStructures (nodes,
## collision, the key cache, asynchronous newest-edit-wins builds), the worker prep, scatter
## clearance, the footprint rules in the map reader, and the fingerprint's node part. The
## pinned digests are in tests/fixtures/structure_digests.txt; a deliberate recipe or pipeline
## change regenerates them (the failure message prints the new lines).
## Summary: docs/systems/structures.md.

const PIN_FILE := "res://tests/fixtures/structure_digests.txt"
const SAVE_PATH := "user://test_structure_build.ttmap"

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	StructureRecipes.ensure_served()


func after_each() -> void:
	StructureGeometry.textured = true
	StructureRecipes.resolver = Callable()
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _plan(centre: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	return PackedVector2Array(
		[
			centre + Vector2(-3, -2),
			centre + Vector2(3, -2),
			centre + Vector2(3, 2),
			centre + Vector2(-3, 2)
		]
	)


func _l_plan() -> PackedVector2Array:
	return PackedVector2Array(
		[
			Vector2(-4, -3),
			Vector2(4, -3),
			Vector2(4, 0),
			Vector2(0, 0),
			Vector2(0, 3),
			Vector2(-4, 3)
		]
	)


func _structure(
	recipe: String = "core:cottage", structure_id: int = 1, at: Vector2 = Vector2.ZERO
) -> Structure:
	return Structure.make(structure_id, recipe, _plan(at), 5)


func _slope() -> void:
	var rise := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			rise[_doc.sample_index(x, z)] = 0.1 * _doc.sample_to_world(Vector2(x, z)).x
	_doc.heights = rise


## Raises a 5 by 5 block of ground samples around map point `at` by `amount` metres.
func _raise(at: Vector2, amount: float) -> void:
	var raised := _doc.heights.duplicate()
	var centre := _doc.world_to_sample(at).round()
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			raised[_doc.sample_index(int(centre.x) + dx, int(centre.y) + dz)] += amount
	_doc.heights = raised


func _scatter_node() -> void:
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	_map.add_child(node)


func _roles(parts: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for mesh: Dictionary in parts.meshes:
		if not out.has(mesh.role):
			out.append(mesh.role)
	return out


func _nodes() -> AuthoredStructures:
	return _map.get_node(AuthoredStructures.NODE_NAME) as AuthoredStructures


# --- recipes -----------------------------------------------------------------------------


func test_the_starter_set_resolves_and_an_unknown_reference_does_not() -> void:
	assert_eq(StructureRecipes.core_refs().size(), 64)
	for ref in StructureRecipes.core_refs():
		assert_true(StructureRecipes.exists(ref), ref)
		assert_eq(StructureRecipes.digest(ref).length(), 64, "a sha256")
		var recipe := StructureRecipes.document(ref)
		assert_not_null(recipe, ref)
		assert_true(StructureRecipes.has_param(recipe, "height"), "%s exposes a height" % ref)
	assert_false(StructureRecipes.exists("core:castle"))
	assert_false(StructureRecipes.exists("other:cottage"), "only core is built in")
	assert_eq(StructureRecipes.digest("core:castle"), "")
	assert_null(StructureRecipes.document("not a reference"))
	assert_ne(
		StructureRecipes.digest("core:cottage"),
		StructureRecipes.digest("core:townhouse"),
		"own text"
	)


func test_params_clamp_to_the_interface_and_unknown_names_drop() -> void:
	var recipe := StructureRecipes.document("core:townhouse")
	var clamped := StructureRecipes.clamp_params(
		recipe, {"height": 999.0, "roof_pitch": -5, "textured": true, "colour": 3.0}
	)
	assert_eq(clamped.keys().size(), 3, "colour is not in the interface")
	assert_lte(float(clamped.height), 8.0)
	assert_gte(float(clamped.roof_pitch), 15.0)
	assert_eq(clamped.textured, 1.0, "a bool is 0 or 1")


func test_the_resolver_seam_replaces_the_table() -> void:
	var text := FileAccess.get_file_as_string("res://procgen/recipes/cottage.json")
	StructureRecipes.resolver = func(ref: String) -> Dictionary:
		return {"text": text} if ref == "mylib:hut" else {}
	assert_true(StructureRecipes.exists("mylib:hut"))
	assert_false(StructureRecipes.exists("core:cottage"), "the resolver owns every reference")
	var parts := StructureGeometry.build_one(_doc, _structure("mylib:hut"))
	assert_eq(parts.problem, "")
	assert_false((parts.meshes as Array).is_empty(), "built through the seam")


# --- the geometry ------------------------------------------------------------------------


func test_a_cottage_builds_roles_collision_layout_and_provenance() -> void:
	var parts := StructureGeometry.build_one(_doc, _structure())
	assert_eq(parts.problem, "")
	var roles := _roles(parts)
	assert_true(roles.has("wall") and roles.has("roof"), "a house is not one material: %s" % roles)
	assert_gt((parts.collision as PackedVector3Array).size(), 0, "faces to stand on")
	assert_almost_eq(float(parts.top), 4.04, 0.05)
	assert_gt((parts.tag_table as PackedStringArray).size(), 0, "provenance kept")
	assert_not_null(parts.layout, "the final layout is kept")
	assert_gt((parts.openings as Array).size(), 0, "a door and windows")
	assert_gt(int(parts.triangles), 500)
	assert_eq(int(parts.triangles), StructureGeometry.triangle_count(parts), "the split keeps all")
	for mesh: Dictionary in parts.meshes:
		var arrays: Array = mesh.arrays
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		assert_eq((mesh.tags as PackedInt32Array).size(), vertices.size(), "a tag per vertex")
		assert_eq((arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size(), vertices.size() * 4)


func test_a_chimneyed_cottage_has_trim_and_a_chimney_by_node_type() -> void:
	var parts := StructureGeometry.build_one(_doc, _structure("core:cottage_chimneyed"))
	var roles := _roles(parts)
	for role in ["wall", "roof", "trim", "chimney"]:
		assert_true(roles.has(role), "%s in %s" % [role, roles])


func test_the_split_follows_the_node_that_made_each_triangle() -> void:
	var parts := StructureGeometry.build_one(_doc, _structure("core:cottage_chimneyed"))
	var table: PackedStringArray = parts.tag_table
	for mesh: Dictionary in parts.meshes:
		var indices: PackedInt32Array = mesh.arrays[Mesh.ARRAY_INDEX]
		for t in mini(indices.size() / 3, 200):
			var tag: int = (mesh.tags as PackedInt32Array)[indices[t * 3]]
			var node_id := table[tag].get_slice("/", 0)
			if mesh.role == StructureLook.CHIMNEY:
				assert_true(node_id.begins_with("roof_furniture"), table[tag])
			elif mesh.role == StructureLook.ROOF:
				assert_true(node_id.begins_with("roof_"), table[tag])


func test_a_structure_follows_the_ground_it_stands_on() -> void:
	_slope()
	var parts := StructureGeometry.build_one(_doc, _structure("core:cottage", 1, Vector2(5, 0)))
	assert_almost_eq(float(parts.top), 0.1 * 8.0 + 4.04, 0.2, "the top rises with the ground")


func test_the_geometry_is_the_same_each_time_and_on_a_worker() -> void:
	var structure := _structure("core:townhouse_trimmed")
	var first := StructureGeometry.digest_of(StructureGeometry.build_one(_doc, structure))
	var again := StructureGeometry.digest_of(StructureGeometry.build_one(_doc, structure))
	assert_eq(first, again, "two builds")
	var out := {}
	var ground := StructureGeometry.ground_snapshot(_doc)
	var task := WorkerThreadPool.add_task(
		func() -> void: out["parts"] = StructureGeometry.build_one(ground, structure)
	)
	WorkerThreadPool.wait_for_task_completion(task)
	assert_eq(StructureGeometry.digest_of(out.parts), first, "a worker on a ground snapshot")
	var other := structure.copy()
	other.footprint = _l_plan()
	assert_ne(
		StructureGeometry.digest_of(StructureGeometry.build_one(_doc, other)),
		first,
		"the plan counts"
	)


func test_the_seed_changes_a_timber_cottage_and_params_change_the_look() -> void:
	var a := _structure("core:cottage_chimneyed")
	var b := a.copy()
	b.seed_value = 6
	assert_ne(
		StructureGeometry.digest_of(StructureGeometry.build_one(_doc, a)),
		StructureGeometry.digest_of(StructureGeometry.build_one(_doc, b)),
		"a new seed is a new house"
	)
	var tall := a.copy()
	tall.params = {"height": 3.4}
	assert_gt(
		float(StructureGeometry.build_one(_doc, tall).top),
		float(StructureGeometry.build_one(_doc, a).top) + 0.5,
		"the height param reaches the recipe"
	)
	var junk := a.copy()
	junk.params = {"no_such_param": 4.0}
	assert_eq(
		StructureGeometry.digest_of(StructureGeometry.build_one(_doc, junk)),
		StructureGeometry.digest_of(StructureGeometry.build_one(_doc, a)),
		"an unknown param changes nothing"
	)


func test_an_l_plan_builds_and_a_bad_plan_or_recipe_builds_nothing() -> void:
	var l := _structure()
	l.footprint = _l_plan()
	var parts := StructureGeometry.build_one(_doc, l)
	assert_eq(parts.problem, "")
	assert_gt(int(parts.triangles), 1000)
	var unknown := StructureGeometry.build_one(_doc, _structure("core:castle"))
	assert_eq((unknown.meshes as Array).size(), 1, "a recipe the game lacks shows a plot")
	assert_true(unknown.placeholder)
	assert_string_contains(unknown.problem, "unknown")
	assert_eq(unknown.top, StructureGeometry.NONE)
	var sliver := _structure()
	sliver.footprint = PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 0.2)])
	assert_ne(StructureGeometry.build_one(_doc, sliver).problem, "", "a sliver is refused")


func test_textured_stone_is_a_part_of_stone_structures() -> void:
	var textured := StructureGeometry.build_one(_doc, _structure("core:townhouse"))
	assert_true(_kinds(textured).has("masonry"), "the texture carries the courses")
	StructureGeometry.textured = false
	var modelled := StructureGeometry.build_one(_doc, _structure("core:townhouse"))
	assert_false(_kinds(modelled).has("masonry"))
	assert_gt(int(modelled.triangles), int(textured.triangles) * 3, "modelled blocks cost more")


func _kinds(parts: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for mesh: Dictionary in parts.meshes:
		out.append(mesh.kind)
	return out


func test_the_key_moves_with_everything_the_geometry_depends_on() -> void:
	var structure := _structure()
	var key := StructureGeometry.key_of(_doc, structure)
	assert_eq(key, StructureGeometry.key_of(_doc, structure), "stable")
	var variants: Array[Structure] = []
	for change in ["footprint", "seed", "params", "style", "recipe"]:
		var changed := structure.copy()
		match change:
			"footprint":
				changed.footprint = _plan(Vector2(1, 0))
			"seed":
				changed.seed_value = 6
			"params":
				changed.params = {"height": 3.0}
			"style":
				changed.style = "alpine"
			"recipe":
				changed.recipe = "core:townhouse"
		variants.append(changed)
		assert_ne(StructureGeometry.key_of(_doc, changed), key, change)
	var far := _structure("core:cottage", 1, Vector2(-9, -9))
	var far_key := StructureGeometry.key_of(_doc, far)
	_raise(Vector2.ZERO, 0.5)
	assert_ne(StructureGeometry.key_of(_doc, structure), key, "ground under the inside of the plan")
	assert_eq(StructureGeometry.key_of(_doc, far), far_key, "ground far away does not")
	StructureGeometry.textured = false
	assert_ne(StructureGeometry.key_of(_doc, structure), key, "the textured switch")


## The memoised keys (keys_memoised) must equal keys_of() after every kind of edit, and the memo
## must never serve a key for a ground it did not see: each edit below changes some ground input
## (struct_perf2: the signature hashes the heights, the pond mask and every water body field).
func test_memoised_keys_equal_the_plain_keys_after_every_ground_edit() -> void:
	_doc.structures.append(_structure("core:cottage", 1, Vector2(-5, 0)))
	_doc.structures.append(_structure("core:cottage", 2, Vector2(5, 0)))
	var memo := {}
	assert_eq(StructureGeometry.keys_memoised(_doc, memo), StructureGeometry.keys_of(_doc), "cold")
	assert_eq(StructureGeometry.keys_memoised(_doc, memo), StructureGeometry.keys_of(_doc), "hit")
	var before := StructureGeometry.keys_of(_doc)
	var edits: Dictionary[String, Callable] = {
		"sculpt under a structure": func() -> void: _raise(Vector2(-5, 0), 0.4),
		"in-place height write":
		func() -> void:
			_doc.heights[_doc.sample_index(20, 20)] += 0.3
			_raise(Vector2(5, 0), 0.0),
		"a river beside it":
		func() -> void:
			_doc.water_bodies.append(
				WaterBody.river(
					1,
					PackedVector2Array([Vector2(-8, 4), Vector2(8, 4)]),
					PackedFloat32Array([1.5, 1.5]),
					WaterBody.Depth.WAIST,
					-0.2
				)
			),
		"the river's level": func() -> void: _doc.water_bodies[0].level_m = 0.9,
		"the river's course": func() -> void: _doc.water_bodies[0].points[0] = Vector2(-8, 3),
		"a pond": func() -> void: _doc.water_bodies.append(WaterBody.pond(2, WaterBody.Depth.WAIST, 0.5)),
		"the pond mask":
		func() -> void:
			var mask := PackedByteArray()
			mask.resize(_doc.sample_count())
			mask[_doc.sample_index(30, 30)] = 2
			_doc.pond_mask = mask,
	}
	for label in edits:
		edits[label].call()
		var plain := StructureGeometry.keys_of(_doc)
		assert_eq(StructureGeometry.keys_memoised(_doc, memo), plain, label)
		if label in ["sculpt under a structure", "the river's level"]:
			assert_ne(plain, before, label + " moves a key")
		before = plain
	var moved := _structure("core:cottage", 2, Vector2(6, 0))
	_doc.structures[1] = moved
	assert_eq(StructureGeometry.keys_memoised(_doc, memo), StructureGeometry.keys_of(_doc), "moved")
	_doc.structures.remove_at(0)
	assert_eq(StructureGeometry.keys_memoised(_doc, memo), StructureGeometry.keys_of(_doc), "gone")
	assert_eq(memo.size(), 1, "the memo forgets a structure that left")


func test_a_new_neighbour_changes_the_key_but_not_the_samples_taken() -> void:
	_doc.structures.append(_structure("core:cottage", 1, Vector2(-4, 0)))
	var memo := {}
	var alone := StructureGeometry.keys_memoised(_doc, memo)
	var samples: Array = memo[1]["samples"]
	_doc.structures.append(_structure("core:cottage", 2, Vector2(6, 0)))
	var joined := StructureGeometry.keys_memoised(_doc, memo)
	assert_ne(joined[1], alone[1], "the yard of 1 sees its new neighbour")
	assert_same(memo[1]["samples"], samples, "the ground under 1 was not sampled again")
	assert_eq(joined, StructureGeometry.keys_of(_doc), "same as the plain keys")


func test_more_builds_than_workers_all_land_and_start_in_order() -> void:
	_scatter_node()
	var structures := AuthoredStructures.of_map(_map)
	var count := AuthoredStructures.max_running() * 3 + 1
	for k in count:
		var at := Vector2((float(k % 4) - 1.5) * 7.0, (float(k / 4) - 1.5) * 6.0)
		_doc.structures.append(_structure("core:cottage", k + 1, at))
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), count, "all queued")
	assert_eq(structures.flush(), count, "all landed")
	assert_eq(structures.get_child_count(), count)
	assert_eq(structures.pending_count(), 0)
	assert_eq(structures.keys(), StructureGeometry.keys_of(_doc), "keys are the plain keys")


func test_the_recipe_digest_is_part_of_the_key() -> void:
	var structure := _structure("mylib:hut")
	var text := FileAccess.get_file_as_string("res://procgen/recipes/cottage.json")
	StructureRecipes.resolver = func(_ref: String) -> Dictionary: return {"text": text}
	var key := StructureGeometry.key_of(_doc, structure)
	StructureRecipes.resolver = func(_ref: String) -> Dictionary: return {"text": text + " "}
	assert_ne(StructureGeometry.key_of(_doc, structure), key, "an edited recipe rebuilds")


func test_the_starter_set_matches_its_pinned_digests() -> void:
	assert_true(FileAccess.file_exists(PIN_FILE), "the pin file")
	var now := PackedStringArray()
	for ref in StructureRecipes.core_refs():
		var plan := StructurePlacement.pin_plan(LibraryStructureStore.structure(ref))
		var parts := StructureGeometry.build_one(_doc, Structure.make(1, ref, plan, 5))
		assert_eq(parts.problem, "", ref)
		now.append(
			(
				"%s %s %d"
				% [ref, StructureGeometry.digest_of(parts), StructureGeometry.triangle_count(parts)]
			)
		)
	# Both sorted: the library lists structures by family and variant, the file by the starter table.
	now.sort()
	var pinned := FileAccess.get_file_as_string(PIN_FILE).strip_edges().split("\n")
	for k in pinned.size():
		pinned[k] = pinned[k].strip_edges()
	pinned.sort()
	var moved := PackedStringArray()
	for k in maxi(now.size(), pinned.size()):
		var got := now[k] if k < now.size() else "(none)"
		var want := pinned[k].strip_edges() if k < pinned.size() else "(none)"
		if got != want:
			moved.append("pinned '%s' now '%s'" % [want, got])
	assert_eq(moved.size(), 0, "a deliberate change regenerates the file: %s" % "; ".join(moved))


# --- budgets -----------------------------------------------------------------------------


func test_a_structure_over_the_hard_budget_is_refused_with_a_reason() -> void:
	var big_doc := MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
	StructureGeometry.textured = false
	var plan := PackedVector2Array(
		[Vector2(-20, -10), Vector2(20, -10), Vector2(20, 10), Vector2(-20, 10)]
	)
	var parts := StructureGeometry.build_one(
		big_doc, Structure.make(1, "core:townhouse_trimmed", plan, 5)
	)
	assert_gt(int(parts.triangles), StructureGeometry.HARD_TRIANGLES)
	assert_true((parts.meshes as Array).is_empty(), "nothing is built")
	assert_string_contains(parts.problem, "over the limit")
	var nodes := AuthoredStructures.new()
	_map.add_child(nodes)
	nodes.apply({"structures": [parts]})
	assert_not_null(nodes.get_structure_node(1), "an empty node holds the id")
	assert_eq(nodes.top_y, -INF)


func test_a_starter_structure_is_well_under_the_soft_budget() -> void:
	for ref in StructureRecipes.core_refs():
		var plan := StructurePlacement.pin_plan(LibraryStructureStore.structure(ref))
		var parts := StructureGeometry.build_one(_doc, Structure.make(1, ref, plan, 5))
		assert_lt(int(parts.triangles), StructureGeometry.SOFT_TRIANGLES, ref)
		assert_eq(parts.warning, "")


# --- the nodes ---------------------------------------------------------------------------


func test_the_nodes_hold_a_structure_meshes_and_its_collision_body() -> void:
	_doc.structures.append(_structure())
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var node := structures.get_structure_node(1)
	assert_not_null(node)
	assert_not_null(node.get_node_or_null("wall_wood"), "walls")
	assert_not_null(node.get_node_or_null("roof_wood"), "a roof of its own")
	var body := node.get_node("Collision") as StaticBody3D
	assert_eq(body.get_meta(AuthoredStructures.STRUCTURE_META), 1)
	assert_eq(body.collision_layer, WaterSurface.TERRAIN_LAYER)
	assert_eq(AuthoredStructures.exclude_of(_map).size(), 1)
	assert_almost_eq(structures.top_y, 4.04, 0.05)
	var wall := node.get_node("wall_wood") as MeshInstance3D
	var roof := node.get_node("roof_wood") as MeshInstance3D
	assert_ne(wall.mesh.surface_get_material(0), roof.mesh.surface_get_material(0), "two materials")
	assert_not_null(structures.layout_of(1))
	assert_gt(structures.openings_of(1).size(), 0)
	assert_ne(structures.provenance_at(1, "roof_wood", 0), "", "a triangle knows its node")


func test_a_token_stands_on_the_roof() -> void:
	_doc.structures.append(_structure())
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	await get_tree().physics_frame
	var space := _map.get_world_3d().direct_space_state
	var landing := WaterSurface.landing_below(space, Vector3(0, 0, 0), 12.0)
	assert_ne(landing, Vector3.INF, "something to stand on")
	# The starters are handmade (wonk 0.7): the ridge sags in the middle where this ray lands, while
	# `top_y` is the highest point of the displaced roof, so the landing sits up to a hand below it.
	assert_between(landing.y, structures.top_y - 0.5, structures.top_y + 0.15, "on the ridge")
	var beside := WaterSurface.landing_below(space, Vector3(9, 0, 0), 12.0)
	assert_eq(beside, Vector3.INF, "the structure is the only ground in this test map")
	var skipped := WaterSurface.cast_down(
		space,
		Vector3(0, 0, 0),
		12.0,
		WaterSurface.TERRAIN_LAYER,
		AuthoredStructures.exclude_of(_map)
	)
	assert_true(skipped.is_empty(), "the tools that edit the ground see through it")


func test_scatter_is_cleared_under_the_footprint_and_nowhere_else() -> void:
	_doc.structures.append(_structure())
	var strips := StructureGeometry.clearance_crossings(_doc)
	assert_gt(strips.size(), 2)
	assert_eq(CrossingGeometry.clearance(strips, Vector2(0, 0)), 0.0, "under the house")
	assert_eq(CrossingGeometry.clearance(strips, Vector2(2.6, 1.6)), 0.0, "near a corner")
	assert_eq(CrossingGeometry.clearance(strips, Vector2(8, 8)), 1.0, "far away it grows")
	assert_gt(CrossingGeometry.clearance(strips, Vector2(5.5, 0)), 0.9, "beyond the margin")
	_doc.structures[0].footprint = _l_plan()
	var l_strips := StructureGeometry.clearance_crossings(_doc)
	assert_eq(CrossingGeometry.clearance(l_strips, Vector2(-2, 2)), 0.0, "the arm")
	assert_eq(CrossingGeometry.clearance(l_strips, Vector2(3, 2)), 1.0, "the notch is open")


func test_the_edit_reach_is_the_footprint_grown() -> void:
	var bounds := StructureGeometry.clear_bounds(_structure())
	assert_eq(bounds, Rect2(-3, -2, 6, 4).grow(StructureGeometry.REACH_M))


# --- edits: asynchronous, newest wins, cached --------------------------------------------


func test_an_edit_builds_on_a_worker_and_the_old_node_stays_until_it_is_ready() -> void:
	_doc.structures.append(_structure())
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var before := structures.get_structure_node(1)
	_doc.structures[0] = _doc.structures[0].copy()
	_doc.structures[0].footprint = _l_plan()
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 1, "queued")
	assert_eq(structures.get_structure_node(1), before, "the old building stays")
	assert_eq(structures.flush(), 1)
	assert_ne(structures.get_structure_node(1), before)
	assert_eq(structures.pending_count(), 0)
	assert_eq(structures.keys()[1], StructureGeometry.key_of(_doc, _doc.structures[0]))


func test_a_node_lands_by_itself_within_a_few_frames() -> void:
	_doc.structures.append(_structure())
	var structures := AuthoredStructures.new()
	structures.name = AuthoredStructures.NODE_NAME
	_map.add_child(structures)
	structures.refresh(_doc)
	assert_null(structures.get_structure_node(1), "nothing yet")
	await wait_for_signal(structures.built, 5.0)
	assert_not_null(structures.get_structure_node(1))
	assert_eq(structures.builds, 1)


func test_a_drag_faster_than_the_build_still_shows_the_building_move() -> void:
	# struct_perf: a courtyard takes 100 to 200 ms to build, and a handle drag previews at 10 Hz or
	# faster. Dropping the running build for every newer edit meant none ever landed (40 previews at
	# 10 Hz, 0 landings); now the newest edit waits behind the running build, so landings keep coming.
	var structure := Structure.make(1, "core:siheyuan", _plan(), 5)
	structure.footprint = PackedVector2Array(
		[Vector2(-7, -6), Vector2(7, -6), Vector2(7, 6), Vector2(-7, 6)]
	)
	_doc.structures.append(structure)
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var landed_before := structures.builds
	for i in 15:
		var next := _doc.structures[0].copy()
		next.footprint = PackedVector2Array(
			[Vector2(-7, -6), Vector2(7.0 + 0.1 * i, -6), Vector2(7.0 + 0.1 * i, 6), Vector2(-7, 6)]
		)
		_doc.structures[0] = next
		structures.refresh(_doc)
		await get_tree().create_timer(0.04).timeout
	assert_gt(structures.builds, landed_before, "a build landed while the drag was still going")
	assert_eq(structures.flush() >= 0, true)
	assert_eq(structures.pending_count(), 0, "nothing waits after a flush")
	assert_eq(
		structures.keys()[1],
		StructureGeometry.key_of(_doc, _doc.structures[0]),
		"the final state is the newest edit"
	)


func test_the_newest_edit_wins() -> void:
	_doc.structures.append(_structure())
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var first := _structure()
	first.footprint = _l_plan()
	var second := _structure("core:cottage_chimneyed")
	_doc.structures[0] = first
	structures.refresh(_doc)
	_doc.structures[0] = second
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 1, "the older build is forgotten")
	assert_eq(structures.flush(), 1, "only the newest lands")
	var parts := StructureGeometry.build_one(_doc, second)
	assert_eq(
		structures.get_structure_node(1).get_child_count(),
		(
			(parts.meshes as Array).size()
			+ (
				["ground", "props"]
				. filter(func(k: String) -> bool: return not parts.dressing[k].is_empty())
				. size()
			)
			+ 1
		),
		"the chimneyed cottage's meshes, its yard's two meshes and its body"
	)
	assert_eq(structures.keys()[1], StructureGeometry.key_of(_doc, second))


func test_an_edit_back_to_what_is_shown_cancels_a_build() -> void:
	var original := _structure()
	_doc.structures.append(original)
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	_doc.structures[0] = _structure("core:townhouse")
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 1)
	_doc.structures[0] = original.copy()
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 0, "no longer wanted")
	assert_eq(structures.flush(), 0)


func test_built_parts_are_cached_by_key_so_an_undo_is_immediate() -> void:
	var a := _structure()
	_doc.structures.append(a)
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	assert_eq(structures.cache_size(), 1, "a load seeds the cache")
	var b := _structure("core:townhouse")
	_doc.structures[0] = b
	structures.refresh(_doc)
	structures.flush()
	_doc.structures[0] = a.copy()
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 0, "from the cache")
	assert_eq(structures.last_rebuilt, 1)
	assert_not_null(structures.get_structure_node(1))


func test_a_refresh_changes_only_the_structures_that_moved() -> void:
	_doc.structures.append(_structure("core:cottage", 1, Vector2(-8, 0)))
	_doc.structures.append(_structure("core:townhouse", 2, Vector2(8, 0)))
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	structures.refresh(_doc)
	assert_eq(structures.last_rebuilt, 0)
	assert_eq(structures.pending_count(), 0, "a load seeds the keys")
	var kept := structures.get_structure_node(2)
	_raise(Vector2(-8, 0), 0.4)
	structures.refresh(_doc)
	assert_eq(structures.pending_count(), 1, "only the cottage over the raised ground")
	structures.flush()
	assert_eq(structures.get_structure_node(2), kept, "the other is the same node")
	_doc.structures.remove_at(0)
	structures.refresh(_doc)
	assert_null(structures.get_structure_node(1), "a removed structure's node goes")
	assert_almost_eq(structures.top_y, 6.84, 0.05, "the top follows what remains")


func test_a_flushed_build_equals_a_synchronous_one() -> void:
	var structure := _structure("core:cottage_chimneyed")
	var async_nodes := AuthoredStructures.new()
	_map.add_child(async_nodes)
	_doc.structures.append(structure)
	async_nodes.refresh(_doc)
	async_nodes.flush()
	var sync_nodes := AuthoredStructures.new()
	_map.add_child(sync_nodes)
	sync_nodes.refresh(_doc, false)
	assert_eq(
		_signature(async_nodes.get_structure_node(1)), _signature(sync_nodes.get_structure_node(1))
	)


func _signature(node: Node3D) -> String:
	var out := PackedStringArray()
	for child in node.get_children():
		if child is MeshInstance3D:
			var arrays := ((child as MeshInstance3D).mesh as ArrayMesh).surface_get_arrays(0)
			out.append("%s %s" % [child.name, str(hash(arrays[Mesh.ARRAY_VERTEX]))])
	return "|".join(out)


# --- the editor ----------------------------------------------------------------------------


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	var node := AuthoredScatter.create()
	node.name = MapSourceLoader.SCATTER_NODE
	node.budget = 1_000_000_000
	node.grow_seconds = 0.0
	_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	return editor


func test_the_editor_builds_undoes_and_redoes_the_nodes() -> void:
	var editor := _editor()
	var id := editor.structures.add(_structure("core:cottage", 9))
	assert_eq(id, 1)
	assert_eq(_nodes().pending_count(), 1, "the build is on a worker")
	assert_eq(_nodes().flush(), 1)
	assert_not_null(_nodes().get_structure_node(1))
	_history.undo()
	assert_null(_nodes().get_structure_node(1), "an undo removes the building")
	_history.redo()
	assert_eq(_nodes().pending_count(), 0, "a redo takes it from the cache")
	assert_not_null(_nodes().get_structure_node(1))
	assert_true(editor.structures.remove(1))
	assert_null(_nodes().get_structure_node(1))


func test_a_sculpt_under_a_structure_rebuilds_it_and_a_far_one_does_not() -> void:
	var editor := _editor()
	editor.structures.add(_structure())
	_nodes().flush()
	var before := _nodes().keys()
	_raise(Vector2(0, 0), 0.5)
	assert_true(editor.structures.follow(Rect2(-1, -1, 2, 2)).has("area"), "the edit reached it")
	_nodes().flush()
	assert_ne(_nodes().keys(), before, "and rebuilt it")
	assert_true(editor.structures.follow(Rect2(12, 12, 1, 1)).is_empty(), "a far edit reaches none")


func test_a_live_edit_builds_the_structure_on_a_peer() -> void:
	var editor := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	editor.structures.add(_structure())
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	var decoded := LiveEditCodec.decode(
		LiveEditCodec.encode(LiveEditCodec.op_of(entries[0], editor)), peer.document
	)
	LiveEditCodec.apply(decoded.op, peer)
	var peer_nodes := peer_map.get_node(AuthoredStructures.NODE_NAME) as AuthoredStructures
	peer_nodes.flush()
	_nodes().flush()
	assert_not_null(peer_nodes.get_structure_node(1), "the peer builds what the host laid")
	assert_eq(peer_nodes.keys(), _nodes().keys(), "the same key on both")


func test_the_scatter_snapshot_carries_the_structures_so_workers_clear_under_them() -> void:
	_doc.structures.append(_structure())
	var frozen := ScatterRegen.snapshot(_doc)
	assert_eq(frozen.structures.size(), 1)
	assert_eq(
		CrossingGeometry.clearance(StructureGeometry.clearance_crossings(frozen), Vector2.ZERO), 0.0
	)
	assert_eq(
		RockKeep.snapshot(_doc, _doc.heights, null).structures.size(), 1, "and the rock keeper"
	)


# --- panes ---------------------------------------------------------------------------------


func test_the_recipes_glazing_gives_panes_and_leaves_in_the_opening_role() -> void:
	var parts := StructureGeometry.build_one(_doc, _structure("core:townhouse"))
	var panes: Dictionary = {}
	for mesh: Dictionary in parts.meshes:
		if mesh.role == StructureLook.OPENING:
			panes = mesh
	assert_false(panes.is_empty(), "panes")
	assert_eq(panes.kind, StructureLook.GLASS_KIND)
	var seen := {}
	for tag: int in panes.tags:
		var path := String((parts.tag_table as PackedStringArray)[tag])
		assert_true(path.begins_with("glazing_"), path)
		seen[path.get_slice("/", path.get_slice_count("/") - 1).replace("panel", "leaf")] = true
	assert_true(seen.has("pane") and seen.has("leaf"), "a window pane and a door leaf: %s" % seen)
	var nodes := AuthoredStructures.new()
	_map.add_child(nodes)
	nodes.apply({"structures": [parts]})
	var instance := nodes.get_structure_node(1).get_node("opening_glass") as MeshInstance3D
	assert_eq(instance.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


# --- load, save, fingerprint -------------------------------------------------------------


func _town() -> void:
	_doc.structures.append(_structure("core:cottage", 1, Vector2(-8, -6)))
	_doc.structures.append(_structure("core:townhouse", 2, Vector2(2, -6)))
	var l := _structure("core:cottage_chimneyed", 3, Vector2(-6, 6))
	l.footprint = _l_plan()
	for k in l.footprint.size():
		l.footprint[k] += Vector2(-4, 6)
	_doc.structures.append(l)
	_doc.structures.append(_structure("core:stone_house", 4, Vector2(7, 6)))


func test_a_map_with_several_structures_loads_through_the_worker_prep() -> void:
	_town()
	var threaded := AuthoredLoadPrep.start(_doc).finish()
	var direct := AuthoredLoadPrep.compute(_doc)
	assert_true(threaded.has(AuthoredLoadPrep.STRUCTURES))
	assert_eq(
		(threaded[AuthoredLoadPrep.STRUCTURES].structures as Array).size(),
		4,
		"one parts per record"
	)
	for k in 4:
		assert_eq(
			StructureGeometry.digest_of(threaded[AuthoredLoadPrep.STRUCTURES].structures[k]),
			StructureGeometry.digest_of(direct[AuthoredLoadPrep.STRUCTURES].structures[k]),
			"workers build what the calling thread does"
		)
	var structures := MapSourceLoader.add_authored_structures(
		_map, _doc, threaded[AuthoredLoadPrep.STRUCTURES]
	)
	assert_not_null(structures)
	assert_eq(structures.get_child_count(), 4)
	assert_eq(structures.pending_count(), 0)
	var bare := Node3D.new()
	add_child_autofree(bare)
	assert_null(
		MapSourceLoader.add_authored_structures(bare, MapDocument.new()), "none without any"
	)
	assert_false(AuthoredLoadPrep.compute(MapDocument.new()).has(AuthoredLoadPrep.STRUCTURES))


func test_a_saved_map_reloads_to_the_same_fingerprint() -> void:
	_town()
	_scatter_node()
	var built := AuthoredStructures.create(_doc)
	_map.add_child(built)
	var before := MapFingerprint.of(_map, _doc)
	assert_eq((before.structures as Array).size(), 8, "a record and a node line per structure")
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK, "saved")
	var read := MapDocumentIO.read(SAVE_PATH)
	assert_eq((read["warnings"] as Array).size(), 0, str(read["warnings"]))
	var loaded: MapDocument = read["document"]
	assert_eq(loaded.structures.size(), 4)
	var other := Node3D.new()
	other.name = "LevelMap"
	add_child_autofree(other)
	var other_scatter := AuthoredScatter.create()
	other_scatter.name = MapSourceLoader.SCATTER_NODE
	other.add_child(other_scatter)
	other.add_child(AuthoredStructures.create(loaded, AuthoredLoadPrep.compute(loaded).structures))
	assert_eq(MapFingerprint.diff(before, MapFingerprint.of(other, loaded)), [] as Array[String])


func test_the_fingerprint_has_a_node_line_per_built_structure() -> void:
	_town()
	_scatter_node()
	var structures := AuthoredStructures.create(_doc)
	_map.add_child(structures)
	var nodes := 0
	for line: String in MapFingerprint.of(_map, _doc).structures:
		if line.begins_with("node Structure_"):
			nodes += 1
	assert_eq(nodes, 4)
	_doc.structures[0].footprint = _plan(Vector2(-7, -6))
	var moved := MapFingerprint.of(_map, _doc)
	structures.refresh(_doc)
	structures.flush()
	assert_ne(MapFingerprint.diff(moved, MapFingerprint.of(_map, _doc)), [] as Array[String])


# --- the footprint rules in the map reader -----------------------------------------------


func test_the_reader_refuses_self_crossing_and_sliver_footprints() -> void:
	var bowtie := _structure()
	bowtie.footprint = PackedVector2Array(
		[Vector2(-3, -2), Vector2(3, 2), Vector2(3, -2), Vector2(-3, 2)]
	)
	assert_ne(
		MapStructureIO.structure_problem(bowtie, _doc.extent_m()), "", "a bow tie crosses itself"
	)
	var sliver := _structure()
	sliver.footprint = PackedVector2Array([Vector2(0, 0), Vector2(6, 0), Vector2(6, 0.3)])
	assert_ne(
		MapStructureIO.structure_problem(sliver, _doc.extent_m()), "", "a sliver is too sharp"
	)
	var short := _structure()
	short.footprint = PackedVector2Array(
		[Vector2(0, 0), Vector2(0.3, 0), Vector2(0.3, 4), Vector2(0, 4)]
	)
	assert_ne(MapStructureIO.structure_problem(short, _doc.extent_m()), "", "an edge under 0.5 m")
	var backwards := _structure()
	backwards.footprint = PackedVector2Array(
		[Vector2(-3, 2), Vector2(3, 2), Vector2(3, -2), Vector2(-3, -2)]
	)
	assert_ne(
		MapStructureIO.structure_problem(backwards, _doc.extent_m()), "", "wound the wrong way"
	)
	var tiny := _structure()
	tiny.footprint = PackedVector2Array(
		[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	)
	assert_ne(MapStructureIO.structure_problem(tiny, _doc.extent_m()), "", "under 2 m2")
	var l := _structure()
	l.footprint = _l_plan()
	assert_eq(MapStructureIO.structure_problem(l, _doc.extent_m()), "", "an L is fine")
	assert_eq(MapStructureIO.structure_problem(_structure(), _doc.extent_m()), "")


func test_the_reader_skips_a_bad_footprint_with_a_warning_and_the_writer_refuses() -> void:
	var good := MapStructureIO.structure_json(_structure("core:cottage", 1))
	var bad := MapStructureIO.structure_json(_structure("core:cottage", 2))
	bad.footprint = [[-3.0, -2.0], [3.0, 2.0], [3.0, -2.0], [-3.0, 2.0]]
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapStructureIO.parse_list([good, bad], _doc.extent_m(), warn_log)
	assert_eq(list.size(), 1)
	assert_eq(warn_log.items.size(), 1)
	var crossed := _structure("core:cottage", 2)
	crossed.footprint = PackedVector2Array(
		[Vector2(-3, -2), Vector2(3, 2), Vector2(3, -2), Vector2(-3, 2)]
	)
	_doc.structures.append(crossed)
	assert_ne(MapStructureIO.problem(_doc), "", "the writer's check")
	assert_ne(MapDocumentIO.write(_doc, SAVE_PATH), OK, "a document with it does not save")
	assert_engine_error("not writing")


func test_ground_samples_read_the_ground_exactly_as_a_call_per_point_does() -> void:
	# struct_perf: ground_samples batches its reads (WaterGeometry.grounds_at); the key must not move,
	# so every sample equals ground_at() at the same point, on a slope with a bump, for a plan inside
	# the map, an L and a plan hanging off the map's edge (where the read clamps).
	_slope()
	_raise(Vector2(1, 1), 0.7)
	var edge := _plan(Vector2(_doc.extent_m().x * 0.5 - 1.0, 0.0))
	for plan: PackedVector2Array in [_plan(), _l_plan(), edge]:
		var points := StructureGeometry.sample_points(plan)
		var samples := StructureGeometry.ground_samples(_doc, plan)
		assert_gt(points.size(), 8)
		assert_eq(samples.size(), points.size())
		var mismatches := 0
		for i in points.size():
			if samples[i] != PackedFloat32Array([WaterGeometry.ground_at(_doc, points[i])])[0]:
				mismatches += 1
		assert_eq(mismatches, 0, "every sample is ground_at() at its point")
	assert_eq(StructureGeometry.ground_samples(_doc, PackedVector2Array()).size(), 0)
