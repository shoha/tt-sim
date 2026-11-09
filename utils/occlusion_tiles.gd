class_name OcclusionTiles
extends RefCounted

## Screen tiles for the occlusion fade (topic perfaudit, card occfade).
##
## The fade (occlusion_fade_include.gdshaderinc) used to test every token in every tree and
## map fragment: 1.3 ms of GPU time with 10 tokens and 4-5 ms with 32, covered or not. Here the
## tokens are binned into a grid of screen tiles for one camera, as Forward+ bins its lights: a
## tile lists every token whose fade zone touches it, so a fragment tests only its own tile's
## tokens (usually none) with the unchanged per-token test.
##
## A token's zone is the circle (or, for an avatar figure, the upright ellipse) the shader tests
## in the plane of the token's view depth. That plane is flat, so the zone projects to an exact
## ellipse on screen for an orthographic or a perspective camera alike, and the tiles under its
## bounding rectangle (padded by a margin) are a conservative superset of the tiles the shader
## will read for a faded fragment.
##
## Everything lives in one RGBAF texture, TEXTURE_WIDTH texels a row, read by texel index:
## - texels 0 to FALLBACK_TOKENS - 1: the plain loop's tokens (world centre, fade radius), read
##   by passes from any other view (the sun's shadow pass), as before the tiles;
## - from HEADER_BASE, one header per tile, row by row: (first list texel, token count, 0, 0);
## - then the lists: each entry is a copy of its token's texel, so the shader needs one fetch
##   per token.
## Pure functions only; OcclusionFadeManager owns the texture and the camera.

## Texels a row (OCCLUSION_TEXTURE_WIDTH in the shader).
const TEXTURE_WIDTH := 256
## The tile grid over the viewport, whatever its aspect: 60 px tiles at 1920x1080.
const TILES := Vector2i(32, 18)
## Tokens the plain loop reads, the old cap: other views (the shadow pass) keep it.
const FALLBACK_TOKENS := 32
## Texel index of the first tile header.
const HEADER_BASE := FALLBACK_TOKENS
## Padding round a zone's rectangle, in pixels: float noise and sub-pixel camera jitter.
const MARGIN_PX := 2.0
## Rows the texture may grow to (TEXTURE_WIDTH * MAX_ROWS texels, 1 MB). A tile list past it is
## cut short; at 4 tiles a token that is 16000 tokens on screen.
const MAX_ROWS := 256
## An avatar figure's zone half-width over its half-height (FIGURE_WIDTH in the shader).
const FIGURE_WIDTH := 0.6
## The rectangle of a token that can fade nothing in this view.
const NO_ZONE := Rect2(-2.0, -2.0, 0.0, 0.0)
## The tile range of a token that touches no tile.
const NO_TILES := Vector4i(-1, -1, -1, -1)


## The screen rectangle, in viewport UV (x right, y down, 0 to 1 across the viewport), of the
## fade zone of `entry` (world centre xyz, fade radius w; a negative radius is an avatar figure's
## ellipse) seen through `view` (the camera's inverse transform) and `projection`. NO_ZONE when
## the entry has no radius or sits at or behind a perspective camera, where no fragment in front
## of it is drawn.
static func zone_rect(entry: Vector4, view: Transform3D, projection: Projection) -> Rect2:
	var radius := absf(entry.w)
	if radius <= 0.0:
		return NO_ZONE
	var centre := view * Vector3(entry.x, entry.y, entry.z)
	var clip := projection * Vector4(centre.x, centre.y, centre.z, 1.0)
	if clip.w <= 0.000001:
		return NO_ZONE
	var half := Vector2(radius * FIGURE_WIDTH, radius) if entry.w < 0.0 else Vector2(radius, radius)
	# At a fixed view depth clip.w is constant, so the projection is affine across the plane.
	var half_ndc := (
		Vector2(
			absf(projection.x.x) * half.x + absf(projection.y.x) * half.y,
			absf(projection.x.y) * half.x + absf(projection.y.y) * half.y
		)
		/ clip.w
	)
	var centre_uv := Vector2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5)
	return Rect2(centre_uv - half_ndc * 0.5, half_ndc)


## The tiles (x0, y0, x1, y1, inclusive) under `rect` padded by `margin` (viewport UV), or
## NO_TILES when it lies off the viewport.
static func tile_range(rect: Rect2, tiles: Vector2i, margin: Vector2) -> Vector4i:
	var lo := (rect.position - margin).clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	var hi := (rect.end + margin).clamp(Vector2(-1.0, -1.0), Vector2(2.0, 2.0))
	if hi.x < 0.0 or hi.y < 0.0 or lo.x >= 1.0 or lo.y >= 1.0:
		return NO_TILES
	return Vector4i(
		clampi(floori(lo.x * tiles.x), 0, tiles.x - 1),
		clampi(floori(lo.y * tiles.y), 0, tiles.y - 1),
		clampi(floori(hi.x * tiles.x), 0, tiles.x - 1),
		clampi(floori(hi.y * tiles.y), 0, tiles.y - 1)
	)


## The tile a fragment at `frag_coord` (pixels, origin top left) of a `viewport_size` viewport
## reads, as the shader computes it.
static func tile_of(frag_coord: Vector2, viewport_size: Vector2, tiles: Vector2i) -> Vector2i:
	var t := frag_coord / viewport_size * Vector2(tiles)
	return Vector2i(clampi(int(t.x), 0, tiles.x - 1), clampi(int(t.y), 0, tiles.y - 1))


## Bins `entries` into the tiles of one view. Returns [starts, items]: tile t (row by row) lists
## items[starts[t]] to items[starts[t + 1] - 1], indices into `entries` in their order.
static func bin(
	entries: Array[Vector4],
	view: Transform3D,
	projection: Projection,
	tiles: Vector2i,
	margin: Vector2
) -> Array[PackedInt32Array]:
	var tile_count := tiles.x * tiles.y
	var starts := PackedInt32Array()
	starts.resize(tile_count + 1)
	starts.fill(0)
	var owners := PackedInt32Array()
	var ranges: Array[Vector4i] = []
	for i in entries.size():
		var r := tile_range(zone_rect(entries[i], view, projection), tiles, margin)
		if r.x < 0:
			continue
		owners.append(i)
		ranges.append(r)
		for ty in range(r.y, r.w + 1):
			for tx in range(r.x, r.z + 1):
				starts[ty * tiles.x + tx + 1] += 1
	for t in tile_count:
		starts[t + 1] += starts[t]
	var items := PackedInt32Array()
	items.resize(starts[tile_count])
	var fill := starts.duplicate()
	for k in owners.size():
		var r := ranges[k]
		for ty in range(r.y, r.w + 1):
			for tx in range(r.x, r.z + 1):
				var t := ty * tiles.x + tx
				items[fill[t]] = owners[k]
				fill[t] += 1
	return [starts, items]


## The plain loop's tokens: the entries whose zone is on screen (some tile lists them) first,
## then the rest, each in their order, at most FALLBACK_TOKENS.
static func fallback_entries(
	entries: Array[Vector4], bins: Array[PackedInt32Array]
) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var on_screen := PackedByteArray()
	on_screen.resize(entries.size())
	on_screen.fill(0)
	for i in bins[1]:
		on_screen[i] = 1
	for pass_flag in [1, 0]:
		for i in entries.size():
			if out.size() >= FALLBACK_TOKENS:
				return out
			if on_screen[i] == pass_flag:
				out.append(entries[i])
	return out


## Packs the plain loop's tokens, the tile headers and the tile lists of `bins` into one RGBAF
## image TEXTURE_WIDTH texels wide (see the class header). Its height is a power of two of at
## least `min_rows`, so a texture keeps its size while the lists change a little.
static func build_image(
	entries: Array[Vector4], bins: Array[PackedInt32Array], tiles: Vector2i, min_rows: int = 4
) -> Image:
	var starts := bins[0]
	var items := bins[1]
	var tile_count := tiles.x * tiles.y
	var list_base := HEADER_BASE + tile_count
	var rows := maxi(min_rows, 1)
	while rows * TEXTURE_WIDTH < list_base + items.size() and rows < MAX_ROWS:
		rows *= 2
	var capacity := rows * TEXTURE_WIDTH - list_base
	var texels := PackedVector4Array()
	texels.resize(rows * TEXTURE_WIDTH)
	texels.fill(Vector4.ZERO)
	var fallback := fallback_entries(entries, bins)
	for i in fallback.size():
		texels[i] = fallback[i]
	for t in tile_count:
		var first := mini(starts[t], capacity)
		var end := mini(starts[t + 1], capacity)
		texels[HEADER_BASE + t] = Vector4(list_base + first, end - first, 0.0, 0.0)
	for k in mini(items.size(), capacity):
		texels[list_base + k] = entries[items[k]]
	return Image.create_from_data(
		TEXTURE_WIDTH, rows, false, Image.FORMAT_RGBAF, texels.to_byte_array()
	)


## The plain loop's token count for `entries` (occlusion_token_count): 0 means no tokens.
static func fallback_count(entries: Array[Vector4]) -> int:
	return mini(entries.size(), FALLBACK_TOKENS)
