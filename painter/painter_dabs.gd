class_name PainterDabs
extends RefCounted
## The meshes of the dabs of the bodies that stand on the ground: small stones (card
## painter-terrain-dabs) and, on an authored terrain, every boulder, rock group and log (card
## painter-terrain-contact). PainterSites has the model, the outline and the geometry of one dab.
##
## PainterOcclusion finds the bodies (the sites) with its footprints and hands them here
## after every rebuild of its field. This host keeps one mesh per CELL_M square of the map that
## holds a site, all under one node beside the terrain (in the terrain's frame, drawn with the dabs'
## material, PainterSurfaces.dab_material(): the ground's shader body with the dab's code compiled
## in and every ground parameter the chunks' have; casting no shadow), and each site's patch as it
## was last built, so a change costs what changed.
##
## A dab is one function of two things: its site (PainterSites.site(), the stone's place, size,
## foot and measured sections) and the terrain's heights in the samples its outline and its patch
## read (READ, kept with it). So each sync matches the sites it is handed to the held ones by place
## (world x, z and radius) and keeps every dab whose site is equal and whose samples did not
## change; it builds only the new and the changed ones and drops the gone ones. Which samples
## changed is not taken on trust: the host keeps the heights its patches were built on and, where
## an edit was marked since (`mark`: a rect of samples, or the whole terrain), compares them row by
## row with the terrain's. So a whole new set of the same stones (the scatter made again at a
## stroke's end, an undo, a level's rebuild) or a mark of the whole terrain whose heights did not
## move (the skirt built again) builds nothing; a sculpt builds the stones on what it moved.
## The sites are first compared with the last sync's in their order (the same Array is the same
## stone: PainterOcclusion hands a scatter node's sites again as they were while it stands still),
## so a sync with nothing changed walks no held stone.
## A cell one of the built or dropped stones lies in is put together again from its sites' kept
## arrays and uploaded; every other cell is left as it is. A stone built again keeps its turn in its
## cell, so the patches after it keep their first vertex and their indices are appended as they
## are (adding an offset to every index of a cell was half the cost of an edit under a stroke).
## A stone's outline is not in its patch: each held site has a slot in one texture of the dab's
## shader (LOBES_PARAM, ROW slots a row), written when a slot's outline changes, and its patch's
## vertices carry the slot. A kept dab keeps its slot; a new one takes a freed slot first. So a
## dab equals a whole rebuild's bit for bit but for its slot's number and its turn in its cell.
## Nothing here reads the sun: the mark's reach away from it is the shader's (a uniform), so the
## hour changing builds nothing (`built` counts the sites built, for the tests and the proof).
## A map without an authored terrain (a GLB map) has no heights to lay a dab on and gets none.
##
## MANAGED BY: PainterOcclusion (painter/painter_occlusion.gd). Classic never loads this file.

## What is kept of a site (the fields of its Array).
enum { SITE, CELL, VERTICES, UVS, CUSTOM, INDICES, READ, FIRST, PLACED, SLOT, OWN }

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

## The sites built since this host was made, and the cells put together.
var built := 0
var uploaded := 0
## The last sync's parts (milliseconds): the ground compared (and its rows that changed), the sites
## matched and built, and the cells put together and uploaded (with how many), for the stats and
## the edit-cost probe.
var parts := {}

var _holder: Node3D = null
## A site's kept patch by its place (world x, z and radius): the site (PainterSites.site(), in the
## world's frame), its cell, its vertices, their uvs, their four custom arrays, its indices (from
## its own first vertex), the samples its outline and patch read (a rect of the terrain's grid),
## its indices as its cell's mesh last took them (the first vertex they were counted from, and the
## indices so counted), its slot and its outline (PainterSites.outline, in the terrain's frame).
var _held: Dictionary = {}
## The places of a cell's sites (a Dictionary used as an ordered set), and the cell's node.
var _sites: Dictionary = {}
var _nodes: Dictionary = {}
## Where the next sync compares the terrain's heights with those the patches were built on: all of
## them, or the samples in a rect.
var _whole := true
var _dirty := Rect2i()
## The terrain the kept patches were built on (its id, transform, grid size, step and extent), its
## heights then, the sites of the last sync and the material the cells are drawn with.
var _ground: Array = []
var _grid := PackedFloat32Array()
var _last: Array = []
var _material: ShaderMaterial = null
## The stones' outlines by slot (PainterSites.outline, in the terrain's frame), their texture, the
## slots given out and those free again.
var _lobes := PackedFloat32Array()
var _lobe_texture: ImageTexture = null
var _slots := 0
var _free: Array[int] = []
## Metres past its body's cell a patch can lie: the furthest reach of any body built since the
## last clear() (a pebble's is a quarter of a metre, a long log's several) and a sample's step.
var _reach_max := 0.0


## Notes an edit of the terrain's samples in `rect`: the next sync compares the heights there with
## those its patches were built on. A rect without area means the whole terrain (a new document,
## the terrain built again).
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
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var ground := [terrain.get_instance_id(), terrain.transform, columns, rows, step, half]
	if ground != _ground or not is_instance_valid(_holder) or _holder.get_parent() != map:
		clear()
		_ground = ground
	var t_ground := Time.get_ticks_usec()
	var grid := TerrainMeshBuilder.collision_heights(doc)
	var moved := _ground_moved(grid, columns, rows)
	# A copy: the grid is the document's own array, which a sculpt writes in place.
	if _whole or _dirty.has_area() or _grid.size() != grid.size():
		_grid = grid.duplicate()
	_whole = false
	_dirty = Rect2i()
	var t_sites := Time.get_ticks_usec()
	var changed := {}
	var todo := _to_look_at(sites, moved, step, half, changed)
	_last = sites.duplicate()
	if material != _material:
		for cell: Vector2i in _nodes:
			(_nodes[cell] as MeshInstance3D).material_override = material
		_material = material
	if todo.is_empty() and changed.is_empty():
		parts = {}
		return 0
	if _holder == null:
		_holder = Node3D.new()
		_holder.name = NODE_NAME
		map.add_child(_holder)
		_holder.transform = terrain.transform
	var to_local := terrain.global_transform.affine_inverse()
	var reach_step := maxf(step.x, step.y)
	var count := 0
	var fresh := 0
	for site: Array in todo:
		var place := _place(site)
		var was: Array = _held.get(place, [])
		if not was.is_empty():
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
		var own := PainterSites.outline(local, grid, columns, rows, step, half)
		# A stone built again keeps its slot and (assigned at its place below) its turn in its cell.
		var slot: int = was[SLOT] if not was.is_empty() else _take_slot()
		var vertices := PackedVector3Array()
		var uvs := PackedVector2Array()
		var custom := PackedFloat32Array()
		var indices := PackedInt32Array()
		PainterSites.append_dab(
			own, local, grid, columns, rows, step, half, vertices, uvs, custom, indices, slot
		)
		if not own.is_empty() and (was.is_empty() or own != was[OWN]):
			_put_lobes(slot, own)
			fresh += 1
		# The samples it read: the patch's square a sample's step wide of the dab's reach, and
		# round the stone the heights its outline took (its middle, and its foot's width across).
		var far := reach_step + (PainterSites.reach(own) if not own.is_empty() else 0.0)
		_reach_max = maxf(_reach_max, far)
		var mid := Vector2(own[0], own[1]) if not own.is_empty() else Vector2(at.x, at.z)
		var near := (own[2] if not own.is_empty() else 0.0) + 2.0 * reach_step
		var box := Rect2(mid.x - far, mid.y - far, 2.0 * far, 2.0 * far).merge(
			Rect2(at.x - near, at.z - near, 2.0 * near, 2.0 * near)
		)
		var read := _samples_of(box, step, half, columns, rows)
		var cell := Vector2i(floori(at.x / CELL_M), floori(at.z / CELL_M))
		_held[place] = [site, cell, vertices, uvs, custom, indices, read, -1, indices, slot, own]
		if not _sites.has(cell):
			_sites[cell] = {}
		(_sites[cell] as Dictionary)[place] = true
		changed[cell] = true
		count += 1
	var t_cells := Time.get_ticks_usec()
	# The outlines are sent only when one changed.
	if fresh > 0:
		_upload_lobes()
	if _lobe_texture != null and material.get_shader_parameter(LOBES_PARAM) != _lobe_texture:
		material.set_shader_parameter(LOBES_PARAM, _lobe_texture)
	for cell: Vector2i in changed:
		_put_together(cell, material)
	parts = {
		"ground_ms": (t_sites - t_ground) / 1000.0,
		"rows": moved.size(),
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
	_grid = PackedFloat32Array()
	_last = []
	_material = null
	_whole = true
	_dirty = Rect2i()
	_lobes = PackedFloat32Array()
	_slots = 0
	_free.clear()
	_reach_max = 0.0


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


## The place a site is known by: its world x and z and its radius.
static func _place(site: Array) -> Vector3:
	return Vector3(site[0], site[1], site[2])


## Where `grid` differs from the heights the kept patches were built on, looked at only where an
## edit was marked since (everywhere after a mark of the whole terrain) and while a patch is held:
## per row of samples, the first and last column that differ.
func _ground_moved(grid: PackedFloat32Array, columns: int, rows: int) -> Dictionary:
	var out := {}
	if _held.is_empty() or not (_whole or _dirty.has_area()):
		return out
	if _grid.size() != grid.size():
		for j in rows:
			out[j] = Vector2i(0, columns - 1)
		return out
	var area := Rect2i(0, 0, columns, rows)
	if not _whole:
		area = _dirty.intersection(area)
	elif grid == _grid:
		return out
	for j in range(area.position.y, area.end.y):
		var a := j * columns + area.position.x
		var b := j * columns + area.end.x
		if grid.slice(a, b) == _grid.slice(a, b):
			continue
		var first := a
		while grid[first] == _grid[first]:
			first += 1
		var last := b - 1
		while grid[last] == _grid[last]:
			last -= 1
		out[j] = Vector2i(first - j * columns, last - j * columns)
	return out


## The sites of `sites` this sync must build: each that no held stone at its place equals (a new
## stone, or one that changed), and each held one whose samples `moved` (_ground_moved). The held
## stones not in `sites` are dropped, their slots freed and their cells marked in `changed`.
## While the scatter hands the same sites again in their order only those that differ from the
## last sync's at their turn are looked at; another number of them is matched whole, by place.
func _to_look_at(
	sites: Array, moved: Dictionary, step: Vector2, half: Vector2, changed: Dictionary
) -> Array:
	var present := {}
	var gone: Array = []
	if sites.size() == _last.size():
		for i in sites.size():
			var site: Array = sites[i]
			var was: Array = _last[i]
			if is_same(site, was) or site == was:
				continue
			present[_place(site)] = site
			gone.append(_place(was))
	else:
		for site: Array in sites:
			present[_place(site)] = site
		gone = _held.keys()
	for place: Vector3 in gone:
		if present.has(place) or not _held.has(place):
			continue
		var cell: Vector2i = _held[place][CELL]
		(_sites[cell] as Dictionary).erase(place)
		_free.append(_held[place][SLOT])
		_held.erase(place)
		changed[cell] = true
	var todo: Array = []
	var seen := {}
	for place: Vector3 in present:
		var site: Array = present[place]
		var kept: Array = _held.get(place, [])
		if kept.is_empty() or kept[SITE] != site:
			todo.append(site)
			seen[place] = true
	if moved.is_empty():
		return todo
	# The held stones on the samples that moved, found by the cells those can reach.
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for j: int in moved:
		var span: Vector2i = moved[j]
		lo = Vector2i(mini(lo.x, span.x), mini(lo.y, j))
		hi = Vector2i(maxi(hi.x, span.y), maxi(hi.y, j))
	var pad := Vector2.ONE * _reach_max
	var from := Vector2i(((Vector2(lo) * step - half - pad) / CELL_M).floor())
	var to := Vector2i(((Vector2(hi + Vector2i.ONE) * step - half + pad) / CELL_M).floor())
	for cell_z in range(from.y, to.y + 1):
		for cell_x in range(from.x, to.x + 1):
			for place: Vector3 in _sites.get(Vector2i(cell_x, cell_z), {}):
				var kept: Array = _held[place]
				if not seen.has(place) and _reads_moved(kept[READ], moved):
					todo.append(kept[SITE])
					seen[place] = true
	return todo


## Whether any sample of `read` (a rect of the grid) is in `moved` (_ground_moved).
static func _reads_moved(read: Rect2i, moved: Dictionary) -> bool:
	for j in range(read.position.y, read.end.y):
		var span: Vector2i = moved.get(j, Vector2i(1 << 30, -1))
		if span.x < read.end.x and span.y >= read.position.x:
			return true
	return false


## The grid's samples (`columns` by `rows`, `step` metres apart, centred: `half` is half the
## extent) whose cells `box` (metres of the terrain's frame) touches, both corners of each.
static func _samples_of(
	box: Rect2, step: Vector2, half: Vector2, columns: int, rows: int
) -> Rect2i:
	var i0 := clampi(floori((box.position.x + half.x) / step.x), 0, columns - 1)
	var i1 := clampi(ceili((box.end.x + half.x) / step.x), i0, columns - 1)
	var j0 := clampi(floori((box.position.y + half.y) / step.y), 0, rows - 1)
	var j1 := clampi(ceili((box.end.y + half.y) / step.y), j0, rows - 1)
	return Rect2i(i0, j0, i1 - i0 + 1, j1 - j0 + 1)


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
