extends GutTest

## The A/B view's model (step S9): DesignerSplit paints one map with the draft on one side of a
## divider and the reference on the other (only the samples the divider crossed are written),
## DesignerReference lists what the draft can be compared with and compiles the saved version of
## the biome under a runtime id of its own, and DesignerFocus says which assets a "show only this
## rule" keeps. Pure over a MapDocument and the designer fixture library.

const Fixture := preload("res://tests/unit/designer_fixture.gd")
const FOLDER := "user://test_designer_split/mini"
const RIGHT := Vector2(0.7071, -0.7071)


func _document() -> MapDocument:
	var doc := MapDocument.create_flat(NewMap.size_cells(100), "grass", "test", 1)
	var slots := PackedByteArray()
	slots.resize(doc.sample_count())
	slots.fill(DesignerSplit.DRAFT_SLOT)
	doc.biome_slots = slots
	return doc


func _count(doc: MapDocument, slot: int) -> int:
	var n := 0
	for value in doc.biome_slots:
		n += 1 if value == slot else 0
	return n


func _model() -> BiomeDesignerModel:
	DirAccess.make_dir_recursive_absolute(FOLDER + "/biomes")
	return BiomeDesignerModel.from_context(Fixture.context(FOLDER, true), "meadow")


# ---- the painting ----


func test_the_whole_map_is_painted_on_both_sides_of_the_divider() -> void:
	var doc := _document()
	var span := DesignerSplit.span(doc, RIGHT)
	assert_almost_eq(span.x, -span.y, 0.001, "a square map is symmetric about its centre")
	var changed := DesignerSplit.paint(doc, RIGHT, NAN, 0.0)
	assert_true(changed.has_area())
	var left := _count(doc, DesignerSplit.DRAFT_SLOT)
	var right := _count(doc, DesignerSplit.REFERENCE_SLOT)
	assert_eq(left + right, doc.sample_count())
	assert_true(absi(left - right) < doc.sample_count() / 50, "the middle splits it about in half")
	var step := doc.sample_step()
	for point in [Vector2i(5, 5), Vector2i(100, 30), Vector2i(60, 110), Vector2i(10, 100)]:
		var t := doc.sample_to_world(Vector2(point)).dot(RIGHT)
		var want := DesignerSplit.DRAFT_SLOT if t < 0.0 else DesignerSplit.REFERENCE_SLOT
		if absf(t) > step.x:
			assert_eq(doc.biome_slots[doc.sample_index(point.x, point.y)], want, str(point))


func test_moving_the_divider_writes_only_the_samples_it_crossed() -> void:
	var doc := _document()
	DesignerSplit.paint(doc, RIGHT, NAN, 0.0)
	var before := doc.biome_slots.duplicate()
	var changed := DesignerSplit.paint(doc, RIGHT, 0.0, 8.0)
	assert_true(changed.has_area())
	var moved := 0
	for i in before.size():
		if before[i] != doc.biome_slots[i]:
			moved += 1
			assert_eq(doc.biome_slots[i], DesignerSplit.DRAFT_SLOT, "the draft grows to the right")
	assert_true(moved > 0)
	assert_true(moved < doc.sample_count() / 3, "a band, not the map")
	var again := DesignerSplit.paint(doc, RIGHT, 8.0, 8.0)
	assert_false(again.has_area(), "a divider that did not move changes nothing")
	DesignerSplit.paint(doc, RIGHT, 8.0, -8.0)
	assert_true(_count(doc, DesignerSplit.REFERENCE_SLOT) > _count(doc, DesignerSplit.DRAFT_SLOT))


func test_moving_back_restores_the_same_painting() -> void:
	var doc := _document()
	DesignerSplit.paint(doc, RIGHT, NAN, 3.0)
	var start := doc.biome_slots.duplicate()
	DesignerSplit.paint(doc, RIGHT, 3.0, -9.0)
	DesignerSplit.paint(doc, RIGHT, -9.0, 3.0)
	assert_eq(doc.biome_slots, start)
	var fresh := _document()
	DesignerSplit.paint(fresh, RIGHT, NAN, 3.0)
	assert_eq(fresh.biome_slots, start, "a band-by-band paint equals painting from scratch")


func test_clear_gives_every_sample_back_to_the_draft() -> void:
	var doc := _document()
	DesignerSplit.paint(doc, RIGHT, NAN, 0.0)
	assert_true(DesignerSplit.clear(doc).has_area())
	assert_eq(_count(doc, DesignerSplit.DRAFT_SLOT), doc.sample_count())
	assert_false(DesignerSplit.clear(doc).has_area())


func test_a_document_without_biome_masks_is_left_alone() -> void:
	var doc := MapDocument.create_flat(NewMap.size_cells(100), "grass", "test", 1)
	assert_false(DesignerSplit.paint(doc, RIGHT, NAN, 0.0).has_area())
	assert_false(DesignerSplit.clear(doc).has_area())


func test_other_camera_directions_split_along_their_own_line() -> void:
	var doc := _document()
	for right in [Vector2(1.0, 0.0), Vector2(0.0, 1.0), Vector2(0.6, 0.8)]:
		DesignerSplit.paint(doc, right, NAN, 5.0)
		var half := doc.extent_m() * 0.5
		var low := doc.sample_to_world(Vector2(0, 0))
		var high := doc.sample_to_world(Vector2(doc.samples_x() - 1, doc.samples_z() - 1))
		assert_eq(low, -half)
		for corner: Vector2 in [low, high]:
			var want := (
				DesignerSplit.DRAFT_SLOT if corner.dot(right) < 5.0 else DesignerSplit.REFERENCE_SLOT
			)
			var at := doc.world_to_sample(corner).round()
			assert_eq(doc.biome_slots[doc.sample_index(int(at.x), int(at.y))], want)


func test_the_cells_a_move_can_change_are_the_ones_it_crosses() -> void:
	var doc := _document()
	var cells := DesignerSplit.cells_crossed(doc, RIGHT, -2.0, 2.0, 10.0)
	var all := DesignerSplit.cells_crossed(doc, RIGHT, -1.0e9, 1.0e9, 10.0)
	assert_true(cells.size() > 0)
	assert_true(cells.size() < all.size(), "a thin band touches only some of the cells")
	for cell in cells:
		var corners := [
			cell.position, cell.position + Vector2(cell.size.x, 0.0), cell.end,
			cell.position + Vector2(0.0, cell.size.y)
		]
		var low := 1.0e9
		var high := -1.0e9
		for corner: Vector2 in corners:
			low = minf(low, corner.dot(RIGHT))
			high = maxf(high, corner.dot(RIGHT))
		assert_true(high >= -2.0 and low < 2.0)
	assert_eq(DesignerSplit.cells_crossed(doc, RIGHT, 1.0e8, 1.0e9, 10.0).size(), 0)


func test_the_draft_share_follows_the_divider() -> void:
	var doc := _document()
	assert_almost_eq(DesignerSplit.draft_share(doc, RIGHT, 0.0), 0.5, 0.05)
	assert_true(DesignerSplit.draft_share(doc, RIGHT, 10.0) > 0.6)
	assert_almost_eq(DesignerSplit.draft_share(doc, RIGHT, -1.0e9), 0.0, 0.001)
	assert_almost_eq(DesignerSplit.draft_share(doc, RIGHT, 1.0e9), 1.0, 0.001)


# ---- what to compare with ----


func test_the_references_offered_are_the_saved_version_the_other_seasons_and_other_biomes() -> void:
	var model := _model()
	var options := DesignerReference.options(model, "summer")
	assert_eq(options[0]["kind"], "saved")
	assert_eq(options[1]["kind"], "season")
	assert_eq(options[1]["season"], "autumn")
	assert_eq(options[1]["runtime"], "mini__meadow_autumn_s2")
	for option in options:
		if option["kind"] == "biome":
			assert_ne(option["biome"], "meadow", "the draft is not offered against itself")


func test_the_saved_version_compiles_under_its_own_runtime_id() -> void:
	var model := _model()
	model.set_field("oak", "density_per_m2", 0.5)
	var saved := DesignerReference.compile_saved(model, "summer")
	assert_true(saved["ok"], str(saved["warnings"]))
	assert_eq(saved["runtime"], "mini__meadow_summer_s%d" % DesignerReference.SEED_BASE)
	assert_false(saved["runtime"] in model.runtime_ids())
	var biome: Dictionary = saved["compiled"]["palette"]["biomes"][0]
	assert_eq(biome["species"][0]["density_per_m2"], 0.01, "the saved density, not the draft's")
	var draft_biome: Dictionary = model.compile()["compiled"]["palette"]["biomes"][0]
	assert_eq(draft_biome["species"][0]["density_per_m2"], 0.5)
	assert_eq(
		saved["compiled"]["palette"]["biomes"].size(), 1, "one season only: the one being compared"
	)
	assert_false(DesignerReference.compile_saved(model, "monsoon")["ok"])


func test_the_saved_version_is_what_the_last_save_wrote() -> void:
	var model := _model()
	model.set_field("oak", "density_per_m2", 0.5)
	assert_true(model.save()["ok"])
	var saved := DesignerReference.compile_saved(model, "summer")
	assert_eq(saved["compiled"]["palette"]["biomes"][0]["species"][0]["density_per_m2"], 0.5)


func test_a_seed_that_a_season_has_is_skipped() -> void:
	var model := _model()
	DesignerSeasonEdits.add_season(model, "winter", DesignerReference.SEED_BASE)
	assert_eq(DesignerReference.saved_seed(model), DesignerReference.SEED_BASE + 1)


# ---- show only this rule ----


func test_a_rules_assets_are_what_the_focus_keeps() -> void:
	var model := _model()
	var compiled: Dictionary = model.compile()["compiled"]
	LibraryRegistry.serve_draft(compiled, model.context)
	var kept := DesignerFocus.assets_of_rule("mini__meadow_summer_s1", "oak")
	assert_eq(kept.size(), 2)
	for asset_id: String in kept:
		assert_true(asset_id.begins_with("mini__meadow_summer_s1/Tree_oak"))
	assert_eq(DesignerFocus.assets_of_rule("mini__meadow_summer_s1", "no_such_rule"), {})
	PaletteLibrary.clear_cache()
