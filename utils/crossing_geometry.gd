class_name CrossingGeometry
extends RefCounted

## The geometry of a map document's crossings (MapDocument.crossings, Crossing), pure: mesh
## arrays, collision triangles and the deck heights the grid lies on, built from the crossings'
## fields and the document's ground alone, so every peer builds the same crossing. Safe on any
## thread (no Node, no resource the renderer owns): AuthoredLoadPrep runs build() on a worker
## during a load, AuthoredCrossings makes the nodes from its output. Summary:
## docs/systems/crossings.md.
##
## Frame. Everything is in the map frame (the document's), under a node at the map origin with
## an identity transform, like AuthoredWater. Along a crossing, u runs from its start anchor
## (u = 0) to its end anchor (u = span), v across it (to the left of the start-to-end
## direction), y up.
##
## Plank footbridge (house style: chunky, a few big readable parts, nothing fussy at play
## zoom). The walking surface follows deck_y(): a quadratic arch through the three levels. On it
## lie planks across the span, one PLANK_PITCH_M apart, each with a little jitter in length,
## offset, yaw, drop and colour so the deck reads as hand-laid boards; two stringers carry them
## along the arch onto a sill beam bedded in each bank; posts stand along both edges
## (POST_SPACING_M apart at most, one at each end) under a single top rail; a long span over
## ground well below the deck gets pile bents (two piles and a cap beam) down to the bed. The
## wood samples the palette's `planks` surface: each box's grain runs along its length, and its
## faces map into one board of the texture (WOOD_SWATCHES, clean runs between the texture's
## own joints), so a modelled plank never shows a painted seam. The deck's collision is its
## walking surface as a smooth strip (the planks' jitter stays visual).
##
## Stepping stones: flat-topped, slightly irregular stones along the line one stride apart
## (the document's grid cell: about one 5 ft square per step), centred on the span, each
## rooted in the bed so it never floats. A stone's top is the middle level (just above the
## water), raised to STONE_ABOVE_GROUND_M over the ground where a bank rises under it. Flat
## shaded facets (a chamfered top ring, a shoulder, a flared root) read like the palette's
## rocks. The stones take a rock surface triplanar (AuthoredCrossings' material); their vertex
## colour darkens the root below the top, where the water wets it. Collision is the stones'
## own triangles.
##
## Stone arch (phase 4d): CrossingArch builds it (abutments, barrel, spandrels, pier,
## parapets in `stone`; the paved deck slab in `paving`) on the same deck_y curve, so its
## collision, deck field and clearance are a deck's (Crossing.is_deck()).
##
## Ford (phase 4d, P4d-2): CrossingFord builds it (the gravel bar and its bank landings in
## `gravel`, its marker stones in `stone`, stone() for each); like the stones it has no deck
## (no deck field: the grid lies on the water over it) and its collision is its own
## triangles, bar and stones.
##
## Winding: clockwise seen from the front (Godot's front face, as the terrain and water).

## Plank deck (metres).
const PLANK_THICK_M := 0.06
const PLANK_PITCH_M := 0.27
const PLANK_GAP_M := 0.04
const STRINGER_W_M := 0.12
const STRINGER_H_M := 0.14
## Stringer centre from the deck edge.
const STRINGER_INSET_M := 0.16
const SILL_W_M := 0.24
## A sill's top sits this far above the bank ground at its anchor, its body at least SILL_H_M
## deep, sunk SILL_SINK_M into the ground.
const SILL_ABOVE_M := 0.0
const SILL_H_M := 0.2
const SILL_SINK_M := 0.1
## How far the walking surface stands over the bank ground at an anchor: sill, stringer and
## plank stacked. CrossingPlacement sets a plank crossing's end levels to the ground plus this.
const DECK_ABOVE_BANK_M := SILL_ABOVE_M + STRINGER_H_M + PLANK_THICK_M
const POST_W_M := 0.11
const POST_H_M := 0.8
const POST_SPACING_M := 2.2
## End posts stand this far inside the anchors.
const POST_END_INSET_M := 0.14
const RAIL_W_M := 0.075
const RAIL_H_M := 0.085
## Pile bents: only on a span over PILE_MIN_SPAN_M, at most PILE_SPACING_M apart, and only
## where the ground is more than PILE_MIN_DROP_M below the stringers.
const PILE_W_M := 0.16
const PILE_SPACING_M := 3.0
const PILE_MIN_SPAN_M := 5.5
const PILE_MIN_DROP_M := 0.45
const PILE_BURY_M := 0.3
const CAP_H_M := 0.13
## Stringer segments and collision strip resolution along the span.
const SEGMENT_M := 0.4
## The grid's deck field reaches this far past the deck's edges and ends, over a sample, so the
## grid shader's triangles along a deck's edge have a deck height at every corner
## (GroundHeightField's deck texture).
const DECK_FIELD_PAD_M := 0.3
## Wood texture: world size of one repeat (the palette's planks tile_m), and the clean boards
## of its albedo in UV (u0, v0, width, height): runs between the painted joints, inset from
## the painted gaps.
const WOOD_TILE_M := 2.0
const WOOD_SWATCHES: Array[Rect2] = [
	Rect2(0.012, 0.23, 0.09, 0.76),
	Rect2(0.126, 0.0, 0.118, 0.75),
	Rect2(0.27, 0.47, 0.138, 0.52),
	Rect2(0.436, 0.405, 0.096, 0.59),
	Rect2(0.56, 0.09, 0.135, 0.9),
	Rect2(0.725, 0.39, 0.112, 0.6),
	Rect2(0.866, 0.4, 0.1, 0.59),
	Rect2(0.27, 0.0, 0.138, 0.45),
]
## Wood vertex colours: planks vary in lightness around 1, the frame is darker.
const PLANK_SHADE_MIN := 0.82
const PLANK_SHADE_MAX := 1.08
const FRAME_SHADE := 0.72
const SILL_SHADE := 0.6
## Stepping stones (metres unless noted).
const STONE_SIDES := 9
## The profile from the top down: a flat top out to STONE_TOP_INSET of the radius, a chamfer
## out to STONE_CHAMFER_INSET, STONE_CHAMFER_M lower, then the rounded shoulder at the full
## radius STONE_SHOULDER_M below the top (about the waterline), then the flared root.
const STONE_TOP_INSET := 0.7
## The top is a fan to an inner ring at this share of the radius, then a band out to the top
## ring: facets small enough that a stone's moss (AuthoredCrossings.moss_split, decided per
## facet like the palette rocks') forms patches instead of pie slices (P4b-3).
const STONE_INNER_INSET := 0.36
const STONE_CHAMFER_INSET := 0.93
const STONE_CHAMFER_M := 0.045
const STONE_SHOULDER_M := 0.14
const STONE_DOME_M := 0.012
## The root flares to this share of the radius and goes this far under the bed.
const STONE_ROOT_FLARE := 1.15
const STONE_BURY_M := 0.15
const STONE_ABOVE_GROUND_M := 0.06
## The first and last stone stand at least this far inside the anchors.
const STONE_END_GAP_M := 0.55
## Stone colours: top, shoulder, root (the wet part under the water).
const STONE_TOP_SHADE := 1.0
const STONE_SIDE_SHADE := 0.86
const STONE_ROOT_SHADE := 0.55
## The deck field and heights outside every deck.
const NONE := -INF
## Plants keep off a crossing (clearance()): its footprint grown by CLEAR_MARGIN_M across and
## CLEAR_ANCHOR_M past each anchor (the bank landings), fading back in over CLEAR_SOFT_M.
const CLEAR_MARGIN_M := 0.35
const CLEAR_ANCHOR_M := 0.9
const CLEAR_SOFT_M := 0.5
## Trees (and shrubs and rocks, less) keep this much further back, so a trunk never crowds a landing
## and a canopy does not hide the deck (P4b-3 judgment set: a pine 1.5 m off a forest
## bridge's landing hid its end and the token on it in play; bushes grew over a landing).
## Canopies still frame a crossing.
const CLEAR_TREE_M := 1.2
const CLEAR_SHRUB_M := 0.6


## Mesh arrays built one quad at a time. Tangents (4 floats per vertex) point along +U with
## the binormal sign in w, as mikktspace would give for these planar quads.
class _Mesh:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var tangents: PackedFloat32Array = PackedFloat32Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var colors: PackedColorArray = PackedColorArray()
	var indices: PackedInt32Array = PackedInt32Array()

	## A planar quad with corners `p` (four, in order around it) facing `normal`, UVs `uv` per
	## corner and one colour. Emitted clockwise seen from the front whatever the corner order.
	func quad(p: Array[Vector3], uv: Array[Vector2], normal: Vector3, color: Color) -> void:
		var base := vertices.size()
		var du1 := uv[1] - uv[0]
		var du2 := uv[3] - uv[0]
		var e1 := p[1] - p[0]
		var e2 := p[3] - p[0]
		var det := du1.x * du2.y - du2.x * du1.y
		var tangent := e1
		var handed := 1.0
		if absf(det) > 1e-9:
			tangent = (e1 * du2.y - e2 * du1.y) / det
			var bitangent := (e2 * du1.x - e1 * du2.x) / det
			handed = 1.0 if normal.cross(tangent).dot(bitangent) >= 0.0 else -1.0
		tangent = (tangent - normal * normal.dot(tangent)).normalized()
		for k in 4:
			vertices.append(p[k])
			normals.append(normal)
			uvs.append(uv[k])
			colors.append(color)
			tangents.append_array(PackedFloat32Array([tangent.x, tangent.y, tangent.z, handed]))
		var clockwise := (p[1] - p[0]).cross(p[2] - p[0]).dot(normal) < 0.0
		if clockwise:
			indices.append_array(
				PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])
			)
		else:
			indices.append_array(
				PackedInt32Array([base, base + 2, base + 1, base, base + 3, base + 2])
			)

	## One flat-shaded triangle (a stone facet); UVs are unused (triplanar) and zero.
	func triangle(a: Vector3, b: Vector3, c: Vector3, color: Color, outward: Vector3) -> void:
		var normal := (b - a).cross(c - a).normalized()
		if normal.dot(outward) > 0.0:
			# Counter-clockwise from outside: swap to Godot's clockwise front.
			var swap := b
			b = c
			c = swap
			normal = -normal
		normal = -normal
		var base := vertices.size()
		for v in [a, b, c]:
			vertices.append(v)
			normals.append(normal)
			uvs.append(Vector2.ZERO)
			colors.append(color)
			tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2]))

	func is_empty() -> bool:
		return vertices.is_empty()

	func to_arrays() -> Array:
		if vertices.is_empty():
			return []
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TANGENT] = tangents
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		return arrays


# --- the whole document --------------------------------------------------------------


## Everything AuthoredCrossings needs for `doc`: {"crossings": [one Dictionary per crossing:
## "id", "kind", "style", "wood" (mesh arrays, [] for none), "stone" (mesh arrays, [] for
## none; a stone arch's masonry and a ford's marker stones too), "paving" (mesh arrays, an
## arch's deck slab, [] for none), "gravel" (mesh arrays, a ford's bar and landings, [] for
## none), "collision" (PackedVector3Array triangles), "top" (highest walking surface, map
## Y)], "deck": the deck field (deck_field(), empty without a deck crossing)}. Pure.
static func build(doc: MapDocument) -> Dictionary:
	var out: Array = []
	for crossing in doc.crossings:
		out.append(build_one(doc, crossing))
	return {"crossings": out, "deck": deck_field(doc, doc.crossings)}


## One crossing's parts (see build()).
static func build_one(doc: MapDocument, crossing: Crossing) -> Dictionary:
	var parts := {
		"id": crossing.id,
		"kind": crossing.kind,
		"style": crossing.style,
		"wood": [],
		"stone": [],
		"paving": [],
		"gravel": [],
		"collision": PackedVector3Array(),
		"top": NONE,
	}
	if crossing.span_m() <= 0.0:
		return parts
	if crossing.is_plank():
		var wood := _Mesh.new()
		_plank_bridge(doc, crossing, wood)
		parts.wood = wood.to_arrays()
		parts.collision = deck_collision(crossing)
		parts.top = deck_top(crossing)
	elif crossing.is_arch():
		var masonry := _Mesh.new()
		var paving := _Mesh.new()
		CrossingArch.build(doc, crossing, masonry, paving)
		parts.stone = masonry.to_arrays()
		parts.paving = paving.to_arrays()
		parts.collision = deck_collision(crossing)
		parts.top = deck_top(crossing)
	elif crossing.is_ford():
		var gravel := _Mesh.new()
		var markers := _Mesh.new()
		CrossingFord.build(doc, crossing, gravel, markers)
		parts.gravel = gravel.to_arrays()
		parts.stone = markers.to_arrays()
		# A token lands on the bar and on the marker stones alike.
		parts.collision = faces_of(gravel) + faces_of(markers)
		parts.top = maxf(highest(gravel), highest(markers))
	else:
		var rocks := _Mesh.new()
		var top := NONE
		for spec in stone_layout(doc, crossing):
			stone(spec, rocks)
			top = maxf(top, float(spec.top))
		parts.stone = rocks.to_arrays()
		parts.collision = faces_of(rocks)
		parts.top = top
	return parts


## `mesh`'s triangles as collision faces (every three vertices one face, in index order).
static func faces_of(mesh: _Mesh) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for i in mesh.indices:
		faces.append(mesh.vertices[i])
	return faces


## The highest vertex of `mesh` (map Y), NONE when it is empty.
static func highest(mesh: _Mesh) -> float:
	var top := NONE
	for v in mesh.vertices:
		top = maxf(top, v.y)
	return top


# --- the deck ------------------------------------------------------------------------


## The walking surface's height at fraction `t` (0 at the start anchor, 1 at the end) of a
## crossing whose levels are `levels` (start, middle, end): the quadratic through them (a
## Bezier whose control point puts the middle level at t = 0.5). Pure.
static func deck_y(levels: Vector3, t: float) -> float:
	var control := 2.0 * levels.y - 0.5 * (levels.x + levels.z)
	var s := 1.0 - t
	return s * s * levels.x + 2.0 * s * t * control + t * t * levels.z


## d(deck_y)/dt at fraction `t`.
static func deck_slope(levels: Vector3, t: float) -> float:
	var control := 2.0 * levels.y - 0.5 * (levels.x + levels.z)
	return 2.0 * (1.0 - t) * (control - levels.x) + 2.0 * t * (levels.z - control)


## The highest point of a deck crossing's walking surface.
static func deck_top(crossing: Crossing) -> float:
	var top := maxf(crossing.levels.x, crossing.levels.z)
	var control := 2.0 * crossing.levels.y - 0.5 * (crossing.levels.x + crossing.levels.z)
	var denominator := crossing.levels.x - 2.0 * control + crossing.levels.z
	if absf(denominator) > 1e-9:
		var t := (crossing.levels.x - control) / denominator
		if t > 0.0 and t < 1.0:
			top = maxf(top, deck_y(crossing.levels, t))
	return top


## Map XYZ of the point `u` along and `v` across `crossing` at height `y`.
static func point(crossing: Crossing, u: float, v: float, y: float) -> Vector3:
	var d := crossing.direction()
	var left := Vector2(-d.y, d.x)
	var p := crossing.start + d * u + left * v
	return Vector3(p.x, y, p.y)


## (u along, v across) of map point `p` in `crossing`'s frame.
static func local_of(crossing: Crossing, p: Vector2) -> Vector2:
	var d := crossing.direction()
	var rel := p - crossing.start
	return Vector2(rel.dot(d), rel.dot(Vector2(-d.y, d.x)))


## The deck field of `crossings` over `doc`'s sample grid: per sample the highest deck
## walking surface (plank or arch, Crossing.is_deck()) over it (its nearest point along the
## span), within DECK_FIELD_PAD_M past the deck's edges and ends, NONE elsewhere; empty when
## no crossing has a deck. The grid's ground field raises to it
## (GroundHeightField.raise_to_decks). Pure.
static func deck_field(doc: MapDocument, crossings: Array[Crossing]) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	var columns := doc.samples_x()
	var rows := doc.samples_z()
	for crossing in crossings:
		var span := crossing.span_m()
		if not crossing.is_deck() or span <= 0.0:
			continue
		if field.is_empty():
			field.resize(columns * rows)
			field.fill(NONE)
		var half := crossing.width_m * 0.5 + DECK_FIELD_PAD_M
		var box := Rect2(crossing.start, Vector2.ZERO).expand(crossing.end).grow(half)
		var first := Vector2i(doc.world_to_sample(box.position).floor())
		var last := Vector2i(doc.world_to_sample(box.end).ceil())
		for z in range(maxi(first.y, 0), mini(last.y + 1, rows)):
			for x in range(maxi(first.x, 0), mini(last.x + 1, columns)):
				var uv := local_of(crossing, doc.sample_to_world(Vector2(x, z)))
				if absf(uv.y) > half or uv.x < -DECK_FIELD_PAD_M or uv.x > span + DECK_FIELD_PAD_M:
					continue
				var y := deck_y(crossing.levels, clampf(uv.x / span, 0.0, 1.0))
				var at := z * columns + x
				field[at] = maxf(field[at], y)
	return field


## What plants may keep at map point `p` beside `crossings` (ScatterGround): 0 on a
## crossing's footprint (its deck, posts or stones, and CLEAR_ANCHOR_M of bank past each
## anchor), 1 from CLEAR_SOFT_M beyond it, smooth between. Pure; cheap per point (a few
## multiplies per crossing).
## `extra` widens the whole footprint (trees CLEAR_TREE_M, shrubs CLEAR_SHRUB_M).
static func clearance(crossings: Array[Crossing], p: Vector2, extra: float = 0.0) -> float:
	var keep := 1.0
	var anchor := CLEAR_ANCHOR_M + extra
	for crossing in crossings:
		var span := crossing.span_m()
		if span <= 0.0:
			continue
		var uv := local_of(crossing, p)
		var half := crossing.width_m * 0.5 + CLEAR_MARGIN_M + extra
		var du := maxf(maxf(-anchor - uv.x, uv.x - span - anchor), 0.0)
		var dv := maxf(absf(uv.y) - half, 0.0)
		keep = minf(keep, smoothstep(0.0, CLEAR_SOFT_M, Vector2(du, dv).length()))
	return keep


## The map rectangle clearance() reads for `crossing` (its footprint and fade).
static func clear_bounds(crossing: Crossing) -> Rect2:
	var reach := (
		crossing.width_m * 0.5 + CLEAR_MARGIN_M + CLEAR_SOFT_M + CLEAR_ANCHOR_M + CLEAR_TREE_M
	)
	return Rect2(crossing.start, Vector2.ZERO).expand(crossing.end).grow(reach)


## The walking surface of a deck crossing (plank or arch) as collision triangles: a strip
## across the deck's width, SEGMENT_M long pieces along the arch.
static func deck_collision(crossing: Crossing) -> PackedVector3Array:
	var faces := PackedVector3Array()
	var span := crossing.span_m()
	var pieces := maxi(1, ceili(span / SEGMENT_M))
	var half := crossing.width_m * 0.5
	for k in pieces:
		var u0 := span * k / pieces
		var u1 := span * (k + 1) / pieces
		var y0 := deck_y(crossing.levels, float(k) / pieces)
		var y1 := deck_y(crossing.levels, float(k + 1) / pieces)
		var a := point(crossing, u0, -half, y0)
		var b := point(crossing, u0, half, y0)
		var c := point(crossing, u1, half, y1)
		var d := point(crossing, u1, -half, y1)
		faces.append_array(PackedVector3Array([a, c, b, a, d, c]))
	return faces


# --- plank bridge -------------------------------------------------------------------


## A deterministic generator for `crossing`'s variation (every peer draws the same).
static func rng_for(doc: MapDocument, crossing: Crossing) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([doc.map_seed, crossing.id, crossing.kind])
	return rng


static func _plank_bridge(doc: MapDocument, crossing: Crossing, mesh: _Mesh) -> void:
	var rng := rng_for(doc, crossing)
	var span := crossing.span_m()
	var d := crossing.direction()
	var left := Vector3(-d.y, 0.0, d.x)
	var half := crossing.width_m * 0.5
	_planks(crossing, rng, mesh)
	# Stringers along the arch, reaching past each anchor onto the sills.
	var under := PLANK_THICK_M
	for side in [-1.0, 1.0]:
		var v: float = side * (half - STRINGER_INSET_M)
		var reach := SILL_W_M * 0.5 + 0.06
		var pieces := maxi(2, ceili((span + 2.0 * reach) / SEGMENT_M))
		for k in pieces:
			var u0 := -reach + (span + 2.0 * reach) * k / pieces
			var u1 := -reach + (span + 2.0 * reach) * (k + 1) / pieces
			var mid0 := _deck_at(crossing, u0) - under - STRINGER_H_M * 0.5
			var mid1 := _deck_at(crossing, u1) - under - STRINGER_H_M * 0.5
			var a := point(crossing, u0, v, mid0)
			var b := point(crossing, u1, v, mid1)
			# Overlap the next piece a little so the joint never opens on the arch.
			var along := (b - a).normalized()
			a -= along * 0.02
			b += along * 0.02
			_beam(mesh, a, b, left, STRINGER_W_M, STRINGER_H_M, FRAME_SHADE, rng)
	# Sills bedded in each bank under the stringers' ends.
	for u in [0.0, span]:
		var top := _deck_at(crossing, u) - under - STRINGER_H_M
		var ground := minf(
			_ground(doc, point(crossing, u, -half, 0.0)),
			_ground(doc, point(crossing, u, half, 0.0))
		)
		var bottom := minf(top - SILL_H_M, ground - SILL_SINK_M)
		var reach_v := half + 0.18
		var centre := point(crossing, u, 0.0, (top + bottom) * 0.5)
		_box(
			mesh,
			centre,
			left,
			Vector3.UP,
			Vector3(reach_v, (top - bottom) * 0.5, SILL_W_M * 0.5),
			Color(SILL_SHADE, SILL_SHADE, SILL_SHADE),
			rng
		)
	_piles(doc, crossing, rng, mesh)
	_rails(doc, crossing, rng, mesh)


## The walking surface at `u` along the span (flat past the anchors).
static func _deck_at(crossing: Crossing, u: float) -> float:
	return deck_y(crossing.levels, clampf(u / crossing.span_m(), 0.0, 1.0))


static func _ground(doc: MapDocument, p: Vector3) -> float:
	return WaterGeometry.ground_at(doc, Vector2(p.x, p.z))


static func _planks(crossing: Crossing, rng: RandomNumberGenerator, mesh: _Mesh) -> void:
	var span := crossing.span_m()
	var d := crossing.direction()
	var count := maxi(1, floori((span + PLANK_GAP_M) / PLANK_PITCH_M))
	var pitch := (span + PLANK_GAP_M) / count
	var board := pitch - PLANK_GAP_M
	var half := crossing.width_m * 0.5
	for k in count:
		var u := pitch * (k + 0.5) - PLANK_GAP_M * 0.5
		var t := u / span
		var slope := deck_slope(crossing.levels, t) / span
		var along_span := Vector3(d.x, slope, d.y).normalized()
		var across := Vector3(-d.y, 0.0, d.x)
		var up := along_span.cross(across).normalized()
		if up.y < 0.0:
			up = -up
		var yaw := deg_to_rad(rng.randf_range(-2.0, 2.0))
		across = across.rotated(up, yaw)
		var length := half + rng.randf_range(-0.03, 0.05)
		var offset := rng.randf_range(-0.04, 0.04)
		var drop := rng.randf_range(0.0, 0.012)
		var top := deck_y(crossing.levels, t) - drop
		var centre := point(crossing, u, offset, top) - up * (PLANK_THICK_M * 0.5)
		var shade := rng.randf_range(PLANK_SHADE_MIN, PLANK_SHADE_MAX)
		var warm := rng.randf_range(-0.03, 0.03)
		_box(
			mesh,
			centre,
			across,
			up,
			Vector3(length, PLANK_THICK_M * 0.5, board * rng.randf_range(0.46, 0.5)),
			Color(shade + warm, shade, shade - warm),
			rng
		)


static func _piles(
	doc: MapDocument, crossing: Crossing, rng: RandomNumberGenerator, mesh: _Mesh
) -> void:
	var span := crossing.span_m()
	if span <= PILE_MIN_SPAN_M:
		return
	var bents := maxi(1, ceili(span / PILE_SPACING_M) - 1)
	var half := crossing.width_m * 0.5
	var left := Vector3(-crossing.direction().y, 0.0, crossing.direction().x)
	var shade := Color(FRAME_SHADE, FRAME_SHADE, FRAME_SHADE) * 0.92
	for k in bents:
		var u := span * (k + 1) / (bents + 1)
		var cap_top := _deck_at(crossing, u) - PLANK_THICK_M - STRINGER_H_M
		var cap_bottom := cap_top - CAP_H_M
		var lowest := INF
		for side in [-1.0, 1.0]:
			lowest = minf(
				lowest, _ground(doc, point(crossing, u, side * (half - STRINGER_INSET_M), 0))
			)
		if cap_bottom - lowest < PILE_MIN_DROP_M:
			continue
		_box(
			mesh,
			point(crossing, u, 0.0, (cap_top + cap_bottom) * 0.5),
			left,
			Vector3.UP,
			Vector3(half + 0.05, CAP_H_M * 0.5, CAP_H_M * 0.5),
			shade,
			rng
		)
		for side in [-1.0, 1.0]:
			var v: float = side * (half - STRINGER_INSET_M)
			var bottom := _ground(doc, point(crossing, u, v, 0)) - PILE_BURY_M
			var centre := point(crossing, u, v, (cap_bottom + bottom) * 0.5)
			_box(
				mesh,
				centre,
				Vector3.UP,
				left,
				Vector3((cap_bottom - bottom) * 0.5, PILE_W_M * 0.5, PILE_W_M * 0.5),
				shade,
				rng
			)


## Posts along both edges and a top rail between them.
static func _rails(
	doc: MapDocument, crossing: Crossing, rng: RandomNumberGenerator, mesh: _Mesh
) -> void:
	var span := crossing.span_m()
	var inner := maxf(span - 2.0 * POST_END_INSET_M, 0.0)
	var gaps := maxi(1, ceili(inner / POST_SPACING_M))
	var half := crossing.width_m * 0.5
	var frame := Color(FRAME_SHADE, FRAME_SHADE, FRAME_SHADE)
	for side in [-1.0, 1.0]:
		var v: float = side * (half + POST_W_M * 0.5)
		var tops: Array[Vector3] = []
		for k in gaps + 1:
			var u := POST_END_INSET_M + inner * k / gaps
			var deck := _deck_at(crossing, u)
			var end_post := k == 0 or k == gaps
			var bottom := deck - PLANK_THICK_M - STRINGER_H_M - 0.04
			if end_post:
				bottom = minf(bottom, _ground(doc, point(crossing, u, v, 0.0)) - 0.12)
			var height := POST_H_M + (0.06 if end_post else rng.randf_range(-0.02, 0.02))
			var top := deck + height
			var lean := Vector3(rng.randf_range(-0.012, 0.012), 0.0, rng.randf_range(-0.012, 0.012))
			var axis := (Vector3.UP + lean).normalized()
			var foot := point(crossing, u, v, bottom)
			var head := foot + axis * (top - bottom)
			var d := crossing.direction()
			var along := Vector3(d.x, 0.0, d.y)
			_box(
				mesh,
				(foot + head) * 0.5,
				axis,
				along,
				Vector3((top - bottom) * 0.5, POST_W_M * 0.5, POST_W_M * 0.5),
				frame * rng.randf_range(0.92, 1.05),
				rng
			)
			tops.append(point(crossing, u, v, deck + POST_H_M - RAIL_H_M * 0.5 - 0.01))
		for k in tops.size() - 1:
			var a := tops[k]
			var b := tops[k + 1]
			var direction := (b - a).normalized()
			_beam(
				mesh,
				a - direction * POST_W_M * 0.6,
				b + direction * POST_W_M * 0.6,
				Vector3(-crossing.direction().y, 0.0, crossing.direction().x),
				RAIL_W_M,
				RAIL_H_M,
				FRAME_SHADE * 1.06,
				rng
			)


## A beam from `a` to `b` (its centre line), `width` across (along `side`, levelled) and
## `height` deep, grain along its length.
static func _beam(
	mesh: _Mesh,
	a: Vector3,
	b: Vector3,
	side: Vector3,
	width: float,
	height: float,
	shade: float,
	rng: RandomNumberGenerator
) -> void:
	var along := (b - a).normalized()
	var across := (side - along * along.dot(side)).normalized()
	var up := along.cross(across).normalized()
	if up.y < 0.0:
		up = -up
	var tone := shade * rng.randf_range(0.94, 1.04)
	_box(
		mesh,
		(a + b) * 0.5,
		along,
		up,
		Vector3(a.distance_to(b) * 0.5, height * 0.5, width * 0.5),
		Color(tone, tone, tone),
		rng
	)


## A box centred at `centre` whose grain runs along `along`, with `up` its second axis (the
## third is their cross product) and half extents `half` (along, up, third). Each face maps
## into one board of the wood texture (WOOD_SWATCHES): V along the grain at WOOD_TILE_M per
## repeat (squeezed to fit a board shorter than the face), U across the face's width.
static func _box(
	mesh: _Mesh,
	centre: Vector3,
	along: Vector3,
	up: Vector3,
	half: Vector3,
	color: Color,
	rng: RandomNumberGenerator
) -> void:
	var a := along.normalized()
	var b := (up - a * a.dot(up)).normalized()
	var c := a.cross(b).normalized()
	var axes: Array[Vector3] = [a, b, c]
	var extents: Array[float] = [half.x, half.y, half.z]
	var swatch := WOOD_SWATCHES[rng.randi_range(0, WOOD_SWATCHES.size() - 1)]
	var length := 2.0 * half.x
	var v_scale := minf(1.0 / WOOD_TILE_M, swatch.size.y / maxf(length, 1e-4))
	var v_room := maxf(swatch.size.y - length * v_scale, 0.0)
	var v0 := swatch.position.y + rng.randf_range(0.0, v_room)
	for face in 3:
		for facing in [1.0, -1.0]:
			var n: Vector3 = axes[face] * facing
			var s: int = (face + 1) % 3
			var t: int = (face + 2) % 3
			var o: Vector3 = centre + n * extents[face]
			var es: Vector3 = axes[s] * extents[s]
			var et: Vector3 = axes[t] * extents[t]
			var corners: Array[Vector3] = [o - es - et, o + es - et, o + es + et, o - es + et]
			var uv: Array[Vector2] = []
			for k in 4:
				var cs := 1.0 if k == 1 or k == 2 else -1.0
				var ct := 1.0 if k >= 2 else -1.0
				# The grain axis (0) maps to V; the other to U across the board.
				var grain := 0.0
				var cross_share := 0.0
				if s == 0:
					grain = cs * extents[0]
					cross_share = ct * 0.5 + 0.5
				elif t == 0:
					grain = ct * extents[0]
					cross_share = cs * 0.5 + 0.5
				else:
					# An end face: a small patch of the board's end.
					grain = ct * minf(extents[t], 0.05)
					cross_share = cs * 0.5 + 0.5
				uv.append(
					Vector2(
						swatch.position.x + cross_share * swatch.size.x,
						v0 + (grain + extents[0]) * v_scale
					)
				)
			mesh.quad(corners, uv, n, color)


# --- stepping stones ----------------------------------------------------------------


## Where `crossing`'s stones stand: one Dictionary per stone {"at": Vector2 map XZ, "radius",
## "aspect" (length over breadth of its outline), "yaw" (radians), "top" (map Y of its top),
## "bed" (map Y of the ground under it), "seed" (int, its outline)}. One stride (the
## document's grid cell) apart along the span, centred on it, at least STONE_END_GAP_M inside
## each anchor, each nudged a little across and along the line. Pure and deterministic.
static func stone_layout(doc: MapDocument, crossing: Crossing) -> Array[Dictionary]:
	var stones: Array[Dictionary] = []
	var span := crossing.span_m()
	if span <= 0.0:
		return stones
	var stride := doc.cell_size_m
	var room := maxf(span - 2.0 * STONE_END_GAP_M, 0.0)
	var count := floori(room / stride) + 1
	var rng := rng_for(doc, crossing)
	var d := crossing.direction()
	for k in count:
		var u := span * 0.5 + (k - (count - 1) * 0.5) * stride + rng.randf_range(-0.08, 0.08)
		var zig := (0.09 if k % 2 == 0 else -0.09) + rng.randf_range(-0.06, 0.06)
		var at := crossing.start + d * u + Vector2(-d.y, d.x) * zig
		var bed := WaterGeometry.ground_at(doc, at)
		var top := maxf(crossing.levels.y, bed + STONE_ABOVE_GROUND_M)
		top += rng.randf_range(-0.02, 0.02)
		(
			stones
			. append(
				{
					"at": at,
					"radius": crossing.width_m * 0.5 * rng.randf_range(0.84, 1.14),
					"aspect": rng.randf_range(1.0, 1.35),
					"yaw": atan2(d.y, d.x) + rng.randf_range(-0.6, 0.6),
					"top": top,
					"bed": bed,
					"seed": rng.randi(),
				}
			)
		)
	return stones


## One stone of stone_layout() (or a ford's marker stone, CrossingFord, the same spec shape)
## as flat-shaded facets: a nearly flat top fan, a chamfer, a rounded shoulder about the
## waterline, and sides flaring to a root under the bed (see the STONE_* profile constants).
static func stone(spec: Dictionary, mesh: _Mesh) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(spec.seed)
	var at: Vector2 = spec.at
	var radius: float = spec.radius
	var aspect: float = spec.aspect
	var yaw: float = spec.yaw
	var top: float = spec.top
	var shoulder := top - STONE_SHOULDER_M * rng.randf_range(0.85, 1.15)
	var bottom: float = minf(float(spec.bed) - STONE_BURY_M, shoulder - 0.05)
	# Rings from the top down: top, chamfer, shoulder, root; and the top's inner ring.
	var rings: Array[PackedVector3Array] = [
		PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()
	]
	var inner := PackedVector3Array()
	var phase := rng.randf_range(0.0, TAU)
	for k in STONE_SIDES:
		var angle := phase + TAU * k / STONE_SIDES + rng.randf_range(-0.18, 0.18)
		var r := radius * rng.randf_range(0.86, 1.1)
		var local := Vector2(cos(angle) * r * sqrt(aspect), sin(angle) * r / sqrt(aspect))
		var o := local.rotated(yaw)
		var lift := rng.randf_range(-0.01, 0.01)
		var chamfer := top - STONE_CHAMFER_M * rng.randf_range(0.7, 1.3)
		var flare := STONE_ROOT_FLARE * rng.randf_range(0.95, 1.05)
		# Between the top ring's corners, turned half a side, so the band is a zigzag.
		var half_turn := local.rotated(PI / STONE_SIDES).rotated(yaw) * STONE_INNER_INSET
		inner.append(
			Vector3(
				at.x + half_turn.x,
				top + STONE_DOME_M * 0.6 + rng.randf_range(-0.006, 0.006),
				at.y + half_turn.y
			)
		)
		rings[0].append(
			Vector3(at.x + o.x * STONE_TOP_INSET, top + lift, at.y + o.y * STONE_TOP_INSET)
		)
		rings[1].append(
			Vector3(at.x + o.x * STONE_CHAMFER_INSET, chamfer, at.y + o.y * STONE_CHAMFER_INSET)
		)
		rings[2].append(Vector3(at.x + o.x, shoulder + lift, at.y + o.y))
		rings[3].append(Vector3(at.x + o.x * flare, bottom, at.y + o.y * flare))
	var centre := Vector3(at.x, top + STONE_DOME_M, at.y)
	var tone := rng.randf_range(0.9, 1.06)
	var shades: Array[float] = [
		STONE_TOP_SHADE, lerpf(STONE_TOP_SHADE, STONE_SIDE_SHADE, 0.4), STONE_ROOT_SHADE
	]
	var colors: Array[Color] = []
	for shade in shades:
		colors.append(Color(shade * tone, shade * tone, shade * tone))
	var middle := Vector3(at.x, (top + bottom) * 0.5, at.y)
	for k in STONE_SIDES:
		var n := (k + 1) % STONE_SIDES
		# inner[k] sits between top corners k and k + 1.
		mesh.triangle(centre, inner[k], inner[n], colors[0], Vector3.UP)
		mesh.triangle(inner[k], rings[0][k], rings[0][n], colors[0], Vector3.UP)
		mesh.triangle(inner[k], rings[0][n], inner[n], colors[0], Vector3.UP)
		for band in 3:
			var a := rings[band]
			var b := rings[band + 1]
			var outward := (b[k] + b[n]) * 0.5 - middle
			if band == 0:
				outward += Vector3.UP * 0.6
			mesh.triangle(a[k], b[k], b[n], colors[band], outward)
			mesh.triangle(a[k], b[n], a[n], colors[band], outward)
