class_name StructureOrnaments
extends RefCounted

## The ornaments a player puts on a placed building (card ornaments_ui): ivy, a corner turret,
## buttresses, a rose window, a weathervane, a hanging sign, flower boxes, an awning, banners. They
## are procgen's nine ornament kinds (ProcgenOrnaments), added to the building's recipe document
## when it is built (ProcgenRecipesOrnaments.apply_to_document), so every peer that has the record
## builds the same dressed building.
##
## What is stored: two reserved entries of Structure.params, so a set of ornaments saves, undoes,
## copies and reaches every peer by exactly the paths a stepped parameter does (the map document,
## the "structures" live edit, the build key) and no new field exists:
##   `ornaments`   a bit mask, bit i for KIND_BITS[i], 0 (absent) for none;
##   `ivy_amount`  how much ivy, IVY_MIN..IVY_MAX, absent for IVY_DEFAULT.
## The names are not recipe interface entries (StructureRecipes.clamp_params drops them from the
## recipe's inputs); StructureEdit.kept_params keeps them across a restyle.
##
## Pure and safe on any thread: Dictionary in, Dictionary out, nothing shared.

const PARAM_MASK := "ornaments"
const PARAM_IVY := "ivy_amount"
const RESERVED: Array[String] = [PARAM_MASK, PARAM_IVY]
## The kinds in mask-bit order. Never reorder: a saved map stores the bits. A test pins this set to
## ProcgenOrnaments.KINDS.
const KIND_BITS: Array[String] = [
	"ivy", "bartizan", "buttress", "rose", "vane", "sign", "flower_boxes", "awning", "banner"
]
## The chips, in display order: the kind, its plain-word label and what it does.
const CHIPS: Array[Dictionary] = [
	{
		"kind": "ivy",
		"label": "Ivy",
		"tip": "Climbing ivy on the walls, from the ground up.",
	},
	{
		"kind": "bartizan",
		"label": "Corner turret",
		"tip": "A little turret hung on a corner of the building.",
	},
	{
		"kind": "buttress",
		"label": "Buttresses",
		"tip": "Stepped stone supports along the longest walls.",
	},
	{
		"kind": "rose",
		"label": "Rose window",
		"tip": "A round stained-glass window high on a gable end.",
	},
	{
		"kind": "vane",
		"label": "Weathervane",
		"tip": "A weathervane, or a finial, on the ridge of the roof.",
	},
	{
		"kind": "sign",
		"label": "Hanging sign",
		"tip": "A painted sign on a bracket beside the door.",
	},
	{
		"kind": "flower_boxes",
		"label": "Flower boxes",
		"tip": "Flower boxes under the front windows.",
	},
	{
		"kind": "awning",
		"label": "Awning",
		"tip": "A striped awning over the door.",
	},
	{
		"kind": "banner",
		"label": "Banners",
		"tip": "Pennants or banners on poles at the roof corners.",
	},
]
const IVY_MIN := 0.2
const IVY_MAX := 1.0
## procgen's own coverage for ivy (ProcgenOrnaments.NUMBERS.ivy.coverage).
const IVY_DEFAULT := 0.55
const IVY_STEP := 0.05
## How many a "Surprise me" picks, at least and at most.
const SURPRISE_MIN := 2
const SURPRISE_MAX := 3
## The painted parts' colours, a few jewel tones a building draws one from (sRGB hex): a sign, the
## first stripe of an awning, a banner. Which one is a pure function of the building's seed.
const PAINT: Array[String] = ["#B5443A", "#2F6FA3", "#D79B2E", "#3E8A5A", "#8C4F9E", "#D0663A"]
## The kinds a building of each theme is likely to wear (Surprise me), best first.
const THEMES: Dictionary = {
	"fort": ["bartizan", "banner", "buttress", "ivy", "vane"],
	"chapel": ["rose", "buttress", "vane", "ivy", "banner"],
	"shop": ["sign", "awning", "flower_boxes", "banner", "vane"],
	"home": ["ivy", "flower_boxes", "vane", "sign", "banner"],
}
## Words in a structure's name, family or tags that put it in a theme (first match wins).
const THEME_WORDS: Dictionary = {
	"fort": ["keep", "castle", "tower", "gate", "fort", "bastion"],
	"chapel": ["chapel", "church", "temple", "cathedral", "abbey", "shrine"],
	"shop": ["inn", "shop", "market", "cafe", "tavern", "store", "hall", "clinic"],
}
const RUIN_REASON := "A ruin has nothing left to hang it on."
const BUILT_IN_REASON := "Already part of this building's style."


## The mask of `params` (0 for none), clamped to the nine bits.
static func mask_of(params: Dictionary) -> int:
	var value: Variant = params.get(PARAM_MASK, 0)
	if value is bool or not (value is float or value is int):
		return 0
	return clampi(roundi(float(value)), 0, (1 << KIND_BITS.size()) - 1)


## The kinds `params` asks for, in KIND_BITS order.
static func kinds_of(params: Dictionary) -> Array[String]:
	var mask := mask_of(params)
	var out: Array[String] = []
	for bit in KIND_BITS.size():
		if mask & (1 << bit) != 0:
			out.append(KIND_BITS[bit])
	return out


## `params` asking for exactly `kinds` (unknown names dropped). An empty set removes both reserved
## entries; the ivy amount stays only while ivy is asked for. A new dictionary.
static func with_kinds(params: Dictionary, kinds: Array) -> Dictionary:
	var out := params.duplicate()
	var mask := 0
	for kind: Variant in kinds:
		var bit := KIND_BITS.find(String(kind))
		if bit >= 0:
			mask |= 1 << bit
	if mask == 0:
		out.erase(PARAM_MASK)
	else:
		out[PARAM_MASK] = float(mask)
	if mask & 1 == 0:
		out.erase(PARAM_IVY)
	return out


## `params` with `kind` switched on or off. A new dictionary.
static func with_kind(params: Dictionary, kind: String, on: bool) -> Dictionary:
	var kinds := kinds_of(params)
	if on and not kinds.has(kind):
		kinds.append(kind)
	elif not on:
		kinds.erase(kind)
	return with_kinds(params, kinds)


## The ivy amount of `params` (IVY_DEFAULT when unset), within IVY_MIN..IVY_MAX.
static func ivy_amount(params: Dictionary) -> float:
	var value: Variant = params.get(PARAM_IVY, IVY_DEFAULT)
	if value is bool or not (value is float or value is int):
		return IVY_DEFAULT
	return clampf(float(value), IVY_MIN, IVY_MAX)


## `params` with the ivy amount set (snapped to IVY_STEP; the default is stored as nothing). A new
## dictionary; ivy that is not asked for leaves it unchanged.
static func with_ivy_amount(params: Dictionary, amount: float) -> Dictionary:
	var out := params.duplicate()
	if not kinds_of(params).has("ivy"):
		return out
	var snapped_amount := Structure.round_param(
		clampf(snappedf(amount, IVY_STEP), IVY_MIN, IVY_MAX)
	)
	if is_equal_approx(snapped_amount, IVY_DEFAULT):
		out.erase(PARAM_IVY)
	else:
		out[PARAM_IVY] = snapped_amount
	return out


## `params` without the ornaments entries.
static func without(params: Dictionary) -> Dictionary:
	var out := params.duplicate()
	for key in RESERVED:
		out.erase(key)
	return out


## The ornament entries `params` asks for, as ProcgenOrnaments entries: the ivy sized by its
## amount, and a painted part (sign, awning, banners) in a colour drawn from `seed_value`.
static func entries(params: Dictionary, seed_value: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for kind in kinds_of(params):
		var entry := {"kind": kind}
		match kind:
			"ivy":
				var amount := ivy_amount(params)
				entry["coverage"] = amount
				entry["height"] = clampf(0.25 + 0.82 * amount, 0.25, 1.0)
			"sign", "awning", "banner":
				entry["color"] = paint_of(seed_value, kind)
		out.append(entry)
	return out


## The colour (hex) a painted ornament of `kind` wears on the building of `seed_value`: stable
## across peers (a plain hash of two integers, not the engine's).
static func paint_of(seed_value: int, kind: String) -> String:
	var h := (seed_value * 73856093) ^ (KIND_BITS.find(kind) * 19349663)
	return PAINT[posmod(h, PAINT.size())]


## Adds the ornaments `params` asks for to `recipe` (the building's recipe document); how many
## nodes were added. Nothing when `recipe` cannot take them (problem_for) or none are asked for.
static func apply(recipe: PlantGraphDocument, params: Dictionary, seed_value: int) -> int:
	var asked := entries(params, seed_value)
	if recipe == null or asked.is_empty() or problem_for(recipe, params) != "":
		return 0
	return ProcgenRecipesOrnaments.apply_to_document(recipe, asked)


## Why `recipe` with `params` cannot take ornaments ("" when it can): a ruin (the recipe's own, or
## the Ruin stepper above nothing), a courtyard, a recipe with no walls.
static func problem_for(recipe: PlantGraphDocument, params: Dictionary) -> String:
	var why := ProcgenRecipesOrnaments.problem_of(recipe)
	if why != "":
		return why
	var spec := StructureEdit.param_spec(recipe.interface, "ruin")
	if not spec.is_empty() and StructureEdit.param_value(params, recipe.interface, "ruin") > 0.001:
		return RUIN_REASON
	return ""


## The kinds `recipe` already draws itself (its style's own ornaments); a chip for one shows on and
## cannot be taken off.
static func built_in(recipe: PlantGraphDocument) -> Array[String]:
	return ProcgenRecipesOrnaments.kinds_in(recipe) if recipe != null else ([] as Array[String])


## The state of every chip for the building `recipe` + `params`: kind -> {"on", "enabled",
## "reason"}. A built-in kind is on and disabled; every kind is disabled with the reason when the
## building cannot take ornaments at all.
static func chip_states(recipe: PlantGraphDocument, params: Dictionary) -> Dictionary:
	var why := problem_for(recipe, params)
	var own := built_in(recipe)
	var asked := kinds_of(params)
	var out := {}
	for kind in KIND_BITS:
		if why != "":
			out[kind] = {"on": false, "enabled": false, "reason": why}
		elif own.has(kind):
			out[kind] = {"on": true, "enabled": false, "reason": BUILT_IN_REASON}
		else:
			out[kind] = {"on": asked.has(kind), "enabled": true, "reason": ""}
	return out


## The theme of a structure row (name, family, tags): "fort", "chapel", "shop" or "home".
static func theme_of(row: Dictionary) -> String:
	var words := PackedStringArray([String(row.get("name", "")), String(row.get("family", ""))])
	for tag: Variant in row.get("tags", []):
		words.append(String(tag))
	var text := " ".join(words).to_lower()
	for theme: String in ["fort", "chapel", "shop"]:
		for word: String in THEME_WORDS[theme]:
			if word in text:
				return theme
	return "home"


## A pleasing set for a building of `theme`: SURPRISE_MIN..SURPRISE_MAX kinds drawn from the
## theme's list (the earlier ones likelier), none of `skip` (kinds that cannot be added), the same
## for the same `draw` number. At most one of the two roof-top kinds, so a roof is not crowded.
static func surprise(theme: String, draw: int, skip: Array = []) -> Array[String]:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([theme, draw])
	var pool: Array[String] = []
	for kind: String in THEMES.get(theme, THEMES["home"]):
		if not skip.has(kind):
			pool.append(kind)
	var want := mini(rng.randi_range(SURPRISE_MIN, SURPRISE_MAX), pool.size())
	var out: Array[String] = []
	var roof_tops := 0
	while out.size() < want and not pool.is_empty():
		# Rank-weighted: the first of the pool has weight n, the last 1.
		var total := pool.size() * (pool.size() + 1) / 2
		var roll := rng.randi_range(1, total)
		var at := 0
		var acc := pool.size()
		while roll > acc and at < pool.size() - 1:
			at += 1
			acc += pool.size() - at
		var kind := pool[at]
		pool.remove_at(at)
		if kind == "vane" or kind == "banner":
			if roof_tops >= 1:
				continue
			roof_tops += 1
		out.append(kind)
	# In mask order, the one order a set is compared and stored in.
	return kinds_of(with_kinds({}, out))
