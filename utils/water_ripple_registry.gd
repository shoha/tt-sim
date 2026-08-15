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


## Test-only: clear all registered tokens so tests don't leak state into each other
## (static var persists across test cases within the same run).
static func clear() -> void:
	_submerged.clear()
	_refcounts.clear()
