class_name PondExits
extends RefCounted

## Ponds and lakes that reach the map edge, and the basin they run on in past it (phase 6,
## P6-4). A pond painted against the edge carries on into the ground skirt as scenery, as a
## river does (RiverExits): its basin continued as a rounded lobe with the water at the pond's
## level in it, both dissolving into the backdrop with the skirt. Decoration only. Pure; map XZ
## throughout. RiverExitMesh builds the geometry with the rivers' (the same skirt windows,
## patch, fade and fog); this class holds what differs.
##
## An exit is a run of boundary samples along one side of the map that are in a pond's area
## (MapDocument.pond_mask) and wet (under its level): the wet span on the edge. Its lobe is
## derived, never saved. Across it, the lobe starts as wide as the span (the edge's own
## waterline offsets), each side running on along the shoreline's direction at the edge (the
## pond mask's run FLARE_IN_M inside against its run on the edge) and then closing into a
## rounded end, further out the wider the span, picked from the map seed and the pond: a small
## cove at a narrow touch; at a wide one a long bay, or a lobe that runs on past the skirt's
## fade, an open lake running into the haze.
## Its shore wobbles with the seeded value noise (TerrainRules.value_noise, the skirt fade's)
## at a low frequency. In it the ground is the edge's cross-section scaled to the lobe's width,
## shallowing toward the rounded end; past its shore, the edge's banks by the distance to it.

## The side normals of the map edge, in the order exits() walks them.
const SIDES: Array[Vector2] = [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1)]
## A wet run on the edge needs at least this many samples.
const MIN_RUN_SAMPLES := 2
## The lobe's length past the edge: from its half-span toward the skirt's fade by the share
## (half-span / WIDE_HALF_M) squared, times a factor between LENGTH_SPREAD's two values (map seed
## and pond). A narrow touch makes a small cove; a wide one a long bay, or, when the share
## reaches 1, an open lake running on to RiverExits.FADE_REACH_M plus its half-span.
const WIDE_HALF_M := 8.0
const LENGTH_SPREAD := Vector2(0.5, 1.5)
## The shoreline's direction at the edge is read this far inside the map, clamped to
## FLARE_RANGE (widening per metre outward), and followed for about FLARE_RUN_M, the width it
## gains or loses saturating at FLARE_GROW or FLARE_SHRINK of the span's.
const FLARE_IN_M := 2.0
const FLARE_RANGE := Vector2(-0.6, 0.8)
const FLARE_RUN_M := 4.0
const FLARE_GROW := 0.6
const FLARE_SHRINK := 0.4
## The lobe's end rounds off over this many half-spans (at most its length).
const ROUND_SPANS := 0.7
## The shore's wobble: this share of the width, noise every WOBBLE_SCALE_M along the lobe,
## grown in over WOBBLE_IN_M from the edge (none on it, so the seam is the edge's).
const WOBBLE := 0.15
const WOBBLE_SCALE_M := 7.0
const WOBBLE_IN_M := 4.0
## The lobe's half-widths are tabled every WIDTH_STEP_M along it.
const WIDTH_STEP_M := 0.25
## The water: a vertex about every RIBBON_ACROSS_M across, at most RIBBON_ACROSS_MAX.
const RIBBON_ACROSS_M := 1.0
const RIBBON_ACROSS_MAX := 65
## The mouth's key for the lobe's half-width tables (left, right), which marks a pond mouth.
const WIDTHS := "widths"


## Whether any pond of `doc` is wet on the map edge (exits() would find one).
static func reaches_edge(doc: MapDocument) -> bool:
	return not exits(doc, RiverExits.FADE_REACH_M).is_empty()


## The pond exits of `doc` whose skirt fades over `fall` (see the header): [{"id", "level",
## "mouth": the span's middle on the edge, "dir": the edge's outward normal, "half_width": the
## run's half-length, "length": the lobe's, "flare": Vector2(left, right) slopes, "sector":
## Vector2(left, right) offsets of the side's corners, "noise": the wobble's seed}].
static func exits(doc: MapDocument, fall: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var mask := doc.pond_mask
	if mask.size() != doc.sample_count():
		return out
	var ponds := {}
	for body in doc.water_bodies:
		if not body.is_river():
			ponds[body.id] = body
	if ponds.is_empty():
		return out
	for side in SIDES.size():
		var line := _side(doc, side)
		var run_id := 0
		var start := 0
		for k in line.size() + 1:
			var id := 0
			if k < line.size():
				var i := doc.sample_index(line[k].x, line[k].y)
				var body: WaterBody = ponds.get(mask[i])
				if body != null and doc.heights[i] < body.level_m:
					id = body.id
			if id == run_id:
				continue
			if run_id != 0 and k - start >= MIN_RUN_SAMPLES:
				out.append(_exit(doc, ponds[run_id], line, Vector2i(start, k - 1), side, fall))
			run_id = id
			start = k
	return out


## The boundary samples of side `side` (SIDES), in order along it.
static func _side(doc: MapDocument, side: int) -> Array[Vector2i]:
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	var line: Array[Vector2i] = []
	var along := last.y if side < 2 else last.x
	for k in along + 1:
		match side:
			0:
				line.append(Vector2i(0, k))
			1:
				line.append(Vector2i(last.x, k))
			2:
				line.append(Vector2i(k, 0))
			_:
				line.append(Vector2i(k, last.y))
	return line


static func _exit(
	doc: MapDocument, body: WaterBody, line: Array[Vector2i], run: Vector2i, side: int, fall: float
) -> Dictionary:
	var half := doc.extent_m() * 0.5
	var dir := SIDES[side]
	var across := Vector2(-dir.y, dir.x)
	var a := doc.sample_to_world(Vector2(line[run.x]))
	var b := doc.sample_to_world(Vector2(line[run.y]))
	var mouth := (a + b) * 0.5
	# On the edge exactly, as the map's boundary vertices are.
	if dir.x != 0.0:
		mouth.x = dir.x * half.x
	else:
		mouth.y = dir.y * half.y
	var step := doc.sample_step()
	var along := step.y if dir.x != 0.0 else step.x
	var half_width := 0.5 * absf((b - a).dot(across)) + 0.5 * along
	var ua := (doc.sample_to_world(Vector2(line[0])) - mouth).dot(across)
	var ub := (doc.sample_to_world(Vector2(line[-1])) - mouth).dot(across)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([doc.map_seed & 0x7FFFFFFF, body.id, side, run.x])
	var wide := minf(half_width / WIDE_HALF_M, 1.0)
	var share := wide * wide * lerpf(LENGTH_SPREAD.x, LENGTH_SPREAD.y, rng.randf())
	var length := lerpf(half_width, fall, share)
	if share >= 1.0 or length >= fall:
		length = RiverExits.FADE_REACH_M + half_width
	return {
		"id": body.id,
		"level": body.level_m,
		"mouth": mouth,
		"dir": dir,
		"half_width": half_width,
		"length": maxf(length, half_width),
		"flare": _flare(doc, body.id, line, run, dir, mouth),
		"sector": Vector2(maxf(ua, ub), -minf(ua, ub)),
		"noise": rng.randi() & 0x7FFFFFFF,
	}


## The shoreline's direction at the edge either side of wet run `run` on `line`: Vector2(left,
## right), how fast the pond mask's run widens outward (the edge's run against the one through
## its middle FLARE_IN_M inside), clamped to FLARE_RANGE; 0 where the middle is not in the pond
## there.
static func _flare(
	doc: MapDocument, id: int, line: Array[Vector2i], run: Vector2i, dir: Vector2, mouth: Vector2
) -> Vector2:
	var across := Vector2(-dir.y, dir.x)
	var step := doc.sample_step()
	var inward := step.x if dir.x != 0.0 else step.y
	var rows := maxi(1, roundi(FLARE_IN_M / inward))
	var shift := Vector2i(-roundi(dir.x), -roundi(dir.y)) * rows
	var inside := func(k: int) -> bool:
		var s := line[k] + shift
		return doc.pond_mask[doc.sample_index(s.x, s.y)] == id
	var middle := (run.x + run.y) / 2
	if not inside.call(middle):
		return Vector2.ZERO
	var lo := middle
	while lo > 0 and inside.call(lo - 1):
		lo -= 1
	var hi := middle
	while hi < line.size() - 1 and inside.call(hi + 1):
		hi += 1
	var offset := func(k: int) -> float:
		return (doc.sample_to_world(Vector2(line[k])) - mouth).dot(across)
	var edge := Vector2(offset.call(run.x), offset.call(run.y))
	var deep := Vector2(offset.call(lo), offset.call(hi))
	var run_m := rows * inward
	var left := (maxf(edge.x, edge.y) - maxf(deep.x, deep.y)) / run_m
	var right := (minf(deep.x, deep.y) - minf(edge.x, edge.y)) / run_m
	return Vector2(
		clampf(left, FLARE_RANGE.x, FLARE_RANGE.y), clampf(right, FLARE_RANGE.x, FLARE_RANGE.y)
	)


## Exit `found` (exits()) as RiverExitMesh's mouth, with its lobe: the river mouth's keys
## ("course": the lobe's axis led in from the edge, "half": its footprint's half-width,
## "profile" with "profile_half", "wet", "ground", "reach", "box"), plus "length", "flare",
## "sector", "noise" and WIDTHS.
static func mouth(doc: MapDocument, found: Dictionary) -> Dictionary:
	var at: Vector2 = found.mouth
	var dir: Vector2 = found.dir
	var across := Vector2(-dir.y, dir.x)
	var half_width: float = found.half_width
	var cut := RiverExitMesh.section(doc, at, across, half_width, found.level)
	var profile: PackedFloat32Array = cut.profile
	var wet: Vector2 = cut.wet
	var out := found.duplicate()
	(
		out
		. merge(
			{
				"across": across,
				"profile": profile,
				"profile_half": half_width + RiverExitMesh.PROFILE_BANK_M,
				"wet": wet,
				"ground": 0.5 * (profile[0] + profile[-1]),
			}
		)
	)
	var widths := [_widths(out, 0), _widths(out, 1)]
	out[WIDTHS] = widths
	var widest := 0.0
	for table: PackedFloat32Array in widths:
		for w in table:
			widest = maxf(widest, w)
	var length: float = found.length
	var footprint := widest + RiverExitMesh.PROFILE_BANK_M
	var course := PackedVector2Array(
		[at - dir * RiverExitMesh.LEAD_IN_M, at, at + dir * (length + RiverExitMesh.PROFILE_BANK_M)]
	)
	(
		out
		. merge(
			{
				"course": course,
				"half": footprint,
				"reach": length + RiverExitMesh.PROFILE_BANK_M,
				"box": WaterGeometry.bounds(course, footprint + 0.5),
			}
		)
	)
	return out


## The lobe's half-width table on side `side` (0 left of the outward normal, 1 right): one every
## WIDTH_STEP_M from the edge, the last at or past the lobe's end, 0.
static func _widths(lobe: Dictionary, side: int) -> PackedFloat32Array:
	var length: float = lobe.length
	var wet: Vector2 = lobe.wet
	var start := wet.y if side == 0 else -wet.x
	var flare: float = lobe.flare[side]
	var cap: float = lobe.sector[side]
	var noise: int = lobe.noise
	# The end rounds off over its last ROUND_SPANS half-spans (an ellipse over the whole length
	# drew a narrow cove's end as a point).
	var round_m := minf(length, ROUND_SPANS * float(lobe.half_width))
	var table := PackedFloat32Array()
	var count := ceili(length / WIDTH_STEP_M) + 1
	for i in count:
		var s := i * WIDTH_STEP_M
		if s >= length:
			table.append(0.0)
			continue
		var t := maxf(s - (length - round_m), 0.0) / round_m
		# The shore's own direction, followed for a few metres and saturating (a converging shore
		# carried on straight met its other side in a point before the end could round off).
		var turn := flare * FLARE_RUN_M * tanh(s / FLARE_RUN_M)
		var most := start * (FLARE_GROW if turn > 0.0 else FLARE_SHRINK)
		if most > 0.0:
			turn = most * tanh(turn / most)
		var w := (start + turn) * sqrt(1.0 - t * t)
		var n := TerrainRules.value_noise(Vector2(s / WOBBLE_SCALE_M, 11.3 * side + 2.7), noise)
		w *= 1.0 + WOBBLE * (n - 0.5) * 2.0 * smoothstep(0.0, WOBBLE_IN_M, s)
		table.append(clampf(w, 0.0, cap + s))
	table[-1] = 0.0
	return table


## The lobe's half-width `s` metres past the edge on side `side` (_widths()).
static func width_at(lobe: Dictionary, s: float, side: int) -> float:
	var table: PackedFloat32Array = lobe[WIDTHS][side]
	var f := maxf(s, 0.0) / WIDTH_STEP_M
	if f >= table.size() - 1:
		return 0.0
	var i := floori(f)
	return lerpf(table[i], table[i + 1], f - i)


## The basin of pond mouth `lobe` at map point `xz`, `d` metres past the map, where the skirt
## is at `skirt_y` and its fade is `alpha`: Vector3(height, bed weight, shore weight), as
## RiverExitMesh.channel_at. Never above the skirt.
static func basin_at(
	lobe: Dictionary, xz: Vector2, d: float, skirt_y: float, fall: float, alpha: float
) -> Vector3:
	var rel: Vector2 = xz - lobe.mouth
	var s := maxf(rel.dot(lobe.dir), 0.0)
	var u := rel.dot(lobe.across)
	var side := 0 if u >= 0.0 else 1
	var w := width_at(lobe, s, side)
	var wet: Vector2 = lobe.wet
	var level: float = lobe.level
	var bank := RiverExitMesh.PROFILE_BANK_M
	var carved: float
	var lateral := 1.0
	if absf(u) < w:
		# The edge's cross-section scaled to the lobe's width here, shallowing toward its end.
		var start := wet.y if side == 0 else wet.x
		var t := minf(s / float(lobe.length), 1.0)
		var edge := RiverExitMesh.profile_at(lobe, start * absf(u) / w)
		carved = level - (level - edge) * sqrt(1.0 - t * t)
	else:
		var dist := _shore_distance(lobe, s, absf(u), side)
		if dist >= bank:
			return Vector3(skirt_y, 0.0, 0.0)
		var left := RiverExitMesh.profile_at(lobe, wet.y + dist)
		var right := RiverExitMesh.profile_at(lobe, wet.x - dist)
		carved = lerpf(right, left, smoothstep(-0.5, 0.5, u))
		lateral = 1.0 - smoothstep(bank - RiverExitMesh.LATERAL_BLEND_M, bank, dist)
	var drop := RiverExitMesh.drop_at(lobe, d, fall)
	var weight := (
		lateral * smoothstep(RiverExitMesh.FADE_SETTLED_ALPHA, RiverExitMesh.FADE_ALPHA, alpha)
	)
	var y := lerpf(skirt_y, minf(skirt_y, carved + drop), weight)
	return RiverExitMesh.dressed(y, level + drop, weight)


## How far a point `s` along the lobe and `across` from its axis on side `side`, outside its
## shore, is from the shore (the nearest tabled half-width within a bank's reach).
static func _shore_distance(lobe: Dictionary, s: float, across: float, side: int) -> float:
	var table: PackedFloat32Array = lobe[WIDTHS][side]
	var bank := RiverExitMesh.PROFILE_BANK_M
	var best := across - width_at(lobe, s, side)
	var first := maxi(0, floori((s - bank) / WIDTH_STEP_M))
	var last := mini(table.size() - 1, ceili((s + bank) / WIDTH_STEP_M))
	for i in range(first, last + 1):
		var ds := s - i * WIDTH_STEP_M
		var du := across - table[i]
		best = minf(best, sqrt(ds * ds + du * du))
	return best


## The water of pond mouth `lobe` (the skirt's fade `fade`, RiverExitMesh.build()): rows every
## RiverExitMesh.RIBBON_ROW_M along the lobe, each across its width plus the ribbon's margin
## either side, at the pond's level lowered with the skirt; the first on the edge at the level
## exactly, the last the first past which the fade is 0 or past the lobe's end. {"vertices",
## "uvs", "indices", "outline": the water's outline (map XZ, a closed polygon)}.
static func ribbon_piece(doc: MapDocument, lobe: Dictionary, fade: Dictionary) -> Dictionary:
	var half: Vector2 = fade.half
	var extent := doc.extent_m()
	var texels := WaterFlowBaker.resolution_for(extent)
	var low := Vector2(
		RiverExitMesh.FLOW_INSET_TEXELS / texels.x, RiverExitMesh.FLOW_INSET_TEXELS / texels.y
	)
	var margin := RiverExitMesh.RIBBON_MARGIN_M
	var mouth_at: Vector2 = lobe.mouth
	var dir: Vector2 = lobe.dir
	var across: Vector2 = lobe.across
	var level: float = lobe.level
	var length: float = lobe.length
	var rows := PackedFloat32Array()
	var s := 0.0
	while s < length + margin:
		rows.append(s)
		s += RiverExitMesh.RIBBON_ROW_M
	rows.append(length + margin)
	var widest := 0.0
	for r in rows:
		widest = maxf(widest, _extent(lobe, r, 0) + _extent(lobe, r, 1))
	var count := clampi(
		ceili(widest / RIBBON_ACROSS_M) + 1, RiverExitMesh.RIBBON_ACROSS, RIBBON_ACROSS_MAX
	)
	var spans: Array[PackedVector2Array] = []
	for r in rows:
		var row := PackedVector2Array()
		var right := _extent(lobe, r, 1)
		var left := _extent(lobe, r, 0)
		for j in count:
			row.append(mouth_at + dir * r + across * lerpf(-right, left, float(j) / (count - 1)))
		spans.append(row)
	# The water runs on until the skirt's fade is 0 at every vertex of a row, and that row is its
	# last (the fade's noise is not monotonic), or to the lobe's end.
	var made := mini(rows.size(), 2)
	for r in range(rows.size() - 1, 1, -1):
		var most := 0.0
		for q in spans[r]:
			most = maxf(most, RiverExits.skirt_alpha(q, half, fade.fall, fade.wobble, fade.seed))
		if most > 0.0:
			made = mini(r + 2, rows.size())
			break
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var left_side := PackedVector2Array()
	var right_side := PackedVector2Array()
	for r in made:
		var row := spans[r]
		for j in count:
			var q := row[j]
			var drop := 0.0
			if r > 0:
				drop = RiverExitMesh.drop_at(lobe, RiverExits.outside_distance(q, half), fade.fall)
			vertices.append(Vector3(q.x, level + drop, q.y))
			var flow_at := mouth_at - dir * 0.4 + across * (q - mouth_at).dot(across)
			uvs.append(((flow_at + half) / extent).clamp(low, Vector2.ONE - low))
		right_side.append(row[0])
		left_side.append(row[-1])
	for i in made - 1:
		for j in count - 1:
			var a := i * count + j
			var c := a + count
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	right_side.reverse()
	left_side.append_array(right_side)
	return {"vertices": vertices, "uvs": uvs, "indices": indices, "outline": left_side}


## How far the water reaches across the lobe `s` metres past the edge on side `side`: the
## shore plus the ribbon's margin, rounding off past the lobe's end, inside the side's sector.
static func _extent(lobe: Dictionary, s: float, side: int) -> float:
	var margin := RiverExitMesh.RIBBON_MARGIN_M
	var length: float = lobe.length
	var reach := width_at(lobe, s, side) + margin
	if s > length:
		reach = sqrt(maxf(margin * margin - (s - length) * (s - length), 0.0))
	return minf(reach, float(lobe.sector[side]) + s)


## The outlines among `outlines` (ponds' water, ribbon_piece()) whose bounds meet `box`.
static func covering(outlines: Array[PackedVector2Array], box: Rect2) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	for outline in outlines:
		if WaterGeometry.bounds(outline, 0.0).intersects(box, true):
			out.append(outline)
	return out


## Water piece `piece` ({"vertices", "uvs", "indices"}, a river's ribbon) with what lies inside
## any of `outlines` cut away (Geometry2D.clip_polygons per triangle), heights and UVs
## interpolated over each cut triangle; `piece` itself when there is nothing to cut.
static func clip(piece: Dictionary, outlines: Array[PackedVector2Array]) -> Dictionary:
	if outlines.is_empty():
		return piece
	var boxes: Array[Rect2] = []
	for outline in outlines:
		boxes.append(WaterGeometry.bounds(outline, 0.0))
	var verts: PackedVector3Array = piece.vertices
	var uvs: PackedVector2Array = piece.uvs
	var indices: PackedInt32Array = piece.indices
	var out_verts := verts.duplicate()
	var out_uvs := uvs.duplicate()
	var out_indices := PackedInt32Array()
	for f in indices.size() / 3:
		var corners := indices.slice(f * 3, f * 3 + 3)
		var flat := PackedVector2Array()
		for k in corners:
			flat.append(Vector2(verts[k].x, verts[k].z))
		var polygons: Array[PackedVector2Array] = [flat]
		var box := WaterGeometry.bounds(flat, 0.0)
		var touched := false
		for o in outlines.size():
			if not boxes[o].intersects(box, true):
				continue
			touched = true
			var kept: Array[PackedVector2Array] = []
			for polygon in polygons:
				var clockwise := Geometry2D.is_polygon_clockwise(polygon)
				for cut: PackedVector2Array in Geometry2D.clip_polygons(polygon, outlines[o]):
					if Geometry2D.is_polygon_clockwise(cut) == clockwise:
						kept.append(cut)  # (The other way round, a hole: an outline inside.)
			polygons = kept
		if not touched:
			out_indices.append_array(corners)
			continue
		var up := (flat[1] - flat[0]).cross(flat[2] - flat[0])
		for polygon in polygons:
			var base := out_verts.size()
			for p in polygon:
				var w := _barycentric(p, flat)
				out_verts.append(
					verts[corners[0]] * w.x + verts[corners[1]] * w.y + verts[corners[2]] * w.z
				)
				out_uvs.append(
					uvs[corners[0]] * w.x + uvs[corners[1]] * w.y + uvs[corners[2]] * w.z
				)
			var tris := Geometry2D.triangulate_polygon(polygon)
			for t in tris.size() / 3:
				var a := tris[t * 3]
				var b := tris[t * 3 + 1]
				var c := tris[t * 3 + 2]
				var facing := (polygon[b] - polygon[a]).cross(polygon[c] - polygon[a])
				if facing * up < 0.0:
					var swap := b
					b = c
					c = swap
				out_indices.append_array([base + a, base + b, base + c])
	return {"vertices": out_verts, "uvs": out_uvs, "indices": out_indices}


## The barycentric weights of `p` in triangle `tri`.
static func _barycentric(p: Vector2, tri: PackedVector2Array) -> Vector3:
	var v0 := tri[1] - tri[0]
	var v1 := tri[2] - tri[0]
	var v2 := p - tri[0]
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-12:
		return Vector3(1.0, 0.0, 0.0)
	var b := (v2.x * v1.y - v1.x * v2.y) / den
	var c := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - b - c, b, c)
