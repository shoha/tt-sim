class_name DesignerSlots
extends RefCounted

## The slots of the designer's slot list (design doc 4.3): the closed roles grouped into the
## rows an author thinks in (canopy, understory, shrubs, grass...), each with its words. The
## list shows every group even when it holds no rule, so a gap (a forest with no ground cover) is
## visible. Pure data and lookups.

## [{id, label, roles (the first is what a new rule of the slot gets), hint}].
const GROUPS: Array[Dictionary] = [
	{
		"id": "canopy",
		"label": "Canopy",
		"roles": ["canopy_tree", "bank_tree", "snag", "palm"],
		"hint": "The tall trees that make the skyline.",
	},
	{
		"id": "understory",
		"label": "Understory",
		"roles": ["understory_tree"],
		"hint": "Young and small trees under the canopy.",
	},
	{
		"id": "shrubs",
		"label": "Shrubs",
		"roles": ["shrub", "cactus_tall"],
		"hint": "Bushes and tall succulents.",
	},
	{
		"id": "tall_grass",
		"label": "Tall grass",
		"roles": ["tall_grass", "emergent"],
		"hint": "Grass that stands knee high, and reeds.",
	},
	{
		"id": "grass",
		"label": "Grass",
		"roles": ["grass", "litter", "char_litter", "cactus_low"],
		"hint": "Short grass, leaf litter and low cover.",
	},
	{
		"id": "ferns",
		"label": "Ferns",
		"roles": ["fern"],
		"hint": "Ferns and rosettes, at home on a bank.",
	},
	{
		"id": "flowers",
		"label": "Flowers",
		"roles": ["flower", "carpet"],
		"hint": "Flowers and flowering carpets.",
	},
	{
		"id": "rocks",
		"label": "Rocks",
		"roles": ["boulder", "rock", "stone", "stones"],
		"hint": "Boulders, rocks and loose stones.",
	},
	{
		"id": "deadwood",
		"label": "Deadwood",
		"roles": ["log", "stump", "branches", "charred_deadwood"],
		"hint": "Logs, stumps and fallen branches.",
	},
	{
		"id": "props",
		"label": "Props",
		"roles": ["prop"],
		"hint": "Anything else a library offers: ruins, fences, tents.",
	},
]

## How the roles read in a dropdown.
const ROLE_LABELS := {
	"boulder": "Boulder",
	"bank_tree": "Bank tree",
	"branches": "Fallen branches",
	"canopy_tree": "Canopy tree",
	"cactus_low": "Low cactus",
	"cactus_tall": "Tall cactus",
	"carpet": "Flower carpet",
	"char_litter": "Burnt litter",
	"charred_deadwood": "Burnt deadwood",
	"emergent": "Reeds (in water)",
	"fern": "Fern",
	"flower": "Flower",
	"grass": "Grass",
	"litter": "Leaf litter",
	"log": "Log",
	"palm": "Palm",
	"prop": "Prop",
	"rock": "Rock",
	"shrub": "Shrub",
	"snag": "Snag",
	"stone": "Stone",
	"stones": "Stones",
	"stump": "Stump",
	"tall_grass": "Tall grass",
	"understory_tree": "Understory tree",
}

## The catalog category an asset used as a role usually has, for the picker's filter when a
## slot's "+" asks for an asset.
const ROLE_CATEGORY := {
	"boulder": "rock",
	"bank_tree": "tree",
	"branches": "deadwood",
	"canopy_tree": "tree",
	"cactus_low": "bush",
	"cactus_tall": "bush",
	"carpet": "flower",
	"char_litter": "ground_cover",
	"charred_deadwood": "deadwood",
	"emergent": "ground_cover",
	"fern": "ground_cover",
	"flower": "flower",
	"grass": "ground_cover",
	"litter": "ground_cover",
	"log": "deadwood",
	"palm": "tree",
	"prop": "prop",
	"rock": "rock",
	"shrub": "bush",
	"snag": "tree",
	"stone": "rock",
	"stones": "rock",
	"stump": "deadwood",
	"tall_grass": "ground_cover",
	"understory_tree": "tree",
}

## The role a new rule from an asset of a category and size class starts as ("" is any class).
const ROLE_BY_CATEGORY := {
	"tree":
	{
		"large": "canopy_tree",
		"medium": "understory_tree",
		"small": "understory_tree",
		"": "canopy_tree"
	},
	"bush": {"": "shrub"},
	"ground_cover": {"ground": "grass", "small": "fern", "medium": "fern", "": "grass"},
	"flower": {"": "flower"},
	"deadwood": {"": "log"},
	"rock": {"small": "rock", "medium": "boulder", "large": "boulder", "ground": "stones", "": "rock"},
	"prop": {"": "prop"},
	"structure": {"": "prop"},
	"other": {"": "prop"},
}

const CATEGORY_LABELS := {
	"tree": "Tree",
	"bush": "Bush",
	"ground_cover": "Ground cover",
	"flower": "Flower",
	"deadwood": "Deadwood",
	"rock": "Rock",
	"prop": "Prop",
	"structure": "Structure",
	"other": "Other",
}


## The role a new rule starts as for an asset of `category` and `size_class`.
static func role_for(category: String, size_class: String) -> String:
	var table: Dictionary = ROLE_BY_CATEGORY.get(category, {"": "prop"})
	return String(table.get(size_class, table.get("", "prop")))


## The group id that holds `role`.
static func group_of(role: String) -> String:
	for group in GROUPS:
		if role in group["roles"]:
			return String(group["id"])
	return "props"


## The group record with id `group_id`, {} when none.
static func group(group_id: String) -> Dictionary:
	for item in GROUPS:
		if item["id"] == group_id:
			return item
	return {}


## The words for `role`.
static func role_label(role: String) -> String:
	return String(ROLE_LABELS.get(role, role.capitalize()))


static func category_label(category: String) -> String:
	return String(CATEGORY_LABELS.get(category, category.capitalize()))
