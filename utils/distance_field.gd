class_name DistanceField
extends RefCounted

## Exact Euclidean distance transforms on a regular grid (Felzenszwalb and Huttenlocher's
## separable lower-envelope algorithm), pure. Used by the water carve (a pond's signed
## distance to the edge of its painted area) and the water dressing (how far a dry sample is
## from the nearest wet one, and which one that is). The grid may be anisotropic: distances
## are in metres, `step` apart on each axis.
##
## transform() returns, for every cell of a `width` x `height` grid whose `feature` byte is
## 0, the squared distance to the nearest cell whose byte is non-zero, and that cell's index;
## feature cells get 0 and themselves. A grid without a feature cell reads FAR everywhere and
## index -1. Cost is linear in the cell count (two passes, each a lower envelope of
## parabolas per row or column): about 90 ms for 244 x 244 cells in GDScript.

## Squared distance of a cell with no feature cell in its grid.
const FAR := 1e20


## {"distance_sq": PackedFloat32Array (metres squared), "nearest": PackedInt32Array (row-
## major cell index of the nearest feature cell, -1 when none)} over the grid (see the
## header).
static func transform(
	feature: PackedByteArray, width: int, height: int, step: Vector2 = Vector2.ONE
) -> Dictionary:
	var count := width * height
	var distance := PackedFloat32Array()
	var nearest := PackedInt32Array()
	distance.resize(count)
	nearest.resize(count)
	nearest.fill(-1)
	if count == 0 or feature.size() < count:
		distance.fill(FAR)
		return {"distance_sq": distance, "nearest": nearest}
	# Pass 1, along X: per row, the squared distance to the nearest feature in that row and
	# its column.
	var row_distance := PackedFloat64Array()
	var row_column := PackedInt32Array()
	row_distance.resize(count)
	row_column.resize(count)
	var f := PackedFloat64Array()
	f.resize(maxi(width, height))
	var out := PackedFloat64Array()
	out.resize(maxi(width, height))
	var arg := PackedInt32Array()
	arg.resize(maxi(width, height))
	var sx := step.x * step.x
	var sz := step.y * step.y
	for z in height:
		var row := z * width
		for x in width:
			f[x] = 0.0 if feature[row + x] != 0 else FAR
		_envelope(f, width, sx, out, arg)
		for x in width:
			row_distance[row + x] = out[x]
			row_column[row + x] = arg[x]
	# Pass 2, along Z over the row results.
	for x in width:
		for z in height:
			f[z] = row_distance[z * width + x]
		_envelope(f, height, sz, out, arg)
		for z in height:
			var i := z * width + x
			var d := out[z]
			if d >= FAR * 0.5:
				distance[i] = FAR
				continue
			distance[i] = d
			var from_row := arg[z]
			nearest[i] = from_row * width + row_column[from_row * width + x]
	return {"distance_sq": distance, "nearest": nearest}


## The lower envelope of the parabolas (q - v)^2 * scale + f[v] over the first `n` entries
## of `f`: out[q] is its value at q and arg[q] the v that attains it. Entries of f at FAR are
## skipped (no parabola); with none left, out is FAR and arg -1.
static func _envelope(
	f: PackedFloat64Array, n: int, scale: float, out: PackedFloat64Array, arg: PackedInt32Array
) -> void:
	var v := PackedInt32Array()
	var z := PackedFloat64Array()
	v.resize(n)
	z.resize(n + 1)
	var k := -1
	for q in n:
		if f[q] >= FAR * 0.5:
			continue
		var fq := f[q] / scale + q * q
		if k < 0:
			k = 0
			v[0] = q
			z[0] = -INF
			z[1] = INF
			continue
		var s := (fq - (f[v[k]] / scale + v[k] * v[k])) / (2.0 * (q - v[k]))
		while s <= z[k]:
			k -= 1
			s = (fq - (f[v[k]] / scale + v[k] * v[k])) / (2.0 * (q - v[k]))
		k += 1
		v[k] = q
		z[k] = s
		z[k + 1] = INF
	if k < 0:
		for q in n:
			out[q] = FAR
			arg[q] = -1
		return
	var j := 0
	for q in n:
		while z[j + 1] < q:
			j += 1
		var d := q - v[j]
		out[q] = d * d * scale + f[v[j]]
		arg[q] = v[j]
