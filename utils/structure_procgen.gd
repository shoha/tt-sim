class_name StructureProcgen
extends RefCounted

## The one door from the game into procgen's structure generators that the start-up does not
## compile (perf audit boot, 2026-11-09).
##
## ProcgenStructureRegistry builds every structure node type (57 of them), so naming it compiles
## about 90 procgen scripts, and ProcgenRow and RowNode reach it; until this door the library
## serve, walls and streets named them and the start-up compiled all of it before the first frame.
## This file loads them by path on first use, behind typed functions, so its callers stay typed:
## - new_registry(): the real registry, for evaluating a structure graph (a build).
## - type_names(): a registry that only knows the type ids, for checking a recipe's node types
##   without building the nodes (the library serve reads every structure recipe at start-up).
## - row_plan(), row_lot_path(), new_row_node(): the street row recipe's lots.
## STRUCTURE_TYPE_IDS and ROW_PRESET_MODERN copy procgen's values; test_boot_graph.gd pins both,
## so a new node type or row preset fails a test until the copy follows.

const STRUCTURE_REGISTRY := "res://procgen/graph/structure_registry.gd"
const ROW_GEN := "res://procgen/gen/row_gen.gd"
const ROW_NODE := "res://procgen/nodes/row_node.gd"
const EVALUATOR := "res://procgen/graph/graph_evaluator.gd"
const SETTLEMENT := "res://procgen/gen/settlement.gd"
const PROPS := "res://procgen/gen/props.gd"
const ORNAMENTS := "res://procgen/gen/ornaments.gd"
const RECIPES_ORNAMENTS := "res://procgen/graph/recipes_ornaments.gd"
## ProcgenRow.PRESET_MODERN, the last street species.
const ROW_PRESET_MODERN := 11
## ProcgenStructureRegistry.new().type_ids(), in its order.
const STRUCTURE_TYPE_IDS: Array[String] = [
	"guide",
	"planks",
	"deck_collision",
	"stringers",
	"sills",
	"posts_rail",
	"piles",
	"stones",
	"arch_layout",
	"arch_body",
	"arch_parapets",
	"arch_deck",
	"ford_bar",
	"ford_stones",
	"stone_wall",
	"fence",
	"building",
	"building_layout",
	"building_walls",
	"building_timber",
	"facade",
	"facade_trim",
	"cornice",
	"quoins",
	"glazing",
	"roof_furniture",
	"roof_gable",
	"roof_hip",
	"roof_flat",
	"roof_round",
	"roof_profile",
	"stack",
	"beams",
	"framing",
	"gallery",
	"dormer",
	"stilts",
	"ornament",
	"round_corners",
	"parapet",
	"vigas",
	"roof_props",
	"street_row",
	"wonk",
	"ruin",
	"tower",
	"crenellations",
	"arch_heads",
	"courtyard_wing",
	"courtyard_yard",
	"roof_cap",
	"sails",
	"round_court",
	"tree_core",
	"taper",
	"prop",
	"output",
]


## A registry that knows the structure node types by id only (has_type, type_ids); get_type is
## null. Enough for LibraryStructures.recipe_problem, which checks a recipe before it is built.
class TypeNames:
	extends ProcgenRegistry

	func has_type(id: String) -> bool:
		return STRUCTURE_TYPE_IDS.has(id)

	func type_ids() -> Array[String]:
		return STRUCTURE_TYPE_IDS.duplicate()


## A new ProcgenStructureRegistry: every structure node type, for evaluating a structure graph.
static func new_registry() -> ProcgenRegistry:
	var script: Variant = load(STRUCTURE_REGISTRY)
	return script.new()


## The structure node types by id only (TypeNames), for checking recipes.
static func type_names() -> ProcgenRegistry:
	return TypeNames.new()


## ProcgenRow.plan(): the lots a street row lays along `guide` (each {"points", "height", "pitch",
## "ridge", "side", "index", ...}).
static func row_plan(guide: ProcgenGuide, rng: PlantRng, params: Dictionary) -> Array[Dictionary]:
	var row: Variant = load(ROW_GEN)
	return row.plan(guide, rng, params)


## ProcgenRow.lot_path(): a lot's provenance path, "left/lot3".
static func row_lot_path(lot: Dictionary) -> String:
	var row: Variant = load(ROW_GEN)
	return row.lot_path(lot)


## A new RowNode (the street row recipe's node), for its coerce_params and node_seed.
static func new_row_node() -> PlantNode:
	var script: Variant = load(ROW_NODE)
	return script.new()


## A new PlantGraphEvaluator over `registry`: it names every node type the recipe uses, so its
## script is loaded at the first build, not at start-up. Its evaluate_structure() and errors are
## called dynamically.
static func new_evaluator(registry: ProcgenRegistry) -> RefCounted:
	var script: Variant = load(EVALUATOR)
	return script.new(registry)


## The scripts of procgen's settlement, prop, ornament and building layout classes, for their
## constants and static functions (ProcgenSettlement.VARIANTS, ProcgenProps.NAMES,
## ProcgenOrnaments.anchors, ProcgenRecipesOrnaments.apply_to_document ...), loaded on first use.
static func settlement() -> Variant:
	return load(SETTLEMENT)


static func props() -> Variant:
	return load(PROPS)


static func ornaments() -> Variant:
	return load(ORNAMENTS)


static func recipes_ornaments() -> Variant:
	return load(RECIPES_ORNAMENTS)


## Whether `layout` is a ProcgenBuildingLayout (a building's final layout), told by its script.
static func is_building_layout(layout: Variant) -> bool:
	if not layout is Object:
		return false
	var script: Script = (layout as Object).get_script()
	return script != null and script.get_global_name() == &"ProcgenBuildingLayout"
