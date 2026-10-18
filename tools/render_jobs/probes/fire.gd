extends RefCounted

## Render-job probe (`call` op) for persistent ground fire's look (FireField, FireLook; the fire
## cards' jobs firefeat_build, firefeat_look and firefeat_cleanup). Actions:
##   info              flames shown and planned (the cap), burning blocks, entries by band, the
##                     fire book's state; the lights (place, energy, the sun's gate) and the
##                     smoke's sites
##   extras {show, what}  shows or hides the fire's lights and smoke (FireLights,
##                     FireFieldSmoke; `what` "lights", "smoke" or "both"), so a capture can
##                     show the field as round 4 drew it
##   lights {energy, range, rise, decay, toward}  re-tunes the lights in place (harness only;
##                     `toward` moves each that many metres toward the camera, level)
##   shot {key}        "<day|dusk|sunset|night|dark>_<view>": the sky (SKIES: the sun at 14:00,
##                     DUSK_HOUR or NIGHT_HOUR through the level's sun as the Sun pane's time of
##                     day does, and the level's environment or the game's outdoor_sunset or
##                     outdoor_night preset as the Sky pane applies it; dark is the level's night
##                     with the scene's ambient and sky energy cut to DARK, the harness's own
##                     diagnostic for the lights), the view (home; z8,
##                     zoom 8 over a point on the blaze; z20, zoom 20 over the fire's middle; z30,
##                     zoom 30 there; zs, zoom 12 framing the largest smoke
##                     column) and an on-screen label, `label` (default
##                     "NEW") before the key's words
##   label {text}      an on-screen caption for captures ("" removes it)
##   replay {path, text}  an earlier capture over the whole window under the caption `text`, so
##                     a capture re-labels it for a sheet (an empty path removes it)
##   flames {show}     shows or hides the flames (not the lights or smoke), to judge the
##                     ground's glow or the lights alone
##   param {target, name, value}  sets a shader parameter on the "ground" (the map's ground
##                     material), the "flames" (FireLook's material) or the "smoke"
##                     (FireFieldSmoke's), for look comparisons
##   shadows {on}      turns every directional light's shadow on or off
##   time              the engine clock and frames drawn, to measure a motion strip's spacing
##   burst {dir, name, count, every}  grabs `count` frames of the window `every` seconds apart
##                     and saves them as <name>_<k>.png with their engine times in
##                     <name>_times.txt (a capture step takes about 0.4 s, too slow for a strip
##                     of held drawings); wait about count x 0.25 s after it
##   scale {value}     Engine.time_scale (the shaders' clock and the burst's spacing follow it):
##                     0.25 with a burst every 1/24 s grabs a motion strip at the drawings' own
##                     rate; 1 puts the clock back
##   grab {tag, freeze}  keeps the raw 3D frame under `tag` for diff; `freeze` true holds the
##                     fire's lights at their gated energy with no flicker (false lets them go)
##   diff {a, b, out, gain, near, rings, points}  compares grabs `a` (lights off) and `b` (on):
##                     saves (b - a) x gain as <out>.png and writes <out>.txt with both colours
##                     at level ground `rings` metres from the light nearest `near` (eight ways
##                     each, with the light's attenuation, cosine and reach there) and at the
##                     labelled screen points `points` ([name, x, y] in shares of the frame)
##   profile {points, every, across, radius}  the fire mask along `points` ([x, z] world)
##                     smoothed as a line's release smooths it, every `every` metres: lowest,
##                     highest, and each stretch under FireField.FLAME_MIN; and across the line
##                     at every `across` metres, the offset each side where it falls under
##                     FLAME_MIN, against FireBrush.line_reach for a Blaze line of `radius`
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
const NIGHT_HOUR := 23.0
## A shot key's sky: the hour (-1: the default time of day) and the environment preset ("": the
## level's own). Sunset and night are the game's own dark presets with a low and a set sun (the
## look is judged there); dusk is the level's own sky at the dusk hour, dark the harness's; hell
## and ethereal are those presets at the default hour (the glow card's no-fire set).
const SKIES := {
	"day": [-1.0, ""],
	"hell": [-1.0, "hell"],
	"ethereal": [-1.0, "ethereal"],
	"dusk": [DUSK_HOUR, ""],
	"sunset": [DUSK_HOUR, "outdoor_sunset"],
	"night": [NIGHT_HOUR, "outdoor_night"],
	"dark": [NIGHT_HOUR, ""],
}
## The smoke view (zs) centres this share of the largest column's height above where its
## billows are born.
const SMOKE_VIEW_RISE := 0.35
const VIEWS := {
	"zs": "zoom 12 on the smoke",
	"home": "home",
	"z8": "zoom 8",
	"z20": "zoom 20",
	"z30": "zoom 30",
	"ahome": "author fire, home zoom",
	"az20": "author fire, zoom 20",
}

## The dark key's share of the sky's energy, and its flat ambient (a moonlit blue, dim).
const DARK := 0.1
const DARK_AMBIENT := Color(0.05, 0.06, 0.1)

static var _sun_key := ""
static var _view_key := ""
## While the dark key holds: Environment -> its saved properties, DirectionalLight3D -> visible.
static var _env_saved := {}
## The grab action's frames by tag.
static var _grabs := {}


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
	if action == "scale":
		Engine.time_scale = float(step.get("value", 1.0))
		return "time scale %.3f" % Engine.time_scale
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
		"profile":
			return _profile(ctrl.editor, step)
		"shot":
			var gm: GameMap = base.get("_game_map")
			var label := String(step.get("label", "NEW"))
			return _shot(base, ctrl, gm, String(step.get("key", "")), label)
		"save":
			return _save(ctrl, String(step.get("folder", PREFIX + "look")))
		"flames":
			var show := bool(step.get("show", true))
			for chunk in ctrl.editor.fire_field.get_children():
				if not (chunk is FireLights or chunk is FireFieldSmoke or chunk is FireNoiseBake):
					(chunk as Node3D).visible = show
			return "flames %s" % ("shown" if show else "hidden")
		"extras":
			var field: FireField = ctrl.editor.fire_field
			if field == null or field.lights() == null:
				return "no lights or smoke"
			var on := bool(step.get("show", true))
			var what := String(step.get("what", "both"))
			if what != "smoke":
				field.lights().visible = on
			if what != "lights":
				field.smoke().visible = on
			return "%s %s" % [what, "shown" if on else "hidden"]
		"lights":
			return _tune_lights(ctrl.editor.fire_field, step)
		"param":
			return _param(ctrl.editor.fire_field, step)
		"grab":
			return _grab(base, ctrl.editor.fire_field, step)
		"diff":
			return _diff(base, ctrl, step)
	return "unknown action %s" % action


static func _profile(editor: AuthoringEditor, step: Dictionary) -> String:
	var doc := editor.document
	if doc.fire_mask.size() != doc.sample_count():
		return "no fire mask"
	var raw := PackedVector2Array()
	for p: Array in step.get("points", []):
		raw.append(Vector2(float(p[0]), float(p[1])))
	var path := StrokePath.smooth_line(raw)
	var every := float(step.get("every", 0.5))
	var across := float(step.get("across", 4.0))
	var low := 255
	var high := 0
	var dips := PackedStringArray()
	var reaches := PackedStringArray()
	var mean_reach := 0.0
	var count := 0
	var walked := 0.0
	var next_across := across * 0.5
	for i in path.size() - 1:
		var length := path[i].distance_to(path[i + 1])
		var tangent := (path[i + 1] - path[i]) / maxf(length, 0.0001)
		var s := 0.0
		while s < length:
			var at := path[i] + tangent * s
			var v := _mask_at(editor, at)
			low = mini(low, v)
			high = maxi(high, v)
			if v < FireField.FLAME_MIN:
				dips.append("%.1f m (%.1f, %.1f) %d" % [walked + s, at.x, at.y, v])
			if walked + s >= next_across:
				var normal := Vector2(-tangent.y, tangent.x)
				var sides := Vector2(_reach_side(editor, at, normal), _reach_side(editor, at, -normal))
				reaches.append("%.1f m: %.1f / %.1f" % [walked + s, sides.x, sides.y])
				mean_reach += sides.x + sides.y
				count += 2
				next_across += across
			s += every
		walked += length
	var radius := float(step.get("radius", 0.0))
	var flow := float(step.get("flow", 1.0))
	var predicted := radius * FireBrush.line_reach(FireBrush.BLAZE, flow, false)
	var summary := (
		"mean reach %.2f m, line_reach %.2f m; centre over %.1f m: low %d high %d"
		% [mean_reach / maxf(float(count), 1.0), predicted, walked, low, high]
	)
	var under := ", ".join(dips) if not dips.is_empty() else "none"
	return (
		"%s; under %d: %s | across (m): %s"
		% [summary, FireField.FLAME_MIN, under, "; ".join(reaches)]
	)


## The fire mask byte at world XZ `xz` (the nearest sample).
static func _mask_at(editor: AuthoringEditor, xz: Vector2) -> int:
	var doc := editor.document
	var s := Vector2i(doc.world_to_sample(editor.to_map_xz(Vector3(xz.x, 0, xz.y))).round())
	if s.x < 0 or s.y < 0 or s.x >= doc.samples_x() or s.y >= doc.samples_z():
		return 0
	return doc.fire_mask[doc.sample_index(s.x, s.y)]


## How far from `at` along `normal` the mask stays at or over FireField.FLAME_MIN (0.1 m steps).
static func _reach_side(editor: AuthoringEditor, at: Vector2, normal: Vector2) -> float:
	var d := 0.0
	while d < 12.0 and _mask_at(editor, at + normal * (d + 0.1)) >= FireField.FLAME_MIN:
		d += 0.1
	return d


static func _grab(base: Node, field: FireField, step: Dictionary) -> String:
	var lights := field.lights() if field != null else null
	if step.has("freeze") and lights != null:
		var hold := bool(step["freeze"])
		lights.process_mode = Node.PROCESS_MODE_DISABLED if hold else Node.PROCESS_MODE_INHERIT
		if hold:
			var energies: PackedFloat32Array = lights.get("_energy")
			var gate := FireLook.light_gate(FoliageLight.last_sun)
			for slot in lights.lights().size():
				lights.lights()[slot].light_energy = energies[slot] * gate
	var gm: GameMap = base.get("_game_map")
	var tag := String(step.get("tag", "off"))
	_grabs[tag] = gm.camera_node.get_viewport().get_texture().get_image()
	return "grabbed %s" % tag


## Compares two grabs (see the header's diff).
static func _diff(base: Node, ctrl: AuthoringController, step: Dictionary) -> String:
	var off: Image = _grabs.get(String(step.get("a", "off")))
	var on: Image = _grabs.get(String(step.get("b", "on")))
	if off == null or on == null:
		return "no grabs"
	var size := Vector2i(960, 540)
	var scale := Vector2(size) / Vector2(off.get_size())
	off = off.duplicate() as Image
	on = on.duplicate() as Image
	for image: Image in [off, on]:
		image.convert(Image.FORMAT_RGB8)
		image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	var gain := float(step.get("gain", 4.0))
	var bytes_off := off.get_data()
	var bytes_on := on.get_data()
	var bytes := PackedByteArray()
	bytes.resize(bytes_off.size())
	for k in bytes.size():
		bytes[k] = clampi(roundi((bytes_on[k] - bytes_off[k]) * gain), 0, 255)
	var out := String(step.get("out", "user://render_jobs/lights_diff"))
	Image.create_from_data(size.x, size.y, false, Image.FORMAT_RGB8, bytes).save_png(out + ".png")
	var lines := PackedStringArray()
	var gm: GameMap = base.get("_game_map")
	var light := _nearest_light(ctrl.editor.fire_field, step.get("near", [0.0, 0.0]))
	if light != null:
		var p := light.global_position
		lines.append(
			(
				"light at (%.1f, %.1f, %.1f) energy %.2f range %.1f decay %.2f"
				% [p.x, p.y, p.z, light.light_energy, light.omni_range, light.omni_attenuation]
			)
		)
		for ring: float in step.get("rings", [2.0, 4.0, 8.0]):
			for k in 8:
				var angle := k * TAU / 8.0
				var g := Vector3(p.x + ring * cos(angle), 0.0, p.z + ring * sin(angle))
				g.y = ctrl.editor.ground_height_at(g)
				var at := _on_screen(gm.camera_node, g, scale, size)
				if at.x < 0:
					continue
				var dist := p.distance_to(g)
				var fall := pow(maxf(1.0 - pow(dist / light.omni_range, 4.0), 0.0), 2.0)
				var att := fall * pow(maxf(dist, 1e-4), -light.omni_attenuation)
				var cosine := (p.y - g.y) / dist
				lines.append(
					(
						"ground %4.1f m %3d deg px (%d, %d) off %s on %s att %.3f cos %.2f reach %.2f"
						% [
							ring,
							k * 45,
							at.x,
							at.y,
							_box_text(off, at),
							_box_text(on, at),
							att,
							cosine,
							light.light_energy * att * cosine
						]
					)
				)
	for point: Array in step.get("points", []):
		var at := Vector2i(int(float(point[1]) * size.x), int(float(point[2]) * size.y))
		lines.append(
			(
				"point %s px (%d, %d) off %s on %s"
				% [point[0], at.x, at.y, _box_text(off, at), _box_text(on, at)]
			)
		)
	var file := FileAccess.open(out + ".txt", FileAccess.WRITE)
	file.store_string("\n".join(lines) + "\n")
	file.close()
	return "diff written %s (%d lines)" % [out, lines.size()]


static func _nearest_light(field: FireField, near: Array) -> OmniLight3D:
	if field == null or field.lights() == null:
		return null
	var best: OmniLight3D = null
	var best_d := INF
	var spot := Vector2(float(near[0]), float(near[1]))
	for light in field.lights().lights():
		var d := Vector2(light.global_position.x, light.global_position.z).distance_to(spot)
		if d < best_d and light.light_energy > 0.0:
			best = light
			best_d = d
	return best


## Where world point `g` falls in the scaled frame (-1, -1 when off it or behind the camera).
static func _on_screen(camera: Camera3D, g: Vector3, scale: Vector2, size: Vector2i) -> Vector2i:
	if camera.is_position_behind(g):
		return Vector2i(-1, -1)
	var s := camera.unproject_position(g) * scale
	if s.x < 3.0 or s.y < 3.0 or s.x > size.x - 4.0 or s.y > size.y - 4.0:
		return Vector2i(-1, -1)
	return Vector2i(int(s.x), int(s.y))


## The mean colour (0-255) of the 5 x 5 box at `at`, as text.
static func _box_text(image: Image, at: Vector2i) -> String:
	var sum := Color(0, 0, 0)
	var n := 0
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := clampi(at.x + dx, 0, image.get_width() - 1)
			var y := clampi(at.y + dy, 0, image.get_height() - 1)
			sum += image.get_pixel(x, y)
			n += 1
	return "(%d, %d, %d)" % [roundi(sum.r / n * 255), roundi(sum.g / n * 255), roundi(sum.b / n * 255)]


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


## Re-tunes the fire's lights in place for a look comparison (the harness only): each light in
## use stands `rise` metres over its cluster's centroid (where FireLights stood it, without one)
## with `energy` (before the gate and the flicker), `range` and the falloff `decay`
## (OmniLight3D.omni_attenuation).
static func _tune_lights(field: FireField, step: Dictionary) -> String:
	if field == null or field.lights() == null:
		return "no lights"
	var lights := field.lights()
	var clusters := FireClusters.lights(FireClusters.merge(field.get("_cells")))
	var slots: Array[Vector2i] = lights.get("_cells")
	var energies: PackedFloat32Array = lights.get("_energy")
	var forward := FireLook.DEFAULT_FORWARD
	var toward := -Vector3(forward.x, 0.0, forward.z).normalized() * float(step.get("toward", 0.0))
	for slot in slots.size():
		for cluster in clusters:
			if cluster["cell"] != slots[slot]:
				continue
			var light: OmniLight3D = lights.lights()[slot]
			var at: Vector3 = cluster["at"]
			if step.has("rise"):
				# Without a rise the light keeps the stand FireLights gave it.
				light.position = at + Vector3(0.0, float(step["rise"]), 0.0) + toward
			light.omni_range = float(step.get("range", FireLights.RANGE_M))
			light.omni_attenuation = float(step.get("decay", FireLights.DECAY))
			energies[slot] = float(step.get("energy", FireLook.LIGHT_ENERGY))
	lights.set("_energy", energies)
	return "lights tuned %s" % str(step)


static func _param(field: FireField, step: Dictionary) -> String:
	var target := String(step.get("target", "flames"))
	var key := String(step.get("name", ""))
	var material: ShaderMaterial = FireLook.material()
	if target == "smoke":
		material = FireFieldSmoke.material()
	elif target == "ground":
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
	var out := (
		"fire shown %d of planned %d (cap %d); blocks with flames %d; sparks %d flames %d blaze %d"
		% [field.flame_count(), planned, FireField.MAX_FLAMES, burning, bands[1], bands[2], bands[3]]
	)
	out += "; book %s" % String(FireLook.Book.keys()[FireLook.book_state()]).to_lower()
	var bake := field.get_node_or_null(FireNoiseBake.NODE_NAME) as FireNoiseBake
	if bake != null:
		out += "; ground bake %d bytes over %s m" % [bake.memory_bytes(), str(bake.sim_rect())]
	if field.lights() == null:
		return out + "; no lights or smoke"
	var gate := FireLook.light_gate(FoliageLight.last_sun)
	var lit := PackedStringArray()
	for light in field.lights().lights():
		lit.append(
			"(%.1f, %.1f, %.1f) e %.2f %s"
			% [
				light.position.x,
				light.position.y,
				light.position.z,
				light.light_energy,
				"on" if light.visible else "off"
			]
		)
	var cells := FireClusters.merge(field.get("_cells"))
	return (
		out
		+ (
			"; gate %.2f (sun weight %.3f); lights %d: %s; smoke sites %d, billows %d: %s"
			+ "; largest clusters: %s; largest blaze clusters: %s"
		)
		% [
			gate,
			FoliageLight.last_sun.w,
			field.lights().count(),
			", ".join(lit),
			field.smoke().site_count(),
			field.smoke().live_count(),
			_clusters_text(field.smoke().sites()),
			_clusters_text(FireClusters.find(cells, false).slice(0, 6)),
			_clusters_text(FireClusters.find(cells, true).slice(0, 6))
		]
	)


static func _clusters_text(clusters: Array) -> String:
	var parts := PackedStringArray()
	for cluster: Dictionary in clusters:
		var at: Vector3 = cluster["at"]
		parts.append(
			"(%.1f, %.1f) size %.0f top %.1f" % [at.x, at.z, cluster["size"], cluster["top"]]
		)
	return ", ".join(parts)


static func _shot(
	base: Node, ctrl: AuthoringController, gm: GameMap, key: String, label: String
) -> String:
	var parts := key.split("_")
	if parts.size() != 2 or not VIEWS.has(parts[1]):
		return "bad key %s" % key
	var out := PackedStringArray()
	if parts[0] != _sun_key:
		if not SKIES.has(parts[0]):
			return "bad key %s" % key
		var sky: Array = SKIES[parts[0]]
		out.append(_dark(base, false))
		out.append(_environment(ctrl, String(sky[1])))
		out.append(_sun(ctrl, DefaultSun.DEFAULT_TIME_OF_DAY if sky[0] < 0.0 else float(sky[0])))
		if parts[0] == "dark":
			out.append(_dark(base, true))
		_sun_key = parts[0]
	if parts[1] != _view_key:
		out.append(_view(gm, parts[1], ctrl.editor.fire_field))
		_view_key = parts[1]
	out.append(_label(base, "%s   |   %s, %s" % [label, parts[0], VIEWS[parts[1]]]))
	return "; ".join(out)


## Applies environment preset `preset` as the Sky pane does, or the level's own ("").
static func _environment(ctrl: AuthoringController, preset: String) -> String:
	var manager: LevelEnvironmentManager = ctrl.get("_environment")
	if manager == null:
		return "no environment manager"
	if preset == "":
		manager.apply_environment_settings(
			ctrl.level.environment_preset, ctrl.level.environment_overrides
		)
		return "the level's environment (%s)" % ctrl.level.environment_preset
	manager.apply_environment_settings(preset, {})
	return "preset %s" % preset


static func _sun(ctrl: AuthoringController, hour: float) -> String:
	var manager: LevelEnvironmentManager = ctrl.get("_environment")
	if manager == null:
		return "no environment manager"
	var settings := DefaultSun.settings_for_time(hour)
	manager.apply_sun_settings(settings)
	var elevation := settings.elevation_degrees
	return "sun %.1f h: energy %.2f elevation %.1f" % [hour, settings.energy, elevation]


## The harness's dark night (the "dark" sun key; never the game's own): every WorldEnvironment's
## ambient made a flat DARK_AMBIENT colour (a sky ambient ignores the ambient energy), its sky
## reflections off and its sky energy cut to DARK, so the fire's lights can be judged against a
## genuinely dark scene; `on` false puts them back.
static func _dark(base: Node, on: bool) -> String:
	var keys := [
		"ambient_light_source",
		"ambient_light_color",
		"ambient_light_energy",
		"reflected_light_source",
		"background_energy_multiplier"
	]
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env: Environment = (node as WorldEnvironment).environment
		if env == null:
			continue
		if on and not _env_saved.has(env):
			var saved := {}
			for key: String in keys:
				saved[key] = env.get(key)
			_env_saved[env] = saved
			env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
			env.ambient_light_color = DARK_AMBIENT
			env.ambient_light_energy = 1.0
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			env.background_energy_multiplier *= DARK
		elif not on and _env_saved.has(env):
			for key: String in keys:
				env.set(key, _env_saved[env][key])
			_env_saved.erase(env)
	# The sun off too (it stands below the horizon at NIGHT_HOUR, but the scene stayed lit).
	for light in base.get_tree().root.find_children("*", "DirectionalLight3D", true, false):
		if on and not _env_saved.has(light):
			_env_saved[light] = (light as DirectionalLight3D).visible
			(light as DirectionalLight3D).visible = false
		elif not on and _env_saved.has(light):
			(light as DirectionalLight3D).visible = _env_saved[light]
			_env_saved.erase(light)
	return "dark %s" % ("on" if on else "off")


static func _view(gm: GameMap, view: String, field: FireField = null) -> String:
	var cc := gm.get_camera_controller()
	match view:
		"zs":
			cc.set("_target_zoom", 12.0)
			_look(gm, _smoke_spot(field))
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


## The ground point that frames the largest smoke column in the middle of the screen
## (SMOKE_VIEW_RISE of its height above where its billows are born, carried down the camera's
## fixed forward axis to the ground), or FIRE_AT without smoke.
static func _smoke_spot(field: FireField) -> Vector2:
	if field == null or field.smoke() == null or field.smoke().site_count() == 0:
		return FIRE_AT
	var site: Dictionary = field.smoke().sites()[0]
	var born := FireFieldSmoke.source(site)
	var forward := FireLook.DEFAULT_FORWARD.normalized()
	var rise := FireFieldSmoke.column_extent(site).x * SMOKE_VIEW_RISE
	var target := born + Vector3(0.0, rise, 0.0)
	var ground := target + forward * ((float(site["at"].y) - target.y) / forward.y)
	return Vector2(ground.x, ground.z)


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
