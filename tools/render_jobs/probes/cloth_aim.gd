extends RefCounted

## Render-job probe (`call` op) that frames a structure's banner or pennant cloth (perf4, card item 1).
## The keep's banners stand at the roof corners, often high and turned away from the default view, so
## a whole-building frame never showed them. Reached through structures.gd (`aim_cloth`, `aim_wind`).
## step.action:
##   aim_cloth {index, off_deg, fill, preset, clock}
##       Takes the last structure laid (structures.gd `tile`), finds the world centre, size and outward
##       normal of each cloth piece tagged `ornament/banner<k>/cloth` (the wall corner side it flies
##       from), picks the one `index` names (default: the one turned most toward the camera as it
##       stands), turns the camera `off_deg` (default 45) off that piece's outward normal, puts the
##       piece at the screen centre and zooms so its longest side fills about `fill` (default 0.25) of
##       the frame height. With `preset` it also sets the wind so it blows across the screen.
##   aim_wind {preset, clock}
##       Sets the wind (wind.gd `set`) blowing from the left to the right of the current view.

const WIND_PROBE := "res://tools/render_jobs/probes/wind.gd"


static func run(base: Node, step: Dictionary) -> String:
	if String(step.get("action", "")) == "aim_wind":
		return _wind_across(base, step)
	return _aim(base, step)


## The cloth pieces of structure node `node`: [{name, centre, size, outward}] with the world centre
## and extent of each banner or pennant sheet and the horizontal direction from the footprint's
## centre `from` (a map X, Z point) to it.
static func pieces_of(node: Node3D, from: Vector2) -> Array[Dictionary]:
	var table: PackedStringArray = node.get_meta(AuthoredStructures.TAGS_META, PackedStringArray())
	var low := {}
	var high := {}
	for child in node.get_children():
		var instance := child as MeshInstance3D
		if instance == null or instance.mesh == null or instance.mesh.get_surface_count() == 0:
			continue
		var tags: PackedInt32Array = instance.get_meta(
			AuthoredStructures.TAGS_META, PackedInt32Array()
		)
		var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		for k in mini(vertices.size(), tags.size()):
			var tag := tags[k]
			if tag < 0 or tag >= table.size():
				continue
			var name := table[tag]
			if not name.contains("ornament/banner") or not name.ends_with("/cloth"):
				continue
			var world := instance.global_transform * vertices[k]
			low[name] = (low[name] as Vector3).min(world) if low.has(name) else world
			high[name] = (high[name] as Vector3).max(world) if high.has(name) else world
	var out: Array[Dictionary] = []
	var names: Array = low.keys()
	names.sort()
	for name: String in names:
		var lo: Vector3 = low[name]
		var hi: Vector3 = high[name]
		var centre := (lo + hi) * 0.5
		var flat := Vector2(centre.x, centre.z) - from
		out.append(
			{
				"name": name,
				"centre": centre,
				"size": hi - lo,
				"outward": flat.normalized() if flat.length() > 0.001 else Vector2.RIGHT
			}
		)
	return out


static func _aim(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var nodes := AuthoredStructures.of_map(ctrl.map_root)
	var doc: MapDocument = ctrl.document
	if doc.structures.is_empty():
		return "no structure"
	var structure: Structure = doc.structures[doc.structures.size() - 1]
	var node := nodes.get_structure_node(structure.id)
	if node == null:
		return "no node for structure %d" % structure.id
	var from := Vector2.ZERO
	for corner in structure.footprint:
		from += corner
	from /= float(maxi(structure.footprint.size(), 1))
	var pieces := pieces_of(node, from)
	if pieces.is_empty():
		return "no banner cloth in structure %d" % structure.id
	var game_map: GameMap = base.get("_game_map")
	var holder := game_map.cameraholder_node
	var camera := game_map.camera_node
	holder.rotation.y = 0.0
	var home_back := _flat(camera.global_basis.z)
	var chosen: Dictionary = pieces[0]
	if step.has("index"):
		chosen = pieces[clampi(int(step["index"]), 0, pieces.size() - 1)]
	else:
		var best := -2.0
		for piece in pieces:
			var facing := (piece.outward as Vector2).dot(Vector2(home_back.x, home_back.z))
			if facing > best:
				best = facing
				chosen = piece
	var outward: Vector2 = chosen.outward
	var wanted := Vector3(outward.x, 0.0, outward.y).rotated(
		Vector3.UP, deg_to_rad(float(step.get("off_deg", 45.0)))
	)
	holder.rotation.y = home_back.signed_angle_to(wanted, Vector3.UP)
	var size: Vector3 = chosen.size
	var longest := maxf(maxf(size.x, size.z), size.y)
	var controller := game_map.get_camera_controller()
	controller.set_zoom_limits(0.5, 100.0)
	controller.set("_target_zoom", maxf(longest, 0.3) / float(step.get("fill", 0.25)))
	controller.finish_zoom()
	var centre: Vector3 = chosen.centre
	var screen := Vector2(game_map.world_viewport.size) * 0.5
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hit := origin + direction * ((centre.y - origin.y) / direction.y)
	holder.global_position += Vector3(centre.x - hit.x, 0.0, centre.z - hit.z)
	controller.finish_zoom()
	var report := (
		"cloth %s of %d: centre %s size %s outward %s, camera yaw %.1f deg, ortho size %.2f"
		% [
			chosen.name,
			pieces.size(),
			centre,
			size,
			outward,
			rad_to_deg(holder.rotation.y),
			camera.size
		]
	)
	for piece in pieces:
		report += "; %s at %s" % [piece.name, piece.centre]
	if step.has("preset"):
		report += "; " + _wind_across(base, step)
	return report


static func _wind_across(base: Node, step: Dictionary) -> String:
	var game_map: GameMap = base.get("_game_map")
	var right := _flat(game_map.camera_node.global_basis.x)
	var degrees := fposmod(rad_to_deg(atan2(right.z, right.x)), 360.0)
	var wind_step := {
		"action": "set",
		"preset": step.get("preset", "windy"),
		"clock": float(step.get("clock", 0.0)),
		"dir_deg": degrees,
	}
	var result: String = load(WIND_PROBE).run(base, wind_step)
	return "wind %s across the screen at %.0f deg: %s" % [wind_step.preset, degrees, result]


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z).normalized()
