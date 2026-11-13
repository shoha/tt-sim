class_name PainterSheet
extends RefCounted

## The painted look's sheet: the tones of every mood, keyed by the sun's height (docs/systems/
## painter.md). Pure functions over plain data, no scene tree; the scene host (PainterScene) and
## the tests read it, later cards' ground, plant and building painters will too.
##
## The model. A sheet is text in the painter spike's dialect (comments /* */, `name: value;`
## declarations, colours as `oklch(L C H)` or `#rrggbb`, `var(--token)` references):
##   sheet := ( ":world" "{" decl* "}" | "@mood" name "{" world? key* "}" )*
##   key   := "@key" (high | low | night) elevation-degrees "{" decl* "}"
## A mood holds up to three keyframes, each a complete tone set for one sun height: `high` (a
## midday sun), `low` (the sun near the horizon) and `night` (the sun under it). The resolver
## blends the two keyframes either side of the level's sun elevation (smoothstep in elevation,
## then OKLCH by the short way round the hue circle), and holds the end keyframes past their
## elevations. The sun's DIRECTION is never in the sheet: the level's time of day or manual sun
## sets it, and the painter only reads its elevation (owner, 2026-11-12).
##
## Tones were tuned for one sun per mood in the spike and broke at other suns (cold front walls,
## magenta roofs at a low sun), so a mood needs all three keyframes; the moods in HIGH_ONLY are
## allowed one `high` keyframe for now and hold it at every sun until their own card.

## The moods a sheet must define (RenderStyle maps the environment presets onto them).
const MOODS: Array[String] = ["summer", "dusk", "grimdark", "winter", "autumn"]
## Moods allowed a single `high` keyframe until their own look card (the lint's allow-list).
const HIGH_ONLY: Array[String] = ["dusk", "grimdark", "winter", "autumn"]
## Keyframe names, lowest sun first.
const KEYS: Array[String] = ["night", "low", "high"]
## Colour roles every keyframe sets. The environment uses sun, sky, horizon, ambient and haze;
## the rest are the tones later cards paint the ground, plants, trees and roofs with.
const COLOR_ROLES: Array[String] = [
	"sun",
	"sky",
	"horizon",
	"ambient",
	"haze",
	"ground",
	"leaf",
	"bark",
	"stone",
	"path",
	"roof-clay",
	"roof-slate",
	"roof-shingle",
	"roof-turf",
	"roof-thatch",
]
## Number properties every keyframe sets: the sun's and the ambient light's energy.
const NUMBER_PROPS: Array[String] = ["sun-energy", "ambient-energy"]
## Below this OKLCH chroma a colour's hue is meaningless: a blend takes the other end's hue.
const GREY_CHROMA := 0.02
## The sheets the game ships, by id.
const SHEETS_DIR := "res://painter/sheets/"

static var _cache: Dictionary = {}


## The compiled sheet `id` (painter/sheets/<id>.sheet), parsed, linted and cached; {} with an
## error pushed when it is missing or fails the lint.
static func load_sheet(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := SHEETS_DIR + id + ".sheet"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("PainterSheet: cannot read %s" % path)
		return {}
	var parsed := parse(text)
	var errors := lint(parsed)
	if not errors.is_empty():
		push_error("PainterSheet: %s fails the lint: %s" % [path, "; ".join(errors)])
		return {}
	var compiled := compile(parsed)
	_cache[id] = compiled
	return compiled


## Forgets the loaded sheets (tests, and a sheet edited while the game runs).
static func clear_cache() -> void:
	_cache.clear()


## {"tokens": {name: value}, "moods": {name: {"tokens", "keys": {key: {"elevation", "props"}}}},
## "errors": [...]} from sheet text. Structure only; lint() checks the content.
static func parse(text: String) -> Dictionary:
	var out := {"tokens": {}, "moods": {}, "errors": []}
	for block: Dictionary in _blocks(_strip_comments(text), out["errors"]):
		var head: String = block["head"]
		if head == ":world":
			(out["tokens"] as Dictionary).merge(_decls(block["body"]), true)
		elif head.begins_with("@mood "):
			var mood_name := head.substr(6).strip_edges()
			out["moods"][mood_name] = _parse_mood(block["body"], out["errors"], mood_name)
		else:
			(out["errors"] as Array).append("unknown block: %s" % head)
	return out


## Everything wrong with a parsed sheet, as readable lines ([] when it is sound).
static func lint(parsed: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray(parsed.get("errors", []))
	var moods: Dictionary = parsed.get("moods", {})
	for mood_name: String in moods:
		if not MOODS.has(mood_name):
			errors.append("unknown mood: %s" % mood_name)
	for mood_name: String in MOODS:
		if not moods.has(mood_name):
			errors.append("missing mood: %s" % mood_name)
			continue
		var mood: Dictionary = moods[mood_name]
		var keys: Dictionary = mood["keys"]
		var needed: Array = ["high"] if HIGH_ONLY.has(mood_name) else KEYS
		for key_name: String in needed:
			if not keys.has(key_name):
				errors.append("%s: missing keyframe %s" % [mood_name, key_name])
		var last := -INF
		for key_name: String in KEYS:
			if not keys.has(key_name):
				continue
			var elevation: float = keys[key_name]["elevation"]
			if elevation <= last:
				errors.append("%s: keyframe %s is not above the one below it" % [mood_name, key_name])
			last = elevation
		for key_name: String in keys:
			if not KEYS.has(key_name):
				errors.append("%s: unknown keyframe %s" % [mood_name, key_name])
				continue
			var vars: Dictionary = (parsed.get("tokens", {}) as Dictionary).duplicate()
			vars.merge(mood["tokens"], true)
			_lint_key(keys[key_name]["props"], vars, "%s.%s" % [mood_name, key_name], errors)
	return errors


## The lint-clean parsed sheet as {mood: [{"elevation", "lch": {role: Vector3}, "numbers": {}}]},
## keyframes in ascending elevation.
static func compile(parsed: Dictionary) -> Dictionary:
	var out := {}
	var moods: Dictionary = parsed["moods"]
	for mood_name: String in moods:
		var mood: Dictionary = moods[mood_name]
		var vars: Dictionary = (parsed["tokens"] as Dictionary).duplicate()
		vars.merge(mood["tokens"], true)
		var frames: Array = []
		for key_name: String in KEYS:
			if not (mood["keys"] as Dictionary).has(key_name):
				continue
			var key: Dictionary = mood["keys"][key_name]
			var lch := {}
			var numbers := {}
			for role: String in COLOR_ROLES:
				lch[role] = parse_color(_resolve(str(key["props"][role]), vars))
			for prop: String in NUMBER_PROPS:
				numbers[prop] = _resolve(str(key["props"][prop]), vars).to_float()
			frames.append({"name": key_name, "elevation": key["elevation"], "lch": lch, "numbers": numbers})
		out[mood_name] = frames
	return out


## The sRGB colour of `role` in `mood` for a sun `elevation` degrees above the horizon.
static func tone(compiled: Dictionary, mood: String, role: String, elevation: float) -> Color:
	return color_of_lch(tone_lch(compiled, mood, role, elevation))


## The same tone as OKLCH (L, C, H in degrees).
static func tone_lch(compiled: Dictionary, mood: String, role: String, elevation: float) -> Vector3:
	var span := _span(compiled.get(mood, []), elevation)
	if span.is_empty():
		return Vector3(0.6, 0.0, 0.0)
	var a: Vector3 = span[0]["lch"][role]
	var b: Vector3 = span[1]["lch"][role]
	return lerp_lch(a, b, span[2])


## A number property of `mood` for a sun `elevation` degrees above the horizon.
static func number(compiled: Dictionary, mood: String, prop: String, elevation: float) -> float:
	var span := _span(compiled.get(mood, []), elevation)
	if span.is_empty():
		return 0.0
	return lerpf(float(span[0]["numbers"][prop]), float(span[1]["numbers"][prop]), span[2])


## Every role (sRGB Color) and number of `mood` at `elevation`, in one dictionary.
static func tones(compiled: Dictionary, mood: String, elevation: float) -> Dictionary:
	var out := {}
	for role: String in COLOR_ROLES:
		out[role] = tone(compiled, mood, role, elevation)
	for prop: String in NUMBER_PROPS:
		out[prop] = number(compiled, mood, prop, elevation)
	return out


# ---------------------------------------------------------------- colour (OKLCH)


## "oklch(L C H)" (L may be a percent) or "#rrggbb" as OKLCH; Vector3(-1, 0, 0) when neither.
static func parse_color(text: String) -> Vector3:
	var v := text.strip_edges()
	if v.begins_with("oklch(") and v.ends_with(")"):
		var parts := v.substr(6, v.length() - 7).split(" ", false)
		if parts.size() == 3 and parts[1].is_valid_float() and parts[2].is_valid_float():
			var lightness := parts[0]
			var chroma := parts[1].to_float()
			var hue := parts[2].to_float()
			if lightness.ends_with("%"):
				return Vector3(lightness.trim_suffix("%").to_float() * 0.01, chroma, hue)
			if lightness.is_valid_float():
				return Vector3(lightness.to_float(), chroma, hue)
	if v.begins_with("#") and v.length() == 7 and v.substr(1).is_valid_hex_number():
		return lch_of_color(Color.html(v))
	return Vector3(-1.0, 0.0, 0.0)


## The blend of two OKLCH colours: lightness and chroma straight, the hue the short way round
## (a near-grey end takes the other end's hue, as CSS treats a powerless hue).
static func lerp_lch(a: Vector3, b: Vector3, t: float) -> Vector3:
	var hue := a.z
	if a.y < GREY_CHROMA and b.y >= GREY_CHROMA:
		hue = b.z
	elif b.y >= GREY_CHROMA:
		hue = a.z + (fposmod(b.z - a.z + 180.0, 360.0) - 180.0) * t
	return Vector3(lerpf(a.x, b.x, t), lerpf(a.y, b.y, t), fposmod(hue, 360.0))


## OKLCH to OKLab.
static func oklab_of(lch: Vector3) -> Vector3:
	var h := deg_to_rad(lch.z)
	return Vector3(lch.x, lch.y * cos(h), lch.y * sin(h))


## An sRGB colour as OKLCH.
static func lch_of_color(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var l := _cbrt(0.4122214708 * lin.r + 0.5363325363 * lin.g + 0.0514459929 * lin.b)
	var m := _cbrt(0.2119034982 * lin.r + 0.6806995451 * lin.g + 0.1073969566 * lin.b)
	var s := _cbrt(0.0883024619 * lin.r + 0.2817188376 * lin.g + 0.6299787005 * lin.b)
	var big_l := 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
	var a := 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
	var b := 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
	return Vector3(big_l, Vector2(a, b).length(), fposmod(rad_to_deg(atan2(b, a)), 360.0))


## OKLCH to an sRGB Color, clipped into the gamut channel by channel.
static func color_of_lch(lch: Vector3) -> Color:
	var lab := oklab_of(lch)
	var l := pow(lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z, 3.0)
	var m := pow(lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z, 3.0)
	var s := pow(lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z, 3.0)
	var r := 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
	var g := -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
	var bl := -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
	return Color(clampf(r, 0.0, 1.0), clampf(g, 0.0, 1.0), clampf(bl, 0.0, 1.0)).linear_to_srgb()


# ---------------------------------------------------------------- internals


static func _cbrt(x: float) -> float:
	return signf(x) * pow(absf(x), 1.0 / 3.0)


## [frame below, frame above, blend 0..1] for `elevation` over ascending `frames`; [] for none.
static func _span(frames: Array, elevation: float) -> Array:
	if frames.is_empty():
		return []
	if elevation <= float(frames[0]["elevation"]):
		return [frames[0], frames[0], 0.0]
	for i in range(frames.size() - 1):
		var lo: float = frames[i]["elevation"]
		var hi: float = frames[i + 1]["elevation"]
		if elevation < hi:
			return [frames[i], frames[i + 1], smoothstep(0.0, 1.0, (elevation - lo) / (hi - lo))]
	var last: Dictionary = frames[frames.size() - 1]
	return [last, last, 0.0]


static func _parse_mood(body: String, errors: Array, mood_name: String) -> Dictionary:
	var mood := {"tokens": {}, "keys": {}}
	for block: Dictionary in _blocks(body, errors):
		var head: String = block["head"]
		if head == ":world":
			(mood["tokens"] as Dictionary).merge(_decls(block["body"]), true)
			continue
		var parts := head.split(" ", false)
		if parts.size() != 3 or parts[0] != "@key" or not parts[2].is_valid_float():
			errors.append("%s: bad block: %s" % [mood_name, head])
			continue
		mood["keys"][parts[1]] = {"elevation": parts[2].to_float(), "props": _decls(block["body"])}
	return mood


## [{"head", "body"}] for each top-level `head { body }` in `text` (nested braces kept whole).
static func _blocks(text: String, errors: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var i := 0
	while true:
		var open := text.find("{", i)
		if open < 0:
			if not text.substr(i).strip_edges().is_empty():
				errors.append("text outside a block: %s" % text.substr(i).strip_edges().left(40))
			break
		var depth := 1
		var j := open + 1
		while depth > 0 and j < text.length():
			var ch := text[j]
			if ch == "{":
				depth += 1
			elif ch == "}":
				depth -= 1
			j += 1
		if depth > 0:
			errors.append("unclosed block: %s" % text.substr(i, open - i).strip_edges())
			break
		var head := text.substr(i, open - i).strip_edges()
		out.append({"head": head, "body": text.substr(open + 1, j - open - 2)})
		i = j
	return out


static func _decls(body: String) -> Dictionary:
	var out := {}
	for decl: String in body.split(";", false):
		var colon := decl.find(":")
		if colon > 0:
			out[decl.substr(0, colon).strip_edges()] = decl.substr(colon + 1).strip_edges()
	return out


static func _strip_comments(text: String) -> String:
	var out := ""
	var i := 0
	while true:
		var a := text.find("/*", i)
		if a < 0:
			out += text.substr(i)
			break
		out += text.substr(i, a - i)
		var b := text.find("*/", a + 2)
		if b < 0:
			break
		i = b + 2
	return out


## `value` with every var(--token) replaced from `vars` (unknown tokens stay as written).
static func _resolve(value: String, vars: Dictionary) -> String:
	var v := value
	for _guard in 8:
		var a := v.find("var(")
		if a < 0:
			break
		var b := v.find(")", a)
		if b < 0:
			break
		var token := v.substr(a + 4, b - a - 4).strip_edges()
		if not vars.has(token):
			break
		v = v.substr(0, a) + str(vars[token]) + v.substr(b + 1)
	return v


static func _lint_key(
	props: Dictionary, vars: Dictionary, where: String, errors: PackedStringArray
) -> void:
	for prop: String in props:
		if not COLOR_ROLES.has(prop) and not NUMBER_PROPS.has(prop):
			errors.append("%s: unknown role %s" % [where, prop])
	for role: String in COLOR_ROLES:
		if not props.has(role):
			errors.append("%s: missing role %s" % [where, role])
		elif parse_color(_resolve(str(props[role]), vars)).x < 0.0:
			errors.append("%s: %s is not a colour: %s" % [where, role, props[role]])
	for prop: String in NUMBER_PROPS:
		if not props.has(prop):
			errors.append("%s: missing %s" % [where, prop])
		elif not _resolve(str(props[prop]), vars).is_valid_float():
			errors.append("%s: %s is not a number: %s" % [where, prop, props[prop]])
