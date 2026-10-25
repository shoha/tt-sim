extends GutTest

## The A/B view and the season switch on a real map and a real scatter (step S9), over the small
## multi-library world of tests/unit/library_world.gd (`core` official with biome `forest`,
## `alienworld` the player's with `crystal_basin`): turning the view on paints two biomes on one
## proving ground and grows both, moving the divider moves the plants with it, turning it off
## gives the map back to the draft; edits keep regenerating the draft's side; the season switch
## moves the map to that season's own plants. The camera and the ground are not part of this
## (the render job designer_s9_ab judges them).

const World := preload("res://tests/unit/library_world.gd")
const ROOT := "user://test_biome_designer_ab"
const ALIEN := "alienworld"
const DRAFT := World.ALIEN_RUNTIME
const CORE_OAK := World.CORE_RUNTIME + "/Tree_Oak_v0"
const SPIRE := DRAFT + "/Crystal_Spire_v0"

var _paths: Dictionary = {}
var _saved_settings: String = ""
var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_settings = LibraryRegistry.settings_path
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.settings_path = _saved_settings
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	World.remove_tree(ROOT)


func before_each() -> void:
	World.remove_tree(ROOT)
	_paths = World.build(ROOT)
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.settings_path = ROOT + "/settings.cfg"
	LibraryRegistry.official_root = _paths["official"]
	LibraryRegistry.user_root = _paths["user"]
	LibraryRegistry.apply()


func _live() -> Dictionary:
	var prepared := BiomeDesignerEntry.prepare(ALIEN, "crystal_basin")
	assert_true(prepared["ok"], str(prepared["error"]))
	var model: BiomeDesignerModel = prepared["model"]
	var document := ProvingGround.build(DRAFT)
	var scatter := AuthoredScatter.new()
	add_child_autofree(scatter)
	scatter.attach_document(document)
	scatter.grow_seconds = 0.0
	scatter.request_region(Rect2(-document.extent_m() * 0.5, document.extent_m()))
	await _settle(scatter)
	var controller := AuthoringController.new()
	controller.scatter = scatter
	controller.document = document
	add_child_autofree(controller)
	var session := BiomeDesignerSession.new()
	session.debounce = 0.0
	add_child_autofree(session)
	session.setup(model, controller)
	return {"scatter": scatter, "session": session, "model": model, "document": document}


func _settle(scatter: AuthoredScatter) -> void:
	var frames := 0
	while (scatter.is_regenerating() or scatter.is_growing()) and frames < 900:
		await get_tree().process_frame
		frames += 1
	scatter.complete_growth()


func _rows(scatter: AuthoredScatter, asset_id: String) -> int:
	var rows: PackedFloat32Array = scatter.rows_by_asset().get(asset_id, PackedFloat32Array())
	return rows.size() / MapDocument.ROW_STRIDE


## The x coordinate of every row of `asset_id` (document metres).
func _xs(scatter: AuthoredScatter, asset_id: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rows: PackedFloat32Array = scatter.rows_by_asset().get(asset_id, PackedFloat32Array())
	for r in rows.size() / MapDocument.ROW_STRIDE:
		out.append(rows[r * MapDocument.ROW_STRIDE])
	return out


func _right_of(session: BiomeDesignerSession) -> Vector2:
	return session.compare.right


func _projected(scatter: AuthoredScatter, asset_id: String, right: Vector2) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var rows: PackedFloat32Array = scatter.rows_by_asset().get(asset_id, PackedFloat32Array())
	for r in rows.size() / MapDocument.ROW_STRIDE:
		var at := r * MapDocument.ROW_STRIDE
		out.append(Vector2(rows[at], rows[at + 2]).dot(right))
	return out


# ---- the A/B view ----


func test_the_view_paints_two_biomes_and_grows_both() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var document: MapDocument = live["document"]
	var spires_before := _rows(scatter, SPIRE)
	assert_true(spires_before > 5)
	var started := session.compare.start(
		{"kind": "biome", "label": "Forest (Core)", "runtime": World.CORE_RUNTIME}
	)
	assert_true(started["ok"], str(started["error"]))
	assert_true(session.compare.active)
	assert_eq(document.biome_ids, PackedStringArray([DRAFT, World.CORE_RUNTIME]))
	var draft_samples := 0
	var reference_samples := 0
	for value in document.biome_slots:
		draft_samples += 1 if value == DesignerSplit.DRAFT_SLOT else 0
		reference_samples += 1 if value == DesignerSplit.REFERENCE_SLOT else 0
	assert_eq(draft_samples + reference_samples, document.sample_count())
	assert_true(draft_samples > 0 and reference_samples > 0)
	await _settle(scatter)
	var right := _right_of(session)
	var divider := session.compare.divider_t
	assert_true(_rows(scatter, CORE_OAK) > 3, "the reference grows on its side")
	assert_true(_rows(scatter, SPIRE) > 0, "and the draft on its own")
	assert_true(_rows(scatter, SPIRE) < spires_before, "but only on half the map")
	for t in _projected(scatter, SPIRE, right):
		assert_true(t < divider + 1.0, "no draft plant stands on the reference's side")
	for t in _projected(scatter, CORE_OAK, right):
		assert_true(t > divider - 1.0, "no reference plant stands on the draft's side")


func test_the_divider_moves_the_plants_with_it() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var document: MapDocument = live["document"]
	session.compare.start({"kind": "biome", "label": "Forest", "runtime": World.CORE_RUNTIME})
	await _settle(scatter)
	var span := DesignerSplit.span(document, session.compare.right)
	var oaks_middle := _rows(scatter, CORE_OAK)
	session.compare.move_divider(lerpf(span.x, span.y, 0.15), false)
	await get_tree().process_frame
	await _settle(scatter)
	assert_true(_rows(scatter, CORE_OAK) > oaks_middle, "the reference covers more of the map")
	for t in _projected(scatter, SPIRE, session.compare.right):
		assert_true(t < session.compare.divider_t + 1.0)
	session.compare.move_divider(lerpf(span.x, span.y, 0.85), false)
	await get_tree().process_frame
	await _settle(scatter)
	assert_true(_rows(scatter, CORE_OAK) < oaks_middle, "and less when the divider goes right")
	assert_true(session.compare.draft_share() > 0.75)


func test_turning_the_view_off_gives_the_map_back_to_the_draft() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var document: MapDocument = live["document"]
	var before := _rows(scatter, SPIRE)
	session.compare.start({"kind": "biome", "label": "Forest", "runtime": World.CORE_RUNTIME})
	await _settle(scatter)
	session.compare.stop()
	await get_tree().process_frame
	await _settle(scatter)
	assert_false(session.compare.active)
	assert_eq(document.biome_ids, PackedStringArray([DRAFT]))
	assert_eq(_rows(scatter, CORE_OAK), 0, "the reference's plants are gone")
	assert_eq(_rows(scatter, SPIRE), before, "the draft's are the same as before")


func test_an_edit_keeps_regenerating_the_drafts_side() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var model: BiomeDesignerModel = live["model"]
	session.compare.start({"kind": "biome", "label": "Forest", "runtime": World.CORE_RUNTIME})
	await _settle(scatter)
	var oaks := _rows(scatter, CORE_OAK)
	model.set_field("trees", "density_per_m2", 0.0)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	assert_eq(_rows(scatter, SPIRE), 0)
	assert_eq(_rows(scatter, CORE_OAK), oaks, "the reference does not move with the draft")


func test_the_saved_version_stands_beside_the_edited_draft() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var model: BiomeDesignerModel = live["model"]
	model.set_field("trees", "density_per_m2", 0.0)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	assert_eq(_rows(scatter, SPIRE), 0)
	var started := session.compare.start({"kind": "saved", "label": "Saved version"})
	assert_true(started["ok"], str(started["error"]))
	var saved_id := session.compare.reference_runtime()
	assert_ne(saved_id, DRAFT)
	await _settle(scatter)
	assert_true(_rows(scatter, saved_id + "/Crystal_Spire_v0") > 0, "the saved spires grow")
	assert_eq(_rows(scatter, SPIRE), 0, "the draft has none")


func test_the_budget_counts_the_draft_over_its_own_share() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var whole := session.budget()
	session.compare.start({"kind": "biome", "label": "Forest", "runtime": World.CORE_RUNTIME})
	await _settle(scatter)
	var split := session.budget()
	assert_true(split["instances"] < whole["instances"], "half the map, half the plants")
	var per_tile_whole := float(whole["per_tile"]["instances"])
	var per_tile_split := float(split["per_tile"]["instances"])
	assert_almost_eq(per_tile_split / per_tile_whole, 1.0, 0.35, "the density is the same")


func test_a_reference_cannot_be_the_draft_itself() -> void:
	var live := await _live()
	var session: BiomeDesignerSession = live["session"]
	var made := session.compare.start({"kind": "biome", "label": "itself", "runtime": DRAFT})
	assert_false(made["ok"])
	assert_false(session.compare.active)
	assert_false(session.compare.start({"kind": "biome", "runtime": "nowhere"})["ok"])


# ---- seasons on the map ----


func test_a_seasons_overrides_reach_the_plants_when_it_is_switched_to() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var model: BiomeDesignerModel = live["model"]
	DesignerSeasonEdits.add_season(model, "autumn")
	DesignerSeasonEdits.set_rule_field(model, "trees", "autumn", "density_factor", 0.0)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	assert_true(_rows(scatter, SPIRE) > 5, "summer is still on the map")
	session.set_season(1)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	var autumn := "alienworld__crystal_basin_autumn_s2"
	assert_eq(session.runtime_biome_id(), autumn)
	assert_eq(_rows(scatter, SPIRE), 0, "the summer plants are gone")
	assert_eq(_rows(scatter, autumn + "/Crystal_Spire_v0"), 0, "autumn has no spires")
	assert_true(_rows(scatter, autumn + "/Crystal_Shard_v0") > 5, "its shards stand")
	session.set_season(0)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	assert_true(_rows(scatter, SPIRE) > 5)
	assert_eq(_rows(scatter, autumn + "/Crystal_Shard_v0"), 0)


func test_removing_the_season_on_the_map_falls_back_to_the_first() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var model: BiomeDesignerModel = live["model"]
	DesignerSeasonEdits.add_season(model, "autumn")
	session.set_season(1)
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	DesignerSeasonEdits.remove_season(model, "autumn")
	await get_tree().create_timer(0.1).timeout
	await _settle(scatter)
	assert_eq(session.season_index, 0)
	assert_eq(session.runtime_biome_id(), DRAFT)
	assert_true(_rows(scatter, SPIRE) > 5, "the summer plants are back")


func test_the_focus_hides_the_other_rules_nodes_and_clears() -> void:
	var live := await _live()
	var scatter: AuthoredScatter = live["scatter"]
	var session: BiomeDesignerSession = live["session"]
	var visible_before := 0
	var nodes: Array[MultiMeshInstance3D] = []
	for cell: Vector2i in scatter._cells:
		for asset_id: String in scatter._cells[cell]:
			var node := scatter.get_cell_node(cell, asset_id)
			if node != null:
				nodes.append(node)
				visible_before += 1 if node.visible else 0
	assert_eq(visible_before, nodes.size())
	session.set_focus("trees")
	var hidden := 0
	for cell: Vector2i in scatter._cells:
		for asset_id: String in scatter._cells[cell]:
			var node := scatter.get_cell_node(cell, asset_id)
			if node != null and not node.visible:
				hidden += 1
				assert_false(asset_id.begins_with(DRAFT + "/Crystal_Spire"))
	assert_true(hidden > 0, "the stones are hidden")
	session.set_focus("")
	for node in nodes:
		assert_true(node.visible)
