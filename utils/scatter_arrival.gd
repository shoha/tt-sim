class_name ScatterArrival
extends RefCounted

## How scatter arrives under a brush and how it leaves: the motion of AuthoredScatter's grow-in
## (a cell's new rows) and of ScatterShrink's shrink-out (its removed rows). The user's pick from
## the brushland feel probe, "STAGED + LIFE" (review board item brushland-motion, 2026-10-20;
## docs/systems/scatter.md "Arrival motion").
##
## Staged. A species waits by its palette size class before it starts: large at once, then
## medium, small and ground cover STAGE_STEP apart, so the painted thing arrives first and the
## floor answers it. Only a brush landing is staged (one that carries its brush centre,
## ScatterRegen "Brush centres"); a direct rebuild (a prop placed or removed, an undo of props)
## starts at once, so a rock the Place tool puts down shows under the cursor straight away.
##
## Life. A plant grows with a back-out ease that peaks about 10 percent over full size, each
## instance after a ripple delay of RIPPLE_SECONDS_PER_M per metre from the brush centre (at most
## RIPPLE_MAX_SECONDS). Each wind instance works its size out in the shader
## (wind_foliage_grow.gdshaderinc) from two per-node instance uniforms, so the ripple costs the
## CPU one uniform write per node per frame, as the plain grow-in did. Rocks, whose materials have
## no such uniform, drop in from above and rebound, each instance through its own MultiMesh
## transform after its own delay; a grow node holds a few rocks, so that is a few transform writes
## a frame while they fall. Shrink-outs are staged the same way: plants swell a little and
## collapse, rippling, and rocks hop and sink.
##
## No restart. A row's stage and ripple delays are fixed when it first appears: new rows get their
## own grow node and tween, and a later landing that keeps them leaves that node running
## (AuthoredScatter._refresh_growing), so the provisional landings a held brush brings about
## every ScatterRegen.LIVE_INTERVAL_MSEC never start a row over. A row removed mid-arrival shrinks
## from the size (or height) it had reached (as_shown).
##
## Each peer animates its own rebuilds from its own landings; nothing here is networked.

## Seconds between one size class's start and the next's (large, medium, small, ground).
const STAGE_STEP := 0.12
## The ripple: seconds of delay per metre from the brush centre (about 17 m/s), and the longest.
const RIPPLE_SECONDS_PER_M := 0.06
const RIPPLE_MAX_SECONDS := 0.35
## Seconds one plant instance takes to grow in (the back ease needs a little longer than a cubic
## for its overshoot to read) and to swell and collapse.
const LIFE_GROW_SECONDS := 0.42
const LIFE_SHRINK_SECONDS := 0.3
## The back ease's constant: about 10 percent past full size. Mirrored by GROW_BACK in
## wind_foliage_grow.gdshaderinc.
const BACK := 1.70158
## A rock's drop: its height times ROCK_DROP_FRACTION within the bounds, over ROCK_DROP_SECONDS,
## the last ROCK_SETTLE share of which is a rebound of ROCK_REBOUND of the drop.
const ROCK_DROP_FRACTION := 0.6
const ROCK_DROP_MIN_M := 0.3
const ROCK_DROP_MAX_M := 1.2
const ROCK_DROP_SECONDS := 0.32
const ROCK_SETTLE := 0.35
const ROCK_REBOUND := 0.08
const WAVE_UNIFORM := &"grow_wave"
const CLOCK_UNIFORM := &"grow_clock"
const GROW_UNIFORM := &"grow"
const _SIZE_CLASSES := ["large", "medium", "small", "ground"]
const _HIDDEN := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)

## For measurement and side-by-side films only: today's motion before this one (everything at
## once, a cubic ease over AuthoredScatter.grow_seconds, rocks rising out of the ground).
static var classic: bool = false


## A species' stage from its palette size class: large 0, medium 1, small 2, ground 3; an
## unknown class counts as medium.
static func stage_of(size_class: String) -> int:
	var found := _SIZE_CLASSES.find(size_class)
	return found if found >= 0 else 1


## The stage of a palette asset (stage_of its manifest size class).
static func stage_for(asset_id: String, root: String) -> int:
	return stage_of(String(PaletteLibrary.asset(asset_id, root).get("size_class", "")))


## Seconds a species of `stage` waits on a brush landing before it starts.
static func stage_delay(stage: int) -> float:
	return 0.0 if classic else float(maxi(stage, 0)) * STAGE_STEP


## The ripple delay of an instance `distance` metres from the brush centre.
static func ripple_delay(distance: float) -> float:
	return minf(maxf(distance, 0.0) * RIPPLE_SECONDS_PER_M, RIPPLE_MAX_SECONDS)


## The back-out ease (0 at 0, about 1.1 at its peak, 1 at 1), the GDScript twin of the shader's.
static func back_out(t: float) -> float:
	var u := clampf(t, 0.0, 1.0) - 1.0
	return 1.0 + (BACK + 1.0) * u * u * u + BACK * u * u


## A dropping rock's height above its bed at `t` (0..1 of ROCK_DROP_SECONDS): a fall that speeds
## up from `drop`, then a small rebound that settles at 0.
static func drop_height(t: float, drop: float) -> float:
	var fall := 1.0 - ROCK_SETTLE
	t = clampf(t, 0.0, 1.0)
	if t < fall:
		var u := t / fall
		return drop * (1.0 - u * u)
	return drop * ROCK_REBOUND * sin(PI * (t - fall) / ROCK_SETTLE)


## How far a rock `height` metres tall drops in.
static func drop_of(height: float) -> float:
	return clampf(height * ROCK_DROP_FRACTION, ROCK_DROP_MIN_M, ROCK_DROP_MAX_M)


## The world point instances of `parent` (a node whose children they are, rows local to it)
## ripple from: `centre` as a landing carries it (Vector2, `parent`'s XZ), a world Vector3 as is,
## or, for null, the centroid of `transforms`.
static func origin_of(parent: Node3D, transforms: Array[Transform3D], centre: Variant) -> Vector3:
	if centre is Vector3:
		return centre
	var local := Vector3.ZERO
	if centre is Vector2:
		local = Vector3(centre.x, 0.0, centre.y)
	else:
		for xform in transforms:
			local += xform.origin
		local /= maxf(float(transforms.size()), 1.0)
	var world := _to_world(parent) * local
	return Vector3(world.x, 0.0, world.z)


## Builds the grow-in of `entry` (AuthoredScatter's growing entry: "node" and an empty "tween")
## for `species` (its record: "mesh", "height", "stage"), whose new instances are `transforms`
## (instance order, local to the node's parent). `centre`: the landing's brush centre (Vector2)
## or null for a direct rebuild, which is not staged. `seconds`: the classic grow-in's length.
static func grow_in(
	entry: Dictionary,
	species: Dictionary,
	transforms: Array[Transform3D],
	centre: Variant,
	seconds: float
) -> void:
	var node: MultiMeshInstance3D = entry.node
	var tween: Tween = entry.tween
	var by_shader: bool = species.get("by_shader", ScatterShrink.shrinks_by_shader(species.mesh))
	if classic:
		var tallest := 0.0
		for xform in transforms:
			tallest = maxf(tallest, xform.basis.get_scale().y)
		var rise := _rise.bind(node, by_shader, maxf(float(species.height) * tallest, 0.05))
		rise.call(0.0)
		tween.tween_method(rise, 0.0, 1.0, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(
			Tween.EASE_OUT
		)
		return
	var delay := stage_delay(int(species.get("stage", 1))) if centre != null else 0.0
	var parent := node.get_parent() as Node3D
	var at := origin_of(parent, transforms, centre)
	entry["arrival"] = {"delay": delay, "at": at}
	if by_shader:
		var span := LIFE_GROW_SECONDS + _ripple_span(parent, transforms, at)
		node.set_instance_shader_parameter(WAVE_UNIFORM, _wave(at))
		_clock(0.0, node, LIFE_GROW_SECONDS)
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_method(_clock.bind(node, LIFE_GROW_SECONDS), 0.0, span, span)
		return
	var drop := {"node": node, "at": at, "delay": delay, "height": float(species.height)}
	_rebase(drop, transforms)
	entry.arrival["drop"] = drop
	_drop_frame(0.0, drop)
	var total: float = drop.longest + ROCK_DROP_SECONDS
	tween.tween_method(_drop_frame.bind(drop), 0.0, total, total)


## Takes the rocks of `entry` from `transforms` (at rest, instance order) after AuthoredScatter
## rebuilt its node's MultiMesh from them (rows left it) and puts them back where the drop has
## them, so none shows at rest for a frame. Their delays follow from where they stand, so a kept
## rock carries on from where it was.
static func refreshed(entry: Dictionary, transforms: Array[Transform3D]) -> void:
	var drop: Dictionary = entry.get("arrival", {}).get("drop", {})
	if not drop.is_empty():
		_rebase(drop, transforms)
		_drop_frame(float(drop.get("clock", 0.0)), drop)


## `transforms` of instances leaving `entry`'s grow-in mid-arrival as they stand now: a plant
## scaled to the size it reached, a rock lifted to the height it is at. One that has not appeared
## yet is left out. `parent` is the node's parent, `by_shader` and `height` the species'.
static func as_shown(
	entry: Dictionary,
	parent: Node3D,
	transforms: Array[Transform3D],
	by_shader: bool,
	height: float
) -> Array[Transform3D]:
	var arrival: Dictionary = entry.arrival
	var tween: Tween = entry.get("tween")
	var elapsed := tween.get_total_elapsed_time() if tween != null and tween.is_valid() else INF
	var clock := elapsed - float(arrival.delay)
	var at: Vector3 = arrival.at
	var to_world := _to_world(parent)
	var shown: Array[Transform3D] = []
	for xform in transforms:
		var world := to_world * xform.origin
		var ripple := ripple_delay(Vector2(world.x - at.x, world.z - at.z).length())
		if clock < ripple:
			continue
		var out := xform
		if by_shader:
			var size := back_out((clock - ripple) / LIFE_GROW_SECONDS)
			out.basis = xform.basis * size
		else:
			var t := (clock - ripple) / ROCK_DROP_SECONDS
			out.origin.y += drop_height(t, drop_of(height * xform.basis.get_scale().y))
		shown.append(out)
	return shown


## Appends the shrink-out of `node` (ScatterShrink's temporary node, `transforms` its instances)
## to `tween`, after `delay` seconds: wind instances swell a little and collapse, rippling out from
## `centre` (origin_of's forms); the others hop and sink `depth` metres.
static func shrink_out(
	tween: Tween,
	node: MultiMeshInstance3D,
	by_shader: bool,
	transforms: Array[Transform3D],
	centre: Variant,
	delay: float,
	depth: float
) -> void:
	var parent := node.get_parent() as Node3D
	var at := origin_of(parent, transforms, centre)
	if by_shader:
		var span := LIFE_SHRINK_SECONDS + _ripple_span(parent, transforms, at)
		node.set_instance_shader_parameter(WAVE_UNIFORM, _wave(at))
		_clock(0.0, node, -LIFE_SHRINK_SECONDS)
		if delay > 0.0:
			tween.tween_interval(delay)
		tween.tween_method(_clock.bind(node, -LIFE_SHRINK_SECONDS), 0.0, span, span)
		return
	var centroid := origin_of(parent, transforms, null)
	var wait := delay + ripple_delay(Vector2(centroid.x - at.x, centroid.z - at.z).length())
	if wait > 0.0:
		tween.tween_interval(wait)
	(
		tween
		. tween_method(_sink.bind(node, depth), 1.0, 0.0, LIFE_SHRINK_SECONDS)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_IN)
	)


static func _to_world(parent: Node3D) -> Transform3D:
	return parent.global_transform if parent != null and parent.is_inside_tree() else Transform3D()


static func _wave(at: Vector3) -> Vector4:
	return Vector4(at.x, at.z, RIPPLE_SECONDS_PER_M, RIPPLE_MAX_SECONDS)


static func _clock(clock: float, node: MultiMeshInstance3D, seconds: float) -> void:
	if is_instance_valid(node):
		node.set_instance_shader_parameter(CLOCK_UNIFORM, Vector2(clock, seconds))


## The classic grow-in at `value` (0..1): the grow uniform, or a rise of `lift` metres.
static func _rise(value: float, node: MultiMeshInstance3D, by_shader: bool, lift: float) -> void:
	if not is_instance_valid(node):
		return
	if by_shader:
		node.set_instance_shader_parameter(GROW_UNIFORM, value)
	else:
		node.position.y = -lift * (1.0 - value)


static func _sink(value: float, node: MultiMeshInstance3D, depth: float) -> void:
	if is_instance_valid(node):
		node.position.y = -depth * (1.0 - value)


## The longest ripple delay among `transforms` (the shader's, on the CPU once per node).
static func _ripple_span(parent: Node3D, transforms: Array[Transform3D], at: Vector3) -> float:
	var to_world := _to_world(parent)
	var farthest := 0.0
	for xform in transforms:
		var world := to_world * xform.origin
		farthest = maxf(farthest, Vector2(world.x - at.x, world.z - at.z).length_squared())
	return ripple_delay(sqrt(farthest))


## Keeps a dropping node's rocks at rest (`transforms`, its MultiMesh's instance order; never read
## back from the MultiMesh) and works out each one's delay (stage plus ripple) and drop;
## `longest` is the latest start.
static func _rebase(drop: Dictionary, transforms: Array[Transform3D]) -> void:
	var node: MultiMeshInstance3D = drop.node
	var multimesh := node.multimesh
	var to_world := _to_world(node.get_parent() as Node3D)
	var at: Vector3 = drop.at
	var base: Array[Transform3D] = []
	var delays := PackedFloat32Array()
	var drops := PackedFloat32Array()
	var longest := 0.0
	for xform in transforms:
		var world := to_world * xform.origin
		var wait: float = drop.delay + ripple_delay(Vector2(world.x - at.x, world.z - at.z).length())
		base.append(xform)
		delays.append(wait)
		drops.append(drop_of(float(drop.height) * xform.basis.get_scale().y))
		longest = maxf(longest, wait)
	var rested := PackedByteArray()
	rested.resize(base.size())
	drop.multimesh = multimesh
	drop.base = base
	drop.delays = delays
	drop.drops = drops
	drop.longest = longest
	drop.rested = rested


## Poses each rock of `drop` `clock` seconds into its arrival: hidden before its delay, then the
## fall and rebound; one at rest is written once and left alone.
static func _drop_frame(clock: float, drop: Dictionary) -> void:
	drop.clock = clock
	var held: Variant = drop.node
	if not is_instance_valid(held) or (held as MultiMeshInstance3D).multimesh != drop.multimesh:
		return  # freed, or rebuilt and not yet refreshed()
	var multimesh: MultiMesh = drop.multimesh
	var base: Array[Transform3D] = drop.base
	var delays: PackedFloat32Array = drop.delays
	var drops: PackedFloat32Array = drop.drops
	# A packed array is copied on read: written back below.
	var rested: PackedByteArray = drop.rested
	for i in base.size():
		if rested[i] != 0:
			continue
		var xform := base[i]
		var t := (clock - delays[i]) / ROCK_DROP_SECONDS
		if clock < delays[i]:
			xform.basis = _HIDDEN
		elif t < 1.0:
			xform.origin.y += drop_height(t, drops[i])
		else:
			rested[i] = 1
		multimesh.set_instance_transform(i, xform)
	drop.rested = rested
