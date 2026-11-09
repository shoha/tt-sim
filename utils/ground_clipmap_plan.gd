class_name GroundClipmapPlan
extends RefCounted

## The geometry of the ground clipmap (card clipmap1; docs/systems/ground_clipmap.md), pure
## functions with no scene: which levels a map and a view need, which tiles a level holds, and the
## next strip to bake. GroundClipmap (scenes/terrain/) drives it; the shader reads the result
## (CLIPMAP in shaders/authored_ground.gdshaderinc).
##
## MODEL: level l is a toroidal window of WINDOW_PX square texels at D0 / 2^l texels per metre, so
## it spans extent_m(l) metres, cut into TILES x TILES tiles of TILE_PX texels on the world grid
## (tile (i, j) covers [i, i + 1) x [j, j + 1) times tile_m(l)). A tile's texels live at slot
## (i mod TILES, j mod TILES); moving the window only rebakes the tiles that enter it. The
## coarsest level that spans the whole map is static (its block never moves); finer levels follow
## the view's focus. `valid` is the rectangle of tiles baked (a Rect2i in tile units, empty while
## nothing is), always a sub-rectangle of the level's target block, and grows one strip at a time:
## a column of tiles as tall as the block, or a row as wide, so it stays a rectangle.

enum Kind { COLUMN, ROW }

const CLIP_LEVELS := 5
const WINDOW_PX := 2048
const TILE_PX := 256
const TILES := 8
## Texels per metre of level 0 (a 10.24 m window).
const D0 := 200.0
## The shader's lod bias and the density margin for choosing the finest level a view needs.
const LOD_BIAS := 0.0
## Tiles of hysteresis before a following level re-centres.
const RECENTRE_TILES := 0.75


## Texels per metre of level `l`.
static func density(l: int) -> float:
	return D0 / pow(2.0, l)


## Metres spanned by one window of level `l`.
static func extent_m(l: int) -> float:
	return WINDOW_PX / density(l)


## Metres per tile of level `l`.
static func tile_m(l: int) -> float:
	return TILE_PX / density(l)


## The coarsest level for a map `map_extent_m` across: the first whose window holds the map with
## one tile to spare (it is static), else the last level (which then follows the view too).
static func top_level(map_extent_m: float) -> int:
	for l in CLIP_LEVELS:
		if extent_m(l) >= map_extent_m + tile_m(l):
			return l
	return CLIP_LEVELS - 1


## True when level `l` spans the whole map and so never moves.
static func is_static(l: int, map_extent_m: float) -> bool:
	return extent_m(l) >= map_extent_m + tile_m(l)


## The finest level a view needs: the shader floors log2(footprint x D0) + LOD_BIAS, and the
## footprint of the densest ground on screen is 1 / `px_per_m` metres. Clamped to [0, top].
static func finest_level(px_per_m: float, top: int) -> int:
	if px_per_m <= 0.0:
		return top
	var lod := log(D0 / px_per_m) / log(2.0) + LOD_BIAS
	return clampi(int(floor(maxf(lod, 0.0))), 0, top)


## The block of tiles a level should hold for a view focused at `focus` (map-frame metres).
## `current` is the block it holds now (empty to choose fresh); the block only moves when the
## focus is more than RECENTRE_TILES from its centre, so it does not flap on a tile boundary.
static func target_block(l: int, focus: Vector2, current: Rect2i) -> Rect2i:
	var ts := tile_m(l)
	var centre := Vector2i(int(floor(focus.x / ts + 0.5)), int(floor(focus.y / ts + 0.5)))
	if current.size == Vector2i(TILES, TILES):
		var held := Vector2(current.position + Vector2i(TILES / 2, TILES / 2))
		var off := (focus / ts - held).abs()
		if off.x <= RECENTRE_TILES and off.y <= RECENTRE_TILES:
			return current
	return Rect2i(centre - Vector2i(TILES / 2, TILES / 2), Vector2i(TILES, TILES))


## The fixed block of a static level: centred on the map's centre.
static func static_block(l: int, map_centre: Vector2) -> Rect2i:
	var ts := tile_m(l)
	var centre := Vector2i(int(floor(map_centre.x / ts + 0.5)), int(floor(map_centre.y / ts + 0.5)))
	return Rect2i(centre - Vector2i(TILES / 2, TILES / 2), Vector2i(TILES, TILES))


## `valid` cut to `target` (what stays correct when the block moves); empty if nothing does.
static func clip_valid(valid: Rect2i, target: Rect2i) -> Rect2i:
	var cut := valid.intersection(target)
	if cut.size.x <= 0 or cut.size.y <= 0:
		return Rect2i()
	return cut


## The next strip to bake toward `target`, or {} when `valid` is the whole block. A job is
## {kind, tile (the column or row index), span (the block's tile range along the strip),
## after (valid once it is baked)}. Columns first, then rows; the side nearer the block's centre.
static func next_job(valid: Rect2i, target: Rect2i) -> Dictionary:
	var v := clip_valid(valid, target)
	var centre := target.position + Vector2i(TILES / 2, TILES / 2)
	if v.size.x <= 0:
		return {
			"kind": Kind.COLUMN,
			"tile": centre.x,
			"span": target.position.y,
			"after": Rect2i(centre.x, target.position.y, 1, TILES),
		}
	if v.size.x < TILES:
		var left := v.position.x - 1
		var right := v.end.x
		var take_left := left >= target.position.x
		if take_left and right < target.end.x:
			take_left = absi(left - centre.x) <= absi(right - centre.x)
		var tile := left if take_left else right
		var after := Rect2i(
			v.position.x - (1 if take_left else 0), v.position.y, v.size.x + 1, v.size.y
		)
		return {"kind": Kind.COLUMN, "tile": tile, "span": target.position.y, "after": after}
	if v.size.y < TILES:
		var up := v.position.y - 1
		var down := v.end.y
		var take_up := up >= target.position.y
		if take_up and down < target.end.y:
			take_up = absi(up - centre.y) <= absi(down - centre.y)
		var tile_row := up if take_up else down
		var after_row := Rect2i(
			v.position.x, v.position.y - (1 if take_up else 0), v.size.x, v.size.y + 1
		)
		return {"kind": Kind.ROW, "tile": tile_row, "span": target.position.x, "after": after_row}
	return {}


## Where a strip lands in the window, as 1 or 2 pieces (a strip that wraps the torus splits):
## each {src: Rect2i in strip texels, dst: Vector2i in window texels}. `kind`, the strip's
## `tile` index along its short axis and `span` (its first tile along the long one).
static func blits(kind: int, tile: int, span: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var short_slot := posmod(tile, TILES) * TILE_PX
	var first := posmod(span, TILES)
	var head := mini(TILES - first, TILES)
	# Tiles first .. first + head - 1 fit before the wrap; the rest start at slot 0.
	var pieces := [[0, first, head]]
	if head < TILES:
		pieces.append([head, 0, TILES - head])
	for p: Array in pieces:
		var src_from: int = p[0] * TILE_PX
		var dst_from: int = p[1] * TILE_PX
		var run_px: int = p[2] * TILE_PX
		if kind == Kind.COLUMN:
			out.append(
				{"src": Rect2i(0, src_from, TILE_PX, run_px), "dst": Vector2i(short_slot, dst_from)}
			)
		else:
			out.append(
				{"src": Rect2i(src_from, 0, run_px, TILE_PX), "dst": Vector2i(dst_from, short_slot)}
			)
	return out


## A strip's world rectangle (position, size in metres) for level `l`: the camera frames it.
static func strip_rect(l: int, kind: int, tile: int, span: int) -> Rect2:
	var ts := tile_m(l)
	if kind == Kind.COLUMN:
		return Rect2(Vector2(tile, span) * ts, Vector2(1, TILES) * ts)
	return Rect2(Vector2(span, tile) * ts, Vector2(TILES, 1) * ts)


## `valid` (tiles) as the shader's rectangle: (min x, min z, max x, max z) in metres, cut to
## `bounds` (the map's rectangle, for a static level) when it is not empty.
static func valid_rect_m(l: int, valid: Rect2i, bounds: Rect2) -> Vector4:
	if valid.size.x <= 0 or valid.size.y <= 0:
		return Vector4(1.0e9, 1.0e9, -1.0e9, -1.0e9)
	var ts := tile_m(l)
	var r := Rect2(Vector2(valid.position) * ts, Vector2(valid.size) * ts)
	if bounds.size.x > 0.0:
		r = r.intersection(bounds)
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return Vector4(1.0e9, 1.0e9, -1.0e9, -1.0e9)
	return Vector4(r.position.x, r.position.y, r.end.x, r.end.y)
