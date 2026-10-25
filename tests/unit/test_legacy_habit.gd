extends GutTest

## The habit of a species rule (step S2 of the content library): a palette rule's own `habit`
## wins in ScatterGround.plan_role, the LEGACY key and kind lists (LegacyHabit) answer for a rule
## without one, and both give the pre-S2 plan role for every rule of every built-in biome. Also
## the palette validator's whitelist for `role`, `habit` and `weight`: a bad value warns, an
## absent one never does, and a legacy rule gains no field.

const BIOME := "b_summer_s1"
const TREE := BIOME + "/Tree"


## The plan_role algorithm as it was before S2 (key lists inline), the reference for identity.
func _reference_role(rule: Dictionary) -> int:
	var role := ScatterGround.role_of(rule)
	if role == ScatterGround.ROLE_ROCK:
		return role
	var key := String(rule.get("key", ""))
	if key in ["reeds", "rushes", "cattail", "sedge"]:
		role |= ScatterGround.EDGE_EMERGENT
	elif key in ["willow", "poplar", "alder", "fern", "fern_small"]:
		role |= ScatterGround.EDGE_BANK
	if rule.get("kind", "") == "flower":
		role |= ScatterGround.FLOWER_BIT
	if rule.get("kind", "") in ["cactus"]:
		role |= ScatterGround.ARID_BIT
	if key in ["snag", "snag_conifer", "high_stump", "stump", "branches", "log", "char_litter"]:
		role |= ScatterGround.CHARRED_BIT
	return role


func _document(rule: Dictionary) -> Dictionary:
	var base := {
		"key": "tree",
		"kind": "tree",
		"size_class": "large",
		"density_per_m2": 0.02,
		"assets": [TREE],
	}
	base.merge(rule, true)
	return {
		"format": 1,
		"palette_version": "t",
		"surfaces": {},
		"assets":
		{
			TREE:
			{
				"file": "t.glb",
				"node": "Tree",
				"wind_category": "tree",
				"size_class": "large",
				"dimensions_m": [1, 2, 1],
			}
		},
		"biomes": [{"id": BIOME, "species": [base]}],
	}


func _validated(rule: Dictionary) -> Dictionary:
	var result := PaletteLibrary.validate_palette(_document(rule))
	assert_eq(result.palette.biomes.size(), 1, str(result.warnings))
	return result.palette.biomes[0].species[0]


func _warnings(rule: Dictionary) -> Array[String]:
	var found: Array[String] = []
	found.assign(PaletteLibrary.validate_palette(_document(rule)).warnings)
	return found


func test_every_built_in_rule_plans_the_same_role_by_fallback_and_by_habit() -> void:
	var biomes := PaletteLibrary.biomes()
	assert_gte(biomes.size(), 9, "the nine built-in biomes")
	var checked := 0
	var edge := 0
	for biome: Dictionary in biomes:
		for rule: Dictionary in PaletteLibrary.species(String(biome["id"])):
			var want := _reference_role(rule)
			assert_eq(ScatterGround.plan_role(rule), want, "fallback %s" % rule["key"])
			var with_habit := rule.duplicate(true)
			with_habit["habit"] = LegacyHabit.for_key(String(rule["key"]), String(rule["kind"]))
			assert_eq(
				ScatterGround.plan_role(with_habit),
				want,
				"habit %s/%s" % [biome["id"], rule["key"]]
			)
			assert_eq(ScatterGround.habit_of(rule), with_habit["habit"], "habit_of is the fallback")
			checked += 1
			if (want & ~ScatterGround.ROLE_BITS) != 0:
				edge += 1
	assert_gt(checked, 100, "every rule of every biome")
	assert_gt(edge, 10, "some rules carry water, flower or charred bits")


func test_a_rule_without_habit_uses_the_key_lists() -> void:
	var reeds := {"key": "reeds", "kind": "grass", "size_class": "ground"}
	assert_eq(ScatterGround.plan_role(reeds) & ScatterGround.EDGE_EMERGENT, 16)
	assert_eq(ScatterGround.habit_of(reeds), {"water": "emergent", "charred": false})
	var willow := {"key": "willow", "kind": "tree", "size_class": "large"}
	assert_eq(ScatterGround.habit_of(willow)["water"], "bank")
	var cactus := {"key": "saguaro", "kind": "cactus", "size_class": "medium"}
	assert_eq(ScatterGround.habit_of(cactus)["water"], "arid")
	var stump := {"key": "stump", "kind": "deadwood", "size_class": "small"}
	assert_true(ScatterGround.habit_of(stump)["charred"])
	assert_eq(LegacyHabit.for_key("daisy", "flower"), {"water": "", "charred": false})


func test_the_rules_own_habit_beats_the_key_lists() -> void:
	var calm := {"key": "reeds", "kind": "grass", "size_class": "ground"}
	calm["habit"] = {"water": "", "charred": false}
	assert_eq(ScatterGround.plan_role(calm) & ~ScatterGround.ROLE_BITS, 0, "reeds that are not")
	var snag := {"key": "snag", "kind": "tree", "size_class": "large"}
	snag["habit"] = {"water": "", "charred": false}
	assert_eq(ScatterGround.plan_role(snag) & ScatterGround.CHARRED_BIT, 0, "a living snag")
	var moss := {"key": "carpet_moss", "kind": "grass", "size_class": "ground"}
	moss["habit"] = {"water": "emergent", "charred": false}
	assert_ne(ScatterGround.plan_role(moss) & ScatterGround.EDGE_EMERGENT, 0, "a new reed")
	var cactus := {"key": "x", "kind": "tree", "size_class": "large", "habit": {"water": "arid"}}
	assert_ne(ScatterGround.plan_role(cactus) & ScatterGround.ARID_BIT, 0)
	var rock := {"key": "reeds", "kind": "rock", "size_class": "small"}
	rock["habit"] = {"water": "bank", "charred": true}
	assert_eq(ScatterGround.plan_role(rock), ScatterGround.ROLE_ROCK, "rocks carry no bits")


func test_a_legacy_rule_gains_no_library_field() -> void:
	var rule := _validated({})
	assert_false(rule.has("role"))
	assert_false(rule.has("habit"))
	assert_false(rule.has("weight"))
	assert_eq(_warnings({}).size(), 0)


func test_role_habit_and_weight_are_kept_and_validated() -> void:
	var rule := _validated({"role": "bank_tree", "habit": {"charred": true}, "weight": 2.5})
	assert_eq(rule["role"], "bank_tree")
	assert_eq(rule["habit"], {"water": "bank", "charred": true}, "role default plus own flag")
	assert_eq(rule["weight"], 2.5)
	assert_eq(_warnings({"role": "bank_tree", "habit": {"charred": true}, "weight": 2.5}).size(), 0)
	var only_role := _validated({"role": "snag"})
	assert_eq(only_role["habit"], {"water": "", "charred": true}, "the role supplies the habit")
	var only_habit := _validated({"habit": {"water": "emergent"}})
	assert_eq(only_habit["habit"], {"water": "emergent", "charred": false})
	assert_false(only_habit.has("role"))
	assert_eq(ScatterGround.plan_role(only_role) & ScatterGround.CHARRED_BIT, 128)


func test_bad_values_warn_and_are_dropped() -> void:
	var rule := _validated({"role": "tree_of_life"})
	assert_false(rule.has("role"))
	assert_false(rule.has("habit"))
	assert_eq(_warnings({"role": "tree_of_life"}).size(), 1)
	assert_eq(_warnings({"role": 7}).size(), 1)
	var bad_water := {"habit": {"water": "swamp", "charred": true}}
	assert_eq(_validated(bad_water)["habit"], {"water": "", "charred": true})
	assert_eq(_warnings(bad_water).size(), 1)
	var bad_charred := {"role": "snag", "habit": {"charred": "yes"}}
	assert_eq(_validated(bad_charred)["habit"], {"water": "", "charred": true}, "role's flag stays")
	assert_eq(_warnings(bad_charred).size(), 1)
	assert_eq(_warnings({"habit": "bank"}).size(), 1)
	assert_eq(_warnings({"habit": {"water": "bank", "wet": true}}).size(), 1)
	assert_false(_validated({"weight": "heavy"}).has("weight"))
	assert_eq(_warnings({"weight": "heavy"}).size(), 1)
	assert_eq(_validated({"weight": 1e9})["weight"], 1000.0, "clamped")


func test_absent_fields_never_warn() -> void:
	for rule: Dictionary in [{"role": null}, {"habit": null}, {"weight": null}]:
		assert_eq(_warnings(rule).size(), 0, str(rule))
