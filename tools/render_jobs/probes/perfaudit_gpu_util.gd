extends RefCounted

## Helpers of the GPU audit probe (perfaudit_gpu.gd; card gpuprepass, 2026-11-08): shaders built
## from an include and defines, so a probe compares compile-time variants of one include without a
## file per variant, and the 8-bit difference of two captures.

const GROUND_MODE := (
	"blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx"
)
const FOLIAGE_NO_AA_MODE := "cull_disabled, diffuse_burley, specular_schlick_ggx"


## A spatial shader from "res://x.gdshaderinc#A,B": `render_mode` and `#define A`, `#define B`
## before the include, cached in `cache` per spec and mode.
static func define_shader(spec: String, render_mode: String, cache: Dictionary) -> Shader:
	var key := spec + "|" + render_mode
	if cache.has(key):
		return cache[key]
	var parts := spec.split("#")
	var code := "shader_type spatial;\nrender_mode %s;\n" % render_mode
	for d in parts[1].split(",", false):
		code += "#define %s\n" % d
	code += '#include "%s"\n' % parts[0]
	var sh := Shader.new()
	sh.code = code
	cache[key] = sh
	return sh


## The per-channel difference of two RGB8 captures in 8-bit levels: the max, the mean and the
## share of channels off by more than 1, 2, 4 and 8 levels, as one log line. Saves the
## difference times 16 at `diff_path` when anything differs.
static func diff_line(label: String, ref: Image, img: Image, diff_path: String) -> String:
	var a := ref.get_data()
	var b := img.get_data()
	if a.size() != b.size():
		return "diff %s: sizes differ" % label
	var out := PackedByteArray()
	out.resize(a.size())
	var over := [0, 0, 0, 0]
	var total := 0
	var peak := 0
	for i in a.size():
		var d := absi(int(a[i]) - int(b[i]))
		total += d
		peak = maxi(peak, d)
		out[i] = mini(d * 16, 255)
		if d > 1:
			over[0] += 1
			if d > 2:
				over[1] += 1
				if d > 4:
					over[2] += 1
					if d > 8:
						over[3] += 1
	var n := float(maxi(a.size(), 1))
	if peak > 0:
		Image.create_from_data(img.get_width(), img.get_height(), false, Image.FORMAT_RGB8, out).save_png(
			diff_path
		)
	return (
		(
			"diff %s: max %d mean %.4f levels; over 1: %.3f%% over 2: %.3f%% over 4: %.3f%%"
			+ " over 8: %.3f%%"
		)
		% [
			label, peak, total / n, 100.0 * over[0] / n, 100.0 * over[1] / n,
			100.0 * over[2] / n, 100.0 * over[3] / n
		]
	)
