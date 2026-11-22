extends SceneTree

## Pixel identity of two runs' captures (README "Comparing runs and worktrees"), headless:
##   godot --headless --path <checkout> --script res://tools/render_jobs/capture_diff.gd --
##       <folder a> <folder b> <mask folder or -> <name.png> [<name.png> | <a.png>=<b.png> ...]
## `name.png` compares the file of that name in both folders; `a.png=b.png` compares a in A with b
## in B. Per pair it prints one `DIFF` line: the pixels that differ in any channel, the largest
## channel difference, how many differ by 1, 2-3, 4-15 and 16 or more levels, and their bounding
## box; the first few 16+ pixels follow with both colours (they say which surface flips). With a
## mask folder, each differing pair also writes `mask_<name>`: A dimmed to a quarter with the
## differing pixels painted cyan (1-3), yellow (4-15) or red (16+).
## Read the DIFF lines first and open a mask only to see where.

## How many 16+ pixels a pair prints with their colours.
const SAMPLES := 8


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4:
		print("usage: -- <folder a> <folder b> <mask folder or -> <name.png> [...]")
		quit(1)
		return
	var mask_dir := String(args[2])
	if mask_dir != "-":
		DirAccess.make_dir_recursive_absolute(mask_dir)
	for k in range(3, args.size()):
		var pair := String(args[k]).split("=")
		print(_compare(String(args[0]).path_join(pair[0]), String(args[1]).path_join(pair[-1]), mask_dir))
	quit()


## The DIFF line for one pair (and its mask when `mask_dir` is not "-").
static func _compare(path_a: String, path_b: String, mask_dir: String) -> String:
	var name := path_a.get_file()
	var a := Image.load_from_file(path_a)
	var b := Image.load_from_file(path_b)
	if a == null or b == null:
		return "DIFF %s: cannot load" % name
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	if a.get_size() != b.get_size():
		return "DIFF %s: sizes %s %s" % [name, a.get_size(), b.get_size()]
	var da := a.get_data()
	var db := b.get_data()
	if da == db:
		return "DIFF %s %s: 0 px differ" % [name, a.get_size()]
	var w := a.get_width()
	var differ := 0
	var worst := 0
	var bins := [0, 0, 0, 0]
	var box := Rect2i()
	var mask := da.duplicate()
	var samples := PackedStringArray()
	for i in w * a.get_height():
		var o := i * 3
		var d := maxi(absi(da[o] - db[o]), maxi(absi(da[o + 1] - db[o + 1]), absi(da[o + 2] - db[o + 2])))
		var paint := Color8(da[o] / 4, da[o + 1] / 4, da[o + 2] / 4)
		if d > 0:
			differ += 1
			worst = maxi(worst, d)
			var bin := 0 if d == 1 else (1 if d < 4 else (2 if d < 16 else 3))
			bins[bin] += 1
			paint = [Color8(0, 220, 255), Color8(0, 220, 255), Color8(255, 230, 0), Color8(255, 0, 0)][bin]
			var px := Rect2i(i % w, i / w, 1, 1)
			box = box.merge(px) if box.has_area() else px
			if bin == 3 and samples.size() < SAMPLES:
				samples.append(
					(
						"  (%d,%d) a %d,%d,%d b %d,%d,%d"
						% [i % w, i / w, da[o], da[o + 1], da[o + 2], db[o], db[o + 1], db[o + 2]]
					)
				)
		mask[o] = paint.r8
		mask[o + 1] = paint.g8
		mask[o + 2] = paint.b8
	if mask_dir != "-":
		var img := Image.create_from_data(w, a.get_height(), false, Image.FORMAT_RGB8, mask)
		img.save_png(mask_dir.path_join("mask_" + name))
	var line := (
		"DIFF %s %s: %d px differ (%.3f%%), max %d, by 1/2-3/4-15/16+: %s, box %s"
		% [name, a.get_size(), differ, 100.0 * differ / (w * a.get_height()), worst, bins, box]
	)
	if not samples.is_empty():
		line += "\n" + "\n".join(samples)
	return line
