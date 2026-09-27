extends GutTest

## AuthoredScatter (utils/authored_scatter.gd) and ScatterRegen (utils/scatter_regen.gd):
## per-cell scatter nodes for authored maps, rebuilt by brushes without touching other
## cells, creating materials, or re-growing instances that did not change. Uses the
## built-in palette's temperate forest assets. MultiMesh transforms read back as identity
## headless (AGENTS.md), so transform math is tested through the pure functions and
## nodes through identity, names and instance counts.

const BIOME := "temperate_forest_summer_s1"
const OAK := BIOME + "/Tree_Oak_summer_01"
const PINE := BIOME + "/Tree_Pine_summer_00"
const GRASS := BIOME + "/Grass_Short_summer_19"
const BOULDER := BIOME + "/Rock_Boulder_summer_04"
const BIG_BUDGET := 1_000_000_000

var _map: Node3D = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)


# --- helpers ------------------------------------------------------------------------


func _rows(points: Array, scale: float = 1.0) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	for p in points:
		rows.append_array([p.x, 0.0, p.y, 0.0, 0.0, 0.0, 1.0, scale, scale, scale])
	return rows


## `count` rows spread inside one 10 m cell.
func _cell_rows(cell: Vector2i, count: int, offset: float = 0.0) -> PackedFloat32Array:
	var points: Array = []
	for i in count:
		var local := Vector2(0.5 + fmod(i * 1.37 + offset, 9.0), 0.5 + fmod(i * 2.11, 9.0))
		points.append(Vector2(cell) * 10.0 + local)
	return _rows(points)


func _scatter(animate_grow: bool = true) -> AuthoredScatter:
	var scatter := AuthoredScatter.create()
	scatter.budget = BIG_BUDGET
	if not animate_grow:
		scatter.grow_seconds = 0.0
	_map.add_child(scatter)
	return scatter


## The settled and growing chunk nodes (transient shrink-out nodes left out).
func _chunk_names(scatter: AuthoredScatter) -> Array[String]:
	var names: Array[String] = []
	for child in scatter.get_children():
		if child is MultiMeshInstance3D and not String(child.name).contains(ScatterShrink.INFIX):
			names.append(String(child.name))
	names.sort()
	return names


func _flat_doc(cells: Vector2i) -> MapDocument:
	var doc := MapDocument.create_flat(cells, "", "", 11)
	doc.biome_ids = PackedStringArray([BIOME])
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	var density := PackedByteArray()
	density.resize(doc.sample_count())
	doc.biome_slots = slots
	doc.biome_density = density
	return doc


## Paints the biome at full density inside `rect` (world XZ).
func _paint(doc: MapDocument, rect: Rect2, value: int = 255) -> void:
	for z in doc.samples_z():
		for x in doc.samples_x():
			var world := doc.sample_to_world(Vector2(x, z))
			if rect.has_point(world):
				var i := doc.sample_index(x, z)
				doc.biome_slots[i] = 1
				doc.biome_density[i] = value


func _generate_all(doc: MapDocument) -> Dictionary:
	var bounds := Rect2(-doc.extent_m() * 0.5, doc.extent_m())
	var fields := ScatterGenerator.document_fields(doc, BIOME)
	return ScatterGenerator.generate(
		BIOME,
		PaletteLibrary.species(BIOME),
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		doc.map_seed,
		ScatterGenerator.cells_in_bounds(bounds),
		fields.bounds
	)


# --- pure functions -----------------------------------------------------------------


func test_node_names_are_always_cell_suffixed() -> void:
	assert_eq(
		AuthoredScatter.node_name_for(OAK, Vector2i(-1, 2)),
		"temperate_forest_summer_s1_Tree_Oak_summer_01_MultiMesh_c-1_2"
	)


func test_instance_order_is_a_permutation_and_depends_on_the_seed() -> void:
	var rows := _cell_rows(Vector2i.ZERO, 40)
	var keys := AuthoredScatter.row_keys(rows.to_byte_array().to_int32_array())
	var all := PackedInt32Array(range(40))
	var order := ScatterRows.instance_order(keys, all, "a_c0_0")
	var sorted := order.duplicate()
	sorted.sort()
	assert_eq(sorted, all)
	assert_ne(order, all, "a hash order is not the row order")
	assert_ne(order, ScatterRows.instance_order(keys, all, "a_c1_0"))
	assert_eq(order, ScatterRows.instance_order(keys, all, "a_c0_0"), "deterministic")


func test_instance_order_of_a_subset_keeps_the_relative_order() -> void:
	# Adding or removing instances must not reorder the others, or the density budget's
	# visible prefix would swap unchanged instances in and out on every rebuild.
	var rows := _cell_rows(Vector2i.ZERO, 60)
	var keys := AuthoredScatter.row_keys(rows.to_byte_array().to_int32_array())
	var full := ScatterRows.instance_order(keys, PackedInt32Array(range(60)), "s")
	var subset := PackedInt32Array()
	for i in range(0, 60, 3):
		subset.append(i)
	var expected := PackedInt32Array()
	for index in full:
		if index % 3 == 0:
			expected.append(index)
	assert_eq(ScatterRows.instance_order(keys, subset, "s"), expected)


func test_row_keys_identify_rows_by_content() -> void:
	var a := _rows([Vector2(1, 2), Vector2(3, 4)])
	var b := _rows([Vector2(3, 4), Vector2(1, 2), Vector2(5, 6)])
	var ka := AuthoredScatter.row_keys(a.to_byte_array().to_int32_array())
	var kb := AuthoredScatter.row_keys(b.to_byte_array().to_int32_array())
	assert_eq(ka[0], kb[1])
	assert_eq(ka[1], kb[0])
	assert_ne(ka[0], ka[1])
	var scaled := AuthoredScatter.row_keys(
		_rows([Vector2(1, 2)], 1.5).to_byte_array().to_int32_array()
	)
	assert_ne(scaled[0], ka[0], "a rescaled instance is a different instance")
	# A height edit moves Y and tilts the rotation; the instance stays the same one.
	var moved := a.duplicate()
	moved[1] = 2.5
	moved[3] = 0.1
	moved[6] = 0.99
	var km := AuthoredScatter.row_keys(moved.to_byte_array().to_int32_array())
	assert_eq(km[0], ka[0], "Y and rotation are not part of the identity")
	assert_ne(
		ka[0], AuthoredScatter.row_keys(_rows([Vector2(2, 1)]).to_byte_array().to_int32_array())[0]
	)
	assert_ne(
		ka[0],
		AuthoredScatter.row_keys(_rows([Vector2(1, 2.01)]).to_byte_array().to_int32_array())[0]
	)


func test_a_rebuild_that_only_moves_y_grows_nothing() -> void:
	var scatter := _scatter()
	var rows := _cell_rows(Vector2i.ZERO, 30)
	scatter.set_cells({Vector2i.ZERO: {GRASS: rows}}, false)
	var lifted := rows.duplicate()
	for b in range(0, lifted.size(), MapDocument.ROW_STRIDE):
		lifted[b + 1] = 1.25
	scatter.set_cells({Vector2i.ZERO: {GRASS: lifted}}, true)
	assert_false(scatter.is_growing(), "no instance grew back in")
	assert_eq(scatter.get_growing_nodes(Vector2i.ZERO, GRASS).size(), 0)
	var shrinking := scatter.get_children().filter(
		func(child: Node) -> bool: return String(child.name).contains(ScatterShrink.INFIX)
	)
	assert_eq(shrinking.size(), 0, "and none shrank out")


func test_move_rows_rewrites_instances_in_place() -> void:
	var scatter := _scatter()
	var rows := _cell_rows(Vector2i.ZERO, 12)
	scatter.set_cells({Vector2i.ZERO: {GRASS: rows}}, false)
	var node := scatter.get_cell_node(Vector2i.ZERO, GRASS)
	var multimesh := node.multimesh
	var moved := rows.duplicate()
	moved[1 + 3 * MapDocument.ROW_STRIDE] = 0.75
	assert_true(scatter.move_rows(Vector2i.ZERO, GRASS, moved, PackedInt32Array([3])))
	assert_eq(scatter.cell_rows(Vector2i.ZERO)[GRASS], moved, "the cell holds the new rows")
	assert_eq(scatter.get_cell_node(Vector2i.ZERO, GRASS), node, "same node")
	assert_eq(node.multimesh, multimesh, "same MultiMesh, transforms rewritten")
	assert_eq(multimesh.instance_count, 12)
	assert_false(
		scatter.move_rows(Vector2i.ZERO, GRASS, moved.slice(10), PackedInt32Array([0])),
		"different rows are refused"
	)
	assert_false(scatter.move_rows(Vector2i(5, 5), GRASS, moved, PackedInt32Array([0])))
	var expected: Transform3D = ScatterGlbUtils._row_to_transform(Array(moved.slice(30, 40)))
	assert_true(ScatterRows.row_transform(moved, 3).is_equal_approx(expected))


func test_transforms_from_rows_match_the_glb_row_conversion() -> void:
	var rows := PackedFloat32Array([1.5, 0.25, -2.0, 0.0, 0.3826834, 0.0, 0.9238795, 1.2, 0.8, 1.1])
	rows.append_array([4.0, 0.0, 5.0, 0.0, 0.0, 0.0, 2.0, 1.0, 1.0, 1.0])
	var got := ScatterRows.transforms_from_rows(rows, PackedInt32Array([1, 0]))
	assert_eq(got.size(), 2)
	var expected_first: Transform3D = ScatterGlbUtils._row_to_transform(Array(rows.slice(10, 20)))
	var expected_second: Transform3D = ScatterGlbUtils._row_to_transform(Array(rows.slice(0, 10)))
	assert_true(got[0].is_equal_approx(expected_first))
	assert_true(got[1].is_equal_approx(expected_second))


func test_split_by_cell_groups_rows_by_origin_cell() -> void:
	var rows := _rows([Vector2(1, 1), Vector2(12, 1), Vector2(2, 3), Vector2(-0.5, 1)])
	var split := ScatterRegen.split_by_cell(rows)
	assert_eq(split.size(), 3)
	assert_eq((split[Vector2i(0, 0)] as PackedFloat32Array).size(), 20)
	assert_eq((split[Vector2i(1, 0)] as PackedFloat32Array).size(), 10)
	assert_eq((split[Vector2i(-1, 0)] as PackedFloat32Array).size(), 10)


func test_merge_cell_replaces_only_the_regenerated_assets() -> void:
	var existing := {"a": _rows([Vector2(1, 1)]), "b": _rows([Vector2(2, 2)])}
	var fresh := {"b": PackedFloat32Array(), "c": _rows([Vector2(3, 3)])}
	var merged := ScatterRegen.merge_cell(existing, PackedStringArray(["b", "c"]), fresh)
	assert_eq(merged.keys(), ["a", "c"])
	assert_eq(merged["a"], existing["a"])


func test_species_reach_is_zero_for_unrelated_species_and_covers_relation_chains() -> void:
	var plan := ScatterPlan.build(BIOME, PaletteLibrary.species(BIOME), 3)
	var reach := ScatterGenerator.species_reach(plan)
	var by_key := {}
	for s in reach.size():
		by_key[plan.species[s].key] = reach[s]
	assert_eq(by_key["oak"], 0.0, "large trees depend only on their own point")
	assert_eq(by_key["grass"], 0.0)
	# bluebell is near bush (2.5 m + 2.0 m transition, through its clump parents) and bush
	# keeps clear of the trees, so the chain reaches further than the relation alone.
	assert_gt(by_key["bluebell"], 4.5 + by_key["bush"])
	assert_gt(by_key["bush"], 0.0, "medium species keep clear of large ones")


func test_build_chunk_returns_the_node_it_adds_and_nothing_for_no_transforms() -> void:
	var parent: Node3D = autofree(Node3D.new())
	var none: Array[Transform3D] = []
	assert_null(ScatterGlbUtils.build_chunk(parent, BoxMesh.new(), "Box", none))
	assert_eq(parent.get_child_count(), 0)
	var one: Array[Transform3D] = [Transform3D.IDENTITY]
	var node := ScatterGlbUtils.build_chunk(parent, BoxMesh.new(), "Box", one, "grass", "_c0_0")
	assert_eq(node.get_parent(), parent)
	assert_eq(String(node.name), "Box_MultiMesh_c0_0")
	assert_eq(node.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_eq(node.multimesh.instance_count, 1)


# --- scheduler (pure bookkeeping) ------------------------------------------------------


func _regen(doc: MapDocument) -> ScatterRegen:
	var regen := ScatterRegen.for_document(doc)
	regen.set_biome(BIOME, PaletteLibrary.species(BIOME))
	return regen


func test_a_request_dirties_the_touched_cells_for_all_species_and_the_halo_for_some() -> void:
	var regen := _regen(_flat_doc(Vector2i(40, 40)))
	var cells := regen.request_region(Rect2(1.0, 1.0, 2.0, 2.0))
	assert_true(Vector2i(0, 0) in cells)
	assert_true(Vector2i(-1, -1) in cells, "the relation halo reaches the next cell")
	assert_false(Vector2i(2, 2) in cells, "nothing reaches 17 m")
	var job := regen.take_job(100)
	var work: Dictionary = job.work[BIOME]
	var plan := ScatterPlan.build(BIOME, PaletteLibrary.species(BIOME), 11)
	for s in plan.species.size():
		var species_cells: Array = work.cells_by_species[s]
		assert_true(Vector2i(0, 0) in species_cells, "every species in the painted cell")
		if plan.species[s].key == "oak":
			assert_false(Vector2i(-1, -1) in species_cells, "no halo for a species without one")


func test_a_newer_request_discards_an_older_in_flight_job() -> void:
	var regen := _regen(_flat_doc(Vector2i(40, 40)))
	regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0))
	var first := regen.take_job(100)
	regen.request_region(Rect2(2.0, 2.0, 1.0, 1.0))
	var second := regen.take_job(100)
	assert_eq(regen.accept(second).size(), (second.cells as Array).size())
	assert_eq(regen.accept(first), [] as Array[Vector2i], "the stale job is dropped")


func test_a_stale_job_keeps_its_work_for_the_next_one() -> void:
	var regen := _regen(_flat_doc(Vector2i(40, 40)))
	# First request: a big dab dirties every species in cell (0, 0).
	regen.request_region(Rect2(1.0, 1.0, 8.0, 8.0))
	var first := regen.take_job(100)
	# Second: only the halo of a far dab reaches (0, 0), for the halo species alone.
	regen.request_region(Rect2(18.0, 5.0, 0.5, 0.5))
	assert_eq(regen.accept(first).has(Vector2i(0, 0)), false)
	var second := regen.take_job(100)
	var work: Dictionary = second.work[BIOME]
	var plan := ScatterPlan.build(BIOME, PaletteLibrary.species(BIOME), 11)
	for s in plan.species.size():
		assert_true(
			Vector2i(0, 0) in (work.cells_by_species[s] as Array),
			"species %s from the dropped job is carried over" % plan.species[s].key
		)
	assert_true(regen.accept(second).has(Vector2i(0, 0)))


func test_queued_requests_for_one_cell_coalesce() -> void:
	var regen := _regen(_flat_doc(Vector2i(40, 40)))
	for i in 5:
		regen.request_region(Rect2(3.0, 3.0, 1.0, 1.0))
	var cells := {}
	while regen.has_pending():
		for cell in regen.take_job(1).cells:
			assert_false(cells.has(cell), "cell %s queued twice" % cell)
			cells[cell] = true


func test_regenerating_a_dab_with_its_halo_matches_regenerating_the_whole_map() -> void:
	# The halo is sufficient: rows outside the dirtied cells cannot change, and inside them
	# the regenerated species reproduce a whole-map generation of the edited document.
	# Filling a hole in painted forest changes relation-driven instances in the next cell
	# over (checked below), so the halo is exercised, not just the painted cells.
	var dab := Rect2(1.0, 1.0, 5.0, 5.0)
	var after := _flat_doc(Vector2i(20, 20))
	_paint(after, Rect2(-16.0, -16.0, 32.0, 32.0))
	var before := _flat_doc(Vector2i(20, 20))
	before.biome_slots = after.biome_slots.duplicate()
	before.biome_density = after.biome_density.duplicate()
	_paint(before, dab, 0)
	var old_cells := AuthoredScatter.rows_by_cell_of(_generate_all(before))
	var new_cells := AuthoredScatter.rows_by_cell_of(_generate_all(after))
	var painted_cells := ScatterGenerator.cells_in_bounds(dab.grow(0.3))
	var halo_changed := false
	for cell in new_cells:
		if not cell in painted_cells and old_cells.get(cell, {}) != new_cells[cell]:
			halo_changed = true
	assert_true(halo_changed, "the scenario changes a cell outside the painted ones")

	var regen := _regen(after)
	regen.request_region(dab)
	var patched := old_cells.duplicate()
	while regen.has_pending():
		var job := regen.take_job(4)
		var result := ScatterRegen.run(after, job.work)
		for cell in regen.accept(job):
			patched[cell] = ScatterRegen.merge_cell(
				old_cells.get(cell, {}), job.regenerated[cell], result.rows_by_cell.get(cell, {})
			)
	var all_cells := {}
	all_cells.merge(patched)
	all_cells.merge(new_cells)
	for cell in all_cells:
		var got: Dictionary = patched.get(cell, {})
		var want: Dictionary = new_cells.get(cell, {})
		assert_eq(got.keys().size(), want.keys().size(), "assets in %s" % cell)
		for asset_id in want:
			assert_eq(got.get(asset_id), want[asset_id], "%s in %s" % [asset_id, cell])


# --- nodes ---------------------------------------------------------------------------


func test_build_all_builds_one_suffixed_node_per_asset_and_cell() -> void:
	var scatter := _scatter()
	var rows: Dictionary = {
		OAK: _cell_rows(Vector2i(0, 0), 3), GRASS: _cell_rows(Vector2i(1, 0), 5)
	}
	rows[GRASS].append_array(_cell_rows(Vector2i(-1, 0), 4))
	scatter.build_all(rows)
	assert_eq(
		_chunk_names(scatter),
		[
			AuthoredScatter.node_name_for(GRASS, Vector2i(-1, 0)),
			AuthoredScatter.node_name_for(GRASS, Vector2i(1, 0)),
			AuthoredScatter.node_name_for(OAK, Vector2i(0, 0)),
		]
	)
	assert_eq(scatter.get_cell_node(Vector2i(1, 0), GRASS).multimesh.instance_count, 5)
	assert_eq(scatter.get_cell_node(Vector2i(0, 0), OAK).get_meta("wind_foliage_category"), "tree")
	assert_false(scatter.is_growing(), "a load builds in place")


func test_build_all_equals_set_cells_over_every_cell() -> void:
	var rows: Dictionary = {
		OAK: _cell_rows(Vector2i(0, 0), 3), GRASS: _cell_rows(Vector2i(1, 0), 5)
	}
	rows[BOULDER] = _cell_rows(Vector2i(0, 1), 2)
	var loaded := _scatter()
	loaded.build_all(rows)
	var painted := _scatter()
	painted.set_cells(AuthoredScatter.rows_by_cell_of(rows), false)
	assert_eq(_chunk_names(loaded), _chunk_names(painted))
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
		for asset_id in rows:
			var a := loaded.get_cell_node(cell, asset_id)
			var b := painted.get_cell_node(cell, asset_id)
			assert_eq(a == null, b == null)
			if a != null:
				assert_eq(a.multimesh.instance_count, b.multimesh.instance_count)
	assert_eq(loaded.rows_by_asset(), painted.rows_by_asset())


func test_rebuilding_one_cell_leaves_the_others_untouched() -> void:
	var scatter := _scatter()
	var a := Vector2i(0, 0)
	var b := Vector2i(1, 0)
	scatter.build_all({OAK: _cell_rows(a, 3) + _cell_rows(b, 4), GRASS: _cell_rows(b, 6)})
	var b_oak := scatter.get_cell_node(b, OAK)
	var b_grass := scatter.get_cell_node(b, GRASS)
	var b_oak_mesh := b_oak.multimesh
	var b_grass_mesh := b_grass.multimesh
	var a_oak := scatter.get_cell_node(a, OAK)

	scatter.set_cells({a: {OAK: _cell_rows(a, 5, 0.3), GRASS: _cell_rows(a, 2)}})
	scatter.complete_growth()

	assert_same(scatter.get_cell_node(b, OAK), b_oak)
	assert_same(scatter.get_cell_node(b, GRASS), b_grass)
	assert_same(b_oak.multimesh, b_oak_mesh, "cell B's MultiMesh was not rebuilt")
	assert_same(b_grass.multimesh, b_grass_mesh)
	assert_eq(b_oak.multimesh.instance_count, 4)
	assert_eq(b_grass.multimesh.instance_count, 6)
	assert_same(scatter.get_cell_node(a, OAK), a_oak, "the rebuilt cell keeps its node")
	assert_eq(a_oak.multimesh.instance_count, 5)
	assert_eq(String(a_oak.name), AuthoredScatter.node_name_for(OAK, a))


func test_names_stay_stable_across_rebuilds() -> void:
	var scatter := _scatter()
	var cell := Vector2i(-2, 3)
	scatter.set_cells({cell: {OAK: _cell_rows(cell, 3)}})
	scatter.complete_growth()
	var first := _chunk_names(scatter)
	scatter.set_cells({cell: {OAK: _cell_rows(cell, 6, 0.7)}})
	scatter.complete_growth()
	scatter.set_cells({cell: {OAK: _cell_rows(cell, 2)}})
	scatter.complete_growth()
	assert_eq(_chunk_names(scatter), first)
	assert_eq(first, [AuthoredScatter.node_name_for(OAK, cell)])


func test_an_emptied_cell_frees_its_nodes() -> void:
	var scatter := _scatter()
	var cell := Vector2i(0, 0)
	scatter.build_all({OAK: _cell_rows(cell, 3)})
	scatter.set_cells({cell: {}})
	assert_null(scatter.get_cell_node(cell, OAK))
	assert_eq(_chunk_names(scatter), [] as Array[String])
	assert_eq(scatter.rows_by_asset(), {} as Dictionary[String, PackedFloat32Array])


func test_removed_instances_shrink_out_instead_of_vanishing() -> void:
	var scatter := _scatter()
	var cell := Vector2i(1, 1)
	scatter.build_all({OAK: _cell_rows(cell, 5), BOULDER: _cell_rows(cell, 2, 0.3)})
	scatter.set_cells({cell: {OAK: _cell_rows(cell, 2)}})
	var shrinking := {}
	for child in scatter.get_children():
		if String(child.name).contains(ScatterShrink.INFIX):
			var node := child as MultiMeshInstance3D
			shrinking[String(node.name).get_slice(ScatterShrink.INFIX, 0)] = node
	var oak_name := AuthoredScatter.node_name_for(OAK, cell)
	var boulder_name := AuthoredScatter.node_name_for(BOULDER, cell)
	assert_true(shrinking.has(oak_name), "the three removed oaks shrink")
	assert_eq((shrinking[oak_name] as MultiMeshInstance3D).multimesh.instance_count, 3)
	assert_true(shrinking.has(boulder_name), "the removed boulders sink")
	assert_same(
		(shrinking[oak_name] as MultiMeshInstance3D).multimesh.mesh,
		scatter.get_cell_node(cell, OAK).multimesh.mesh,
		"the shrink node shares the species mesh (no new materials)"
	)
	scatter.set_cells({cell: {OAK: _cell_rows(cell, 1)}}, false)
	var after := 0
	for child in scatter.get_children():
		if String(child.name).contains(ScatterShrink.INFIX):
			after += 1
	assert_eq(after, shrinking.size(), "an unanimated rebuild removes at once")


func test_worker_snapshots_do_not_share_the_document_masks() -> void:
	var doc := MapDocument.create_flat(Vector2i(4, 4), "grass", "v", 1)
	var mask := PackedByteArray()
	mask.resize(doc.sample_count())
	doc.biome_slots = mask
	doc.biome_density = mask.duplicate()
	doc.biome_ids = PackedStringArray([BIOME])
	var snapshot := AuthoredScatter._snapshot(doc)
	doc.biome_density[5] = 200
	doc.biome_slots[5] = 1
	doc.biome_ids.append("another")
	assert_eq(snapshot.biome_density[5], 0, "a brush write after dispatch is not seen")
	assert_eq(snapshot.biome_slots[5], 0)
	assert_eq(snapshot.biome_ids.size(), 1)


func test_rebuilds_create_no_materials_for_resolved_species() -> void:
	var scatter := _scatter()
	var added: Array = []
	scatter.species_added.connect(
		func(materials: Array[ShaderMaterial]) -> void: added.append(materials)
	)
	scatter.build_all({OAK: _cell_rows(Vector2i(0, 0), 3), GRASS: _cell_rows(Vector2i(0, 0), 3)})
	assert_eq(added.size(), 2, "one emission per resolved wind species")
	var oak_materials := scatter.species_materials(OAK)
	var mesh := scatter.get_cell_node(Vector2i(0, 0), OAK).multimesh.mesh
	var surfaces: Array[Material] = []
	for i in mesh.get_surface_count():
		surfaces.append(mesh.surface_get_material(i))

	scatter.set_cells({Vector2i(0, 0): {OAK: _cell_rows(Vector2i(0, 0), 7, 0.4)}})
	scatter.set_cells({Vector2i(3, 3): {OAK: _cell_rows(Vector2i(3, 3), 2)}})
	scatter.complete_growth()

	assert_eq(added.size(), 2, "no new species, no new materials")
	assert_eq(scatter.species_materials(OAK), oak_materials)
	for cell in [Vector2i(0, 0), Vector2i(3, 3)]:
		var cell_mesh := scatter.get_cell_node(cell, OAK).multimesh.mesh
		assert_same(cell_mesh, mesh, "every chunk shares the species' one mesh")
		for i in cell_mesh.get_surface_count():
			assert_same(cell_mesh.surface_get_material(i), surfaces[i])


func test_the_density_budget_is_reapplied_after_a_rebuild() -> void:
	var scatter := _scatter()
	scatter.build_all({GRASS: _cell_rows(Vector2i(0, 0), 20)})
	scatter.set_cells({Vector2i(1, 0): {GRASS: _cell_rows(Vector2i(1, 0), 30)}}, false)
	for cell in [Vector2i(0, 0), Vector2i(1, 0)]:
		var multimesh := scatter.get_cell_node(cell, GRASS).multimesh
		assert_eq(multimesh.visible_instance_count, multimesh.instance_count, "under budget")

	var per_instance := FoliageBudget.primitives_per_instance(
		scatter.get_cell_node(Vector2i(0, 0), GRASS).multimesh.mesh
	)
	scatter.budget = per_instance * 25
	scatter.set_cells({Vector2i(2, 0): {GRASS: _cell_rows(Vector2i(2, 0), 10)}}, false)
	var shown := 0
	for cell in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]:
		var multimesh := scatter.get_cell_node(cell, GRASS).multimesh
		assert_ne(multimesh.visible_instance_count, -1)
		shown += multimesh.visible_instance_count
	# 60 instances over a 25-instance budget: the global allocation (floor of 25.0, which
	# float rounding can put at 24) spans the untouched cells too.
	assert_between(shown, 24, 25)


func test_under_budget_rebuilds_skip_the_global_replan_but_stay_correct() -> void:
	var scatter := _scatter()
	scatter.build_all({GRASS: _cell_rows(Vector2i(0, 0), 20)})
	var untouched := scatter.get_cell_node(Vector2i(0, 0), GRASS).multimesh
	untouched.visible_instance_count = 3  # a marker the fast path must leave alone
	scatter.set_cells({Vector2i(1, 0): {GRASS: _cell_rows(Vector2i(1, 0), 30)}})
	assert_eq(untouched.visible_instance_count, 3, "no map-wide re-plan while under budget")
	for node in scatter.get_growing_nodes(Vector2i(1, 0), GRASS):
		assert_eq(node.multimesh.visible_instance_count, node.multimesh.instance_count)
	scatter.complete_growth()
	var grown := scatter.get_cell_node(Vector2i(1, 0), GRASS).multimesh
	assert_eq(grown.visible_instance_count, 30)


func test_a_density_change_reaches_the_scatter_through_its_group() -> void:
	var scatter := _scatter()
	get_tree().call_group(AuthoredScatter.GROUP, "set_budget", 1234)
	assert_eq(scatter.budget, 1234)


func test_new_instances_grow_in_and_unchanged_ones_stay_put() -> void:
	var scatter := _scatter()
	var cell := Vector2i(0, 0)
	var old_rows := _cell_rows(cell, 6)
	scatter.build_all({OAK: old_rows})
	var settled := scatter.get_cell_node(cell, OAK)
	var extra := _rows([Vector2(9.2, 9.3), Vector2(9.6, 0.2)])
	scatter.set_cells({cell: {OAK: old_rows + extra}})

	assert_same(scatter.get_cell_node(cell, OAK), settled)
	assert_eq(settled.multimesh.instance_count, 6, "unchanged instances are not re-grown")
	var growing := scatter.get_growing_nodes(cell, OAK)
	assert_eq(growing.size(), 1)
	assert_eq(growing[0].multimesh.instance_count, 2)
	assert_eq(growing[0].get_instance_shader_parameter(AuthoredScatter.GROW_UNIFORM), 0.0)

	scatter.complete_growth()
	assert_false(scatter.is_growing())
	assert_eq(settled.multimesh.instance_count, 8)
	assert_eq(_chunk_names(scatter), [AuthoredScatter.node_name_for(OAK, cell)])


func test_a_rebuild_mid_growth_keeps_the_running_grow_in() -> void:
	var scatter := _scatter()
	var cell := Vector2i(0, 0)
	var base := _cell_rows(cell, 4)
	scatter.build_all({OAK: base})
	var first := _rows([Vector2(9.1, 9.1)])
	scatter.set_cells({cell: {OAK: base + first}})
	var growing := scatter.get_growing_nodes(cell, OAK)[0]
	var second := _rows([Vector2(9.5, 0.5)])
	scatter.set_cells({cell: {OAK: base + first + second}})
	var nodes := scatter.get_growing_nodes(cell, OAK)
	assert_eq(nodes.size(), 2)
	assert_same(nodes[0], growing, "the first grow-in carries on, not restarted")
	assert_eq(scatter.get_cell_node(cell, OAK).multimesh.instance_count, 4)
	scatter.complete_growth()
	assert_eq(scatter.get_cell_node(cell, OAK).multimesh.instance_count, 6)


func test_species_without_wind_rise_out_of_the_ground() -> void:
	var scatter := _scatter()
	var cell := Vector2i(0, 0)
	scatter.set_cells({cell: {BOULDER: _cell_rows(cell, 3)}})
	var growing := scatter.get_growing_nodes(cell, BOULDER)
	assert_eq(growing.size(), 1)
	assert_lt(growing[0].position.y, 0.0, "starts below the ground")
	scatter.complete_growth()
	var settled := scatter.get_cell_node(cell, BOULDER)
	assert_eq(settled.position, Vector3.ZERO)
	assert_eq(settled.multimesh.instance_count, 3)


func test_growth_finishes_by_itself() -> void:
	var scatter := _scatter()
	scatter.grow_seconds = 0.05
	scatter.set_cells({Vector2i(0, 0): {GRASS: _cell_rows(Vector2i(0, 0), 5)}})
	assert_true(scatter.is_growing())
	for _frame in 60:
		if not scatter.is_growing():
			break
		await get_tree().create_timer(0.02).timeout
	assert_false(scatter.is_growing())
	assert_eq(scatter.get_cell_node(Vector2i(0, 0), GRASS).multimesh.instance_count, 5)


# --- mid-session species bookkeeping -----------------------------------------------------


func test_a_species_first_painted_mid_session_gets_the_load_time_bookkeeping() -> void:
	# The game at load: occlusion fade set up, Antialiasing off (no-AA shader), wind
	# materials cached for re-tuning. GameMap and its controller are wired by hand, the way
	# GameMap._ready would, without the scene.
	var fade := OcclusionFadeManager.new()
	add_child_autofree(fade)
	var game_map: GameMap = autofree(GameMap.new())
	game_map.map_container = _map
	game_map.occlusion_fade = fade
	var effects: VisualEffectsController = autofree(VisualEffectsController.new())
	effects._game_map = game_map
	effects._foliage_antialiasing_level = Viewport.MSAA_DISABLED
	var environment := LevelEnvironmentManager.new()

	var scatter := _scatter()
	scatter.build_all({PINE: _cell_rows(Vector2i(0, 0), 2)})
	fade.setup(null, _map, autofree(Node3D.new()))
	effects.apply_foliage_antialiasing()
	environment.store_wind_materials(_map)
	environment.apply_foliage_overrides({"tree_sway_speed": 2.5})
	scatter.species_added.connect(effects.adopt_foliage_materials)
	scatter.species_added.connect(environment.add_wind_materials)

	scatter.set_cells({Vector2i(1, 0): {OAK: _cell_rows(Vector2i(1, 0), 2)}})

	var materials := scatter.species_materials(OAK)
	assert_gt(materials.size(), 0)
	for material in materials:
		assert_eq(material.shader, WindFoliage.get_shader_no_aa(), "AA variant")
		assert_true(material in fade._tree_materials, "occlusion fade")
		assert_true(material.get_shader_parameter("enable_occlusion"))
		assert_true(material in environment._wind_materials["tree"], "wind re-tuning")
		assert_eq(material.get_shader_parameter("sway_speed"), 2.5, "current wind tuning")
	for material in scatter.species_materials(PINE):
		assert_true(material in fade._tree_materials, "load-time species are unaffected")
	fade.clear()


func test_occlusion_registration_ignores_grass_and_waits_for_setup() -> void:
	var fade := OcclusionFadeManager.new()
	add_child_autofree(fade)
	var tree := ShaderMaterial.new()
	tree.shader = WindFoliage.get_shader()
	tree.set_meta("wind_category", "tree")
	var grass := ShaderMaterial.new()
	grass.shader = WindFoliage.get_shader()
	grass.set_meta("wind_category", "grass")
	var materials: Array[ShaderMaterial] = [tree, grass]
	fade.register_tree_materials(materials)
	assert_eq(fade._tree_materials.size(), 0, "not set up yet")
	fade.setup(null, _map, autofree(Node3D.new()))
	fade.register_tree_materials(materials)
	assert_eq(fade._tree_materials, [tree] as Array[ShaderMaterial])
	fade.clear()


# --- worker threads ---------------------------------------------------------------------


func test_brush_regeneration_runs_on_workers_and_matches_the_generator() -> void:
	var doc := _flat_doc(Vector2i(20, 20))
	var scatter := _scatter(false)
	scatter.attach_document(doc)
	var dab := Rect2(-4.0, -4.0, 6.0, 6.0)
	_paint(doc, dab)
	scatter.request_region(dab)
	assert_true(scatter.is_regenerating())
	var waited := 0
	while scatter.is_regenerating() and waited < 400:
		await get_tree().process_frame
		waited += 1
	assert_false(scatter.is_regenerating(), "jobs finished within the bounded wait")
	var expected := AuthoredScatter.rows_by_cell_of(_generate_all(doc))
	for cell in expected:
		assert_eq(scatter.cell_rows(cell), expected[cell], "cell %s" % cell)
	assert_gt(scatter.last_worker_usec, 0)
