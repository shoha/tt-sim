extends RefCounted

## Render-job probe (`call` op) for the biome designer (content library step S8a).
## step.action:
##   open {library, biome}        opens the designer on that biome (EventBus.biome_designer_requested,
##                                as the title's picker does); follow it with `wait_ready`.
##   report                       logs the designer's state: the rules, the selection, what the scatter
##                                holds, the last regeneration's stats and the budget meter.
##   select {rule}                selects a rule ("" for none).
##   set {rule, field, value}     one numeric field of a rule through the model (null clears it).
##   curve {rule, axis, preset | points}   sets a response curve (a preset name or [[x, y]...]).
##   slope_min {rule, degrees}    the band edge.
##   ground {field, surface}      a ground surface of the biome (the map is rebuilt from its document).
##   add_ref {rule, ref}, remove_rule {rule}, add_rule {role}, undo, redo.
##   debounce {seconds}           the session's debounce (0 to time an edit without it).
##   edit_timed {rule, field, value}   `set` that also notes the time, so `stats` reports it.
##   stats                        logs the last edit's timing (compile, serve, request, regen, total).
##   full                         regenerates every rule of the biome (the cost to compare against).
##   cancel                       cancels the regeneration under way.
##   pick {at: [x, z]}            logs the rule of the plant nearest that ground point.
##   click_rule {rule}            clicks (the host's pick_at) the middle of the first plant of that rule
##                                on the map, and logs the rule it selected.
##   save_check                   logs what Save would do (writable, dirty, errors).
##   picker                       shows the title's "Design a biome" sheet over the game.
##   press {name, under}          presses the button called `name` (inside the node `under`).
##   text {name, value}           types into the LineEdit called `name`.
##   save, leave                  the designer's Save and Leave, as the buttons do them.
##   libraries                    logs the collections served and the user collection folders.
##   cleanup {library}            deletes the user collection `library` and serves the rest again.


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "open":
		EventBus.biome_designer_requested.emit(String(step.library), String(step.biome))
		return "requested %s / %s" % [step.library, step.biome]
	if action == "picker":
		BiomeDesignerPicker.show_over(base)
		return "picker shown"
	if action == "press" or action == "text":
		return _ui(base, step, action)
	if action == "libraries":
		return _libraries()
	if action == "cleanup":
		return _cleanup(String(step.library))
	var controller: AuthoringController = base.get("_authoring_controller")
	if controller == null or controller.designer == null:
		return "no designer open"
	var session := controller.designer.session
	var model := session.model
	match action:
		"report":
			return _report(controller, session)
		"select":
			session.select_rule(String(step.get("rule", "")))
			return "selected '%s'" % session.selected_rule
		"set", "edit_timed":
			return _edit(session, step, action == "edit_timed")
		"curve":
			return _curve(model, step)
		"ground":
			return str(DesignerBiomeEdits.set_ground(model, String(step.field), String(step.surface)))
		"slope_min":
			return str(DesignerResponseEdits.set_slope_min(model, String(step.rule), step.degrees))
		"add_ref":
			return str(model.add_ref(String(step.rule), String(step.ref)))
		"remove_rule":
			return str(model.remove_rule(String(step.rule)))
		"add_rule":
			return model.add_rule(String(step.role))
		"undo":
			return str(model.undo())
		"redo":
			return str(model.redo())
		"whole":
			session.whole = bool(step.get("on", true))
			return "whole regeneration %s" % session.whole
		"debounce":
			session.debounce = float(step.get("seconds", 0.0))
			return "debounce %.2f" % session.debounce
		"stats":
			return "%s %s" % [step.get("label", ""), JSON.stringify(session.stats)]
		"full":
			session.regenerate_all()
			return "regenerating all"
		"cancel":
			session.cancel()
			return "state %d" % session.state
		"pick":
			return _pick(controller, session, step)
		"click_rule":
			return _click_rule(controller, session, step)
		"save":
			controller.designer.save()
			return "saved, dirty %s" % model.is_dirty()
		"leave":
			controller.designer.request_leave()
			return "leaving"
		"save_check":
			var verdict := model.validation()
			return (
				"writable %s dirty %s errors %d warnings %d"
				% [
					model.writable,
					model.is_dirty(),
					(verdict["errors"] as Array).size(),
					(verdict["warnings"] as Array).size()
				]
			)
	return "unknown action"


static func _report(controller: AuthoringController, session: BiomeDesignerSession) -> String:
	var model := session.model
	var held := ScatterRefresh.counts(controller.scatter)
	var budget := session.budget()
	var lines := PackedStringArray()
	lines.append(
		(
			"biome %s in %s (%s), %d rules, dirty %s, selected '%s', state %d"
			% [
				model.biome_id,
				model.library_id,
				model.source,
				model.rule_keys().size(),
				model.is_dirty(),
				session.selected_rule,
				session.state
			]
		)
	)
	lines.append(
		(
			"scatter: %d instances in %d assets, regenerating %s"
			% [
				held["instances"],
				(held["counts"] as Dictionary).size(),
				controller.scatter.is_regenerating()
			]
		)
	)
	if not budget.is_empty():
		lines.append(
			(
				"budget: %d tris per tile, %.0f%% of the 200 ft budget (%s), %d draw est."
				% [
					int(budget["per_tile"]["triangles"]),
					float(budget["map"]["share"]) * 100.0,
					budget["map"]["level"],
					int(budget["draw_calls"])
				]
			)
		)
	lines.append("stats " + JSON.stringify(session.stats))
	return "\n".join(lines)


static func _edit(session: BiomeDesignerSession, step: Dictionary, timed: bool) -> String:
	if timed:
		session.debounce = float(step.get("debounce", 0.0))
	var value: Variant = step.get("value")
	if value is String and String(value).is_valid_float():
		value = String(value).to_float()
	var ok := session.model.set_field(String(step.rule), String(step.field), value)
	return "%s %s.%s = %s" % ["ok" if ok else "no change", step.rule, step.field, str(value)]


static func _curve(model: BiomeDesignerModel, step: Dictionary) -> String:
	var rule := String(step.rule)
	var axis := String(step.axis)
	if step.has("preset"):
		var ok := DesignerResponseEdits.set_preset(model, rule, axis, String(step.preset))
		return "%s preset %s" % ["ok" if ok else "no change", step.preset]
	var ok := DesignerResponseEdits.set_curve(model, rule, axis, step.points)
	return "%s points %s" % ["ok" if ok else "no change", str(step.points)]


static func _pick(
	controller: AuthoringController, session: BiomeDesignerSession, step: Dictionary
) -> String:
	var at: Array = step.at
	var ground := Vector2(float(at[0]), float(at[1]))
	var best := ""
	var best_distance := 1e9
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var centre := Vector2i(floori(ground.x / size), floori(ground.y / size))
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var rows := controller.scatter.cell_rows(centre + Vector2i(dx, dz))
			for asset_id: String in rows:
				var flat: PackedFloat32Array = rows[asset_id]
				for r in flat.size() / MapDocument.ROW_STRIDE:
					var distance := Vector2(flat[r * 10], flat[r * 10 + 2]).distance_to(ground)
					if distance < best_distance:
						best_distance = distance
						best = asset_id
	return "nearest %s at %.2f m -> rule '%s'" % [best, best_distance, session.rule_of_asset(best)]


static func _ui(base: Node, step: Dictionary, action: String) -> String:
	var scope: Node = base
	if step.has("under"):
		scope = base.find_child(String(step.under), true, false)
		if scope == null:
			return "no node %s" % step.under
	var found := scope.find_child(String(step.name), true, false)
	if found == null:
		return "no control %s" % step.name
	if action == "press":
		(found as Button).pressed.emit()
		return "pressed %s" % step.name
	(found as LineEdit).text = String(step.value)
	(found as LineEdit).text_changed.emit(String(step.value))
	return "typed '%s' into %s" % [step.value, step.name]


static func _libraries() -> String:
	var lines := PackedStringArray()
	for entry in LibraryRegistry.list():
		lines.append(
			(
				"%s [%s] status %s biomes %s"
				% [entry["id"], entry["source"], entry["status"], str(entry["biome_ids"])]
			)
		)
	lines.append("user folders: " + str(DirAccess.get_directories_at(LibraryRegistry.user_root)))
	return "\n".join(lines)


static func _cleanup(library: String) -> String:
	var folder := LibraryRegistry.user_root.path_join(library)
	if library == "" or library == "core" or not DirAccess.dir_exists_absolute(folder):
		return "nothing to remove"
	_remove_tree(folder)
	FoliageLibrary.apply(FoliageLibrary.current(), FoliageLibrary.active_package())
	return "removed %s" % folder


static func _remove_tree(path: String) -> void:
	for file_name in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	for sub in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)


static func _click_rule(
	controller: AuthoringController, session: BiomeDesignerSession, step: Dictionary
) -> String:
	var wanted := String(step.rule)
	var camera: Camera3D = controller.designer._game_map.camera_node
	if camera == null:
		return "no camera"
	var best := Vector3.INF
	var best_asset := ""
	for cell: Vector2i in controller.scatter._cells:
		var held: Dictionary = controller.scatter._cells[cell]
		for asset_id: String in held:
			if session.rule_of_asset(asset_id) != wanted:
				continue
			var rows: PackedFloat32Array = held[asset_id]
			var height := float(PaletteLibrary.asset(asset_id).get("dimensions_m", [0, 1, 0])[1])
			for r in rows.size() / MapDocument.ROW_STRIDE:
				var at := r * MapDocument.ROW_STRIDE
				var middle := Vector3(
					rows[at], rows[at + 1] + height * 0.5 * rows[at + 8], rows[at + 2]
				)
				if (
					best == Vector3.INF
					or Vector2(middle.x, middle.z).length() < Vector2(best.x, best.z).length()
				):
					best = middle
					best_asset = asset_id
	if best == Vector3.INF:
		return "no plant of rule %s on the map" % wanted
	var pointer := camera.unproject_position(best)
	var key := controller.designer.pick_at(pointer)
	return "clicked %s at %s: selected '%s'" % [best_asset, str(pointer), key]
