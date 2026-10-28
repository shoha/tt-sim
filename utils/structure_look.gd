class_name StructureLook
extends RefCounted

## The one table that says what a part of a built structure is made of: the node type that made a
## vertex (its provenance tag, PlantGeometry.tag_table) gives a material ROLE, and a role plus the
## surface kind gives the material (AuthoredStructures). The simplest sensible split of card S2, so
## a house is not one material: walls, roofs, trim and chimneys. The painterly role table (roof
## tile surface, slate, trim lift) is card S6; it replaces ROLE_TINTS and NODE_ROLES here, and the
## contract page (ASSET_PIPELINE.md section 12) is where the table is shared with structgen.
##
## Pure and safe on any thread.

const WALL := "wall"
const ROOF := "roof"
const TRIM := "trim"
const CHIMNEY := "chimney"
## The panes and door leaves: procgen's `glazing` node (surface kind `glass`, flat vertex colours).
const OPENING := "opening"
## Every role, in the order a structure's meshes are made.
const ROLES: Array[String] = [WALL, ROOF, TRIM, CHIMNEY, OPENING]
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
	"facade_trim": TRIM,
	"cornice": TRIM,
	"quoins": TRIM,
	"roof_furniture": CHIMNEY,
	"glazing": OPENING,
}

## What each role multiplies a surface's tint by (a roof is warm terracotta over the planks, trim is
## lifted and painted, a chimney is the stone as it is).
const ROLE_TINTS: Dictionary = {
	WALL: Color(1.0, 1.0, 1.0),
	ROOF: Color(1.3, 0.72, 0.52),
	TRIM: Color(1.35, 1.3, 1.2),
	CHIMNEY: Color(1.05, 0.95, 0.9),
	OPENING: Color(1.0, 1.0, 1.0),
}


## The role of the node type `node_type`.
static func role_of_type(node_type: String) -> String:
	return String(NODE_ROLES.get(node_type, WALL))


## The role of the vertices tagged `path` ("<node id>" or "<node id>/<slot path>") in `doc`.
static func role_of_path(doc: PlantGraphDocument, path: String) -> String:
	var node_id := path.get_slice("/", 0)
	return role_of_type(doc.node_type(node_id))


## The role a (surface kind, role) pair is drawn with. A roof is its own material only where it is
## planks ("wood"): a gable's end triangles are masonry and a flat roof's coping is stone, and they
## belong to the walls.
static func material_role(kind: String, role: String) -> String:
	if role == ROOF and kind != "wood":
		return WALL
	return role


## The tint a role puts over its surface.
static func tint_of(role: String) -> Color:
	return ROLE_TINTS.get(role, Color.WHITE)
