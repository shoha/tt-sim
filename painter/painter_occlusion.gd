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
## Tokens are the only moving things: their feet discs go in a small uniform array refreshed
## when one moved (one pass over the token group a frame, no field rebuild).
## Base gradients (the second half of the look): a trunk, a rock or a log is a step darker over
## its lowest metre, so it grows out of the ground (`base_dark`, in the tree block-in and the
## selector), which the shaders take as a uniform.
##
## MANAGED BY: PainterSurfaces (painter/painter_surfaces.gd). Classic never loads this file.

## Metres a field texel covers.
const TEXEL_M := 0.5
## Seconds of quiet before a changed map's field is rebuilt (growth installs trees every frame).
const REBUILD_DELAY_S := 0.3
const MAX_TOKENS := 32
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
	for material: ShaderMaterial in _surfaces.call("base_materials"):
		material.set_shader_parameter(&"base_dark", 0.0)


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
	_origin = -extent * 0.5
	_size = Vector2i(ceili(extent.x / TEXEL_M), ceili(extent.y / TEXEL_M))
	var pool := PackedFloat32Array()
	var core := PackedFloat32Array()
	pool.resize(_size.x * _size.y)
	core.resize(_size.x * _size.y)
	_count = 0
	_add_trees(pool, core)
	_add_solids(pool, core)
	_add_structures(pool, core)
	var bytes := PackedByteArray()
	bytes.resize(pool.size() * 2)
	for i in pool.size():
		bytes[i * 2] = int(clampf(pool[i], 0.0, 1.0) * 255.0)
		bytes[i * 2 + 1] = int(clampf(core[i], 0.0, 1.0) * 255.0)
	var image := Image.create_from_data(_size.x, _size.y, false, Image.FORMAT_RG8, bytes)
	if _tex == null or _tex.get_size() != Vector2(_size):
		_tex = ImageTexture.create_from_image(image)
	else:
		_tex.update(image)
	for material: ShaderMaterial in _surfaces.call("ground_materials"):
		material.set_shader_parameter(&"occ_map", _tex)
		material.set_shader_parameter(&"occ_origin", _origin)
		material.set_shader_parameter(&"occ_step", TEXEL_M)
		material.set_shader_parameter(&"occ_present", true)


## The painted trees and bushes: a pool under the crown's projection (centre halfway from the
## trunk to the crown's middle), and a core at the trunk's foot.
func _add_trees(pool: PackedFloat32Array, core: PackedFloat32Array) -> void:
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
			_disc(pool, p.x + mid.x, p.z + mid.z, half * 1.35)
			_disc(core, p.x + mid.x, p.z + mid.z, half * 0.95)
			continue
		var c := Vector2(p.x + mid.x * 0.5, p.z + mid.z * 0.5)
		_disc(pool, c.x, c.y, half * 0.5 + 0.5)
		_disc(core, p.x, p.z, 0.55 + 0.05 * box.size.y)


## Rocks, logs and stumps of the scatter: an oriented box each, a pool round it, a seam at its foot.
func _add_solids(pool: PackedFloat32Array, core: PackedFloat32Array) -> void:
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
			var box := mm.mesh.get_aabb()
			var to_world := (node as Node3D).global_transform
			for i in mm.instance_count:
				var xf := to_world * mm.get_instance_transform(i)
				var sx := xf.basis.x.length()
				var sz := xf.basis.z.length()
				var half := Vector2(box.size.x * sx, box.size.z * sz) * 0.5
				var c := xf * box.get_center()
				var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
				_count += 1
				_box(pool, c.x, c.z, yaw, half, 0.45 + 0.35 * half.length())
				_box(core, c.x, c.z, yaw, half, 0.22)


## Structures: each one's footprint box, a pool round it and a seam at its walls.
func _add_structures(pool: PackedFloat32Array, core: PackedFloat32Array) -> void:
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
		var to_local := root.global_transform.affine_inverse()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for mi: Node in root.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var rel := to_local * m.global_transform
			var box := m.mesh.get_aabb()
			for corner in 8:
				var q := rel * box.get_endpoint(corner)
				lo = lo.min(Vector2(q.x, q.z))
				hi = hi.max(Vector2(q.x, q.z))
		if lo.x > hi.x:
			continue
		var centre := root.global_transform * Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.y + hi.y) * 0.5)
		var half := (hi - lo) * 0.5
		var yaw := atan2(root.global_basis.x.z, root.global_basis.x.x)
		_count += 1
		_box(pool, centre.x, centre.z, yaw, half, 0.9)
		_box(core, centre.x, centre.z, yaw, half, 0.35)


## The coverage at `x` (distance over the footprint's nominal reach): 1 inside, 0.5 at the reach,
## 0 past 1.45 of it.
static func cover(x: float) -> float:
	return 1.0 - smoothstep(0.55, 1.45, x)


## Writes a disc of nominal radius `r` (metres) at world (x, z) into `field`, keeping the maximum.
func _disc(field: PackedFloat32Array, x: float, z: float, r: float) -> void:
	var reach := r * 1.45
	var i0 := maxi(0, floori((x - reach - _origin.x) / TEXEL_M))
	var i1 := mini(_size.x - 1, floori((x + reach - _origin.x) / TEXEL_M))
	var j0 := maxi(0, floori((z - reach - _origin.y) / TEXEL_M))
	var j1 := mini(_size.y - 1, floori((z + reach - _origin.y) / TEXEL_M))
	for j in range(j0, j1 + 1):
		var dz := _origin.y + (j + 0.5) * TEXEL_M - z
		for i in range(i0, i1 + 1):
			var dx := _origin.x + (i + 0.5) * TEXEL_M - x
			var v := cover(sqrt(dx * dx + dz * dz) / r)
			var at := j * _size.x + i
			if v > field[at]:
				field[at] = v


## Writes a box (half extents `half` in its own x, z, turned by `yaw` about +y) grown by `reach`
## metres at world (x, z) into `field`, keeping the maximum.
func _box(
	field: PackedFloat32Array, x: float, z: float, yaw: float, half: Vector2, reach: float
) -> void:
	var rad := half.length() + reach * 1.45
	var i0 := maxi(0, floori((x - rad - _origin.x) / TEXEL_M))
	var i1 := mini(_size.x - 1, floori((x + rad - _origin.x) / TEXEL_M))
	var j0 := maxi(0, floori((z - rad - _origin.y) / TEXEL_M))
	var j1 := mini(_size.y - 1, floori((z + rad - _origin.y) / TEXEL_M))
	var cs := cos(yaw)
	var sn := sin(yaw)
	for j in range(j0, j1 + 1):
		var dz := _origin.y + (j + 0.5) * TEXEL_M - z
		for i in range(i0, i1 + 1):
			var dx := _origin.x + (i + 0.5) * TEXEL_M - x
			# Into the box's frame (its +x axis at `yaw` from world +x towards +z).
			var lx := absf(dx * cs + dz * sn) - half.x
			var lz := absf(-dx * sn + dz * cs) - half.y
			var d := Vector2(maxf(lx, 0.0), maxf(lz, 0.0)).length() + minf(maxf(lx, lz), 0.0)
			var v := cover(d / reach)
			var at := j * _size.x + i
			if v > field[at]:
				field[at] = v


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
