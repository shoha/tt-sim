class_name CrossingArch
extends RefCounted

## The stone arch bridge's geometry (Crossing.Kind.ARCH, phase 4d, P4d-1), pure and
## worker-safe like CrossingGeometry, whose build_one() calls build() with the meshes to fill
## and which keeps the shared pieces (point(), deck_y(), rng_for(), the mesh builder, the
## deck's collision strip). Summary: docs/systems/crossings.md.
##
## Frame as CrossingGeometry's: u along the span from the start anchor, v across it (left of
## the start-to-end direction), y up. The walking surface is CrossingGeometry.deck_y, so the
## deck collision, the grid's deck field and the clearances treat an arch as a deck.
##
## The parts, a few big readable ones at tabletop zoom (the house style: flat-shaded facets
## with a little shade jitter, like the stepping stones; never fussy masonry). An abutment at
## each end: a block from ABUTMENT_BACK_M behind the anchor to ABUTMENT_FACE_M toward the water,
## bedded ABUTMENT_BURY_M under the lowest ground beneath it (so it reaches the bed where the
## bank drops), its cap DECK_THICK_M under the deck. Between the abutment faces the barrel: a
## segmental intrados (the underside, a parabola from the springing SPRING_DROP_M below each
## cap to the crown BARREL_THICK_M under the deck at the arch's centre, faceted BARREL_SEGMENTS
## along and BARREL_ACROSS across), spandrel walls rising from it to the deck on both sides, and
## the stone lip at deck level outside the parapets. Over PIER_MIN_SPAN_M the barrel is two
## arches on a pier PIER_W_M thick at mid-span, from the bed to the springing (the deck stays
## one deck_y curve). On top: a paved deck slab between the parapets (its own mesh, the biome's
## paving surface mapped in world metres along and across, AuthoredCrossings), and a parapet
## along each edge PARAPET_INSET_M in from the deck edge, PARAPET_W_M thick and PARAPET_H_M
## high with a coping stone on top overhanging COPING_OVERHANG_M. The parapet copings, the lip
## and the abutment caps face up, so AuthoredCrossings.moss_split gives them the palette's
## moss in damp climates as it does the stones' tops; the walls and the intrados never take it.
##
## Vertex colours shade the stone: the intrados darkest, the walls a little below the caps,
## every facet jittered SHADE_JITTER; an abutment's or the pier's foot below the water level
## (plus WET_ABOVE_M) is darkened like a stepping stone's root. Winding is clockwise seen from
## the front, as everywhere in the map's geometry. Collision is the deck strip alone
## (CrossingGeometry.deck_collision); the parapets are visual.

## Deck to intrados at an arch's crown.
const BARREL_THICK_M := 0.35
## Facets along each arch and across the barrel.
const BARREL_SEGMENTS := 16
const BARREL_ACROSS := 6
## The intrados springs this far below the abutment cap (and the pier cap).
const SPRING_DROP_M := 0.3
## The stone over the intrados is never thinner than this.
const MIN_RING_M := 0.1
## An abutment reaches this far behind the anchor into the bank and this far toward the water.
const ABUTMENT_BACK_M := 0.35
const ABUTMENT_FACE_M := 0.6
const ABUTMENT_BURY_M := 0.4
## A span over this gets a pier at mid-span, this thick along the span, its head at least
## this far over the water.
const PIER_MIN_SPAN_M := 9.0
const PIER_W_M := 0.9
const PIER_FREEBOARD_M := 0.15
## The paved slab's thickness (its end face shows over the abutment cap).
const DECK_THICK_M := 0.12
const PARAPET_H_M := 0.45
const PARAPET_W_M := 0.25
const PARAPET_INSET_M := 0.05
const COPING_H_M := 0.08
const COPING_OVERHANG_M := 0.03
## A foot is wet up to the water level plus this.
const WET_ABOVE_M := 0.12
## Shades: caps, lips and copings; walls, abutments and the pier; the intrados; wet feet.
const CAP_SHADE := 1.0
const WALL_SHADE := 0.88
const INTRADOS_SHADE := 0.58
const WET_SHADE := 0.55
const PAVING_SHADE := 1.0
const SHADE_JITTER := 0.05
const PAVING_JITTER := 0.03


## True when `crossing`'s span needs a mid-stream pier.
static func has_pier(crossing: Crossing) -> bool:
	return crossing.span_m() > PIER_MIN_SPAN_M


## Where the arch's parts stand along `crossing` (u in metres from the start anchor, heights in
## map Y): {"span", "face_a" / "face_b" (the abutments' inner faces), "cap_a" / "cap_b" (the
## abutment caps' tops), "pier" (bool), "pier_u0" / "pier_u1" / "pier_cap" (with a pier),
## "arches": [{"u0", "u1", "spring0", "spring1", "crown"} per barrel]}. The pier's cap is the
## mean springing, lifted to PIER_FREEBOARD_M over `pier_water` (the water level at mid-span,
## when the caller knows it) so the pier's head shows over the water. Pure.
static func layout(crossing: Crossing, pier_water: float = -INF) -> Dictionary:
	var span := crossing.span_m()
	var levels := crossing.levels
	var face_a := minf(ABUTMENT_FACE_M, span * 0.25)
	var face_b := span - face_a
	var cap_a := levels.x - DECK_THICK_M
	var cap_b := levels.z - DECK_THICK_M
	var spring_a := cap_a - SPRING_DROP_M
	var spring_b := cap_b - SPRING_DROP_M
	var out := {
		"span": span,
		"face_a": face_a,
		"face_b": face_b,
		"cap_a": cap_a,
		"cap_b": cap_b,
		"pier": has_pier(crossing),
		"arches": [],
	}
	var arches: Array[Dictionary] = []
	if out.pier:
		var mid := span * 0.5
		var pier_cap := maxf((spring_a + spring_b) * 0.5, pier_water + PIER_FREEBOARD_M)
		pier_cap = minf(pier_cap, CrossingGeometry.deck_y(levels, 0.5) - BARREL_THICK_M - 0.1)
		out.pier_u0 = mid - PIER_W_M * 0.5
		out.pier_u1 = mid + PIER_W_M * 0.5
		out.pier_cap = pier_cap
		arches.append(_arch(levels, span, face_a, out.pier_u0, spring_a, pier_cap))
		arches.append(_arch(levels, span, out.pier_u1, face_b, pier_cap, spring_b))
	else:
		arches.append(_arch(levels, span, face_a, face_b, spring_a, spring_b))
	out.arches = arches
	return out


## The barrel's underside at `u` along the span of a layout(), or NAN over an abutment or the
## pier. Pure.
static func intrados_at(lay: Dictionary, u: float) -> float:
	var arch := _arch_of(lay, u)
	return NAN if arch.is_empty() else _intrados(arch, u)


## Fills `stone` (the masonry: abutments, barrel, spandrels, lip, pier, parapets) and `paving`
## (the deck slab, UVs in world metres along and across the deck) for `crossing` over `doc`.
static func build(
	doc: MapDocument,
	crossing: Crossing,
	stone: CrossingGeometry._Mesh,
	paving: CrossingGeometry._Mesh
) -> void:
	var half := crossing.width_m * 0.5
	var courses := WaterGeometry.river_courses(
		doc, Rect2(crossing.start, Vector2.ZERO).expand(crossing.end).grow(half + 2.0)
	)
	var mid := CrossingGeometry.point(crossing, crossing.span_m() * 0.5, 0.0, 0.0)
	var lay := layout(crossing, WaterGeometry.level_at(doc, Vector2(mid.x, mid.z), -1, courses))
	var rng := CrossingGeometry.rng_for(doc, crossing)
	var span: float = lay.span
	var inner := half - PARAPET_INSET_M - PARAPET_W_M
	var d := crossing.direction()
	var left := Vector3(-d.y, 0.0, d.x)
	var along := Vector3(d.x, 0.0, d.y)
	var us := _columns(lay)
	for k in us.size() - 1:
		var u0 := us[k]
		var u1 := us[k + 1]
		var deck0 := _deck(crossing, u0)
		var deck1 := _deck(crossing, u1)
		var under := _under(lay, u0, u1)
		under.x = minf(under.x, deck0 - MIN_RING_M)
		under.y = minf(under.y, deck1 - MIN_RING_M)
		for side in [-1.0, 1.0]:
			var v: float = side * half
			# The spandrel wall (over an abutment or the pier, the band from its cap to the deck).
			_facet(
				stone,
				crossing,
				[
					Vector3(u0, v, under.x),
					Vector3(u1, v, under.y),
					Vector3(u1, v, deck1),
					Vector3(u0, v, deck0)
				],
				left * side,
				_shade(WALL_SHADE, rng)
			)
			# The stone lip at deck level outside the parapet.
			var v_in: float = side * inner
			_facet(
				stone,
				crossing,
				[
					Vector3(u0, v_in, deck0),
					Vector3(u1, v_in, deck1),
					Vector3(u1, v, deck1),
					Vector3(u0, v, deck0)
				],
				Vector3.UP,
				_shade(CAP_SHADE, rng)
			)
		if not _arch_of(lay, (u0 + u1) * 0.5).is_empty():
			for j in BARREL_ACROSS:
				var v0 := -half + crossing.width_m * j / BARREL_ACROSS
				var v1 := -half + crossing.width_m * (j + 1) / BARREL_ACROSS
				_facet(
					stone,
					crossing,
					[
						Vector3(u0, v0, under.x),
						Vector3(u1, v0, under.y),
						Vector3(u1, v1, under.y),
						Vector3(u0, v1, under.x)
					],
					Vector3.DOWN,
					_shade(INTRADOS_SHADE, rng)
				)
		# The paving between the parapets, mapped in metres.
		var tone := PAVING_SHADE + rng.randf_range(-PAVING_JITTER, PAVING_JITTER)
		_facet(
			paving,
			crossing,
			[
				Vector3(u0, -inner, deck0),
				Vector3(u1, -inner, deck1),
				Vector3(u1, inner, deck1),
				Vector3(u0, inner, deck0)
			],
			Vector3.UP,
			Color(tone, tone, tone),
			[Vector2(u0, -inner), Vector2(u1, -inner), Vector2(u1, inner), Vector2(u0, inner)]
		)
	_parapets(stone, crossing, us, half, left, along, rng)
	_deck_ends(stone, paving, crossing, lay, half, inner, along, rng)
	# The body over a cap is closed toward the arch, so nothing looks into it from below.
	var closers: Array = [[lay.face_a, lay.cap_a, along], [lay.face_b, lay.cap_b, -along]]
	if lay.pier:
		closers.append([lay.pier_u0, lay.pier_cap, -along])
		closers.append([lay.pier_u1, lay.pier_cap, along])
	for closer: Array in closers:
		var u: float = closer[0]
		var cap: float = closer[1]
		var y := _deck(crossing, u)
		_facet(
			stone,
			crossing,
			[
				Vector3(u, -half, cap),
				Vector3(u, half, cap),
				Vector3(u, half, y),
				Vector3(u, -half, y)
			],
			closer[2],
			_shade(WALL_SHADE, rng)
		)
	# Abutments bedded in each bank, and the pier.
	_footing(stone, doc, crossing, courses, -ABUTMENT_BACK_M, lay.face_a, half, lay.cap_a, rng)
	_footing(
		stone, doc, crossing, courses, lay.face_b, span + ABUTMENT_BACK_M, half, lay.cap_b, rng
	)
	if lay.pier:
		_footing(stone, doc, crossing, courses, lay.pier_u0, lay.pier_u1, half, lay.pier_cap, rng)


# --- layout -------------------------------------------------------------------------------


static func _arch(
	levels: Vector3, span: float, u0: float, u1: float, spring0: float, spring1: float
) -> Dictionary:
	var centre := (u0 + u1) * 0.5
	var crown := CrossingGeometry.deck_y(levels, centre / span) - BARREL_THICK_M
	crown = maxf(crown, maxf(spring0, spring1) + 0.05)
	return {"u0": u0, "u1": u1, "spring0": spring0, "spring1": spring1, "crown": crown}


## The arch of `lay` holding `u`, or {}.
static func _arch_of(lay: Dictionary, u: float) -> Dictionary:
	for arch: Dictionary in lay.arches:
		if u >= float(arch.u0) - 1e-6 and u <= float(arch.u1) + 1e-6:
			return arch
	return {}


## The intrados of one arch at `u`: a parabola from its springing line to its crown.
static func _intrados(arch: Dictionary, u: float) -> float:
	var length := maxf(float(arch.u1) - float(arch.u0), 1e-6)
	var s := clampf((u - float(arch.u0)) / length, 0.0, 1.0)
	var spring := lerpf(float(arch.spring0), float(arch.spring1), s)
	var rise := float(arch.crown) - (float(arch.spring0) + float(arch.spring1)) * 0.5
	var w := 2.0 * s - 1.0
	return spring + rise * (1.0 - w * w)


## The u of every column of the body along the span: the anchors, the abutment faces, the
## pier faces and BARREL_SEGMENTS per arch between them.
static func _columns(lay: Dictionary) -> PackedFloat64Array:
	var us := PackedFloat64Array([0.0])
	for arch: Dictionary in lay.arches:
		for k in BARREL_SEGMENTS + 1:
			_push(us, lerpf(float(arch.u0), float(arch.u1), float(k) / BARREL_SEGMENTS))
	_push(us, float(lay.span))
	return us


static func _push(us: PackedFloat64Array, u: float) -> void:
	if u > us[-1] + 1e-4:
		us.append(u)


## The body's underside at the two ends of the column pair `u0`..`u1`: the intrados within an
## arch, else the cap it stands on (an abutment's or the pier's).
static func _under(lay: Dictionary, u0: float, u1: float) -> Vector2:
	var mid := (u0 + u1) * 0.5
	var arch := _arch_of(lay, mid)
	if not arch.is_empty():
		return Vector2(_intrados(arch, u0), _intrados(arch, u1))
	if mid < float(lay.face_a):
		return Vector2.ONE * float(lay.cap_a)
	if mid > float(lay.face_b):
		return Vector2.ONE * float(lay.cap_b)
	return Vector2.ONE * float(lay.pier_cap)


static func _deck(crossing: Crossing, u: float) -> float:
	return CrossingGeometry.deck_y(crossing.levels, clampf(u / crossing.span_m(), 0.0, 1.0))


# --- parts --------------------------------------------------------------------------------


## The parapet along each edge: a wall from the deck up, a coping on top, closed at the ends.
static func _parapets(
	stone: CrossingGeometry._Mesh,
	crossing: Crossing,
	us: PackedFloat64Array,
	half: float,
	left: Vector3,
	along: Vector3,
	rng: RandomNumberGenerator
) -> void:
	var wall_h := PARAPET_H_M - COPING_H_M
	for side in [-1.0, 1.0]:
		var v_out: float = side * (half - PARAPET_INSET_M)
		var v_in: float = v_out - side * PARAPET_W_M
		var c_out: float = v_out + side * COPING_OVERHANG_M
		var c_in: float = v_in - side * COPING_OVERHANG_M
		for k in us.size() - 1:
			var u0 := us[k]
			var u1 := us[k + 1]
			var y0 := _deck(crossing, u0)
			var y1 := _deck(crossing, u1)
			var wall := _shade(WALL_SHADE, rng)
			var coping := _shade(CAP_SHADE, rng)
			for face in [[v_out, left * side], [v_in, -left * side]]:
				var v: float = face[0]
				_facet(
					stone,
					crossing,
					[
						Vector3(u0, v, y0),
						Vector3(u1, v, y1),
						Vector3(u1, v, y1 + wall_h),
						Vector3(u0, v, y0 + wall_h)
					],
					face[1],
					wall
				)
			for face in [[c_out, left * side], [c_in, -left * side]]:
				var v: float = face[0]
				_facet(
					stone,
					crossing,
					[
						Vector3(u0, v, y0 + wall_h),
						Vector3(u1, v, y1 + wall_h),
						Vector3(u1, v, y1 + PARAPET_H_M),
						Vector3(u0, v, y0 + PARAPET_H_M)
					],
					face[1],
					coping
				)
			_facet(
				stone,
				crossing,
				[
					Vector3(u0, c_in, y0 + PARAPET_H_M),
					Vector3(u1, c_in, y1 + PARAPET_H_M),
					Vector3(u1, c_out, y1 + PARAPET_H_M),
					Vector3(u0, c_out, y0 + PARAPET_H_M)
				],
				Vector3.UP,
				coping
			)
		# The ends, facing off the deck.
		for end in [[0.0, -along], [us[-1], along]]:
			var u: float = end[0]
			var y := _deck(crossing, u)
			_facet(
				stone,
				crossing,
				[
					Vector3(u, v_in, y),
					Vector3(u, v_out, y),
					Vector3(u, v_out, y + wall_h),
					Vector3(u, v_in, y + wall_h)
				],
				end[1],
				_shade(WALL_SHADE, rng)
			)
			_facet(
				stone,
				crossing,
				[
					Vector3(u, c_in, y + wall_h),
					Vector3(u, c_out, y + wall_h),
					Vector3(u, c_out, y + PARAPET_H_M),
					Vector3(u, c_in, y + PARAPET_H_M)
				],
				end[1],
				_shade(CAP_SHADE, rng)
			)


## The deck's end faces over the abutment caps: the slab's in paving, the lips' in stone.
static func _deck_ends(
	stone: CrossingGeometry._Mesh,
	paving: CrossingGeometry._Mesh,
	crossing: Crossing,
	lay: Dictionary,
	half: float,
	inner: float,
	along: Vector3,
	rng: RandomNumberGenerator
) -> void:
	for end in [[0.0, float(lay.cap_a), -along], [float(lay.span), float(lay.cap_b), along]]:
		var u: float = end[0]
		var cap: float = end[1]
		var y := _deck(crossing, u)
		var tone := PAVING_SHADE + rng.randf_range(-PAVING_JITTER, PAVING_JITTER)
		_facet(
			paving,
			crossing,
			[
				Vector3(u, -inner, cap),
				Vector3(u, inner, cap),
				Vector3(u, inner, y),
				Vector3(u, -inner, y)
			],
			end[2],
			Color(tone, tone, tone),
			[Vector2(-inner, cap), Vector2(inner, cap), Vector2(inner, y), Vector2(-inner, y)]
		)
		for side in [-1.0, 1.0]:
			var v0: float = side * inner
			var v1: float = side * half
			_facet(
				stone,
				crossing,
				[Vector3(u, v0, cap), Vector3(u, v1, cap), Vector3(u, v1, y), Vector3(u, v0, y)],
				end[2],
				_shade(WALL_SHADE, rng)
			)


## A footing block (an abutment or the pier) from `u0` to `u1` along the span and the deck's
## full width, its top at `top`, bedded ABUTMENT_BURY_M under the lowest ground beneath it;
## the part below the water level there (plus WET_ABOVE_M) in the wet shade.
static func _footing(
	stone: CrossingGeometry._Mesh,
	doc: MapDocument,
	crossing: Crossing,
	courses: Dictionary,
	u0: float,
	u1: float,
	half: float,
	top: float,
	rng: RandomNumberGenerator
) -> void:
	var lowest := INF
	var water := -INF
	for u in [u0, (u0 + u1) * 0.5, u1]:
		for v in [-half, 0.0, half]:
			var p := CrossingGeometry.point(crossing, u, v, 0.0)
			var xz := Vector2(p.x, p.z)
			lowest = minf(lowest, WaterGeometry.ground_at(doc, xz))
			water = maxf(water, WaterGeometry.level_at(doc, xz, -1, courses))
	var bottom := minf(lowest - ABUTMENT_BURY_M, top - 0.1)
	var wet := water + WET_ABOVE_M
	if wet <= bottom + 0.02:
		_block(stone, crossing, u0, u1, half, bottom, top, WALL_SHADE, rng)
	elif wet >= top - 0.02:
		_block(stone, crossing, u0, u1, half, bottom, top, WET_SHADE, rng)
	else:
		_block(stone, crossing, u0, u1, half, bottom, wet, WET_SHADE, rng)
		_block(stone, crossing, u0, u1, half, wet, top, WALL_SHADE, rng)


## A block in the crossing's frame: four sides and a top (the bottom is buried), each facet
## with its own shade.
static func _block(
	stone: CrossingGeometry._Mesh,
	crossing: Crossing,
	u0: float,
	u1: float,
	half: float,
	y0: float,
	y1: float,
	shade: float,
	rng: RandomNumberGenerator
) -> void:
	var d := crossing.direction()
	var left := Vector3(-d.y, 0.0, d.x)
	var along := Vector3(d.x, 0.0, d.y)
	_facet(
		stone,
		crossing,
		[
			Vector3(u0, -half, y0),
			Vector3(u0, half, y0),
			Vector3(u0, half, y1),
			Vector3(u0, -half, y1)
		],
		-along,
		_shade(shade, rng)
	)
	_facet(
		stone,
		crossing,
		[
			Vector3(u1, -half, y0),
			Vector3(u1, half, y0),
			Vector3(u1, half, y1),
			Vector3(u1, -half, y1)
		],
		along,
		_shade(shade, rng)
	)
	for side in [-1.0, 1.0]:
		var v: float = side * half
		_facet(
			stone,
			crossing,
			[Vector3(u0, v, y0), Vector3(u1, v, y0), Vector3(u1, v, y1), Vector3(u0, v, y1)],
			left * side,
			_shade(shade, rng)
		)
	_facet(
		stone,
		crossing,
		[
			Vector3(u0, -half, y1),
			Vector3(u1, -half, y1),
			Vector3(u1, half, y1),
			Vector3(u0, half, y1)
		],
		Vector3.UP,
		_shade(CAP_SHADE if shade == WALL_SHADE else shade, rng)
	)


## One flat facet from four corners in the crossing's frame (u, v, y), facing the side of
## `outward`; `uv` per corner, or none (triplanar stone).
static func _facet(
	mesh: CrossingGeometry._Mesh,
	crossing: Crossing,
	local: Array,
	outward: Vector3,
	color: Color,
	uv: Array = []
) -> void:
	var p: Array[Vector3] = []
	for l: Vector3 in local:
		p.append(CrossingGeometry.point(crossing, l.x, l.y, l.z))
	var normal := (p[1] - p[0]).cross(p[2] - p[0])
	if normal.length_squared() < 1e-12:
		normal = (p[2] - p[0]).cross(p[3] - p[0])
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	if normal.dot(outward) < 0.0:
		normal = -normal
	var uvs: Array[Vector2] = []
	if uv.is_empty():
		uvs.assign([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
	else:
		uvs.assign(uv)
	mesh.quad(p, uvs, normal, color)


static func _shade(base: float, rng: RandomNumberGenerator) -> Color:
	var s := base + rng.randf_range(-SHADE_JITTER, SHADE_JITTER)
	return Color(s, s, s)
