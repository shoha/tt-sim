class_name FireFieldSmoke
extends MultiMeshInstance3D

## The persistent fire's smoke (FireField; design section 4 "Smoke"): one tall leaning plume over
## each of up to FireClusters.MAX_SMOKE of the largest blaze clusters (FireClusters.smoke). Each
## column is one quad (PER_SITE instance) standing on its source and turning about the world's up
## axis to face the camera, drawn by shaders/fire_smoke_book.gdshader from the smoke book
## (FireSmokeBook, assets/fire/fire_smoke_book.res): a closed loop of held frames of the whole
## column's silhouette per seed, baked once offline from the plume the game used to work out per
## pixel (round 6 of the reference fit; git history holds that shader, fire_field_smoke.gdshader,
## and the structures earlier rounds tried). The draw cross-fades the loop's frames on the
## column's own clock (a lobe climbs in about LIFE_S), from the flame tips to about four flame
## heights, leaning down the map's wind, and tones them live by the sun and the night.
##
## A column's size is its cluster's: the unit (column_unit) is the cluster's tallest flame,
## scaled down for a smaller cluster, so the biggest fire is the biggest smoker. place() writes
## one instance buffer when the blocks re-plan (instance_buffer, pure); nothing runs per frame,
## and the shared material carries the map's wind (set_wind). Smoke is a look only: every peer
## runs its own clock; where it rises is the plan's.
##
## The smoke book loads with the flames' (FireLook.request_book, poll_book and release_book call
## this class's): a threaded load with the first fire, bound on the main thread when it lands,
## let go when the last FireField leaves the tree. Until it is bound `frames` is 0 and the
## columns draw nothing; a missing book or a Git LFS pointer pushes one error.

const NODE_NAME := "FireSmoke"
const SHADER := preload("res://shaders/fire_smoke_book.gdshader")
## Instances a column (the whole column is one quad since round 4: rounds 1-3's separate billow
## quads read as crowns, a haze, then a chain of discs) and the column's clock: a lobe climbs it
## in about LIFE_S seconds (each column's own within LIFE_VARY of it).
const PER_SITE := 1
const LIFE_S := 10.0
const LIFE_VARY := 0.1
## The column, in its unit: its source BORN_AT up (among the tips of the tallest flames), RISE
## tall above it and leaning LEAN of that down the wind at the top, WIDTH its half width at the
## source and the crown (the shader's uniforms are set from these): a plume about twice as tall
## as wide, rising over the trees.
const BORN_AT := 0.95
const RISE := 3.4
const LEAN := 0.45
const WIDTH := Vector2(0.3, 0.64)
## The unit is the cluster's tallest flame times UNIT_SMALL over the smallest clusters, rising
## to 1 at FULL_SIZE square metres of flame (FireClusters' size).
const UNIT_SMALL := 0.75
const FULL_SIZE := 60.0

static var _material: ShaderMaterial = null
## The smoke book's state (FireLook.Book) and its texture once bound.
static var _book := FireLook.Book.NONE
static var _book_texture: Texture2DArray = null

var _sites: Array[Dictionary] = []


func _init() -> void:
	name = NODE_NAME
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = material()
	var billows := MultiMesh.new()
	billows.transform_format = MultiMesh.TRANSFORM_3D
	billows.use_custom_data = true
	billows.mesh = FireLook.mesh()
	billows.instance_count = capacity()
	billows.visible_instance_count = 0
	multimesh = billows


## The smoke's material (shared): the column's shape from this class's constants, drawn
## before the flames.
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = -1
		_material.set_shader_parameter("rise", RISE)
		_material.set_shader_parameter("lean", LEAN)
		_material.set_shader_parameter("width", WIDTH)
	return _material


## Sets the map's wind (FireLook.wind_for of `map_seed`) on the shared material: the columns
## lean down it.
static func set_wind(map_seed: int) -> void:
	material().set_shader_parameter("lean_dir", FireLook.wind_for(map_seed).normalized())


## Starts loading the smoke book on a thread (once; FireLook.request_book asks with the flames'
## book). A missing book or a Git LFS pointer pushes one error and the smoke stays invisible.
static func request_book(path: String = FireSmokeBook.PATH) -> void:
	material()
	if _book != FireLook.Book.NONE:
		return
	if not ResourceLoader.exists(path) or FireBook.is_lfs_pointer(path):
		_fail()
		return
	if ResourceLoader.load_threaded_request(path, "", false) != OK:
		_fail()
		return
	_book = FireLook.Book.LOADING


## Binds the smoke book once its load has landed (FireLook.poll_book); true once bound.
static func poll_book(path: String = FireSmokeBook.PATH) -> bool:
	if _book != FireLook.Book.LOADING:
		return _book == FireLook.Book.READY
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return false
	_land_book(path, status == ResourceLoader.THREAD_LOAD_LOADED)
	return _book == FireLook.Book.READY


## Waits for the smoke book's load and binds it (tests and probes; the game polls).
static func finish_book(path: String = FireSmokeBook.PATH) -> bool:
	if _book == FireLook.Book.LOADING:
		_land_book(path, true)
	return _book == FireLook.Book.READY


## The smoke book's state (FireLook.Book).
static func book_state() -> FireLook.Book:
	return _book


## The bound smoke book's texture (null until it lands).
static func book_texture() -> Texture2DArray:
	return _book_texture


## Lets go of the smoke book (FireLook.release_book, when the last FireField leaves the tree):
## the sampler nulled, `frames` 0 so nothing draws, and the texture freed. A load still in flight
## is waited for and dropped.
static func release_book(path: String = FireSmokeBook.PATH) -> void:
	if _book == FireLook.Book.LOADING:
		ResourceLoader.load_threaded_get(path)
	_book = FireLook.Book.NONE
	_book_texture = null
	if _material != null:
		_material.set_shader_parameter("smoke_book", null)
		_material.set_shader_parameter("frames", 0)


static func _land_book(path: String, loaded: bool) -> void:
	var book := ResourceLoader.load_threaded_get(path) as FireSmokeBook if loaded else null
	if book == null or book.problem() != "":
		_fail()
		return
	var texture := book.create_texture()
	if texture == null:
		_fail()
		return
	var mat := material()
	mat.set_shader_parameter("smoke_book", texture)
	mat.set_shader_parameter("seeds", book.seeds)
	mat.set_shader_parameter("domain", book.domain)
	mat.set_shader_parameter("frames", book.frames)
	_book_texture = texture
	_book = FireLook.Book.READY


static func _fail() -> void:
	_book = FireLook.Book.FAILED
	push_error("fire smoke book missing, malformed or an LFS pointer: run git lfs pull")


## Billows the pool holds: every site's column.
static func capacity() -> int:
	return FireClusters.MAX_SMOKE * PER_SITE


## Raises columns over `clusters` (FireClusters.smoke; document metres, this node's frame).
func place(clusters: Array[Dictionary]) -> void:
	_sites = clusters.duplicate()
	var shown := mini(_sites.size(), FireClusters.MAX_SMOKE)
	multimesh.visible_instance_count = 0
	if shown > 0:
		multimesh.buffer = instance_buffer(_sites)
		custom_aabb = bounds(_sites)
	multimesh.visible_instance_count = shown * PER_SITE


## Sites smoking.
func site_count() -> int:
	return _sites.size()


## The clusters smoking (FireClusters.smoke's records), largest first.
func sites() -> Array[Dictionary]:
	return _sites


## Instances drawn (each column's PER_SITE).
func live_count() -> int:
	return mini(_sites.size(), FireClusters.MAX_SMOKE) * PER_SITE


## A column's unit (metres) over `cluster`: its tallest flame, less over a small cluster. Pure.
static func column_unit(cluster: Dictionary) -> float:
	var share := clampf(float(cluster["size"]) / FULL_SIZE, 0.0, 1.0)
	return float(cluster["top"]) * lerpf(UNIT_SMALL, 1.0, share)


## Where a column stands over `cluster` (its source; this node's frame). Pure.
static func source(cluster: Dictionary) -> Vector3:
	var at: Vector3 = cluster["at"]
	return at + Vector3(0.0, float(cluster["top"]) * BORN_AT, 0.0)


## A column's height above its source and its width at the crown (metres), without the lean.
## Pure.
static func column_extent(cluster: Dictionary) -> Vector2:
	var unit := column_unit(cluster)
	return Vector2(unit * RISE, unit * WIDTH.y * 2.0)


## The MultiMesh buffer (capacity() instances of FireLook.INSTANCE_FLOATS) for columns over the
## first MAX_SMOKE of `clusters`: site k's column is instance k, a uniform scale of the column's
## unit at its source, with (phase, seed, life, 1) as custom data; the rest stay zero. Pure.
static func instance_buffer(clusters: Array[Dictionary]) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(capacity() * FireLook.INSTANCE_FLOATS)
	for site in mini(clusters.size(), FireClusters.MAX_SMOKE):
		var cluster := clusters[site]
		var unit := column_unit(cluster)
		var at := source(cluster)
		var life := LIFE_S * (1.0 + LIFE_VARY * (fmod(site * 0.618034 + 0.31, 1.0) * 2.0 - 1.0))
		for k in PER_SITE:
			var n := site * PER_SITE + k
			var i := n * FireLook.INSTANCE_FLOATS
			# Row-major 3x4: (basis x, y, z, origin) per row.
			out[i] = unit
			out[i + 3] = at.x
			out[i + 5] = unit
			out[i + 7] = at.y
			out[i + 10] = unit
			out[i + 11] = at.z
			out[i + 12] = fmod(float(k) / PER_SITE + site * 0.381966 + 1.0, 1.0)
			out[i + 13] = fmod(n * 0.618034 + 0.13, 1.0)
			out[i + 14] = life
			out[i + 15] = 1.0
	return out


## The bounds of the columns over `clusters`: every source, with room for the book's frame
## (FireSmokeBook.DOMAIN: its half width either side of the leaning centre line, its foot below
## the source and its top above) and the most the wind leans the top (LEAN x RISE, whichever way
## the camera looks). Pure.
static func bounds(clusters: Array[Dictionary]) -> AABB:
	var box := AABB()
	var reach := 0.0
	for site in mini(clusters.size(), FireClusters.MAX_SMOKE):
		var at := source(clusters[site])
		box = AABB(at, Vector3.ZERO) if site == 0 else box.expand(at)
		reach = maxf(reach, column_unit(clusters[site]))
	var side := reach * (LEAN * RISE + FireSmokeBook.DOMAIN.x)
	var room := Vector3(side, -reach * FireSmokeBook.DOMAIN.y, side)
	var top := Vector3(0.0, reach * FireSmokeBook.DOMAIN.z, 0.0)
	return AABB(box.position - room, box.size + room * 2.0 + top)
