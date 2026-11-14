class_name PainterTreeTones
extends RefCounted
## The painted trees' colours and stroke manner as the two textures the tree shaders read
## (docs/systems/painter.md "Trees"). Pure static functions over a compiled sheet
## (PainterSheet.load_sheet) and tree_roles.json (each species' role props as the painterspike
## sheet resolved them, and that sheet's world defaults).
##
## A STYLE ROW is one (species, role) style. The rows: 0 the deposit (snow), 1 the ground, then
## per species (PainterTreeSpecies.names() order) its leaf, bark and trim and, for a conifer, its
## evergreen. role_rows() says which row each of a tree's nine roles uses (the row map's columns
## 0..8: leaf, bark, stone, wall, roof, trim, ground, deposit, evergreen).
##
## palette (TONES wide, MAX_ROWS x VARIANTS high, RGBA8 sRGB): per row and variant v (value and
## hue spread by -1, -1/3, 1/3, 1), the tones shade -> mid -> lit lerped in OKLab, shade, mid and
## lit from PainterTones.steps. role_params (MAX_ROWS x PARAM_ROWS, RGBAF): the spike's PStyle6
## layout (size, aspect, brush, density), (align, lift, jitter, size-var), (patch-mix, patch-freq,
## settle, blockin), (hang, sky, layer, rise), (mark, mark-value, mark-turn + 2 mark-trim,
## mark-size), (cap, far, mark-brush, mark-aspect), (grain, fill, 0, 0).
##
## Colours follow the sheet. A species keeps its own colour (the spike's tuned birch, oak,
## spruce, ...), moved by how far the sheet's role at the level's mood and sun stands from the
## spike world's colour of that role (SPIKE_ROLE, the one the species were tuned against):
## lightness and chroma by their ratio (so a dark mood narrows the species' spread rather than
## pushing the darkest to black; a chroma gain above 1 by its square root, so a pale birch does
## not go neon), hue the short way round, by less as the sheet's colour greys.
## So the species never share one green, and each moves the way the sheet moves the plants.
##
## The ramp. A species keeps its own shade depth and lit numbers, moved by the sheet's ramp
## numbers' difference from its summer midday (REFERENCE). Its shade's hue, pull and keep are
## the sheet's: a crown's (leaf, evergreen) `crown-shade-*` (and its lit step leans toward the
## mood's `lit-hue` by `crown-lit-pull`, `crown-lit-lift` lighter and `crown-lit-chroma` times
## as rich, keyframed by the sun so a low sun gilds a crown's lit side; its shade
## `crown-shade-lift` less deep), a stem's (bark, trim) the mood's `shade-hue` with
## `bark-shade-pull` and `-keep`, its depth `bark-shade-lift` less. painter-a2a3 found the spike's
## per-species pulls (oak 1.1, world 1.0, toward 305) cancelling a green crown's chroma to grey
## and swinging brown bark to maroon; the prototype's crowns shade to a deep teal green, and its
## stems (painter-a2a4) shade to their own warm brown a step under the lit side.

const DATA := "res://painter/trees/tree_roles.json"
const TONES := 32
const VARIANTS := 4
const MAX_ROWS := 64
const PARAM_ROWS := 7
const DEPOSIT_ROW := 0
const GROUND_ROW := 1
## The row map's role columns (the spike's PStyle4.ROLE_NAMES).
const ROLE_NAMES: Array[String] = [
	"leaf", "bark", "stone", "wall", "roof", "trim", "ground", "deposit", "evergreen"
]
## The sheet role each tree role follows, and the spike world colour it was tuned against.
const SHEET_ROLE := {"leaf": "leaf", "bark": "bark", "trim": "bark", "evergreen": "needle"}
const SPIKE_ROLE := {"leaf": "--leaf", "bark": "--bark", "trim": "--bark", "evergreen": "--needle"}
## The sheet prefix of each tree role's shade numbers (a crown's or a stem's).
const SHADE_PREFIX := {"leaf": "crown-", "evergreen": "crown-", "bark": "bark-", "trim": "bark-"}
## Below this sheet chroma a role's hue no longer moves a species' hue (the move fades to 0).
const HUE_CHROMA := 0.04
## The share of crown-lit-pull a conifer's needles take (painter-trees-polish: a dark, low-chroma
## needle turned fully toward the dusk sun's hue read as a flat khaki slab).
const NEEDLE_LIT_SHARE := 0.5
## The sheet keyframe the species' own colours stand for.
const REFERENCE := {"mood": "summer", "elevation": 60.0}
const SHAPE_KEYS: Array[String] = [
	"shade-hue", "shade-pull", "shade-depth", "lit-hue", "lit-pull", "lit-lift"
]
## Brush names (PainterTreeBrushes' layers).
const BRUSHES := {
	"round": 0.0,
	"dry": 1.0,
	"flat": 2.0,
	"lobed": 3.0,
	"scale": 4.0,
	"flick": 5.0,
	"spray": 6.0,
	"tuft": 7.0,
	"strand": 8.0,
	"bloom": 9.0,
	"edge": 10.0,
	"block": 11.0,
	"thatch": 12.0
}

## The role_params rows: four (key, fallback) per row; "" is a constant 0 (mark-turn's texel adds
## twice mark-trim).
const PARAMS: Array = [
	[["stroke", 0.5], ["aspect", 1.5], ["brush", 0.0], ["density", 1.0]],
	[["align", 0.0], ["lift", 0.1], ["jitter", 0.15], ["size-var", 0.3]],
	[["patch-mix", 0.6], ["patch-freq", 0.3], ["settle", 0.0], ["blockin", 1.0]],
	[["hang", 0.0], ["sky", 0.0], ["layer", 0.0], ["rise", 0.0]],
	[["mark", 0.0], ["mark-value", 1.0], ["mark-turn", 0.0], ["mark-size", 1.0]],
	[["cap", 0.0], ["far", 0.0], ["mark-brush", -1.0], ["mark-aspect", 0.0]],
	[["grain", 0.0], ["fill", 0.0], ["", 0.0], ["", 0.0]],
]

static var _data: Dictionary = {}


## tree_roles.json (loaded once).
static func data() -> Dictionary:
	if _data.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA))
		if parsed is Dictionary:
			_data = parsed
	return _data


## The tree roles `species` paints, in row order.
static func roles_of(species: String) -> Array[String]:
	var out: Array[String] = ["leaf", "bark", "trim"]
	if ((data()["species"] as Dictionary)[species] as Dictionary).has("evergreen"):
		out.append("evergreen")
	return out


## species -> {role -> style row} for every species, the bushes (PainterTreeSpecies.BUSHES) last
## (pure in the data).
static func row_table() -> Dictionary:
	var table := {}
	var row := GROUND_ROW + 1
	for species in PainterTreeSpecies.names() + PainterTreeSpecies.BUSHES:
		var rows := {}
		for role in roles_of(species):
			rows[role] = row
			row += 1
		table[species] = rows
	return table


## The nine role rows (ROLE_NAMES order) of a tree of `species`; unused roles take row 0.
static func role_rows(species: String) -> PackedInt32Array:
	var rows: Dictionary = row_table().get(species, {})
	var out := PackedInt32Array()
	out.resize(ROLE_NAMES.size())
	for i in ROLE_NAMES.size():
		out[i] = int(rows.get(ROLE_NAMES[i], 0))
	out[6] = GROUND_ROW
	out[7] = DEPOSIT_ROW
	return out


## {"palette": Image, "params": Image} for `mood` at sun `elevation` (pure).
static func bake(sheet: Dictionary, mood: String, elevation: float) -> Dictionary:
	var palette := Image.create(TONES, MAX_ROWS * VARIANTS, false, Image.FORMAT_RGBA8)
	var params := Image.create(MAX_ROWS, PARAM_ROWS, false, Image.FORMAT_RGBAF)
	var world: Dictionary = data()["world"]
	var styles: Array = [[_deposit(world), 0, ""], [world, 1, ""]]
	var table := row_table()
	for species: String in table:
		for role: String in table[species]:
			styles.append([(data()["species"][species] as Dictionary)[role], role, species])
	for ri in mini(styles.size(), MAX_ROWS):
		var props: Dictionary = styles[ri][0]
		var tag: Variant = styles[ri][1]
		var lch: Vector3 = PainterSheet.parse_color(str(props.get("color", "")))
		var shape := _shape(props, world)
		if tag is String:
			var spike := PainterSheet.parse_color(str(world.get(SPIKE_ROLE[tag], "")))
			lch = _moved(lch, spike, PainterSheet.tone_lch(sheet, mood, SHEET_ROLE[tag], elevation))
			if tag == "leaf" and PainterTreeSpecies.is_bush(str(styles[ri][2])):
				# A bush's leaf is the sheet's bush (bush_ramp's colour: the leaf a step deeper and
				# quieter), so it sits under the crowns in their family in every mood.
				lch = _bush_lch(sheet, mood, elevation)
			shape = _sheet_shade(_moved_shape(shape, sheet, mood, elevation), sheet, mood, elevation, tag)
		elif int(tag) == GROUND_ROW:
			lch = PainterSheet.tone_lch(sheet, mood, "ground", elevation)
		_paint_row(palette, ri, lch, shape, props)
		_param_row(params, ri, props)
	return {"palette": palette, "params": params}


## The six sRGB tones a painted bush paints with (PainterPlantRoles.KIND_CROWN; PainterTones.ramp's
## order: shade, mid, lit of the dark variant, then of the light one). The sheet's leaf at
## `bush-value` of its lightness and `bush-chroma` of its chroma (ratios, so a bush follows every
## mood as the leaf does), on a crown's ramp: the world's shape moved as a species' is, with the
## sheet's crown shade and lit numbers. So a bush sits under the crowns in their family and gilds,
## frosts and darkens with them (painter-trees-polish2: the plain leaf ramp read as lime gumdrops).
static func bush_ramp(sheet: Dictionary, mood: String, elevation: float) -> Array[Color]:
	var world: Dictionary = data()["world"]
	var lch := _bush_lch(sheet, mood, elevation)
	var shape := _sheet_shade(
		_moved_shape(_shape({}, world), sheet, mood, elevation), sheet, mood, elevation, "leaf"
	)
	var hue_spread := _num(world, "hue-spread", 8.0)
	var value_spread := _num(world, "value-spread", 0.03)
	var out: Array[Color] = []
	for side: float in [-1.0, 1.0]:
		var steps := PainterTones.steps(
			Vector3(lch.x + side * value_spread, lch.y, lch.z + side * hue_spread), shape
		)
		var lit := steps[2]
		lit.y *= float(shape["lit-chroma"])
		steps[2] = lit
		for s: Vector3 in steps:
			out.append(PainterSheet.color_of_lch(s))
	return out


## A bush's leaf colour (OKLCH): the sheet's leaf at `bush-value` of its lightness and `bush-chroma`
## of its chroma.
static func _bush_lch(sheet: Dictionary, mood: String, elevation: float) -> Vector3:
	var leaf := PainterSheet.tone_lch(sheet, mood, "leaf", elevation)
	return Vector3(
		leaf.x * PainterSheet.number(sheet, mood, "bush-value", elevation),
		leaf.y * PainterSheet.number(sheet, mood, "bush-chroma", elevation),
		leaf.z
	)


## The deposit's style: the spike world's deposit colour and ramp.
static func _deposit(world: Dictionary) -> Dictionary:
	var out := world.duplicate()
	out["color"] = world.get("deposit-color", "oklch(0.925 0.020 240)")
	for k in ["shade-hue", "shade-pull", "shade-depth", "lit-lift"]:
		if world.has("deposit-" + k):
			out[k] = world["deposit-" + k]
	return out


static func _num(props: Dictionary, key: String, fallback: float) -> float:
	var v: String = str(props.get(key, ""))
	return v.to_float() if v.is_valid_float() else fallback


static func _shape(props: Dictionary, world: Dictionary) -> Dictionary:
	var fallback := {
		"shade-hue": 285.0,
		"shade-pull": 0.9,
		"shade-depth": 0.66,
		"lit-hue": 95.0,
		"lit-pull": 0.35,
		"lit-lift": 0.17
	}
	var out := {"shade-keep": 1.0, "lit-chroma": _num(props, "lit-chroma", 1.0)}
	for k: String in SHAPE_KEYS:
		out[k] = _num(props, k, _num(world, k, fallback[k]))
	return out


## A species colour `lch`, tuned against the spike world's `spike`, moved as the sheet's role
## `now` stands from it (pure).
static func _moved(lch: Vector3, spike: Vector3, now: Vector3) -> Vector3:
	var l_ratio := now.x / spike.x if spike.x > 0.001 else 1.0
	var c_ratio := now.y / spike.y if spike.y > 0.001 else 1.0
	if c_ratio > 1.0:
		c_ratio = sqrt(c_ratio)
	var turn := fposmod(now.z - spike.z + 180.0, 360.0) - 180.0
	return Vector3(
		clampf(lch.x * l_ratio, 0.02, 0.985),
		maxf(lch.y * c_ratio, 0.0),
		fposmod(lch.z + turn * clampf(now.y / HUE_CHROMA, 0.0, 1.0), 360.0)
	)


## `shape` with the sheet's shade hue, pull and keep for a tree role `tag` (SHADE_PREFIX).
static func _sheet_shade(
	shape: Dictionary, sheet: Dictionary, mood: String, elevation: float, tag: String
) -> Dictionary:
	var out := shape.duplicate()
	var prefix: String = SHADE_PREFIX[tag]
	var hue_key := "crown-shade-hue" if prefix == "crown-" else "shade-hue"
	out["shade-hue"] = PainterSheet.number(sheet, mood, hue_key, elevation)
	out["shade-pull"] = PainterSheet.number(sheet, mood, prefix + "shade-pull", elevation)
	var keep := PainterSheet.number(sheet, mood, prefix + "shade-keep", elevation)
	out["shade-keep"] = clampf(keep, 0.0, 1.0)
	if prefix == "crown-":
		out["lit-hue"] = PainterSheet.number(sheet, mood, "lit-hue", elevation)
		var lit_pull := PainterSheet.number(sheet, mood, "crown-lit-pull", elevation)
		out["lit-pull"] = lit_pull * (NEEDLE_LIT_SHARE if tag == "evergreen" else 1.0)
		var lit_lift := PainterSheet.number(sheet, mood, "crown-lit-lift", elevation)
		out["lit-lift"] = maxf(float(out["lit-lift"]) + lit_lift, 0.0)
		var lit_chroma := PainterSheet.number(sheet, mood, "crown-lit-chroma", elevation)
		out["lit-chroma"] = float(out["lit-chroma"]) * maxf(lit_chroma, 0.0)
		var shade_lift := PainterSheet.number(sheet, mood, "crown-shade-lift", elevation)
		out["shade-depth"] = clampf(float(out["shade-depth"]) + shade_lift, 0.0, 1.0)
	else:
		var lift := PainterSheet.number(sheet, mood, "bark-shade-lift", elevation)
		out["shade-depth"] = clampf(float(out["shade-depth"]) + lift, 0.0, 1.0)
	return out


static func _moved_shape(
	shape: Dictionary, sheet: Dictionary, mood: String, elevation: float
) -> Dictionary:
	var out := shape.duplicate()
	var ref_mood: String = REFERENCE["mood"]
	var ref_elev: float = REFERENCE["elevation"]
	for k: String in SHAPE_KEYS + ["shade-keep"]:
		var d := (
			PainterSheet.number(sheet, mood, k, elevation)
			- PainterSheet.number(sheet, ref_mood, k, ref_elev)
		)
		if k.ends_with("hue"):
			out[k] = fposmod(float(out[k]) + fposmod(d + 180.0, 360.0) - 180.0, 360.0)
		else:
			out[k] = maxf(float(out[k]) + d, 0.0)
	out["shade-keep"] = clampf(float(out["shade-keep"]), 0.0, 1.0)
	return out


static func _paint_row(
	palette: Image, ri: int, lch: Vector3, shape: Dictionary, props: Dictionary
) -> void:
	var hue_spread := _num(props, "hue-spread", 8.0)
	var value_spread := _num(props, "value-spread", 0.03)
	for vi in VARIANTS:
		var fv := float(vi) / float(VARIANTS - 1) * 2.0 - 1.0
		var steps := PainterTones.steps(
			Vector3(lch.x + fv * value_spread, lch.y, lch.z + fv * hue_spread), shape
		)
		# The spike's lit step: LIT_CHROMA of the chroma, times the role's own lit-chroma.
		var lit := steps[2]
		lit.y *= float(shape["lit-chroma"])
		steps[2] = lit
		var labs: Array[Vector3] = []
		for s: Vector3 in steps:
			labs.append(PainterSheet.oklab_of(s))
		for ti in TONES:
			var t := float(ti) / float(TONES - 1)
			var lab := labs[0].lerp(labs[1], t * 2.0) if t < 0.5 else labs[1].lerp(labs[2], t * 2.0 - 1.0)
			var lch_t := Vector3(
				lab.x, Vector2(lab.y, lab.z).length(), fposmod(rad_to_deg(atan2(lab.z, lab.y)), 360.0)
			)
			palette.set_pixel(ti, ri * VARIANTS + vi, PainterSheet.color_of_lch(lch_t))


static func _brush(props: Dictionary, key: String, fallback: float) -> float:
	if not props.has(key):
		return fallback
	var b: String = str(props[key])
	return float(BRUSHES.get(b, b.to_float() if b.is_valid_float() else fallback))


static func _param_row(params: Image, ri: int, r: Dictionary) -> void:
	for y in PARAMS.size():
		var c := Color()
		for i in 4:
			var key: String = PARAMS[y][i][0]
			var fallback: float = PARAMS[y][i][1]
			if key == "":
				c[i] = 0.0
			elif key.ends_with("brush"):
				c[i] = _brush(r, key, fallback)
			else:
				c[i] = _num(r, key, fallback)
		if y == 4:
			c.b += 2.0 * _num(r, "mark-trim", 0.0)
		params.set_pixel(ri, y, c)
