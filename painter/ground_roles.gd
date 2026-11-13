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

const ROLES: Array[String] = ["meadow", "floor", "path", "rock", "shore"]
## The sheet role each ground role paints with (index for index with ROLES).
const TONE_ROLE: Dictionary = {
	"meadow": "ground",
	"floor": "floor",
	"path": "path",
	"rock": "stone",
	"shore": "shore",
}
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
	["shore", ["badlands", "desert", "beach", "dunes"]],
	["meadow", ["meadow", "grassland", "savanna", "alpine", "wetland", "birch", "woodland"]],
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
