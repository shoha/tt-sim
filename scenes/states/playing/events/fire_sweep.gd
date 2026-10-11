class_name FireSweep
extends ForestFall

## A fire sweeping through a forest (TerrainEvent.Kind.FIRE), played on one board. The trees
## are found, hidden in their chunks and drawn by stand-ins as ForestFall's are (the burnt
## biome's own snags are passed over: a burnt forest does not burn again), and the fire runs
## out from the centre as a front: the nearest tree catches first, the farthest SPREAD_S
## later.
##
## The fire reads through the trees themselves. A stand-in draws a copy of its tree's mesh
## whose surfaces use shaders/wind_foliage_burn.gdshader, and each tree's burn (burn_progress,
## the instance's custom data) runs its crown through the burn in bold patches: hot yellow
## along the leading edge, ember red-orange, then charcoal, the leaf cards burning away from a
## glowing edge until the charred trunk and limbs stand bare (the bark only chars).
##
## Its flames, its ground fire and its smoke are one family: one noise, one erosion rule
## (shaders/fire_noise.gdshaderinc: a shape eaten by the noise as it ages, its edge a crisp
## step, never an alpha fade) and one palette running from the flames' stepped bands (a deep
## red rim, amber, gold, a pale core) through the ember glow to warm charcoal smoke going pale
## as it rises. Small banded tongues (EventPuffs' crown flame, red, orange and amber, no pale
## core) rise among each crown's leaf cards as the burn climbs it, sized by the crown's width
## so a narrow pine's stay in its crown, and a spark drifts up from a few. On the ground a
## glowing ring runs out
## with the front (GroundBurn), small tongues standing on it where it passes (FRONT_TONGUES),
## charred ground left inside it until the ash lands. Billows of smoke (SmokePuffs) rise from
## half the trees and in a short column over the middle: smoke crowns, each a cluster of small
## painted puff cards built and lit the way the trees' crowns are, born about a crown across,
## breaking up card by card as they age. Over the event's last SNAG_GO_S the
## charred snags shrink away (snag_transform) as the change lands.
##
## Colours are linear, as every puff's and shader constant's is: each is picked as the colour
## it should show through the scene's filmic tonemap, which shows low values lighter still
## than raising them to 1/2.2 does (mid values show pale; the first look's amber and lilac read
## as cream and pink mist).
##
## The map change follows (TerrainEvents): the burnt biome painted over the area, its snags
## and litter growing in under the smoke, then ash laid over the ground (plan_for; a palette
## without them gets a Clear and the peat it has). A burnt tree is gone from its chunk when
## that change rebuilds it, as a fallen one is.
##
## Bounded: at most MAX_TREES trees, one stand-in mesh copy per species made in setup, two
## pools of fixed size made once (every flame and billow of one fire fits at once, so none is
## overwritten), one ground ring, every random draw and every ground tongue's place made in
## setup, so a frame only sets transforms, colours and custom data; no allocation while it
## plays. The burn shader's noise runs only on the stand-ins.

## The palette biome a fire leaves (its "biome" key) and the ground it lays, or the stand-in
## an older palette has (ASSET_PIPELINE.md "Fire").
const BURNT_BIOME := "burnt_forest"
const ASH := "ash"
const ASH_FALLBACK := "dirt_peat"
## The burnt biome's paint: one dab this many times the radius, this long (the biome takes the
## ground to about the radius and thins the forest past it, MaskStroke's contest), and the
## ash's (a soft edge just past the burnt ground).
const BURN_REACH := 1.2
const BURN_SECONDS := 3.0
const ASH_REACH := 1.25
const ASH_SECONDS := 2.5
## The front: the nearest tree catches at once, the farthest SPREAD_S later, each plus up to
## SPREAD_JITTER (the ring on the ground runs just ahead of the crowns).
const SPREAD_S := 2.0
const SPREAD_JITTER := 0.25
## How long a tree burns, from catching to a bare charred snag.
const BURN_S := Vector2(1.2, 1.5)
## The burn shader's progress at the end of a tree's burn (every patch has burnt through by
## about 1.55: a patch catches between 0 and 1 and its leaves are gone 0.55 after).
const BURN_RATE := 1.7
## The charred snags shrink away over the event's last this many seconds.
const SNAG_GO_S := 0.6
## A crown's flames: CROWN_TONGUES small tongues tucked among its leaf cards (EventPuffs'
## crown flame), each rising once the burn has reached its height (tongue_at; a tongue on a
## crown still green there stood as a sticker): how long it lives (a share of the tree's
## burn), where its foot stands (TONGUE_FOOT, a share of the tree's height, and up to
## TONGUE_SPREAD of the crown's width out from the trunk), its width (TONGUE_WIDE of the
## crown's, within TONGUE_BOUNDS of the tree's height) and its height over its width. One big
## tongue on a crown's flank read as a clip-art sticker (fire-look-4). No tongue reaches past
## TONGUE_TOP of the tree's height (its tip is held under it): the tongues at a crown's narrow
## top stood against the sky as flame icons (fire-look-5); the top burns through its patches.
const CROWN_TONGUES := 7
const TONGUE_LIFE := Vector2(0.3, 0.45)
const TONGUE_FOOT := Vector2(0.4, 0.74)
const TONGUE_TOP := 0.84
const TONGUE_SPREAD := 0.38
const TONGUE_WIDE := 0.25
const TONGUE_BOUNDS := Vector2(0.06, 0.11)
const TONGUE_TALL := 1.25
## The burn shader's moment for a patch at height `up`: 0.55 * up plus its noise's 0.45 share
## (CATCH_NOISE the part of it a tongue waits for, plus up to CATCH_JITTER more).
const CATCH_HEIGHT := 0.55
const CATCH_NOISE := 0.25
const CATCH_JITTER := 0.15
## When a tree throws its spark, a share of its burn.
const SPARK_AT := 0.08
## A tree's draws before its tongues' (the side, the spark, the smoke).
const DRAWS_PER_TREE := 6
## The share of trees that throw up a spark as they catch.
const EMBER_CHANCE := 0.35
## The ground fire's tongues: how many stand on the ring as it passes (their places drawn over
## the burning area in setup), their width (metres), height over width and life (seconds).
const FRONT_TONGUES := 28
const FRONT_WIDE := Vector2(0.45, 0.8)
const FRONT_TALL := 1.3
const FRONT_LIFE := Vector2(0.8, 1.15)
## When a tree's smoke rises (a share of its burn), the share of trees that smoke (none under
## SMOKE_MIN_TALL metres), a billow's size against the crown's width (it is born a little
## smaller and spreads to about twice the crown, SmokePuffs.billow_size) and how fast it climbs
## (metres a second).
const SMOKE_AT := 0.65
const SMOKE_CHANCE := 0.5
const SMOKE_MIN_TALL := 2.5
const SMOKE_SIZE := 1.0
const SMOKE_RISE := 0.6
## The column over the centre: its billows' start times (seconds) and size against the trees'
## mean height (about a crown's width; at four times the crowns it hung as balloons).
const COLUMN_AT: Array[float] = [0.8, 1.9]
const COLUMN_SIZE := 0.45
## Pools: every puff of one fire at once (flames: a crown's tongues and a spark a tree, and the
## ground's tongues; smoke: a billow a tree and the column's).
const FLAMES_PER_TREE := CROWN_TONGUES + 1
const FLAME_POOL := FLAMES_PER_TREE * MAX_TREES + FRONT_TONGUES
const SMOKE_POOL := MAX_TREES + 2
## Draw order: the flames over the water and the ring.
const FLAME_PRIORITY := EventPuffs.RENDER_PRIORITY + 2
## Colours (linear, see the header): a flame's rim (shows a deep red-orange; its bands burn
## amber, gold and a pale core inside it, the puff shader's), the second tongue's redder; a
## spark. The smoke's palette is its shader's.
const FLAME := Color(0.75, 0.047, 0.006, 1.0)
const FLAME_LATE := Color(0.61, 0.018, 0.004, 1.0)
const EMBER := Color(1.0, 0.35, 0.036, 1.0)
const BURN_SHADER := preload("res://shaders/wind_foliage_burn.gdshader")

var _flames: EventPuffs = null
var _smoke: SmokePuffs = null
var _ground: GroundBurn = null
## The way the smoke drifts (map frame, horizontal, metres a second), the stand's middle on
## the ground and its trees' mean height, drawn in setup.
var _drift := Vector3.ZERO
var _middle := Vector3.ZERO
var _tall := 1.0
var _columns := 0
## The nearest tree's distance from the centre (it catches first).
var _nearest := 0.0
## The camera's right, flat, in the map frame: a second tongue stands beside the first across
## the view, not behind it.
var _across := Vector3.RIGHT
## The ground's tongues, in the order the ring reaches them: where each stands (xyz) and when
## (w, seconds), its draw, and how many have risen.
var _front: Array[Vector4] = []
var _front_draws := PackedFloat32Array()
var _front_next := 0


## The id of the palette's burnt biome under `root`, or "" when it has none.
static func burnt_biome(root: String = PaletteLibrary.DEFAULT_ROOT) -> String:
	# Read in place, not copied (PaletteLibrary.biomes copies deep): the cursor asks often.
	var biomes: Array = PaletteLibrary.get_palette(root)["biomes"]
	return String(plan_for(biomes, {}).biome)


## The map change a fire makes with a palette of `biomes` (PaletteLibrary.biomes) and
## `surfaces` (PaletteLibrary.surfaces): {"biome": the burnt biome's id, or "" for a Clear,
## "surface": ASH, else ASH_FALLBACK, else "" (none laid)}. Pure.
static func plan_for(biomes: Array, surfaces: Dictionary) -> Dictionary:
	var biome := ""
	for entry: Dictionary in biomes:
		if String(entry.get("biome", "")) == BURNT_BIOME:
			biome = String(entry.get("id", ""))
			break
	var surface := ""
	for name_of in [ASH, ASH_FALLBACK]:
		if surfaces.has(name_of):
			surface = name_of
			break
	return {"biome": biome, "surface": surface}


## The trees a fire within `radius` of map point `centre` burns on `scatter`, the burnt
## biome's own (palette `root`) passed over (trees_near).
static func burnable(
	scatter: AuthoredScatter,
	centre: Vector2,
	radius: float,
	root: String = PaletteLibrary.DEFAULT_ROOT,
	limit: int = MAX_TREES
) -> Array[Dictionary]:
	var burnt := burnt_biome(root)
	return trees_near(scatter, centre, radius, limit, burnt + "/" if burnt != "" else "")


## The burn shader's progress for a tree `t` seconds after it caught a burn of `burn`
## seconds: 0 until it catches, BURN_RATE at the end of its burn, on past it. Pure.
static func burn_progress(t: float, burn: float) -> float:
	return maxf(t, 0.0) / maxf(burn, 0.01) * BURN_RATE


## When a crown tongue at `up` (a share of its tree's height) rises, as a share of the tree's
## burn: once the burn shader's patches there are glowing (burn_progress past CATCH_HEIGHT * up
## plus CATCH_NOISE), up to CATCH_JITTER later by `jitter` (0..1). Pure.
static func tongue_at(up: float, jitter: float) -> float:
	var progress := CATCH_HEIGHT * up + CATCH_NOISE + CATCH_JITTER * clampf(jitter, 0.0, 1.0)
	return progress / BURN_RATE


## A tree standing at `base`, `elapsed` seconds into a fire of `duration`: where it stands,
## shrinking away about its foot over the last SNAG_GO_S. Pure.
static func snag_transform(base: Transform3D, elapsed: float, duration: float) -> Transform3D:
	var x := clampf((elapsed - duration + SNAG_GO_S) / SNAG_GO_S, 0.0, 1.0)
	if x <= 0.0:
		return base
	var keep := 1.0 - smoothstep(0.0, 1.0, x)
	return Transform3D(base.basis * Basis.from_scale(Vector3.ONE * keep), base.origin)


## When the ring on the ground reaches `distance` metres from the centre, the nearest tree
## `nearest` out and the rim `radius` (GroundBurn.front_radius run backwards). Pure.
static func front_reaches(distance: float, nearest: float, radius: float) -> float:
	return SPREAD_S * clampf((distance - nearest) / maxf(radius - nearest, 0.1), 0.0, 1.0)


## Prepares the fire `event` describes on `editor`'s map; false when no forest stands there.
## Starts loading the burnt biome and the ash on every board, so the change lands warm.
func setup(editor: AuthoringEditor, event: TerrainEvent) -> bool:
	if not super(editor, event):
		return false
	name = "FireSweep"
	var heading := _rng.randf_range(0.0, TAU)
	_drift = Vector3(cos(heading), 0.0, sin(heading)) * 0.35
	var total := Vector3.ZERO
	var tall := 0.0
	for tree in _trees:
		total += (tree.base as Transform3D).origin
		tall += float(tree.height)
	_middle = total / float(_trees.size())
	_tall = maxf(tall / float(_trees.size()), 1.0)
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null:
		var right := global_basis.inverse() * camera.global_basis.x
		right.y = 0.0
		if right.length_squared() > 1e-6:
			_across = right.normalized()
	var plan := plan_for(
		PaletteLibrary.biomes(editor.palette_root), PaletteLibrary.surfaces(editor.palette_root)
	)
	if plan.biome != "":
		editor.prepare_biome(plan.biome)
	if plan.surface != "" and is_instance_valid(editor.terrain):
		editor.terrain.warm_surface(plan.surface)
	_ground = GroundBurn.new()
	add_child(_ground)
	_ground.setup(
		Vector3(event.centre.x, _middle.y, event.centre.y),
		_nearest,
		event.radius_m,
		SPREAD_S,
		duration
	)
	_place_front(editor.document, event)
	return true


## Plays the fire `elapsed` seconds in (after `delta` more seconds of flames and smoke).
func step(elapsed: float, delta: float) -> void:
	for tree in _trees:
		var t := elapsed - float(tree.start)
		var burn := float(tree.burn)
		var multimesh := (tree.stand_in as MultiMeshInstance3D).multimesh
		multimesh.set_instance_custom_data(tree.slot, Color(burn_progress(t, burn), 0.0, 0.0, 0.0))
		multimesh.set_instance_transform(tree.slot, snag_transform(tree.base, elapsed, duration))
		# A burning tree goes still (ForestFall.calm_weight's colour), as a falling one does.
		var calm := calm_weight(t, burn)
		multimesh.set_instance_color(tree.slot, Color(calm, calm, 1.0, 1.0))
		_kindle(tree, t)
	while _front_next < _front.size() and elapsed >= _front[_front_next].w:
		_front_tongue(_front_next)
		_front_next += 1
	while _columns < COLUMN_AT.size() and elapsed >= COLUMN_AT[_columns]:
		_column(_columns)
		_columns += 1
	_smoke.step(delta)
	_flames.step(delta)
	_ground.step(elapsed)
	if elapsed >= duration and not _ended:
		_ended = true
		for tree in _trees:
			(tree.stand_in as Node3D).visible = false


## True once the fire has burnt out, its smoke has cleared and its char has gone under the ash.
func is_played(elapsed: float) -> bool:
	var charred := GroundBurn.char_at(elapsed, duration) > 0.0
	return elapsed >= duration and _flames.is_idle() and _smoke.is_idle() and not charred


## The trees `event` burns (burnable).
func _find(editor: AuthoringEditor, event: TerrainEvent) -> Array[Dictionary]:
	var found := burnable(_scatter, event.centre, event.radius_m, editor.palette_root)
	_nearest = float(found[0].distance) if not found.is_empty() else 0.0
	return found


## The fire's two pools (see the header), its flames banded.
func _make_puffs() -> void:
	_smoke = SmokePuffs.new(SMOKE_POOL)
	_flames = EventPuffs.new(FLAME_POOL, FLAME_PRIORITY)
	add_child(_smoke)
	add_child(_flames)
	_flames.band_flames(true)
	_puffs = _flames


## A copy of `mesh` whose surfaces burn: each surface's own wind material, duplicated with the
## burn shader (the same textures, wind and fades, so a tree waiting for the front matches the
## one it replaced).
func _stand_in_mesh(mesh: Mesh) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for i in copy.get_surface_count():
		var source := mesh.surface_get_material(i) as ShaderMaterial
		if source == null:
			continue
		var burning := source.duplicate() as ShaderMaterial
		burning.shader = BURN_SHADER
		copy.surface_set_material(i, burning)
	return copy


## The burn of `tree` (a trees_near entry) of mesh bounds `box`, `height` metres tall, in
## `event`: when the front reaches it, how long it burns, its crown's width, and the draws its
## flames, spark and smoke take (made here, so a frame draws nothing).
func _tree_entry(tree: Dictionary, event: TerrainEvent, box: AABB, height: float) -> Dictionary:
	var base: Transform3D = tree.base
	var scale := base.basis.get_scale()
	var width := maxf(box.size.x * scale.x, box.size.z * scale.z)
	# Six for the spark and the smoke, then four for each crown tongue (when, how high, where
	# round the trunk, how far out), its rising times sorted low first.
	var draws := PackedFloat32Array()
	for i in DRAWS_PER_TREE + 4 * CROWN_TONGUES:
		draws.append(_rng.randf())
	# Each tongue's time is when the burn reaches its height (tongue_at); held in the first
	# draw, the tongues sorted by it.
	var tongues: Array[Vector4] = []
	for i in CROWN_TONGUES:
		var at := DRAWS_PER_TREE + 4 * i
		var up := lerpf(TONGUE_FOOT.x, TONGUE_FOOT.y, draws[at + 1])
		tongues.append(
			Vector4(tongue_at(up, draws[at]), draws[at + 1], draws[at + 2], draws[at + 3])
		)
	tongues.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.x < b.x)
	for i in CROWN_TONGUES:
		for j in 4:
			draws[DRAWS_PER_TREE + 4 * i + j] = tongues[i][j]
	return {
		"height": height,
		"width": clampf(width, height * 0.3, height),
		"start":
		(
			front_reaches(float(tree.distance), _nearest, event.radius_m)
			+ _rng.randf_range(0.0, SPREAD_JITTER)
		),
		"burn": _rng.randf_range(BURN_S.x, BURN_S.y),
		"draws": draws,
		"tongues": 0,
		"lit": false,
		"smoked": false,
	}


## The ground's FRONT_TONGUES places over `event`'s area on `document`'s ground, spread evenly
## over it (from the nearest tree out to the rim), each timed for when the ring reaches it and
## sorted by that time.
func _place_front(document: MapDocument, event: TerrainEvent) -> void:
	var places: Array[Vector4] = []
	var reach := maxf(event.radius_m * 0.95, _nearest + 0.1)
	for i in FRONT_TONGUES:
		var angle := _rng.randf_range(0.0, TAU)
		var near_sq := _nearest * _nearest
		var distance := sqrt(lerpf(near_sq, reach * reach, _rng.randf()))
		var xz := event.centre + Vector2(cos(angle), sin(angle)) * distance
		var y := WaterGeometry.ground_at(document, xz) if document != null else _middle.y
		places.append(Vector4(xz.x, y, xz.y, front_reaches(distance, _nearest, event.radius_m)))
	places.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.w < b.w)
	_front = places
	_front_draws.resize(FRONT_TONGUES)
	for i in FRONT_TONGUES:
		_front_draws[i] = _rng.randf()


## The ground's tongue `index` rising where the ring has reached.
func _front_tongue(index: int) -> void:
	var place := _front[index]
	var draw := _front_draws[index]
	var wide := lerpf(FRONT_WIDE.x, FRONT_WIDE.y, draw)
	_flames.emit_flame(
		Vector3(place.x, place.y, place.z),
		Vector3.ZERO,
		wide,
		wide * FRONT_TALL,
		lerpf(FRONT_LIFE.x, FRONT_LIFE.y, fmod(draw * 7.3, 1.0)),
		FLAME if draw < 0.6 else FLAME_LATE
	)


## Emits what `tree` throws up by `t` seconds after catching: its crown's tongues as the burn
## climbs to each, a spark (on some trees) as it catches, and its smoke (on some).
func _kindle(tree: Dictionary, t: float) -> void:
	if t < 0.0:
		return
	var burn := float(tree.burn)
	var height := float(tree.height)
	var width := float(tree.width)
	var origin := (tree.base as Transform3D).origin
	var draws: PackedFloat32Array = tree.draws
	while int(tree.tongues) < CROWN_TONGUES:
		var at_draw := DRAWS_PER_TREE + 4 * int(tree.tongues)
		if t < draws[at_draw] * burn:
			break
		_crown_tongue(draws, at_draw, origin, height, width, burn)
		tree.tongues = int(tree.tongues) + 1
	if not tree.lit and t >= SPARK_AT * burn:
		tree.lit = true
		if draws[2] < EMBER_CHANCE:
			_flames.emit_ember(
				origin + Vector3(0.0, height * 0.95, 0.0),
				_drift + Vector3(0.0, 1.4 + draws[5], 0.0),
				0.4,
				1.4 + 0.4 * draws[4],
				EMBER
			)
	if not tree.smoked and t >= SMOKE_AT * burn:
		tree.smoked = true
		# Bushes smoulder: a billow from one stood low as a pebble.
		if draws[3] < SMOKE_CHANCE and height >= SMOKE_MIN_TALL:
			_smoke.emit(
				origin + Vector3(0.0, height * 0.85, 0.0),
				_drift * 1.5 + Vector3(0.0, SMOKE_RISE + 0.3 * draws[5], 0.0),
				width * SMOKE_SIZE,
				2.6 + 0.5 * draws[4],
				Color.WHITE
			)


## One of a tree's crown tongues, its draws from `at_draw` in `draws`: a small tongue standing
## at a point in the crown (up its height, round the trunk, part way out), tucked among the
## leaf cards (EventPuffs.emit_crown_flame), redder on some.
func _crown_tongue(
	draws: PackedFloat32Array,
	at_draw: int,
	origin: Vector3,
	height: float,
	width: float,
	burn: float
) -> void:
	var wide := clampf(width * TONGUE_WIDE, height * TONGUE_BOUNDS.x, height * TONGUE_BOUNDS.y)
	wide *= lerpf(0.75, 1.15, fmod(draws[at_draw + 2] * 5.7, 1.0))
	# Its tip held under the crown's top (TONGUE_TOP), so none stands against the sky.
	var up := lerpf(TONGUE_FOOT.x, TONGUE_FOOT.y, draws[at_draw + 1])
	up = minf(up, TONGUE_TOP - wide * TONGUE_TALL / maxf(height, 0.01))
	var angle := draws[at_draw + 2] * TAU
	var out := sqrt(draws[at_draw + 3]) * TONGUE_SPREAD * width
	var deep := Vector3(-_across.z, 0.0, _across.x)
	var round_trunk := _across * cos(angle) + deep * sin(angle)
	# The crown narrows toward its top, so a high tongue stands nearer the trunk.
	var at := origin + Vector3(0.0, height * up, 0.0) + round_trunk * out * (1.3 - up)
	# A tongue climbs slowly, so it stays in its crown (a fast one rose off as a beam).
	var rise := Vector3(0.0, height * 0.03, 0.0) + _drift * 0.3
	var life := burn * lerpf(TONGUE_LIFE.x, TONGUE_LIFE.y, fmod(draws[at_draw + 3] * 3.1, 1.0))
	var color := FLAME if fmod(draws[at_draw] * 9.7, 1.0) < 0.6 else FLAME_LATE
	_flames.emit_crown_flame(at, rise, wide, wide * TONGUE_TALL, life, color)


## The column's billow `index`: a large billow climbing slowly over the stand's middle, higher
## each time.
func _column(index: int) -> void:
	_smoke.emit(
		_middle + Vector3(0.0, _tall * (1.0 + 0.35 * index), 0.0),
		_drift * 2.0 + Vector3(0.0, 0.7, 0.0),
		_tall * (COLUMN_SIZE + 0.08 * index),
		3.4,
		Color.WHITE
	)
