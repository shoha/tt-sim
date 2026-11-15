class_name RenderStyle
extends RefCounted

## Which look a level is drawn in: Classic (the game as it was) or Painted (the painter's sheet
## owns the light, docs/systems/painter.md). Visual only and per player: a peer on Classic sees
## the same map, so mixing styles across peers is safe and nothing here is networked except the
## map's own `look` field, which travels in the level data like the environment preset.
##
## The model. The effective style comes from two layers:
##   1. the local Settings choice (Settings > Graphics > Look, graphics/look): Classic or Painted
##      overrides every map; "Map's choice" follows the level;
##   2. the level's `look` field (LevelData.look: {"style", "sheet", "mood"}), Classic when unset.
## Then the environment preset decides whether the painter can draw it at all: MOOD_FOR_PRESET
## maps each preset to a mood, or to "" for the indoor and effect presets no mood paints yet, and
## those fall back to Classic. A look's own mood wins over the preset's.
##
## The Settings default is Classic, so a player who never opens the row sees no change. The
## quality presets (QualityPreset) do not set this row; a weak-GPU tier that forces Classic is the
## cost card's (A5). This script is named by start-up code (the Settings graphics helper), so it
## names no other painter script: PainterScene and PainterSheet load by path on first use.

const CLASSIC := "classic"
const PAINTED := "painted"
const STYLES: Array[String] = [CLASSIC, PAINTED]
## The sheet a look names when it names none (painter/sheets/core.sheet).
const DEFAULT_SHEET := "core"

## Settings choices (the item ids of the Look row in settings_menu.tscn).
const CHOICE_CLASSIC := 0
const CHOICE_PAINTED := 1
const CHOICE_MAP := 2
const CHOICES: Array[int] = [CHOICE_CLASSIC, CHOICE_PAINTED, CHOICE_MAP]
const DEFAULT_CHOICE := CHOICE_CLASSIC
## The settings file key, in the [graphics] section.
const KEY := "look"

## Every environment preset (EnvironmentPresets.PRESETS) to the mood that paints it, or "" for
## Classic only. "" (the map's own lighting) is painted as summer.
const MOOD_FOR_PRESET: Dictionary = {
	"": "summer",
	"outdoor_day": "summer",
	"outdoor_overcast": "grimdark",
	"outdoor_sunset": "dusk",
	"outdoor_night": "summer",
	"forest": "summer",
	"swamp": "grimdark",
	"arctic": "winter",
	"desert": "autumn",
	"indoor_neutral": "",
	"dungeon_dark": "",
	"dungeon_crypt": "",
	"cave": "",
	"tavern": "",
	"underwater": "",
	"hell": "",
	"ethereal": "",
	"none": "",
	"bright_editor": "",
}

## The applied Settings choice. Root sets it from the settings file at startup, Settings sets it
## on Apply, and LevelEnvironmentManager reads it whenever it applies a level's light.
static var choice: int = DEFAULT_CHOICE


## Starts PainterWarmup (the painter's shaders compiling on a worker) when the Settings choice can
## paint a level: Painted, or the map's choice. A Classic session never loads it. Root calls it
## behind the title and Settings when the choice changes.
static func start_warmup() -> void:
	if choice == CHOICE_CLASSIC:
		return
	(load("res://painter/painter_warmup.gd") as GDScript).call("start")


## Stops PainterWarmup at exit when it was loaded (Root's _exit_tree).
static func release_warmup() -> void:
	var path := "res://painter/painter_warmup.gd"
	if ResourceLoader.has_cached(path):
		(load(path) as GDScript).call("release")


## [param value] if it is one of CHOICES, else DEFAULT_CHOICE.
static func sanitize(value: int) -> int:
	return value if CHOICES.has(value) else DEFAULT_CHOICE


## The saved choice in a loaded settings file (DEFAULT_CHOICE when absent or unknown).
static func stored(config: ConfigFile) -> int:
	var value: Variant = config.get_value("graphics", KEY, DEFAULT_CHOICE)
	return sanitize(int(value)) if value is int or value is float else DEFAULT_CHOICE


## A level's `look` field cleaned for storage: {} (Classic, the preset's mood) or a dictionary
## with a known "style", a "sheet" and a "mood" (either may be "", meaning the default).
static func sanitize_look(raw: Variant) -> Dictionary:
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var look: Dictionary = raw
	var style := str(look.get("style", CLASSIC))
	return {
		"style": style if STYLES.has(style) else CLASSIC,
		"sheet": str(look.get("sheet", "")),
		"mood": str(look.get("mood", "")),
	}


## The mood that paints [param preset], or "" when only Classic can draw it.
static func mood_for_preset(preset: String) -> String:
	return str(MOOD_FOR_PRESET.get(preset, ""))


## {"style", "sheet", "mood"}: what a level with [param look] and environment [param preset] is
## drawn in under the Settings [param settings_choice]. Pure.
static func resolve(look: Dictionary, preset: String, settings_choice: int = choice) -> Dictionary:
	var clean := sanitize_look(look)
	var style := str(clean.get("style", CLASSIC))
	match sanitize(settings_choice):
		CHOICE_CLASSIC:
			style = CLASSIC
		CHOICE_PAINTED:
			style = PAINTED
	var preset_mood := mood_for_preset(preset)
	var mood := str(clean.get("mood", ""))
	if mood.is_empty():
		mood = preset_mood
	if preset_mood.is_empty():
		style = CLASSIC
	var sheet := str(clean.get("sheet", ""))
	return {
		"style": style,
		"sheet": sheet if not sheet.is_empty() else DEFAULT_SHEET,
		"mood": mood if style == PAINTED else "",
	}
