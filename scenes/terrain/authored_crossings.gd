class_name AuthoredCrossings
extends Node3D

## The crossings of a map (MapDocument.crossings: plank bridges and stepping stones) as
## nodes, at the map origin with an identity transform (the map frame, like AuthoredWater).
## Per crossing, a Node3D `Crossing_<id>` holds its meshes (wood and stone, from
## CrossingGeometry) and one StaticBody3D on the terrain layer (layer 1, mask 0, not ray
## pickable, CROSSING_META = its id): tokens land on a deck or a stone as on the ground, the
## drop indicator, measure tool and drag ruler hit it, and a Blender map's grid sampling finds
## it. The tools that edit the ground under a crossing skip these bodies (exclude_of(): the
## brush rays, prop bedding, a dressed map's ground sampling); a sculpt stroke marches the
## document's heights and never sees them.
##
## `deck_heights` (per document sample, CrossingGeometry.deck_field; empty without a plank
## bridge) is what the grid's ground field raises to (GroundHeightField), and `version` changes
## with every rebuild so a cached composition knows it is stale. `top_y` is the highest
## walking surface (map Y, -INF with none), which the drag's ground cast starts above
## (GameMap._resolve_drag_ground).
##
## Materials come from the palette per crossing style (the biome id a crossing carries,
## Crossing.style): wood samples the `planks` surface tinted by the biome's climate
## (WOOD_TINTS), stones the biome's cliff rock (its cliff_surface, triplanar), both shaded
## further by the geometry's vertex colours. One material per (kind, style) is shared by
## every crossing that uses it. Building is cheap (well under a millisecond per crossing), so
## an edit rebuilds on the main thread (refresh()); a load builds the arrays on a worker
## (AuthoredLoadPrep) and create() only makes the nodes. Summary: docs/ARCHITECTURE.md
## "Crossings".

const NODE_NAME := "AuthoredCrossings"
## Set on every crossing's collision body: the crossing's id.
const CROSSING_META := &"tt_crossing"
const WOOD_SURFACE := "planks"
const DEFAULT_STONE_SURFACE := "cliff"
## Wood albedo tint by the style biome's climate (PaletteLibrary biome "climate"): sun-bleached
## (paler and less orange: the tint lifts blue more than red) in dry country, silvered in the
## cold, warm oak elsewhere. Judged on red badlands sand, where the untinted planks read as the
## ground's own orange (P4b-1 renders).
const WOOD_TINTS := {
	"temperate": Color(1.0, 0.97, 0.92),
	"cold": Color(0.9, 0.95, 1.08),
	"warm": Color(1.05, 1.02, 0.95),
	"dry": Color(1.1, 1.14, 1.3),
}
const DEFAULT_WOOD_TINT := Color(1.0, 0.97, 0.92)
## Stone albedo tint (a touch warm).
const STONE_TINT := Color(1.0, 0.99, 0.96)
## Stones sample their rock this many times its tile size: the cliff textures are strata, and
## at their own scale a stone's top showed three or four stripes and read as a cut log.
const STONE_TILE_SCALE := 1.4
## Wood roughness is the texture's ORM; this scales its normal map (a board's grain, gentle).
const WOOD_NORMAL_SCALE := 0.6
const STONE_NORMAL_SCALE := 0.8
## Stepping stones in a damp climate grow moss on their tops, like the palette's boulders
## there (P4b-2 review: plain grey stones read foreign beside mossy forest boulders): the
## vertex colour of upward facets is multiplied toward this tint, in patches. Vertex colours
## are stored as 8-bit (clamped to 1), so the tint can only take red and blue away: a mild
## one read as khaki on the rock, so it is a strong green. Dry country's stones stay bare.
const MOSS_TINTS := {
	"temperate": Color(0.42, 0.72, 0.18),
	"cold": Color(0.62, 0.74, 0.45),
}

## Per document sample, the deck's walking surface (CrossingGeometry.NONE elsewhere).
var deck_heights: PackedFloat32Array = PackedFloat32Array()
var version: int = 0
var top_y: float = -INF
## Microseconds of the last refresh's geometry and its node swap.
var last_build_usec: int = 0
var last_swap_usec: int = 0

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _materials: Dictionary = {}


## The crossings of `doc` as nodes, from `built` (CrossingGeometry.build(doc), which a loader's
## worker ran: AuthoredLoadPrep) or, when that is empty, from a build on the calling thread.
static func create(
	doc: MapDocument, built: Dictionary = {}, root: String = PaletteLibrary.DEFAULT_ROOT
) -> AuthoredCrossings:
	var crossings := AuthoredCrossings.new()
	crossings.name = NODE_NAME
	crossings._palette_root = root
	var started := Time.get_ticks_usec()
	var geometry := built if not built.is_empty() else CrossingGeometry.build(doc)
	crossings.last_build_usec = Time.get_ticks_usec() - started if built.is_empty() else 0
	crossings.apply(geometry)
	return crossings


## The AuthoredCrossings under map root `root`, created there if missing, rebuilt from
## `doc` (the authoring edits' entry, CrossingEditor). Returns the node.
static func refresh_map(root: Node3D, doc: MapDocument) -> AuthoredCrossings:
	var crossings := of_map(root)
	crossings.refresh(doc)
	return crossings


## The AuthoredCrossings under map root `root`, created there (empty) if missing.
static func of_map(root: Node3D) -> AuthoredCrossings:
	var crossings := root.get_node_or_null(NODE_NAME) as AuthoredCrossings
	if crossings == null:
		crossings = AuthoredCrossings.new()
		crossings.name = NODE_NAME
		root.add_child(crossings)
	return crossings


## Makes the wood and stone materials of every style in `styles` (biome ids; none: the
## defaults) now, their textures bound and their shaders built, so the first crossing of a
## style costs its geometry alone (the Bridge tool warms them as it opens, P4b-2).
func warm_materials(styles: PackedStringArray) -> void:
	var all := styles.duplicate()
	if all.is_empty():
		all.append("")
	for style in all:
		for material: BaseMaterial3D in [_wood_material(style), _stone_material(style)]:
			# A BaseMaterial3D builds its shader when its RID is first asked for: now, rather
			# than when the first crossing's mesh takes it.
			material.get_rid()


## The collision bodies' RIDs of the crossings under map root `root` (none: []), for a ray
## that must see the ground under them (PhysicsRayQueryParameters3D.exclude).
static func exclude_of(root: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if root == null:
		return rids
	var crossings := root.get_node_or_null(NODE_NAME) as AuthoredCrossings
	if crossings != null:
		rids = crossings.body_rids()
	return rids


## Rebuilds every crossing from `doc` on this thread.
func refresh(doc: MapDocument) -> void:
	var started := Time.get_ticks_usec()
	var built := CrossingGeometry.build(doc)
	last_build_usec = Time.get_ticks_usec() - started
	apply(built)


## Replaces every child with the crossings `built` (CrossingGeometry.build()).
func apply(built: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	for child in get_children():
		remove_child(child)
		child.free()
	deck_heights = built.get("deck", PackedFloat32Array())
	top_y = -INF
	version += 1
	for parts: Dictionary in built.get("crossings", []):
		add_child(_crossing_node(parts))
		top_y = maxf(top_y, float(parts.get("top", -INF)))
	last_swap_usec = Time.get_ticks_usec() - started


## True when some crossing has a deck the grid lies on.
func has_decks() -> bool:
	return not deck_heights.is_empty()


## top_y in world space (the node's global transform: the level's map scale and offset), or
## -INF with no crossing.
func world_top() -> float:
	if top_y == -INF:
		return -INF
	if not is_inside_tree():
		return top_y
	return (global_transform * Vector3(0.0, top_y, 0.0)).y


## Every crossing's collision body RID.
func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child in get_children():
		var body := child.get_node_or_null(^"Collision") as StaticBody3D
		if body != null:
			rids.append(body.get_rid())
	return rids


## The crossing node of crossing `crossing_id`, or null.
func get_crossing_node(crossing_id: int) -> Node3D:
	return get_node_or_null(NodePath("Crossing_%d" % crossing_id)) as Node3D


func _crossing_node(parts: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Crossing_%d" % int(parts.id)
	var style: String = parts.get("style", "")
	var wood: Array = parts.get("wood", [])
	if not wood.is_empty():
		node.add_child(_mesh_instance("Wood", wood, _wood_material(style)))
	var stone: Array = parts.get("stone", [])
	if not stone.is_empty():
		var moss: Variant = MOSS_TINTS.get(String(_biome(style).get("climate", "")))
		if moss is Color:
			stone = mossed(stone, moss)
		node.add_child(_mesh_instance("Stones", stone, _stone_material(style)))
	var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
	if not faces.is_empty():
		node.add_child(_body(faces, int(parts.id)))
	return node


## Stone mesh `arrays` (CrossingGeometry's) with moss on their upward facets: each vertex's
## colour multiplied toward `moss` by how much its facet faces up, in patches (a fixed pattern
## of the vertex's position, so every peer draws the same). Pure; the input is not changed.
static func mossed(arrays: Array, moss: Color) -> Array:
	var out := arrays.duplicate()
	var colors := (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).duplicate()
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in colors.size():
		var up := smoothstep(0.55, 0.95, normals[i].y)
		if up <= 0.0:
			continue
		var v := vertices[i]
		var patch := 0.5 + 0.5 * sin(v.x * 7.3 + v.z * 5.1) * cos(v.z * 6.7 - v.x * 3.9)
		var tint := Color.WHITE.lerp(moss, up * lerpf(0.7, 1.0, patch))
		colors[i] = Color(colors[i].r * tint.r, colors[i].g * tint.g, colors[i].b * tint.b)
	out[Mesh.ARRAY_COLOR] = colors
	return out


static func _mesh_instance(node_name: String, arrays: Array, material: Material) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	return instance


static func _body(faces: PackedVector3Array, crossing_id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = WaterSurface.TERRAIN_LAYER
	body.collision_mask = 0
	body.input_ray_pickable = false
	body.set_meta(CROSSING_META, crossing_id)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision)
	return body


## The palette biome `style` names ({} when none).
func _biome(style: String) -> Dictionary:
	return PaletteLibrary.biome(style, _palette_root) if style != "" else {}


func _wood_material(style: String) -> Material:
	var key := "wood:" + style
	if _materials.has(key):
		return _materials[key]
	var climate := String(_biome(style).get("climate", ""))
	var tint: Color = WOOD_TINTS.get(climate, DEFAULT_WOOD_TINT)
	var material := _surface_material(WOOD_SURFACE, tint, WOOD_NORMAL_SCALE)
	_materials[key] = material
	return material


func _stone_material(style: String) -> Material:
	var key := "stone:" + style
	if _materials.has(key):
		return _materials[key]
	var surface := stone_surface(style, _palette_root)
	var material := _surface_material(surface, STONE_TINT, STONE_NORMAL_SCALE)
	var tile := float(PaletteLibrary.surfaces(_palette_root).get(surface, {}).get("tile_m", 3.0))
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile * STONE_TILE_SCALE, 0.1)
	_materials[key] = material
	return material


## Resource paths of every palette texture the crossings of `doc` bind (the loader requests
## them on background threads with the ground's, so the nodes' materials find them cached).
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var paths := PackedStringArray()
	var surfaces := PaletteLibrary.surfaces(root)
	var names := {}
	for crossing in doc.crossings:
		if crossing.is_plank():
			names[WOOD_SURFACE] = true
			continue
		names[stone_surface(crossing.style, root)] = true
	for surface_name in names:
		var surface: Dictionary = surfaces.get(surface_name, {})
		for key in ["albedo", "normal", "orm"]:
			var relative: Variant = surface.get(key, "")
			if relative is String and relative != "":
				paths.append(root.path_join(relative))
	return paths


## The palette rock surface stepping stones of style `style` (a biome id, or "") take: the
## biome's cliff_surface, else DEFAULT_STONE_SURFACE.
static func stone_surface(style: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	var biome := PaletteLibrary.biome(style, root) if style != "" else {}
	var surface := String(biome.get("cliff_surface", ""))
	return surface if PaletteLibrary.surfaces(root).has(surface) else DEFAULT_STONE_SURFACE


## The palette surfaces a crossing of any kind in any of the styles `styles` (biome ids) binds
## (the planks and each style's stone rock), for warming them before a first placement.
static func surfaces_for_styles(
	styles: PackedStringArray, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var out := PackedStringArray([WOOD_SURFACE])
	for style in styles:
		var surface := stone_surface(style, root)
		if not out.has(surface):
			out.append(surface)
	if styles.is_empty():
		out.append(DEFAULT_STONE_SURFACE)
	return out


## An ORM material of palette surface `surface_name` (albedo, normal, ORM maps) with vertex
## colour multiplying the albedo and `tint` over it; a missing surface draws the tint alone.
func _surface_material(surface_name: String, tint: Color, normal_scale: float) -> ORMMaterial3D:
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.albedo_color = tint
	var surface: Dictionary = PaletteLibrary.surfaces(_palette_root).get(surface_name, {})
	var albedo := GroundPalette.load_texture(_palette_root, surface.get("albedo", ""))
	if albedo != null:
		material.albedo_texture = albedo
	var normal := GroundPalette.load_texture(_palette_root, surface.get("normal", ""))
	if normal != null:
		material.normal_enabled = true
		material.normal_texture = normal
		material.normal_scale = normal_scale
	var orm := GroundPalette.load_texture(_palette_root, surface.get("orm", ""))
	if orm != null:
		material.orm_texture = orm
	else:
		material.roughness = 0.9
	return material
