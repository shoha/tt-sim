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
## three stones is three islands (`islands`: stones side by side stay apart though their boxes
## overlap, only a body mostly inside another is part of it, `nested`), each with a seam and a
## pool no wider than itself (`solid_reach`), so a scatter of stones is small marks at the
## stones, not one oval three times the stones' size. A solid's
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
## The share of the smaller body's plan that must lie inside another's for the two to be one body.
const NEST_SHARE := 0.5
## Seconds of quiet before a changed map's field is rebuilt (growth installs trees every frame).
const REBUILD_DELAY_S := 0.3
## A change is baked whole, not by its dirty rects, when more than MAX_DIRTY footprints changed or
## their rects hold more than FULL_SHARE of the field (a level load, the trees' growth).
const MAX_DIRTY := 48
const FULL_SHARE := 0.3
## A footprint (a mark) is an Array of floats, sorted as such: its shape (DISC or BOX), a disc's
## channel, world x and z, a box's turn and half extents, the pool's reach (a disc's radius), the
## seam's reach, the corners' rounding and the foot (its height times its weight, the weight).
## A small stone is no footprint (card painter-terrain-dabs; PainterSites has the model): a mark
## its size is a texel or two of this field, so it is a SITE instead, a few flat triangles on the
## ground under it (PainterDabs, synced after every rebuild of the field).
const DISC := 0.0
const BOX := 1.0
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
## The field's floats (CHANNELS a texel), the sorted marks it was baked from, and the texel window
## the rasterizers may write (the whole field, or one dirty rect).
var _data := PackedFloat32Array()
var _marks: Array = []
var _win := Rect2i()
## The small stones' dabs (their meshes) and the sites the last rebuild found.
var _dabs := PainterDabs.new()
var _site_count := 0
## A scatter multimesh's marks by its node's id: [its transform, its buffer, its mesh's id, its
## marks, its footprints, its sites]. A multimesh nothing moved in is not walked again.
var _held: Dictionary = {}
## The last rebuild (stats()).
var _last: Dictionary = {}


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
	_held.clear()
	_marks = []
	_data = PackedFloat32Array()
	_site_count = 0
	_dabs.clear()
	_clear_ground()
	_surfaces = null


## The number of footprints in the last field (tests and the notes).
func footprints() -> int:
	return _count


## The small stones' dabs (tests and the probes).
func dabs() -> PainterDabs:
	return _dabs


## An edit of the terrain's samples in `rect` (none: a new terrain): the dabs standing there are
## laid on the ground again at the next rebuild.
func ground_edited(rect: Rect2i) -> void:
	_dabs.mark(rect)


## The last rebuild (tests, the notes and the edit-cost probe): `texels` rewritten (0: no footprint
## had moved, nothing was baked or uploaded), `whole` (a full bake), `marks`, and the milliseconds
## of its three parts, `collect_ms`, `bake_ms` and `upload_ms`.
func stats() -> Dictionary:
	return _last


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


## Brings the field up to date with the map's trees, scatter solids and structures, and hands it
## to the ground, in three parts. The footprints are collected as marks (a scatter multimesh that
## nothing moved in is not walked again). The marks are compared with the last bake's (`update`):
## when none moved nothing is baked or uploaded, when a few moved only their rects are baked, and
## otherwise (a level load, the trees' growth) the whole field. A changed field is uploaded. The
## small stones found on the way (the sites) go to their dabs (PainterDabs.sync: the new ones and
## those on edited ground are built). Pure CPU, GDScript, debounced (REBUILD_DELAY_S), never per
## frame; painter.md "Grounding" has the measured cost of each kind of edit.
func rebuild() -> void:
	_queued = false
	if _map == null or _surfaces == null:
		return
	var extent: Vector2 = _surfaces.call("map_extent")
	if extent.x <= 0.0 or extent.y <= 0.0:
		return
	var t0 := Time.get_ticks_usec()
	var layout := field_layout(extent)
	_count = 0
	var marks: Array = []
	var sites: Array = []
	_add_trees(marks)
	_add_solids(marks, sites)
	_add_structures(marks)
	var t1 := Time.get_ticks_usec()
	var size := Vector2i(roundi(layout.size.x), roundi(layout.size.y))
	var texels := update(layout.position, size, marks)
	var t2 := Time.get_ticks_usec()
	if texels > 0 or _tex == null:
		_upload()
	_hand_over()
	_apply()
	var t3 := Time.get_ticks_usec()
	_site_count = sites.size()
	var terrain := _map.get_node_or_null(^"AuthoredTerrain") as AuthoredTerrain
	var ground: ShaderMaterial = (_surfaces.call("ground_materials") as Array)[0]
	var built := _dabs.sync(_map, terrain, ground, sites)
	_last = {
		"run": int(_last.get("run", 0)) + 1,
		"texels": texels,
		"whole": texels == size.x * size.y,
		"marks": marks.size(),
		"sites": _site_count,
		"dabs_built": built,
		"collect_ms": (t1 - t0) / 1000.0,
		"bake_ms": (t2 - t1) / 1000.0,
		"upload_ms": (t3 - t2) / 1000.0,
		"dabs_ms": (Time.get_ticks_usec() - t3) / 1000.0,
		"dabs_parts": _dabs.parts,
	}


## Bakes `marks` into the field laid out at `origin`, `size` texels across, and returns the texels
## it rewrote: none when no mark moved since the last bake, the rects of the marks that did when
## they are few, the whole field when its layout changed or too much did. The marks are sorted
## first and a texel is one function of the marks that cover it, taken in that order, so a partial
## bake equals a whole one bit for bit and the order the footprints were collected in is nothing.
func update(origin: Vector2, size: Vector2i, marks: Array) -> int:
	marks.sort()
	var whole := origin != _origin or size != _size or _data.size() != size.x * size.y * CHANNELS
	var dirty: Array[Rect2i] = []
	if not whole:
		if marks == _marks:
			return 0
		dirty = _changed(marks)
		var area := 0
		for rect: Rect2i in dirty:
			area += rect.get_area()
		whole = area > FULL_SHARE * size.x * size.y
	lay_out(origin, size)
	_marks = marks
	if whole:
		_data = PackedFloat32Array()
		_data.resize(size.x * size.y * CHANNELS)
		_data.fill(0.0)
		for mark: Array in marks:
			_draw(_data, mark)
		return size.x * size.y
	var texels := 0
	for rect: Rect2i in dirty:
		_win = rect
		_wipe(rect)
		# The marks that may reach the rect, by a bound no smaller than their own (the rasterizers
		# keep to the window).
		var lo := _origin + Vector2(rect.position) * TEXEL_M
		var hi := _origin + Vector2(rect.end) * TEXEL_M
		for mark: Array in marks:
			var x: float = mark[2]
			var z: float = mark[3]
			var reach: float = mark[5] + mark[6] + 1.5 * maxf(mark[7], mark[8]) + TEXEL_M
			if x + reach < lo.x or x - reach > hi.x or z + reach < lo.y or z - reach > hi.y:
				continue
			_draw(_data, mark)
		texels += rect.get_area()
	_win = Rect2i(Vector2i.ZERO, size)
	return texels


## Lays the field out: its first texel's corner (world x, z), its size in texels, the whole of it
## open to the rasterizers.
func lay_out(origin: Vector2, size: Vector2i) -> void:
	_origin = origin
	_size = size
	_win = Rect2i(Vector2i.ZERO, size)


## A disc's mark: channel `ch`, nominal radius `r` (metres) at world (x, z).
static func disc(ch: int, x: float, z: float, r: float) -> Array:
	return [DISC, float(ch), x, z, 0.0, 0.0, 0.0, r, 0.0, 0.0, 0.0, 0.0]


## A box's mark: half extents `half` in its own x and z, turned by `yaw` about +y at world (x, z),
## its corners rounded by `corner` metres, grown by `reach` (x the pool's, y the seam's, a negative
## one for none), with its `foot` (the foot's height times its weight, the weight; zero for none).
static func box(
	x: float, z: float, yaw: float, half: Vector2, reach: Vector2, corner: float, foot := Vector2.ZERO
) -> Array:
	return [BOX, 0.0, x, z, yaw, half.x, half.y, reach.x, reach.y, corner, foot.x, foot.y]


## The texel rects of the marks that `marks` adds to or drops from the last bake's, joined where
## they meet; the whole field when more than MAX_DIRTY changed.
func _changed(marks: Array) -> Array[Rect2i]:
	var before := {}
	for mark: Array in _marks:
		before[mark] = true
	var after := {}
	var rects: Array[Rect2i] = []
	for mark: Array in marks:
		after[mark] = true
		if not before.has(mark):
			rects.append(_span(mark))
	for mark: Array in _marks:
		if not after.has(mark):
			rects.append(_span(mark))
	if rects.size() > MAX_DIRTY:
		return [Rect2i(Vector2i.ZERO, _size)]
	return joined(rects)


## `rects` with every two that meet made one, and those without area dropped.
static func joined(rects: Array[Rect2i]) -> Array[Rect2i]:
	var out: Array[Rect2i] = []
	for rect: Rect2i in rects:
		if not rect.has_area():
			continue
		var grown := rect
		var k := out.size() - 1
		while k >= 0:
			if out[k].intersects(grown):
				grown = grown.merge(out[k])
				out.remove_at(k)
				k = out.size()
			k -= 1
		out.append(grown)
	return out


## The field's texels a mark may write (a rect without area: none).
func _span(mark: Array) -> Rect2i:
	if mark[0] == DISC:
		var r: float = mark[7]
		return _texels(mark[2], mark[3], r + soft(r), r + soft(r))
	return _box_span(
		mark[2], mark[3], mark[4], Vector2(mark[5], mark[6]), far_of(Vector2(mark[7], mark[8]))
	)


## Writes a mark into `data` (the window's texels of it).
func _draw(data: PackedFloat32Array, mark: Array) -> void:
	if mark[0] == DISC:
		_disc(data, int(mark[1]), mark[2], mark[3], mark[7])
	else:
		_boxes(
			data,
			mark[2],
			mark[3],
			mark[4],
			Vector2(mark[5], mark[6]),
			Vector2(mark[7], mark[8]),
			mark[9],
			Vector2(mark[10], mark[11])
		)


func _wipe(rect: Rect2i) -> void:
	var count := rect.size.x * CHANNELS
	for j in range(rect.position.y, rect.end.y):
		var at := (j * _size.x + rect.position.x) * CHANNELS
		for k in count:
			_data[at + k] = 0.0


## The field as a texture: floats as written, then half floats (one native pass each).
func _upload() -> void:
	var image := Image.create_from_data(
		_size.x, _size.y, false, Image.FORMAT_RGBAF, _data.to_byte_array()
	)
	image.convert(Image.FORMAT_RGBAH)
	if _tex == null or _tex.get_size() != Vector2(_size) or _tex.get_format() != image.get_format():
		_tex = ImageTexture.create_from_image(image)
	else:
		_tex.update(image)


## Hands the field to the ground's materials and the yard's (also one made since the last bake).
func _hand_over() -> void:
	var targets: Array[ShaderMaterial] = _surfaces.call("ground_materials")
	var yard := _yard_material()
	if yard != null:
		targets.append(yard)
	for material: ShaderMaterial in targets:
		material.set_shader_parameter(&"occ_map", _tex)
		material.set_shader_parameter(&"occ_origin", _origin)
		material.set_shader_parameter(&"occ_step", TEXEL_M)
		material.set_shader_parameter(&"occ_present", true)


## The field's layout for a map `extent` metres across: position the world (x, z) of its first
## texel's corner, size its width and height in texels (the extent plus EDGE_PAD_M on every side).
static func field_layout(extent: Vector2) -> Rect2:
	var pad := Vector2(EDGE_PAD_M, EDGE_PAD_M)
	var cells := ((extent + pad * 2.0) / TEXEL_M).ceil()
	return Rect2(-extent * 0.5 - pad, cells)


## The painted trees and bushes: a pool under the crown's projection (centre halfway from the
## trunk to the crown's middle), and a core at the trunk's foot.
func _add_trees(marks: Array) -> void:
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
			marks.append(disc(POOL_CH, p.x + mid.x, p.z + mid.z, half * 1.35))
			marks.append(disc(CORE_CH, p.x + mid.x, p.z + mid.z, half * 0.95))
			continue
		_tree(marks, p, Vector3(p.x + mid.x, p.y, p.z + mid.z), half, box.size.y)


## Rocks, logs and stumps of the scatter: each body of the mesh (`islands`) a box rounded by its
## narrower half (a stone round, a log a capsule), a pool round it and a seam at its foot, neither
## wider than the body (`solid_reach`), shown only near the height of its foot. A tree the painter
## does not grow (its mesh carries a leaf surface beside its bark, or it is tall and slender:
## TREE_M) gets a crown's disc.
func _add_solids(marks: Array, sites: Array) -> void:
	var meshes: Dictionary = _surfaces.call("solid_meshes")
	var held := {}
	if not meshes.is_empty():
		for scatter: Node in _surfaces.call("scatters"):
			if not is_instance_valid(scatter):
				continue
			for node: Node in scatter.find_children("*", "MultiMeshInstance3D", true, false):
				var mm := (node as MultiMeshInstance3D).multimesh
				if mm == null or mm.mesh == null or not meshes.has(mm.mesh.get_instance_id()):
					continue
				# The multimesh's marks as they were, unless it moved or its instances did.
				var id := mm.mesh.get_instance_id()
				var to_world := (node as Node3D).global_transform
				var buffer := mm.buffer
				var was: Array = _held.get(node.get_instance_id(), [])
				if was.is_empty() or was[0] != to_world or was[1] != buffer or was[2] != id:
					var own_sites: Array = []
					var own := _solids_of(mm, to_world, bool(meshes[id]), own_sites)
					was = [to_world, buffer, id, own, mm.instance_count, own_sites]
				held[node.get_instance_id()] = was
				marks.append_array(was[3])
				sites.append_array(was[5])
				_count += int(was[4])
	_held = held


## The marks of one scatter multimesh whose node stands at `to_world`; its small stones go to
## `sites` (PainterSites.site()).
func _solids_of(mm: MultiMesh, to_world: Transform3D, leafy: bool, sites: Array) -> Array:
	var out: Array = []
	var id := mm.mesh.get_instance_id()
	var box := mm.mesh.get_aabb()
	if not _bodies.has(id):
		_bodies[id] = islands(mm.mesh)
	var bodies: Array[AABB] = _bodies[id]
	for i in mm.instance_count:
		var xf := to_world * mm.get_instance_transform(i)
		var scale := Vector3(xf.basis.x.length(), xf.basis.y.length(), xf.basis.z.length())
		var whole := Vector2(box.size.x * scale.x, box.size.z * scale.z) * 0.5
		var height := box.size.y * scale.y
		if leafy or (height > TREE_M and height > TREE_SLENDER * maxf(whole.x, whole.y)):
			_tree(out, xf.origin, xf * box.get_center(), maxf(whole.x, whole.y), height)
			continue
		var yaw := atan2(xf.basis.x.z, xf.basis.x.x)
		for body: AABB in bodies:
			_solid(out, sites, xf * body.get_center(), yaw, body.size * scale * 0.5)
	return out


## One body of a scatter solid: its middle `c` (world), its turn and its half size (metres). A
## small stone is no mark: it goes to `sites`.
func _solid(marks: Array, sites: Array, c: Vector3, yaw: float, half3: Vector3) -> void:
	var half := Vector2(half3.x, half3.z)
	var corner := minf(half.x, half.y)
	if PainterSites.holds(half):
		# A stone a coverage its size cannot hold: its own dab, as geometry (PainterDabs).
		var r := PainterSites.radius(half)
		if r > 0.0:
			sites.append(PainterSites.site(c.x, c.z, r, c.y - 0.5 * half3.y, half3.y))
		return
	var reach := solid_reach(half)
	if corner + reach.x < 0.5 * TEXEL_M:
		return
	# The ground a bedded stone stands on lies between its underside and about its middle: the
	# mark shows within half the body's height and its seam's reach of that. (With the body's
	# width added it still ran half a metre down the wall under stones on a ledge.)
	var up := 0.5 * half3.y + reach.x
	var foot := Vector2((c.y - 0.5 * half3.y) / up, 1.0 / up)
	marks.append(box(c.x, c.z, yaw, half, Vector2(reach.y, reach.x), corner, foot))


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
	# A body that lies mostly inside another's plan is part of it. Stones set side by side stay
	# apart: their boxes overlap at the corners, and joined on any overlap the core library's
	# cluster of five was one box again, its mark an oval a metre wide (card
	# painter-rocks-forms-finish).
	var merged := true
	while merged:
		merged = false
		var i := 0
		while i < out.size():
			for j in range(out.size() - 1, i, -1):
				if nested(_plan(out[i]), _plan(out[j])):
					out[i] = out[i].merge(out[j])
					out.remove_at(j)
					merged = true
			i += 1
	out.sort_custom(func(a: AABB, b: AABB) -> bool: return _plan(a).get_area() > _plan(b).get_area())
	if out.size() > MAX_ISLANDS:
		out.resize(MAX_ISLANDS)
	return out


## Whether the smaller of two plans lies mostly (NEST_SHARE of its area) inside the other: a shell
## nested in a stone, a chip on its top. A plan with no area that touches the other is inside it.
static func nested(a: Rect2, b: Rect2) -> bool:
	if not a.intersects(b, true):
		return false
	return a.intersection(b).get_area() >= NEST_SHARE * minf(a.get_area(), b.get_area())


static func _plan(box: AABB) -> Rect2:
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _root(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## A tree's pool, as the painted trees' (_add_trees): a disc under the crown's projection, centred
## halfway from the trunk's foot `foot` to the crown's middle `crown`, and a seam at the trunk.
func _tree(marks: Array, foot: Vector3, crown: Vector3, half: float, height: float) -> void:
	marks.append(
		disc(POOL_CH, (foot.x + crown.x) * 0.5, (foot.z + crown.z) * 0.5, half * 0.5 + 0.5)
	)
	marks.append(disc(CORE_CH, foot.x, foot.z, trunk_seam(height)))


## The nominal radius (metres) of the seam at the foot of a trunk `height` metres tall.
static func trunk_seam(height: float) -> float:
	return TRUNK_SEAM_M + TRUNK_SEAM_K * height


## Structures: each one's own plan (PainterFootprint: its walls' feet, a rounded rectangle), a pool
## reaching a little past its walls (more for a larger, taller one) and a seam at them.
func _add_structures(marks: Array) -> void:
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
		marks.append(box(c.x, c.y, yaw, half, Vector2(reach, WALL_SEAM_M), corner))


## Half the width (metres) of the band a footprint of `reach` falls off over: 0.45 of the reach,
## and at least half a texel, so a small mark's edge is still held by the field.
static func soft(reach: float) -> float:
	return maxf(0.45 * reach, 0.5 * TEXEL_M)


## The coverage `d` metres from a footprint whose nominal reach is `reach`: 1 inside, 0.5 at the
## reach, 0 past the band (`soft`).
static func cover(d: float, reach: float) -> float:
	var band := soft(reach)
	return 1.0 - smoothstep(reach - band, reach + band, d)


## The further edge (metres past the body) of a box's two bands (`reach`: x the pool's, y the
## seam's, a negative one has none).
static func far_of(reach: Vector2) -> float:
	var far := -INF
	if reach.x >= 0.0:
		far = reach.x + soft(reach.x)
	if reach.y >= 0.0:
		far = maxf(far, reach.y + soft(reach.y))
	return far


## The field's texels within `ex` and `ez` metres of world (x, z); a rect without area for none.
func _texels(x: float, z: float, ex: float, ez: float) -> Rect2i:
	var i0 := maxi(0, floori((x - ex - _origin.x) / TEXEL_M))
	var i1 := mini(_size.x - 1, floori((x + ex - _origin.x) / TEXEL_M))
	var j0 := maxi(0, floori((z - ez - _origin.y) / TEXEL_M))
	var j1 := mini(_size.y - 1, floori((z + ez - _origin.y) / TEXEL_M))
	return Rect2i(i0, j0, maxi(i1 - i0 + 1, 0), maxi(j1 - j0 + 1, 0))


## The texels of a box turned by `yaw` whose bands end `far` metres past it: its own extent along
## the world's axes, grown by that.
func _box_span(x: float, z: float, yaw: float, half: Vector2, far: float) -> Rect2i:
	var cs := absf(cos(yaw))
	var sn := absf(sin(yaw))
	return _texels(x, z, cs * half.x + sn * half.y + far, sn * half.x + cs * half.y + far)


## Writes a disc of nominal radius `r` (metres) at world (x, z) into channel `ch` of `data`
## (CHANNELS floats a texel), keeping the maximum, inside the window.
func _disc(data: PackedFloat32Array, ch: int, x: float, z: float, r: float) -> void:
	var band := soft(r)
	var reach := r + band
	var span := _texels(x, z, reach, reach).intersection(_win)
	var i0 := span.position.x
	var i1 := span.end.x - 1
	var j0 := span.position.y
	var j1 := span.end.y - 1
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


## Writes a box (half extents `half` in its own x, z, turned by `yaw` about +y, its corners rounded
## by `corner` metres, at most its narrower half) at world (x, z) into `data`, inside the window:
## the pool and the seam in one pass over the texels, each grown by its `reach` (x the pool's, y the
## seam's, a negative one writes nothing), keeping the maximum. `foot` (the foot's height times its
## weight, the weight; zero for none) goes with every texel the box raises.
func _boxes(
	data: PackedFloat32Array,
	x: float,
	z: float,
	yaw: float,
	half: Vector2,
	reach: Vector2,
	corner: float,
	foot: Vector2
) -> void:
	var r := clampf(corner, 0.0, minf(half.x, half.y))
	var inner := half - Vector2(r, r)
	var lo := Vector2(reach.x - soft(reach.x), reach.y - soft(reach.y))
	var hi := Vector2(reach.x + soft(reach.x), reach.y + soft(reach.y))
	if reach.x < 0.0:
		hi.x = -INF
	if reach.y < 0.0:
		hi.y = -INF
	var far := maxf(hi.x, hi.y)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var span := _box_span(x, z, yaw, half, far).intersection(_win)
	var i0 := span.position.x
	var i1 := span.end.x - 1
	var j0 := span.position.y
	var j1 := span.end.y - 1
	var footed := foot.y > 0.0
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
			if d >= far:
				continue
			var at := (row + i) * CHANNELS
			var wrote := false
			if d < hi.x:
				var v := 1.0 if d <= lo.x else 1.0 - smoothstep(lo.x, hi.x, d)
				if v > data[at + POOL_CH]:
					data[at + POOL_CH] = v
					wrote = true
			if d < hi.y:
				var v := 1.0 if d <= lo.y else 1.0 - smoothstep(lo.y, hi.y, d)
				if v > data[at + CORE_CH]:
					data[at + CORE_CH] = v
					wrote = true
			if wrote and footed:
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
