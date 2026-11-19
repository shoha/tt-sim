class_name PainterFieldBlur
extends RefCounted

## The separable box blur of a w x h float field the painted ground's zone maps use
## (PainterSurfaces.zone_image and its siblings). Pure; split out of PainterSurfaces to keep it
## under the file-length cap.


## A separable box blur of a w x h field, radius r samples (edges clamp). Radius 1, the zone map's,
## takes a three-tap pass with the edges outside the loop.
static func box(a: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	if r != 1 or w < 2 or h < 2:
		return box_generic(a, w, h, r)
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var out := PackedFloat32Array()
	out.resize(w * h)
	for y in h:
		var row := y * w
		tmp[row] = (a[row] * 2.0 + a[row + 1]) / 3.0
		for i in range(row + 1, row + w - 1):
			tmp[i] = (a[i - 1] + a[i] + a[i + 1]) / 3.0
		tmp[row + w - 1] = (a[row + w - 2] + a[row + w - 1] * 2.0) / 3.0
	for y in h:
		var above := maxi(y - 1, 0) * w
		var here := y * w
		var below := mini(y + 1, h - 1) * w
		for x in w:
			out[here + x] = (tmp[above + x] + tmp[here + x] + tmp[below + x]) / 3.0
	return out


## The general blur (any radius).
static func box_generic(a: PackedFloat32Array, w: int, h: int, r: int) -> PackedFloat32Array:
	if r <= 0:
		return a
	var tmp := PackedFloat32Array()
	tmp.resize(w * h)
	var out := PackedFloat32Array()
	out.resize(w * h)
	var span := float(2 * r + 1)
	for y in h:
		var acc := 0.0
		for x in range(-r, r + 1):
			acc += a[y * w + clampi(x, 0, w - 1)]
		for x in w:
			tmp[y * w + x] = acc / span
			acc += a[y * w + mini(x + r + 1, w - 1)] - a[y * w + maxi(x - r, 0)]
	for x in w:
		var acc := 0.0
		for y in range(-r, r + 1):
			acc += tmp[clampi(y, 0, h - 1) * w + x]
		for y in h:
			out[y * w + x] = acc / span
			acc += tmp[mini(y + r + 1, h - 1) * w + x] - tmp[maxi(y - r, 0) * w + x]
	return out
