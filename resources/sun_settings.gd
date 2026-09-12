class_name SunSettings
extends Resource

## Typed sun and shadow configuration for a level (schema version 1).
##
## Replaces the untyped LevelData.sun_overrides dictionary, which carried only
## "mode" and "time_of_day" and therefore locked direction, color, and energy
## together on a single hand-authored curve. Every field here is independently
## art-directable.
##
## Construction: production code uses default() for a fresh level, from_dict()
## when loading a version-1 level, or from_legacy() when migrating a level saved
## before format_version existed. The field initializers below exist so that a
## bare new() is valid (tests, and from_dict()'s missing-key fallback); they are
## deliberately neutral and are NOT the product's default sun, which is derived
## from DefaultSun.KEYFRAMES.
##
## softness and shadow_darkness default to the engine defaults that were in
## effect before they were exposed, so a migrated level renders identically.

## "auto" (sun only if the map brought no lights of its own) | "on" | "off"
@export var mode: String = "auto"

## Compass rotation, degrees. Applied to DirectionalLight3D.rotation_degrees.y.
@export var azimuth_degrees: float = 0.0

## Height above the horizon, degrees. Applied as -rotation_degrees.x.
@export var elevation_degrees: float = 45.0

@export var color: Color = Color.WHITE
@export var energy: float = 1.0

@export var shadows_enabled: bool = true

## Sun angular size in degrees. Applied to light_angular_distance, which gives
## distance-correct penumbra: shadows stay sharp at contact and soften with
## distance. 0.0 is the engine default (hard shadows).
@export var softness: float = 0.0

## Applied to shadow_opacity (0-1). Lowering it lifts shadows toward the ambient
## term without removing them.
@export var shadow_darkness: float = 1.0

## Last input given to DefaultSun.settings_for_time(). Retained so the edit
## panel can offer to regenerate from a time of day, and can detect that the sun
## has since been hand-aimed by comparing against that regenerated result.
@export var time_of_day: float = DefaultSun.DEFAULT_TIME_OF_DAY


## The product's default sun: whatever the keyframes say at the default hour.
## Derived rather than written as literals so DefaultSun.KEYFRAMES stays the
## single source of truth for what "default lighting" looks like.
static func default() -> SunSettings:
	return DefaultSun.settings_for_time(DefaultSun.DEFAULT_TIME_OF_DAY)


## Migrate a pre-version-1 LevelData.sun_overrides dictionary, whose only keys
## were "mode" and "time_of_day".
##
## Appearance-preserving by construction: direction, color, and energy come from
## the same DefaultSun keyframe lerp the old runtime used, and the three shadow
## fields keep their SunSettings defaults, which are the values that were in
## effect when shadows were hardcoded. See
## tests/unit/test_sun_settings_migration.gd for the proof.
static func from_legacy(sun_overrides: Dictionary) -> SunSettings:
	var hour: float = float(sun_overrides.get("time_of_day", DefaultSun.DEFAULT_TIME_OF_DAY))
	var settings := DefaultSun.settings_for_time(hour)
	settings.mode = str(sun_overrides.get("mode", "auto"))
	return settings


## JSON-safe dictionary. Colors become "#rrggbb" strings, matching the existing
## convention in EnvironmentPresets.overrides_to_json(). Used for both the
## on-disk level format and the network payload, so there is one format.
func to_dict() -> Dictionary:
	return {
		"mode": mode,
		"azimuth_degrees": azimuth_degrees,
		"elevation_degrees": elevation_degrees,
		"color": "#" + color.to_html(false),
		"energy": energy,
		"shadows_enabled": shadows_enabled,
		"softness": softness,
		"shadow_darkness": shadow_darkness,
		"time_of_day": time_of_day,
	}


## Rebuild from to_dict() output. Missing keys keep the field initializer value,
## so a partial dictionary is always safe.
static func from_dict(data: Dictionary) -> SunSettings:
	var s := SunSettings.new()
	s.mode = str(data.get("mode", s.mode))
	s.azimuth_degrees = float(data.get("azimuth_degrees", s.azimuth_degrees))
	s.elevation_degrees = float(data.get("elevation_degrees", s.elevation_degrees))
	s.color = _color_from_json(data.get("color", s.color))
	s.energy = float(data.get("energy", s.energy))
	s.shadows_enabled = bool(data.get("shadows_enabled", s.shadows_enabled))
	s.softness = float(data.get("softness", s.softness))
	s.shadow_darkness = float(data.get("shadow_darkness", s.shadow_darkness))
	s.time_of_day = float(data.get("time_of_day", s.time_of_day))
	return s


## Independent copy. Resource is a reference type, so plain assignment aliases,
## and the drawer's cancel path depends on this being a real copy.
##
## Resource.duplicate() copies every @export field by value, which is exactly
## what is needed here: all nine fields are value types (String, float, Color,
## bool) and there are no sub-resources. Deliberately NOT a to_dict()/from_dict()
## round-trip, which would quantize the color to 8 bits per channel -- see
## test_copy_settings_preserves_full_color_precision.
##
## Note for wrappers: a resource that OWNS a sub-resource must NOT use plain
## duplicate(), because shallow duplication aliases the child. VisualSettings
## copies its `sun` explicitly for that reason.
func copy_settings() -> SunSettings:
	return duplicate() as SunSettings


## Accept a hex string (both disk and network carry to_dict()'s hex form) or a
## live Color (in-memory dictionaries). Anything else falls back to white rather
## than failing the level load.
static func _color_from_json(value: Variant) -> Color:
	if value is Color:
		return value
	if value is String and (value as String).begins_with("#"):
		return Color.from_string(value, Color.WHITE)
	return Color.WHITE
