extends GutTest

## HDRI sky presets: every entry points at shipped files with sane numbers, the
## resolver builds a panorama sky (and falls back to the gradient when the file
## is missing), and sky rotation follows the sun only for HDRI keys.

const HDRI_KEYS := ["clear_day", "cloudy", "overcast", "morning", "sunset", "dusk", "storm"]
const COLOURS := [
	"sky_top_color", "sky_horizon_color", "ground_horizon_color", "ground_bottom_color"
]


func test_hdri_entries_point_at_shipped_files_with_sane_numbers() -> void:
	for key in HDRI_KEYS:
		assert_true(EnvironmentPresets.is_hdri_sky(key), key)
		var entry: Dictionary = EnvironmentPresets.SKY_PRESETS[key]
		for field in ["panorama", "tile", "preview"]:
			assert_true(ResourceLoader.exists(entry[field]), "%s %s" % [key, field])
		assert_between(float(entry["sun_azimuth_deg"]), 0.0, 360.0, key)
		assert_between(float(entry["energy"]), 0.05, 4.0, key)
		for colour in COLOURS:
			assert_true(entry.has(colour), "%s keeps %s for the fallback" % [key, colour])
		assert_false(String(entry["description"]).is_empty(), key + " described")
	assert_false(EnvironmentPresets.is_hdri_sky("night_sky"))
	assert_false(EnvironmentPresets.is_hdri_sky(""))
	assert_false(EnvironmentPresets.is_hdri_sky("map_default"))


func test_names_include_the_eight_keys() -> void:
	var names := EnvironmentPresets.get_sky_preset_names()
	for key in HDRI_KEYS:
		assert_has(names, key)
	assert_has(names, "night_sky")


func test_hdri_preset_builds_a_panorama_sky_and_night_stays_procedural() -> void:
	var day := EnvironmentPresets.create_sky_from_preset("clear_day")
	assert_true(day.sky_material is PanoramaSkyMaterial)
	var material := day.sky_material as PanoramaSkyMaterial
	assert_not_null(material.panorama)
	# PanoramaSkyMaterial.energy_multiplier is a single-precision engine property;
	# assigning the double preset literal truncates it (0.754 -> 0.7540000081062317
	# on readback), so this compares with tolerance rather than assert_eq.
	assert_almost_eq(
		material.energy_multiplier,
		float(EnvironmentPresets.SKY_PRESETS["clear_day"]["energy"]),
		0.0001
	)
	assert_true(
		EnvironmentPresets.create_sky_from_preset("night_sky").sky_material is ProceduralSkyMaterial
	)


func test_missing_panorama_falls_back_to_the_gradient_and_warns_once() -> void:
	var config: Dictionary = EnvironmentPresets.SKY_PRESETS["clear_day"].duplicate()
	config["panorama"] = "res://assets/skies/does_not_exist.exr"
	var sky := EnvironmentPresets.create_sky_from_config(config)
	assert_true(sky.sky_material is ProceduralSkyMaterial)
	assert_eq((sky.sky_material as ProceduralSkyMaterial).sky_top_color, config["sky_top_color"])
	EnvironmentPresets.create_sky_from_config(config)
	assert_engine_error(1, "one warning for the missing file, not one per call")


func test_sky_rotation_follows_the_sun_only_for_hdri_keys() -> void:
	assert_eq(EnvironmentPresets.sky_rotation_for(90.0, "night_sky"), Vector3.ZERO)
	assert_eq(EnvironmentPresets.sky_rotation_for(90.0, ""), Vector3.ZERO)
	assert_eq(EnvironmentPresets.sky_rotation_for(90.0, "map_default"), Vector3.ZERO)
	var sky_azimuth := EnvironmentPresets.get_sky_sun_azimuth("clear_day")
	var offset := EnvironmentPresets.SKY_YAW_OFFSET_DEG
	var expected := wrapf(90.0 + sky_azimuth + offset, 0.0, 360.0)
	var rotation := EnvironmentPresets.sky_rotation_for(90.0, "clear_day")
	assert_eq(rotation.x, 0.0)
	assert_eq(rotation.z, 0.0)
	assert_almost_eq(rotation.y, deg_to_rad(expected), 0.0001)
	# A sun azimuth that lands the yaw at 350 once the sky azimuth and offset are
	# added: proves the wrap rather than a negative angle.
	var sun_for_350 := wrapf(350.0 - sky_azimuth - offset, 0.0, 360.0)
	var wrapped := EnvironmentPresets.sky_rotation_for(sun_for_350, "clear_day")
	assert_almost_eq(wrapped.y, deg_to_rad(350.0), 0.0001, "wraps into [0, 360)")
	assert_eq(EnvironmentPresets.get_sky_sun_azimuth("night_sky"), 0.0)


## Pins the calibrated convention with a literal, not the formula: on the sunset
## dome (sky azimuth 270.7) adding versus subtracting the sky azimuth differ by
## 181 degrees, and the live check on 2026-09-16 proved the sun at azimuth 0
## needs a yaw of 90.7. A sign or offset regression fails here.
func test_sunset_yaw_matches_the_live_calibration() -> void:
	var at_zero := EnvironmentPresets.sky_rotation_for(0.0, "sunset")
	assert_almost_eq(rad_to_deg(at_zero.y), 90.7, 0.1, "calibrated on the sunset dome")
	var at_180 := EnvironmentPresets.sky_rotation_for(180.0, "sunset")
	assert_almost_eq(rad_to_deg(at_180.y), 270.7, 0.1)
