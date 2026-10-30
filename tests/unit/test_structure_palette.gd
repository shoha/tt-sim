extends GutTest

## StructurePalette (search, grouping, family order) and the pane's use of it.

static var rows: Array = [
	_row("ruin", "Ruined barn", ["ruin", "farm"]),
	_row("castle", "Castle keep", ["stone"]),
	_row("cottage", "Log cabin", []),
	_row("cottage", "Cottage", ["thatch_roof"]),
]


static func _row(family: String, row_name: String, tags: Array) -> Dictionary:
	var ref := "core:" + row_name.to_lower().replace(" ", "_")
	return {"ref": ref, "library": "core", "family": family, "name": row_name, "tags": tags}


func test_an_empty_search_matches_everything() -> void:
	for row: Dictionary in rows:
		assert_true(StructurePalette.matches(row, ""))
		assert_true(StructurePalette.matches(row, "   "))


func test_search_reads_name_family_and_tags_case_blind() -> void:
	assert_true(StructurePalette.matches(rows[0], "BARN"))
	assert_true(StructurePalette.matches(rows[0], "farm"))
	assert_true(StructurePalette.matches(rows[2], "cott"))
	assert_true(StructurePalette.matches(rows[3], "thatch roof"), "underscores read as spaces")
	assert_false(StructurePalette.matches(rows[1], "barn"))


func test_every_word_must_match() -> void:
	assert_true(StructurePalette.matches(rows[0], "ruin farm"))
	assert_false(StructurePalette.matches(rows[0], "ruin timber"))


func test_sections_put_the_common_families_first_then_alphabetical() -> void:
	var found := StructurePalette.sections(rows, "")
	var families: Array[String] = []
	for section: Dictionary in found:
		families.append(String(section["family"]))
	assert_eq(families, ["cottage", "castle", "ruin"] as Array[String])
	assert_eq((found[0]["rows"] as Array).size(), 2)


func test_sections_keep_only_the_found_rows() -> void:
	var found := StructurePalette.sections(rows, "log")
	assert_eq(found.size(), 1)
	assert_eq(String((found[0]["rows"] as Array)[0]["ref"]), "core:log_cabin")
	assert_true(StructurePalette.sections(rows, "zzz").is_empty())


func test_section_caption_counts() -> void:
	assert_eq(StructurePalette.section_caption("stilt_house", 2), "Stilt House (2)")


func test_the_pane_filters_its_tiles_and_remembers_the_pick() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var all := pane.refs().size()
	var picked := pane.picked_ref()
	assert_gt(all, 0)
	pane.search_edit.text = "ruin"
	pane.search_edit.text_changed.emit("ruin")
	assert_lt(pane.refs().size(), all, "the search narrows the tiles")
	assert_eq(pane.picked_ref(), picked, "a hidden pick stays the pick")
	pane.search_edit.text = "zzzzzz"
	pane.search_edit.text_changed.emit("zzzzzz")
	assert_eq(pane.refs().size(), 0)
	assert_true(pane.get_node("StructureNoMatch").visible, "says nothing matched")
	assert_true(pane.reroll_button.visible, "search and Mix afresh stay reachable")
	pane.search_edit.text = ""
	pane.search_edit.text_changed.emit("")
	assert_eq(pane.refs().size(), all)
	assert_false(pane.get_node("StructureNoMatch").visible)


func test_the_selection_bar_takes_extra_sections_above_its_buttons() -> void:
	var pane := StructureToolPane.new()
	add_child_autofree(pane)
	var extra := VBoxContainer.new()
	extra.name = "Ornaments"
	pane.add_selection_section(extra)
	assert_gt(extra.get_index(), pane.done_button.get_parent().get_index(), "below the buttons")
	assert_lt(pane.done_button.get_parent().get_index(), pane.steppers["floors"]["row"].get_index())
