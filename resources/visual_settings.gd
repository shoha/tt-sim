class_name VisualSettings
extends Resource

## Schema version 1 container for a level's visual configuration.
##
## Holds only `sun` today. It exists as a wrapper rather than LevelData owning a
## SunSettings directly so that the intent-level look schema (fog, bloom, grade)
## can be added here additively, without another change to LevelData's shape.
##
## The four remaining untyped override bags on LevelData
## (environment_overrides, lofi_overrides, weather_overrides,
## foliage_overrides) are deliberately NOT migrated into this resource yet --
## they move in a later sub-project, once the intent-dial vocabulary has been
## validated against working UI.

@export var sun: SunSettings = SunSettings.new()


## A fresh level's visual settings.
static func default() -> VisualSettings:
	var settings := VisualSettings.new()
	settings.sun = SunSettings.default()
	return settings


func to_dict() -> Dictionary:
	return {"sun": sun.to_dict()}


static func from_dict(data: Dictionary) -> VisualSettings:
	var settings := VisualSettings.new()
	var raw: Variant = data.get("sun", {})
	settings.sun = SunSettings.from_dict(raw) if raw is Dictionary else SunSettings.default()
	return settings


## Independent copy, including the nested sun. Required by the edit drawer's
## cancel path -- see SunSettings.copy_settings().
func copy_settings() -> VisualSettings:
	var settings := VisualSettings.new()
	settings.sun = sun.copy_settings()
	return settings
