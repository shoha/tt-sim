class_name WaterFallMesh
extends RefCounted

## The geometry of a map's waterfalls (phase 4c, P4c-3), pure: for every fall of a document
## (WaterFalls.falls) a falling curtain, a foam ring on the plunge pool and a few mist puffs,
## all in one mesh at the map origin with an identity transform, built by
## WaterMeshBuilder.build() (the "falls" key) on the water refresh worker and turned into the
## `AuthoredWater-falls` node by AuthoredWater. Summary: docs/systems/waterfalls.md (Runtime).
##
## Curtain. One ribbon per fall across the wetted width at the crest (crest_widths(): the
## ground along the lip line read outward from the course until it stands at the upper
## level; the half-width minus the shore's fade, each side its own), a column every COLUMN_M
## and a row at every ROW_FALL_M of fall (finer over the first ROW_FALL_M, the lip roll). A
## column's path (trajectory()) runs straight downstream from its point on the lip line: the
## water leaves the upper level over LIP_ROLL_M, then falls ballistically with a horizontal
## speed of V0_BASE + V0_PER_SPEED x the river's speed, and is floored FALL_CLEARANCE_M in
## front of the rock under it, the rock being the carved face (WaterCarve.fall_shape along
## the lower course, x = 0 at the lip) or the document's ground under the column, whichever
## stands higher (the carve may have met rock or tier ground above its goal), so the curtain
## hugs a curved face and never cuts into it; it never rises above the upper level (over the
## brink the clearance gives way to the water level). It ends END_BELOW_M under the lower
## level, a strip the foam ring covers (P4c-0 probe a). The rows are shared across the
## columns (a regular grid), so the ribbon is one strip of quads.
##
## Vertex layout (the contract with shaders/waterfall.gdshader, P4c-4; the model matrix is
## the identity, so VERTEX is map space):
##   NORMAL  outward (the lower course's direction at the lip); the curtain's are its
##           surface normals oriented downstream, the ring's and the mist's up.
##   UV      curtain: (metres across from its left edge, metres fallen from the lip);
##           ring: metres (across, downstream) from its centre; mist: the quad's corner,
##           (0, 0) to (1, 1).
##   UV2     curtain: (the fall's height, the lower level); ring: (its radius, the lower
##           level); mist: the corner's offset from the puff's centre in metres (x to the
##           camera's right, y up), for the vertex billboard of P4c-0 probe (c).
##   COLOR   r: the edge fade (curtain: 0 at a side edge, 1 from EDGE_FADE_M in; ring: 1 at
##           the centre, 0 at the rim; mist: 1); g: the kind flag, KIND_CURTAIN 0, KIND_RING
##           0.5, KIND_MIST 1 (vertex colours are 8-bit, so the shader tests g against 0.25
##           and 0.75); b: a per-puff seed for the mist, 0 otherwise; a: curtain: the fall's
##           wetted crest width over WIDTH_ENCODE_M, clamped (P4c-6c: the shader scales its
##           aeration and edge bite by the width, so a narrow fall is a white ribbon and a
##           wide one glass between bold tongues; 8-bit, so 3 cm steps up to 8 m); ring and
##           mist: 1.
## Triangles wind clockwise seen from the front (Godot's front face), the front being the
## downstream side for the curtain and above for the ring. The mist quads are packed (all
## four vertices at the puff's centre), so the mesh's own bounds miss them: build() returns
## the bounds grown by the largest puff for ArrayMesh.custom_aabb.
##
## Foam ring: a flat disc RING_WIDTH_FACTOR x the fall's width across, RING_SEGMENTS rim
## vertices round a centre, RING_LIFT_M over the lower level (the shader adds the water's
## bob), centred where the middle column meets the pool, RING_FORWARD of its radius
## downstream (the churn spreads downstream; the part behind the face is under the rock).
## Mist: MIST_MIN to MIST_MAX puffs per fall, sized by the fall's width and drop (capped at
## MIST_HALF_MAX_M against overdraw), standing between the face's foot and the pool and
## staggered from the pool up the lowest MIST_LOW_SHARE of the face, never higher than
## MIST_RISE_MAX_M over the pool (spray rises from where the water lands, P4c-4; at 1.5 m
## plus the shader's rise the clouds sat at 70% of a tier fall's height, P4c-6c), plus, on a
## fall at least MIST_HIGH_MIN_DROP_M high, one puff set back near the lip with its top over
## the brink, the cue an away-facing fall keeps. The
## shader rises and grows every puff over its cycle (MIST_SHADER_RISE_M, MIST_SHADER_GROW
## mirror waterfall.gdshader), so the bounds grow by that too. Everything is a function of
## the document alone (the puff placement uses a golden-ratio sequence, no RNG), so every
## peer and every rebuild gets the same mesh.

const MESH_NAME := "AuthoredWater-falls"
## Columns across the curtain and rows down it (metres across, metres of fall); the first
## ROW_FALL_M of fall is split into ROLL_ROW_FALL_M rows (the lip roll).
const COLUMN_M := 0.2
const ROW_FALL_M := 0.12
const ROLL_ROW_FALL_M := 0.03
## The water runs level over the brink this far before it falls.
const LIP_ROLL_M := 0.3
## The curtain ends this far under the lower level.
const END_BELOW_M := 0.03
## How far past the carved face's foot (WaterCarve.fall_foot) a column is traced: the pool
## level is crossed before the foot on every carved fall, so a row still unreached there is
## one the ground never gives (the lower course bends away from the lip's direction right
## after the fall, or an old document's stub was never carved below the level) and it sits
## at the trace's end. Tracing on to the plunge pool's end laid those rows along the bank
## as a white strip up to 3 m long (P4c-6).
const END_PAST_FOOT_M := 0.5
## The curtain stands at least this far in front of the rock under it.
const FALL_CLEARANCE_M := 0.08
## The horizontal speed the water leaves the lip with: base plus per unit of river speed.
const V0_BASE := 0.8
const V0_PER_SPEED := 0.6
const GRAVITY := 9.81
## The step a column's path is traced at, and the bisection passes that place a row within
## a step (to 0.02 mm).
const MARCH_M := 0.02
const BISECT_PASSES := 10
## The ground along the lip line is read every this far to find the wetted width; when the
## middle of the crest is dry (an uncarved document) the curtain takes this share of the
## half-width.
const WIDTH_SCAN_M := 0.05
const DRY_CREST_SHARE := 0.5
## COLOR.r on the curtain: 0 at a side edge, 1 this far in.
const EDGE_FADE_M := 0.35
## COLOR.a on the curtain: the wetted crest width over this (waterfall.gdshader decodes it
## with the same constant).
const WIDTH_ENCODE_M := 8.0
## The foam ring: rim vertices, its width over the fall's (1.1: the shader thins the churn to
## nothing by RING_REACH of the radius, so the foam stays inside the fall's width, well within
## the widened plunge pool; at 1.4 the disc stood over the banks of a waist river, P4c-4),
## its lift over the level, and how far downstream of the plunge its centre sits, in radii.
const RING_SEGMENTS := 64
const RING_WIDTH_FACTOR := 1.1
const RING_LIFT_M := 0.01
const RING_FORWARD := 0.3
## Mist puffs per fall and their half-size (metres): base plus per metre of wetted
## half-width and of drop, clamped; the share of the face the low puffs stagger up (capped),
## where between the lip and the plunge they stand (shares of the plunge distance) and how
## far across they spread; the high puff's shortest fall and its set-back; the shader's rise
## and growth, for the bounds.
const MIST_MIN := 3
const MIST_MAX := 5
const MIST_HALF_BASE_M := 0.3
const MIST_HALF_PER_WIDTH := 0.35
const MIST_HALF_PER_DROP := 0.08
const MIST_HALF_MIN_M := 0.35
const MIST_HALF_MAX_M := 1.2
## A puff is never wider than the fall itself: its half-size is capped at this share of the
## wetted width (P4c-6: on a 1.1 m ankle stream the drop term alone made 1.5 m puffs that
## read as grey discs on the grass beside the notch), never under MIST_HALF_MIN_M.
const MIST_HALF_PER_FALL_WIDTH := 0.5
const MIST_LOW_SHARE := 0.33
const MIST_RISE_MAX_M := 0.6
const MIST_BACK_MIN := 0.55
const MIST_BACK_MAX := 1.0
const MIST_SPREAD := 0.6
const MIST_HIGH_MIN_DROP_M := 1.2
const MIST_HIGH_BACK := 0.15
const MIST_HIGH_OVER := 0.3
const MIST_SHADER_RISE_M := 0.5
const MIST_SHADER_GROW := 1.3
## The kind flag in COLOR.g.
const KIND_CURTAIN := 0.0
const KIND_RING := 0.5
const KIND_MIST := 1.0
## The golden ratio's fractional part, the puff placement's sequence.
const GOLDEN := 0.6180339887


## The falls mesh of `doc` for its `falls` (WaterFalls.falls(doc)): {"arrays": Mesh arrays
## (vertex, normal, UV, UV2, colour, index; [] with no fall), "aabb": the bounds grown by the
## largest mist puff at the shader's full growth plus its rise (for ArrayMesh.custom_aabb),
## "count": the falls built}.
static func build(doc: MapDocument, falls: Array[Dictionary]) -> Dictionary:
	var buffers := _Buffers.new()
	var largest_puff := 0.0
	for fall in falls:
		if fall.upper_index < 0 or fall.upper_index >= doc.water_bodies.size():
			continue
		if fall.lower_index < 0 or fall.lower_index >= doc.water_bodies.size():
			continue
		largest_puff = maxf(largest_puff, _fall(doc, fall, buffers))
	if buffers.vertices.is_empty():
		return {"arrays": [], "aabb": AABB(), "count": 0}
	var bounds := AABB(buffers.vertices[0], Vector3.ZERO)
	for v in buffers.vertices:
		bounds = bounds.expand(v)
	return {
		"arrays": buffers.arrays(),
		"aabb": bounds.grow(mist_bounds_margin(largest_puff)),
		"count": falls.size(),
	}


## How far the bounds grow for a puff of half-size `half`: its size at the shader's full
## growth plus the rise.
static func mist_bounds_margin(half: float) -> float:
	return half * MIST_SHADER_GROW + MIST_SHADER_RISE_M


## The wetted half-widths at the crest of a fall whose lip is `lip` and whose course runs
## along `dir` there, Vector2(left, right) (left is -dir.orthogonal()): from the lip outward
## along the lip line every WIDTH_SCAN_M until the ground stands at `top` (the upper level),
## the crossing interpolated; never past `half_width`, the channel's waterline (the carve's
## own bank stands at or above the level past it; where another river's bank cut has shaved
## that ground to a hair under the level, P4c-6, the curtain must not run out along it as a
## sheet lying on the bank). A dry middle (the crest not carved) gives DRY_CREST_SHARE of
## the half-width both sides.
static func crest_widths(
	doc: MapDocument, lip: Vector2, dir: Vector2, half_width: float, top: float
) -> Vector2:
	var across := dir.orthogonal()
	var out := Vector2.ZERO
	var reach := half_width
	for side in 2:
		var sign_value := -1.0 if side == 0 else 1.0
		var previous_w := 0.0
		var previous_g := WaterGeometry.ground_at(doc, lip)
		var width := reach
		var w := WIDTH_SCAN_M
		while w <= reach + 1e-6:
			var g := WaterGeometry.ground_at(doc, lip + across * (w * sign_value))
			if g >= top:
				var t := (top - previous_g) / (g - previous_g) if g > previous_g + 1e-9 else 0.0
				width = lerpf(previous_w, w, clampf(t, 0.0, 1.0))
				break
			previous_w = w
			previous_g = g
			w += WIDTH_SCAN_M
		out[side] = width
	if out.x < WIDTH_SCAN_M or out.y < WIDTH_SCAN_M:
		return Vector2.ONE * (half_width * DRY_CREST_SHARE)
	return out


## The rows of a curtain over a fall of `drop` metres: the metres fallen at each, ascending:
## 0, the roll rows every ROLL_ROW_FALL_M up to ROW_FALL_M, then every ROW_FALL_M, the
## pool level (`drop`) and the end (`drop` + END_BELOW_M); two rows closer than half a roll
## row merge.
static func row_falls(drop: float) -> PackedFloat32Array:
	var rows := PackedFloat32Array()
	var v := 0.0
	while v < ROW_FALL_M - 1e-6:
		rows.append(v)
		v += ROLL_ROW_FALL_M
	v = ROW_FALL_M
	while v < drop - 1e-6:
		rows.append(v)
		v += ROW_FALL_M
	rows.append(drop)
	rows.append(drop + END_BELOW_M)
	var out := PackedFloat32Array()
	for row in rows:
		if out.is_empty() or row - out[-1] >= ROLL_ROW_FALL_M * 0.5:
			out.append(row)
		else:
			out[-1] = row
	return out


## The column offsets across a curtain `widths` (crest_widths()) wide: from -widths.x to
## widths.y, evenly, no further apart than COLUMN_M, both edges included.
static func column_offsets(widths: Vector2) -> PackedFloat32Array:
	var span := widths.x + widths.y
	var count := maxi(2, ceili(span / COLUMN_M - 1e-6) + 1)
	var out := PackedFloat32Array()
	for i in count:
		out.append(-widths.x + span * float(i) / float(count - 1))
	return out


## The height of a column's curtain `x` metres downstream of its lip point `origin` (see
## the header): the ballistic path from the roll, floored FALL_CLEARANCE_M over the higher of
## the carved face (WaterCarve.fall_shape for a fall from `top` into `bottom` over water
## `depth` deep) and the document's ground there, never above `top`.
static func curtain_height(
	doc: MapDocument,
	origin: Vector2,
	dir: Vector2,
	x: float,
	top: float,
	bottom: float,
	depth: float,
	v0: float
) -> float:
	var run := maxf(x - LIP_ROLL_M, 0.0)
	var free := top - GRAVITY * run * run / (2.0 * v0 * v0)
	var carved := WaterCarve.fall_shape(x, top, bottom, depth).y
	var ground := WaterGeometry.ground_at(doc, origin + dir * x)
	var floor_y := maxf(carved, ground) + FALL_CLEARANCE_M
	return minf(top, maxf(free, floor_y))


## One column's curtain: its point at every row of `rows` (row_falls(); metres fallen from
## `top`), Vector3(map x, height, map z), the path traced from `origin` along `dir` every
## MARCH_M and each row placed where the path first reaches it (bisected within the step, so
## the vertex is on the path, not on a chord under the floor); a row the path never reaches
## within `x_max` (the carved foot plus END_PAST_FOOT_M) sits at the path's end.
static func trajectory(
	doc: MapDocument,
	origin: Vector2,
	dir: Vector2,
	top: float,
	bottom: float,
	depth: float,
	v0: float,
	rows: PackedFloat32Array,
	x_max: float
) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(rows.size())
	var x := 0.0
	var y := curtain_height(doc, origin, dir, 0.0, top, bottom, depth, v0)
	var k := 0
	while k < rows.size():
		var target := top - rows[k]
		if y <= target + 1e-9:
			out[k] = _point(origin + dir * x, target)
			k += 1
			continue
		if x >= x_max - 1e-9:
			out[k] = _point(origin + dir * x, y)
			k += 1
			continue
		var next_x := minf(x + MARCH_M, x_max)
		var next_y := curtain_height(doc, origin, dir, next_x, top, bottom, depth, v0)
		if next_y <= target:
			var low := x
			var high := next_x
			for _pass in BISECT_PASSES:
				var mid := (low + high) * 0.5
				if curtain_height(doc, origin, dir, mid, top, bottom, depth, v0) <= target:
					high = mid
				else:
					low = mid
			x = high
			y = target
		else:
			x = next_x
			y = next_y
	return out


## The puff half-size for a fall `drop` metres high and `width` metres wide at the crest.
static func mist_half_size(drop: float, width: float) -> float:
	var cap := maxf(width * MIST_HALF_PER_FALL_WIDTH, MIST_HALF_MIN_M)
	return clampf(
		MIST_HALF_BASE_M + MIST_HALF_PER_WIDTH * width * 0.5 + MIST_HALF_PER_DROP * drop,
		MIST_HALF_MIN_M,
		minf(MIST_HALF_MAX_M, cap)
	)


## How many puffs a fall `drop` metres high and `width` metres wide gets.
static func mist_count(drop: float, width: float) -> int:
	return clampi(2 + roundi(width * 0.4 + drop * 0.4), MIST_MIN, MIST_MAX)


## The foam ring's radius for a fall `crest_width` metres wide at the crest (the wetted
## width; CrossingPlacement reads it with the channel's full width, a hair wider). Pure.
static func ring_radius(crest_width: float) -> float:
	return RING_WIDTH_FACTOR * crest_width * 0.5


## The foam ring's centre: `pool_x` metres down the lower course from `lip` (where the
## curtain meets the pool) plus RING_FORWARD of the ring's `radius`, along `dir`. Pure.
static func ring_centre(lip: Vector2, dir: Vector2, pool_x: float, radius: float) -> Vector2:
	return lip + dir * (pool_x + RING_FORWARD * radius)


## Builds one fall into `buffers`; returns its largest puff's half-size (for the bounds).
static func _fall(doc: MapDocument, fall: Dictionary, buffers: _Buffers) -> float:
	var upper: WaterBody = doc.water_bodies[fall.upper_index]
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	if dir == Vector2.ZERO:
		return 0.0
	var across := dir.orthogonal()
	var top: float = fall.top
	var bottom: float = fall.bottom
	var drop := top - bottom
	var depth := lower.depth_m()
	var widths := crest_widths(doc, lip, dir, fall.half_width, top)
	var v0 := V0_BASE + V0_PER_SPEED * upper.speed
	var rows := row_falls(drop)
	var offsets := column_offsets(widths)
	var x_max := WaterCarve.fall_foot(drop, depth) + END_PAST_FOOT_M
	var outward := Vector3(dir.x, 0.0, dir.y)
	var columns: Array[PackedVector3Array] = []
	for w in offsets:
		columns.append(trajectory(doc, lip + across * w, dir, top, bottom, depth, v0, rows, x_max))
	_curtain(buffers, columns, offsets, widths, rows, outward, drop, bottom)
	# Where the middle of the curtain meets the pool: the pool-level row of the column
	# nearest the course.
	var middle := 0
	for i in offsets.size():
		if absf(offsets[i]) < absf(offsets[middle]):
			middle = i
	var pool_row := rows.size() - 2
	var at_pool := columns[middle][pool_row]
	var pool_x := (Vector2(at_pool.x, at_pool.z) - lip).dot(dir)
	var width := widths.x + widths.y
	_ring(buffers, lip, dir, across, pool_x, width, bottom)
	return _mist(buffers, fall, lip, dir, across, pool_x, width, drop, top, bottom)


## COLOR.a of a curtain `width` metres wide at the crest (see the header).
static func width_code(width: float) -> float:
	return clampf(width / WIDTH_ENCODE_M, 0.0, 1.0)


## The curtain's grid: `columns` (one trajectory each, at offsets `offsets` across).
static func _curtain(
	buffers: _Buffers,
	columns: Array[PackedVector3Array],
	offsets: PackedFloat32Array,
	widths: Vector2,
	rows: PackedFloat32Array,
	outward: Vector3,
	drop: float,
	bottom: float
) -> void:
	var first := buffers.vertices.size()
	var count := offsets.size()
	var code := width_code(widths.x + widths.y)
	for i in count:
		var w := offsets[i]
		var fade := clampf(minf(w + widths.x, widths.y - w) / EDGE_FADE_M, 0.0, 1.0)
		for k in rows.size():
			var p := columns[i][k]
			var left := columns[maxi(i - 1, 0)][k]
			var right := columns[mini(i + 1, count - 1)][k]
			var above := columns[i][maxi(k - 1, 0)]
			var below := columns[i][mini(k + 1, rows.size() - 1)]
			var normal := (below - above).cross(right - left)
			if normal.dot(outward) < 0.0:
				normal = -normal
			if normal.length_squared() < 1e-12 or normal.dot(outward) <= 0.0:
				normal = outward
			buffers.add(
				p,
				normal.normalized(),
				Vector2(w + widths.x, rows[k]),
				Vector2(drop, bottom),
				Color(fade, KIND_CURTAIN, 0.0, code)
			)
	for i in count - 1:
		for k in rows.size() - 1:
			var a := first + i * rows.size() + k
			var b := first + (i + 1) * rows.size() + k
			buffers.triangle(a, b, a + 1, outward)
			buffers.triangle(b, b + 1, a + 1, outward)


## The foam ring on the pool (see the header).
static func _ring(
	buffers: _Buffers,
	lip: Vector2,
	dir: Vector2,
	across: Vector2,
	pool_x: float,
	width: float,
	bottom: float
) -> void:
	var radius := ring_radius(width)
	var centre := ring_centre(lip, dir, pool_x, radius)
	var y := bottom + RING_LIFT_M
	var first := buffers.vertices.size()
	buffers.add(
		_point(centre, y),
		Vector3.UP,
		Vector2.ZERO,
		Vector2(radius, bottom),
		Color(1.0, KIND_RING, 0.0, 1.0)
	)
	for s in RING_SEGMENTS:
		var angle := TAU * float(s) / float(RING_SEGMENTS)
		var local := Vector2(cos(angle), sin(angle)) * radius
		var p := centre + across * local.x + dir * local.y
		buffers.add(
			_point(p, y),
			Vector3.UP,
			local,
			Vector2(radius, bottom),
			Color(0.0, KIND_RING, 0.0, 1.0)
		)
	for s in RING_SEGMENTS:
		var rim := first + 1 + s
		var next := first + 1 + (s + 1) % RING_SEGMENTS
		buffers.triangle(first, rim, next, Vector3.UP)


## The mist puffs (see the header); returns the largest half-size placed.
static func _mist(
	buffers: _Buffers,
	fall: Dictionary,
	lip: Vector2,
	dir: Vector2,
	across: Vector2,
	pool_x: float,
	width: float,
	drop: float,
	top: float,
	bottom: float
) -> float:
	var half := mist_half_size(drop, width)
	var count := mist_count(drop, width)
	var rise := minf(drop * MIST_LOW_SHARE, MIST_RISE_MAX_M)
	var base := int(fall.lower_index) * MIST_MAX
	var largest := 0.0
	for j in count:
		var h0 := fposmod(0.5 + float(base + j) * GOLDEN, 1.0)
		var h1 := fposmod(0.25 + float(base + j) * GOLDEN * 2.0, 1.0)
		var h2 := fposmod(0.75 + float(base + j) * GOLDEN * 3.0, 1.0)
		var size := half * lerpf(0.75, 1.0, h1)
		largest = maxf(largest, size)
		var w := (h0 * 2.0 - 1.0) * MIST_SPREAD * width * 0.5
		var x := pool_x * lerpf(MIST_BACK_MIN, MIST_BACK_MAX, h1)
		var y := minf(bottom + size * 0.5 + h2 * rise, top - size * 0.5)
		if j == count - 1 and drop >= MIST_HIGH_MIN_DROP_M:
			# The high puff: near the lip, its top over the brink (the shader lifts it further).
			w = 0.0
			x = pool_x * MIST_HIGH_BACK
			y = top - size * MIST_HIGH_OVER
		var centre := _point(lip + dir * x + across * w, maxf(y, bottom + size * 0.5))
		var first := buffers.vertices.size()
		var corners: Array[Vector2] = [
			Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)
		]
		for corner in corners:
			buffers.add(
				centre,
				Vector3.UP,
				(corner + Vector2.ONE) * 0.5,
				corner * size,
				Color(1.0, KIND_MIST, h2, 1.0)
			)
		# Clockwise seen from the camera once the shader has spread the corners to its right
		# and up.
		buffers.indices.append_array(
			PackedInt32Array([first, first + 2, first + 1, first, first + 3, first + 2])
		)
	return largest


static func _point(xz: Vector2, y: float) -> Vector3:
	return Vector3(xz.x, y, xz.y)


## The mesh arrays being built.
class _Buffers:
	extends RefCounted

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	func add(p: Vector3, normal: Vector3, uv: Vector2, uv2: Vector2, color: Color) -> void:
		vertices.append(p)
		normals.append(normal)
		uvs.append(uv)
		uv2s.append(uv2)
		colors.append(color)

	## Triangle a, b, c wound so its front (Godot: clockwise seen from the front, the face
	## normal (c - a) x (b - a)) faces `front`.
	func triangle(a: int, b: int, c: int, front: Vector3) -> void:
		var pa := vertices[a]
		var normal := (vertices[c] - pa).cross(vertices[b] - pa)
		if normal.dot(front) < 0.0:
			indices.append_array(PackedInt32Array([a, c, b]))
		else:
			indices.append_array(PackedInt32Array([a, b, c]))

	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = vertices
		out[Mesh.ARRAY_NORMAL] = normals
		out[Mesh.ARRAY_TEX_UV] = uvs
		out[Mesh.ARRAY_TEX_UV2] = uv2s
		out[Mesh.ARRAY_COLOR] = colors
		out[Mesh.ARRAY_INDEX] = indices
		return out
