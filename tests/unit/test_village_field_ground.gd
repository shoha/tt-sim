extends GutTest

## What a village's fields do to the ground round them (topic fields round 3,
## docs/systems/villages.md section 11; VillageFieldGround): the paint lands under the field's ring
## (not mirrored or offset), the scatter grows no wild plant over a field while it still grows
## beside it, an edit asks the scatter to regrow exactly the changed fields, and a field that would
## cover a building is refused by the editor and by the Village tool's ghost.

const AT := Vector2(6, -14)
const RADIUS := 6.0

var _map: Node3D = null
var _doc: MapDocument = null
var _history: AuthoringHistory = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(40, 40), "grass", "v", 9)
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


## A dressed farming hamlet on a street along z = 0, x -12..12; its id.
func _hamlet(editor: AuthoringEditor) -> int:
	var street := editor.walls.place(
		Wall.Kind.ROW, Vector3(-12, 0, 0), Vector3(12, 0, 0), -1.0, {"seed": 5, "side": 2, "preset": 3}
	)
	return editor.settlements.dress(street, "farming_hamlet")


## The summed weight (0..255) of the painted surfaces in `surfaces` at map point `p`.
func _painted(p: Vector2, surfaces: Array[String]) -> int:
	var s := _doc.world_to_sample(p).round()
	var index := _doc.sample_index(int(s.x), int(s.y))
	var total := 0
	for surface in surfaces:
		total += _doc.surface_weight(index, _doc.surface_ids.find(surface))
	return total


func _sampler() -> Callable:
	return ScatterGround.sampler(
		_doc,
		_doc.heights,
		Rect2i(0, 0, _doc.samples_x(), _doc.samples_z()),
		PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
		PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	)


func test_the_paint_lands_under_the_ring_not_mirrored() -> void:
	var editor := _editor()
	var id := _hamlet(editor)
	assert_true(editor.settlements.add_field(id, AT, RADIUS, "crops"))
	var field := _doc.settlement(id).fields[0]
	var surfaces := VillageFields.surfaces_of(field, _doc.settlement(id).seed_value)
	var inside: Array[Vector2] = [
		Vector2.ZERO, Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3)
	]
	for offset in inside:
		assert_gt(_painted(AT + offset, surfaces), 240, "earth or rows cover %s" % [AT + offset])
	for away: Vector2 in [
		Vector2(-AT.x, AT.y), Vector2(AT.x, -AT.y), -AT, AT + Vector2(RADIUS + 3.0, 0)
	]:
		assert_eq(_painted(away, surfaces), 0, "nothing painted at %s" % [away])


func test_no_wild_plant_grows_over_a_field_and_the_meadow_grows_beside_it() -> void:
	var editor := _editor()
	var id := _hamlet(editor)
	var sampler := _sampler()
	var bare: Vector3 = sampler.call(AT, ScatterGround.ROLE_COVER)
	assert_almost_eq(bare.x, 1.0, 0.01, "the meadow grows there before the field")
	# An orchard clears too: its own trees are not scatter (AuthoredFieldPlants), the wild ones go.
	assert_true(editor.settlements.add_field(id, AT, RADIUS, "orchard"))
	sampler = _sampler()
	for role: int in [
		ScatterGround.ROLE_COVER,
		ScatterGround.ROLE_TALL_COVER,
		ScatterGround.ROLE_SHRUB,
		ScatterGround.ROLE_TREE,
		ScatterGround.ROLE_ROCK,
	]:
		for offset: Vector2 in [Vector2.ZERO, Vector2(RADIUS - 1.0, 0), Vector2(0, 1.0 - RADIUS)]:
			var open: Vector3 = sampler.call(AT + offset, role)
			assert_almost_eq(open.x, 0.0, 0.01, "role %d cleared at %s" % [role, AT + offset])
	var beside: Vector3 = sampler.call(AT + Vector2(RADIUS + 4.0, 0), ScatterGround.ROLE_COVER)
	assert_almost_eq(beside.x, 1.0, 0.01, "the meadow still grows four metres past the rim")
	# The scatter's workers read a snapshot: it must carry the fields (round 3 found it did not).
	var strips := VillageFieldGround.clearance_crossings(_doc).size()
	assert_gt(strips, 0)
	var worker := ScatterRegen.snapshot(_doc)
	assert_eq(VillageFieldGround.clearance_crossings(worker).size(), strips, "the regen snapshot")
	var rocks := RockKeep.snapshot(_doc, _doc.heights)
	assert_eq(VillageFieldGround.clearance_crossings(rocks).size(), strips, "the rock snapshot")


func test_an_edit_regrows_exactly_the_changed_fields() -> void:
	var record := Settlement.make(1, "farming_hamlet", 1, 5)
	var other := Settlement.make(2, "market_town", 2, 7)
	other.fields.append({"at": Vector2(-20, 20), "radius": 4.0, "kind": "garden"})
	var before: Array[Settlement] = [record, other]
	var grown := record.copy()
	grown.fields.append({"at": AT, "radius": RADIUS, "kind": "crops"})
	var after: Array[Settlement] = [grown, other]
	var area := VillageFieldGround.area_of(before, after)
	assert_true(area.has_point(AT + Vector2(RADIUS, 0)), "the new field's rim")
	assert_false(area.has_point(Vector2(-20, 20)), "the untouched village's garden")
	assert_eq(VillageFieldGround.area_of(after, before), area, "the undo regrows the same ground")
	assert_false(VillageFieldGround.area_of(after, after).has_area(), "no field changed")
	var gone: Array[Settlement] = [grown]
	assert_true(
		VillageFieldGround.area_of(after, gone).has_point(Vector2(-20, 20)),
		"a cleared village gives its fields' ground back"
	)


func test_a_field_over_a_house_is_refused_by_the_editor_and_the_ghost() -> void:
	var editor := _editor()
	var id := _hamlet(editor)
	var plans := VillageFieldGround.footprints(_doc)
	assert_gt(plans.size(), 0, "the street's houses are footprints")
	# The house nearest the field's place (the street's houses stand 3 to 9.4 m each side of it).
	var house := Vector2.INF
	for plan in plans:
		var middle := Vector2.ZERO
		for corner in plan:
			middle += corner / plan.size()
		if middle.distance_to(AT) < house.distance_to(AT):
			house = middle
	var fields := _doc.settlement(id).fields.size()
	var entries := _history.undo_count()
	assert_false(editor.settlements.add_field(id, house, 4.0, "crops"))
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_BUILDING)
	assert_eq(_doc.settlement(id).fields.size(), fields, "nothing recorded")
	assert_eq(_history.undo_count(), entries, "no history entry")
	assert_eq(
		VillageBrush.refusal_text(SettlementEditor.REFUSED_BUILDING), VillageBrush.ON_BUILDING
	)
	var brush := VillageBrush.new()
	brush.set_lay(true, "crops")
	assert_eq(brush.refusal_at(_doc, id, house), VillageBrush.ON_BUILDING, "the ghost says so")
	assert_eq(VillageRings.short_refusal(VillageBrush.ON_BUILDING), VillageBrush.ON_BUILDING_SHORT)
	assert_eq(
		brush.refusal_at(_doc, id, AT), VillageBrush.ON_BUILDING, "a click's 8 m disc reaches a house"
	)
	assert_eq(brush.refusal_at(_doc, id, AT, true), "", "a press there may drag a smaller field")
	assert_eq(brush.refusal_at(_doc, id, AT + Vector2(0, -6)), "", "open ground is fine")
	assert_true(editor.settlements.add_field(id, AT, RADIUS, "crops"))
	var index := _doc.settlement(id).fields.size() - 1
	var reach := house.distance_to(AT) + 2.0
	assert_false(editor.settlements.resize_field(id, index, reach), "growing over the house")
	assert_eq(editor.settlements.last_refusal, SettlementEditor.REFUSED_BUILDING)
