class_name FireField
extends Node3D

## The persistent ground fire of a map document, drawn (MapDocument.fire_mask; design:
## docs/plans/2026-10-11-fire-features/design.md section 4). One per map with a document, a
## child of the map root (MapSourceLoader adds it), so its frame is the document's. It owns
## placement, chunks, the budget and the LOD switch; FireLook owns the meshes and materials.
##
## Placement is pure (plan_block): per diff block of the mask (MaskStroke.BLOCK samples, 10 m
## at the default spacing), a jittered lattice at FLAME_SPACING_M seeded by the map seed and
## the lattice point, so peers agree and re-planning one block moves nothing elsewhere. A
## point burns where the bilinear mask is at least EMBER_MIN and the ground is neither wet
## (the wet dressing's wet line) nor steeper than the cliff rule (TerrainRules); its height is
## the document's own triangle (ScatterGenerator.triangle_height). Where flames may stand is
## derived here and never saved: a river carved through a fire puts it out on screen and the
## fire comes back if the river is erased.
##
## What stands there depends on the band (the look card F4a): the ember band gets no flames
## (the ground's glow draws it), only a spark at about one point in SPARK_EVERY. Flames and
## the blaze are gathered by a low-frequency clump noise (clump, about CLUMP_CELL_M across):
## it drops the points where it is lowest and scales the rest from CLUMP_SCALE.x at a clump's
## edge to .y in its middle, so flames stand in bonfire-sized clumps with open ground between
## (the weaker the fire, the wider the gaps). In a blaze the point whose clump value tops its
## eight lattice neighbours is a big flame (BIG_SCALE) and the blaze points beside it shrink to
## licks at its feet (LICK_SCALE).
## Intensity changes the shape too: it picks the tongue layout (weak flames one or two tongues,
## a blaze three or four) and the shader's bands and erosion. Each plan is emitted shuffled
## (ordered by its points' seeds), so any prefix of it is an even thinning.
##
## Budget: the whole map shows at most MAX_FLAMES. Past it every burning block shows the same
## share of its plan (budget_shares: a uniform thinning in proportion to each block's burning
## area, as FoliageBudget.plan; the remainder by largest fraction, ties in block order), a pure
## function of all the plans, so a peer that rebuilt once and one that refreshed stroke by
## stroke show the same flames. LOD: past LOD_ZOOM half the flames hide and the rest grow
## (FireLook.set_far: one uniform when the zoom crosses it). Nothing runs per flame per frame.

const NODE_NAME := "FireField"
## Lattice spacing of the flames, and how far each is moved off its lattice point (a share of
## the spacing, either way).
const FLAME_SPACING_M := 0.9
const JITTER := 0.35
## Intensity bands (mask bytes): below EMBER_MIN nothing burns.
const EMBER_MIN := 40
const FLAME_MIN := 110
const BLAZE_MIN := 200
## Flames and sparks on the whole map, at most.
const MAX_FLAMES := 4096
## A sample whose wet line (the wet dressing's alpha) is at least this does not burn.
const WET_LINE_MIN := 128
## A face steeper than this does not burn (the cliff rule's start).
const STEEP_DEG := TerrainRules.CLIFF_START_DEG
## Floats per planned flame, and where each sits: x, y, z (document metres), intensity 0..1,
## seed (the tongue layout plus a 0..1 seed), height and width (metres), kind (FLAME, SPARK).
const STRIDE := 8
const INTENSITY := 3
const SEED := 4
const HEIGHT := 5
const WIDTH := 6
const KIND := 7
const FLAME := 0.0
const SPARK := 1.0
## A flame's height (metres) at the flames band's start and end, and a blaze's, before its clump
## scale; its width as a share of its height (a blaze takes the upper part).
const FLAME_HEIGHT_M := Vector2(0.55, 1.05)
const BLAZE_HEIGHT_M := 1.2
const WIDTH_SHARE := Vector2(0.35, 0.75)
const BLAZE_WIDTH_FROM := 0.55
## The clump noise: its cell, how it scales a flame, below what value a flame point drops (at
## the flames band's start and end), and below what a blaze point does.
const CLUMP_CELL_M := 3.0
const CLUMP_SCALE := Vector2(0.6, 1.6)
const FLAME_GAP := Vector2(0.42, 0.26)
const BLAZE_GAP := 0.14
## A blaze clump's big flame and the licks at its feet (scales).
const BIG_SCALE := Vector2(1.6, 2.2)
const LICK_SCALE := Vector2(0.45, 0.7)
## About one ember point in this many throws a spark, and its size (metres).
const SPARK_EVERY := 6
const SPARK_SIZE_M := 0.07
## Tongue layouts (fire_field.gdshader's tongue()): one tall with a side lick, two, three, four.
const LAYOUT_ONE := 0
const LAYOUT_TWO := 1
const LAYOUT_THREE := 2
const LAYOUT_CROWN := 3
## Past this camera zoom (the orthographic size) half the flames hide.
const LOD_ZOOM := 24.0
## Lattice points a block's window reaches past its own (a lick looks two points out).
const WINDOW_MARGIN := 2

var document: MapDocument = null
## block Vector2i -> the block's whole plan, for burning blocks only.
var _plans: Dictionary = {}
## block Vector2i -> MultiMeshInstance3D, for blocks that show something.
var _chunks: Dictionary = {}
## block Vector2i -> flames shown there.
var _counts: Dictionary = {}
var _glow_texture: ImageTexture = null
var _far := false


## A field for `doc`, already planned and drawn.
static func create(doc: MapDocument) -> FireField:
	var field := FireField.new()
	field.name = NODE_NAME
	field.document = doc
	field.rebuild()
	return field


func _ready() -> void:
	if document != null:
		FireLook.set_wind(document.map_seed)
	FireLook.set_far(false)
	_bind_glow()


func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	var far := (
		camera != null and camera.projection == Camera3D.PROJECTION_ORTHOGONAL
		and camera.size > LOD_ZOOM
	)
	if far != _far:
		_far = far
		FireLook.set_far(far)


## Re-plans the whole map (after a load or a whole-document change).
func rebuild() -> void:
	for block in _chunks:
		(_chunks[block] as Node).free()
	_chunks.clear()
	_counts.clear()
	_plans.clear()
	if document == null:
		return
	refresh(Rect2i(0, 0, document.samples_x(), document.samples_z()))


## Re-plans the blocks the samples of `sample_rect` touch (a stroke's frame, an undo), then
## re-shares the budget: a block whose share changed is drawn again.
func refresh(sample_rect: Rect2i) -> void:
	if document == null or not sample_rect.has_area():
		return
	var touched := blocks_of(document, sample_rect)
	for block in touched:
		var plan := plan_block(document, block)
		if plan.is_empty():
			_plans.erase(block)
		else:
			_plans[block] = plan
	var planned := {}
	for block in _plans:
		@warning_ignore("integer_division")
		planned[block] = (_plans[block] as PackedFloat32Array).size() / STRIDE
	var shares := budget_shares(planned, MAX_FLAMES)
	var stale: Array = _counts.keys()
	for block in shares:
		if not block in stale:
			stale.append(block)
	for block in stale:
		var share := int(shares.get(block, 0))
		if block in touched or share != int(_counts.get(block, 0)):
			_show(block, share)
	_bind_glow()


## Flames (and sparks) shown on the whole map.
func flame_count() -> int:
	var total := 0
	for block in _counts:
		total += int(_counts[block])
	return total


## The diff blocks the samples of `sample_rect` touch, row by row.
static func blocks_of(doc: MapDocument, sample_rect: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var rect := sample_rect.intersection(Rect2i(0, 0, doc.samples_x(), doc.samples_z()))
	if not rect.has_area():
		return out
	@warning_ignore("integer_division")
	var first := rect.position / MaskStroke.BLOCK
	@warning_ignore("integer_division")
	var last := (rect.end - Vector2i.ONE) / MaskStroke.BLOCK
	for bz in range(first.y, last.y + 1):
		for bx in range(first.x, last.x + 1):
			out.append(Vector2i(bx, bz))
	return out


## The band of mask byte `intensity`: 0 none, 1 embers, 2 flames, 3 blaze.
static func band(intensity: int) -> int:
	if intensity >= BLAZE_MIN:
		return 3
	if intensity >= FLAME_MIN:
		return 2
	if intensity >= EMBER_MIN:
		return 1
	return 0


## A flame's height (metres) at intensity `t` (0..1 of 255) before its clump scale; 0 in the
## ember band. Pure.
static func base_height(t: float) -> float:
	var heat := t * 255.0
	if heat >= BLAZE_MIN:
		return BLAZE_HEIGHT_M
	if heat < FLAME_MIN:
		return 0.0
	return lerpf(
		FLAME_HEIGHT_M.x, FLAME_HEIGHT_M.y, (heat - FLAME_MIN) / float(BLAZE_MIN - FLAME_MIN)
	)


## The clump noise at document point `p` (metres) of map seed `map_seed`, 0..1: two octaves of
## value noise about CLUMP_CELL_M across, spread so both ends occur. Pure.
static func clump(map_seed: int, p: Vector2) -> float:
	var q := p / CLUMP_CELL_M
	var v := 0.7 * _value_noise(map_seed + 7, q) + 0.3 * _value_noise(map_seed + 8, q * 2.3)
	return smoothstep(0.22, 0.78, v)


## The flames of diff block `block` of `doc` (see the header): STRIDE floats each, shuffled.
## Pure and deterministic; empty without a fire mask.
static func plan_block(doc: MapDocument, block: Vector2i) -> PackedFloat32Array:
	var count := doc.sample_count()
	if doc.fire_mask.size() != count or doc.heights.size() != count:
		return PackedFloat32Array()
	var rect := MaskStroke.block_rect(doc, block)
	if not rect.has_area():
		return PackedFloat32Array()
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var low := -half + Vector2(rect.position) * step
	var high := -half + Vector2(rect.end) * step
	# Lattice points whose unjittered spot lies in [low, high) belong to this block.
	var first := Vector2i(ceili(low.x / FLAME_SPACING_M), ceili(low.y / FLAME_SPACING_M))
	var end := Vector2i(ceili(high.x / FLAME_SPACING_M), ceili(high.y / FLAME_SPACING_M))
	var window := LatticeWindow.new(doc, first, end)
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	var wet := doc.water_dressing.size() == count * 4
	var flat_y := cos(deg_to_rad(STEEP_DEG))
	var entries: Array = []
	for iz in range(first.y, end.y):
		for ix in range(first.x, end.x):
			var i := window.index(ix, iz)
			var heat := window.heat[i]
			if heat < EMBER_MIN:
				continue
			var key := _key(ix, iz)
			var p := Vector2(window.px[i], window.pz[i])
			var at := (p + half) / step
			var nearest := doc.sample_index(
				clampi(roundi(at.x), 0, columns - 1), clampi(roundi(at.y), 0, rows - 1)
			)
			if wet and doc.water_dressing[nearest * 4 + 3] >= WET_LINE_MIN:
				continue
			var normal := ScatterGenerator.triangle_normal(doc.heights, columns, rows, at, step)
			if normal.y < flat_y:
				continue
			var entry := _flame(doc.map_seed, key, heat, window, i)
			if entry.is_empty():
				continue
			entry[0] = p.x
			entry[1] = ScatterGenerator.triangle_height(doc.heights, columns, rows, at)
			entry[2] = p.y
			entries.append(entry)
	entries.sort_custom(func(a: PackedFloat32Array, b: PackedFloat32Array) -> bool:
		return fmod(a[SEED], 1.0) < fmod(b[SEED], 1.0))
	var out := PackedFloat32Array()
	for entry: PackedFloat32Array in entries:
		out.append_array(entry)
	return out


## Each block's share of `cap` for blocks planning `planned` (block -> flames): all of them
## under the cap, else the same fraction of each (floored, the remainder one each to the
## largest fractions, ties in row order). Pure.
static func budget_shares(planned: Dictionary, cap: int) -> Dictionary:
	var total := 0
	for block in planned:
		total += int(planned[block])
	var shares := {}
	if total <= cap:
		for block in planned:
			shares[block] = int(planned[block])
		return shares
	var rest: Array = []
	var given := 0
	for block: Vector2i in planned:
		var exact := float(planned[block]) * cap / total
		shares[block] = floori(exact)
		given += floori(exact)
		rest.append([exact - floori(exact), block])
	rest.sort_custom(
		func(a: Array, b: Array) -> bool:
			if a[0] != b[0]:
				return a[0] > b[0]
			var p: Vector2i = a[1]
			var q: Vector2i = b[1]
			return p.y < q.y or (p.y == q.y and p.x < q.x)
	)
	for k in mini(cap - given, rest.size()):
		shares[rest[k][1]] += 1
	return shares


## The first `budget` flames of `plan` (an even thinning: plans are shuffled). Pure.
static func thin(plan: PackedFloat32Array, budget: int) -> PackedFloat32Array:
	return plan.slice(0, maxi(budget, 0) * STRIDE)


## A flame for lattice point `i` of `window` at mask value `heat`, or empty where none stands
## (an ember point with no spark, a point in a clump's gap). Its x, y, z are filled by the
## caller.
static func _flame(
	map_seed: int, key: int, heat: float, window: LatticeWindow, i: int
) -> PackedFloat32Array:
	var seed := MaskBrush.sample_noise(map_seed + 2, key) * 0.999
	var pick := MaskBrush.sample_noise(map_seed + 3, key)
	var t := heat / 255.0
	var c := window.clump[i]
	if heat < FLAME_MIN:
		if pick * SPARK_EVERY >= 1.0:
			return PackedFloat32Array()
		return PackedFloat32Array([0, 0, 0, t, seed, SPARK_SIZE_M, SPARK_SIZE_M, SPARK])
	var size := pick
	var width_share := lerpf(WIDTH_SHARE.x, WIDTH_SHARE.y, MaskBrush.sample_noise(map_seed + 4, key))
	var layout: int
	var scale: float
	if heat < BLAZE_MIN:
		var strength := (heat - FLAME_MIN) / float(BLAZE_MIN - FLAME_MIN)
		var gap := lerpf(FLAME_GAP.x, FLAME_GAP.y, strength)
		if c < gap:
			return PackedFloat32Array()
		# Small at a clump's edge, big in its middle.
		scale = lerpf(CLUMP_SCALE.x, CLUMP_SCALE.y, (c - gap) / (1.0 - gap))
		layout = floori(size * (2.0 if strength < 0.4 else 3.0))
	elif window.big(i):
		scale = lerpf(BIG_SCALE.x, BIG_SCALE.y, c)
		layout = LAYOUT_CROWN if size < 0.6 else LAYOUT_THREE
		width_share = lerpf(BLAZE_WIDTH_FROM, WIDTH_SHARE.y, size)
	elif window.blaze(i):
		if window.beside_big(i):
			scale = lerpf(LICK_SCALE.x, LICK_SCALE.y, size)
			layout = LAYOUT_ONE if size < 0.5 else LAYOUT_TWO
		else:
			scale = lerpf(CLUMP_SCALE.x, CLUMP_SCALE.y, (c - BLAZE_GAP) / (1.0 - BLAZE_GAP))
			layout = LAYOUT_THREE if size < 0.65 else LAYOUT_CROWN
			width_share = lerpf(BLAZE_WIDTH_FROM, WIDTH_SHARE.y, size)
	else:
		return PackedFloat32Array()
	var height := base_height(t) * scale
	return PackedFloat32Array([0, 0, 0, t, layout + seed, height, height * width_share, FLAME])


static func _key(ix: int, iz: int) -> int:
	return (ix * 73856093) ^ (iz * 19349663)


static func _value_noise(map_seed: int, q: Vector2) -> float:
	var cx := floori(q.x)
	var cz := floori(q.y)
	var f := q - Vector2(cx, cz)
	f = f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	var a := MaskBrush.sample_noise(map_seed, _key(cx, cz))
	var b := MaskBrush.sample_noise(map_seed, _key(cx + 1, cz))
	var d := MaskBrush.sample_noise(map_seed, _key(cx, cz + 1))
	var e := MaskBrush.sample_noise(map_seed, _key(cx + 1, cz + 1))
	return lerpf(lerpf(a, b, f.x), lerpf(d, e, f.x), f.y)


static func _bilinear(mask: PackedByteArray, columns: int, rows: int, at: Vector2) -> float:
	var fx := clampf(at.x, 0.0, columns - 1)
	var fz := clampf(at.y, 0.0, rows - 1)
	var x0 := mini(floori(fx), columns - 2)
	var z0 := mini(floori(fz), rows - 2)
	var tx := fx - x0
	var tz := fz - z0
	var i := z0 * columns + x0
	var top := lerpf(mask[i], mask[i + 1], tx)
	var bottom := lerpf(mask[i + columns], mask[i + columns + 1], tx)
	return lerpf(top, bottom, tz)


func _show(block: Vector2i, shown: int) -> void:
	var chunk: MultiMeshInstance3D = _chunks.get(block)
	if shown <= 0:
		if chunk != null:
			chunk.free()
		_chunks.erase(block)
		_counts.erase(block)
		return
	if chunk == null:
		chunk = FireLook.make_chunk("Fire_%d_%d" % [block.x, block.y])
		add_child(chunk)
		_chunks[block] = chunk
	FireLook.fill_chunk(chunk, _plans[block], shown, _forward())
	_counts[block] = shown


## The camera's forward axis in this node's frame (the game camera never turns).
func _forward() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return FireLook.DEFAULT_FORWARD.normalized()
	return (global_basis.inverse() * -camera.global_basis.z).normalized()


## The ground's glow follows the mask: bound to the sibling AuthoredTerrain's material.
func _bind_glow() -> void:
	var parent := get_parent()
	if parent == null or document == null:
		return
	for child in parent.get_children():
		var terrain := child as AuthoredTerrain
		if terrain != null and terrain.get_material() != null:
			_glow_texture = FireLook.glow_texture(document, _glow_texture)
			FireLook.bind_glow(terrain.get_material(), _glow_texture)
			return


## The lattice around one block (WINDOW_MARGIN points past it on every side): each point's
## jittered spot, its mask value and its clump value, so a point can see its neighbours
## across the block's edge without reading another block's plan.
class LatticeWindow:
	var origin: Vector2i
	var width: int
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	var heat := PackedFloat32Array()
	var clump := PackedFloat32Array()

	func _init(doc: MapDocument, first: Vector2i, end: Vector2i) -> void:
		origin = first - Vector2i(WINDOW_MARGIN, WINDOW_MARGIN)
		var last := end + Vector2i(WINDOW_MARGIN, WINDOW_MARGIN)
		width = last.x - origin.x
		var size := width * (last.y - origin.y)
		px.resize(size)
		pz.resize(size)
		heat.resize(size)
		clump.resize(size)
		var spread := 2.0 * JITTER * FLAME_SPACING_M
		var half := doc.extent_m() * 0.5
		var step := doc.sample_step()
		for iz in range(origin.y, last.y):
			for ix in range(origin.x, last.x):
				var i := index(ix, iz)
				var key := FireField._key(ix, iz)
				var jitter := Vector2(
					MaskBrush.sample_noise(doc.map_seed, key) - 0.5,
					MaskBrush.sample_noise(doc.map_seed + 1, key) - 0.5
				)
				var p := Vector2(ix, iz) * FLAME_SPACING_M + jitter * spread
				px[i] = p.x
				pz[i] = p.y
				clump[i] = FireField.clump(doc.map_seed, p)
				if absf(p.x) > half.x or absf(p.y) > half.y:
					heat[i] = 0.0
					continue
				heat[i] = FireField._bilinear(
					doc.fire_mask, doc.samples_x(), doc.samples_z(), (p + half) / step
				)

	func index(ix: int, iz: int) -> int:
		return (iz - origin.y) * width + (ix - origin.x)

	## Whether point `i` stands in a blaze clump (not in its gap).
	func blaze(i: int) -> bool:
		return heat[i] >= BLAZE_MIN and clump[i] >= BLAZE_GAP

	## Whether point `i` is its clump's big flame: a blaze point whose clump value tops every
	## blaze neighbour's (ties to the lower index).
	func big(i: int) -> bool:
		if not blaze(i):
			return false
		for j in _neighbours(i):
			if blaze(j) and (clump[j] > clump[i] or (clump[j] == clump[i] and j < i)):
				return false
		return true

	## Whether a neighbour of point `i` is a big flame.
	func beside_big(i: int) -> bool:
		for j in _neighbours(i):
			if big(j):
				return true
		return false

	func _neighbours(i: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		@warning_ignore("integer_division")
		var rows := heat.size() / width
		@warning_ignore("integer_division")
		var z := i / width
		var x := i % width
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				if (dx != 0 or dz != 0) and x + dx >= 0 and x + dx < width:
					if z + dz >= 0 and z + dz < rows:
						out.append(i + dz * width + dx)
		return out
