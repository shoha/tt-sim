class_name AvatarPresets
extends RefCounted

## The preset avatars the Add Token browser offers under "Player avatars" until the avatar
## builder replaces them: recipes in the contract's form (docs/ASSET_PIPELINE.md section 10
## "Recipe") over the kit's parts, colour sets, face cells and stances. The first three are
## figurine's judging recipes (figurine/scripts/render_figures.py RECIPES); the rest use the
## stances those leave out. Colour picks index the kit's colour_sets (primary, secondary and
## accent index `cloth`).

const PARTS := {"body": "body_a", "head": "head_round", "hair": "hair_bun"}

const PRESETS: Array[Dictionary] = [
	{
		"name": "Plum",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours": {"skin": 1, "hair": 0, "eyes": 0, "primary": 0, "secondary": 1, "accent": 2},
			"face": {"eyes": 1, "brows": 1, "mouths": 0, "marks": 0},
			"proportions": {"height": 0.5, "build": 0.45, "head": 0.55},
			"stance": "stance_ready",
		},
	},
	{
		"name": "Marigold",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours": {"skin": 0, "hair": 2, "eyes": 1, "primary": 3, "secondary": 5, "accent": 4},
			"face": {"eyes": 3, "brows": 2, "mouths": 1, "marks": 1},
			"proportions": {"height": 0.15, "build": 0.3, "head": 0.85},
			"stance": "stance_relaxed",
		},
	},
	{
		"name": "Teal",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours":
			{"skin": 3, "hair": 3, "eyes": 2, "primary": 10, "secondary": 6, "accent": 0},
			"face": {"eyes": 4, "brows": 0, "mouths": 4, "marks": 2},
			"proportions": {"height": 0.9, "build": 0.75, "head": 0.3},
			"stance": "stance_heroic",
		},
	},
	{
		"name": "Ranger",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours":
			{"skin": 4, "hair": 6, "eyes": 4, "primary": 7, "secondary": 11, "accent": 8},
			"face": {"eyes": 0, "brows": 1, "mouths": 3, "marks": 0},
			"proportions": {"height": 0.7, "build": 0.55, "head": 0.45},
			"stance": "stance_sneaky",
		},
	},
	{
		"name": "Starling",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours": {"skin": 2, "hair": 7, "eyes": 6, "primary": 9, "secondary": 5, "accent": 3},
			"face": {"eyes": 5, "brows": 3, "mouths": 2, "marks": 4},
			"proportions": {"height": 0.6, "build": 0.35, "head": 0.6},
			"stance": "stance_casting",
		},
	},
	{
		"name": "Sunny",
		"recipe":
		{
			"format": 1,
			"parts": PARTS,
			"colours": {"skin": 2, "hair": 5, "eyes": 1, "primary": 2, "secondary": 0, "accent": 1},
			"face": {"eyes": 2, "brows": 0, "mouths": 1, "marks": 3},
			"proportions": {"height": 0.3, "build": 0.6, "head": 0.7},
			"stance": "stance_cheerful",
		},
	},
]


## Preset `index`'s recipe (a deep copy), with `stance` in place of its own when given.
static func recipe(index: int, stance: String = "") -> Dictionary:
	var out: Dictionary = (PRESETS[index].recipe as Dictionary).duplicate(true)
	if not stance.is_empty():
		out["stance"] = stance
	return out


## A stance id as a label: "stance_ready" -> "Ready".
static func stance_label(stance: String) -> String:
	return stance.trim_prefix("stance_").capitalize()
