extends SceneTree

## Re-encodes a library's surface maps as lossless WebP (card texwebp, 2026-11-09; the producer
## step of the board's "webp" answer). For every `<surfaces>/<name>/<kind>.png` it decodes the PNG
## the way the game does (SurfaceBake.decode: a 16-bit PNG becomes 8 bits), encodes the decoded
## pixels with Godot's own lossless WebP encoder (Image.save_webp_to_buffer(false, 1.0); the
## encoder pin is this Godot build's libwebp and the two webp_compression project settings,
## printed in the report), and checks that
## - exact: the WebP decodes to the same pixels as the PNG (in the PNG's decoded format),
## - baked_exact (height only): SurfaceBake.bake of both is byte-identical (L8, no compression),
## - deterministic: a second encode gives the same bytes.
## It writes `<kind>.webp` beside the PNG only when all three hold, and never deletes a PNG (the
## sources repo removes them with git). One JSON line per map and a summary line go to stdout.
##
## godot --headless --path <tt-sim> --script res://tools/texture_ab/webp_encode.gd --
##     --surfaces D:/dev/tabletop/core-library/surfaces [--only ash,cliff] [--dry 1] [--factor 25]

const FACTOR_SETTING := "rendering/textures/webp_compression/lossless_compression_factor"
const METHOD_SETTING := "rendering/textures/webp_compression/compression_method"


func _initialize() -> void:
	var args := _args()
	var root := String(args.get("surfaces", ""))
	if root == "" or not DirAccess.dir_exists_absolute(root):
		printerr("webp_encode: --surfaces <folder> is required")
		quit(2)
		return
	if args.has("factor"):
		ProjectSettings.set_setting(FACTOR_SETTING, float(args["factor"]))
	var only := PackedStringArray()
	if String(args.get("only", "")) != "":
		only = String(args["only"]).split(",")
	var dry := String(args.get("dry", "0")) == "1"
	var totals := {"maps": 0, "png_bytes": 0, "webp_bytes": 0, "failed": 0, "written": 0}
	var names := DirAccess.get_directories_at(root)
	names.sort()
	for name in names:
		if not only.is_empty() and not name in only:
			continue
		for kind in SurfaceBake.KINDS:
			var png := root.path_join(name).path_join(kind + ".png")
			if not FileAccess.file_exists(png):
				continue
			var row := _encode(png, kind, dry)
			row["surface"] = name
			totals["maps"] += 1
			totals["png_bytes"] += int(row.get("png_bytes", 0))
			totals["webp_bytes"] += int(row.get("webp_bytes", 0))
			totals["failed"] += 0 if row["ok"] else 1
			totals["written"] += 1 if row.get("written", false) else 0
			print(JSON.stringify(row, "", true))
	totals["engine"] = Engine.get_version_info()["string"]
	totals["factor"] = ProjectSettings.get_setting(FACTOR_SETTING)
	totals["method"] = ProjectSettings.get_setting(METHOD_SETTING)
	print("SUMMARY " + JSON.stringify(totals, "", true))
	quit(0 if totals["failed"] == 0 else 1)


func _encode(png: String, kind: String, dry: bool) -> Dictionary:
	var row := {"kind": kind, "ok": false}
	var bytes := FileAccess.get_file_as_bytes(png)
	row["png_bytes"] = bytes.size()
	var source := SurfaceBake.decode(bytes, "png")
	if source == null:
		row["error"] = "the PNG does not decode"
		return row
	var started := Time.get_ticks_msec()
	var webp := source.save_webp_to_buffer(false, 1.0)
	row["encode_ms"] = Time.get_ticks_msec() - started
	row["webp_bytes"] = webp.size()
	row["deterministic"] = source.save_webp_to_buffer(false, 1.0) == webp
	var back := SurfaceBake.decode(webp, "webp")
	if back == null:
		row["error"] = "the WebP does not decode"
		return row
	var like := back.duplicate() as Image
	if like.get_format() != source.get_format():
		like.convert(source.get_format())
	row["exact"] = like.get_data() == source.get_data()
	row["baked_exact"] = true
	if kind == "height":
		var a := SurfaceBake.bake(source, kind)
		var b := SurfaceBake.bake(back, kind)
		row["baked_exact"] = a != null and b != null and a.get_data() == b.get_data()
	row["ok"] = row["exact"] and row["baked_exact"] and row["deterministic"]
	if row["ok"] and not dry:
		var file := FileAccess.open(png.get_basename() + ".webp", FileAccess.WRITE)
		file.store_buffer(webp)
		file.close()
		row["written"] = true
	return row


func _args() -> Dictionary:
	var out := {}
	var raw := OS.get_cmdline_user_args()
	var i := 0
	while i < raw.size():
		var key := raw[i]
		if key.begins_with("--") and i + 1 < raw.size():
			out[key.substr(2)] = raw[i + 1]
			i += 2
		else:
			i += 1
	return out
