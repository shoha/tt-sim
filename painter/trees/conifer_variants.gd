class_name PainterConiferVariants
extends RefCounted
## The painted conifers' needle colours, one family per tree (docs/systems/painter.md "Trees",
## painter-look-taiga). Pure static functions, no scene tree.
##
## The model. A conifer species has ONE evergreen style row (its needles), so every spruce of a
## level drew in the same teal and a taiga read as one colour. The tone bake now paints COUNT rows
## for the evergreen role of a conifer: row 0 is the species' own, rows 1.. are its variants, each
## the same row moved by SHIFTS (hue, lightness and chroma, and how far the lit step leans toward
## the mood's light hue: a warm tip). The pack gives every conifer one of the variants (`assign`):
## its seed picks, and a variant a nearer tree already holds costs more, so near neighbours do not
## wear the same needles. The shaders are untouched: the row map's evergreen column names the row,
## and a stroke still takes its own value and hue spread from the row's four variants.

## One shift per variant: x hue (degrees), y lightness, z chroma, w extra lit pull (0..1).
## Row 0 is the species' own colour, a deep teal; the others stay inside a painterly range, a
## blue-green, a fresh yellow-green, a warm deep green and a teal that turns gold at its tips.
const SHIFTS: Array[Vector4] = [
	Vector4(0.0, 0.0, 0.0, 0.0),
	Vector4(8.0, 0.04, 0.01, 0.0),
	Vector4(-28.0, 0.07, 0.04, 0.2),
	Vector4(-18.0, 0.01, 0.03, 0.0),
	Vector4(-8.0, 0.05, 0.02, 0.6),
]
## Two conifers nearer than this (metres) hold different variants when a free one exists.
const NEAR_M := 9.0


## How many needle rows a conifer paints (its own and its variants).
static func count() -> int:
	return SHIFTS.size()


## The needle colour `lch` (lightness, chroma, hue) of variant `v`, moved by its shift (pure). Each
## move takes `strength` of its size (0..1), so a dark or quiet mood narrows the family.
static func shifted(lch: Vector3, v: int, strength: float) -> Vector3:
	var s: Vector4 = SHIFTS[clampi(v, 0, SHIFTS.size() - 1)]
	var k := clampf(strength, 0.0, 1.0)
	return Vector3(
		clampf(lch.x + s.y * k, 0.02, 0.985),
		maxf(lch.y + s.z * k, 0.0),
		fposmod(lch.z + s.x * k, 360.0)
	)


## The extra lit pull of variant `v` (a warm tip), taken by `strength`.
static func lit_pull(v: int, strength: float) -> float:
	return SHIFTS[clampi(v, 0, SHIFTS.size() - 1)].w * clampf(strength, 0.0, 1.0)


## key (Vector3i) -> variant for every conifer of `trees` (key -> position Vector3), pure in the
## set. Trees go in key order; each takes the variant least held by the trees already placed within
## NEAR_M (a nearer holder weighs more), the seed's own variant first on a tie.
static func assign(trees: Dictionary) -> Dictionary:
	var keys: Array = trees.keys()
	keys.sort_custom(_key_before)
	var grid := {}
	var out := {}
	for key: Vector3i in keys:
		var p: Vector3 = trees[key]
		var gc := Vector2i(floori(p.x / NEAR_M), floori(p.z / NEAR_M))
		# What each variant costs here: the nearer a tree holding it, the more.
		var held := PackedFloat32Array()
		held.resize(count())
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				for q: Array in grid.get(gc + Vector2i(dx, dz), []):
					var d := (q[0] as Vector3).distance_to(p)
					if d < NEAR_M:
						held[int(q[1])] += (NEAR_M - d) * (NEAR_M - d)
		var v := _seed_variant(key)
		var best := v
		for i in count():
			var c := (v + i) % count()
			if held[c] < held[best]:
				best = c
		out[key] = best
		if not grid.has(gc):
			grid[gc] = []
		(grid[gc] as Array).append([p, best])
	return out


static func _seed_variant(key: Vector3i) -> int:
	return PainterTreeSpecies.seed_of(key) % count()


static func _key_before(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.z != b.z:
		return a.z < b.z
	return a.y < b.y
