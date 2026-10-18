class_name EnvironmentGlow
extends RefCounted

## The game's glow: one tuning for every map and preset (the user's decision U2, 2026-10-18,
## carrying the round 6 fire look's screen glow to the whole game). Only what passes the HDR
## threshold blooms strongly (the fire's over-bright cores, sun glints on water, emissive
## materials), added on top of the frame over a wide spread of levels; the bloom share keeps a
## soft wash over the whole frame.
##
## A preset's and a level's glow keys keep the meaning they had before the re-tune, so presets
## and saved levels need no new numbers and no migration:
## - glow_intensity is read against the preset's own value (the reference): at the reference the
##   glow is INTENSITY, so fire blooms alike under every preset (round 6 parity by day, at sunset
##   and at night), and the Color pane's Glow slider scales the whole glow from there (0 is no
##   glow, twice the preset's value twice the glow);
## - the wash keeps today's amount, glow_bloom x glow_intensity: the bloom share is glow_bloom x
##   reference / INTENSITY, so the slider scales the wash with the rest;
## - glow_strength (the spread) passes through.
## On the Mobile renderer the intensity is MOBILE_GAIN times higher (its over-bright cores are
## capped near the threshold, so the round 6 probe needed the gain to match Forward+'s halo) and
## the bloom share is divided by the same, so the wash stays.

const INTENSITY := 0.5
const HDR_THRESHOLD := 1.05
const HDR_SCALE := 1.5
const BLEND_MODE := Environment.GLOW_BLEND_MODE_ADDITIVE
## Environment glow levels 1 to 7 (set_glow_level 0 to 6): the middle sizes, a wide halo.
const LEVELS: Array[float] = [0.0, 0.0, 0.6, 1.0, 1.0, 0.5, 0.0]
const MOBILE_GAIN := 2.0
## The reference when a preset's own intensity is about zero: PROPERTY_DEFAULTS' value.
const FALLBACK_REFERENCE := 0.3


## The Environment glow properties (by property name) for `config` (a resolved environment
## config), read against `reference`, the preset's own glow_intensity without the level's
## overrides, on rendering method `method` ("" the running one).
static func settings(config: Dictionary, reference: float, method := "") -> Dictionary:
	if method == "":
		method = RenderingServer.get_current_rendering_method()
	var gain := MOBILE_GAIN if method == "mobile" else 1.0
	var ref := reference if reference > 0.001 else FALLBACK_REFERENCE
	var share := float(config.get("glow_intensity", ref)) / ref
	return {
		"glow_enabled": bool(config.get("glow_enabled", false)),
		"glow_intensity": INTENSITY * gain * share,
		"glow_bloom": float(config.get("glow_bloom", 0.0)) * ref / (INTENSITY * gain),
		"glow_strength": float(config.get("glow_strength", 1.0)),
		"glow_hdr_threshold": HDR_THRESHOLD,
		"glow_hdr_scale": HDR_SCALE,
		"glow_blend_mode": BLEND_MODE,
	}


## Applies the game's glow for `config` to `env` (settings() plus the levels).
static func apply(env: Environment, config: Dictionary, reference: float, method := "") -> void:
	var values := settings(config, reference, method)
	for key: String in values:
		env.set(key, values[key])
	for k in LEVELS.size():
		env.set_glow_level(k, LEVELS[k])
