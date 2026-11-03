extends SceneTree

## Contact sheets for the eyelook round (card SR10). Headless:
##   godot --headless --path <tt-sim> --script res://tools/eyelook_sheets.gd -- <out_dir> <job:map>...
## For each `<job>:<map>` argument it reads user://render_jobs/<job>/el_<map>_p<pitch>_y<yaw>.png
## (the window captures of the el_* jobs) and writes <out_dir>/el_<map>_sheet.png: three columns
## (pitch 0, 12, -15) by four rows (yaw 45, 135, 225, 315), 2000 px wide.
## A `cmp:<before_job>:<after_job>:<map>:<name>` argument writes a before/after sheet instead,
## <out_dir>/<name>.png: four rows (the yaws), columns before and after at pitch 0, then before
## and after at pitch -15 (card eyesky2).

const PITCHES: Array[String] = ["p00", "p12", "pm15"]
const CMP_COLUMNS: Array[String] = ["p00", "p00", "pm15", "pm15"]
const YAWS: Array[String] = ["y045", "y135", "y225", "y315"]
const SHEET_WIDTH := 2000
const GAP := 4


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: <out_dir> <job:map>...")
		quit(2)
		return
	var out_dir := args[0]
	for i in range(1, args.size()):
		var parts := args[i].split(":")
		if parts[0] == "cmp":
			_compare(out_dir, parts[1], parts[2], parts[3], parts[4])
		else:
			_sheet(out_dir, parts[0], parts[1])
	quit(0)


func _sheet(out_dir: String, job: String, map_name: String) -> void:
	var paths: Array[String] = []
	for yaw in YAWS:
		for pitch in PITCHES:
			paths.append("user://render_jobs/%s/el_%s_%s_%s.png" % [job, map_name, pitch, yaw])
	_write(paths, PITCHES.size(), "%s/el_%s_sheet.png" % [out_dir, map_name])


func _compare(
	out_dir: String, before: String, after: String, map_name: String, sheet_name: String
) -> void:
	var paths: Array[String] = []
	for yaw in YAWS:
		for k in CMP_COLUMNS.size():
			var job := before if k % 2 == 0 else after
			paths.append("user://render_jobs/%s/el_%s_%s_%s.png" % [job, map_name, CMP_COLUMNS[k], yaw])
	_write(paths, CMP_COLUMNS.size(), "%s/%s.png" % [out_dir, sheet_name])


## Lays the images at `paths` out row by row, `columns` to a row, and saves the sheet at `out`.
func _write(paths: Array[String], columns: int, out: String) -> void:
	var tile_w := int((SHEET_WIDTH - (columns - 1) * GAP) / columns)
	var tiles: Array[Image] = []
	for path in paths:
		var img := Image.load_from_file(path)
		if img == null:
			push_error("cannot load " + path)
			return
		var h := int(round(float(img.get_height()) * tile_w / img.get_width()))
		img.resize(tile_w, h, Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		tiles.append(img)
	var tile_h := tiles[0].get_height()
	var rows := int(ceil(float(tiles.size()) / columns))
	var sheet := Image.create(SHEET_WIDTH, rows * tile_h + (rows - 1) * GAP, false, Image.FORMAT_RGB8)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for k in tiles.size():
		var at := Vector2i((k % columns) * (tile_w + GAP), (k / columns) * (tile_h + GAP))
		sheet.blit_rect(tiles[k], Rect2i(0, 0, tile_w, tile_h), at)
	sheet.save_png(out)
	print("SHEET| %s %dx%d" % [out, sheet.get_width(), sheet.get_height()])
