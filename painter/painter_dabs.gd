class_name PainterDabs
extends RefCounted
## The meshes of the small stones' dabs (card painter-terrain-dabs; PainterSites has the model and
## the geometry of one dab).
##
## PainterOcclusion finds the small stones (the sites) with its footprints and hands them here
## after every rebuild of its field. This host keeps one mesh per CELL_M square of the map that
## holds a site, all under one node beside the terrain (in the terrain's frame, drawn with the
## chunks' own material, casting no shadow), and each site's patch as it was last built, so a
## change costs what changed:
## - a site that is new, or that stands where the ground was edited since the last sync
##   (`mark`), is built: a copy of the terrain's triangles under it;
## - a site that is gone is dropped;
## - a cell one of those lies in is put together again from its sites' kept arrays and uploaded;
##   every other cell is left as it is.
## A stone is known by its place and radius, so one the ground moved under (its foot's height
## changed) keeps its turn in its cell: the patches after it keep their first vertex and their
## indices are appended as they are (adding an offset to every index of a cell was half the cost
## of an edit under a stroke).
## Nothing here reads the sun: the dab's lean is the shader's (a uniform), so the hour changing
## builds nothing (`built` counts the sites built, for the tests and the proof).
## A map without an authored terrain (a GLB map) has no heights to lay a dab on and gets none.
##
## MANAGED BY: PainterOcclusion (painter/painter_occlusion.gd). Classic never loads this file.

## What is kept of a site (the fields of its Array).
enum { SITE, CELL, VERTICES, UVS, CUSTOM, INDICES, RECT, FIRST, PLACED }

const NODE_NAME := "PainterDabs"
## Metres a cell of dabs is across (one mesh, one draw).
const CELL_M := 16.0
## The mesh format's flags: four custom channels of four floats (PainterSites: the lobes, the base).
const FORMAT := (
	(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
)

## The sites built since this host was made, and the cells put together.
var built := 0
var uploaded := 0

var _holder: Node3D = null
## A site's kept patch by its place (world x, z and radius): the site (PainterSites.site(), in the
## world's frame), its cell, its vertices, their uvs, their four custom arrays, its indices (from
## its own first vertex), the rect it lies in (the terrain's frame), and its indices as its cell's
## mesh last took them: the first vertex they were counted from, and the indices so counted.
var _held: Dictionary = {}
## The places of a cell's sites (a Dictionary used as an ordered set), and the cell's node.
var _sites: Dictionary = {}
var _nodes: Dictionary = {}
## What the next sync must build again whatever it holds: everything, or the sites in a rect of
## the terrain's samples.
var _whole := true
var _dirty := Rect2i()
## The terrain the kept patches were built on (its id and transform) and its grid's size, and the
## sites of the last sync.
var _ground: Array = []
var _last: Array = []


## Notes an edit of the terrain's samples in `rect`: the next sync builds the sites there again. A
## rect without area means the whole terrain (a new document).
func mark(rect: Rect2i) -> void:
	if not rect.has_area():
		_whole = true
	elif _dirty.has_area():
		_dirty = _dirty.merge(rect)
	else:
		_dirty = rect


## Brings the dabs up to `sites` (PainterSites.site(), in the world's frame) on `terrain`, drawn
## with `material` under `map`, and returns how many sites it built.
func sync(map: Node3D, terrain: AuthoredTerrain, material: ShaderMaterial, sites: Array) -> int:
	if not is_instance_valid(map) or not is_instance_valid(terrain) or terrain.document == null:
		clear()
		return 0
	var doc := terrain.document
	var ground := [terrain.get_instance_id(), terrain.transform, doc.samples_x(), doc.samples_z()]
	if ground != _ground or not is_instance_valid(_holder) or _holder.get_parent() != map:
		clear()
		_ground = ground
	var redo := _dirty.has_area()
	if not _whole and not redo and sites == _last:
		return 0
	_last = sites.duplicate()
	if _holder == null:
		if sites.is_empty():
			return 0
		_holder = Node3D.new()
		_holder.name = NODE_NAME
		map.add_child(_holder)
		_holder.transform = terrain.transform
	var grid := TerrainMeshBuilder.collision_heights(doc)
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var to_local := terrain.global_transform.affine_inverse()
	# The edited samples as metres of the terrain's frame.
	var edited := Rect2(Vector2(_dirty.position) * step - half, Vector2(_dirty.size) * step)
	var changed := {}
	var seen := {}
	var count := 0
	for site: Array in sites:
		var place := Vector3(site[0], site[1], site[2])
		seen[place] = true
		var was: Array = _held.get(place, [])
		if not was.is_empty():
			if was[SITE] == site and not _whole and not (redo and edited.intersects(was[RECT])):
				continue
			changed[was[CELL]] = true
		var local := site.duplicate()
		var at := to_local * Vector3(site[0], site[3], site[1])
		local[0] = at.x
		local[1] = at.z
		local[3] = at.y
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var custom: Array[PackedFloat32Array] = [
			PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()
		]
		var indices := PackedInt32Array()
		PainterSites.append_dab(
			local, grid, doc.samples_x(), doc.samples_z(), step, half, vertices, uvs, custom, indices
		)
		# A sample's step past the dab's reach: the patch ends on the grid's lines.
		var far := PainterSites.reach(site[2]) + maxf(step.x, step.y)
		var cell := Vector2i(floori(at.x / CELL_M), floori(at.z / CELL_M))
		var rect := Rect2(at.x - far, at.z - far, 2.0 * far, 2.0 * far)
		# Assigned at its place: a stone built again keeps its turn in its cell.
		_held[place] = [site, cell, vertices, uvs, custom, indices, rect, -1, indices]
		if not _sites.has(cell):
			_sites[cell] = {}
		(_sites[cell] as Dictionary)[place] = true
		changed[cell] = true
		count += 1
	for place: Vector3 in _held.keys():
		if seen.has(place):
			continue
		var cell: Vector2i = _held[place][CELL]
		(_sites[cell] as Dictionary).erase(place)
		_held.erase(place)
		changed[cell] = true
	_whole = false
	_dirty = Rect2i()
	for cell: Vector2i in changed:
		_put_together(cell, material)
	built += count
	return count


## Frees the dabs' node and forgets every site.
func clear() -> void:
	if is_instance_valid(_holder):
		_holder.queue_free()
	_holder = null
	_held.clear()
	_sites.clear()
	_nodes.clear()
	_ground = []
	_last = []
	_whole = true
	_dirty = Rect2i()


## The dabs' node (null while the map has no site), for the tests and the probes.
func holder() -> Node3D:
	return _holder if is_instance_valid(_holder) else null


## The sites held (PainterSites.site(), in the world's frame), for the probes.
func sites() -> Array:
	var out: Array = []
	for place: Vector3 in _held:
		out.append(_held[place][SITE])
	return out


## How many sites are held, and how many of them have a dab (a stone off this ground has none).
func counts() -> Vector2i:
	var drawn := 0
	for place: Vector3 in _held:
		if not (_held[place][VERTICES] as PackedVector3Array).is_empty():
			drawn += 1
	return Vector2i(_held.size(), drawn)


## One cell's mesh from its sites' kept patches (the node is freed when no site has a dab).
func _put_together(cell: Vector2i, material: ShaderMaterial) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom: Array[PackedFloat32Array] = [
		PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()
	]
	var indices := PackedInt32Array()
	for place: Vector3 in _sites.get(cell, {}):
		var kept: Array = _held[place]
		var first := vertices.size()
		vertices.append_array(kept[VERTICES])
		uvs.append_array(kept[UVS])
		for k in 4:
			custom[k].append_array(kept[CUSTOM][k])
		if kept[FIRST] != first:
			# Counted from this first vertex once; as they are while the patches before it stay.
			var placed := PackedInt32Array()
			for index: int in kept[INDICES]:
				placed.append(first + index)
			kept[FIRST] = first
			kept[PLACED] = placed
		indices.append_array(kept[PLACED])
	var node: MeshInstance3D = _nodes.get(cell, null)
	if vertices.is_empty():
		if is_instance_valid(node):
			node.queue_free()
		_nodes.erase(cell)
		if (_sites.get(cell, {}) as Dictionary).is_empty():
			_sites.erase(cell)
		return
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom[0]
	arrays[Mesh.ARRAY_CUSTOM1] = custom[1]
	arrays[Mesh.ARRAY_CUSTOM2] = custom[2]
	arrays[Mesh.ARRAY_CUSTOM3] = custom[3]
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, FORMAT)
	if not is_instance_valid(node):
		node = MeshInstance3D.new()
		node.name = "%s_%d_%d" % [NODE_NAME, cell.x, cell.y]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_holder.add_child(node)
		_nodes[cell] = node
	node.mesh = mesh
	node.material_override = material
	uploaded += 1
