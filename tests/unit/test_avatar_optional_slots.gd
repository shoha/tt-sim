extends GutTest

## Optional part slots and hats over hair (docs/ASSET_PIPELINE.md section 10 "Slots" and
## "Hats and hair", card B1): the kit's `slots` block, recipe resolution (an optional slot
## omitted, null or unknown is empty; a required one falls back), a hat's `hair_mode` applied
## to the hair, Surprise me leaving optional slots empty part of the time, the builder's
## "None" tile, and recipes saved before the change still loading.

## A recipe as clients wrote it before card B1 (every slot the kit had, no nulls).
const OLD_RECIPE := {
	"format": 1,
	"kit_version": "0.1.0+1b25d19",
	"parts": {"body": "body_a", "head": "head_round", "hair": "hair_bun"},
	"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
	"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
	"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
	"stance": "stance_ready",
}
## A stand-in hat: the head's GLB under a hat entry (only the entry's fields matter here).
const HAT_ID := "_b1_test_hat"
const LEVEL_FILE := "user://_b1_optional_slots_test_level.json"
const LIBRARY_DIR := "user://_b1_optional_slots_test_library/"

var _kit: AvatarKit
var _scene: Node = null
var _old_scene: Node = null


func before_each() -> void:
	_kit = AvatarKit.load_kit()


func after_each() -> void:
	_remove_hat(AvatarTokenFactory.kit())
	for entry in AvatarLibrary.list(LIBRARY_DIR):
		AvatarLibrary.delete(String(entry.id), LIBRARY_DIR)
	if _scene != null:
		get_tree().current_scene = _old_scene
		_scene.free()
		_scene = null


func after_all() -> void:
	if FileAccess.file_exists(LEVEL_FILE):
		DirAccess.remove_absolute(LEVEL_FILE)
	DirAccess.remove_absolute(LIBRARY_DIR)


func _add_hat(kit: AvatarKit, mode: Variant = "trimmed") -> void:
	var entry := {
		"id": HAT_ID,
		"slot": "hat",
		"glb": "parts/head/head_round.glb",
		"slots_used": ["primary"],
		"hides": [],
		"tags": ["cloth"],
	}
	if mode != null:
		entry["hair_mode"] = mode
	kit.parts_by_id[HAT_ID] = entry
	kit.parts_by_slot["hat"] = [HAT_ID]


func _remove_hat(kit: AvatarKit) -> void:
	kit.parts_by_id.erase(HAT_ID)
	kit.parts_by_slot.erase("hat")


func _with_parts(parts: Dictionary) -> Dictionary:
	var recipe := OLD_RECIPE.duplicate(true)
	recipe["parts"] = parts
	return recipe


func _regions(mesh: Mesh) -> PackedStringArray:
	var out := PackedStringArray()
	for s in mesh.get_surface_count():
		out.append(mesh.surface_get_material(s).resource_name)
	return out


# --- the kit's slots ----------------------------------------------------------------------------


func test_the_kit_marks_hat_cloak_and_gear_optional() -> void:
	assert_eq(_kit.optional_slots(), ["cloak", "gear", "hat"] as Array[String])
	assert_true(_kit.is_optional("hat"))
	assert_false(_kit.is_optional("hair"))
	var hair: Dictionary = _kit.parts_by_id.hair_bun
	assert_eq(hair.get("regions"), ["hair", "bun"])
	assert_eq(hair.get("hat_trim"), ["bun"])
	# A kit from before the slots block takes the contract's table.
	assert_eq(AvatarRecipe.optional_slots({}), ["hat", "cloak", "gear"] as Array[String])
	var own := {"slots": {"hat": {"optional": false}, "cloak": {"optional": true}}}
	assert_eq(AvatarRecipe.optional_slots(own), ["cloak"] as Array[String])


func test_the_shipped_hair_has_its_bun_as_its_own_surface() -> void:
	var mesh: ArrayMesh = _kit.load_part("hair_bun").mesh
	assert_eq(_regions(mesh), PackedStringArray(["hair", "bun"]))


# --- resolution ---------------------------------------------------------------------------------


func test_an_optional_slot_omitted_null_or_unknown_is_empty() -> void:
	_add_hat(_kit)
	var base := {"body": "body_a", "head": "head_round", "hair": "hair_bun"}
	var omitted := _kit.resolve(_with_parts(base))
	assert_false(omitted.parts.has("hat"))
	assert_eq(omitted.fallbacks.size(), 0)
	var nulled := base.duplicate()
	nulled["hat"] = null
	var r := _kit.resolve(_with_parts(nulled))
	assert_false(r.parts.has("hat"))
	assert_eq(r.fallbacks.size(), 0, "null is a choice, not a fallback")
	var unknown := base.duplicate()
	unknown["hat"] = "hat_from_the_future"
	unknown["cloak"] = "cloak_x"
	r = _kit.resolve(_with_parts(unknown))
	assert_false(r.parts.has("hat"), "never a substitute hat")
	assert_false(r.parts.has("cloak"))
	var notes := "\n".join(r.fallbacks)
	assert_string_contains(notes, "part 'hat_from_the_future' for hat not in kit; left empty")
	assert_string_contains(notes, "part 'cloak_x' for cloak not in kit; left empty")
	var worn := base.duplicate()
	worn["hat"] = HAT_ID
	assert_eq(_kit.resolve(_with_parts(worn)).parts.get("hat"), HAT_ID)


func test_a_required_slot_omitted_or_null_falls_back() -> void:
	var r := _kit.resolve(_with_parts({"body": "body_a", "head": "head_round", "hair": null}))
	assert_eq(r.parts.get("hair"), "hair_bun")
	assert_string_contains(
		"\n".join(r.fallbacks), "part None for hair not in kit; using 'hair_bun'"
	)
	r = _kit.resolve(_with_parts({}))
	assert_eq(r.parts, {"body": "body_a", "hair": "hair_bun", "head": "head_round"})


# --- hats over hair -----------------------------------------------------------------------------


func test_hair_trim_follows_the_hats_hair_mode() -> void:
	var hair := {"hat_trim": ["bun"]}
	assert_eq(AvatarKit.hair_trim({}, hair), [], "no hat: the whole hair")
	assert_eq(AvatarKit.hair_trim({"hair_mode": "full"}, hair), [])
	assert_eq(AvatarKit.hair_trim({"hair_mode": "trimmed"}, hair), ["bun"])
	assert_null(AvatarKit.hair_trim({"hair_mode": "hidden"}, hair))
	assert_null(AvatarKit.hair_trim({"slot": "hat"}, hair), "no hair_mode counts as hidden")
	assert_null(AvatarKit.hair_trim({"hair_mode": "trimmed"}, {}), "no hat_trim: hidden")
	assert_eq(AvatarKit.hair_trim({"hair_mode": "trimmed"}, {"hat_trim": []}), [])


func test_a_figure_applies_the_hats_hair_mode() -> void:
	var parts := {"body": "body_a", "head": "head_round", "hair": "hair_bun", "hat": HAT_ID}
	for case in [["trimmed", ["hair"]], ["full", ["hair", "bun"]], ["hidden", null]]:
		_add_hat(_kit, case[0])
		var figure := _kit.build_figure(_with_parts(parts))
		add_child_autofree(figure)
		assert_not_null(figure.find_child(HAT_ID, true, false), "%s: the hat is worn" % case[0])
		var hair := figure.find_child("hair_bun", true, false) as MeshInstance3D
		if case[1] == null:
			assert_null(hair, "hidden: no hair")
			assert_eq(AvatarKit.figure_parts(figure).size(), 3)
		else:
			assert_eq(_regions(hair.mesh), PackedStringArray(case[1]), case[0])
	_remove_hat(_kit)
	var bare := _kit.build_figure(_with_parts(parts))
	add_child_autofree(bare)
	assert_null(bare.find_child(HAT_ID, true, false), "a hat the kit lacks is not worn")
	var whole := bare.find_child("hair_bun", true, false) as MeshInstance3D
	assert_eq(_regions(whole.mesh), PackedStringArray(["hair", "bun"]))


# --- surprise me --------------------------------------------------------------------------------


func test_surprise_leaves_optional_slots_empty_part_of_the_time() -> void:
	_add_hat(_kit)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var hats := 0
	var draws := 600
	for i in draws:
		var parts := AvatarSurprise.parts(_kit, rng)
		for slot in ["body", "head", "hair"]:
			assert_true(parts.has(slot), "draw %d wears a %s" % [i, slot])
		hats += 1 if parts.has("hat") else 0
		assert_eq(_kit.resolve(_with_parts(parts)).fallbacks.size(), 0)
	var rate := float(hats) / float(draws)
	assert_almost_eq(rate, AvatarSurprise.wear_chance("hat"), 0.06, "hat rate %.2f" % rate)
	assert_gt(AvatarSurprise.wear_chance("gear"), AvatarSurprise.wear_chance("hat"))


func test_surprise_without_optional_parts_draws_as_before() -> void:
	# The shipped kit has no optional parts, so a seeded draw is unchanged by them.
	var a := RandomNumberGenerator.new()
	a.seed = 5
	var parts := AvatarSurprise.parts(_kit, a)
	assert_eq(parts, {"body": "body_a", "hair": "hair_bun", "head": "head_round"})


# --- the builder --------------------------------------------------------------------------------


func _open_builder() -> AvatarBuilder:
	_old_scene = get_tree().current_scene
	_scene = Node.new()
	_scene.name = "OptionalSlotsTestScene"
	get_tree().root.add_child(_scene)
	get_tree().current_scene = _scene
	AvatarLibrary.directory = LIBRARY_DIR
	return AvatarBuilder.open_for_new(_scene, OLD_RECIPE, "Plum")


func test_the_parts_pane_offers_none_first_for_an_optional_slot() -> void:
	_add_hat(AvatarTokenFactory.kit())
	var builder := _open_builder()
	var tiles := builder._part_rows.get("hat") as TileRow
	assert_not_null(tiles, "one hat is a choice: the hat or none")
	assert_false(builder._part_rows.has("hair"), "a lone required part offers no choice")
	var first := tiles.get_child(0) as Button
	assert_eq(first.text, "None")
	assert_true(first.button_pressed, "the recipe wears no hat")
	builder.pick_part("hat", HAT_ID)
	assert_eq(builder.recipe.parts.get("hat"), HAT_ID)
	assert_false(first.button_pressed)
	builder.pick_part("hat", "")
	assert_false((builder.recipe.parts as Dictionary).has("hat"), "None empties the slot")
	assert_true(first.button_pressed)
	builder.cancel()
	AvatarLibrary.directory = AvatarLibrary.DEFAULT_DIRECTORY


# --- older recipes ------------------------------------------------------------------------------


func test_a_library_entry_from_before_the_change_still_loads() -> void:
	var saved := AvatarLibrary.save("Plum", OLD_RECIPE, "", LIBRARY_DIR)
	# Read back through JSON, as a library file from an older client is.
	var entry := AvatarLibrary.get_entry(String(saved.id), LIBRARY_DIR)
	var recipe: Dictionary = entry.recipe
	var resolved := _kit.resolve(recipe)
	assert_eq(resolved.fallbacks.size(), 0, str(resolved.fallbacks))
	assert_eq(resolved.parts, OLD_RECIPE.parts)
	var figure := _kit.build_figure(recipe)
	add_child_autofree(figure)
	assert_eq(AvatarKit.figure_parts(figure).size(), 3)


func test_a_level_saved_before_the_change_still_loads_its_avatar() -> void:
	var level := LevelData.new()
	level.level_name = "_b1_optional_slots_test"
	var placement := TokenPlacement.new()
	placement.avatar_recipe = OLD_RECIPE.duplicate(true)
	placement.token_name = "Plum"
	level.token_placements.append(placement)
	assert_true(LevelManager.export_level_json(level, LEVEL_FILE))
	var loaded := LevelManager.import_level_json(LEVEL_FILE)
	var recipe: Dictionary = loaded.token_placements[0].avatar_recipe
	var resolved := AvatarTokenFactory.kit().resolve(recipe)
	assert_eq(resolved.fallbacks.size(), 0, str(resolved.fallbacks))
	assert_eq(resolved.parts, OLD_RECIPE.parts)
