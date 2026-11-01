extends RefCounted

## The Beasts and Farm Animals roster (tools/roster/build_beasts.gd): which source file becomes
## which token and how tall it stands in metres. The sources are Quaternius's animals at an
## arbitrary modeller scale, and tt-sim applies no automatic token scale (docs/ASSET_PIPELINE.md
## section 7: 1 unit is 1 metre, a grid cell is 1.524 m), so the build bakes each real-world height
## (head to hoof, ears and horns included) into the GLB's root node. A horse and a pug are then
## different token sizes with no manifest field and no user step.

## id -> {fbx, name, height_m}. Heights are bounding-box heights at rest, in metres.
const ANIMALS := {
	"cow": {"fbx": "Cow.fbx", "name": "Cow", "height_m": 1.5},
	"horse": {"fbx": "Horse.fbx", "name": "Horse", "height_m": 2.1},
	"llama": {"fbx": "Llama.fbx", "name": "Llama", "height_m": 1.8},
	"pig": {"fbx": "Pig.fbx", "name": "Pig", "height_m": 0.9},
	"pug": {"fbx": "Pug.fbx", "name": "Pug", "height_m": 0.4},
	"sheep": {"fbx": "Sheep.fbx", "name": "Sheep", "height_m": 1.0},
	"zebra": {"fbx": "Zebra.fbx", "name": "Zebra", "height_m": 1.5},
}

## Source clip (lower case) -> the name the token animation tree plays
## (scenes/board_token/board_token_animation_tree.tscn: battlewait01 is the idle it starts in,
## damage01 and down01 follow health). A clip with no entry is dropped from the model.
const CLIPS := {
	"armature|idle": "battlewait01",
	"armature|jump": "damage01",
	"armature|death": "down01_start",
}


## The model's name for a source clip, or "" to drop it.
static func clip_name(source_name: String) -> String:
	return String(CLIPS.get(source_name.to_lower(), ""))
