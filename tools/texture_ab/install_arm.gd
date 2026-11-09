extends SceneTree

## Puts a candidate's maps where the game looks for its baked surfaces, so a render job shows
## what a player would see if that candidate shipped. Every <surface>_<kind>.ttimg already in
## user://library_cache (made by one normal run, which bakes the PNGs of the surfaces the map
## uses) is rebuilt from the candidate's pixels: encode, decode, SurfaceBake.bake, SurfaceCache
## write, under the same hash folder, so SurfaceStore takes it as a cache hit and the renderer
## changes nowhere else.
##
## Arms: png (re-bake the PNG: the baseline and, run twice, the encoder's noise floor), d95m,
## d90m, d85m (lossy WebP for albedo, ORM and height, the normal map re-baked from the PNG), and
## d85all (lossy WebP for all four).
##
##   godot --headless --path <project> --script res://tools/texture_ab/install_arm.gd -- --arm=d90m

const ARMS := {
	"png": {},
	"d95m": {"albedo": "d95_webp", "orm": "d95_webp", "height": "d95_webp"},
	"d90m": {"albedo": "d90_webp", "orm": "d90_webp", "height": "d90_webp"},
	"d85m": {"albedo": "d85_webp", "orm": "d85_webp", "height": "d85_webp"},
	"d85all":
	{"albedo": "d85_webp", "normal": "d85_webp", "orm": "d85_webp", "height": "d85_webp"},
}


func _initialize() -> void:
	var arm := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--arm="):
			arm = arg.trim_prefix("--arm=")
	if not ARMS.has(arm):
		push_error("usage: --arm=%s" % ", ".join(ARMS.keys()))
		quit(2)
		return
	var cache := TextureAb.cache_script()
	var root: String = cache.root
	var done := 0
	var skipped := 0
	for library in DirAccess.get_directories_at(root):
		for hash_dir in DirAccess.get_directories_at(root.path_join(library)):
			var folder := root.path_join(library).path_join(hash_dir)
			for file in DirAccess.get_files_at(folder):
				if file.get_extension() != "ttimg":
					continue
				if _rebuild(cache, folder.path_join(file), file.get_basename(), ARMS[arm]):
					done += 1
				else:
					skipped += 1
	print("arm ", arm, ": rebuilt ", done, " maps, skipped ", skipped)
	quit(0)


func _rebuild(cache: GDScript, path: String, stem: String, kinds: Dictionary) -> bool:
	var at := stem.rfind("_")
	var surface := stem.substr(0, at)
	var kind := stem.substr(at + 1)
	var src := TextureAb.load_source(surface, kind)
	if src == null:
		return false
	var image := src
	if kinds.has(kind):
		var candidate: String = kinds[kind]
		image = TextureAb.decode(candidate, TextureAb.encode(candidate, src, kind), src)
	var baked := SurfaceBake.bake(image, kind)
	return baked != null and cache.write(path, baked)
