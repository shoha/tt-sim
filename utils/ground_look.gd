class_name GroundLook
extends RefCounted

## A biome's ground look (contract: docs/ASSET_PIPELINE.md section 9, "Ground look and grass
## masses"): the colour zones, the painted light, the grass-mass shading, the rim and the accent
## shape a biome's `ground_look` asks for. tt-sim holds every base value (BASE, the contract
## table's Base column); a palette's `ground_look` carries only the biome's overrides of them, so
## each value lives once. validate() merges a biome's overrides over BASE under the consumer's
## lenient rules (an unknown key or a wrong type warns and keeps the base value, an out-of-range
## value is clamped, a look without zones.colors_linear warns and is ignored), so the merged look
## always holds every key. PaletteLibrary keeps it on the biome; a biome without one (and every
## event biome) has {} and draws today's ground and grass.
##
## Colours are linear, as the shaders take them; angles are radians; triples are RGB colours or
## per-zone values (zones 1 to 3). The scatter reads only the zone shapes, strokes and accent
## shape (GroundZones.record); the ground shader's uniforms come from the same merged look.

## Every contract key with its base value. ref_surface and zones.colors_linear are required
## (they have no base): "" and [] here stand for absent and validate() fills them.
const BASE := {
	"ref_surface": "",
	"zones":
	{
		"colors_linear": [],
		"strength": 1.0,
		"cover": [0.0, 0.0, 0.0],
		"scale_m": [12.0, 9.0, 6.0],
		"edge": [0.045, 0.04, 0.035],
		"stretch": 1.0,
		"stretch_k": [1.0, 1.0, 1.0],
		"angle": 0.0,
		"angle_k": [0.0, 0.0, 0.0],
		"warp": 0.55,
		"rag": 0.12,
		"rag_m": 2.2,
		"nest": 0.0,
		"edge_vary": 0.4,
		"edge_vary_m": 24.0,
		"shade_warm": [1.04, 0.92, 0.84],
		"oklab": 2.0,
		"layers": [],
	},
	"strokes":
	{
		"on": 1.0,
		"m": 1.6,
		"len": 3.5,
		"edge": 5.0,
		"soft_lo": 0.08,
		"soft_hi": 0.3,
		"soft_m": 9.0,
	},
	"brush": {"contrast": 0.4, "hue": 0.08, "key": 0.85, "mean": 0.0},
	"light":
	{
		"strength": 1.0,
		"key": 1.0,
		"scale_m": 6.0,
		"cover": 0.32,
		"lift": 0.36,
		"lit_tint": [1.03, 1.0, 0.86],
		"shade": 0.36,
		"shade_tint": [0.96, 0.99, 0.98],
		"streak": 0.04,
		"streak_m": 2.2,
		"streak_stretch": 3.0,
		"streak_angle": 0.5,
		"streak_ripple": 0.0,
		"streak_cover": 0.6,
		"knee": 0.5,
		"cap": 0.85,
		"sat_cap": 0.88,
		"broad": 0.35,
		"stretch": 1.0,
		"crisp": 0.35,
		"ripple_curve": 0.0,
	},
	"tuft":
	{
		"strength": 1.0,
		"step": 2.35,
		"contrast": 0.7,
		"hue": 0.3,
		"knee": 0.55,
		"cap": 0.82,
		"capped": 1.0,
	},
	"mass":
	{
		"step": 1.18,
		"sat": 1.25,
		"lit": 0.25,
		"lit_m": 2.0,
		"contrast": 0.3,
		"base": 0.7,
		"tip": 1.25,
		"h_m": 0.8,
		"own": 0.0,
		"up_pow": 1.0,
		"shade": 0.12,
		"shade_size": 0.9,
		"shade_push": 0.9,
		"lift": 0.03,
		"lift_size": 1.0,
		"lift_push": 0.25,
	},
	"rim":
	{
		"surfaces": [],
		"accent_rim_m": 0.15,
		"path_rim_m": 0.2,
		"strength": 0.6,
		"wobble": 0.6,
		"gap": 0.45,
		"path_blend_width": 0.06,
		"color_linear": [0.1789, 0.0835, 0.0174],
		"accent_core_m": 0.0,
		"core_dark": 0.0,
		"accent_tint": [1.0, 1.0, 1.0],
	},
	"accent_shape": {"stretch": 1.8, "stretch_angle": 0.6, "break": 0.4, "edge_scale": 1.0},
}

## The contract's ranges, as [low, high] per "group.key" (a triple clamps each value). A key not
## listed takes any finite value. "> 0" is held at POSITIVE.
const POSITIVE := 0.0001
const UNIT := [0.0, 1.0]
const OVER_ZERO := [POSITIVE, INF]
const AT_LEAST_ZERO := [0.0, INF]
const AT_LEAST_ONE := [1.0, INF]
const RANGES := {
	"zones.colors_linear": UNIT,
	"zones.strength": UNIT,
	"zones.cover": UNIT,
	"zones.scale_m": OVER_ZERO,
	"zones.edge": OVER_ZERO,
	"zones.stretch": AT_LEAST_ONE,
	"zones.stretch_k": OVER_ZERO,
	"zones.warp": AT_LEAST_ZERO,
	"zones.rag": UNIT,
	"zones.rag_m": OVER_ZERO,
	"zones.nest": UNIT,
	"zones.edge_vary": UNIT,
	"zones.edge_vary_m": OVER_ZERO,
	"zones.shade_warm": OVER_ZERO,
	"zones.oklab": [0.0, 2.0],
	"strokes.on": UNIT,
	"strokes.m": OVER_ZERO,
	"strokes.len": AT_LEAST_ONE,
	"strokes.edge": AT_LEAST_ONE,
	"strokes.soft_lo": UNIT,
	"strokes.soft_hi": UNIT,
	"strokes.soft_m": OVER_ZERO,
	"brush.contrast": AT_LEAST_ZERO,
	"brush.hue": UNIT,
	"brush.key": AT_LEAST_ZERO,
	"brush.mean": AT_LEAST_ZERO,
	"light.strength": UNIT,
	"light.key": OVER_ZERO,
	"light.scale_m": OVER_ZERO,
	"light.cover": UNIT,
	"light.lift": AT_LEAST_ZERO,
	"light.lit_tint": OVER_ZERO,
	"light.shade": UNIT,
	"light.shade_tint": OVER_ZERO,
	"light.streak": AT_LEAST_ZERO,
	"light.streak_m": OVER_ZERO,
	"light.streak_stretch": AT_LEAST_ONE,
	"light.streak_ripple": UNIT,
	"light.streak_cover": UNIT,
	"light.knee": UNIT,
	"light.cap": UNIT,
	"light.sat_cap": UNIT,
	"light.broad": UNIT,
	"light.stretch": AT_LEAST_ONE,
	"light.crisp": UNIT,
	"light.ripple_curve": UNIT,
	"tuft.strength": UNIT,
	"tuft.step": OVER_ZERO,
	"tuft.contrast": AT_LEAST_ZERO,
	"tuft.hue": UNIT,
	"tuft.knee": UNIT,
	"tuft.cap": UNIT,
	"tuft.capped": UNIT,
	"mass.step": OVER_ZERO,
	"mass.sat": OVER_ZERO,
	"mass.lit": UNIT,
	"mass.lit_m": OVER_ZERO,
	"mass.base": OVER_ZERO,
	"mass.tip": OVER_ZERO,
	"mass.h_m": OVER_ZERO,
	"mass.own": UNIT,
	"mass.up_pow": OVER_ZERO,
	"mass.shade": [0.0, 0.9],
	"mass.shade_size": OVER_ZERO,
	"mass.shade_push": AT_LEAST_ZERO,
	"mass.lift": [0.0, 0.2],
	"mass.lift_size": OVER_ZERO,
	"mass.lift_push": AT_LEAST_ZERO,
	"rim.accent_rim_m": AT_LEAST_ZERO,
	"rim.path_rim_m": AT_LEAST_ZERO,
	"rim.strength": UNIT,
	"rim.wobble": UNIT,
	"rim.gap": UNIT,
	"rim.path_blend_width": AT_LEAST_ZERO,
	"rim.color_linear": UNIT,
	"rim.accent_core_m": AT_LEAST_ZERO,
	"rim.core_dark": UNIT,
	"rim.accent_tint": OVER_ZERO,
	"accent_shape.stretch": AT_LEAST_ONE,
	"accent_shape.break": UNIT,
	"accent_shape.edge_scale": OVER_ZERO,
}
## Surface lists and the roles their names must have.
const SURFACE_LISTS := {"zones.layers": ["ground"], "rim.surfaces": ["ground", "built"]}
## At most this many names in a surface list, and three or four zone colours.
const MAX_SURFACES := 4
const MIN_COLORS := 3
const MAX_COLORS := 4


## The merged look of a palette biome (validate()'s result, kept by PaletteLibrary), or {} when
## the biome has none.
static func for_biome(biome_id: String, root: String = PaletteLibrary.DEFAULT_ROOT) -> Dictionary:
	return PaletteLibrary.ground_look(biome_id, root)


## A biome's `ground_look` (raw JSON) merged over BASE under the consumer's lenient rules, or {}
## when it is absent, not an object or has no usable zones.colors_linear (the biome then draws
## today's ground). `ground` is the biome's ground surface, the fallback for a missing or
## unusable ref_surface; `surfaces` is the palette's surface table (name -> {role, ...}).
static func validate(
	raw: Variant, biome_id: String, ground: String, surfaces: Dictionary, warnings: Array[String]
) -> Dictionary:
	if raw == null:
		return {}
	var where := "biome '%s' ground_look" % biome_id
	if not raw is Dictionary:
		warnings.append("%s is not an object, ignored" % where)
		return {}
	var zones_raw: Variant = raw.get("zones")
	var colors := _colors(zones_raw.get("colors_linear") if zones_raw is Dictionary else null)
	if colors.is_empty():
		warnings.append("%s has no usable zones.colors_linear, ignored" % where)
		return {}
	var look: Dictionary = BASE.duplicate(true)
	for group in raw:
		if group == "ref_surface":
			continue
		if not BASE.get(group) is Dictionary or not raw[group] is Dictionary:
			warnings.append("%s: unknown or malformed '%s' ignored" % [where, str(group)])
			continue
		for key in raw[group]:
			var name := "%s.%s" % [group, str(key)]
			if name == "zones.colors_linear":
				continue
			if not (BASE[group] as Dictionary).has(key):
				warnings.append("%s: unknown key '%s' ignored" % [where, name])
				continue
			var value: Variant = _value(raw[group][key], BASE[group][key], name, surfaces)
			if value == null:
				warnings.append("%s: %s has the wrong type, using the base value" % [where, name])
				continue
			if value is Array and SURFACE_LISTS.has(name) and value.size() < raw[group][key].size():
				warnings.append("%s: %s names a surface that does not resolve, dropped" % [where, name])
			look[group][key] = value
	look.zones.colors_linear = colors
	look.ref_surface = _ref_surface(raw.get("ref_surface"), ground, surfaces, where, warnings)
	return look


## The ref_surface name when it is a ground surface, else (with a warning) the biome's ground.
static func _ref_surface(
	value: Variant, ground: String, surfaces: Dictionary, where: String, warnings: Array[String]
) -> String:
	if value is String and _role_of(surfaces, value) == "ground":
		return value
	warnings.append("%s: ref_surface missing or not a ground surface, using '%s'" % [where, ground])
	return ground


## Three or four [r, g, b] colours clamped to 0..1, or [] when `value` is not that shape.
static func _colors(value: Variant) -> Array:
	if not value is Array or value.size() < MIN_COLORS or value.size() > MAX_COLORS:
		return []
	var out := []
	for color: Variant in value:
		var rgb: Variant = _numbers(color, 3, UNIT)
		if rgb == null:
			return []
		out.append(rgb)
	return out


## `value` in the shape of `base` (a number, a numeric array of base's length, or a surface list)
## clamped to the range of `name`, or null when its type is wrong.
static func _value(value: Variant, base: Variant, name: String, surfaces: Dictionary) -> Variant:
	var limits: Array = RANGES.get(name, [-INF, INF])
	if SURFACE_LISTS.has(name):
		if not value is Array or value.size() > MAX_SURFACES:
			return null
		var kept := []
		for item: Variant in value:
			if item is String and _role_of(surfaces, item) in SURFACE_LISTS[name] and not item in kept:
				kept.append(item)
		return kept
	if base is Array:
		return _numbers(value, base.size(), limits)
	return _number(value, limits)


## `count` finite numbers clamped to `limits`, or null.
static func _numbers(value: Variant, count: int, limits: Array) -> Variant:
	if not value is Array or value.size() != count:
		return null
	var out := []
	for item: Variant in value:
		var number: Variant = _number(item, limits)
		if number == null:
			return null
		out.append(number)
	return out


## A finite number clamped to `limits`, or null.
static func _number(value: Variant, limits: Array) -> Variant:
	if value is bool or not (value is float or value is int):
		return null
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return null
	return clampf(number, float(limits[0]), float(limits[1]))


static func _role_of(surfaces: Dictionary, name: String) -> String:
	var entry: Variant = surfaces.get(name)
	return String(entry.get("role", "")) if entry is Dictionary else ""
