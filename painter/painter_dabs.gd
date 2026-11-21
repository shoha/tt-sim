class_name PainterDabs
extends RefCounted
## The meshes of the small stones' dabs (card painter-terrain-dabs; PainterSites has the model, the
## outline and the geometry of one dab).
##
## PainterOcclusion finds the small stones (the sites) with its footprints and hands them here
## after every rebuild of its field. This host keeps one mesh per CELL_M square of the map that
## holds a site, all under one node beside the terrain (in the terrain's frame, drawn with the dabs'
## material, PainterSurfaces.dab_material(): the ground's shader body with the dab's code compiled
## in and every ground parameter the chunks' have; casting no shadow), and each site's patch as it
## was last built, so a
## change costs what changed:
## - a site that is new or changed, or that stands where the ground was edited since the last sync
##   (`mark`), is built: its outline on the ground there, and the terrain's surface under it;
## - a site that is gone is dropped;
## - a cell one of those lies in is put together again from its sites' kept arrays and uploaded;
##   every other cell is left as it is.
## What a sync looks at is found without walking every stone's patch: the sites are compared with
## the last sync's in their order (the same Array is the same stone: PainterOcclusion hands a
## scatter node's sites again as they were while it stands still), and an edit's rect is looked up
## in the cells it can touch.
## A stone is known by its place and radius, so one the ground moved under (its foot's height
## changed) keeps its turn in its cell: the patches after it keep their first vertex and their
## indices are appended as they are (adding an offset to every index of a cell was half the cost
## of an edit under a stroke).
## A stone's outline is not in its patch: each held site has a slot in one texture of the dab's
## shader (LOBES_PARAM, ROW slots a row), written when a slot's outline changes, and its patch's
## vertices carry the slot.
## Nothing here reads the sun: the mark's reach away from it is the shader's (a uniform), so the
## hour changing builds nothing (`built` counts the sites built, for the tests and the proof).
## A map without an authored terrain (a GLB map) has no heights to lay a dab on and gets none.
##
## MANAGED BY: PainterOcclusion (painter/painter_occlusion.gd). Classic never loads this file.

## What is kept of a site (the fields of its Array).
enum { SITE, CELL, VERTICES, UVS, CUSTOM, INDICES, RECT, FIRST, PLACED, SLOT, OWN }

const NODE_NAME := "PainterDabs"
## Metres a cell of dabs is across (one mesh, one draw).
const CELL_M := 16.0
## The mesh format's flags: one custom channel of four floats (PainterSites.append_dab's CUSTOM3).
const FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT
## The dab shader's texture of the stones' outlines (painter_ground_body dab_lobes): a stone's slot
## is LOBE_TEXELS RGBA32F texels, ROW slots a row (painter_ground_body DAB_ROW: keep the two equal).
const LOBES_PARAM := &"dab_lobes"
const ROW := 256
const LOBE_TEXELS := 3
## Metres past its stone's cell a patch can lie (the largest stone's reach and a sample's step).
const REACH_MAX_M := 2.0

## The sites built since this host was made, and the cells put together.
var built := 0
var uploaded := 0
## The last sync's parts (milliseconds): the sites compared and built, and the cells put together
## and uploaded (with how many), for the stats and the edit-cost probe.
var parts := {}

var _holder: Node3D = null
## A site's kept patch by its place (world x, z and radius): the site (PainterSites.site(), in the
## world's frame), its cell, its vertices, their uvs, their four custom arrays, its indices (from
## its own first vertex), the rect it lies in (the terrain's frame), its indices as its cell's
## mesh last took them (the first vertex they were counted from, and the indices so counted), its
## slot and its outline (PainterSites.outline, in the terrain's frame).
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
## The stones' outlines by slot (PainterSites.outline, in the terrain's frame), their texture, the
## slots given out and those free again.
var _lobes := PackedFloat32Array()
var _lobe_texture: ImageTexture = null
var _slots := 0
var _free: Array[int] = []


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
	var t_sites := Time.get_ticks_usec()
	var redo := _dirty.has_area()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	# The edited samples as metres of the terrain's frame.
	var edited := Rect2(Vector2(_dirty.position) * step - half, Vector2(_dirty.size) * step)
	var changed := {}
	var todo := _to_look_at(sites, redo, edited, changed)
	_last = sites.duplicate()
	if todo.is_empty() and changed.is_empty():
		_whole = false
		_dirty = Rect2i()
		parts = {}
		return 0
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = NODE_NAME
		map.add_child(_holder)
		_holder.transform = terrain.transform
	var grid := TerrainMeshBuilder.collision_heights(doc)
	var to_local := terrain.global_transform.affine_inverse()
	var count := 0
	var fresh := 0
	for site: Array in todo:
		var place := Vector3(site[0], site[1], site[2])
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
		if local.size() > PainterSites.BOTTOM:
			var under := Vector3(site[0], site[PainterSites.BOTTOM], site[1])
			local[PainterSites.BOTTOM] = (to_local * under).y
		# Its outline on this ground (none: it does not stand on it), and the ground under that.
		var own := PainterSites.outline(local, grid, doc.samples_x(), doc.samples_z(), step, half)
		# A stone built again keeps its slot and (assigned at its place below) its turn in its cell.
		var slot: int = was[SLOT] if not was.is_empty() else _take_slot()
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var custom := PackedFloat32Array()
		var indices := PackedInt32Array()
		PainterSites.append_dab(
			own,
			local,
			grid,
			doc.samples_x(),
			doc.samples_z(),
			step,
			half,
			vertices,
			uvs,
			custom,
			indices,
			slot
		)
		if not own.is_empty() and (was.is_empty() or own != was[OWN]):
			_put_lobes(slot, own)
			fresh += 1
		# A sample's step past the dab's reach: a patch ends inside the cells its square touches.
		var far := maxf(step.x, step.y) + (PainterSites.reach(own) if not own.is_empty() else 0.0)
		var mid := Vector2(own[0], own[1]) if not own.is_empty() else Vector2(at.x, at.z)
		var cell := Vector2i(floori(at.x / CELL_M), floori(at.z / CELL_M))
		var rect := Rect2(mid.x - far, mid.y - far, 2.0 * far, 2.0 * far)
		_held[place] = [site, cell, vertices, uvs, custom, indices, rect, -1, indices, slot, own]
		if not _sites.has(cell):
			_sites[cell] = {}
		(_sites[cell] as Dictionary)[place] = true
		changed[cell] = true
		count += 1
	_whole = false
	_dirty = Rect2i()
	var t_cells := Time.get_ticks_usec()
	# The outlines are sent only when one changed.
	if fresh > 0:
		_upload_lobes()
	if _lobe_texture != null and material.get_shader_parameter(LOBES_PARAM) != _lobe_texture:
		material.set_shader_parameter(LOBES_PARAM, _lobe_texture)
	for cell: Vector2i in changed:
		_put_together(cell, material)
	parts = {
		"sites_ms": (t_cells - t_sites) / 1000.0,
		"cells_ms": (Time.get_ticks_usec() - t_cells) / 1000.0,
		"cells": changed.size(),
	}
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
	_lobes = PackedFloat32Array()
	_slots = 0
	_free.clear()


## The dabs' node (null while the map has no site), for the tests and the probes.
func holder() -> Node3D:
	return _holder if is_instance_valid(_holder) else null


## The sites held (PainterSites.site(), in the world's frame), for the probes.
func sites() -> Array:
	var out: Array = []
	for place: Vector3 in _held:
		out.append(_held[place][SITE])
	return out


## The outlines held (PainterSites.outline, in the terrain's frame; empty for a stone off this
## ground), in the order of sites(), for the probes.
func outlines() -> Array:
	var out: Array = []
	for place: Vector3 in _held:
		out.append(_held[place][OWN])
	return out


## How many sites are held, and how many of them have a dab (a stone off this ground has none).
func counts() -> Vector2i:
	var drawn := 0
	for place: Vector3 in _held:
		if not (_held[place][VERTICES] as PackedVector3Array).is_empty():
			drawn += 1
	return Vector2i(_held.size(), drawn)


## The sites of `sites` this sync must look at: all of them when everything is built again or
## their number changed (the gone are dropped, their cells marked in `changed`); else those that
## differ from the last sync's at the same turn, and, when the ground was edited (`redo`), the held
## ones whose patch lies in `edited` (metres of the terrain's frame), found by cell.
func _to_look_at(sites: Array, redo: bool, edited: Rect2, changed: Dictionary) -> Array:
	if _whole or sites.size() != _last.size():
		_drop_gone(sites, changed)
		return sites
	var todo: Array = []
	var seen := {}
	for i in sites.size():
		var site: Array = sites[i]
		if is_same(site, _last[i]) or site == _last[i]:
			continue
		todo.append(site)
		seen[Vector3(site[0], site[1], site[2])] = true
	if not todo.is_empty():
		_drop_gone(sites, changed)
	if redo:
		var grown := edited.grow(REACH_MAX_M)
		var from := Vector2i((grown.position / CELL_M).floor())
		var to := Vector2i((grown.end / CELL_M).floor())
		for cell_z in range(from.y, to.y + 1):
			for cell_x in range(from.x, to.x + 1):
				for place: Vector3 in _sites.get(Vector2i(cell_x, cell_z), {}):
					var kept: Array = _held[place]
					if not seen.has(place) and edited.intersects(kept[RECT]):
						todo.append(kept[SITE])
	return todo


## One cell's mesh from its sites' kept patches (the node is freed when no site has a dab).
func _put_together(cell: Vector2i, material: ShaderMaterial) -> void:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom := PackedFloat32Array()
	var indices := PackedInt32Array()
	for place: Vector3 in _sites.get(cell, {}):
		var kept: Array = _held[place]
		var first := vertices.size()
		vertices.append_array(kept[VERTICES])
		uvs.append_array(kept[UVS])
		custom.append_array(kept[CUSTOM])
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
	arrays[Mesh.ARRAY_CUSTOM3] = custom
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


## A slot in the texture of outlines: one freed by a stone that went, else the next.
func _take_slot() -> int:
	if not _free.is_empty():
		return _free.pop_back()
	_slots += 1
	return _slots - 1


## Writes `own` (PainterSites.outline: LOBE_TEXELS texels of four floats) at `slot`.
func _put_lobes(slot: int, own: PackedFloat32Array) -> void:
	var rows := slot / ROW + 1
	if _lobes.size() < rows * ROW * LOBE_TEXELS * 4:
		_lobes.resize(rows * ROW * LOBE_TEXELS * 4)
	var at := slot * LOBE_TEXELS * 4
	for k in mini(own.size(), LOBE_TEXELS * 4):
		_lobes[at + k] = own[k]


## The stones' outlines as the ground's shader reads them (null before the first): slot s's texel
## k is (LOBE_TEXELS * (s % ROW) + k, s / ROW).
func lobe_image() -> Image:
	var rows := _lobes.size() / (ROW * LOBE_TEXELS * 4)
	if rows == 0:
		return null
	return Image.create_from_data(
		ROW * LOBE_TEXELS, rows, false, Image.FORMAT_RGBAF, _lobes.to_byte_array()
	)


## Sends the outlines to the dab shader's texture (its image replaced: 12 KB a row; updated in
## place while the rows are as many).
func _upload_lobes() -> void:
	var image := lobe_image()
	if image == null:
		return
	if _lobe_texture == null:
		_lobe_texture = ImageTexture.create_from_image(image)
	elif Vector2i(_lobe_texture.get_size()) == image.get_size():
		_lobe_texture.update(image)
	else:
		_lobe_texture.set_image(image)


## Forgets the stones that are not in `sites` (their slots freed for the next new ones), marking
## their cells in `changed`.
func _drop_gone(sites: Array, changed: Dictionary) -> void:
	if sites.size() == _held.size() and sites == _last:
		return
	var seen := {}
	for site: Array in sites:
		seen[Vector3(site[0], site[1], site[2])] = true
	for place: Vector3 in _held.keys():
		if seen.has(place):
			continue
		var gone: Vector2i = _held[place][CELL]
		(_sites[gone] as Dictionary).erase(place)
		_free.append(_held[place][SLOT])
		_held.erase(place)
		changed[gone] = true
