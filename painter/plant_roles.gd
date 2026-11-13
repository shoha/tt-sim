class_name PainterPlantRoles
extends RefCounted

## How the painted look draws each scatter asset tt-sim builds from a GLB (docs/systems/painter.md
## "Surfaces"): a selector KIND (painter_selector.gdshaderinc) and the sheet role whose ramp it
## paints in, or nothing for an asset the Painted look leaves Classic. Pure functions.
##
## The model (the painter spike's rules): the asset's name words say what it is; the palette's
## flower flag and wind category break ties. Trees stay Classic until the painter grows them
## (card A2). Grass and flowers are ground cover: thinned in groups (the sheet's keep-*) and
## casting no shadow of their own. Like the ground's roles this reads names, a first pass: the
## real data is a catalog category per asset (the plan's "by catalog category").

const KIND_MASS := 0
const KIND_GRASS := 1
const KIND_SOLID := 2
const KIND_FLOWER := 3
## [kind, sheet role, words], first match wins (substrings of the asset id, lower case).
const RULES: Array = [
	[
		KIND_FLOWER,
		"grass",
		[
			"flower",
			"daisy",
			"poppy",
			"clover",
			"bloom",
			"lupin",
			"bell",
			"buttercup",
			"dandelion",
			"foxglove",
			"thistle",
			"heather",
		]
	],
	[KIND_SOLID, "litter", ["litter", "leaves", "needles"]],
	[KIND_GRASS, "grass", ["grass", "sedge", "reed", "tuft", "wheat", "rush", "cattail"]],
	[KIND_SOLID, "stone", ["rock", "stone", "boulder", "pebble", "scree", "cliff"]],
	[
		KIND_SOLID,
		"bark",
		["log", "stump", "branch", "deadwood", "stick", "twig", "mushroom", "root", "snag"]
	],
	[KIND_MASS, "leaf", ["fern", "bracken", "ivy", "moss", "bush", "shrub", "hedge"]],
]


## {"kind", "role", "ground_cover"} for asset `asset_id` of wind category `wind_category`
## (WindFoliage: "tree", "grass" or "" for still) and the palette's `flower` flag, or {} when the
## Painted look leaves it Classic (trees).
static func of(asset_id: String, wind_category: String, flower: bool = false) -> Dictionary:
	if wind_category == "tree":
		return {}
	if flower:
		return _entry(KIND_FLOWER, "grass")
	var id := asset_id.to_lower()
	for rule: Array in RULES:
		for word: String in rule[2]:
			if id.contains(word):
				return _entry(int(rule[0]), str(rule[1]))
	# Anything else that sways is a leaf mass; anything still is a stone.
	if wind_category != "":
		return _entry(KIND_MASS, "leaf")
	return _entry(KIND_SOLID, "stone")


static func _entry(kind: int, role: String) -> Dictionary:
	return {
		"kind": kind,
		"role": role,
		"ground_cover": kind == KIND_GRASS or kind == KIND_FLOWER,
	}
