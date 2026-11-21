extends SceneTree

## The water corpus's frame detectors (docs/systems/water.md "The water corpus"). Headless:
##   godot --headless --path <project> --script res://tools/render_jobs/water_corpus_detect.gd -- <dir> [--selftest <stem>]
## `<dir>` holds a corpus render (jobs/water_corpus.json): per layout view `<name>_t_sub.png` (wet),
## `<name>_td_sub.png` (the same view with the water hidden), `<name>_t_aux.png` and
## `<name>_t_meta.json` (probes/water_corpus.gd `aux`: the field projected through the camera), and
## the same with `_o` for the oblique view. Writes `scores.tsv` (one row per view), `flags.md` (the
## views a detector flagged) and contact sheets `sheet_<n>.png` (top and oblique per layout, the
## flagged places boxed in red, each tile numbered; `sheets.md` names them).
##
## The detectors are guardrails for covering many layouts, not the verdict: read the sheets.
##   ticks        small isolated white marks where a stream meets a pond (a mouth), against the
##                same count elsewhere on the water.
##   ring_gaps    sectors of a pond's shore band with far less white than the ring's median.
##   xflow_white  long thin white marks lying across the flow of a river (a curl, a seam).
##   tone_seams   a step of the blurred lightness along the flow, standing across the channel.
##   occ_white    the share of white in the water pixels touching something that hides water the
##                field holds (an occluder's silhouette).
##   holes        places the field holds water (0.3 m from any shore) and the frame shows none.
##   slivers      detached scraps of drawn water under 0.15 m2.
##   pale, flat   a body of drawn water with almost no colour, or with no marks at all.
## `--selftest <stem>` plants each defect in that (good) view and checks its detector fires.

const MASK_DIFF := 12
const WHITE_MIN := 200
const WHITE_SPREAD := 44
const DIGITS := [
	"111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
	"111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111",
]

var _w := 0
var _h := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: -- <dir> [--selftest <stem>]")
		quit(1)
		return
	var dir := String(args[0])
	if args.size() >= 3 and args[1] == "--selftest":
		quit(0 if _selftest(dir, String(args[2])) else 1)
		return
	_score_all(dir)
	quit(0)


func _score_all(dir: String) -> void:
	var stems := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		if file.ends_with("_meta.json"):
			stems.append(file.trim_suffix("_meta.json"))
	stems.sort()
	var keys := [
		"ticks_mouth", "ticks_other", "ring_gaps", "ring_cover", "xflow_white", "tone_seams",
		"occ_band", "occ_white", "holes", "hole_m2", "slivers", "pale", "flat", "min_chroma",
		"min_std", "water_m2", "white_share",
	]
	var rows := PackedStringArray(["view\tmap\t" + "\t".join(keys) + "\tflags"])
	var flagged := PackedStringArray()
	var tiles: Array[Dictionary] = []
	for stem in stems:
		var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(stem + "_meta.json")))
		var variants := [""]
		for extra: String in ["_nolap", "_nowhite", "_noedge", "_p2", "_old"]:
			if FileAccess.file_exists(dir.path_join(stem + extra + "_sub.png")):
				variants.append(extra)
		for variant: String in variants:
			var wet := Image.load_from_file(dir.path_join(stem + variant + "_sub.png"))
			var dry := Image.load_from_file(dir.path_join(stem + "d_sub.png"))
			var aux := Image.load_from_file(dir.path_join(stem + "_aux.png"))
			if wet == null or dry == null or aux == null:
				continue
			var r := analyse(wet, dry, aux, float(meta.px_per_m), String(meta.map))
			var cells := PackedStringArray()
			for k: String in keys:
				cells.append(str(snappedf(float(r[k]), 0.001)))
			var flags: PackedStringArray = r.flags
			rows.append("%s%s\t%s\t%s\t%s" % [stem, variant, meta.map, "\t".join(cells), ",".join(flags)])
			if not flags.is_empty():
				flagged.append("- `%s%s` (%s): %s" % [stem, variant, meta.map, ", ".join(flags)])
			if variant == "":
				tiles.append({"stem": stem, "map": meta.map, "boxes": r.boxes, "flags": flags})
			print("DETECT| %s%s %s" % [stem, variant, ",".join(flags)])
	_store(dir.path_join("scores.tsv"), "\n".join(rows))
	_store(dir.path_join("flags.md"), "# Views a detector flagged\n\n" + "\n".join(flagged) + "\n")
	_sheets(dir, tiles)


func _store(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)


## The scores of one view: `wet` and `dry` the captures, `aux` the projected field, `px_per_m` the
## view's scale, `map` the corpus map ("wood" holds occluders, so what hides water is no hole).
## Returns the score keys of `scores.tsv`, "flags" and "boxes" (Rect2i per flagged place).
func analyse(wet: Image, dry: Image, aux: Image, px_per_m: float, map: String) -> Dictionary:
	wet.convert(Image.FORMAT_RGB8)
	dry.convert(Image.FORMAT_RGB8)
	aux.convert(Image.FORMAT_RGBA8)
	_w = wet.get_width()
	_h = wet.get_height()
	if aux.get_width() != _w or aux.get_height() != _h:
		aux.resize(_w, _h, Image.INTERPOLATE_NEAREST)
	var wd := wet.get_data()
	var dd := dry.get_data()
	var ad := aux.get_data()
	var n := _w * _h
	var mask := PackedByteArray()
	mask.resize(n)
	var white := PackedByteArray()
	white.resize(n)
	var occl := PackedByteArray()
	occl.resize(n)
	var lum := PackedFloat32Array()
	lum.resize(n)
	var mask_n := 0
	var white_n := 0
	for i in n:
		var r := wd[i * 3]
		var g := wd[i * 3 + 1]
		var b := wd[i * 3 + 2]
		lum[i] = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
		var diff := maxi(maxi(absi(r - dd[i * 3]), absi(g - dd[i * 3 + 1])), absi(b - dd[i * 3 + 2]))
		if diff > MASK_DIFF:
			mask[i] = 1
			mask_n += 1
			var lo := mini(r, mini(g, b))
			if lo > WHITE_MIN and maxi(r, maxi(g, b)) - lo < WHITE_SPREAD:
				white[i] = 1
				white_n += 1
		elif ad[i * 4 + 3] > 0 and ad[i * 4 + 1] > 38:
			occl[i] = 1
	var out := {"flags": PackedStringArray(), "boxes": []}
	var m2 := 1.0 / (px_per_m * px_per_m)
	out["water_m2"] = mask_n * m2
	out["white_share"] = float(white_n) / maxf(mask_n, 1.0)
	_whites(out, white, ad, px_per_m)
	_ring(out, white, mask, ad)
	_seams(out, lum, mask, ad, px_per_m)
	_occluders(out, occl, mask, white, px_per_m, map)
	_bodies(out, mask, white, wd, px_per_m)
	return out


## Connected components (8 neighbours) of `flags`: {"labels" (per pixel, 0 none), "comps": [{"n",
## "cx", "cy", "major", "minor" (px), "angle" (of the major axis), "rect", "first"}]}.
func _components(flags: PackedByteArray) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(flags.size())
	var comps: Array[Dictionary] = []
	var stack := PackedInt32Array()
	for start in flags.size():
		if flags[start] == 0 or labels[start] != 0:
			continue
		var id := comps.size() + 1
		labels[start] = id
		stack.clear()
		stack.append(start)
		var cnt := 0
		var sx := 0.0
		var sy := 0.0
		var sxx := 0.0
		var syy := 0.0
		var sxy := 0.0
		var x0 := _w
		var y0 := _h
		var x1 := 0
		var y1 := 0
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			var x := i % _w
			var y := i / _w
			cnt += 1
			sx += x
			sy += y
			sxx += x * x
			syy += y * y
			sxy += x * y
			x0 = mini(x0, x)
			y0 = mini(y0, y)
			x1 = maxi(x1, x)
			y1 = maxi(y1, y)
			for dy in range(-1, 2):
				var ny := y + dy
				if ny < 0 or ny >= _h:
					continue
				for dx in range(-1, 2):
					var nx := x + dx
					if nx < 0 or nx >= _w:
						continue
					var j := ny * _w + nx
					if flags[j] != 0 and labels[j] == 0:
						labels[j] = id
						stack.append(j)
		var mx := sx / cnt
		var my := sy / cnt
		var cxx := sxx / cnt - mx * mx
		var cyy := syy / cnt - my * my
		var cxy := sxy / cnt - mx * my
		var mid := 0.5 * (cxx + cyy)
		var rad := sqrt(maxf(0.25 * (cxx - cyy) * (cxx - cyy) + cxy * cxy, 0.0))
		comps.append(
			{
				"n": cnt,
				"cx": mx,
				"cy": my,
				"major": sqrt(12.0 * maxf(mid + rad, 0.0)) + 1.0,
				"minor": sqrt(12.0 * maxf(mid - rad, 0.0)) + 1.0,
				"angle": 0.5 * atan2(2.0 * cxy, cxx - cyy),
				"rect": Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1),
				"first": start,
			}
		)
	return {"labels": labels, "comps": comps}


## The angle between two undirected directions (0 .. PI / 2).
func _apart(a: float, b: float) -> float:
	return absf(fposmod(a - b + PI * 0.5, PI) - PI * 0.5)


## Ticks at mouths and white marks across the flow.
func _whites(out: Dictionary, white: PackedByteArray, ad: PackedByteArray, px_per_m: float) -> void:
	# A coarse grid of 0.6 m cells: a mouth cell has pond and river water within one cell.
	var cell := maxi(2, roundi(0.6 * px_per_m))
	var gw := _w / cell + 1
	var gh := _h / cell + 1
	var kind := PackedByteArray()
	kind.resize(gw * gh)
	for y in range(0, _h, 2):
		for x in range(0, _w, 2):
			var a := (y * _w + x) * 4
			if ad[a + 3] == 0:
				continue
			kind[(y / cell) * gw + x / cell] |= 1 if ad[a + 2] < 150 else 2
	var mouth := PackedByteArray()
	mouth.resize(gw * gh)
	var mouth_cells := 0
	for gy in gh:
		for gx in gw:
			var seen := 0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var qx := gx + dx
					var qy := gy + dy
					if qx >= 0 and qy >= 0 and qx < gw and qy < gh:
						seen |= kind[qy * gw + qx]
			if seen == 3:
				mouth[gy * gw + gx] = 1
				mouth_cells += 1
	var found := _components(white)
	var ticks_mouth := 0
	var ticks_other := 0
	var across := 0
	for c: Dictionary in found.comps:
		var major_m: float = c.major / px_per_m
		var minor_m: float = c.minor / px_per_m
		var first: int = c.first
		var in_mouth := mouth[((first / _w) / cell) * gw + (first % _w) / cell] == 1
		if int(c.n) >= 3 and major_m >= 0.12 and major_m <= 0.9:
			if in_mouth:
				ticks_mouth += 1
				out.boxes.append(c.rect)
			else:
				ticks_other += 1
		var a := first * 4
		var river := ad[a + 3] > 0 and ad[a + 2] > 150 and ad[a + 2] < 215
		if river and ad[a] > 0 and ad[a + 1] > 25 and major_m >= 0.8 and minor_m <= 0.35 * major_m:
			var flow := (ad[a] - 1.0) / 254.0 * PI
			if _apart(float(c.angle), flow) > deg_to_rad(35.0):
				across += 1
				out.boxes.append(c.rect)
	out["ticks_mouth"] = ticks_mouth
	out["ticks_other"] = ticks_other
	out["xflow_white"] = across
	var mouth_m2 := mouth_cells * 0.36
	var other_m2 := maxf(float(out.water_m2) - mouth_m2, 1.0)
	# Measured on the first corpus render: 11, 7 and 5 at joined mouths, 0 on a pond alone and on
	# a pond whose streams stop short of it.
	out["tick_density"] = ticks_mouth / maxf(mouth_m2, 1.0) - (ticks_other + 1.0) / other_m2
	if ticks_mouth >= 4:
		out.flags.append("ticks")
	if across > 0:
		out.flags.append("xflow_white")


## A pond's foam ring by sector: the white share of its shore band (0.05 to 0.45 m from the
## waterline) in 24 sectors about the pond pixels' centroid.
func _ring(out: Dictionary, white: PackedByteArray, mask: PackedByteArray, ad: PackedByteArray) -> void:
	var sx := 0.0
	var sy := 0.0
	var cnt := 0
	for y in range(0, _h, 2):
		for x in range(0, _w, 2):
			var a := (y * _w + x) * 4
			if ad[a + 3] > 0 and ad[a + 2] < 150:
				sx += x
				sy += y
				cnt += 1
	out["ring_gaps"] = 0
	out["ring_cover"] = 0.0
	if cnt < 200:
		return
	var c := Vector2(sx / cnt, sy / cnt)
	var band := PackedInt32Array()
	band.resize(24)
	var lit := PackedInt32Array()
	lit.resize(24)
	for y in _h:
		for x in _w:
			var i := y * _w + x
			var a := i * 4
			if ad[a + 3] == 0 or ad[a + 2] >= 150 or ad[a + 1] < 6 or ad[a + 1] > 57 or mask[i] == 0:
				continue
			var s := int(fposmod(atan2(y - c.y, x - c.x), TAU) / TAU * 24.0) % 24
			band[s] += 1
			lit[s] += white[i]
	var covers := PackedFloat32Array()
	for s in 24:
		if band[s] >= 20:
			covers.append(float(lit[s]) / band[s])
	if covers.size() < 12:
		return
	var sorted := covers.duplicate()
	sorted.sort()
	var median := sorted[sorted.size() / 2]
	var gaps := 0
	for v in covers:
		if median > 0.1 and v < 0.35 * median:
			gaps += 1
	out["ring_gaps"] = gaps
	out["ring_cover"] = median
	if gaps > 0:
		out.flags.append("cut_ring")


## A step of the blurred lightness along the flow, standing across a river's channel.
func _seams(
	out: Dictionary, lum: PackedFloat32Array, mask: PackedByteArray, ad: PackedByteArray, px_per_m: float
) -> void:
	# Box blur by an integral image, radius 0.15 m.
	var rb := maxi(1, roundi(0.15 * px_per_m))
	var integral := PackedFloat32Array()
	integral.resize((_w + 1) * (_h + 1))
	for y in _h:
		var row := 0.0
		for x in _w:
			row += lum[y * _w + x]
			integral[(y + 1) * (_w + 1) + x + 1] = integral[y * (_w + 1) + x + 1] + row
	var blur := func(x: int, y: int) -> float:
		var x0 := maxi(x - rb, 0)
		var y0 := maxi(y - rb, 0)
		var x1 := mini(x + rb + 1, _w)
		var y1 := mini(y + rb + 1, _h)
		var sum := (
			integral[y1 * (_w + 1) + x1]
			- integral[y0 * (_w + 1) + x1]
			- integral[y1 * (_w + 1) + x0]
			+ integral[y0 * (_w + 1) + x0]
		)
		return sum / ((x1 - x0) * (y1 - y0))
	var marks := PackedByteArray()
	marks.resize(_w * _h)
	var d := 0.3 * px_per_m
	for y in range(0, _h, 2):
		for x in range(0, _w, 2):
			var i := y * _w + x
			var a := i * 4
			if mask[i] == 0 or ad[a + 3] == 0 or ad[a] == 0 or ad[a + 2] < 150 or ad[a + 2] > 215 or ad[a + 1] < 25:
				continue
			var flow := (ad[a] - 1.0) / 254.0 * PI
			var fx := cos(flow) * d
			var fy := sin(flow) * d
			var ax := int(x + fx)
			var ay := int(y + fy)
			var bx := int(x - fx)
			var by := int(y - fy)
			if ax < 0 or ay < 0 or bx < 0 or by < 0 or ax >= _w or ay >= _h or bx >= _w or by >= _h:
				continue
			var ia := ay * _w + ax
			var ib := by * _w + bx
			if mask[ia] == 0 or mask[ib] == 0 or ad[ia * 4 + 2] != ad[a + 2] or ad[ib * 4 + 2] != ad[a + 2]:
				continue
			if absf(blur.call(ax, ay) - blur.call(bx, by)) > 0.085:
				# The stride's 2 x 2 block, so neighbours on the stride grid connect.
				marks[i] = 1
				if x + 1 < _w:
					marks[i + 1] = 1
				if y + 1 < _h:
					marks[i + _w] = 1
					if x + 1 < _w:
						marks[i + _w + 1] = 1
	var seams := 0
	for c: Dictionary in _components(marks).comps:
		var a := int(c.first) * 4
		var flow := (ad[a] - 1.0) / 254.0 * PI
		if float(c.major) / px_per_m >= 0.7 and _apart(float(c.angle), flow) > deg_to_rad(50.0):
			seams += 1
			out.boxes.append(c.rect)
	out["tone_seams"] = seams
	if seams > 0:
		out.flags.append("tone_seam")


## Holes (or, on the wood map, occluders and the white along their silhouettes).
func _occluders(
	out: Dictionary, occl: PackedByteArray, mask: PackedByteArray, white: PackedByteArray, px_per_m: float, map: String
) -> void:
	var band := 0
	var lit := 0
	for y in range(2, _h - 2):
		for x in range(2, _w - 2):
			var i := y * _w + x
			if mask[i] == 0:
				continue
			if (
				occl[i - 1] + occl[i + 1] + occl[i - _w] + occl[i + _w] + occl[i - 2] + occl[i + 2]
				+ occl[i - 2 * _w] + occl[i + 2 * _w] > 0
			):
				band += 1
				lit += white[i]
	out["occ_band"] = band
	out["occ_white"] = float(lit) / maxf(band, 1.0)
	var holes := 0
	var hole_px := 0
	var least := 0.05 * px_per_m * px_per_m
	for c: Dictionary in _components(occl).comps:
		if int(c.n) >= least:
			holes += 1
			hole_px += int(c.n)
			if map != "wood":
				out.boxes.append(c.rect)
	out["holes"] = holes
	out["hole_m2"] = hole_px / (px_per_m * px_per_m)
	if map == "wood":
		if band >= 150 and float(out.occ_white) > maxf(0.25, 3.0 * float(out.white_share)):
			out.flags.append("occluder_outline")
	elif holes > 0:
		out.flags.append("holes")


## Slivers, and each body's colour and marks.
func _bodies(out: Dictionary, mask: PackedByteArray, white: PackedByteArray, wd: PackedByteArray, px_per_m: float) -> void:
	var found := _components(mask)
	var labels: PackedInt32Array = found.labels
	var count: int = found.comps.size()
	var sum_c := PackedFloat32Array()
	sum_c.resize(count + 1)
	var sum_l := PackedFloat32Array()
	sum_l.resize(count + 1)
	var sum_ll := PackedFloat32Array()
	sum_ll.resize(count + 1)
	var plain := PackedInt32Array()
	plain.resize(count + 1)
	for i in labels.size():
		var id := labels[i]
		if id == 0 or white[i] == 1:
			continue
		var r := wd[i * 3]
		var g := wd[i * 3 + 1]
		var b := wd[i * 3 + 2]
		var l := (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0
		sum_c[id] += (maxi(r, maxi(g, b)) - mini(r, mini(g, b))) / 255.0
		sum_l[id] += l
		sum_ll[id] += l * l
		plain[id] += 1
	var slivers := 0
	var pale := 0
	var flat := 0
	var min_chroma := 1.0
	var min_std := 1.0
	var m2 := 1.0 / (px_per_m * px_per_m)
	for k in count:
		var c: Dictionary = found.comps[k]
		var area := int(c.n) * m2
		# A scrap of drawn water, not one of the lap's detached white dashes (those are by design).
		if int(c.n) >= 4 and area < 0.15 and plain[k + 1] * 2 > int(c.n):
			slivers += 1
			out.boxes.append(c.rect)
		if area < 1.0 or plain[k + 1] < 50:
			continue
		var cnt := float(plain[k + 1])
		var chroma := sum_c[k + 1] / cnt
		var mean := sum_l[k + 1] / cnt
		var std := sqrt(maxf(sum_ll[k + 1] / cnt - mean * mean, 0.0))
		min_chroma = minf(min_chroma, chroma)
		min_std = minf(min_std, std)
		if chroma < 0.1:
			pale += 1
			out.boxes.append(c.rect)
		if std < 0.012:
			flat += 1
			out.boxes.append(c.rect)
	out["slivers"] = slivers
	out["pale"] = pale
	out["flat"] = flat
	out["min_chroma"] = min_chroma
	out["min_std"] = min_std
	if slivers > 0:
		out.flags.append("slivers")
	if pale > 0:
		out.flags.append("pale")
	if flat > 0:
		out.flags.append("flat")


## Contact sheets: eight layouts each, the top view beside the oblique one, numbered.
func _sheets(dir: String, tiles: Array[Dictionary]) -> void:
	var tops: Array[Dictionary] = []
	for t in tiles:
		if String(t.stem).ends_with("_t"):
			tops.append(t)
	var tile := Vector2i(400, 225)
	var notes := PackedStringArray(["# Corpus sheets (each row: top view, oblique view, twice)", ""])
	var per := 8
	for s in range(0, tops.size(), per):
		var rows := ceili(mini(per, tops.size() - s) / 2.0)
		var sheet := Image.create(tile.x * 4 + 6, rows * (tile.y + 2), false, Image.FORMAT_RGB8)
		sheet.fill(Color(0.1, 0.1, 0.12))
		notes.append("## sheet_%d.png" % (s / per))
		for k in mini(per, tops.size() - s):
			var t: Dictionary = tops[s + k]
			var name := String(t.stem).trim_suffix("_t")
			var at := Vector2i((k % 2) * (tile.x * 2 + 4), (k / 2) * (tile.y + 2))
			var top := Image.load_from_file(dir.path_join(name + "_t_sub.png"))
			var obl := Image.load_from_file(dir.path_join(name + "_o_sub.png"))
			if top == null:
				continue
			var scale := float(tile.x) / top.get_width()
			top.convert(Image.FORMAT_RGB8)
			top.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
			for box: Rect2i in t.boxes:
				_frame(top, Rect2i(Vector2i(Vector2(box.position) * scale) - Vector2i(3, 3), Vector2i(Vector2(box.size) * scale) + Vector2i(6, 6)))
			_number(top, s + k)
			sheet.blit_rect(top, Rect2i(Vector2i.ZERO, tile), at)
			if obl != null:
				obl.convert(Image.FORMAT_RGB8)
				obl.resize(tile.x, tile.y, Image.INTERPOLATE_BILINEAR)
				sheet.blit_rect(obl, Rect2i(Vector2i.ZERO, tile), at + Vector2i(tile.x + 2, 0))
			var obl_flags := PackedStringArray()
			for other in tiles:
				if other.stem == name + "_o":
					obl_flags = other.flags
			notes.append("- %d `%s` (%s): top [%s] oblique [%s]" % [s + k, name, t.map, ", ".join(t.flags), ", ".join(obl_flags)])
		sheet.save_png(dir.path_join("sheet_%d.png" % (s / per)))
		notes.append("")
	_store(dir.path_join("sheets.md"), "\n".join(notes))


func _frame(img: Image, rect: Rect2i) -> void:
	var r := rect.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if not r.has_area():
		return
	var red := Color(1.0, 0.1, 0.1)
	img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, 1)), red)
	img.fill_rect(Rect2i(r.position + Vector2i(0, r.size.y - 1), Vector2i(r.size.x, 1)), red)
	img.fill_rect(Rect2i(r.position, Vector2i(1, r.size.y)), red)
	img.fill_rect(Rect2i(r.position + Vector2i(r.size.x - 1, 0), Vector2i(1, r.size.y)), red)


func _number(img: Image, value: int) -> void:
	var text := str(value)
	img.fill_rect(Rect2i(2, 2, text.length() * 16 + 4, 24), Color(0, 0, 0))
	for k in text.length():
		var glyph: String = DIGITS[int(text[k])]
		for j in 15:
			if glyph[j] == "1":
				img.fill_rect(Rect2i(4 + k * 16 + (j % 3) * 4, 4 + (j / 3) * 4, 4, 4), Color(1, 1, 0.3))


## Plants each defect in the (good) view `stem` and checks its detector: returns true when the
## clean view raises none of them and every planted one is found.
func _selftest(dir: String, stem: String) -> bool:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(stem + "_meta.json")))
	var ppm := float(meta.px_per_m)
	var dry := Image.load_from_file(dir.path_join(stem + "d_sub.png"))
	var aux := Image.load_from_file(dir.path_join(stem + "_aux.png"))
	var load_wet := func() -> Image:
		var img := Image.load_from_file(dir.path_join(stem + "_sub.png"))
		img.convert(Image.FORMAT_RGB8)
		return img
	aux.convert(Image.FORMAT_RGBA8)
	var base := analyse(load_wet.call(), dry, aux, ppm, "flat")
	print("SELFTEST| clean %s flags %s" % [stem, base.flags])
	# A river pixel well inside the channel, nearest the frame's middle, and its flow.
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in range(0, aux.get_height(), 3):
		for x in range(0, aux.get_width(), 3):
			var c := aux.get_pixel(x, y)
			if c.a > 0.5 and c.r8 > 0 and c.b8 > 150 and c.b8 < 215 and c.g8 > 60:
				var dist := Vector2(x, y).distance_to(Vector2(aux.get_size()) * 0.5)
				if dist < best_d:
					best_d = dist
					best = Vector2i(x, y)
	if best.x < 0:
		print("SELFTEST| no river pixel in %s" % stem)
		return false
	var flow := (aux.get_pixel(best.x, best.y).r8 - 1.0) / 254.0 * PI
	var along := Vector2.from_angle(flow)
	var side := along.orthogonal()
	var ok := true
	# 1. A white bar across the flow, 1.2 m by 0.12 m.
	var img: Image = load_wet.call()
	for s in range(-int(0.45 * ppm), int(0.45 * ppm)):
		for t in range(-int(0.06 * ppm), int(0.06 * ppm) + 1):
			var p := Vector2i(Vector2(best) + side * s + along * t)
			img.set_pixel(p.x, p.y, Color(0.96, 0.98, 0.98))
	var r := analyse(img, dry, aux, ppm, "flat")
	ok = _expect(r, "xflow_white", "white bar across the flow") and ok
	ok = _expect(r, "tone_seam", "white bar across the flow (as a seam)") and ok
	# 2. A hole: the dry frame shows through a 0.4 m disc.
	img = load_wet.call()
	var dry_rgb := dry.duplicate() as Image
	dry_rgb.convert(Image.FORMAT_RGB8)
	var rad := int(0.4 * ppm)
	for y in range(-rad, rad + 1):
		for x in range(-rad, rad + 1):
			if x * x + y * y <= rad * rad:
				img.set_pixel(best.x + x, best.y + y, dry_rgb.get_pixel(best.x + x, best.y + y))
	ok = _expect(analyse(img, dry, aux, ppm, "flat"), "holes", "hole") and ok
	# 3. A tone step: everything downstream of the pixel 0.13 darker. 4. Pale. 5. Flat.
	var step_img: Image = load_wet.call()
	var pale_img: Image = load_wet.call()
	var flat_img: Image = load_wet.call()
	for y in step_img.get_height():
		for x in step_img.get_width():
			var c := step_img.get_pixel(x, y)
			var under := dry_rgb.get_pixel(x, y)
			if maxf(absf(c.r - under.r), maxf(absf(c.g - under.g), absf(c.b - under.b))) < 0.05:
				continue
			if (Vector2(x, y) - Vector2(best)).dot(along) > 0.0:
				step_img.set_pixel(x, y, Color(c.r - 0.13, c.g - 0.13, c.b - 0.13))
			var grey := (c.r + c.g + c.b) / 3.0
			pale_img.set_pixel(x, y, Color(lerpf(c.r, grey, 0.9), lerpf(c.g, grey, 0.9), lerpf(c.b, grey, 0.9)))
			flat_img.set_pixel(x, y, Color(0.2, 0.5, 0.7))
	ok = _expect(analyse(step_img, dry, aux, ppm, "flat"), "tone_seam", "tone step across the flow") and ok
	ok = _expect(analyse(pale_img, dry, aux, ppm, "flat"), "pale", "pale body") and ok
	ok = _expect(analyse(flat_img, dry, aux, ppm, "flat"), "flat", "flat body") and ok
	for f: String in ["xflow_white", "tone_seam", "holes", "pale", "flat"]:
		if (base.flags as PackedStringArray).has(f):
			print("SELFTEST| NOTE the clean view already raises %s" % f)
	print("SELFTEST| %s" % ("all planted defects found" if ok else "FAILED"))
	return ok


func _expect(r: Dictionary, flag: String, what: String) -> bool:
	var found := (r.flags as PackedStringArray).has(flag)
	print("SELFTEST| %s -> %s %s" % [what, flag, "found" if found else "MISSED"])
	return found
