class_name RiverExitMesh
extends RefCounted

## The geometry of the rivers that run on past the map edge (phase 6, P6-1; RiverExits finds
## them and their courses): a channel carved into the ground skirt along each continued course,
## and a ribbon of water in it. Pure: mesh arrays only, built on a worker (AuthoredLoadPrep
## at load, AuthoredWater's refresh after an edit) and handed to AuthoredTerrain, which owns
## the skirt.
##
## The channel. The skirt (TerrainMeshBuilder.build_skirt_arrays) is a ring of 8 rings
## stepping out from the map's boundary samples, too coarse across its width to carry a
## channel a few metres wide that bends. Around each river exit a window of skirt columns is
## cut out of it (skip_columns()) and rebuilt as a patch with a ring every quarter metre near
## the map (coarser further out) to the channel's reach, the skirt's own 8 rings included, so the
## skirt's cost stays as it was
## everywhere else. The patch's two outer columns carry no channel; their extra vertices lie
## on the skirt's own edges (heights and normals interpolated), so the patch meets the skirt
## without a crack. Ring 0 is the map's boundary vertices, as in the skirt. Past the edge the
## ground along the course is the river's own cross-section on the edge (the map's boundary
## heights across the carve's bed and banks, PROFILE_BANK_M past the half-width either side,
## edge_point(); read 0.3 m inside, it was up to 0.12 m deeper than the edge and drew a step
## in the waterline at the seam and a deeper, greener stream past it) carried along the course,
## lowered with the skirt where the skirt falls back to the map floor, and eased back to the
## skirt at its sides and where the skirt's fade (RiverExits.skirt_alpha, the shader's twin)
## runs out. It never raises the skirt. UV2 carries the wet dressing (x the bed weight, y the
## shore weight) by height over the water, which the skirt shader routes to the base biome's
## bed and shore surfaces (it reads the map's own dressing within a couple of metres of the
## edge, so the two meet without a seam).
##
## The ribbon. A strip of water along the course at the river's level (lowered with the skirt
## like the channel), wider than the waterline by RIBBON_MARGIN_M either side so the banks
## cross it: the water shader's own shoreline fade and foam draw its edge against the channel
## in the depth texture, as in the map. Its UVs are on the in-map water's flow-map frame,
## clamped to the texels just inside the map at the river's mouth (the border texels are still
## water), so the edge's flow carries on past it. AuthoredTerrain draws it with the shared water
## material, its alpha times the skirt's fade.

## The channel's cross-section reaches this far past the river's half-width either side and
## eases back to the skirt over the outer LATERAL_BLEND_M of it.
const PROFILE_BANK_M := 3.5
const PROFILE_STEP_M := 0.1
const LATERAL_BLEND_M := 1.2
## The course is led in this far from the mouth, so the skirt beside the mouth reads its
## offset across the channel.
const LEAD_IN_M := 2.0
## The channel eases back to the skirt as the skirt's fade falls from FADE_ALPHA to
## FADE_SETTLED_ALPHA: late, so the river keeps its width into the haze, but settled before
## the fade ends (P6-3), and the ribbon runs on under the settled skirt to where the fade is 0.
const FADE_ALPHA := 0.1
const FADE_SETTLED_ALPHA := 0.02
## Past the edge the skirt beside a mouth eases from the carve's height at the edge to the
## bank's over this distance (_unghosted).
const GHOST_M := 2.0
## The patch's extra rings: one every RING_STEP_M (the sample step, so the cells are square
## and a bank at an angle to them stays smooth) out to RING_FINE_M, where the skirt is still
## nearly opaque, then one every RING_STEP_MID_M out to RING_MID_M and one every
## RING_STEP_FAR_M out to the channel's reach.
const RING_STEP_M := 0.25
const RING_FINE_M := 24.0
const RING_STEP_MID_M := 0.5
const RING_MID_M := 32.0
const RING_STEP_FAR_M := 1.0
## An extra ring this close to one of the skirt's own is dropped.
const RING_MERGE_M := 0.15
## Skirt columns kept in a window past the channel's footprint on either side.
const WINDOW_PAD_COLUMNS := 2
## The ribbon: a row every RIBBON_ROW_M, RIBBON_ACROSS vertices across, RIBBON_MARGIN_M past
## the waterline either side; its last row is the first past which the skirt's fade is 0.
const RIBBON_ROW_M := 0.5
const RIBBON_ACROSS := 9
const RIBBON_MARGIN_M := 0.6
## The ribbon's flow UVs stay this many texels inside the flow map's edge.
const FLOW_INSET_TEXELS := 1.5
## The wet dressing by height over the water: the bed from 4 cm above it to 10 cm under it
## (WaterDressing's ramp), the shore up to BANK_DRY_M fading from BANK_WET_M.
const BED_ABOVE_M := 0.04
const BED_UNDER_M := 0.10
const BANK_WET_M := 0.3
const BANK_DRY_M := 0.8


## The skirt for `doc` with its river exits: {"skirt": TerrainMeshBuilder.build_skirt_arrays
## with the exits' windows cut out, "exits": build() ({} without exits), "mirror": the skirt's
## vertex mirror for in-place edge updates (TerrainMeshBuilder.skirt_mirror_of)}. `width`,
## `fall`, `wobble`: the skirt's (AuthoredTerrain.skirt_width_m(), SKIRT_FADE_M, SKIRT_WOBBLE).
static func skirt_parts(doc: MapDocument, width: float, fall: float, wobble: float) -> Dictionary:
	var arrays := TerrainMeshBuilder.build_skirt_arrays(doc, width, fall)
	var count := TerrainMeshBuilder.boundary_samples(doc).size()
	var mirror := TerrainMeshBuilder.skirt_mirror_of(arrays, count)
	var exits := build(doc, width, fall, wobble)
	if not exits.is_empty():
		arrays[Mesh.ARRAY_INDEX] = skip_columns(arrays[Mesh.ARRAY_INDEX], count, exits.windows)
	return {"skirt": arrays, "exits": exits, "mirror": mirror}


## The exits' geometry (see the header): {"windows": Array[Vector2i] (first boundary column,
## quads), "channel": the patch's mesh arrays (vertex, normal, UV, UV2, index), "ribbon": the
## water's (vertex, normal, UV, index; [] when none), "mouths": Array[Dictionary] (each exit
## where its course meets the edge: "mouth", "dir", "level", "wet" span, "profile")}, or {}
## when no river leaves the map.
static func build(doc: MapDocument, width: float, fall: float, wobble: float) -> Dictionary:
	var half := doc.extent_m() * 0.5
	var mouths: Array[Dictionary] = []
	for found in RiverExits.exits(doc):
		var mouth := _mouth(doc, found, half)
		if not mouth.is_empty():
			mouths.append(mouth)
	if mouths.is_empty():
		return {}
	var seed_value := doc.map_seed & 0x7FFFFFFF
	var loop := TerrainMeshBuilder.boundary_samples(doc)
	var windows := _windows(doc, loop, mouths, width)
	var reach := 0.0
	for mouth in mouths:
		reach = maxf(reach, mouth.reach)
	var dists := ring_distances(width, minf(reach, minf(width, RiverExits.FADE_REACH_M)))
	var fade := {"half": half, "fall": fall, "wobble": wobble, "seed": seed_value}
	return {
		"windows": windows,
		"channel": _channel_arrays(doc, loop, windows, mouths, dists, fade),
		"ribbon": _ribbon_arrays(doc, mouths, fade),
		"mouths": mouths,
	}


## The skirt's index array `indices` (build_skirt_arrays, `count` boundary samples) without the
## quads of the columns in `windows` (first column, quads; wrapping), which the patch draws.
static func skip_columns(indices: PackedInt32Array, count: int, windows: Array) -> PackedInt32Array:
	var skip := PackedByteArray()
	skip.resize(count)
	for window: Vector2i in windows:
		for q in window.y:
			skip[(window.x + q) % count] = 1
	var out := PackedInt32Array()
	var rings := indices.size() / (count * 6)
	for r in rings:
		for i in count:
			if skip[i] == 0:
				var at := (r * count + i) * 6
				out.append_array(indices.slice(at, at + 6))
	return out


## The patch's ring distances: the skirt's own (TerrainMeshBuilder.skirt_vertex, the last one
## `width`) and the extra ones (see the constants) out to `reach`, sorted. Doubles, so the
## skirt's own
## compare equal to skirt_distance().
static func ring_distances(width: float, reach: float) -> PackedFloat64Array:
	var own := PackedFloat64Array()
	for r in TerrainMeshBuilder.SKIRT_RINGS + 1:
		own.append(skirt_distance(width, r))
	var out := own.duplicate()
	var d := RING_STEP_M
	while d < reach:
		var near := false
		for g in own:
			near = near or absf(g - d) < RING_MERGE_M
		if not near:
			out.append(d)
		if d < RING_FINE_M:
			d += RING_STEP_M
		elif d < RING_MID_M:
			d += RING_STEP_MID_M
		else:
			d += RING_STEP_FAR_M
	out.sort()
	return out


## The skirt's ring `ring` distance, exactly as TerrainMeshBuilder.skirt_vertex computes it.
static func skirt_distance(width: float, ring: int) -> float:
	return (
		width
		* pow(
			float(ring) / TerrainMeshBuilder.SKIRT_RINGS,
			TerrainMeshBuilder.SKIRT_RING_SPACING_POWER
		)
	)


## Exit `river_exit` (RiverExits.exits) where its course meets the edge, with its cross-section:
## {"course" (led in LEAD_IN_M from the mouth), "mouth", "dir", "across", "half": the profile's
## half extent, "profile", "level", "wet": Vector2 (the waterline's offsets across), "ground":
## the bank height the skirt falls from, "reach": how far past the map it reaches}, or {} when
## the course never leaves the map.
static func _mouth(doc: MapDocument, river_exit: Dictionary, half: Vector2) -> Dictionary:
	var course: PackedVector2Array = river_exit.course
	var first_out := -1
	for i in course.size():
		if RiverExits.edge_distance(course[i], half) < 0.0:
			first_out = i
			break
	if first_out < 0:
		return {}
	var mouth := course[0]
	if first_out > 0:
		mouth = RiverExits.crossing(course[first_out], course[first_out - 1], half)
	var outward := PackedVector2Array([mouth])
	outward.append_array(course.slice(first_out))
	var dir := outward[1] - mouth
	if dir.length_squared() < 1e-8:
		return {}
	dir = dir.normalized()
	var across := Vector2(-dir.y, dir.x)
	var half_width := float(river_exit.half_width)
	var extent_half := half_width + PROFILE_BANK_M
	var profile := PackedFloat32Array()
	var samples := roundi(2.0 * extent_half / PROFILE_STEP_M) + 1
	for i in samples:
		profile.append(
			WaterGeometry.ground_at(
				doc, edge_point(mouth, across, i * PROFILE_STEP_M - extent_half, half)
			)
		)
	var level: float = river_exit.level
	var wet := Vector2(INF, -INF)
	for i in samples:
		if profile[i] < level:
			var u := i * PROFILE_STEP_M - extent_half
			wet = Vector2(minf(wet.x, u), maxf(wet.y, u))
	if wet.x > wet.y:
		wet = Vector2(-half_width, half_width)
	var reach := 0.0
	for p in outward:
		reach = maxf(reach, RiverExits.outside_distance(p, half))
	var led := PackedVector2Array([mouth - dir * LEAD_IN_M])
	led.append_array(outward)
	return {
		"course": led,
		"mouth": mouth,
		"dir": dir,
		"across": across,
		"half": extent_half,
		"profile": profile,
		"level": level,
		"wet": wet,
		"ground": 0.5 * (profile[0] + profile[-1]),
		"reach": reach + extent_half,
		"box": WaterGeometry.bounds(led, extent_half + 0.5),
	}


## The point on the map edge through `mouth` that lies `u` metres across the course (`across`,
## the unit vector left of it) from the mouth: where the river's cross-section at offset `u`
## meets the edge. On the map's boundary line, so the ground there is the map's own boundary
## heights (linear between its samples, as its triangles draw it). At a corner (both edges
## within reach) the offset is taken straight across.
static func edge_point(mouth: Vector2, across: Vector2, u: float, half: Vector2) -> Vector2:
	var normal := RiverExits.edge_normal(mouth, half)
	if absf(normal.x) > 1e-6 and absf(normal.y) > 1e-6:
		return (mouth + across * u).clamp(-half, half)
	var tangent := Vector2(-normal.y, normal.x)
	var facing := tangent.dot(across)
	if absf(facing) < 1e-4:
		return mouth
	return (mouth + tangent * (u / facing)).clamp(-half, half)


## Windows of skirt columns (Vector2i(first column, quads), wrapping round the loop) whose
## radial lines pass within a mouth's footprint, padded WINDOW_PAD_COLUMNS either side; the
## first and last column of each touch no channel.
static func _windows(
	doc: MapDocument, loop: Array[Vector2i], mouths: Array[Dictionary], width: float
) -> Array[Vector2i]:
	var count := loop.size()
	var hit := PackedByteArray()
	hit.resize(count)
	for i in count:
		var inner3 := TerrainMeshBuilder.sample_position(doc, loop[i].x, loop[i].y)
		var out3 := _out(doc, loop[i])
		var inner := Vector2(inner3.x, inner3.z)
		var tip := inner + Vector2(out3.x, out3.z) * width
		var box := Rect2(inner, Vector2.ZERO).expand(tip)
		for mouth in mouths:
			if not (mouth.box as Rect2).intersects(box, true):
				continue
			if _course_distance(mouth.course, inner, tip) < float(mouth.half) + 0.5:
				hit[i] = 1
				break
	var padded := PackedByteArray()
	padded.resize(count)
	for i in count:
		if hit[i] == 0:
			continue
		for k in range(-WINDOW_PAD_COLUMNS - 1, WINDOW_PAD_COLUMNS + 2):
			padded[posmod(i + k, count)] = 1
	var windows: Array[Vector2i] = []
	var start := padded.find(0)
	if start < 0:
		windows.append(Vector2i(0, count))
		return windows
	var run := -1
	for step in count + 1:
		var i := (start + step) % count
		if padded[i] == 1 and run < 0:
			run = step
		elif padded[i] == 0 and run >= 0:
			# Columns start + run .. start + step - 1 are padded; the window's outer columns are
			# the last padded ones, whose radial lines are WINDOW_PAD_COLUMNS from any channel.
			if step - 1 - run > 0:
				windows.append(Vector2i((start + run) % count, step - 1 - run))
			run = -1
	return windows


## The skirt's outward step for boundary sample `sample` (TerrainMeshBuilder.skirt_vertex's).
static func _out(doc: MapDocument, sample: Vector2i) -> Vector3:
	var last := Vector2i(doc.samples_x() - 1, doc.samples_z() - 1)
	return Vector3(
		-1.0 if sample.x == 0 else (1.0 if sample.x == last.x else 0.0),
		0.0,
		-1.0 if sample.y == 0 else (1.0 if sample.y == last.y else 0.0)
	)


## The skirt's [position, normal] for boundary sample `sample` `distance` metres out
## (TerrainMeshBuilder.skirt_vertex at any distance).
static func _skirt_point(doc: MapDocument, sample: Vector2i, distance: float, fall: float) -> Array:
	var inner := TerrainMeshBuilder.sample_position(doc, sample.x, sample.y)
	var out := _out(doc, sample)
	var along := out.normalized()
	var point := inner + out * distance
	point.y = TerrainMeshBuilder.skirt_height(inner.y, distance, fall)
	var t := clampf(distance / maxf(fall, 1e-4), 0.0, 1.0)
	var slope := -inner.y * 6.0 * t * (1.0 - t) / maxf(fall, 1e-4)
	return [point, Vector3(-along.x * slope, 1.0, -along.z * slope).normalized()]


static func _channel_arrays(
	doc: MapDocument,
	loop: Array[Vector2i],
	windows: Array[Vector2i],
	mouths: Array[Dictionary],
	dists: PackedFloat64Array,
	fade: Dictionary
) -> Array:
	var count := loop.size()
	var rings := dists.size()
	var own := PackedInt32Array()  # Per patch ring: the skirt ring it is, or -1.
	var width := dists[-1]  # The skirt's last ring is at its full width.
	for d in dists:
		var found := -1
		for r in TerrainMeshBuilder.SKIRT_RINGS + 1:
			if skirt_distance(width, r) == d:
				found = r
		own.append(found)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var wets := PackedVector2Array()
	var fixed := PackedByteArray()
	var indices := PackedInt32Array()
	for window in windows:
		var base := vertices.size()
		var columns := window.y + 1
		for c in columns:
			var sample := loop[(window.x + c) % count]
			var outer := c == 0 or c == columns - 1
			for k in rings:
				var v := _patch_vertex(doc, sample, dists, own, k, outer, mouths, fade)
				vertices.append(v[0])
				normals.append(v[1])
				uvs.append(Vector2(v[0].x, v[0].z))
				wets.append(v[2])
				# 2: the skirt's or the map's normal stays; 1: undipped; 0: carved.
				fixed.append(2 if outer or k == 0 else (0 if v[3] else 1))
		for c in columns - 1:
			for k in rings - 1:
				var a := base + c * rings + k
				var b := base + (c + 1) * rings + k
				# Split each quad along the diagonal whose ends are closer in height, so the
				# banks' contours (and the waterline on them) follow the channel instead of
				# zigzagging across the grid where the river runs at an angle to it.
				if (
					absf(vertices[a].y - vertices[b + 1].y)
					<= absf(vertices[b].y - vertices[a + 1].y)
				):
					_add_up(indices, vertices, a, b, b + 1)
					_add_up(indices, vertices, a, b + 1, a + 1)
				else:
					_add_up(indices, vertices, a, b, a + 1)
					_add_up(indices, vertices, b, b + 1, a + 1)
	_smooth_normals(vertices, normals, fixed, indices)
	if vertices.is_empty():
		return []
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = wets
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## One patch vertex: [position, normal, Vector2(bed, shore), dipped]. An outer column's extra
## ring lies on the skirt's own edge between its rings (interpolated); ring 0 is the map's
## boundary vertex with the map's normal.
static func _patch_vertex(
	doc: MapDocument,
	sample: Vector2i,
	dists: PackedFloat64Array,
	own: PackedInt32Array,
	k: int,
	outer: bool,
	mouths: Array[Dictionary],
	fade: Dictionary
) -> Array:
	var width := dists[-1]
	var fall: float = fade.fall
	var d := dists[k]
	if outer and own[k] < 0:
		var r := 0
		while skirt_distance(width, r + 1) < d:
			r += 1
		var near := skirt_distance(width, r)
		var far := skirt_distance(width, r + 1)
		var t := (d - near) / (far - near)
		var a := _skirt_point(doc, sample, near, fall)
		var b := _skirt_point(doc, sample, far, fall)
		var normal: Vector3 = (a[1] as Vector3).lerp(b[1], t).normalized()
		return [(a[0] as Vector3).lerp(b[0], t), normal, Vector2.ZERO, false]
	var skirt := _skirt_point(doc, sample, d, fall)
	var point: Vector3 = skirt[0]
	if k == 0:
		var normal := skirt[1] as Vector3
		if not outer:
			normal = TerrainMeshBuilder.sample_normal(doc, sample.x, sample.y)
		return [point, normal, Vector2.ZERO, false]
	if outer:
		return [point, skirt[1], Vector2.ZERO, false]
	var xz := Vector2(point.x, point.z)
	var half: Vector2 = fade.half
	var alpha := -1.0
	var base := _unghosted(doc, sample, d, fall, mouths, point.y)
	var y := base
	var wet := Vector2.ZERO
	for mouth in mouths:
		if not (mouth.box as Rect2).has_point(xz):
			continue
		if alpha < 0.0:
			alpha = RiverExits.skirt_alpha(xz, half, fall, fade.wobble, fade.seed)
		var dip := channel_at(mouth, xz, RiverExits.outside_distance(xz, half), base, fall, alpha)
		y = minf(y, dip.x)
		wet = Vector2(maxf(wet.x, dip.y), maxf(wet.y, dip.z))
	var dipped := absf(y - point.y) > 1e-4 or wet != Vector2.ZERO
	return [Vector3(point.x, y, point.z), skirt[1], wet, dipped]


## The skirt's height `d` metres out from boundary sample `sample` (`skirt_y` as the skirt
## builds it) without the river's carve carried straight out: a column that starts in a
## mouth's channel would otherwise keep the carve's low edge as it rolls back up, a ghost
## trench running square off the edge wherever the river leaves at an angle. Its edge height
## eases to the mouth's bank height over GHOST_M, and the channel is carved along the course
## alone.
static func _unghosted(
	doc: MapDocument,
	sample: Vector2i,
	d: float,
	fall: float,
	mouths: Array[Dictionary],
	skirt_y: float
) -> float:
	var inner := TerrainMeshBuilder.sample_position(doc, sample.x, sample.y)
	var at := Vector2(inner.x, inner.z)
	var out := skirt_y
	for mouth in mouths:
		var bank: float = mouth.ground
		if inner.y >= bank or not (mouth.box as Rect2).has_point(at):
			continue
		var raised := lerpf(inner.y, bank, smoothstep(0.0, GHOST_M, d))
		out = maxf(out, TerrainMeshBuilder.skirt_height(raised, d, fall))
	return out


## The channel of `mouth` at map point `xz`, `d` metres past the map, where the skirt is at
## `skirt_y` and its fade is `alpha`: Vector3(height, bed weight, shore weight). The height is
## never above the skirt's.
static func channel_at(
	mouth: Dictionary, xz: Vector2, d: float, skirt_y: float, fall: float, alpha: float
) -> Vector3:
	var near := _nearest(mouth.course, xz)
	var extent_half: float = mouth.half
	if near.y >= extent_half:
		return Vector3(skirt_y, 0.0, 0.0)
	var drop := drop_at(mouth, d, fall)
	var carved := profile_at(mouth, near.x) + drop
	var weight := (
		(1.0 - smoothstep(extent_half - LATERAL_BLEND_M, extent_half, near.y))
		* smoothstep(FADE_SETTLED_ALPHA, FADE_ALPHA, alpha)
	)
	var y := lerpf(skirt_y, minf(skirt_y, carved), weight)
	var above := y - (float(mouth.level) + drop)
	var bed := (1.0 - smoothstep(-BED_UNDER_M, BED_ABOVE_M, above)) * weight
	var shore := (1.0 - smoothstep(BANK_WET_M, BANK_DRY_M, above)) * smoothstep(-0.1, 0.0, above)
	return Vector3(y, bed, shore * weight)


## How far the river past `mouth` moves `d` metres past the map: with the skirt as it settles
## back to the map floor (TerrainMeshBuilder.skirt_height), so the channel stays a channel in
## it. From a sunken edge (a valley floor) that is up: held at the river's level instead, the
## rising skirt would leave it in a gorge with walls metres high; carried up, it reads as the
## valley's river arriving from, or running on into, higher ground as both fade.
static func drop_at(mouth: Dictionary, d: float, fall: float) -> float:
	var ground: float = mouth.ground
	return TerrainMeshBuilder.skirt_height(ground, d, fall) - ground


## The mouth's cross-section `u` metres across the course (left of it positive).
static func profile_at(mouth: Dictionary, u: float) -> float:
	var profile: PackedFloat32Array = mouth.profile
	var f := clampf((u + float(mouth.half)) / PROFILE_STEP_M, 0.0, profile.size() - 1.0)
	var i := mini(floori(f), profile.size() - 2)
	return lerpf(profile[i], profile[i + 1], f - i)


## The ribbon of every mouth (see the header).
static func _ribbon_arrays(doc: MapDocument, mouths: Array[Dictionary], fade: Dictionary) -> Array:
	var half: Vector2 = fade.half
	var extent := doc.extent_m()
	var texels := WaterFlowBaker.resolution_for(extent)
	var low := Vector2(FLOW_INSET_TEXELS / texels.x, FLOW_INSET_TEXELS / texels.y)
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for mouth in mouths:
		var course: PackedVector2Array = (mouth.course as PackedVector2Array).slice(1)
		var wet: Vector2 = mouth.wet
		var dir: Vector2 = mouth.dir
		var base := vertices.size()
		var made := 0
		var rows := _rows(course, RIBBON_ROW_M)
		# The ribbon runs on until the skirt's fade is 0 at every vertex of a row, and that row
		# is its last: the fade's noise is not monotonic along the course, so stopping at the
		# first faint row (P6-1) could end the water where the fade came back up beyond it,
		# a faint darker stub of dry channel at full zoom-out.
		var count := mini(rows.size(), 2)
		for r in range(rows.size() - 1, 1, -1):
			if _row_alpha(rows[r], wet, half, fade) > 0.0:
				count = mini(r + 2, rows.size())
				break
		for row in rows.slice(0, count):
			var p: Vector2 = row[0]
			var tangent: Vector2 = row[1]
			var across := Vector2(-tangent.y, tangent.x)
			for j in RIBBON_ACROSS:
				var u := lerpf(
					wet.x - RIBBON_MARGIN_M, wet.y + RIBBON_MARGIN_M, float(j) / (RIBBON_ACROSS - 1)
				)
				var q := p + across * u
				var drop := 0.0
				if made == 0:
					# The first row lies on the edge, where the map's water ends, at its level
					# exactly (the in-map mesh's last row is flat at the level out to the edge,
					# WaterMeshBuilder._run_out), across the course as the channel's profile is.
					q = edge_point(mouth.mouth, mouth.across, u, half)
				else:
					if RiverExits.edge_distance(q, half) > 0.0:
						q = _onto_edge(q, dir, half)
					drop = drop_at(mouth, RiverExits.outside_distance(q, half), fade.fall)
				vertices.append(Vector3(q.x, float(mouth.level) + drop, q.y))
				var flow_at: Vector2 = mouth.mouth - dir * 0.4 + (mouth.across as Vector2) * u
				uvs.append(((flow_at + half) / extent).clamp(low, Vector2.ONE - low))
			made += 1
		for i in made - 1:
			for j in RIBBON_ACROSS - 1:
				var a := base + i * RIBBON_ACROSS + j
				var c := a + RIBBON_ACROSS
				indices.append_array([a, c, a + 1, a + 1, c, c + 1])
	if indices.is_empty():
		return []
	var normals := PackedVector3Array()
	normals.resize(vertices.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


## The skirt's greatest fade over the vertices of ribbon row `row` ([point, direction],
## _rows()) across the waterline `wet` widened by RIBBON_MARGIN_M either side.
static func _row_alpha(row: Array, wet: Vector2, half: Vector2, fade: Dictionary) -> float:
	var p: Vector2 = row[0]
	var tangent: Vector2 = row[1]
	var across := Vector2(-tangent.y, tangent.x)
	var most := 0.0
	for j in RIBBON_ACROSS:
		var u := lerpf(
			wet.x - RIBBON_MARGIN_M, wet.y + RIBBON_MARGIN_M, float(j) / (RIBBON_ACROSS - 1)
		)
		var at := p + across * u
		most = maxf(most, RiverExits.skirt_alpha(at, half, fade.fall, fade.wobble, fade.seed))
	return most


## Points every `step` metres along `course` with the course's direction there (a chord over
## a metre and a half, so a row turns smoothly round a corner of the polyline): [[point, dir]].
static func _rows(course: PackedVector2Array, step: float) -> Array:
	var arc := PackedFloat32Array([0.0])
	for i in course.size() - 1:
		arc.append(arc[-1] + course[i].distance_to(course[i + 1]))
	var total := arc[-1]
	var out := []
	if total <= 1e-4:
		return out
	var s := 0.0
	while s <= total + 1e-4:
		var at := _point_at(course, arc, minf(s, total))
		var ahead := _point_at(course, arc, minf(s + 0.75, total))
		var behind := _point_at(course, arc, maxf(s - 0.75, 0.0))
		var dir := ahead - behind
		out.append([at, dir.normalized() if dir.length_squared() > 1e-10 else Vector2.RIGHT])
		s += step
	return out


static func _point_at(course: PackedVector2Array, arc: PackedFloat32Array, s: float) -> Vector2:
	for i in course.size() - 1:
		if s <= arc[i + 1] or i == course.size() - 2:
			var length := arc[i + 1] - arc[i]
			var t := clampf((s - arc[i]) / length, 0.0, 1.0) if length > 1e-9 else 0.0
			return course[i].lerp(course[i + 1], t)
	return course[-1]


## `q` (inside the map) moved along `dir` onto the map edge.
static func _onto_edge(q: Vector2, dir: Vector2, half: Vector2) -> Vector2:
	var t := INF
	for axis in 2:
		if absf(dir[axis]) > 1e-6:
			var to := (signf(dir[axis]) * half[axis] - q[axis]) / dir[axis]
			if to >= 0.0:
				t = minf(t, to)
	return q + dir * t if t != INF else q


## Vector2(signed offset, distance) of `p` from polyline `course`: the offset is positive on
## the left of the nearest segment (Vector2(-dir.y, dir.x)).
static func _nearest(course: PackedVector2Array, p: Vector2) -> Vector2:
	var best := INF
	var side := 0.0
	for i in course.size() - 1:
		var a := course[i]
		var segment := course[i + 1] - a
		var length_sq := segment.length_squared()
		if length_sq <= 1e-12:
			continue
		var t := clampf((p - a).dot(segment) / length_sq, 0.0, 1.0)
		var q := a + segment * t
		var d := p.distance_to(q)
		if d < best:
			best = d
			side = signf((p - q).dot(Vector2(-segment.y, segment.x)))
	return Vector2(side * best, best)


## The least distance between polyline `course` and the segment `a`-`b`.
static func _course_distance(course: PackedVector2Array, a: Vector2, b: Vector2) -> float:
	var best := INF
	for i in course.size() - 1:
		best = minf(best, _segment_distance(course[i], course[i + 1], a, b))
	return best


static func _segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return minf(
		minf(
			a0.distance_to(Geometry2D.get_closest_point_to_segment(a0, b0, b1)),
			a1.distance_to(Geometry2D.get_closest_point_to_segment(a1, b0, b1))
		),
		minf(
			b0.distance_to(Geometry2D.get_closest_point_to_segment(b0, a0, a1)),
			b1.distance_to(Geometry2D.get_closest_point_to_segment(b1, a0, a1))
		)
	)


## Triangle (a, b, c) appended, wound to face +Y (TerrainMeshBuilder's convention).
static func _add_up(
	indices: PackedInt32Array, vertices: PackedVector3Array, a: int, b: int, c: int
) -> void:
	var facing := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).y
	indices.append(a)
	indices.append(b if facing < 0.0 else c)
	indices.append(c if facing < 0.0 else b)


## Normals of the vertices not `fixed` from the triangles round them (area weighted); a vertex
## no carved triangle touches keeps the skirt's own.
static func _smooth_normals(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	fixed: PackedByteArray,
	indices: PackedInt32Array
) -> void:
	var sums := PackedVector3Array()
	sums.resize(vertices.size())
	sums.fill(Vector3.ZERO)
	for f in indices.size() / 3:
		var a := indices[f * 3]
		var b := indices[f * 3 + 1]
		var c := indices[f * 3 + 2]
		var n := (vertices[c] - vertices[a]).cross(vertices[b] - vertices[a])
		if n.y < 0.0:
			n = -n
		sums[a] += n
		sums[b] += n
		sums[c] += n
	for f in indices.size() / 3:
		var carved := false
		for corner in 3:
			carved = carved or fixed[indices[f * 3 + corner]] == 0
		if not carved:
			continue
		for corner in 3:
			var k := indices[f * 3 + corner]
			if fixed[k] == 1:
				# An undipped vertex beside the carve: its normal follows the triangles too.
				fixed[k] = 3
	for k in vertices.size():
		if (fixed[k] == 0 or fixed[k] == 3) and sums[k].length_squared() > 0.0:
			normals[k] = sums[k].normalized()
