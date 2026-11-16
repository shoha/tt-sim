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
## A bush, shrub, hedge or fern: a leaf mass painted in the crowns' hand (painter-trees-polish2):
## lobed domes over a rounded form with a broken outline, toned by the trees' crown ramp
## (CROWN_TONES). painter-trees-fix: the ferns joined; as a plain leaf mass each frond card kept a
## quarter of its own normal and read as splayed streaky shards with hard edges, grey-lilac in
## winter.
const KIND_CROWN := 4
## The script whose bush_ramp() tones a KIND_CROWN plant (loaded by path, as PainterSurfaces loads
## the painted trees, so a Classic start-up never compiles the trees' code).
const CROWN_TONES := "res://painter/trees/tree_tones.gd"
## The tone role of a dry biome's grass (PainterGroundRoles.DERIVED).
const DRY_GRASS_ROLE := "dry-grass"
## The tone role of a cactus and an agave (PainterGroundRoles.DERIVED).
const CACTUS_ROLE := "cactus"
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
	[KIND_CROWN, "leaf", ["bush", "shrub", "hedge", "fern", "bracken"]],
	[KIND_MASS, "leaf", ["ivy", "moss"]],
]
## Words of a tree-category asset that is a bush the plant shader paints, not a tree
## (painter-trees-polish: the core forest's bushes sway as trees, stayed Classic and read summer
## green in winter and black in grimdark).
const TREE_MASS_WORDS: Array[String] = ["bush", "shrub", "hedge"]


## {"kind", "role", "ground_cover"} for asset `asset_id` of wind category `wind_category`
## (WindFoliage: "tree", "grass" or "" for still) and the palette's `flower` flag, or {} when the
## Painted look leaves it Classic or the painted trees draw it (trees; a bush is a leaf mass).
## The words are read in the asset's own name, never its biome's (painter-trees-fix2: every
## "grassland_meadow_summer_s1/..." asset matched "grass", so a meadow's stones were painted as
## grass tufts).
static func of(asset_id: String, wind_category: String, flower: bool = false) -> Dictionary:
	var id := asset_id.get_file().to_lower()
	# The desert plants (painter-coverage): a cactus is a solid in a blue green, an agave a rosette
	# of the same, a dead shrub a mass of sticks; none is a green leaf crown.
	if id.contains("cactus"):
		return _entry(KIND_SOLID, CACTUS_ROLE)
	if id.contains("agave"):
		return _entry(KIND_MASS, CACTUS_ROLE)
	if id.contains("deadshrub"):
		return _entry(KIND_MASS, "bark")
	if wind_category == "tree":
		for word in TREE_MASS_WORDS:
			if id.contains(word):
				return _entry(KIND_CROWN, "leaf")
		# A tree the painter does not grow (acacia, palm, dead tree: species.json's table has no
		# row): its own surfaces painted by material, leaf or bark (for_surface).
		if PainterTreeSpecies.species_for(asset_id).is_empty():
			var entry := _entry(KIND_MASS, "leaf")
			entry["by_surface"] = true
			return entry
		return {}
	if flower:
		return _entry(KIND_FLOWER, "grass")
	for rule: Array in RULES:
		for word: String in rule[2]:
			if id.contains(word):
				var role := str(rule[1])
				if int(rule[0]) == KIND_GRASS and _dry_biome(asset_id):
					role = DRY_GRASS_ROLE
				return _entry(int(rule[0]), role)
	# Anything else that sways is a leaf mass; anything still is a stone.
	if wind_category != "":
		return _entry(KIND_MASS, "leaf")
	return _entry(KIND_SOLID, "stone")


## The entry for one surface of an asset `entry` (of()) names: a tree the painter does not grow
## carries `by_surface`, and its material says what the surface is, bark (a solid in the bark role)
## or leaf (a leaf mass); any other entry is returned as it is. `material` may be null.
static func for_surface(entry: Dictionary, material: Material) -> Dictionary:
	if not bool(entry.get("by_surface", false)):
		return entry
	var name := "" if material == null else material.resource_name.to_lower()
	if name.contains("bark"):
		return _entry(KIND_SOLID, "bark")
	return _entry(KIND_MASS, "leaf")


## True when the asset's biome folder (the part of `asset_id` before its file name) is a dry biome
## (the ground roles dry, earth or ash: savanna, rocky badlands, burnt forest), whose tufts are
## straw, not green.
static func _dry_biome(asset_id: String) -> bool:
	var folder := asset_id.get_base_dir()
	if folder.is_empty():
		return false
	var role := PainterGroundRoles.biome_role(folder.get_file())
	return role == "dry" or role == "earth" or role == "ash"


static func _entry(kind: int, role: String) -> Dictionary:
	return {
		"kind": kind,
		"role": role,
		"ground_cover": kind == KIND_GRASS or kind == KIND_FLOWER,
	}
