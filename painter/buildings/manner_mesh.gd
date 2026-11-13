class_name PainterMannerMesh
extends RefCounted

## The hand-drawn manner's mesh (card painter-manner's choice B, PainterMannerHost): a built
## structure's recipe mesh redrawn with procgen's manner data (procgen docs/manner_data.md) for a
## stroke pass that costs about what the recipe costs.
##
## The model. A structure's meshes are in the map frame and every vertex carries the tag of the
## piece that made it (AuthoredStructures.TAGS_META); the manner records give each piece a frame
## (origin, u, v, n, u_len, v_len) and a kind. From them, per mesh, pure and worker-safe:
##   draw    the mesh cut along its long horizontal edges where the piece wanders (walls, roof
##           slopes, gable ends, the ridge: one cut per SEG_M metres, a rule per edge so the two
##           triangles on an edge agree), every vertex moved by one smooth field per building
##           (`wander`: a lean that grows with height, eaves and ridges that wobble), and per vertex
##           the piece's own coordinates in metres (UV2) and [u_len, v_len, code, accent] (CUSTOM0)
##           so a shader draws strokes along the piece instead of along the world;
##   shadow  the uncut mesh moved by the same field: the shadow pass keeps the recipe's triangles;
##   fringe  a thatch roof's ragged teeth, a few triangles along each eave, appended to the draw.
## Nothing here reads the scene tree; the same inputs give the same arrays.

const CODE_NONE := 0
const CODE_WALL := 1
const CODE_ROOF := 2
const CODE_GABLE := 3
const CODE_BOX := 4
const CODE_LEAF := 5
const CODE_RIDGE := 6
const CODE_FRINGE := 7
## A record kind's code in CUSTOM0.z.
const CODES: Dictionary = {
	"wall_face": CODE_WALL,
	"coping": CODE_WALL,
	"roof_slope": CODE_ROOF,
	"gable_end": CODE_GABLE,
	"beam": CODE_BOX,
	"frame": CODE_BOX,
	"sill": CODE_BOX,
	"shutter": CODE_BOX,
	"door_case": CODE_BOX,
	"chimney": CODE_BOX,
	"door_leaf": CODE_LEAF,
	"door_panel": CODE_LEAF,
	"ridge": CODE_RIDGE,
}
## Codes whose triangles are cut so the wander bends them.
## (Walls are not cut: their openings' corners already give the lean enough vertices, and cutting
## them more than doubled the recipe's triangles in round 1.)
const CUT_CODES: Array[int] = [CODE_ROOF, CODE_GABLE, CODE_RIDGE]
## The longest horizontal run of a cut edge, metres.
const SEG_M := 1.0
## A thatch tooth's width along the eave, metres, and its length when the record has no fringe.
const TOOTH_M := 0.2
const TOOTH_LEN_M := 0.22
const FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


## The wander at map point `p` (`foot` the wall foot and `eave` the eave height, map Y; `phase` from
## the structure's seed), three terms:
##   lean  horizontal, `amp` metres a 3 m of height (none at the foot, so the building stays
##         planted), of about 20 m wavelength: each house leans its own way, a wall stays near
##         flat between the vertices it already has (its openings' corners), so trim stays on it;
##   bow   horizontal, about 4.5 m, only above the eave: eaves, verges and ridges bend;
##   wob   vertical, about 3 m, grows with height: an eave or ridge line rises and dips.
## Pure.
static func wander(
	p: Vector3, amp: float, phase: Vector3, foot: float, eave: float = 0.0
) -> Vector3:
	var w := clampf((p.y - foot) / 3.0, 0.0, 2.0)
	var r := smoothstep(eave - 0.3, eave + 1.0, p.y) if eave > foot else 0.0
	var lean := Vector3(
		sin(p.z * 0.3 + p.x * 0.2 + phase.x), 0.0, sin(p.x * 0.3 - p.z * 0.25 + phase.y)
	)
	var bow := Vector3(
		sin(p.z * 1.4 + p.x * 0.9 + phase.y), 0.0, sin(p.x * 1.3 + p.z * 1.1 + phase.z)
	)
	var wob := (
		0.6 * sin(p.x * 1.9 + p.z * 1.3 + phase.z) + 0.4 * sin(p.z * 2.6 - p.x * 1.1 + phase.x)
	)
	return (lean * w + bow * 0.45 * r + Vector3.UP * wob * 0.35 * minf(w, 1.0)) * amp


## wander() with its numbers from `field` ({"amp", "phase", "foot", "eave"}). Pure.
static func wander_at(p: Vector3, field: Dictionary) -> Vector3:
	return wander(
		p,
		float(field.get("amp", 0.0)),
		field.get("phase", Vector3.ZERO),
		float(field.get("foot", 0.0)),
		float(field.get("eave", 0.0))
	)


## The field's phase for a structure seed. Pure.
static func phase_of(seed_value: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	return Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


## The record of every vertex (null where none, or of a kind with no code). Pure.
static func records_of(
	tags: PackedInt32Array, table: PackedStringArray, records: Dictionary
) -> Array:
	var by_tag: Array = []
	for path in table:
		var rec: Variant = records.get(path)
		by_tag.append(rec if rec != null and CODES.has(str(rec["kind"])) else null)
	var out: Array = []
	out.resize(tags.size())
	for k in tags.size():
		out[k] = by_tag[tags[k]] if tags[k] >= 0 and tags[k] < by_tag.size() else null
	return out


## The draw, shadow and fringe arrays of one mesh (see the header). `arrays` a surface's arrays
## (map frame), `tags` its per-vertex tags, `table` the structure's tag table, `records` path ->
## record. `opts`: the field ({"amp", "phase", "foot", "eave"}, wander_at) and "cut", "fringe".
## Returns {"draw", "shadow",
## "triangles": [source, draw, shadow]}. Pure.
static func build(
	arrays: Array,
	tags: PackedInt32Array,
	table: PackedStringArray,
	records: Dictionary,
	opts: Dictionary
) -> Dictionary:
	var src: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colours := PackedColorArray()
	if arrays[Mesh.ARRAY_COLOR] != null:
		colours = arrays[Mesh.ARRAY_COLOR]
	if colours.size() != src.size():
		colours.resize(src.size())
		colours.fill(Color(1, 1, 1, 0))
	var index := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		index = arrays[Mesh.ARRAY_INDEX]
	if index.is_empty():
		for k in src.size():
			index.append(k)
	var recs := records_of(tags, table, records)
	var m := Grow.new()
	for k in src.size():
		m.add(src[k], normals[k], colours[k], recs[k])
	var cut_idx := PackedInt32Array()
	var mids: Dictionary = {}
	for t in range(0, index.size() - 2, 3):
		var tri := [index[t], index[t + 1], index[t + 2]]
		if bool(opts.get("cut", true)) and CUT_CODES.has(m.code(tri[0])):
			_cut(m, tri, mids, cut_idx)
		else:
			cut_idx.append_array(PackedInt32Array(tri))
	if bool(opts.get("fringe", true)):
		_fringe(m, recs, colours, cut_idx)
	for k in m.pos.size():
		m.pos[k] += wander_at(m.pos[k], opts)
	var moved := src.duplicate()
	for k in moved.size():
		moved[k] += wander_at(moved[k], opts)
	var shadow := arrays.duplicate()
	shadow[Mesh.ARRAY_VERTEX] = moved
	var draw: Array = []
	draw.resize(Mesh.ARRAY_MAX)
	draw[Mesh.ARRAY_VERTEX] = m.pos
	draw[Mesh.ARRAY_NORMAL] = m.nor
	draw[Mesh.ARRAY_COLOR] = m.col
	draw[Mesh.ARRAY_TEX_UV2] = m.uv2
	draw[Mesh.ARRAY_CUSTOM0] = m.cus
	draw[Mesh.ARRAY_INDEX] = cut_idx
	return {
		"draw": draw,
		"shadow": shadow,
		"triangles": [index.size() / 3, cut_idx.size() / 3, index.size() / 3]
	}


## A mesh's arrays as they grow (the cut's midpoints and the fringe's teeth are appended).
class Grow:
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var col := PackedColorArray()
	var uv2 := PackedVector2Array()
	var cus := PackedFloat32Array()

	func add(p: Vector3, n: Vector3, c: Color, rec: Variant) -> int:
		pos.append(p)
		nor.append(n)
		col.append(c)
		if rec == null:
			uv2.append(Vector2.ZERO)
			cus.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.5]))
		else:
			var r: Dictionary = rec
			var d: Vector3 = p - (r["origin"] as Vector3)
			uv2.append(Vector2(d.dot(r["u"]), d.dot(r["v"])))
			cus.append_array(
				PackedFloat32Array(
					[
						float(r["u_len"]),
						float(r["v_len"]),
						float(CODES[str(r["kind"])]),
						float(r.get("accent", 0.5))
					]
				)
			)
		return pos.size() - 1

	func code(k: int) -> int:
		return int(cus[k * 4 + 2])

	## The midpoint of `a` and `b`, made once per edge.
	func mid(a: int, b: int, mids: Dictionary) -> int:
		var key := Vector2i(mini(a, b), maxi(a, b))
		if mids.has(key):
			return mids[key]
		pos.append((pos[a] + pos[b]) * 0.5)
		nor.append((nor[a] + nor[b]).normalized())
		col.append(col[a].lerp(col[b], 0.5))
		uv2.append((uv2[a] + uv2[b]) * 0.5)
		cus.append_array(cus.slice(a * 4, a * 4 + 4))
		mids[key] = pos.size() - 1
		return pos.size() - 1


## Cuts triangle `tri` at the middle of its longest horizontal edge until none is over SEG_M.
static func _cut(m: Grow, tri: Array, mids: Dictionary, out: PackedInt32Array) -> void:
	var stack: Array = [tri]
	while not stack.is_empty():
		var t: Array = stack.pop_back()
		var best := -1
		var best_len := SEG_M
		for e in 3:
			var d: Vector3 = m.pos[t[(e + 1) % 3]] - m.pos[t[e]]
			var h := Vector2(d.x, d.z).length()
			if h > best_len:
				best_len = h
				best = e
		if best < 0:
			out.append_array(PackedInt32Array(t))
			continue
		var a: int = t[best]
		var b: int = t[(best + 1) % 3]
		var c: int = t[(best + 2) % 3]
		var mi := m.mid(a, b, mids)
		stack.append([a, mi, c])
		stack.append([mi, b, c])


## A thatch roof's teeth: along every eave edge of a thatch roof slope with vertices in this mesh,
## one thin wedge (front and back) per TOOTH_M, hanging down the slope by about the record's fringe.
static func _fringe(m: Grow, recs: Array, colours: PackedColorArray, out: PackedInt32Array) -> void:
	var seen: Dictionary = {}
	for k in recs.size():
		var rec: Variant = recs[k]
		if rec == null or str(rec["kind"]) != "roof_slope" or seen.has(str(rec["id"])):
			continue
		seen[str(rec["id"])] = true
		if str(rec.get("material", "")) != "thatch":
			continue
		var r: Dictionary = rec
		var tooth := float(r.get("fringe", 0.0))
		tooth = tooth if tooth > 0.05 else TOOTH_LEN_M
		var colour := colours[k]
		colour.a = 0.0
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(r["id"]))
		var n: Vector3 = r["n"]
		var down: Vector3 = r.get("down", -(r["v"] as Vector3))
		for e: Dictionary in r.get("edges", []):
			if str(e["kind"]) != "eave":
				continue
			var a: Vector3 = e["a"]
			var b: Vector3 = e["b"]
			var count := maxi(1, int((b - a).length() / TOOTH_M))
			for i in count:
				var p0 := a.lerp(b, float(i) / count) + n * 0.012
				var p1 := a.lerp(b, float(i + 1) / count) + n * 0.012
				var reach := tooth * rng.randf_range(0.55, 1.45)
				var side := (b - a).normalized() * rng.randf_range(-0.06, 0.06)
				var tip := (p0 + p1) * 0.5 + down * reach + side
				var i0 := m.add(p0, n, colour, r)
				var i1 := m.add(p1, n, colour, r)
				var i2 := m.add(tip, n, colour, r)
				for j in [i0, i1, i2]:
					m.cus[j * 4 + 2] = float(CODE_FRINGE)
				out.append_array(PackedInt32Array([i0, i2, i1, i0, i1, i2]))
