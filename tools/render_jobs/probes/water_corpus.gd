extends RefCounted

## Render-job probe (`call` op) of the water corpus (tests/unit/water_corpus_cases.gd, docs/systems/
## water.md "The water corpus"): builds the corpus maps as test levels, frames each layout and
## writes what the frame detectors need beside each capture. step.action:
##   build {prefix, maps}   builds the named corpus maps (all when `maps` is absent), bakes each
##                          one's flow map and writes it as the level `<prefix><map>` (no map need
##                          be open: run it at the title).
##   view {name, kind}      the camera on layout `name`: "top" (pitch 88) or "obl" (pitch 45).
##   aux {name, kind, dir}  writes `<dir>/<name>_<t|o>_aux.png` and `_meta.json` for the view shown:
##                          the playing level's WaterField projected through the camera, one pixel
##                          per capture pixel. A 255 where the field holds water over 2 cm; R the
##                          flow direction on screen (1..255 over half a turn, 0 where no stroke
##                          flows: a pond); G the shore distance (0..2 m); B 100 pond, 200 river,
##                          230 a river's white water (a fall's face and foot, a riffle).
##   list {map}             the layout names of a map, for a job's `expand`.
## The detectors (tools/render_jobs/water_corpus_detect.gd) read a view's wet capture, its dry
## capture (water hidden: water_field.gd `water`) and this image.

const Corpus := preload("res://tests/unit/water_corpus_cases.gd")
const WATER := preload("res://tools/render_jobs/probes/water.gd")
const FIELD := preload("res://tools/render_jobs/probes/water_field.gd")
const TOP_PITCH := 88.0
const OBLIQUE_PITCH := 45.0
## The orbit zoom of both views: about 25 m by 14 m of map at 16:9, a whole layout cell.
const ZOOM := 14.0


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"build":
			return _build(step)
		"view":
			return _view(base, step)
		"aux":
			return _aux(base, step)
		"list":
			var names := PackedStringArray()
			for l: Dictionary in Corpus.map_named(String(step.get("map", ""))).get("layouts", []):
				names.append(l.name)
			return "layouts %s" % JSON.stringify(names)
	return "unknown action %s" % step.get("action", "")


static func _build(step: Dictionary) -> String:
	var prefix := String(step.get("prefix", ""))
	if not WATER.TEST_PREFIXES.has(prefix):
		return "not a test prefix: %s" % prefix
	var wanted: Array = step.get("maps", [])
	var out := PackedStringArray()
	for m in Corpus.maps():
		if not wanted.is_empty() and not wanted.has(m.name):
			continue
		var started := Time.get_ticks_msec()
		var doc: MapDocument = Corpus.build(m).doc
		# The flow map, as the Water tool bakes it (a level written without one is rebaked at
		# every load until it is saved again: WaterFlowBaker.refreshed).
		WaterFlowBaker.ensure(doc)
		var folder := prefix + String(m.name)
		DirAccess.make_dir_recursive_absolute(LevelManager.folder_path(folder))
		var level := AuthoringController.new_level()
		level.level_name = folder
		level.level_folder = folder
		var ok := AuthoringController.write_level(level, doc, null)
		out.append(
			(
				"%s %s digest %s bodies %d in %d ms"
				% [
					folder,
					"saved" if ok else "NOT saved",
					Corpus.digest(doc),
					doc.water_bodies.size(),
					Time.get_ticks_msec() - started
				]
			)
		)
	return "built: " + "; ".join(out)


static func _view(base: Node, step: Dictionary) -> String:
	var layout := Corpus.layout_named(String(step.get("name", "")))
	if layout.is_empty():
		return "no layout %s" % step.get("name", "")
	var gm := base.get("_game_map") as GameMap
	var cc := gm.get_camera_controller()
	var top := String(step.get("kind", "top")) == "top"
	cc.set_yaw_now(0.0)
	cc.set_pitch_now(TOP_PITCH if top else OBLIQUE_PITCH)
	(cc.view_mode() as OrbitView).target_zoom = float(step.get("zoom", ZOOM))
	var at: Vector2 = layout.at
	return "%s %s: %s" % [layout.name, step.get("kind", "top"), WATER.run(base, {"action": "look", "at": [at.x, at.y]})]


static func _aux(base: Node, step: Dictionary) -> String:
	var pw := FIELD.painter_water(base)
	var host: Variant = pw.call("field") if pw != null and pw.has_method("field") else null
	if host == null or host.field == null:
		return "no field"
	var f: WaterField = host.field
	var gm := base.get("_game_map") as GameMap
	var cam := gm.camera_node
	var scale := float(step.get("scale", 0.5))
	var view := Vector2(gm.world_viewport.size) * scale
	var img := Image.create(int(view.x), int(view.y), false, Image.FORMAT_RGBA8)
	var layout := Corpus.layout_named(String(step.get("name", "")))
	var at: Vector2 = layout.get("at", Vector2.ZERO)
	var centre := Vector3(at.x, 0.0, at.y)
	var px_per_m := cam.unproject_position(centre).distance_to(cam.unproject_position(centre + Vector3.RIGHT)) * scale
	var half := int(ceil(px_per_m * f.step.x * 0.5)) + 1
	var sx := f.size.x
	var no_u := WaterField.NO_FLOW_U * 0.5
	var no_foot: float = WaterFieldStroke.NO_FOOT * 0.5
	var wet := 0
	for z in f.size.y:
		for x in sx:
			var i := z * sx + x
			if f.depth[i] <= 0.02:
				continue
			var p := Vector3(f.origin.x + x * f.step.x, f.ew[i], f.origin.y + z * f.step.y)
			if cam.is_position_behind(p):
				continue
			var s := cam.unproject_position(p) * scale
			if s.x < -half or s.y < -half or s.x > view.x + half or s.y > view.y + half:
				continue
			var red := 0.0
			var blue := 100.0
			if f.flow_u[i] > no_u:
				blue = 200.0
				if f.foot[i] < no_foot or f.steep[i] > 0.1 or f.energy[i] > 0.3:
					blue = 230.0
				var g := Vector2.ZERO
				if x > 0 and x < sx - 1 and f.flow_u[i - 1] > no_u and f.flow_u[i + 1] > no_u:
					if f.owner[i - 1] == f.owner[i] and f.owner[i + 1] == f.owner[i]:
						g.x = f.flow_u[i + 1] - f.flow_u[i - 1]
				if z > 0 and z < f.size.y - 1 and f.flow_u[i - sx] > no_u and f.flow_u[i + sx] > no_u:
					if f.owner[i - sx] == f.owner[i] and f.owner[i + sx] == f.owner[i]:
						g.y = f.flow_u[i + sx] - f.flow_u[i - sx]
				if g.length() > 0.05 and g.length() < 4.0:
					g = g.normalized()
					var s2 := cam.unproject_position(p + Vector3(g.x, 0.0, g.y) * 0.5) * scale
					var ang := fposmod((s2 - s).angle(), PI)
					red = 1.0 + 254.0 * ang / PI
			var col := Color8(int(red), int(clampf(f.shore[i] / 2.0, 0.0, 1.0) * 255.0), int(blue), 255)
			img.fill_rect(Rect2i(int(s.x) - half, int(s.y) - half, 2 * half + 1, 2 * half + 1), col)
			wet += 1
	var dir := String(step.get("dir", "user://"))
	var stem := "%s_%s" % [step.get("name", "view"), "t" if String(step.get("kind", "top")) == "top" else "o"]
	img.save_png(dir.path_join(stem + "_aux.png"))
	var meta := {"px_per_m": px_per_m, "layout": layout.get("name", ""), "map": layout.get("map", ""), "kind": step.get("kind", "top")}
	var file := FileAccess.open(dir.path_join(stem + "_meta.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(meta))
	return "aux %s: %d wet samples, %.1f px/m" % [stem, wet, px_per_m]
