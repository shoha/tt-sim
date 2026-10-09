extends SceneTree

## Avatar token probe (2026-10-05): compares two captures inside a rectangle, to tell
## whether a skinned figure (outline hull included) renders the same pixels as its baked
## twin. Standalone, not a `call` probe:
##
##   godot --headless --path D:/dev/tt-sim
##     --script res://tools/render_jobs/probes/avatar_diff.gd -- <a> <b> <x0> <y0> <x1> <y1>
##
## Prints the mean absolute channel difference (0-255) and how many pixels differ by more
## than 8 and by more than 32 in any channel. The rectangle is in the images' own pixels.
## A pixel-exact diff needs full-size captures (a halved one averages a one-pixel difference
## away), so avatar_probe.json pins its twin captures at "scale" 1.0; the result line names
## the image size and says when the rectangle had to be clamped to it.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	# `crop <in.png> <x> <y> <w> <h> <out.png> [scale]`: cut a region out for a close look.
	if args.size() >= 7 and args[0] == "crop":
		var src := Image.load_from_file(args[1])
		var region := src.get_region(Rect2i(int(args[2]), int(args[3]), int(args[4]), int(args[5])))
		var s := int(args[7]) if args.size() > 7 else 1
		region.resize(region.get_width() * s, region.get_height() * s, Image.INTERPOLATE_NEAREST)
		region.save_png(args[6])
		print("cropped %s" % args[6])
		quit(0)
		return
	if args.size() < 6:
		print("usage: <a.png> <b.png> <x0> <y0> <x1> <y1>")
		quit(1)
		return
	var a := Image.load_from_file(args[0])
	var b := Image.load_from_file(args[1])
	if a == null or b == null or a.get_size() != b.get_size():
		print("could not load both images at one size")
		quit(1)
		return
	var x0 := clampi(int(args[2]), 0, a.get_width() - 1)
	var y0 := clampi(int(args[3]), 0, a.get_height() - 1)
	var x1 := clampi(int(args[4]), 0, a.get_width() - 1)
	var y1 := clampi(int(args[5]), 0, a.get_height() - 1)
	var clamped := (
		Vector4i(x0, y0, x1, y1) != Vector4i(int(args[2]), int(args[3]), int(args[4]), int(args[5]))
	)
	var total := 0.0
	var n := 0
	var over8 := 0
	var over32 := 0
	# Optional 7th argument: a PNG path for the diff mask (white over 32, grey over 8).
	var mask := Image.create(a.get_width(), a.get_height(), false, Image.FORMAT_RGB8)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var d := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b)) * 255.0
			total += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) * 255.0 / 3.0
			n += 1
			over8 += 1 if d > 8.0 else 0
			over32 += 1 if d > 32.0 else 0
			if d > 8.0:
				mask.set_pixel(x, y, Color.WHITE if d > 32.0 else Color(0.4, 0.4, 0.4))
	if args.size() > 6:
		mask.save_png(args[6])
	print(
		(
			"diff rect %d,%d-%d,%d of %dx%d%s: %d px, mean %.3f, over 8: %d, over 32: %d"
			% [
				x0,
				y0,
				x1,
				y1,
				a.get_width(),
				a.get_height(),
				" (clamped)" if clamped else "",
				n,
				total / maxi(n, 1),
				over8,
				over32
			]
		)
	)
	quit(0)
