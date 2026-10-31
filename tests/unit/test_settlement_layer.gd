extends GutTest

## Settlements, the scene half (card settlement): SettlementEditor (one history entry per action,
## undo, redo), the derived layer AuthoredSettlements (cells, keys, ground, no collision, one
## surface per material), a street split into buildings, a saved map and the baked surfaces.
## Summary: docs/systems/settlements.md.

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


func _street(editor: AuthoringEditor, preset: int = 3, seed_value: int = 5) -> int:
	return editor.walls.place(
		Wall.Kind.ROW,
		Vector3(-12, 0, 0),
		Vector3(12, 0, 0),
		-1.0,
		{"seed": seed_value, "side": 2, "preset": preset}
	)


func _layer() -> AuthoredSettlements:
	var layer := (
		_map.get_node_or_null(NodePath(AuthoredSettlements.NODE_NAME)) as AuthoredSettlements
	)
	assert_not_null(layer, "the layer exists")
	return layer


func _dressed(editor: AuthoringEditor, kit: String = "market_town") -> int:
	var street := _street(editor)
	var id := editor.settlements.dress(street, kit)
	assert_gt(id, 0)
	_layer().flush()
	return id


func _mesh_count(layer: AuthoredSettlements) -> int:
	var total := 0
	for child in layer.get_children():
		total += 1 if child is MeshInstance3D else 0
	return total


func test_dressing_a_street_builds_baked_cells_with_no_collision() -> void:
	var editor := _editor()
	_dressed(editor)
	var layer := _layer()
	assert_gt(layer.placed, 5, "a market street is furnished")
	assert_gt(_mesh_count(layer), 0)
	assert_lte(_mesh_count(layer), 6, "a 24 m street is a few cells")
	for child in layer.get_children():
		var node := child as MeshInstance3D
		assert_not_null(node, "a cell is one MeshInstance3D")
		assert_gt(node.mesh.get_surface_count(), 0)
		assert_lte(node.mesh.get_surface_count(), 9, "one surface per material")
		assert_eq(node.find_children("*", "CollisionObject3D", true, false).size(), 0)
		assert_true(node.has_meta(AuthoredSettlements.META))
	var triangles := 0
	for child in layer.get_children():
		var mesh := (child as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			triangles += (
				(mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			)
	assert_gt(triangles, 500)


func test_a_refresh_with_nothing_changed_rebuilds_nothing() -> void:
	var editor := _editor()
	_dressed(editor)
	var layer := _layer()
	var builds := layer.builds
	var keys := {}
	for name_key in layer.cell_names():
		keys[name_key] = layer.key_of_cell(name_key)
	layer.refresh(_doc)
	assert_eq(layer.pending_count(), 0)
	assert_eq(layer.flush(), 0)
	assert_eq(layer.builds, builds)
	for name_key in keys:
		assert_eq(layer.key_of_cell(name_key), keys[name_key])


func test_one_history_entry_per_action_and_undo_redo() -> void:
	var editor := _editor()
	var street := _street(editor)
	var undo_count := _history.undo_count()
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_eq(_history.undo_count(), undo_count + 1, "Dress is one entry")
	_layer().flush()
	var names := _layer().cell_names()
	assert_gt(names.size(), 0)
	editor.settlements.redress(id)
	assert_eq(_history.undo_count(), undo_count + 2, "Re-dress is one entry")
	var seed_after := _doc.settlement(id).seed_value
	assert_true(editor.settlements.set_kit(id, "harbour_town"))
	assert_eq(_history.undo_count(), undo_count + 3, "a character change is one entry")
	assert_true(editor.settlements.set_feel(id, 0.9, 0.3))
	assert_eq(_history.undo_count(), undo_count + 4, "wealth and density are one entry")
	assert_false(editor.settlements.set_feel(id, 0.9, 0.3), "no change, no entry")
	assert_true(editor.settlements.clear(id))
	assert_eq(_history.undo_count(), undo_count + 5, "Clear is one entry")
	assert_eq(_doc.settlements.size(), 0)
	_layer().flush()
	assert_eq(_layer().cell_names().size(), 0, "clearing removes every cell")
	_history.undo()
	assert_eq(_doc.settlements.size(), 1)
	_layer().flush()
	assert_gt(_layer().cell_names().size(), 0, "undo puts the furnishings back")
	_history.undo()
	_history.undo()
	assert_eq(_doc.settlement(id).kit, "farming_hamlet", "the character change is undone")
	assert_eq(_doc.settlement(id).seed_value, seed_after)
	_history.undo()
	assert_ne(_doc.settlement(id).seed_value, seed_after, "the re-dress is undone")
	_history.undo()
	assert_eq(_doc.settlements.size(), 0, "all the way back")
	_layer().flush()
	assert_eq(_layer().cell_names().size(), 0)
	_history.redo()
	assert_eq(_doc.settlements.size(), 1)


func test_redress_draws_a_new_seed_and_other_furnishing() -> void:
	var editor := _editor()
	var id := _dressed(editor, "farming_hamlet")
	var before := _doc.settlement(id).seed_value
	var layer := _layer()
	var keys_before := PackedStringArray()
	for name_key in layer.cell_names():
		keys_before.append(layer.key_of_cell(name_key))
	assert_eq(editor.settlements.dress(_doc.settlements[0].source, "farming_hamlet"), id)
	assert_ne(_doc.settlement(id).seed_value, before)
	layer.flush()
	var keys_after := PackedStringArray()
	for name_key in layer.cell_names():
		keys_after.append(layer.key_of_cell(name_key))
	assert_ne(keys_after, keys_before, "another seed furnishes another street")
	assert_eq(_doc.settlements.size(), 1, "Re-dress edits the settlement")


func test_dress_refuses_what_is_not_a_street() -> void:
	var editor := _editor()
	var fence := editor.walls.place(Wall.Kind.FENCE, Vector3(-3, 0, 6), Vector3(1, 0, 6))
	var undo_count := _history.undo_count()
	assert_eq(editor.settlements.dress(fence, "farming_hamlet"), -1)
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_STREET)
	assert_eq(editor.settlements.dress(77, "farming_hamlet"), -1)
	var street := _street(editor)
	assert_eq(editor.settlements.dress(street, "elf_city"), -1)
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_KIT)
	assert_eq(_history.undo_count(), undo_count + 1, "only the street itself was recorded")


func test_props_stand_on_the_ground_not_in_water_and_not_on_steep_banks() -> void:
	var editor := _editor()
	var street := _street(editor)
	# The east half of the map is a pond.
	_doc.water_bodies.append(WaterBody.pond(1, WaterBody.Depth.DEEP, 0.6))
	var pond := PackedByteArray()
	pond.resize(_doc.sample_count())
	for z in _doc.samples_z():
		for x in range(_doc.samples_x() / 2 + 1, _doc.samples_x()):
			pond[_doc.sample_index(x, z)] = 1
	_doc.pond_mask = pond
	var id := editor.settlements.dress(street, "market_town")
	_layer().flush()
	var layer := _layer()
	assert_gt(layer.skipped_ground, 0, "placements on water were skipped")
	for row in layer.standing(id):
		var at: Vector2 = row["item"]["position"]
		assert_false(WaterGeometry.is_wet_at(_doc, at), "no prop in water: %s" % at)
		assert_almost_eq(
			float(row["y"]), WaterGeometry.ground_at(_doc, at) - AuthoredSettlements.SINK_M, 0.01
		)
	# A steep ramp under the street drops every placement on it.
	_doc.water_bodies.clear()
	_doc.pond_mask = PackedByteArray()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			_doc.heights[_doc.sample_index(x, z)] = float(x) * 3.0
	layer.refresh(_doc)
	layer.flush()
	assert_eq(layer.standing(id).size(), 0, "a wall of ground holds no props")


func test_moving_one_lot_rebakes_only_its_cells() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	assert_true(editor.settlements.freeze_street(street))
	_layer().flush()
	var layer := _layer()
	var total := layer.cell_names().size()
	assert_gt(total, 1, "the street spans cells")
	var keys := {}
	for name_key in layer.cell_names():
		keys[name_key] = layer.key_of_cell(name_key)
	# Move the first lot of the first frontage by half a metre: its own furnishings move.
	var held := _doc.settlement(id).copy()
	var frontage: Dictionary = held.frozen[0]
	var lot: Dictionary = frontage["lots"][0]
	lot["s0"] = float(lot["s0"]) + 0.3
	lot["s1"] = float(lot["s1"]) + 0.3
	lot["doors"][0]["s"] = float(lot["doors"][0]["s"]) + 0.3
	var list: Array[Settlement] = [held]
	editor.settlements.apply_list(list, Rect2())
	layer.flush()
	var moved := 0
	for name_key in keys:
		if layer.key_of_cell(name_key) != keys[name_key]:
			moved += 1
	assert_lt(layer.last_rebuilt, total, "not every cell was rebuilt")
	assert_lte(moved, layer.last_rebuilt)


func test_splitting_a_dressed_street_keeps_its_furnishings_and_undo_restores_it() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	_layer().flush()
	var layer := _layer()
	var before := layer.standing(id).size()
	assert_gt(before, 0)
	var made := editor.walls.split_street(street)
	assert_gt(made, 0)
	layer.flush()
	var split := _doc.settlement(id)
	assert_eq(split.source, 0, "the settlement no longer belongs to a street")
	assert_gt(split.frozen.size(), 0, "it keeps the frontage the street had")
	assert_eq(layer.standing(id).size(), before, "the furnishings stay where they were")
	assert_eq(_doc.walls.size(), 0)
	_history.undo()
	layer.flush()
	assert_eq(_doc.settlement(id).source, street, "undo gives the street back")
	assert_eq(_doc.settlement(id).frozen.size(), 0)
	assert_eq(layer.standing(id).size(), before)


func test_a_street_that_goes_leaves_a_settlement_that_draws_nothing_and_returns_on_undo() -> void:
	var editor := _editor()
	var street := _street(editor)
	var id := editor.settlements.dress(street, "farming_hamlet")
	_layer().flush()
	assert_true(editor.walls.remove(street))
	_layer().flush()
	assert_eq(_layer().cell_names().size(), 0)
	assert_eq(_doc.settlement(id).source, street)
	_history.undo()
	_layer().flush()
	assert_gt(_layer().cell_names().size(), 0)


func test_a_saved_and_reloaded_map_shows_the_same_furnishings() -> void:
	var editor := _editor()
	var id := _dressed(editor, "harbour_town")
	var fingerprint := MapFingerprint.of(_map, _doc)
	assert_gt((fingerprint["settlements"] as Array).size(), 1)
	var path := "user://test_settlement_layer.ttmap"
	assert_eq(MapDocumentIO.write(_doc, path), OK)
	var read: MapDocument = MapDocumentIO.read(path)["document"]
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var other := Node3D.new()
	add_child_autofree(other)
	var layer := MapSourceLoader.add_authored_settlements(other, read)
	assert_not_null(layer)
	layer.flush()
	var again := MapFingerprint.of(other, read)
	assert_eq(again["settlements"], fingerprint["settlements"], "the same cells on a loaded map")
	assert_eq(layer.standing(id).size(), _layer().standing(id).size())


func test_cloth_keeps_its_wind_weights_in_the_baked_surface() -> void:
	var editor := _editor()
	_dressed(editor)
	var layer := _layer()
	var found := false
	for ref in ["core:market_stall", "core:laundry_line"]:
		for surface: Dictionary in layer.variant(ref).get("surfaces", []):
			if String(surface["kind"]) == "cloth":
				found = true
				var arrays: Array = surface["arrays"]
				assert_true(
					arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array,
					"%s carries wind weights" % ref
				)
	assert_true(found, "a stall or a washing line has cloth")
	var stall: Dictionary = layer.variant("core:market_stall")
	var baked := (
		SettlementBake
		. bake(
			[
				{"variant": "a", "transform": Transform3D(Basis.IDENTITY, Vector3(5, 0, 0))},
				{
					"variant": "a",
					"transform": Transform3D(Basis(Vector3.UP, 1.0), Vector3(9, 0, 0))
				},
			],
			{"a": stall}
		)
	)
	var triangles := 0
	for surface in stall["surfaces"] as Array:
		triangles += (surface["arrays"][Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	assert_eq(SettlementBake.triangle_count(baked), triangles * 2)
	assert_eq(baked.size(), (stall["surfaces"] as Array).size(), "one surface per material kind")
	for surface in baked:
		if String(surface["kind"]) == "cloth":
			assert_eq(
				(surface["arrays"][Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size(),
				(surface["arrays"][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			)


func test_the_bake_turns_a_prop_so_its_front_faces_the_yaw() -> void:
	var item := {"position": Vector2(2, 3), "yaw": PI * 0.5, "scale": 2.0}
	var transform := SettlementBake.transform_of(item, 1.0)
	assert_eq(transform.origin, Vector3(2, 1, 3))
	assert_almost_eq(
		(transform.basis * Vector3.BACK).x, 2.0, 0.001, "front +z turns to +x at a quarter turn"
	)
