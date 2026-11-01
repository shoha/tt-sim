class_name StructureDressingProps
extends RefCounted

## The painted props a building's yard is planted with (StructureDressing): shrubs, flowering
## shrubs, boulders, grass tufts, terracotta planters by the door, a woodpile against a wall and
## the stepping stones of a cottage path. Each is a few bold shapes from StructureDressingShapes in
## the palette below, drawn into the "props" soup at a point of the yard; every size, offset and
## tone is drawn from the building's Rng, in the same order on every peer. Pure and safe on any
## thread.

const FOLIAGE := [
	Color(0.31, 0.6, 0.22),
	Color(0.42, 0.68, 0.24),
	Color(0.24, 0.55, 0.34),
	Color(0.58, 0.7, 0.26),
]
const BLOOMS := [
	Color(0.96, 0.52, 0.62),
	Color(0.99, 0.84, 0.35),
	Color(0.78, 0.6, 0.95),
	Color(0.98, 0.95, 0.88),
	Color(0.98, 0.58, 0.32),
]
const ROCK := Color(0.62, 0.58, 0.52)
const BARK := Color(0.46, 0.31, 0.18)
const LOG_END := Color(0.82, 0.64, 0.38)
const TERRACOTTA := Color(0.78, 0.42, 0.27)
const STONE_PALE := Color(0.76, 0.71, 0.63)


## Pale stones out of the door along the cottage path's sway (`sway` knots, `sway_amp` metres).
static func stepping_stones(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	at: Vector2,
	out: Vector2,
	side: Vector2,
	length: float,
	sway: PackedFloat32Array,
	sway_amp: float,
	rng: StructureDressingShapes.Rng
) -> void:
	var count := clampi(roundi(length / 0.62), 3, 7)
	for i in count:
		var u := float(i) / maxf(1.0, count - 1.0)
		var knot := u * 2.0
		var k0 := mini(int(knot), 1)
		var bend := lerpf(sway[k0], sway[k0 + 1], smoothstep(0.0, 1.0, knot - float(k0)))
		var s := 0.55 + (length - 0.4) * u
		var centre := at + out * s + side * (bend * sway_amp * u + rng.between(-0.1, 0.1))
		var tone := rng.between(0.9, 1.08)
		var color := Color(STONE_PALE.r * tone, STONE_PALE.g * tone, STONE_PALE.b * tone)
		StructureDressingShapes.disc(props, doc, centre, rng.between(0.2, 0.28), 0.05, color, rng)


## Two or three green blobs.
static func shrub(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	at: Vector2,
	rng: StructureDressingShapes.Rng
) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	var count := 2 + rng.pick(2)
	for i in count:
		var offset := Vector2(rng.between(-0.22, 0.22), rng.between(-0.22, 0.22))
		var radius := rng.between(0.38, 0.62)
		StructureDressingShapes.blob(
			props,
			doc,
			at + offset,
			radius,
			radius * rng.between(0.7, 0.95),
			StructureDressingShapes.vary(green, rng),
			rng
		)


## Two small green blobs dotted with blooms of two colours.
static func flower_shrub(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	at: Vector2,
	rng: StructureDressingShapes.Rng
) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	var bloom: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var second: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var count := 2
	for i in count:
		var offset := Vector2(rng.between(-0.25, 0.25), rng.between(-0.25, 0.25))
		var radius := rng.between(0.26, 0.4)
		var centre := at + offset
		StructureDressingShapes.blob(
			props, doc, centre, radius, radius * 0.8, StructureDressingShapes.vary(green, rng), rng
		)
		var base := StructureDressingShapes.ground_height(doc, centre)
		var height := radius * 0.8
		for d in 4:
			var angle := rng.between(0.0, TAU)
			var up := rng.between(0.35, 0.9)
			var flat := sqrt(maxf(0.0, 1.0 - up * up))
			var dot := Vector3(
				centre.x + cos(angle) * flat * radius * 1.02,
				base + height * 0.55 + up * height * 1.02,
				centre.y + sin(angle) * flat * radius * 1.02
			)
			StructureDressingShapes.soup_dot(props, dot, 0.07, bloom if d % 2 == 0 else second)


## One or two low grey boulders.
static func rock(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	at: Vector2,
	rng: StructureDressingShapes.Rng
) -> void:
	var count := 1 + rng.pick(2)
	for i in count:
		var radius := rng.between(0.22, 0.42)
		var offset := Vector2(rng.between(-0.35, 0.35), rng.between(-0.35, 0.35)) * float(i)
		var tone := rng.between(0.88, 1.1)
		var color := Color(ROCK.r * tone, ROCK.g * tone * 0.98, ROCK.b * tone * 0.94)
		StructureDressingShapes.blob(
			props, doc, at + offset, radius, radius * rng.between(0.5, 0.7), color, rng, 0.3
		)


## A handful of crossed grass blades, light at the tip.
static func tufts(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	at: Vector2,
	rng: StructureDressingShapes.Rng
) -> void:
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())].lerp(Color(0.72, 0.78, 0.3), 0.35)
	var clumps := 2 + rng.pick(2)
	for c in clumps:
		var base := at + Vector2(rng.between(-0.35, 0.35), rng.between(-0.35, 0.35))
		var y := StructureDressingShapes.ground_height(doc, base) - 0.02
		for b in 5:
			var angle := rng.between(0.0, TAU)
			var lean := Vector2(cos(angle), sin(angle)) * rng.between(0.05, 0.2)
			var half := Vector2(-sin(angle), cos(angle)) * 0.045
			var height := rng.between(0.35, 0.65)
			var left := StructureDressingShapes.soup_vertex(
				props, Vector3(base.x - half.x, y, base.y - half.y), green.darkened(0.25)
			)
			var right := StructureDressingShapes.soup_vertex(
				props, Vector3(base.x + half.x, y, base.y + half.y), green.darkened(0.25)
			)
			var tip := StructureDressingShapes.soup_vertex(
				props, Vector3(base.x + lean.x, y + height, base.y + lean.y), green.lightened(0.18)
			)
			props.tri(left, right, tip)


## Terracotta planters either side of the door with a green dome and blooms.
static func planters(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	door: Dictionary,
	rng: StructureDressingShapes.Rng
) -> void:
	var out: Vector2 = door.out
	var side := out.orthogonal()
	var bloom: Color = BLOOMS[rng.pick(BLOOMS.size())]
	var green: Color = FOLIAGE[rng.pick(FOLIAGE.size())]
	for sign_value in [-1.0, 1.0]:
		if rng.chance(0.12):
			continue
		var at: Vector2 = door.at + out * 0.38 + side * 1.0 * float(sign_value)
		StructureDressingShapes.slab(props, doc, at, out, 0.36, 0.36, 0.34, TERRACOTTA, rng)
		var top := StructureDressingShapes.ground_height(doc, at) + 0.3
		StructureDressingShapes.blob_at(
			props,
			Vector3(at.x, top + 0.08, at.y),
			0.26,
			0.2,
			StructureDressingShapes.vary(green, rng),
			rng
		)
		for d in 3:
			var jitter := Vector3(rng.between(-0.15, 0.15), 0.0, rng.between(-0.15, 0.15))
			StructureDressingShapes.soup_dot(
				props, Vector3(at.x, top + 0.26, at.y) + jitter, 0.06, bloom
			)


## A stack of logs against a wall: a dark block with pale log ends on its face.
static func woodpile(
	props: StructureDressingShapes.Soup,
	doc: MapDocument,
	frame: Dictionary,
	rng: StructureDressingShapes.Rng
) -> void:
	var n: Vector2 = frame.n
	var t: Vector2 = frame.t
	var at: Vector2 = frame.p + n * 0.38
	StructureDressingShapes.slab(props, doc, at, n, 1.0, 0.4, 0.62, BARK, rng)
	var base := StructureDressingShapes.ground_height(doc, at)
	var face := at + n * 0.2 + n * 0.005
	for row in 2:
		for col in 3:
			var centre := face + t * (float(col) - 1.0) * 0.28
			var y := base + 0.15 + float(row) * 0.3
			StructureDressingShapes.end_disc(
				props,
				Vector3(centre.x, y, centre.y),
				Vector3(n.x, 0.0, n.y),
				t,
				0.115,
				LOG_END,
				rng
			)
