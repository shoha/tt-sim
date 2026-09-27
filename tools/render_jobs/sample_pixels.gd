extends SceneTree

## Standalone helper for reading captures: prints the mean colour of a 9x9 box every <step>
## pixels down column <x> from <y0> to <y1>, for each PNG given.
##   godot --headless --path D:/dev/tt-sim --script res://tools/render_jobs/sample_pixels.gd
##     -- <x> <y0> <y1> <step> <png>...


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
		print(args[k].get_file())
		var line := ""
		for y in range(y0, y1 + 1, step):
			var sum := Color(0, 0, 0, 0)
			for dy in range(-4, 5):
				for dx in range(-4, 5):
					sum += img.get_pixel(
						clampi(x + dx, 0, img.get_width() - 1),
						clampi(y + dy, 0, img.get_height() - 1)
					)
			sum /= 81.0
			line += "%d:%d,%d,%d " % [y, int(sum.r * 255), int(sum.g * 255), int(sum.b * 255)]
		print(line)
	quit(0)
