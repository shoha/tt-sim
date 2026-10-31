extends RefCounted

## Render-job probe (`call` op) for dressed streets (card settlement, docs/systems/settlements.md).
## step.action:
##   street {from, to, preset, side, seed, setback}   lays a street through the editor (world XZ)
##   dress {id, kit, wealth, density}    dresses street `id` (default: the first), bakes the cells
##                                       now and reports them
##   redress / clear {id}                the Re-dress and Clear buttons (settlement id, default 1)
##   select {id}                         picks the street in the Street tool, so its bar shows
##   report                              cells, surfaces, triangles, placements, skipped
##   perf {...}                          lays a long street, dresses it and measures the layer
##   undo                                the editor's history undo
## Every action returns the line the job log prints.


static func run(base: Node, step: Dictionary) -> String:
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match String(step.get("action", "report")):
		"street":
			return _street(ctrl.editor, step)
		"dress":
			return _dress(ctrl.editor, step)
		"redress":
			var id := int(step.get("id", 1))
			var ok := ctrl.editor.settlements.redress(id)
			return _flush(ctrl.editor, "redress %d %s" % [id, str(ok)])
		"clear":
			var id := int(step.get("id", 1))
			var ok := ctrl.editor.settlements.clear(id)
			return _flush(ctrl.editor, "clear %d %s" % [id, str(ok)])
		"select":
			return _select(base, int(step.get("id", 1)))
		"undo":
			var label := ctrl.history.undo() if ctrl.history != null else "no history"
			return _flush(ctrl.editor, "undo " + label)
		"perf":
			return _perf(ctrl.editor, step)
		"corridor":
			return _corridor(ctrl)
		"aim":
			return _aim(base, ctrl.editor, step)
	return _report(ctrl.editor)


static func _street(editor: AuthoringEditor, step: Dictionary) -> String:
	var a: Array = step.get("from", [-12, 0])
	var b: Array = step.get("to", [12, 0])
	var id := editor.walls.place(
		Wall.Kind.ROW,
		Vector3(float(a[0]), 0, float(a[1])),
		Vector3(float(b[0]), 0, float(b[1])),
		float(step.get("setback", 3.0)),
		{
			"seed": int(step.get("seed", 5)),
			"side": int(step.get("side", 2)),
			"preset": int(step.get("preset", 3))
		}
	)
	return "street %d" % id if id >= 0 else "refused: %s" % editor.walls.last_refusal


static func _dress(editor: AuthoringEditor, step: Dictionary) -> String:
	var street := int(step.get("id", -1))
	if street < 0 and not editor.document.walls.is_empty():
		street = editor.document.walls[0].id
	var started := Time.get_ticks_usec()
	var id := editor.settlements.dress(
		street,
		String(step.get("kit", "farming_hamlet")),
		float(step.get("wealth", -1.0)),
		float(step.get("density", -1.0))
	)
	var layer := _layer(editor)
	var made := layer.flush() if layer != null else 0
	return (
		"dressed settlement %d on street %d: %d cells baked in %.1f ms; %s"
		% [id, street, made, (Time.get_ticks_usec() - started) / 1000.0, _report(editor)]
	)


static func _select(base: Node, wall_id: int) -> String:
	var gm := base.get("_game_map") as GameMap
	if gm == null or gm.get_brush_tool() == null:
		return "no brush"
	WallTool.of(gm.get_brush_tool()).select(wall_id)
	return "selected street %d" % wall_id


static func _layer(editor: AuthoringEditor) -> AuthoredSettlements:
	if not is_instance_valid(editor.map_root):
		return null
	return editor.map_root.get_node_or_null(AuthoredSettlements.NODE_NAME) as AuthoredSettlements


static func _flush(editor: AuthoringEditor, head: String) -> String:
	var layer := _layer(editor)
	if layer != null:
		layer.flush()
	return head + "; " + _report(editor)


static func _report(editor: AuthoringEditor) -> String:
	var layer := _layer(editor)
	if layer == null:
		return (
			"no AuthoredSettlements; settlements in document %d"
			% editor.document.settlements.size()
		)
	var surfaces := 0
	var triangles := 0
	var vertices := 0
	for child in layer.get_children():
		var mesh := (child as MeshInstance3D).mesh
		surfaces += mesh.get_surface_count()
		for s in mesh.get_surface_count():
			triangles += (
				(mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			)
			vertices += mesh.surface_get_array_len(s)
	return (
		(
			"settlements %d; cells %d; draw surfaces %d; triangles %d; vertices %d; placed %d;"
			+ " skipped ground %d, missing %d"
		)
		% [
			editor.document.settlements.size(),
			layer.get_child_count(),
			surfaces,
			triangles,
			vertices,
			layer.placed,
			layer.skipped_ground,
			layer.skipped_missing,
		]
	)


## Puts the camera on the `index`th placement of prop `prop` ("laundry_line", "market_stall") in
## the dressed streets, zoomed to `zoom` (follow with a `settle`), and logs what is placed.
static func _aim(base: Node, editor: AuthoringEditor, step: Dictionary) -> String:
	var layer := _layer(editor)
	var gm := base.get("_game_map") as GameMap
	if layer == null or gm == null:
		return "no layer or map"
	var wanted := String(step.get("prop", "laundry_line"))
	var found: Array[Vector2] = []
	var counts := {}
	for settlement in editor.document.settlements:
		for row in layer.standing(settlement.id):
			var name_of := String(row["item"]["prop"])
			counts[name_of] = int(counts.get(name_of, 0)) + 1
			if name_of == wanted:
				found.append(row["item"]["position"])
	if found.is_empty():
		return "no %s among %s" % [wanted, str(counts)]
	var at := found[mini(int(step.get("index", 0)), found.size() - 1)]
	var cc := gm.get_camera_controller()
	var off: Vector2 = cc.call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)
	if step.has("zoom"):
		cc.set("_target_zoom", float(step["zoom"]))
	return "aimed at %s %d of %d at %s; %s" % [wanted, int(step.get("index", 0)), found.size(), str(at), str(counts)]


## Scatter rows (per asset file) standing inside each street's corridor (within the setback of its
## centre line), and the ground sampler's open share on the centre line.
static func _corridor(ctrl: AuthoringController) -> String:
	var doc := ctrl.document
	var rows: Dictionary = ctrl.scatter.rows_by_asset() if ctrl.scatter else {}
	var lines := PackedStringArray()
	for wall in doc.walls:
		if not wall.is_row():
			continue
		var inside := {}
		var total := 0
		var all := 0
		for asset_id: String in rows:
			var flat: PackedFloat32Array = rows[asset_id]
			for r in range(0, flat.size(), MapDocument.ROW_STRIDE):
				all += 1
				var p := Vector2(flat[r], flat[r + 2])
				var best := INF
				for k in wall.points.size() - 1:
					var a := wall.points[k]
					var along := (wall.points[k + 1] - a).normalized()
					var t := (p - a).dot(along)
					if t < 0.0 or t > a.distance_to(wall.points[k + 1]):
						continue
					best = minf(best, absf((p - a).dot(Vector2(-along.y, along.x))))
				if best <= wall.height_m + WallGeometry.STREET_CLEAR_EXTRA_M - 0.5:
					total += 1
					inside[asset_id.get_file()] = int(inside.get(asset_id.get_file(), 0)) + 1
		lines.append(
			"street %d setback %.1f: %d of %d scatter rows in the corridor %s"
			% [wall.id, wall.height_m, total, all, str(inside)]
		)
	return "\n".join(lines)


## A long street dressed and measured: the layer's draws, bake times and memory.
static func _perf(editor: AuthoringEditor, step: Dictionary) -> String:
	var kit := String(step.get("kit", "market_town"))
	var street := editor.document.walls[0].id if not editor.document.walls.is_empty() else -1
	if street < 0:
		return "no street"
	AuthoredSettlements.clear_variants()
	var memory_before := Performance.get_monitor(Performance.MEMORY_STATIC)
	var started := Time.get_ticks_usec()
	var id := editor.settlements.dress(
		street, kit, float(step.get("wealth", 0.6)), float(step.get("density", 1.2))
	)
	var plan_ms := (Time.get_ticks_usec() - started) / 1000.0
	var layer := _layer(editor)
	var baked_started := Time.get_ticks_usec()
	var made := layer.flush()
	var bake_ms := (Time.get_ticks_usec() - baked_started) / 1000.0
	var again_started := Time.get_ticks_usec()
	editor.settlements.redress(id)
	layer.flush()
	var redress_ms := (Time.get_ticks_usec() - again_started) / 1000.0
	var memory_after := Performance.get_monitor(Performance.MEMORY_STATIC)
	return (
		(
			"perf %s: plan and refresh %.1f ms; cold bake (variants and %d cells) %.1f ms; re-dress"
			+ " (warm variants) %.1f ms; static memory +%.2f MB; %s"
		)
		% [
			kit,
			plan_ms,
			made,
			bake_ms,
			redress_ms,
			(memory_after - memory_before) / 1048576.0,
			_report(editor),
		]
	)
