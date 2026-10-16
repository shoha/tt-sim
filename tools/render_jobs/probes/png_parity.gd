extends SceneTree

## Pixel parity of captures (the ground optimization card's exactness check,
## jobs/ground_opt_parity.json):
##
##   godot --headless --path D:/dev/tt-sim --script res://tools/render_jobs/probes/png_parity.gd
##       -- <folder a> <folder b>
##   ... -- <folder> <token a> <token b>
##
## Two folders: every PNG in `a` against its namesake in `b`. A folder and two tokens: every PNG
## whose name holds `token a` against the one with `token b` in its place (`_new` against `_old`:
## one run's captures of one frozen view with the new and the old code). Per pair `identical`, or
## the largest difference of any channel, how many pixels differ and their bounding box. Folders
## are absolute or user:// paths. Captures must be full size (a capture step's `scale` 1.0 or
## `--full`): halving averages a one-level difference away. The last line sums it up.
##
## Captures of one view from two runs are not comparable: on 2026-10-15 two runs of the same
## saved levels differed in 37 of 40 views (zoomed views by millions of pixels), so a parity check
## compares captures taken inside one run.


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		print("RJ| parity usage: -- <folder a> <folder b>, or -- <folder> <token a> <token b>")
		quit(1)
		return
	var pairs := _pairs(args)
	var differing := 0
	var worst := 0
	for pair: Array in pairs:
		var result := compare(Image.load_from_file(pair[0]), Image.load_from_file(pair[1]))
		if int(result.max) != 0:
			differing += 1
		worst = maxi(worst, int(result.max))
		print("RJ| parity %s: %s" % [String(pair[0]).get_file(), String(result.text)])
	print(
		(
			"RJ| parity done: %d pairs compared, %d differ, max channel diff %d"
			% [pairs.size(), differing, worst]
		)
	)
	quit(0)


## [path a, path b] for every pair the arguments name (see the header).
static func _pairs(args: PackedStringArray) -> Array:
	var out: Array = []
	var a := String(args[0])
	var two_folders := args.size() == 2
	var b := String(args[1]) if two_folders else a
	for file in DirAccess.get_files_at(a):
		if not file.ends_with(".png"):
			continue
		var other := file
		if not two_folders:
			if not file.contains(args[1]):
				continue
			other = file.replace(args[1], args[2])
		if FileAccess.file_exists(b.path_join(other)):
			out.append([a.path_join(file), b.path_join(other)])
		else:
			print("RJ| parity %s: no %s" % [file, b.path_join(other)])
	return out


## {max, pixels, text} for two images: the largest channel difference (255 when the sizes
## differ), how many pixels differ in any channel, and a line saying so with their bounds.
static func compare(ia: Image, ib: Image) -> Dictionary:
	if ia == null or ib == null:
		return {"max": 255, "pixels": -1, "text": "unreadable"}
	if ia.get_size() != ib.get_size():
		return {"max": 255, "pixels": -1, "text": "sizes %s and %s" % [ia.get_size(), ib.get_size()]}
	ia.convert(Image.FORMAT_RGBA8)
	ib.convert(Image.FORMAT_RGBA8)
	var da := ia.get_data()
	var db := ib.get_data()
	if da == db:
		return {"max": 0, "pixels": 0, "text": "identical"}
	var width := ia.get_width()
	var worst := 0
	var pixels := 0
	var lo := Vector2i(width, ia.get_height())
	var hi := Vector2i(-1, -1)
	for i in range(0, da.size(), 4):
		var d := maxi(
			maxi(absi(da[i] - db[i]), absi(da[i + 1] - db[i + 1])),
			maxi(absi(da[i + 2] - db[i + 2]), absi(da[i + 3] - db[i + 3]))
		)
		if d > 0:
			pixels += 1
			worst = maxi(worst, d)
			var at := Vector2i((i / 4) % width, (i / 4) / width)
			lo = Vector2i(mini(lo.x, at.x), mini(lo.y, at.y))
			hi = Vector2i(maxi(hi.x, at.x), maxi(hi.y, at.y))
	return {
		"max": worst,
		"pixels": pixels,
		"text": "max channel diff %d, %d pixels differ, within %s-%s" % [worst, pixels, lo, hi],
	}
