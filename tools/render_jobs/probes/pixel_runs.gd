extends SceneTree

## Capture probe (2026-11-02): the runs of near-equal colour down one pixel column of a PNG, to
## measure a UI element's edges in the image's own pixels. Standalone, not a `call` probe:
##
##   godot --headless --path D:/dev/tabletop/tt-sim
##     --script res://tools/render_jobs/probes/pixel_runs.gd -- <png> <x> <y0> <y1> [tolerance]
##
## Prints one line per run: `y0-y1 (n px) #rrggbb`. A run ends where a pixel differs from the
## run's first by more than `tolerance` (0-255, default 10) in any channel.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: <png> <x> <y0> <y1> [tolerance]")
		quit(1)
		return
	var image := Image.load_from_file(args[0])
	if image == null:
		print("could not load %s" % args[0])
		quit(1)
		return
	var x := clampi(int(args[1]), 0, image.get_width() - 1)
	var y0 := clampi(int(args[2]), 0, image.get_height() - 1)
	var y1 := clampi(int(args[3]), 0, image.get_height() - 1)
	var tolerance := float(args[4]) / 255.0 if args.size() > 4 else 10.0 / 255.0
	print("%s is %dx%d, column x=%d" % [args[0], image.get_width(), image.get_height(), x])
	var start := y0
	var base := image.get_pixel(x, y0)
	for y in range(y0 + 1, y1 + 2):
		var done := y > y1
		if not done:
			var c := image.get_pixel(x, y)
			var d := maxf(maxf(absf(c.r - base.r), absf(c.g - base.g)), absf(c.b - base.b))
			done = d > tolerance
		if done:
			print("%d-%d (%d px) #%s" % [start, y - 1, y - start, base.to_html(false)])
			if y <= y1:
				start = y
				base = image.get_pixel(x, y)
	quit(0)
