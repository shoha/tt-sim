extends GutTest

## Tests for OcclusionTiles, the screen-tile binning of the occlusion fade (topic perfaudit,
## card occfade). The shader tests only the tokens its fragment's tile lists, so the lists must
## be conservative: every fragment the per-token test would fade must read a tile that lists
## that token. The per-token test is mirrored here as the shader runs it (EyeCanopy.token_plane_xy
## for the perspective scale), and a fragment's pixel is its view position projected the way
## the GPU does (x right, y down from the top left); the real-pixel parity of the shader is
## checked by the occfade render job, not here.

const SIZE := Vector2(1920.0, 1080.0)
const TILES := OcclusionTiles.TILES


func _view(eye: Vector3, target: Vector3) -> Transform3D:
	return Transform3D(Basis(), eye).looking_at(target, Vector3.UP).affine_inverse()


func _ortho() -> Projection:
	# The play camera: orthographic, its near plane pulled behind it (CameraController).
	return Projection.create_orthogonal_aspect(24.0, SIZE.aspect(), -61.0, 1000.0, false)


func _perspective() -> Projection:
	return Projection.create_perspective(60.0, SIZE.aspect(), 0.05, 1000.0, false)


func _margin() -> Vector2:
	return Vector2.ONE * OcclusionTiles.MARGIN_PX / SIZE


## The pixel a view-space point lands on.
func _pixel(view_point: Vector3, projection: Projection) -> Vector2:
	var clip := projection * Vector4(view_point.x, view_point.y, view_point.z, 1.0)
	var ndc := Vector2(clip.x, clip.y) / clip.w
	return Vector2((ndc.x * 0.5 + 0.5) * SIZE.x, (0.5 - ndc.y * 0.5) * SIZE.y)


## The shader's per-token test: does `entry` fade a fragment at view-space `fragment`?
func _fades(entry: Vector4, fragment: Vector3, view: Transform3D, perspective: bool) -> bool:
	var radius := absf(entry.w)
	if radius <= 0.0:
		return false
	var token := view * Vector3(entry.x, entry.y, entry.z)
	if fragment.z <= token.z:
		return false
	var offset := EyeCanopy.token_plane_xy(fragment, token, perspective) - Vector2(token.x, token.y)
	if entry.w < 0.0:
		return (offset / Vector2(radius * OcclusionTiles.FIGURE_WIDTH, radius)).length() < 1.0
	return offset.length() < radius


func _random_entries(rng: RandomNumberGenerator, count: int, spread: float) -> Array[Vector4]:
	var entries: Array[Vector4] = []
	for i in count:
		var radius := rng.randf_range(0.3, 1.6)
		if i % 3 == 0:
			radius = -rng.randf_range(0.8, 1.8)
		entries.append(
			Vector4(
				rng.randf_range(-spread, spread),
				rng.randf_range(0.0, 1.5),
				rng.randf_range(-spread, spread),
				radius
			)
		)
	return entries


func _listed(bins: Array[PackedInt32Array], tile: Vector2i, index: int) -> bool:
	var t := tile.y * TILES.x + tile.x
	for k in range(bins[0][t], bins[0][t + 1]):
		if bins[1][k] == index:
			return true
	return false


## Samples fragments the per-token test fades and checks each one's tile lists the token.
func _assert_conservative(view: Transform3D, projection: Projection, perspective: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var entries := _random_entries(rng, 60, 9.0)
	var bins := OcclusionTiles.bin(entries, view, projection, TILES, _margin())
	var tested := 0
	var missed := 0
	for i in entries.size():
		var entry := entries[i]
		var token := view * Vector3(entry.x, entry.y, entry.z)
		var radius := absf(entry.w)
		var half := Vector2(radius, radius)
		if entry.w < 0.0:
			half.x *= OcclusionTiles.FIGURE_WIDTH
		for s in 40:
			# A point of the zone, in the token's plane (near its edge half the time).
			var angle := rng.randf() * TAU
			var reach := 0.999 if s % 2 == 0 else rng.randf()
			var zone_point := Vector3(
				token.x + cos(angle) * half.x * reach, token.y + sin(angle) * half.y * reach, token.z
			)
			# A fragment in front of the token on that point's view ray.
			var fragment := zone_point + Vector3(0.0, 0.0, rng.randf_range(0.01, 20.0))
			if perspective:
				fragment = zone_point * rng.randf_range(0.05, 0.999)
				if zone_point.z >= -0.06:
					continue
			if not _fades(entry, fragment, view, perspective):
				continue
			var pixel := _pixel(fragment, projection)
			if pixel.x < 0.0 or pixel.y < 0.0 or pixel.x >= SIZE.x or pixel.y >= SIZE.y:
				continue
			tested += 1
			if not _listed(bins, OcclusionTiles.tile_of(pixel, SIZE, TILES), i):
				missed += 1
	assert_gt(tested, 500, "enough faded fragments on screen to mean something")
	assert_eq(missed, 0, "every faded fragment's tile lists its token")


func test_tiles_are_conservative_for_the_orthographic_play_camera() -> void:
	_assert_conservative(_view(Vector3(14.0, 22.0, 14.0), Vector3.ZERO), _ortho(), false)


func test_tiles_are_conservative_for_a_perspective_eye() -> void:
	_assert_conservative(_view(Vector3(0.0, 1.7, 12.0), Vector3(0.0, 0.8, 0.0)), _perspective(), true)


func test_each_tile_lists_exactly_the_tokens_whose_rectangle_touches_it() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var entries := _random_entries(rng, 80, 12.0)
	var view := _view(Vector3(14.0, 22.0, 14.0), Vector3.ZERO)
	var bins := OcclusionTiles.bin(entries, view, _ortho(), TILES, _margin())
	var wrong := 0
	for ty in TILES.y:
		for tx in TILES.x:
			var t := ty * TILES.x + tx
			var listed := Array(bins[1].slice(bins[0][t], bins[0][t + 1]))
			var expected := []
			for i in entries.size():
				var r := OcclusionTiles.tile_range(
					OcclusionTiles.zone_rect(entries[i], view, _ortho()), TILES, _margin()
				)
				if r.x >= 0 and tx >= r.x and tx <= r.z and ty >= r.y and ty <= r.w:
					expected.append(i)
			if listed != expected:
				wrong += 1
	assert_eq(wrong, 0, "lists match the rectangles, in entry order, no duplicates")


func test_tokens_off_screen_behind_the_eye_or_without_radius_touch_no_tile() -> void:
	var view := _view(Vector3(0.0, 1.7, 12.0), Vector3(0.0, 0.8, 0.0))
	var behind := Vector4(0.0, 1.0, 20.0, 1.0)
	var off_screen := Vector4(400.0, 0.0, 0.0, 1.0)
	var no_radius := Vector4(0.0, 1.0, 0.0, 0.0)
	for entry in [behind, off_screen, no_radius]:
		var r := OcclusionTiles.tile_range(
			OcclusionTiles.zone_rect(entry, view, _perspective()), TILES, _margin()
		)
		assert_eq(r, OcclusionTiles.NO_TILES, "%s touches no tile" % entry)


func test_more_than_32_tokens_all_reach_their_tiles() -> void:
	var entries: Array[Vector4] = []
	for i in 100:
		entries.append(Vector4((i % 10) * 1.5 - 7.0, 0.5, (i / 10) * 1.5 - 7.0, 0.75))
	var bins := OcclusionTiles.bin(
		entries, _view(Vector3(14.0, 22.0, 14.0), Vector3.ZERO), _ortho(), TILES, _margin()
	)
	var seen := {}
	for i in bins[1]:
		seen[i] = true
	assert_eq(seen.size(), 100, "no cap on the tokens the tiles carry")
	assert_eq(OcclusionTiles.fallback_count(entries), OcclusionTiles.FALLBACK_TOKENS)


func test_the_image_holds_the_headers_and_lists_the_shader_reads() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var entries := _random_entries(rng, 120, 10.0)
	var bins := OcclusionTiles.bin(
		entries, _view(Vector3(14.0, 22.0, 14.0), Vector3.ZERO), _ortho(), TILES, _margin()
	)
	var image := OcclusionTiles.build_image(entries, bins, TILES)
	var w := OcclusionTiles.TEXTURE_WIDTH
	var bad := 0
	for t in TILES.x * TILES.y:
		var h := OcclusionTiles.HEADER_BASE + t
		var header := image.get_pixel(h % w, h / w)
		if int(header.g) != bins[0][t + 1] - bins[0][t]:
			bad += 1
			continue
		for k in int(header.g):
			var texel := int(header.r) + k
			var c := image.get_pixel(texel % w, texel / w)
			var e := entries[bins[1][bins[0][t] + k]]
			if Vector4(c.r, c.g, c.b, c.a) != e:
				bad += 1
	assert_eq(bad, 0, "each header points at copies of its tokens' texels")
	assert_gt(bins[1].size(), 0)


func test_the_plain_loop_prefers_tokens_on_screen() -> void:
	var view := _view(Vector3(14.0, 22.0, 14.0), Vector3.ZERO)
	var entries: Array[Vector4] = []
	for i in 40:
		entries.append(Vector4(500.0 + i, 0.0, 0.0, 1.0))
	entries.append(Vector4(0.0, 0.5, 0.0, 1.0))
	var bins := OcclusionTiles.bin(entries, view, _ortho(), TILES, _margin())
	var fallback := OcclusionTiles.fallback_entries(entries, bins)
	assert_eq(fallback.size(), OcclusionTiles.FALLBACK_TOKENS)
	assert_eq(fallback[0], entries[40], "the one token on screen comes first")
	assert_eq(fallback[1], entries[0], "then the rest in scene order")


func test_the_shader_reads_the_same_layout() -> void:
	var text := FileAccess.get_file_as_string("res://shaders/occlusion_fade_include.gdshaderinc")
	assert_string_contains(
		text, "const int OCCLUSION_TEXTURE_WIDTH = %d;" % OcclusionTiles.TEXTURE_WIDTH
	)
	assert_string_contains(text, "const float FIGURE_WIDTH = %s;" % OcclusionTiles.FIGURE_WIDTH)
	assert_string_contains(text, "ivec2(frag_coord / viewport_size * vec2(grid))")
