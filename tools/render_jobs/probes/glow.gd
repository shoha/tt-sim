extends RefCounted

## Render-job probe (`call` op) for the game's glow (EnvironmentGlow; jobs firefeat_glow and
## firefeat_look_mobile). Actions:
##   env {preset, overrides}  applies `preset` ("" the level's own) with `overrides` as the Sky and
##                     Color panes do, so a capture shows a level override (the Glow slider)
##   report            every WorldEnvironment's glow as Godot holds it, and the renderer
##   variant {variant, preset}  the glow alone switched in place on the live Environment, for an
##                     in-run A/B (job fire_c7b_glow): new (EnvironmentGlow, the game's own), old
##                     (main's glow before card C5b: the preset's intensity, strength and bloom over
##                     Godot's Environment defaults for the rest) or off; `preset` names the
##                     environment the shot key applied ("" the level's own, with its overrides),
##                     and a "#2" suffix on the variant is ignored (palindrome windows);
##                     "+key=value" suffixes then set single glow properties on top
##                     ("old+glow_bloom=0.2", "new+glow_strength=1",
##                     "new+levels=0:.8:.4:.1:0:0:0"), for a calibration
##   shot {value, specs}  fire.gd's shot for "<sky>_<view>" of a value "<sky>_<view>_<name>", then
##                     the variant specs[name] for that sky's preset, so an expand's capture
##                     names stay file names (a calibration A/B on one frame)
##   stats {dir, pairs, out, width}  for each [a, b] of `pairs` (capture names in `dir`, or
##                     absolute paths; `<name>.png`), the mean luma, mean saturation, contrast
##                     (the luma's standard deviation) and the luma's 50th and 98th percentiles
##                     of a and b, both taken down to the smaller size (and to `width` when
##                     given), and b - a;
##                     writes the table to <dir>/<out>.txt (default stats) and returns the deltas
##   cleanup {folder}  deletes that one FOLDERS test level (fire.gd's cleanup deletes every
##                     _firefeat_ level, _firefeat_look included)

const FireProbe := preload("res://tools/render_jobs/probes/fire.gd")
## The test levels this probe may delete.
const FOLDERS: Array[String] = ["_firefeat_glow"]
## Rec. 709 luma weights, applied to the PNG's (sRGB) values.
const LUMA := Vector3(0.2126, 0.7152, 0.0722)
const KEYS: Array[String] = [
	"glow_enabled",
	"glow_intensity",
	"glow_strength",
	"glow_bloom",
	"glow_hdr_threshold",
	"glow_hdr_scale",
	"glow_blend_mode",
]


static func run(base: Node, step: Dictionary) -> String:
	match String(step.get("action", "")):
		"report":
			return _report(base)
		"cleanup":
			return _cleanup(String(step.get("folder", "")))
		"variant":
			var variant := String(step.get("variant", "new")).get_slice("#", 0)
			return _variant(base, variant, String(step.get("preset", "")))
		"shot":
			return _named_shot(base, String(step.get("value", "")), step.get("specs", {}))
		"stats":
			return _stats(step)
		"env":
			var ctrl: AuthoringController = base.get("_authoring_controller")
			if ctrl == null:
				return "no authoring controller"
			var manager: LevelEnvironmentManager = ctrl.get("_environment")
			if manager == null:
				return "no environment manager"
			var preset := String(step.get("preset", ""))
			var overrides: Dictionary = step.get("overrides", {})
			if preset == "":
				preset = ctrl.level.environment_preset
				var merged: Dictionary = ctrl.level.environment_overrides.duplicate()
				merged.merge(overrides, true)
				overrides = merged
			manager.apply_environment_settings(preset, overrides)
			return "env %s %s; %s" % [preset, str(overrides), _report(base)]
	return "unknown action"


static func _report(base: Node) -> String:
	var lines := PackedStringArray(["renderer %s" % RenderingServer.get_current_rendering_method()])
	for node in base.get_tree().root.find_children("*", "WorldEnvironment", true, false):
		var env := (node as WorldEnvironment).environment
		if env == null:
			continue
		var line := PackedStringArray()
		for key: String in KEYS:
			line.append("%s %s" % [key.trim_prefix("glow_"), str(env.get(key))])
		var levels := PackedStringArray()
		for k in 7:
			levels.append("%.2f" % env.get_glow_level(k))
		line.append("levels [%s]" % ", ".join(levels))
		lines.append("%s: %s" % [node.name, ", ".join(line)])
	return "; ".join(lines)


## Sets glow variant `variant` (new, old, off) on the live Environment without re-applying the
## preset, so the sky, the sun and everything else stay as the shot left them. The config is the
## one the Sky pane resolves for `preset` ("" the level's own preset and overrides). "+key=value"
## suffixes on `spec` set single glow properties after the variant.
static func _variant(base: Node, spec: String, preset: String) -> String:
	var parts := spec.split("+")
	var variant := parts[0]
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null:
		return "no authoring controller"
	var manager: LevelEnvironmentManager = ctrl.get("_environment")
	if manager == null:
		return "no environment manager"
	var world_env := manager.get("_world_environment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return "no environment"
	var overrides: Dictionary = {}
	if preset == "":
		preset = ctrl.level.environment_preset
		overrides = ctrl.level.environment_overrides
	var raw: Variant = manager.get("_map_environment_config")
	var map_defaults: Dictionary = raw if raw is Dictionary else {}
	var config := EnvironmentPresets.get_environment_config(preset, overrides, map_defaults)
	var env := world_env.environment
	match variant:
		"new":
			var glow_ref := EnvironmentPresets.glow_reference(preset, map_defaults)
			EnvironmentGlow.apply(env, config, glow_ref)
		"old":
			# What _apply_config_to_environment set before card C5b; the rest Godot's defaults.
			var defaults := Environment.new()
			env.glow_enabled = bool(config.get("glow_enabled", false))
			env.glow_intensity = float(config.get("glow_intensity", 0.8))
			env.glow_strength = float(config.get("glow_strength", 1.0))
			env.glow_bloom = float(config.get("glow_bloom", 0.0))
			env.glow_hdr_threshold = defaults.glow_hdr_threshold
			env.glow_hdr_scale = defaults.glow_hdr_scale
			env.glow_blend_mode = defaults.glow_blend_mode
			for k in 7:
				env.set_glow_level(k, defaults.get_glow_level(k))
		"off":
			env.glow_enabled = false
		_:
			return "unknown variant %s" % variant
	var unknown := _set_keys(env, parts.slice(1))
	if unknown != "":
		return "unknown glow key %s" % unknown
	return "glow %s (%s); %s" % [spec, preset, _report(base)]


## Sets each "key=value" of `pairs` on `env` (a glow property, or "levels" as seven values joined
## by ":"); returns the first key it does not know, or "".
static func _set_keys(env: Environment, pairs: PackedStringArray) -> String:
	for pair in pairs:
		var key := pair.get_slice("=", 0)
		var value := pair.get_slice("=", 1)
		if key == "levels":
			var levels := value.split(":")
			for level in mini(levels.size(), 7):
				env.set_glow_level(level, float(levels[level]))
		elif key == "glow_blend_mode":
			env.glow_blend_mode = int(value) as Environment.GlowBlendMode
		elif key == "glow_enabled":
			env.glow_enabled = int(value) != 0
		elif key in KEYS:
			env.set(key, float(value))
		else:
			return key
	return ""


## fire.gd's shot for the "<sky>_<view>" of `value` ("<sky>_<view>_<name>"), then the glow variant
## `specs`[name] ("new" when missing) for that sky's preset.
static func _named_shot(base: Node, value: String, specs: Dictionary) -> String:
	var parts := value.split("_")
	if parts.size() < 3:
		return "bad value %s" % value
	var key := "%s_%s" % [parts[0], parts[1]]
	var name := "_".join(parts.slice(2))
	var shot: String = FireProbe.run(base, {"action": "shot", "key": key, "label": ""})
	var sky: Array = FireProbe.SKIES.get(parts[0], [-1.0, ""])
	var spec := String(specs.get(name, "new"))
	return "%s; %s" % [shot, _variant(base, spec, String(sky[1]))]


## The stats action (see the header): one row per pair, written to <dir>/<out>.txt.
static func _stats(step: Dictionary) -> String:
	var dir := String(step.get("dir", "user://render_jobs/firefeat_glow"))
	var width := int(step.get("width", 0))
	var rows := PackedStringArray(
		["a | b | a: luma sat con p50 p98 | b: luma sat con p50 p98 | b - a: luma sat con p50 p98"]
	)
	var deltas := PackedStringArray()
	for pair: Array in step.get("pairs", []):
		var images: Array[Image] = []
		for name: String in [String(pair[0]), String(pair[1])]:
			var path := (name if name.is_absolute_path() else dir.path_join(name)) + ".png"
			var image := Image.load_from_file(ProjectSettings.globalize_path(path))
			if image == null or image.is_empty():
				return "no image at %s" % path
			image.convert(Image.FORMAT_RGB8)
			images.append(image)
		var size := images[0].get_size().min(images[1].get_size())
		if width > 0 and width < size.x:
			size = Vector2i(width, roundi(float(width) * size.y / size.x))
		var a := _image_stats(images[0], size)
		var b := _image_stats(images[1], size)
		var d := PackedFloat64Array()
		for k in a.size():
			d.append(b[k] - a[k])
		rows.append(
			"%s | %s | %s | %s | %s" % [pair[0], pair[1], _row(a, false), _row(b, false), _row(d, true)]
		)
		deltas.append("%s %s" % [String(pair[1]).get_file(), _row(d, true)])
	var out := dir.path_join(String(step.get("out", "stats")) + ".txt")
	var file := FileAccess.open(out, FileAccess.WRITE)
	if file == null:
		return "cannot write %s" % out
	file.store_string("\n".join(rows) + "\n")
	file.close()
	return "stats %s (b - a: luma sat con p50 p98): %s" % [out, "; ".join(deltas)]


## Mean luma, mean saturation (HSV), contrast (the luma's standard deviation) and the luma's 50th
## and 98th percentiles of `image` taken to `size`, on the 0..1 scale of the PNG's values.
static func _image_stats(source: Image, size: Vector2i) -> PackedFloat64Array:
	var image := source
	if image.get_size() != size:
		image = source.duplicate() as Image
		image.resize(size.x, size.y, Image.INTERPOLATE_TRILINEAR)
	var bytes := image.get_data()
	var count := bytes.size() / 3
	var histogram := PackedInt32Array()
	histogram.resize(256)
	var sum := 0.0
	var sum_sq := 0.0
	var saturation := 0.0
	for k in range(0, bytes.size(), 3):
		var r := bytes[k]
		var g := bytes[k + 1]
		var b := bytes[k + 2]
		var luma := LUMA.x * r + LUMA.y * g + LUMA.z * b
		sum += luma
		sum_sq += luma * luma
		var most := maxi(r, maxi(g, b))
		if most > 0:
			saturation += float(most - mini(r, mini(g, b))) / most
		histogram[mini(int(luma), 255)] += 1
	var mean := sum / count
	var spread := sqrt(maxf(sum_sq / count - mean * mean, 0.0))
	return PackedFloat64Array(
		[
			mean / 255.0,
			saturation / count,
			spread / 255.0,
			_percentile(histogram, count, 0.5),
			_percentile(histogram, count, 0.98)
		]
	)


## The luma below which `share` of the `count` pixels in `histogram` fall, 0..1.
static func _percentile(histogram: PackedInt32Array, count: int, share: float) -> float:
	var seen := 0
	for k in histogram.size():
		seen += histogram[k]
		if seen >= share * count:
			return k / 255.0
	return 1.0


static func _row(values: PackedFloat64Array, signed: bool) -> String:
	var cells := PackedStringArray()
	for value in values:
		cells.append(("%+.4f" if signed else "%.4f") % value)
	return " ".join(cells)


static func _cleanup(folder: String) -> String:
	if not folder in FOLDERS:
		return "refused: %s is not one of %s" % [folder, str(FOLDERS)]
	var path := LevelManager.folder_path(folder)
	if not DirAccess.dir_exists_absolute(path):
		return "no %s" % folder
	return "removed %s: %s" % [folder, str(LevelManager.delete_level_folder(path))]
