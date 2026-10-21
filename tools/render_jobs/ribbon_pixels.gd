extends SceneTree

## Standalone helper for reading a line tool's ribbon off a capture: within a box of each PNG
## it compares the composited window (<name>.png, the brush cursor drawn) with its raw 3D
## SubViewport (<name>_sub.png, the board alone) pixel by pixel, keeps the pixels the ribbon
## changed (by more than THRESHOLD, and not darkened below INK_SHARE of the board, so its ink
## outline is left out) and prints, for all of them, those over a golden board (yellow:
## red at least green, little blue) and those over grass (green over red), their count, their
## median relative luminance (WCAG), the board's under them, the median contrast ratio between
## the two, and both mean colours.
##   godot --headless --path D:/dev/tabletop/tt-sim
##     --script res://tools/render_jobs/ribbon_pixels.gd
##     -- <x0> <y0> <x1> <y1> <png>...
## Coordinates are the PNG's own pixels (half size unless the run passed --full). Keep the box
## off the ring and its chip, drawn in the ring's colour whatever the ribbon's.

## The least change (summed over r, g, b, 0..3) that counts as the ribbon's.
const THRESHOLD := 0.15
## A pixel darker than this share of the board's luminance is the ribbon's ink, not its fill.
const INK_SHARE := 0.6


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 5:
		print("usage: -- <x0> <y0> <x1> <y1> <png>...")
		quit(2)
		return
	var box := Rect2i(
		Vector2i(int(args[0]), int(args[1])),
		Vector2i(int(args[2]) - int(args[0]), int(args[3]) - int(args[1]))
	)
	for k in range(4, args.size()):
		print(_read(args[k], box))
	quit(0)


func _read(path: String, box: Rect2i) -> String:
	var shown := Image.load_from_file(path)
	var board := Image.load_from_file(path.get_basename() + "_sub.png")
	if shown == null or board == null:
		return "%s: could not load it and its _sub" % path.get_file()
	if shown.get_size() != board.get_size():
		# The board's viewport renders at the content scale (1371x771 under a 1280x720 window).
		board.resize(shown.get_width(), shown.get_height(), Image.INTERPOLATE_BILINEAR)
	var area := box.intersection(Rect2i(Vector2i.ZERO, shown.get_size()))
	var groups := {"all": [], "gold": [], "grass": []}
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := shown.get_pixel(x, y)
			var g := board.get_pixel(x, y)
			var change := absf(c.r - g.r) + absf(c.g - g.g) + absf(c.b - g.b)
			if change < THRESHOLD or luminance(c) < INK_SHARE * luminance(g):
				continue
			groups.all.append([c, g])
			if g.r >= g.g * 0.95 and g.b < g.g * 0.6:
				groups.gold.append([c, g])
			elif g.g > g.r * 1.05 and g.g > g.b:
				groups.grass.append([c, g])
	var out := "%s %s:" % [path.get_file(), str(area)]
	for key: String in groups:
		out += "\n  " + _summary(key, groups[key])
	return out


## The ribbon pixels `pairs` ([shown, board] colours) over one kind of board: their count, the
## median luminance of each, the median contrast ratio between them and both mean colours.
static func _summary(key: String, pairs: Array) -> String:
	if pairs.is_empty():
		return "%s: no ribbon pixels" % key
	var lit := PackedFloat32Array()
	var under := PackedFloat32Array()
	var ratios := PackedFloat32Array()
	var sum_lit := Color(0, 0, 0, 0)
	var sum_under := Color(0, 0, 0, 0)
	for pair: Array in pairs:
		var lc := luminance(pair[0])
		var lg := luminance(pair[1])
		lit.append(lc)
		under.append(lg)
		ratios.append((maxf(lc, lg) + 0.05) / (minf(lc, lg) + 0.05))
		sum_lit += pair[0]
		sum_under += pair[1]
	var n := float(pairs.size())
	return (
		"%s %d px: ribbon L %.3f over board L %.3f, contrast %.2f:1, ribbon %s board %s"
		% [
			key,
			pairs.size(),
			_median(lit),
			_median(under),
			_median(ratios),
			_rgb(sum_lit / n),
			_rgb(sum_under / n),
		]
	)


## WCAG relative luminance of `c` (sRGB).
static func luminance(c: Color) -> float:
	var lin := c.srgb_to_linear()
	return 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b


static func _median(values: PackedFloat32Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[sorted.size() / 2]


static func _rgb(c: Color) -> String:
	return "%d,%d,%d" % [int(c.r * 255), int(c.g * 255), int(c.b * 255)]
