extends SceneTree

## Contact sheets for the eyelook round (card SR10). Headless:
##   godot --headless --path <tt-sim> --script res://tools/eyelook_sheets.gd -- <out_dir> <job:map>...
## For each `<job>:<map>` argument it reads user://render_jobs/<job>/el_<map>_p<pitch>_y<yaw>.png
## (the window captures of the el_* jobs) and writes <out_dir>/el_<map>_sheet.png: three columns
## (pitch 0, 12, -15) by four rows (yaw 45, 135, 225, 315), 2000 px wide.

const PITCHES: Array[String] = ["p00", "p12", "pm15"]
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
		var job := parts[0]
		var map_name := parts[1]
		_sheet(out_dir, job, map_name)
	quit(0)


func _sheet(out_dir: String, job: String, map_name: String) -> void:
	var tile_w := int((SHEET_WIDTH - (PITCHES.size() - 1) * GAP) / PITCHES.size())
	var tiles: Array[Image] = []
	for yaw in YAWS:
		for pitch in PITCHES:
			var path := "user://render_jobs/%s/el_%s_%s_%s.png" % [job, map_name, pitch, yaw]
			var img := Image.load_from_file(path)
			if img == null:
				push_error("cannot load " + path)
				return
			var h := int(round(float(img.get_height()) * tile_w / img.get_width()))
			img.resize(tile_w, h, Image.INTERPOLATE_LANCZOS)
			img.convert(Image.FORMAT_RGB8)
			tiles.append(img)
	var tile_h := tiles[0].get_height()
	var sheet := Image.create(
		SHEET_WIDTH, YAWS.size() * tile_h + (YAWS.size() - 1) * GAP, false, Image.FORMAT_RGB8
	)
	sheet.fill(Color(0.1, 0.1, 0.1))
	for k in tiles.size():
		var at := Vector2i((k % PITCHES.size()) * (tile_w + GAP), (k / PITCHES.size()) * (tile_h + GAP))
		sheet.blit_rect(tiles[k], Rect2i(0, 0, tile_w, tile_h), at)
	var out := "%s/el_%s_sheet.png" % [out_dir, map_name]
	sheet.save_png(out)
	print("SHEET| %s %dx%d" % [out, sheet.get_width(), sheet.get_height()])
