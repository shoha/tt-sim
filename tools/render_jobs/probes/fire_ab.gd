extends RefCounted

## Render-job probe (`call` op) for same-run A/B of the persistent fire's shaders (card F4b-3;
## jobs fire_ab_cost and fire_ab_look): the ground's fire term, the flames and the smoke are
## swapped in place for variants, timed with perf.gd in one run, and compared pixel for pixel
## under a held clock. Actions:
##   patch {file, variant}  puts variant `variant` of the JSON file `file` in place: an object of
##                     parts ("glow", the ground's fire_glow.gdshaderinc inlined into the ground
##                     shader; "flames"; "smoke"), each {"source": a path whose text replaces the
##                     part's own file, "edits": [[find, replace], ...] applied to that text};
##                     the parts a variant leaves out, and the variant "none", get their own
##                     code back. A variant's "config" (fire_perf.gd's: "off", "no_glow", ...)
##                     is applied with it, "on" otherwise; a "#n" suffix is ignored, so an
##                     expand can repeat a variant
##   hold {on}         Engine.time_scale 0 (the shaders' TIME, the lights' flicker and the
##                     camera stop; the driver's waits count real time meanwhile) or back to 1
##   grab {tag}        keeps the raw 3D frame under `tag`
##   load {tag, path}  keeps the PNG at `path` (an earlier capture, a reference frame) under
##                     `tag` for pdiff, which takes the larger of two frames down to the smaller
##   pdiff {a, b, out, gain}  compares grabs `a` and `b`: the mean, RMS and largest difference
##                     (0..255, Image.compute_image_metrics) and the share of pixels any channel
##                     of which differs by more than 8 and 24; saves a row for a sheet at
##                     <out>.png: a | b | |b - a| x gain (default 4), 640x360 each
##   sheet {out}       stacks the rows of every pdiff since the last sheet into <out>.png

const PerfProbe := preload("res://tools/render_jobs/probes/fire_perf.gd")
const GROUND_INC := "res://shaders/authored_ground.gdshaderinc"
const GLOW_INC := "res://shaders/fire_glow.gdshaderinc"
const FILES := {
	"flames": "res://shaders/fire_flames.gdshader",
	"smoke": "res://shaders/fire_field_smoke.gdshader",
}
const ROW_TILE := Vector2i(640, 360)

## part -> its shader's own code, kept by the first patch.
static var _codes := {}
static var _grabs := {}
static var _rows: Array[Image] = []


static func run(base: Node, step: Dictionary) -> String:
	var action := String(step.get("action", ""))
	match action:
		"hold":
			Engine.time_scale = 0.0 if bool(step.get("on", true)) else 1.0
			return "time scale %.0f" % Engine.time_scale
		"pdiff":
			return _pdiff(step)
		"sheet":
			return _sheet(String(step.get("out", "user://render_jobs/fire_ab/sheet")))
		"load":
			return _load(step)
	var ctrl: AuthoringController = base.get("_authoring_controller")
	if ctrl == null or ctrl.editor == null:
		return "no authoring editor"
	match action:
		"patch":
			return _patch(ctrl, step)
		"grab":
			var gm: GameMap = base.get("_game_map")
			var tag := String(step.get("tag", "a"))
			_grabs[tag] = gm.camera_node.get_viewport().get_texture().get_image()
			return "grabbed %s" % tag
	return "unknown action %s" % action


static func _patch(ctrl: AuthoringController, step: Dictionary) -> String:
	var name := String(step.get("variant", "none")).split("#")[0]
	var variant := {}
	if name != "none":
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(String(step.get("file", "")))
		)
		if not parsed is Dictionary or not (parsed as Dictionary).has(name):
			return "no variant %s" % name
		variant = parsed[name]
	var shaders := {
		"glow": ctrl.editor.terrain.get_material().shader,
		"flames": FireLook.material().shader,
		"smoke": FireFieldSmoke.material().shader,
	}
	var changed := PackedStringArray()
	for part: String in shaders:
		var shader: Shader = shaders[part]
		if not _codes.has(part):
			_codes[part] = shader.code
		var code := String(_codes[part])
		if variant.has(part):
			code = _variant_code(part, code, variant[part])
			if code == "":
				return "variant %s: a %s edit was not found" % [name, part]
			changed.append(part)
		if shader.code != code:
			shader.code = code
	var config := PerfProbe._config(ctrl, ctrl.editor.fire_field, String(variant.get("config", "on")))
	return "variant %s (%s); %s" % [name, ", ".join(changed), config]


## `part`'s code with variant `spec` (see the header); "" when an edit's text is missing.
static func _variant_code(part: String, own: String, spec: Dictionary) -> String:
	var path := GLOW_INC if part == "glow" else String(FILES[part])
	var source := _read(String(spec.get("source", path)))
	if source == "":
		return ""
	for edit: Array in spec.get("edits", []):
		if not source.contains(String(edit[0])):
			return ""
		source = source.replace(String(edit[0]), String(edit[1]))
	if part != "glow":
		return source
	var ground := FileAccess.get_file_as_string(GROUND_INC)
	ground = ground.replace('#include "%s"' % GLOW_INC, source)
	return own.replace('#include "%s"' % GROUND_INC, ground)


## The text at `path`, or of the file `inner` in a zip for "<archive>.zip:<inner>" (main's
## sources: `git archive --format=zip --output=<archive>.zip HEAD <paths>`); "" when missing.
static func _read(path: String) -> String:
	var split := path.find(".zip:")
	if split < 0:
		return FileAccess.get_file_as_string(path)
	var zip := ZIPReader.new()
	if zip.open(path.substr(0, split + 4)) != OK:
		return ""
	var text := zip.read_file(path.substr(split + 5)).get_string_from_utf8()
	zip.close()
	return text


static func _load(step: Dictionary) -> String:
	var path := String(step.get("path", ""))
	var image := Image.load_from_file(ProjectSettings.globalize_path(path))
	if image == null or image.is_empty():
		return "no image at %s" % path
	var tag := String(step.get("tag", "a"))
	_grabs[tag] = image
	return "loaded %s as %s (%s)" % [path, tag, str(image.get_size())]


static func _pdiff(step: Dictionary) -> String:
	var a: Image = _grabs.get(String(step.get("a", "a")))
	var b: Image = _grabs.get(String(step.get("b", "b")))
	if a == null or b == null:
		return "no grabs to compare"
	a = a.duplicate() as Image
	b = b.duplicate() as Image
	# A reference frame saved at another size: the larger one taken down to the smaller.
	var size := a.get_size().min(b.get_size())
	for image: Image in [a, b]:
		if image.get_size() != size:
			image.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var metrics := a.compute_image_metrics(b, false)
	# The share of pixels over the thresholds, and the diff, at half size.
	var half := a.get_size() / 2
	var small_a := a.duplicate() as Image
	var small_b := b.duplicate() as Image
	small_a.resize(half.x, half.y, Image.INTERPOLATE_NEAREST)
	small_b.resize(half.x, half.y, Image.INTERPOLATE_NEAREST)
	var bytes_a := small_a.get_data()
	var bytes_b := small_b.get_data()
	var diff := PackedByteArray()
	diff.resize(bytes_a.size())
	var gain := float(step.get("gain", 4.0))
	var over := [0, 0]
	for k in range(0, bytes_a.size(), 3):
		var most := 0
		for c in 3:
			var d := absi(bytes_b[k + c] - bytes_a[k + c])
			most = maxi(most, d)
			diff[k + c] = mini(roundi(d * gain), 255)
		over[0] += 1 if most > 8 else 0
		over[1] += 1 if most > 24 else 0
	var count := float(half.x * half.y)
	var tiles: Array[Image] = [
		small_a, small_b, Image.create_from_data(half.x, half.y, false, Image.FORMAT_RGB8, diff)
	]
	var row := Image.create(ROW_TILE.x * 3, ROW_TILE.y, false, Image.FORMAT_RGB8)
	for k in tiles.size():
		var tile := tiles[k]
		tile.resize(ROW_TILE.x, ROW_TILE.y, Image.INTERPOLATE_BILINEAR)
		row.blit_rect(tile, Rect2i(Vector2i.ZERO, ROW_TILE), Vector2i(ROW_TILE.x * k, 0))
	_rows.append(row)
	var out := String(step.get("out", "user://render_jobs/fire_ab/row"))
	row.save_png(out + ".png")
	return (
		"pdiff %s vs %s: mean %.3f, rms %.3f, max %d; pixels over 8: %.3f %%, over 24: %.3f %%"
		% [
			step.get("a", "a"), step.get("b", "b"), float(metrics.get("mean", 0.0)),
			float(metrics.get("root_mean_squared", 0.0)), int(metrics.get("max", 0)),
			100.0 * over[0] / count, 100.0 * over[1] / count
		]
	)


static func _sheet(out: String) -> String:
	if _rows.is_empty():
		return "no rows"
	var width := _rows[0].get_width()
	var sheet := Image.create(width, ROW_TILE.y * _rows.size(), false, Image.FORMAT_RGB8)
	for k in _rows.size():
		sheet.blit_rect(_rows[k], Rect2i(Vector2i.ZERO, _rows[k].get_size()), Vector2i(0, ROW_TILE.y * k))
	sheet.save_png(out + ".png")
	var n := _rows.size()
	_rows.clear()
	return "sheet of %d rows: %s.png" % [n, out]
