class_name DesignerLookFields
extends RefCounted

## The fields of the ground look the designer's editor offers (step S9), grouped as the contract
## groups them (GroundLook.BASE is the full table; docs/ASSET_PIPELINE.md section 9 says what each
## does). The editor builds its rows from this table: a field has a `kind` (`number`, `triple`,
## three numbers, `color`, a linear RGB colour, or `colors`, the zone colours), the slider's `low`,
## `high` and `step` (always inside GroundLook.RANGES), a `unit` and a `tip`. Fields the editor
## leaves out (the zone angles and nesting layers, the rim's surface list) stay as the library has
## them. Pure data.

const GROUPS: Array[Dictionary] = [
	{
		"id": "zones",
		"label": "Colour zones",
		"tip": "Patches of different ground colour, in four colours.",
		"fields":
		[
			{
				"key": "colors_linear",
				"label": "Zone colours",
				"kind": "colors",
				"tip": "Three or four colours the ground is split into.",
			},
			{
				"key": "strength",
				"label": "Strength",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How strongly the zones colour the ground.",
			},
			{
				"key": "cover",
				"label": "Cover",
				"kind": "triple",
				"labels": ["zone 1", "zone 2", "zone 3"],
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much of the ground each of the first three zones takes.",
			},
			{
				"key": "scale_m",
				"label": "Patch size",
				"kind": "triple",
				"labels": ["zone 1", "zone 2", "zone 3"],
				"low": 0.5,
				"high": 40.0,
				"step": 0.5,
				"unit": "m",
				"tip": "The size of the patches of each zone.",
			},
			{
				"key": "edge",
				"label": "Edge softness",
				"kind": "triple",
				"labels": ["zone 1", "zone 2", "zone 3"],
				"low": 0.005,
				"high": 0.2,
				"step": 0.005,
				"tip": "How sharp the edge of each zone is.",
			},
			{
				"key": "stretch",
				"label": "Stretch",
				"kind": "number",
				"low": 1.0,
				"high": 4.0,
				"step": 0.05,
				"tip": "How much the patches are drawn out in one direction.",
			},
			{
				"key": "warp",
				"label": "Warp",
				"kind": "number",
				"low": 0.0,
				"high": 2.0,
				"step": 0.05,
				"tip": "How much the patch outlines wander.",
			},
			{
				"key": "rag",
				"label": "Ragged edge",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How broken the zone edges are.",
			},
			{
				"key": "rag_m",
				"label": "Ragged size",
				"kind": "number",
				"low": 0.2,
				"high": 8.0,
				"step": 0.1,
				"unit": "m",
				"tip": "The size of the breaks in the edges.",
			},
			{
				"key": "nest",
				"label": "Nesting",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much a zone sits inside another.",
			},
		],
	},
	{
		"id": "light",
		"label": "Painted light",
		"tip": "Lit and shaded patches painted on the ground.",
		"fields":
		[
			{
				"key": "strength",
				"label": "Strength",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much painted light there is.",
			},
			{
				"key": "key",
				"label": "Key",
				"kind": "number",
				"low": 0.1,
				"high": 3.0,
				"step": 0.05,
				"tip": "The brightness of the lit patches.",
			},
			{
				"key": "cover",
				"label": "Lit cover",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "The share of the ground that is lit.",
			},
			{
				"key": "lift",
				"label": "Lift",
				"kind": "number",
				"low": 0.0,
				"high": 1.5,
				"step": 0.01,
				"tip": "How far the lit patches lift above the colour.",
			},
			{
				"key": "shade",
				"label": "Shade",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How dark the shaded patches are.",
			},
			{
				"key": "lit_tint",
				"label": "Lit tint",
				"kind": "triple",
				"labels": ["red", "green", "blue"],
				"low": 0.5,
				"high": 1.5,
				"step": 0.01,
				"tip": "The colour the lit patches lean to (1 is none).",
			},
			{
				"key": "shade_tint",
				"label": "Shade tint",
				"kind": "triple",
				"labels": ["red", "green", "blue"],
				"low": 0.5,
				"high": 1.5,
				"step": 0.01,
				"tip": "The colour the shaded patches lean to (1 is none).",
			},
			{
				"key": "streak",
				"label": "Streaks",
				"kind": "number",
				"low": 0.0,
				"high": 0.5,
				"step": 0.005,
				"tip": "Long streaks of light along the ground.",
			},
			{
				"key": "scale_m",
				"label": "Patch size",
				"kind": "number",
				"low": 0.5,
				"high": 30.0,
				"step": 0.5,
				"unit": "m",
				"tip": "The size of the painted light's patches.",
			},
		],
	},
	{
		"id": "brush",
		"label": "Brush",
		"tip": "The painted brush texture over the ground.",
		"fields":
		[
			{
				"key": "contrast",
				"label": "Contrast",
				"kind": "number",
				"low": 0.0,
				"high": 2.0,
				"step": 0.02,
				"tip": "How much the strokes differ in value.",
			},
			{
				"key": "hue",
				"label": "Hue shift",
				"kind": "number",
				"low": 0.0,
				"high": 0.5,
				"step": 0.005,
				"tip": "How much the strokes differ in hue.",
			},
			{
				"key": "mean",
				"label": "Mean",
				"kind": "number",
				"low": 0.0,
				"high": 8.0,
				"step": 0.1,
				"tip": "The brightness the brush texture is measured against.",
			},
		],
	},
	{
		"id": "strokes",
		"label": "Strokes",
		"tip": "The size and length of the brush strokes.",
		"fields":
		[
			{
				"key": "on",
				"label": "Strokes",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much of the ground is drawn in strokes.",
			},
			{
				"key": "m",
				"label": "Stroke size",
				"kind": "number",
				"low": 0.3,
				"high": 6.0,
				"step": 0.1,
				"unit": "m",
				"tip": "The width of a stroke.",
			},
			{
				"key": "len",
				"label": "Stroke length",
				"kind": "number",
				"low": 1.0,
				"high": 10.0,
				"step": 0.1,
				"tip": "How many times longer than wide a stroke is.",
			},
		],
	},
	{
		"id": "tuft",
		"label": "Grass tufts",
		"tip": "How the grass tufts take the colour of the ground under them.",
		"fields":
		[
			{
				"key": "strength",
				"label": "Strength",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much the tufts take the ground's zone colour.",
			},
			{
				"key": "contrast",
				"label": "Contrast",
				"kind": "number",
				"low": 0.0,
				"high": 2.0,
				"step": 0.02,
				"tip": "How much the tufts differ in value.",
			},
			{
				"key": "hue",
				"label": "Hue shift",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much the tufts differ in hue.",
			},
		],
	},
	{
		"id": "mass",
		"label": "Grass masses",
		"tip": "The shade and light stamped under big masses of grass.",
		"fields":
		[
			{
				"key": "step",
				"label": "Step",
				"kind": "number",
				"low": 1.0,
				"high": 2.5,
				"step": 0.01,
				"tip": "The jump in value between a mass and the ground.",
			},
			{
				"key": "sat",
				"label": "Saturation",
				"kind": "number",
				"low": 0.5,
				"high": 2.0,
				"step": 0.01,
				"tip": "How saturated the masses are.",
			},
			{
				"key": "lit",
				"label": "Lit side",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much the sunward side of a mass is lit.",
			},
			{
				"key": "shade",
				"label": "Shade",
				"kind": "number",
				"low": 0.0,
				"high": 0.9,
				"step": 0.01,
				"tip": "How dark the ground is under a mass.",
			},
			{
				"key": "lift",
				"label": "Lift",
				"kind": "number",
				"low": 0.0,
				"high": 0.2,
				"step": 0.005,
				"tip": "How much light is lifted round a mass.",
			},
		],
	},
	{
		"id": "rim",
		"label": "Rims",
		"tip": "The rim where an accent patch or a path meets the ground.",
		"fields":
		[
			{
				"key": "strength",
				"label": "Strength",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How strong the rims are.",
			},
			{
				"key": "color_linear",
				"label": "Rim colour",
				"kind": "color",
				"tip": "The colour of the rims.",
			},
			{
				"key": "accent_rim_m",
				"label": "Accent rim",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"unit": "m",
				"tip": "The width of the rim round an accent patch.",
			},
			{
				"key": "path_rim_m",
				"label": "Path rim",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"unit": "m",
				"tip": "The width of the rim along a path.",
			},
			{
				"key": "wobble",
				"label": "Wobble",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much the rim wanders.",
			},
			{
				"key": "gap",
				"label": "Gaps",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How much of the rim is broken.",
			},
		],
	},
	{
		"id": "accent_shape",
		"label": "Accent patches",
		"tip": "The shape of the accent patches of the ground strip.",
		"fields":
		[
			{
				"key": "stretch",
				"label": "Stretch",
				"kind": "number",
				"low": 1.0,
				"high": 4.0,
				"step": 0.05,
				"tip": "How drawn out the patches are.",
			},
			{
				"key": "break",
				"label": "Break",
				"kind": "number",
				"low": 0.0,
				"high": 1.0,
				"step": 0.01,
				"tip": "How broken up the patches are.",
			},
		],
	},
]


## The spec of (`group`, `key`), {} when the editor does not offer it.
static func spec(group: String, key: String) -> Dictionary:
	for entry in GROUPS:
		if entry["id"] == group:
			for field: Dictionary in entry["fields"]:
				if field["key"] == key:
					return field
	return {}


## Every (group, key) the editor offers, as "group.key".
static func names() -> Array[String]:
	var out: Array[String] = []
	for entry in GROUPS:
		for field: Dictionary in entry["fields"]:
			out.append("%s.%s" % [entry["id"], field["key"]])
	return out
