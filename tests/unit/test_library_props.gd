extends GutTest

## Props in the core library (villages.md, topic props_host): 18 entries of family `prop`, each with
## four draws (seeds 0 to 3) served as `core:<id>` and `core:<id>_v<k>`. They are no placeable
## structure: LibraryStructureStore.structures() stays the 100 the Building tool lists, and the
## props are read with props() and prop(name, seed). Digests: tests/fixtures/prop_digests.txt
## (`<id> <seed> <digest> <triangles>`, the fixture of a deliberate change).

const FIXTURE := "res://tests/fixtures/prop_digests.txt"
const PINS := "res://libraries/core/structures/prop_pins.txt"
const SW := preload("res://tests/unit/library_structure_world.gd")
const PLACEABLE := 100

var _saved_official: String = ""
var _saved_user: String = ""


func before_all() -> void:
	_saved_official = LibraryRegistry.official_root
	_saved_user = LibraryRegistry.user_root


func after_all() -> void:
	LibraryRegistry.official_root = _saved_official
	LibraryRegistry.user_root = _saved_user
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()


func before_each() -> void:
	LibraryRegistry.official_root = LibraryRegistry.OFFICIAL_ROOT
	LibraryRegistry.user_root = "user://test_library_props/no_user_libraries"
	LibraryRegistry.clear()
	PaletteLibrary.clear_cache()
	LibraryRegistry.apply(PaletteLibrary.DEFAULT_ROOT)


func after_each() -> void:
	StructureGeometry.textured = true


func _lines(path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line in FileAccess.get_file_as_string(path).strip_edges().split("\n"):
		out.append(line.strip_edges())
	return out


func test_the_core_library_serves_the_18_props_and_the_placeable_structures_stay_100() -> void:
	var props := LibraryStructureStore.props("core")
	var names := PackedStringArray()
	for row in props:
		names.append(String(row["id"]))
	names.sort()
	var want := PackedStringArray(ProcgenProps.NAMES)
	want.sort()
	assert_eq(names, want, "every procgen prop is an entry")
	var placeable := LibraryStructureStore.structures("core")
	assert_eq(placeable.size(), PLACEABLE, "the palette total stays 100")
	for row in placeable:
		assert_ne(String(row["family"]), "prop", String(row["ref"]))
	assert_eq(StructureRecipes.core_refs().size(), PLACEABLE)
	assert_eq(LibraryStructureStore.structures().size(), PLACEABLE, "no library lists a prop")


func test_a_prop_row_carries_its_index_fields_and_a_tile() -> void:
	for row in LibraryStructureStore.props("core"):
		var ref := String(row["ref"])
		assert_eq(ref, "core:" + String(row["id"]))
		assert_true(ProcgenStructureIndex.prop_errors(row).is_empty(), ref)
		assert_true(ProcgenStructureIndex.plan_errors(row).is_empty(), ref)
		assert_eq(row["plans"], ["prop"], ref)
		assert_true("prop" in row["tags"] and ("prop/" + String(row["id"])) in row["tags"], ref)
		assert_gt(float(row["radius_m"]), 0.0, ref)
		assert_false((row["slots"] as Array).is_empty(), ref)
		assert_ne(String(row["thumb"]), "", "%s has a tile" % ref)
		for slot: Variant in row["slots"]:
			assert_true(String(slot) in row["tags"], "%s: slot %s is a tag" % [ref, slot])


func test_prop_gives_each_draw_its_own_reference_and_recipe() -> void:
	var seen := {}
	for k in LibraryStructures.PROP_VARIANTS:
		var row := LibraryStructureStore.prop("barrel", k)
		assert_false(row.is_empty(), "barrel draw %d" % k)
		assert_eq(int(row["seed"]), k)
		assert_eq(row["base"], "core:barrel")
		assert_eq(row["ref"], "core:" + LibraryStructures.variant_id("barrel", k))
		assert_true(StructureRecipes.exists(row["ref"]))
		seen[StructureRecipes.digest(row["ref"])] = true
	assert_gt(seen.size(), 1, "the draws differ")
	assert_eq(LibraryStructureStore.prop("barrel", 0)["ref"], "core:barrel")
	assert_eq(LibraryStructureStore.prop("barrel", 1)["ref"], "core:barrel_v1")


func test_prop_is_empty_for_what_is_no_prop_or_no_draw() -> void:
	assert_true(LibraryStructureStore.prop("barrel", LibraryStructures.PROP_VARIANTS).is_empty())
	assert_true(LibraryStructureStore.prop("cottage", 0).is_empty(), "a building is no prop")
	assert_true(LibraryStructureStore.prop("no_such_prop", 0).is_empty())
	assert_true(LibraryStructureStore.prop("barrel", 0, "nowhere").is_empty())
	var all := LibraryStructureStore.props()
	for row in all:
		assert_false(String(row["id"]).contains("_v"), "a variant is no row: %s" % row["id"])
	assert_eq(all.size(), ProcgenProps.NAMES.size())


func test_the_props_build_at_their_default_footprint_and_match_the_pins() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var now := PackedStringArray()
	for row in LibraryStructureStore.props("core"):
		var size: Array = row["default_size_m"]
		var plan := ProcgenProps.footprint(Vector2(float(size[0]), float(size[1])))
		for k in LibraryStructures.PROP_VARIANTS:
			var ref := String(LibraryStructureStore.prop(String(row["id"]), k)["ref"])
			var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, plan, 5))
			assert_eq(parts.problem, "", ref)
			assert_lt(StructureGeometry.triangle_count(parts), ProcgenProps.BUDGET_TRIS + 1, ref)
			now.append(
				(
					"%s %d %s %d"
					% [
						row["id"],
						k,
						StructureGeometry.digest_of(parts),
						StructureGeometry.triangle_count(parts)
					]
				)
			)
	now.sort()
	for path in [FIXTURE, PINS]:
		var pinned := PackedStringArray()
		for line in _lines(path):
			pinned.append(" ".join(line.split(" ").slice(0, 4)))
		pinned.sort()
		assert_eq(now.size(), 72, path)
		var moved := PackedStringArray()
		for i in mini(now.size(), pinned.size()):
			if now[i] != pinned[i]:
				moved.append("pinned '%s' now '%s'" % [pinned[i], now[i]])
		assert_eq(pinned.size(), now.size(), path)
		assert_eq(moved.size(), 0, "%s: a deliberate change re-pins: %s" % [path, "; ".join(moved)])


func test_a_prop_footprint_is_judged_by_the_prop_rules_only() -> void:
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	var small := ProcgenProps.footprint(Vector2(0.8, 0.8))
	var barrel := StructureGeometry.build_one(doc, Structure.make(1, "core:barrel", small, 5))
	assert_eq(barrel.problem, "")
	assert_gt(barrel.triangles, 0)
	var cottage := StructureGeometry.build_one(doc, Structure.make(1, "core:cottage", small, 5))
	assert_ne(cottage.problem, "", "a building still needs 2 m2")
	assert_ne(MapStructureIO.footprint_problem(small, doc.extent_m()), "")
	assert_eq(MapStructureIO.footprint_problem(small, doc.extent_m(), ProcgenPlan.KIND_PROP), "")


func test_the_reader_refuses_prop_keys_on_a_building_and_keeps_them_on_a_prop() -> void:
	var recipes := {"hut.structure.json": SW.recipe_text("cottage")}
	var bad := {"warnings": [] as Array[String]}
	LibraryStructures.read(SW.sources([SW.entry("hut", {"radius_m": 1.0})], recipes), [], false, bad)
	assert_eq((bad["structures"] as Array).size(), 0, "radius_m only goes with family prop")
	var good := {"warnings": [] as Array[String]}
	var entry := SW.entry(
		"hut",
		{
			"family": "prop",
			"plans": ["prop"],
			"radius_m": 1.5,
			"slots": ["plaza"],
			"blocks": "stand",
			"tint": "jewel",
			"default_size_m": [2.0, 2.0],
			"min_side_m": 0.5,
		}
	)
	LibraryStructures.read(SW.sources([entry], recipes), [], false, good)
	assert_eq((good["structures"] as Array).size(), 1, str(good["warnings"]))
	var row: Dictionary = good["structures"][0]["entry"]
	assert_eq(row["plans"], ["prop"])
	assert_eq(row["radius_m"], 1.5)
	assert_eq(row["blocks"], "stand")
	assert_eq(row["tint"], "jewel")
	var worse := SW.entry("hut", {"family": "prop", "plans": ["prop"], "radius_m": -1.0})
	var refused := {"warnings": [] as Array[String]}
	LibraryStructures.read(SW.sources([worse], recipes), [], false, refused)
	assert_eq((refused["structures"] as Array).size(), 0, "a bad radius refuses the entry")
