extends GutTest

## Migration oracle for the sun schema (see
## docs/superpowers/specs/2026-09-11-sun-shadow-visual-settings-design.md).
##
## _reference_configure() below is a FROZEN, verbatim copy of the algorithm
## DefaultSun.configure_directional_light() used before the sun schema was
## introduced. It exists so that "the migration is appearance-preserving" is a
## verified property rather than a claim: Task 1 asserts the live pre-migration
## implementation agrees with this copy, and Task 4 asserts the post-migration
## code path agrees with it too.
##
## DO NOT EDIT _reference_configure(). If a future change legitimately alters
## the sun ramp, add new tests alongside these -- do not update the frozen copy,
## because then it no longer records what shipped.

const _FROZEN_HOURS: Array[float] = [0.0, 6.0, 12.0, 18.0, 24.0]

## Hours to sweep. Covers every keyframe, both midnight ends, the default
## (14.0), several inter-keyframe points, and the out-of-range clamp.
const _SWEEP: Array[float] = [
	-5.0, 0.0, 1.5, 3.0, 6.0, 9.0, 11.99, 12.0, 14.0, 15.5, 18.0, 21.0, 23.5, 24.0, 30.0
]


func _reference_configure(light: DirectionalLight3D, time_of_day: float) -> void:
	var t := clampf(time_of_day, 0.0, 24.0)

	var lo_hour := 0.0
	var hi_hour := 24.0
	for hour in _FROZEN_HOURS:
		if hour <= t:
			lo_hour = hour
		if hour >= t:
			hi_hour = hour
			break

	var lo: Dictionary = DefaultSun.KEYFRAMES[lo_hour]
	var hi: Dictionary = DefaultSun.KEYFRAMES[hi_hour]
	var span := hi_hour - lo_hour
	var f := 0.0 if span == 0.0 else (t - lo_hour) / span

	var elevation: float = lerpf(lo["elevation_degrees"], hi["elevation_degrees"], f)
	var azimuth: float = lerpf(lo["azimuth_degrees"], hi["azimuth_degrees"], f)
	var color: Color = lo["color"].lerp(hi["color"], f)
	var energy: float = lerpf(lo["energy"], hi["energy"], f)

	light.rotation_degrees = Vector3(-elevation, azimuth, 0.0)
	light.light_color = color
	light.light_energy = energy


func _assert_lights_match(
	actual: DirectionalLight3D, expected: DirectionalLight3D, hour: float
) -> void:
	assert_almost_eq(
		actual.rotation_degrees.x, expected.rotation_degrees.x, 0.0001, "elevation at %f" % hour
	)
	assert_almost_eq(
		actual.rotation_degrees.y, expected.rotation_degrees.y, 0.0001, "azimuth at %f" % hour
	)
	assert_almost_eq(actual.light_color.r, expected.light_color.r, 0.0001, "color.r at %f" % hour)
	assert_almost_eq(actual.light_color.g, expected.light_color.g, 0.0001, "color.g at %f" % hour)
	assert_almost_eq(actual.light_color.b, expected.light_color.b, 0.0001, "color.b at %f" % hour)
	assert_almost_eq(actual.light_energy, expected.light_energy, 0.0001, "energy at %f" % hour)


# The test that proved _reference_configure() faithful against the live
# pre-schema DefaultSun.configure_directional_light() lived here. That function
# no longer exists, so the check cannot be re-run; it passed in the commit that
# introduced this file, which is what makes the frozen copy trustworthy.
# Task 4's migration tests are the ongoing consumers of the oracle.


func test_migrated_legacy_sun_renders_identically_across_the_day() -> void:
	# The load-bearing migration guarantee: for every time_of_day a pre-schema
	# level could have stored, migrating and applying must put the light in
	# exactly the state the old code would have.
	for hour in _SWEEP:
		var migrated_light := DirectionalLight3D.new()
		var frozen_light := DirectionalLight3D.new()

		var settings := SunSettings.from_legacy({"mode": "on", "time_of_day": hour})
		DefaultSun.apply(migrated_light, settings)
		_reference_configure(frozen_light, hour)

		_assert_lights_match(migrated_light, frozen_light, hour)

		migrated_light.free()
		frozen_light.free()


func test_migrated_legacy_sun_with_no_time_of_day_uses_the_default_hour() -> void:
	var migrated_light := DirectionalLight3D.new()
	var frozen_light := DirectionalLight3D.new()

	var settings := SunSettings.from_legacy({"mode": "auto"})
	DefaultSun.apply(migrated_light, settings)
	_reference_configure(frozen_light, DefaultSun.DEFAULT_TIME_OF_DAY)

	_assert_lights_match(migrated_light, frozen_light, DefaultSun.DEFAULT_TIME_OF_DAY)

	migrated_light.free()
	frozen_light.free()


func test_migration_preserves_the_shadow_state_that_was_in_effect_before() -> void:
	# Before the schema, shadow_enabled was hardcoded true, and
	# light_angular_distance / shadow_opacity were never touched, so they sat at
	# their engine defaults of 0.0 and 1.0. Migration must reproduce that or
	# existing levels change appearance.
	#
	# Pin the engine side of that claim too, on a bare light: the justification
	# above is only as good as those defaults, so a Godot version bump that moved
	# either one would otherwise change every migrated level's shadows silently
	# while this test stayed green. shadow_enabled is deliberately NOT asserted
	# here -- a bare DirectionalLight3D has shadows OFF, and it is our applier
	# that turns them on, which is exactly what the hardcoded `true` reproduced.
	var bare := DirectionalLight3D.new()
	assert_almost_eq(bare.light_angular_distance, 0.0, 0.0001, "engine softness default moved")
	assert_almost_eq(bare.shadow_opacity, 1.0, 0.0001, "engine shadow_opacity default moved")
	bare.free()

	var settings := SunSettings.from_legacy({"mode": "on", "time_of_day": 10.0})

	assert_eq(settings.shadows_enabled, true)
	assert_almost_eq(settings.softness, 0.0, 0.0001)
	assert_almost_eq(settings.shadow_darkness, 1.0, 0.0001)


func test_migration_carries_the_mode_through_unchanged() -> void:
	assert_eq(SunSettings.from_legacy({"mode": "off"}).mode, "off")
	assert_eq(SunSettings.from_legacy({"mode": "on"}).mode, "on")
	assert_eq(SunSettings.from_legacy({"mode": "auto"}).mode, "auto")


func test_migration_defaults_mode_to_auto_when_absent() -> void:
	assert_eq(SunSettings.from_legacy({}).mode, "auto")


func test_migration_records_the_hour_it_came_from() -> void:
	# So the edit panel can still offer "regenerate from this time of day" on a
	# migrated level.
	assert_almost_eq(SunSettings.from_legacy({"time_of_day": 7.25}).time_of_day, 7.25, 0.001)
