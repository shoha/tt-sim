class_name PainterMannerStrokes
extends RefCounted

## PROBE (card painter-manner; delete with the probe if it is not chosen): the prototype's built
## strokes (the painter spike's built_strokes.gd families) laid from procgen's manner records
## instead of recovered from triangles. A stroke is [u, v, angle, length, width, value] in a piece's
## own metres (angle 0 along u, PI/2 along v; value under 1 darkens, over 1 lightens).
##   face   a wall, roof slope or gable end in its material's manner (PainterBuildings patterns):
##          plaster dry-brush washes, stone marks in courses, log and board seams, tile dashes in
##          rows, thatch strokes down the slope with three course lines;
##   edges  a ruled line just inside every edge of a face record and short marks that straddle it
##          (an eave dark, a ridge pale);
##   box    a beam, frame, sill, shutter or door part: one broad stroke and a light and a dark line
##          along it; a door leaf its planks.
## `quads` turns strokes into geometry (candidate A); PainterMannerBake rasterises face strokes into
## a texture (candidate C). Pure; a seeded RandomNumberGenerator makes the same strokes again.

const U := 0
const V := 1
const ANG := 2
const LEN := 3
const WID := 4
const VAL := 5
## Long strokes are drawn in pieces this long so the wander bends them with the face.
const PIECE_M := 0.5
const FACE_KINDS: Array[String] = ["wall_face", "roof_slope", "gable_end"]


## Whether (`u`, `v`) lies on face record `rec`: inside its rectangle (a gable end: its triangle)
## and outside its holes, `margin` metres in. Pure.
static func inside(rec: Dictionary, u: float, v: float, margin: float = 0.0) -> bool:
	var ul := float(rec["u_len"])
	var vl := float(rec["v_len"])
	if u < margin or u > ul - margin or v < margin or v > vl - margin:
		return false
	if str(rec["kind"]) == "gable_end":
		var apex := apex_u(rec)
		var half := maxf(apex, ul - apex)
		if v > vl * (1.0 - absf(u - apex) / maxf(half, 0.01)) - margin:
			return false
	for h: Dictionary in rec.get("holes", []):
		if (
			u > float(h["u0"]) - margin
			and u < float(h["u1"]) + margin
			and v > float(h["v0"]) - margin
			and v < float(h["v1"]) + margin
		):
			return false
	return true


## A gable end's apex along u (its verge edges meet there; the middle when unknown). Pure.
static func apex_u(rec: Dictionary) -> float:
	var o: Vector3 = rec["origin"]
	var best := float(rec["u_len"]) * 0.5
	var top := -INF
	for e: Dictionary in rec.get("edges", []):
		for key in ["a", "b"]:
			var p: Vector3 = e[key]
			var h := (p - o).dot(rec["v"])
			if h > top:
				top = h
				best = (p - o).dot(rec["u"])
	return best


## The face strokes of `rec` in the manner of `pattern` (PainterBuildings.P_*), `density` times the
## prototype's count. Pure.
static func face(
	rec: Dictionary, pattern: int, density: float, rng: RandomNumberGenerator
) -> Array:
	var out: Array = []
	var ul := float(rec["u_len"])
	var vl := float(rec["v_len"])
	var area := ul * vl
	match pattern:
		1:
			# Stone: short marks in courses, about half the blocks, more near the foot.
			var row := 0.3
			for r in int(vl / row):
				var u := rng.randf() * 0.4
				while u < ul:
					var step := rng.randf_range(0.38, 0.6)
					var foot := 1.0 - float(r) * row / maxf(vl, 0.1)
					if rng.randf() < (0.35 + 0.3 * foot) * density:
						var value := _dark_or(rng, 0.62, 0.84, 1.1)
						_add(out, rec, u + step * 0.5, (r + 0.5) * row, 0.0, step * 0.7, 0.17, value)
					u += step
		2:
			_lines(out, rec, rng, 0.3, 0.0, 0.035, 0.72, density)
		3:
			_lines(out, rec, rng, 0.24, PI * 0.5, 0.03, 0.74, density)
		5, 6, 7:
			# Tiles, slates, shingles: dashes across the slope under each course.
			var course := 0.42 if pattern == 5 else (0.32 if pattern == 6 else 0.26)
			for r in int(vl / course):
				var u := rng.randf() * 0.5
				while u < ul:
					var dash := rng.randf_range(0.25, 0.6)
					if rng.randf() < 0.55 * density:
						var value := 0.74 if rng.randf() < 0.8 else 1.12
						var at := (r + 0.15) * course
						_add(out, rec, u + dash * 0.5, at, 0.0, dash, 0.05, value)
					u += dash + rng.randf_range(0.05, 0.4)
		8:
			# Thatch: long strokes down the slope, light and dark, and three course lines.
			for k in int(area * 6.0 * density):
				var length := rng.randf_range(0.5, 1.1)
				var value := _dark_or(rng, 0.45, 0.8, 1.14)
				var wid := rng.randf_range(0.05, 0.09)
				_add(out, rec, rng.randf() * ul, rng.randf() * vl, PI * 0.5, length, wid, value)
			for c in 3:
				var v := vl * (0.25 + 0.25 * c) + rng.randf_range(-0.1, 0.1)
				var u := 0.0
				while u < ul:
					var piece := rng.randf_range(0.5, 1.0)
					_add(out, rec, u + piece * 0.5, v, 0.0, piece, 0.05, 0.7)
					u += piece + rng.randf_range(0.0, 0.25)
		9:
			for k in int(area * 2.0 * density):
				var value := _dark_or(rng, 0.5, 0.85, 1.12)
				var length := rng.randf_range(0.2, 0.4)
				_add(out, rec, rng.randf() * ul, rng.randf() * vl, 0.0, length, 0.18, value)
		_:
			# Plaster, adobe: broad dry-brush washes along the wall, a few a step darker.
			for k in int(area * 3.0 * density):
				var value := _dark_or(rng, 0.3, 0.88, 1.1)
				var length := rng.randf_range(0.35, 0.9)
				var wid := rng.randf_range(0.07, 0.14)
				_add(out, rec, rng.randf() * ul, rng.randf() * vl, 0.0, length, wid, value)
	return out


## Edge strokes of face record `rec`: a ruled line inside each edge and straddle marks. Pure.
static func edges(rec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var o: Vector3 = rec["origin"]
	var roof := str(rec["kind"]) == "roof_slope"
	for e: Dictionary in rec.get("edges", []):
		var ea: Vector3 = (e["a"] as Vector3) - o
		var eb: Vector3 = (e["b"] as Vector3) - o
		var a := Vector2(ea.dot(rec["u"]), ea.dot(rec["v"]))
		var b := Vector2(eb.dot(rec["u"]), eb.dot(rec["v"]))
		var length := a.distance_to(b)
		if length < 0.2:
			continue
		var d := (b - a) / length
		var perp := Vector2(-d.y, d.x)
		var mid := (a + b) * 0.5
		if not inside(rec, mid.x + perp.x * 0.12, mid.y + perp.y * 0.12):
			perp = -perp
		var kind := str(e["kind"])
		var value := 0.8
		var wid := 0.06 if roof else 0.05
		if kind == "eave":
			value = 0.66 if roof else 0.72
		elif kind == "ridge":
			value = 1.16
		elif kind == "opening":
			value = 0.72
		var c := mid + perp * (wid * 0.5 + 0.02)
		_add(out, rec, c.x, c.y, d.angle(), length * 0.97, wid, value)
		if kind == "opening":
			continue
		for k in int(length / 0.8 + rng.randf() * 0.6):
			var ml := minf(rng.randf_range(0.3, 0.8), length)
			var mc := (
				mid + d * rng.randf_range(-0.5, 0.5) * (length - ml) + perp * rng.randf_range(-0.06, 0.04)
			)
			var turn := d.angle() + rng.randf_range(-0.09, 0.09)
			var wid_m := rng.randf_range(0.08, 0.14)
			_add(out, rec, mc.x, mc.y, turn, ml, wid_m, rng.randf_range(0.86, 1.06))
	return out


## The strokes of box record `rec` (beam, frame, sill, shutter, door part) on its outward face, in
## coordinates from the face's minimum corner. Pure.
static func box(rec: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var ul := float(rec["u_len"])
	var vl := float(rec["v_len"])
	if str(rec["kind"]) in ["door_leaf", "door_panel"]:
		var planks := maxi(2, int(vl / 0.16))
		for k in planks:
			out.append([ul * 0.5, vl * (k + 0.5) / planks, 0.0, ul * 0.94, 0.025, 0.66])
		return out
	var wid := clampf(vl * 0.96, 0.03, 0.3)
	out.append([ul * 0.5, vl * 0.5, 0.0, ul * 1.03, wid, rng.randf_range(0.94, 1.06)])
	out.append([ul * 0.46, vl * 0.7, 0.0, ul * 0.84, wid * 0.25, 1.22])
	out.append([ul * 0.5, vl * 0.28, 0.0, ul * 0.6, wid * 0.2, 0.76])
	return out


## Appends `strokes` of record `rec` as quads to `m`, moved by the building's wander `field`
## (PainterMannerMesh.wander_at). Box strokes stand on the outward face, face strokes `lift` metres
## off the face. COLOR is the piece's own paint (a roof's tone is picked from it), UV2 (value / 2,
## grain). Pure on its inputs.
static func quads(
	m: Buf, rec: Dictionary, strokes: Array, is_box: bool, lift: float, field: Dictionary, paint: Color
) -> void:
	var u: Vector3 = rec["u"]
	var v: Vector3 = rec["v"]
	var n: Vector3 = rec["n"]
	var o: Vector3 = rec["origin"] + n * lift
	if is_box:
		var centre: Vector3 = rec.get("centre", rec["origin"])
		o = (
			centre
			+ n * (float(rec.get("thickness", 0.0)) * 0.5 + lift)
			- u * float(rec["u_len"]) * 0.5
			- v * float(rec["v_len"]) * 0.5
		)
	for s: Array in strokes:
		var dir: Vector3 = u * cos(float(s[ANG])) + v * sin(float(s[ANG]))
		var across: Vector3 = n.cross(dir).normalized() * float(s[WID]) * 0.5
		var length := float(s[LEN])
		var c: Vector3 = o + u * float(s[U]) + v * float(s[V])
		var pieces := maxi(1, ceili(length / PIECE_M))
		var tone := Vector2(clampf(float(s[VAL]) * 0.5, 0.0, 1.0), randf_seeded(s))
		var first: int = m.pos.size()
		for k in pieces + 1:
			var t := float(k) / pieces
			var p: Vector3 = c + dir * length * (t - 0.5)
			for side in [-1.0, 1.0]:
				var q: Vector3 = p + across * side
				m.pos.append(q + PainterMannerMesh.wander_at(q, field))
				m.nor.append(n)
				m.col.append(paint)
				m.uv.append(Vector2(t, (side + 1.0) * 0.5))
				m.uv2.append(tone)
		for k in pieces:
			var a := first + k * 2
			m.idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))


## Candidate A's stroke geometry as it grows (members, so appends stay: a packed array taken out
## of a Dictionary is a copy).
class Buf:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	## The arrays for ArrayMesh.add_surface_from_arrays ([] with no stroke).
	func arrays() -> Array:
		if idx.is_empty():
			return []
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = pos
		out[Mesh.ARRAY_NORMAL] = nor
		out[Mesh.ARRAY_COLOR] = col
		out[Mesh.ARRAY_TEX_UV] = uv
		out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_INDEX] = idx
		return out


## A stable 0..1 per stroke (its own grain in the shader). Pure.
static func randf_seeded(s: Array) -> float:
	return float(hash(Vector2(float(s[U]), float(s[V]))) % 1024) / 1023.0


static func _add(
	out: Array,
	rec: Dictionary,
	u: float,
	v: float,
	ang: float,
	length: float,
	wid: float,
	value: float
) -> void:
	if str(rec["kind"]) in FACE_KINDS and not inside(rec, u, v, wid * 0.5):
		return
	out.append([u, v, ang, length, wid, value])


## `dark` (a share of `p_dark`) or `light`.
static func _dark_or(
	rng: RandomNumberGenerator, p_dark: float, dark: float, light: float
) -> float:
	if rng.randf() < p_dark:
		return dark * rng.randf_range(0.95, 1.05)
	return light * rng.randf_range(0.97, 1.03)


## Seams along `ang` every `spacing` metres, in broken pieces.
static func _lines(
	out: Array,
	rec: Dictionary,
	rng: RandomNumberGenerator,
	spacing: float,
	ang: float,
	wid: float,
	value: float,
	density: float
) -> void:
	var along_u := ang == 0.0
	var span := float(rec["u_len"]) if along_u else float(rec["v_len"])
	var across := float(rec["v_len"]) if along_u else float(rec["u_len"])
	for r in int(across / spacing):
		var x := rng.randf() * 0.3
		while x < span:
			var piece := rng.randf_range(0.5, 1.2)
			if rng.randf() < 0.7 * density:
				var at := (r + 1) * spacing
				if along_u:
					_add(out, rec, x + piece * 0.5, at, ang, piece, wid, value)
				else:
					_add(out, rec, at, x + piece * 0.5, ang, piece, wid, value)
			x += piece + rng.randf_range(0.05, 0.3)
