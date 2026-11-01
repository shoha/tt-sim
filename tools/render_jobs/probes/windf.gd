extends RefCounted

## Render-job probe (`call` op) for the global wind's phase (f) consumers (card windf,
## docs/systems/wind.md "Phase (f) as built"). `action`:
## - `dust` {at, age, height}: a fallen tree's dust as ForestFall throws it (a billow off the
##   crown and a roll along the trunk, both drifting blobs of EventPuffs) at map XZ `at` on the
##   ground, stepped `age` seconds in and then held, so a capture shows how far the wind has
##   carried it. A pool from an earlier call is freed first. `height` is the tree's (default 8).
## - `clear`: frees the dust pool.

const POOL_NAME := "WindfDust"


static func run(base: Node, step: Dictionary) -> String:
	var gm := base.get("_game_map") as GameMap
	match String(step.get("action", "dust")):
		"clear":
			_clear(gm)
			return "dust cleared"
	return _dust(gm, step)


static func _clear(gm: GameMap) -> void:
	var old := gm.map_container.get_node_or_null(POOL_NAME)
	if old != null:
		gm.map_container.remove_child(old)
		old.queue_free()


static func _dust(gm: GameMap, step: Dictionary) -> String:
	_clear(gm)
	var at_list: Array = step.get("at", [0, 0])
	var x := float(at_list[0])
	var z := float(at_list[1])
	var ground := _ground_y(gm, x, z)
	var height := float(step.get("height", 8.0))
	var pool := EventPuffs.new(8)
	pool.name = POOL_NAME
	gm.map_container.add_child(pool)
	var base_at := pool.to_local(Vector3(x, ground, z))
	# The tree fell toward +x (screen right and away); the side is across it.
	var dir := Vector3(1.0, 0.0, 0.0)
	var side := Vector3(0.0, 0.0, 1.0)
	pool.emit(
		base_at + dir * height * 0.62 + Vector3(0.0, height * 0.06, 0.0),
		dir * 0.8 + Vector3(0.0, 0.3, 0.0),
		height * ForestFall.BILLOW,
		1.3,
		ForestFall.DUST,
		0.0,
		EventPuffs.SQUAT
	)
	pool.emit(
		base_at + dir * height * 0.36 + Vector3(0.0, height * 0.04, 0.0),
		side * 0.9 + Vector3(0.0, 0.18, 0.0),
		height * ForestFall.ROLL,
		1.2,
		ForestFall.DUST,
		0.0,
		ForestFall.ROLL_LENGTH,
		dir
	)
	pool.step(float(step.get("age", 0.6)))
	return (
		"dust at (%.1f, %.2f, %.1f) age %.2f blown %s %s motion %.2f"
		% [x, ground, z, float(step.get("age", 0.6)), pool._blown[0], pool._blown[1],
			Wind.motion_scale()]
	)


static func _ground_y(gm: GameMap, x: float, z: float) -> float:
	var space := gm.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(Vector3(x, 80.0, z), Vector3(x, -80.0, z))
	var hit := space.intersect_ray(query)
	return float((hit.get("position", Vector3.ZERO) as Vector3).y) if not hit.is_empty() else 0.0
