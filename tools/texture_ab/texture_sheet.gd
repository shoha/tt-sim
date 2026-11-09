extends SceneTree

## The worst case for a lossy map: the texture itself at 1:1 texels, no lighting, no minification.
## For each surface one JPG with the crop of the baked top mip (decompressed BC7, what the GPU
## samples at the finest level) of the PNG, then of lossy WebP q95, q90 and q85 after the same
## bake, and below them the difference of each lossy tile from the PNG's, amplified.
##
##   godot --path <project> --windowed --resolution 1600x760 \
##       --script res://tools/texture_ab/texture_sheet.gd -- \
##       --surfaces=gravel,cliff --kind=albedo --crop=300,300,400,300 --out=<folder> [--gain=16]

const CANDS: Array[String] = ["d95_webp", "d90_webp", "d85_webp"]

var _gain := 16


func _initialize() -> void:
	var surfaces: PackedStringArray = []
	var kind := "albedo"
	var box := PackedStringArray(["300", "300", "400", "300"])
	var out := ""
	for arg in OS.get_cmdline_user_args():
		var at := arg.find("=")
		var value := arg.substr(at + 1)
		match arg.substr(0, at):
			"--surfaces":
				surfaces = value.split(",")
			"--kind":
				kind = value
			"--crop":
				box = value.split(",")
			"--out":
				out = value
			"--gain":
				_gain = int(value)
	DirAccess.make_dir_recursive_absolute(out)
	var rect := Rect2i(int(box[0]), int(box[1]), int(box[2]), int(box[3]))
	_run.call_deferred(surfaces, kind, rect, out)


func _run(surfaces: PackedStringArray, kind: String, rect: Rect2i, out: String) -> void:
	for surface in surfaces:
		var src := TextureAb.load_source(surface, kind)
		var ref := TextureAb.mip0_rgba(SurfaceBake.bake(src, kind))
		var tiles: Array = [["A: PNG baked (BC)", ref.get_region(rect)]]
		var diffs: Array = [["difference x%d from A" % _gain, null]]
		for candidate in CANDS:
			var decoded := TextureAb.decode(candidate, TextureAb.encode(candidate, src, kind), src)
			var baked := TextureAb.mip0_rgba(TextureAb.to_baked(decoded, kind))
			var label := "%s baked" % candidate.replace("_webp", "").to_upper()
			tiles.append([label, baked.get_region(rect)])
			diffs.append([label + " - A", _diff(ref.get_region(rect), baked.get_region(rect))])
		diffs[0][1] = Image.create_empty(rect.size.x, rect.size.y, false, Image.FORMAT_RGBA8)
		await _sheet(
			tiles + diffs, "%s/%s_%s.jpg" % [out, surface, kind], "%s %s" % [surface, kind]
		)
	quit(0)


func _diff(a: Image, b: Image) -> Image:
	var da := a.get_data()
	var db := b.get_data()
	var out := PackedByteArray()
	out.resize(da.size())
	for i in da.size():
		out[i] = 255 if i % 4 == 3 else mini(255, absi(da[i] - db[i]) * _gain)
	return Image.create_from_data(a.get_width(), a.get_height(), false, a.get_format(), out)


func _sheet(tiles: Array, path: String, title: String) -> void:
	var holder := PanelContainer.new()
	var column := VBoxContainer.new()
	var head := Label.new()
	head.text = title
	column.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	holder.add_child(column)
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
