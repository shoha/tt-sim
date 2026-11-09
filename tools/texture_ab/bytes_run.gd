extends SceneTree

## Bytes and load cost of every candidate (TextureAb.CANDIDATES) for a list of core surfaces.
## Writes each candidate's file under <out>/<candidate>/<surface>/<kind>.<ext> (the zstd and
## deflate sizes come from pack_sizes.py, which reads that tree) and <out>/bytes.json with, per
## surface, kind and candidate: bytes, enc_ms, dec_ms (decode to the pixels the bake takes),
## bake_ms (that image to the baked map; 0 for c_ttimg, which is baked already) and for c_ttimg
## zstd_ms (Godot's zstd decompress of the file). a8 and b also record `exact`: the decoded
## pixels equal the decoded PNG's.
##
##   godot --headless --path <project> --script res://tools/texture_ab/bytes_run.gd -- \
##       --surfaces=all --out=D:/some/folder

var _out_dir := ""


func _initialize() -> void:
	var surfaces: PackedStringArray = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--surfaces="):
			var value := arg.trim_prefix("--surfaces=")
			surfaces = TextureAb.all_surfaces() if value == "all" else value.split(",")
		elif arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
	if _out_dir == "" or surfaces.is_empty():
		push_error("usage: --surfaces=all|a,b --out=<abs dir>")
		quit(2)
		return
	var report := {}
	for surface in surfaces:
		report[surface] = _surface(surface)
		print("done ", surface)
	var file := FileAccess.open(_out_dir.path_join("bytes.json"), FileAccess.WRITE)
	if file == null:
		DirAccess.make_dir_recursive_absolute(_out_dir)
		file = FileAccess.open(_out_dir.path_join("bytes.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0)


func _surface(surface: String) -> Dictionary:
	var out := {}
	for kind in SurfaceBake.KINDS:
		var path := TextureAb.SURFACES_ROOT + "%s/%s.png" % [surface, kind]
		var png := FileAccess.get_file_as_bytes(path)
		var src := Image.new()
		var t0 := Time.get_ticks_usec()
		src.load_png_from_buffer(png)
		var t1 := Time.get_ticks_usec()
		var baked := SurfaceBake.bake(src, kind)
		var t2 := Time.get_ticks_usec()
		var maps := {
			"a_png":
			{
				"bytes": png.size(),
				"enc_ms": 0.0,
				"dec_ms": (t1 - t0) / 1000.0,
				"bake_ms": (t2 - t1) / 1000.0,
			}
		}
		for candidate in TextureAb.CANDIDATES:
			if candidate != "a_png":
				maps[candidate] = _candidate(candidate, surface, kind, src)
		out[kind] = maps
		if baked == null:
			push_warning("%s %s did not bake" % [surface, kind])
	return out


func _candidate(candidate: String, surface: String, kind: String, src: Image) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var bytes := TextureAb.encode(candidate, src, kind)
	var t1 := Time.get_ticks_usec()
	var folder := _out_dir.path_join(candidate).path_join(surface)
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(
		folder.path_join("%s.%s" % [kind, TextureAb.EXTENSIONS[candidate]]), FileAccess.WRITE
	)
	file.store_buffer(bytes)
	file.close()
	var result := {"bytes": bytes.size(), "enc_ms": (t1 - t0) / 1000.0}
	var t2 := Time.get_ticks_usec()
	var decoded := TextureAb.decode(candidate, bytes, src)
	var t3 := Time.get_ticks_usec()
	result["dec_ms"] = (t3 - t2) / 1000.0
	if candidate == "c_ttimg":
		result["bake_ms"] = 0.0
		var packed := bytes.compress(FileAccess.COMPRESSION_ZSTD)
		var t4 := Time.get_ticks_usec()
		packed.decompress(bytes.size(), FileAccess.COMPRESSION_ZSTD)
		result["zstd_ms"] = (Time.get_ticks_usec() - t4) / 1000.0
		result["zstd3_bytes"] = packed.size()
	else:
		var t4 := Time.get_ticks_usec()
		var baked := TextureAb.to_baked(decoded, kind)
		result["bake_ms"] = (Time.get_ticks_usec() - t4) / 1000.0
		if baked == null:
			result["failed"] = true
	if candidate == "a8_png8" or candidate == "b_webp_ll":
		result["exact"] = decoded != null and decoded.get_data() == src.get_data()
	return result
