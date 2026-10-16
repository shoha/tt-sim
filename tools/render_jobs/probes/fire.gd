extends RefCounted

## Render-job probe (`call` op) for persistent ground fire's look (FireField, FireLook; the fire
## cards' jobs firefeat_build, firefeat_look and firefeat_cleanup). Actions:
##   info              flames shown and planned (the cap), burning blocks, entries by band
##   shot {key}        "<day|dusk>_<view>": the sun (DefaultSun at 14:00 or DUSK_HOUR, through
##                     the level's sun as the Sun pane's time of day does), the view (home; z8,
##                     zoom 8 over a point on the blaze; z20, zoom 20 over the fire's middle; z30,
##                     zoom 30 there, past the LOD zoom) and an on-screen label, `label` (default
##                     "NEW") before the key's words
##   label {text}      an on-screen caption for captures ("" removes it)
##   replay {path, text}  an earlier capture over the whole window under the caption `text`, so
##                     a capture re-labels it for a sheet (an empty path removes it)
##   flames {show}     shows or hides the flames, to judge the ground's glow alone
##   param {target, name, value}  sets a shader parameter on the "ground" (the map's ground
##                     material) or the "flames" (FireLook's material), for look comparisons
##   shadows {on}      turns every directional light's shadow on or off
##   time              the engine clock and frames drawn, to measure a motion strip's spacing
##   burst {dir, name, count, every}  grabs `count` frames of the window `every` seconds apart
##                     and saves them as <name>_<k>.png with their engine times in
##                     <name>_times.txt (a capture step takes about 0.4 s, too slow for a strip
##                     of held drawings); wait about count x 0.25 s after it
##   save {folder}     saves the open map as a PREFIX test level (replacing one there)
##   cleanup           deletes every PREFIX test level
## The views and the sun match the F3 probe's (docs/plans/2026-10-11-fire-features/probe.md), so
## its frames can sit beside new ones in a sheet; ahome and az20 look at firefeat_build's second,
## author-laid fire (a blob and a curving line) at the home zoom and zoom 20.

const PREFIX := "_firefeat_"
const LABEL := "FireProbeLabel"
const LABEL_MIN_W := 960.0
const REPLAY := "FireProbeReplay"
## Where the zoomed views look: a point on the blaze, and the middle of the fire.
const BLAZE_AT := Vector2(-2.0, -2.5)
const FIRE_AT := Vector2(0.0, -3.0)
const AUTHOR_AT := Vector2(3.0, 17.0)
const DUSK_HOUR := 19.0
const VIEWS := {
	"home": "home",
	"z8": "zoom 8",
	"z20": "zoom 20",
	"z30": "zoom 30",
	"ahome": "author fire, home zoom",
	"az20": "author fire, zoom 20",
}

static var _sun_key := ""
static var _view_key := ""


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	if action == "cleanup":
		return _cleanup()
	if action == "label":
		return _label(base, String(step.get("text", "")))
	if action == "replay":
		return _replay(base, String(step.get("path", "")), String(step.get("text", "")))
	if action == "time":
		return "time %.3f s frames %d" % [Time.get_ticks_usec() / 1e6, Engine.get_frames_drawn()]
	if action == "burst":
		return _burst(base, step)
	if action == "shadows":
		var on := bool(step.get("on", true))
		for light in base.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
			(light as DirectionalLight3D).shadow_enabled = on
		return "shadows %s" % ("on" if on else "off")
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match action:
		"info":
			return _info(ctrl.document, ctrl.editor.fire_field)
		"shot":
			var gm: GameMap = base.get("_game_map")
			var label := String(step.get("label", "NEW"))
			return _shot(base, ctrl, gm, String(step.get("key", "")), label)
		"save":
			return _save(ctrl, String(step.get("folder", PREFIX + "look")))
		"flames":
			var show := bool(step.get("show", true))
			ctrl.editor.fire_field.visible = show
			return "flames %s" % ("shown" if show else "hidden")
		"param":
			return _param(ctrl.editor.fire_field, step)
	return "unknown action %s" % action


## Grabs step.count frames of the window step.every seconds apart, then saves them (see the
## header's burst).
static func _burst(base: Node, step: Dictionary) -> String:
	var dir := String(step.get("dir", "user://render_jobs"))
	var prefix := String(step.get("name", "burst"))
	var count := int(step.get("count", 8))
	var timer := Timer.new()
	timer.wait_time = float(step.get("every", 0.1))
	var frames: Array[Image] = []
	var times: Array[String] = []
	base.add_child(timer)
	timer.timeout.connect(
		func() -> void:
			frames.append(base.get_viewport().get_texture().get_image())
			times.append("%d %.3f" % [frames.size() - 1, Time.get_ticks_usec() / 1e6])
			if frames.size() < count:
				return
			timer.stop()
			for k in frames.size():
				frames[k].save_png(dir.path_join("%s_%d.png" % [prefix, k]))
			var file := FileAccess.open(dir.path_join(prefix + "_times.txt"), FileAccess.WRITE)
			file.store_string("\n".join(PackedStringArray(times)))
			file.close()
			timer.queue_free()
	)
	timer.start()
	return "burst %d frames every %.2f s into %s" % [count, timer.wait_time, dir]


static func _param(field: FireField, step: Dictionary) -> String:
	var target := String(step.get("target", "flames"))
	var key := String(step.get("name", ""))
	var material: ShaderMaterial = FireLook.material()
	if target == "ground":
		material = null
		for child in field.get_parent().get_children():
			if child is AuthoredTerrain and (child as AuthoredTerrain).get_material() != null:
				material = (child as AuthoredTerrain).get_material()
		if material == null:
			return "no ground material"
	material.set_shader_parameter(key, step.get("value"))
	return "%s %s = %s" % [target, key, str(step.get("value"))]


static func _info(doc: MapDocument, field: FireField) -> String:
	if field == null:
		return "no fire field"
	var planned := 0
	var burning := 0
	var bands := [0, 0, 0, 0]
	for block in FireField.blocks_of(doc, Rect2i(0, 0, doc.samples_x(), doc.samples_z())):
		var plan := FireField.plan_block(doc, block)
		@warning_ignore("integer_division")
		var n := plan.size() / FireField.STRIDE
		planned += n
		burning += 1 if n > 0 else 0
		for k in n:
			var heat := roundi(plan[k * FireField.STRIDE + FireField.INTENSITY] * 255.0)
			bands[FireField.band(heat)] += 1
	return (
		"fire shown %d of planned %d (cap %d); blocks with flames %d; sparks %d flames %d blaze %d"
		% [field.flame_count(), planned, FireField.MAX_FLAMES, burning, bands[1], bands[2], bands[3]]
	)


static func _shot(
	base: Node, ctrl: AuthoringController, gm: GameMap, key: String, label: String
) -> String:
	var parts := key.split("_")
	if parts.size() != 2 or not VIEWS.has(parts[1]):
		return "bad key %s" % key
	var out := PackedStringArray()
	if parts[0] != _sun_key:
		var hour := DUSK_HOUR if parts[0] == "dusk" else DefaultSun.DEFAULT_TIME_OF_DAY
		out.append(_sun(ctrl, hour))
		_sun_key = parts[0]
	if parts[1] != _view_key:
		out.append(_view(gm, parts[1]))
		_view_key = parts[1]
	out.append(_label(base, "%s   |   %s, %s" % [label, parts[0], VIEWS[parts[1]]]))
	return "; ".join(out)


static func _sun(ctrl: AuthoringController, hour: float) -> String:
	var manager: LevelEnvironmentManager = ctrl.get("_environment")
	if manager == null:
		return "no environment manager"
	var settings := DefaultSun.settings_for_time(hour)
	manager.apply_sun_settings(settings)
	var elevation := settings.elevation_degrees
	return "sun %.1f h: energy %.2f elevation %.1f" % [hour, settings.energy, elevation]


static func _view(gm: GameMap, view: String) -> String:
	var cc := gm.get_camera_controller()
	match view:
		"home":
			cc.call("_reset_camera_to_home")
		"z8":
			cc.set("_target_zoom", 8.0)
			_look(gm, BLAZE_AT)
		"z20":
			cc.set("_target_zoom", 20.0)
			_look(gm, FIRE_AT)
		"z30":
			cc.call("set_zoom_limits", float(cc.get("min_zoom")), 40.0)
			cc.set("_target_zoom", 30.0)
			_look(gm, FIRE_AT)
		"ahome":
			cc.set("_target_zoom", float(cc.get("_home_zoom")))
			_look(gm, AUTHOR_AT)
		"az20":
			cc.set("_target_zoom", 20.0)
			_look(gm, AUTHOR_AT)
	return "view %s" % view


static func _look(gm: GameMap, at: Vector2) -> void:
	var off: Vector2 = gm.get_camera_controller().call("_get_view_center_ground_offset")
	var holder := gm.cameraholder_node
	holder.global_position = Vector3(at.x - off.x, holder.global_position.y, at.y - off.y)


static func _label(base: Node, text: String) -> String:
	var root := base.get_tree().root
	var old := root.get_node_or_null(LABEL)
	if text == "":
		if old != null:
			old.free()
		return "label removed"
	var layer := old as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = LABEL
		layer.layer = 120
		var panel := PanelContainer.new()
		panel.name = "Panel"
		panel.position = Vector2(28, 24)
		# Wide and opaque, so a replayed capture's own caption does not show past it.
		panel.custom_minimum_size = Vector2(LABEL_MIN_W, 0.0)
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.05, 0.07, 1.0)
		box.set_content_margin_all(14.0)
		box.set_corner_radius_all(8)
		panel.add_theme_stylebox_override("panel", box)
		var caption := Label.new()
		caption.name = "Text"
		caption.add_theme_font_size_override("font_size", 40)
		caption.add_theme_color_override("font_color", Color(1, 1, 1))
		panel.add_child(caption)
		layer.add_child(panel)
		root.add_child(layer)
	(layer.get_node("Panel/Text") as Label).text = text
	return "label %s" % text


## Shows the earlier capture at `path` over the whole window (under the label), so a capture
## step re-frames it with a new caption ("" removes it).
static func _replay(base: Node, path: String, text: String) -> String:
	var root := base.get_tree().root
	var old := root.get_node_or_null(REPLAY)
	if path == "":
		if old != null:
			old.free()
		return "replay removed"
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return "no capture at %s" % path
	var layer := old as CanvasLayer
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = REPLAY
		layer.layer = 110
		var frame := TextureRect.new()
		frame.name = "Frame"
		frame.set_anchors_preset(Control.PRESET_FULL_RECT)
		frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		frame.stretch_mode = TextureRect.STRETCH_SCALE
		layer.add_child(frame)
		root.add_child(layer)
	(layer.get_node("Frame") as TextureRect).texture = ImageTexture.create_from_image(image)
	return "replay %s; %s" % [path.get_file(), _label(base, text)]


static func _save(ctrl: AuthoringController, folder: String) -> String:
	if not folder.begins_with(PREFIX):
		return "refused: %s is not a %s level" % [folder, PREFIX]
	var path := LevelManager.folder_path(folder)
	_remove_tree(path)
	DirAccess.make_dir_recursive_absolute(path)
	var saved := ctrl.level.duplicate(true) as LevelData
	saved.level_name = folder
	saved.level_folder = folder
	ctrl.call("_sync_document")
	var ok := AuthoringController.write_level(saved, ctrl.document, null)
	return "saved %s: %s" % [folder, str(ok)]


static func _cleanup() -> String:
	var dir := DirAccess.open(LevelManager.levels_dir)
	if dir == null:
		return "no levels folder"
	var removed := PackedStringArray()
	for folder in dir.get_directories():
		if folder.begins_with(PREFIX):
			if not LevelManager.delete_level_folder(LevelManager.folder_path(folder)):
				_remove_tree(LevelManager.folder_path(folder))
			removed.append(folder)
	return "removed %s" % str(removed)


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)
	for sub in dir.get_directories():
		_remove_tree(path.path_join(sub))
	DirAccess.remove_absolute(path)
