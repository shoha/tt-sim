class_name FireVariants
extends RefCounted

## The Painted look's variants of the event fire's shaders (card painter-fire; docs/systems/
## painter.md "Fire and events"). Classic draws event_puff, fire_smoke and ground_burn as they
## are; under Painted each is the same shader with a few lines edited: time held in steps of
## STEP_HZ (a brush-drawn fire jumps between drawings, it does not glide), the flame's heart a
## warmer yellow, an ember a small firm dab, the smoke a warm lilac-grey that takes more of the
## sun's colour (so the mood tints it through the light, the way it tints a crown), the burn's
## char a warm brown.
##
## The model. A variant is the original's source with EDITS applied, built once and cached, so no
## Classic file changes and the two cannot drift apart silently: a test applies every edit and
## fails when one no longer finds its text. The flag is static (like TokenGhost.painted):
## LevelEnvironmentManager sets it when the painted state changes, and each effect picks its
## shader when it is created (shader_for). The variants are warmed with the painter's shaders
## (PainterWarmup), so the first fire compiles nothing on the main thread.

const PUFF := "res://shaders/event_puff.gdshader"
const SMOKE := "res://shaders/fire_smoke.gdshader"
const BURN := "res://shaders/ground_burn.gdshader"
## How often painted fire time advances (a brush-drawn fire's frames).
const STEP_HZ := 10.0
## Source text of a variant's time: the engine's TIME held in steps.
const STEPPED := "(floor(TIME * 10.0) / 10.0)"

## shader path -> [[from, to], ...], applied in order by replace (every `from` must occur).
const EDITS: Dictionary = {
	PUFF: [
		["TIME", STEPPED],
		["FIRE_CORE = vec3(1.0, 0.79, 0.27);", "FIRE_CORE = vec3(1.0, 0.86, 0.36);"],
		[
			"shape = (1.0 - smoothstep(0.15, 1.0, r)) * (0.75 + 0.25 * sin(",
			"shape = (1.0 - smoothstep(0.5, 1.0, r)) * (0.8 + 0.2 * sin("
		],
	],
	SMOKE: [
		["SMOKE_DARK = vec3(0.05, 0.036, 0.026);", "SMOKE_DARK = vec3(0.085, 0.056, 0.058);"],
		["SMOKE_PALE = vec3(0.6, 0.6, 0.58);", "SMOKE_PALE = vec3(0.7, 0.61, 0.66);"],
		["SUN_TINT = 0.2;", "SUN_TINT = 0.5;"],
		["SHADE_FILL = vec3(0.2, 0.185, 0.16);", "SHADE_FILL = vec3(0.25, 0.19, 0.21);"],
		["fire_cloud(corner * 1.3 + card_draw", "fire_cloud(corner * 0.95 + card_draw"],
	],
	BURN: [["CHAR_TINT = vec3(0.3, 0.24, 0.21);", "CHAR_TINT = vec3(0.36, 0.24, 0.17);"]],
}

## Whether the Painted look is on (set by LevelEnvironmentManager).
static var painted := false
static var _cache: Dictionary = {}


## Sets the flag.
static func set_painted(on: bool) -> void:
	painted = on


## The shader to draw `path` with: the Painted variant while painted, else the original itself.
static func shader_for(path: String) -> Shader:
	if painted and EDITS.has(path):
		return variant(path)
	return load(path) as Shader


## The Painted variant of `path` (built once).
static func variant(path: String) -> Shader:
	if _cache.has(path):
		return _cache[path]
	var shader := Shader.new()
	shader.code = edited_code(FileAccess.get_file_as_string(path), EDITS[path])
	_cache[path] = shader
	return shader


## `code` with `edits` applied; an edit whose text is missing is reported and skipped.
static func edited_code(code: String, edits: Array) -> String:
	for edit: Array in edits:
		if not code.contains(edit[0]):
			push_warning("FireVariants: edit not found: %s" % edit[0])
			continue
		code = code.replace(edit[0], edit[1])
	return code


## Every variant, for the warm-up.
static func all_variants() -> Array[Shader]:
	var out: Array[Shader] = []
	for path: String in EDITS:
		out.append(variant(path))
	return out
