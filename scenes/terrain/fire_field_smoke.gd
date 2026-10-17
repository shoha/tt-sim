class_name FireFieldSmoke
extends MultiMeshInstance3D

## The persistent fire's smoke (FireField; design section 4 "Smoke"): one tall leaning plume over
## each of up to FireClusters.MAX_SMOKE of the largest blaze clusters (FireClusters.smoke). Each
## column is one quad (PER_SITE instance) standing on its source and turning about the world's up
## axis to face the camera, drawn by shaders/fire_field_smoke.gdshader (the header there holds
## the look and the structures earlier rounds tried), which paints the whole column as
## one silhouette and moves its lobes up it on the column's own clock (a life of LIFE_S), from
## the flame tips to about four flame heights, leaning down the map's wind.
##
## A column's size is its cluster's: the unit (column_unit) is the cluster's tallest flame,
## scaled down for a smaller cluster, so the biggest fire is the biggest smoker. place() writes
## one instance buffer when the blocks re-plan (instance_buffer, pure); nothing runs per frame,
## and the shared material carries the map's wind (set_wind). Smoke is a look only: every peer
## runs its own clock; where it rises is the plan's.

const NODE_NAME := "FireSmoke"
const SHADER := preload("res://shaders/fire_field_smoke.gdshader")
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
## Room the quad keeps either side of the leaning centre line, above the crown and below the
## source (the shader's ROOM, CROWN_PAD and BASE_PAD), for the bounds.
const ROOM := 2.9
const CROWN_PAD := 0.75
const BASE_ROOM := 0.45
## The unit is the cluster's tallest flame times UNIT_SMALL over the smallest clusters, rising
## to 1 at FULL_SIZE square metres of flame (FireClusters' size).
const UNIT_SMALL := 0.75
const FULL_SIZE := 60.0

static var _material: ShaderMaterial = null

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


## The bounds of the columns over `clusters`: every source, with room for a column's height,
## lean and width. Pure.
static func bounds(clusters: Array[Dictionary]) -> AABB:
	var box := AABB()
	var reach := 0.0
	for site in mini(clusters.size(), FireClusters.MAX_SMOKE):
		var at := source(clusters[site])
		box = AABB(at, Vector3.ZERO) if site == 0 else box.expand(at)
		reach = maxf(reach, column_unit(clusters[site]))
	var side := reach * (LEAN * RISE + WIDTH.y * ROOM)
	var room := Vector3(side, reach * BASE_ROOM, side)
	var top := Vector3(0.0, reach * (RISE + CROWN_PAD), 0.0)
	return AABB(box.position - room, box.size + room * 2.0 + top)
