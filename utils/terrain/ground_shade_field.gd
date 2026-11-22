class_name GroundShadeField
extends RefCounted

## The Painted ground's shading field: what painter_ground.gdshader lights the terrain from, in
## place of the mesh's interpolated normal and its screen derivatives (card painter-ground-robust).
## One RGBA half-float texel per height sample of a MapDocument (texel i's middle lies on sample i,
## as the zone map's), read bilinearly:
##   r, g  the gradient (d/dx, d/dz, metres per metre) of the BAND-LIMITED heights: the heights
##         under a binomial [1 4 6 4 1] blur run twice (sigma 1.41 samples). The shader's normal is
##         normalize(-r, 1, -g), so a threshold on N.L or on the slope has a smooth contour that no
##         triangle, sample or chunk border shows in.
##   b     the convexity (1/m): the divergence of that normal's horizontal part, positive on a
##         rim, negative in a foot.
##   a     the nearest steep face: the steepest one-sample step of the RAW heights (the larger of
##         the forward and the backward step on each axis, the two axes as one gradient, as a
##         slope 1 - n.y), softened [1 2 1]. A sheer step half a metre high is one sample wide and
##         all but vanishes from the band-limited slope; this keeps its rock face.
## The model is a chain of stages, each a pure function of the stage before it at a fixed reach:
##   raw -> blur -> blur (smooth) -> gradient -> convexity      reach 2, 4, 5, 6 samples
##   raw -> steep -> softened                                   reach 1, 2 samples
## bake() runs every stage over the grid; update() runs each stage over the changed samples'
## rectangle grown by that stage's reach. The two are equal bit for bit, because a sample's value
## is the same expression of the same stored inputs either way (test_ground_shade_field.gd).
## Pure data: the texture is made on first use, and nothing here touches the scene tree.

## How far (samples) a changed height reaches into the field.
const REACH := 6

## The grid's size in samples and its step in metres.
var width := 0
var depth := 0
var step := Vector2.ONE

var _raw := PackedFloat32Array()
var _blur1 := PackedFloat32Array()
var _smooth := PackedFloat32Array()
var _gx := PackedFloat32Array()
var _gz := PackedFloat32Array()
## The band-limited normal's y (1 / sqrt(1 + gx^2 + gz^2)).
var _ny := PackedFloat32Array()
var _steep := PackedFloat32Array()
## The texture's texels: four half floats per sample.
var _bytes := PackedByteArray()
var _texture: ImageTexture = null


## Bakes the whole field of `doc`.
func bake(doc: MapDocument) -> void:
	width = doc.samples_x()
	depth = doc.samples_z()
	step = doc.sample_step()
	var count := width * depth
	for values: PackedFloat32Array in [_raw, _blur1, _smooth, _gx, _gz, _ny, _steep]:
		values.resize(count)
	_bytes.resize(count * 8)
	var grid := Rect2i(0, 0, width, depth)
	_read_heights(doc, grid)
	_run_stages(grid)
	_upload()


## Follows a height edit of `doc` inside `rect` (samples): rewrites the texels the changed heights
## reach and returns their rectangle, empty when no height in `rect` changed (a mask edit). A
## document of another size than the baked one is baked whole.
func update(doc: MapDocument, rect: Rect2i) -> Rect2i:
	if doc.samples_x() != width or doc.samples_z() != depth or doc.sample_step() != step:
		bake(doc)
		return Rect2i(0, 0, width, depth)
	var grid := Rect2i(0, 0, width, depth)
	if rect.encloses(grid) and doc.heights == _raw:
		# The whole grid and not a height changed (a water swap re-adds the terrain's skirt): one
		# native compare instead of the sample loop (8.6 ms on a 320 ft map, card painter-river-landing).
		return Rect2i()
	var changed := _read_heights(doc, rect.intersection(grid))
	if not changed.has_area():
		return Rect2i()
	_run_stages(changed)
	_upload()
	return changed.grow(REACH).intersection(grid)


## A copy of this field's stages and texels without its texture, for update() on a worker while
## this one stays as it is (PainterGroundField): the packed arrays are duplicated, copy-on-write,
## so the worker's writes copy them and never reach this field.
func clone() -> GroundShadeField:
	var c := GroundShadeField.new()
	c.width = width
	c.depth = depth
	c.step = step
	c._raw = _raw.duplicate()
	c._blur1 = _blur1.duplicate()
	c._smooth = _smooth.duplicate()
	c._gx = _gx.duplicate()
	c._gz = _gz.duplicate()
	c._ny = _ny.duplicate()
	c._steep = _steep.duplicate()
	c._bytes = _bytes.duplicate()
	return c


## Takes the stages and texels of `other` (a clone() updated on a worker, for the same grid) and
## uploads them to this field's texture.
func adopt(other: GroundShadeField) -> void:
	_raw = other._raw
	_blur1 = other._blur1
	_smooth = other._smooth
	_gx = other._gx
	_gz = other._gz
	_ny = other._ny
	_steep = other._steep
	_bytes = other._bytes
	_upload()


## Whether this field was baked for a grid of `doc`'s size and step.
func matches(doc: MapDocument) -> bool:
	return (
		width > 0
		and doc.samples_x() == width
		and doc.samples_z() == depth
		and doc.sample_step() == step
	)


## The field's texture (RGBA half float, no mipmaps), updated in place by bake() and update()
## (re-allocated, the same object, when the grid's size changes).
func texture() -> ImageTexture:
	if _texture == null and width > 0:
		_texture = ImageTexture.create_from_image(_image())
	return _texture


## The texture's bytes: per sample four half floats (gradient x, gradient z, convexity, steep).
func bytes() -> PackedByteArray:
	return _bytes


## The texel of sample (x, z) as the shader reads it at the sample's middle.
func texel(x: int, z: int) -> Color:
	var o := (z * width + x) * 8
	return Color(
		_bytes.decode_half(o),
		_bytes.decode_half(o + 2),
		_bytes.decode_half(o + 4),
		_bytes.decode_half(o + 6)
	)


func _image() -> Image:
	return Image.create_from_data(width, depth, false, Image.FORMAT_RGBAH, _bytes)


## Puts the texels on the texture, if it was made. A grid of another size than the texture's (a
## second map played in one session) re-allocates it: ImageTexture.update() refuses an image of
## another size ("new image dimensions must match") and would leave the first map's field on the
## ground. The ImageTexture object stays the same, so the materials bound to it follow.
func _upload() -> void:
	if _texture == null:
		return
	if _texture.get_width() == width and _texture.get_height() == depth:
		_texture.update(_image())
	else:
		_texture.set_image(_image())


## Copies `doc`'s heights inside `rect` and returns the rectangle of the samples that changed.
func _read_heights(doc: MapDocument, rect: Rect2i) -> Rect2i:
	var heights := doc.heights
	var limit := heights.size()
	var x0 := rect.end.x
	var x1 := rect.position.x - 1
	var z0 := rect.end.y
	var z1 := rect.position.y - 1
	for z in range(rect.position.y, rect.end.y):
		var from := doc.sample_index(rect.position.x, z)
		var to := z * width + rect.position.x
		for k in rect.size.x:
			var h := heights[from + k] if from + k < limit else 0.0
			if h != _raw[to + k]:
				_raw[to + k] = h
				var x := rect.position.x + k
				x0 = mini(x0, x)
				x1 = maxi(x1, x)
				z0 = mini(z0, z)
				z1 = maxi(z1, z)
	if x1 < x0:
		return Rect2i()
	return Rect2i(x0, z0, x1 - x0 + 1, z1 - z0 + 1)


## Runs every stage over what the changed heights of `changed` reach.
func _run_stages(changed: Rect2i) -> void:
	var grid := Rect2i(0, 0, width, depth)
	_blur(_raw, _blur1, changed.grow(2).intersection(grid))
	_blur(_blur1, _smooth, changed.grow(4).intersection(grid))
	_gradient(changed.grow(5).intersection(grid))
	_steepness(changed.grow(1).intersection(grid))
	_pack(changed.grow(REACH).intersection(grid))


## `dst` inside `rect`: `src` under a separable binomial [1 4 6 4 1] / 16 blur, edges clamped.
func _blur(src: PackedFloat32Array, dst: PackedFloat32Array, rect: Rect2i) -> void:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var xmax := width - 1
	var zmax := depth - 1
	var ta := maxi(rect.position.y - 2, 0)
	var tb := mini(rect.end.y + 2, depth)
	var tw := x1 - x0
	var temp := PackedFloat32Array()
	temp.resize(tw * (tb - ta))
	for z in range(ta, tb):
		var row := z * width
		var t := (z - ta) * tw - x0
		for x in range(x0, x1):
			var a := src[row + maxi(x - 2, 0)] + src[row + mini(x + 2, xmax)]
			var b := src[row + maxi(x - 1, 0)] + src[row + mini(x + 1, xmax)]
			temp[t + x] = (a + 4.0 * b + 6.0 * src[row + x]) / 16.0
	for z in range(rect.position.y, rect.end.y):
		var r0 := (maxi(z - 2, 0) - ta) * tw - x0
		var r1 := (maxi(z - 1, 0) - ta) * tw - x0
		var r2 := (z - ta) * tw - x0
		var r3 := (mini(z + 1, zmax) - ta) * tw - x0
		var r4 := (mini(z + 2, zmax) - ta) * tw - x0
		var row := z * width
		for x in range(x0, x1):
			var a := temp[r0 + x] + temp[r4 + x]
			var b := temp[r1 + x] + temp[r3 + x]
			dst[row + x] = (a + 4.0 * b + 6.0 * temp[r2 + x]) / 16.0


## The band-limited heights' gradient and normal height inside `rect` (one-sided at the map edge).
func _gradient(rect: Rect2i) -> void:
	var xmax := width - 1
	var zmax := depth - 1
	for z in range(rect.position.y, rect.end.y):
		var row := z * width
		var za := maxi(z - 1, 0)
		var zb := mini(z + 1, zmax)
		var above := za * width
		var below := zb * width
		var inv_dz := 1.0 / ((zb - za) * step.y)
		for x in range(rect.position.x, rect.end.x):
			var xa := maxi(x - 1, 0)
			var xb := mini(x + 1, xmax)
			var gx := (_smooth[row + xb] - _smooth[row + xa]) / ((xb - xa) * step.x)
			var gz := (_smooth[below + x] - _smooth[above + x]) * inv_dz
			_gx[row + x] = gx
			_gz[row + x] = gz
			_ny[row + x] = 1.0 / sqrt(1.0 + gx * gx + gz * gz)


## The steepest one-sample step of the raw heights at each sample of `rect`, as a slope: the same
## for a face along the grid and one across its diagonal.
func _steepness(rect: Rect2i) -> void:
	var xmax := width - 1
	var zmax := depth - 1
	for z in range(rect.position.y, rect.end.y):
		var row := z * width
		var above := maxi(z - 1, 0) * width
		var below := mini(z + 1, zmax) * width
		for x in range(rect.position.x, rect.end.x):
			var c := _raw[row + x]
			var dx := maxf(absf(_raw[row + mini(x + 1, xmax)] - c), absf(c - _raw[row + maxi(x - 1, 0)]))
			var dz := maxf(absf(_raw[below + x] - c), absf(c - _raw[above + x]))
			# The two axes' steps as one gradient: a face reads the same whichever way it is turned
			# to the grid (with the larger axis alone a diagonal 50 degree face read as 39).
			var gx := dx / step.x
			var gz := dz / step.y
			_steep[row + x] = 1.0 - 1.0 / sqrt(1.0 + gx * gx + gz * gz)


## The texels of `rect`: the gradient, the convexity (the divergence of the normal's horizontal
## part) and the softened steepness.
func _pack(rect: Rect2i) -> void:
	var xmax := width - 1
	var zmax := depth - 1
	for z in range(rect.position.y, rect.end.y):
		var row := z * width
		var za := maxi(z - 1, 0)
		var zb := mini(z + 1, zmax)
		var above := za * width
		var below := zb * width
		var inv_dz := 1.0 / ((zb - za) * step.y)
		for x in range(rect.position.x, rect.end.x):
			var xa := maxi(x - 1, 0)
			var xb := mini(x + 1, xmax)
			var i := row + x
			var div := (
				(_gx[row + xa] * _ny[row + xa] - _gx[row + xb] * _ny[row + xb])
				/ ((xb - xa) * step.x)
			)
			div += (_gz[above + x] * _ny[above + x] - _gz[below + x] * _ny[below + x]) * inv_dz
			var soft := 4.0 * _steep[i]
			soft += 2.0 * (_steep[row + xa] + _steep[row + xb] + _steep[above + x] + _steep[below + x])
			soft += _steep[above + xa] + _steep[above + xb] + _steep[below + xa] + _steep[below + xb]
			var o := i * 8
			_bytes.encode_half(o, _gx[i])
			_bytes.encode_half(o + 2, _gz[i])
			_bytes.encode_half(o + 4, div)
			_bytes.encode_half(o + 6, soft / 16.0)
