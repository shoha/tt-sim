class_name LibraryContracts
extends RefCounted

## The closed vocabulary of the content library format (contract 1): roles, size classes, class
## defaults, habit flags, the caps and the key tables the reader checks files against. tt-sim
## owns this contract the way it owns palette.json (docs/ASSET_PIPELINE.md section 9): plantgen
## and any other producer follow the contract.json that export_json writes, so a producer and the
## reader can never disagree about a role or a cap. Tables are append-only across contract
## versions. Pure data and pure functions: no files, no scene tree. Map and model:
## docs/systems/library.md.

const CONTRACT_VERSION := 1
const FORMAT_CONTRACT := "ttsim-contract"
const FORMAT_LIBRARY := "ttsim-library"
const FORMAT_CATALOG := "ttsim-catalog"
const FORMAT_BIOME := "ttsim-biome"
const FORMAT_LOCK := "ttsim-biome-lock"
## The only format version of each library file this build reads; a higher one is refused.
const FORMAT_VERSION := 1

const SIZE_CLASSES: Array[String] = ["large", "medium", "small", "ground"]
const WIND_CATEGORIES: Array[String] = ["tree", "grass", ""]
const CATEGORIES: Array[String] = [
	"tree", "bush", "ground_cover", "flower", "deadwood", "rock", "prop", "structure", "other"
]
const ALIGNS: Array[String] = ["upright", "normal"]
## habit.water values: "" none, a bank plant, an emergent (in the water), an arid plant.
const HABIT_WATER: Array[String] = ["", "bank", "emergent", "arid"]
const EXTENSIONS: Array[String] = [".json", ".glb", ".png", ".jpg", ".txt", ".md"]
## Library ids tt-sim keeps for itself; `core` is the official library and is allowed.
const RESERVED_LIBRARY_IDS: Array[String] = ["legacy", "draft", "dev"]
## The one library whose runtime ids carry no prefix, so every saved map keeps opening.
const CORE_ID := "core"

## role -> {kind (the palette rule kind), size_class (the default class)}. The roles replace
## the key lists of the scatter code (design doc 2.6.2); a library cannot add one.
const ROLES := {
	"boulder": {"kind": "rock", "size_class": "medium"},
	"bank_tree": {"kind": "tree", "size_class": "large"},
	"branches": {"kind": "deadwood", "size_class": "small"},
	"canopy_tree": {"kind": "tree", "size_class": "large"},
	"cactus_low": {"kind": "cactus", "size_class": "small"},
	"cactus_tall": {"kind": "cactus", "size_class": "medium"},
	"carpet": {"kind": "flower", "size_class": "ground"},
	"char_litter": {"kind": "grass", "size_class": "ground"},
	"charred_deadwood": {"kind": "deadwood", "size_class": "small"},
	"emergent": {"kind": "grass", "size_class": "ground"},
	"fern": {"kind": "grass", "size_class": "small"},
	"flower": {"kind": "flower", "size_class": "ground"},
	"grass": {"kind": "grass", "size_class": "ground"},
	"litter": {"kind": "grass", "size_class": "ground"},
	"log": {"kind": "deadwood", "size_class": "small"},
	"palm": {"kind": "palm", "size_class": "large"},
	"prop": {"kind": "", "size_class": ""},
	"rock": {"kind": "rock", "size_class": "small"},
	"shrub": {"kind": "tree", "size_class": "medium"},
	"snag": {"kind": "tree", "size_class": "large"},
	"stone": {"kind": "rock", "size_class": "medium"},
	"stones": {"kind": "rock", "size_class": "small"},
	"stump": {"kind": "deadwood", "size_class": "small"},
	"tall_grass": {"kind": "grass", "size_class": "ground"},
	"understory_tree": {"kind": "tree", "size_class": "medium"},
}

## role -> the habit the role implies (the rule's own habit overrides key by key). Roles absent
## here have the neutral habit {water: "", charred: false}.
const HABIT_DEFAULTS := {
	"bank_tree": {"water": "bank"},
	"snag": {"charred": true},
	"fern": {"water": "bank"},
	"emergent": {"water": "emergent"},
	"char_litter": {"charred": true},
	"charred_deadwood": {"charred": true},
	"cactus_low": {"water": "arid"},
	"cactus_tall": {"water": "arid"},
}

## The class budget model's defaults per size class (treecube geoscatter.py CLASS_RULES).
const CLASS_DEFAULTS := {
	"ground":
	{
		"density_per_m2": 8.0,
		"scale_spread": 0.3,
		"slope_max_deg": 50.0,
		"spacing_m": 0.0,
		"yaw_random_deg": 360.0
	},
	"large":
	{
		"density_per_m2": 0.02,
		"scale_spread": 0.15,
		"slope_max_deg": 35.0,
		"spacing_m": 4.5,
		"yaw_random_deg": 360.0
	},
	"medium":
	{
		"density_per_m2": 0.06,
		"scale_spread": 0.2,
		"slope_max_deg": 40.0,
		"spacing_m": 2.0,
		"yaw_random_deg": 360.0
	},
	"small":
	{
		"density_per_m2": 0.15,
		"scale_spread": 0.3,
		"slope_max_deg": 55.0,
		"spacing_m": 0.8,
		"yaw_random_deg": 360.0
	},
}

## The axes of a rule's `response` curves (step S12) and the range of each axis' x values:
## slope in degrees, height in world metres (the ground's y), wet the shore weight 0..1 (the
## stored wet dressing, which reaches 2.4 m from the waterline) and water_dist metres to the
## nearest water (S12c: 0 on water, capped at 64 m, ScatterTerrain.water_distance_grid). A curve is
## RESPONSE_MIN_POINTS to RESPONSE_MAX_POINTS [x, y] points, x strictly ascending, y 0..1,
## piecewise linear and flat beyond its ends; axes multiply and only ever lower a rule's density.
const RESPONSE_AXES := {
	"slope": [0.0, 90.0],
	"height": [-500.0, 5000.0],
	"wet": [0.0, 1.0],
	"water_dist": [0.0, 64.0],
}
## Axes the contract names that this build's scatter does not evaluate (they warn and act as 1):
## none since S12c. Kept so a future axis can be named before its engine half lands.
const RESPONSE_UNSUPPORTED: Array[String] = []
const RESPONSE_MIN_POINTS := 2
const RESPONSE_MAX_POINTS := 8

## Hard caps, in bytes or counts, checked before anything is kept.
const CAPS := {
	"assets": 8192,
	"assets_per_rule": 64,
	"biome_bytes": 1048576,
	"biomes": 64,
	"catalog_bytes": 4194304,
	"glb_bytes": 67108864,
	"library_json_bytes": 1048576,
	"rules_per_biome": 128,
}
## Text and name limits of the reader (not part of contract.json).
const MAX_TEXT_LENGTH := 128
const MAX_DESCRIPTION_LENGTH := 1024
const MAX_RELATIVE_PATH := 120
const MAX_LOCAL_ID := 64
const MAX_BIOME_NAME := 48
const MAX_LIBRARY_ID := 32
const MAX_DEPENDENCIES := 8
const MAX_DEPENDENCY_DEPTH := 4
## Libraries served at once (the registry refuses more), and the texture side a GLB may embed.
const MAX_ACTIVE_LIBRARIES := 16
const MAX_GLB_TEXTURE_PX := 4096
const MAX_GLB_IMAGES := 64
const MAX_SEASONS := 8

## Keys each library file may carry; any other key is reported as a warning (the palette
## validator drops unknown keys silently, so this is the only place a typo is caught).
const LIBRARY_KEYS: Array[String] = [
	"format",
	"format_version",
	"id",
	"name",
	"description",
	"version",
	"contract",
	"requires",
	"author",
	"license",
	"url",
	"thumbnail",
	"dependencies",
	"default_biome",
	"bindings",
	"aliases",
	"retired",
	"tags",
	"stats",
	"partial",
]
const CATALOG_KEYS: Array[String] = ["format", "format_version", "assets"]
const CATALOG_ENTRY_KEYS: Array[String] = [
	"id",
	"group",
	"name",
	"category",
	"subtype",
	"tags",
	"biomes",
	"roles",
	"seasons",
	"game_kind",
	"wind_category",
	"size_class",
	"dimensions_m",
	"triangles",
	"lods",
	"file",
	"node",
	"thumb",
	"sidecar",
	"bytes",
	"sha256",
	"package_stem",
]
const BIOME_KEYS: Array[String] = [
	"format",
	"format_version",
	"id",
	"name",
	"description",
	"tags",
	"climate",
	"thumbnail",
	"seasons",
	"ground",
	"ground_look",
	"water",
	"density_scale",
	"rules",
	"surfaces",
	"legacy",
]
const GROUND_KEYS: Array[String] = [
	"surface", "cliff", "scree", "water_bed", "shore", "accents", "paths"
]
const RULE_KEYS: Array[String] = [
	"key",
	"role",
	"size_class",
	"weight",
	"density_per_m2",
	"density_factor",
	"spacing_m",
	"slope_max_deg",
	"slope_min_deg",
	"response",
	"scale_spread",
	"scale_floor",
	"yaw_random_deg",
	"align",
	"pattern",
	"clump",
	"near",
	"avoid",
	"avoid_bare",
	"keep_colour",
	"habit",
	"seasons",
	"query",
]
const QUERY_KEYS: Array[String] = [
	"match", "tags_all", "tags_any", "tags_none", "size_class", "seasons", "count", "order", "pin"
]
## The keys of one `query.match` clause: `ref` names one asset (or a whole group) explicitly; the
## others are AND-ed filters over the catalog (LibraryQuery, design doc 2.6.3).
const QUERY_CLAUSE_KEYS: Array[String] = [
	"ref", "category", "subtype", "group", "ids", "role", "library"
]
## query.order: groups by FNV-1a hash of "<biome id>/<rule key>|<group>", by group id, or as
## the clause's `ids` list names them.
const QUERY_ORDERS: Array[String] = ["hash", "id", "explicit"]
## query.seasons: "auto" keeps assets whose `seasons` is empty or lists the season being
## compiled; "any" keeps all.
const QUERY_SEASON_MODES: Array[String] = ["auto", "any"]
## Assets a query's selection may expand to (variants of the taken groups), and the most tags,
## ids and pins a query may list.
const QUERY_MAX_ASSETS := 64
const QUERY_MAX_LIST := 64
## Names Windows reserves as devices; a file or id with one cannot exist on every platform.
const RESERVED_DEVICE_NAMES: Array[String] = [
	"con",
	"prn",
	"aux",
	"nul",
	"com1",
	"com2",
	"com3",
	"com4",
	"com5",
	"com6",
	"com7",
	"com8",
	"com9",
	"lpt1",
	"lpt2",
	"lpt3",
	"lpt4",
	"lpt5",
	"lpt6",
	"lpt7",
	"lpt8",
	"lpt9",
]


## The role's record {kind, size_class}, or {} for an unknown role.
static func role(role_id: String) -> Dictionary:
	return (ROLES.get(role_id, {}) as Dictionary).duplicate()


static func has_role(role_id: String) -> bool:
	return ROLES.has(role_id)


## The palette rule kind a role compiles to ("" for an unknown role and for `prop`).
static func kind_of(role_id: String) -> String:
	return String((ROLES.get(role_id, {}) as Dictionary).get("kind", ""))


## The default size class of a role ("" for an unknown role and for `prop`).
static func size_class_of(role_id: String) -> String:
	return String((ROLES.get(role_id, {}) as Dictionary).get("size_class", ""))


## The class budget defaults of one size class, {} for an unknown class.
static func class_defaults(size_class: String) -> Dictionary:
	return (CLASS_DEFAULTS.get(size_class, {}) as Dictionary).duplicate()


## The role's habit flags with `overrides` laid over them: {water: String, charred: bool}.
static func habit_for(role_id: String, overrides: Variant = null) -> Dictionary:
	var habit := {"water": "", "charred": false}
	habit.merge((HABIT_DEFAULTS.get(role_id, {}) as Dictionary).duplicate(), true)
	if overrides is Dictionary:
		for flag: String in ["water", "charred"]:
			if (overrides as Dictionary).has(flag):
				habit[flag] = (overrides as Dictionary)[flag]
	return habit


## The default align of a role: rocks lie on the slope, the rest stand upright.
static func align_of(role_id: String) -> String:
	return "normal" if kind_of(role_id) == "rock" else "upright"


## Why `points` is not a valid curve on `axis` (RESPONSE_AXES), or "" when it is: a list of
## RESPONSE_MIN_POINTS to RESPONSE_MAX_POINTS [x, y] pairs of finite numbers, x inside the axis'
## range and strictly ascending, y from 0 to 1. The one rule the reader (an error) and the
## palette validator (a warning and a dropped axis) share.
static func response_problem(axis: String, points: Variant) -> String:
	if not RESPONSE_AXES.has(axis):
		return "unknown axis"
	if (
		not points is Array
		or (points as Array).size() < RESPONSE_MIN_POINTS
		or (points as Array).size() > RESPONSE_MAX_POINTS
	):
		return "needs %d to %d points" % [RESPONSE_MIN_POINTS, RESPONSE_MAX_POINTS]
	var range_x: Array = RESPONSE_AXES[axis]
	var last := -INF
	for point: Variant in points as Array:
		if not point is Array or (point as Array).size() != 2:
			return "a point is not an [x, y] pair"
		var pair: Array = point
		for part: Variant in pair:
			if part is bool or not (part is float or part is int) or is_nan(part) or is_inf(part):
				return "a point is not made of numbers"
		var x := float(pair[0])
		var y := float(pair[1])
		if x < float(range_x[0]) or x > float(range_x[1]):
			return "x must be from %s to %s" % [str(range_x[0]), str(range_x[1])]
		if x <= last:
			return "x must be strictly ascending"
		if y < 0.0 or y > 1.0:
			return "y must be from 0 to 1"
		last = x
	return ""


## The contract as the JSON plantgen vendors (packaging/contract.json): sorted keys, tab
## indent, a trailing newline.
static func export_json() -> String:
	var roles := {}
	for role_id: String in ROLES:
		roles[role_id] = (ROLES[role_id] as Dictionary).duplicate()
	var axes := {}
	for axis: String in RESPONSE_AXES:
		axes[axis] = (RESPONSE_AXES[axis] as Array).duplicate()
	var data := {
		"bindings": LibraryBindings.TABLE.duplicate(true),
		"caps": CAPS.duplicate(),
		"categories": CATEGORIES.duplicate(),
		"class_defaults": CLASS_DEFAULTS.duplicate(true),
		"contract": CONTRACT_VERSION,
		"extensions": EXTENSIONS.duplicate(),
		"format": FORMAT_CONTRACT,
		"habit_defaults": HABIT_DEFAULTS.duplicate(true),
		"habit_water": HABIT_WATER.duplicate(),
		"note":
		"Exported by tt-sim LibraryContracts.export_json (utils/library/library_contracts.gd).",
		"query":
		{
			"clause_keys": QUERY_CLAUSE_KEYS.duplicate(),
			"max_assets": QUERY_MAX_ASSETS,
			"orders": QUERY_ORDERS.duplicate(),
			"season_modes": QUERY_SEASON_MODES.duplicate(),
		},
		"response":
		{
			"axes": axes,
			"max_points": RESPONSE_MAX_POINTS,
			"min_points": RESPONSE_MIN_POINTS,
			"unsupported_axes": RESPONSE_UNSUPPORTED.duplicate(),
		},
		"roles": roles,
		"size_classes": SIZE_CLASSES.duplicate(),
		"surface_caps":
		{
			"expected_size": SurfaceBake.EXPECTED_SIZE,
			"info_keys": SurfaceBake.INFO_KEYS.duplicate(),
			"kinds": SurfaceBake.KINDS.duplicate(),
			"max_info_bytes": SurfaceBake.MAX_INFO_BYTES,
			"max_size": SurfaceBake.MAX_SIZE,
			"max_surfaces": SurfaceBake.MAX_SURFACES,
			"max_text": SurfaceBake.MAX_TEXT,
			"max_tile_m": SurfaceBake.MAX_TILE_M,
			"min_size": SurfaceBake.MIN_SIZE,
			"min_tile_m": SurfaceBake.MIN_TILE_M,
			"roles": SurfaceBake.ROLES.duplicate(),
		},
		"wind_categories": WIND_CATEGORIES.duplicate(),
	}
	return JSON.stringify(data, "\t", true) + "\n"
