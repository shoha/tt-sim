class_name WaterRippleRegistry
extends RefCounted

## Tracks tokens currently submerged in any `-water` mesh's WaterZone, and builds the
## fixed-size disturbance-point array pushed onto the shared water ShaderMaterial each
## frame (see WaterZone._process() and water.gdshader's water_disturbance_points
## uniform). Static/shared across the whole game, matching WaterGlbUtils/WaterPresets'
## style -- there's one registry for the whole game, not one per WaterZone, since a
## token submerged via one zone should still show its ripple regardless of which zone
## is the one currently ticking _process().

const MAX_DISTURBANCE_POINTS := 8

static var _submerged: Dictionary = {}  # instance_id (int) -> Node3D
static var _refcounts: Dictionary = {}  # instance_id (int) -> int, zones claiming this token
static var _last_push_frame: int = -1  # Engine.get_process_frames() value of the last flush
static var _cleared: bool = true  # true once the all-inactive array has been pushed since empty


## Register a token as submerged by one zone. Safe to call again for an
## already-registered id -- overwrites with the latest node reference and
## increments the refcount, so a token inside multiple overlapping WaterZones
## stays correctly submerged until it has left all of them (see unregister()).
## Returns true if this is the token's FIRST active zone (refcount 0 -> 1) --
## callers should only trigger entry side-effects (visual sink, splash) on a
## true return, so entering a second overlapping zone doesn't re-trigger them.
static func register(id: int, body: Node3D) -> bool:
	_submerged[id] = body
	var count: int = _refcounts.get(id, 0) + 1
	_refcounts[id] = count
	return count == 1


## Unregister one zone's claim on a token. No-op if the id was never
## registered or already fully unregistered -- tokens can be freed while
## submerged (e.g. deleted mid-drag), and WaterZone's body_exited handler must
## not error in that case. Returns true if this was the token's LAST active
## zone (refcount reached zero) -- callers should only trigger exit
## side-effects (visual un-sink, splash) on a true return, since the token may
## still be inside another overlapping WaterZone.
static func unregister(id: int) -> bool:
	if not _refcounts.has(id):
		return false
	_refcounts[id] -= 1
	if _refcounts[id] > 0:
		return false
	_refcounts.erase(id)
	_submerged.erase(id)
	return true


## Build the fixed-size array pushed to the shared material's water_disturbance_points
## uniform: up to MAX_DISTURBANCE_POINTS active entries (xz = world position, w = 1.0),
## padded with inactive (w = 0.0) entries. Skips any registered node that's been freed
## without being unregistered, and silently drops entries beyond the cap.
static func build_disturbance_array() -> Array:
	var points: Array = []
	for id in _submerged:
		if points.size() >= MAX_DISTURBANCE_POINTS:
			break
		if not is_instance_valid(_submerged[id]):
			continue
		var body: Node3D = _submerged[id]
		var pos := body.global_position
		points.append(Vector4(pos.x, pos.z, 0.0, 1.0))
	while points.size() < MAX_DISTURBANCE_POINTS:
		points.append(Vector4(0.0, 0.0, 0.0, 0.0))
	return points


## Push the current disturbance state onto the shared water material, but at most once
## per frame and only when it actually changed -- called by every live WaterZone's
## _process() each frame (see WaterZone._process()), which is redundant across zones on
## the same map and, while any zone exists but nothing is submerged, was pushing the
## same all-inactive array every frame for no reason. Skips entirely once the
## all-inactive array has already been pushed (idle water), and re-pushes once more the
## instant the last token unregisters (or is pruned, see _prune_freed_bodies()) so the
## shader sees the cleared state.
static func flush_disturbances() -> void:
	if Engine.get_process_frames() == _last_push_frame:
		return
	_prune_freed_bodies()
	if _submerged.is_empty():
		if _cleared:
			return
		WaterGlbUtils.push_disturbance_points(build_disturbance_array())
		_cleared = true
	else:
		WaterGlbUtils.push_disturbance_points(build_disturbance_array())
		_cleared = false
	_last_push_frame = Engine.get_process_frames()


## Drop any registered token whose body has been freed without a matching unregister()
## call (e.g. deleted mid-drag while still submerged -- see unregister()'s doc comment).
## Runs before the emptiness check in flush_disturbances() so a single freed body left
## behind can't keep _submerged permanently non-empty and the registry pushing every
## frame forever -- build_disturbance_array() already skips freed bodies per-call, but
## never removed them, so flush_disturbances() alone couldn't tell submerged had truly
## gone empty.
static func _prune_freed_bodies() -> void:
	if _submerged.is_empty():
		return
	# Allocated only once an invalid entry is found, so the idle path stays
	# allocation-free.
	var freed_ids: Variant = null
	for id in _submerged:
		if not is_instance_valid(_submerged[id]):
			if freed_ids == null:
				freed_ids = []
			freed_ids.append(id)
	if freed_ids == null:
		return
	for id in freed_ids:
		_submerged.erase(id)
		_refcounts.erase(id)


## Test-only: clear all registered tokens so tests don't leak state into each other
## (static var persists across test cases within the same run).
static func clear() -> void:
	_submerged.clear()
	_refcounts.clear()
	_last_push_frame = -1
	_cleared = true
