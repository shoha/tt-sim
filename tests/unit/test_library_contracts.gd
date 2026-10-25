extends GutTest

## LibraryContracts (utils/library/library_contracts.gd), the closed vocabulary of the content
## library: the roles table and the defaults it supplies, the habit flags, the caps against the
## limits the palette validator enforces, and the contract.json export plantgen vendors.


func test_roles_supply_a_kind_and_a_size_class() -> void:
	for role_id: String in LibraryContracts.ROLES:
		var kind := LibraryContracts.kind_of(role_id)
		var size_class := LibraryContracts.size_class_of(role_id)
		if role_id == "prop":
			assert_eq(kind, "", "a prop has no kind")
			assert_eq(size_class, "", "a prop has no class")
			continue
		assert_ne(kind, "", role_id)
		assert_true(size_class in LibraryContracts.SIZE_CLASSES, "%s class" % role_id)
		assert_true(LibraryContracts.has_role(role_id), role_id)
	assert_false(LibraryContracts.has_role("not_a_role"))
	assert_eq(LibraryContracts.kind_of("not_a_role"), "")
	assert_eq(LibraryContracts.size_class_of("not_a_role"), "")


func test_every_size_class_has_class_defaults() -> void:
	for size_class: String in LibraryContracts.SIZE_CLASSES:
		var defaults := LibraryContracts.class_defaults(size_class)
		for field: String in [
			"density_per_m2", "scale_spread", "slope_max_deg", "spacing_m", "yaw_random_deg"
		]:
			assert_true(defaults.has(field), "%s.%s" % [size_class, field])
	assert_eq(LibraryContracts.class_defaults("giant"), {})


func test_habit_defaults_name_real_roles_and_valid_flags() -> void:
	for role_id: String in LibraryContracts.HABIT_DEFAULTS:
		assert_true(LibraryContracts.has_role(role_id), "%s is a role" % role_id)
		var flags: Dictionary = LibraryContracts.HABIT_DEFAULTS[role_id]
		for flag: String in flags:
			assert_true(flag in ["water", "charred"], "%s.%s" % [role_id, flag])
		if flags.has("water"):
			assert_true(flags["water"] in LibraryContracts.HABIT_WATER, role_id)
		if flags.has("charred"):
			assert_true(flags["charred"] is bool, role_id)


func test_habit_for_lays_a_rules_flags_over_the_roles() -> void:
	assert_eq(LibraryContracts.habit_for("fern"), {"water": "bank", "charred": false})
	assert_eq(LibraryContracts.habit_for("snag"), {"water": "", "charred": true})
	assert_eq(LibraryContracts.habit_for("grass"), {"water": "", "charred": false})
	assert_eq(LibraryContracts.habit_for(""), {"water": "", "charred": false})
	assert_eq(
		LibraryContracts.habit_for("grass", {"water": "emergent"}),
		{"water": "emergent", "charred": false}
	)
	assert_eq(
		LibraryContracts.habit_for("snag", {"charred": false}),
		{"water": "", "charred": false},
		"a rule's own flag beats the role's"
	)
	assert_eq(LibraryContracts.habit_for("cactus_tall").get("water"), "arid")
	assert_eq(LibraryContracts.habit_for("emergent").get("water"), "emergent")


func test_align_follows_the_roles_kind() -> void:
	assert_eq(LibraryContracts.align_of("boulder"), "normal")
	assert_eq(LibraryContracts.align_of("canopy_tree"), "upright")
	assert_eq(LibraryContracts.role("nope"), {})
	assert_eq(LibraryContracts.role("shrub"), {"kind": "tree", "size_class": "medium"})


func test_caps_agree_with_the_palette_validator_limits() -> void:
	var caps: Dictionary = LibraryContracts.CAPS
	assert_eq(caps["assets"], PaletteLibrary.MAX_ASSETS)
	assert_eq(caps["assets_per_rule"], PaletteLibrary.MAX_ASSETS_PER_SPECIES)
	assert_eq(caps["rules_per_biome"], PaletteLibrary.MAX_SPECIES_PER_BIOME)
	assert_eq(caps["glb_bytes"], PaletteLibrary.MAX_ASSET_FILE_BYTES)
	assert_lte(int(caps["biomes"]), PaletteLibrary.MAX_BIOMES)
	assert_lte(int(caps["biome_bytes"]), PaletteLibrary.MAX_FILE_BYTES)
	assert_lte(int(caps["library_json_bytes"]), PaletteLibrary.MAX_FILE_BYTES)


func test_contract_wind_categories_and_aligns_match_the_palette() -> void:
	assert_eq(Array(LibraryContracts.WIND_CATEGORIES), Array(PaletteLibrary.WIND_CATEGORIES))
	assert_eq(Array(LibraryContracts.ALIGNS), Array(PaletteLibrary.ALIGN_MODES))


func test_export_json_round_trips_every_table() -> void:
	var text := LibraryContracts.export_json()
	var data: Variant = JSON.parse_string(text)
	assert_true(data is Dictionary)
	assert_eq(data["format"], LibraryContracts.FORMAT_CONTRACT)
	assert_eq(int(data["contract"]), LibraryContracts.CONTRACT_VERSION)
	assert_eq((data["roles"] as Dictionary).size(), LibraryContracts.ROLES.size())
	for role_id: String in LibraryContracts.ROLES:
		assert_eq(data["roles"][role_id], LibraryContracts.ROLES[role_id], role_id)
	assert_eq(data["size_classes"], Array(LibraryContracts.SIZE_CLASSES))
	assert_eq(data["habit_water"], Array(LibraryContracts.HABIT_WATER))
	assert_eq(data["habit_defaults"], LibraryContracts.HABIT_DEFAULTS)
	for size_class: String in LibraryContracts.SIZE_CLASSES:
		for field: String in LibraryContracts.CLASS_DEFAULTS[size_class]:
			assert_eq(
				float(data["class_defaults"][size_class][field]),
				float(LibraryContracts.CLASS_DEFAULTS[size_class][field]),
				"%s.%s" % [size_class, field]
			)
	for cap: String in LibraryContracts.CAPS:
		assert_eq(int(data["caps"][cap]), int(LibraryContracts.CAPS[cap]), cap)
	assert_eq(data["categories"], Array(LibraryContracts.CATEGORIES))
	assert_eq(data["extensions"], Array(LibraryContracts.EXTENSIONS))
	assert_true(text.ends_with("}\n"))
	assert_eq(LibraryContracts.export_json(), text, "deterministic")


func test_export_json_publishes_the_legacy_habit_lists_once() -> void:
	var data: Dictionary = JSON.parse_string(LibraryContracts.export_json())
	var legacy: Dictionary = data["legacy_habit"]
	assert_eq(legacy["emergent_keys"], Array(LegacyHabit.EMERGENT_KEYS))
	assert_eq(legacy["bank_keys"], Array(LegacyHabit.BANK_KEYS))
	assert_eq(legacy["charred_keys"], Array(LegacyHabit.CHARRED_KEYS))
	assert_eq(legacy["arid_kinds"], Array(LegacyHabit.ARID_KINDS))
	assert_eq(ScatterGround.EMERGENT_KEYS, LegacyHabit.EMERGENT_KEYS, "one list, two names")
	assert_eq(ScatterGround.BANK_KEYS, LegacyHabit.BANK_KEYS)
	assert_eq(ScatterGround.CHARRED_KEYS, LegacyHabit.CHARRED_KEYS)
	assert_eq(ScatterGround.ARID_KINDS, LegacyHabit.ARID_KINDS)
