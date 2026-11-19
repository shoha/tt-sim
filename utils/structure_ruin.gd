class_name StructureRuin
extends RefCounted

## What a fire leaves of a building (card painter-structure-fire): its ruin, the same structure
## record with a ruin recipe in place of its own (core's `ruin_*` family: a ragged skyline, standing
## gables, rubble and moss) on the same footprint, so it is document state like any edit. It saves,
## undoes (the fire's one history entry holds it), and reaches every peer as the structures op the
## event's change makes (TerrainEvents._burn, StructureEditor.burn_down). Pure over the record and
## the served library; no scene tree.
##
## The ruin recipe is picked from what the building was: a round plan takes the tower, a barn the
## barn, a chapel or church the chapel, a townhouse or terrace the townhouse, anything else the
## cottage. The plan is brought inside the ruin's sizes (StructureEdit.refit); a plan the ruin
## cannot take (a polygon that is not a rectangle, outside the ruin's limits) has no ruin, and the
## fire removes the building instead (the charred ground it stood on is the ash surface's).

## The family and tag of the ruin recipes: a ruin does not burn again.
const FAMILY := "ruin"
## How far gone the ruin is (the recipe's `ruin` parameter, 0 to 1).
const AMOUNT := 0.85
const PARAM := "ruin"
const FALLBACK := "ruin_cottage"
## Words in a building's recipe id or tags -> the ruin recipe id it takes, first match wins.
const BY_WORD: Array[Array] = [
	["barn", "ruin_barn"],
	["chapel", "ruin_chapel"],
	["church", "ruin_chapel"],
	["temple", "ruin_chapel"],
	["townhouse", "ruin_townhouse"],
	["terrace", "ruin_townhouse"],
	["canal", "ruin_townhouse"],
]
const ROUND_ID := "ruin_tower"
## Set on a ruin's structure node (AuthoredStructures._structure_node): true. (The painted look
## no longer chars a ruin's roof remnant by it, card painter-roofs-ivy: it is painted as its
## roof kind.)
const META := &"tt_ruin"


## Whether `structure` is a ruin already (family `ruin` or the tag): it is not burnable.
static func is_ruin(structure: Structure) -> bool:
	return is_ruin_recipe(structure.recipe)


## Whether the recipe id `recipe` is a ruin's (is_ruin's test; the node of a structure carries it as
## the `ruin` meta so the painter can char the roof pieces that stand over it).
static func is_ruin_recipe(recipe: String) -> bool:
	var row := LibraryStructureStore.structure(recipe)
	if row.is_empty():
		return recipe.get_slice(":", 1).begins_with("ruin_")
	return String(row.get("family", "")) == FAMILY or (row.get("tags", []) as Array).has(FAMILY)


## The ruin recipe id a building of recipe id `id`, tags `tags`, round or not, becomes. Pure.
static func ruin_id_for(id: String, tags: Array, is_round: bool) -> String:
	if is_round:
		return ROUND_ID
	var words: Array[String] = [id]
	for tag: Variant in tags:
		words.append(String(tag))
	for pair in BY_WORD:
		for word in words:
			if word.contains(String(pair[0])):
				return String(pair[1])
	return FALLBACK


## The ruin of `structure` (a new record: its id, seed, style and footprint kept, the recipe a
## ruin's, `ruin` raised to AMOUNT), for a document of `extent` metres at `scale` metres per map
## unit; null when no ruin fits (see the header) or the building is a ruin already.
static func ruin_of(structure: Structure, extent: Vector2, scale: float) -> Structure:
	if is_ruin(structure):
		return null
	var source := LibraryStructureStore.structure(structure.recipe)
	var library := structure.recipe.get_slice(":", 0)
	var id := ruin_id_for(
		structure.recipe.get_slice(":", 1),
		source.get("tags", []),
		not source.is_empty() and StructurePlacement.is_round(source)
	)
	var ref := "%s:%s" % [library, id]
	var row := LibraryStructureStore.structure(ref)
	var recipe := StructureRecipes.document(ref)
	if row.is_empty() or recipe == null:
		return null
	var ruin := structure.copy()
	ruin.recipe = ref
	ruin.footprint = StructureEdit.refit(
		structure.footprint, StructureBrush.scaled_row(row, scale)
	)
	var params := StructureEdit.kept_params(structure.params, recipe.interface)
	if not StructureEdit.param_spec(recipe.interface, PARAM).is_empty():
		params[PARAM] = Structure.round_param(AMOUNT)
	ruin.params = params
	if MapStructureIO.structure_problem(ruin, extent) != "":
		return null
	return ruin
