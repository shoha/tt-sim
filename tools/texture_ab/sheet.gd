extends SceneTree

## Contact sheets of the arms' render-job captures (windowed: it draws labels with the engine's
## font and reads the window back). For each crop, one JPG of the arms' 1:1 crops side by side and
## one of their difference from the reference arm, amplified. Also writes stats.json: per view and
## arm the whole frame's mean absolute level difference, the share over 4 levels and the maximum
## against the reference.
##
##   godot --path <project> --windowed --resolution 1600x720 \
##       --script res://tools/texture_ab/sheet.gd -- \
##       --dir=<render_jobs folder> --arms=png,png2,d90m --labels="A|A2|D90" --ref=png \
##       --crops=close:520,470,520,330;close:200,100,520,330 --names=close_cobble,close_grass \
##       --out=<folder> [--gain=16] [--cols=3] [--suffix=_sub]

var _dir := ""
var _arms: PackedStringArray = []
var _labels: PackedStringArray = []
var _ref := ""
var _crops: PackedStringArray = []
var _names: PackedStringArray = []
var _out := ""
var _gain := 16
var _cols := 3
var _suffix := "_sub"
var _cache := {}


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		var at := arg.find("=")
		if at < 0:
			continue
		var key := arg.substr(0, at)
		var value := arg.substr(at + 1)
		match key:
			"--dir":
				_dir = value
			"--arms":
				_arms = value.split(",")
			"--labels":
				_labels = value.split("|")
			"--ref":
				_ref = value
			"--crops":
				_crops = value.split(";")
			"--names":
				_names = value.split(",")
			"--out":
				_out = value
			"--gain":
				_gain = int(value)
			"--cols":
				_cols = int(value)
			"--suffix":
				_suffix = value
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var stats := {}
	for i in _crops.size():
		var spec := _crops[i].split(":")
		var view := spec[0]
		var box := spec[1].split(",")
		var rect := Rect2i(int(box[0]), int(box[1]), int(box[2]), int(box[3]))
		var looks: Array = []
		var diffs: Array = []
		var ref := _image(view, _ref)
		for a in _arms.size():
			var arm := _arms[a]
			var image := _image(view, arm)
			looks.append([_labels[a], image.get_region(rect)])
			if arm != _ref:
				var s := _stats(ref, image)
				stats["%s/%s" % [view, arm]] = s
				var text := "%s - %s  mean %.3f  >4: %.2f%%  max %d" % [
					_labels[a], _labels[_arms.find(_ref)], s["mean"], s["over4"] * 100.0, s["max"]
				]
				diffs.append([text, _diff(ref.get_region(rect), image.get_region(rect))])
		await _sheet(looks, "%s/%s_look.jpg" % [_out, _names[i]])
		await _sheet(diffs, "%s/%s_diff.jpg" % [_out, _names[i]])
	var file := FileAccess.open(_out.path_join("stats.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(stats, "\t"))
	file.close()
	quit(0)


func _image(view: String, arm: String) -> Image:
	var key := view + arm
	if not _cache.has(key):
		var image := Image.load_from_file(
			"%s/textures_%s/%s%s.png" % [_dir, arm, view, _suffix]
		)
		image.convert(Image.FORMAT_RGB8)
		_cache[key] = image
	return _cache[key]


func _stats(a: Image, b: Image) -> Dictionary:
	var da := a.get_data()
	var db := b.get_data()
	var sum := 0
	var over := 0
	var worst := 0
	for i in da.size():
		var d := absi(da[i] - db[i])
		sum += d
		if d > 4:
			over += 1
		if d > worst:
			worst = d
	return {"mean": float(sum) / da.size(), "over4": float(over) / da.size(), "max": worst}


func _diff(a: Image, b: Image) -> Image:
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(da.size())
	for i in da.size():
		out[i] = mini(255, absi(da[i] - db[i]) * _gain)
	return Image.create_from_data(a.get_width(), a.get_height(), false, a.get_format(), out)


func _sheet(tiles: Array, path: String) -> void:
	var holder := PanelContainer.new()
	var grid := GridContainer.new()
	grid.columns = _cols
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	holder.add_child(grid)
	for tile in tiles:
		var box := VBoxContainer.new()
		var label := Label.new()
		label.text = String(tile[0])
		label.add_theme_font_size_override("font_size", 14)
		box.add_child(label)
		var rect := TextureRect.new()
		rect.texture = ImageTexture.create_from_image(tile[1])
		rect.stretch_mode = TextureRect.STRETCH_KEEP
		box.add_child(rect)
		grid.add_child(box)
	root.add_child(holder)
	holder.position = Vector2.ZERO
	await process_frame
	await process_frame
	await process_frame
	var size := holder.size
	DisplayServer.window_set_size(Vector2i(size))
	root.size = Vector2i(size)
	await process_frame
	await process_frame
	var shot := root.get_texture().get_image()
	shot.save_jpg(path, 0.93)
	print("sheet ", path, " ", shot.get_size())
	root.remove_child(holder)
	holder.queue_free()
