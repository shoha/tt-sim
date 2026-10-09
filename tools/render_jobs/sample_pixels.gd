extends SceneTree

## Standalone helper for reading captures: prints the mean colour of a 9x9 box every <step>
## pixels down column <x> from <y0> to <y1>, for each PNG given.
##   godot --headless --path D:/dev/tt-sim --script res://tools/render_jobs/sample_pixels.gd
##     -- <x> <y0> <y1> <step> <png>...
## Coordinates are the PNG's own pixels, read off the image being sampled. Captures are half
## size (960x540) by default and full size only with --full, so coordinates taken from one
## size are wrong on the other: each image's size is printed with its name, and a column or
## row outside it is flagged rather than silently clamped to the edge.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		print("usage: -- <x> <y0> <y1> <step> <png>...")
		quit(2)
		return
	var x := int(args[0])
	var y0 := int(args[1])
	var y1 := int(args[2])
	var step := int(args[3])
	for k in range(4, args.size()):
		var img := Image.load_from_file(args[k])
		if img == null:
			print("%s: could not load" % args[k])
			continue
		var w := img.get_width()
		var h := img.get_height()
		var outside := x >= w or y0 >= h or y1 >= h
		print(
			(
				"%s %dx%d%s"
				% [args[k].get_file(), w, h, " (coordinates outside the image)" if outside else ""]
			)
		)
		var line := ""
		for y in range(y0, y1 + 1, step):
			var sum := Color(0, 0, 0, 0)
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					sum += img.get_pixel(clampi(x + dx, 0, w - 1), clampi(y + dy, 0, h - 1))
			sum /= 81.0
			line += "%d:%d,%d,%d " % [y, int(sum.r * 255), int(sum.g * 255), int(sum.b * 255)]
		print(line)
	quit(0)
