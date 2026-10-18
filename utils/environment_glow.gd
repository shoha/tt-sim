class_name EnvironmentGlow
extends RefCounted

## The game's glow: one tuning for every map and preset (the user's decision U2, 2026-10-18,
## carrying the round 6 fire look's screen glow to the whole game). Only what passes the HDR
## threshold blooms strongly (the fire's over-bright cores, sun glints on water, emissive
## materials), added on top of the frame over a wide spread of levels; the bloom share keeps a
## soft wash over the whole frame.
##
## A preset's and a level's glow keys keep the meaning they had before the re-tune, so saved
## levels need no new numbers and no migration:
## - glow_intensity is read against the preset's own value (the reference): at the reference the
##   glow is INTENSITY, so fire blooms alike under every preset (round 6 parity by day, at sunset
##   and at night). The Color pane's Glow slider scales the halo round bright things from there
##   (0 is no glow, twice the preset's value twice the halo) and the wash by the square root of
##   that share (twice the value, 1.41 times the wash), so a high slider blooms the highlights
##   more than it lifts the whole frame;
## - the wash at the preset's own value keeps the amount it had, glow_bloom x glow_intensity,
##   times the preset's optional glow_bloom_scale: the wide, additive wash lifts and greys a frame
##   more than the old screen-blended one did, so the presets with a strong wash (hell, ethereal)
##   carry a scale calibrated against the old glow on a map without fire (card fire-prod-c5c);
## - a preset's optional glow_hdr_threshold replaces HDR_THRESHOLD: outdoor_sunset's lower one
##   lets its fire-lit ground bloom as round 6's did once its wash is scaled to the old glow's
##   (card fire-prod-c5d). The Color pane never writes it, and an override of it reaches the
##   config only on a preset that carries it (get_environment_config drops a key the config lacks);
## - glow_strength keeps its old relative effect. Godot multiplies each level by the strength once
##   per blur pass on the way down (level k by strength^(k+1)), so over the wide LEVELS a strength
##   above 1 compounds far more than it did over Godot's own levels (1.3 was 3.3 times the glow
##   of a strength of 1, against 1.9 times before): strength() maps it back (1 stays 1).
## On the Mobile renderer the intensity is MOBILE_GAIN times higher (its over-bright cores are
## capped near the threshold, so the round 6 probe needed the gain to match Forward+'s halo) and
## the bloom share is divided by the same, so the wash stays.

const INTENSITY := 0.5
const HDR_THRESHOLD := 1.05
const HDR_SCALE := 1.5
const BLEND_MODE := Environment.GLOW_BLEND_MODE_ADDITIVE
## Environment glow levels 1 to 7 (set_glow_level 0 to 6): the middle sizes, a wide halo.
const LEVELS: Array[float] = [0.0, 0.0, 0.6, 1.0, 1.0, 0.5, 0.0]
## Godot's own levels, which every preset's glow_strength was tuned over before the re-tune.
const OLD_LEVELS: Array[float] = [0.0, 0.8, 0.4, 0.1, 0.0, 0.0, 0.0]
const MOBILE_GAIN := 2.0
## The reference when a preset's own intensity is about zero: PROPERTY_DEFAULTS' value.
const FALLBACK_REFERENCE := 0.3
## The smallest Glow share the wash's square root is taken of (at 0 the intensity is 0 anyway).
const MIN_SHARE := 0.01
## The highest strength strength() searches (the Color pane's slider tops out at 2, which maps
## to about 1.48).
const MAX_STRENGTH := 4.0


## The Environment glow properties (by property name) for `config` (a resolved environment
## config), read against `reference`, the preset's own glow_intensity without the level's
## overrides, on rendering method `method` ("" the running one).
static func settings(config: Dictionary, reference: float, method := "") -> Dictionary:
	if method == "":
		method = RenderingServer.get_current_rendering_method()
	var gain := MOBILE_GAIN if method == "mobile" else 1.0
	var ref := reference if reference > 0.001 else FALLBACK_REFERENCE
	var share := float(config.get("glow_intensity", ref)) / ref
	var bloom := float(config.get("glow_bloom", 0.0)) * ref / (INTENSITY * gain)
	bloom *= float(config.get("glow_bloom_scale", 1.0)) / sqrt(maxf(share, MIN_SHARE))
	return {
		"glow_enabled": bool(config.get("glow_enabled", false)),
		"glow_intensity": INTENSITY * gain * share,
		"glow_bloom": minf(bloom, 1.0),
		"glow_strength": strength(float(config.get("glow_strength", 1.0))),
		"glow_hdr_threshold": float(config.get("glow_hdr_threshold", HDR_THRESHOLD)),
		"glow_hdr_scale": HDR_SCALE,
		"glow_blend_mode": BLEND_MODE,
	}


## The glow_strength that boosts LEVELS as much, against a strength of 1, as `value` boosted
## OLD_LEVELS: a preset's or a level's strength keeps the effect it had (1 stays 1; 1.1 is
## about 1.054, 1.3 about 1.157).
static func strength(value: float) -> float:
	if value <= 0.0 or is_equal_approx(value, 1.0):
		return maxf(value, 0.0)
	var target := _boost(OLD_LEVELS, value) / _boost(OLD_LEVELS, 1.0) * _boost(LEVELS, 1.0)
	var low := 0.0
	var high := MAX_STRENGTH
	for _step in 40:
		var middle := (low + high) * 0.5
		if _boost(LEVELS, middle) < target:
			low = middle
		else:
			high = middle
	return (low + high) * 0.5


## Applies the game's glow for `config` to `env` (settings() plus the levels).
static func apply(env: Environment, config: Dictionary, reference: float, method := "") -> void:
	var values := settings(config, reference, method)
	for key: String in values:
		env.set(key, values[key])
	for k in LEVELS.size():
		env.set_glow_level(k, LEVELS[k])


## The summed weight of `levels` at strength `value` (level k is multiplied k + 1 times).
static func _boost(levels: Array[float], value: float) -> float:
	var total := 0.0
	for k in levels.size():
		total += levels[k] * pow(value, k + 1)
	return total
