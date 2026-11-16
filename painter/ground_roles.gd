class_name PainterGroundRoles
extends RefCounted

## The painted ground's roles: which of five tones a ground surface or a biome paints in (docs/
## systems/painter.md "Ground roles"). Pure functions, no scene tree.
##
## The model. The painted ground does not draw tt-sim's PBR surface sets; it draws one of ROLES,
## each a sheet role (TONE_ROLE) with its own tone ramp (PainterTones.ramp):
##   meadow  open grass, the default            -> sheet `ground`
##   floor   forest floor, litter, moss, ash    -> sheet `floor`
##   path    roads, tracks, paving, gravel      -> sheet `path`
##   rock    cliffs and scree                   -> sheet `stone`
##   shore   sand, mud, riverbeds               -> sheet `shore`
## A surface id's role comes from its WORDS (the id split at `_`): the first of SURFACE_RULES
## whose words include one of the id's wins, so `gravel_sandstone` is a path (gravel), never a
## shore (the word `sand` is not `sandstone`). A biome's role is the role of its own ground surface;
## since a map document names biomes by compiled id (`temperate_forest_summer_s1`), not by surface,
## BIOME_RULES read the id's words the same way, and the tests hold them to the surface each core
## biome-def names. Every core surface and biome resolves by a rule; an id no rule knows (a user
## library's) paints as DEFAULT_ROLE.
##
## This is the first pass the spike shortcut became. The real data is a role per surface in the
## library (a `paint_role` field beside a surface's PBR set, and a biome's taken from its ground
## surface), so an imported library's surfaces keep their meaning; then these tables go.

const ROLES: Array[String] = ["meadow", "floor", "path", "rock", "shore", "dry", "ash", "earth"]
## The sheet role each ground role paints with (index for index with ROLES). A role in DERIVED
## paints with its base role's tone moved by the sheet's numbers.
const TONE_ROLE: Dictionary = {
	"meadow": "ground",
	"floor": "floor",
	"path": "path",
	"rock": "stone",
	"shore": "shore",
	"dry": "ground",
	"ash": "stone",
	"earth": "path",
}
## The tones the painted look derives from a keyframed role instead of keying them (card
## painter-coverage): name -> [the sheet role it is derived from, the prefix of its three sheet
## numbers `<prefix>-hue` (degrees), `<prefix>-chroma` (a factor) and `<prefix>-lift`]. dry, ash
## and earth are ground roles (the savanna's straw, a burnt forest's ash, the badlands' baked
## earth, the third texel group of the zone map); dry-grass is the tufts of a dry biome
## (PainterPlantRoles).
const DERIVED: Dictionary = {
	"dry": ["ground", "dry"],
	"ash": ["stone", "ash"],
	"earth": ["path", "earth"],
	"dry-grass": ["grass", "drygrass"],
	"cactus": ["leaf", "cactus"],
}
## The zone map's second texture holds these (r dry, g ash, b earth): index in ROLES from here.
const BIOME_ROLES_FROM := 5
const DEFAULT_ROLE := "meadow"
## [role, words], first match wins (see the header).
const SURFACE_RULES: Array = [
	["rock", ["cliff", "scree", "rock", "boulder"]],
	["shore", ["sand", "mud", "riverbed", "shore", "beach"]],
	["floor", ["floor", "litter", "duff", "moss", "ash", "peat", "opening", "leaves"]],
	[
		"path",
		[
			"road",
			"path",
			"track",
			"dirt",
			"gravel",
			"cobblestone",
			"flagstone",
			"paving",
			"kerb",
			"plaza",
			"concrete",
			"asphalt",
			"planks",
			"tiles",
		]
	],
	["meadow", ["grass", "meadow", "glade", "lawn", "snow"]],
]
const BIOME_RULES: Array = [
	["ash", ["burnt"]],
	["earth", ["badlands", "desert"]],
	["dry", ["savanna"]],
	["shore", ["beach", "dunes"]],
	["meadow", ["meadow", "grassland", "alpine", "wetland", "birch", "woodland"]],
	["floor", ["forest", "taiga", "jungle"]],
]


## The ground role of surface `surface_id` (DEFAULT_ROLE when no rule knows it).
static func surface_role(surface_id: String) -> String:
	return _role(SURFACE_RULES, surface_id)


## The ground role of biome `biome_id` (a biome-def id or a compiled one; DEFAULT_ROLE when no
## rule knows it).
static func biome_role(biome_id: String) -> String:
	return _role(BIOME_RULES, biome_id)


## The index in SURFACE_RULES that resolves `surface_id`, or -1 when it falls to DEFAULT_ROLE.
static func surface_rule(surface_id: String) -> int:
	return _rule(SURFACE_RULES, surface_id)


## The index in BIOME_RULES that resolves `biome_id`, or -1 when it falls to DEFAULT_ROLE.
static func biome_rule(biome_id: String) -> int:
	return _rule(BIOME_RULES, biome_id)


## The middle tone (OKLCH) of derived role `role` (a key of DERIVED) in `mood` at `elevation`: its
## base role's tone with the hue turned to `<prefix>-hue`, the chroma times `<prefix>-chroma` and
## the lightness moved by `<prefix>-lift`. Pure.
static func derived(sheet: Dictionary, mood: String, role: String, elevation: float) -> Vector3:
	var spec: Array = DERIVED[role]
	var base := PainterSheet.tone_lch(sheet, mood, str(spec[0]), elevation)
	var p := str(spec[1])
	var num := func(suffix: String) -> float:
		return PainterSheet.number(sheet, mood, "%s-%s" % [p, suffix], elevation)
	return Vector3(
		clampf(base.x + float(num.call("lift")), 0.05, 0.98),
		base.y * float(num.call("chroma")),
		float(num.call("hue"))
	)


## The index of `role` in ROLES (the ground shader's role number), DEFAULT_ROLE's for an unknown.
static func index(role: String) -> int:
	var at := ROLES.find(role)
	return at if at >= 0 else ROLES.find(DEFAULT_ROLE)


static func _role(rules: Array, id: String) -> String:
	var at := _rule(rules, id)
	return DEFAULT_ROLE if at < 0 else str(rules[at][0])


static func _rule(rules: Array, id: String) -> int:
	var words := id.to_lower().split("_", false)
	for i in rules.size():
		for word: String in rules[i][1]:
			if words.has(word):
				return i
	return -1
