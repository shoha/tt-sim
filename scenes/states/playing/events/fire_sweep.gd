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
## glowing edge until the charred trunk and limbs stand bare (the bark only chars). A painted
## flame (EventPuffs' flame, FlameAtlas) stands on each crown as it catches, sized by the
## crown's width so a narrow pine's is a tongue on its crown rather than a beam down it, a
## second beside it on some, a spark drifts up from a few, and billows of smoke rise slowly
## from half the trees and in a short column over the middle: painted cumulus, grey-violet
## with cream-gold tops and darker undersides. No ground glow and no mist: a few bold shapes,
## the forest visibly changing under them. Over the event's last SNAG_GO_S the charred snags
## shrink away (snag_transform) as the change lands.
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
## pools of fixed size made once (every puff of one fire fits at once, so none is
## overwritten), every random draw made in setup, so a frame only sets transforms, colours and
## custom data; no allocation while it plays. The burn shader's noise runs only on the
## stand-ins.

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
## How long a tree burns, from catching to a bare charred snag.
const BURN_S := Vector2(1.2, 1.5)
## The burn shader's progress at the end of a tree's burn (every patch has burnt through by
## about 1.55: a patch catches between 0 and 1 and its leaves are gone 0.55 after).
const BURN_RATE := 1.7
## The charred snags shrink away over the event's last this many seconds.
const SNAG_GO_S := 0.6
## A crown's flame: when it rises (a share of the tree's burn) and how long it lives, where its
## foot stands (a share of the tree's height), its width (TONGUE_WIDE of the crown's, held
## within TONGUE_BOUNDS of the tree's height) and its height over its width; a second beside it
## on SIDE_CHANCE of the trees, SIDE_SIZE of its size. Sized by the tree's height alone, a
## narrow pine's flame stood as a tall thin beam down its trunk.
const TONGUE_AT := 0.12
const TONGUE_LIFE := 0.55
const TONGUE_FOOT := 0.5
const TONGUE_WIDE := 0.85
const TONGUE_BOUNDS := Vector2(0.22, 0.38)
const TONGUE_TALL := 1.15
const SIDE_CHANCE := 0.5
const SIDE_SIZE := 0.65
## The share of trees that throw up a spark as they catch.
const EMBER_CHANCE := 0.35
## When a tree's smoke rises (a share of its burn), the share of trees that smoke, a billow's
## size against the crown and how fast it climbs (metres a second).
const SMOKE_AT := 0.65
const SMOKE_CHANCE := 0.5
const SMOKE_SIZE := 1.4
const SMOKE_RISE := 0.6
## The column over the centre: its billows' start times (seconds).
const COLUMN_AT: Array[float] = [0.8, 1.9]
## Pools: every puff of one fire at once (flames: two tongues and a spark a tree).
const FLAMES_PER_TREE := 3
const FLAME_POOL := FLAMES_PER_TREE * MAX_TREES
const SMOKE_POOL := MAX_TREES + 2
## Draw order: the smoke, then the flames over it.
const SMOKE_PRIORITY := EventPuffs.RENDER_PRIORITY + 1
const FLAME_PRIORITY := EventPuffs.RENDER_PRIORITY + 2
## Colours (linear, see the header): a flame's rim (shows a deep red-orange; its body burns
## amber and its core pale gold, the puff shader's), the second tongue's redder; a spark;
## the body of the trees' smoke (shows a warm grey-violet, about 0.45, 0.4, 0.48; the shader
## lights its lobes' tops cream-gold and shades its underside; a plum body lit rust underneath
## read as salmon-pink mist, and a body showing 0.54 as a pile of pale balls) and the
## column's, a little darker. Nearly opaque: a billow is a body, not a haze.
const FLAME := Color(0.75, 0.047, 0.006, 1.0)
const FLAME_LATE := Color(0.61, 0.018, 0.004, 1.0)
const EMBER := Color(1.0, 0.35, 0.036, 1.0)
const SMOKE := Color(0.102, 0.081, 0.119, 0.95)
const SMOKE_COLUMN := Color(0.085, 0.069, 0.102, 0.95)
const BURN_SHADER := preload("res://shaders/wind_foliage_burn.gdshader")

var _flames: EventPuffs = null
var _smoke: EventPuffs = null
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


## A tree standing at `base`, `elapsed` seconds into a fire of `duration`: where it stands,
## shrinking away about its foot over the last SNAG_GO_S. Pure.
static func snag_transform(base: Transform3D, elapsed: float, duration: float) -> Transform3D:
	var x := clampf((elapsed - duration + SNAG_GO_S) / SNAG_GO_S, 0.0, 1.0)
	if x <= 0.0:
		return base
	var keep := 1.0 - smoothstep(0.0, 1.0, x)
	return Transform3D(base.basis * Basis.from_scale(Vector3.ONE * keep), base.origin)


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
	while _columns < COLUMN_AT.size() and elapsed >= COLUMN_AT[_columns]:
		_column(_columns)
		_columns += 1
	_smoke.step(delta)
	_flames.step(delta)
	if elapsed >= duration and not _ended:
		_ended = true
		for tree in _trees:
			(tree.stand_in as Node3D).visible = false


## True once the fire has burnt out and its smoke has cleared.
func is_played(elapsed: float) -> bool:
	return elapsed >= duration and _flames.is_idle() and _smoke.is_idle()


## The trees `event` burns (burnable).
func _find(editor: AuthoringEditor, event: TerrainEvent) -> Array[Dictionary]:
	var found := burnable(_scatter, event.centre, event.radius_m, editor.palette_root)
	_nearest = float(found[0].distance) if not found.is_empty() else 0.0
	return found


## The fire's two pools (see the header), its flames painted.
func _make_puffs() -> void:
	_smoke = EventPuffs.new(SMOKE_POOL, SMOKE_PRIORITY)
	_flames = EventPuffs.new(FLAME_POOL, FLAME_PRIORITY)
	add_child(_smoke)
	add_child(_flames)
	_flames.paint_flames()
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
		"lit": false,
		"smoked": false,
	}


## Emits what `tree` throws up by `t` seconds after catching: its flame (and a second beside
## it, and a spark, on some trees) as its crown catches, and its smoke (on some).
func _kindle(tree: Dictionary, t: float) -> void:
	if t < 0.0:
		return
	var burn := float(tree.burn)
	var height := float(tree.height)
	var width := float(tree.width)
	var origin := (tree.base as Transform3D).origin
	var draws: PackedFloat32Array = tree.draws
	if not tree.lit and t >= TONGUE_AT * burn:
		tree.lit = true
		# A flame climbs slowly, so it stays on its crown (a fast one rose off as a beam).
		var rise := Vector3(0.0, height * 0.04, 0.0) + _drift * 0.3
		var side := _across * (1.0 if draws[0] < 0.5 else -1.0)
		var at := origin + Vector3(0.0, height * TONGUE_FOOT, 0.0) + side * width * 0.1
		var wide := clampf(width * TONGUE_WIDE, height * TONGUE_BOUNDS.x, height * TONGUE_BOUNDS.y)
		var size := Vector2(wide, wide * TONGUE_TALL)
		_flames.emit_flame(at, rise, size.x, size.y, burn * TONGUE_LIFE, FLAME)
		if draws[1] < SIDE_CHANCE:
			_flames.emit_flame(
				at - side * width * 0.35 - Vector3(0.0, height * 0.08, 0.0),
				rise,
				size.x * SIDE_SIZE,
				size.y * SIDE_SIZE,
				burn * TONGUE_LIFE * 0.75,
				FLAME_LATE
			)
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
		if draws[3] < SMOKE_CHANCE:
			_smoke.emit_smoke(
				origin + Vector3(0.0, height * 0.85, 0.0),
				_drift * 1.5 + Vector3(0.0, SMOKE_RISE + 0.3 * draws[5], 0.0),
				maxf(width, height * 0.5) * SMOKE_SIZE,
				2.6 + 0.5 * draws[4],
				SMOKE
			)


## The column's billow `index`: a large billow climbing slowly over the stand's middle, higher
## each time.
func _column(index: int) -> void:
	_smoke.emit_smoke(
		_middle + Vector3(0.0, _tall * (1.0 + 0.35 * index), 0.0),
		_drift * 2.0 + Vector3(0.0, 0.7, 0.0),
		_tall * (0.8 + 0.15 * index),
		3.4,
		SMOKE_COLUMN
	)
