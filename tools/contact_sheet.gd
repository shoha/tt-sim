extends SceneTree

## Contact-sheet maker for render-job captures. Headless:
##   godot --headless --path D:/dev/tabletop/tt-sim --script res://tools/contact_sheet.gd -- <out.png> <cols> <tile_width> <in1.png> <in2.png> ...
## Tiles the inputs left to right, top to bottom, each scaled to tile_width, 4 px apart.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		push_error("usage: <out.png> <cols> <tile_width> <in.png>...")
		quit(2)
		return
	var out := args[0]
	var cols := int(args[1])
	var tile_w := int(args[2])
	var images: Array[Image] = []
	for i in range(3, args.size()):
		var img := Image.load_from_file(args[i])
		if img == null:
			push_error("cannot load " + args[i])
			continue
		var h := int(round(float(img.get_height()) * tile_w / img.get_width()))
		img.resize(tile_w, h, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		images.append(img)
	if images.is_empty():
		quit(1)
		return
	var tile_h := images[0].get_height()
	var rows := int(ceil(float(images.size()) / cols))
	var sheet := Image.create(
		cols * tile_w + (cols - 1) * 4, rows * tile_h + (rows - 1) * 4, false, Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for i in images.size():
		var at := Vector2i((i % cols) * (tile_w + 4), (i / cols) * (tile_h + 4))
		sheet.blit_rect(images[i], Rect2i(0, 0, tile_w, tile_h), at)
	sheet.save_png(out)
	print("SHEET| %s %dx%d from %d tiles" % [out, sheet.get_width(), sheet.get_height(), images.size()])
	quit(0)
