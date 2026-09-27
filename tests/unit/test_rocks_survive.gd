extends GutTest

## Rocks survive terrain changes (RockKeep, P3-7, the user's decision of 2026-09-27): a
## sculpt stroke no longer removes the rocks under it. Every drawn rock the stroke-end
## regeneration would remove becomes a placed prop in the stroke's history entry, tilted
## (capped) and bedded; everything else follows the rules; nothing is added; a second stroke
## never grows a twin inside a kept rock; undo, redo and a save round trip restore exactly.
## Uses the installed palette's alpine meadow (boulders, rocks, stones, dwarf pines).
## MultiMesh transforms read back as identity headless, so rows are checked, not nodes.

const BIOME := "alpine_meadow_summer_s1"
## The painted band the strokes run through (map XZ metres).
const PAINTED := Rect2(-11.0, -8.0, 22.0, 16.0)

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null
var _rocks: Dictionary = {}


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(24, 24), "grass", "v", 21)
	_doc.biome_ids = PackedStringArray([BIOME])
	var slots := PackedByteArray()
	slots.resize(_doc.sample_count())
	var density := PackedByteArray()
	density.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			if PAINTED.has_point(_doc.sample_to_world(Vector2(x, z))):
				slots[_doc.sample_index(x, z)] = 1
				density[_doc.sample_index(x, z)] = 255
	_doc.biome_slots = slots
	_doc.biome_density = density
	_rocks = RockKeep.rock_assets(_doc.biome_ids, PaletteLibrary.DEFAULT_ROOT)


func _editor() -> AuthoringEditor:
	_map.add_child(AuthoredTerrain.create(_doc))
	for node_name in [MapSourceLoader.SCATTER_NODE, MapSourceLoader.PROPS_NODE]:
		var node := AuthoredScatter.create()
		node.name = node_name
		node.budget = 1_000_000_000
		node.grow_seconds = 0.0
		_map.add_child(node)
	var editor := AuthoringEditor.create(_doc, _map, _history)
	editor.scatter.attach_document(_doc)
	editor.scatter.set_cells(_generated(PackedFloat32Array()), false)
	return editor


## The whole map's scatter as the document (with `blockers`) generates it: cell -> rows.
func _generated(blockers: PackedFloat32Array) -> Dictionary:
	var fields := ScatterGenerator.document_fields(
		_doc,
		BIOME,
		Rect2(),
		PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
		PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	)
	var species := PaletteLibrary.species(BIOME)
	var cells := ScatterGenerator.cells_in_bounds(fields.bounds)
	var cells_by_species: Array = []
	for _s in species.size():
		cells_by_species.append(cells)
	var rows := ScatterGenerator.generate_species_cells(
		BIOME,
		species,
		fields.density_at,
		fields.height_at,
		fields.normal_at,
		_doc.map_seed,
		cells_by_species,
		fields.bounds,
		fields.species_density_at,
		blockers
	)
	return AuthoredScatter.rows_by_cell_of(rows)


## A tier stroke (one tier up, 4 m brush) across the painted band.
func _tier(editor: AuthoringEditor) -> void:
	assert_true(editor.begin_height_stroke(HeightBrush.TIER, _doc.tier_height_m))
	for k in 30:
		var x := -7.0 + k * 0.5
		editor.stroke_dab(Vector3(x - 0.5, 0, -1), Vector3(x, 0, -1), 4.0, 0.1)
		editor.flush()
	assert_true(editor.end_stroke())


## Waits for the regeneration to land (bounded).
func _settle(editor: AuthoringEditor) -> void:
	editor.finish_height_work()
	var waited := 0
	while editor.scatter.is_regenerating() and waited < 900:
		await get_tree().process_frame
		waited += 1
	assert_false(editor.scatter.is_regenerating(), "regeneration landed")


## Every cell of `scatter` against `expected` (cell -> rows); returns the mismatches.
func _mismatches(scatter: AuthoredScatter, expected: Dictionary) -> int:
	var cells := {}
	for cell in expected:
		cells[cell] = true
	for cell in ScatterGenerator.cells_in_bounds(Rect2(-_doc.extent_m() * 0.5, _doc.extent_m())):
		cells[cell] = true
	var bad := 0
	for cell in cells:
		if not _same(scatter.cell_rows(cell), expected.get(cell, {})):
			bad += 1
	return bad


func _same(a: Dictionary, b: Dictionary) -> bool:
	var keys := {}
	keys.merge(a)
	keys.merge(b)
	for asset_id in keys:
		if a.get(asset_id, PackedFloat32Array()) != b.get(asset_id, PackedFloat32Array()):
			return false
	return true


func _keys(rows: PackedFloat32Array) -> PackedInt64Array:
	return ScatterRows.row_keys(rows.to_byte_array().to_int32_array())


## asset id -> {key: true} of every rock row in cell rows `by_cell`.
func _rock_keys(by_cell: Dictionary) -> Dictionary:
	var out := {}
	for cell in by_cell:
		for asset_id in by_cell[cell]:
			if _rocks.has(asset_id):
				var known: Dictionary = out.get(asset_id, {})
				for key in _keys(by_cell[cell][asset_id]):
					known[key] = true
				out[asset_id] = known
	return out


func _cells_of(scatter: AuthoredScatter) -> Dictionary:
	return AuthoredScatter.rows_by_cell_of(scatter.rows_by_asset())


func _count(rows_by_asset: Dictionary) -> int:
	var total := 0
	for asset_id in rows_by_asset:
		@warning_ignore("integer_division")
		total += (rows_by_asset[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
	return total


# --- pure rules -------------------------------------------------------------------------


func test_the_tilt_cap_keeps_yaw_and_stops_at_the_cap() -> void:
	var steep := Vector3(1.0, 0.25, 0.0).normalized()
	var capped := RockKeep.capped_up(steep, RockKeep.MAX_TILT_RAD)
	assert_almost_eq(capped.angle_to(Vector3.UP), RockKeep.MAX_TILT_RAD, 1e-5)
	assert_almost_eq(capped.z, 0.0, 1e-6, "leans the same way")
	var gentle := Vector3(0.3, 1.0, 0.0).normalized()
	assert_true(
		RockKeep.capped_up(gentle, RockKeep.MAX_TILT_RAD).is_equal_approx(gentle),
		"a gentle tilt stays"
	)
	var yawed := Quaternion(Vector3.UP, steep) * Quaternion(Vector3.UP, 0.7)
	var q := RockKeep.capped_rotation(yawed, RockKeep.MAX_TILT_RAD)
	var up := q * Vector3.UP
	assert_almost_eq(up.angle_to(Vector3.UP), RockKeep.MAX_TILT_RAD, 1e-4)
	var row := PropRows.make_row(Vector3.ZERO, steep, true, 0.7, 1.0)
	row[3] = q.x
	row[4] = q.y
	row[5] = q.z
	row[6] = q.w
	assert_almost_eq(PropRows.row_yaw(row), 0.7, 1e-4, "keeps its yaw")


func test_a_kept_row_is_bedded_at_the_lowest_ground_under_its_footprint() -> void:
	var doc := MapDocument.create_flat(Vector2i(8, 8), "grass", "v", 3)
	for z in doc.samples_z():
		for x in doc.samples_x():
			# A 45 degree ramp rising toward +X.
			doc.heights[doc.sample_index(x, z)] = doc.sample_to_world(Vector2(x, z)).x
	var grid := GroundSnap.grid_of(doc)
	var tilted := Quaternion(Vector3.UP, Vector3(-1, 1, 0).normalized())
	var row := PackedFloat32Array(
		[1.0, 1.0, 0.0, tilted.x, tilted.y, tilted.z, tilted.w, 1.5, 1.5, 1.5]
	)
	var kept := RockKeep.kept_row(row, doc.heights, grid, 0.4, true)
	assert_almost_eq(kept[1], 1.0 - 0.4 * 1.5, 1e-4, "sunk to the footprint's low side")
	assert_eq(kept[7], 1.5, "scale kept")
	var q := Quaternion(kept[3], kept[4], kept[5], kept[6])
	assert_almost_eq((q * Vector3.UP).angle_to(Vector3.UP), PI / 4.0, 1e-4, "within the cap")


func test_generation_skips_rocks_and_trees_inside_a_blocker_only() -> void:
	var free := _generated(PackedFloat32Array())
	var blockers := PackedFloat32Array()
	var blocked_keys := {}
	# Block every other rock and tree of the free generation.
	var flip := false
	for cell in free:
		for asset_id in free[cell]:
			var rule := RockKeep.rule_for_asset(asset_id, PaletteLibrary.DEFAULT_ROOT)
			if not RockKeep.is_rock(rule) and String(rule.get("size_class", "")) != "large":
				continue
			var rows: PackedFloat32Array = free[cell][asset_id]
			var keys := _keys(rows)
			for r in keys.size():
				flip = not flip
				if flip:
					blockers.append_array([rows[r * 10], rows[r * 10 + 2], 0.05])
					blocked_keys[keys[r]] = true
	assert_gt(blocked_keys.size(), 3, "the band has rocks and trees")
	var blocked := _generated(blockers)
	var lost := 0
	var other := 0
	for cell in free:
		for asset_id in free[cell]:
			var have := {}
			for key in _keys(blocked.get(cell, {}).get(asset_id, PackedFloat32Array())):
				have[key] = true
			for key in _keys(free[cell][asset_id]):
				if have.has(key):
					continue
				if blocked_keys.has(key):
					lost += 1
				else:
					other += 1
	assert_eq(lost, blocked_keys.size(), "every blocked instance is skipped")
	assert_eq(other, 0, "and nothing else changes (relations still see them)")


# --- the editor -------------------------------------------------------------------------


func test_rocks_the_stroke_would_remove_become_bedded_tilted_props() -> void:
	var editor := _editor()
	var before := _cells_of(editor.scatter)
	var before_rocks := _rock_keys(before)
	var start_heights := _doc.heights.duplicate()
	_tier(editor)
	await _settle(editor)
	gut.p(
		(
			"rock keeping: %d kept, main thread %d us, worker %d us"
			% [
				editor.rock_keeper.last_kept,
				editor.rock_keeper.last_usec,
				editor.rock_keeper.last_worker_usec
			]
		)
	)
	var kept: Dictionary = editor.props.rows_by_asset()
	assert_gt(_count(kept), 0, "the tier's face kept some rocks")
	var after := _cells_of(editor.scatter)
	var after_rocks := _rock_keys(after)
	var grid := GroundSnap.grid_of(_doc)
	var steepest := 0.0
	for asset_id in kept:
		assert_true(_rocks.has(asset_id), "%s is a rock" % asset_id)
		var rule: Dictionary = _rocks.get(asset_id, {})
		var rows: PackedFloat32Array = kept[asset_id]
		var keys := _keys(rows)
		for r in keys.size():
			var b := r * MapDocument.ROW_STRIDE
			assert_true(before_rocks.get(asset_id, {}).has(keys[r]), "it was there: none added")
			assert_false(after_rocks.get(asset_id, {}).has(keys[r]), "the scatter has no twin")
			var p := Vector2(rows[b], rows[b + 2])
			var lowest := GroundSnap.lowest_under(
				_doc.heights, grid, p, GroundSnap.footing_radius(rule) * rows[b + 7]
			)
			assert_almost_eq(rows[b + 1], lowest, 1e-5, "bedded at the lowest ground")
			var q := Quaternion(rows[b + 3], rows[b + 4], rows[b + 5], rows[b + 6])
			var tilt := (q * Vector3.UP).angle_to(Vector3.UP)
			assert_lt(tilt, RockKeep.MAX_TILT_RAD + 1e-3, "within the cap")
			steepest = maxf(steepest, tilt)
	assert_gt(steepest, deg_to_rad(20.0), "some lean with the new ground")
	# Everything the scatter holds is what the document (props included) generates.
	var blockers := RockKeep.blockers(kept, PaletteLibrary.DEFAULT_ROOT)
	assert_eq(_mismatches(editor.scatter, _generated(blockers)), 0, "the rest follows the rules")
	assert_ne(_doc.heights, start_heights)


func test_the_keeping_lands_over_frames_and_holds_the_regeneration_until_then() -> void:
	var editor := _editor()
	_tier(editor)
	assert_true(editor.rock_keeper.is_running(), "worked out on a worker")
	assert_true(editor.has_height_work())
	assert_false(editor.scatter.is_regenerating(), "nothing regenerates before it lands")
	var frames := 0
	while editor.has_height_work() and frames < 300:
		await wait_process_frames(1)
		editor.step_height_work()
		frames += 1
	assert_false(editor.has_height_work(), "landed in %d frames" % frames)
	assert_gt(_count(editor.props.rows_by_asset()), 0, "rocks kept")
	await _settle(editor)


func test_non_rock_species_still_follow_the_rules() -> void:
	var editor := _editor()
	var before := _cells_of(editor.scatter)
	_tier(editor)
	await _settle(editor)
	var after := _cells_of(editor.scatter)
	var removed := 0
	for cell in before:
		for asset_id in before[cell]:
			if _rocks.has(asset_id):
				continue
			var have := {}
			for key in _keys(after.get(cell, {}).get(asset_id, PackedFloat32Array())):
				have[key] = true
			for key in _keys(before[cell][asset_id]):
				if not have.has(key):
					removed += 1
	assert_gt(removed, 0, "plants on the new face are removed as before")
	for asset_id in editor.props.rows_by_asset():
		assert_true(_rocks.has(asset_id), "only rocks become props")


func test_undo_and_redo_restore_exactly() -> void:
	var editor := _editor()
	var start_cells := _cells_of(editor.scatter)
	var start_heights := _doc.heights.duplicate()
	_tier(editor)
	await _settle(editor)
	var stroke_cells := _cells_of(editor.scatter)
	var stroke_props := editor.props.rows_by_asset()
	var stroke_heights := _doc.heights.duplicate()
	assert_gt(_count(stroke_props), 0)
	_history.undo()
	assert_eq(_count(editor.props.rows_by_asset()), 0, "the kept rocks leave the props at once")
	var back := _rock_keys(_cells_of(editor.scatter))
	var missing := 0
	for asset_id in stroke_props:
		for key in _keys(stroke_props[asset_id]):
			if not back.get(asset_id, {}).has(key):
				missing += 1
	assert_eq(missing, 0, "and are back in the scatter at once")
	await _settle(editor)
	assert_eq(_doc.heights, start_heights)
	assert_eq(_mismatches(editor.scatter, start_cells), 0, "the regeneration agrees")
	_history.redo()
	assert_eq(editor.props.rows_by_asset(), stroke_props, "redo makes them props again")
	await _settle(editor)
	assert_eq(_doc.heights, stroke_heights)
	assert_eq(editor.props.rows_by_asset(), stroke_props)
	assert_eq(_mismatches(editor.scatter, stroke_cells), 0, "and the scatter as it was")


func test_a_second_stroke_never_grows_a_twin_inside_a_kept_rock() -> void:
	var editor := _editor()
	_tier(editor)
	await _settle(editor)
	var kept_count := _count(editor.props.rows_by_asset())
	assert_gt(kept_count, 0)
	# Flatten the tier back to the ground: the rules allow the rocks there again.
	assert_true(editor.begin_height_stroke(HeightBrush.FLATTEN, 0.0))
	for _frame in 60:
		for k in 8:
			var x := -8.0 + k * 2.0
			editor.stroke_dab(Vector3(x, 0, -1), Vector3(x + 2.0, 0, -1), 5.0, 0.1)
		editor.flush()
	editor.end_stroke()
	await _settle(editor)
	var props := editor.props.rows_by_asset()
	assert_eq(_count(props), kept_count, "no rock kept twice, none lost")
	var blockers := RockKeep.blockers(props, PaletteLibrary.DEFAULT_ROOT)
	var twins := 0
	for cell in _cells_of(editor.scatter).values():
		for asset_id in cell:
			if not _rocks.has(asset_id):
				continue
			var rows: PackedFloat32Array = cell[asset_id]
			@warning_ignore("integer_division")
			for r in rows.size() / MapDocument.ROW_STRIDE:
				if RockKeep.blocked(blockers, Vector2(rows[r * 10], rows[r * 10 + 2])):
					twins += 1
	assert_eq(twins, 0, "no generated rock inside a kept one")
	assert_eq(_mismatches(editor.scatter, _generated(blockers)), 0, "the rest follows the rules")


func test_kept_rocks_survive_a_save_round_trip() -> void:
	var editor := _editor()
	_tier(editor)
	await _settle(editor)
	_doc.scatter = editor.scatter.rows_by_asset()
	_doc.props = editor.props.rows_by_asset()
	var packed := MapDocumentIO.serialize(_doc)
	assert_eq(packed.error, "")
	var read: MapDocument = MapDocumentIO.parse(packed.entries).document
	assert_not_null(read)
	if read == null:
		return
	var want_ids := _doc.props.keys()
	var got_ids := read.props.keys()
	want_ids.sort()
	got_ids.sort()
	assert_eq(got_ids, want_ids)
	for asset_id in _doc.props:
		var want: PackedFloat32Array = _doc.props[asset_id]
		var got: PackedFloat32Array = read.props.get(asset_id, PackedFloat32Array())
		assert_eq(got.size(), want.size(), asset_id)
		var worst := 0.0
		for i in mini(got.size(), want.size()):
			worst = maxf(worst, absf(got[i] - want[i]))
		assert_lt(worst, 1e-5, "%s rows round trip" % asset_id)
