class_name WaterFallFrames
extends RefCounted

## The fall frames of a map (card painter-fall-frame-foam), pure: one small set of numbers per
## waterfall, derived once from the document, that every surface near the fall carries in its
## vertices, so the painted look draws ONE white foam over the brink, down the curtain and on the
## plunge pool from one function (painter/shaders/painter_fall_white.gdshaderinc) instead of a lip
## roll on the curtain, nothing on the river and a separate foam ring on the pool (the spike
## painter-fall-spike, approach 1; its handoff names the seams this removes: C3, the colour band at
## the brink, and C4, the colour jump at the foot). Summary: docs/systems/waterfalls.md (Runtime).
##
## A frame, per fall of WaterFalls.falls(doc) with valid bodies and a direction:
##   lip, dir    the middle of the lip line (map XZ) and the lower course's direction there.
##   widths      the wetted half-widths at the crest, Vector2(left, right)
##               (WaterFallMesh.crest_widths; left is -dir.orthogonal()).
##   x_pool      metres downstream of the lip where the curtain's middle column (the one nearest
##               the course) meets the pool level.
##   drop        top - bottom.
## and what the curtain is built from, so WaterFallMesh traces each column once: "fall" (the
## WaterFalls entry), top, bottom, depth (the lower body's), v0, rows (row_falls), offsets
## (column_offsets) and columns (one trajectory per offset).
##
## The pseudo-arc. Metres along the water from the lip, upstream negative: on the river and the
## pool `along` (the point's distance along dir from the lip) where it is upstream of the lip and
## along + drop past it; on the curtain max(along, 0) + metres fallen. It is 0 at the lip on both
## the river and the curtain, and x_pool + drop (a_pool) where the curtain's middle column meets
## the pool on both the curtain and the pool, so a white keyed to it is continuous over both joins.
##
## Vertex contract (both meshes, FORMAT): CUSTOM0 = (lip x, lip z, dir x, dir z), CUSTOM1 =
## (left half-width, right half-width, x_pool, drop), map space (the meshes' model matrix is the
## identity). All zeros is no fall (a zero direction). The painter shaders read them as FLAT
## varyings and compute along and across from the fragment's own map position, so a triangle uses
## one vertex's frame whole and exactly; interpolating the numbers would blend two frames into
## nonsense where a triangle straddles the edge of a window. On the water surface
## (WaterMeshBuilder) a vertex carries the frame whose window holds it (vertex_frame()); on the
## falls mesh (WaterFallMesh) a curtain vertex carries its own fall's, the ring and the mist zeros.
## Classic's shaders ignore both channels.
##
## The window: WINDOW_UP_M upstream of the lip to WINDOW_DOWN_M past x_pool, out to WINDOW_SIDE x
## the wider crest half-width plus WINDOW_SIDE_M across; it holds the white's whole reach
## (painter_fall_white.gdshaderinc: the brink up to 0.64 m upstream, the foot up to 1.84 m past the
## pool point, 1.45 half-widths across) with a margin of a few samples, so a triangle at its edge
## draws no white whichever frame it takes. Where two windows overlap the nearer fall's wins (the
## distance outside its along span plus the distance across).

## The two custom channels' formats, for add_surface_from_arrays(..., flags).
const FORMAT := (
	(Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
)
const WINDOW_UP_M := 1.2
const WINDOW_DOWN_M := 2.5
const WINDOW_SIDE := 1.5
const WINDOW_SIDE_M := 0.6
## A vertex's channels with no fall: CUSTOM0 then CUSTOM1.
const NONE: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


## The frames of `doc` for its `falls` (WaterFalls.falls(doc)), in order, skipping a fall whose
## bodies are out of range or whose direction is zero (see the header).
static func frames(doc: MapDocument, falls: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for fall in falls:
		if fall.upper_index < 0 or fall.upper_index >= doc.water_bodies.size():
			continue
		if fall.lower_index < 0 or fall.lower_index >= doc.water_bodies.size():
			continue
		var dir: Vector2 = fall.dir
		if dir == Vector2.ZERO:
			continue
		out.append(frame(doc, fall))
	return out


## The frame of one `fall` of `doc` (see the header; the caller has checked its bodies and
## direction).
static func frame(doc: MapDocument, fall: Dictionary) -> Dictionary:
	var upper: WaterBody = doc.water_bodies[fall.upper_index]
	var lower: WaterBody = doc.water_bodies[fall.lower_index]
	var lip: Vector2 = fall.lip
	var dir: Vector2 = fall.dir
	var across := dir.orthogonal()
	var top: float = fall.top
	var bottom: float = fall.bottom
	var drop := top - bottom
	var depth := lower.depth_m()
	var widths := WaterFallMesh.crest_widths(doc, lip, dir, fall.half_width, top)
	var v0 := WaterFallMesh.V0_BASE + WaterFallMesh.V0_PER_SPEED * upper.speed
	var rows := WaterFallMesh.row_falls(drop)
	var offsets := WaterFallMesh.column_offsets(widths)
	var x_max := WaterCarve.fall_foot(drop, depth) + WaterFallMesh.END_PAST_FOOT_M
	var columns: Array[PackedVector3Array] = []
	var middle := 0
	for i in offsets.size():
		var w := offsets[i]
		columns.append(
			WaterFallMesh.trajectory(doc, lip + across * w, dir, top, bottom, depth, v0, rows, x_max)
		)
		if absf(w) < absf(offsets[middle]):
			middle = i
	var at_pool := columns[middle][rows.size() - 2]
	return {
		"fall": fall,
		"lip": lip,
		"dir": dir,
		"widths": widths,
		"x_pool": (Vector2(at_pool.x, at_pool.z) - lip).dot(dir),
		"drop": drop,
		"top": top,
		"bottom": bottom,
		"depth": depth,
		"v0": v0,
		"rows": rows,
		"offsets": offsets,
		"columns": columns,
	}


## The eight channel values of `frame` (CUSTOM0 then CUSTOM1, see the header).
static func channels(frame: Dictionary) -> Array[float]:
	var lip: Vector2 = frame.lip
	var dir: Vector2 = frame.dir
	var widths: Vector2 = frame.widths
	return [lip.x, lip.y, dir.x, dir.y, widths.x, widths.y, float(frame.x_pool), float(frame.drop)]


## How far map point `p` lies from `frame`'s window: < 0 outside it, else the distance outside
## its along span plus the distance across (0 on the course inside the span).
static func window_distance(frame: Dictionary, p: Vector2) -> float:
	var lip: Vector2 = frame.lip
	var dir: Vector2 = frame.dir
	var widths: Vector2 = frame.widths
	var d := p - lip
	var along := d.dot(dir)
	var across := absf(d.dot(dir.orthogonal()))
	var start := -WINDOW_UP_M
	var end := float(frame.x_pool) + WINDOW_DOWN_M
	var side := maxf(widths.x, widths.y) * WINDOW_SIDE + WINDOW_SIDE_M
	if along < start or along > end or across > side:
		return -1.0
	return across


## The channels a vertex at map point `p` carries (see the header): the frame of `frames` whose
## window holds `p` (the nearest by window_distance()), else NONE.
static func vertex_frame(frames: Array[Dictionary], p: Vector2) -> Array[float]:
	var best := -1
	var best_d := INF
	for i in frames.size():
		var d := window_distance(frames[i], p)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = i
	return channels(frames[best]) if best >= 0 else NONE


## CUSTOM0 and CUSTOM1 for `vertices` (map space): [PackedFloat32Array, PackedFloat32Array], four
## floats per vertex each (vertex_frame()).
static func vertex_channels(
	frames: Array[Dictionary], vertices: PackedVector3Array
) -> Array[PackedFloat32Array]:
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	custom0.resize(vertices.size() * 4)
	custom1.resize(vertices.size() * 4)
	if not frames.is_empty():
		for i in vertices.size():
			var v := vertices[i]
			var c := vertex_frame(frames, Vector2(v.x, v.z))
			for k in 4:
				custom0[i * 4 + k] = c[k]
				custom1[i * 4 + k] = c[k + 4]
	return [custom0, custom1]


## The pseudo-arc (see the header) of a point of the river or the pool at map point `p`, as the
## water shader computes it from `frame`.
static func water_arc(frame: Dictionary, p: Vector2) -> float:
	var along := (p - (frame.lip as Vector2)).dot(frame.dir as Vector2)
	return along if along < 0.0 else along + float(frame.drop)


## The pseudo-arc of a point of the curtain at map point `p`, `fallen` metres under the lip, as the
## waterfall shader computes it from `frame`.
static func curtain_arc(frame: Dictionary, p: Vector2, fallen: float) -> float:
	var along := (p - (frame.lip as Vector2)).dot(frame.dir as Vector2)
	return maxf(along, 0.0) + fallen
