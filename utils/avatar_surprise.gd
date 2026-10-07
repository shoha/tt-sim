class_name AvatarSurprise
extends RefCounted

## "Surprise me" for the avatar builder: random recipes (docs/ASSET_PIPELINE.md section 10
## "Recipe") drawn from the kit's curated sets so every draw is a figure someone would keep,
## plus a reroll of one section at a time (stance, face, colours, shape, parts) that leaves
## the rest as it is. Everything here is a pure function of the kit's manifest and a
## RandomNumberGenerator, so a seeded generator gives the same avatar twice.
##
## What makes a draw harmonious:
## - the outfit's three cloth picks are related by hue: the trim (`secondary`) sits across
##   the wheel from the main cloth (`primary`) or is a neutral, and the accent is a saturated
##   third colour clear of both, so no draw puts two near-identical reds side by side or
##   three muddy tones together;
## - a fantasy skin (a hue off the warm band) is drawn a third as often as a natural one;
## - "none" is the likeliest marks cell, so most faces are plain and a blush is a surprise;
## - proportions stay off the very ends of their ranges and on the builder's step, so a
##   figure never starts at a corner the sliders would have to be dragged back from; the
##   build is the exception, drawn evenly over its whole range, plus-size end included.
## The rules read the sets, not fixed indices, so a kit with more colours or parts keeps
## working without a change here.

## The builder's proportion step: sliders and random shapes land on multiples of it, so a
## value already built is found again in the figure cache (AvatarFigureCache).
const STEP := 0.05
const SHAPE_MIN := 0.1
const SHAPE_MAX := 0.9
## Controls drawn over their whole 0..1 range (the build's high end is the plus-size body).
const FULL_RANGE_CONTROLS: Array[String] = ["build"]
## A cloth colour below this saturation counts as a neutral (white, cream) and goes with
## anything.
const NEUTRAL_SATURATION := 0.3
## The least hue distance (degrees) between the main cloth and its trim.
const TRIM_HUE_DEG := 90.0
## The least hue distance between the accent and the two cloths, and its least saturation.
const ACCENT_HUE_DEG := 50.0
const ACCENT_SATURATION := 0.45
## Skin hues within this band (degrees from red) are natural; others are fantasy skins.
const NATURAL_SKIN_HUE_DEG := 50.0
const FANTASY_SKIN_WEIGHT := 1.0 / 3.0
const MARKS_NONE_WEIGHT := 3.0

const SECTIONS: Array[StringName] = [&"stance", &"face", &"colours", &"shape", &"parts"]

## Names a new avatar may start with (the presets' names and friends).
const NAMES: Array[String] = [
	"Plum",
	"Marigold",
	"Teal",
	"Ranger",
	"Starling",
	"Sunny",
	"Juniper",
	"Wren",
	"Clove",
	"Ember",
	"Moss",
	"Pip",
	"Hazel",
	"Bramble",
	"Fennel",
	"Indigo",
	"Rook",
	"Saffron",
	"Tansy",
	"Quill",
	"Sorrel",
	"Lark",
	"Nettle",
	"Opal",
]


## A whole random recipe over `kit`: a part per slot, harmonious colours, a face, a shape
## and a stance.
static func recipe(kit: AvatarKit, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"format": AvatarRecipe.FORMAT,
		"parts": parts(kit, rng),
		"colours": colours(kit, rng),
		"face": face(kit, rng),
		"proportions": shape(kit, rng),
		"stance": stance(kit, rng),
	}


## `recipe` with one `section` (SECTIONS) drawn again; a stance reroll always picks a
## different stance when the kit has more than one.
static func reroll(
	kit: AvatarKit, source: Dictionary, section: StringName, rng: RandomNumberGenerator
) -> Dictionary:
	var out := AvatarRecipe.normalized(source)
	match section:
		&"stance":
			out["stance"] = stance(kit, rng, String(out.get("stance", "")))
		&"face":
			out["face"] = face(kit, rng)
		&"colours":
			out["colours"] = colours(kit, rng)
		&"shape":
			out["proportions"] = shape(kit, rng)
		&"parts":
			out["parts"] = parts(kit, rng)
	return out


## A random part for every slot the kit has, in slot order.
static func parts(kit: AvatarKit, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var slots: Array = kit.parts_by_slot.keys()
	slots.sort()
	for slot in slots:
		var ids: Array = kit.parts_by_slot[slot]
		if not ids.is_empty():
			out[slot] = String(ids[rng.randi_range(0, ids.size() - 1)])
	return out


## Colour picks for every palette slot: a weighted skin, a free hair and eye colour, a
## harmonious outfit (harmonious_outfit) and a free pick for leather and metal.
static func colours(kit: AvatarKit, rng: RandomNumberGenerator) -> Dictionary:
	var sets: Dictionary = kit.manifest.get("colour_sets", {})
	var out := {}
	var skins: Array = sets.get("skin", [])
	var skin_weights: Array[float] = []
	for triple in skins:
		var hue := _hue_deg(_base(triple))
		var natural := hue <= NATURAL_SKIN_HUE_DEG or hue >= 360.0 - NATURAL_SKIN_HUE_DEG
		skin_weights.append(1.0 if natural else FANTASY_SKIN_WEIGHT)
	out["skin"] = weighted(skin_weights, rng)
	out["hair"] = _uniform((sets.get("hair", []) as Array).size(), rng)
	out["eyes"] = _uniform((sets.get("eyes", []) as Array).size(), rng)
	out.merge(harmonious_outfit(sets.get("cloth", []), rng))
	out["leather"] = _uniform((sets.get("leather", []) as Array).size(), rng)
	out["metal"] = _uniform((sets.get("metal", []) as Array).size(), rng)
	return out


## Three cloth picks (`primary`, `secondary`, `accent`) that go together: the trim across
## the wheel from the main cloth (TRIM_HUE_DEG) or a neutral, the accent a saturated colour
## clear of both (ACCENT_HUE_DEG, ACCENT_SATURATION). Each rule falls back to any other
## colour when the set offers nothing that fits, so a small set still draws.
static func harmonious_outfit(cloth: Array, rng: RandomNumberGenerator) -> Dictionary:
	var count := cloth.size()
	if count == 0:
		return {"primary": 0, "secondary": 0, "accent": 0}
	var primary := rng.randi_range(0, count - 1)
	var main := _base(cloth[primary])
	var trims: Array[int] = []
	for j in count:
		if j == primary:
			continue
		var candidate := _base(cloth[j])
		if _is_neutral(main) or _is_neutral(candidate):
			trims.append(j)
		elif hue_distance(main, candidate) >= TRIM_HUE_DEG:
			trims.append(j)
	var secondary := _pick_or_other(trims, [primary], count, rng)
	var trim := _base(cloth[secondary])
	var accents: Array[int] = []
	for k in count:
		if k == primary or k == secondary:
			continue
		var candidate := _base(cloth[k])
		if candidate.s < ACCENT_SATURATION:
			continue
		if hue_distance(main, candidate) < ACCENT_HUE_DEG and not _is_neutral(main):
			continue
		if hue_distance(trim, candidate) < ACCENT_HUE_DEG and not _is_neutral(trim):
			continue
		accents.append(k)
	var accent := _pick_or_other(accents, [primary, secondary], count, rng)
	return {"primary": primary, "secondary": secondary, "accent": accent}


## A face: any eyes, brows and mouth, and marks weighted toward the first cell ("none").
static func face(kit: AvatarKit, rng: RandomNumberGenerator) -> Dictionary:
	var counts := kit.face_counts()
	var out := {}
	for kind in AvatarRecipe.FACE_KINDS:
		var count := int(counts.get(kind, 0))
		if kind == "marks" and count > 1:
			var weights: Array[float] = [MARKS_NONE_WEIGHT]
			for _i in count - 1:
				weights.append(1.0)
			out[kind] = weighted(weights, rng)
		else:
			out[kind] = _uniform(count, rng)
	return out


## Every proportion control at a random value inside [SHAPE_MIN, SHAPE_MAX], on STEP, except
## `build`, drawn uniformly over its whole range: its high end is the plus-size body (kit.json
## `shapes`), and every body in the range should come up as often as any other.
static func shape(kit: AvatarKit, rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	var controls: Array = (kit.manifest.get("proportions", {}) as Dictionary).keys()
	controls.sort()
	for control in controls:
		if FULL_RANGE_CONTROLS.has(String(control)):
			# Every step of the range equally likely, the ends included.
			var steps := maxi(1, roundi(1.0 / STEP))
			out[control] = float(rng.randi_range(0, steps)) / float(steps)
		else:
			out[control] = quantize(rng.randf_range(SHAPE_MIN, SHAPE_MAX))
	return out


## A random stance, never `avoid` when the kit has another.
static func stance(kit: AvatarKit, rng: RandomNumberGenerator, avoid: String = "") -> String:
	var names: Array = kit.stance_names()
	if names.is_empty():
		return "stance_ready"
	var choices: Array = []
	for name in names:
		if String(name) != avoid:
			choices.append(String(name))
	if choices.is_empty():
		return String(names[0])
	return choices[rng.randi_range(0, choices.size() - 1)]


## A starting name.
static func pick_name(rng: RandomNumberGenerator) -> String:
	return NAMES[rng.randi_range(0, NAMES.size() - 1)]


## `value` clamped to 0..1 and snapped to `step`, as the plain decimal (12 / 20 is exactly
## the double 0.6, where 12 * 0.05 is not), so a snapped value compares equal to the same
## decimal read back from a level file.
static func quantize(value: float, step: float = STEP) -> float:
	var steps := maxi(1, roundi(1.0 / step))
	return float(roundi(clampf(value, 0.0, 1.0) * steps)) / float(steps)


## An index drawn by `weights` (all non-negative; an empty array gives 0).
static func weighted(weights: Array[float], rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += maxf(0.0, w)
	if total <= 0.0:
		return 0
	var roll := rng.randf() * total
	for i in weights.size():
		roll -= maxf(0.0, weights[i])
		if roll < 0.0:
			return i
	return weights.size() - 1


## The shorter way round the hue wheel between two colours, in degrees.
static func hue_distance(a: Color, b: Color) -> float:
	var d := absf(_hue_deg(a) - _hue_deg(b))
	return minf(d, 360.0 - d)


static func _hue_deg(colour: Color) -> float:
	return colour.h * 360.0


static func _is_neutral(colour: Color) -> bool:
	return colour.s < NEUTRAL_SATURATION


## The base colour of a kit triple (base, shadow, highlight).
static func _base(triple: Variant) -> Color:
	if triple is Array and not (triple as Array).is_empty():
		return Color.html(String((triple as Array)[0]))
	return Color.WHITE


static func _uniform(count: int, rng: RandomNumberGenerator) -> int:
	return rng.randi_range(0, count - 1) if count > 0 else 0


## A random entry of `candidates`, or of every index below `count` not in `taken`.
static func _pick_or_other(
	candidates: Array[int], taken: Array, count: int, rng: RandomNumberGenerator
) -> int:
	if not candidates.is_empty():
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var others: Array[int] = []
	for i in count:
		if not taken.has(i):
			others.append(i)
	if others.is_empty():
		return 0
	return others[rng.randi_range(0, others.size() - 1)]
