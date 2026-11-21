class_name PainterOcclusion
extends RefCounted

## The painted ground's contact occlusion (card painter-grounding; painter.md "Grounding").
##
## The sun's shadow darkens the ground only along the sun's direction, so under a crown, round a
## trunk, a rock, a wall or a token's feet the ground stayed as bright as the open meadow and
## everything read as set on top of the landscape. This host writes the footprints of what
## stands on the ground into a small field the painted ground shader reads with one fetch:
##   r  POOL, the broad shade under and round a crown, a bush, a rock, a house;
##   g  CORE, the tight seam at a trunk's foot, a rock's or a wall's base (a soil tone).
## The field is built on the CPU once per change (the painted trees' install, the scatter's
## applied cells, a structure added or removed, a ground edit), never per frame, at TEXEL_M a
## texel over the map's extent: each footprint is a coverage in [0, 1] whose 0.5 contour is the
## footprint's nominal edge (`cover`), the texels take the maximum. The shader thresholds it
## through the ground's own brush noise, so a pool is a flat stroke-edged shape in the ground's
## deeper shade, not a blur (the painter's ground is flat shapes with firm wandering edges).
## The pool shows ONLY where the ground is in shade (card painter-tree-ground): what stands on the
## ground shuts out the sky, not the sun, so the pool deepens each cast shadow at its root and the
## sunlit ground beside a trunk stays lit (a pool there, centred on the trunk while the shadow ran
## away from the sun, read as a second light). The seam stays in the sun too, lighter, and the
## shader reads the field a little toward the sun so the seam leans to the shadow's side.
## Every pool follows its thing's own shape (card painter-pool-shapes): a crown's disc, also for the
## trees the painter does not grow (acacia, palm, dead tree: scatter solids by their bark); a rock's
## or a log's rounded box; a building's own plan (PainterFootprint: its walls' feet, never its yard
## or its roof's overhang) as a rounded rectangle whose reach grows with its size and height. The
## yard's skirt and path (painter_yard_ground) read the field too, so the shade at a wall's foot
## shows through the wash laid over it.
## A scatter solid's footprint is each of its BODIES' own (card painter-rocks-forms): a mesh of
## three stones is three islands (`islands`), each with a seam and a pool no wider than itself
## (`solid_reach`), so a scatter of stones is three small marks, not one oval three times the
## stones' size. A solid's
## footprint also carries the height of its foot (b, a: the foot's height times a weight, and the
## weight, one over its vertical reach), and the ground shows the mark only within that reach of the
## foot: the field is a plan view, and under stones at a cliff's edge the mark ran down the wall. A
## footprint too small for the field to hold (under half a texel) is not drawn at all: its cast
## shadow and its darker foot ground it.
## Tokens are the only moving things: their feet discs go in a small uniform array refreshed
## when one moved (one pass over the token group a frame, no field rebuild).
## Base gradients (the second half of the look): a trunk, a rock or a log is a step darker over
## its lowest metre, so it grows out of the ground (`base_dark`, in the tree block-in and the
## selector), which the shaders take as a uniform.
##
## MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd). Classic never loads this file.

## Metres a field texel covers (0.5 until card painter-rocks-forms: a stone's own mark is about
## half a metre across, which a half-metre texel cannot place or keep apart from its neighbour's).
const TEXEL_M := 0.25
## The field's channels: the pool, the seam, the foot's height times its weight, the weight.
const CHANNELS := 4
const POOL_CH := 0
const CORE_CH := 1
const FOOT_CH := 2
## A scatter solid's seam and pool reach (metres past its body): at most these, and at most
## SEAM_BODY and POOL_BODY of the body's narrower half, so a mark is never wider than its stone.
const SEAM_M := 0.22
const SEAM_BODY := 0.5
const POOL_BODY := 1.0
## The most bodies of one mesh that get their own footprint (the largest), the largest mesh (in
## vertices) that is split at all, and the grid (metres) its vertices are welded on.
const MAX_ISLANDS := 12
const MAX_SPLIT_VERTICES := 6000
const WELD_M := 0.002
## Seconds of quiet before a changed map's field is rebuilt (growth installs trees every frame).
const REBUILD_DELAY_S := 0.3
const MAX_TOKENS := 32
## Metres of empty field kept round the map's extent. The shader samples the field with a clamped
## edge, so a footprint cut by the field's last row (a tree near the map's edge) would be repeated
## outward as a thin dark streak running off the map (card painter-trunk-streak); the margin holds
## every footprint whole (a big crown's disc reaches about 4 m) and leaves the edge row empty.
const EDGE_PAD_M := 8.0
## A scatter solid taller than this (metres) and than TREE_SLENDER of its crown's half width is a
## tree (a dead tree carries no leaf surface to tell it by): a crown's disc, not a box.
const TREE_M := 2.0
const TREE_SLENDER := 1.6
## The seam at a building's walls (metres past them): 0.3 read as nothing at zoom 16 through the
## yard's wash (card painter-tree-ground).
const WALL_SEAM_M := 0.45
## A trunk's seam: TRUNK_SEAM_M plus TRUNK_SEAM_K of the tree's height (metres, its nominal
## radius). It shows in the sun too, so it is a small dab at the foot; at 0.55 m + 5 % it was a
## metre-wide disc that read as a grey plate beside the trunk (card painter-tree-ground).
const TRUNK_SEAM_M := 0.3
const TRUNK_SEAM_K := 0.025
## The yard's ground (PainterBuildings' stand-in of `dressing_ground`), which reads the pool too.
const YARD_KEY := "dressing_ground"
## The sheet's numbers read here (all DEFAULT_NUMBERS).
const POOL := "occ-pool"
const CORE := "occ-core"
const DARK := "occ-dark"
const SOIL := "occ-soil"
const COOL := "occ-cool"
const SHADE := "occ-shade"
const BASE := "base-dark"

## Which of the two looks is on (the comparison probe switches them; both on is the shipped one).
var ground_on := true
var base_on := true

var _surfaces: RefCounted = null
var _map: Node3D = null
var _origin := Vector2.ZERO
var _size := Vector2i.ZERO
var _tex: ImageTexture = null
var _queued := false
var _tokens := PackedVector4Array()
var _token_bounds: Dictionary = {}
var _watching := false
var _numbers: Dictionary = {}
var _count := 0
## A scatter mesh's bodies (islands()), by the mesh's instance id.
var _bodies: Dictionary = {}


## Starts following `map` for `surfaces` (a PainterSurfaces); `numbers` is read by retone().
func bind(surfaces: RefCounted, map: Node3D) -> void:
	_surfaces = surfaces
	_map = map
	_watch()
	queue()


## Forgets the map and clears the ground's field and tokens.
func release() -> void:
	_map = null
	_tex = null
	_tokens = PackedVector4Array()
	_token_bounds.clear()
	_bodies.clear()
	_clear_ground()
	_surfaces = null


## The number of footprints in the last field (tests and the notes).
func footprints() -> int:
	return _count


## Asks for a rebuild of the field after REBUILD_DELAY_S of quiet.
func queue() -> void:
	if _queued or _map == null:
		return
	_queued = true
	var tree := Engine.get_main_loop() as SceneTree
	tree.create_timer(REBUILD_DELAY_S).timeout.connect(rebuild)


## Sets the look's tones from the sheet (the mood's numbers at the sun's height).
func retone(sheet: Dictionary, mood: String, elevation: float) -> void:
	_numbers.clear()
	for key: String in [POOL, CORE, DARK, SOIL, COOL, SHADE, BASE]:
		_numbers[key] = PainterSheet.number(sheet, mood, key, elevation)
	_apply()


## Switches the ground look and the base gradients (the comparison sheet's modes).
func set_mode(ground: bool, base: bool) -> void:
	ground_on = ground
	base_on = base
	_apply()


func _apply() -> void:
	if _surfaces == null or _numbers.is_empty():
		return
	var cool: float = _numbers[COOL]
	var tint := Vector4(1.0 - cool, 1.0, 1.0 - cool * 0.35, _numbers[SHADE])
	var gk := 1.0 if ground_on else 0.0
	var tk := 1.0 if (ground_on or base_on) else 0.0
	var k := Vector4(
		float(_numbers[POOL]) * gk, float(_numbers[CORE]) * gk, _numbers[DARK], _numbers[SOIL]
	)
	for material: ShaderMaterial in _surfaces.call("ground_materials"):
		material.set_shader_parameter(&"occ_k", k)
		material.set_shader_parameter(&"occ_tint", tint)
		var ring := Vector2(float(_numbers[CORE]), float(_numbers[POOL])) * tk
		material.set_shader_parameter(&"tok_k", ring)
	var yard := _yard_material()
	if yard != null:
		yard.set_shader_parameter(&"occ_k", k)
		yard.set_shader_parameter(&"occ_tint", tint)
	var base := float(_numbers[BASE]) * (1.0 if base_on else 0.0)
	for material: ShaderMaterial in _surfaces.call("base_materials"):
		material.set_shader_parameter(&"base_dark", base)


func _clear_ground() -> void:
	if _surfaces == null:
		return
	var zero := PackedVector4Array()
	zero.resize(MAX_TOKENS)
	for material: ShaderMaterial in _surfaces.call("ground_materials"):
		material.set_shader_parameter(&"occ_present", false)
		material.set_shader_parameter(&"tok_n", 0)
		material.set_shader_parameter(&"tok", zero)
	var yard := _yard_material()
	if yard != null:
		yard.set_shader_parameter(&"occ_present", false)
	for material: ShaderMaterial in _surfaces.call("base_materials"):
		material.set_shader_parameter(&"base_dark", 0.0)


## The yard ground's stand-in (one shared by every structure), null before a yard was painted.
func _yard_material() -> ShaderMaterial:
	var holder: Object = _surfaces.call("buildings") if _surfaces != null else null
	if holder == null:
		return null
	return holder.call("material_of", YARD_KEY) as ShaderMaterial


# ---------------------------------------------------------------- the field


## Rebuilds the field from the map's trees, scatter solids and structures, and hands it to the
## ground. Pure CPU, one pass; about a millisecond for a hundred footprints.
func rebuild() -> void:
	_queued = false
	if _map == null or _surfaces == null:
		return
	var extent: Vector2 = _surfaces.call("map_extent")
	if extent.x <= 0.0 or extent.y <= 0.0:
		return
	var layout := field_layout(extent)
	_origin = layout.position
	_size = Vector2i(roundi(layout.size.x), roundi(layout.size.y))
	var data := PackedFloat32Array()
	data.resize(_size.x * _size.y * CHANNELS)
	_count = 0
	_add_trees(data)
	_add_solids(data)
	_add_structures(data)
	# Floats as written, then half floats (one native pass; no loop over the texels here).
	var image := Image.create_from_data(
		_size.x, _size.y, false, Image.FORMAT_RGBAF, data.to_byte_array()
	)
	image.convert(Image.FORMAT_RGBAH)
	if _tex == null or _tex.get_size() != Vector2(_size) or _tex.get_format() != image.get_format():
		_tex = ImageTexture.create_from_image(image)
	else:
		_tex.update(image)
	var targets: Array[ShaderMaterial] = _surfaces.call("ground_materials")
	var yard := _yard_material()
	if yard != null:
		targets.append(yard)
	for material: ShaderMaterial in targets:
		material.set_shader_parameter(&"occ_map", _tex)
		material.set_shader_parameter(&"occ_origin", _origin)
		material.set_shader_parameter(&"occ_step", TEXEL_M)
		material.set_shader_parameter(&"occ_present", true)
	_apply()


## The field's layout for a map `extent` metres across: position the world (x, z) of its first
## texel's corner, size its width and height in texels (the extent plus EDGE_PAD_M on every side).
static func field_layout(extent: Vector2) -> Rect2:
	var pad := Vector2(EDGE_PAD_M, EDGE_PAD_M)
	var cells := ((extent + pad * 2.0) / TEXEL_M).ceil()
	return Rect2(-extent * 0.5 - pad, cells)


## The painted trees and bushes: a pool under the crown's projection (centre halfway from the
## trunk to the crown's middle), and a core at the trunk's foot.
func _add_trees(data: PackedFloat32Array) -> void:
	var host: Object = _surfaces.call("trees")
	if host == null:
		return
	var trees: Dictionary = host.get("trees")
	for key: Vector3i in trees:
		var t: Dictionary = trees[key]
		var p: Vector3 = t["pos"]
		var box: AABB = (t["d"] as Dictionary)["aabb"]
		var half := maxf(box.size.x, box.size.z) * 0.5
		var mid := box.get_center()
		_count += 1
		if bool(t["bush"]):
			# A bush: its own footprint and a thin seam round it.
			_disc(data, POOL_CH, p.x + mid.x, p.z + mid.z, half * 1.35)
			_disc(data, CORE_CH, p.x + mid.x, p.z + mid.z, half * 0.95)
			continue
		_tree(data, p, Vector3(p.x + mid.x, p.y, p.z + mid.z), half, box.size.y)


## Rocks, logs and stumps of the scatter: each body of the mesh (`islands`) a box rounded by its
## narrower half (a stone round, a log a capsule), a pool round it and a seam at its foot, neither
## wider than the body (`solid_reach`), shown only near the height of its foot. A tree the painter
## does not grow (its mesh carries a leaf surface beside its bark, or it is tall and slender:
## TREE_M) gets a crown's disc.
func _add_solids(data: PackedFloat32Array) -> void:
	var meshes: Dictionary = _surfaces.call("solid_meshes")
	if meshes.is_empty():
		return
	for scatter: Node in _surfaces.call("scatters"):
		if not is_instance_valid(scatter):
			continue
		for node: Node in scatter.find_children("*", "MultiMeshInstance3D", true, false):
			var mm := (node as MultiMeshInstance3D).multimesh
			if mm == null or mm.mesh == null or not meshes.has(mm.mesh.get_instance_id()):
				continue
			var id := mm.mesh.get_instance_id()
			var leafy := bool(meshes[id])
			var box := mm.mesh.get_aabb()
			if not _bodies.has(id):
				_bodies[id] = islands(mm.mesh)
			var bodies: Array[AABB] = _bodies[id]
			var to_world := (node as Node3D).global_transform
			for i in mm.instance_count:
				var xf := to_world * mm.get_instance_transform(i)
				var scale := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
				var whole := Vector2(box.size.x * scale.x, box.size.z * scale.z) * 0.5
				var height := box.size.y * scale.y
				_count += 1
				if leafy or (height > TREE_M and height > TREE_SLENDER * maxf(whole.x, whole.y)):
					_tree(data, xf.origin, xf * box.get_center(), maxf(whole.x, whole.y), height)
					continue
				var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
				for body: AABB in bodies:
					_solid(data, xf * body.get_center(), yaw, body.size * scale * 0.5)


## One body of a scatter solid: its middle `c` (world), its turn and its half size (metres).
func _solid(data: PackedFloat32Array, c: Vector3, yaw: float, half3: Vector3) -> void:
	var half := Vector2(half3.x, half3.z)
	var corner := minf(half.x, half.y)
	var reach := solid_reach(half)
	if corner + reach.x < 0.5 * TEXEL_M:
		return
	# The ground a bedded stone stands on lies between its underside and about its middle: the
	# mark shows within the body's own reach of that.
	var up := 0.5 * half3.y + corner + reach.x
	var foot := Vector2((c.y - 0.5 * half3.y) / up, 1.0 / up)
	_box(data, POOL_CH, c.x, c.z, yaw, half, reach.y, corner, foot)
	_box(data, CORE_CH, c.x, c.z, yaw, half, reach.x, corner, foot)


## A scatter solid's reaches (metres past a body of half size `half`): x the seam's, y the pool's.
## Each is its old fixed reach, capped by the body's narrower half, so a boulder keeps its seam
## and a small stone's mark is about the stone's size.
static func solid_reach(half: Vector2) -> Vector2:
	var corner := minf(half.x, half.y)
	return Vector2(
		minf(SEAM_M, SEAM_BODY * corner), minf(0.45 + 0.35 * half.length(), POOL_BODY * corner)
	)


## The separate bodies of `mesh`, as boxes in its own space: its triangles joined where they share
## a vertex (welded on WELD_M), and bodies whose plans overlap taken as one (a stone built of nested
## shells, two stones that touch). A mesh that is one body, is not triangles, or is too large to
## split gives its whole box. At most MAX_ISLANDS, the largest in plan.
static func islands(mesh: Mesh) -> Array[AABB]:
	var whole: Array[AABB] = [mesh.get_aabb()]
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null:
		return whole
	var parent := PackedInt32Array()
	var points := PackedVector3Array()
	var ids := {}
	for s in array_mesh.get_surface_count():
		if array_mesh.surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			return whole
		var arrays := array_mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if points.size() + verts.size() > MAX_SPLIT_VERTICES:
			return whole
		var welded := PackedInt32Array()
		welded.resize(verts.size())
		for k in verts.size():
			var key := Vector3i((verts[k] / WELD_M).round())
			if not ids.has(key):
				ids[key] = points.size()
				parent.append(points.size())
				points.append(verts[k])
			welded[k] = ids[key]
		var index := PackedInt32Array()
		if arrays[Mesh.ARRAY_INDEX] != null:
			index = arrays[Mesh.ARRAY_INDEX]
		var indexed := not index.is_empty()
		var corners := index.size() if indexed else verts.size()
		for t in range(0, corners - 2, 3):
			var a := _root(parent, welded[index[t] if indexed else t])
			var b := _root(parent, welded[index[t + 1] if indexed else t + 1])
			parent[b] = a
			var c := _root(parent, welded[index[t + 2] if indexed else t + 2])
			parent[c] = a
	var by_root := {}
	for k in points.size():
		var root := _root(parent, k)
		if by_root.has(root):
			by_root[root] = (by_root[root] as AABB).expand(points[k])
		else:
			by_root[root] = AABB(points[k], Vector3.ZERO)
	var out: Array[AABB] = []
	out.assign(by_root.values())
	if out.size() <= 1 or out.size() > 8 * MAX_ISLANDS:
		return whole
	# Bodies whose plans overlap are one footprint.
	var merged := true
	while merged:
		merged = false
		var i := 0
		while i < out.size():
			for j in range(out.size() - 1, i, -1):
				if _plan(out[i]).intersects(_plan(out[j])):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					merged = true
			i += 1
	out.sort_custom(func(a: AABB, b: AABB) -> bool: return _plan(a).get_area() > _plan(b).get_area())
	if out.size() > MAX_ISLANDS:
		out.resize(MAX_ISLANDS)
	return out


static func _plan(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## A tree's pool, as the painted trees' (_add_trees): a disc under the crown's projection, centred
## halfway from the trunk's foot `foot` to the crown's middle `crown`, and a seam at the trunk.
func _tree(
	data: PackedFloat32Array, foot: Vector3, crown: Vector3, half: float, height: float
) -> void:
	_disc(data, POOL_CH, (foot.x + crown.x) * 0.5, (foot.z + crown.z) * 0.5, half * 0.5 + 0.5)
	_disc(data, CORE_CH, foot.x, foot.z, trunk_seam(height))


## The nominal radius (metres) of the seam at the foot of a trunk `height` metres tall.
static func trunk_seam(height: float) -> float:
	return TRUNK_SEAM_M + TRUNK_SEAM_K * height


## Structures: each one's own plan (PainterFootprint: its walls' feet, a rounded rectangle), a pool
## reaching a little past its walls (more for a larger, taller one) and a seam at them.
func _add_structures(data: PackedFloat32Array) -> void:
	var holder: Object = _surfaces.call("buildings")
	if holder == null:
		return
	var structures: Node = holder.get("_structures")
	if structures == null or not is_instance_valid(structures):
		return
	for child: Node in structures.get_children():
		var root := child as Node3D
		if root == null or not root.is_inside_tree():
			continue
		var plan := PainterFootprint.of_structure(root)
		if plan.is_empty():
			continue
		var c: Vector2 = plan["centre"]
		var half: Vector2 = plan["half"]
		var yaw: float = plan["yaw"]
		var corner: float = plan["corner"]
		var reach := PainterFootprint.reach(half, float(plan["height"]), String(root.name))
		_count += 1
		_box(data, POOL_CH, c.x, c.y, yaw, half, reach, corner)
		_box(data, CORE_CH, c.x, c.y, yaw, half, WALL_SEAM_M, corner)


## Half the width (metres) of the band a footprint of `reach` falls off over: 0.45 of the reach,
## and at least half a texel, so a small mark's edge is still held by the field.
static func soft(reach: float) -> float:
	return maxf(0.45 * reach, 0.5 * TEXEL_M)


## The coverage `d` metres from a footprint whose nominal reach is `reach`: 1 inside, 0.5 at the
## reach, 0 past the band (`soft`).
static func cover(d: float, reach: float) -> float:
	var band := soft(reach)
	return 1.0 - smoothstep(reach - band, reach + band, d)


## Writes a disc of nominal radius `r` (metres) at world (x, z) into channel `ch` of `data`
## (CHANNELS floats a texel), keeping the maximum. `foot` (the foot's height times its weight, the
## weight; zero for none) goes with every texel the disc takes.
func _disc(
	data: PackedFloat32Array, ch: int, x: float, z: float, r: float, foot := Vector2.ZERO
) -> void:
	var band := soft(r)
	var reach := r + band
	var i0 := maxi(0, floori((x - reach - _origin.x) / TEXEL_M))
	var i1 := mini(_size.x - 1, floori((x + reach - _origin.x) / TEXEL_M))
	var j0 := maxi(0, floori((z - reach - _origin.y) / TEXEL_M))
	var j1 := mini(_size.y - 1, floori((z + reach - _origin.y) / TEXEL_M))
	var full := maxf(r - band, 0.0)
	var full2 := full * full
	var reach2 := reach * reach
	for j in range(j0, j1 + 1):
		var dz := _origin.y + (j + 0.5) * TEXEL_M - z
		var row := j * _size.x
		for i in range(i0, i1 + 1):
			var dx := _origin.x + (i + 0.5) * TEXEL_M - x
			var d2 := dx * dx + dz * dz
			if d2 >= reach2:
				continue
			var v := 1.0 if d2 <= full2 else 1.0 - smoothstep(r - band, reach, sqrt(d2))
			var at := (row + i) * CHANNELS
			if v > data[at + ch]:
				data[at + ch] = v
				if foot.y > 0.0:
					data[at + FOOT_CH] = foot.x
					data[at + FOOT_CH + 1] = foot.y


## Writes a box (half extents `half` in its own x, z, turned by `yaw` about +y, its corners rounded
## by `corner` metres, at most its narrower half) grown by `reach` metres at world (x, z) into
## channel `ch` of `data`, keeping the maximum; `foot` as in _disc.
func _box(
	data: PackedFloat32Array,
	ch: int,
	x: float,
	z: float,
	yaw: float,
	half: Vector2,
	reach: float,
	corner: float = 0.0,
	foot := Vector2.ZERO
) -> void:
	var r := clampf(corner, 0.0, minf(half.x, half.y))
	var inner := half - Vector2(r, r)
	var band := soft(reach)
	var rad := half.length() + reach + band
	var i0 := maxi(0, floori((x - rad - _origin.x) / TEXEL_M))
	var i1 := mini(_size.x - 1, floori((x + rad - _origin.x) / TEXEL_M))
	var j0 := maxi(0, floori((z - rad - _origin.y) / TEXEL_M))
	var j1 := mini(_size.y - 1, floori((z + rad - _origin.y) / TEXEL_M))
	var cs := cos(yaw)
	var sn := sin(yaw)
	var lo := reach - band
	var hi := reach + band
	for j in range(j0, j1 + 1):
		var dz := _origin.y + (j + 0.5) * TEXEL_M - z
		var row := j * _size.x
		for i in range(i0, i1 + 1):
			var dx := _origin.x + (i + 0.5) * TEXEL_M - x
			# Into the box's frame (its +x axis at `yaw` from world +x towards +z).
			var lx := absf(dx * cs + dz * sn) - inner.x
			var lz := absf(-dx * sn + dz * cs) - inner.y
			var d := minf(maxf(lx, lz), 0.0) - r
			if lx > 0.0 or lz > 0.0:
				d += sqrt(maxf(lx, 0.0) ** 2 + maxf(lz, 0.0) ** 2)
			if d >= hi:
				continue
			var v := 1.0 if d <= lo else 1.0 - smoothstep(lo, hi, d)
			var at := (row + i) * CHANNELS
			if v > data[at + ch]:
				data[at + ch] = v
				if foot.y > 0.0:
					data[at + FOOT_CH] = foot.x
					data[at + FOOT_CH + 1] = foot.y


# ---------------------------------------------------------------- tokens


func _watch() -> void:
	if _watching:
		return
	_watching = true
	(Engine.get_main_loop() as SceneTree).process_frame.connect(_on_frame)


func _on_frame() -> void:
	if _map == null or _surfaces == null:
		_watching = false
		(Engine.get_main_loop() as SceneTree).process_frame.disconnect(_on_frame)
		return
	var tree := _map.get_tree()
	if tree == null:
		return
	var now := PackedVector4Array()
	for node: Node in tree.get_nodes_in_group(BoardToken.GROUP_NAME):
		var token := node as BoardToken
		if token == null or token.rigid_body == null or not token.rigid_body.is_inside_tree():
			continue
		var info := _bounds_of(token)
		if info.is_empty():
			continue
		var gt := token.rigid_body.global_transform
		var c: Vector3 = info["center"]
		var feet := gt * (c - Vector3(0.0, float(info["half_height"]), 0.0))
		var at := gt * c
		now.append(Vector4(at.x, at.z, float(info["radius"]) * 0.7, feet.y))
		if now.size() >= MAX_TOKENS:
			break
	if now == _tokens:
		return
	_tokens = now
	var padded := now.duplicate()
	padded.resize(MAX_TOKENS)
	for material: ShaderMaterial in _surfaces.call("ground_materials"):
		material.set_shader_parameter(&"tok", padded)
		material.set_shader_parameter(&"tok_n", now.size())


## A token's body bounds (TokenGhost.body_bounds), cached by the body's id (its size is fixed).
func _bounds_of(token: BoardToken) -> Dictionary:
	var id := token.rigid_body.get_instance_id()
	if _token_bounds.has(id):
		return _token_bounds[id]
	var meshes := TokenGhost.meshes_of(token.rigid_body)
	if meshes.is_empty():
		return {}
	var info := TokenGhost.body_bounds(token.rigid_body, meshes)
	if not info.is_empty():
		_token_bounds[id] = info
	return info
