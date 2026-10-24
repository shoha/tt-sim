class_name FireField
extends Node3D

## The persistent ground fire of a map document, drawn (MapDocument.fire_mask; design:
## docs/plans/2026-10-11-fire-features/design.md section 4). One per map with a document, a
## child of the map root (MapSourceLoader adds it), so its frame is the document's. It owns
## placement, chunks and the budget; FireLook owns the meshes, the materials and the fire book.
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
## What stands there is FireFires' (the reference fit's fewer, bigger fires; its header): the
## ember band gets no flames (the ground's glow draws it), only a spark at about one point in
## SPARK_EVERY; in the flames band each clump of a low-frequency clump noise (clump, about
## CLUMP_CELL_M across, its lattices turned and warped off the map's axes so clumps are blobs,
## not hedges; it drops the points where it is lowest) stands one big fire, and the ragged
## edges keep single stragglers; in a blaze every lattice point stands this field's own flame
## (_flame: the point whose clump value tops its eight lattice neighbours a big flame,
## BIG_SCALE, the blaze points beside it licks at its feet, LICK_SCALE, the rest scaled through
## the clump range), shrunk and widened so they merge into one mass. Each plan is emitted
## shuffled (ordered by its points' seeds), so any prefix of it is an even thinning.
##
## A base fire unifies the flames (the user's 2026-10-16 verdict): the flames' heat raster
## (HEAT_STEP_M) sums each planned flame's height under a soft kernel, re-splatted around the
## region a refresh re-plans. The ground burns as a bed on that summed heat
## (fire_glow.gdshaderinc), and each drawn flame carries the heat at its foot, so a fire on a hot,
## merged bed takes its shape jitter whole, shifts its colour bands and keeps its core's bloom by
## day (fire_flames.gdshader): a crowded clump reads as one hotter body. A second raster on
## the same grid, the feet's pools (POOL_REACH, round 4), marks where flames stand, so the
## ground glows under every foot and stays dark crust between. The rasters come
## from the whole plans (not the budget's prefix), so thinning does not dim the bed. A peer
## that refreshed stroke by stroke and one that rebuilt hold the same plans and the same raster
## bytes (plan_digest): a refresh re-plans every block whose fires a changed mask can reach
## (blocks_to_replan), clears the rasters as far as those blocks' fires reach (HEAT_GROW) and
## re-splats every block that reaches into the cleared rect, in row order, so each texel sums
## its flames in the same order however the plans were made.
##
## Budget: the whole map shows at most MAX_FLAMES. Past it every burning block shows the same
## share of its plan (budget_shares: a uniform thinning in proportion to each block's burning
## area, as FoliageBudget.plan; the remainder by largest fraction, ties in block order), a pure
## function of all the plans, so a peer that rebuilt once and one that refreshed stroke by
## stroke show the same flames. There is no LOD: every zoom draws the same fires, and nothing
## runs per flame per frame.
##
## The flames draw from the fire book (FireLook): a field in the tree asks for it with its
## first fire (request_book), polls its threaded load each frame until it is bound, and is
## counted while it is in the tree, so the last field to leave lets the book go.
##
## Lights, smoke and sound (look card F4b-1, cards F7 and F7b): each re-planned block's flames are
## summed on the clusters' grid (FireClusters.cells_of, kept per block), and every refresh finds
## the hot spots from those sums: FireLights stands up to four warm lights over the largest burning
## clusters (shown only while the sun is low), FireFieldSmoke raises a leaning plume from the smoke
## book over up to eight of the largest blaze clusters, and FireSound plays the fire's roar loop at
## the two strongest clusters near the view. All three are children, made with the first fire and
## freed with the map; their per-frame work is the lights' flicker and the sound's fades (the smoke
## moves in its shader). The field is in GROUP, so the drag ruler finds the document's fire under
## a drop (DragRuler.in_fire, through mask_at, card F7a). The ground's fire term reads everything
## of it that does not change with time from the sim bake (FireNoiseBake, cards F4b-4 and
## ground-cost), also a child, made with the first fire mask and bound once drawn; each refresh
## redraws it over the region it re-planned, and the field's leaving the tree lets the ground go
## of it.
##
## A refresh's pure half (FirePlanJob: the re-plan, the cluster sums, the rasters) runs on a
## WorkerThreadPool task with `use_worker` (the authoring and play-time editors set it, as they
## do the water's), from a snapshot of the document, and lands on a later frame (_process, or
## at once from finish_work()); refreshes asked for meanwhile are merged into the next job.
## Without it (tests, probes, a load's rebuild) the same function runs at once on this thread.

const NODE_NAME := "FireField"
## The group every field made by create() is in (one per map).
const GROUP := &"fire_fields"
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
## A face steeper than this does not burn (the cliff rule's start), and the up component of a
## face's normal at it (its cosine as a literal, so no platform's cos moves a fire).
const STEEP_DEG := TerrainRules.CLIFF_START_DEG
const STEEP_NORMAL_Y := 0.719339800339
## Floats per planned flame, and where each sits: x, y, z (document metres), intensity 0..1,
## seed (0..1, from the map seed and the lattice point; the shader's picks hash it), height and
## width (metres), kind (FLAME, SPARK).
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
## the turns of its two octaves' lattices off the map's axes (CLUMP_TURN, radians), each held
## as its (cos, sin) in literals so no platform's sin or cos moves a clump.
const CLUMP_WARP := Vector2(6.0, 3.0)
const CLUMP_TURN := Vector2(0.56, 1.21)
const CLUMP_TURN_A := Vector2(0.847255111013, 0.531186197921)
const CLUMP_TURN_B := Vector2(0.353019401219, 0.935616001553)
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
## narrow kernel reaching POOL_REACH.x plus POOL_REACH.y of its width (a pool of light about
## twice a fire's width); uploaded clamped to 1.
const POOL_REACH := Vector2(0.4, 0.85)
## Texels a block's flames can reach past it with their kernels, so the cleared rect of a
## refresh reaches this far past its blocks: FireFires' largest fire (about 3.4 m tall and 3.7 m
## wide) stands up to 1.8 m off its block and its heat kernel reaches 4.7 m
## (FireFires.heat_reach_m, 6.48 m).
const HEAT_GROW := 13
## Texels round a block its flames' feet read the heat raster at (each drawn flame carries the
## heat at its foot): FireFires.spill_m and the bilinear read's next texel.
const FEET_GROW := 5
## Metres the sim bake's redraw reaches past a refresh's blocks: the rasters' cleared rect
## (HEAT_GROW texels) and their B-spline, and the ground's mask reads (the wander, the fill's
## taps and the early-out's rings, under 6 m together).
const BAKE_REACH_M := 8.0
## Lattice points a block's window reaches past its own (a lick looks two points out).
const WINDOW_MARGIN := 2

var document: MapDocument = null
## Whether refreshes plan on a worker (see the header).
var use_worker := false
## block Vector2i -> the block's whole plan, for burning blocks only.
var _plans: Dictionary = {}
## block Vector2i -> MultiMeshInstance3D, for blocks that show something.
var _chunks: Dictionary = {}
## block Vector2i -> flames shown there.
var _counts: Dictionary = {}
var _glow_texture: ImageTexture = null
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
var _sound: FireSound = null
## The ground fire's bakes (made with the first fire mask).
var _noise: FireNoiseBake = null
## The refresh planning on a worker (null: none) and the samples asked for while it runs.
var _job: FirePlanJob = null
var _queued := Rect2i()


## A field for `doc`, already planned and drawn.
static func create(doc: MapDocument) -> FireField:
	var field := FireField.new()
	field.name = NODE_NAME
	field.document = doc
	field.add_to_group(GROUP)
	field.rebuild()
	return field


func _enter_tree() -> void:
	FireLook.hold_book()
	if not _plans.is_empty():
		FireLook.request_book()
	# Back in the tree (_exit_tree let the ground go of the bake).
	if is_node_ready():
		_bind_glow()


func _ready() -> void:
	if document != null:
		FireLook.set_wind(document.map_seed)
	_bind_glow()


func _process(_delta: float) -> void:
	FireLook.poll_book()
	if _job != null and WorkerThreadPool.is_task_completed(_job.task):
		_finish_job()


func _exit_tree() -> void:
	# A job's task must not outlive the field that holds it.
	finish_work()
	FireLook.drop_book()
	_unbind_glow()


## Re-plans the whole map (after a load or a whole-document change), at once on this thread.
func rebuild() -> void:
	finish_work()
	for block in _chunks:
		(_chunks[block] as Node).free()
	_chunks.clear()
	_counts.clear()
	_plans.clear()
	_cells.clear()
	if document == null:
		_place_lights_and_smoke()
		return
	var job := _job_for(Rect2i(0, 0, document.samples_x(), document.samples_z()))
	job.compute()
	_land(job)


## Re-plans the blocks the samples of `sample_rect` touch (a stroke's frame, an undo), and those
## whose points read the mask there through the placement warp, then re-shares the budget: a
## block whose share changed is drawn again. With use_worker the re-plan runs on a worker and
## lands on a later frame (see the header).
func refresh(sample_rect: Rect2i) -> void:
	if document == null or not sample_rect.has_area():
		return
	if _job != null:
		_queued = sample_rect if not _queued.has_area() else _queued.merge(sample_rect)
		return
	var job := _job_for(sample_rect)
	if use_worker:
		job.task = WorkerThreadPool.add_task(job.compute, false, "Fire re-plan")
		_job = job
		return
	job.compute()
	_land(job)


## Whether a refresh is planning on a worker or waiting to.
func is_working() -> bool:
	return _job != null


## Lands the refresh in progress and any asked for meanwhile, at once (waiting for the worker).
func finish_work() -> void:
	while _job != null:
		_finish_job()


## A job re-planning the blocks the samples of `sample_rect` reach (see refresh).
func _job_for(sample_rect: Rect2i) -> FirePlanJob:
	var touched := blocks_to_replan(document, sample_rect)
	return FirePlanJob.make(document, touched, _plans, _heat, _pools, _heat_size)


## The blocks whose plans a change to the mask's samples `sample_rect` can change, row by row: a
## lattice point reads the mask through the placement warp (PLACE_WARP.y, plus its jitter and
## the bilinear read's sample), and a FireFires decision reads the window's points up to
## FireFires.MARGIN lattice points away (about 8.7 m together). Pure.
static func blocks_to_replan(doc: MapDocument, sample_rect: Rect2i) -> Array[Vector2i]:
	var step := doc.sample_step()
	var points := maxi(FireFires.MARGIN, WINDOW_MARGIN) + JITTER
	var reach := PLACE_WARP.y + points * FLAME_SPACING_M
	return blocks_of(doc, sample_rect.grow(ceili(reach / minf(step.x, step.y)) + 1))


## Waits for the job in flight, lands it and starts the next for the samples queued meanwhile.
func _finish_job() -> void:
	var job := _job
	_job = null
	if job.task >= 0:
		WorkerThreadPool.wait_for_task_completion(job.task)
	_land(job)
	if _queued.has_area():
		var next := _queued
		_queued = Rect2i()
		refresh(next)


## Installs `job`'s plans, cluster sums and rasters, re-shares the budget, draws the blocks
## whose share or neighbourhood changed, redraws the ground's bake there and moves the lights
## and smoke.
func _land(job: FirePlanJob) -> void:
	if document == null:
		return
	var touched := job.touched
	for block in touched:
		var plan: PackedFloat32Array = job.planned[block]
		if plan.is_empty():
			_plans.erase(block)
			_cells.erase(block)
		else:
			_plans[block] = plan
			_cells[block] = job.cells[block]
	if is_inside_tree() and not _plans.is_empty():
		FireLook.request_book()
	# The rasters changed inside the cleared rect only (all of them with a new size).
	var cleared := Rect2i(Vector2i.ZERO, job.heat_size)
	if job.heat_size == _heat_size:
		cleared = cleared_rect(document, touched)
	_heat = job.heat
	_pools = job.pools
	_heat_size = job.heat_size
	_heat_texture = FireLook.raster_texture(job.heat_bytes, _heat_size, _heat_texture)
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
		# A block whose flames stand where the rasters changed is drawn again too: the heat at
		# their feet may have changed.
		var feet := raster_box(document, block, FEET_GROW)
		if feet.intersects(cleared) or share != int(_counts.get(block, 0)):
			_show(block, share)
	_bind_glow()
	if _noise != null:
		_noise.rebake(bake_region(document, touched))
	_place_lights_and_smoke()


## The document region (map-frame metres) whose ground bake a refresh of blocks `touched`
## changes: the blocks grown by BAKE_REACH_M. Pure.
static func bake_region(doc: MapDocument, touched: Array[Vector2i]) -> Rect2:
	var step := doc.sample_step()
	var half := doc.extent_m() * 0.5
	var region := Rect2()
	for block in touched:
		var r := MaskStroke.block_rect(doc, block)
		var box := Rect2(-half + Vector2(r.position) * step, Vector2(r.size) * step)
		region = box if not region.has_area() else region.merge(box)
	return region.grow(BAKE_REACH_M) if region.has_area() else region


## A stable hash of the field's landed plans and rasters (hex SHA-256 over the burning blocks in
## row order with their plans, then the rasters' size and bytes): equal on every peer holding the
## same fire, whether it refreshed stroke by stroke or rebuilt. Read it once is_working() is
## false (finish_work()); for tests and the net check.
func plan_digest() -> String:
	var bytes := PackedByteArray()
	for block: Vector2i in row_order(_plans.keys()):
		bytes.append_array(PackedInt32Array([block.x, block.y]).to_byte_array())
		bytes.append_array((_plans[block] as PackedFloat32Array).to_byte_array())
	bytes.append_array(PackedInt32Array([_heat_size.x, _heat_size.y]).to_byte_array())
	bytes.append_array(_heat.to_byte_array())
	bytes.append_array(_pools.to_byte_array())
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(bytes)
	return hashing.finish().hex_encode()


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


## The fire's sound (null before the first fire), for probes and tests.
func sound() -> FireSound:
	return _sound


## The fire mask of `doc` at document point `p` (metres, the map's frame), read bilinearly as the
## flames read it (without their wander): 0..255, 0 off the map or without a mask. Pure.
static func mask_at(doc: MapDocument, p: Vector2) -> float:
	if doc == null or doc.fire_mask.size() != doc.sample_count():
		return 0.0
	var half := doc.extent_m() * 0.5
	if absf(p.x) > half.x or absf(p.y) > half.y:
		return 0.0
	return _bilinear(doc.fire_mask, doc.samples_x(), doc.samples_z(), doc.world_to_sample(p))


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
	var q := _turn(p + warp * CLUMP_WARP.y, CLUMP_TURN_A) / CLUMP_CELL_M
	var fine := _turn(q, CLUMP_TURN_B) * 2.3
	var v := 0.7 * _value_noise(map_seed + 7, q) + 0.3 * _value_noise(map_seed + 8, fine)
	return smoothstep(0.22, 0.78, v)


## The fires of diff block `block` of `doc` (FireFires.plan_block; see the header): STRIDE
## floats each, shuffled. Pure and deterministic; empty without a fire mask.
static func plan_block(doc: MapDocument, block: Vector2i) -> PackedFloat32Array:
	return FireFires.plan_block(doc, block)


## `v` turned by the turn whose (cos, sin) is `turn`.
static func _turn(v: Vector2, turn: Vector2) -> Vector2:
	return Vector2(v.x * turn.x - v.y * turn.y, v.x * turn.y + v.y * turn.x)


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


## The own flame of lattice point `i` of `window` at mask value `heat` (FireFires stands it in the
## ember band and the blaze): an ember point's spark, a blaze point's flame, or empty where none
## stands (an ember point with no spark, a blaze point in its clump's gap, a flames-band point).
## Its x, y, z and seed (plan_seed) are filled by the caller.
static func _flame(
	map_seed: int, key: int, heat: float, window: LatticeWindow, i: int
) -> PackedFloat32Array:
	var pick := MaskBrush.sample_noise(map_seed + 3, key)
	var t := heat / 255.0
	var c := window.clump[i]
	if heat < FLAME_MIN:
		if pick * SPARK_EVERY >= 1.0:
			return PackedFloat32Array()
		return PackedFloat32Array([0, 0, 0, t, 0, SPARK_SIZE_M, SPARK_SIZE_M, SPARK])
	var size := pick
	var width_share := lerpf(WIDTH_SHARE.x, WIDTH_SHARE.y, MaskBrush.sample_noise(map_seed + 4, key))
	var own := (MaskBrush.sample_noise(map_seed + 5, key) - 0.5) * 2.0 * SCALE_JITTER
	var clump_scale: float
	if window.big(i):
		clump_scale = lerpf(BIG_SCALE.x, BIG_SCALE.y, c)
		width_share = lerpf(BLAZE_WIDTH_FROM, WIDTH_SHARE.y, size)
	elif window.blaze(i):
		if window.beside_big(i):
			clump_scale = lerpf(LICK_SCALE.x, LICK_SCALE.y, size)
		else:
			var place := (c - BLAZE_GAP) / (1.0 - BLAZE_GAP) + own
			clump_scale = lerpf(CLUMP_SCALE.x, CLUMP_SCALE.y, clampf(place, 0.0, 1.0))
			width_share = lerpf(BLAZE_WIDTH_FROM, WIDTH_SHARE.y, size)
	else:
		return PackedFloat32Array()
	var height := base_height(t) * clump_scale
	return PackedFloat32Array([0, 0, 0, t, 0, height, height * width_share, FLAME])


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


## The heat raster's texels the flames of `block` of `doc` can reach: its rect grown by `grow`
## texels (HEAT_GROW: their kernels; FEET_GROW: the texels their feet read). Pure.
static func raster_box(doc: MapDocument, block: Vector2i, grow := HEAT_GROW) -> Rect2i:
	var step := doc.sample_step()
	var r := MaskStroke.block_rect(doc, block)
	var lo := Vector2i((Vector2(r.position) * step / HEAT_STEP_M).floor()) - Vector2i.ONE * grow
	var hi := Vector2i((Vector2(r.end) * step / HEAT_STEP_M).ceil()) + Vector2i.ONE * grow
	return Rect2i(lo, hi - lo)


## The texels a refresh of blocks `touched` of `doc` clears and re-splats: every texel their
## flames, old or new, can reach (the raster_box rects merged), clipped to the raster. Pure.
static func cleared_rect(doc: MapDocument, touched: Array[Vector2i]) -> Rect2i:
	var area := Rect2i()
	for block in touched:
		var box := raster_box(doc, block)
		area = box if area.size == Vector2i.ZERO else area.merge(box)
	return area.intersection(Rect2i(Vector2i.ZERO, heat_size(doc)))


## `blocks` (Vector2i) sorted in row order: by row, then column.
static func row_order(blocks: Array) -> Array:
	var out := blocks.duplicate()
	out.sort_custom(
		func(p: Vector2i, q: Vector2i) -> bool: return p.y < q.y or (p.y == q.y and p.x < q.x)
	)
	return out


## The seed (0..1) of the fire standing on lattice point (ix, iz) of a map with `map_seed`: each
## index hashed in turn, so no two points share one. (The lattice key folds (ix, iz) and
## (-ix, -iz) together when both are odd, so a seed from it would stamp point-mirrored fires
## beside the map's middle with one drawing.) The flames' shader hashes it for every pick
## (FireLook.fire_seed). Pure.
static func plan_seed(map_seed: int, ix: int, iz: int) -> float:
	# 31 bits, so sample_noise's product stays inside a 64-bit int.
	var row := int(MaskBrush.sample_noise(map_seed + 2, iz) * 2147483648.0)
	return MaskBrush.sample_noise(row, ix) * 0.999


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


## The heat raster `heat` and the pools `pools` (`old_size` texels; written in place, so pass
## copies) of `doc` re-splatted from `plans` (block -> plan) over the cleared rect of the
## re-planned blocks `touched` (cleared_rect), or whole when the raster's size changed:
## {"heat", "pools", "size"}. Every block reaching into the cleared rect is splatted there, in
## row order, so the bytes equal a whole re-splat's.
static func resplat(
	doc: MapDocument,
	plans: Dictionary,
	touched: Array[Vector2i],
	heat: PackedFloat32Array,
	pools: PackedFloat32Array,
	old_size: Vector2i
) -> Dictionary:
	var size := heat_size(doc)
	var clip := Rect2i(Vector2i.ZERO, size)
	var whole := size != old_size
	if whole:
		heat = PackedFloat32Array()
		heat.resize(size.x * size.y)
		pools = PackedFloat32Array()
		pools.resize(size.x * size.y)
	else:
		clip = cleared_rect(doc, touched)
		for z in range(clip.position.y, clip.end.y):
			for x in range(clip.position.x, clip.end.x):
				heat[z * size.x + x] = 0.0
				pools[z * size.x + x] = 0.0
	var half := doc.extent_m() * 0.5
	# In row order, not the Dictionary's (a refresh appends a newly burning block last): every
	# texel sums its flames in the same order on a refreshed peer and a rebuilt one.
	for block: Vector2i in row_order(plans.keys()):
		if whole or raster_box(doc, block).intersects(clip):
			splat_heat(heat, size, half, plans[block], clip, pools)
	return {"heat": heat, "pools": pools, "size": size}


## The camera's forward axis in this node's frame (the game camera never turns).
func _forward() -> Vector3:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return FireLook.DEFAULT_FORWARD.normalized()
	return (global_basis.inverse() * -camera.global_basis.z).normalized()


## The ground's glow follows the mask: the sim bake bound to the sibling AuthoredTerrain's
## material.
func _bind_glow() -> void:
	var material := _ground_material()
	if material == null or document == null:
		return
	_glow_texture = FireLook.glow_texture(document, _glow_texture)
	if _glow_texture != null:
		_ensure_noise()
	if _noise == null:
		FireLook.bind_glow(material, null, Vector4.ZERO)
		return
	var half := document.extent_m() * 0.5
	_noise.set_inputs(_glow_texture, _heat_texture, -half, document.sample_step())
	var sim_map := _noise.sim_texture() if _glow_texture != null else null
	FireLook.bind_glow(material, sim_map, _noise.sim_rect())


## Lets the ground go of this field's bake when it leaves the tree (the last field's leaving
## lets go of the book too): the terrain's material samples it no longer.
func _unbind_glow() -> void:
	var material := _ground_material()
	if material == null or _noise == null:
		return
	var bound: Variant = material.get_shader_parameter("fire_sim_map")
	if FireLook.live_fields() == 0 or (bound != null and bound == _noise.sim_texture()):
		FireLook.bind_glow(material, null, Vector4.ZERO)


## The sibling AuthoredTerrain's material (null without one).
func _ground_material() -> ShaderMaterial:
	var parent := get_parent()
	if parent == null:
		return null
	for child in parent.get_children():
		var terrain := child as AuthoredTerrain
		if terrain != null and terrain.get_material() != null:
			return terrain.get_material()
	return null


## Bakes the ground fire's terms for the map's extent (FireNoiseBake) the first time the map
## has a fire mask, and again when the extent changed; its drawing binds the glow again.
func _ensure_noise() -> void:
	var extent := document.extent_m()
	if _noise != null and _noise.sim_rect() == FireNoiseBake.rect_for(extent, FireNoiseBake.SIM_PER_M):
		return
	if _noise == null:
		_noise = FireNoiseBake.new()
		add_child(_noise)
		_noise.baked.connect(_bind_glow)
	_noise.bake(document.extent_m())


## Stands the lights over the largest burning clusters and the smoke over the largest blaze
## ones (FireClusters, from the kept per-block sums), and hands every burning cluster to the
## sound, which picks the strongest near the view; all three are made with the first fire and
## kept, empty, after it goes out.
func _place_lights_and_smoke() -> void:
	var cells := FireClusters.merge(_cells)
	var burning := FireClusters.find(cells, false)
	var lit := burning.slice(0, FireClusters.MAX_LIGHTS)
	var smoky := FireClusters.smoke(cells)
	if _lights == null:
		if lit.is_empty() and smoky.is_empty():
			return
		_lights = FireLights.new()
		add_child(_lights)
		_smoke = FireFieldSmoke.new()
		add_child(_smoke)
		_sound = FireSound.new()
		add_child(_sound)
	if document != null:
		FireFieldSmoke.set_wind(document.map_seed)
	_lights.place(lit)
	_smoke.place(smoky)
	_sound.place(burning, FireClusters.spots(cells))


## The lattice around one block (`margin` points past it on every side, WINDOW_MARGIN at least;
## FireFires reads FireFires.MARGIN): each point's jittered spot, its mask value and its clump
## value, so a point can see its neighbours across the block's edge without reading another
## block's plan.
class LatticeWindow:
	var origin: Vector2i
	var width: int
	var px := PackedFloat32Array()
	var pz := PackedFloat32Array()
	var heat := PackedFloat32Array()
	var clump := PackedFloat32Array()

	func _init(doc: MapDocument, first: Vector2i, end: Vector2i, margin := WINDOW_MARGIN) -> void:
		origin = first - Vector2i(margin, margin)
		var last := end + Vector2i(margin, margin)
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
