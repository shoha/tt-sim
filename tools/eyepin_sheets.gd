extends SceneTree

## Labelled contact sheet for the eyepin round (needs a window, so not --headless):
##   godot --path <tt-sim> --script res://tools/eyepin_sheets.gd -- <out.png> <columns> <tile_width> <item>...
## Each item is `label|path` (a PNG; user:// paths work) or `-` for an empty cell. Cells run row by
## row; each tile is `tile_width` wide with its label on a bar above it.

const BAR := 30
const GAP := 6


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var columns := int(args[1])
	var tile_w := int(args[2])
	var items := args.slice(3)
	var tile_h := int(tile_w * 9.0 / 16.0)
	var rows := int(ceil(float(items.size()) / columns))
	var size := Vector2i(columns * (tile_w + GAP) + GAP, rows * (tile_h + BAR + GAP) + GAP)
	var viewport := SubViewport.new()
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var back := ColorRect.new()
	back.color = Color(0.1, 0.1, 0.12)
	back.size = Vector2(size)
	viewport.add_child(back)
	for i in items.size():
		if items[i] == "-":
			continue
		var parts := String(items[i]).split("|")
		var at := Vector2(GAP + (i % columns) * (tile_w + GAP), GAP + (i / columns) * (tile_h + BAR + GAP))
		# A bar of its own under the label, so the text is light on a dark ground whatever the sheet's
		# background does, with a dark outline besides.
		var bar := ColorRect.new()
		bar.color = Color(0.2, 0.21, 0.28)
		bar.position = at
		bar.size = Vector2(tile_w, BAR)
		viewport.add_child(bar)
		var label := Label.new()
		label.text = parts[0]
		label.position = at + Vector2(6, 2)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 4)
		viewport.add_child(label)
		var image := Image.load_from_file(parts[1])
		if image == null:
			push_error("cannot read %s" % parts[1])
			continue
		var tile := TextureRect.new()
		tile.texture = ImageTexture.create_from_image(image)
		tile.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tile.stretch_mode = TextureRect.STRETCH_SCALE
		tile.position = at + Vector2(0, BAR)
		tile.size = Vector2(tile_w, tile_h)
		viewport.add_child(tile)
	for _f in 4:
		await process_frame
	var sheet := viewport.get_texture().get_image()
	sheet.save_png(out)
	print("sheet %s %s" % [out, str(sheet.get_size())])
	quit(0)
