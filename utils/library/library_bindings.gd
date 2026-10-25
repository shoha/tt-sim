class_name LibraryBindings
extends RefCounted

## The named things game code needs from a content library (design doc 2.7.3 and 2.8): the
## surface fire leaves, the biome a fire turns a forest into, the surfaces crossings are built
## of, the Paint tool's first surface, the water bed and shore, the New map dialog's first
## biome. They used to be constants in fire_sweep.gd, authored_crossings.gd, authoring_panel.gd,
## ground_palette.gd and new_map_dialog.gd; those constants stay as the legacy values and are
## this class's DEFAULTS, so a game with no content library, or a library that binds nothing,
## behaves exactly as before.
##
## A library names bindings in library.json `bindings` ({"fire": {"ash_surface": "ash"}}) and
## `default_biome`. LibraryRegistry.apply flattens them to runtime names (a surface the library
## itself defines becomes its runtime surface name, a biome its palette `biome` field) and
## records them here with set_served(); value() answers from the served libraries in the order
## they were set and falls back to the default. Pure statics plus that one table.

## Binding key -> {default, kind}. kind says what the value names: a palette "surface", a
## palette "biome" (the biome field, not a season id) or a "biome_id" (a runtime biome id).
const TABLE := {
	"fire.ash_surface": {"default": "ash", "kind": "surface"},
	"fire.ash_fallback": {"default": "dirt_peat", "kind": "surface"},
	"fire.burnt_biome": {"default": "burnt_forest", "kind": "biome"},
	"crossings.planks": {"default": "planks", "kind": "surface"},
	"crossings.moss": {"default": "moss", "kind": "surface"},
	"crossings.gravel": {"default": "gravel", "kind": "surface"},
	"crossings.stone_default": {"default": "cliff", "kind": "surface"},
	"crossings.paving": {"default": "flagstone", "kind": "surface"},
	"paint.default": {"default": "dirt_road_packed", "kind": "surface"},
	"water.bed": {"default": "riverbed", "kind": "surface"},
	"water.shore": {"default": "mud", "kind": "surface"},
	"default_biome": {"default": "temperate_forest_summer_s1", "kind": "biome_id"},
}
const MAX_VALUE_LENGTH := 64

## Library id -> {binding key: runtime value}, in the order set_served was called.
static var _served: Dictionary = {}


## The binding `key`: the first served library that sets it, else the legacy default. "" for a
## key that is not in TABLE.
static func value(key: String) -> String:
	for library_id: String in _served:
		var values: Dictionary = _served[library_id]
		if values.has(key):
			return String(values[key])
	return default_of(key)


## The legacy default of `key` (what the game did before bindings existed).
static func default_of(key: String) -> String:
	return String((TABLE.get(key, {}) as Dictionary).get("default", ""))


## Records the runtime values of one served library (replacing its earlier record).
static func set_served(library_id: String, values: Dictionary) -> void:
	_served[library_id] = values.duplicate()


## Forgets every served library: all bindings read their defaults again.
static func clear() -> void:
	_served.clear()


static func fire_ash_surface() -> String:
	return value("fire.ash_surface")


static func fire_ash_fallback() -> String:
	return value("fire.ash_fallback")


static func fire_burnt_biome() -> String:
	return value("fire.burnt_biome")


static func crossing_planks() -> String:
	return value("crossings.planks")


static func crossing_moss() -> String:
	return value("crossings.moss")


static func crossing_gravel() -> String:
	return value("crossings.gravel")


static func crossing_stone_default() -> String:
	return value("crossings.stone_default")


static func crossing_paving() -> String:
	return value("crossings.paving")


static func paint_default() -> String:
	return value("paint.default")


## [bed, shore]: the surfaces that dress water where the palette says nothing else
## (GroundPalette.base_water_surfaces).
static func water_defaults() -> PackedStringArray:
	return PackedStringArray([value("water.bed"), value("water.shore")])


## The runtime id of the biome the New map dialog starts on.
static func default_biome() -> String:
	return value("default_biome")


## The bindings of a library.json flattened to {"fire.ash_surface": "ash", ...} plus problems.
## `bindings` is the library's `bindings` object (or null), `default_biome` its top-level field
## (or null). A key outside TABLE, a value that is not a short name, or a section that is not an
## object is reported and left out; the rest is kept. Pure.
static func flatten(bindings: Variant, default_biome_id: Variant) -> Dictionary:
	var flat := {}
	var problems: Array[String] = []
	if bindings is Dictionary:
		for section: Variant in bindings:
			var body: Variant = (bindings as Dictionary)[section]
			if not body is Dictionary:
				problems.append("bindings.%s is not an object (ignored)" % _short(String(section)))
				continue
			for name: Variant in body as Dictionary:
				var key := "%s.%s" % [section, name]
				_take(flat, problems, key, (body as Dictionary)[name])
	elif bindings != null:
		problems.append("bindings is not an object (ignored)")
	if default_biome_id != null:
		_take(flat, problems, "default_biome", default_biome_id)
	return {"values": flat, "problems": problems}


static func _take(flat: Dictionary, problems: Array[String], key: String, raw: Variant) -> void:
	if not TABLE.has(key):
		problems.append("bindings: unknown binding '%s' (ignored)" % _short(key))
	elif not raw is String or not _name_ok(raw):
		problems.append("bindings: '%s' must be a short lower-case name (ignored)" % key)
	else:
		flat[key] = raw


static func _name_ok(text: String) -> bool:
	if text.length() < 1 or text.length() > MAX_VALUE_LENGTH:
		return false
	for i in text.length():
		var c := text.unicode_at(i)
		var low := c >= 97 and c <= 122
		var digit := c >= 48 and c <= 57
		if not (low or digit or c == 95) or (i == 0 and not low):
			return false
	return true


## `flat` (flatten's values) as runtime values for library `library_id`: a surface binding that
## names one of the library's own surfaces (`own_surfaces`, local names) becomes its runtime
## surface name, otherwise it stays as written (a legacy or core surface); a biome binding
## becomes the palette `biome` field; default_biome becomes the runtime id of the first season
## of that biome among `compiled` (the compiled palette biomes), or is left out when it did not
## compile.
static func to_runtime(
	library_id: String, flat: Dictionary, own_surfaces: Array, compiled: Array
) -> Dictionary:
	var out := {}
	for key: String in flat:
		var name := String(flat[key])
		match String((TABLE[key] as Dictionary)["kind"]):
			"surface":
				out[key] = (
					LibraryIds.runtime_surface(library_id, name) if name in own_surfaces else name
				)
			"biome":
				out[key] = LibraryIds.biome_field(library_id, name)
			"biome_id":
				# A local biome id (the design) or a runtime id (what plantgen's first export
				# wrote): the first season of the biome, or the biome of that id.
				var field := LibraryIds.biome_field(library_id, name)
				for entry: Dictionary in compiled:
					if (
						String(entry.get("biome", "")) == field
						or String(entry.get("id", "")) == name
					):
						out[key] = String(entry["id"])
						break
	return out


static func _short(text: String) -> String:
	return text if text.length() <= 48 else text.substr(0, 45) + "..."
