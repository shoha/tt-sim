class_name VisualSettings
extends Resource

## Schema version 1 container for a level's visual configuration.
##
## Holds only `sun` today. It exists as a wrapper rather than LevelData owning a
## SunSettings directly so that the intent-level look schema (fog, bloom, grade)
## can be added here additively, without another change to LevelData's shape.
##
## The lo-fi, weather and foliage bags are now typed resources of their own on
## LevelData (`lofi`, `weather`, `foliage`); they are deliberately NOT nested
## here yet -- they move in a later sub-project, once the intent-dial vocabulary
## has been validated against working UI. LevelData.environment_overrides stays
## an open-keyed dictionary, because its key set is
## EnvironmentPresets.PROPERTY_DEFAULTS rather than a fixed field list.

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
