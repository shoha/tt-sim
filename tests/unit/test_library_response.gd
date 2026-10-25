extends GutTest

## The terrain response fields of a rule (step S12a): `slope_min_deg` and `response` through the
## whole library chain: the contract's table and curve check, the reader (errors and warnings),
## the biome compiler (carried only when present) and the lenient palette validator (a bad axis
## warns and is dropped, y is clamped, points are sorted). The engine side is
## test_scatter_curves.gd.

const SAVANNA := "res://tests/fixtures/library_savanna"
const GOOD := {
	"slope": [[0, 1], [30, 1], [45, 0.2], [60, 0]],
	"height": [[0, 0.3], [40, 1], [120, 0.5]],
	"wet": [[0, 0], [0.5, 1]],
}


## The savanna sources with its rule `key` edited by `fields`.
func _sources(key: String, fields: Dictionary) -> Dictionary:
	var sources := LibraryRegistry.read_sources(SAVANNA)
	sources.erase("files")
	var biome: Dictionary = JSON.parse_string(sources["biomes"]["savanna.json"])
	for rule: Dictionary in biome["rules"]:
		if rule["key"] == key:
			rule.merge(fields, true)
	sources["biomes"] = {"savanna.json": JSON.stringify(biome)}
	return sources


func _has(lines: Array, needle: String) -> bool:
	return lines.any(func(line: String) -> bool: return needle in line)


func test_response_problem_names_each_fault() -> void:
	var ok := [[0, 1], [90, 0]]
	assert_eq(LibraryContracts.response_problem("slope", ok), "")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1]]), "", "one point")
	assert_ne(LibraryContracts.response_problem("slope", "steep"), "", "not a list")
	var nine := []
	for i in 9:
		nine.append([i * 10, 0.5])
	assert_ne(LibraryContracts.response_problem("slope", nine), "", "nine points")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1], [91, 0]]), "", "x range")
	assert_ne(LibraryContracts.response_problem("wet", [[0, 1], [1.5, 0]]), "", "wet range")
	assert_ne(LibraryContracts.response_problem("slope", [[10, 1], [10, 0]]), "", "repeated x")
	assert_ne(LibraryContracts.response_problem("slope", [[30, 1], [10, 0]]), "", "descending x")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1], [10, 1.2]]), "", "y over 1")
	assert_ne(LibraryContracts.response_problem("slope", [[0, -0.1], [10, 1]]), "", "y under 0")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1], ["a", 1]]), "", "not numbers")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1], [10]]), "", "not a pair")
	assert_ne(LibraryContracts.response_problem("slope", [[0, true], [10, 1]]), "", "bool")
	assert_ne(LibraryContracts.response_problem("slope", [[0, 1], [10, NAN]]), "", "nan")
	assert_eq(LibraryContracts.response_problem("height", [[-500, 1], [5000, 0]]), "")
	assert_eq(LibraryContracts.response_problem("water_dist", [[0, 1], [200, 0]]), "")
	assert_ne(LibraryContracts.response_problem("moisture", ok), "", "unknown axis")


func test_the_contract_publishes_the_axes_and_stays_version_one() -> void:
	var data: Dictionary = JSON.parse_string(LibraryContracts.export_json())
	assert_eq(int(data["contract"]), 1, "additive: the contract version does not move")
	var response: Dictionary = data["response"]
	assert_eq(int(response["min_points"]), 2)
	assert_eq(int(response["max_points"]), 8)
	assert_eq(response["unsupported_axes"], ["water_dist"])
	for axis: String in LibraryContracts.RESPONSE_AXES:
		assert_eq(response["axes"][axis], LibraryContracts.RESPONSE_AXES[axis], axis)
	assert_true("response" in LibraryContracts.RULE_KEYS)
	assert_true("slope_min_deg" in LibraryContracts.RULE_KEYS)


func test_the_reader_accepts_good_fields_and_checks_bad_ones() -> void:
	var good := LibraryReader.read(
		_sources("dry_grass", {"slope_min_deg": 15, "response": GOOD.duplicate(true)})
	)
	assert_eq(good["errors"], [])
	assert_eq(good["warnings"], [], "no unknown-key warning for either field")
	var cases := {
		"slope_min high": {"slope_min_deg": 120},
		"slope_min text": {"slope_min_deg": "steep"},
		"response list": {"response": [[0, 1], [1, 0]]},
		"one point": {"response": {"slope": [[0, 1]]}},
		"x out of range": {"response": {"slope": [[0, 1], [100, 0]]}},
		"x descending": {"response": {"slope": [[40, 1], [10, 0]]}},
		"y too high": {"response": {"wet": [[0, 2], [1, 0]]}},
		"not a pair": {"response": {"height": [[0, 1], 5]}},
	}
	for label: String in cases:
		var read := LibraryReader.read(_sources("dry_grass", cases[label]))
		assert_false(read["ok"], label)
		assert_true(_has(read["errors"], "dry_grass"), label)
	var unknown := LibraryReader.read(
		_sources("dry_grass", {"response": {"moisture": [[0, 1], [1, 0]]}})
	)
	assert_true(unknown["ok"], "an unknown axis is a warning")
	assert_true(_has(unknown["warnings"], "moisture"))
	var water := LibraryReader.read(
		_sources("dry_grass", {"response": {"water_dist": [[0, 1], [20, 0]]}})
	)
	assert_true(water["ok"])
	assert_true(_has(water["warnings"], "water_dist"), "named as not evaluated yet")


func test_the_compiler_carries_the_fields_only_when_present() -> void:
	var plain := BiomeCompiler.compile(LibraryReader.read(_sources("dry_grass", {})), {})
	for rule: Dictionary in plain["palette"]["biomes"][0]["species"]:
		assert_false(rule.has("slope_min_deg"), rule["key"])
		assert_false(rule.has("response"), rule["key"])
	var fields := {"slope_min_deg": 15, "response": GOOD.duplicate(true)}
	var curved := BiomeCompiler.compile(LibraryReader.read(_sources("dry_grass", fields)), {})
	var seen := 0
	for rule: Dictionary in curved["palette"]["biomes"][0]["species"]:
		if rule["key"] == "dry_grass":
			seen += 1
			assert_eq(float(rule["slope_min_deg"]), 15.0)
			assert_eq(rule["response"], JSON.parse_string(JSON.stringify(GOOD)))
		else:
			assert_false(rule.has("response"), rule["key"])
	assert_eq(seen, 1)
	var served: Dictionary = PaletteLibrary.validate_palette(curved["palette"])["palette"]
	for rule: Dictionary in served["biomes"][0]["species"]:
		if rule["key"] == "dry_grass":
			assert_eq(float(rule["slope_min_deg"]), 15.0)
			var axes: Array = (rule["response"] as Dictionary).keys()
			axes.sort()
			assert_eq(axes, ["height", "slope", "wet"])
			assert_eq(rule["response"]["slope"][2], [45.0, 0.2])
		else:
			assert_false(rule.has("response"), "legacy rules stay as they were")


func test_the_validator_sorts_clamps_and_drops_with_a_warning() -> void:
	var warnings: Array[String] = []
	var entry := {
		"slope_min_deg": 20,
		"response":
		{
			"slope": [[60, 0], [0, 1], [30, 1]],
			"height": [[0, 1.4], [10, -2]],
			"wet": [[0, 1]],
			"moisture": [[0, 1], [1, 0]],
			"water_dist": [[0, 1], [20, 0]],
		},
	}
	var out := PaletteValidator._library_fields(entry, "rule", warnings)
	assert_eq(out["slope_min_deg"], 20.0)
	var response: Dictionary = out["response"]
	assert_eq(response["slope"], [[0.0, 1.0], [30.0, 1.0], [60.0, 0.0]], "sorted by x")
	assert_eq(response["height"], [[0.0, 1.0], [10.0, 0.0]], "y clamped")
	assert_false(response.has("wet"), "one point: dropped")
	assert_false(response.has("moisture"), "unknown axis: dropped")
	assert_true(response.has("water_dist"), "kept and planned, not evaluated")
	assert_true(warnings.any(func(w: String) -> bool: return "response.wet" in w))
	assert_true(warnings.any(func(w: String) -> bool: return "moisture" in w))
	assert_true(warnings.any(func(w: String) -> bool: return "response.height" in w))
	var bad: Array[String] = []
	var junk := PaletteValidator._library_fields(
		{"slope_min_deg": "steep", "response": "no", "habit": null}, "rule", bad
	)
	assert_false(junk.has("slope_min_deg"))
	assert_false(junk.has("response"))
	assert_eq(bad.size(), 2)
	var quiet: Array[String] = []
	assert_eq(PaletteValidator._library_fields({}, "rule", quiet), {}, "absent: no fields")
	assert_eq(quiet, [], "absent: no warning")
	var duplicate: Array[String] = []
	var repeated := PaletteValidator._library_fields(
		{"response": {"slope": [[10, 1], [10, 0]]}}, "rule", duplicate
	)
	assert_false(repeated.has("response"), "a repeated x is dropped")
	assert_eq(duplicate.size(), 1)
