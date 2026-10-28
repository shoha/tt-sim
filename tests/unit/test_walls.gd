extends GutTest

## Walls and fences (Wall, MapWallIO, WallGeometry, AuthoredWalls, WallEditor, WallBrush,
## WallTool): the document entry and its validation, the geometry the procgen recipes build on
## the document's ground, the nodes and their collision, the editor's plan and edits (extend,
## close, remove, undo), the live edit a peer applies, and the tool's registration.
## Summary: docs/systems/walls.md.

const SAVE_PATH := "user://test_walls.ttmap"

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


func after_each() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _line() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-3, 0), Vector2(1, 0), Vector2(1, 3)])


func _wall(kind: Wall.Kind = Wall.Kind.STONE, closed: bool = false) -> Wall:
	return Wall.make(1, kind, _line(), closed, Wall.DEFAULT_HEIGHT_M[kind], "")


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


func _nodes() -> AuthoredWalls:
	return _map.get_node(AuthoredWalls.NODE_NAME) as AuthoredWalls


# --- the document entry -----------------------------------------------------------------


func test_a_wall_round_trips_through_json() -> void:
	var wall := _wall(Wall.Kind.FENCE, false)
	wall.style = "temperate_forest"
	var json := MapWallIO.wall_json(wall)
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapWallIO.parse_list([json], _doc.extent_m(), warn_log)
	assert_eq(warn_log.items.size(), 0)
	assert_eq(list.size(), 1)
	assert_true(wall.same_as(list[0]), "every field comes back")


func test_the_reader_drops_a_wall_that_breaks_a_rule() -> void:
	var good := MapWallIO.wall_json(_wall())
	var short_side := MapWallIO.wall_json(_wall())
	short_side["points"] = [[0.0, 0.0], [0.1, 0.0]]
	var off_map := MapWallIO.wall_json(_wall())
	off_map["points"] = [[0.0, 0.0], [900.0, 0.0]]
	var too_tall := MapWallIO.wall_json(_wall())
	too_tall["height_m"] = 9.0
	var bad_kind := MapWallIO.wall_json(_wall())
	bad_kind["kind"] = "moat"
	var two_corners_closed := MapWallIO.wall_json(_wall())
	two_corners_closed["points"] = [[0.0, 0.0], [4.0, 0.0]]
	two_corners_closed["closed"] = true
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapWallIO.parse_list(
		[good, short_side, off_map, too_tall, bad_kind, two_corners_closed, "nope"],
		_doc.extent_m(),
		warn_log
	)
	assert_eq(list.size(), 1, "only the good wall survives")
	assert_eq(warn_log.items.size(), 6, "and each other one is said")


func test_a_saved_map_keeps_its_walls() -> void:
	_doc.walls.append(_wall())
	var fence := _wall(Wall.Kind.FENCE, true)
	fence.id = 2
	fence.points = PackedVector2Array([Vector2(4, 4), Vector2(8, 4), Vector2(8, 8)])
	_doc.walls.append(fence)
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(read.walls.size(), 2)
	assert_true(read.walls[0].same_as(_doc.walls[0]))
	assert_true(read.walls[1].same_as(_doc.walls[1]))
	assert_eq(read.wall(2).kind, Wall.Kind.FENCE)


func test_the_writer_refuses_a_document_with_a_bad_wall() -> void:
	var wall := _wall()
	wall.height_m = 50.0
	_doc.walls.append(wall)
	assert_ne(MapWallIO.problem(_doc), "")
	assert_ne(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	assert_engine_error("not writing")


func test_ids_are_free_ones_and_the_document_is_capped() -> void:
	assert_eq(_doc.next_wall_id(), 1)
	_doc.walls.append(_wall())
	assert_eq(_doc.next_wall_id(), 2)
	for k in MapDocument.MAX_WALLS - 1:
		var more := _wall()
		more.id = k + 2
		_doc.walls.append(more)
	assert_eq(_doc.next_wall_id(), -1, "full")


func test_the_procgen_crossings_flag_is_a_map_fact() -> void:
	assert_false(_doc.procgen_crossings, "an older map keeps the code-built crossings")
	assert_false(ProcgenCrossing.active(_doc))
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var plain: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_false(plain.procgen_crossings, "no key in the manifest reads as false")
	_doc.procgen_crossings = true
	assert_true(ProcgenCrossing.active(_doc))
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_true(read.procgen_crossings, "the flag survives a save")
	assert_true(ProcgenCrossing.active(read))
	var made := NewMap.create(50, NewMap.BARE_BIOME, 7)
	assert_true(made.procgen_crossings, "a new map says yes")


# --- the geometry ------------------------------------------------------------------------


func test_a_stone_wall_builds_masonry_and_a_solid_hull() -> void:
	var parts := WallGeometry.build_one(_doc, _wall())
	assert_false((parts.stone as Array).is_empty(), "masonry")
	assert_true((parts.wood as Array).is_empty())
	assert_gt((parts.collision as PackedVector3Array).size(), 0, "a hull to stand on")
	assert_almost_eq(float(parts.top), Wall.DEFAULT_HEIGHT_M[Wall.Kind.STONE], 0.08)


func test_a_fence_builds_wood_and_no_collision() -> void:
	var parts := WallGeometry.build_one(_doc, _wall(Wall.Kind.FENCE))
	assert_false((parts.wood as Array).is_empty())
	assert_true((parts.stone as Array).is_empty())
	assert_eq((parts.collision as PackedVector3Array).size(), 0, "a fence blocks nothing")


func test_a_wall_follows_the_ground_it_stands_on() -> void:
	var rise := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			rise[_doc.sample_index(x, z)] = 0.1 * _doc.sample_to_world(Vector2(x, z)).x
	_doc.heights = rise
	var wall := _wall()
	wall.points = PackedVector2Array([Vector2(-4, 0), Vector2(4, 0)])
	var parts := WallGeometry.build_one(_doc, wall)
	assert_almost_eq(
		float(parts.top), 0.1 * 4.0 + wall.height_m, 0.1, "the top rises with the ground"
	)


func test_the_geometry_is_the_same_each_time_and_its_key_moves_with_the_ground() -> void:
	var wall := _wall()
	var a := WallGeometry.build_one(_doc, wall)
	var b := WallGeometry.build_one(_doc, wall)
	assert_eq((a.stone as Array)[Mesh.ARRAY_VERTEX], (b.stone as Array)[Mesh.ARRAY_VERTEX])
	var key := WallGeometry.key_of(_doc, wall)
	assert_eq(key, WallGeometry.key_of(_doc, wall))
	var raised := _doc.heights.duplicate()
	raised[_doc.sample_index(_doc.samples_x() / 2, _doc.samples_z() / 2)] += 0.5
	_doc.heights = raised
	assert_ne(WallGeometry.key_of(_doc, wall), key, "a sculpt under the wall changes the key")
	var taller := wall.copy()
	taller.height_m = 1.4
	assert_ne(WallGeometry.key_of(_doc, taller), WallGeometry.key_of(_doc, wall))


func test_plants_are_cleared_along_a_wall() -> void:
	_doc.walls.append(_wall(Wall.Kind.STONE, false))
	var sides := WallGeometry.clearance_crossings(_doc)
	assert_eq(sides.size(), 2, "one per side of the open line")
	assert_eq(CrossingGeometry.clearance(sides, Vector2(-1, 0)), 0.0, "nothing on the wall")
	assert_eq(CrossingGeometry.clearance(sides, Vector2(-1, 6)), 1.0, "far away it grows")
	var closed := _wall(Wall.Kind.STONE, true)
	_doc.walls[0] = closed
	assert_eq(WallGeometry.clearance_crossings(_doc).size(), 3, "a closed wall has its last side")


func test_textured_masonry_is_a_part_of_stone_buildings_and_streets() -> void:
	assert_true(MasonryTextures.available(), "the baked set is in the project")
	var before := WallGeometry.textured
	assert_true(before, "on: it reads as well as modelled blocks at a tenth of the triangles")
	WallGeometry.textured = true
	var street := Wall.make(
		1, Wall.Kind.ROW, PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), false, 3.0
	)
	assert_eq(
		WallGeometry.inputs_for(_doc, street).params.get("textured"), 1.0, "asked of the recipe"
	)
	var parts := WallGeometry.build_one(_doc, street)
	assert_false((parts.masonry as Array).is_empty(), "a street's walls are masonry")
	var fence := _wall(Wall.Kind.FENCE)
	assert_false(WallGeometry.inputs_for(_doc, fence).params.has("textured"), "a fence has none")
	WallGeometry.textured = false
	assert_true((WallGeometry.build_one(_doc, street).masonry as Array).is_empty(), "switched off")
	WallGeometry.textured = before


# --- the nodes ---------------------------------------------------------------------------


func test_the_nodes_hold_a_wall_and_its_collision_body() -> void:
	_doc.walls.append(_wall())
	var walls := AuthoredWalls.create(_doc)
	_map.add_child(walls)
	var node := walls.get_wall_node(1)
	assert_not_null(node)
	assert_not_null(node.get_node_or_null("Stone"))
	var body := node.get_node("Collision") as StaticBody3D
	assert_eq(body.get_meta(AuthoredWalls.WALL_META), 1)
	assert_eq(body.collision_layer, WaterSurface.TERRAIN_LAYER)
	assert_eq(AuthoredWalls.exclude_of(_map).size(), 1)
	assert_gt(walls.top_y, 0.5)


func test_a_refresh_rebuilds_only_the_walls_that_changed() -> void:
	var near := _wall()
	var far := _wall()
	far.id = 2
	far.points = PackedVector2Array([Vector2(-8, 8), Vector2(-4, 8)])
	_doc.walls.append(near)
	_doc.walls.append(far)
	var walls := AuthoredWalls.create(_doc)
	_map.add_child(walls)
	walls.refresh(_doc)
	assert_eq(walls.last_rebuilt, 0, "a load seeds the keys")
	var raised := _doc.heights.duplicate()
	var at := _doc.world_to_sample(Vector2(-1, 0)).round()
	raised[_doc.sample_index(int(at.x), int(at.y))] += 0.4
	_doc.heights = raised
	walls.refresh(_doc)
	assert_eq(walls.last_rebuilt, 1, "only the wall over the raised ground")
	_doc.walls.remove_at(1)
	walls.refresh(_doc)
	assert_null(walls.get_wall_node(2), "a removed wall's node goes")


# --- the editor --------------------------------------------------------------------------


func test_plan_previews_without_changing_anything() -> void:
	var editor := _editor()
	var plan := editor.walls.plan(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	assert_not_null(plan)
	assert_eq(plan.points.size(), 2)
	assert_true(_doc.walls.is_empty())
	assert_false(_history.can_undo())
	assert_null(editor.walls.plan(Wall.Kind.STONE, Vector3(0, 0, 0), Vector3(0.1, 0, 0)))
	assert_eq(editor.walls.last_refusal, WallEditor.REFUSED_SHORT)


func test_place_undo_redo() -> void:
	var editor := _editor()
	var first := editor.walls.place(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	var second := editor.walls.place(Wall.Kind.FENCE, Vector3(-3, 0, 6), Vector3(1, 0, 6))
	assert_eq([first, second], [1, 2])
	assert_not_null(_nodes().get_wall_node(1))
	assert_not_null(_nodes().get_wall_node(2))
	assert_eq(_history.undo(), "Place fence")
	assert_null(_nodes().get_wall_node(2), "the node follows the undo")
	assert_eq(_history.undo(), "Place wall")
	assert_true(_doc.walls.is_empty())
	_history.redo()
	_history.redo()
	assert_eq(_doc.walls.size(), 2)
	assert_not_null(_nodes().get_wall_node(2))


func test_a_drag_from_a_free_end_extends_the_wall() -> void:
	var editor := _editor()
	var id := editor.walls.place(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	var next := editor.walls.place(Wall.Kind.STONE, Vector3(1.2, 0, 0), Vector3(1, 0, 3))
	assert_eq(next, id, "the same wall")
	assert_eq(_doc.walls.size(), 1)
	assert_eq(_doc.wall(id).points.size(), 3)
	assert_eq(_doc.wall(id).points[2], Vector2(1, 3))
	# From the other end the new point goes in front.
	editor.walls.place(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(-6, 0, 0))
	assert_eq(_doc.wall(id).points[0], Vector2(-6, 0))
	assert_eq(_doc.wall(id).points.size(), 4)
	assert_eq(_history.undo(), "Extend wall")
	assert_eq(_doc.wall(id).points.size(), 3)
	# A fence does not extend a stone wall.
	var fence := editor.walls.place(Wall.Kind.FENCE, Vector3(1, 0, 3), Vector3(1, 0, 6))
	assert_ne(fence, id)


func test_a_drag_back_to_the_first_end_closes_the_wall() -> void:
	var editor := _editor()
	var id := editor.walls.place(Wall.Kind.STONE, Vector3(0, 0, 0), Vector3(4, 0, 0))
	editor.walls.place(Wall.Kind.STONE, Vector3(4, 0, 0), Vector3(4, 0, 4))
	editor.walls.place(Wall.Kind.STONE, Vector3(4, 0, 4), Vector3(0.2, 0, 0.1))
	assert_true(_doc.wall(id).closed, "the loop closed")
	assert_eq(_doc.wall(id).points.size(), 3, "without a repeated point")
	var walls := _nodes()
	assert_not_null(walls.get_wall_node(id))
	# A closed wall has no free end.
	var again := editor.walls.place(Wall.Kind.STONE, Vector3(0, 0, 0), Vector3(-4, 0, 0))
	assert_ne(again, id)


func test_remove_and_wall_at() -> void:
	var editor := _editor()
	var id := editor.walls.place(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	assert_eq(editor.walls.wall_at(Vector3(-1, 0, 0.2)), id, "on the line")
	assert_eq(editor.walls.wall_at(Vector3(-1, 0, 3)), -1, "beside it")
	assert_true(editor.walls.remove(id))
	assert_false(editor.walls.remove(id), "already gone")
	assert_null(_nodes().get_wall_node(id))
	_history.undo()
	assert_eq(_doc.walls[0].id, id, "the id comes back with it")


func test_a_sculpt_under_a_wall_refreshes_it() -> void:
	var editor := _editor()
	editor.walls.place(Wall.Kind.STONE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	var before := _nodes().keys()
	var raised := _doc.heights.duplicate()
	var at := _doc.world_to_sample(Vector2(-1, 0)).round()
	raised[_doc.sample_index(int(at.x), int(at.y))] += 0.5
	_doc.heights = raised
	var record := editor.walls.follow(Rect2(-2, -1, 2, 2))
	assert_false(record.is_empty(), "the edit reached the wall")
	assert_ne(_nodes().keys(), before, "and rebuilt it")
	assert_true(editor.walls.follow(Rect2(8, 8, 1, 1)).is_empty(), "a far edit reaches none")


# --- the removed building kind (card S8) -------------------------------------------------


## A walls.json an older build wrote: a fence, a building (a closed square, style 4) and a street.
func _old_walls_json() -> Dictionary:
	var building := {
		"id": 2,
		"kind": "building",
		"points": [[0.0, 0.0], [6.0, 0.0], [6.0, 4.0], [0.0, 4.0]],
		"closed": true,
		"height_m": 2.4,
		"style": "",
		"preset": 4,
	}
	var street := MapWallIO.wall_json(
		Wall.make(3, Wall.Kind.ROW, PackedVector2Array([Vector2(-8, 4), Vector2(8, 4)]), false, 3.0)
	)
	return {
		"version": 1,
		"walls": [MapWallIO.wall_json(_wall(Wall.Kind.FENCE)), building, street],
	}


func test_the_building_kind_is_gone_and_the_others_keep_their_names() -> void:
	assert_eq(Wall.KIND_NAMES, ["stone", "fence", "row"] as Array[String])
	assert_eq(Wall.KIND_NAMES.size(), Wall.Kind.size())
	assert_eq(Wall.MIN_HEIGHT_M.size(), Wall.Kind.size())
	assert_eq(Wall.MAX_HEIGHT_M.size(), Wall.Kind.size())
	assert_eq(Wall.DEFAULT_HEIGHT_M.size(), Wall.Kind.size())
	assert_eq(Wall.KIND_NAMES[Wall.Kind.ROW], "row")


func test_a_building_entry_of_an_old_map_is_skipped_with_a_warning() -> void:
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapWallIO.parse_list(_old_walls_json()["walls"], _doc.extent_m(), warn_log)
	assert_eq(list.size(), 2, "the fence and the street load")
	assert_eq([list[0].kind, list[1].kind], [Wall.Kind.FENCE, Wall.Kind.ROW])
	assert_eq(warn_log.items.size(), 1, "and the building is said once")
	assert_string_contains(warn_log.items[0], "building")
	assert_string_contains(warn_log.items[0], "Structure tool")


func test_a_whole_old_map_with_a_building_entry_loads_without_it() -> void:
	var entries: Dictionary = MapDocumentIO.serialize(_doc)["entries"]
	entries["walls.json"] = JSON.stringify(_old_walls_json()).to_utf8_buffer()
	var packer := ZIPPacker.new()
	assert_eq(packer.open(SAVE_PATH), OK)
	for entry_name: String in entries:
		packer.start_file(entry_name)
		packer.write_file(entries[entry_name])
		packer.close_file()
	packer.close()
	var result := MapDocumentIO.read(SAVE_PATH)
	assert_not_null(result["document"], "the map opens")
	var read: MapDocument = result["document"]
	assert_eq(read.walls.size(), 2, "without the building")
	assert_eq(read.walls[1].kind, Wall.Kind.ROW)
	assert_eq(read.wall(2), null, "its id is free again")
	assert_eq((result["warnings"] as PackedStringArray).size(), 1, "one warning")
	# The next save is plain: no building entry comes back, and the walls re-save byte for byte.
	assert_eq(MapDocumentIO.write(read, SAVE_PATH), OK)
	var again: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(MapDocumentIO.write(again, SAVE_PATH + ".b"), OK)
	assert_eq(
		FileAccess.get_file_as_bytes(SAVE_PATH + ".b"), FileAccess.get_file_as_bytes(SAVE_PATH)
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".b"))


func test_other_bad_kind_values_are_skipped_not_fatal() -> void:
	var bad: Array = []
	for value: Variant in ["Building", "", null, 2, 1.5, ["row"], {"kind": "row"}, "row "]:
		var json := MapWallIO.wall_json(_wall())
		json["kind"] = value
		bad.append(json)
	var warn_log := MapDocumentIO._WarningLog.new()
	var list := MapWallIO.parse_list(bad, _doc.extent_m(), warn_log)
	assert_eq(list.size(), 0, "none is read as a wall")
	assert_eq(warn_log.items.size(), bad.size(), "and each is said")


func test_a_wall_of_a_kind_past_the_end_is_refused_by_the_writer() -> void:
	var wall := _wall()
	wall.kind = Wall.KIND_NAMES.size() as Wall.Kind
	assert_eq(MapWallIO.wall_problem(wall, _doc.extent_m()), "unknown kind")


func test_walls_and_streets_keep_their_geometry_after_the_kind_was_removed() -> void:
	# A street's seed counted its kind as 3 while the building kind existed; it still does.
	var street := Wall.make(
		5, Wall.Kind.ROW, PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), false, 3.0
	)
	street.seed_value = 17
	var expected := hash([_doc.map_seed, 5, 103, 17])
	assert_eq(WallGeometry.inputs_for(_doc, street).seed_value, expected)
	var stone := _wall(Wall.Kind.STONE)
	assert_eq(
		WallGeometry.inputs_for(_doc, stone).seed_value,
		hash([_doc.map_seed, stone.id, 100, stone.seed_value])
	)
	assert_eq(WallGeometry.recipe_path(Wall.Kind.ROW), WallGeometry.STREET_ROW_RECIPE)
	assert_eq(WallGeometry.recipe_path(Wall.Kind.STONE), WallGeometry.STONE_RECIPE)
	assert_eq(WallGeometry.recipe_path(Wall.Kind.FENCE), WallGeometry.FENCE_RECIPE)


# --- streets -----------------------------------------------------------------------------


func _street(editor: AuthoringEditor, variation: Dictionary = {}) -> int:
	return editor.walls.place(Wall.Kind.ROW, Vector3(-12, 0, 0), Vector3(12, 0, 0), -1.0, variation)


func test_a_street_keeps_its_seed_side_and_setback_through_a_save() -> void:
	var street := Wall.make(
		1, Wall.Kind.ROW, PackedVector2Array([Vector2(-10, 0), Vector2(10, 0)]), false, 4.0
	)
	street.seed_value = 12345
	street.side = 0
	_doc.walls.append(street)
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(read.walls.size(), 1)
	assert_true(read.walls[0].same_as(street), "seed, side and setback come back")
	var closed := street.copy()
	closed.closed = true
	assert_ne(MapWallIO.wall_problem(closed, _doc.extent_m()), "", "a street is an open line")
	var bad_side := street.copy()
	bad_side.side = 7
	assert_ne(MapWallIO.wall_problem(bad_side, _doc.extent_m()), "", "side 0 to 2")


func test_a_street_is_laid_extended_and_remixed_with_undo() -> void:
	var editor := _editor()
	var id := _street(editor, {"seed": 99, "side": 1})
	assert_gt(id, 0, "a 24 m street is laid")
	var street := _doc.wall(id)
	assert_true(street.is_row())
	assert_eq([street.seed_value, street.side], [99, 1], "the brush's seed and side")
	assert_eq(
		editor.walls.place(Wall.Kind.ROW, Vector3(12, 0, 0), Vector3(12, 0, 12)), id, "carried on"
	)
	assert_eq(_doc.wall(id).seed_value, 99, "an extended street keeps its own mix")
	assert_eq(_doc.wall(id).points.size(), 3)
	var before := _doc.wall(id).seed_value
	assert_true(editor.walls.reroll(id))
	assert_ne(_doc.wall(id).seed_value, before, "another mix")
	assert_eq(_history.undo(), "Reroll row")
	assert_eq(_doc.wall(id).seed_value, before, "undone")
	assert_null(editor.walls.plan(Wall.Kind.ROW, Vector3(0, 0, 8), Vector3(2, 0, 8)))
	assert_eq(editor.walls.last_refusal, WallEditor.REFUSED_SHORT, "too short for a building")
	assert_false(editor.walls.reroll(9999))


func test_a_street_builds_buildings_and_clears_plants_under_them() -> void:
	var editor := _editor()
	var id := _street(editor)
	var street := _doc.wall(id)
	var lots := WallGeometry.row_lots(_doc, street)
	assert_gt(lots.size(), 4, "a good few buildings along 24 m")
	var node := _nodes().get_wall_node(id)
	assert_not_null(node.get_node_or_null("Stone"), "masonry")
	assert_not_null(node.get_node_or_null("Roof"), "roofs, a mesh of their own since card S6")
	assert_not_null(node.get_node_or_null("Collision"), "and a hull")
	assert_eq(WallGeometry.row_lots(_doc, street).size(), lots.size(), "the lots repeat")
	assert_eq(
		WallGeometry.clearance_crossings(_doc).size(), lots.size(), "one clearing per building"
	)
	var other := street.copy()
	other.seed_value = 4242
	var a: PackedVector3Array = lots[0].points
	var b: PackedVector3Array = WallGeometry.row_lots(_doc, other)[0].points
	assert_ne(a, b, "another seed, another street")
	assert_ne(WallGeometry.key_of(_doc, other), WallGeometry.key_of(_doc, street), "and its key")
	# The first lot's middle is over a building; the street's own line is not.
	var inside := Vector3((a[0].x + a[2].x) * 0.5, 0.0, (a[0].z + a[2].z) * 0.5)
	assert_eq(editor.walls.wall_at(inside), id, "picked over one of its buildings")


func test_a_streets_species_is_kept_laid_and_changes_the_buildings() -> void:
	var editor := _editor()
	var id := _street(editor, {"preset": 3, "seed": 5})
	assert_eq(_doc.wall(id).preset, 3, "the brush's species is laid")
	assert_eq(MapDocumentIO.write(_doc, SAVE_PATH), OK)
	var read: MapDocument = MapDocumentIO.read(SAVE_PATH)["document"]
	assert_eq(read.walls[0].preset, 3, "and saved")
	var bad := _doc.wall(id).copy()
	bad.preset = 9
	assert_ne(MapWallIO.wall_problem(bad, _doc.extent_m()), "", "species 0 to 4")
	var village := WallGeometry.row_lots(_doc, _doc.wall(id))
	var terrace_wall := _doc.wall(id).copy()
	terrace_wall.preset = 1
	var terrace := WallGeometry.row_lots(_doc, terrace_wall)
	assert_ne(village.size(), terrace.size(), "another species, another street")
	assert_ne(
		WallGeometry.key_of(_doc, terrace_wall), WallGeometry.key_of(_doc, _doc.wall(id)), "its key"
	)
	assert_eq(village[0].yard, 1, "a village is fenced")
	# Plants clear over the yard, not only the building.
	assert_eq(WallGeometry.clearance_crossings(_doc).size(), village.size(), "one clearing per lot")


func test_the_pane_offers_the_species_only_for_a_street() -> void:
	var pane := WallToolPane.new()
	add_child_autofree(pane)
	assert_false(pane.preset_field.visible, "hidden for a wall")
	assert_eq(WallToolPane.PRESET_TILES.size(), Wall.ROW_PRESETS, "a tile per species")
	for tile in WallToolPane.PRESET_TILES:
		assert_not_null(IconButton.load_icon(String(tile.icon)), String(tile.icon))
	pane.kind_field.tiles.selection_changed.emit(&"wall_row")
	assert_true(pane.preset_field.visible, "shown for a street")
	watch_signals(pane)
	pane.preset_field.tiles.selection_changed.emit(&"street_village")
	assert_signal_emitted_with_parameters(pane, "preset_selected", [3])
	pane.select_kind(Wall.Kind.STONE)
	assert_false(pane.preset_field.visible, "and hidden again")
	assert_eq(
		WallBrush.readout_row(8, 0, 0.0, 0.0, 0.0, "", 3), "Street  Village, 8 buildings, left side"
	)


func test_q_e_and_r_choose_a_streets_side_and_mix() -> void:
	var tool := BrushTool.new()
	add_child_autofree(tool)
	var brush := WallBrush.new()
	assert_false(brush.rerolls(), "not for walls")
	brush.kind = Wall.Kind.ROW
	assert_true(brush.rotates() and brush.rerolls())
	assert_eq(brush.row_side, 2)
	brush.rotate(tool, 1)
	assert_eq(brush.row_side, 0, "round to the left")
	brush.rotate(tool, -1)
	assert_eq(brush.row_side, 2, "and back")
	assert_eq(BrushTool.decide(_key(KEY_R), false, false, false), BrushTool.Action.REROLL)
	assert_eq(WallBrush.readout_row(5, 1, 0.0, 0.0, 0.0, ""), "Street  5 buildings, right side")


func _key(code: Key) -> InputEventKey:
	var key := InputEventKey.new()
	key.keycode = code
	key.pressed = true
	return key


# --- the gesture -------------------------------------------------------------------------


func test_the_brush_lays_a_side_on_release_and_erases_with_ctrl() -> void:
	var editor := _editor()
	var brush := WallBrush.new()
	brush.begin(Vector3(-3, 0, 0))
	brush.track(editor, Vector3(1, 0, 0), false)
	assert_not_null(brush.preview)
	assert_eq(brush.finish(editor), 1)
	assert_eq(_doc.walls.size(), 1)
	assert_true(brush.erase_at(editor, Vector3(-1, 0, 0)))
	assert_true(_doc.walls.is_empty())
	assert_false(brush.erase_at(editor, Vector3(-1, 0, 0)))
	assert_eq(brush.message(), WallBrush.NOTHING)
	brush.begin(Vector3(0, 0, 0))
	brush.track(editor, Vector3(0.05, 0, 0), false)
	assert_eq(brush.finish(editor), -1)
	assert_eq(brush.message(), WallBrush.SHORT)


func test_the_height_steps_within_the_kinds_range() -> void:
	var up := WallBrush.stepped_height(1.0, 100, Wall.Kind.STONE)
	assert_eq(up, Wall.MAX_HEIGHT_M[Wall.Kind.STONE])
	var down := WallBrush.stepped_height(1.0, -100, Wall.Kind.FENCE)
	assert_eq(down, Wall.MIN_HEIGHT_M[Wall.Kind.FENCE])
	var brush := WallBrush.new()
	brush.kind = Wall.Kind.FENCE
	var before := brush.height()
	brush.step_height(2)
	assert_gt(brush.height(), before)


# --- the tool ----------------------------------------------------------------------------


func test_the_tool_is_registered_with_a_pane_and_a_brush() -> void:
	var tool := ToolRegistry.find(WallTool.ID)
	assert_not_null(tool)
	assert_true(tool.exists_in(ToolDescriptor.AUTHORING))
	assert_true(tool.exists_in(ToolDescriptor.PLAY), "and by the GM in play")
	assert_eq(tool.brush_mode, WallBrush)
	var pane := WallToolPane.new()
	add_child_autofree(pane)
	assert_eq(WallToolPane.KIND_TILES.size(), Wall.Kind.size(), "a tile per kind")
	for tile in WallToolPane.KIND_TILES:
		assert_not_null(IconButton.load_icon(String(tile.icon)), String(tile.icon))
	assert_eq(pane.kind_field.tiles.selected, &"wall_stone", "Stone preselected")
	watch_signals(pane)
	pane.kind_field.tiles.selection_changed.emit(&"wall_fence")
	assert_signal_emitted_with_parameters(pane, "kind_selected", [Wall.Kind.FENCE])
	pane.select_kind(Wall.Kind.STONE)
	assert_signal_emit_count(pane, "kind_selected", 1, "select_kind is silent")


# --- the peer's copy ---------------------------------------------------------------------


func test_a_live_edit_carries_a_wall_to_a_peer() -> void:
	var host := _editor()
	var entries: Array[Dictionary] = []
	_history.recorded.connect(func(entry: Dictionary) -> void: entries.append(entry))
	host.walls.place(Wall.Kind.FENCE, Vector3(-3, 0, 0), Vector3(1, 0, 0))
	assert_eq(entries.size(), 1)
	var op := LiveEditCodec.op_of(entries[0], host)
	assert_eq(op.kind, "walls")
	var peer_doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), peer_doc)
	assert_eq(decoded.problem, "")
	var peer_map := Node3D.new()
	add_child_autofree(peer_map)
	peer_map.add_child(AuthoredTerrain.create(peer_doc))
	var peer := AuthoringEditor.create(peer_doc, peer_map, AuthoringHistory.new())
	LiveEditCodec.apply(decoded.op, peer)
	assert_eq(peer_doc.walls.size(), 1)
	assert_true(peer_doc.walls[0].same_as(_doc.walls[0]))
	assert_not_null(peer_map.get_node(AuthoredWalls.NODE_NAME).get_node_or_null("Wall_1"))


func test_a_live_edit_with_a_bad_wall_is_refused() -> void:
	var bad := MapWallIO.wall_json(_wall())
	bad["height_m"] = 99.0
	var op := {"v": LiveEditCodec.VERSION, "kind": "walls", "args": [[bad], Rect2()], "redo": true}
	var decoded := LiveEditCodec.decode(LiveEditCodec.encode(op), _doc)
	assert_ne(decoded.problem, "")
