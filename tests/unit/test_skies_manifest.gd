extends GutTest

## The sky manifest drives the curation tool; every entry must be complete and
## every curated output it promises must exist in assets/skies/, or the Sky
## pane ships a broken tile.

const MANIFEST_PATH := "res://tools/skies_manifest.json"
const REPORT_PATH := "res://assets/skies/curation_report.json"
const REQUIRED := [
	"key", "label", "description", "source", "source_name", "source_site", "source_url"
]


func _load_json(path: String) -> Variant:
	var text := FileAccess.get_file_as_string(path)
	assert_false(text.is_empty(), path + " readable")
	return JSON.parse_string(text)


func test_manifest_entries_are_complete_and_unique() -> void:
	var entries: Array = _load_json(MANIFEST_PATH)
	assert_eq(entries.size(), 7)
	var keys := {}
	for entry in entries:
		for field in REQUIRED:
			assert_true(entry.has(field) and not String(entry[field]).is_empty(), field)
		assert_false(keys.has(entry["key"]), "duplicate key " + String(entry["key"]))
		keys[entry["key"]] = true
		assert_true(entry.has("energy"), "energy key present (null allowed)")


func test_report_covers_every_manifest_key_with_existing_outputs() -> void:
	var entries: Array = _load_json(MANIFEST_PATH)
	var report: Dictionary = _load_json(REPORT_PATH)
	for entry in entries:
		var key: String = entry["key"]
		assert_true(report.has(key), key + " reported")
		var row: Dictionary = report[key]
		for field in ["panorama", "tile", "preview"]:
			assert_true(ResourceLoader.exists(row[field]), "%s %s exists" % [key, field])
		assert_between(float(row["sun_azimuth_deg"]), 0.0, 360.0)
		assert_between(float(row["energy"]), 0.05, 4.0)
		assert_eq(row["description"], entry["description"])


## The runtime table is pasted from the report by hand; a curation rerun that is
## not pasted back would silently ship stale numbers or paths.
func test_sky_presets_table_matches_the_curation_report() -> void:
	var report: Dictionary = _load_json(REPORT_PATH)
	for key in report:
		var row: Dictionary = report[key]
		assert_true(EnvironmentPresets.SKY_PRESETS.has(key), key + " in SKY_PRESETS")
		var entry: Dictionary = EnvironmentPresets.SKY_PRESETS[key]
		for field in ["panorama", "tile", "preview"]:
			assert_eq(entry[field], row[field], "%s %s" % [key, field])
		assert_almost_eq(
			float(entry["sun_azimuth_deg"]), float(row["sun_azimuth_deg"]), 0.05, key + " azimuth"
		)
		assert_almost_eq(float(entry["energy"]), float(row["energy"]), 0.0005, key + " energy")
		assert_eq(entry["description"], row["description"], key + " description")
