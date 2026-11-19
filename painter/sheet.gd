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
## magenta roofs at a low sun), so a mood needs all three keyframes; a mood in HIGH_ONLY would be
## allowed one `high` keyframe and hold it at every sun (none is, since card A1b).
##
## Defaults. A keyframe must set every COLOR_ROLES and NUMBER_PROPS entry. The DEFAULT_ROLES and
## DEFAULT_NUMBERS (the ground's and the plants' extra tones, the tone ramp, the thinning) may
## instead come from a declaration of the same name, without `--`, in the mood's `:world` block,
## else in the sheet's: keyframe, then mood, then sheet. The lint checks each resolves.

## The moods a sheet must define (RenderStyle maps the environment presets onto them).
const MOODS: Array[String] = ["summer", "dusk", "grimdark", "winter", "autumn"]
## Moods allowed a single `high` keyframe until their own look card (the lint's allow-list).
const HIGH_ONLY: Array[String] = []
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
## Colour roles a keyframe may leave to a `:world` default (see the header): the ground's forest
## floor and shore, the grass, the ground's pale drift and fallen-leaf marks, the four flower
## accents (PainterSurfaces paints with them), the conifers' needles and a bare season's clinging
## dry leaves (PainterTreeTones), and the
## buildings' walls and timber (PainterBuildings: plaster, a stone wall, log and board walls, the
## beams, frames and doors) and the water's (PainterWater: the three depth bands of the wash, the
## lighter and the darker stroke, the white water, the sun's glint and the ice).
const DEFAULT_ROLES: Array[String] = [
	"needle",
	"plaster",
	"wall-stone",
	"wall-log",
	"wall-boards",
	"timber",
	"floor",
	"shore",
	"grass",
	"drift",
	"litter",
	"flower-gold",
	"flower-rose",
	"flower-violet",
	"flower-white",
	"flower-red",
	"flower-blue",
	"dry-leaf",
	"water-shallow",
	"water-mid",
	"water-deep",
	"water-lit",
	"water-shade",
	"water-foam",
	"water-glint",
	"water-ice",
]
## Numbers a keyframe may leave to a `:world` default. The tone ramp (PainterTones.ramp: how a
## role's shade and lit colours are drawn from it, the ground's own ramp under `ground-`), the
## plants' light steps (tone-lo, tone-hi, N.L thresholds), the thinning of grass and flowers in
## groups (keep-*: the share kept, keep-freq-*: 1/m of the world noise that groups them), the
## flowers' colour groups (flower-mix, 1/m), and the ground's brush marks (marks: the share of
## cells that hold one, mark-thin: how far a flat area thins them, drift-marks and litter-marks:
## how much of the small marks, patches: the block-in's variation, mark-px-*: the pixel footprints
## in metres between which a mark fades out, cut: the shadow step's wiggle). The painted trees'
## own (PainterTreeTones): a crown's shade hue, pull and keep and lit pull and a stem's shade pull
## and keep in place of the species' (crown-*, bark-*), how much less deep a stem's shade is than
## a role's (bark-shade-lift), a crown's lit step's extra lift and chroma factor and its shade's
## extra lift (crown-lit-lift, crown-lit-chroma, crown-shade-lift), the share of a crown's up side
## the frost deposit takes (crown-deposit), the share of a broadleaf's leaf clumps it keeps
## (leaf-keep, 1 in leaf; each species falls by its leaf role's `fall` from tree_roles.json), how
## far a crown's kept leaves turn to the `dry-leaf` colour (leaf-turn) and how much less deep a
## turned leaf's shade is (dry-shade-lift: the share of its lightness it keeps more), how much of
## its own chroma it keeps and how far it pulls to the crowns' shade hue (dry-shade-keep,
## dry-shade-pull), how much heavier the snow lies on a conifer's boughs
## (needle-snow, times its `settle`), the share of the leaf's lightness and chroma a bush takes
## on the crowns' ramp (bush-value, bush-chroma), and how far a sun's cast shadow steps a
## tree into its cool tint (tree-cast).
## The buildings' (PainterBuildings), all relative to the mood's ramp so one value
## serves every mood and sun: walls' shade hue turned from the mood's shade-hue (wall-shade-turn,
## degrees), their pull as a share of its shade-pull (wall-pull, stone walls and chimneys
## stone-pull) and their shade that much less deep (wall-shade-lift); the roofs' pull share and
## lift (roof-pull, roof-shade-lift); timber's
## own turn and pull share (timber-shade-turn, timber-pull: a brown turned toward the violet
## shade goes the short way through red to maroon); and the share of the mood's lit-lift and
## lit-pull every building role takes (building-lit: a pale wall under the full lift is white);
## and how much of a roof lies under snow (roof-snow, 0 to 1, in the drift role's colour).
## The biome tones derived from a keyframed role (PainterGroundRoles.DERIVED, card
## painter-coverage): per name a target hue (degrees), a chroma factor and a lightness shift, so
## a dry biome's straw, an ash ground and a baked earth follow the mood and the sun the role they
## come from follows: dry- from `ground`, drygrass- from `grass`, ash- from `stone`, earth- from
## `path`.
## The water's (PainterWater, painter_water.gdshader): the share of the stroke lattice's cells that
## hold a stroke (water-strokes), a stroke's length in metres (water-stroke-len), its boil's period
## in seconds (water-boil), how much of the sun's side glints (water-glints), the wash's deepest
## alpha (water-opacity), the shore ribbon's width in metres (water-foam-width) and how far still
## water freezes (ice-over, 0 to 1: winter's).
const DEFAULT_NUMBERS: Array[String] = [
	"shade-hue",
	"shade-pull",
	"shade-depth",
	"shade-keep",
	"lit-hue",
	"lit-pull",
	"lit-lift",
	"hue-spread",
	"value-spread",
	"ground-shade-pull",
	"ground-shade-depth",
	"ground-shade-keep",
	"ground-lit-pull",
	"ground-lit-lift",
	"grass-shade-keep",
	"grass-lit-pull",
	"grass-lit-lift",
	"grass-hue-spread",
	"grass-value-spread",
	"ground-hue-spread",
	"ground-value-spread",
	"tone-lo",
	"tone-hi",
	"keep-grass",
	"keep-flower",
	"keep-freq-grass",
	"keep-freq-flower",
	"flower-mix",
	"marks",
	"occ-pool",
	"occ-core",
	"occ-dark",
	"occ-soil",
	"occ-cool",
	"occ-shade",
	"base-dark",
	"mark-thin",
	"drift-marks",
	"litter-marks",
	"patches",
	"mark-px-lo",
	"mark-px-hi",
	"cut",
	"crown-shade-hue",
	"crown-shade-pull",
	"crown-shade-keep",
	"crown-lit-pull",
	"crown-lit-lift",
	"crown-lit-chroma",
	"crown-shade-lift",
	"crown-deposit",
	"leaf-keep",
	"leaf-turn",
	"dry-shade-lift",
	"dry-shade-keep",
	"dry-shade-pull",
	"needle-snow",
	"bush-value",
	"bush-chroma",
	"bark-shade-pull",
	"bark-shade-keep",
	"bark-shade-lift",
	"tree-cast",
	"wall-shade-turn",
	"wall-pull",
	"stone-pull",
	"wall-shade-lift",
	"roof-pull",
	"roof-shade-lift",
	"timber-shade-turn",
	"timber-pull",
	"building-lit",
	"roof-snow",
	"dry-hue",
	"dry-chroma",
	"dry-lift",
	"drygrass-hue",
	"drygrass-chroma",
	"drygrass-lift",
	"ash-hue",
	"ash-chroma",
	"ash-lift",
	"earth-hue",
	"earth-chroma",
	"earth-lift",
	"cactus-hue",
	"cactus-chroma",
	"cactus-lift",
	"charcoal-hue",
	"charcoal-chroma",
	"charcoal-lift",
	"crossing-turn",
	"crossing-chroma",
	"crossing-value",
	"water-strokes",
	"water-stroke-len",
	"water-boil",
	"water-glints",
	"water-opacity",
	"water-foam-width",
	"ice-over",
]
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
		_lint_defaults(mood["tokens"], mood_name, errors)
	_lint_defaults(parsed.get("tokens", {}), ":world", errors)
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
			for role: String in COLOR_ROLES + DEFAULT_ROLES:
				lch[role] = parse_color(_resolve(_prop(key["props"], vars, role), vars))
			for prop: String in NUMBER_PROPS + DEFAULT_NUMBERS:
				numbers[prop] = _resolve(_prop(key["props"], vars, prop), vars).to_float()
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
	for role: String in COLOR_ROLES + DEFAULT_ROLES:
		out[role] = tone(compiled, mood, role, elevation)
	for prop: String in NUMBER_PROPS + DEFAULT_NUMBERS:
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


## A keyframe's `name`: its own declaration, else the `:world` default of that name ("" if none).
static func _prop(props: Dictionary, vars: Dictionary, name: String) -> String:
	return str(props.get(name, vars.get(name, "")))


static func _lint_key(
	props: Dictionary, vars: Dictionary, where: String, errors: PackedStringArray
) -> void:
	var roles: Array[String] = COLOR_ROLES + DEFAULT_ROLES
	var numbers: Array[String] = NUMBER_PROPS + DEFAULT_NUMBERS
	for prop: String in props:
		if not roles.has(prop) and not numbers.has(prop):
			errors.append("%s: unknown role %s" % [where, prop])
	for role: String in roles:
		var value := _prop(props, vars, role)
		if value.is_empty():
			errors.append("%s: missing role %s" % [where, role])
		elif parse_color(_resolve(value, vars)).x < 0.0:
			errors.append("%s: %s is not a colour: %s" % [where, role, value])
	for prop: String in numbers:
		var value := _prop(props, vars, prop)
		if value.is_empty():
			errors.append("%s: missing %s" % [where, prop])
		elif not _resolve(value, vars).is_valid_float():
			errors.append("%s: %s is not a number: %s" % [where, prop, value])


## A `:world` block's declarations: `--name` tokens, or defaults named after a DEFAULT_ROLES or
## DEFAULT_NUMBERS entry; anything else is a typo.
static func _lint_defaults(tokens: Dictionary, where: String, errors: PackedStringArray) -> void:
	for name: String in tokens:
		if not name.begins_with("--") and not (DEFAULT_ROLES + DEFAULT_NUMBERS).has(name):
			errors.append("%s: unknown default %s" % [where, name])
