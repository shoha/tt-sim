extends RefCounted

## Render-job probe (`call` op) for the sculpt pipeline (phase 3, P3-3a): drives height
## strokes through AuthoringEditor over real frames (there is no Sculpt tool yet) and
## measures and checks what they do. step.action picks what it does:
##   stroke {name, sculpt, points, radius, speed, hold, flow, target_at, target_y}
##                         a height stroke along `points` ([[x, z], ...] world metres) at
##                         `speed` m/s, then `hold` s at the end; sculpt is raise / lower /
##                         smooth / flatten / tier; each frame's exposure is its delta
##                         times `flow`; flatten and tier aim at the ground height under
##                         `target_at` ([x, z]) read at the press, or at `target_y` (world
##                         height) when given. Logs, when the stroke
##                         ends: frame times, the worst frame and its breakdown (dab,
##                         terrain, collision, snap, rows moved, chunks), end_stroke's cost
##                         by part (terrain, collision, snap, rule fields; the rest is the
##                         rock keeping's start); then, once regeneration and settling are
##                         done, the tail's frame times, its parts summed over the tail
##                         (terrain settling, collision, snap, rock keeping's finish,
##                         regenerated cells applied) and its worst frame's parts, and the
##                         plants the regeneration grew and shrank against the instances it
##                         really added and removed (a plant that only moved must do neither).
##   compare {at, radius, reps}  alternate, one per frame, a whole-chunk rebuild
##                         (rebuild_chunks) and an in-place update (queue_heights +
##                         process_heights) of every chunk a brush of `radius` at `at`
##                         touches, after nudging its heights; logs the call times and the
##                         frame times that followed each.
##   collision {reps}      times AuthoredTerrain.update_collision().
##   snap_dense            times snapping every plant of the densest scatter cell after a
##                         real height change under it (then cancels the change).
##   check {area}          correctness in `area` ([x0, z0, x1, z1] world): layer-1 rays
##                         against the triangle surface, scatter and prop rows against the
##                         ground, every in-place chunk against a rebuilt one, chunk AABBs,
##                         and the near plane against the terrain's top.
##   view_shift {rise}     how far a ground point moves on screen when the terrain's top
##                         rises by `rise` m (the near-plane guard must not move the view).
##   look_bottom {at, y}   pans so world point (at, y) sits near the bottom edge of the
##                         screen (the near-plane check).

const STROKER := "SculptStroker"
const OPS := {
	"raise": HeightBrush.RAISE,
	"lower": HeightBrush.LOWER,
	"smooth": HeightBrush.SMOOTH,
	"flatten": HeightBrush.FLATTEN,
	"tier": HeightBrush.TIER,
}


## Helpers the inner classes can reach (they cannot call the script's own statics).
class Util:
	static func stats(values: PackedFloat64Array) -> String:
		var s := values.duplicate()
		s.sort()
		var n := s.size()
		if n == 0:
			return "n 0"
		var total := 0.0
		for v in s:
			total += v
		return (
			"n %d median %.2f p95 %.2f worst %.2f mean %.2f"
			% [n, s[n / 2], s[clampi(ceili(0.95 * n) - 1, 0, n - 1)], s[n - 1], total / n]
		)

	static func emit_line(tree: SceneTree, s: String) -> void:
		for node in tree.root.get_children():
			if node.has_method("log_line"):
				node.call("log_line", s)
				return
		print("RJ| " + s)


class Stroker:
	extends Node
	var ctrl: AuthoringController = null
	var gm: GameMap = null
	var step: Dictionary = {}
	var phase := 0
	var dist := 0.0
	var held := 0.0
	var last_us := 0
	var last_point := Vector3.ZERO
	var frames := PackedFloat64Array()
	var parts := {}
	var worst := {}
	var tail := PackedFloat64Array()
	var keys_before := {}
	var grown := 0
	var shrunk := 0
	var pending_nodes: Array = []
	var end_ms := 0.0
	var tail_start := 0
	## end_stroke by part (ms), the tail's parts summed over its frames, its worst frame.
	var end_parts := {}
	var tail_parts := {}
	var tail_worst := {}

	func _ready() -> void:
		process_priority = -90
		last_us = Time.get_ticks_usec()
		for key in ["ray", "dab", "flush", "terrain", "collision", "snap", "rows", "chunks"]:
			parts[key] = PackedFloat64Array()

	func _points() -> Array:
		return step.get("points", [[0, 0]])

	func _point_at(d: float) -> Vector3:
		var points := _points()
		var left := d
		for k in range(1, points.size()):
			var a := Vector2(points[k - 1][0], points[k - 1][1])
			var b := Vector2(points[k][0], points[k][1])
			var seg := a.distance_to(b)
			if left <= seg or k == points.size() - 1:
				var p := a.lerp(b, clampf(left / maxf(seg, 0.0001), 0.0, 1.0))
				return Vector3(p.x, 0.0, p.y)
			left -= seg
		return Vector3(points[0][0], 0.0, points[0][1])

	func _length() -> float:
		var points := _points()
		var total := 0.0
		for k in range(1, points.size()):
			total += Vector2(points[k][0], points[k][1]).distance_to(
				Vector2(points[k - 1][0], points[k - 1][1])
			)
		return total

	func _process(delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last_us) / 1000.0
		last_us = now
		var editor := ctrl.editor
		match phase:
			0:
				var target_y := 0.0
				if step.has("target_at"):
					var at: Array = step.target_at
					target_y = editor.ground_height_at(Vector3(float(at[0]), 0.0, float(at[1])))
				target_y = float(step.get("target_y", target_y))
				var op: int = OPS.get(String(step.get("sculpt", "raise")), HeightBrush.RAISE)
				if not editor.begin_height_stroke(op, target_y):
					Util.emit_line(get_tree(), "stroke %s: refused" % step.get("name", ""))
					queue_free()
					return
				last_point = _point_at(0.0)
				phase = 1
			1:
				frames.append(ms)
				var speed := float(step.get("speed", 4.0))
				var total := _length()
				dist = minf(dist + speed * delta, total)
				var point := _point_at(dist)
				if dist >= total:
					held += delta
				var radius := float(step.get("radius", 4.0))
				# The brush's own ground ray mid-stroke (BrushTool asks raycast_ground).
				var camera := gm.camera_node
				var screen := camera.unproject_position(point)
				var ray_started := Time.get_ticks_usec()
				editor.raycast_ground(
					camera.project_ray_origin(screen), camera.project_ray_normal(screen)
				)
				var ray_ms := (Time.get_ticks_usec() - ray_started) / 1000.0
				editor.stroke_dab(last_point, point, radius, delta * float(step.get("flow", 1.0)))
				editor.flush()
				last_point = point
				var sample := {
					"frame": ms,
					"ray": ray_ms,
					"dab": editor.last_dab_usec / 1000.0,
					"flush": editor.last_flush_usec / 1000.0,
					"terrain": editor.heights.last_terrain_usec / 1000.0,
					"collision": editor.heights.last_collision_usec / 1000.0,
					"snap": editor.heights.last_snap_usec / 1000.0,
					"rows": float(editor.heights.last_snap_rows),
					"chunks": float(editor.terrain.last_heights_chunks),
				}
				for key in parts:
					var series: PackedFloat64Array = parts[key]
					series.append(sample[key])
					parts[key] = series
				if frames.size() > 3 and (worst.is_empty() or ms > float(worst.frame)):
					worst = sample
				if dist >= total and held >= float(step.get("hold", 0.0)):
					_snapshot_keys()
					editor.terrain.last_fields_usec = 0
					var started := Time.get_ticks_usec()
					editor.end_stroke()
					end_ms = (Time.get_ticks_usec() - started) / 1000.0
					end_parts = {
						"terrain": editor.heights.last_terrain_usec / 1000.0,
						"collision": editor.heights.last_collision_usec / 1000.0,
						"snap": editor.heights.last_snap_usec / 1000.0,
						"fields": editor.terrain.last_fields_usec / 1000.0,
					}
					_reset_tail_parts()
					_report_stroke()
					ctrl.scatter.child_entered_tree.connect(_on_child)
					tail_start = Time.get_ticks_msec()
					phase = 2
			2:
				tail.append(ms)
				# What the previous frame (the one `ms` timed) spent on the stroke's leftovers.
				var sample := {
					"frame": ms,
					"terrain": editor.heights.last_terrain_usec / 1000.0,
					"collision": editor.heights.last_collision_usec / 1000.0,
					"snap": editor.heights.last_snap_usec / 1000.0,
					"keep": editor.rock_keeper.last_usec / 1000.0,
					"apply": ctrl.scatter.last_apply_usec / 1000.0,
				}
				for key in sample:
					if key != "frame":
						tail_parts[key] = float(tail_parts.get(key, 0.0)) + float(sample[key])
				if tail.size() == 1:
					# That frame also ran end_stroke (end_parts).
					sample["end_stroke"] = end_ms
				if tail_worst.is_empty() or ms > float(tail_worst.frame):
					tail_worst = sample
				_reset_tail_parts()
				for node in pending_nodes:
					if is_instance_valid(node) and node.multimesh:
						if String(node.name).contains(AuthoredScatter.GROWING_INFIX):
							grown += node.multimesh.instance_count
						else:
							shrunk += node.multimesh.instance_count
				pending_nodes.clear()
				var busy: bool = (
					ctrl.scatter.is_regenerating()
					or ctrl.scatter.is_growing()
					or editor.has_height_work()
					or editor.terrain.has_unsettled_chunks()
				)
				if busy and Time.get_ticks_msec() - tail_start < 20000:
					return
				ctrl.scatter.child_entered_tree.disconnect(_on_child)
				_report_tail()
				queue_free()

	func _reset_tail_parts() -> void:
		var editor := ctrl.editor
		editor.heights.last_terrain_usec = 0
		editor.heights.last_collision_usec = 0
		editor.heights.last_snap_usec = 0
		editor.rock_keeper.last_usec = 0
		ctrl.scatter.last_apply_usec = 0

	func _on_child(node: Node) -> void:
		var node_name := String(node.name)
		if (
			node_name.contains(AuthoredScatter.GROWING_INFIX)
			or node_name.contains(ScatterShrink.INFIX)
		):
			pending_nodes.append(node)

	func _keys() -> Dictionary:
		var out := {}
		var rows := ctrl.scatter.rows_by_asset()
		for asset_id in rows:
			var flat: PackedFloat32Array = rows[asset_id]
			for key in AuthoredScatter.row_keys(flat.to_byte_array().to_int32_array()):
				out[str(asset_id) + ":" + str(key)] = true
		return out

	func _snapshot_keys() -> void:
		keys_before = _keys()

	func _report_stroke() -> void:
		var text := "stroke %s: frames %s" % [step.get("name", ""), Util.stats(frames)]
		for key in parts:
			text += " | %s %s" % [key, Util.stats(parts[key])]
		text += " | worst frame %s" % JSON.stringify(worst)
		text += " | end_stroke %.2f ms %s" % [end_ms, JSON.stringify(end_parts)]
		Util.emit_line(get_tree(), text)

	func _report_tail() -> void:
		var after := _keys()
		var added := 0
		var removed := 0
		for key in after:
			if not keys_before.has(key):
				added += 1
		for key in keys_before:
			if not after.has(key):
				removed += 1
		Util.emit_line(
			get_tree(),
			(
				(
					"stroke %s tail: frames %s | instances added %d grown %d | removed %d shrunk %d"
					+ " | rows before %d after %d | parts summed %s | worst frame %s"
					+ " | rocks kept %d (worker %.1f ms)"
				)
				% [
					step.get("name", ""),
					Util.stats(tail),
					added,
					grown,
					removed,
					shrunk,
					keys_before.size(),
					after.size(),
					JSON.stringify(tail_parts),
					JSON.stringify(tail_worst),
					ctrl.editor.rock_keeper.last_kept,
					ctrl.editor.rock_keeper.last_worker_usec / 1000.0
				]
			)
		)


class Comparer:
	extends Node
	var ctrl: AuthoringController = null
	var cells: Array[Vector2i] = []
	var rect := Rect2i()
	var reps := 10
	var i := 0
	var last_us := 0
	var mode := ""
	var rebuild_call := PackedFloat64Array()
	var inplace_call := PackedFloat64Array()
	var rebuild_frame := PackedFloat64Array()
	var inplace_frame := PackedFloat64Array()

	func _ready() -> void:
		process_priority = -90
		last_us = Time.get_ticks_usec()

	func _process(_delta: float) -> void:
		var now := Time.get_ticks_usec()
		var ms := (now - last_us) / 1000.0
		last_us = now
		if mode == "rebuild":
			rebuild_frame.append(ms)
		elif mode == "inplace":
			inplace_frame.append(ms)
		mode = ""
		if i >= reps * 2 + 2:
			Util.emit_line(
				get_tree(),
				(
					(
						"compare %d chunks, %d samples: rebuild call %s | its frame %s"
						+ " | in-place call %s | its frame %s"
					)
					% [
						cells.size(),
						rect.get_area(),
						Util.stats(rebuild_call),
						Util.stats(rebuild_frame),
						Util.stats(inplace_call),
						Util.stats(inplace_frame)
					]
				)
			)
			# Leave the terrain consistent: the rebuild reps bypassed the vertex copies and
			# the collision.
			var terrain := ctrl.editor.terrain
			terrain.queue_heights(rect)
			terrain.process_heights(-1)
			terrain.settle_heights()
			terrain.update_collision()
			queue_free()
			return
		i += 1
		if i <= 2:
			return  # settle
		var doc := ctrl.document
		var sign := 1.0 if i % 4 < 2 else -1.0
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				doc.heights[doc.sample_index(x, z)] += 0.02 * sign
		var terrain := ctrl.editor.terrain
		var started := Time.get_ticks_usec()
		if i % 2 == 0:
			# The internal rebuild keeps the in-place vertex copies (both follow the
			# document), so the in-place reps measure steady-state updates.
			for cell in cells:
				terrain.call("_rebuild_chunk", cell)
			rebuild_call.append((Time.get_ticks_usec() - started) / 1000.0)
			mode = "rebuild"
		else:
			terrain.queue_heights(rect)
			terrain.process_heights(-1)
			inplace_call.append((Time.get_ticks_usec() - started) / 1000.0)
			mode = "inplace"


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	var gm: GameMap = base.get("_game_map")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match String(step.get("action", "")):
		"stroke":
			var stroker := Stroker.new()
			stroker.name = STROKER
			stroker.ctrl = ctrl
			stroker.gm = gm
			stroker.step = step
			base.get_tree().root.add_child(stroker)
			return "stroking %s" % step.get("name", "")
		"compare":
			var at: Array = step.get("at", [0, 0])
			var radius := float(step.get("radius", 12.0))
			var doc := ctrl.document
			var centre := Vector2(float(at[0]), float(at[1]))
			var comparer := Comparer.new()
			comparer.ctrl = ctrl
			comparer.reps = int(step.get("reps", 10))
			comparer.rect = MaskBrush.capsule_rect(doc, centre, centre, radius)
			var world := MaskBrush.sample_rect_to_world(doc, comparer.rect.grow(1))
			for cell in ScatterGenerator.cells_in_bounds(world.grow(doc.sample_step().x)):
				if TerrainMeshBuilder.chunk_sample_rect(doc, cell).size != Vector2i.ZERO:
					comparer.cells.append(cell)
			base.get_tree().root.add_child(comparer)
			return "comparing over %d chunks" % comparer.cells.size()
		"collision":
			var times := PackedFloat64Array()
			var small_times := PackedFloat64Array()
			var ray_times := PackedFloat64Array()
			var terrain := ctrl.editor.terrain
			var camera := gm.camera_node
			var size := Vector2(gm.world_viewport.size)
			# The CPU ray march the brush uses mid-stroke, through points across the screen.
			for rep in int(step.get("reps", 20)):
				var point := size * Vector2(0.2 + 0.03 * rep, 0.3 + 0.02 * rep)
				var origin := camera.project_ray_origin(point)
				var direction := camera.project_ray_normal(point)
				var started := Time.get_ticks_usec()
				ctrl.editor.raycast_ground(origin, direction)
				ray_times.append((Time.get_ticks_usec() - started) / 1000.0)
			# One chunk's worth (41 x 41 samples) on its own body, for a per-chunk split.
			var small := HeightMapShape3D.new()
			var body := StaticBody3D.new()
			var holder := CollisionShape3D.new()
			holder.shape = small
			body.add_child(holder)
			body.position = Vector3(0, -500, 0)
			terrain.add_child(body)
			var small_data := PackedFloat32Array()
			small_data.resize(41 * 41)
			for rep in int(step.get("reps", 20)):
				var started := Time.get_ticks_usec()
				terrain.update_collision()
				times.append((Time.get_ticks_usec() - started) / 1000.0)
				small_data[0] = rep * 0.01
				started = Time.get_ticks_usec()
				small.map_width = 41
				small.map_depth = 41
				small.map_data = small_data
				small_times.append((Time.get_ticks_usec() - started) / 1000.0)
			body.queue_free()
			return (
				(
					"update_collision (whole map) %s | a lone 41x41 shape %s | CPU ray march %s"
					+ " | physics thread %s"
				)
				% [
					Util.stats(times),
					Util.stats(small_times),
					Util.stats(ray_times),
					str(ProjectSettings.get_setting("physics/3d/run_on_separate_thread", false))
				]
			)
		"view_shift":
			# How far a fixed ground point moves on screen when the terrain's top rises by
			# `rise` m (the near-plane guard moving the camera back); 0 px is the goal.
			var camera := gm.camera_node
			var point := Vector3(12.0, 0.0, -9.0)
			var before := camera.unproject_position(point)
			var top: float = gm.get_camera_controller().ground_top_y
			gm.set_ground_top(top + float(step.get("rise", 8.0)))
			var after := camera.unproject_position(point)
			var moved_to := camera.global_position
			gm.set_ground_top(top)
			# The previous rule for comparison: scale the base offset by the same rise.
			var base_offset: Vector3 = gm.get_camera_controller().get("_base_camera_offset")
			var saved := camera.position
			var scale := saved.length() / base_offset.length()
			camera.position = base_offset * (scale + float(step.get("rise", 8.0)) / base_offset.y)
			var old_rule := camera.unproject_position(point)
			camera.position = saved
			return (
				(
					"view_shift: ground top %.2f -> %.2f moves a ground point %.2f px (camera %s);"
					+ " scaling the base offset instead moves it %.2f px"
				)
				% [
					top,
					top + float(step.get("rise", 8.0)),
					before.distance_to(after),
					str(moved_to),
					before.distance_to(old_rule)
				]
			)
		"snap_dense":
			return _snap_dense(ctrl)
		"check":
			return _check(ctrl, gm, step.get("area", [-30, -30, 30, 30]))
		"look_bottom":
			var at: Array = step.get("at", [0, 0])
			var target := Vector3(float(at[0]), float(step.get("y", 0.0)), float(at[1]))
			var camera := gm.camera_node
			var size := Vector2(gm.world_viewport.size)
			var point := Vector2(size.x * 0.5, size.y * 0.95)
			var origin := camera.project_ray_origin(point)
			var direction := camera.project_ray_normal(point)
			var hit := origin + direction * ((target.y - origin.y) / direction.y)
			var holder := gm.cameraholder_node
			holder.global_position += Vector3(target.x - hit.x, 0.0, target.z - hit.z)
			return "looking at %s from the bottom edge" % str(target)
	return "unknown action %s" % step.get("action", "")


static func _snap_dense(ctrl: AuthoringController) -> String:
	var editor := ctrl.editor
	var best := Vector2i.ZERO
	var most := -1
	for cell in ctrl.scatter.get("_cells").keys():
		var rows: Dictionary = ctrl.scatter.cell_rows(cell)
		var count := 0
		for asset_id in rows:
			count += (rows[asset_id] as PackedFloat32Array).size() / MapDocument.ROW_STRIDE
		if count > most:
			most = count
			best = cell
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var window := Rect2(Vector2(best) * size, Vector2(size, size))
	var centre := window.get_center()
	var results := PackedStringArray()
	for rep in 3:
		editor.begin_height_stroke(HeightBrush.RAISE)
		editor.height_dab(Vector3(centre.x, 0, centre.y), Vector3(centre.x, 0, centre.y), 9.0, 0.3)
		# Snap only this cell, timed; the terrain and collision are not part of it.
		var started := Time.get_ticks_usec()
		var moved: int = editor.heights.call("_snap_cell", best, window.grow(0.5))
		var snap_ms := (Time.get_ticks_usec() - started) / 1000.0
		editor.cancel_stroke()
		results.append("%.2f ms (%d rows moved)" % [snap_ms, moved])
	return "snap_dense cell %s with %d rows: %s" % [str(best), most, ", ".join(results)]


static func _check(ctrl: AuthoringController, gm: GameMap, area: Array) -> String:
	var doc := ctrl.document
	var terrain := ctrl.editor.terrain
	var rect := Rect2(
		Vector2(float(area[0]), float(area[1])),
		Vector2(float(area[2]) - float(area[0]), float(area[3]) - float(area[1]))
	)
	var heights := doc.heights
	var columns := doc.samples_x()
	var rows_count := doc.samples_z()
	var ground := func(p: Vector2) -> float:
		return ScatterGenerator.triangle_height(
			heights, columns, rows_count, doc.world_to_sample(p)
		)
	# Rays (a token-sized footprint: the centre and four points 0.3 m around it).
	var space := gm.world_viewport.find_world_3d().direct_space_state
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var ray_worst := 0.0
	var misses := 0
	for _i in 200:
		var c := Vector2(
			rng.randf_range(rect.position.x, rect.end.x),
			rng.randf_range(rect.position.y, rect.end.y)
		)
		for offset in [
			Vector2.ZERO, Vector2(0.3, 0), Vector2(-0.3, 0), Vector2(0, 0.3), Vector2(0, -0.3)
		]:
			var p: Vector2 = c + offset
			var query := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 200.0, p.y), Vector3(p.x, -200.0, p.y), 1
			)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				misses += 1
				continue
			ray_worst = maxf(ray_worst, absf(hit.position.y - float(ground.call(p))))
	# Rows.
	var row_worst := 0.0
	var off_rows := 0
	var checked := 0
	for node in [ctrl.scatter, ctrl.props]:
		var by_asset: Dictionary = node.rows_by_asset()
		for asset_id in by_asset:
			var flat: PackedFloat32Array = by_asset[asset_id]
			for b in range(0, flat.size(), MapDocument.ROW_STRIDE):
				var p := Vector2(flat[b], flat[b + 2])
				if not rect.has_point(p):
					continue
				checked += 1
				var d := absf(flat[b + 1] - float(ground.call(p)))
				row_worst = maxf(row_worst, d)
				if d > 0.02:
					off_rows += 1
	# In-place chunks against a rebuild, and chunk AABBs.
	var mirrors: Dictionary = terrain.get("_mirrors")
	var mismatched := 0
	for cell in mirrors:
		var fresh := TerrainMeshBuilder.chunk_vertex_mirror(doc, cell)
		var mirror: Dictionary = mirrors[cell]
		if mirror.positions != fresh.positions or mirror.normals != fresh.normals:
			mismatched += 1
	var aabb_worst := 0.0
	for cell in terrain.chunk_cells():
		var chunk_rect := TerrainMeshBuilder.chunk_sample_rect(doc, cell)
		var low := INF
		var high := -INF
		for z in range(chunk_rect.position.y, chunk_rect.end.y + 1):
			for x in range(chunk_rect.position.x, chunk_rect.end.x + 1):
				var h := heights[doc.sample_index(x, z)]
				low = minf(low, h)
				high = maxf(high, h)
		var aabb := terrain.get_chunk(cell).mesh.get_aabb()
		aabb_worst = maxf(aabb_worst, maxf(absf(aabb.position.y - low), absf(aabb.end.y - high)))
	# Near plane.
	var camera := gm.camera_node
	var size := Vector2(gm.world_viewport.size)
	var bl := camera.project_ray_origin(Vector2(0, size.y))
	var br := camera.project_ray_origin(size)
	var top := terrain.world_height_range().y
	var cc := gm.get_camera_controller()
	return (
		(
			"check %s: rays %d misses %d worst |dy| %.4f m"
			+ " | rows checked %d worst |dy| %.4f m, %d off by > 2 cm"
			+ " | in-place chunks %d, %d differ from a rebuild | chunk AABB worst %.4f m"
			+ " | near plane: bottom ray origins y %.2f / %.2f, terrain top %.2f, ground_top_y %.2f"
		)
		% [
			str(area),
			1000,
			misses,
			ray_worst,
			checked,
			row_worst,
			off_rows,
			mirrors.size(),
			mismatched,
			aabb_worst,
			bl.y,
			br.y,
			top,
			cc.ground_top_y
		]
	)
