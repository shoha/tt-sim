class_name StructureLook
extends RefCounted

## The one table that says what a part of a built structure is made of: the node type that made a
## vertex (its provenance tag, PlantGeometry.tag_table) gives a material ROLE, and a role plus the
## surface kind gives the material (StructureMaterials). A house is not one material: walls, roofs,
## trim, chimneys and openings. Card S6 added the painterly part: the roof tile palette and wall
## leans a building draws from (ROOF_PALETTE, WALL_LEANS; StructurePaint paints them into the
## vertex colours) and the roles of a street's provenance paths. The contract page
## (ASSET_PIPELINE.md section 12) is where the role table is shared with structgen; structgen's own
## palette (StructPalette) is separate and was only a reference for the look.
##
## Pure and safe on any thread.

const WALL := "wall"
const ROOF := "roof"
const TRIM := "trim"
const CHIMNEY := "chimney"
## The panes and door leaves: procgen's `glazing` node (surface kind `glass`, flat vertex colours).
const OPENING := "opening"
## The timber a building carries on its walls: the Timber Beams of a half-timbered storey, the vigas
## of an adobe, a roof ladder and hatch (styles integration 2). Its own role so the beams keep their
## own dark honey tone instead of taking the plaster's wall tone (StructurePaint).
const FRAME := "frame"
## The surface kinds a roof role is its own material for (card S6 had only planks): "wood" and
## "tile" the tile shader, slate, shingle, thatch and turf the style roof shader. A roof surface of
## any other kind (a gable end in plaster, a flat roof in adobe) is drawn as a wall.
const ROOF_KINDS: Array[String] = ["wood", "tile", "slate", "shingle", "thatch", "turf"]
## The wall kinds the style wall shader draws (plaster, adobe, brick, log), in its `pattern` order.
const STYLE_WALL_KINDS: Array[String] = ["plaster", "adobe", "brick", "log"]
## The roof kinds the style roof shader draws, in its `pattern` order.
const STYLE_ROOF_KINDS: Array[String] = ["slate", "shingle", "thatch", "turf"]
## Every role, in the order a structure's meshes are made.
const ROLES: Array[String] = [WALL, ROOF, TRIM, CHIMNEY, OPENING, FRAME]
## The surface kind of the panes and leaves (ProcgenGlazing.KIND); drawn unshaded from the vertex
## colours.
const GLASS_KIND := "glass"

## Procgen node type -> role. A type not listed is a wall.
const NODE_ROLES: Dictionary = {
	"building_walls": WALL,
	"building_timber": WALL,
	"facade": WALL,
	"roof_gable": ROOF,
	"roof_hip": ROOF,
	"roof_flat": ROOF,
	# Profile roofs (gambrel, mansard, half-hip, saltbox, curved gable, upswept hip, pagoda) and the
	# cones, domes and spires over round plans and towers (styles integration 3, 2026-10-28).
	"roof_profile": ROOF,
	"roof_round": ROOF,
	"facade_trim": TRIM,
	"cornice": TRIM,
	"quoins": TRIM,
	"roof_furniture": CHIMNEY,
	"glazing": OPENING,
	"beams": FRAME,
	"vigas": FRAME,
	"roof_props": FRAME,
}

## What each role multiplies a surface's tint by. A painterly wall or roof is drawn by the
## structure_wall / structure_roof shaders from its vertex colours (StructurePaint), so these tints
## reach only the modelled `stone` kind (coping, a placeholder plot) and the wall shader's albedo:
## walls as the rock is, trim lifted and painted pale, a chimney a warm brick.
const ROLE_TINTS: Dictionary = {
	WALL: Color(1.0, 1.0, 1.0),
	ROOF: Color(1.0, 1.0, 1.0),
	TRIM: Color(1.3, 1.26, 1.16),
	CHIMNEY: Color(1.25, 0.9, 0.78),
	OPENING: Color(1.0, 1.0, 1.0),
	FRAME: Color(1.0, 1.0, 1.0),
}

## The roof tile colours a building draws from (sRGB, as a painter names them), each with the share
## of buildings that wear it. The choice is a pure function of the record's seed and id
## (StructurePaint.palette_of), so every peer paints the same town. The shader multiplies this by a
## soft tile pattern and grades it from a deeper eave to a paler ridge.
const ROOF_PALETTE: Array[Dictionary] = [
	{"name": "terracotta", "srgb": Color(0.80, 0.36, 0.28), "weight": 4.0},
	{"name": "clay", "srgb": Color(0.86, 0.50, 0.31), "weight": 2.0},
	{"name": "slate", "srgb": Color(0.46, 0.62, 0.59), "weight": 3.0},
	{"name": "thatch", "srgb": Color(0.84, 0.66, 0.34), "weight": 2.0},
	{"name": "moss", "srgb": Color(0.52, 0.64, 0.34), "weight": 1.5},
	{"name": "heather", "srgb": Color(0.64, 0.47, 0.52), "weight": 0.7},
]

## The leans a building's walls draw from (multiplied into the wall vertex colours): warm cream,
## rose, ochre, sage, a cool pale. Small, so the rock still reads as the rock.
const WALL_LEANS: Array[Color] = [
	Color(1.0, 0.97, 0.90),
	Color(1.0, 0.92, 0.88),
	Color(1.0, 0.95, 0.78),
	Color(0.94, 1.0, 0.92),
	Color(0.93, 0.96, 1.0),
]


## The role of the node type `node_type`.
static func role_of_type(node_type: String) -> String:
	return String(NODE_ROLES.get(node_type, WALL))


## The role of the vertices tagged `path` ("<node id>" or "<node id>/<slot path>") in `doc`.
static func role_of_path(doc: PlantGraphDocument, path: String) -> String:
	var node_id := path.get_slice("/", 0)
	return role_of_type(doc.node_type(node_id))


## The role of a provenance path inside a street row ("street_row_2/left/lot0/roof_gable_4"): the
## last segment whose name (without its trailing node number) is in NODE_ROLES, WALL if none.
## The row's lots are sub-graphs, so their nodes are not in the row's document.
static func role_of_tag_path(path: String) -> String:
	var segments := path.split("/")
	for k in range(segments.size() - 1, -1, -1):
		var seg_name := segments[k]
		var cut := seg_name.rfind("_")
		if cut > 0 and seg_name.substr(cut + 1).is_valid_int():
			seg_name = seg_name.substr(0, cut)
		if NODE_ROLES.has(seg_name):
			return String(NODE_ROLES[seg_name])
	return WALL


## The lot a row provenance path belongs to ("left/lot0"), or "" outside a lot.
static func lot_of_tag_path(path: String) -> String:
	var segments := path.split("/")
	for k in range(1, segments.size()):
		if segments[k].begins_with("lot") and segments[k].substr(3).is_valid_int():
			return "%s/%s" % [segments[k - 1], segments[k]]
	return ""


## The role a (surface kind, role) pair is drawn with. A roof is its own material only where its
## kind is a roofing (ROOF_KINDS: planks "wood", or one of a style's): a gable's end triangles are
## masonry (or plaster, brick, ...) and a flat roof's coping is stone, and they belong to the walls.
static func material_role(kind: String, role: String) -> String:
	if role == ROOF and not ROOF_KINDS.has(kind):
		return WALL
	return role


## The palette hints of the recipe `doc` (a building style's, written on its Output node by
## ProcgenRecipes.building_from): {"wall": Array[Color], "roof": Array[Color]} in sRGB, a key only
## when the recipe lists tones for it. {} for a recipe without hints, which keeps StructurePaint's
## own draw (ROOF_PALETTE, WALL_LEANS).
static func palette_hints(doc: PlantGraphDocument) -> Dictionary:
	var out := {}
	if doc == null:
		return out
	for node_id in doc.nodes_of_type("output"):
		var params := doc.node_params(node_id)
		for part: String in ["wall", "roof"]:
			var tones: Array[Color] = []
			for hex: String in String(params.get("palette_" + part, "")).split(",", false):
				if hex.strip_edges().is_valid_html_color():
					tones.append(Color.html(hex.strip_edges()))
			if not tones.is_empty():
				out[part] = tones
	return out


## The tint a role puts over its surface.
static func tint_of(role: String) -> Color:
	return ROLE_TINTS.get(role, Color.WHITE)
