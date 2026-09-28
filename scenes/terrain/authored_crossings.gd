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
## (WOOD_TINTS), stones the biome's cliff rock (its cliff_surface, triplanar) with the
## palette's moss on their upward facets in damp climates (moss_split), all shaded further by
## the geometry's vertex colours. One material per (kind, style) is shared by
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
## Per rock surface, a tint that brings a stepping stone near the palette boulders beside it:
## the cold biomes' basalt cliff is near black, their boulders light grey, and dark slabs read
## as holes in the water (P4b-3 judgment set, alpine and boreal).
const STONE_SURFACE_TINTS := {"cliff_basalt": Color(1.6, 1.58, 1.5)}
## Stones sample their rock this many times its tile size: the cliff textures are strata, and
## at their own scale a stone's top showed three or four stripes and read as a cut log.
const STONE_TILE_SCALE := 1.4
## Wood roughness is the texture's ORM; this scales its normal map (a board's grain, gentle).
const WOOD_NORMAL_SCALE := 0.6
const STONE_NORMAL_SCALE := 0.8
## Stepping stones in a damp climate grow moss on their tops, like the palette's boulders
## there: facets that face up take the palette's `moss` surface, decided per facet in patches
## (moss_split), the way treecube's rocks give each face rock or moss. How much moss by the
## style biome's climate; dry country's stones stay bare. (P4b-2 tinted the rock's vertex
## colours instead; 8-bit colours can only darken, so the tops read dull olive beside the
## boulders' bright moss, P4b-3.)
const MOSS_SURFACE := "moss"
const MOSS_AMOUNTS := {"temperate": 0.6, "cold": 0.45}
const MOSS_TINT := Color(1.0, 1.0, 1.0)
const MOSS_NORMAL_SCALE := 0.7
## Moss patches: the field's scale (radians per metre) and how far it moves the facing test.
const MOSS_FIELD_FREQ := Vector4(5.3, 3.1, 4.7, 2.3)
const MOSS_FIELD_REACH := 1.1
## Steeper facets (the shoulder at the waterline, the wet root) never take moss.
const MOSS_MIN_UP := 0.6

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
		var materials: Array[Material] = [_wood_material(style), _stone_material(style)]
		if moss_amount(style, _palette_root) > 0.0:
			materials.append(_moss_material())
		for material in materials:
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
		var amount := moss_amount(style, _palette_root)
		var split := moss_split(stone, amount) if amount > 0.0 else [stone, []]
		var mesh := ArrayMesh.new()
		for k in 2:
			var part: Array = split[k]
			if part.is_empty():
				continue
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, part)
			mesh.surface_set_material(
				mesh.get_surface_count() - 1, _stone_material(style) if k == 0 else _moss_material()
			)
		var instance := MeshInstance3D.new()
		instance.name = "Stones"
		instance.mesh = mesh
		node.add_child(instance)
	var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
	if not faces.is_empty():
		node.add_child(_body(faces, int(parts.id)))
	return node


## How much moss stepping stones of style `style` grow (MOSS_AMOUNTS by the biome's climate;
## 0: bare, also when the palette has no `moss` surface).
static func moss_amount(style: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> float:
	var biome := PaletteLibrary.biome(style, root) if style != "" else {}
	if biome.is_empty() or not PaletteLibrary.surfaces(root).has(MOSS_SURFACE):
		return 0.0
	return float(MOSS_AMOUNTS.get(String(biome.get("climate", "")), 0.0))


## True when a stone facet facing `up` (its normal's Y) with its centre at `centre` (map frame)
## is moss for `amount` (0..1): the more a facet faces up and the higher a fixed field of its
## position there, the likelier; so patches, the same on every peer. Pure.
static func is_moss(up: float, centre: Vector3, amount: float) -> bool:
	if amount <= 0.0 or up < MOSS_MIN_UP:
		return false
	var f := MOSS_FIELD_FREQ
	var field := sin(centre.x * f.x + centre.z * f.y) * cos(centre.z * f.z - centre.x * f.w)
	return up + field * 0.5 * MOSS_FIELD_REACH > 1.45 - amount


## Stone mesh `arrays` (CrossingGeometry's, indexed flat-shaded triangles) split by facet into
## [rock, moss] mesh arrays sharing the vertex arrays ([] for a part with no facet), each
## facet by is_moss(). Pure; the input is not changed.
static func moss_split(arrays: Array, amount: float) -> Array:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var rock := PackedInt32Array()
	var moss := PackedInt32Array()
	for t in range(0, indices.size(), 3):
		var a := indices[t]
		var centre := (vertices[a] + vertices[indices[t + 1]] + vertices[indices[t + 2]]) / 3.0
		var target := moss if is_moss(normals[a].y, centre, amount) else rock
		target.append_array(PackedInt32Array([a, indices[t + 1], indices[t + 2]]))
	var out: Array = []
	for part in [rock, moss]:
		var part_arrays: Array = []
		if not part.is_empty():
			part_arrays = arrays.duplicate()
			part_arrays[Mesh.ARRAY_INDEX] = part
		out.append(part_arrays)
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
	var tint: Color = STONE_SURFACE_TINTS.get(surface, STONE_TINT)
	var material := _surface_material(surface, tint, STONE_NORMAL_SCALE)
	var tile := float(PaletteLibrary.surfaces(_palette_root).get(surface, {}).get("tile_m", 3.0))
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile * STONE_TILE_SCALE, 0.1)
	_materials[key] = material
	return material


## The moss on stone tops (the palette's `moss` surface, triplanar at its own tile size), one
## for every style.
func _moss_material() -> Material:
	var key := "moss"
	if _materials.has(key):
		return _materials[key]
	var material := _surface_material(MOSS_SURFACE, MOSS_TINT, MOSS_NORMAL_SCALE)
	var tile := float(
		PaletteLibrary.surfaces(_palette_root).get(MOSS_SURFACE, {}).get("tile_m", 3.0)
	)
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile, 0.1)
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
		if moss_amount(crossing.style, root) > 0.0:
			names[MOSS_SURFACE] = true
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
## (the planks, each style's stone rock, and the moss where its stones grow it), for warming
## them before a first placement.
static func surfaces_for_styles(
	styles: PackedStringArray, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var out := PackedStringArray([WOOD_SURFACE])
	for style in styles:
		var surface := stone_surface(style, root)
		if not out.has(surface):
			out.append(surface)
		if moss_amount(style, root) > 0.0 and not out.has(MOSS_SURFACE):
			out.append(MOSS_SURFACE)
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
