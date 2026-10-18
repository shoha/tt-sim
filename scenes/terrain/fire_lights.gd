class_name FireLights
extends Node3D

## The persistent fire's lights (FireField; design section 4 "Light", the user's F3 decision
## of 2026-10-16): at most FireClusters.MAX_LIGHTS shared OmniLight3D, no shadows, range
## RANGE_M, in the flames' warm colour (FireLook.LIGHT_COLOR), over the largest burning clusters
## (FireClusters.lights), each a little above its cluster's centroid. They carry the fire at
## dusk and night only: their energy follows FireLook.light_gate of the published sun
## (FoliageLight.last_sun, written whenever the level's sun changes), and they are hidden while
## the gate is 0, so by day they cost nothing.
##
## place() runs when blocks re-plan; a cluster already lit keeps its light
## (FireClusters.keep_slots), so a re-plan moves only the lights whose clusters changed. Per
## frame, a slow flicker (FireLook.flicker) is the only work: one energy set per light shown.
##
## The game itself adds no other omni light to a play scene (only a Blender map's own
## KHR_lights_punctual lamps can), so these four fit the Mobile renderer's eight omni lights per
## mesh beside up to four of a map's.

const NODE_NAME := "FireLights"
## How far a light reaches (metres) and its falloff (OmniLight3D.omni_attenuation; 1 is the
## inverse distance). Broad and flat (round 2's dark probe, the harness's night with the ambient
## cut): at range 7 and falloff 1 a light only warmed the logs right under it, a low strong
## light blew out a yellow patch under itself, and range 12 at falloff 0.5 washed the ash, rock
## and logs across the burn warm, the read of the fire as the scene's light. Round 4 measured
## (outdoor_night, lights on against off, pixel probes): the burn's char and ash move strongly
## out to 8 m, but range 12's window, (1 - (d / range)^4)^2, leaves 2 % of the light at 11 m, so
## the green beyond the burn's edge (10 m and more from a light) never moved; range 20 keeps the
## near field as it was (within 4 m the window is above 0.99) and leaves an attenuation of 0.24
## at 11 m (0.016 at range 12): green ground 8-11 m out now warms, canopies near the burn take a
## lit fire side, with no blown patch. But at range 20 the light still held 0.08 at 16 m, and
## the critic read night as a dim sunset, everything brown-orange. Round 5 compared four
## falloffs at the home blaze's light (lights on against off, at 2 to 16 m): range 15 with a
## decay of 0.75 and energy 18 (FireLook.LIGHT_ENERGY) keeps the near field (0.97 of range 20's
## light at 4 m), the burn's edge at 11 m about 0.44 of it, 13 m 0.2 and nothing from 15 m, so
## the firelit pool falls off to the night's green within a few trunk lengths of the burn.
## Round 6 of the reference fit (spike-flipbook, card ref-fit-flipbook-r2 onward) stands bigger,
## fewer fires with their own glowing pools on the ground (fire_glow.gdshaderinc), so the light
## no longer has to carry the burn: range 8 with a decay of 1.4 (energy unchanged) keeps the
## warmth under and round each fire and leaves the char between fires dark, as round 6 judged.
const RANGE_M := 8.0
const DECAY := 1.4
## A light stands this share of its cluster's tallest flame above the cluster's centroid,
## within RISE_M (high enough to reach past the burn's edge without a hot spot under it).
const RISE_SHARE := 0.7
const RISE_M := Vector2(1.4, 2.4)
## An empty slot's cell.
const NONE := Vector2i(2147483647, 2147483647)

var _lights: Array[OmniLight3D] = []
## Each slot's cluster cell (NONE: unused) and its energy before the gate and flicker.
var _cells: Array[Vector2i] = []
var _energy := PackedFloat32Array()
var _shown := false
var _clock := 0.0


func _init() -> void:
	name = NODE_NAME
	_energy.resize(FireClusters.MAX_LIGHTS)
	for slot in FireClusters.MAX_LIGHTS:
		var light := OmniLight3D.new()
		light.name = "FireLight%d" % slot
		light.omni_range = RANGE_M
		light.omni_attenuation = DECAY
		light.shadow_enabled = false
		light.light_color = FireLook.LIGHT_COLOR
		light.light_specular = 0.0
		light.light_bake_mode = Light3D.BAKE_DISABLED
		light.visible = false
		add_child(light)
		_lights.append(light)
		_cells.append(NONE)


## Stands the lights over `clusters` (FireClusters.lights; document metres, this node's frame),
## a cluster already lit keeping its light.
func place(clusters: Array[Dictionary]) -> void:
	var wanted: Array[Vector2i] = []
	for cluster in clusters:
		wanted.append(cluster["cell"])
	var slots := FireClusters.keep_slots(_cells, wanted)
	for slot in _lights.size():
		var k := slots[slot]
		_cells[slot] = NONE if k < 0 else wanted[k]
		_lights[slot].visible = _shown and k >= 0
		if k < 0:
			continue
		var cluster := clusters[k]
		var at: Vector3 = cluster["at"]
		var rise := clampf(float(cluster["top"]) * RISE_SHARE, RISE_M.x, RISE_M.y)
		_lights[slot].position = at + Vector3(0.0, rise, 0.0)
		_energy[slot] = FireLook.light_energy(float(cluster["size"]))


## Lights in use (over a cluster), shown or not.
func count() -> int:
	return _cells.size() - _cells.count(NONE)


## The lights, for probes and tests.
func lights() -> Array[OmniLight3D]:
	return _lights


func _process(delta: float) -> void:
	_clock += delta
	var gate := FireLook.light_gate(FoliageLight.last_sun)
	var shown := gate > 0.0
	if shown != _shown:
		_shown = shown
		for slot in _lights.size():
			_lights[slot].visible = shown and _cells[slot] != NONE
	if not shown:
		return
	for slot in _lights.size():
		if _cells[slot] != NONE:
			_lights[slot].light_energy = _energy[slot] * gate * FireLook.flicker(_clock, slot)
