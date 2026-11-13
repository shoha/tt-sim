class_name PainterTones
extends RefCounted

## The painted surfaces' tone ramps, drawn from a sheet's role colours (docs/systems/painter.md
## "Surfaces"). Pure functions over a compiled sheet (PainterSheet.load_sheet), no scene tree.
##
## The model (the painter spike's PStyle4.tones, which the prototype's sheet tuned). A role's
## colour is the MIDDLE of three steps. Its SHADE is its lightness times `shade-depth`, its OKLab
## chroma vector pulled toward the hue `shade-hue` by `shade-pull` (0.085 of chroma per unit),
## so every shade in a mood leans the same way (summer's blue-violet). Its LIT step is
## `lit-lift` lighter, a little less chroma, its hue pulled toward `lit-hue` by `lit-pull`. Each
## role has two VARIANTS, `value-spread` darker and lighter and `hue-spread` degrees either side,
## which a surface mixes between by a slow world noise so a field of one role is never one flat
## colour. The ground reads its own `ground-` depth, pull, lift and spreads. All numbers are the
## sheet's (keyframed, so they follow the sun), none are here.

## OKLab chroma per unit of shade-pull (the spike's constant: its sheet was tuned against it).
const PULL_CHROMA := 0.085
## A lit step keeps this share of the role's chroma (the spike's).
const LIT_CHROMA := 0.96
## The lit step's lightness ceiling.
const LIT_MAX_L := 0.985


## [shade0, mid0, lit0, shade1, mid1, lit1] (sRGB Colors) of `role` in `mood` at `elevation`:
## the dark-cool variant first. `ground` reads the ground's own ramp numbers.
static func ramp(
	sheet: Dictionary, mood: String, role: String, elevation: float, ground: bool = false
) -> Array[Color]:
	var base := PainterSheet.tone_lch(sheet, mood, role, elevation)
	var pre := "ground-" if ground else ""
	var hue_spread := PainterSheet.number(sheet, mood, pre + "hue-spread", elevation)
	var value_spread := PainterSheet.number(sheet, mood, pre + "value-spread", elevation)
	var shape := {
		"shade-hue": PainterSheet.number(sheet, mood, "shade-hue", elevation),
		"shade-pull": PainterSheet.number(sheet, mood, pre + "shade-pull", elevation),
		"shade-depth": PainterSheet.number(sheet, mood, pre + "shade-depth", elevation),
		"lit-hue": PainterSheet.number(sheet, mood, "lit-hue", elevation),
		"lit-pull": PainterSheet.number(sheet, mood, pre + "lit-pull", elevation),
		"lit-lift": PainterSheet.number(sheet, mood, pre + "lit-lift", elevation),
	}
	var out: Array[Color] = []
	for variant in 2:
		var side := float(variant) * 2.0 - 1.0
		var lch := Vector3(base.x + side * value_spread, base.y, base.z + side * hue_spread)
		for step: Vector3 in steps(lch, shape):
			out.append(PainterSheet.color_of_lch(step))
	return out


## [shade, mid, lit] OKLCH of the middle tone `lch` under the ramp numbers `shape` (the keys of
## ramp()'s dictionary). Pure.
static func steps(lch: Vector3, shape: Dictionary) -> Array[Vector3]:
	var hb := deg_to_rad(lch.z)
	var hs := deg_to_rad(float(shape["shade-hue"]))
	var pull := float(shape["shade-pull"]) * PULL_CHROMA
	var sa := lch.y * cos(hb) + pull * cos(hs)
	var sb := lch.y * sin(hb) + pull * sin(hs)
	var shade := Vector3(
		lch.x * float(shape["shade-depth"]),
		Vector2(sa, sb).length(),
		fposmod(rad_to_deg(atan2(sb, sa)), 360.0)
	)
	var lit := Vector3(
		minf(LIT_MAX_L, lch.x + float(shape["lit-lift"])),
		lch.y * LIT_CHROMA,
		_hue_toward(lch.z, float(shape["lit-hue"]), float(shape["lit-pull"]))
	)
	return [shade, lch, lit]


## The linear-light RGB of `c` as a shader's plain vec3 uniform wants it.
static func linear(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	return Vector3(lin.r, lin.g, lin.b)


## `ramp` (six sRGB colours) as six linear vec3s.
static func linear_ramp(colors: Array[Color]) -> PackedVector3Array:
	var out := PackedVector3Array()
	for c in colors:
		out.append(linear(c))
	return out


## `hue` turned `amount` (0..1) of the short way toward `target` (degrees).
static func _hue_toward(hue: float, target: float, amount: float) -> float:
	var delta := fposmod(target - hue + 180.0, 360.0) - 180.0
	return fposmod(hue + delta * clampf(amount, 0.0, 1.0), 360.0)
