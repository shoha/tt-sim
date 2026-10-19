extends RefCounted

## Render-job probe (`call` op): tiles a job's captures into one contact sheet, so a set of
## looks (one landform's seeds side by side, say) is judged in one image and sameness across
## them shows at a glance. step:
##   dir      the folder the captures are in (the job's out_dir as a path: "user://...")
##   names    capture names in reading order (each `<name>.png`, the composited window; a
##            missing one leaves its tile blank); an absolute name ("user://render_jobs/other/
##            x") is read from there, so another job's captures can sit beside this one's
##   columns  tiles per row (default 3)
##   tile     [width, height] of a tile in pixels (default [640, 360]); a capture keeps its
##            aspect, fitted and centred in its tile
##   crop     [x, y, width, height], fractions of each capture: only that part is tiled (the
##            middle of a look, say; default the whole capture)
##   crops    one crop (or null for the whole) per name, in the names' order, over `crop`: a
##            sheet whose rows crop differently (a 720p detail under the 1080p frames)
##   out      the sheet's name, written as `<out>.png` in `dir`
## A GAP_PX dark gutter separates the tiles. Returns the sheet's path and the tiles filled.

const GAP_PX := 4
const BACKGROUND := Color(0.1, 0.1, 0.12)


static func run(_base: Node, step: Dictionary) -> String:
	var dir := String(step.get("dir", ""))
	var names: Array = step.get("names", [])
	var columns := maxi(1, int(step.get("columns", 3)))
	var tile_size: Array = step.get("tile", [640, 360])
	var tile := Vector2i(int(tile_size[0]), int(tile_size[1]))
	var rows := maxi(1, ceili(float(names.size()) / columns))
	var sheet := Image.create(
		columns * (tile.x + GAP_PX) - GAP_PX, rows * (tile.y + GAP_PX) - GAP_PX, false, Image.FORMAT_RGB8
	)
	sheet.fill(BACKGROUND)
	var filled := 0
	for k in names.size():
		var name := String(names[k])
		var path := (name if name.is_absolute_path() else dir.path_join(name)) + ".png"
		if not FileAccess.file_exists(path):
			continue
		var image := Image.load_from_file(path)
		if image == null or image.is_empty():
			continue
		image.convert(Image.FORMAT_RGB8)
		var crops: Array = step.get("crops", [])
		var crop: Variant = crops[k] if k < crops.size() else step.get("crop", null)
		if crop is Array:
			var c: Array = crop
			var full := Vector2(image.get_size())
			var from := Vector2i(Vector2(float(c[0]), float(c[1])) * full)
			var span := Vector2i(Vector2(float(c[2]), float(c[3])) * full)
			image = image.get_region(Rect2i(from, span))
		var fit := minf(float(tile.x) / image.get_width(), float(tile.y) / image.get_height())
		var size := Vector2i(roundi(image.get_width() * fit), roundi(image.get_height() * fit))
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
		var cell := Vector2i(k % columns, floori(float(k) / columns))
		var at := cell * (tile + Vector2i(GAP_PX, GAP_PX)) + (tile - size) / 2
		sheet.blit_rect(image, Rect2i(Vector2i.ZERO, size), at)
		filled += 1
	var out := dir.path_join(String(step.get("out", "sheet")) + ".png")
	sheet.save_png(out)
	return "sheet %s: %d of %d tiles" % [out, filled, names.size()]
