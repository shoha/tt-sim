class_name BiomeDesignerHost
extends Node

## Puts the biome designer into an authoring session (step S8a): AuthoringController opens the
## proving ground as it opens any new map and, when the request carries a designer, attaches this
## host to it. The host hides the tool drawer, builds the session (BiomeDesignerSession: the
## live compile and the partial regeneration) and the screen (DesignerUI), and owns what leaves
## the screen: Save and Save as new collection (LibraryWriter), Revert, the keyboard (Ctrl+Z and
## Ctrl+Y, Delete for the selected rule, Escape to leave), clicking a plant on the map to select
## its rule, and the way out, which asks about unsaved edits and puts the served libraries back
## as they were before the draft was laid over them. The proving ground is never a saved map: the
## controller's autosave is off for the session and leaving does not ask about the map.
## Map and model: docs/systems/biome_designer.md.

signal left

const ZOOM_OUT_STEPS := 60

var controller: AuthoringController = null
var model: BiomeDesignerModel = null
var session: BiomeDesignerSession = null
var ui: DesignerUI = null

var _game_map: GameMap = null
var _prompt: Node = null
var _leaving: bool = false


## Attaches a host to `authoring` (an open session whose map is the proving ground) over the
## designer request `config` ({model}). Returns the host, already in the tree.
static func attach(
	authoring: AuthoringController, game_map: GameMap, config: Dictionary
) -> BiomeDesignerHost:
	var host := BiomeDesignerHost.new()
	host.name = "BiomeDesignerHost"
	authoring.add_child(host)
	host.setup(authoring, game_map, config["model"])
	return host


func setup(authoring: AuthoringController, game_map: GameMap, designed: BiomeDesignerModel) -> void:
	controller = authoring
	_game_map = game_map
	model = designed
	controller.brush.deactivate()
	# The whole proving ground in view to start with.
	var camera_controller := game_map.get_camera_controller()
	for _step in ZOOM_OUT_STEPS:
		camera_controller.zoom_out_step()
	if controller.panel != null:
		controller.panel.visible = false
	session = BiomeDesignerSession.new()
	session.name = "Session"
	add_child(session)
	session.setup(model, controller)
	ui = DesignerUI.new()
	ui.setup(session)
	ui.header.meter.live_source = _live_cost
	ui.save_requested.connect(save)
	ui.save_as_requested.connect(save_as_collection)
	ui.revert_requested.connect(revert)
	ui.leave_requested.connect(request_leave)
	var layer: Node = controller.panel.get_parent() if controller.panel != null else controller
	layer.add_child(ui)
	set_process_unhandled_input(true)


## Writes the draft to its library folder.
func save() -> void:
	var written := model.save()
	if written["ok"]:
		LibraryRegistry.refresh()
		UIManager.show_toast(
			"Saved %s to %s." % [model.biome_id, model.library_name], UIManager.TOAST_SUCCESS, 4.0
		)
	else:
		UIManager.show_toast(String(written["error"]), UIManager.TOAST_WARNING, 6.0)


## Copies the draft into a new user collection and continues in the copy.
func save_as_collection(collection_id: String, collection_name: String) -> void:
	var made := LibraryWriter.create_collection(
		LibraryRegistry.user_root,
		collection_id,
		collection_name,
		model.context,
		model.biome_id,
		model.def
	)
	if not made["ok"]:
		UIManager.show_toast(String(made["error"]), UIManager.TOAST_WARNING, 6.0)
		return
	var library_id := collection_id
	var biome_id := model.biome_id
	UIManager.show_toast(
		"Created the %s %s. Opening it." % [LibraryNames.lower(), collection_name],
		UIManager.TOAST_SUCCESS,
		4.0
	)
	_leave_then_open(library_id, biome_id)


func revert() -> void:
	model.revert()


## Leaves, asking first when the biome has unsaved edits.
func request_leave() -> void:
	if _leaving or is_instance_valid(_prompt):
		return
	if not model.is_dirty():
		_leave()
		return
	if model.writable:
		_prompt = UIManager.show_choice(
			"Leave with unsaved changes?",
			"The changes to %s are not saved yet." % model.biome_id,
			"Save and leave",
			"Discard",
			"Cancel",
			func() -> void:
				save()
				if not model.is_dirty():
					_leave(),
			_leave
		)
	else:
		_prompt = UIManager.show_confirmation(
			"Discard your changes?",
			(
				"%s is read-only, so the changes are lost unless you save a copy first."
				% model.library_name
			),
			"Discard",
			"Keep designing",
			_leave
		)


func _unhandled_input(event: InputEvent) -> void:
	if _leaving or ui == null or ui.has_dialog():
		return
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT and button.pressed:
			_pick_at_pointer()
		return
	if not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	if _typing():
		return
	if key.ctrl_pressed and key.keycode == KEY_Z:
		if key.shift_pressed:
			model.redo()
		else:
			model.undo()
	elif key.ctrl_pressed and key.keycode == KEY_Y:
		model.redo()
	elif key.ctrl_pressed and key.keycode == KEY_S:
		save()
	elif key.keycode == KEY_DELETE and session.selected_rule != "":
		var gone := session.selected_rule
		session.select_rule("")
		model.remove_rule(gone)
	elif key.keycode == KEY_ESCAPE:
		request_leave()
	else:
		return
	get_viewport().set_input_as_handled()


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


## Selects the rule of the plant under the pointer, if any.
func _pick_at_pointer() -> void:
	if _game_map != null:
		pick_at(_game_map.world_viewport.get_mouse_position())


## Selects the rule of the plant at `pointer` (world viewport pixels) and returns its key, ""
## when there is none (the selection is cleared).
func pick_at(pointer: Vector2) -> String:
	var made := controller.scatter
	if made == null or _game_map == null:
		return ""
	var viewport := _game_map.world_viewport
	var camera := _game_map.camera_node
	var origin := camera.project_ray_origin(pointer)
	var direction := camera.project_ray_normal(pointer)
	var space := viewport.find_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		origin, origin + direction * BrushTool.RAY_LENGTH
	)
	query.collision_mask = BrushTool.TERRAIN_LAYER
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		session.select_rule("")
		return ""
	var ground := Vector2(hit.position.x, hit.position.z)
	var size := ScatterChunker.CHUNK_SIZE_WORLD_UNITS
	var centre := Vector2i(floori(ground.x / size), floori(ground.y / size))
	var cells := {}
	var heights := {}
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var rows := made.cell_rows(centre + Vector2i(dx, dz))
			cells[centre + Vector2i(dx, dz)] = rows
			for asset_id: String in rows:
				var dims: Variant = PaletteLibrary.asset(asset_id).get("dimensions_m", Vector3.ONE)
				heights[asset_id] = float(dims[1])
	var picked := DesignerPicking.pick(
		func(point: Vector3) -> Vector2: return camera.unproject_position(point),
		pointer,
		ground,
		cells,
		heights
	)
	var key := (
		session.rule_of_asset(String(picked.get("asset", ""))) if not picked.is_empty() else ""
	)
	session.select_rule(key)
	return key


## The renderer's cost of the map now, for the budget meter.
func _live_cost() -> Dictionary:
	if _game_map == null:
		return {}
	var rid := _game_map.world_viewport.get_viewport_rid()
	var visible := RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE
	return {
		"draw_calls":
		RenderingServer.viewport_get_render_info(
			rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME
		),
		"primitives":
		RenderingServer.viewport_get_render_info(
			rid, visible, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME
		),
		"cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(rid),
		"gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(rid),
	}


func _exit_tree() -> void:
	# Torn down by something other than Leave: the served libraries still go back.
	if not _leaving:
		_restore_libraries()


func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	_restore_libraries()
	left.emit()
	controller.leave_now()


## Leaves the session and asks Root to open `biome_id` of `library_id` in a fresh one.
func _leave_then_open(library_id: String, biome_id: String) -> void:
	_leaving = true
	_restore_libraries()
	left.emit()
	controller.leave_now()
	EventBus.biome_designer_requested.emit(library_id, biome_id)


## The served libraries as they were: the draft overlay is gone and a saved biome is read again.
func _restore_libraries() -> void:
	FoliageLibrary.apply(FoliageLibrary.current(), FoliageLibrary.active_package())
