class_name WaterFieldContour
extends RefCounted

## The waterline of a WaterField as the contour of a depth over the terrain's own triangles
## (field-resolution spike F1, ported by the foot-2 spike): marching triangles, one segment per
## triangle at most, so the line is exactly where the drawn surface meets the terrain mesh and
## there are no saddles. WaterField `_shore` builds the table over its window and asks it for
## exact distances.

## The contour of `ed` (depth per sample of `win`, row-major, -INF where there is no surface, wet
## when > 0) over the cells with a boundary sample (`has`), on a lattice at `origin` with `step`:
## {"seg": 8 floats per cell (two triangles' segments, each ax, ay, bx, by in map metres), "ok": 2
## flags per cell}, indexed like the window's samples. A cell's first triangle is (0,0),(1,0),(0,1),
## the second (1,0),(1,1),(0,1) (TerrainMeshBuilder's split).
static func table(
	ed: PackedFloat32Array,
	win: Rect2i,
	has: PackedByteArray,
	origin: Vector2,
	step: Vector2
) -> Dictionary:
	var ww := win.size.x
	var count := ww * win.size.y
	var seg := PackedFloat32Array()
	seg.resize(count * 8)
	var ok := PackedByteArray()
	ok.resize(count * 2)
	for z in win.size.y - 1:
		for x in ww - 1:
			var c := z * ww + x
			if has[c] == 0 and has[c + 1] == 0 and has[c + ww] == 0 and has[c + ww + 1] == 0:
				continue
			var v00 := ed[c]
			var v10 := ed[c + 1]
			var v01 := ed[c + ww]
			var v11 := ed[c + ww + 1]
			# Positions from the global sample coordinates, so a window's crop changes no bit.
			var p00 := origin + Vector2(win.position + Vector2i(x, z)) * step
			var p10 := p00 + Vector2(step.x, 0.0)
			var p01 := p00 + Vector2(0.0, step.y)
			var p11 := p00 + step
			if v00 != -INF and v10 != -INF and v01 != -INF:
				_segment(seg, ok, c * 2, [p00, p10, p01], [v00, v10, v01])
			if v10 != -INF and v11 != -INF and v01 != -INF:
				_segment(seg, ok, c * 2 + 1, [p10, p11, p01], [v10, v11, v01])
	return {"seg": seg, "ok": ok}


## The distance from `q` to the contour segments of the cells on the grid edge `edge` (start
## sample * 2 + 0 for the edge to its right, + 1 for the edge below it, in window indices of a
## window `ww` wide), INF where there is none.
static func distance(q: Vector2, contour: Dictionary, edge: int, ww: int) -> float:
	var seg: PackedFloat32Array = contour.seg
	var ok: PackedByteArray = contour.ok
	var start := edge >> 1
	var other := start - ww if (edge & 1) == 0 else start - 1
	var best := INF
	for c in [start, other]:
		if c < 0:
			continue
		for t in 2:
			var slot: int = c * 2 + t
			if ok[slot] == 0:
				continue
			var a := Vector2(seg[slot * 4], seg[slot * 4 + 1])
			var b := Vector2(seg[slot * 4 + 2], seg[slot * 4 + 3])
			var ab := b - a
			var l2 := ab.length_squared()
			var d := q.distance_to(a)
			if l2 > 1e-12:
				d = q.distance_to(a + ab * clampf((q - a).dot(ab) / l2, 0.0, 1.0))
			best = minf(best, d)
	return best


## Writes into slot `slot` the segment where the plane through three corners `p` with values `v`
## crosses zero (wet is > 0), when the corners differ in sign.
static func _segment(
	seg: PackedFloat32Array, ok: PackedByteArray, slot: int, p: Array, v: Array
) -> void:
	var pts := PackedVector2Array()
	for k in 3:
		var j := (k + 1) % 3
		var va: float = v[k]
		var vb: float = v[j]
		if (va > 0.0) != (vb > 0.0):
			pts.append((p[k] as Vector2).lerp(p[j], va / (va - vb)))
	if pts.size() != 2:
		return
	ok[slot] = 1
	seg[slot * 4] = pts[0].x
	seg[slot * 4 + 1] = pts[0].y
	seg[slot * 4 + 2] = pts[1].x
	seg[slot * 4 + 3] = pts[1].y
