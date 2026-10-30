extends SceneTree

## Headless: writes the `structures/` kind of the core library (card S3): the starter recipes as
## `structures/<id>.structure.json` (procgen's ProcgenRecipes documents, unmodified), the index
## `structures/index.json` and `structures/pins.txt` (one line per structure, the digest of what
## tt-sim's pipeline builds at the fixed footprint and seed). The files are DATA committed in the
## core-library repo; this tool is how they were made and how a change to a recipe or to the
## pipeline is re-pinned on purpose.
##
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/export_core_structures.gd -- \
##       --out D:/dev/tabletop/core-library [--check 1]
##
## --check 1 writes nothing and exits 1 when a file on disk differs from what the tool makes.
## pins.txt lines: `<id> <pipeline digest> <triangles> <procgen digest>`. The pipeline digest is
## StructureGeometry.digest_of (the surfaces split by material role, what a host reads), the
## procgen digest ProcgenBuildingCases.digest (procgen's raw surfaces). The footprint is a 6 by 4 m
## rectangle centred on the origin of a flat 20 by 20 cell map, the seed 5, `textured` on, the
## same inputs as tests/fixtures/structure_digests.txt.

const PIN_SEED := 5
## The starters' default `wonk` (0..1) and the thatched cottages' `fringe` (metres).
const HANDMADE_WONK := 0.7
const THATCH_FRINGE_M := 0.35

## The starter set. `recipe` says how ProcgenRecipes.building makes the document (every recipe is
## glazed and exposes the `ridge` choice; the keys are `roof`, `walls`, `style`, `trim` ("" or the
## set's name: "townhouse" or "cottage"), `furniture`, and the interface defaults `height`,
## `chimneys`, `ridge` and `window_width` where they differ from the builder's). A starter's
## default ridge is 0 (the plan's longer side) unless its recipe says otherwise, so the first five
## keep the pins they had before `ridge` existed (their recipe files gain only the interface entry).
const STARTERS: Array[Dictionary] = [
	{
		"id": "stone_house",
		"recipe": {"roof": "gable", "walls": "stone", "style": "", "trim": "", "furniture": []},
		"name": "Stone house",
		"family": "house",
		"variant": "Stone",
		"tags": ["house", "stone", "gable"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "roof_pitch", "ridge"],
	},
	{
		"id": "cottage",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "cottage",
			"trim": "",
			"furniture": [],
			"fringe": THATCH_FRINGE_M
		},
		"name": "Cottage",
		"family": "cottage",
		"variant": "Timber",
		"tags": ["house", "timber", "gable"],
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "cottage_chimneyed",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "cottage",
			"trim": "cottage",
			"furniture": ["chimneys"],
			"fringe": THATCH_FRINGE_M
		},
		"name": "Cottage with chimney",
		"family": "cottage",
		"variant": "Timber, chimney",
		"tags": ["house", "timber", "gable", "chimney", "shutters"],
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "",
			"furniture": [],
			"height": 5.2
		},
		"name": "Townhouse",
		"family": "townhouse",
		"variant": "Plain",
		"tags": ["house", "stone", "gable", "townhouse"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "townhouse_trimmed",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Townhouse, trimmed",
		"family": "townhouse",
		"variant": "Trimmed",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	# The street-split card's widening (2026-10-28): the roofs, walls and chimneys a street's
	# species draw that the five above cannot show.
	{
		"id": "townhouse_timber",
		"recipe":
		{
			"roof": "gable",
			"walls": "timber",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Timber townhouse",
		"family": "townhouse",
		"variant": "Timber",
		"tags": ["house", "timber", "gable", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "ridge"],
	},
	{
		"id": "townhouse_chimneyed",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2
		},
		"name": "Townhouse with chimneys",
		"family": "townhouse",
		"variant": "Chimneys",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins", "chimney"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse_end",
		"recipe":
		{
			"roof": "gable",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2,
			"ridge": 2
		},
		"name": "Terrace-end house",
		"family": "townhouse",
		"variant": "Gable to the front",
		"tags": ["house", "stone", "gable", "townhouse", "trim", "quoins", "chimney", "end"],
		"min_side_m": 3.0,
		"max_side_m": 20.0,
		"max_area_m2": 180.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "townhouse_flat",
		"recipe":
		{
			"roof": "flat",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": [],
			"height": 5.2
		},
		"name": "Flat-roofed townhouse",
		"family": "townhouse",
		"variant": "Flat roof",
		"tags": ["house", "stone", "flat", "townhouse", "trim", "quoins"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors"],
	},
	{
		"id": "townhouse_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "stone",
			"style": "townhouse",
			"trim": "townhouse",
			"furniture": ["end_chimneys"],
			"height": 5.2,
			"chimneys": 2
		},
		"name": "Hip-roof townhouse",
		"family": "townhouse",
		"variant": "Hip roof",
		"tags": ["house", "stone", "hip", "townhouse", "trim", "quoins", "chimney"],
		"min_side_m": 3.0,
		"max_side_m": 16.0,
		"max_area_m2": 150.0,
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "cottage_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "timber",
			"style": "cottage",
			"trim": "cottage",
			"furniture": ["chimneys"]
		},
		"name": "Hip-roof cottage",
		"family": "cottage",
		"variant": "Timber, hip roof",
		"tags": ["house", "timber", "hip", "chimney", "shutters"],
		"expose": ["height", "floors", "roof_pitch", "chimneys", "ridge"],
	},
	{
		"id": "house_hip",
		"recipe":
		{
			"roof": "hip",
			"walls": "stone",
			"style": "",
			"trim": "",
			"furniture": [],
			"window_width": 0.9
		},
		"name": "Stone house, hip roof",
		"family": "house",
		"variant": "Stone, hip roof",
		"tags": ["house", "stone", "hip"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "roof_pitch", "window_width", "ridge"],
	},
	{
		"id": "house_flat",
		"recipe":
		{
			"roof": "flat",
			"walls": "stone",
			"style": "",
			"trim": "",
			"furniture": [],
			"window_width": 0.9
		},
		"name": "Stone house, flat roof",
		"family": "house",
		"variant": "Stone, flat roof",
		"tags": ["house", "stone", "flat"],
		"max_side_m": 12.0,
		"max_area_m2": 100.0,
		"expose": ["height", "window_width"],
	},
	# Architecture styles (card 1, 2026-10-29): each starter is one seeded draw of a procgen building
	# style (`procgen/recipes/building_styles/<bundle>.json`, ProcgenBuildingStyles.draw with `seed`,
	# `overrides` over the draw). The style supplies the default size, the tags (culture among them),
	# the exposed controls and the palette hints (written on the recipe's Output node); a starter
	# names only the id, the label and family and the seed.
	{
		"id": "villa_stucco",
		"bundle": "mediterranean_villa",
		"seed": 3,
		"name": "Stucco villa",
		"family": "house",
		"variant": "Stucco villa",
	},
	{
		"id": "adobe_house",
		"bundle": "adobe_house",
		"seed": 2,
		"name": "Adobe house",
		"family": "house",
		"variant": "Adobe",
	},
	{
		"id": "slate_house",
		"bundle": "slate_house",
		"seed": 0,
		"name": "Slate-roofed stone house",
		"family": "house",
		"variant": "Slate roof",
	},
	{
		"id": "alpine_chalet",
		"bundle": "alpine_chalet",
		"seed": 0,
		"name": "Alpine chalet",
		"family": "house",
		"variant": "Alpine chalet",
	},
	{
		"id": "thatched_cottage",
		"bundle": "thatched_cottage",
		"seed": 3,
		"name": "Thatched cottage",
		"family": "cottage",
		"variant": "Thatched",
	},
	{
		"id": "log_cabin",
		"bundle": "log_cabin",
		"seed": 2,
		"name": "Log cabin",
		"family": "cottage",
		"variant": "Log cabin",
	},
	{
		"id": "turf_longhouse",
		"bundle": "turf_longhouse",
		"seed": 1,
		"name": "Turf-roof longhouse",
		"family": "cottage",
		"variant": "Turf longhouse",
	},
	{
		"id": "brick_terrace",
		"bundle": "brick_terrace",
		"seed": 0,
		"name": "Brick terrace house",
		"family": "townhouse",
		"variant": "Brick, slate roof",
	},
	{
		"id": "canal_house",
		"bundle": "canal_house",
		"seed": 0,
		"name": "Canal house",
		"family": "townhouse",
		"variant": "Brick, gable to the street",
	},
	{
		"id": "barn",
		"bundle": "barn",
		"seed": 2,
		"name": "Barn",
		"family": "farm",
		"variant": "Barn",
	},
	# Styles integration 2 (2026-10-28): the stacked, jettied and flat-roof-kit styles. A starter may
	# also name `style_patch` (a dictionary deep-merged over the style file's, arrays replaced),
	# `kit_index` (the style's kit patch number, always drawn) and `tags_add` / `expose_add`.
	{
		"id": "tudor_townhouse",
		"bundle": "tudor_townhouse",
		"seed": 0,
		"name": "Tudor townhouse",
		"family": "townhouse",
		"variant": "Tudor, jettied",
		"tags_add": ["english", "jetty", "beams"],
	},
	{
		"id": "pueblo",
		"bundle": "pueblo",
		"seed": 0,
		"name": "Pueblo",
		"family": "house",
		"variant": "Pueblo, stepped",
	},
	{
		"id": "adobe_parapet",
		"bundle": "adobe_house",
		"seed": 5,
		"kit_index": 1,
		"name": "Adobe house, parapet",
		"family": "house",
		"variant": "Adobe, parapet",
		"tags_add": ["parapet"],
	},
	{
		"id": "adobe_rounded",
		"bundle": "adobe_house",
		"seed": 6,
		"kit_index": 2,
		"name": "Adobe house, rounded",
		"family": "house",
		"variant": "Adobe, vigas",
		"tags_add": ["parapet", "vigas", "rounded"],
	},
	# Styles integration 3 (2026-10-28): procgen's architecture-styles cards 4 and 5 (profile roofs,
	# towers, battlements, stepped gables, arched openings). The footprint is the main building's;
	# a tower attached to a corner or side stands outside it (docs/systems/structures.md "Styles 3").
	{
		"id": "gambrel_barn",
		"bundle": "gambrel_barn",
		"seed": 1,
		"name": "Gambrel barn",
		"family": "farm",
		"variant": "Gambrel roof",
	},
	{
		"id": "mansard_townhouse",
		"bundle": "mansard_townhouse",
		"seed": 0,
		"name": "Mansard townhouse",
		"family": "townhouse",
		"variant": "Mansard, slate",
	},
	{
		"id": "dutch_canal_house",
		"bundle": "dutch_canal_house",
		"seed": 0,
		"kit_index": 0,
		"name": "Dutch gable house",
		"family": "townhouse",
		"variant": "Stepped gable",
		"tags_add": ["stepped_gable"],
	},
	{
		"id": "dutch_bell_house",
		"bundle": "dutch_canal_house",
		"seed": 1,
		"kit_index": 2,
		"name": "Dutch bell-gable house",
		"family": "townhouse",
		"variant": "Bell gable",
		"tags_add": ["bell_gable"],
		"tags_drop": ["stepped_gable"],
	},
	{
		"id": "minka",
		"bundle": "minka",
		"seed": 0,
		"name": "Minka",
		"family": "house",
		"variant": "Thatched, upswept hip",
	},
	{
		"id": "half_hip_cottage",
		"bundle": "half_hip_cottage",
		"seed": 0,
		"name": "Half-hip cottage",
		"family": "cottage",
		"variant": "Jerkinhead, tile",
	},
	{
		"id": "saltbox_house",
		"bundle": "saltbox_house",
		"seed": 0,
		"name": "Saltbox house",
		"family": "cottage",
		"variant": "Catslide, shingle",
	},
	{
		"id": "chapel",
		"bundle": "chapel",
		"seed": 0,
		"name": "Chapel",
		"family": "hall",
		"variant": "Bell tower, spire",
	},
	{
		"id": "market_hall",
		"bundle": "market_hall",
		"seed": 0,
		"name": "Market hall",
		"family": "hall",
		"variant": "Arcaded, hip roof",
	},
	{
		"id": "chinese_hall",
		"bundle": "chinese_hall",
		"seed": 0,
		"name": "Chinese hall",
		"family": "hall",
		"variant": "Upswept hip, tile",
	},
	{
		"id": "pagoda_tower",
		"bundle": "pagoda_tower",
		"seed": 0,
		"name": "Pagoda",
		"family": "tower",
		"variant": "Tiered, upswept",
	},
	{
		"id": "castle_keep",
		"bundle": "castle_keep",
		"seed": 0,
		"name": "Castle keep",
		"family": "castle",
		"variant": "Corner turrets, battlements",
	},
	{
		"id": "gatehouse",
		"bundle": "gatehouse",
		"seed": 0,
		"name": "Gatehouse",
		"family": "castle",
		"variant": "Twin towers, arched gate",
	},
	# Half-timber framing (architecture-styles card 7, 2026-10-29): the Framing node's four looks.
	# Each is a draw of `half_timber` or `tudor_framed` with the framing pattern pinned in a
	# `style_patch` (arrays replace), so the four differ by pattern, stud spacing and plaster tone.
	{
		"id": "half_timber_house",
		"bundle": "half_timber",
		"seed": 0,
		"name": "Half-timber house",
		"family": "house",
		"variant": "Half-timber, braces",
		"style_patch":
		{
			"framing": {"pattern": [["braces", 1]], "stud_spacing": [[0.0, 1]]},
			"palette": {"wall": ["#F2DDA2", "#EDD596"]},
		},
	},
	{
		"id": "tudor_framed",
		"bundle": "tudor_framed",
		"seed": 0,
		"name": "Framed Tudor townhouse",
		"family": "townhouse",
		"variant": "Tudor, jettied, cross-braced",
		"tags_add": ["english"],
		"style_patch":
		{
			"framing": {"pattern": [["cross", 1]], "stud_spacing": [[0.0, 1]]},
			"palette": {"wall": ["#F0D9A0", "#EBD08E"]},
		},
	},
	{
		"id": "herringbone_cottage",
		"bundle": "half_timber",
		"seed": 3,
		"name": "Herringbone cottage",
		"family": "cottage",
		"variant": "Ochre plaster, herringbone",
		"style_patch":
		{
			"framing": {"pattern": [["herringbone", 1]], "stud_spacing": [[0.0, 1]]},
			"palette": {"wall": ["#E0B25C", "#D9A64E", "#E6BE70"]},
		},
	},
	{
		"id": "close_studded_house",
		"bundle": "half_timber",
		"seed": 5,
		"name": "Close-studded house",
		"family": "house",
		"variant": "Close studding, panels",
		"style_patch":
		{
			"framing": {"pattern": [["panels", 1]], "stud_spacing": [[0.6, 1]]},
			"palette": {"wall": ["#F5E8B8", "#F2E2AE"]},
		},
	},
	# Porches, galleries and dormers (architecture-styles cards 9a, 9b, 2026-10-29): the Gallery and
	# Dormer nodes' looks, each pinned in a `style_patch` so the draw always has the feature.
	{
		"id": "porch_cottage",
		"bundle": "porch_cottage",
		"seed": 0,
		"name": "Porch cottage",
		"family": "cottage",
		"variant": "Porch over the door",
		"style_patch":
		{
			"gallery": {"span": [["door", 1]], "roof": [["pent", 1]], "rail": [["balusters", 1]]},
			"dormers": [[{"form": "gable", "side": "front"}, 1]],
		},
	},
	{
		"id": "veranda_cottage",
		"bundle": "porch_cottage",
		"seed": 2,
		"name": "Veranda cottage",
		"family": "cottage",
		"variant": "Veranda along the front",
		"style_patch":
		{
			"gallery": {"span": [["front", 1]], "roof": [["pent", 1]], "rail": [["panel", 1]]},
			"dormers": [[false, 1]],
		},
	},
	{
		"id": "inn_gallery",
		"bundle": "inn_gallery",
		"seed": 0,
		"name": "Galleried inn",
		"family": "inn",
		"variant": "Upper gallery",
		"tags_add": ["english"],
		"style_patch": {"palette": {"wall": ["#F0E2BC", "#EAD8A8", "#F2E6C6"]}},
	},
	{
		"id": "dormered_house",
		"bundle": "dormered_house",
		"seed": 0,
		"name": "Dormered house",
		"family": "house",
		"variant": "Dormers on a steep roof",
		"tags_add": ["french"],
		"style_patch":
		{
			"dormers": {"form": [["gable", 1]], "side": "front", "width": [0.9, 1.2]},
			# Warm creams: the shaded face of a pale grey plaster reads mauve (as the framed houses').
			"palette": {"wall": ["#EEDDB4", "#E9D4A6", "#F0E2BC"]},
		},
	},
	# Houses on stilts (architecture-styles card 10, 2026-10-29): a raised floor on piles or
	# staddles with a stair or ladder to the door. Each is `regional` (the styles' own culture
	# tags are none of a street's region tags, and the stabbur is also `farm`), so a street split
	# never picks one; the Building tool offers them.
	{
		"id": "stilt_house",
		"bundle": "stilt_house",
		"seed": 0,
		"name": "Stilt house",
		"family": "stilt_house",
		"variant": "Raised on posts, veranda deck",
	},
	{
		"id": "lake_dwelling",
		"bundle": "lake_dwelling",
		"seed": 0,
		"name": "Lake dwelling",
		"family": "stilt_house",
		"variant": "Reed thatch over the water",
	},
	{
		"id": "stabbur",
		"bundle": "stabbur",
		"seed": 0,
		"name": "Stabbur granary",
		"family": "granary",
		"variant": "Log granary on stone staddles",
	},
	# Courtyards (architecture-styles card 11, courtyard_rows 2026-10-29): wings round a paved yard,
	# from the styles' own size (default 14 by 12 m, least side 9 m, since procgen shows the plain
	# building under 9 by 8 m). Each is `regional` (a street's lots never pick one; the Building
	# tool does), the style's tags give `inn` and `farm`. The pin is the default rectangle
	# (StructurePlacement.pin_plan: a row whose least side is over 4 m).
	{
		"id": "coaching_inn",
		"bundle": "coaching_inn",
		"seed": 0,
		"name": "Coaching inn",
		"family": "courtyard",
		"variant": "Galleried inn round a yard",
	},
	{
		"id": "siheyuan",
		"bundle": "siheyuan",
		"seed": 0,
		"name": "Siheyuan",
		"family": "courtyard",
		"variant": "Courtyard house",
	},
	{
		"id": "hof_farm",
		"bundle": "hof_farm",
		"seed": 0,
		"name": "Hof farmstead",
		"family": "courtyard",
		"variant": "Barns round a yard",
	},
	# Round and polygonal plans (styles integration card, 2026-10-28): each is a regular polygon
	# (plan kind "round", the `sides:<n>` tag), built by ProcgenRecipesRound. `round` says how:
	# {"kind": a ProcgenRecipesRound kind, "shape": a tower's roof shape} or {"make": the options
	# of ProcgenRecipesRound.make, with "sides", "radius", "radius_min" and "radius_max"}; a kind's
	# sides and radius ranges are ProcgenRecipesRound.info's, and any key of the table overrides
	# them. The index sizes are diameters (2 * radius). Adding a round structure is one entry.
	{
		"id": "roundhouse",
		"round": {"kind": "roundhouse"},
		"name": "Thatched roundhouse",
		"family": "roundhouse",
		"variant": "Thatched",
		"tags": ["house", "stone", "thatch", "roundhouse"],
		"expose": ["height", "roof_pitch", "overhang", "fringe", "finial", "textured", "wonk"],
	},
	{
		"id": "round_hut",
		"round": {"kind": "hut"},
		"name": "Round timber hut",
		"family": "roundhouse",
		"variant": "Timber hut",
		"tags": ["house", "timber", "hut", "roundhouse"],
		"expose": ["height", "roof_pitch", "overhang"],
	},
	{
		"id": "watchtower",
		"round": {"kind": "tower", "shape": "pyramid"},
		"name": "Stone watchtower",
		"family": "tower",
		"variant": "Square, pyramid roof",
		"tags": ["tower", "stone", "watchtower"],
		"expose": ["height", "floors", "roof_pitch", "overhang", "textured"],
	},
	{
		"id": "tower_hex",
		"round": {"kind": "tower", "shape": "cone", "sides": 6, "radius": 2.6, "radius_min": 2.0},
		"name": "Hex tower",
		"family": "tower",
		"variant": "Hexagonal, cone roof",
		"tags": ["tower", "stone", "cone"],
		"expose": ["height", "floors", "roof_pitch", "overhang", "textured", "finial"],
	},
	{
		"id": "dome_hall",
		"round":
		{
			"make":
			{
				"walls": "stone",
				"style": "round_hall",
				"shape": "dome",
				"height": [3.4, 2.4, 6.0],
				"pitch": [50.0, 30.0, 70.0],
				"overhang": 0.3,
				"trim": ["sills", "door_frame", "step", "cornice"],
				"glazing": true,
			},
			"sides": 10,
			"radius": 4.6,
			"radius_min": 3.4,
			"radius_max": 7.0,
		},
		"name": "Domed hall",
		"family": "hall",
		"variant": "Stone, dome",
		"tags": ["hall", "stone", "dome"],
		"expose": ["height", "roof_pitch", "overhang", "textured"],
	},
	# Ruins (styles integration 2): a style drawn with a `ruin` amount (ProcgenRuin: a ragged skyline,
	# standing doorways and gables, rubble, moss). The family is "ruin", the tag `ruin` keeps a
	# street's lots off them (StreetSplit.RUIN_TAG), and `ruin` is exposed as a slider.
	{
		"id": "ruin_cottage",
		"bundle": "slate_house",
		"seed": 1,
		"overrides": {"ruin": 0.55, "moss": 0.8},
		"name": "Ruined stone cottage",
		"family": "ruin",
		"variant": "Cottage",
		"tags_add": ["ruin", "cottage"],
		"tags_drop": ["chimney", "trim"],
		"expose_add": ["ruin"],
		"style_patch": {"size": {"default": [6, 4.5], "max_area": 70.0}},
	},
	{
		"id": "ruin_chapel",
		"bundle": "slate_house",
		"seed": 2,
		"overrides": {"ruin": 0.45, "moss": 0.9},
		"name": "Ruined chapel",
		"family": "ruin",
		"variant": "Chapel, gables standing",
		"tags_add": ["ruin", "chapel"],
		"tags_drop": ["chimney", "trim"],
		"expose_add": ["ruin"],
		"style_patch":
		{
			"defaults": {"height": [4.8, 5.4], "roof_pitch": [46, 52], "wonk": 0.3, "textured": 1},
			"size": {"default": [9, 5.5], "min_side": 4.0, "max_side": 14.0, "max_area": 110.0},
		},
	},
	{
		"id": "ruin_townhouse",
		"bundle": "canal_house",
		"seed": 1,
		"overrides": {"ruin": 0.5, "moss": 0.7},
		"name": "Ruined townhouse",
		"family": "ruin",
		"variant": "Townhouse, brick",
		"tags_add": ["ruin", "townhouse"],
		"tags_drop": ["trim", "quoins"],
		"expose_add": ["ruin"],
	},
	{
		"id": "ruin_barn",
		"bundle": "barn",
		"seed": 3,
		"overrides": {"ruin": 0.6, "moss": 0.5},
		"name": "Ruined barn",
		"family": "ruin",
		"variant": "Barn, timber",
		"tags_add": ["ruin", "barn"],
		"expose_add": ["ruin"],
	},
	{
		"id": "ruin_tower",
		"round":
		{
			"make":
			{
				"walls": "stone",
				"style": "tower",
				"shape": "cone",
				"height": [7.0, 3.0, 12.0],
				"pitch": [52.0, 30.0, 75.0],
				"overhang": 0.4,
				"floors": true,
				"trim": ["sills", "door_frame", "step", "cornice"],
				"ruin": 0.55,
				"moss": 0.8,
			},
			"sides": 8,
			"radius": 2.6,
			"radius_min": 2.0,
			"radius_max": 4.0,
		},
		"name": "Ruined tower",
		"family": "ruin",
		"variant": "Tower, octagon",
		"tags": ["ruin", "tower", "stone"],
		"expose": ["height", "floors", "roof_pitch", "ruin"],
	},
]


func _initialize() -> void:
	var args := _args()
	var out_dir := String(args.get("out", ""))
	if out_dir == "":
		printerr("--out <core-library folder> is required")
		quit(2)
		return
	var check := String(args.get("check", "")) in ["1", "true"]
	var made := _make()
	var problems := 0
	for relative: String in made["files"]:
		var path := out_dir.path_join(relative)
		var text := String(made["files"][relative])
		if check:
			var have := FileAccess.get_file_as_string(path).replace("\r\n", "\n")
			if have != text:
				printerr("differs: %s" % relative)
				problems += 1
			continue
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			printerr("cannot write %s" % path)
			quit(2)
			return
		file.store_string(text)
		file.close()
	for line: String in made["pins"]:
		print(line)
	for warning: String in made["warnings"]:
		printerr("warning: " + warning)
	print("%d files %s" % [(made["files"] as Dictionary).size(), "checked" if check else "written"])
	quit(1 if problems > 0 else 0)


## {files: {library-relative path: text}, pins: [line], warnings: [text]}.
func _make() -> Dictionary:
	var files := {}
	var warnings: Array[String] = []
	var entries: Array = []
	var texts := {}
	for starter in STARTERS:
		var id := String(starter["id"])
		var style := _style_of(starter)
		var doc := _document_of_starter(starter, style)
		var text := doc.to_json()
		# The shipped recipes are procgen's builders with glazing on (a pane in every window, a leaf
		# in every door), so they differ from procgen's committed `recipes/` files by that node.
		files[LibraryStructures.recipe_path(id)] = text
		texts["core:" + id] = text
		var declares_textured := false
		for entry in doc.interface:
			declares_textured = declares_textured or String(entry.get("name", "")) == "textured"
		var size: Dictionary = style.get("size", {})
		var round_spec := _round_spec(starter)
		if not round_spec.is_empty():
			var rmax: float = round_spec["radius_max"]
			size = {
				"default": [2.0 * float(round_spec["radius"]), 2.0 * float(round_spec["radius"])],
				"min_side": 2.0 * float(round_spec["radius_min"]),
				"max_side": 2.0 * rmax,
				"max_area": 4.0 * rmax * rmax,
			}
		(
			entries
			. append(
				{
					"id": id,
					"name": starter["name"],
					"family": starter["family"],
					"variant": starter["variant"],
					"tags": _tags_of(starter, style),
					"file": LibraryStructures.recipe_path(id),
					"default_size_m": size.get("default", [6, 4]),
					"min_side_m":
					starter.get(
						"min_side_m", size.get("min_side", LibraryStructures.DEFAULT_MIN_SIDE_M)
					),
					"max_side_m":
					starter.get(
						"max_side_m", size.get("max_side", LibraryStructures.DEFAULT_MAX_SIDE_M)
					),
					"max_area_m2":
					starter.get(
						"max_area_m2", size.get("max_area", LibraryStructures.DEFAULT_MAX_AREA_M2)
					),
					"plans":
					[StructurePlacement.ROUND_PLAN] if not round_spec.is_empty() else ["rect"],
					"expose": _exposed(starter, style, doc),
					"textured": declares_textured,
					"thumb": LibraryStructures.thumb_path(id),
				}
			)
		)
	files[LibraryStructures.INDEX_FILE] = LibraryStructures.index_text(entries)
	StructureRecipes.resolver = func(ref: String) -> Dictionary:
		return {"text": texts[ref]} if texts.has(ref) else {}
	var rows := {}
	for entry: Dictionary in entries:
		rows[String(entry["id"])] = entry
	var pins: Array[String] = []
	var doc := MapDocument.create_flat(Vector2i(20, 20), "grass", "v", 9)
	for starter in STARTERS:
		var ref := "core:" + String(starter["id"])
		var plan := _pin_plan_of(starter, rows[String(starter["id"])] as Dictionary)
		var parts := StructureGeometry.build_one(doc, Structure.make(1, ref, plan, PIN_SEED))
		if String(parts["problem"]) != "":
			warnings.append("%s: %s" % [ref, parts["problem"]])
		pins.append(
			(
				"%s %s %d %s"
				% [
					starter["id"],
					StructureGeometry.digest_of(parts),
					StructureGeometry.triangle_count(parts),
					_raw_digest(doc, ref, plan)
				]
			)
		)
	files[LibraryStructures.PINS_FILE] = "\n".join(pins) + "\n"
	StructureRecipes.resolver = Callable()
	return {"files": files, "pins": pins, "warnings": warnings}


## The ProcgenRecipes document of starter recipe `spec` (see STARTERS), with glazing, the ridge
## choice and the handmade look on (ProcgenRecipes.building's last three arguments; the named
## builders do not pass them). The handmade look is the starter set's default (2026-10-28 look
## integration): `wonk` (default 0.7) for every starter, `fringe` (the ragged thatch edge, metres)
## only where the recipe names it, on the timber gable cottages.
func _document_of(spec: Dictionary) -> PlantGraphDocument:
	var trim: Array = []
	match String(spec.get("trim", "")):
		"townhouse":
			trim = ProcgenRecipes.TOWNHOUSE_TRIM
		"cottage":
			trim = ProcgenRecipes.COTTAGE_TRIM
	var doc := ProcgenRecipes.building(
		String(spec["roof"]),
		String(spec["walls"]),
		String(spec["style"]),
		trim,
		spec["furniture"] as Array,
		true,
		true,
		true
	)
	_set_default(doc, "wonk", float(spec.get("wonk", HANDMADE_WONK)))
	for key: String in ["height", "chimneys", "ridge", "window_width", "fringe"]:
		if spec.has(key):
			_set_default(doc, key, float(spec[key]))
	return doc


## What a round starter is made for: {"sides", "radius", "radius_min", "radius_max"} (metres), the
## kind's ProcgenRecipesRound.info with the starter's own keys over it; {} for any other starter.
static func _round_spec(starter: Dictionary) -> Dictionary:
	if not starter.has("round"):
		return {}
	var spec: Dictionary = starter["round"]
	var info: Dictionary = ProcgenRecipesRound.info(String(spec.get("kind", "")))
	var out := {
		"sides": int(spec.get("sides", info.get("sides", 8))),
		"radius": float(spec.get("radius", info.get("radius", 3.0))),
		"radius_min": float(spec.get("radius_min", info.get("radius_min", 2.0))),
		"radius_max": float(spec.get("radius_max", info.get("radius_max", 5.0))),
	}
	return out


## The footprint the starter is pinned at: the fixed 6 by 4 m rectangle, or a round starter's own
## regular polygon at its default radius (turn 0), or for a row whose least side is 8 m or more (the
## courtyards, which show the plain building under their 9 by 8 m minimum) its default rectangle.
## `row` is the starter's index entry (StructurePlacement.pin_plan decides).
func _pin_plan_of(starter: Dictionary, row: Dictionary) -> PackedVector2Array:
	var round_spec := _round_spec(starter)
	if round_spec.is_empty():
		return StructurePlacement.pin_plan(row)
	return StructurePlacement.round_plan(
		Vector2.ZERO, float(round_spec["radius"]), 0.0, int(round_spec["sides"])
	)


## The building style a starter is a draw of ({} for a starter written as a `recipe`).
static func _style_of(starter: Dictionary) -> Dictionary:
	if not starter.has("bundle"):
		return {}
	var style := ProcgenBuildingStyles.named(String(starter["bundle"]))
	if starter.has("kit_index"):
		# One of the style's kit patches, always drawn.
		var kit: Array = style.get("kit", [])
		style["kit"] = [[(kit[int(starter["kit_index"])] as Array)[0], 1]]
	return _merged(style, starter.get("style_patch", {}) as Dictionary)


## `patch` laid over `base`: dictionaries merge key by key, anything else (an array too) replaces.
static func _merged(base: Dictionary, patch: Dictionary) -> Dictionary:
	var out := base.duplicate(true)
	for key: String in patch:
		if out.get(key) is Dictionary and patch[key] is Dictionary:
			out[key] = _merged(out[key] as Dictionary, patch[key] as Dictionary)
		else:
			out[key] = patch[key]
	return out


## The tags of `starter`: its own, else its style's and `regional` (StreetSplit.REGIONAL_TAG: a
## street's generic lots do not pick a regional style).
static func _tags_of(starter: Dictionary, style: Dictionary) -> Array:
	var round_spec := _round_spec(starter)
	if not round_spec.is_empty():
		# A round plan is never a street's lot (its lots are rectangles) and belongs to a region.
		var tags: Array = (starter.get("tags", []) as Array).duplicate()
		tags.append(StructurePlacement.ROUND_PLAN)
		tags.append("%s%d" % [StructurePlacement.SIDES_TAG, int(round_spec["sides"])])
		tags.append(StreetSplit.REGIONAL_TAG)
		return tags
	if starter.has("tags"):
		return starter["tags"]
	var tags: Array = (style.get("tags", []) as Array).duplicate()
	for gone: Variant in starter.get("tags_drop", []) as Array:
		tags.erase(gone)
	for extra: Variant in starter.get("tags_add", []) as Array:
		if not extra in tags:
			tags.append(extra)
	if starter.has("bundle"):
		tags.append(StreetSplit.REGIONAL_TAG)
	return tags


## The recipe document of `starter`: a seeded draw of its style (`bundle`, `seed`, `overrides`), or
## the builder's document of its `recipe`.
func _document_of_starter(starter: Dictionary, style: Dictionary) -> PlantGraphDocument:
	if starter.has("round"):
		var spec: Dictionary = starter["round"]
		if spec.has("make"):
			return ProcgenRecipesRound.make(spec["make"] as Dictionary)
		if String(spec["kind"]) == "tower":
			return ProcgenRecipesRound.tower(String(spec.get("shape", "pyramid")))
		return ProcgenRecipesRound.named(String(spec["kind"]))
	if starter.has("bundle"):
		var doc := ProcgenRecipes.building_from(
			ProcgenBuildingStyles.draw(
				style, int(starter.get("seed", 0)), starter.get("overrides", {}) as Dictionary
			)
		)
		# A draw keeps one wall tone; a library structure keeps the style's whole list, so each
		# placement draws its own (StructurePaint.palette_of).
		var walls: Array = (style.get("palette", {}) as Dictionary).get("wall", [])
		if walls.size() > 1:
			for id in doc.nodes_of_type("output"):
				doc.set_param(id, "palette_wall", ",".join(PackedStringArray(walls)))
		return doc
	return _document_of(starter["recipe"] as Dictionary)


## The starter's `expose` list plus the handmade look's controls (`wonk` on all, `fringe` where
## set). A style's own list is kept to the names its drawn recipe declares (the interface differs by roof
## and furniture), and already holds what its style wants.
static func _exposed(starter: Dictionary, style: Dictionary, doc: PlantGraphDocument) -> Array:
	if starter.has("round"):
		var declared := PackedStringArray()
		for entry in doc.interface:
			declared.append(String(entry["name"]))
		return (starter["expose"] as Array).filter(
			func(name: Variant) -> bool: return String(name) in declared
		)
	if starter.has("bundle"):
		var names := PackedStringArray()
		for entry in doc.interface:
			names.append(String(entry["name"]))
		var kept: Array = []
		var wanted: Array = (style.get("expose", []) as Array).duplicate()
		wanted.append_array(starter.get("expose_add", []) as Array)
		for name: Variant in wanted:
			if String(name) in names and not name in kept:
				kept.append(name)
		return kept
	var out: Array = (starter["expose"] as Array).duplicate()
	out.append("wonk")
	if (starter["recipe"] as Dictionary).has("fringe"):
		out.append("fringe")
	return out


static func _set_default(doc: PlantGraphDocument, name: String, value: float) -> void:
	for entry in doc.interface:
		if entry["name"] == name:
			entry["default"] = value


## procgen's own digest of the same build (ProcgenBuildingCases.digest of the first LOD).
func _raw_digest(doc: MapDocument, ref: String, plan: PackedVector2Array) -> String:
	var recipe := StructureRecipes.document(ref)
	if recipe == null:
		return "-"
	var structure := Structure.make(1, ref, plan, PIN_SEED)
	var evaluator := PlantGraphEvaluator.new(recipe.registry)
	var plant: Variant = evaluator.evaluate_structure(
		recipe, StructureGeometry.inputs_for(doc, structure, recipe), true
	)
	if plant == null:
		return "-"
	return ProcgenBuildingCases.digest((plant as Dictionary)["lods"][0])


func _args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		if raw[i].begins_with("--") and i + 1 < raw.size():
			out[raw[i].trim_prefix("--")] = raw[i + 1]
			i += 2
		else:
			i += 1
	return out
