extends RefCounted

## The Beasts and Farm Animals roster (tools/roster/build_beasts.gd): which source file becomes
## which token and how tall it stands in metres. The sources are Quaternius's animals at an
## arbitrary modeller scale, and tt-sim applies no automatic token scale (docs/ASSET_PIPELINE.md
## section 7: 1 unit is 1 metre, a grid cell is 1.524 m), so the build bakes each real-world height
## (head to hoof, ears and horns included) into the GLB's root node. A horse and a pug are then
## different token sizes with no manifest field and no user step.

## id -> {source, file, name, height_m}. `source` is the download it comes from ("farm": the
## Farm Animal Pack's FBX files; "animals": the Ultimate Animated Animal Pack's glTF files; the
## build takes a folder for each). Heights are bounding-box heights at rest in metres, head
## (antlers, raised neck) to hoof, in the idle pose. The Farm pack's own Cow and Horse are not
## built: the Animals pack's are richer and share its rig and clip set (docs/licences).
const ANIMALS := {
	"horse": {"source": "animals", "file": "Horse.gltf", "name": "Horse", "height_m": 2.1},
	"horse_white":
	{"source": "animals", "file": "Horse_White.gltf", "name": "White horse", "height_m": 2.1},
	"donkey": {"source": "animals", "file": "Donkey.gltf", "name": "Donkey", "height_m": 1.4},
	"bull": {"source": "animals", "file": "Bull.gltf", "name": "Bull", "height_m": 1.6},
	"cow": {"source": "animals", "file": "Cow.gltf", "name": "Cow", "height_m": 1.5},
	"alpaca": {"source": "animals", "file": "Alpaca.gltf", "name": "Alpaca", "height_m": 1.5},
	"stag": {"source": "animals", "file": "Stag.gltf", "name": "Stag", "height_m": 1.9},
	"deer": {"source": "animals", "file": "Deer.gltf", "name": "Deer", "height_m": 1.4},
	"wolf": {"source": "animals", "file": "Wolf.gltf", "name": "Wolf", "height_m": 0.85},
	"husky": {"source": "animals", "file": "Husky.gltf", "name": "Husky", "height_m": 0.65},
	"shiba_inu": {"source": "animals", "file": "ShibaInu.gltf", "name": "Shiba Inu", "height_m": 0.5},
	"fox": {"source": "animals", "file": "Fox.gltf", "name": "Fox", "height_m": 0.5},
	"llama": {"source": "farm", "file": "Llama.fbx", "name": "Llama", "height_m": 1.8},
	"zebra": {"source": "farm", "file": "Zebra.fbx", "name": "Zebra", "height_m": 1.5},
	"sheep": {"source": "farm", "file": "Sheep.fbx", "name": "Sheep", "height_m": 1.0},
	"pig": {"source": "farm", "file": "Pig.fbx", "name": "Pig", "height_m": 0.9},
	"pug": {"source": "farm", "file": "Pug.fbx", "name": "Pug", "height_m": 0.4},
}

## Source clip (lower case, without the FBX "Armature|" prefix) -> the name the token animation
## tree plays (scenes/board_token/board_token_animation_tree.tscn: battlewait01 is the idle it
## starts in, damage01 and down01 follow health). A clip with no entry is dropped from the model.
## The Farm pack has no hit clip, so its Jump stands in for it.
const CLIPS := {
	"idle": "battlewait01",
	"idle_hitreact1": "damage01",
	"jump": "damage01",
	"death": "down01_start",
}


## The model's name for a source clip, or "" to drop it.
static func clip_name(source_name: String) -> String:
	var short := source_name.get_slice("|", source_name.get_slice_count("|") - 1)
	return String(CLIPS.get(short.to_lower(), ""))
