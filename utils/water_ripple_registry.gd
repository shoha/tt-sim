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


## Register a token as submerged. Safe to call again for an already-registered id --
## just overwrites with the latest node reference.
static func register(id: int, body: Node3D) -> void:
	_submerged[id] = body


## Unregister a token. No-op if the id was never registered or already removed --
## tokens can be freed while submerged (e.g. deleted mid-drag), and WaterZone's
## body_exited handler must not error in that case.
static func unregister(id: int) -> void:
	_submerged.erase(id)


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
