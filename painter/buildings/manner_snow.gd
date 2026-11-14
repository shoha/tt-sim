class_name PainterMannerSnow
extends RefCounted

## The body of a winter mood's roof snow on the hand-drawn buildings (card painter-roof-snow): a
## few thin strips that give the snow an edge you can see, built from procgen's manner records
## (PainterMannerHost) while the sheet lays snow on roofs (roof-snow above 0), never otherwise.
##
## The model. Every roof slope whose edges are an eave, two sides and a ridge or an apex (and every
## dormer's or porch's roof piece, given those edges from its frame) lies under one blanket
## (PainterMannerBlanket, card painter-buildings-fix2): thickest in the middle and toward the
## ridge, thin and soft at the verges, a modest rounded lip at the eave, the two halves of a ridge
## or a hip meeting in one rounded crest. Any other roof (a flat roof, a plan the blanket cannot
## read) keeps the strips it had before:
##   lip   along every eave and verge: a rounded roll that starts flush on the slope a hand's
##         width inside the edge, rises to its own lit top, rounds over the edge and tucks under
##         it, its nose hanging in scallops (more on thatch, which holds more snow);
##   cap   along every ridge and hip, one half per slope, rising from the slope to a soft crest
##         midway to the other half's edge, where the two halves meet.
## And on every roof:
##   pad   a cushion on each chimney's cap, a small drift collar where its stack meets the
##         blanket (heaped on the uphill side) and a wedge on each window sill.
## The roof itself, under the blanket, is drawn by the manner shader as a plain snow cover.
## Every vertex carries the manner's per-vertex data (UV2: metres along the strip and the profile
## step; CUSTOM0: [length, profile steps, CODE, accent]) and is moved by the building's wander
## field, so the strips follow the leaning eaves. The strips cast no shadow (PainterMannerHost puts
## them on their own node). Pure and worker-safe.

## The manner code of a snow vertex (painter_structure_manner.gdshader).
const CODE := 9
## How much snow a roof material holds (thatch the most); others take DEFAULT_HOLD.
const HOLD: Dictionary = {"thatch": 1.0, "turf": 0.9, "wood": 0.75, "shingle": 0.75}
const DEFAULT_HOLD := 0.7
## Segment lengths along an eave, a verge and a ridge (metres; an eave's carries its scallops).
const SEG_EAVE_M := 0.3
const SEG_VERGE_M := 0.5
const SEG_RIDGE_M := 0.8
## The lip at full hold: thickness above the slope, reach up the slope from the edge, overhang
## past the edge and the deepest droop of a scallop (metres); a verge's is VERGE_SCALE of an
## eave's.
const LIP_T_M := 0.24
const LIP_IN_M := 0.42
const LIP_OVER_M := 0.19
const LIP_DROOP_M := 0.09
const VERGE_SCALE := 0.7
## The ridge cap at full hold: height above the ridge and reach down each slope.
const CAP_T_M := 0.28
const CAP_IN_M := 0.5
## A chimney's drift collar at full hold: its height against the stack (more uphill) and its
## reach out over the roof, in half-widths of the stack.
const COLLAR_T_M := 0.14
const COLLAR_REACH := 1.4
## Two cap edges of different roofs this close (metres, line to line) are one ridge's halves.
const PAIR_M := 0.7
## A chimney cushion's and a sill wedge's thickness.
const PAD_T_M := 0.12
const SILL_T_M := 0.06
## Edge kinds that get a lip and a cap.
const LIP_KINDS: Array[String] = ["eave", "verge"]
const CAP_KINDS: Array[String] = ["ridge", "hip"]
## Record kinds whose edges carry snow.
const ROOF_KINDS: Array[String] = ["roof_slope", "roof_part", "roof_flat"]
## Mesh name prefixes that may hold chimney caps and sills.
const TOP_MESHES: Array[String] = ["chimney_", "trim_", "opening_"]

## False lays every roof's lips and caps as before card painter-buildings-fix2 (an A/B switch for
## measurements; read when a structure's snow is built).
static var blanket := true


## What the strips of one structure need, taken from its manner feed (PainterMannerSource) and the
## field `opts` (PainterMannerMesh.wander_at's, with "walls"): {"roofs": [roof records], "pads":
## [{"kind" "chimney"|"sill", "centre", "a", "b" (half axes), "top", "out" (a sill's wall normal)}],
## "opts"}. Small: kept per structure so a later turn to winter needs no evaluation. Pure.
static func source(
	records: Dictionary, meshes: Dictionary, table: PackedStringArray, opts: Dictionary
) -> Dictionary:
	var roofs: Array = []
	for rec: Dictionary in records.values():
		if not ROOF_KINDS.has(str(rec["kind"])):
			continue
		if not (rec.get("edges", []) as Array).is_empty():
			roofs.append(rec)
		elif str(rec["kind"]) == "roof_part":
			var framed := _framed(rec)
			if not framed.is_empty():
				roofs.append(framed)
	return {"roofs": roofs, "pads": _pads(records, meshes, table, opts), "opts": opts}


## A roof piece with no edges (a dormer's or a porch's roof) as a slope: its frame's lowest side the
## eave, the side across from it the ridge (a porch roof's against its wall), the other two verges,
## its normal turned up; {} for a piece that stands near upright. Pure.
static func _framed(rec: Dictionary) -> Dictionary:
	var n: Vector3 = rec["n"]
	if absf(n.y) < 0.2:
		return {}
	var o: Vector3 = rec["origin"]
	var u: Vector3 = (rec["u"] as Vector3) * float(rec["u_len"])
	var v: Vector3 = (rec["v"] as Vector3) * float(rec["v_len"])
	var c: Array[Vector3] = [o, o + u, o + u + v, o + v]
	var low := 0
	for k in 4:
		if c[k].y + c[(k + 1) % 4].y < c[low].y + c[(low + 1) % 4].y - 0.001:
			low = k
	var edges: Array = []
	for k in 4:
		var kind := "eave" if k == low else ("ridge" if k == (low + 2) % 4 else "verge")
		edges.append({"kind": kind, "a": c[k], "b": c[(k + 1) % 4]})
	var out := rec.duplicate()
	out["n"] = n if n.y > 0.0 else -n
	out["edges"] = edges
	return out


## The snow of `src` (source()): {"arrays" (Mesh arrays, PainterMannerMesh.FORMAT), "triangles",
## "by_kind": {blanket, lip, cap, pad}}; "arrays" empty when there is nothing to lay snow on. Pure.
static func build(src: Dictionary) -> Dictionary:
	var g := Strips.new()
	var counts := {"blanket": 0, "lip": 0, "cap": 0, "pad": 0}
	var opts: Dictionary = src.get("opts", {})
	var phase: Vector3 = opts.get("phase", Vector3.ZERO)
	var seed := int(phase.x * 1000.0)
	var caps: Array = []
	var lays: Dictionary = {}
	for roof: Dictionary in src.get("roofs", []):
		var hold := float(HOLD.get(str(roof.get("material", "")), DEFAULT_HOLD))
		var lay := PainterMannerBlanket.layout(roof) if blanket else {}
		if not lay.is_empty():
			lays[roof["id"]] = lay
		var n: Vector3 = roof["n"]
		var mid := _mid(roof)
		for e: Dictionary in roof["edges"]:
			var kind := str(e["kind"])
			var before := g.idx.size()
			if CAP_KINDS.has(kind):
				caps.append(
					{
						"a": e["a"],
						"b": e["b"],
						"n": n,
						"mid": mid,
						"hold": hold,
						"roof": roof["id"],
						"blanket": not lay.is_empty(),
						"edge": e,
					}
				)
			elif LIP_KINDS.has(kind) and lay.is_empty():
				var s := 1.0 if kind == "eave" else VERGE_SCALE
				var seg := SEG_EAVE_M if kind == "eave" else SEG_VERGE_M
				_lip(g, e["a"], e["b"], n, mid, hold * s, seg, seed + before)
				counts.lip += (g.idx.size() - before) / 3
	for roof: Dictionary in src.get("roofs", []):
		if not lays.has(roof["id"]):
			continue
		var lay: Dictionary = lays[roof["id"]]
		var partners := {}
		for cap: Dictionary in caps:
			if cap["roof"] != roof["id"]:
				continue
			var other := _partner(cap, caps)
			if other.is_empty():
				continue
			var which := "ridge"
			if cap["edge"] == lay["left_edge"]:
				which = "left"
			elif cap["edge"] == lay["right_edge"]:
				which = "right"
			partners[which] = other["n"]
		var hold := float(HOLD.get(str(roof.get("material", "")), DEFAULT_HOLD))
		counts.blanket += PainterMannerBlanket.lay_into(
			g, roof, lay, partners, hold, phase, seed + g.pos.size()
		)
	var before_caps := g.idx.size()
	for cap: Dictionary in caps:
		if not cap["blanket"]:
			_cap(g, cap, _partner(cap, caps), seed)
	counts.cap = (g.idx.size() - before_caps) / 3
	var before_pads := g.idx.size()
	for pad: Dictionary in src.get("pads", []):
		_pad(g, pad)
		if str(pad["kind"]) == "chimney":
			_collar(g, pad, src.get("roofs", []), lays, phase)
	counts.pad = (g.idx.size() - before_pads) / 3
	if g.idx.is_empty():
		return {"arrays": [], "triangles": 0, "by_kind": counts}
	for k in g.pos.size():
		g.pos[k] += PainterMannerMesh.wander_at(g.pos[k], opts)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = g.pos
	arrays[Mesh.ARRAY_NORMAL] = g.nor
	var colours := PackedColorArray()
	colours.resize(g.pos.size())
	colours.fill(Color(1, 1, 1, 1))
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_TEX_UV2] = g.uv2
	arrays[Mesh.ARRAY_CUSTOM0] = g.cus
	arrays[Mesh.ARRAY_INDEX] = g.idx
	return {"arrays": arrays, "triangles": g.idx.size() / 3, "by_kind": counts}


## The strips' arrays as they grow.
class Strips:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var cus := PackedFloat32Array()
	var idx := PackedInt32Array()

	func add(p: Vector3, n: Vector3, along: float, step: float, size: Vector2, acc: float) -> int:
		return put(p, n, Vector2(along, step), PackedFloat32Array([size.x, size.y, float(CODE), acc]))

	## A vertex with its own UV2 and CUSTOM0 (`data`, four floats).
	func put(p: Vector3, n: Vector3, uv: Vector2, data: PackedFloat32Array) -> int:
		pos.append(p)
		nor.append(n.normalized())
		uv2.append(uv)
		cus.append_array(data)
		return pos.size() - 1

	## Triangle (a, b, c) wound so its front faces along `facing` (clockwise seen from the front,
	## Godot's front face: the face normal is cross(c - a, b - a)).
	func tri(a: int, b: int, c: int, facing: Vector3) -> void:
		if (pos[c] - pos[a]).cross(pos[b] - pos[a]).dot(facing) < 0.0:
			idx.append_array(PackedInt32Array([a, c, b]))
		else:
			idx.append_array(PackedInt32Array([a, b, c]))

	## The quads between two rows of `count` profile vertices (`r0` and `r1` the first index of
	## each), each facing the mean normal of its corners.
	func band(r0: int, r1: int, count: int) -> void:
		for j in count - 1:
			var facing := nor[r0 + j] + nor[r0 + j + 1] + nor[r1 + j] + nor[r1 + j + 1]
			tri(r0 + j, r1 + j, r1 + j + 1, facing)
			tri(r0 + j, r1 + j + 1, r0 + j + 1, facing)

	## A fan closing a strip's end (`r` the row's first index, `count` profile vertices) facing
	## `out`.
	func end_cap(r: int, count: int, out: Vector3) -> void:
		for j in range(1, count - 1):
			tri(r, r + j, r + j + 1, out)


## A smooth swell along an edge, about 0.65 to 1.35 (`s` metres along it, `seed` per edge): the
## heaped, scalloped outline of a lip. Pure.
static func swell(s: float, seed: int) -> float:
	var ph := float(seed % 997) * 0.37
	return 1.0 + 0.22 * sin(s * 1.7 + ph) + 0.13 * sin(s * 4.1 + ph * 2.3)


## The hang of a lip's scallops along its edge, 0 to 1 (`s` metres along it, `seed` per edge):
## about one scallop a metre, each its own width. Pure.
static func scallop(s: float, seed: int) -> float:
	var ph := float(seed % 991) * 0.53
	return 0.5 + 0.5 * sin(s * 6.6 + ph + 0.9 * sin(s * 2.3 + ph))


## The direction in the slope's plane (normal `n`) across edge a-b, away from the slope's middle
## `mid`. Pure.
static func outward(a: Vector3, b: Vector3, n: Vector3, mid: Vector3) -> Vector3:
	var o := n.cross((b - a).normalized()).normalized()
	return o if o.dot((a + b) * 0.5 - mid) >= 0.0 else -o


## A lip along edge a-b of a slope with normal `n` (four profile steps: inner, top, nose, under).
static func _lip(
	g: Strips, a: Vector3, b: Vector3, n: Vector3, mid: Vector3, hold: float, seg: float, seed: int
) -> void:
	var length := a.distance_to(b)
	if length < 0.2:
		return
	var o := outward(a, b, n, mid)
	var along := (b - a) / length
	var count := maxi(1, ceili(length / seg))
	var size := Vector2(length, 3.0)
	var acc := float(seed % 1000) / 1000.0
	var first := g.pos.size()
	for i in count + 1:
		var s := length * float(i) / count
		var p := a + along * s
		var sw := swell(s, seed)
		var end := minf(minf(s, length - s) / 0.35, 1.0)
		var t := LIP_T_M * hold * sw * lerpf(0.6, 1.0, end)
		var reach := LIP_IN_M * hold * (2.0 - sw)
		var over := LIP_OVER_M * hold * sw * lerpf(0.5, 1.0, end) * (1.0 + 0.25 * sin(s * 3.3 + seed))
		var droop := LIP_DROOP_M * hold * scallop(s, seed) * end
		g.add(p - o * reach - n * 0.015, n, s, 0.0, size, acc)
		g.add(p - o * reach * 0.3 + n * t, n + o * 0.35, s, 1.0, size, acc)
		g.add(p + o * over + n * t * 0.3 - Vector3.UP * droop * 0.5, o + n * 0.25, s, 2.0, size, acc)
		g.add(p + o * over * 0.4 - n * t * 0.3 - Vector3.UP * droop, o * 0.4 - n, s, 3.0, size, acc)
	for i in count:
		g.band(first + i * 4, first + (i + 1) * 4, 4)
	g.end_cap(first, 4, -along)
	g.end_cap(first + count * 4, 4, along)


## The cap edge of another roof that runs beside `cap` (nearly parallel, its line within
## PAIR_M): the other half of a ridge, or the neighbour face of a hip; {} for none. Pure.
static func _partner(cap: Dictionary, caps: Array) -> Dictionary:
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	var dir := (b - a).normalized()
	var mid := (a + b) * 0.5
	var best: Dictionary = {}
	var best_d := PAIR_M
	for other: Dictionary in caps:
		if other["roof"] == cap["roof"]:
			continue
		var oa: Vector3 = other["a"]
		var od := ((other["b"] as Vector3) - oa).normalized()
		if absf(od.dot(dir)) < 0.95:
			continue
		var d := (mid - (oa + od * (mid - oa).dot(od))).length()
		if d < best_d:
			best_d = d
			best = other
	return best


## Half a ridge (or hip) cap along `cap`'s edge (three profile steps: inner, shoulder, crest). The
## crest runs midway to its `partner`'s edge, at the same height and swell on both halves (the
## swell follows the world, not the edge), so the two halves meet in one soft crest; with no
## partner it stands over the edge.
static func _cap(g: Strips, cap: Dictionary, partner: Dictionary, seed: int) -> void:
	var a: Vector3 = cap["a"]
	var b: Vector3 = cap["b"]
	var n: Vector3 = cap["n"]
	var hold := float(cap["hold"])
	var length := a.distance_to(b)
	if length < 0.2:
		return
	var o := outward(a, b, n, cap["mid"])
	var along := (b - a) / length
	var canon := along if along.x > 0.001 or (absf(along.x) <= 0.001 and along.z >= 0.0) else -along
	var count := maxi(1, ceili(length / SEG_RIDGE_M))
	var size := Vector2(length, 2.0)
	var first := g.pos.size()
	for i in count + 1:
		var s := length * float(i) / count
		var p := a + along * s
		var sw := swell(p.dot(canon), seed + 7)
		var t := CAP_T_M * hold * sw
		var reach := CAP_IN_M * hold * (2.0 - sw)
		var crest := p
		if not partner.is_empty():
			var pa: Vector3 = partner["a"]
			var pd := ((partner["b"] as Vector3) - pa).normalized()
			var q := pa + pd * (p - pa).dot(pd)
			crest = (p + q) * 0.5
			crest.y = maxf(p.y, q.y)
		g.add(p - o * reach - n * 0.015, n, s, 0.0, size, 0.5)
		g.add(p - o * reach * 0.35 + n * t * 0.75, n + Vector3.UP, s, 1.0, size, 0.5)
		g.add(crest + Vector3.UP * t, Vector3.UP, s, 2.0, size, 0.5)
	for i in count:
		g.band(first + i * 3, first + (i + 1) * 3, 3)
	g.end_cap(first, 3, -along)
	g.end_cap(first + count * 3, 3, along)


## A chimney's cushion (rim, shoulder ring, crown: 12 triangles) or a sill's wedge (back, top,
## front lip: 4 triangles).
static func _pad(g: Strips, pad: Dictionary) -> void:
	var c: Vector3 = pad["centre"]
	var ha: Vector3 = pad["a"]
	var hb: Vector3 = pad["b"]
	var size := Vector2(ha.length() * 2.0, 2.0)
	if str(pad["kind"]) == "sill":
		var out: Vector3 = pad["out"]
		var depth := hb.length()
		var along := ha
		var rows: Array[int] = []
		for side: float in [-1.0, 1.0]:
			var p := c + along * side * 0.97
			rows.append(g.pos.size())
			g.add(p - out * depth + Vector3.UP * 0.005, Vector3.UP, 0.0, 0.0, size, 0.5)
			g.add(p + out * depth * 0.2 + Vector3.UP * SILL_T_M, Vector3.UP + out * 0.4, 0.0, 1.0, size, 0.5)
			g.add(p + out * (depth + 0.025) + Vector3.UP * SILL_T_M * 0.2, out, 0.0, 2.0, size, 0.5)
		g.band(rows[0], rows[1], 3)
		return
	var rim := g.pos.size()
	var corners := [-ha - hb, ha - hb, ha + hb, -ha + hb]
	for corner: Vector3 in corners:
		var dir := Vector3(corner.x, 0.0, corner.z).normalized()
		g.add(c + corner * 1.08 - Vector3.UP * 0.02, dir + Vector3.UP * 0.3, 0.0, 0.0, size, 0.5)
	var ring := g.pos.size()
	for corner: Vector3 in corners:
		var dir := Vector3(corner.x, 0.0, corner.z).normalized()
		g.add(c + corner * 0.8 + Vector3.UP * PAD_T_M * 0.75, Vector3.UP + dir * 0.6, 0.0, 1.0, size, 0.5)
	var crown := g.add(c + Vector3.UP * PAD_T_M, Vector3.UP, 0.0, 2.0, size, 0.5)
	for j in 4:
		var k := (j + 1) % 4
		var facing := g.nor[rim + j] + g.nor[rim + k]
		g.tri(rim + j, ring + j, ring + k, facing)
		g.tri(rim + j, ring + k, rim + k, facing)
		g.tri(ring + j, crown, ring + k, Vector3.UP)


## A chimney's drift collar (16 triangles): where its stack (`pad`, the cap's or the stack's top)
## meets the highest roof slope of `roofs` under it, a ring of snow against the stack's sides,
## heaped and reaching further on the uphill side, sloping down to the roof. Nothing when no slope
## lies under the stack.
static func _collar(
	g: Strips, pad: Dictionary, roofs: Array, lays: Dictionary, phase: Vector3
) -> void:
	var c: Vector3 = pad["centre"]
	var roof: Dictionary = {}
	var best := -INF
	for r: Dictionary in roofs:
		var y := _plane_y(r, c)
		if is_nan(y) or y >= c.y or y <= best:
			continue
		var d := Vector3(c.x, y, c.z) - (r["origin"] as Vector3)
		var du := d.dot(r["u"])
		var dv := d.dot(r["v"])
		if du > -0.1 and du < float(r["u_len"]) + 0.1 and dv > -0.1 and dv < float(r["v_len"]) + 0.1:
			best = y
			roof = r
	if roof.is_empty():
		return
	var n: Vector3 = roof["n"]
	var uphill := -Vector3(n.x, 0.0, n.z).normalized()
	var hold := float(HOLD.get(str(roof.get("material", "")), DEFAULT_HOLD))
	var lay: Dictionary = lays.get(roof["id"], {})
	var ha: Vector3 = pad["a"]
	var hb: Vector3 = pad["b"]
	var size := Vector2(ha.length() * 2.0, 2.0)
	var offs := [-ha - hb, -hb, ha - hb, ha, ha + hb, hb, -ha + hb, -ha]
	var rim := g.pos.size()
	for off: Vector3 in offs:
		var dir := Vector3(off.x, 0.0, off.z).normalized()
		var heap := maxf(dir.dot(uphill), 0.0)
		var p := c + off * (COLLAR_REACH + 0.8 * heap)
		p.y = _plane_y(roof, p) + _on_blanket(roof, lay, hold, p, phase) - 0.03
		g.add(p, n, 0.0, 0.0, size, 0.5)
	for off: Vector3 in offs:
		var dir := Vector3(off.x, 0.0, off.z).normalized()
		var heap := maxf(dir.dot(uphill), 0.0)
		var p := c + off * 1.05
		var rise := COLLAR_T_M * hold * (0.5 + heap)
		p.y = _plane_y(roof, p) + _on_blanket(roof, lay, hold, p, phase) + rise
		g.add(p, n + dir * 0.6 + Vector3.UP * 0.4, 0.0, 1.0, size, 0.5)
	var ring := rim + offs.size()
	for j in offs.size():
		var k := (j + 1) % offs.size()
		var facing := g.nor[ring + j] + g.nor[ring + k]
		g.tri(rim + j, ring + j, ring + k, facing)
		g.tri(rim + j, ring + k, rim + k, facing)


## The height of roof slope `r`'s plane over map point `p` (its x and z); NAN for a slope that
## stands near upright. Pure.
static func _plane_y(r: Dictionary, p: Vector3) -> float:
	var n: Vector3 = r["n"]
	if n.y < 0.2:
		return NAN
	var o: Vector3 = r["origin"]
	return o.y - (n.x * (p.x - o.x) + n.z * (p.z - o.z)) / n.y


## How far the blanket of slope `r` (layout `lay`, {} for none) stands above its plane over map
## point `p`, measured upright. Pure.
static func _on_blanket(
	r: Dictionary, lay: Dictionary, hold: float, p: Vector3, phase: Vector3
) -> float:
	if lay.is_empty():
		return 0.0
	var n: Vector3 = r["n"]
	return PainterMannerBlanket.depth_at(r, lay, hold, p, phase) / maxf(n.y, 0.2)


## The middle of roof record `r`'s frame. Pure.
static func _mid(r: Dictionary) -> Vector3:
	return (
		(r["origin"] as Vector3)
		+ (r["u"] as Vector3) * float(r["u_len"]) * 0.5
		+ (r["v"] as Vector3) * float(r["v_len"]) * 0.5
	)


## The chimney caps and window sills of a structure, read from the vertices of the pieces that
## made them (their record frames do not say which way a box's thickness runs): per piece its top
## (highest vertex) and its extent along its two most level axes. A chimney's cap is used where it
## has one, else its stack; of two sills within 0.3 m (a facade's and its glazing's) the higher.
static func _pads(
	records: Dictionary, meshes: Dictionary, table: PackedStringArray, opts: Dictionary
) -> Array:
	var wanted: Array = []
	for path in table:
		var rec: Variant = records.get(path)
		var kind := str(rec["kind"]) if rec != null else ""
		wanted.append(rec if kind == "chimney" or kind == "sill" else null)
	var pts: Dictionary = {}
	for mesh_name: String in meshes:
		if not _top_mesh(mesh_name):
			continue
		var mesh: Dictionary = meshes[mesh_name]
		var tags: PackedInt32Array = mesh.tags
		var verts: PackedVector3Array = mesh.arrays[Mesh.ARRAY_VERTEX]
		for k in tags.size():
			var tag := tags[k]
			if tag < 0 or tag >= wanted.size() or wanted[tag] == null:
				continue
			var id := str(wanted[tag]["id"])
			if not pts.has(id):
				pts[id] = []
			# An Array, not a PackedVector3Array: a packed array read from a Dictionary is a copy.
			(pts[id] as Array).append(verts[k])
	var caps: Dictionary = {}
	for id: String in pts:
		var rec: Dictionary = records[id]
		if str(rec["kind"]) == "chimney" and (id.ends_with("/cap") or id.ends_with("/stack")):
			var group := id.get_base_dir()
			if not caps.has(group) or id.ends_with("/cap"):
				caps[group] = id
	var out: Array = []
	var walls: Dictionary = opts.get("walls", {})
	var sills: Array = []
	for id: String in pts:
		var rec: Dictionary = records[id]
		var is_sill := str(rec["kind"]) == "sill"
		if not is_sill and not caps.values().has(id):
			continue
		var top := _top(rec, pts[id])
		if top.is_empty():
			continue
		if is_sill:
			var n: Variant = walls.get(int(rec.get("side", -1)))
			if n == null:
				continue
			top["kind"] = "sill"
			top["out"] = (n as Vector3)
			if (top["b"] as Vector3).dot(n) < 0.0:
				top["b"] = -(top["b"] as Vector3)
			if absf((top["a"] as Vector3).normalized().dot(n)) > 0.7:
				var swap: Vector3 = top["a"]
				top["a"] = top["b"]
				top["b"] = swap
			sills.append(top)
		else:
			top["kind"] = "chimney"
			out.append(top)
	sills.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["top"] > y["top"])
	var kept: Array = []
	for s: Dictionary in sills:
		var near := false
		for k: Dictionary in kept:
			if (k["centre"] as Vector3).distance_to(s["centre"]) < 0.3:
				near = true
				break
		if not near:
			kept.append(s)
	out.append_array(kept)
	return out


static func _top_mesh(mesh_name: String) -> bool:
	for prefix in TOP_MESHES:
		if mesh_name.begins_with(prefix):
			return true
	return false


## A piece's top: {"centre" (on the top, at its highest vertex's height), "a", "b" (half axes along
## the record's two most level axes, the longer first), "top"}; {} for a piece with no level top.
static func _top(rec: Dictionary, pts: Array) -> Dictionary:
	var axes: Array[Vector3] = []
	for key in ["u", "v", "n"]:
		var ax: Vector3 = rec[key]
		if absf(ax.y) < 0.3:
			axes.append(Vector3(ax.x, 0.0, ax.z).normalized())
	if axes.size() < 2 or pts.is_empty():
		return {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var top := -INF
	for p: Vector3 in pts:
		var q := Vector2(p.dot(axes[0]), p.dot(axes[1]))
		lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
		hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		top = maxf(top, p.y)
	var half := (hi - lo) * 0.5
	var mid := (hi + lo) * 0.5
	var centre := axes[0] * mid.x + axes[1] * mid.y
	centre.y = top
	var a := axes[0] * half.x
	var b := axes[1] * half.y
	if half.y > half.x:
		var swap := a
		a = b
		b = swap
	return {"centre": centre, "a": a, "b": b, "top": top}
