class_name TextureAb
extends RefCounted

## The A/B harness for how a surface map is SHIPPED (perf audit 2026-11, card textures): the
## candidate formats, how each is encoded and decoded, how it reaches the in-memory baked map the
## player sees, and the numbers that compare two such maps. Pure helpers; the runners
## (bytes_run.gd, quality_run.gd, install_arm.gd) do the I/O. README.md in this folder has the
## model and the commands.
##
## The player never sees a surface PNG: SurfaceBake turns it into BC7 (albedo), BC5 (normal), BC1
## (ORM) or L8 (height) with mips at first use. A candidate is therefore judged on
## candidate -> (decode) -> SurfaceBake.bake -> decompress, against the same chain from the
## shipped PNG, and the noise floor is that chain run twice on the PNG (Godot's BC7 encoder is
## not deterministic).

## Candidate ids: the file they write, in the order the report prints them.
const CANDIDATES: Array[String] = [
	"a_png", "a8_png8", "b_webp_ll", "c_ttimg", "d95_webp", "d90_webp", "d85_webp"
]
const EXTENSIONS := {
	"a_png": "png",
	"a8_png8": "png",
	"b_webp_ll": "webp",
	"c_ttimg": "ttimg",
	"d95_webp": "webp",
	"d90_webp": "webp",
	"d85_webp": "webp",
}
const LOSSY_QUALITY := {"d95_webp": 0.95, "d90_webp": 0.90, "d85_webp": 0.85}
## The channels each kind's baked map carries (the others are padding the metrics must not count).
const CHANNELS := {"albedo": 3, "normal": 2, "orm": 3, "height": 1}
const SURFACES_ROOT := "res://libraries/core/surfaces/"
const BLOCK := 8


## SurfaceCache, loaded at run time: naming it statically drags the autoload chain (through
## LibraryPaths) into the compile of a `--script` runner, which runs before the autoloads exist.
static func cache_script() -> GDScript:
	return load("res://utils/library/surface_cache.gd") as GDScript


## The decoded source PNG of one map (what SurfaceStore.load_map decodes), or null.
static func load_source(surface: String, kind: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(SURFACES_ROOT + "%s/%s.png" % [surface, kind])
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK else null


## Every surface folder of the shipped core library, sorted.
static func all_surfaces() -> PackedStringArray:
	var out := PackedStringArray()
	for dir in DirAccess.get_directories_at(SURFACES_ROOT):
		out.append(dir)
	out.sort()
	return out


## The bytes `candidate` ships for the decoded source `src` of `kind`. "a_png" is the file as
## shipped and is not produced here (the runners read it from disk).
static func encode(candidate: String, src: Image, kind: String) -> PackedByteArray:
	match candidate:
		"a8_png8":
			return src.save_png_to_buffer()
		"b_webp_ll":
			return src.save_webp_to_buffer(false, 1.0)
		"c_ttimg":
			var baked := SurfaceBake.bake(src, kind)
			return cache_script().encode(baked) if baked != null else PackedByteArray()
		_:
			if LOSSY_QUALITY.has(candidate):
				return src.save_webp_to_buffer(true, float(LOSSY_QUALITY[candidate]))
	return PackedByteArray()


## The Image `bytes` of `candidate` decode to, in the pixel format of `like` (the decoded source)
## so the bake sees what it sees today; a c_ttimg decodes to the baked, compressed map itself.
static func decode(candidate: String, bytes: PackedByteArray, like: Image) -> Image:
	var image := Image.new()
	match EXTENSIONS.get(candidate, ""):
		"ttimg":
			return cache_script().decode(bytes)
		"png":
			if image.load_png_from_buffer(bytes) != OK:
				return null
		"webp":
			if image.load_webp_from_buffer(bytes) != OK:
				return null
		_:
			return null
	if image.get_format() != like.get_format():
		image.convert(like.get_format())
	return image


## The baked map `image` becomes in the game (a c_ttimg decode is baked already).
static func to_baked(image: Image, kind: String) -> Image:
	return image if image.is_compressed() else SurfaceBake.bake(image, kind)


## `baked` (or any image) as an uncompressed RGBA8 image of its top mip only.
static func mip0_rgba(baked: Image) -> Image:
	var image := baked.duplicate() as Image
	if image.is_compressed():
		image.decompress()
	image.clear_mipmaps()
	image.convert(Image.FORMAT_RGBA8)
	return image


## Distance between two same-size RGBA8 images over the first `channels` channels:
## {psnr, max, mean, p999, ssim, over4}. `ssim` is the mean over channels of the structural
## similarity of 8x8 blocks (no overlap), `p999` the 99.9th percentile of the absolute level
## difference, `over4` the share of samples more than 4 levels apart.
static func compare(a: Image, b: Image, channels: int) -> Dictionary:
	if a.get_size() != b.get_size():
		return {}
	var da := a.get_data()
	var db := b.get_data()
	var width := a.get_width()
	var height := a.get_height()
	var histogram := PackedInt32Array()
	histogram.resize(256)
	var sq := 0.0
	var ssim_sum := 0.0
	var ssim_n := 0
	var c1 := (0.01 * 255.0) * (0.01 * 255.0)
	var c2 := (0.03 * 255.0) * (0.03 * 255.0)
	var area := float(BLOCK * BLOCK)
	for by in height / BLOCK:
		for bx in width / BLOCK:
			for c in channels:
				var sa := 0.0
				var sb := 0.0
				var saa := 0.0
				var sbb := 0.0
				var sab := 0.0
				for y in BLOCK:
					var at := (((by * BLOCK + y) * width) + bx * BLOCK) * 4 + c
					for x in BLOCK:
						var va := float(da[at])
						var vb := float(db[at])
						var d := da[at] - db[at]
						histogram[absi(d)] += 1
						sq += float(d * d)
						sa += va
						sb += vb
						saa += va * va
						sbb += vb * vb
						sab += va * vb
						at += 4
				var ma := sa / area
				var mb := sb / area
				var va2 := saa / area - ma * ma
				var vb2 := sbb / area - mb * mb
				var cov := sab / area - ma * mb
				ssim_sum += ((2.0 * ma * mb + c1) * (2.0 * cov + c2)) / (
					(ma * ma + mb * mb + c1) * (va2 + vb2 + c2)
				)
				ssim_n += 1
	var samples := float(width * height * channels)
	var mse := sq / samples
	var worst := 0
	var total := 0
	var abs_sum := 0.0
	var over4 := 0
	var p999 := 0
	var p999_found := false
	for level in 256:
		var count := histogram[level]
		if count > 0:
			worst = level
		abs_sum += float(level) * count
		total += count
		if level > 4:
			over4 += count
		if not p999_found and float(total) >= samples * 0.999:
			p999 = level
			p999_found = true
	return {
		"psnr": 99.0 if mse <= 0.0 else 10.0 * log(255.0 * 255.0 / mse) / log(10.0),
		"max": worst,
		"mean": abs_sum / samples,
		"p999": p999,
		"ssim": ssim_sum / maxf(1.0, float(ssim_n)),
		"over4": float(over4) / samples,
	}
