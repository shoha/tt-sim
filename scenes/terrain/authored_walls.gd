class_name AuthoredWalls
extends Node3D

## The walls and fences of a map (MapDocument.walls) as nodes, at the map origin with an
## identity transform (the map frame, like AuthoredCrossings). Per wall, a Node3D `Wall_<id>`
## holds its mesh (`Stone` or `Wood`, from WallGeometry) and, for a stone wall, one StaticBody3D
## on the terrain layer (layer 1, mask 0, not ray pickable, WALL_META = its id): a token lands
## on a wall's coping as on the ground, the drop indicator and measure tool hit it, and the
## tools that edit the ground skip it (exclude_of()). A fence has no collision: it is a mark on
## the ground tokens walk through. `top_y` is the highest wall top (map Y, -INF with none).
##
## Materials come from the palette like a crossing's: a stone wall takes its style biome's cliff
## rock (AuthoredCrossings.stone_surface, triplanar) with the palette's moss on its upward
## facets in damp climates (AuthoredCrossings.moss_split, which reads the coping's moss keys), a
## fence the planks tinted by the biome's climate. One material per (kind, style) is shared. An
## edit rebuilds, on the main thread, only the walls whose key (WallGeometry.key_of: fields and
## the ground under them) changed; a load builds the arrays on a worker (AuthoredLoadPrep) and
## create() only makes the nodes. Summary: docs/systems/walls.md.

const NODE_NAME := "AuthoredWalls"
## Set on every stone wall's collision body: the wall's id.
const WALL_META := &"tt_wall"
const STONE_NORMAL_SCALE := 0.8
## What a textured wall's tint is lifted by over the rock's mean colour (judged beside the
## boulders).
const WALL_MASONRY_LIFT := Color(1.25, 1.3, 1.35)
## Per rock surface, a stronger lift (the basalt cliff's mean is near black and blue).
const WALL_MASONRY_LIFTS := {"cliff_basalt": Color(2.0, 1.9, 1.55)}
## The masonry tile is shown this much larger than baked: stones as big as the modelled ones.
const MASONRY_SCALE_UP := 1.5
## A wall's masonry is lifted and warmed over a stepping stone's tint: its flat-shaded faces, the
## block shade and the dark foot average well under the palette boulders' value, and the cliff
## surfaces read blue-grey beside their warm rocks (judged on alpine, badlands and forest, side by
## side with the boulders, 2026-10-27).
const WALL_STONE_TINT := Color(1.2, 1.2, 1.17)
## The cold biomes' basalt cliff is near black and blue; their boulders are olive grey. The
## badlands' sandstone reads pink beside their golden boulders.
const WALL_SURFACE_TINTS := {
	"cliff_basalt": Color(1.95, 1.85, 1.45), "cliff_sandstone": Color(1.3, 1.27, 1.06)
}
const WOOD_NORMAL_SCALE := 0.6

## Highest wall top, map Y (-INF with none), and a counter that changes with every rebuild.
var top_y: float = -INF
var version: int = 0
## How many walls this node has built since it was made (tests count what an edit rebuilt).
var builds: int = 0
var last_rebuilt: int = 0

var _palette_root: String = PaletteLibrary.DEFAULT_ROOT
var _materials: Dictionary = {}
## Per wall id, the WallGeometry key its node was built from.
var _keys: Dictionary = {}
## Per wall id, its geometry's highest point.
var _tops: Dictionary = {}


## The walls of `doc` as nodes, from `built` (WallGeometry.build(doc), which a loader's worker
## ran) or, when that is empty, from a build on the calling thread.
static func create(
	doc: MapDocument, built: Dictionary = {}, root: String = PaletteLibrary.DEFAULT_ROOT
) -> AuthoredWalls:
	var walls := AuthoredWalls.new()
	walls.name = NODE_NAME
	walls._palette_root = root
	walls.apply(built if not built.is_empty() else WallGeometry.build(doc))
	walls._keys = WallGeometry.keys_of(doc)
	return walls


## The AuthoredWalls under map root `root`, created there (empty) if missing.
static func of_map(root: Node3D) -> AuthoredWalls:
	var walls := root.get_node_or_null(NODE_NAME) as AuthoredWalls
	if walls == null:
		walls = AuthoredWalls.new()
		walls.name = NODE_NAME
		root.add_child(walls)
	return walls


## The AuthoredWalls under map root `root`, created if missing, brought up to `doc`.
static func refresh_map(root: Node3D, doc: MapDocument) -> AuthoredWalls:
	var walls := of_map(root)
	walls.refresh(doc)
	return walls


## The collision bodies' RIDs of the walls under map root `root` (none: []), for a ray that must
## see the ground under them.
static func exclude_of(root: Node) -> Array[RID]:
	var rids: Array[RID] = []
	if root == null:
		return rids
	var walls := root.get_node_or_null(NODE_NAME) as AuthoredWalls
	if walls != null:
		rids = walls.body_rids()
	return rids


## Brings the nodes up to `doc`, rebuilding only the walls whose key differs from the one their
## node was built with or that have no node yet, and freeing the nodes of walls that left.
func refresh(doc: MapDocument) -> void:
	var keys := WallGeometry.keys_of(doc)
	var changed := false
	for child in get_children():
		if not keys.has(_id_of(child)):
			_free_wall_node(_id_of(child))
			changed = true
	var rebuilt := 0
	for wall in doc.walls:
		if _keys.get(wall.id) == keys[wall.id] and get_wall_node(wall.id) != null:
			continue
		var parts := WallGeometry.build_one(doc, wall)
		_free_wall_node(wall.id)
		add_child(_wall_node(parts))
		_tops[wall.id] = float(parts.top)
		rebuilt += 1
		changed = true
	_keys = keys
	builds += rebuilt
	last_rebuilt = rebuilt
	if changed:
		_recompute_top()
		version += 1


## Replaces every child with the walls `built` (WallGeometry.build()). The keys are cleared; the
## next refresh() rebuilds every wall unless create() seeded them.
func apply(built: Dictionary) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	_keys.clear()
	_tops.clear()
	for parts: Dictionary in built.get("walls", []):
		add_child(_wall_node(parts))
		_tops[int(parts.id)] = float(parts.top)
	_recompute_top()
	version += 1


## The key each wall's node was built with (id -> key; tests).
func keys() -> Dictionary:
	return _keys.duplicate()


## top_y in world space (the node's global transform), or -INF with no wall.
func world_top() -> float:
	if top_y == -INF:
		return -INF
	if not is_inside_tree():
		return top_y
	return (global_transform * Vector3(0.0, top_y, 0.0)).y


## Every stone wall's collision body RID.
func body_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for child in get_children():
		var body := child.get_node_or_null(^"Collision") as StaticBody3D
		if body != null:
			rids.append(body.get_rid())
	return rids


## The node of wall `wall_id`, or null.
func get_wall_node(wall_id: int) -> Node3D:
	return get_node_or_null(NodePath("Wall_%d" % wall_id)) as Node3D


## The wall id a `Wall_<id>` node carries (-1 for any other child).
static func _id_of(node: Node) -> int:
	var node_name := String(node.name)
	if not node_name.begins_with("Wall_"):
		return -1
	return int(node_name.trim_prefix("Wall_"))


func _free_wall_node(wall_id: int) -> void:
	var node := get_wall_node(wall_id)
	if node != null:
		remove_child(node)
		node.free()
	_tops.erase(wall_id)


func _recompute_top() -> void:
	top_y = -INF
	for top in _tops.values():
		top_y = maxf(top_y, float(top))


func _wall_node(parts: Dictionary) -> Node3D:
	var node := Node3D.new()
	node.name = "Wall_%d" % int(parts.id)
	var style: String = parts.get("style", "")
	var row: bool = int(parts.get("kind", -1)) == Wall.Kind.ROW
	var stone: Array = parts.get("stone", [])
	if not stone.is_empty():
		var amount := AuthoredCrossings.moss_amount(style, _palette_root)
		var split: Array = [stone, []]
		if amount > 0.0:
			split = AuthoredCrossings.moss_split(stone, amount)
		var mesh := ArrayMesh.new()
		if not (split[0] as Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split[0])
			mesh.surface_set_material(mesh.get_surface_count() - 1, _stone_material(style))
		if not (split[1] as Array).is_empty():
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, split[1])
			mesh.surface_set_material(mesh.get_surface_count() - 1, _moss_material())
		var instance := MeshInstance3D.new()
		instance.name = "Stone"
		instance.mesh = mesh
		node.add_child(instance)
	var masonry: Array = parts.get("masonry", [])
	if not masonry.is_empty():
		var textured_mesh := ArrayMesh.new()
		textured_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, masonry)
		textured_mesh.surface_set_material(
			0, _row_material("masonry", style) if row else _masonry_material(style)
		)
		var masonry_instance := MeshInstance3D.new()
		masonry_instance.name = "Masonry"
		masonry_instance.mesh = textured_mesh
		node.add_child(masonry_instance)
	var wood: Array = parts.get("wood", [])
	if not wood.is_empty():
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, wood)
		mesh.surface_set_material(0, _row_material("wood", style) if row else _wood_material(style))
		var instance := MeshInstance3D.new()
		instance.name = "Wood"
		instance.mesh = mesh
		node.add_child(instance)
	# A street's roofs (WallGeometry.ROOF_PART), drawn with the roof tile shader of the structures.
	var roof: Array = parts.get(WallGeometry.ROOF_PART, [])
	if not roof.is_empty():
		var roof_mesh := ArrayMesh.new()
		roof_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, roof)
		roof_mesh.surface_set_material(0, _row_material("wood", style, true))
		var roof_instance := MeshInstance3D.new()
		roof_instance.name = "Roof"
		roof_instance.mesh = roof_mesh
		node.add_child(roof_instance)
	# A street's panes and door leaves (procgen's glazing node, surface kind "glass").
	var glass: Array = parts.get("glass", [])
	if not glass.is_empty():
		var glass_mesh := ArrayMesh.new()
		glass_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, glass)
		glass_mesh.surface_set_material(0, _glass_material())
		var glass_instance := MeshInstance3D.new()
		glass_instance.name = "Glass"
		glass_instance.mesh = glass_mesh
		glass_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(glass_instance)
	var faces: PackedVector3Array = parts.get("collision", PackedVector3Array())
	if not faces.is_empty():
		node.add_child(_body(faces, int(parts.id)))
	return node


static func _body(faces: PackedVector3Array, wall_id: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = WaterSurface.TERRAIN_LAYER
	body.collision_mask = 0
	body.input_ray_pickable = false
	body.set_meta(WALL_META, wall_id)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = shape
	body.add_child(collision)
	return body


## Panes and door leaves: the vertex colour as a flat painted tone, seen from both sides and
## unshaded (as AuthoredStructures draws them).
func _glass_material() -> Material:
	if _materials.has("glass"):
		return _materials["glass"]
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_materials["glass"] = material
	return material


## The painterly material a street's lots share with the structures (StructureMaterials): masonry
## and timber walls in the wall role, or, with `roof`, the roof tiles.
func _row_material(kind: String, style: String, roof: bool = false) -> Material:
	var role := StructureLook.ROOF if roof else StructureLook.WALL
	var key := "row:%s:%s:%s" % [kind, role, style]
	if not _materials.has(key):
		_materials[key] = StructureMaterials.make(kind, role, style, _palette_root)
	return _materials[key]


func _stone_material(style: String) -> Material:
	var key := "stone:" + style
	if _materials.has(key):
		return _materials[key]
	var surface := AuthoredCrossings.stone_surface(style, _palette_root)
	var tint: Color = WALL_SURFACE_TINTS.get(surface, WALL_STONE_TINT)
	var material := AuthoredCrossings.surface_material(
		_palette_root, surface, tint, STONE_NORMAL_SCALE
	)
	var tile := float(PaletteLibrary.surfaces(_palette_root).get(surface, {}).get("tile_m", 3.0))
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile * AuthoredCrossings.STONE_TILE_SCALE, 0.1)
	_materials[key] = material
	return material


## The baked masonry set (MasonryTextures) tinted by the style's rock colour: UVs are metres, the
## tile 3 by 1.2 m, the normal map and the joints' occlusion from the bake.
func _masonry_material(style: String) -> Material:
	var key := "masonry:" + style
	if _materials.has(key):
		return _materials[key]
	var textures := MasonryTextures.textures()
	var material := ORMMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	var surface_name := AuthoredCrossings.stone_surface(style, _palette_root)
	var surface: Dictionary = PaletteLibrary.surfaces(_palette_root).get(surface_name, {})
	var mean: Array = surface.get("albedo_mean_linear", [0.3, 0.3, 0.3])
	material.albedo_color = MasonryTextures.tint_of(
		mean, WALL_MASONRY_LIFTS.get(surface_name, WALL_MASONRY_LIFT)
	)
	if not textures.is_empty():
		material.albedo_texture = textures.albedo
		material.normal_enabled = true
		material.normal_texture = textures.normal
		material.normal_scale = 1.0
		material.orm_texture = textures.orm
	material.uv1_scale = (
		Vector3(1.0 / MasonryTextures.TILE_M, 1.0 / MasonryTextures.TILE_H_M, 1.0)
		/ MASONRY_SCALE_UP
	)
	_materials[key] = material
	return material


func _moss_material() -> Material:
	var key := "moss"
	if _materials.has(key):
		return _materials[key]
	var moss := LibraryBindings.crossing_moss()
	var material := AuthoredCrossings.surface_material(
		_palette_root, moss, AuthoredCrossings.MOSS_TINT, AuthoredCrossings.MOSS_NORMAL_SCALE
	)
	var tile := float(PaletteLibrary.surfaces(_palette_root).get(moss, {}).get("tile_m", 3.0))
	material.uv1_triplanar = true
	material.uv1_triplanar_sharpness = 4.0
	material.uv1_scale = Vector3.ONE / maxf(tile, 0.1)
	_materials[key] = material
	return material


func _wood_material(style: String) -> Material:
	var key := "wood:" + style
	if _materials.has(key):
		return _materials[key]
	var biome := PaletteLibrary.biome(style, _palette_root) if style != "" else {}
	var tint: Color = AuthoredCrossings.WOOD_TINTS.get(
		String(biome.get("climate", "")), AuthoredCrossings.DEFAULT_WOOD_TINT
	)
	var material := AuthoredCrossings.surface_material(
		_palette_root, LibraryBindings.crossing_planks(), tint, WOOD_NORMAL_SCALE
	)
	_materials[key] = material
	return material


## Resource paths of every palette texture the walls of `doc` bind (the loader requests them on
## background threads with the ground's).
static func texture_paths(
	doc: MapDocument, root: String = PaletteLibrary.DEFAULT_ROOT
) -> PackedStringArray:
	var surfaces := PaletteLibrary.surfaces(root)
	var names := {}
	for wall in doc.walls:
		if wall.is_fence():
			names[LibraryBindings.crossing_planks()] = true
			continue
		names[AuthoredCrossings.stone_surface(wall.style, root)] = true
		if AuthoredCrossings.moss_amount(wall.style, root) > 0.0:
			names[LibraryBindings.crossing_moss()] = true
	var paths := PackedStringArray()
	for surface_name in names:
		var surface: Dictionary = surfaces.get(surface_name, {})
		for key in ["albedo", "normal", "orm"]:
			var relative: Variant = surface.get(key, "")
			if (
				relative is String
				and relative != ""
				and not SurfaceStore.is_library_path(root, relative)
			):
				paths.append(root.path_join(relative))
	return paths
