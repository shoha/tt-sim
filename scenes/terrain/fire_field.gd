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
## point burns where the bilinear mask, read through a broad warp (PLACE_WARP, so a straight
## pass does not stand its flames in rows), is at least EMBER_MIN and the ground is neither wet
## (the wet dressing's wet line) nor steeper than the cliff rule (TerrainRules); its height is
## the document's own triangle (ScatterGenerator.triangle_height). Where flames may stand is
## derived here and never saved: a river carved through a fire puts it out on screen and the
## fire comes back if the river is erased.
##
## What stands there depends on the band (the look card F4a): the ember band gets no flames
## (the ground's glow draws it), only a spark at about one point in SPARK_EVERY. Flames and
## the blaze are gathered by a low-frequency clump noise (clump, about CLUMP_CELL_M across, its
## lattices turned and warped off the map's axes so clumps are blobs, not hedges): it drops the
## points where it is lowest and scales the rest from CLUMP_SCALE.x at a clump's edge to .y in
## its middle, each flame moved a little in that range by its own draw (SCALE_JITTER), so flames
## stand in bonfire-sized clumps of uneven heights with open ground between (the weaker the
## fire, the wider the gaps). In a blaze the point whose clump value tops its
## eight lattice neighbours is a big flame (BIG_SCALE) and the blaze points beside it shrink to
## licks at its feet (LICK_SCALE).
## Intensity changes the shape too: it picks the tongue layout (weak flames one or two tongues,
## a blaze three or four) and the shader's bands and erosion. Each plan is emitted shuffled
## (ordered by its points' seeds), so any prefix of it is an even thinning.
##
## A base fire unifies the flames (the user's 2026-10-16 verdict): the flames' heat raster
## (HEAT_STEP_M) sums each planned flame's height under a soft kernel, re-splatted around the
## blocks a refresh re-plans. The ground burns as a bed on that summed heat
## (fire_glow.gdshaderinc), and each drawn flame carries the heat at its foot, which thins its
## rim and widens its hot bands, so a crowded clump reads as one hotter body. A second raster on
## the same grid, the feet's pools (POOL_REACH, round 4), marks where flames stand, so the
## ground glows under every foot and stays dark crust between. The rasters come
## from the whole plans (not the budget's prefix), so thinning does not dim the bed; a peer
## that refreshed stroke by stroke and one that rebuilt hold the same raster.
##
## Budget: the whole map shows at most MAX_FLAMES. Past it every burning block shows the same
## share of its plan (budget_shares: a uniform thinning in proportion to each block's burning
## area, as FoliageBudget.plan; the remainder by largest fraction, ties in block order), a pure
## function of all the plans, so a peer that rebuilt once and one that refreshed stroke by
## stroke show the same flames. LOD: past LOD_ZOOM half the flames hide and the rest grow
## (FireLook.set_far: one uniform when the zoom crosses it). Nothing runs per flame per frame.
##
## Lights and smoke (look card F4b-1): each re-planned block's flames are summed on the
## clusters' grid (FireClusters.cells_of, kept per block), and every refresh finds the hot spots
## from those sums: FireLights stands up to four warm lights over the largest burning clusters
## (shown only while the sun is low) and FireFieldSmoke puffs slow billows over up to eight of
## the largest blaze clusters. Both are children, made with the first fire and freed with the
## map; their per-frame work is the lights' flicker and the smoke's pool of 24.

const NODE_NAME := "FireField"
## Lattice spacing of the flames, and how far each is moved off its lattice point (a share of
## the spacing, either way).
const FLAME_SPACING_M := 0.9
const JITTER := 0.45
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
## scale; its width as a share of its height (a blaze takes the upper part). A blaze stands two
## to three times a field flame's height.
const FLAME_HEIGHT_M := Vector2(0.55, 1.05)
const BLAZE_HEIGHT_M := 1.8
const WIDTH_SHARE := Vector2(0.35, 0.75)
const BLAZE_WIDTH_FROM := 0.55
## The clump noise: its cell, how it scales a flame, below what value a flame point drops (at
## the flames band's start and end), and below what a blaze point does.
## (Round 4: 3 m clumps of small flames over the whole burn shimmered like wallpaper at the home
## zoom; fewer, larger clumps with wider gaps read as separate fires.)
const CLUMP_CELL_M := 4.2
## The clump noise's warp: the broad noise's cell and how far (metres) it moves a point; and
## the turns (radians) of its two octaves' lattices off the map's axes.
const CLUMP_WARP := Vector2(6.0, 3.0)
const CLUMP_TURN := Vector2(0.56, 1.21)
const CLUMP_SCALE := Vector2(0.6, 1.6)
## How far a flame's own draw moves its place in the clump's scale range (either way), so a
## clump's neighbours are not one height.
const SCALE_JITTER := 0.25
const FLAME_GAP := Vector2(0.5, 0.36)
const BLAZE_GAP := 0.2
## The flames read the mask through a broad warp: its noise's cell and how far (metres) it can
## move the read, so a straight pass's band of flames wanders across the brush's width instead
## of standing in rows (a uniform mask is unaffected).
const PLACE_WARP := Vector2(5.0, 2.0)
## A blaze clump's big flame and the licks at its feet (scales; a big flame's above the clump
## range).
const BIG_SCALE := Vector2(1.62, 1.8)
const LICK_SCALE := Vector2(0.45, 0.7)
## About one ember point in this many throws a spark, and its size (metres: it must read at
## zoom 8).
const SPARK_EVERY := 6
const SPARK_SIZE_M := 0.16
## Tongue layouts (fire_field.gdshader's tongue()): one tall with a side lick, two, three, four.
const LAYOUT_ONE := 0
const LAYOUT_TWO := 1
const LAYOUT_THREE := 2
const LAYOUT_CROWN := 3
## The flames' heat raster (the ground's bed, fire_glow.gdshaderinc; the user's 2026-10-16
## verdict: a base fire unifies the flames): a texel every HEAT_STEP_M from the document's first
## sample; each flame adds its height (metres) times a soft kernel reaching HEAT_REACH.x plus
## HEAT_REACH.y of its width, so a clump sums to a hot plateau and a lone flame to a dim pool; a
## texel's sum over HEAT_FULL_M is the bed's temperature (0..1).
const HEAT_STEP_M := 0.5
const HEAT_FULL_M := 4.5
const HEAT_REACH := Vector2(1.0, 1.0)
## The feet's pools, a second raster on the same grid (round 4: where the ground glows under the
## flames, so every flame's foot stands in glow whatever its size): each flame adds 1 under a
## narrow kernel reaching POOL_REACH.x plus POOL_REACH.y of its width; uploaded clamped to 1.
const POOL_REACH := Vector2(0.45, 0.6)
## Texels the cleared rect of a refresh reaches past its blocks (more than any kernel's reach).
const HEAT_GROW := 8
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
## The flames' heat raster (see HEAT_STEP_M), the feet's pools (POOL_REACH) on its grid, its
## size in texels, and their texture.
var _heat := PackedFloat32Array()
var _pools := PackedFloat32Array()
var _heat_size := Vector2i.ZERO
var _heat_texture: ImageTexture = null
## block Vector2i -> its flames' sums on the clusters' grid (FireClusters.cells_of), for
## burning blocks only; the lights and the smoke (null until the first fire).
var _cells: Dictionary = {}
var _lights: FireLights = null
var _smoke: FireFieldSmoke = null


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
	_cells.clear()
	if document == null:
		_place_lights_and_smoke()
		return
	refresh(Rect2i(0, 0, document.samples_x(), document.samples_z()))


## Re-plans the blocks the samples of `sample_rect` touch (a stroke's frame, an undo), and those
## whose points read the mask there through the placement warp, then re-shares the budget: a
## block whose share changed is drawn again.
func refresh(sample_rect: Rect2i) -> void:
	if document == null or not sample_rect.has_area():
		return
	var step := document.sample_step()
	var reach := PLACE_WARP.y + JITTER * FLAME_SPACING_M
	var touched := blocks_of(document, sample_rect.grow(ceili(reach / minf(step.x, step.y)) + 1))
	for block in touched:
		var plan := plan_block(document, block)
		if plan.is_empty():
			_plans.erase(block)
			_cells.erase(block)
		else:
			_plans[block] = plan
			_cells[block] = FireClusters.cells_of(plan)
	var planned := {}
	for block in _plans:
		@warning_ignore("integer_division")
		planned[block] = (_plans[block] as PackedFloat32Array).size() / STRIDE
	_update_heat(touched)
	var shares := budget_shares(planned, MAX_FLAMES)
	var stale: Array = _counts.keys()
	for block in shares:
		if not block in stale:
			stale.append(block)
	for block in stale:
		var share := int(shares.get(block, 0))
		# A neighbour of a re-planned block is drawn again too: its flames' heat may have changed.
		if _beside(block, touched) or share != int(_counts.get(block, 0)):
			_show(block, share)
	_bind_glow()
	_place_lights_and_smoke()


## Flames (and sparks) shown on the whole map.
func flame_count() -> int:
	var total := 0
	for block in _counts:
		total += int(_counts[block])
	return total


## The fire's lights (null before the first fire), for probes and tests.
func lights() -> FireLights:
	return _lights


## The fire's smoke (null before the first fire), for probes and tests.
func smoke() -> FireFieldSmoke:
	return _smoke


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
## value noise about CLUMP_CELL_M across, spread so both ends occur. Its lattices are turned off
## the map's axes and the point is first moved by a broad noise (CLUMP_WARP), so a clump is a
## blob whose edge follows no lattice line: on the axes, clumps stood as hedges along the game
## camera's diagonals. Pure.
static func clump(map_seed: int, p: Vector2) -> float:
	var wq := p / CLUMP_WARP.x
	var warp := Vector2(
		_value_noise(map_seed + 9, wq) - 0.5, _value_noise(map_seed + 10, wq + Vector2(5.3, 1.7)) - 0.5
	)
	var q := (p + warp * CLUMP_WARP.y).rotated(CLUMP_TURN.x) / CLUMP_CELL_M
	var fine := q.rotated(CLUMP_TURN.y) * 2.3
	var v := 0.7 * _value_noise(map_seed + 7, q) + 0.3 * _value_noise(map_seed + 8, fine)
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
	var own := (MaskBrush.sample_noise(map_seed + 5, key) - 0.5) * 2.0 * SCALE_JITTER
	var layout: int
	var scale: float
	if heat < BLAZE_MIN:
		var strength := (heat - FLAME_MIN) / float(BLAZE_MIN - FLAME_MIN)
		var gap := lerpf(FLAME_GAP.x, FLAME_GAP.y, strength)
		if c < gap:
			return PackedFloat32Array()
		# Small at a clump's edge, big in its middle, each flame a little off its neighbours.
		scale = lerpf(CLUMP_SCALE.x, CLUMP_SCALE.y, clampf((c - gap) / (1.0 - gap) + own, 0.0, 1.0))
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
			var place := (c - BLAZE_GAP) / (1.0 - BLAZE_GAP) + own
			scale = lerpf(CLUMP_SCALE.x, CLUMP_SCALE.y, clampf(place, 0.0, 1.0))
			layout = LAYOUT_THREE if size < 0.65 else LAYOUT_CROWN
			width_share = lerpf(BLAZE_WIDTH_FROM, WIDTH_SHARE.y, size)
	else:
		return PackedFloat32Array()
	var height := base_height(t) * scale
	return PackedFloat32Array([0, 0, 0, t, layout + seed, height, height * width_share, FLAME])


## The heat raster's size for `doc` (texels; see HEAT_STEP_M). Pure.
static func heat_size(doc: MapDocument) -> Vector2i:
	var extent := doc.extent_m()
	return Vector2i(ceili(extent.x / HEAT_STEP_M) + 1, ceili(extent.y / HEAT_STEP_M) + 1)


## Adds the flames of `plan` (document metres; `half` the map's half extent) to the heat raster
## `heat` of `size` texels, and to the feet's pools `pools` when it has the same size, inside
## texel rect `clip` only (sparks add nothing).
static func splat_heat(
	heat: PackedFloat32Array,
	size: Vector2i,
	half: Vector2,
	plan: PackedFloat32Array,
	clip: Rect2i,
	pools := PackedFloat32Array()
) -> void:
	var with_pools := pools.size() == heat.size()
	@warning_ignore("integer_division")
	for k in plan.size() / STRIDE:
		var o := k * STRIDE
		if plan[o + KIND] == SPARK:
			continue
		var at := (Vector2(plan[o], plan[o + 2]) + half) / HEAT_STEP_M
		var width := plan[o + WIDTH]
		var r := (HEAT_REACH.x + HEAT_REACH.y * width) / HEAT_STEP_M
		_splat(heat, size, at, r, plan[o + HEIGHT], clip)
		if with_pools:
			_splat(pools, size, at, (POOL_REACH.x + POOL_REACH.y * width) / HEAT_STEP_M, 1.0, clip)


## Adds `amount` under a soft kernel of radius `r` texels at texel point `at` to `raster`.
static func _splat(
	raster: PackedFloat32Array, size: Vector2i, at: Vector2, r: float, amount: float, clip: Rect2i
) -> void:
	var x0 := maxi(ceili(at.x - r), clip.position.x)
	var x1 := mini(floori(at.x + r), clip.end.x - 1)
	var z0 := maxi(ceili(at.y - r), clip.position.y)
	var z1 := mini(floori(at.y + r), clip.end.y - 1)
	var inv := 1.0 / (r * r)
	for z in range(z0, z1 + 1):
		for x in range(x0, x1 + 1):
			var d := 1.0 - (Vector2(x, z) - at).length_squared() * inv
			if d > 0.0:
				raster[z * size.x + x] += amount * d * d


## The bed's temperature (0..1) in heat raster `heat` (`size` texels) at document point `p`
## (`half` the map's half extent). Pure.
static func heat_at(heat: PackedFloat32Array, size: Vector2i, half: Vector2, p: Vector2) -> float:
	if heat.size() != size.x * size.y or size.x < 2 or size.y < 2:
		return 0.0
	var t := ((p + half) / HEAT_STEP_M).clamp(Vector2.ZERO, Vector2(size - Vector2i.ONE))
	var x0 := mini(floori(t.x), size.x - 2)
	var z0 := mini(floori(t.y), size.y - 2)
	var f := t - Vector2(x0, z0)
	var i := z0 * size.x + x0
	var top := lerpf(heat[i], heat[i + 1], f.x)
	var bottom := lerpf(heat[i + size.x], heat[i + size.x + 1], f.x)
	return clampf(lerpf(top, bottom, f.y) / HEAT_FULL_M, 0.0, 1.0)


## Whether `block` is one of `blocks` or next to one (eight ways).
static func _beside(block: Vector2i, blocks: Array[Vector2i]) -> bool:
	for other in blocks:
		if absi(other.x - block.x) <= 1 and absi(other.y - block.y) <= 1:
			return true
	return false


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
	var plan: PackedFloat32Array = _plans[block]
	var half := document.extent_m() * 0.5
	var feet := PackedFloat32Array()
	feet.resize(shown)
	for k in shown:
		var o := k * STRIDE
		feet[k] = heat_at(_heat, _heat_size, half, Vector2(plan[o], plan[o + 2]))
	FireLook.fill_chunk(chunk, plan, shown, _forward(), feet)
	_counts[block] = shown


## Re-splats the heat raster around the re-planned blocks `touched` (all of it when its size
## changed) and uploads it.
func _update_heat(touched: Array[Vector2i]) -> void:
	var size := heat_size(document)
	var clip := Rect2i(Vector2i.ZERO, size)
	var whole := size != _heat_size
	if whole:
		_heat_size = size
		_heat = PackedFloat32Array()
		_heat.resize(size.x * size.y)
		_pools = PackedFloat32Array()
		_pools.resize(size.x * size.y)
	else:
		var step := document.sample_step()
		var grow := Vector2i(HEAT_GROW, HEAT_GROW)
		var area := Rect2i()
		for block in touched:
			var r := MaskStroke.block_rect(document, block)
			var lo := Vector2i((Vector2(r.position) * step / HEAT_STEP_M).floor()) - grow
			var hi := Vector2i((Vector2(r.end) * step / HEAT_STEP_M).ceil()) + grow
			var box := Rect2i(lo, hi - lo)
			area = box if area.size == Vector2i.ZERO else area.merge(box)
		clip = area.intersection(clip)
		for z in range(clip.position.y, clip.end.y):
			for x in range(clip.position.x, clip.end.x):
				_heat[z * size.x + x] = 0.0
				_pools[z * size.x + x] = 0.0
	var half := document.extent_m() * 0.5
	for block in _plans:
		if whole or _beside(block, touched):
			splat_heat(_heat, size, half, _plans[block], clip, _pools)
	_heat_texture = FireLook.heat_texture(_heat, size, HEAT_FULL_M, _heat_texture, _pools)


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
			FireLook.bind_glow(terrain.get_material(), _glow_texture, _heat_texture)
			return


## Stands the lights over the largest burning clusters and the smoke over the largest blaze
## ones (FireClusters, from the kept per-block sums); both are made with the first fire and
## kept, empty, after it goes out.
func _place_lights_and_smoke() -> void:
	var cells := FireClusters.merge(_cells)
	var lit := FireClusters.lights(cells)
	var smoky := FireClusters.smoke(cells)
	if _lights == null:
		if lit.is_empty() and smoky.is_empty():
			return
		_lights = FireLights.new()
		add_child(_lights)
		_smoke = FireFieldSmoke.new()
		add_child(_smoke)
	if document != null:
		_smoke.drift = FireLook.smoke_drift(document.map_seed)
	_lights.place(lit)
	_smoke.place(smoky)


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
				# The mask is read through a broad warp (PLACE_WARP), so a straight pass's flames
				# wander across its width.
				var wq := p / PLACE_WARP.x
				var wander := Vector2(
					FireField._value_noise(doc.map_seed + 12, wq) - 0.5,
					FireField._value_noise(doc.map_seed + 13, wq + Vector2(2.9, 7.1)) - 0.5
				)
				var read := p + wander * 2.0 * PLACE_WARP.y
				heat[i] = FireField._bilinear(
					doc.fire_mask, doc.samples_x(), doc.samples_z(), (read + half) / step
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
