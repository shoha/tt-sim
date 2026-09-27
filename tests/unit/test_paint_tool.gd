extends GutTest

## The Paint tool (phase 3, P3-6): SurfaceStroke's slot claim, reuse and limit, painting
## and erasing with the newest paint winning, stroke-level undo and redo through
## AuthoringEditor, the cliff-face rule on the CPU (TerrainRules.compose_paint, ScatterGround:
## ground and built paint yield to the automatic rock, painted rock does not), built paint
## clearing plants, and Paint being unavailable on a dressed Blender map. Uses the built-in
## palette's surfaces and temperate forest.

const FOREST := "temperate_forest_summer_s1"
const DENSITY := 128
## The tier step of _step_doc() runs along world x = STEP_X.
const STEP_X := 3.0
const EIGHT := [
	"cobblestone", "flagstone", "planks", "stone_tiles", "dirt", "gravel", "moss", "sand"
]

var _map: Node3D = null
var _history: AuthoringHistory = null
var _doc: MapDocument = null


func before_each() -> void:
	_map = Node3D.new()
	_map.name = "LevelMap"
	add_child_autofree(_map)
	_history = AuthoringHistory.new()
	_doc = MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)


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


func _weight_at(world: Vector2, slot: int) -> int:
	var s := _doc.world_to_sample(world).round()
	return _doc.surface_weight(_doc.sample_index(int(s.x), int(s.y)), slot)


func _paint(surface: String, from: Vector2, to: Vector2, seconds: float = 2.0) -> Dictionary:
	var stroke := SurfaceStroke.begin(_doc, surface, false)
	assert_not_null(stroke, "a slot for %s" % surface)
	if stroke == null:
		return {}
	stroke.dab(from, to, 1.5, seconds)
	return stroke.finish()


func _snapshot() -> Dictionary:
	return {"ids": _doc.surface_ids.duplicate(), "weights": _doc.surface_weights.duplicate()}


# --- Slots ------------------------------------------------------------------------------


func test_the_first_dab_claims_a_slot_and_allocates_the_weights() -> void:
	assert_true(_doc.surface_weights.is_empty())
	_paint("cobblestone", Vector2(-5, 0), Vector2(5, 0))
	assert_eq(_doc.surface_ids, PackedStringArray(["cobblestone"]))
	assert_eq(_doc.surface_weights.size(), _doc.sample_count() * MapDocument.MAX_SURFACES)
	assert_gt(_weight_at(Vector2(0, 0), 0), 240, "the core is covered after a long dwell")
	assert_eq(_weight_at(Vector2(0, 3), 0), 0, "nothing past the brush")
	_paint("cobblestone", Vector2(-5, 4), Vector2(5, 4))
	assert_eq(_doc.surface_ids.size(), 1, "the same surface keeps its slot")


func test_a_ninth_surface_is_refused_until_one_is_erased_completely() -> void:
	for k in EIGHT.size():
		_paint(EIGHT[k], Vector2(-8 + 2 * k, -6), Vector2(-8 + 2 * k, -4), 1.0)
	assert_eq(_doc.surface_ids.size(), MapDocument.MAX_SURFACES)
	assert_null(SurfaceStroke.begin(_doc, "mud", false), "every slot holds paint")
	var before := _snapshot()
	assert_eq(before.ids.size(), 8, "a refused begin changes nothing")
	# Erase the whole map for a long time: every slot empties. The trailing ones are trimmed.
	var erase := SurfaceStroke.begin(_doc, "", true)
	erase.dab(Vector2(-8, -5), Vector2(8, -5), 3.0, 8.0)
	erase.finish()
	assert_true(_doc.surface_ids.is_empty(), "fully erased slots are freed")
	assert_true(_doc.surface_weights.is_empty(), "and the weights with the last one")


func test_a_fully_erased_middle_slot_is_reused() -> void:
	for k in EIGHT.size():
		_paint(EIGHT[k], Vector2(-8 + 2 * k, -6), Vector2(-8 + 2 * k, -4), 1.0)
	# Erase around the third surface's patch (x = -4), long enough to clear it; its
	# neighbours reach further out and keep some paint.
	var erase := SurfaceStroke.begin(_doc, "", true)
	erase.dab(Vector2(-4, -6), Vector2(-4, -4), 3.0, 8.0)
	erase.finish()
	assert_true(_doc.surface_slot_unused(2), "its slot has no paint left")
	assert_eq(_doc.surface_ids.size(), 8, "a middle slot is not trimmed")
	var stroke := SurfaceStroke.begin(_doc, "mud", false)
	assert_not_null(stroke, "the empty slot is taken")
	assert_eq(stroke.slot, 2)
	assert_eq(_doc.surface_ids[2], "mud")


# --- Painting and erasing ---------------------------------------------------------------


func test_the_newest_paint_wins_and_weights_never_overfill() -> void:
	_paint("cobblestone", Vector2(-5, 0), Vector2(5, 0))
	var before := _weight_at(Vector2.ZERO, 0)
	_paint("flagstone", Vector2(-1, 0), Vector2(1, 0), 0.4)
	var cobble := _weight_at(Vector2.ZERO, 0)
	var flag := _weight_at(Vector2.ZERO, 1)
	assert_gt(flag, 0)
	assert_lt(cobble, before, "the older paint makes room")
	assert_true(cobble + flag <= 255, "a sample never sums past 255")
	assert_gt(cobble + flag, 245, "and stays covered")


func test_erase_fades_every_slot_toward_the_automatic_ground() -> void:
	_paint("cobblestone", Vector2(-5, 0), Vector2(5, 0))
	_paint("moss", Vector2(-5, 0), Vector2(5, 0), 0.3)
	var cobble := _weight_at(Vector2.ZERO, 0)
	var moss := _weight_at(Vector2.ZERO, 1)
	assert_true(cobble > 0 and moss > 0)
	var erase := SurfaceStroke.begin(_doc, "", true)
	erase.dab(Vector2.ZERO, Vector2.ZERO, 2.0, 0.1)
	var c2 := _weight_at(Vector2.ZERO, 0)
	var m2 := _weight_at(Vector2.ZERO, 1)
	assert_lt(c2, cobble, "every slot fades")
	assert_lt(m2, moss)
	assert_almost_eq(float(c2) / cobble, float(m2) / moss, 0.05, "by the same factor")
	erase.dab(Vector2.ZERO, Vector2.ZERO, 2.0, 4.0)
	assert_eq(_weight_at(Vector2.ZERO, 0), 0, "a held erase clears the core")
	assert_eq(_weight_at(Vector2.ZERO, 1), 0)


func test_erase_without_paint_does_nothing() -> void:
	assert_null(SurfaceStroke.begin(_doc, "", true))
	assert_null(SurfaceStroke.begin(_doc, "", false), "paint needs a surface")


# --- Editor: undo, redo, cancel ---------------------------------------------------------


func test_paint_and_erase_strokes_undo_and_redo_exactly() -> void:
	var editor := _editor()
	var edits := [0]
	editor.edited.connect(func() -> void: edits[0] += 1)
	var empty := _snapshot()
	assert_true(editor.begin_surface_stroke("cobblestone", false))
	editor.stroke_dab(Vector3(-4, 0, 0), Vector3(4, 0, 1), 2.0, 1.0)
	editor.flush()
	assert_true(editor.end_stroke())
	var painted := _snapshot()
	assert_true(editor.begin_surface_stroke("moss", false))
	editor.stroke_dab(Vector3(0, 0, -3), Vector3(0, 0, 3), 2.0, 0.5)
	editor.flush()
	editor.end_stroke()
	var mossy := _snapshot()
	assert_true(editor.begin_surface_stroke("", true))
	editor.stroke_dab(Vector3(-7, 0, 0), Vector3(7, 0, 0), 8.0, 10.0)
	editor.end_stroke()
	var erased := _snapshot()
	assert_eq(edits[0], 3)
	assert_eq(_history.undo_count(), 3, "one entry per stroke")
	assert_true(erased.ids.is_empty(), "everything erased: the slots are freed")
	_history.undo()
	assert_eq(_snapshot(), mossy)
	_history.undo()
	assert_eq(_snapshot(), painted)
	_history.undo()
	assert_eq(_snapshot(), empty)
	_history.redo()
	assert_eq(_snapshot(), painted)
	_history.redo()
	_history.redo()
	assert_eq(_snapshot(), erased)
	var terrain := _map.get_node("AuthoredTerrain") as AuthoredTerrain
	assert_false(terrain.ground_layers().is_empty(), "the ground drew the paint")


func test_a_cancelled_paint_stroke_leaves_no_trace() -> void:
	var editor := _editor()
	var before := _snapshot()
	assert_true(editor.begin_surface_stroke("flagstone", false))
	editor.stroke_dab(Vector3.ZERO, Vector3(3, 0, 0), 2.0, 1.0)
	editor.flush()
	editor.cancel_stroke()
	assert_eq(_snapshot(), before, "the slot and the weights are given back")
	assert_eq(_history.undo_count(), 0)
	assert_true(editor.begin_surface_stroke("flagstone", false))
	assert_false(editor.end_stroke(), "a stroke with no dab records nothing")
	assert_eq(_snapshot(), before)


func test_the_refusal_says_why_when_every_slot_holds_paint() -> void:
	var editor := _editor()
	for k in EIGHT.size():
		_paint(EIGHT[k], Vector2(-8 + 2 * k, -6), Vector2(-8 + 2 * k, -4), 1.0)
	assert_eq(editor.surface_refusal("mud"), SurfaceStroke.FULL_REASON)
	assert_eq(editor.surface_refusal("moss"), "", "a surface already painted can be painted")
	assert_false(editor.begin_surface_stroke("mud", false))


# --- Dressed maps -----------------------------------------------------------------------


func test_paint_is_unavailable_on_a_dressed_map() -> void:
	_doc.has_base_map = true
	var editor := _editor()
	assert_false(editor.can_paint())
	assert_false(editor.begin_surface_stroke("cobblestone", false))
	assert_ne(editor.surface_refusal("cobblestone"), "", "and says why")
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	var rail: IconRail = panel.get("_rail")
	var item: Button = (rail.get("_buttons") as Dictionary)[AuthoringPanel.TOOL_PAINT]
	assert_false(item.disabled, "available by default")
	panel.set_paint_available(false)
	assert_true(item.disabled)
	assert_eq(item.tooltip_text, AuthoringPanel.PAINT_UNAVAILABLE_TOOLTIP)
	panel.set_paint_available(true)
	assert_false(item.disabled)


# --- Panel ------------------------------------------------------------------------------


func test_paint_tiles_are_grouped_by_role_with_readable_names() -> void:
	var panel := AuthoringPanel.new()
	add_child_autofree(panel)
	panel.ensure_paint_tiles()
	var built: TileField = panel.paint_fields["built"]
	var rock: TileField = panel.paint_fields["cliff"]
	var ground: TileField = panel.paint_fields["ground"]
	assert_true(built.tiles.has_tile(AuthoringPanel.paint_tile_id("cobblestone")))
	assert_true(built.tiles.has_tile(AuthoringPanel.paint_tile_id("dirt_road_packed")))
	assert_true(rock.tiles.has_tile(AuthoringPanel.paint_tile_id("cliff_basalt")))
	assert_true(ground.tiles.has_tile(AuthoringPanel.paint_tile_id("moss")))
	assert_false(ground.tiles.has_tile(AuthoringPanel.paint_tile_id("cobblestone")))
	assert_eq(AuthoringPanel.surface_label("dirt_road_packed"), "Dirt track")
	assert_eq(AuthoringPanel.surface_label("cliff_basalt"), "Basalt")
	assert_eq(AuthoringPanel.surface_label("some_new_thing"), "Some new thing")
	assert_eq(
		AuthoringPanel.paint_tile_surface(AuthoringPanel.paint_tile_id("stone_tiles")),
		"stone_tiles"
	)
	assert_eq(built.tiles.selected, AuthoringPanel.paint_tile_id("dirt_road_packed"))
	# All eight slots taken: the others are disabled and say why.
	panel.set_paint_limits("full", PackedStringArray(["cobblestone"]))
	var cobble := built.tiles.get_node("paint_cobblestone") as Button
	var flag := built.tiles.get_node("paint_flagstone") as Button
	assert_false(cobble.disabled)
	assert_true(flag.disabled)
	assert_eq(flag.tooltip_text, "full")
	panel.set_paint_limits("", PackedStringArray())
	assert_false(flag.disabled)


func test_paint_presses_are_brush_strokes() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	var mode := BrushTool.Mode.PAINT
	assert_eq(BrushTool.decide(press, mode, false, false), BrushTool.Action.BEGIN)
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	assert_eq(BrushTool.decide(rmb, mode, true, false), BrushTool.Action.CANCEL)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	wheel.shift_pressed = true
	assert_eq(BrushTool.decide(wheel, mode, false, false), BrushTool.Action.SHRINK)


# --- The cliff-face rule on the CPU -----------------------------------------------------


func test_compose_paint_yields_ground_and_built_paint_to_the_rock() -> void:
	# Flat ground: a full road stays a road.
	var flat := TerrainRules.compose_paint(1.0, 0.0, Vector2(0.0, 0.0))
	assert_almost_eq(flat.w, 1.0, 1e-6)
	assert_almost_eq(flat.y, 0.0, 1e-6)
	# A full face: the road gives all of it to the rock.
	var face := TerrainRules.compose_paint(1.0, 0.0, Vector2(1.0, 0.0))
	assert_almost_eq(face.w, 0.0, 1e-6)
	assert_almost_eq(face.y, 1.0, 1e-6)
	# Half paint on a half-rock slope with some scree: shares add up to 1.
	var mixed := TerrainRules.compose_paint(0.5, 0.0, Vector2(0.4, 0.2))
	var total := mixed.x + mixed.y + mixed.z + 0.5 * mixed.w
	assert_almost_eq(total, 1.0, 1e-6)
	assert_almost_eq(mixed.y, 0.5 * 0.4 + 0.5 * 0.4, 1e-6, "rock over both halves")
	assert_almost_eq(mixed.z, 0.5 * 0.2, 1e-6, "scree only over the unpainted half")
	# Painted rock holds on a face.
	var held := TerrainRules.compose_paint(0.0, 1.0, Vector2(1.0, 0.0))
	assert_almost_eq(held.y, 0.0, 1e-6, "no automatic rock under painted rock")
	assert_almost_eq(held.x, 0.0, 1e-6)


func _step_doc() -> MapDocument:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "test", 21)
	doc.biome_ids = PackedStringArray([FOREST])
	var slots := PackedByteArray()
	var density := PackedByteArray()
	slots.resize(doc.sample_count())
	density.resize(doc.sample_count())
	slots.fill(1)
	density.fill(DENSITY)
	doc.biome_slots = slots
	doc.biome_density = density
	for z in doc.samples_z():
		for x in doc.samples_x():
			if doc.sample_to_world(Vector2(x, z)).x > STEP_X:
				doc.heights[doc.sample_index(x, z)] = 1.524
	return doc


func _fill(doc: MapDocument, surface: String, low: Vector2, high: Vector2) -> void:
	var slot := doc.ensure_surface(surface)
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x >= low.x and p.x <= high.x and p.y >= low.y and p.y <= high.y:
				doc.set_surface_weight(doc.sample_index(x, z), slot, 255)


func _fields(doc: MapDocument) -> Dictionary:
	return ScatterGenerator.document_fields(
		doc,
		FOREST,
		Rect2(),
		PackedStringArray(PaletteLibrary.surfaces_with_role("built")),
		PackedStringArray(PaletteLibrary.surfaces_with_role("cliff"))
	)


func _face_x(doc: MapDocument) -> float:
	var s := doc.world_to_sample(Vector2(STEP_X, 0.0)).x
	return doc.sample_to_world(Vector2(floorf(s) + 0.5, 0.0)).x


func test_a_road_across_a_face_stops_at_the_rock() -> void:
	var doc := _step_doc()
	_fill(doc, "cobblestone", Vector2(-6, -1.5), Vector2(10, 1.5))
	var sampler := ScatterGround.sampler(
		doc,
		doc.heights,
		Rect2i(0, 0, doc.samples_x(), doc.samples_z()),
		PackedStringArray(["cobblestone"]),
		PackedStringArray(["cliff"])
	)
	var face: Vector3 = sampler.call(Vector2(_face_x(doc), 0.0))
	assert_gt(face.y, 0.95, "the face under the road is the automatic rock")
	assert_lt(face.x, 0.05, "nothing grows on it")
	var low: Vector3 = sampler.call(Vector2(-3.0, 0.0))
	var top: Vector3 = sampler.call(Vector2(7.0, 0.0))
	assert_almost_eq(low.y, 0.0, 1e-6, "below the ledge it is road, not rock")
	assert_almost_eq(top.y, 0.0, 1e-6, "and again on top")
	assert_almost_eq(low.x, 0.0, 1e-6, "the road clears the plants")


func test_painted_ground_no_longer_overrides_the_rock_but_painted_rock_holds() -> void:
	var doc := _step_doc()
	_fill(doc, "grass", Vector2(STEP_X - 2.0, -4), Vector2(STEP_X + 2.0, 4))
	var fields := _fields(doc)
	var face: float = fields.density_at.call(Vector2(_face_x(doc), 0.0))
	assert_lt(face, 0.01, "grass painted over the face: still rock, nothing grows")
	var beside: float = fields.density_at.call(Vector2(STEP_X - 1.5, 0.0))
	assert_almost_eq(beside, DENSITY / 255.0, 1e-6, "painted grass on flat ground grows")
	var rock_doc := _step_doc()
	_fill(rock_doc, "cliff_basalt", Vector2(-10, -2), Vector2(-6, 2))
	var rock_fields := _fields(rock_doc)
	assert_eq(rock_fields.density_at.call(Vector2(-8.0, 0.0)), 0.0, "painted rock is bare")
	var off: float = rock_fields.density_at.call(Vector2(-8.0, 5.0))
	assert_almost_eq(off, DENSITY / 255.0, 1e-6, "beside it plants grow")


func test_partial_paving_clears_plants_steeply() -> void:
	# A quick pass leaves a road at about 0.75 of full cover: the shader draws it as road, so
	# plants clear there completely (ScatterGround.PAVED_CLEAR_*); a faint fringe keeps them.
	var doc := _step_doc()
	var slot := doc.ensure_surface("dirt_road_packed")
	for z in doc.samples_z():
		for x in doc.samples_x():
			var p := doc.sample_to_world(Vector2(x, z))
			if p.x < -7.0:
				doc.set_surface_weight(doc.sample_index(x, z), slot, 191)
			elif p.x < -3.0:
				doc.set_surface_weight(doc.sample_index(x, z), slot, 5)
	var fields := _fields(doc)
	var base := DENSITY / 255.0
	var worst_road := 0.0
	var faint_low := base
	for k in 40:
		var z := -10.0 + k * 0.5
		worst_road = maxf(worst_road, fields.density_at.call(Vector2(-9.5, z)))
		faint_low = minf(faint_low, fields.density_at.call(Vector2(-5.0, z)))
	assert_lt(worst_road, 0.02 * base, "three quarters paved: nothing grows")
	assert_almost_eq(faint_low, base, 1e-6, "a faint fringe keeps its plants")


func test_built_paint_clears_plants_under_it_but_not_beside_it() -> void:
	var doc := _step_doc()
	_fill(doc, "dirt_road_packed", Vector2(-10, -1), Vector2(-4, 1))
	var fields := _fields(doc)
	var base := DENSITY / 255.0
	assert_eq(fields.density_at.call(Vector2(-7.0, 0.0)), 0.0, "on the track")
	assert_eq(fields.rock_density_at.call(Vector2(-7.0, 0.0)), 0.0, "rocks too")
	# A tree whose trunk stands a metre past the painted edge (beyond the 0.3 m edge warp
	# and the partial-paint noise) is untouched.
	assert_almost_eq(fields.density_at.call(Vector2(-7.0, 2.2)), base, 1e-6, "beside it")
