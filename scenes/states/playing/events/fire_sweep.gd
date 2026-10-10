class_name FireSweep
extends ForestFall

## A fire sweeping through a forest (TerrainEvent.Kind.FIRE), played on one board. The trees
## are found, hidden in their chunks and drawn by stand-ins as ForestFall's are (the burnt
## biome's own snags are passed over: a burnt forest does not burn again), and the fire runs
## out from the centre as a front: the nearest tree catches first, the farthest SPREAD_S
## later. A tree that catches lights an oval of firelight on the ground at its foot (a glow)
## and stands in big flames, four overlapping waves of one bold teardrop each over its crown
## and a lick beside the first, a spark or none drifting up; after CATCH of its burn its
## crown draws in to a thin charred shape (CHARRED: across, up) and sinks away under the last
## flames, and a
## firelit smoke billow rises where it stood. A column of lilac smoke climbs over the centre
## while the front runs. Everything is a few large luminous shapes (EventPuffs' flame, ember,
## glow and blob), never a cloud of small ones.
##
## The map change follows (TerrainEvents): the burnt biome painted over the area, its snags
## and litter growing in under the smoke, then ash laid over the ground (plan_for; a palette
## without them gets a Clear and the peat it has). A burnt tree is gone from its chunk when
## that change rebuilds it, as a fallen one is.
##
## Bounded: at most MAX_TREES trees, three pools of fixed size made once (every puff of one
## fire fits at once, so none is overwritten), every random draw made in setup so a frame
## only sets transforms and colours; no allocation while it plays.

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
## SPREAD_JITTER.
const SPREAD_S := 2.0
const SPREAD_JITTER := 0.25
## How long a tree burns, from catching to gone.
const BURN_S := Vector2(1.2, 1.5)
## The share of its burn a crown stands whole in its flames before it draws in, and the
## shape it draws in to (across, up) before it sinks away.
const CATCH := 0.35
const CHARRED := Vector2(0.12, 0.5)
## When each flame wave starts, as a share of the tree's burn, and how long one lives: they
## overlap, so a burning crown is one steady mass of flame (three waves with gaps flickered
## out to a few faint tongues in the first look).
const WAVES: Array[float] = [0.0, 0.22, 0.45, 0.68]
const WAVE_LIFE := 0.55
## When a tree's smoke rises, as a share of its burn.
const SMOKE_AT := 0.65
## The column over the centre: its billows' start times (seconds).
const COLUMN_AT: Array[float] = [0.5, 1.3, 2.2, 3.1]
## Pools: every puff of one fire at once (flames: four waves, a lick and an ember a tree).
const FLAMES_PER_TREE := 6
const FLAME_POOL := FLAMES_PER_TREE * MAX_TREES
const SMOKE_POOL := MAX_TREES + 4
const GLOW_POOL := MAX_TREES
## Draw order: the ground's glow, then the smoke, then the flames over both.
const GLOW_PRIORITY := EventPuffs.RENDER_PRIORITY
const SMOKE_PRIORITY := EventPuffs.RENDER_PRIORITY + 1
const FLAME_PRIORITY := EventPuffs.RENDER_PRIORITY + 2
## Colours: each flame's rim (its core burns pale gold, the puff shader's FIRE_CORE), the
## later waves redder; a spark's halo; the ground's firelight; smoke lit by the fire low down
## and a lilac column above it (luminous, never grey).
const FLAME := Color(1.0, 0.3, 0.06, 1.0)
const FLAME_LATE := Color(0.92, 0.2, 0.08, 1.0)
const EMBER := Color(1.0, 0.6, 0.18, 1.0)
const GLOW := Color(0.98, 0.34, 0.1, 0.45)
const SMOKE_LOW := Color(0.8, 0.6, 0.62, 0.55)
const SMOKE_HIGH := Color(0.68, 0.6, 0.76, 0.6)
## A tree's smoke billow against its crown (a smaller one read as a cotton ball).
const SMOKE_SIZE := 2.0

var _flames: EventPuffs = null
var _smoke: EventPuffs = null
var _glow: EventPuffs = null
## The way the smoke drifts (map frame, horizontal, metres a second), the stand's middle on
## the ground and its trees' mean height, drawn in setup.
var _drift := Vector3.ZERO
var _middle := Vector3.ZERO
var _tall := 1.0
var _columns := 0
## The nearest tree's distance from the centre (it catches first).
var _nearest := 0.0


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
	var plan := plan_for(
		PaletteLibrary.biomes(editor.palette_root), PaletteLibrary.surfaces(editor.palette_root)
	)
	if plan.biome != "":
		editor.prepare_biome(plan.biome)
	if plan.surface != "" and is_instance_valid(editor.terrain):
		editor.terrain.warm_surface(plan.surface)
	return true


## Plays the fire `elapsed` seconds in (after `delta` more seconds of flames and smoke).
func step(elapsed: float, delta: float) -> void:
	for tree in _trees:
		var t := elapsed - float(tree.start)
		var multimesh := (tree.stand_in as MultiMeshInstance3D).multimesh
		multimesh.set_instance_transform(tree.slot, burn_transform(tree, t))
		# A burning tree goes still (ForestFall.calm_weight's colour), as a falling one does.
		var calm := calm_weight(t, float(tree.burn))
		multimesh.set_instance_color(tree.slot, Color(calm, calm, 1.0, 1.0))
		_kindle(tree, t)
	while _columns < COLUMN_AT.size() and elapsed >= COLUMN_AT[_columns]:
		_column(_columns)
		_columns += 1
	_glow.step(delta)
	_smoke.step(delta)
	_flames.step(delta)
	if elapsed >= duration and not _ended:
		_ended = true
		for tree in _trees:
			(tree.stand_in as Node3D).visible = false


## True once the fire has burnt out and its smoke has cleared.
func is_played(elapsed: float) -> bool:
	return elapsed >= duration and _flames.is_idle() and _smoke.is_idle() and _glow.is_idle()


## The trees `event` burns (burnable).
func _find(editor: AuthoringEditor, event: TerrainEvent) -> Array[Dictionary]:
	var found := burnable(_scatter, event.centre, event.radius_m, editor.palette_root)
	_nearest = float(found[0].distance) if not found.is_empty() else 0.0
	return found


## The fire's three pools (see the header).
func _make_puffs() -> void:
	_glow = EventPuffs.new(GLOW_POOL, GLOW_PRIORITY)
	_smoke = EventPuffs.new(SMOKE_POOL, SMOKE_PRIORITY)
	_flames = EventPuffs.new(FLAME_POOL, FLAME_PRIORITY)
	for pool in [_glow, _smoke, _flames]:
		add_child(pool)
	_puffs = _flames


## The burn of `tree` (a trees_near entry) of mesh bounds `box`, `height` metres tall, in
## `event`: when the front reaches it, how long it burns, its crown's width, and the draws its
## flames, spark and smoke take (made here, so a frame draws nothing).
func _tree_entry(tree: Dictionary, event: TerrainEvent, box: AABB, height: float) -> Dictionary:
	var base: Transform3D = tree.base
	var reach := (float(tree.distance) - _nearest) / maxf(event.radius_m - _nearest, 0.1)
	var scale := base.basis.get_scale()
	var width := maxf(box.size.x * scale.x, box.size.z * scale.z)
	var draws := PackedFloat32Array()
	for i in 6:
		draws.append(_rng.randf())
	return {
		"height": height,
		"width": clampf(width, height * 0.3, height),
		"start": SPREAD_S * reach + _rng.randf_range(0.0, SPREAD_JITTER),
		"burn": _rng.randf_range(BURN_S.x, BURN_S.y),
		"draws": draws,
		"waves": 0,
		"smoked": false,
	}


## Tree `tree` ({"base", "burn", "height"}) `t` seconds after it caught: whole, then drawing
## in to its charred shape, then sinking away to nothing by the end of its burn. Pure.
static func burn_transform(tree: Dictionary, t: float) -> Transform3D:
	var base: Transform3D = tree.base
	var burn := float(tree.burn)
	if t <= burn * CATCH:
		return base
	var x := clampf((t - burn * CATCH) / (burn * (1.0 - CATCH)), 0.0, 1.0)
	var across := lerpf(1.0, CHARRED.x, smoothstep(0.0, 0.7, x))
	var up := lerpf(1.0, CHARRED.y, smoothstep(0.0, 0.8, x))
	var keep := 1.0 - smoothstep(0.75, 1.0, x)
	var shape := Basis.from_scale(Vector3(across, up, across) * maxf(keep, 0.0))
	var sink := Vector3(0.0, -float(tree.height) * 0.08 * x, 0.0)
	return Transform3D(base.basis * shape, base.origin + sink)


## Emits what `tree` throws up by `t` seconds after catching: its glow and flame waves, a
## spark with the second, and its smoke.
func _kindle(tree: Dictionary, t: float) -> void:
	if t < 0.0:
		return
	var burn := float(tree.burn)
	var height := float(tree.height)
	var width := float(tree.width)
	var origin := (tree.base as Transform3D).origin
	var draws: PackedFloat32Array = tree.draws
	while int(tree.waves) < WAVES.size() and t >= WAVES[int(tree.waves)] * burn:
		var wave := int(tree.waves)
		tree.waves = wave + 1
		# Each wave lower and smaller than the last, as the crown burns down.
		# A flame climbs slowly, so it stays on its crown (a fast one rose off as a beam).
		var grow := 1.0 - 0.14 * wave
		var at := origin + Vector3(0.0, height * (0.18 - 0.04 * wave), 0.0)
		var rise := Vector3(0.0, height * 0.1, 0.0) + _drift * 0.5
		var size := maxf(width * 1.3, height * 0.5) * grow
		var color := FLAME if wave < 2 else FLAME_LATE
		_flames.emit_flame(at, rise, size, height * 0.85 * grow, burn * WAVE_LIFE, color)
		if wave == 0:
			_glow.emit_glow(origin, width * 1.1, burn + 1.0, GLOW)
			var side := Vector3(draws[0] - 0.5, 0.0, draws[1] - 0.5).normalized() * width * 0.45
			_flames.emit_flame(
				origin + side + Vector3(0.0, height * 0.12, 0.0),
				rise * 0.8,
				size * 0.55,
				height * 0.6,
				burn * 0.5,
				FLAME
			)
		elif wave == 1 and draws[2] < 0.6:
			var out := Vector3(draws[3] - 0.5, 0.0, draws[4] - 0.5) * 1.2 + _drift
			_flames.emit_ember(
				origin + Vector3(0.0, height * 0.9, 0.0),
				out + Vector3(0.0, 1.5 + draws[5], 0.0),
				0.45,
				1.4 + 0.4 * draws[5],
				EMBER
			)
	if not tree.smoked and t >= SMOKE_AT * burn:
		tree.smoked = true
		_smoke.emit(
			origin + Vector3(0.0, height * 0.75, 0.0),
			_drift * 2.0 + Vector3(0.0, 1.0 + 0.4 * draws[5], 0.0),
			maxf(width, height * 0.5) * SMOKE_SIZE,
			2.8 + 0.6 * draws[4],
			SMOKE_LOW
		)


## The column's billow `index`: a large lilac puff climbing over the stand's middle, higher
## each time.
func _column(index: int) -> void:
	var lift := _tall * (0.7 + 0.3 * index)
	_smoke.emit(
		_middle + Vector3(0.0, lift, 0.0),
		_drift * 3.0 + Vector3(0.0, 1.2, 0.0),
		_tall * (1.1 + 0.2 * index),
		3.4,
		SMOKE_HIGH
	)
