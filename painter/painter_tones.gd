class_name PainterTones
extends RefCounted

## The painted surfaces' tone ramps, drawn from a sheet's role colours (docs/systems/painter.md
## "Surfaces"). Pure functions over a compiled sheet (PainterSheet.load_sheet), no scene tree.
##
## The model (the painter spike's PStyle4.tones, which the prototype's sheet tuned). A role's
## colour is the MIDDLE of three steps. Its SHADE is its lightness times `shade-depth`, its OKLab
## chroma vector scaled by `shade-keep` (1: all of it) and pulled toward the hue `shade-hue` by
## `shade-pull` (0.085 of chroma per unit), so every shade in a mood leans the same way (summer's
## blue-violet). A low keep with a small pull gives every role one shade family whatever its own
## hue (dusk's lilac); a full keep with a large pull swings a grey role to a saturated shade and a
## role opposite the shade hue to grey (painter-a1c read both as magenta paths and electric blue
## snow). Its LIT step is
## `lit-lift` lighter, a little less chroma, its hue pulled toward `lit-hue` by `lit-pull`. Each
## role has two VARIANTS, `value-spread` darker and lighter and `hue-spread` degrees either side,
## which a surface mixes between by a slow world noise so a field of one role is never one flat
## colour. A surface may read its own numbers under a prefix: the ground its `ground-` depth,
## keep, pulls, lift and spreads, grass and flowers their `grass-` keep, lit pull and lift (a high
## sun keeps a lawn green rather than lifting it to cream). A prefixed name the sheet's defaults
## do not list falls back to the plain one. All numbers are the sheet's (keyframed, so they follow
## the sun), none are here.

## OKLab chroma per unit of shade-pull (the spike's constant: its sheet was tuned against it).
const PULL_CHROMA := 0.085
## A lit step keeps this share of the role's chroma (the spike's).
const LIT_CHROMA := 0.96
## The lit step's lightness ceiling.
const LIT_MAX_L := 0.985


## [shade0, mid0, lit0, shade1, mid1, lit1] (sRGB Colors) of `role` in `mood` at `elevation`:
## the dark-cool variant first. `prefix` ("ground-", "grass-" or "") picks a surface's own ramp
## numbers where the sheet defines them.
static func ramp(
	sheet: Dictionary, mood: String, role: String, elevation: float, prefix: String = ""
) -> Array[Color]:
	var base := PainterSheet.tone_lch(sheet, mood, role, elevation)
	var num := func(name: String) -> float:
		var own := prefix + name
		var key := own if own in PainterSheet.DEFAULT_NUMBERS else name
		return PainterSheet.number(sheet, mood, key, elevation)
	var hue_spread: float = num.call("hue-spread")
	var value_spread: float = num.call("value-spread")
	var shape := {
		"shade-hue": num.call("shade-hue"),
		"shade-pull": num.call("shade-pull"),
		"shade-depth": num.call("shade-depth"),
		"shade-keep": num.call("shade-keep"),
		"lit-hue": num.call("lit-hue"),
		"lit-pull": num.call("lit-pull"),
		"lit-lift": num.call("lit-lift"),
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
	var own := lch.y * float(shape.get("shade-keep", 1.0))
	var sa := own * cos(hb) + pull * cos(hs)
	var sb := own * sin(hb) + pull * sin(hs)
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
