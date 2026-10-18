class_name FireLook
extends RefCounted

## The look of persistent ground fire (design: docs/plans/2026-10-11-fire-features/design.md
## section 4; the production port: production.md): FireField owns placement, chunks and the
## budget; this owns the meshes and the materials, the fire book's loading and binding, how a
## block's plan becomes MultiMesh instances, and the ground's glow binding.
##
## The flames are fire_flames.gdshader: one camera-facing quad per fire drawing from the fire
## book (FireBook, assets/fire/fire_book.res: sequences of drawings baked by a small fire
## simulation), its pick, motion and colour all in the shader (the header there holds the
## model), so nothing runs per flame per frame. A chunk's instance data is one packed buffer
## (instance_buffer): a scale-only basis (the flame's width and height in metres) at its foot,
## and (seed, intensity, kind + the bed's heat at the foot, the fire's integer seed) as custom
## data; the shader hashes the integer seed for every pick, so the plan, not the GPU or the
## transform, decides what each fire draws. The first `count` entries of the plan are drawn
## (FireField emits each plan shuffled, so any prefix is an even thinning), sorted back to
## front along the camera's fixed forward axis once, since alpha-blended instances draw in
## buffer order and the camera only pans and zooms. A chunk's bounds hold every quad at the
## shader's jitter maxima (bounds).
##
## The book loads once there is fire: request_book on a live field's first non-empty plan or
## when the Fire tool is armed starts a threaded load, poll_book (each live FireField's
## _process) builds its texture and binds it on the main thread once it lands; until then the
## sampler is null, `drawings` is 0 and the flames draw nothing. A missing book or a Git LFS
## pointer pushes one error and leaves the flames invisible. Live fields are counted
## (hold_book, drop_book); when the last leaves the tree the material lets go of the book and
## the texture is freed.
##
## The glow is a term in the authored ground shader (fire_glow.gdshaderinc) read from the sim
## bake (FireNoiseBake), worked out from the document's fire_mask uploaded whole as an R8 texture
## on the sample grid (glow_texture) and FireField's heat raster with the feet's pools as an RG8
## one (heat_texture); the bake is bound to the terrain's material (bind_glow).
##
## One map is shown at a time, so the material's per-map uniform (the wind) is set on the
## shared material by the map's FireField.
##
## The fire's lights (FireLights) take their look from here: their warm colour, energy, slow
## flicker and the gate that shows them only while the sun is low (light_gate). The smoke
## (FireFieldSmoke, fire_field_smoke.gdshader) shares the flames' quad and leans down wind_for.

## The book's states: not asked for, loading on a thread, bound, or missing (one error pushed).
enum Book { NONE, LOADING, READY, FAILED }

const FLAMES_SHADER := preload("res://shaders/fire_flames.gdshader")
## Floats per instance in a MultiMesh buffer: a 3x4 transform, then the custom data.
const INSTANCE_FLOATS := 16
## How far the wind leans a flame's tip to the side on screen (a share of its height).
const WIND_LEAN := 0.25
## The bed temperature at a flame's foot rides in its kind's fraction, scaled by this (under 1).
const FOOT_SHARE := 0.99
## The fire's integer seed's range: a plan seed (0..1) times this, floored, is exact in a float.
const SEED_RANGE := 16777216.0
## Cuts in the shared quad (QuadMesh.subdivide_depth: rows - 1), so the shader leans a fire by
## moving its rows.
const ROW_CUTS := 4
## The shader's sequence array's size (seq_bounds is padded to it).
const BOOK_SEQUENCES := 16
## The camera's forward axis when there is none (tests, a field built before the camera): the
## game camera's fixed yaw and about its pitch.
const DEFAULT_FORWARD := Vector3(-0.67, -0.33, -0.67)
## fire_flames.gdshader's quad, for the bounds (keep them in step with the shader): the tile's
## height in flame heights and its width over its height; the jitter maxima of a fire's size,
## of its height, width and lean (shares of its height), of the wind's lean (its gust and its
## own draw: 1.15 x 1.1) and the most a row moves (LEAN_REACH); how far a quad stands toward
## the camera (metres, and a share of its half width); a spark's rise, drift and wobble.
const QUAD_ROOM := 2.1
const QUAD_ASPECT := 0.75
const QUAD_SIZE_MAX := 1.13
const QUAD_JITTER := Vector3(0.25, 0.18, 0.15)
const QUAD_GUST_MAX := 1.265
const QUAD_LEAN_REACH := 1.4
const QUAD_TOWARD := Vector2(0.12, 0.25)
const SPARK_RISE_M := 1.8
const SPARK_DRIFT_M := 0.45
const SPARK_WOBBLE_M := 0.08
## The lights' colour: the flames' amber band as a light (sRGB), a little softer, so it warms
## the ground and the trees round the fire without dyeing them orange.
const LIGHT_COLOR := Color(1.0, 0.56, 0.24)
## A light's energy over the largest clusters, and the share it keeps over the smallest (by
## the cluster's size against LIGHT_FULL_SIZE square metres of flame, FireClusters). (The F3
## probe found energy 3 invisible against the dusk ambient; 2 read as nothing and 6 as very
## little at the home zoom in this card's first rounds, since most of it falls on dark char.
## With FireLights' broad flat falloff, 6 washed the burn warm in the dark probe. Under the
## game's outdoor_night preset, 8 warmed the ash and logs only a little and 14 warms the ash,
## logs and stumps across the burn with no blown patch; the burnt bark itself, linear albedo
## about 0.035, stays dark either way. Round 5's steeper falloff, FireLights.DECAY 0.75, takes
## 18 for the same light within 4 m.)
const LIGHT_ENERGY := 18.0
const LIGHT_SMALL := 0.6
const LIGHT_FULL_SIZE := 60.0
## The flicker: how deep it dips, and its two slow rates (radians a second).
const FLICKER_DEPTH := 0.22
const FLICKER_RATES := Vector2(1.7, 4.3)
## The lights fade in as the published sun's weight (FoliageLight.sun_value: its energy times
## how high it stands) falls from LIGHT_GATE.y to .x: off by day, full at dusk and night.
const LIGHT_GATE := Vector2(0.1, 0.35)

static var _mesh: QuadMesh = null
static var _material: ShaderMaterial = null
## The book's state, its texture once bound, the FireFields in the tree, and the load's timings
## (when it was asked for; milliseconds to land and to build and bind the texture).
static var _book := Book.NONE
static var _book_texture: Texture2DArray = null
static var _live_fields := 0
static var _requested_usec := 0
static var _load_ms := 0.0
static var _upload_ms := 0.0


## The flame quad (shared): a unit quad of ROW_CUTS + 1 rows the shader stands on its foot,
## turns to the camera and leans row by row.
static func mesh() -> QuadMesh:
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2.ONE
		_mesh.subdivide_depth = ROW_CUTS
	return _mesh


## The flames' material (shared).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = FLAMES_SHADER
	return _material


## Starts loading the fire book on a thread (once; FireField's first fire, the Fire tool's
## arming). A missing book or a Git LFS pointer pushes one error and the flames stay invisible.
static func request_book(path: String = FireBook.PATH) -> void:
	material()
	if _book != Book.NONE:
		return
	_requested_usec = Time.get_ticks_usec()
	_load_ms = 0.0
	_upload_ms = 0.0
	if not ResourceLoader.exists(path) or FireBook.is_lfs_pointer(path):
		_fail()
		return
	if ResourceLoader.load_threaded_request(path, "", false) != OK:
		_fail()
		return
	_book = Book.LOADING


## Binds the book once its load has landed (each live FireField's _process); true once bound.
static func poll_book(path: String = FireBook.PATH) -> bool:
	if _book != Book.LOADING:
		return _book == Book.READY
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return false
	_land_book(path, status == ResourceLoader.THREAD_LOAD_LOADED)
	return _book == Book.READY


## Waits for the book's load and binds it (tests and probes; the game polls).
static func finish_book(path: String = FireBook.PATH) -> bool:
	if _book == Book.LOADING:
		_land_book(path, true)
	return _book == Book.READY


## The book's state (Book).
static func book_state() -> Book:
	return _book


## The bound book's texture (null until it lands).
static func book_texture() -> Texture2DArray:
	return _book_texture


## The last load's timings: {"load_ms": from the request to the poll that found it landed,
## "upload_ms": building its texture and binding it on the main thread}.
static func book_timings() -> Dictionary:
	return {"load_ms": _load_ms, "upload_ms": _upload_ms}


## A FireField entered the tree.
static func hold_book() -> void:
	_live_fields += 1


## A FireField left the tree; the last one's leaving releases the book.
static func drop_book() -> void:
	_live_fields = maxi(_live_fields - 1, 0)
	if _live_fields == 0:
		release_book()


## FireFields in the tree.
static func live_fields() -> int:
	return _live_fields


## Lets go of the book: the material's samplers nulled (nothing draws) and the texture freed. A
## load still in flight is waited for and dropped, so no loaded book stays behind on the loader.
static func release_book(path: String = FireBook.PATH) -> void:
	if _book == Book.LOADING:
		ResourceLoader.load_threaded_get(path)
	_book = Book.NONE
	_book_texture = null
	if _material != null:
		_material.set_shader_parameter("flipbook", null)
		_material.set_shader_parameter("drawings", 0)
		_material.set_shader_parameter("tear_layer", -1)


static func _land_book(path: String, loaded: bool) -> void:
	var book := ResourceLoader.load_threaded_get(path) as FireBook if loaded else null
	_load_ms = (Time.get_ticks_usec() - _requested_usec) / 1000.0
	if book == null:
		_fail()
		return
	var started := Time.get_ticks_usec()
	var texture := book.create_texture()
	if texture == null:
		_fail()
		return
	var bounds := book.seq_bounds.duplicate()
	bounds.resize(BOOK_SEQUENCES)
	var mat := material()
	mat.set_shader_parameter("flipbook", texture)
	mat.set_shader_parameter("seq_bounds", bounds)
	mat.set_shader_parameter("class_first", book.class_first)
	mat.set_shader_parameter("drawings", book.drawings)
	mat.set_shader_parameter("tear_layer", book.tear_layer)
	_book_texture = texture
	_book = Book.READY
	_upload_ms = (Time.get_ticks_usec() - started) / 1000.0


static func _fail() -> void:
	_book = Book.FAILED
	push_error("fire book missing or an LFS pointer: run git lfs pull")


## The map's wind for map seed `map_seed`: a direction in world XZ times WIND_LEAN. Pure.
static func wind_for(map_seed: int) -> Vector2:
	var angle := MaskBrush.sample_noise(map_seed + 11, 0x51ED) * TAU
	return Vector2.from_angle(angle) * WIND_LEAN


## Sets the map's wind on the shared material.
static func set_wind(map_seed: int) -> void:
	material().set_shader_parameter("wind", wind_for(map_seed))


## How much the fire's lights show (0..1) under the published sun `sun` (FoliageLight.last_sun:
## the direction toward it and its weight): none by day, fading in as the sun sinks, full at
## dusk, at night and with no sun. Pure.
static func light_gate(sun: Vector4) -> float:
	return 1.0 - smoothstep(LIGHT_GATE.x, LIGHT_GATE.y, sun.w)


## A light's energy over a cluster of `size` square metres of flame, before the gate and
## flicker. Pure.
static func light_energy(size: float) -> float:
	return LIGHT_ENERGY * lerpf(LIGHT_SMALL, 1.0, clampf(size / LIGHT_FULL_SIZE, 0.0, 1.0))


## Light `slot`'s slow flicker at `t` seconds: a share of its energy, 1 - FLICKER_DEPTH to 1,
## each slot on its own phase. Pure.
static func flicker(t: float, slot: int) -> float:
	var phase := slot * 2.39
	var wave := (
		0.5
		+ 0.3 * sin(t * FLICKER_RATES.x + phase)
		+ 0.2 * sin(t * FLICKER_RATES.y + phase * 1.7)
	)
	return 1.0 - FLICKER_DEPTH * wave


## A chunk for one burning block, empty until fill_chunk.
static func make_chunk(chunk_name: String) -> MultiMeshInstance3D:
	var chunk := MultiMeshInstance3D.new()
	chunk.name = chunk_name
	chunk.material_override = material()
	chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = mesh()
	chunk.multimesh = multimesh
	return chunk


## Draws the first `count` entries of `plan` (FireField's STRIDE layout) in `chunk`, sorted
## back to front along `forward`; `feet` holds each entry's bed temperature (0..1) at its foot.
static func fill_chunk(
	chunk: MultiMeshInstance3D,
	plan: PackedFloat32Array,
	count: int,
	forward: Vector3,
	feet := PackedFloat32Array()
) -> void:
	var buffer := instance_buffer(plan, count, forward, feet)
	var multimesh := chunk.multimesh
	multimesh.instance_count = count
	multimesh.buffer = buffer
	chunk.custom_aabb = bounds(plan, count, forward)


## The MultiMesh buffer for the first `count` entries of `plan` (INSTANCE_FLOATS each), the
## far ones first along `forward`. The custom data's z is the entry's kind plus, as its
## fraction, its bed temperature from `feet` (none: 0), and its w the fire's integer seed
## (fire_seed). Pure.
static func instance_buffer(
	plan: PackedFloat32Array, count: int, forward: Vector3, feet := PackedFloat32Array()
) -> PackedFloat32Array:
	var stride := FireField.STRIDE
	var order: Array = []
	for k in count:
		var o := k * stride
		order.append([Vector3(plan[o], plan[o + 1], plan[o + 2]).dot(forward), k])
	order.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var out := PackedFloat32Array()
	out.resize(count * INSTANCE_FLOATS)
	for slot in count:
		var k: int = order[slot][1]
		var o := k * stride
		var i := slot * INSTANCE_FLOATS
		var width := plan[o + FireField.WIDTH]
		var height := plan[o + FireField.HEIGHT]
		# Row-major 3x4: (basis x, y, z, origin) per row.
		out[i] = width
		out[i + 3] = plan[o]
		out[i + 5] = height
		out[i + 7] = plan[o + 1]
		out[i + 10] = width
		out[i + 11] = plan[o + 2]
		out[i + 12] = plan[o + FireField.SEED]
		out[i + 13] = plan[o + FireField.INTENSITY]
		var foot := clampf(feet[k], 0.0, 1.0) if k < feet.size() else 0.0
		out[i + 14] = plan[o + FireField.KIND] + foot * FOOT_SHARE
		out[i + 15] = fire_seed(plan[o + FireField.SEED])
	return out


## The fire's integer seed the shader hashes for its picks, from its plan seed `seed` (0..1,
## drawn from the map seed and its lattice point): exact in a float, so every peer and GPU
## draws the same fire. Pure.
static func fire_seed(seed: float) -> float:
	return floorf(clampf(seed, 0.0, 1.0) * (SEED_RANGE - 1.0))


## The camera's frame for forward axis `forward` as the shader builds it: x the screen's right
## (level), y the screen's up (world up laid in the view plane), z toward the camera. Pure.
static func view_frame(forward: Vector3) -> Basis:
	var back := -forward.normalized()
	var up := Vector3.UP - back * Vector3.UP.dot(back)
	if up.length() < 1e-4:
		up = Vector3.FORWARD
	up = up.normalized()
	return Basis(up.cross(back).normalized(), up, back)


## The bounds of the first `count` entries of `plan` seen along `forward`: each entry's quad at
## fire_flames.gdshader's jitter maxima round its foot (quad_box). Pure.
static func bounds(
	plan: PackedFloat32Array, count: int, forward: Vector3 = DEFAULT_FORWARD
) -> AABB:
	var frame := view_frame(forward)
	var box := AABB()
	for k in count:
		var o := k * FireField.STRIDE
		var at := Vector3(plan[o], plan[o + 1], plan[o + 2])
		var spark := plan[o + FireField.KIND] == FireField.SPARK
		var quad := quad_box(frame, plan[o + FireField.HEIGHT], plan[o + FireField.WIDTH], spark)
		quad.position += at
		box = quad if k == 0 else box.merge(quad)
	return box


## The box round its foot that a flame of `height` and `width` metres (or a spark, `spark`)
## can reach in camera frame `frame` (view_frame): its half width at the widest pick and the
## largest size, plus the wind's and its own lean on the top rows, sideways; the tile's room at
## the tallest pick, up the screen; its step toward the camera. A spark rises, drifts and
## wobbles. Pure.
static func quad_box(frame: Basis, height: float, width: float, spark: bool) -> AABB:
	var toward := QUAD_TOWARD.x + QUAD_TOWARD.y * 0.5 * width
	if spark:
		var drift := Vector3(SPARK_DRIFT_M, 0.0, SPARK_DRIFT_M)
		var rise := AABB(-drift, drift * 2.0 + Vector3(0.0, SPARK_RISE_M, 0.0))
		var half := 0.5 * width
		return rise.merge(_reach(frame, SPARK_WOBBLE_M + half, -half, half, toward))
	var half_wide := 0.5 * QUAD_ASPECT * QUAD_ROOM * (1.0 + QUAD_JITTER.y)
	var lean := (WIND_LEAN * QUAD_GUST_MAX + QUAD_JITTER.z) * QUAD_LEAN_REACH
	var side := height * QUAD_SIZE_MAX * (half_wide + lean)
	var top := height * QUAD_SIZE_MAX * QUAD_ROOM * (1.0 + QUAD_JITTER.x)
	return _reach(frame, side, 0.0, top, toward)


## The box of every point `a` frame.x + `b` frame.y + `c` frame.z with |a| up to `side`, b from
## `low` to `high` and c from 0 to `toward`.
static func _reach(frame: Basis, side: float, low: float, high: float, toward: float) -> AABB:
	var lo := Vector3.ZERO
	var hi := Vector3.ZERO
	for i in 3:
		var r := absf(frame.x[i]) * side
		var u := frame.y[i]
		var c := frame.z[i] * toward
		lo[i] = -r + minf(u * low, u * high) + minf(c, 0.0)
		hi[i] = r + maxf(u * low, u * high) + maxf(c, 0.0)
	return AABB(lo, hi - lo)


## The fire mask of `doc` as an R8 texture on its sample grid: `texture` updated in place when
## it has the grid's size, else a new one; null without a mask.
static func glow_texture(doc: MapDocument, texture: ImageTexture) -> ImageTexture:
	var size := Vector2i(doc.samples_x(), doc.samples_z())
	if doc.fire_mask.size() != size.x * size.y:
		return null
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_R8, doc.fire_mask)
	if texture != null and Vector2i(texture.get_size()) == size:
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


## The flames' heat raster `heat` (`size` texels, FireField.HEAT_STEP_M apart) as an RG8
## texture: red its sums over `full`, green the feet's pools `pools` (clamped to 1; none: 0).
## `texture` is updated in place when it has the size, else a new one.
static func heat_texture(
	heat: PackedFloat32Array,
	size: Vector2i,
	full: float,
	texture: ImageTexture,
	pools := PackedFloat32Array()
) -> ImageTexture:
	return raster_texture(heat_bytes(heat, size, full, pools), size, texture)


## heat_texture's bytes (RG8, row by row). Pure, so a worker can encode them (FirePlanJob).
static func heat_bytes(
	heat: PackedFloat32Array, size: Vector2i, full: float, pools := PackedFloat32Array()
) -> PackedByteArray:
	var count := size.x * size.y
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	if heat.size() == count:
		var scale := 255.0 / full
		var with_pools := pools.size() == count
		for i in count:
			bytes[i * 2] = mini(roundi(heat[i] * scale), 255)
			if with_pools:
				bytes[i * 2 + 1] = mini(roundi(pools[i] * 255.0), 255)
	return bytes


## The RG8 raster `bytes` of `size` texels as a texture: `texture` updated in place when it has
## the size, else a new one.
static func raster_texture(
	bytes: PackedByteArray, size: Vector2i, texture: ImageTexture
) -> ImageTexture:
	var image := Image.create_from_data(size.x, size.y, false, Image.FORMAT_RG8, bytes)
	if texture != null and Vector2i(texture.get_size()) == size:
		texture.update(image)
		return texture
	return ImageTexture.create_from_image(image)


## Binds the ground fire's sim bake (FireNoiseBake: its texture, null until drawn or with no
## fire, and one tile's frame) to the ground material `ground`; null turns the ground's fire off.
static func bind_glow(ground: ShaderMaterial, sim_map: Texture2D, sim_rect: Vector4) -> void:
	ground.set_shader_parameter("fire_sim_map", sim_map)
	ground.set_shader_parameter("fire_sim_rect", sim_rect)
	ground.set_shader_parameter("fire_present", 0 if sim_map == null else 1)
