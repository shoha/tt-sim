class_name FireFieldSmoke
extends SmokePuffs

## The persistent fire's smoke (FireField; design section 4 "Smoke"): slow billows of the fire
## events' family (SmokePuffs, shaders/fire_smoke.gdshader) over up to FireClusters.MAX_SMOKE
## of the largest blaze clusters (FireClusters.smoke). Each site puffs a billow every EVERY_S
## seconds, the sites staggered so they never puff together: born just above its tallest
## flames, sized by its cluster, rising slowly and leaning down the map's wind
## (FireLook.smoke_drift), its underside lit warm by the fire while it is low (WARMTH, the
## shader's fire_below), so a blaze stands under a short leaning column of a few bold crowns.
##
## One pool of MAX_SMOKE x PER_SITE billows (24), sized so a site never takes a live billow's
## slot (a billow lives at most PER_SITE puffs). Per frame: each site's clock counts down (at
## most 8) and step() places the live billows (at most 24 transforms and custom data). Smoke
## is a look only: its timing is each peer's own; where it rises is the plan's.

const NODE_NAME := "FireSmoke"
## Billows a site keeps alive at once, a billow's life (seconds) and a site's puff interval.
const PER_SITE := 3
const LIFE_S := 6.6
const EVERY_S := LIFE_S / PER_SITE
## A billow's size (metres) over the smallest and the largest clusters (by the cluster's size
## against FULL_SIZE square metres of flame), and how far a puff's own size and speed vary
## (either way, a share). Large, so the crown's cards read as a few bold shapes at the home
## zoom (2.2 m read as a small crumpled grey ball there).
const SIZE_M := Vector2(3.0, 4.6)
const FULL_SIZE := 60.0
const VARY := 0.15
## A billow is born this share of its cluster's tallest flame above the centroid.
const BORN_AT := 0.85
## How strongly the fire lights the billows' undersides (the shader's fire_below).
const WARMTH := 1.0
## The crown: fewer, larger cards than a fire event's (SmokePuffs.CARDS of CARD_HALF), so a
## slow billow reads as a few bold lumps rather than a crumpled ball of small pieces.
const CARDS_FIELD := 16
const CARD_HALF_FIELD := Vector2(0.28, 0.17)
const CROWN_SEED_FIELD := 2311

static var _field_crown: ArrayMesh = null

## The billows' drift (metres a second), set from the map's seed by FireField.
var drift := Vector3(0.0, FireLook.SMOKE_RISE, 0.0)
var _sites: Array[Dictionary] = []
var _wait := PackedFloat32Array()
var _puffs := 0


func _init() -> void:
	super(FireClusters.MAX_SMOKE * PER_SITE)
	name = NODE_NAME
	if _field_crown == null:
		_field_crown = SmokePuffs.build_crown(CARDS_FIELD, CARD_HALF_FIELD, CROWN_SEED_FIELD)
	multimesh.mesh = _field_crown
	# A column rises several metres over its fire, so the cull box reaches past the pool's.
	extra_cull_margin = 10.0
	_wait.resize(FireClusters.MAX_SMOKE)
	for site in _wait.size():
		_wait[site] = fmod(site * 0.618, 1.0) * EVERY_S


## Puffs over `clusters` (FireClusters.smoke; document metres, this node's frame) from now on;
## billows already rising keep rising.
func place(clusters: Array[Dictionary]) -> void:
	_sites = clusters.duplicate()


## Sites puffing.
func site_count() -> int:
	return _sites.size()


## The clusters puffing (FireClusters.smoke's records), largest first.
func sites() -> Array[Dictionary]:
	return _sites


## Where a site's billows are born (this node's frame) and how big they grow, for `cluster`.
## Pure.
static func source(cluster: Dictionary) -> Array:
	var at: Vector3 = cluster["at"]
	var size := lerpf(SIZE_M.x, SIZE_M.y, clampf(float(cluster["size"]) / FULL_SIZE, 0.0, 1.0))
	return [at + Vector3(0.0, float(cluster["top"]) * BORN_AT + size * 0.2, 0.0), size]


func _process(delta: float) -> void:
	for site in _sites.size():
		_wait[site] -= delta
		if _wait[site] <= 0.0:
			_wait[site] += EVERY_S
			_puff(_sites[site])
	step(delta)


func _puff(cluster: Dictionary) -> void:
	_puffs += 1
	var draw := fmod(_puffs * 0.618034, 1.0)
	var turn := fmod(_puffs * 0.414214, 1.0)
	var from: Array = source(cluster)
	var size: float = from[1] * (1.0 + VARY * (draw * 2.0 - 1.0))
	var velocity := drift * (1.0 + VARY * (turn * 2.0 - 1.0))
	var life := LIFE_S * (1.0 - 0.12 * turn)
	emit(from[0], velocity, size, life, Color.WHITE, WARMTH)
