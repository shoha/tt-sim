extends GutTest

## Ornaments on a placed building (card ornaments_ui): StructureOrnaments' pure rules (the mask in
## the record's params, the ivy amount, the entries, Surprise me, the chip states), the build (more
## triangles, the ornament role and kinds, a ruin left plain), the edit (one history entry, undo,
## a restyle and a copy keep them, save and the live edit carry them) and the Decorate row.
## Summary: docs/systems/structures.md "Ornaments".

const COTTAGE := "core:cottage"
const KEEP := "core:castle_keep"
const RUIN := "core:ruin_cottage"
const CHIMNEYED := "core:cottage_chimneyed"

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


func _lay(editor: AuthoringEditor, ref: String = COTTAGE, centre: Vector2 = Vector2.ZERO) -> int:
	var plan := StructurePlacement.rect_plan(centre, Vector2(6, 4), 0.0)
	return editor.structures.add(editor.structures.lot(ref, plan, 100))


func _built(ref: String, params: Dictionary) -> Dictionary:
	var plan := StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0)
	return StructureGeometry.build_one(_doc, Structure.make(1, ref, plan, 7, params))


func _kinds_of(parts: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for mesh: Dictionary in parts["meshes"]:
		var key := "%s/%s" % [mesh["role"], mesh["kind"]]
		if not out.has(key):
			out.append(key)
	return out


# --- the pure rules ------------------------------------------------------------------------


func test_the_bits_name_procgens_kinds_and_every_kind_has_a_chip() -> void:
	var procgen: Array[String] = []
	procgen.assign(ProcgenOrnaments.KINDS)
	assert_eq(StructureOrnaments.KIND_BITS, procgen, "the mask bits are procgen's kinds in order")
	var chipped: Array[String] = []
	for item: Dictionary in StructureOrnaments.CHIPS:
		chipped.append(String(item["kind"]))
	chipped.sort()
	var sorted_bits := StructureOrnaments.KIND_BITS.duplicate()
	sorted_bits.sort()
	assert_eq(chipped, sorted_bits, "a chip for each of the nine")


func test_kinds_round_trip_through_the_mask_and_leave_other_params_alone() -> void:
	var params := {"floors": 2.0}
	var on := StructureOrnaments.with_kind(params, "vane", true)
	on = StructureOrnaments.with_kind(on, "ivy", true)
	assert_eq(StructureOrnaments.kinds_of(on), ["ivy", "vane"] as Array[String], "mask order")
	assert_eq(on["floors"], 2.0, "the recipe's parameter stays")
	assert_eq(params, {"floors": 2.0}, "the input is not touched")
	assert_eq(StructureOrnaments.mask_of(on), 1 + 16)
	var off := StructureOrnaments.with_kind(on, "vane", false)
	off = StructureOrnaments.with_kind(off, "ivy", false)
	assert_eq(off, {"floors": 2.0}, "none left removes the reserved entries")
	assert_eq(StructureOrnaments.mask_of({"ornaments": true}), 0, "a bool is no mask")
	assert_eq(StructureOrnaments.mask_of({"ornaments": 99999.0}), 511, "clamped to nine bits")
	assert_eq(StructureOrnaments.kinds_of({"ornaments": 2.0}), ["bartizan"] as Array[String])


func test_the_ivy_amount_is_stored_only_while_ivy_is_on_and_off_the_default() -> void:
	var plain := StructureOrnaments.with_ivy_amount({}, 0.9)
	assert_false(plain.has("ivy_amount"), "no ivy, no amount")
	var ivy := StructureOrnaments.with_kind({}, "ivy", true)
	assert_eq(StructureOrnaments.ivy_amount(ivy), StructureOrnaments.IVY_DEFAULT)
	var thick := StructureOrnaments.with_ivy_amount(ivy, 0.93)
	assert_almost_eq(StructureOrnaments.ivy_amount(thick), 0.95, 0.001, "snapped to a step")
	assert_false(
		StructureOrnaments.with_ivy_amount(thick, 0.55).has("ivy_amount"), "default erased"
	)
	assert_false(StructureOrnaments.with_kind(thick, "ivy", false).has("ivy_amount"), "ivy off")
	var entry := StructureOrnaments.entries(thick, 3)[0]
	assert_eq(entry["kind"], "ivy")
	assert_almost_eq(float(entry["coverage"]), 0.95, 0.001)
	assert_between(float(entry["height"]), 0.25, 1.0)


func test_painted_parts_draw_a_stable_colour_from_the_seed() -> void:
	var a := StructureOrnaments.paint_of(11, "awning")
	assert_eq(a, StructureOrnaments.paint_of(11, "awning"), "stable")
	assert_true(StructureOrnaments.PAINT.has(a))
	var seen := {}
	for seed_value in 40:
		seen[StructureOrnaments.paint_of(seed_value, "sign")] = true
	assert_gt(seen.size(), 3, "buildings do not all wear one colour")
	var entries := StructureOrnaments.entries(
		StructureOrnaments.with_kinds({}, ["sign", "ivy", "vane"]), 5
	)
	for entry in entries:
		assert_eq(entry.has("color"), entry["kind"] == "sign", "only painted parts take a colour")


func test_surprise_me_is_seeded_small_themed_and_skips_what_cannot_be_added() -> void:
	for theme: String in StructureOrnaments.THEMES:
		for draw in 12:
			var set_a := StructureOrnaments.surprise(theme, draw, ["ivy"])
			assert_eq(
				set_a, StructureOrnaments.surprise(theme, draw, ["ivy"]), "same draw, same set"
			)
			assert_between(set_a.size(), 2, 3, "%s draw %d" % [theme, draw])
			assert_false(set_a.has("ivy"), "a skipped kind is never drawn")
			var roof_tops := (1 if set_a.has("vane") else 0) + (1 if set_a.has("banner") else 0)
			assert_lte(roof_tops, 1, "one thing on the roof")
			for kind in set_a:
				assert_true(
					(StructureOrnaments.THEMES[theme] as Array).has(kind),
					"%s fits %s" % [kind, theme]
				)
	var seen := {}
	for draw in 30:
		seen[str(StructureOrnaments.surprise("home", draw))] = true
	assert_gt(seen.size(), 3, "pressing again gives another set")
	var none: Array[String] = []
	assert_eq(StructureOrnaments.surprise("fort", 1, StructureOrnaments.KIND_BITS), none)


func test_a_structures_theme_comes_from_its_name_family_and_tags() -> void:
	assert_eq(StructureOrnaments.theme_of({"name": "Castle keep", "family": "keep"}), "fort")
	assert_eq(StructureOrnaments.theme_of({"name": "Chapel", "family": "chapel"}), "chapel")
	assert_eq(StructureOrnaments.theme_of({"name": "Coaching inn", "family": "inn"}), "shop")
	assert_eq(StructureOrnaments.theme_of({"name": "Cottage", "family": "cottage"}), "home")
	assert_eq(StructureOrnaments.theme_of({}), "home")


# --- the build -----------------------------------------------------------------------------


func test_ornaments_add_geometry_in_the_ornament_role_and_the_walls_kind() -> void:
	var plain := _built(COTTAGE, {})
	var dressed := _built(COTTAGE, StructureOrnaments.with_kinds({}, ["ivy", "vane", "banner"]))
	assert_eq(String(dressed["problem"]), "", "builds")
	assert_gt(int(dressed["triangles"]), int(plain["triangles"]), "more triangles")
	var kinds := _kinds_of(dressed)
	assert_true("ornament/leaf" in kinds or "ornament/leaf_b" in kinds, "ivy keeps its leaves")
	assert_true("ornament/metal" in kinds, "the vane is metal")
	assert_true("ornament/cloth" in kinds, "the banner is cloth")
	for mesh: Dictionary in dressed["meshes"]:
		if mesh["role"] == StructureLook.ORNAMENT:
			assert_true(StructureLook.ORNAMENT_KINDS.has(String(mesh["kind"])), "only soft kinds")
	assert_eq(
		StructureGeometry.digest_of(_built(COTTAGE, {})),
		StructureGeometry.digest_of(plain),
		"a plain record builds as before"
	)


func test_the_same_record_builds_the_same_ornaments_every_time() -> void:
	var params := StructureOrnaments.with_kinds({}, ["rose", "sign", "flower_boxes", "awning"])
	var a := _built(CHIMNEYED, params)
	var b := _built(CHIMNEYED, params)
	assert_eq(StructureGeometry.digest_of(a), StructureGeometry.digest_of(b), "repeatable")
	assert_ne(
		StructureGeometry.digest_of(a),
		StructureGeometry.digest_of(_built(CHIMNEYED, {})),
		"and not the plain building"
	)


func test_the_hard_parts_of_a_keep_take_the_wall_role() -> void:
	var dressed := _built(KEEP, StructureOrnaments.with_kinds({}, ["buttress", "bartizan"]))
	assert_eq(String(dressed["problem"]), "")
	assert_gt(int(dressed["triangles"]), int(_built(KEEP, {})["triangles"]), "they added geometry")
	for mesh: Dictionary in dressed["meshes"]:
		if mesh["role"] == StructureLook.ORNAMENT:
			assert_true(StructureLook.ORNAMENT_KINDS.has(String(mesh["kind"])), "soft kinds only")


func test_a_ruin_and_a_stepped_ruin_take_no_ornaments() -> void:
	var params := StructureOrnaments.with_kinds({}, ["ivy", "vane"])
	var ruin := StructureRecipes.document(RUIN)
	assert_ne(StructureOrnaments.problem_for(ruin, params), "", "a ruin recipe is refused")
	assert_eq(StructureOrnaments.apply(ruin, params, 1), 0, "and nothing is added")
	var cottage := StructureRecipes.document(COTTAGE)
	assert_eq(StructureOrnaments.problem_for(cottage, params), "")
	var states := StructureOrnaments.chip_states(ruin, params)
	for kind: String in states:
		assert_false(bool(states[kind]["enabled"]), "%s is greyed" % kind)
		assert_ne(String(states[kind]["reason"]), "", "with a reason")


func test_chip_states_show_a_styles_own_ornaments_on_and_locked() -> void:
	var styled := ProcgenBuildingStyles.document("ivy_manor", 2)
	var own := StructureOrnaments.built_in(styled)
	var states := StructureOrnaments.chip_states(styled, {})
	for kind: String in StructureOrnaments.KIND_BITS:
		assert_eq(bool(states[kind]["on"]), own.has(kind), "%s on iff built in" % kind)
		assert_eq(bool(states[kind]["enabled"]), not own.has(kind), "%s locked iff built in" % kind)
	assert_eq(StructureOrnaments.apply(styled, StructureOrnaments.with_kinds({}, own), 1), 0)


# --- the edit ------------------------------------------------------------------------------


func test_a_set_is_one_history_entry_that_undoes_and_survives_a_restyle_and_a_copy() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var entries := _history.undo_count()
	assert_true(editor.structures.set_ornaments(id, ["ivy", "vane"], "Add ivy to"))
	assert_eq(_history.undo_count(), entries + 1, "one entry")
	assert_eq(
		StructureOrnaments.kinds_of(_doc.structure(id).params), ["ivy", "vane"] as Array[String]
	)
	assert_false(
		editor.structures.set_ornaments(id, ["ivy", "vane"], "again"), "no change, no entry"
	)
	assert_true(editor.structures.set_ornaments(id, ["ivy", "vane"], "Change ivy of", 0.9))
	assert_almost_eq(StructureOrnaments.ivy_amount(_doc.structure(id).params), 0.9, 0.001)
	assert_true(editor.structures.swap_recipe(id, CHIMNEYED), "restyle")
	assert_eq(
		StructureOrnaments.kinds_of(_doc.structure(id).params),
		["ivy", "vane"] as Array[String],
		"a restyle keeps them"
	)
	var copy := editor.structures.duplicate(id)
	assert_eq(
		StructureOrnaments.kinds_of(_doc.structure(copy).params),
		["ivy", "vane"] as Array[String],
		"a copy wears them too"
	)
	_history.undo()
	_history.undo()
	_history.undo()
	_history.undo()
	assert_eq(_doc.structure(id).params, {} as Dictionary, "undo takes them away")


func test_the_standing_building_follows_an_edit_and_undo() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var nodes := AuthoredStructures.of_map(_map)
	assert_not_null(nodes, "the map has its structure nodes")
	nodes.flush()
	var before := _mesh_names(nodes)
	assert_false("ornament_leaf" in before, "plain: no foliage")
	editor.structures.set_ornaments(id, ["ivy", "banner"], "Add")
	nodes.flush()
	var after := _mesh_names(nodes)
	# The ivy is blobs (ornament_leaf) or, where the library has decor plants, multimeshes of them.
	var plants := nodes.find_children("decor_*", "MultiMeshInstance3D", true, false)
	assert_true(
		"ornament_leaf" in after or not plants.is_empty(),
		"the standing building grew its ivy: %s" % str(after)
	)
	assert_true("ornament_cloth" in after, "and its banners")
	_history.undo()
	nodes.flush()
	assert_false("ornament_leaf" in _mesh_names(nodes), "undo took them off the standing building")


func _mesh_names(nodes: Node) -> Array[String]:
	var out: Array[String] = []
	for mesh in nodes.find_children("*", "MeshInstance3D", true, false):
		out.append(String(mesh.name))
	return out


func test_a_saved_record_and_a_live_edit_carry_the_ornaments() -> void:
	var params := StructureOrnaments.with_kinds({"floors": 1.0}, ["ivy", "awning"])
	params = StructureOrnaments.with_ivy_amount(params, 0.8)
	var structure := Structure.make(
		3, COTTAGE, StructurePlacement.rect_plan(Vector2.ZERO, Vector2(6, 4), 0.0), 9, params
	)
	var json := JSON.stringify(MapStructureIO.structure_json(structure))
	var data: Variant = JSON.parse_string(json)
	var back := MapStructureIO.parse_list([data], _doc.extent_m(), MapDocumentIO._WarningLog.new())
	assert_eq(back.size(), 1, "the record is read back")
	assert_eq(back[0].params, structure.params, "params and all")
	assert_eq(MapStructureIO.params_problem(structure.params), "", "well-formed names")
	assert_ne(
		StructureGeometry.key_of(_doc, structure),
		StructureGeometry.key_of(_doc, Structure.make(3, COTTAGE, structure.footprint, 9, {})),
		"the build key moves with them"
	)


# --- the Decorate row ----------------------------------------------------------------------


func test_the_row_shows_the_chips_greys_the_blocked_ones_and_asks_on_a_click() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var section := StructureOrnamentsSection.new()
	add_child_autofree(section)
	section.show_for(_doc.structure(id))
	assert_eq(section.chips.size(), 9, "nine chips")
	assert_false((section.chips["ivy"] as Button).button_pressed)
	assert_true(section.clear_button.disabled, "nothing to clear")
	assert_false(section.ivy_row.visible, "no ivy, no slider")
	watch_signals(section)
	(section.chips["ivy"] as Button).button_pressed = true
	assert_signal_emitted_with_parameters(
		section, "ornaments_requested", [["ivy"] as Array[String], "Add ivy to"]
	)
	var held := _doc.structure(id).copy()
	held.params = StructureOrnaments.with_kinds({}, ["ivy", "sign"])
	section.show_for(held)
	assert_true((section.chips["ivy"] as Button).button_pressed, "on from the record")
	assert_true(section.ivy_row.visible, "ivy on shows the slider")
	assert_false(section.clear_button.disabled)
	(section.chips["ivy"] as Button).button_pressed = false
	assert_signal_emitted_with_parameters(
		section, "ornaments_requested", [["sign"] as Array[String], "Take ivy off"]
	)
	section.ivy_slider.value = 0.8
	assert_signal_emitted_with_parameters(section, "ivy_requested", [0.8])
	section.surprise_button.pressed.emit()
	assert_signal_emit_count(section, "ornaments_requested", 3)
	var ruin := held.copy()
	ruin.recipe = RUIN
	section.show_for(ruin)
	for kind: String in section.chips:
		assert_true((section.chips[kind] as Button).disabled, "%s greyed on a ruin" % kind)
	assert_string_contains((section.chips["ivy"] as Button).tooltip_text, "ruin")
	assert_true(section.surprise_button.disabled)


func test_the_tool_turns_a_click_into_an_edit_and_the_bar_shows_it() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var tool := ToolRegistry.find(StructureTool.ID) as StructureTool
	var controller := AuthoringController.new()
	add_child_autofree(controller)
	var brush := BrushTool.new()
	add_child_autofree(brush)
	brush.editor = editor
	controller.brush = brush
	controller.editor = editor
	var pane := tool.build_pane(null) as StructureToolPane
	add_child_autofree(pane)
	tool.connect_pane(controller, pane)
	StructureTool.of(brush).select(id)
	var entries := _history.undo_count()
	pane.ornaments_section.chips["flower_boxes"].button_pressed = true
	assert_eq(
		StructureOrnaments.kinds_of(_doc.structure(id).params), ["flower_boxes"] as Array[String]
	)
	assert_eq(_history.undo_count(), entries + 1, "one entry for one click")
	assert_true(pane.ornaments_section.chips["flower_boxes"].button_pressed, "the bar shows it")
	pane.ornaments_section.surprise_button.pressed.emit()
	assert_ne(_doc.structure(id).params, {} as Dictionary, "Surprise me dresses it")
	pane.ornaments_section.clear_button.pressed.emit()
	assert_eq(_doc.structure(id).params, {} as Dictionary, "Clear takes them off")


# --- the placed kinds ----------------------------------------------------------------------


func test_a_build_reports_the_kinds_it_placed_and_leaves_the_digest_alone() -> void:
	var plain := _built(COTTAGE, {})
	assert_eq(plain["placed_kinds"], [] as Array[String], "nothing asked, nothing placed")
	var dressed := _built(COTTAGE, StructureOrnaments.with_kinds({}, ["ivy", "vane", "banner"]))
	var placed: Array = dressed["placed_kinds"]
	assert_true(placed.has("ivy") and placed.has("vane") and placed.has("banner"), str(placed))
	assert_eq(
		StructureGeometry.digest_of(plain),
		StructureGeometry.digest_of(_built(COTTAGE, {})),
		"the field is not in the digest"
	)


func test_the_row_mutes_a_chip_that_found_no_room_and_says_so() -> void:
	var editor := _editor()
	var id := _lay(editor)
	var held := _doc.structure(id).copy()
	held.params = StructureOrnaments.with_kinds({}, ["ivy", "sign"])
	var section := StructureOrnamentsSection.new()
	add_child_autofree(section)
	section.show_for(held)
	var plain_tip := (section.chips["sign"] as Button).tooltip_text
	section.show_missing(["sign", "vane"])
	var sign_chip: Button = section.chips["sign"]
	assert_lt(sign_chip.modulate.a, 1.0, "muted")
	assert_true(sign_chip.button_pressed, "still on, so a click takes it off")
	assert_false(sign_chip.disabled)
	assert_string_contains(sign_chip.tooltip_text, "No room")
	assert_eq((section.chips["ivy"] as Button).modulate, Color.WHITE, "a placed chip is not muted")
	assert_eq((section.chips["vane"] as Button).modulate, Color.WHITE, "not asked, not muted")
	section.show_missing([])
	assert_eq(sign_chip.modulate, Color.WHITE)
	assert_eq(sign_chip.tooltip_text, plain_tip)


func test_the_map_reports_the_requested_kinds_a_build_lacks() -> void:
	var root := Node3D.new()
	add_child_autofree(root)
	var structures := AuthoredStructures.new()
	structures.name = AuthoredStructures.NODE_NAME
	root.add_child(structures)
	assert_eq(
		AuthoredStructures.missing_kinds_in(root, 4, ["ivy"]), [] as Array[String], "not built yet"
	)
	structures._details[4] = {"placed_kinds": ["ivy"] as Array[String]}
	assert_eq(
		AuthoredStructures.missing_kinds_in(root, 4, ["ivy", "sign", "sign"]),
		["sign"] as Array[String],
		"the one asked and not placed, once"
	)
	assert_eq(AuthoredStructures.missing_kinds_in(null, 4, ["ivy"]), [] as Array[String])
