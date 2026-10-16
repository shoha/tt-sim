extends SceneTree

## Capture reader for pixel parity (ground ship card 3c, jobs/ground_parity.json): compares
## pairs of same-size captures and says where they differ. Standalone, not a `call` probe:
##
##   godot --headless --path D:/dev/tt-sim
##     --script res://tools/render_jobs/probes/parity_diff.gd -- <manifest.json>
##
## The manifest: {"out_dir", "dilate_px" (default 6), "pairs": [{"view", "ref", "mine",
## "bare" (optional), "save_as" (optional)}]}. Per pair it prints, on 0-255 sRGB values: the
## mean colour of both and the largest channel delta, the mean luma of the darkest and of the
## brightest tenth of the pixels and their deltas, the share of pixels whose largest channel
## differs by more than 2, and where those sit. `bare` is `mine` captured with the scatter
## hidden: a pixel where the two differ (dilated by `dilate_px`, so a blade swayed a few
## pixels and its moving shadow still count) is scatter, any other pixel ground. With
## `save_as` it writes `<save_as>.png` (a copy of `mine`), `diff_<save_as>.png` (a dimmed
## `ref` with each differing pixel drawn grey on scatter and red on ground, brighter the larger
## the difference) and, in `half/`, half-size copies of both plus `sheet_<save_as>.png` (ref,
## mine and diff side by side).

const OVER := 2


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var manifest: Variant = (
		JSON.parse_string(FileAccess.get_file_as_string(args[0])) if args.size() > 0 else null
	)
	if not manifest is Dictionary:
		print("usage: <manifest.json>")
		quit(1)
		return
	var out_dir := String(manifest.get("out_dir", ""))
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir.path_join("half"))
	print(
		"PD| view | mean ref | mean mine | max ch d | dark10 ref/mine/d | bright10 ref/mine/d"
		+ " | >2 % | on scatter % | on ground % | ground mean |d|"
	)
	for pair: Dictionary in manifest.get("pairs", []):
		print(_compare(pair, out_dir, int(manifest.get("dilate_px", 6))))
	quit(0)


static func _load(path: String) -> Image:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img != null:
		img.convert(Image.FORMAT_RGB8)
	return img


static func _compare(pair: Dictionary, out_dir: String, dilate: int) -> String:
	var view := String(pair.get("view", "?"))
	var a := _load(String(pair.get("ref", "")))
	var b := _load(String(pair.get("mine", "")))
	if a == null or b == null or a.get_size() != b.get_size():
		return "PD| %s | could not load both at one size" % view
	var w := a.get_width()
	var h := a.get_height()
	var n := w * h
	var bare := _load(String(pair.get("bare", "")))
	var mask := PackedByteArray()
	mask.resize(n)
	if bare != null and bare.get_size() == b.get_size():
		mask = _dilate(_differs(b.get_data(), bare.get_data(), n), w, h, dilate)
	var da := a.get_data()
	var db := b.get_data()
	# Per-channel sums as 64-bit floats (a Vector3 is 32-bit and loses levels over 2 M pixels).
	var sums := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	var hist_a := PackedInt64Array()
	var hist_b := PackedInt64Array()
	hist_a.resize(2551)
	hist_b.resize(2551)
	var over := 0
	var over_scatter := 0
	var ground := 0
	var ground_abs := 0.0
	var max_d := 0
	var diff := PackedByteArray()
	diff.resize(n * 3)
	for i in n:
		var k := i * 3
		var ra := da[k]
		var ga := da[k + 1]
		var ba := da[k + 2]
		var rb := db[k]
		var gb := db[k + 1]
		var bb := db[k + 2]
		sums[0] += ra
		sums[1] += ga
		sums[2] += ba
		sums[3] += rb
		sums[4] += gb
		sums[5] += bb
		var la := (2126 * ra + 7152 * ga + 722 * ba) / 1000
		hist_a[la] += 1
		hist_b[(2126 * rb + 7152 * gb + 722 * bb) / 1000] += 1
		var d := maxi(maxi(absi(ra - rb), absi(ga - gb)), absi(ba - bb))
		max_d = maxi(max_d, d)
		var on_scatter := mask[i] != 0
		if not on_scatter:
			ground += 1
			ground_abs += d
		# A dimmed reference underneath; a differing pixel grey on scatter, red on ground.
		var px := Vector3i(la / 50, la / 50, la / 50)
		if d > OVER:
			over += 1
			var v := mini(255, 60 + d * 4)
			if on_scatter:
				over_scatter += 1
				px = Vector3i(v, v, v)
			else:
				px = Vector3i(255, mini(255, d * 2), mini(255, d * 2))
		diff[k] = px.x
		diff[k + 1] = px.y
		diff[k + 2] = px.z
	var mean_a := Vector3(sums[0], sums[1], sums[2]) / n
	var mean_b := Vector3(sums[3], sums[4], sums[5]) / n
	var dmean := (mean_b - mean_a).abs()
	var dark_a := _tenth(hist_a, n, false)
	var dark_b := _tenth(hist_b, n, false)
	var bright_a := _tenth(hist_a, n, true)
	var bright_b := _tenth(hist_b, n, true)
	if pair.has("save_as") and out_dir != "":
		var diff_img := Image.create_from_data(w, h, false, Image.FORMAT_RGB8, diff)
		_write(String(pair.save_as), a, b, diff_img, out_dir)
	return (
		"PD| %s | %s | %s | %.2f | %.2f/%.2f/%+.2f | %.2f/%.2f/%+.2f | %.2f | %.2f | %.2f | %.3f (max %d)"
		% [
			view,
			_rgb(mean_a),
			_rgb(mean_b),
			maxf(maxf(dmean.x, dmean.y), dmean.z),
			dark_a,
			dark_b,
			dark_b - dark_a,
			bright_a,
			bright_b,
			bright_b - bright_a,
			100.0 * over / n,
			100.0 * over_scatter / n,
			100.0 * (over - over_scatter) / n,
			ground_abs / maxi(ground, 1),
			max_d,
		]
	)


static func _rgb(c: Vector3) -> String:
	return "%.2f,%.2f,%.2f" % [c.x, c.y, c.z]


## The mean luma (0-255) of the darkest or brightest tenth of the pixels, from a histogram
## of luma in tenths of a level.
static func _tenth(hist: PackedInt64Array, n: int, bright: bool) -> float:
	var want := n / 10
	var left := want
	var total := 0.0
	for j in hist.size():
		var bin := hist.size() - 1 - j if bright else j
		var take := mini(hist[bin], left)
		total += take * bin / 10.0
		left -= take
		if left <= 0:
			break
	return total / maxi(want, 1)


static func _differs(x: PackedByteArray, y: PackedByteArray, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	for i in n:
		var k := i * 3
		var d := maxi(maxi(absi(x[k] - y[k]), absi(x[k + 1] - y[k + 1])), absi(x[k + 2] - y[k + 2]))
		out[i] = 1 if d > OVER else 0
	return out


## A square dilation by `r` pixels: per axis, a pixel is set when a set pixel lies within `r`
## along it, found from the distance to the last set pixel on each side.
static func _dilate(m: PackedByteArray, w: int, h: int, r: int) -> PackedByteArray:
	return _dilate_axis(_dilate_axis(m, w, h, r, true), w, h, r, false)


static func _dilate_axis(m: PackedByteArray, w: int, h: int, r: int, rows: bool) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(w * h)
	var lines := h if rows else w
	var length := w if rows else h
	var step := 1 if rows else w
	for line in lines:
		var start := line * w if rows else line
		var since := r + 1
		for t in length:
			var i := start + t * step
			since = 0 if m[i] != 0 else since + 1
			if since <= r:
				out[i] = 1
		since = r + 1
		for t in range(length - 1, -1, -1):
			var i := start + t * step
			since = 0 if m[i] != 0 else since + 1
			if since <= r:
				out[i] = 1
	return out


static func _write(name: String, a: Image, b: Image, diff: Image, out_dir: String) -> void:
	b.save_png(out_dir.path_join(name + ".png"))
	diff.save_png(out_dir.path_join("diff_%s.png" % name))
	var hw := a.get_width() / 2
	var hh := a.get_height() / 2
	var sheet := Image.create(hw * 3, hh, false, Image.FORMAT_RGB8)
	var x := 0
	for img: Image in [a, b, diff]:
		var half := img.duplicate() as Image
		half.resize(hw, hh, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(half, Rect2i(0, 0, hw, hh), Vector2i(x, 0))
		if img == b:
			half.save_png(out_dir.path_join("half/%s.png" % name))
		elif img == diff:
			half.save_png(out_dir.path_join("half/diff_%s.png" % name))
		x += hw
	sheet.save_png(out_dir.path_join("half/sheet_%s.png" % name))
