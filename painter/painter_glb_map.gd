class_name PainterGlbMap
extends RefCounted

## The painted look's host for a Blender-made map.glb (docs/systems/painter.md "GLB maps"; card
## painter-glb-parity): the ground meshes, scatter, trees and props that PainterSurfaces does not
## reach through AuthoredTerrain and AuthoredScatter. PainterSurfaces owns one (made by path on the
## first painted map, so a Classic start-up never compiles it) and calls paint() with every painted
## map and look change, retone() with a new mood or sun, and release() when the look leaves Painted.
##
## What it does, by what a node is (the contract names no roles: by name, meta and shape):
##   * a terrain mesh (wide, shallow, facing up: PainterGlbRoles.is_ground) gets the painted ground
##     shader as its material_override, in the map's world frame; its zone (meadow, path, rock,
##     shore) is read from its baked albedo's colour, so the artist's layout of paths and rock
##     stays and the sheet supplies the tones, the brush marks and the shade steps. Several
##     surfaces, a non-standard material or UVs that are not one planar map leave the mesh as
##     authored.
##   * a scatter chunk (MultiMeshInstance3D with the wind_foliage_category meta, as ScatterGlbUtils
##     builds them) of a tree the painted look grows (oak, birch, spruce ...:
##     PainterGlbRoles.tree_species) is hidden and its instances become rows of PainterTrees
##     (rows_on), grown as the authored scatter's trees; any other chunk's species mesh gets the
##     plant or solid stand-ins of PainterSurfaces.swap_surface (grass, flowers, bushes, rocks,
##     logs, trees by surface).
##   * a prop (a MeshInstance3D, or a MultiMeshInstance3D of collapsed duplicates) gets a painted
##     solid stand-in per surface in the sheet role its material or node name says
##     (PainterGlbRoles.prop_role); a light, pane, ironwork, water or a textured surface whose name
##     says nothing stays as authored.
## Everything is put back exactly by release(). The scan is spread over frames (STEP_US a frame), so
## the level entry does not stall; complete() finishes it at once (tests, render jobs).

## The time one scan step may take on the main thread.
const STEP_US := 3000
const CHUNK_META := &"wind_foliage_category"
const CHUNK_STEM := "_MultiMesh"
## Metas of nodes this look made (PainterTrees' root): never dressed.
const OWN_METAS: Array[StringName] = [&"painter_tree", &"painter_trees_host"]
## The map root's meta that carries the tree rows to PainterTrees (rows_on).
const ROWS_META := &"painter_glb_rows"

## What is drawn now: the state the last paint() was given ({} while nothing is painted).
var applied: Dictionary = {}
## func(mesh: Mesh) -> Array: the arrays of a terrain mesh's surface 0. A test replaces it: the
## headless dummy renderer keeps no mesh data to read back (the way MultiMesh.get_instance_transform
## reads identity there).
var surface_arrays: Callable = func(mesh: Mesh) -> Array: return mesh.surface_get_arrays(0)

var _map: Node3D = null
var _surfaces: RefCounted = null
var _queue: Array[Node] = []
var _seen: Dictionary = {}
var _meshes: Dictionary = {}
## The tree chunk nodes hidden (their instances are PainterTrees' rows now).
var _hidden: Array[Node3D] = []
var _generation := 0
var _scheduled := false
## [node, the material_override it had] per terrain mesh dressed.
var _grounds: Array = []
## [node, surface, the override it had, stand-in, entry] per prop surface dressed.
var _props: Array = []
## Source name -> {"species", "rows"}: the trees PainterTrees draws (rows_on).
var _tree_rows: Dictionary = {}
## "node: reason" for what was looked at and left as authored.
var _left: Array[String] = []


## Paints the GLB nodes of `map` in `state` ({"sheet", "mood", "elevation"}) for `surfaces` (the
## PainterSurfaces that owns this); called again for a re-tone or a new node.
func paint(map: Node3D, state: Dictionary, surfaces: RefCounted) -> void:
	if map != _map:
		release()
	if map == null:
		return
	_map = map
	_surfaces = surfaces
	applied = state
	_collect(map)
	_schedule()


## Puts every material back and the trees' chunk nodes shown, and forgets the map.
func release() -> void:
	_generation += 1
	_queue.clear()
	_seen.clear()
	_meshes.clear()
	for node in _hidden:
		if is_instance_valid(node):
			node.visible = true
	_hidden.clear()
	for pair: Array in _grounds:
		var node: Variant = pair[0]
		if is_instance_valid(node):
			(node as GeometryInstance3D).material_override = pair[1]
	_grounds.clear()
	for entry: Array in _props:
		var node: Variant = entry[0]
		if is_instance_valid(node):
			var mesh_node := node as MeshInstance3D
			if mesh_node.get_surface_override_material(entry[1]) == entry[3]:
				mesh_node.set_surface_override_material(entry[1], entry[2])
	_props.clear()
	_tree_rows = {}
	_left.clear()
	if is_instance_valid(_map):
		_map.remove_meta(ROWS_META)
	_map = null
	_surfaces = null
	_scheduled = false
	applied = {}


## Whether the scan still has nodes to look at.
func is_scanning() -> bool:
	return not _queue.is_empty()


## Looks at everything queued at once (tests and render jobs).
func complete() -> void:
	while not _queue.is_empty():
		_step(INF)


## Puts the sheet's tones for `mood` at sun `elevation` on every prop stand-in.
func retone(sheet: Dictionary, mood: String, elevation: float) -> void:
	for entry: Array in _props:
		PainterSurfaces._tone_plant(entry[3], entry[4], sheet, mood, elevation)


## The prop stand-ins that darken at their base (stone and wood).
func base_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for entry: Array in _props:
		out.append(entry[3])
	return out


## The terrain meshes dressed now.
func ground_nodes() -> Array[GeometryInstance3D]:
	var out: Array[GeometryInstance3D] = []
	for pair: Array in _grounds:
		if is_instance_valid(pair[0]):
			out.append(pair[0])
	return out


## The prop surfaces dressed now: [node, surface, previous override, stand-in, entry] records.
func props() -> Array:
	return _props


## The tree rows PainterTrees draws for this map (see rows_on).
func tree_rows() -> Dictionary:
	return _tree_rows


## What was looked at and left as authored, "node: reason".
func left_as_authored() -> Array[String]:
	return _left


## The rows (MapDocument's layout: position, rotation, scale) of `transforms`, which are in the
## frame of `to_map`. Pure.
static func rows_of(
	transforms: Array[Transform3D], to_map: Transform3D, scale_k: float = 1.0
) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	rows.resize(transforms.size() * MapDocument.ROW_STRIDE)
	var at := 0
	for transform in transforms:
		var t := to_map * transform
		var q := t.basis.orthonormalized().get_rotation_quaternion()
		var s := t.basis.get_scale() * scale_k
		var row := [t.origin.x, t.origin.y, t.origin.z, q.x, q.y, q.z, q.w, s.x, s.y, s.z]
		for value: float in row:
			rows[at] = value
			at += 1
	return rows


# ---------------------------------------------------------------- the scan


func _collect(node: Node) -> void:
	if _excluded(node):
		return
	var drawn := node is MeshInstance3D or node is MultiMeshInstance3D
	if drawn and not _seen.has(node.get_instance_id()):
		_queue.append(node)
	for child in node.get_children():
		_collect(child)


## Nodes the scan never dresses: the authored layers (their own looks), what this look made, and
## collision bodies.
func _excluded(node: Node) -> bool:
	if node is StaticBody3D or node is Light3D:
		return true
	var script := node.get_script() as Script
	if script != null:
		var named := str(script.get_global_name())
		if named.begins_with("Authored") or named == "FireField":
			return true
	for key in OWN_METAS:
		if node.has_meta(key):
			return true
	return false


func _schedule() -> void:
	if _scheduled or _queue.is_empty():
		return
	_scheduled = true
	var generation := _generation
	var tree := Engine.get_main_loop() as SceneTree
	tree.process_frame.connect(
		func() -> void:
			_scheduled = false
			if generation == _generation:
				_step(float(STEP_US))
				_schedule(),
		CONNECT_ONE_SHOT
	)


func _step(budget_us: float) -> void:
	var start := Time.get_ticks_usec()
	while not _queue.is_empty() and float(Time.get_ticks_usec() - start) < budget_us:
		_look(_queue.pop_front())
	if _queue.is_empty():
		_finish()


## The scan's end: the trees found go to PainterTrees.
func _finish() -> void:
	if _surfaces == null or _tree_rows.is_empty():
		return
	_map.set_meta(ROWS_META, _tree_rows)
	var trees: Variant = _surfaces.call("trees")
	if trees != null:
		(trees as Object).call("sync")


func _look(node: Node) -> void:
	if not is_instance_valid(node) or _seen.has(node.get_instance_id()):
		return
	_seen[node.get_instance_id()] = true
	if node is MultiMeshInstance3D:
		_look_multimesh(node as MultiMeshInstance3D)
	elif node is MeshInstance3D:
		_look_mesh(node as MeshInstance3D)


# ---------------------------------------------------------------- scatter chunks and duplicates


func _look_multimesh(node: MultiMeshInstance3D) -> void:
	var multimesh := node.multimesh
	if multimesh == null or multimesh.mesh == null:
		return
	var mesh := multimesh.mesh
	var stem := String(node.name).get_slice(CHUNK_STEM, 0)
	if not node.has_meta(CHUNK_META):
		# A prop's duplicates (MeshInstancingUtils): painted by surface, as a prop.
		if _claim(mesh):
			_swap_props(mesh, stem, mesh.get_aabb().size.y)
		return
	var category := str(node.get_meta(CHUNK_META))
	var species := PainterGlbRoles.tree_species(stem) if category == "tree" else ""
	if species != "":
		_add_tree_rows(stem, species, node)
		return
	if not _claim(mesh):
		return
	var entry := PainterPlantRoles.of(stem, category, false)
	if entry.is_empty():
		_left.append("%s: a tree the painted look grows by another name" % stem)
		return
	var added: Array = []
	for i in mesh.get_surface_count():
		var swap: Array = _surfaces.call(
			"swap_surface",
			mesh,
			i,
			PainterPlantRoles.for_surface(entry, mesh.surface_get_material(i)),
			mesh.get_aabb().size.y
		)
		if not swap.is_empty():
			added.append(swap)
	if added.is_empty():
		_left.append("%s: no surface a stand-in can replace" % stem)
	_surfaces.call("tone_added", added)


## Whether `mesh` is new to this scan (true once): chunk nodes that share a mesh paint it once.
func _claim(mesh: Mesh) -> bool:
	if _meshes.has(mesh.get_instance_id()):
		return false
	_meshes[mesh.get_instance_id()] = true
	return true


## Takes the instances of a tree chunk as rows for PainterTrees and hides the chunk (release shows
## it again).
func _add_tree_rows(stem: String, species: String, node: MultiMeshInstance3D) -> void:
	var multimesh := node.multimesh
	var transforms: Array[Transform3D] = []
	for i in multimesh.instance_count:
		transforms.append(multimesh.get_instance_transform(i))
	var entry: Dictionary = _tree_rows.get(stem, {"species": species, "rows": PackedFloat32Array()})
	var rows: PackedFloat32Array = entry["rows"]
	var k := PainterGlbRoles.tree_scale(species, multimesh.mesh.get_aabb().size.y)
	rows.append_array(rows_of(transforms, node.transform, k))
	entry["rows"] = rows
	_tree_rows[stem] = entry
	node.visible = false
	_hidden.append(node)


## The tree rows PainterTrees draws for `map` (set by the scan's end; {} for any other map).
static func rows_on(map: Node) -> Dictionary:
	if map == null:
		return {}
	return map.get_meta(ROWS_META, {})


## The painted-tree entries (PainterTrees.wanted's shape) of `glb` (rows_on) in `doc`. Pure in
## the rows and the document.
static func wanted(glb: Dictionary, doc: MapDocument) -> Dictionary:
	var out := {}
	var stride := MapDocument.ROW_STRIDE
	for source: String in glb:
		var rows: PackedFloat32Array = glb[source]["rows"]
		for i in rows.size() / stride:
			var p := Vector3(rows[i * stride], rows[i * stride + 1], rows[i * stride + 2])
			var key := PainterTreeSpecies.key_of(p)
			var scale: float = rows[i * stride + PainterTreeSpecies.SCALE_AT]
			out[key] = {
				"pos": p,
				"species": str(glb[source]["species"]),
				"asset": source,
				"cx": PainterTreeSpecies.context(source, scale, p, PainterTrees.density_at(doc, p)),
				"seed": PainterTreeSpecies.seed_of(key),
			}
	return out


## Stand-ins on the surfaces of a mesh shared by instances (a MultiMesh), the way a prop's are.
func _swap_props(mesh: Mesh, node_name: String, height: float) -> void:
	var added: Array = []
	for i in mesh.get_surface_count():
		var entry := _prop_entry(mesh.surface_get_material(i), node_name)
		if entry.is_empty():
			_left.append("%s: surface %d keeps its material" % [node_name, i])
			continue
		var swap: Array = _surfaces.call("swap_surface", mesh, i, entry, height)
		if not swap.is_empty():
			added.append(swap)
	_surfaces.call("tone_added", added)


# ---------------------------------------------------------------- meshes


func _look_mesh(node: MeshInstance3D) -> void:
	var mesh := node.mesh
	if mesh == null or node.material_override != null or not node.visible:
		return
	if _ground_candidate(node):
		if _dress_ground(node):
			return
	_dress_prop(node)


## Whether `node`'s mesh is wide and shallow enough to be ground (the size test only; the rest reads
## the mesh's arrays in _dress_ground).
func _ground_candidate(node: MeshInstance3D) -> bool:
	if node.mesh.get_surface_count() != 1:
		return false
	var size := (node.global_transform * node.mesh.get_aabb()).size
	return PainterGlbRoles.is_ground(size, 1.0)


## Dresses a terrain mesh in the painted ground; false (nothing changed) when it is not one after
## all or cannot be.
func _dress_ground(node: MeshInstance3D) -> bool:
	var original := node.get_active_material(0)
	if not original is BaseMaterial3D:
		_left.append("%s: terrain with a non-standard material" % node.name)
		return false
	var arrays: Array = surface_arrays.call(node.mesh)
	if arrays.size() <= Mesh.ARRAY_TEX_UV or arrays[Mesh.ARRAY_VERTEX] == null:
		_left.append("%s: terrain mesh data cannot be read" % node.name)
		return false
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals := PackedVector3Array()
	if arrays[Mesh.ARRAY_NORMAL] != null:
		normals = arrays[Mesh.ARRAY_NORMAL]
	var uvs := PackedVector2Array()
	if arrays[Mesh.ARRAY_TEX_UV] != null:
		uvs = arrays[Mesh.ARRAY_TEX_UV]
	if vertices.is_empty() or normals.size() != vertices.size():
		return false
	var xf := node.global_transform
	var stride := maxi(vertices.size() / PainterGlbRoles.SAMPLES, 1)
	var up := PackedVector3Array()
	var xz := PackedVector2Array()
	var sampled_uv := PackedVector2Array()
	for i in range(0, vertices.size(), stride):
		up.append((xf.basis * normals[i]).normalized())
		var world := xf * vertices[i]
		xz.append(Vector2(world.x, world.z))
		if uvs.size() == vertices.size():
			sampled_uv.append(uvs[i])
	var size := (xf * node.mesh.get_aabb()).size
	if not PainterGlbRoles.is_ground(size, PainterGlbRoles.up_share_of(up)):
		return false
	var material := original as BaseMaterial3D
	var ground: ShaderMaterial = _surfaces.call("make_glb_ground")
	ground.set_shader_parameter(&"world_frame", true)
	ground.set_shader_parameter(&"zone_present", false)
	var fit := PainterGlbRoles.uv_affine(xz, sampled_uv)
	var texture := material.albedo_texture
	if texture != null and bool(fit["ok"]):
		ground.set_shader_parameter(&"glb_zone", true)
		ground.set_shader_parameter(&"glb_albedo", texture)
		ground.set_shader_parameter(&"glb_uv", fit["uv"])
		ground.set_shader_parameter(&"glb_uv_b", fit["b"])
		var tint := material.albedo_color.srgb_to_linear()
		ground.set_shader_parameter(&"glb_tint", Vector3(tint.r, tint.g, tint.b))
		ground.set_shader_parameter(
			&"glb_texels_per_m", float(fit["scale"]) * float(texture.get_width())
		)
	else:
		# No texture to read (or UVs that are not one planar map): one role, by the colour.
		var meadow := PainterGlbRoles.role_of_color(material.albedo_color) == "leaf"
		ground.set_shader_parameter(&"base_meadow", 1.0 if (meadow or texture != null) else 0.0)
		if texture != null:
			_left.append("%s: terrain texture not one planar map, drawn as one role" % node.name)
	_grounds.append([node, node.material_override])
	node.material_override = ground
	return true


## Dresses a prop's surfaces in painted solids by their materials' names; surfaces with no role
## stay.
func _dress_prop(node: MeshInstance3D) -> void:
	var mesh := node.mesh
	var height := mesh.get_aabb().size.y
	var any := false
	for i in mesh.get_surface_count():
		if node.get_surface_override_material(i) != null:
			continue
		var entry := _prop_entry(mesh.surface_get_material(i), String(node.name))
		if entry.is_empty():
			_left.append("%s: surface %d keeps its material" % [node.name, i])
			continue
		var stand_in: ShaderMaterial = _surfaces.call(
			"prop_stand_in", mesh, mesh.surface_get_material(i), entry, height
		)
		if stand_in == null:
			continue
		var previous := node.get_surface_override_material(i)
		node.set_surface_override_material(i, stand_in)
		var record := [node, i, previous, stand_in, entry]
		_props.append(record)
		if not applied.is_empty():
			var sheet := PainterSheet.load_sheet(str(applied["sheet"]))
			PainterSurfaces._tone_plant(
				stand_in, entry, sheet, str(applied["mood"]), float(applied["elevation"])
			)
		any = true
	if not any and mesh.get_surface_count() == 0:
		_left.append("%s: no surfaces" % node.name)


## The solid entry of a prop surface (PainterPlantRoles' shape), {} when it keeps its material.
func _prop_entry(material: Material, node_name: String) -> Dictionary:
	if not material is BaseMaterial3D:
		return {}
	var standard := material as BaseMaterial3D
	var role := PainterGlbRoles.prop_role(
		standard.resource_name, node_name, standard.albedo_color, standard.albedo_texture != null
	)
	if role == "":
		return {}
	return {"kind": PainterPlantRoles.KIND_SOLID, "role": role, "ground_cover": false}
