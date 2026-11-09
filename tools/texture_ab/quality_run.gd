extends SceneTree

## How far each lossy candidate lands from the PNG's own baked map, for a few surfaces. Per
## surface and kind, comparisons of the top mip as 8-bit levels (TextureAb.compare):
##   floor     bake(PNG) against a second bake(PNG): the encoder's own run-to-run noise
##   bc_src    bake(PNG) against the decoded PNG: what BC compression already costs
##   <cand>.raw   the candidate's decoded image against the decoded PNG (codec loss only)
##   <cand>.png   bake(candidate) against bake(PNG): the number the card asks for
##   <cand>.src   bake(candidate) against the decoded PNG
## Writes the JSON to --out=<file>.
##
##   godot --headless --path <project> --script res://tools/texture_ab/quality_run.gd -- \
##       --surfaces=gravel,grass --out=D:/some/quality.json

const LOSSY: Array[String] = ["d95_webp", "d90_webp", "d85_webp"]


func _initialize() -> void:
	var surfaces: PackedStringArray = []
	var out_file := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--surfaces="):
			surfaces = arg.trim_prefix("--surfaces=").split(",")
		elif arg.begins_with("--out="):
			out_file = arg.trim_prefix("--out=")
	if out_file == "" or surfaces.is_empty():
		push_error("usage: --surfaces=a,b --out=<file.json>")
		quit(2)
		return
	var report := {}
	for surface in surfaces:
		var kinds := {}
		for kind in SurfaceBake.KINDS:
			kinds[kind] = _kind(surface, kind)
			print("done ", surface, " ", kind)
		report[surface] = kinds
	var file := FileAccess.open(out_file, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit(0)


func _kind(surface: String, kind: String) -> Dictionary:
	var channels: int = TextureAb.CHANNELS[kind]
	var src := TextureAb.load_source(surface, kind)
	var src_rgba := TextureAb.mip0_rgba(src)
	var first := TextureAb.mip0_rgba(SurfaceBake.bake(src, kind))
	var second := TextureAb.mip0_rgba(SurfaceBake.bake(src, kind))
	var out := {
		"floor": TextureAb.compare(first, second, channels),
		"bc_src": TextureAb.compare(first, src_rgba, channels),
	}
	for candidate in LOSSY:
		var bytes := TextureAb.encode(candidate, src, kind)
		var decoded := TextureAb.decode(candidate, bytes, src)
		var baked := TextureAb.mip0_rgba(TextureAb.to_baked(decoded, kind))
		out[candidate] = {
			"bytes": bytes.size(),
			"raw": TextureAb.compare(TextureAb.mip0_rgba(decoded), src_rgba, channels),
			"png": TextureAb.compare(baked, first, channels),
			"src": TextureAb.compare(baked, src_rgba, channels),
		}
	return out
