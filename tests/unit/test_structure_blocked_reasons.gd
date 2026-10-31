extends GutTest

## The Buildings tool's live reason for a spot that will not take a building (check G3, 2026-10-31).
## Each crafted bad spot is hovered or dragged through the real StructureBrush, the ghost's note is
## worked out as the draw does (StructureBrush._refresh_note), and the note's words are compared
## with the brush's own constants: water, steep ground, off the map, a building already there, a
## full map, an unknown building, an unwritable plan, and the size stops. A good spot has no note.

const COTTAGE := "core:cottage"
const UNITS: Array = [1.0, 3.0, "ft"]

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


func _brush(ref: String = COTTAGE) -> StructureBrush:
	var brush := StructureBrush.new()
	brush.pick(ref)
	return brush


## The ghost's note after the pointer rests over `hit`, as the draw works it out.
func _hover_note(editor: AuthoringEditor, brush: StructureBrush, hit: Vector3) -> Dictionary:
	brush.track(editor, hit, 0.0)
	brush._refresh_note(editor.map_scale(), UNITS, brush.problem == "")
	return brush.note


func _flood() -> void:
	var half := _doc.extent_m() * 0.5
	var line := PackedVector2Array([Vector2(0, -half.y), Vector2(0, half.y)])
	# Wider than the nearest-legal reach (7 m) plus a lot, but leaving dry land at the map's edge.
	var wide := minf(12.0, half.x * 0.8)
	var widths := PackedFloat32Array([wide, wide])
	_doc.water_bodies.append(WaterBody.river(1, line, widths, WaterBody.Depth.WAIST, 1.0))
	for k in _doc.heights.size():
		_doc.heights[k] = 0.0


func _tilt(rise: float) -> void:
	var heights := _doc.heights.duplicate()
	for z in _doc.samples_z():
		for x in _doc.samples_x():
			heights[_doc.sample_index(x, z)] = rise * _doc.sample_to_world(Vector2(x, z)).x
	_doc.heights = heights


func test_a_good_spot_has_no_reason() -> void:
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3(2.0, 0.0, 1.0))
	assert_eq(note["text"], "", "no words")
	assert_eq(note["level"], StructureNote.Level.NONE)
	assert_eq(_brush().problem, "")


func test_water_all_round_says_not_on_the_water() -> void:
	_flood()
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3.ZERO)
	assert_eq(note["text"], StructureBrush.WATER_TEXT)
	assert_eq(note["level"], StructureNote.Level.BLOCKED)
	gut.p("water: %s" % note["text"])


func test_steep_ground_all_round_says_too_steep() -> void:
	_tilt(0.9)
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3.ZERO)
	assert_eq(note["text"], StructureBrush.STEEP_TEXT)
	assert_eq(note["level"], StructureNote.Level.BLOCKED)
	gut.p("steep: %s" % note["text"])


func test_far_off_the_map_says_keep_it_on_the_map() -> void:
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3(400.0, 0.0, 0.0))
	assert_eq(note["text"], StructureBrush.OFF_MAP_TEXT)
	assert_eq(note["level"], StructureNote.Level.BLOCKED)
	gut.p("off map: %s" % note["text"])


func test_a_map_filled_by_one_building_says_there_is_one_already() -> void:
	var extent := _doc.extent_m()
	_doc.structures.append(
		Structure.make(
			1, COTTAGE, StructurePlacement.rect_plan(Vector2.ZERO, extent * 0.95, 0.0), 5
		)
	)
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3(1.0, 0.0, 1.0))
	assert_eq(note["text"], StructureBrush.OCCUPIED_TEXT)
	assert_eq(note["level"], StructureNote.Level.BLOCKED)
	gut.p("occupied: %s" % note["text"])


func test_a_full_map_refuses_the_release_with_its_words() -> void:
	for k in MapDocument.MAX_STRUCTURES:
		var plan := StructurePlacement.rect_plan(Vector2(-9.0, -9.0), Vector2(0.6, 0.6), 0.0)
		_doc.structures.append(Structure.make(k + 1, COTTAGE, plan, 5))
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3(3.0, 0.0, 3.0))
	brush.track(editor, Vector3(6.0, 0.0, 6.0), 0.0)
	brush._refresh_note(editor.map_scale(), UNITS, false)
	assert_eq(brush.note["text"], StructureBrush.FULL_TEXT, "the live note while sizing")
	assert_eq(brush.note["level"], StructureNote.Level.BLOCKED)
	assert_eq(brush.finish(editor), -1, "nothing is laid")
	assert_eq(brush.message(), StructureBrush.FULL_TEXT, "and the toast says why")
	assert_eq(_doc.structures.size(), MapDocument.MAX_STRUCTURES)
	gut.p("full: %s" % brush.message())


func test_an_unknown_building_and_an_unwritable_plan_say_their_words() -> void:
	var editor := _editor()
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	assert_null(editor.structures.lot("core:no_such_house", plan, 1))
	assert_eq(
		StructureBrush.refusal_text(editor.structures.last_refusal), StructureBrush.UNKNOWN_TEXT
	)
	var sliver := PackedVector2Array(
		[Vector2(0, 0), Vector2(6, 0), Vector2(6, 0.1), Vector2(0, 0.1)]
	)
	assert_null(editor.structures.lot(COTTAGE, sliver, 1))
	assert_eq(
		StructureBrush.refusal_text(editor.structures.last_refusal), StructureBrush.INVALID_TEXT
	)
	var note := StructureNote.live(String(editor.structures.last_refusal), "", false, "")
	assert_eq(note["text"], StructureBrush.INVALID_TEXT)
	assert_eq(note["level"], StructureNote.Level.BLOCKED)


func test_a_small_or_huge_drag_says_which_size_stop_held_it() -> void:
	var editor := _editor()
	var brush := _brush()
	brush.begin(Vector3(-5.0, 0.0, -5.0))
	brush.track(editor, Vector3(-4.0, 0.0, -4.0), 0.0)
	brush._refresh_note(editor.map_scale(), UNITS, brush.problem == "" and brush.preview != null)
	assert_string_starts_with(String(brush.note["text"]), "Smallest size this building goes")
	assert_eq(brush.note["level"], StructureNote.Level.NOTE, "amber: a release still lays it")
	brush.cancel(null)
	brush.begin(Vector3(-9.0, 0.0, -9.0))
	brush.track(editor, Vector3(60.0, 0.0, 9.0), 0.0)
	brush._refresh_note(editor.map_scale(), UNITS, brush.problem == "" and brush.preview != null)
	assert_string_starts_with(String(brush.note["text"]), "Biggest size this building goes")
	gut.p("size stops: %s" % brush.note["text"])


func test_a_lot_eased_off_narrow_water_says_it_moved() -> void:
	var line := PackedVector2Array([Vector2(0, -14), Vector2(0, 14)])
	_doc.water_bodies.append(
		WaterBody.river(1, line, PackedFloat32Array([1.0, 1.0]), WaterBody.Depth.WAIST, 1.0)
	)
	for k in _doc.heights.size():
		_doc.heights[k] = 0.0
	var editor := _editor()
	var note := _hover_note(editor, _brush(), Vector3.ZERO)
	assert_eq(note["text"], StructureNote.MOVED_WATER)
	assert_eq(note["level"], StructureNote.Level.NOTE)
