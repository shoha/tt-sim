class_name PainterTreeBurial
extends RefCounted
## Which stroke roots of a packed tree the stroke shader kills in leaf, as a pack-time list
## (painter-perf-buried). The shader (painter_tree_stroke_body.gdshaderinc, "Round 8's burial test")
## drops a root whose point lies inside one of its clump's four listed neighbours (texel 9 of the
## record) at squared unit radius BURY_R2; the test is made on the root's own position in the tree's
## frame, before the wind, so it does not depend on the camera, the wind or the time. Those roots
## draw nothing, but a vertex-bound stroke pass still launches their vertices: the pack lists the
## roots, PainterTreePack puts their slots LAST in the slot table and the cells draw only the live
## prefix in leaf. A bare season (leaf drop, no burial test on a kept clump) draws the whole table.
##
## Pure static functions, safe on a worker thread.

## The shader's bury10 default (stroke body, "uniform float bury10") less a float slack: a root
## this test drops the shader drops too (the shader runs in float32, this in doubles).
const BURY_R2: float = 0.72 - 0.004
## Ellipsoid flags the wide test never touches: a pine bough (256) and a willow strand (512) move
## their strokes off the root (the taper, the bend), so a root's test point is not where it draws.
const MOVED_FLAGS: int = 256 + 512


static func _h10(x: int) -> int:
	x &= 0xFFFFFFFF
	x ^= x >> 16
	x = (x * 2146121005) & 0xFFFFFFFF
	x ^= x >> 15
	x = (x * 2221713035) & 0xFFFFFFFF
	x ^= x >> 16
	return x


## The shader's r10(seed, key, ch) for the keys the root position needs.
static func r10(seed_v: int, key: int, ch: int) -> float:
	var inner: int = _h10((key * 2246822519 + ch * 3266489917 + 1) & 0xFFFFFFFF)
	var h: int = _h10(((seed_v * 2654435769) & 0xFFFFFFFF) + inner)
	return float(h >> 8) / 16777216.0


static func _v(data: PackedFloat32Array, texel: int) -> Vector3:
	return Vector3(data[texel * 4], data[texel * 4 + 1], data[texel * 4 + 2])


## The roots of ellipsoid record `ei` (record texels at ei * ell_t) that the shader's burial test
## kills: one byte a root, 1 = dead. `data` is the tree's texels (the records are all written).
## A negative `margin` is exactly the shader's test (its listed neighbours); 0 or more adds the
## other leaf clumps with their axes shortened by `margin` metres each (a stand-in for the wind's
## sway and the stroke's reach: not a subset of the shader's test, a look decision).
static func dead_roots(
	data: PackedFloat32Array, ei: int, n_ell: int, ell_t: int, margin: float = -1.0
) -> PackedByteArray:
	var wide: bool = margin >= 0.0
	var rec: int = ei * ell_t
	var roots: int = int(data[(rec + 6) * 4 + 3] + 0.5)
	var out := PackedByteArray()
	out.resize(roots)
	var c: Vector3 = _v(data, rec)
	var x1: Vector3 = _v(data, rec + 1)
	var x2: Vector3 = _v(data, rec + 2)
	var x3: Vector3 = _v(data, rec + 3)
	var seed_v: int = int(data[(rec + 8) * 4] + 0.5)
	var spin: float = r10(seed_v, 0, 7) * 6.2832
	# The shader's tests: a record's neighbours, each as (centre, three axes, inverse squared lengths).
	var near: Array[int] = []
	for nb: int in 4:
		var e: float = data[(rec + 9) * 4 + nb]
		if e > -0.5:
			near.append(int(e + 0.5) / ell_t)
	var flags: int = int(data[(rec + 1) * 4 + 3] + 0.5)
	var far: Array[int] = []
	if wide and (flags & MOVED_FLAGS) == 0:
		for j: int in n_ell:
			var w: float = data[j * ell_t * 4 + 3]
			if j != ei and (w < 0.5 or w > 7.5) and not near.has(j):
				far.append(j)
	for k: int in roots:
		var y: float = 1.0 - 2.0 * (float(k) + 0.5) / float(roots)
		var r: float = sqrt(maxf(1.0 - y * y, 0.0))
		var a: float = spin + 2.39996323 * float(k)
		var p: Vector3 = c + x1 * (cos(a) * r) + x2 * y + x3 * (sin(a) * r)
		var dead: bool = false
		for j: int in near:
			if _inside(data, j * ell_t, p, 0.0, BURY_R2):
				dead = true
				break
		if not dead:
			for j: int in far:
				if _inside(data, j * ell_t, p, margin, BURY_R2):
					dead = true
					break
		out[k] = 1 if dead else 0
	return out


## Whether `p` lies inside record `rec`'s ellipsoid with every axis shortened by `margin` metres,
## at squared unit radius `r2` (margin 0 is the shader's formula).
static func _inside(
	data: PackedFloat32Array, rec: int, p: Vector3, margin: float, r2: float
) -> bool:
	var q: Vector3 = p - _v(data, rec)
	var s: float = 0.0
	for ax: int in 3:
		var v: Vector3 = _v(data, rec + 1 + ax)
		var l2: float = v.dot(v)
		if margin <= 0.0:
			var u: float = q.dot(v) / l2
			s += u * u
		else:
			var l: float = sqrt(l2)
			if l - margin < 0.05:
				return false
			var u: float = q.dot(v) / (l * (l - margin))
			s += u * u
	return s < r2
