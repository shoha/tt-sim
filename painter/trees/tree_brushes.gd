class_name PainterTreeBrushes
extends RefCounted
## The painted trees' brush shapes (painter_tree_stroke.gdshader `brushes`): LAYERS procedural
## R8 masks with mips, alpha in red, cut at 0.5; x runs along the stroke, y across, directional
## marks point toward +x. Generator code only, no image files, built from Images so it works
## headless. Ported from the painterspike branch: layers 0..2 are the ground's (PainterBrushes:
## round, dry, flat), 3..12 PBrush6's marks, 13 round 11's needle spray:
##   3 lobed (oak)  4 scale (lime)  5 flick (birch, poplar, rowan)  6 spray (spruce)  7 tuft
##   8 strand (willow)  9 bloom  10 edge  11 block  12 thatch  13 needle
## The stroke shader draws brushes 14 (a twig spray) and 15 (the far twig mass) procedurally in
## the fragment stage, so they have no layer. Made once per session on the first painted tree.

const SIZE := 128
const LAYERS := 14
const NEEDLE := 13

static var _texture: Texture2DArray = null


## The shared brush array, made on first use.
static func texture() -> Texture2DArray:
	if _texture == null:
		var tex := Texture2DArray.new()
		tex.create_from_images(images())
		_texture = tex
	return _texture


## The LAYERS masks as mipmapped R8 images (pure).
static func images() -> Array[Image]:
	var out: Array[Image] = PainterBrushes.images()
	var blob := FastNoiseLite.new()
	blob.noise_type = FastNoiseLite.TYPE_SIMPLEX
	blob.frequency = 0.03
	blob.seed = 11
	var streak := FastNoiseLite.new()
	streak.noise_type = FastNoiseLite.TYPE_SIMPLEX
	streak.frequency = 0.05
	streak.seed = 23
	for layer in range(3, NEEDLE):
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
		for py in SIZE:
			for px in SIZE:
				var x := (float(px) + 0.5) / float(SIZE) * 2.0 - 1.0
				var y := (float(py) + 0.5) / float(SIZE) * 2.0 - 1.0
				var n1 := blob.get_noise_2d(float(px + layer * 131), float(py))
				# The thatch fray depends on y only (bristles); the rest use a second blob.
				var n2 := (
					streak.get_noise_2d(float(layer) * 37.0, float(py) * 3.0)
					if layer == 12
					else blob.get_noise_2d(float(px), float(py + 400))
				)
				img.set_pixel(px, py, Color(clampf(mark(layer, x, y, n1, n2), 0.0, 1.0), 0.0, 0.0))
		img.generate_mipmaps()
		out.append(img)
	out.append(_needle())
	return out


## Alpha of mark `layer` (3..12) at (x, y) in -1..1; `n1`, `n2` two noise samples in -1..1.
static func mark(layer: int, x: float, y: float, n1: float, n2: float) -> float:
	match layer:
		3:
			var best := 9.0
			for l: Vector3 in [
				Vector3(0.0, 0.0, 0.5),
				Vector3(0.46, 0.24, 0.36),
				Vector3(-0.44, 0.2, 0.36),
				Vector3(0.36, -0.34, 0.34),
				Vector3(-0.38, -0.32, 0.34),
				Vector3(0.02, 0.5, 0.3),
				Vector3(0.0, -0.52, 0.26)
			]:
				best = minf(best, Vector2(x - l.x, y - l.y).length() / l.z)
			return 1.0 - smoothstep(0.9, 1.1, best + n1 * 0.06)
		4:
			# A heart: two round shoulders at the stalk end, a point at +x.
			var sh := minf(Vector2(x + 0.34, absf(y) - 0.36).length() / 0.46, 9.0)
			var tip := 9.0
			if x > -0.34:
				var w := 0.8 * pow(maxf(1.0 - (x + 0.34) / 1.2, 0.0), 0.75)
				tip = absf(y) / maxf(w, 0.001)
			return 1.0 - smoothstep(0.92, 1.08, minf(sh, tip) + n1 * 0.04)
		5:
			var lens := 0.46 * maxf(1.0 - (x / 0.92) * (x / 0.92), 0.0)
			return 1.0 - smoothstep(lens - 0.05, lens + 0.05, absf(y) + 0.02)
		6:
			var taper := 1.0 - 0.55 * (x + 1.0) * 0.5
			var spine := 1.0 - smoothstep(0.12, 0.2, absf(y))
			var f := fposmod(x * 2.6 + 0.3, 1.0)
			var barb := (
				(1.0 - smoothstep(0.13, 0.22, absf(absf(y) - (1.0 - f) * 0.7 * taper)))
				* (1.0 - smoothstep(0.66 * taper, 0.8 * taper, absf(y)))
			)
			return maxf(spine, barb) * (1.0 - smoothstep(0.86, 0.94, absf(x)))
		7:
			var spike := smoothstep(0.25, 0.6, cos(atan2(y, x) * 8.0 + n1 * 0.8))
			var reach := 0.5 + 0.42 * spike
			return 1.0 - smoothstep(reach - 0.07, reach + 0.05, Vector2(x, y).length())
		8:
			return _strands(x, y)
		9:
			var d := Vector2(x, y).length() / 0.27
			for k in 5:
				var an := TAU * float(k) / 5.0 + 0.4
				d = minf(d, Vector2(x - cos(an) * 0.52, y - sin(an) * 0.52).length() / 0.25)
			return 1.0 - smoothstep(0.9, 1.1, d)
		10:
			var centre := 0.16 * sin(x * 1.9 + 0.6) + 0.07 * sin(x * 4.3 + 2.0) + n1 * 0.05
			var halfw := (
				(0.52 + 0.1 * sin(x * 2.7 + 4.0)) * (1.0 - smoothstep(0.8, 0.98, absf(x)) * 0.85)
			)
			return (
				(1.0 - smoothstep(halfw - 0.05, halfw + 0.05, absf(y - centre)))
				* (1.0 - smoothstep(0.93, 0.99, absf(x)))
			)
		11:
			var q := Vector2(absf(x) - 0.62, absf(y) - 0.56)
			var sd := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			return 1.0 - smoothstep(-0.04, 0.04, sd - 0.24 + n1 * 0.04)
	var reach2 := 0.62 + 0.32 * n2
	var body := 1.0 - smoothstep(0.66, 0.8, absf(y) + n1 * 0.08)
	var gap := smoothstep(0.25, 0.6, n2 * 0.5 + 0.5) * smoothstep(0.2, 0.7, x)
	return (
		body
		* (1.0 - smoothstep(reach2 - 0.1, reach2, x))
		* smoothstep(-0.97, -0.9, x)
		* (1.0 - gap * 0.9)
	)


## Mark 8: three thin wavy hanging lines.
static func _strands(x: float, y: float) -> float:
	var a := 0.0
	var offs: Array[float] = [-0.52, 0.02, 0.5]
	var ends: Array[float] = [0.7, 0.94, 0.55]
	for k in 3:
		var yc := offs[k] + 0.1 * sin(x * 3.6 + float(k) * 2.1)
		var w := 0.15 * (1.0 - 0.55 * smoothstep(-0.2, ends[k], x))
		a = maxf(
			a,
			(
				(1.0 - smoothstep(w - 0.04, w + 0.04, absf(y - yc)))
				* (1.0 - smoothstep(ends[k] - 0.08, ends[k], x))
				* smoothstep(-0.96, -0.9, x)
			)
		)
	return a


## Layer 13: three needles fanning from a point near -x.
static func _needle() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_R8)
	var angs: Array[float] = [-0.46, 0.03, 0.5]
	var lens: Array[float] = [1.35, 1.78, 1.5]
	for py in SIZE:
		for px in SIZE:
			var x := (float(px) + 0.5) / float(SIZE) * 2.0 - 1.0 + 0.86
			var y := (float(py) + 0.5) / float(SIZE) * 2.0 - 1.0
			var a := 0.0
			for k in 3:
				var u := x * cos(angs[k]) + y * sin(angs[k])
				var v := -x * sin(angs[k]) + y * cos(angs[k])
				var t := u / lens[k]
				if t >= 0.0 and t <= 1.0:
					var w := 0.2 * pow(1.0 - t, 0.8) + 0.015
					a = maxf(a, 1.0 - smoothstep(w - 0.04, w + 0.04, absf(v)))
			img.set_pixel(px, py, Color(a, 0.0, 0.0))
	img.generate_mipmaps()
	return img
