class_name PainterMeadowSwathes
extends RefCounted

## The painted meadow's broad gold and moss swathes (card painter-ground-polish; docs/systems/
## painter.md "Meadow swathes"). Classic's meadow carries big gold-ochre and moss-green patches
## from its ground textures; the painted meadow was one calm green. This gives it a few bold soft
## shapes in the ground's own tone:
##
## - Two tones derived from the mood's `ground`: gold (`gold-turn` degrees, `gold-chroma`,
##   `gold-lift`) and moss (`moss-turn`, `moss-chroma`, `moss-lift`), each on the ground's ramp,
##   so every mood and sun moves them as it moves the meadow (an amber swathe at dusk and in
##   autumn, none under winter's snow: its `gold-share` and `moss-share` are 0).
## - Where they lie: one slow field in the ground shader (two octaves of value noise, about 22 m
##   and 9 m) through the meadow's own warp; its highest `gold-share` of the ground is gold, its
##   lowest `moss-share` moss, so the two never touch and a meadow band runs between them. The
##   block-in takes each swathe in two steps (half, then whole) and a brush mark takes it whole at
##   its middle, so the edge is brushed, never a gradient.
## - No sameness: the map's seed moves the field and each swathe's edge (up to SEED_EDGE of the
##   field, about a third of the share either way), so one map is mostly gold-flecked and the next
##   moss-dark.
##
## Pure functions; bind() and the ground tones (PainterGroundPaths.tones) set the uniforms.

## The ground shader's swathe field's spread: the field's standard deviation about 0.5 (measured by
## eye on the value noise; the thresholds below place a share's edge with it).
const FIELD_SD := 0.12
## How far the map's seed moves each swathe's edge in the field (-/+ this).
const SEED_EDGE := 0.035


## Sets the swathe field's seed for `doc` on the ground `materials` (`sw_seed`, seed_of()).
static func bind(materials: Array, doc: MapDocument) -> void:
	var seed := seed_of(doc.map_seed)
	for material: ShaderMaterial in materials:
		material.set_shader_parameter(&"sw_seed", seed)


## The swathe field's seed for map seed `map_seed`: x, y the field's offset (noise cells), z and w
## the gold and the moss edge's shift (-/+ SEED_EDGE; above 0 a smaller swathe). Pure.
static func seed_of(map_seed: int) -> Vector4:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(map_seed) ^ 0x5ea7ed
	return Vector4(
		rng.randf_range(0.0, 97.0),
		rng.randf_range(0.0, 97.0),
		rng.randf_range(-SEED_EDGE, SEED_EDGE),
		rng.randf_range(-SEED_EDGE, SEED_EDGE)
	)


## The swathes' uniforms in `mood` at `elevation`, keyed by the ground shader's names: `sw_lit` and
## `sw_shd` (gold's two variants, then moss's, linear) and `sw_k` (the field value above which gold
## lies, below which moss lies, and 1 when either is drawn).
static func tones(sheet: Dictionary, mood: String, elevation: float) -> Dictionary:
	var lit := PackedVector3Array()
	var shd := PackedVector3Array()
	for kind: String in ["gold", "moss"]:
		var ramp := PainterTones.ramp(
			sheet, mood, "ground", elevation, "ground-", tone_lch(sheet, mood, elevation, kind)
		)
		lit.append_array([PainterTones.linear(ramp[2]), PainterTones.linear(ramp[5])])
		shd.append_array([PainterTones.linear(ramp[0]), PainterTones.linear(ramp[3])])
	var gold := PainterSheet.number(sheet, mood, "gold-share", elevation)
	var moss := PainterSheet.number(sheet, mood, "moss-share", elevation)
	return {
		&"sw_lit": lit,
		&"sw_shd": shd,
		&"sw_k":
		Vector3(
			threshold(gold), 1.0 - threshold(moss), 1.0 if gold > 0.0 or moss > 0.0 else 0.0
		),
	}


## The middle tone (OKLCH) of swathe `kind` ("gold" or "moss"): the mood's ground turned
## `<kind>-turn` degrees, its chroma times `<kind>-chroma`, its lightness moved by `<kind>-lift`.
## Gold's hue is never redder than `gold-hue-min`: a dusk or autumn ground is already a yellow
## green, and the same turn took it to salmon (painter-ground-fire-round3). Pure.
static func tone_lch(sheet: Dictionary, mood: String, elevation: float, kind: String) -> Vector3:
	var ground := PainterSheet.tone_lch(sheet, mood, "ground", elevation)
	var num := func(suffix: String) -> float:
		return PainterSheet.number(sheet, mood, "%s-%s" % [kind, suffix], elevation)
	var hue := ground.z + float(num.call("turn"))
	if kind == "gold":
		hue = maxf(hue, float(num.call("hue-min")))
	return Vector3(
		clampf(ground.x + float(num.call("lift")), 0.05, 0.95),
		ground.y * float(num.call("chroma")),
		fposmod(hue, 360.0)
	)


## The swathe field's threshold for a share `share` (0 to 1) of the ground: the field value above
## which (gold) or below which (moss, the mirror) that share lies, from the field's spread (a normal
## quantile by Tukey's lambda approximation). Pure.
static func threshold(share: float) -> float:
	var p := clampf(1.0 - share, 0.001, 0.999)
	return 0.5 + FIELD_SD * 4.91 * (pow(p, 0.14) - pow(1.0 - p, 0.14))
