class_name PaletteFields
extends RefCounted

## The shared base of the palette validators: the palette contract's constants (formats, caps,
## value tables) and the small checks every validator uses to read untrusted values (a bounded
## String, a palette-relative path, a clamped number, a capped list, a printable label). The
## validators are PaletteSurfaces (surfaces and a biome's ground fields) and PaletteValidator
## (assets, biomes, species rules) which extends it; PaletteLibrary re-exports the constants
## under its own name, so callers keep reading PaletteLibrary.MAX_ID_LENGTH and the like.
## Pure: no files, no caches, no log.

const FORMAT := 1
const WIND_CATEGORIES := ["tree", "grass", "climber", ""]
const ALIGN_MODES := ["upright", "normal"]
const SURFACE_MAPS := ["albedo", "normal", "orm", "height"]
## What a surface is for (contract section 9): soft ground sampled top-down, rock for steep
## faces sampled sideways, walkable paving painted as paths. A missing role is ground.
const SURFACE_ROLES := ["ground", "cliff", "built"]

## Hard caps, checked before anything is kept. Sized an order of magnitude above what
## treecube builds today (8 biomes, about 25 assets and species each, a dozen surfaces),
## so they only ever bite on a corrupt or hostile document.
const MAX_BIOMES := 128
const MAX_SPECIES_PER_BIOME := 128
const MAX_ASSETS := 8192
const MAX_ASSETS_PER_SPECIES := 64
const MAX_SURFACES := 128
const MAX_RELATIONS := 32
## Per biome: ground accents and path surfaces (a handful of each in practice).
const MAX_ACCENTS := 8
const MAX_PATH_SURFACES := 32
const MAX_PATTERN_KEYS := 64
const MAX_VERBATIM_DEPTH := 4
const MAX_ID_LENGTH := 160
const MAX_TEXT_LENGTH := 128
const MAX_PATH_LENGTH := 256
## A ground accent's patch size when the palette gives none or a non-positive one (contract
## section 9), and the largest one kept.
const DEFAULT_ACCENT_SCALE_M := 6.0
const MAX_ACCENT_SCALE_M := 200.0
## A biome's water surfaces when the palette names none (contract section 9, optional
## water_bed_surface and shore_surface, P4-3), by biome key: [bed, shore]. Judged at the game
## camera on carved rivers (P4-4: forest banks are moss, which the ferns gathering there
## grow on; bare mud under a canopy read as a scar); unknown biomes take
## DEFAULT_WATER_SURFACES. A default the
## palette lacks as a ground surface is dropped ("": the ground stays).
const WATER_SURFACE_DEFAULTS := {
	"alpine_meadow": ["riverbed", "gravel"],
	"birch_woodland": ["riverbed", "moss"],
	"boreal_taiga": ["riverbed", "moss"],
	"grassland_meadow": ["riverbed", "mud"],
	"rocky_badlands": ["gravel_sandstone", "gravel_sandstone"],
	"savanna": ["riverbed", "sand"],
	"temperate_forest": ["riverbed", "moss"],
	"wetland_riparian": ["riverbed", "mud"],
}
const DEFAULT_WATER_SURFACES := ["riverbed", "mud"]


## `<package id>/<object>` (`<biome>_<season>_s<seed>/<object>`): one slash, both halves
## non-empty, no path tricks. The package half is not parsed further; ids are opaque keys.
static func _is_asset_id(id: Variant) -> bool:
	if not id is String or id.length() > MAX_ID_LENGTH or id.count("/") != 1:
		return false
	var halves: PackedStringArray = id.split("/")
	return halves[0] != "" and halves[1] != "" and not ".." in id and not "\\" in id


## The value as a String when it is one and fits, else null.
static func _text(value: Variant, max_length: int) -> Variant:
	if value is String and value.length() <= max_length:
		return value
	if value is StringName and String(value).length() <= max_length:
		return String(value)
	return null


static func _text_or(value: Variant, max_length: int, fallback: String) -> String:
	var text: Variant = _text(value, max_length)
	return text if text != null else fallback


## A palette-relative path, or `fallback` when the value could escape the palette root
## (absolute, a scheme, a parent segment, a backslash) or is not a short String.
static func _path_or(value: Variant, fallback: String) -> String:
	var text: Variant = _text(value, MAX_PATH_LENGTH)
	if text == null or text == "":
		return fallback
	if text.begins_with("/") or ":" in text or "\\" in text:
		return fallback
	if ".." in text.split("/"):
		return fallback
	return text


## The value as a float clamped to [low, high], or null when it is not a finite number.
static func _number(value: Variant, low: float, high: float) -> Variant:
	if value is bool or not (value is float or value is int):
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return null
	return clampf(number, low, high)


## An optional numeric field: `fallback` when absent (or explicitly null), a warning plus
## `fallback` when present with the wrong type, else clamped.
static func _optional_number(
	entry: Dictionary,
	field: String,
	low: float,
	high: float,
	fallback: Variant,
	label: String,
	warnings: Array[String]
) -> Variant:
	var value: Variant = entry.get(field)
	if value == null:
		return fallback
	var number: Variant = _number(value, low, high)
	if number == null:
		warnings.append("%s: %s is not a number, using the default" % [label, field])
		return fallback
	return number


static func _vector3_or_zero(value: Variant) -> Vector3:
	if not value is Array or value.size() != 3:
		return Vector3.ZERO
	var parts: Array[float] = []
	for component in value:
		var number: Variant = _number(component, 0.0, 10000.0)
		if number == null:
			return Vector3.ZERO
		parts.append(number)
	return Vector3(parts[0], parts[1], parts[2])


## The first `cap` entries of an array; one warning when the rest are dropped.
static func _capped(items: Array, cap: int, label: String, warnings: Array[String]) -> Array:
	if items.size() <= cap:
		return items
	warnings.append("%s: %d entries over the cap of %d ignored" % [label, items.size() - cap, cap])
	return items.slice(0, cap)


## The first `cap` keys of a Dictionary (insertion order, i.e. file order for JSON).
static func _capped_keys(
	items: Dictionary, cap: int, label: String, warnings: Array[String]
) -> Array:
	return _capped(items.keys(), cap, label, warnings)


## A short printable form of an untrusted value for a warning message.
static func _label(value: Variant) -> String:
	var text := str(value)
	return text if text.length() <= 48 else text.substr(0, 48) + "..."
