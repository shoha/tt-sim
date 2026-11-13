class_name PainterBrushes
extends RefCounted

## The painted ground's brush shapes (painter_ground.gdshader `brushes`): three procedural masks
## in one Texture2DArray, alpha in the red channel with the cut at 0.5. Layer 0 a soft round dab,
## 1 a dry ragged dab (bristles reach along x by a noise of y, dry gaps toward the ends), 2 a long
## flat stroke. The prototype's own generator (the painter spike's PStyle.make_brushes), made
## once per session on the first Painted level (about 0.1 s) and shared by every ground material.

const SIZE := 128
const LAYERS := 3

static var _texture: Texture2DArray = null


## The shared brush array, made on first use.
static func texture() -> Texture2DArray:
	if _texture == null:
		var tex := Texture2DArray.new()
		tex.create_from_images(images())
		_texture = tex
	return _texture


## The three masks as mipmapped R8 images (pure: the same pixels every call).
static func images() -> Array[Image]:
	var blob := FastNoiseLite.new()
	blob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	blob.frequency = 0.02
	blob.seed = 7
	var streak := FastNoiseLite.new()
	streak.noise_type = FastNoiseLite.TYPE_SIMPLEX
	streak.frequency = 0.05
	streak.seed = 19
	var out: Array[Image] = []
	for layer in LAYERS:
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
		for py in SIZE:
			for px in SIZE:
				var x := (float(px) + 0.5) / float(SIZE) * 2.0 - 1.0
				var y := (float(py) + 0.5) / float(SIZE) * 2.0 - 1.0
				var a := _alpha(layer, x, y, px, py, blob, streak)
				img.set_pixel(px, py, Color(clampf(a, 0.0, 1.0), 0.0, 0.0))
		img.generate_mipmaps()
		out.append(img)
	return out


static func _alpha(
	layer: int, x: float, y: float, px: int, py: int, blob: FastNoiseLite, streak: FastNoiseLite
) -> float:
	if layer == 0:
		var d := Vector2(x, y).length() + blob.get_noise_2d(px, py) * 0.16
		return 1.0 - smoothstep(0.5, 0.95, d)
	if layer == 1:
		var reach := 0.62 + 0.3 * streak.get_noise_2d(11.0, py * 3.0)
		var body := 1.0 - smoothstep(reach - 0.22, reach + 0.08, absf(x))
		var env := 1.0 - smoothstep(0.55, 0.92, absf(y) + blob.get_noise_2d(px, py + 300) * 0.2)
		var gap := smoothstep(0.05, 0.45, streak.get_noise_2d(px * 0.35, py * 4.0 + 77.0))
		return body * env * (1.0 - gap * smoothstep(0.15, 0.7, absf(x)))
	var reach2 := 0.8 + 0.14 * streak.get_noise_2d(53.0, py * 2.5)
	var body2 := 1.0 - smoothstep(reach2 - 0.14, reach2 + 0.06, absf(x))
	var env2 := 1.0 - smoothstep(0.62, 0.95, absf(y) + blob.get_noise_2d(px + 200, py) * 0.14)
	var gap2 := smoothstep(0.25, 0.6, streak.get_noise_2d(px * 0.3, py * 3.5 + 190.0))
	return body2 * env2 * (1.0 - gap2 * smoothstep(0.45, 0.85, absf(x)))
