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
##   fringe  a thatch roof's ragged teeth, a few triangles along each eave, appended to the draw;
##   hand    a half-timber beam cut every BEAM_SEG_M along its axis, widened on both long sides
##           by a brush width that wanders (`brush_at`) and bowed between its ends, so its edges
##           read brushed and it stands a little crooked; a window frame or door case widened by
##           a share of that brush; a door leaf and its panels lean away from the leaf's hinge
##           (`door_dir`; `door_lean` where no leaf has one), one way per building;
##   stand-off a wall's trim (procgen's `side`, `proud`) at least MIN_PROUD_M off its wall's face,
##           so the uncut wall never buries a sill or a beam;
##   collider the structure's collision faces moved by the same field (and cut like the roof
##           where they lie above the walls), so a click and a standing token meet what is drawn.
## Nothing here reads the scene tree; the same inputs give the same arrays.

const CODE_NONE := 0
const CODE_WALL := 1
const CODE_ROOF := 2
const CODE_GABLE := 3
const CODE_BOX := 4
const CODE_LEAF := 5
const CODE_RIDGE := 6
const CODE_FRINGE := 7
const CODE_FLAT := 8
## A record kind's code in CUSTOM0.z (a wall face's course in metres rides in its fraction). A
## piece of a kind not listed (or with no record: round and profile roofs, a Taper's pieces,
## ornaments) draws the A3b patterns on the same wandered mesh, so it meets its neighbours.
const CODES: Dictionary = {
	"wall_face": CODE_WALL,
	"coping": CODE_WALL,
	"roof_slope": CODE_ROOF,
	"roof_part": CODE_ROOF,
	"roof_flat": CODE_FLAT,
	"gable_end": CODE_GABLE,
	"beam": CODE_BOX,
	"frame": CODE_BOX,
	"sill": CODE_BOX,
	"shutter": CODE_BOX,
	"door_case": CODE_BOX,
	"chimney": CODE_BOX,
	"block": CODE_BOX,
	"step": CODE_BOX,
	"cornice": CODE_BOX,
	"quoin": CODE_BOX,
	"parapet": CODE_BOX,
	"viga": CODE_BOX,
	"door_leaf": CODE_LEAF,
	"door_panel": CODE_LEAF,
	"ridge": CODE_RIDGE,
}
## Codes whose triangles are cut so the wander bends them.
## (Walls are not cut: their openings' corners already give the lean enough vertices, and cutting
## them more than doubled the recipe's triangles in round 1.)
const CUT_CODES: Array[int] = [CODE_ROOF, CODE_GABLE, CODE_RIDGE]
## A wall's trim (a piece with `side` and `proud`, procgen's stand-off) stands at least this far
## off the face plane: the uncut wall between its vertices strays up to a few centimetres from the
## field its trim follows, and a sill or beam flush with it would be buried there.
const MIN_PROUD_M := 0.03
## The longest horizontal run of a cut edge, metres.
const SEG_M := 1.0
## A thatch tooth's width along the eave, metres, and its length when the record has no fringe.
const TOOTH_M := 0.2
const TOOTH_LEN_M := 0.22
## A beam's cut along its axis, metres (a 3 m post in two, a 6 m plate in four; its back face,
## in the wall, is not cut; a finer cut tripled a post's triangles), and its brush: each long
## side moves out by BEAM_WIDEN_M plus up to BEAM_WANDER_M of a smooth wander along the beam, and
## the whole beam bows across itself by up to BEAM_BOW_M between its ends (card
## painter-buildings-fix: straight timbers read as a second, ruled hand beside the thatch
## cottage's). A window frame or door case widens by FRAME_BRUSH of a beam's brush (its edges a
## little soft), uncut.
const BEAM_SEG_M := 1.6
const BEAM_WIDEN_M := 0.016
const BEAM_WANDER_M := 0.04
const BEAM_BOW_M := 0.09
const FRAME_BRUSH := 0.6
const FRAME_KINDS: Array[String] = ["frame", "door_case"]
## A chimney's plan grows by CHIMNEY_SCALE plus up to CHIMNEY_VARY by building (card
## painter-look-houses3: small pale boxes on every house, too small to be an accent at tabletop
## zoom): its stack, cap and pots about one axis, the height unchanged.
const CHIMNEY_SCALE := 1.35
const CHIMNEY_VARY := 0.4
## A door leaf's lean: metres along the wall per metre above the wall foot.
const DOOR_LEAN := 0.045
## A collision triangle is cut like a roof when its lowest point is above this share of the way
## from the wall foot to the eave (walls, cut nowhere in the draw, stay whole).
const COLLIDER_CUT_ABOVE := 0.6
const FORMAT := Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
## The shortest wall edge searched for a T (_wall_ts): the wander's bend across a shorter edge opens
## under a millimetre or two, and the short reveals and sills are most of a wall's edges.
const T_EDGE_M := 0.5
## The mason's hand (hand_at; card painter-buildings-fix4) on a building whose wall faces are
## mostly of these materials: its walls are cut every WALL_SEG_M (in space, so a wall bends up its
## height too), its eave and ridge sag HAND_EAVE_SAG_M and HAND_SAG_M in the middle, its walls
## bow out HAND_BULGE_M at mid-height and its ends lean HAND_LEAN_M a 3 m of height their own ways.
const STONE_WALLS: Array[String] = ["masonry", "stone", "rubble"]
const WALL_SEG_M := 1.1
const HAND_EAVE_SAG_M := 0.09
const HAND_SAG_M := 0.15
const HAND_BULGE_M := 0.06
const HAND_LEAN_M := 0.12
## The shadow caster of a cut piece (the recipe's uncut triangles, wandered) moved this far in
## along its normals: between its vertices the drawn, cut surface strays a few centimetres from
## the caster's chords, and where it fell behind them the piece shadowed itself (card
## painter-buildings-fix4: dark scalloped blots on the stone house's slate roof).
const SHADOW_INSET_M := 0.04


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


## wander() with its numbers from `field` ({"amp", "phase", "foot", "eave"}), plus hand_at() on a
## building with a mason's hand (`field` "hand", hand_frame). Pure.
static func wander_at(p: Vector3, field: Dictionary) -> Vector3:
	var out := wander(
		p,
		float(field.get("amp", 0.0)),
		field.get("phase", Vector3.ZERO),
		float(field.get("foot", 0.0)),
		float(field.get("eave", 0.0))
	)
	if float(field.get("hand", 0.0)) > 0.0:
		out += hand_at(p, field)
	return out


## The mason's hand on a stone-walled building (card painter-buildings-fix4: the stone house read
## as a ruled box beside the timber and thatch houses), three terms in the building's own frame
## (`field` from hand_frame: "centre", "axis" along its long side, "half" its half extents, "top"
## the ridge's height, "foot", "eave", "phase"):
##   sag    down, HAND_EAVE_SAG_M at the middle of the eave and HAND_SAG_M of the ridge, none at
##          the gable ends, growing with height (linear below the eave and above it, at about one
##          rate, so a roof slope stays near a plane across itself and its shadow caster, the
##          recipe's uncut slope, never stands above it): the eave and the ridge sway;
##   bulge  outward from the middle, HAND_BULGE_M at mid-wall, none at the foot or the eave (the
##          walls are cut, WALL_SEG_M, so a wall's face and corners bow; outward only, so the cut
##          wall never falls behind its uncut shadow caster);
##   lean   a second lean of about 11 m wavelength, HAND_LEAN_M a 3 m of height, so the two ends
##          of a house lean their own ways.
## Pure.
static func hand_at(p: Vector3, field: Dictionary) -> Vector3:
	var hand := float(field.get("hand", 0.0))
	var axis: Vector3 = field.get("axis", Vector3.RIGHT)
	var across := Vector3(-axis.z, 0.0, axis.x)
	var half: Vector2 = field.get("half", Vector2.ONE)
	var phase: Vector3 = field.get("phase", Vector3.ZERO)
	var foot := float(field.get("foot", 0.0))
	var eave := float(field.get("eave", foot + 2.5))
	var top := float(field.get("top", eave + 2.0))
	var d: Vector3 = p - (field.get("centre", Vector3.ZERO) as Vector3)
	var ax := clampf(d.dot(axis) / maxf(half.x, 0.5), -1.0, 1.0)
	var az := clampf(d.dot(across) / maxf(half.y, 0.5), -1.0, 1.0)
	var sag := (
		(1.0 - ax * ax)
		* (
			HAND_EAVE_SAG_M * clampf((p.y - foot) / maxf(eave - foot, 0.5), 0.0, 1.0)
			+ (HAND_SAG_M - HAND_EAVE_SAG_M) * clampf((p.y - eave) / maxf(top - eave, 0.5), 0.0, 1.0)
		)
	)
	var prof := sin(PI * clampf((p.y - foot) / maxf(eave - foot, 0.5), 0.0, 1.0))
	var swell := 0.6 + 0.4 * sin(d.dot(axis) * 1.3 + d.dot(across) * 1.1 + phase.x)
	var bulge := (axis * ax + across * az) * HAND_BULGE_M * prof * swell
	var lean := Vector3(
		sin(p.x * 0.55 + p.z * 0.35 + phase.z), 0.0, sin(p.z * 0.55 - p.x * 0.4 + phase.y)
	)
	lean *= HAND_LEAN_M * clampf((p.y - foot) / 3.0, 0.0, 2.0)
	return (Vector3.DOWN * sag + bulge + lean) * hand


## The mason's hand's frame for `records` (hand_at's keys, merged into the field): "hand" 1 when
## most wall faces are stone (STONE_WALLS), else {} (no hand: the field as before). Pure.
static func hand_frame(records: Dictionary, eave: float) -> Dictionary:
	var walls: Array[Dictionary] = []
	var stone := 0
	var top := eave
	for rec: Dictionary in records.values():
		var kind := str(rec["kind"])
		if kind == "wall_face":
			walls.append(rec)
			if STONE_WALLS.has(str(rec.get("material", ""))):
				stone += 1
		elif kind == "roof_slope" or kind == "roof_part":
			var o: Vector3 = rec["origin"]
			top = maxf(top, maxf(o.y, o.y + (rec["v"] as Vector3).y * float(rec["v_len"])))
	if walls.is_empty() or stone * 2 < walls.size():
		return {}
	var centre := Vector3.ZERO
	var longest: Dictionary = walls[0]
	for rec in walls:
		var u: Vector3 = rec["u"]
		centre += (rec["origin"] as Vector3) + u * float(rec["u_len"]) * 0.5
		if float(rec["u_len"]) > float(longest["u_len"]):
			longest = rec
	centre /= walls.size()
	var axis: Vector3 = longest["u"]
	axis.y = 0.0
	axis = axis.normalized() if axis.length_squared() > 0.01 else Vector3.RIGHT
	var hz := 0.5
	for rec in walls:
		if absf((rec["u"] as Vector3).dot(axis)) < 0.5:
			hz = maxf(hz, float(rec["u_len"]) * 0.5)
	return {
		"hand": 1.0,
		"centre": centre,
		"axis": axis,
		"half": Vector2(float(longest["u_len"]) * 0.5, hz),
		"top": maxf(top, eave + 0.5),
	}


## The field's phase for a structure seed. Pure.
static func phase_of(seed_value: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value)
	return Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)


## How far a beam's long side at map point `p` moves out (metres): BEAM_WIDEN_M plus a smooth
## wander of up to BEAM_WANDER_M along the beam. A function of the point only, so the vertices
## two faces share move together. Pure.
static func brush_at(p: Vector3, phase: Vector3) -> float:
	var s := (
		0.6 * sin(p.x * 3.1 + p.y * 2.3 + p.z * 2.7 + phase.x)
		+ 0.4 * sin(p.x * 7.3 - p.y * 5.1 + p.z * 4.4 + phase.z)
	)
	return BEAM_WIDEN_M + BEAM_WANDER_M * (0.5 + 0.5 * s)


## The lean of a door at map point `p` on a wall facing `n`: along the wall, DOOR_LEAN a metre
## above `foot`, to the side `phase` picks for the whole building. Pure.
static func door_lean(p: Vector3, n: Vector3, foot: float, phase: Vector3) -> Vector3:
	var side := Vector3.UP.cross(n)
	side.y = 0.0
	if side.length_squared() < 0.01:
		return Vector3.ZERO
	var sign_of := 1.0 if sin(phase.y * 3.0) >= 0.0 else -1.0
	return side.normalized() * sign_of * maxf(p.y - foot, 0.0) * DOOR_LEAN


## The collision faces `faces` (a triangle soup, map frame) moved by the field `opts` (wander_at),
## the triangles above the walls first cut as the drawn roof is (every SEG_M in plan), so the
## collider follows the drawn lean, eaves and ridges. Pure.
static func collider(faces: PackedVector3Array, opts: Dictionary) -> PackedVector3Array:
	var foot := float(opts.get("foot", 0.0))
	var eave := float(opts.get("eave", 0.0))
	var above := foot + (eave - foot) * COLLIDER_CUT_ABOVE
	var out := PackedVector3Array()
	for t in range(0, faces.size() - 2, 3):
		var tri := [faces[t], faces[t + 1], faces[t + 2]]
		var low := minf(faces[t].y, minf(faces[t + 1].y, faces[t + 2].y))
		if eave <= foot or low < above:
			for p: Vector3 in tri:
				out.append(p)
			continue
		var stack: Array = [tri]
		while not stack.is_empty():
			var s: Array = stack.pop_back()
			var best := -1
			var best_len := SEG_M
			for e in 3:
				var d: Vector3 = s[(e + 1) % 3] - s[e]
				var h := Vector2(d.x, d.z).length()
				if h > best_len:
					best_len = h
					best = e
			if best < 0:
				for p: Vector3 in s:
					out.append(p)
				continue
			var a: Vector3 = s[best]
			var b: Vector3 = s[(best + 1) % 3]
			var c: Vector3 = s[(best + 2) % 3]
			var mid := (a + b) * 0.5
			stack.append([a, mid, c])
			stack.append([mid, b, c])
	for k in out.size():
		out[k] += wander_at(out[k], opts)
	return out


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


## A record's CUSTOM0 (z, w): z its kind's code plus, for a wall face, its course in metres (the
## record's `course`, a boarded wall's `board_width`; at most 0.45) as the fraction; w its accent
## plus, for a hip roof face, its taper (how far its hip runs along the eave a metre up the slope)
## in sixteenths as the whole part. Pure.
static func code_and_accent(r: Dictionary) -> Vector2:
	var code := float(CODES[str(r["kind"])])
	var accent := clampf(float(r.get("accent", 0.5)), 0.0, 1.0) * 0.999
	if str(r["kind"]) == "wall_face":
		var course := float(r.get("course", 0.0))
		if course <= 0.0:
			course = float(r.get("board_width", 0.0))
		code += clampf(course, 0.0, 0.45)
	elif str(r["kind"]) == "roof_slope" and str(r.get("shape", "")).begins_with("hip"):
		var v_len := float(r["v_len"])
		for e: Dictionary in r.get("edges", []):
			if str(e["kind"]) == "hip" and v_len > 0.01:
				var run := absf(((e["b"] as Vector3) - (e["a"] as Vector3)).dot(r["u"]))
				accent += roundf(clampf(run / v_len, 0.0, 4.0) * 16.0)
				break
	return Vector2(code, accent)


## The draw, shadow and fringe arrays of one mesh (see the header). `arrays` a surface's arrays
## (map frame), `tags` its per-vertex tags, `table` the structure's tag table, `records` path ->
## record. `opts`: the field ({"amp", "phase", "foot", "eave"}, wander_at), "cut", "fringe",
## "walls" (wall_normals: the trim's stand-off) and "door_dir" (door_dir: the doors' lean).
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
	_stand_off(m, opts.get("walls", {}))
	var cut_idx := PackedInt32Array()
	var mids: Dictionary = {}
	var cut := bool(opts.get("cut", true))
	var hand_walls := cut and float(opts.get("hand", 0.0)) > 0.0
	# The recipe's wall Ts (source vertices only). A hand's cut walls follow the field closely
	# between short edges, so their drawn Ts open under about 3 mm and are left; the uncut shadow's
	# are closed as everywhere.
	var ts := _wall_ts(m, index)
	for t in range(0, index.size() - 2, 3):
		var tri := [index[t], index[t + 1], index[t + 2]]
		if cut and CUT_CODES.has(m.code(tri[0])):
			_cut(m, tri, mids, cut_idx, SEG_M, Vector3.ZERO)
		elif hand_walls and m.code(tri[0]) == CODE_WALL:
			_cut(m, tri, mids, cut_idx, WALL_SEG_M, Vector3.ZERO, true)
		elif cut and _is_beam(m.rec[tri[0]]) and m.nor[tri[0]].dot(m.rec[tri[0]]["n"]) > -0.5:
			_cut(m, tri, mids, cut_idx, BEAM_SEG_M, m.rec[tri[0]]["u"])
		elif hand_walls:
			# A hand's walls and roof sag in the middle (hand_at), so a long piece along them (a
			# cornice, a string course, a plinth) is cut as the walls are; left whole, its straight
			# middle stood out of the sagging roof above the eave as a pale sliver (card
			# painter-roof-round3, owner: "is some geometry poking out of the roof?").
			_cut(m, tri, mids, cut_idx, WALL_SEG_M, Vector3.ZERO)
		else:
			cut_idx.append_array(PackedInt32Array(tri))
	if bool(opts.get("fringe", true)):
		_fringe(m, recs, colours, cut_idx)
	if cut:
		_hand(m, opts)
	for k in m.pos.size():
		m.pos[k] += wander_at(m.pos[k], opts)
	if not hand_walls:
		m.pos = _close_ts(m.pos, ts)
	var moved := src.duplicate()
	for k in moved.size():
		moved[k] += wander_at(moved[k], opts)
		if cut and CUT_CODES.has(m.code(k)):
			moved[k] -= normals[k] * SHADOW_INSET_M
	# The walls are not cut, so their vertices are the source's, in order.
	moved = _close_ts(moved, ts)
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
	## The record of each vertex (null where none).
	var rec: Array = []
	## Record id -> its CUSTOM0 (z, w) (code_and_accent), made once per piece.
	var _zw: Dictionary = {}

	func add(p: Vector3, n: Vector3, c: Color, r_in: Variant) -> int:
		pos.append(p)
		nor.append(n)
		col.append(c)
		rec.append(r_in)
		var rec_v: Variant = r_in
		if rec_v == null:
			uv2.append(Vector2.ZERO)
			cus.append_array(PackedFloat32Array([0.0, 0.0, 0.0, 0.5]))
		else:
			var r: Dictionary = rec_v
			var d: Vector3 = p - (r["origin"] as Vector3)
			uv2.append(Vector2(d.dot(r["u"]), d.dot(r["v"])))
			var id := str(r["id"])
			if not _zw.has(id):
				_zw[id] = PainterMannerMesh.code_and_accent(r)
			var zw: Vector2 = _zw[id]
			cus.append_array(PackedFloat32Array([float(r["u_len"]), float(r["v_len"]), zw.x, zw.y]))
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
		rec.append(rec[a])
		mids[key] = pos.size() - 1
		return pos.size() - 1


## Cuts triangle `tri` at the middle of its longest edge until none is over `seg` metres, the
## edges measured in space (`space`: a hand's wall), along `axis` (a beam's own) or, where `axis`
## is zero, in plan (so a roof is cut along its eave and ridge only).
static func _cut(
	m: Grow,
	tri: Array,
	mids: Dictionary,
	out: PackedInt32Array,
	seg: float,
	axis: Vector3,
	space: bool = false
) -> void:
	var horizontal := axis == Vector3.ZERO
	var stack: Array = [tri]
	while not stack.is_empty():
		var t: Array = stack.pop_back()
		var best := -1
		var best_len := seg
		for e in 3:
			var d: Vector3 = m.pos[t[(e + 1) % 3]] - m.pos[t[e]]
			var h := (
				d.length() if space else (Vector2(d.x, d.z).length() if horizontal else absf(d.dot(axis)))
			)
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


static func _is_beam(rec: Variant) -> bool:
	return rec != null and str(rec["kind"]) == "beam"


## The Ts of a mesh's wall triangles: [vertex, edge end a, edge end b, share along a-b] for every
## vertex that lies inside another wall triangle's edge (an opening's corner on the long edge
## beside it). The wander bends such an edge's two ends but not the vertex's place on it, and the
## gap, a few millimetres, drew a hairline down the plaster (card painter-buildings-fix3: gaps up
## to 17 mm on the half-timber house; the T's vertex is often another wall record's, a pier's
## beside the opening). Only upright edges, which drew the hairlines: searching the level ones
## too (Ts under sills and at the eave, gaps up to 23 mm on the half-timber house, many under
## beams and the roof) cost a house about 30 ms of its 100 ms build. An upright edge looks for
## its Ts among the vertices in the 5 cm plan cells it passes over. Pure.
static func _wall_ts(m: Grow, idx: PackedInt32Array) -> Array:
	var pos := m.pos
	var by_xz := {}
	var seen := {}
	var edges: Array[Vector2i] = []
	for t in range(0, idx.size() - 2, 3):
		if m.code(idx[t]) != CODE_WALL:
			continue
		for e in 3:
			var a := idx[t + e]
			var b := idx[t + (e + 1) % 3]
			if not seen.has(a):
				seen[a] = true
				var kxz := Vector2i(roundi(pos[a].x * 20.0), roundi(pos[a].z * 20.0))
				if by_xz.has(kxz):
					by_xz[kxz].append(a)
				else:
					by_xz[kxz] = [a]
			var ab := pos[b] - pos[a]
			if absf(ab.y) > T_EDGE_M and absf(ab.y) > 0.95 * ab.length():
				var key := Vector2i(mini(a, b), maxi(a, b))
				if not seen.has(key):
					seen[key] = true
					edges.append(key)
	var found := {}
	for edge in edges:
		var pa := pos[edge.x]
		var pb := pos[edge.y]
		var ab := pb - pa
		var len2 := ab.length_squared()
		var lo := Vector2i(roundi(minf(pa.x, pb.x) * 20.0), roundi(minf(pa.z, pb.z) * 20.0))
		var hi := Vector2i(roundi(maxf(pa.x, pb.x) * 20.0), roundi(maxf(pa.z, pb.z) * 20.0))
		for i in range(lo.x - 1, hi.x + 2):
			for j in range(lo.y - 1, hi.y + 2):
				var cell: Variant = by_xz.get(Vector2i(i, j))
				if cell == null:
					continue
				for k: int in cell:
					if k == edge.x or k == edge.y or found.has(k):
						continue
					var p := pos[k]
					var s := (p - pa).dot(ab) / len2
					if s > 0.001 and s < 0.999 and p.distance_squared_to(pa + ab * s) < 1e-6:
						found[k] = [k, edge.x, edge.y, s]
	return found.values()


## `pos` with every T's vertex back on its edge (`ts` from _wall_ts; twice, for a T whose edge
## ends on another T). Pure.
static func _close_ts(pos: PackedVector3Array, ts: Array) -> PackedVector3Array:
	for _pass in 2:
		for t: Array in ts:
			pos[t[0]] = pos[t[1]].lerp(pos[t[2]], float(t[3]))
	return pos


## The outward normal of each wall face by its footprint side (`walls` for build's opts). Pure.
static func wall_normals(records: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for rec: Dictionary in records.values():
		if str(rec["kind"]) == "wall_face" and rec.has("side"):
			out[int(rec["side"])] = rec["n"]
	return out


## The lean of the building's doors (`door_dir` for build's opts): along the first door leaf with
## a hinge, away from its hinge (the free edge's top leans out over the step); ZERO with none.
## Pure.
static func door_dir(records: Dictionary) -> Vector3:
	for rec: Dictionary in records.values():
		if str(rec["kind"]) != "door_leaf" or not rec.has("hinge_side"):
			continue
		var u: Vector3 = rec["u"]
		u.y = 0.0
		if u.length_squared() < 0.01:
			continue
		return u.normalized() * (1.0 if str(rec["hinge_side"]) == "u0" else -1.0)
	return Vector3.ZERO


## Every vertex of a wall's trim (a record with `side` and `proud` >= 0) moved out along its
## wall's normal until the piece stands MIN_PROUD_M off the face plane.
static func _stand_off(m: Grow, walls: Dictionary) -> void:
	if walls.is_empty():
		return
	var lifts: Dictionary = {}
	for k in m.pos.size():
		var rec: Variant = m.rec[k]
		if rec == null or not rec.has("proud") or not rec.has("side"):
			continue
		var id := str(rec["id"])
		if not lifts.has(id):
			var proud := float(rec["proud"])
			var n: Variant = walls.get(int(rec["side"]))
			var lift := clampf(MIN_PROUD_M - proud, 0.0, MIN_PROUD_M)
			lifts[id] = (n as Vector3) * lift if n != null and proud >= 0.0 else Vector3.ZERO
		m.pos[k] += lifts[id]


## How much a building's chimneys grow in plan (CHIMNEY_SCALE plus up to CHIMNEY_VARY by the
## structure's field phase `phase`); the snow's cushion on a cap takes the same (card
## painter-look-roofs-winter: a plate of the recipe's size sat on a grown cap). Pure.
static func chimney_growth(phase: Vector3) -> float:
	return CHIMNEY_SCALE + CHIMNEY_VARY * phase.y / TAU


## The hand: every beam vertex moved out across the beam by brush_at (a widened, wandering brush
## edge) and across it by the beam's bow (none at its ends, so joints stay met), every frame and
## door case vertex by FRAME_BRUSH of brush_at, every door leaf and panel vertex by door_lean.
## Before the wander, so all of them move with it.
static func _hand(m: Grow, opts: Dictionary) -> void:
	var phase: Vector3 = opts.get("phase", Vector3.ZERO)
	var foot := float(opts.get("foot", 0.0))
	var dir: Vector3 = opts.get("door_dir", Vector3.ZERO)
	var centres := _chimney_centres(m)
	var chimney_scale := chimney_growth(phase)
	for k in m.pos.size():
		var rec: Variant = m.rec[k]
		if rec == null:
			continue
		var code := m.code(k)
		if _is_beam(rec) or FRAME_KINDS.has(str(rec["kind"])):
			var beam := _is_beam(rec)
			var v: Vector3 = rec["v"]
			var d := m.pos[k] - (rec["origin"] as Vector3)
			var half := maxf(float(rec["v_len"]) * 0.5, 0.001)
			var across := d.dot(v) - half
			var brush := brush_at(m.pos[k], phase) * (1.0 if beam else FRAME_BRUSH)
			var shift := v * clampf(across / half, -1.0, 1.0) * brush
			if beam:
				var length := maxf(float(rec["u_len"]), 0.001)
				var s := d.dot(rec["u"])
				var bow := sin(PI * clampf(s / length, 0.0, 1.0)) * sin(s * 1.3 + phase.y + length)
				shift += v * bow * BEAM_BOW_M
			m.pos[k] += shift
		elif str(rec["kind"]) == "chimney" and centres.has(str(rec["id"])):
			var c: Vector3 = centres[str(rec["id"])]
			var p := m.pos[k]
			m.pos[k] = Vector3(
				c.x + (p.x - c.x) * chimney_scale, p.y, c.z + (p.z - c.z) * chimney_scale
			)
		elif code == CODE_LEAF and dir != Vector3.ZERO:
			m.pos[k] += dir * maxf(m.pos[k].y - foot, 0.0) * DOOR_LEAN
		elif code == CODE_LEAF:
			m.pos[k] += door_lean(m.pos[k], rec["n"], foot, phase)


## Record id -> the middle (the mean of the corner points' XZ, Y 0) of every chimney piece in `m`:
## what _hand scales a chimney's plan about, so its stack, cap and pots stay on one axis.
static func _chimney_centres(m: Grow) -> Dictionary:
	var sums: Dictionary = {}
	for k in m.pos.size():
		var rec: Variant = m.rec[k]
		if rec == null or str(rec["kind"]) != "chimney":
			continue
		var id := str(rec["id"])
		var entry: Vector3 = sums.get(id, Vector3.ZERO)
		sums[id] = entry + Vector3(m.pos[k].x, 1.0, m.pos[k].z)
	var out: Dictionary = {}
	for id: String in sums:
		var s: Vector3 = sums[id]
		out[id] = Vector3(s.x / s.y, 0.0, s.z / s.y)
	return out


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
